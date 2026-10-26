-- Player actions: buy, play, ally triggers, scrap, attack, prompts, turn
-- start/end. Pure state changes like turn.lua; game.lua redraws after each.
--
-- Every action returns true, or false plus a message to show the player.
local Util = require("engine.util")
local State = require("engine.state")
local Turn = require("engine.turn")

local Actions = {}

local function fail(msg) return false, msg end

local function card(game, uid)
  return game.cards:get(State.cardId(game.state, uid))
end

-- The resource spent on buying or attacking: the one with spend = "buy" / "attack".
function Actions.resourceFor(rules, spend)
  for _, res in ipairs(rules.resources or {}) do
    if res.spend == spend then return res.key, res.label or Util.titleCase(res.key) end
  end
  return nil
end

local function isActive(game, seat)
  local state = game.state
  if not state.started then return false, "The game hasn't started." end
  if state.winner then return false, "The game is over." end
  if state.turn.active ~= seat then
    return false, "It's " .. state.players[state.turn.active].name .. "'s turn."
  end
  return true
end

function Actions.inPlay(player)
  local all = {}
  for _, uid in ipairs(player.play) do all[#all + 1] = uid end
  for _, uid in ipairs(player.bases) do all[#all + 1] = uid end
  return all
end

local function hasFaction(c, faction)
  for _, f in ipairs(c.factions) do
    if f == faction or f == "any" then return true end
  end
  return false
end

-- Is another card in play an ally for this group? A group with no faction of
-- its own needs a card sharing any of the owner's factions.
local function allyMet(game, uid, c, group, cardsInPlay)
  for _, other in ipairs(cardsInPlay) do
    if other ~= uid then
      local oc = card(game, other)
      if group.faction then
        if hasFaction(oc, group.faction) then return true end
      else
        for _, f in ipairs(c.factions) do
          if f ~= "none" and hasFaction(oc, f) then return true end
        end
      end
    end
  end
  return false
end

-- Fires every ally group whose condition is met and that hasn't fired yet
-- this turn. Runs until nothing new fires, since an effect may change play.
function Actions.checkAllies(game, seat)
  if game.rules.mechanics and game.rules.mechanics.allies == false then return end
  local player = game.state.players[seat]
  local fired = game.state.turn.allyFired
  local again = true
  while again do
    again = false
    local cardsInPlay = Actions.inPlay(player)
    for _, uid in ipairs(cardsInPlay) do
      local c = card(game, uid)
      for i, group in ipairs(c.allyGroups) do
        local key = uid .. ":" .. i
        if not fired[key] and allyMet(game, uid, c, group, cardsInPlay) then
          fired[key] = true
          game.effects:apply(game, seat, group.effects, { uid = uid, card = c })
          again = true
        end
      end
    end
  end
end

function Actions.play(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local player = game.state.players[seat]
  if not Util.removeValue(player.hand, uid) then return fail("That card isn't in your hand.") end
  local c = card(game, uid)
  if Turn.isPersistent(game.rules, c) then
    player.bases[#player.bases + 1] = uid
  else
    player.play[#player.play + 1] = uid
  end
  game.effects:apply(game, seat, c.effects, { uid = uid, card = c })
  Actions.checkAllies(game, seat)
  return true
end

function Actions.playAll(game, seat)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local hand = game.state.players[seat].hand
  if #hand == 0 then return fail("Your hand is empty.") end
  while #hand > 0 do Actions.play(game, seat, hand[1]) end
  return true
end

-- Where a buyable uid sits: ("row", slot) or ("fixed", card id).
local function locate(market, uid)
  for i, u in ipairs(market.row) do
    if u == uid then return "row", i end
  end
  for id, pile in pairs(market.fixed) do
    if Util.indexOf(pile, uid) then return "fixed", id end
  end
  return nil
end

-- Buys a card from the market row or a fixed pile (always its top card).
-- `free` skips the cost, for effects like "take a card for free".
function Actions.buy(game, seat, uid, free)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local market = game.state.market
  local where, slot = locate(market, uid)
  if not where then return fail("That card can't be bought.") end
  if where == "fixed" then uid = market.fixed[slot][#market.fixed[slot]] end
  local c = card(game, uid)
  local player = game.state.players[seat]

  if not free then
    local key, label = Actions.resourceFor(game.rules, "buy")
    if not key then return fail("These rules have no resource with spend = \"buy\".") end
    if (player.resources[key] or 0) < c.cost then
      return fail("Not enough " .. label .. ": " .. c.name .. " costs " .. c.cost .. ".")
    end
    player.resources[key] = player.resources[key] - c.cost
  end

  if where == "row" then market.row[slot] = State.EMPTY else table.remove(market.fixed[slot]) end
  if player.flags.buyToTop or game.rules.market.buyTo == "deck_top" then
    player.deck[#player.deck + 1] = uid
  else
    player.discard[#player.discard + 1] = uid
  end
  player.flags.buyToTop = nil
  Turn.fillMarket(game.state)
  return true
end

function Actions.scrapFromPlay(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  if game.rules.mechanics and game.rules.mechanics.scrap == false then return fail("Scrapping is off in these rules.") end
  local player = game.state.players[seat]
  local c = card(game, uid)
  if #c.scrapEffects == 0 then return fail(c.name .. " has no scrap ability.") end
  if not (Util.removeValue(player.play, uid) or Util.removeValue(player.bases, uid)) then
    return fail("That card isn't in play.")
  end
  game.state.market.scrap[#game.state.market.scrap + 1] = uid
  game.effects:apply(game, seat, c.scrapEffects, { uid = uid, card = c })
  return true
end

---------------------------------------------------------------------------
-- Attacking
---------------------------------------------------------------------------

-- Bases whose type has guard = true must fall before the player or their
-- other bases can be attacked.
function Actions.guards(game, seat)
  local out = {}
  for _, uid in ipairs(game.state.players[seat].bases) do
    local def = game.rules.cardTypes and game.rules.cardTypes[card(game, uid).type]
    if def and def.guard then out[#out + 1] = uid end
  end
  return out
end

function Actions.destroyBase(game, owner, uid)
  local player = game.state.players[owner]
  if Util.removeValue(player.bases, uid) then
    player.discard[#player.discard + 1] = uid
    return true
  end
  return false
end

-- A player whose win stat drops to `atOrBelow` is out: they take no more
-- turns, can't be attacked and owe nothing. The last player left wins.
function Actions.checkWin(game)
  local win = game.rules.win
  if not win or win.type ~= "stat_depleted" then return end
  local alive = {}
  for seat, p in ipairs(game.state.players) do
    if not p.out and (p.stats[win.stat] or 0) <= (win.atOrBelow or 0) then
      p.out, p.prompts, p.owed = true, {}, {}
    end
    if not p.out then alive[#alive + 1] = seat end
  end
  if #alive == 1 then game.state.winner = alive[1] end
end

-- Without baseUid, spends the whole attack pool on the target player's
-- win stat. With it, spends the base's defense to destroy that base.
function Actions.attack(game, seat, target, baseUid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local victim = game.state.players[target]
  if target == seat or not victim then return fail("Pick an opponent to attack.") end
  if victim.out then return fail(victim.name .. " is already out.") end
  local key, label = Actions.resourceFor(game.rules, "attack")
  if not key then return fail("These rules have no resource with spend = \"attack\".") end
  local player = game.state.players[seat]
  local pool = player.resources[key] or 0
  if pool <= 0 then return fail("You have no " .. label .. " to attack with.") end
  local guards = Actions.guards(game, target)

  if baseUid then
    if not Util.indexOf(victim.bases, baseUid) then return fail("That base isn't in play.") end
    if #guards > 0 and not Util.indexOf(guards, baseUid) then return fail("Destroy their guard bases first.") end
    local c = card(game, baseUid)
    local defense = c.defense or 0
    if pool < defense then return fail(c.name .. " needs " .. defense .. " " .. label .. ".") end
    player.resources[key] = pool - defense
    Actions.destroyBase(game, target, baseUid)
    return true
  end

  if #guards > 0 then return fail("Destroy their guard bases first.") end
  local stat = game.rules.win and game.rules.win.stat
  if not stat then return fail("These rules have no stat to attack (rules.win.stat).") end
  victim.stats[stat] = (victim.stats[stat] or 0) - pool
  player.resources[key] = 0
  Actions.checkWin(game)
  return true
end

---------------------------------------------------------------------------
-- Prompts: choices a player answers from the action panel, first in first out.
-- A prompt is plain data so it survives onSave:
--   { kind, count, optional, text?, from?, options?, maxCost?, uid?, owe? }
-- kinds: choice, scrap, discard, scrap_row, destroy_base, free_buy, reminder,
-- opponent (pick an opponent; `owe` such as { discard = 1 } is added to theirs)
---------------------------------------------------------------------------

function Actions.prompt(game, seat, prompt)
  prompt.count = prompt.count or 1
  local prompts = game.state.players[seat].prompts
  prompts[#prompts + 1] = prompt
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

function Actions.promptText(game, prompt)
  if prompt.text then return prompt.text end
  local n, kind = prompt.count, prompt.kind
  if kind == "choice" then return "Choose one" end
  if kind == "scrap" then return "Scrap up to " .. plural(n, "card") .. " from your hand or discard pile" end
  if kind == "discard" then return "Discard " .. plural(n, "card") end
  if kind == "scrap_row" then return "Scrap up to " .. plural(n, "card") .. " from the market row" end
  if kind == "destroy_base" then return "Destroy up to " .. plural(n, "base") end
  if kind == "free_buy" then return "Take a card costing " .. prompt.maxCost .. " or less from the market row" end
  if kind == "opponent" then
    local owed = prompt.owe and prompt.owe.discard
    return owed and ("Choose an opponent to discard " .. plural(owed, "card") .. " next turn") or "Choose an opponent"
  end
  return kind
end

-- What the first prompt can be answered with right now: { {value, label}, ... }
function Actions.targets(game, seat, prompt)
  local state = game.state
  local player = state.players[seat]
  local out = {}
  local function add(uid, where)
    out[#out + 1] = { value = uid, label = card(game, uid).name .. (where and (" (" .. where .. ")") or "") }
  end
  local kind = prompt.kind
  if kind == "choice" then
    for i, option in ipairs(prompt.options) do
      out[#out + 1] = { value = tostring(i), label = game.effects:describe({ option }) }
    end
  elseif kind == "scrap" then
    for _, from in ipairs(prompt.from or { "hand", "discard" }) do
      for _, uid in ipairs(player[from]) do add(uid, from) end
    end
  elseif kind == "discard" then
    for _, uid in ipairs(player.hand) do add(uid) end
  elseif kind == "scrap_row" or kind == "free_buy" then
    for _, uid in ipairs(state.market.row) do
      if uid ~= State.EMPTY and (kind == "scrap_row" or card(game, uid).cost <= prompt.maxCost) then add(uid) end
    end
  elseif kind == "destroy_base" then
    for _, other in ipairs(game:opponentsOf(seat)) do
      for _, uid in ipairs(state.players[other].bases) do add(uid, state.players[other].name) end
    end
  elseif kind == "opponent" then
    for _, other in ipairs(game:opponentsOf(seat)) do
      out[#out + 1] = { value = tostring(other), label = state.players[other].name }
    end
  end
  return out
end

-- Drops prompts at the front that have nothing left to pick, such as a
-- discard with an empty hand. Reminders always wait for the player.
function Actions.settle(game, seat)
  local prompts = game.state.players[seat].prompts
  while prompts[1] and prompts[1].kind ~= "reminder" and #Actions.targets(game, seat, prompts[1]) == 0 do
    table.remove(prompts, 1)
  end
end

-- Answers the first prompt with one of its targets' values.
function Actions.pick(game, seat, value)
  local state = game.state
  local player = state.players[seat]
  local prompt = player.prompts[1]
  if not prompt then return fail("There's nothing to choose.") end
  local valid = false
  for _, t in ipairs(Actions.targets(game, seat, prompt)) do
    if t.value == value then valid = true end
  end
  if not valid then return fail("That isn't one of the options.") end

  local kind = prompt.kind
  if kind == "choice" then
    table.remove(player.prompts, 1)
    local c = prompt.uid and card(game, prompt.uid)
    game.effects:apply(game, seat, { prompt.options[tonumber(value)] }, { uid = prompt.uid, card = c })
    Actions.settle(game, seat)
    return true
  elseif kind == "scrap" then
    if not Util.removeValue(player.hand, value) then Util.removeValue(player.discard, value) end
    state.market.scrap[#state.market.scrap + 1] = value
  elseif kind == "discard" then
    Util.removeValue(player.hand, value)
    player.discard[#player.discard + 1] = value
  elseif kind == "scrap_row" then
    state.market.row[Util.indexOf(state.market.row, value)] = State.EMPTY
    state.market.scrap[#state.market.scrap + 1] = value
    Turn.fillMarket(state)
  elseif kind == "free_buy" then
    Actions.buy(game, seat, value, true)
  elseif kind == "destroy_base" then
    for _, other in ipairs(game:opponentsOf(seat)) do Actions.destroyBase(game, other, value) end
  elseif kind == "opponent" then
    local owed = state.players[tonumber(value)].owed
    for key, n in pairs(prompt.owe or {}) do owed[key] = (owed[key] or 0) + n end
  end

  prompt.count = prompt.count - 1
  if prompt.count <= 0 then table.remove(player.prompts, 1) end
  Actions.settle(game, seat)
  return true
end

-- Closes the first prompt without picking (or after picking fewer than allowed).
function Actions.done(game, seat)
  local player = game.state.players[seat]
  local prompt = player.prompts[1]
  if not prompt then return fail("There's nothing to finish.") end
  if not prompt.optional and #Actions.targets(game, seat, prompt) > 0 then
    return fail("You have to choose first: " .. Actions.promptText(game, prompt) .. ".")
  end
  table.remove(player.prompts, 1)
  Actions.settle(game, seat)
  return true
end

---------------------------------------------------------------------------
-- Turn start and end
---------------------------------------------------------------------------

-- Start of a seat's turn: owed discards become a prompt, and persistent
-- cards in play apply their effects (and allies) again.
function Actions.startTurn(game, seat)
  local player = game.state.players[seat]
  game.state.turn.allyFired = {}
  if (player.owed.discard or 0) > 0 then
    Actions.prompt(game, seat, { kind = "discard", count = player.owed.discard, optional = false })
    player.owed.discard = 0
  end
  for _, uid in ipairs(player.bases) do
    local c = card(game, uid)
    game.effects:apply(game, seat, c.effects, { uid = uid, card = c })
  end
  Actions.checkAllies(game, seat)
  Actions.settle(game, seat)
end

function Actions.endTurn(game, seat)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local player = game.state.players[seat]
  for _, prompt in ipairs(player.prompts) do
    if not prompt.optional and #Actions.targets(game, seat, prompt) > 0 then
      return fail("Finish this first: " .. Actions.promptText(game, prompt) .. ".")
    end
  end
  player.prompts = {}
  player.flags = {}
  Turn.endTurn(game.state, game.rules, game.random)
  Actions.startTurn(game, game.state.turn.active)
  return true
end

return Actions
