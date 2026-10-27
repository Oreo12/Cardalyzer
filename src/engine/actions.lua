-- Player actions: buy, play, ally triggers, scrap, attack, prompts, turn
-- start/end. Pure state changes like turn.lua; game.lua redraws after each.
--
-- Every action returns true, or false plus a message to show the player.
local Util = require("engine.util")
local Words = require("engine.words")
local function say(game, key, vars) return Words.say(game.rules, key, vars) end
local State = require("engine.state")
local Turn = require("engine.turn")

local Actions = {}

local function fail(msg) return false, msg end

-- Sends a scrapped card to the scrap pile. With rules.market.returnScrapped,
-- a card from a fixed pile (Star Realms' Explorers) goes back to its pile instead.
-- `from` says where it came from ("play", "hand", "discard", "row"): the
-- player's own scraps this turn are counted in state.turn.scrapped
-- ({ total, handOrDiscard }), and scraps from hand or discard pile trigger
-- whenYouScrap on their cards in play.
function Actions.toScrap(game, uid, seat, from)
  local market = game.state.market
  local id = State.cardId(game.state, uid)
  local pile = game.rules.market.returnScrapped and market.fixed[id]
  if pile then
    pile[#pile + 1] = uid
  else
    market.scrap[#market.scrap + 1] = uid
  end
  if seat and from and from ~= "row" then
    local turn = game.state.turn
    turn.scrapped = turn.scrapped or { total = 0, handOrDiscard = 0 }
    turn.scrapped.total = turn.scrapped.total + 1
    if from == "hand" or from == "discard" then
      turn.scrapped.handOrDiscard = turn.scrapped.handOrDiscard + 1
      Actions.trigger(game, seat, "whenYouScrap", { uid = uid, card = game:cardOf(uid), from = from })
    end
  end
end

-- A card's entry in rules.cardTypes (an empty table if none). Besides
-- persistent and guard, a type can set:
--   replay = false   a persistent card doesn't apply its effects again each turn
--   target = false   it can't be attacked or destroyed (Star Realms' Heroes)
--   event = true     revealed into the market row, it resolves and is scrapped
function Actions.typeDef(game, c)
  return game.rules.cardTypes and game.rules.cardTypes[c.type] or {}
end

-- Fills the market row from the market deck. An Event revealed this way is
-- resolved at once for the player whose turn it is (its effects apply; custom
-- effects see ctx.event), announced, sent to the scrap pile, and its slot
-- refilled, which may reveal another.
function Actions.fillMarket(game)
  local state = game.state
  for _ = 1, 100 do
    local again = false
    for _, filled in ipairs(Turn.fillMarket(state)) do
      local uid = filled.market.row[filled.slot]
      -- (an earlier event in this pass may have emptied the slot, e.g. "scrap the row")
      local c = uid ~= State.EMPTY and game:cardOf(uid)
      if c and Actions.typeDef(game, c).event then
        filled.market.row[filled.slot] = State.EMPTY
        state.market.scrap[#state.market.scrap + 1] = uid
        if game.notify then game:notify(Words.say(game.rules, "event", { card = c.name, effects = game.effects:describe(c.effects, c.text) })) end
        game.effects:apply(game, state.turn.active, c.effects, { uid = uid, card = c, event = true })
        for seat = 1, #state.players do Actions.settle(game, seat) end -- drop choices with nothing to pick
        again = true
      end
    end
    if not again then return end
  end
end

-- Events revealed while setting up the market row don't resolve: they go
-- to the bottom of the market deck and the row fills again.
function Actions.setAsideEvents(game)
  local state = game.state
  local total = 0
  for _, m in ipairs(State.rows(state)) do total = total + #m.deck + #m.row end
  for _ = 1, total do
    local moved = false
    for _, m in ipairs(State.rows(state)) do
      for i, uid in ipairs(m.row) do
        if uid ~= State.EMPTY and Actions.typeDef(game, game:cardOf(uid)).event then
          table.insert(m.deck, 1, uid)
          m.row[i] = State.EMPTY
          moved = true
        end
      end
    end
    if not moved then return end
    Turn.fillMarket(state)
  end
end

-- Runs a hook (a function field of a custom effect, e.g. whenYouScrap) on
-- every card the seat has in play, except `except`.
function Actions.trigger(game, seat, hook, event, except)
  for _, other in ipairs(Actions.inPlay(game.state.players[seat])) do
    if other ~= except then
      local oc = game:cardOf(other)
      for _, effect in ipairs(oc.effects) do
        local def = effect.key == "custom" and game.effects.custom[effect.fn]
        if def and def[hook] then def[hook](game, seat, { uid = other, card = oc }, event) end
      end
    end
  end
end

-- What a uid acts as, including a copy made this turn (Game:cardOf).
local function card(game, uid)
  return game:cardOf(uid)
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
  if not state.started then return false, say(game, "notStartedYet") end
  if state.winner then return false, say(game, "gameOver") end
  if state.turn.active ~= seat then
    return false, say(game, "othersTurn", { name = state.players[state.turn.active].name })
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
-- group.need other cards are needed (1, or 2 for a double ally). Counted per
-- faction: a double ally needs two other cards of the same faction.
-- Factions granted this turn (Game:grantAllies) always count as met;
-- granting "all" meets every ally condition.
local function allyMet(game, uid, c, group, cardsInPlay)
  local need = group.need or 1
  local factions = group.faction and { group.faction } or c.factions
  local granted = game.state.turn.granted or {}
  if granted.all then return true end
  for _, f in ipairs(factions) do
    if granted[f] then return true end
  end
  if group.faction == "samename" then -- "Splinter": another card with this name (or one with faction anyname)
    local found = 0
    for _, other in ipairs(cardsInPlay) do
      local oc = other ~= uid and card(game, other)
      if oc and (oc.id == c.id or hasFaction(oc, "anyname")) then found = found + 1 end
    end
    return found >= need
  end
  for _, f in ipairs(factions) do
    if f ~= "none" then
      local found = 0
      for _, other in ipairs(cardsInPlay) do
        if other ~= uid and hasFaction(card(game, other), f) then found = found + 1 end
      end
      if found >= need then return true end
    end
  end
  return false
end
Actions.allyMet = allyMet

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
          -- which factions' ally abilities fired this turn (turn.allyFactions)
          local turnRec = game.state.turn
          turnRec.allyFactions = turnRec.allyFactions or {}
          for _, f in ipairs(group.faction and { group.faction } or c.factions) do
            if f ~= "none" then turnRec.allyFactions[f] = true end
          end
          if game.notify then
            game:notify(say(game, "ally", { card = c.name, effects = game.effects:describe(group.effects, c.text) }))
          end
          game.effects:apply(game, seat, group.effects, { uid = uid, card = c })
          -- whenYouUseAlly(game, seat, ctx, used) on the player's cards in play
          Actions.trigger(game, seat, "whenYouUseAlly", { uid = uid, card = c, faction = group.faction })
          again = true
        end
      end
    end
  end
end

-- A required choice that takes cards from the hand (an owed discard, "scrap a
-- card from your hand") must be answered before any card is played, or Play
-- all would play the cards away. Returns that prompt, if one is waiting.
function Actions.handBlocked(game, seat)
  for _, prompt in ipairs(game.state.players[seat].prompts) do
    local fromHand = prompt.kind == "discard"
      or (prompt.kind == "scrap" and Util.indexOf(prompt.from or { "hand", "discard" }, "hand"))
    if fromHand and not prompt.optional and #Actions.targets(game, seat, prompt) > 0 then return prompt end
  end
  return nil
end

-- Cards in play whose custom effects have a whenYouPlay handler react to
-- their owner playing another card ("whenever you play a ship, gain 1 combat").
local function triggerPlayed(game, seat, uid, c)
  Actions.trigger(game, seat, "whenYouPlay", { uid = uid, card = c }, uid)
end

-- Plays a card from hand. state.turn.played lists the uids played this turn,
-- in order, for effects like "draw a card for each Blob card you've played".
---------------------------------------------------------------------------
-- Turn structure (rules.turn): phases, and costs for playing and buying.
--   phases = { { key = "action", label = "Action", play = { "action" }, buy = false, attack = false },
--              { key = "buy", label = "Buy", play = { "treasure" } } }
--     A phase allows playing `play` (true or left out: any card; a type or
--     list of types; false: none), buying unless buy = false, attacking
--     unless attack = false. A Next button moves on; End Turn ends it at any phase.
--   playCost = { action = { key = "actions", amount = 1 } }: playing a card of
--     that type spends that resource (and needs it).
--   buyCost = { key = "buys", amount = 1 }: so does each card bought.
---------------------------------------------------------------------------

-- The phase the turn is in (nil: a game without phases).
function Actions.phase(game)
  local phases = game.rules.turn and game.rules.turn.phases
  return phases and phases[game.state.turn.phase or 1]
end

-- May `what` ("buy", "attack", or a card for "play") happen in this phase?
function Actions.phaseAllows(game, what, c)
  local phase = Actions.phase(game)
  if not phase then return true end
  if what == "play" then
    if phase.play == nil or phase.play == true then return true end
    if phase.play == false then return false end
    return Actions.typeMatches(phase.play, c)
  end
  return phase[what] ~= false
end

local function notThisPhase(game)
  local phase = Actions.phase(game)
  return fail(say(game, "notThisPhase", { phase = phase.label or phase.key }))
end

-- A play or buy cost (rules.turn.playCost / buyCost): can the player pay it?
local function canPay(game, player, cost)
  if not cost then return true end
  return (player.resources[cost.key] or 0) >= (cost.amount or 1)
end
local function pay(player, cost)
  if cost then player.resources[cost.key] = (player.resources[cost.key] or 0) - (cost.amount or 1) end
end
local function playCost(game, c)
  local costs = game.rules.turn and game.rules.turn.playCost
  return costs and costs[c.type]
end
local function resourceLabel(game, key)
  for _, r in ipairs(game.rules.resources or {}) do
    if r.key == key then return r.label or Util.titleCase(key) end
  end
  return key
end

-- Can this card be played now (phase and play cost)?
function Actions.playable(game, seat, uid)
  local c = card(game, uid)
  return Actions.phaseAllows(game, "play", c) and canPay(game, game.state.players[seat], playCost(game, c))
end

-- rules.turn.skipAhead: playing a card or buying that only a later phase
-- allows moves the turn on to that phase first (playing a treasure in the
-- Action phase starts the Buy phase). Returns true if it moved on.
local function skipAheadFor(game, what, c)
  local t = game.rules.turn
  if not (t and t.skipAhead and t.phases) then return false end
  local turn = game.state.turn
  for i = (turn.phase or 1) + 1, #t.phases do
    local saved = turn.phase
    turn.phase = i
    if Actions.phaseAllows(game, what, c) then return true end
    turn.phase = saved
  end
  return false
end

-- Moves the turn on to its next phase.
function Actions.nextPhase(game, seat)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local phases = game.rules.turn and game.rules.turn.phases or {}
  local turn = game.state.turn
  if (turn.phase or 1) >= #phases then return fail(say(game, "cantUse")) end
  turn.phase = (turn.phase or 1) + 1
  return true
end

local function playNow(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local waiting = Actions.handBlocked(game, seat)
  if waiting then return fail(say(game, "firstDo", { what = Actions.promptText(game, waiting) })) end
  local player = game.state.players[seat]
  if not Util.indexOf(player.hand, uid) then return fail(say(game, "notInHand")) end
  local c = card(game, uid)
  if not Actions.phaseAllows(game, "play", c) and not skipAheadFor(game, "play", c) then return notThisPhase(game) end
  local cost = playCost(game, c)
  if not canPay(game, player, cost) then
    return fail(say(game, "notEnough", { resource = resourceLabel(game, cost.key), card = c.name, n = cost.amount or 1 }))
  end
  pay(player, cost)
  Util.removeValue(player.hand, uid)
  Actions.enterPlay(game, seat, uid)
  return true
end

-- A refused play or buy leaves the turn in the phase it was in (see skipAheadFor).
local function keepPhaseIfRefused(fn)
  return function(game, ...)
    local saved = game.state.turn.phase
    local ok, why = fn(game, ...)
    if not ok then game.state.turn.phase = saved end
    return ok, why
  end
end
Actions.play = keepPhaseIfRefused(playNow)

-- Puts a card into play (from hand, or straight from the market): onto the
-- bases row if persistent, else the play row; records it in turn.played,
-- applies its effects, triggers whenYouPlay and checks allies.
function Actions.enterPlay(game, seat, uid)
  local player = game.state.players[seat]
  local c = card(game, uid)
  if Turn.isPersistent(game.rules, c) then
    player.bases[#player.bases + 1] = uid
  else
    player.play[#player.play + 1] = uid
  end
  local turn = game.state.turn
  turn.played = turn.played or {}
  turn.played[#turn.played + 1] = uid
  game.effects:apply(game, seat, c.effects, { uid = uid, card = c })
  triggerPlayed(game, seat, uid, c)
  Actions.checkAllies(game, seat)
end

-- Does a type filter match this card? true (any), a type ("ship") or a list
-- of types ({ "base", "outpost" }). Used by flags and prompt filters.
function Actions.typeMatches(filter, c)
  if filter == true then return true end
  if type(filter) == "string" then return c.type == filter end
  if type(filter) == "table" then
    for _, t in ipairs(filter) do
      if t == c.type then return true end
    end
  end
  return false
end

-- What Play all would play: the number of cards playable in this phase, or,
-- with rules.turn.skipAhead and nothing playable now, in the first later
-- phase that has some (and that phase). The turn is left in its phase.
function Actions.playAllCount(game, seat)
  local turn = game.state.turn
  local function count()
    local n = 0
    for _, uid in ipairs(game.state.players[seat].hand) do
      if Actions.playable(game, seat, uid) then n = n + 1 end
    end
    return n
  end
  local n = count()
  local t = game.rules.turn
  if n > 0 or not (t and t.skipAhead and t.phases) then return n, nil end
  local saved = turn.phase
  for i = (saved or 1) + 1, #t.phases do
    turn.phase = i
    n = count()
    if n > 0 then
      turn.phase = saved
      return n, i
    end
  end
  turn.phase = saved
  return 0, nil
end

function Actions.playAll(game, seat)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local waiting = Actions.handBlocked(game, seat)
  if waiting then return fail(say(game, "firstDo", { what = Actions.promptText(game, waiting) })) end
  local hand = game.state.players[seat].hand
  if #hand == 0 then return fail(say(game, "handEmpty")) end
  local _, later = Actions.playAllCount(game, seat)
  if later then game.state.turn.phase = later end
  -- Plays every card it can, in hand order, again and again (a card played
  -- may draw more or pay for the next); stops early if a card played asks
  -- for a card from the hand first.
  -- (capped, in case a card keeps coming back to the hand)
  local played, plays = true, 0
  while played and plays < 200 do
    played, plays = false, plays + 1
    for _, uid in ipairs(hand) do
      if Actions.playable(game, seat, uid) then
        if not Actions.play(game, seat, uid) then return true end
        played = true
        break
      end
    end
  end
  return true
end

-- Where a buyable uid sits: ("row", slot, its market) in any market's row,
-- or ("fixed", card id).
local function locate(state, uid)
  local m, slot = State.rowOf(state, uid)
  if m then return "row", slot, m end
  for id, pile in pairs(state.market.fixed) do
    if Util.indexOf(pile, uid) then return "fixed", id end
  end
  return nil
end

-- Buys a card from the market row or a fixed pile (always its top card).
-- `free` skips the cost, for effects like "take a card for free"; `toTop`
-- puts it on top of the deck and `toHand` into the hand. Turn flags send the
-- next matching card bought (see Actions.typeMatches: true, a type or a list
-- of types) somewhere else, and are used up when they apply:
--   flags.buyToHand    into the hand
--   flags.buyToPlay    straight into play (its effects apply)
--   flags.buyToTop     on top of the deck
--   flags.mayBuyToTop  asks: top of the deck or the discard pile (place_bought prompt)
-- Afterwards a custom effect's onAcquire(game, seat, ctx) runs for the card.
local function buyNow(game, seat, uid, free, toTop, toHand)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local buyCost = not free and game.rules.turn and game.rules.turn.buyCost
  if not free and not Actions.phaseAllows(game, "buy") and not skipAheadFor(game, "buy") then return notThisPhase(game) end
  if not canPay(game, game.state.players[seat], buyCost) then
    return fail(say(game, "notEnough", { resource = resourceLabel(game, buyCost.key), card = card(game, uid).name, n = buyCost.amount or 1 }))
  end
  local market = game.state.market
  local where, slot, rowMarket = locate(game.state, uid)
  if not where then return fail(say(game, "cantBuy")) end
  if where == "fixed" then uid = market.fixed[slot][#market.fixed[slot]] end
  local c = card(game, uid)
  local player = game.state.players[seat]

  if not free then
    local key, label = Actions.resourceFor(game.rules, "buy")
    if not key then return fail("These rules have no resource with spend = \"buy\".") end
    -- flags.discount = { faction?, type?, amount }: the next matching card costs less
    local cost, discount = c.cost, player.flags.discount
    local discounted = discount and (not discount.faction or hasFaction(c, discount.faction))
      and (not discount.type or Actions.typeMatches(discount.type, c))
    if discounted then cost = math.max(0, cost - (discount.amount or 1)) end
    if (player.resources[key] or 0) < cost then
      return fail(say(game, "notEnough", { resource = label, card = c.name, n = cost }))
    end
    player.resources[key] = player.resources[key] - cost
    if discounted then player.flags.discount = nil end
    pay(player, buyCost)
  end

  if where == "row" then rowMarket.row[slot] = State.EMPTY else table.remove(market.fixed[slot]) end
  local function take(flag)
    if player.flags[flag] ~= nil and Actions.typeMatches(player.flags[flag], c) then
      player.flags[flag] = nil
      return true
    end
    return false
  end
  if toHand or take("buyToHand") then
    player.hand[#player.hand + 1] = uid
  elseif take("buyToDeck") then -- shuffled into the deck
    player.deck[#player.deck + 1] = uid
    Util.shuffle(player.deck, game.random)
  elseif take("buyToPlay") then
    Actions.fillMarket(game)
    Actions.enterPlay(game, seat, uid)
  elseif toTop or take("buyToTop") or game.rules.market.buyTo == "deck_top" then
    player.deck[#player.deck + 1] = uid
  else
    player.discard[#player.discard + 1] = uid
    if take("mayBuyToTop") then
      Actions.prompt(game, seat, { kind = "place_bought", uid = uid, optional = false })
    end
  end
  Actions.fillMarket(game)
  for _, effect in ipairs(c.effects) do
    local def = effect.key == "custom" and game.effects.custom[effect.fn]
    if def and def.onAcquire then def.onAcquire(game, seat, { uid = uid, card = c }) end
  end
  return true
end

-- Gains the top card of pile `id` (a fixed or supply pile) into the seat's
-- discard pile, if the pile has any left ("gain a Silk", "each opponent gains
-- a Gossip"). Returns the uid gained.
function Actions.gainFromPile(game, seat, id)
  local pile = game.state.market.fixed[id]
  if not pile or #pile == 0 then return nil end
  local uid = table.remove(pile)
  local player = game.state.players[seat]
  player.discard[#player.discard + 1] = uid
  return uid
end

Actions.buy = keepPhaseIfRefused(buyNow)

function Actions.scrapFromPlay(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  if game.rules.mechanics and game.rules.mechanics.scrap == false then return fail("Scrapping is off in these rules.") end
  local player = game.state.players[seat]
  local c = card(game, uid)
  if #c.scrapEffects == 0 then return fail(c.name .. " has no scrap ability.") end
  if not Actions.canScrap(game, seat, uid) then return fail(c.name .. " can only be scrapped with an ally in play.") end
  if not (Util.removeValue(player.play, uid) or Util.removeValue(player.bases, uid)) then
    return fail(say(game, "notInPlay"))
  end
  Actions.toScrap(game, uid, seat, "play")
  game.effects:apply(game, seat, c.scrapEffects, { uid = uid, card = c })
  Actions.trigger(game, seat, "whenYouUseScrap", { uid = uid, card = c })
  return true
end

-- Can this card in play use its scrap ability now? A scrap ability written
-- with a faction prefix ("blob=combat:8", from "Ally: scrap this card from
-- play...") needs an ally of that faction in play.
function Actions.canScrap(game, seat, uid)
  local c = card(game, uid)
  if #c.scrapEffects == 0 then return false end
  for _, effect in ipairs(c.scrapEffects) do
    if effect.ally and not allyMet(game, uid, c, { faction = effect.ally }, Actions.inPlay(game.state.players[seat])) then
      return false
    end
  end
  return true
end

-- Scraps a card from the market row by hand (a player dragged it onto the
-- scrap pile); the slot refills from the market deck.
function Actions.scrapFromRow(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  if game.rules.mechanics and game.rules.mechanics.scrap == false then return fail("Scrapping is off in these rules.") end
  local market, slot = State.rowOf(game.state, uid)
  if not slot then return fail(say(game, "notInRow")) end
  market.row[slot] = State.EMPTY
  Actions.toScrap(game, uid)
  Actions.fillMarket(game)
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
-- rules.win.check(game), in any kind of game, may decide instead: it returns
-- the winning seat, a list of seats (a shared win), or nil to play on.
function Actions.checkWin(game)
  local win = game.rules.win
  if win and win.check and not game.state.winner then
    local result = win.check(game)
    if result then return Actions.declare(game, type(result) == "table" and result or { result }) end
  end
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

-- The game is won by these seats (more than one: a shared win).
function Actions.declare(game, seats)
  game.state.winner = seats[1]
  game.state.winners = #seats > 1 and seats or nil
end

-- The winner's name, or the names of everyone sharing the win.
function Actions.winnerNames(game)
  local s = game.state
  local names = {}
  for _, seat in ipairs(s.winners or { s.winner }) do names[#names + 1] = s.players[seat].name end
  if #names <= 1 then return names[1] end
  return table.concat(names, ", ", 1, #names - 1) .. say(game, "and") .. names[#names]
end

-- A player's score in a points game: the points on every card they own
-- (deck, hand, discard pile, in play) plus their rules.win.stat, if any.
function Actions.score(game, seat)
  local p = game.state.players[seat]
  local win = game.rules.win or {}
  local total = win.stat and (p.stats[win.stat] or 0) or 0
  for _, list in ipairs({ p.deck, p.hand, p.discard, p.play, p.bases }) do
    for _, uid in ipairs(list) do total = total + (card(game, uid).points or 0) end
  end
  return total
end

-- Has something ended a points game? rules.win.endWhen:
--   marketEmpty = true   the market row and deck have run out
--   fixedEmpty = n       n fixed piles are empty
--   pool = { key, amount }  a shared pool of a stat (`amount` to start), taken
--                        from as players gain that stat, has run out
--   rounds = n           n full rounds have been played
--   pileEmpty = "id" or { "id", ... }  one of these fixed or supply piles is empty
--   custom = function(game) return true end
local function endTriggered(game)
  local s, e = game.state, game.rules.win.endWhen or {}
  if e.pileEmpty then
    for _, id in ipairs(type(e.pileEmpty) == "table" and e.pileEmpty or { e.pileEmpty }) do
      if s.market.fixed[id] and #s.market.fixed[id] == 0 then return true end
    end
  end
  if e.marketEmpty and #s.market.deck == 0 then
    local empty = true
    for _, uid in ipairs(s.market.row) do if uid ~= State.EMPTY then empty = false end end
    if empty then return true end
  end
  if e.fixedEmpty then
    local n = 0
    for _, id in ipairs(game.fixedIds or {}) do if #(s.market.fixed[id] or {}) == 0 then n = n + 1 end end
    if n >= e.fixedEmpty then return true end
  end
  if e.pool and (s.pool or 0) <= 0 then return true end
  if e.rounds and (s.turn.round or 0) >= e.rounds then return true end
  if e.custom and e.custom(game) then return true end
  return false
end

-- After each turn of a points game: once the end is triggered, the game ends
-- (at once, or with rules.win.finishRound when the round is over, so everyone
-- has had the same number of turns) and the highest score wins; a tie is a
-- shared win.
function Actions.checkEnd(game, roundOver)
  local win = game.rules.win
  if not win or win.type ~= "points" or game.state.winner then return end
  local s = game.state
  if roundOver then s.turn.round = (s.turn.round or 0) + 1 end
  if not s.ending and endTriggered(game) then s.ending = true end
  if not s.ending or (win.finishRound and not roundOver) then return end
  local best, seats = nil, {}
  for seat in ipairs(s.players) do
    local score = Actions.score(game, seat)
    if not best or score > best then best, seats = score, { seat }
    elseif score == best then seats[#seats + 1] = seat end
  end
  Actions.declare(game, seats)
end

-- A base's defense now: its printed defense plus every defenseMod(game,
-- seat, ctx, base) hook on any player's cards in play. base = { uid, owner }
-- ("your bases gain +1 Defense"). Never below 0.
function Actions.defenseOf(game, owner, uid)
  local defense = card(game, uid).defense or 0
  for seat, player in ipairs(game.state.players) do
    for _, other in ipairs(Actions.inPlay(player)) do
      for _, effect in ipairs(card(game, other).effects) do
        local def = effect.key == "custom" and game.effects.custom[effect.fn]
        if def and def.defenseMod then
          defense = defense + (def.defenseMod(game, seat, { uid = other }, { uid = uid, owner = owner }) or 0)
        end
      end
    end
  end
  return math.max(0, defense)
end

-- Without baseUid, spends the whole attack pool on the target player's
-- win stat. With it, spends the base's defense to destroy that base.
function Actions.attack(game, seat, target, baseUid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  if not Actions.phaseAllows(game, "attack") then return notThisPhase(game) end
  local victim = game.state.players[target]
  if target == seat or not victim then return fail(say(game, "pickOpponent")) end
  if victim.out then return fail(say(game, "alreadyOut", { name = victim.name })) end
  local key, label = Actions.resourceFor(game.rules, "attack")
  if not key then return fail("These rules have no resource with spend = \"attack\".") end
  local player = game.state.players[seat]
  local pool = player.resources[key] or 0
  if pool <= 0 then return fail(say(game, "nothingToAttack", { resource = label })) end
  local guards = Actions.guards(game, target)

  if baseUid then
    if not Util.indexOf(victim.bases, baseUid) then return fail(say(game, "baseNotInPlay")) end
    if Actions.typeDef(game, card(game, baseUid)).target == false then
      return fail(say(game, "cantBeAttacked", { card = card(game, baseUid).name }))
    end
    if #guards > 0 and not Util.indexOf(guards, baseUid) then return fail(say(game, "guardsFirst")) end
    local c = card(game, baseUid)
    local defense = Actions.defenseOf(game, target, baseUid)
    if pool < defense then return fail(say(game, "needs", { card = c.name, n = defense, resource = label })) end
    player.resources[key] = pool - defense
    Actions.destroyBase(game, target, baseUid)
    return true
  end

  if #guards > 0 then return fail(say(game, "guardsFirst")) end
  local stat = game.rules.win and game.rules.win.stat
  if not stat then return fail("These rules have no stat to attack (rules.win.stat).") end
  -- The defender's cards in play can change the damage (whenAttacked).
  local hit = { damage = pool, attacker = seat }
  Actions.trigger(game, target, "whenAttacked", hit)
  victim.stats[stat] = (victim.stats[stat] or 0) - math.max(0, hit.damage)
  player.resources[key] = 0
  Actions.checkWin(game)
  return true
end

---------------------------------------------------------------------------
-- Attacks and reactions: an effect that hits each opponent ("each opponent
-- gains a Gossip") goes to them one at a time, starting on the attacker's
-- left. An opponent holding a card with react_effects is asked first, on
-- their own screen, whether to reveal it: its react effects apply to them
-- (`block` makes the attack miss them), and they may reveal another. The
-- attack then hits them unless it was blocked. The attacker plays on
-- meanwhile; anything still unanswered when their turn ends is taken as
-- "don't reveal".
---------------------------------------------------------------------------

-- The other seats still in the game, in turn order from seat's left.
local function opponentsInOrder(game, seat)
  local out, count = {}, #game.state.players
  for step = 1, count - 1 do
    local other = (seat + step - 1) % count + 1
    if not game.state.players[other].out then out[#out + 1] = other end
  end
  return out
end

-- Reaction cards in the seat's hand not yet revealed to this attack.
local function reactions(game, seat, hit)
  local out = {}
  for _, uid in ipairs(game.state.players[seat].hand) do
    if #card(game, uid).reactEffects > 0 and not (hit and hit.revealed[uid]) then out[#out + 1] = uid end
  end
  return out
end

function Actions.hitOpponents(game, seat, effect, ctx)
  for _, other in ipairs(opponentsInOrder(game, seat)) do
    -- plain data, so a waiting reaction survives onSave
    local hit = { kind = "react", attacker = seat, effect = effect, source = ctx.uid, revealed = {}, optional = true, count = 99 }
    if #reactions(game, other, hit) > 0 then
      Actions.prompt(game, other, hit)
    else
      Actions.resolveHit(game, other, hit)
    end
  end
end

-- The attack in `hit` lands on `victim`, unless a reaction blocked it.
function Actions.resolveHit(game, victim, hit)
  local name = game.state.players[victim].name
  if hit.blocked then
    if game.notify then game:notify(say(game, "unaffected", { name = name })) end
    return
  end
  local effect = hit.effect
  local ctx = { uid = hit.source, card = hit.source and card(game, hit.source) or nil }
  if effect.key == "custom" then
    game.effects.custom[effect.fn].eachOpponent(game, hit.attacker, victim, ctx)
  else
    game.effects.handlers[effect.key].toOpponent(game, hit.attacker, victim, effect.amount, ctx, effect)
  end
  Actions.settle(game, victim)
end

-- Reveals a reaction card against the attack in `hit` (the victim's prompt).
local function reveal(game, seat, uid, hit)
  hit.revealed[uid] = true
  local c = card(game, uid)
  if game.notify then
    game:notify(say(game, "reveals", { name = game.state.players[seat].name, card = c.name, effects = game.effects:describe(c.reactEffects, c.text) }))
  end
  game.effects:apply(game, seat, c.reactEffects, { uid = uid, card = c, attack = hit })
end

-- At the end of the attacker's turn, reactions nobody answered are passed on.
local function closeReactions(game, attacker)
  for seat, p in ipairs(game.state.players) do
    local waiting = {}
    for i = #p.prompts, 1, -1 do
      if p.prompts[i].kind == "react" and p.prompts[i].attacker == attacker then
        table.insert(waiting, 1, table.remove(p.prompts, i))
      end
    end
    for _, hit in ipairs(waiting) do Actions.resolveHit(game, seat, hit) end
  end
end

---------------------------------------------------------------------------
-- Prompts: choices a player answers from the action panel, first in first out.
-- A prompt is plain data so it survives onSave:
--   { kind, count, optional, text?, from?, options?, maxCost?, uid?, owe?,
--     cardType?, includeFixed?, toTop?, drawPerPick?, custom?, exclude? }
-- kinds: choice, scrap, discard, scrap_row, destroy_base, free_buy, reminder,
-- react (reveal a reaction to an attack; see Actions.hitOpponents),
-- opponent (pick an opponent; `owe` such as { discard = 1 } is added to theirs),
-- place_bought (put the bought card `uid` on top of the deck or leave it in the discard pile),
-- pick (pick a card you have in play; rules.customEffects[custom].onPick runs)
--
-- free_buy: maxCost and cardType limit it, includeFixed adds the fixed piles,
-- toTop puts the card on top of the deck. scrap and discard: drawPerPick
-- draws that many cards for each card picked, once the prompt ends.
---------------------------------------------------------------------------

function Actions.prompt(game, seat, prompt)
  prompt.count = prompt.count or 1
  local prompts = game.state.players[seat].prompts
  prompts[#prompts + 1] = prompt
end

function Actions.promptText(game, prompt)
  if prompt.text then return prompt.text end
  local n, kind = prompt.count, prompt.kind
  local cards = say(game, n == 1 and "card" or "cards")
  if kind == "choice" then return say(game, "chooseOne") end
  if kind == "scrap" then
    local from = prompt.from or { "hand", "discard" }
    local names = { hand = "yourHand", discard = "yourDiscardPile", row = "theMarketRow" }
    local list = {}
    for _, f in ipairs(from) do list[#list + 1] = names[f] and say(game, names[f]) or f end
    return say(game, prompt.optional and "scrapUpTo" or "scrapFrom", { n = n, cards = cards, where = table.concat(list, say(game, "or")) })
  end
  if kind == "discard" then return say(game, prompt.optional and "discardUpTo" or "discardN", { n = n, cards = cards }) end
  if kind == "scrap_row" then return say(game, "scrapRow", { n = n, cards = cards }) end
  if kind == "destroy_base" then
    return say(game, prompt.bounce and "returnUpTo" or "destroyUpTo", { n = n, bases = say(game, n == 1 and "base" or "bases") })
  end
  if kind == "free_buy" then
    local what = prompt.cardType and say(game, "aType", {
      type = type(prompt.cardType) == "table" and table.concat(prompt.cardType, say(game, "or")) or prompt.cardType }) or say(game, "aCard")
    return say(game, "takeFree", {
      what = what,
      limit = prompt.maxCost and say(game, "costLimit", { n = prompt.maxCost }) or "",
      where = say(game, prompt.includeFixed and "theMarket" or "theMarketRow"),
      dest = prompt.toTop and say(game, "ontoDeck") or prompt.toHand and say(game, "intoHand") or "",
    })
  end
  if kind == "pick" then return say(game, "chooseCard") end
  if kind == "react" then
    local source = prompt.source and card(game, prompt.source)
    return say(game, "reactTo", {
      name = game.state.players[prompt.attacker].name,
      card = source and source.name or "",
      effects = game.effects:describe({ prompt.effect }),
    })
  end
  if kind == "place_bought" then return say(game, "whereGoes", { card = card(game, prompt.uid).name }) end
  if kind == "opponent" then
    local owed = prompt.owe and prompt.owe.discard
    return owed and say(game, "chooseOpponentDiscard", { n = owed, cards = say(game, owed == 1 and "card" or "cards") })
      or say(game, "chooseOpponent")
  end
  return kind
end

-- Does a card pass a prompt's filters? cardType (see Actions.typeMatches),
-- maxCost, and factions (a list; the card needs one of them).
local function passes(prompt, c)
  if prompt.cardType and not Actions.typeMatches(prompt.cardType, c) then return false end
  if prompt.maxCost and c.cost > prompt.maxCost then return false end
  if prompt.factions then
    for _, f in ipairs(prompt.factions) do
      for _, cf in ipairs(c.factions) do
        if cf == f then return true end
      end
    end
    return false
  end
  return true
end

-- What the first prompt can be answered with right now: { {value, label}, ... }
function Actions.targets(game, seat, prompt)
  local state = game.state
  local player = state.players[seat]
  local out = {}
  local function add(uid, where)
    out[#out + 1] = { value = uid, label = card(game, uid).name .. (where and (" (" .. where .. ")") or "") }
  end
  local function addIf(uid, where)
    if uid == State.EMPTY or uid == prompt.exclude then return end
    if prompt.only and not Util.indexOf(prompt.only, uid) then return end -- limited to these uids
    if passes(prompt, card(game, uid)) then add(uid, where) end
  end
  local kind = prompt.kind
  if kind == "choice" then
    for i, option in ipairs(prompt.options) do
      out[#out + 1] = { value = tostring(i), label = game.effects:describe({ option }) }
    end
  elseif kind == "scrap" then
    -- from: any of "hand", "discard", "row" (the market row)
    for _, from in ipairs(prompt.from or { "hand", "discard" }) do
      if from == "row" then
        for _, m in ipairs(State.rows(state)) do
          for _, uid in ipairs(m.row) do addIf(uid, from) end
        end
      else
        for _, uid in ipairs(player[from]) do addIf(uid, from) end
      end
    end
  elseif kind == "discard" then
    for _, uid in ipairs(player.hand) do add(uid) end
  elseif kind == "scrap_row" then
    for _, m in ipairs(State.rows(state)) do
      for _, uid in ipairs(m.row) do addIf(uid) end
    end
  elseif kind == "free_buy" then
    for _, m in ipairs(State.rows(state)) do
      for _, uid in ipairs(m.row) do addIf(uid) end
    end
    if prompt.includeFixed then
      for _, id in ipairs(game.fixedIds) do
        local pile = state.market.fixed[id]
        local top = pile and pile[#pile]
        if top then addIf(top, "pile") end
      end
    end
  elseif kind == "pick" then
    -- scope: "play" (your cards in play, the default), "bases" (every base in
    -- play), "hand", "discard", "deck" (use `only` for the top few), "opponentDiscard"
    local scope = prompt.scope or "play"
    if scope == "play" then
      for _, uid in ipairs(Actions.inPlay(player)) do addIf(uid) end
    elseif scope == "bases" then
      for s, p in ipairs(state.players) do
        for _, uid in ipairs(p.bases) do addIf(uid, s ~= seat and p.name or nil) end
      end
    elseif scope == "discard" or scope == "hand" or scope == "deck" then
      for _, uid in ipairs(player[scope]) do addIf(uid) end
    elseif scope == "opponentDiscard" then
      for _, other in ipairs(game:opponentsOf(seat)) do
        for _, uid in ipairs(state.players[other].discard) do addIf(uid, state.players[other].name) end
      end
    end
  elseif kind == "destroy_base" then
    for _, other in ipairs(game:opponentsOf(seat)) do
      for _, uid in ipairs(state.players[other].bases) do
        if Actions.typeDef(game, card(game, uid)).target ~= false then add(uid, state.players[other].name) end
      end
    end
  elseif kind == "opponent" then
    for _, other in ipairs(game:opponentsOf(seat)) do
      out[#out + 1] = { value = tostring(other), label = state.players[other].name }
    end
  elseif kind == "react" then
    for _, uid in ipairs(reactions(game, seat, prompt)) do
      out[#out + 1] = { value = uid, label = say(game, "reveal", { card = card(game, uid).name }) }
    end
  elseif kind == "place_bought" then
    if Util.indexOf(player.discard, prompt.uid) then
      out[1] = { value = "top", label = say(game, "topOfDeck") }
      out[2] = { value = "discard", label = say(game, "yourDiscard") }
    end
  end
  return out
end

-- The custom effect a prompt names (prompt.custom), if it has `hook`.
local function promptHook(game, prompt, hook)
  local def = prompt.custom and game.effects.custom[prompt.custom]
  return def and def[hook]
end

-- Removes the first prompt. One with drawPerPick then draws for each card
-- picked ("scrap up to two cards, then draw a card for each"), and the
-- custom effect it names gets afterPrompt(game, seat, prompt) (prompt.picked
-- says how many were picked).
local function finish(game, seat)
  local prompt = table.remove(game.state.players[seat].prompts, 1)
  if not prompt then return end
  if prompt.kind == "react" then return Actions.resolveHit(game, seat, prompt) end
  if prompt.drawPerPick and (prompt.picked or 0) > 0 then
    game:draw(seat, prompt.drawPerPick * prompt.picked)
  end
  local after = promptHook(game, prompt, "afterPrompt")
  if after then after(game, seat, prompt) end
end

-- Drops prompts at the front that have nothing left to pick, such as a
-- discard with an empty hand. Reminders always wait for the player.
function Actions.settle(game, seat)
  local prompts = game.state.players[seat].prompts
  while prompts[1] and prompts[1].kind ~= "reminder" and #Actions.targets(game, seat, prompts[1]) == 0 do
    finish(game, seat)
  end
end

-- Answers the first prompt with one of its targets' values. A prompt naming
-- a custom effect (prompt.custom) calls its afterPick(game, seat, uid,
-- prompt) after each card picked (the card's cost, faction, etc. are known).
function Actions.pick(game, seat, value)
  local state = game.state
  local player = state.players[seat]
  local prompt = player.prompts[1]
  if not prompt then return fail(say(game, "nothingToChoose")) end
  local valid = false
  for _, t in ipairs(Actions.targets(game, seat, prompt)) do
    if t.value == value then valid = true end
  end
  if not valid then return fail(say(game, "notAnOption")) end

  local kind = prompt.kind
  if kind == "choice" or kind == "pick" then
    finish(game, seat)
    if kind == "pick" then
      local def = game.effects.custom[prompt.custom or ""]
      if not def or not def.onPick then error("pick prompt needs custom = a custom effect with onPick", 0) end
      def.onPick(game, seat, value, prompt)
      Actions.settle(game, seat)
      return true
    end
    local c = prompt.uid and card(game, prompt.uid)
    game.effects:apply(game, seat, { prompt.options[tonumber(value)] }, { uid = prompt.uid, card = c })
    Actions.settle(game, seat)
    return true
  elseif kind == "scrap" then
    local from
    if Util.removeValue(player.hand, value) then
      from = "hand"
    elseif Util.removeValue(player.discard, value) then
      from = "discard"
    else
      local m, slot = State.rowOf(state, value)
      m.row[slot] = State.EMPTY
      from = "row"
    end
    Actions.toScrap(game, value, seat, from)
    if from == "row" then Actions.fillMarket(game) end
  elseif kind == "discard" then
    Util.removeValue(player.hand, value)
    player.discard[#player.discard + 1] = value
  elseif kind == "scrap_row" then
    local m, slot = State.rowOf(state, value)
    m.row[slot] = State.EMPTY
    Actions.toScrap(game, value, seat, "row")
    Actions.fillMarket(game)
  elseif kind == "free_buy" then
    Actions.buy(game, seat, value, true, prompt.toTop, prompt.toHand)
  elseif kind == "destroy_base" then
    for _, other in ipairs(game:opponentsOf(seat)) do
      if prompt.bounce then
        local owner = state.players[other]
        if Util.removeValue(owner.bases, value) then owner.hand[#owner.hand + 1] = value end
      else
        Actions.destroyBase(game, other, value)
      end
    end
  elseif kind == "opponent" then
    local owed = state.players[tonumber(value)].owed
    for key, n in pairs(prompt.owe or {}) do owed[key] = (owed[key] or 0) + n end
  elseif kind == "react" then
    reveal(game, seat, value, prompt)
  elseif kind == "place_bought" and value == "top" then
    Util.removeValue(player.discard, prompt.uid)
    player.deck[#player.deck + 1] = prompt.uid
  end

  prompt.picked = (prompt.picked or 0) + 1
  local after = promptHook(game, prompt, "afterPick")
  if after then after(game, seat, value, prompt) end
  prompt.count = prompt.count - 1
  if prompt.count <= 0 then finish(game, seat) end
  Actions.settle(game, seat)
  return true
end

-- Closes the first prompt without picking (or after picking fewer than allowed).
function Actions.done(game, seat)
  local player = game.state.players[seat]
  local prompt = player.prompts[1]
  if not prompt then return fail("There's nothing to finish.") end
  if not prompt.optional and #Actions.targets(game, seat, prompt) > 0 then
    return fail(say(game, "chooseFirst", { what = Actions.promptText(game, prompt) }))
  end
  finish(game, seat)
  Actions.settle(game, seat)
  return true
end

---------------------------------------------------------------------------
-- Activated abilities: a card in play whose custom effect has activate(game,
-- seat, ctx) can be used once each turn without scrapping it (a "Use" button).
---------------------------------------------------------------------------

function Actions.activatable(game, seat)
  local out = {}
  local used = game.state.turn.activated or {}
  for _, uid in ipairs(Actions.inPlay(game.state.players[seat])) do
    if not used[uid] then
      for _, effect in ipairs(card(game, uid).effects) do
        local def = effect.key == "custom" and game.effects.custom[effect.fn]
        if def and def.activate then out[#out + 1] = { uid = uid, def = def }; break end
      end
    end
  end
  return out
end

function Actions.activate(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  for _, a in ipairs(Actions.activatable(game, seat)) do
    if a.uid == uid then
      local turn = game.state.turn
      turn.activated = turn.activated or {}
      turn.activated[uid] = true
      a.def.activate(game, seat, { uid = uid, card = card(game, uid) })
      return true
    end
  end
  return fail(say(game, "cantUse"))
end

---------------------------------------------------------------------------
-- Objectives: secret per-player goals (deck = objective). Each card names a
-- custom effect in its condition column whose check(game, seat) says the
-- goal is met; completing it applies the card's effects as the reward.
-- rules.objectives = { count, perTurn, toWin, label }.
---------------------------------------------------------------------------

-- Is objective `uid` met for this seat right now?
function Actions.objectiveMet(game, seat, uid)
  local c = card(game, uid)
  local def = c.condition and game.effects.custom[c.condition]
  return def and def.check and def.check(game, seat, { uid = uid, card = c }) and true or false
end

-- The seat's objectives that can be completed now (met, and the turn's
-- allowance not used up).
function Actions.completable(game, seat)
  local out = {}
  local rules = game.rules.objectives or {}
  if game.state.turn.active ~= seat or (game.state.turn.completed or 0) >= (rules.perTurn or 1) then return out end
  for _, uid in ipairs(game.state.players[seat].objectives) do
    if Actions.objectiveMet(game, seat, uid) then out[#out + 1] = uid end
  end
  return out
end

function Actions.completeObjective(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local player = game.state.players[seat]
  if not Util.indexOf(player.objectives, uid) then return fail(say(game, "notYourGoal")) end
  if not Util.indexOf(Actions.completable(game, seat), uid) then return fail(say(game, "notYet")) end
  Util.removeValue(player.objectives, uid)
  player.completed[#player.completed + 1] = uid
  local turn = game.state.turn
  turn.completed = (turn.completed or 0) + 1
  local c = card(game, uid)
  if game.notify then game:notify(say(game, "completed", { name = player.name, card = c.name })) end
  game.effects:apply(game, seat, c.effects, { uid = uid, card = c })
  local rules = game.rules.objectives or {}
  if rules.toWin and #player.completed >= rules.toWin then game.state.winner = seat end
  return true
end

---------------------------------------------------------------------------
-- Turn start and end
---------------------------------------------------------------------------

-- Start of a seat's turn: this turn's records (allies fired, cards played,
-- copies) are cleared, owed discards become a prompt, and persistent cards
-- in play apply their effects (and allies) again.
function Actions.startTurn(game, seat)
  local player = game.state.players[seat]
  local turn = game.state.turn
  turn.allyFired, turn.played, turn.copies = {}, {}, {}
  turn.factions, turn.atEnd, turn.scrapped = {}, {}, { total = 0, handOrDiscard = 0 }
  turn.granted, turn.gained, turn.allyFactions, turn.completed = {}, {}, {}, 0
  turn.activated = {}
  turn.phase = 1
  local hooks = game.rules.turn
  if hooks and hooks.onStart then hooks.onStart(game, seat) end
  if (player.owed.discard or 0) > 0 then
    Actions.prompt(game, seat, { kind = "discard", count = player.owed.discard, optional = false })
    player.owed.discard = 0
  end
  for _, uid in ipairs(player.bases) do
    local c = card(game, uid)
    if Actions.typeDef(game, c).replay ~= false then
      game.effects:apply(game, seat, c.effects, { uid = uid, card = c })
    end
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
      return fail(say(game, "finishFirst", { what = Actions.promptText(game, prompt) }))
    end
  end
  while player.prompts[1] do finish(game, seat) end
  closeReactions(game, seat)
  player.flags = {}
  local hooks = game.rules.turn
  if hooks and hooks.onEnd then hooks.onEnd(game, seat) end

  -- End-of-turn hooks: jobs queued this turn (game:atTurnEnd), then cards in
  -- play whose custom effect's whenTurnEnds returns "hand": they're set aside
  -- instead of discarded and go back to the hand after the new hand is drawn.
  local turn = game.state.turn
  for _, job in ipairs(turn.atEnd or {}) do
    local def = game.effects.custom[job.custom]
    if def and def.atTurnEnd then def.atTurnEnd(game, seat, job) end
  end
  local keep = {}
  for _, uid in ipairs(player.play) do
    local c = card(game, uid)
    for _, effect in ipairs(c.effects) do
      local def = effect.key == "custom" and game.effects.custom[effect.fn]
      if def and def.whenTurnEnds and def.whenTurnEnds(game, seat, { uid = uid, card = c }) == "hand" then
        keep[#keep + 1] = uid
        break
      end
    end
  end
  for _, uid in ipairs(keep) do Util.removeValue(player.play, uid) end

  Turn.endTurn(game.state, game.rules, game.random)
  for _, uid in ipairs(keep) do player.hand[#player.hand + 1] = uid end
  -- a round is over when play comes back round to the first seat
  Actions.checkEnd(game, game.state.turn.active == (game.state.turn.first or game.rules.firstSeat or 1))
  Actions.checkWin(game)
  if game.state.winner then return true end
  Actions.startTurn(game, game.state.turn.active)
  return true
end

return Actions
