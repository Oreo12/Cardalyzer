-- Player actions: buy, play, ally triggers, scrap, attack, prompts, turn
-- start/end. Pure state changes like turn.lua; game.lua redraws after each.
--
-- Every action returns true, or false plus a message to show the player.
local Util = require("engine.util")
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
    for _, slot in ipairs(Turn.fillMarket(state)) do
      local uid = state.market.row[slot]
      -- (an earlier event in this pass may have emptied the slot, e.g. "scrap the row")
      local c = uid ~= State.EMPTY and game:cardOf(uid)
      if c and Actions.typeDef(game, c).event then
        state.market.row[slot] = State.EMPTY
        state.market.scrap[#state.market.scrap + 1] = uid
        if game.notify then game:notify("Event: " .. c.name .. ". " .. game.effects:describe(c.effects, c.text)) end
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
  for _ = 1, #state.market.deck + #state.market.row do
    local moved = false
    for i, uid in ipairs(state.market.row) do
      if uid ~= State.EMPTY and Actions.typeDef(game, game:cardOf(uid)).event then
        table.insert(state.market.deck, 1, uid)
        state.market.row[i] = State.EMPTY
        moved = true
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
-- group.need other cards are needed (1, or 2 for a double ally). Counted per
-- faction: a double ally needs two other cards of the same faction.
-- Factions granted this turn (Game:grantAllies) always count as met.
local function allyMet(game, uid, c, group, cardsInPlay)
  local need = group.need or 1
  local factions = group.faction and { group.faction } or c.factions
  local granted = game.state.turn.granted or {}
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
            game:notify(c.name .. " ally: " .. game.effects:describe(group.effects, c.text))
          end
          game.effects:apply(game, seat, group.effects, { uid = uid, card = c })
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
function Actions.play(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local waiting = Actions.handBlocked(game, seat)
  if waiting then return fail("First: " .. Actions.promptText(game, waiting) .. ".") end
  local player = game.state.players[seat]
  if not Util.removeValue(player.hand, uid) then return fail("That card isn't in your hand.") end
  Actions.enterPlay(game, seat, uid)
  return true
end

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

function Actions.playAll(game, seat)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  local waiting = Actions.handBlocked(game, seat)
  if waiting then return fail("First: " .. Actions.promptText(game, waiting) .. ".") end
  local hand = game.state.players[seat].hand
  if #hand == 0 then return fail("Your hand is empty.") end
  -- Stops early if a card played asks for a card from the hand first.
  while #hand > 0 and Actions.play(game, seat, hand[1]) do end
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
-- `free` skips the cost, for effects like "take a card for free"; `toTop`
-- puts it on top of the deck and `toHand` into the hand. Turn flags send the
-- next matching card bought (see Actions.typeMatches: true, a type or a list
-- of types) somewhere else, and are used up when they apply:
--   flags.buyToHand    into the hand
--   flags.buyToPlay    straight into play (its effects apply)
--   flags.buyToTop     on top of the deck
--   flags.mayBuyToTop  asks: top of the deck or the discard pile (place_bought prompt)
-- Afterwards a custom effect's onAcquire(game, seat, ctx) runs for the card.
function Actions.buy(game, seat, uid, free, toTop, toHand)
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
    -- flags.discount = { faction?, type?, amount }: the next matching card costs less
    local cost, discount = c.cost, player.flags.discount
    local discounted = discount and (not discount.faction or hasFaction(c, discount.faction))
      and (not discount.type or Actions.typeMatches(discount.type, c))
    if discounted then cost = math.max(0, cost - (discount.amount or 1)) end
    if (player.resources[key] or 0) < cost then
      return fail("Not enough " .. label .. ": " .. c.name .. " costs " .. cost .. ".")
    end
    player.resources[key] = player.resources[key] - cost
    if discounted then player.flags.discount = nil end
  end

  if where == "row" then market.row[slot] = State.EMPTY else table.remove(market.fixed[slot]) end
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

function Actions.scrapFromPlay(game, seat, uid)
  local ok, why = isActive(game, seat)
  if not ok then return fail(why) end
  if game.rules.mechanics and game.rules.mechanics.scrap == false then return fail("Scrapping is off in these rules.") end
  local player = game.state.players[seat]
  local c = card(game, uid)
  if #c.scrapEffects == 0 then return fail(c.name .. " has no scrap ability.") end
  if not Actions.canScrap(game, seat, uid) then return fail(c.name .. " can only be scrapped with an ally in play.") end
  if not (Util.removeValue(player.play, uid) or Util.removeValue(player.bases, uid)) then
    return fail("That card isn't in play.")
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
  local market = game.state.market
  local slot = Util.indexOf(market.row, uid)
  if not slot then return fail("That card isn't in the market row.") end
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
    if Actions.typeDef(game, card(game, baseUid)).target == false then return fail(card(game, baseUid).name .. " can't be attacked.") end
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
  -- The defender's cards in play can change the damage (whenAttacked).
  local hit = { damage = pool, attacker = seat }
  Actions.trigger(game, target, "whenAttacked", hit)
  victim.stats[stat] = (victim.stats[stat] or 0) - math.max(0, hit.damage)
  player.resources[key] = 0
  Actions.checkWin(game)
  return true
end

---------------------------------------------------------------------------
-- Prompts: choices a player answers from the action panel, first in first out.
-- A prompt is plain data so it survives onSave:
--   { kind, count, optional, text?, from?, options?, maxCost?, uid?, owe?,
--     cardType?, includeFixed?, toTop?, drawPerPick?, custom?, exclude? }
-- kinds: choice, scrap, discard, scrap_row, destroy_base, free_buy, reminder,
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

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

function Actions.promptText(game, prompt)
  if prompt.text then return prompt.text end
  local n, kind = prompt.count, prompt.kind
  if kind == "choice" then return "Choose one" end
  if kind == "scrap" then
    local from = prompt.from or { "hand", "discard" }
    local names = { hand = "your hand", discard = "your discard pile", row = "the market row" }
    local list = {}
    for _, f in ipairs(from) do list[#list + 1] = names[f] or f end
    return (prompt.optional and "Scrap up to " or "Scrap ") .. plural(n, "card") .. " from " .. table.concat(list, " or ")
  end
  if kind == "discard" then return (prompt.optional and "Discard up to " or "Discard ") .. plural(n, "card") end
  if kind == "scrap_row" then return "Scrap up to " .. plural(n, "card") .. " from the market row" end
  if kind == "destroy_base" then
    return (prompt.bounce and "Return up to " or "Destroy up to ") .. plural(n, "base") .. (prompt.bounce and " to its owner's hand" or "")
  end
  if kind == "free_buy" then
    return "Take " .. (prompt.cardType and ("a " .. (type(prompt.cardType) == "table" and table.concat(prompt.cardType, " or ") or prompt.cardType)) or "a card")
      .. (prompt.maxCost and (" costing " .. prompt.maxCost .. " or less") or "")
      .. (prompt.includeFixed and " from the market" or " from the market row") .. " for free"
      .. (prompt.toTop and ", onto your deck" or prompt.toHand and ", into your hand" or "")
  end
  if kind == "pick" then return "Choose a card" end
  if kind == "place_bought" then return "Where should " .. card(game, prompt.uid).name .. " go?" end
  if kind == "opponent" then
    local owed = prompt.owe and prompt.owe.discard
    return owed and ("Choose an opponent to discard " .. plural(owed, "card") .. " next turn") or "Choose an opponent"
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
      for _, uid in ipairs(from == "row" and state.market.row or player[from]) do addIf(uid, from) end
    end
  elseif kind == "discard" then
    for _, uid in ipairs(player.hand) do add(uid) end
  elseif kind == "scrap_row" then
    for _, uid in ipairs(state.market.row) do addIf(uid) end
  elseif kind == "free_buy" then
    for _, uid in ipairs(state.market.row) do addIf(uid) end
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
  elseif kind == "place_bought" then
    if Util.indexOf(player.discard, prompt.uid) then
      out[1] = { value = "top", label = "Top of your deck" }
      out[2] = { value = "discard", label = "Your discard pile" }
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
  if not prompt then return fail("There's nothing to choose.") end
  local valid = false
  for _, t in ipairs(Actions.targets(game, seat, prompt)) do
    if t.value == value then valid = true end
  end
  if not valid then return fail("That isn't one of the options.") end

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
      state.market.row[Util.indexOf(state.market.row, value)] = State.EMPTY
      from = "row"
    end
    Actions.toScrap(game, value, seat, from)
    if from == "row" then Actions.fillMarket(game) end
  elseif kind == "discard" then
    Util.removeValue(player.hand, value)
    player.discard[#player.discard + 1] = value
  elseif kind == "scrap_row" then
    state.market.row[Util.indexOf(state.market.row, value)] = State.EMPTY
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
    return fail("You have to choose first: " .. Actions.promptText(game, prompt) .. ".")
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
  return fail("That can't be used now.")
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
  if not Util.indexOf(player.objectives, uid) then return fail("That isn't one of your goals.") end
  if not Util.indexOf(Actions.completable(game, seat), uid) then return fail("You can't complete that yet.") end
  Util.removeValue(player.objectives, uid)
  player.completed[#player.completed + 1] = uid
  local turn = game.state.turn
  turn.completed = (turn.completed or 0) + 1
  local c = card(game, uid)
  if game.notify then game:notify(player.name .. " completed " .. c.name .. ".") end
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
      return fail("Finish this first: " .. Actions.promptText(game, prompt) .. ".")
    end
  end
  while player.prompts[1] do finish(game, seat) end
  player.flags = {}

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
  Actions.startTurn(game, game.state.turn.active)
  return true
end

return Actions
