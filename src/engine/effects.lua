-- Effects registry: maps effect keywords ("gold:2", "draw:1") to actions.
-- Resource and stat keywords come from the rules module, so a game that calls
-- its money "trade" gets a `trade` keyword without writing any code.
--
-- A handler is { apply = function(game, seat, amount, ctx), text = function(amount) }.
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
      end,
      text = function(amount) return signed(amount) .. " " .. label end,
    })
  end

  self:register("draw", {
    apply = function(game, seat, amount) game:draw(seat, amount) end,
    text = function(amount) return "Draw " .. amount end,
  })

  -- Choices the player makes later (milestone 4 adds the prompts); for now
  -- they are recorded as pending counts on the player.
  self:register("opponent_discard", {
    apply = function(game, seat, amount)
      for _, other in ipairs(game:opponentsOf(seat)) do
        local p = game.state.players[other]
        p.pending.discard = (p.pending.discard or 0) + amount
      end
    end,
    text = function(amount) return "Opponent discards " .. amount end,
  })
  self:register("scrap_hand", {
    apply = function(game, seat, amount)
      local p = game.state.players[seat]
      p.pending.scrap = (p.pending.scrap or 0) + amount
    end,
    text = function(amount) return "You may scrap up to " .. amount .. " from hand or discard" end,
  })

  for name, def in pairs(rules.customEffects or {}) do
    self:registerCustom(name, def)
  end
  return self
end

function Effects:register(key, handler)
  self.handlers[key] = handler
end

-- def is a function(game, seat, ctx) or { apply = fn, text = "rules text" }.
function Effects:registerCustom(name, def)
  if type(def) == "function" then def = { apply = def } end
  self.custom[name] = def
end

function Effects:apply(game, seat, list, ctx)
  for _, effect in ipairs(list) do
    if effect.key == "custom" then
      local def = self.custom[effect.fn]
      if not def then error("no custom effect named '" .. effect.fn .. "'", 0) end
      def.apply(game, seat, ctx or {})
    else
      local handler = self.handlers[effect.key]
      if not handler then error("no effect keyword '" .. effect.key .. "'", 0) end
      handler.apply(game, seat, effect.amount, ctx or {})
    end
  end
end

function Effects:describe(list, fallback)
  local parts = {}
  for _, effect in ipairs(list) do
    if effect.key == "custom" then
      local def = self.custom[effect.fn]
      parts[#parts + 1] = (def and def.text) or fallback or effect.fn
    else
      local handler = self.handlers[effect.key]
      parts[#parts + 1] = handler and handler.text(effect.amount) or (effect.key .. " " .. effect.amount)
    end
  end
  return table.concat(parts, ", ")
end

-- Returns a list of problems, e.g. a card using a keyword the rules don't define.
function Effects:validate(cards)
  local problems = {}
  for _, card in ipairs(cards.list) do
    for _, list in ipairs({ card.effects, card.allyEffects, card.scrapEffects }) do
      for _, effect in ipairs(list) do
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
