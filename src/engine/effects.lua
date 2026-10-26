-- Effects registry: maps effect keywords ("gold:2", "draw:1") to actions.
-- Resource and stat keywords come from the rules module, so a game that calls
-- its money "trade" gets a `trade` keyword without writing any code.
--
-- A handler is { apply = function(game, seat, amount, ctx, effect), text = function(amount) }.
-- ctx carries { uid, card } of the card the effect came from, when there is one.
-- `game` is the facade from engine/game.lua; handlers change game.state only.
local Util = require("engine.util")

local Effects = {}
Effects.__index = Effects

local function signed(n)
  return (n >= 0 and "+" or "") .. n
end

function Effects.new(rules)
  local self = setmetatable({ handlers = {}, custom = {} }, Effects)

  for _, res in ipairs(rules.resources or {}) do
    local key, label = res.key, res.label or Util.titleCase(res.key)
    self:register(key, {
      apply = function(game, seat, amount)
        local pools = game.state.players[seat].resources
        pools[key] = (pools[key] or 0) + amount
        Effects.noteGain(game, seat, key, amount)
      end,
      text = function(amount) return signed(amount) .. " " .. label end,
    })
  end

  for _, stat in ipairs(rules.stats or {}) do
    local key, label = stat.key, stat.label or Util.titleCase(stat.key)
    self:register(key, {
      apply = function(game, seat, amount)
        local stats = game.state.players[seat].stats
        stats[key] = (stats[key] or 0) + amount
        Effects.noteGain(game, seat, key, amount)
      end,
      text = function(amount) return signed(amount) .. " " .. label end,
    })
  end

  self:register("draw", {
    apply = function(game, seat, amount) game:draw(seat, amount) end,
    text = function(amount) return "Draw " .. amount end,
  })

  -- Effects that need the player to pick something add a prompt; the player
  -- answers it from the action panel (see engine/actions.lua).
  -- With more than one opponent left, the player picks which one discards.
  self:register("opponent_discard", {
    apply = function(game, seat, amount)
      local others = game:opponentsOf(seat)
      if #others == 1 then
        local owed = game.state.players[others[1]].owed
        owed.discard = (owed.discard or 0) + amount
      elseif #others > 1 then
        game:prompt(seat, { kind = "opponent", owe = { discard = amount }, optional = false })
      end
    end,
    text = function(amount) return "Opponent discards " .. amount end,
  })
  self:register("scrap_hand", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "scrap", count = amount, optional = true, from = { "hand", "discard" } })
    end,
    text = function(amount) return "You may scrap up to " .. amount .. " from hand or discard" end,
  })
  self:register("scrap_required", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "scrap", count = amount, optional = false, from = { "hand", "discard" } })
    end,
    text = function(amount) return "Scrap " .. amount .. " from hand or discard" end,
  })
  -- Scraps from one place only, optional ("you may") or required.
  for _, from in ipairs({ "hand", "discard" }) do
    local where = from == "hand" and "hand" or "discard pile"
    self:register("scrap_from_" .. from, {
      apply = function(game, seat, amount)
        game:prompt(seat, { kind = "scrap", count = amount, optional = true, from = { from } })
      end,
      text = function(amount) return "You may scrap up to " .. amount .. " from your " .. where end,
    })
    self:register("scrap_from_" .. from .. "_required", {
      apply = function(game, seat, amount)
        game:prompt(seat, { kind = "scrap", count = amount, optional = false, from = { from } })
      end,
      text = function(amount) return "Scrap " .. amount .. " from your " .. where end,
    })
  end
  self:register("discard", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "discard", count = amount, optional = false })
    end,
    text = function(amount) return "Discard " .. amount end,
  })
  self:register("cycle", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "discard", count = amount, optional = true, drawPerPick = 1 })
    end,
    text = function(amount) return "Discard up to " .. amount .. ", then draw that many" end,
  })
  -- Free buys up to a cost (the amount): to the discard pile, the hand, or
  -- the top of the deck (any card, or ships only).
  local freeBuys = {
    free_buy = { "", {} },
    free_buy_hand = { ", into your hand", { toHand = true } },
    free_buy_top = { ", onto your deck", { toTop = true } },
    free_ship_top = { " (a ship), onto your deck", { toTop = true, cardType = "ship" } },
  }
  for key, def in pairs(freeBuys) do
    self:register(key, {
      apply = function(game, seat, amount)
        local prompt = { kind = "free_buy", maxCost = amount, optional = true }
        for k, v in pairs(def[2]) do prompt[k] = v end
        game:prompt(seat, prompt)
      end,
      text = function(amount) return "Take a card costing " .. amount .. " or less for free" .. def[1] end,
    })
  end
  self:register("bounce_base", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "destroy_base", bounce = true, count = amount, optional = true })
    end,
    text = function(amount) return "You may return " .. amount .. " base to its owner's hand" end,
  })
  self:register("scrap_row", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "scrap_row", count = amount, optional = true })
    end,
    text = function(amount) return "You may scrap " .. amount .. " from the market row" end,
  })
  self:register("destroy_base", {
    apply = function(game, seat, amount)
      game:prompt(seat, { kind = "destroy_base", count = amount, optional = true })
    end,
    text = function(amount) return "You may destroy " .. amount .. " base" .. (amount > 1 and "s" or "") end,
  })
  self:register("draw_discard", {
    apply = function(game, seat, amount)
      game:draw(seat, amount)
      game:prompt(seat, { kind = "discard", count = amount, optional = false })
    end,
    text = function(amount) return "Draw " .. amount .. ", then discard " .. amount end,
  })
  self:register("reminder", {
    apply = function(game, seat, _, ctx)
      local card = ctx.card
      game:prompt(seat, {
        kind = "reminder", optional = true, count = 1,
        text = (card and card.name .. ": " or "") .. (card and card.text ~= "" and card.text or "resolve this card by hand"),
      })
    end,
    text = function() return "See card text" end,
  })
  self:register("choice", {
    apply = function(game, seat, _, ctx, effect)
      game:prompt(seat, { kind = "choice", count = 1, optional = false, options = effect.options, uid = ctx.uid })
    end,
  })

  for name, def in pairs(rules.customEffects or {}) do
    self:registerCustom(name, def)
  end
  return self
end

-- What the active player gained this turn, per resource or stat key
-- (state.turn.gained), for goals like "gain 4 Trade in a single turn".
function Effects.noteGain(game, seat, key, amount)
  local turn = game.state.turn
  if amount <= 0 or seat ~= turn.active then return end
  turn.gained = turn.gained or {}
  local first = (turn.gained[key] or 0) == 0
  turn.gained[key] = (turn.gained[key] or 0) + amount
  -- whenYouGain(game, seat, ctx, gain) on the player's cards in play; gain.first
  -- is true the first time this turn they gain this key.
  local Actions = require("engine.actions")
  Actions.trigger(game, seat, "whenYouGain", { key = key, amount = amount, first = first })
end

function Effects:register(key, handler)
  self.handlers[key] = handler
end

-- def is a function(game, seat, ctx) or a table with any of:
--   apply = fn(game, seat, ctx)          runs when the card's effects apply
--   text = "rules text"                  shown in descriptions and prompts
--   whenYouPlay = fn(game, seat, ctx, played)
--                                        while the card is in play, runs each time
--                                        its owner plays another card ({uid, card})
--   onPick = fn(game, seat, uid, prompt) answers a { kind = "pick", custom = name } prompt
function Effects:registerCustom(name, def)
  if type(def) == "function" then def = { apply = def } end
  self.custom[name] = def
end

function Effects:apply(game, seat, list, ctx)
  for _, effect in ipairs(list) do
    if effect.key == "custom" then
      local def = self.custom[effect.fn]
      if not def then error("no custom effect named '" .. effect.fn .. "'", 0) end
      if def.apply then def.apply(game, seat, ctx or {}) end
    else
      local handler = self.handlers[effect.key]
      if not handler then error("no effect keyword '" .. effect.key .. "'", 0) end
      handler.apply(game, seat, effect.amount, ctx or {}, effect)
    end
  end
end

function Effects:describe(list, fallback)
  local parts = {}
  for _, effect in ipairs(list) do
    if effect.key == "custom" then
      local def = self.custom[effect.fn]
      parts[#parts + 1] = (def and def.text) or fallback or effect.fn
    elseif effect.key == "choice" then
      local options = {}
      for _, option in ipairs(effect.options) do options[#options + 1] = self:describe({ option }, fallback) end
      parts[#parts + 1] = table.concat(options, " or ")
    else
      local handler = self.handlers[effect.key]
      parts[#parts + 1] = handler and handler.text and handler.text(effect.amount) or (effect.key .. " " .. effect.amount)
    end
    if effect.ally then
      parts[#parts] = "(" .. Util.titleCase(effect.ally) .. ") " .. parts[#parts]
    end
  end
  return table.concat(parts, ", ")
end

-- Returns a list of problems, e.g. a card using a keyword the rules don't define.
function Effects:validate(cards)
  local problems = {}
  for _, card in ipairs(cards.list) do
    for _, list in ipairs({ card.effects, card.allyEffects, card.scrapEffects, card.doubleAllyEffects or {} }) do
      local flat = {}
      for _, effect in ipairs(list) do
        if effect.key == "choice" then
          for _, option in ipairs(effect.options) do flat[#flat + 1] = option end
        else
          flat[#flat + 1] = effect
        end
      end
      for _, effect in ipairs(flat) do
        if effect.key == "custom" then
          if not self.custom[effect.fn] then
            problems[#problems + 1] = "card '" .. card.id .. "' uses custom:" .. effect.fn .. " but rules.customEffects has no " .. effect.fn
          end
        elseif not self.handlers[effect.key] then
          problems[#problems + 1] = "card '" .. card.id .. "' uses unknown keyword '" .. effect.key .. "'"
        end
      end
    end
  end
  return problems
end

return Effects
