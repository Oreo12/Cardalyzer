-- Turn loop over game state: setup, drawing (with reshuffle), market refill,
-- and end-of-turn cleanup. Pure state changes; the board re-renders after.
local Util = require("engine.util")
local State = require("engine.state")

local Turn = {}

-- How many cards the player `order`-th in turn order draws first, out of
-- `count` players. An opening-hand rule is one of:
--   5                                   everyone draws 5
--   { 3, 5 }                            by turn order; the last number repeats
--   { players = { [2] = { 3, 5 } }, otherwise = { 3, 4, 5 } }
--                                       by player count, then turn order
function Turn.openingHandSize(spec, order, count, handSize)
  if type(spec) == "table" and spec.players then
    spec = spec.players[count] or spec.otherwise or handSize
  end
  if type(spec) == "table" then return spec[order] or spec[#spec] end
  return spec or handSize
end

-- The opening-hand rule in use: rules.openingHands[choice].hands when the
-- game offers a choice (picked in the setup menu), else rules.openingHand.
function Turn.openingRule(rules, choice)
  local options = rules.openingHands
  if options and #options > 0 then
    local picked = options[choice or 1] or options[1]
    return picked.hands
  end
  return rules.openingHand
end

-- `opening` is the opening-hand rule (see Turn.openingRule); default rules.openingHand.
-- `sets` ({ [key] = true }) limits the cards to those sets; a card with no
-- set is always in. nil means every card.
-- `kits` ({ [seat] = kit }) gives players their own starting pack (rules.kits):
-- the kit's set supplies that player's starter cards (instead of the usual
-- ones) and its dealt cards go into their play area; its market cards join
-- the market deck. kit.stats and kit.handSize override the player's.
-- `supplyChoice` picks the supply piles (see Turn.chooseSupply).
function Turn.setup(state, rules, cards, random, opening, sets, kits, supplyChoice)
  kits = kits or {}
  local pool = rules.win and rules.win.endWhen and rules.win.endWhen.pool
  if pool then state.pool = pool.amount end
  local kitSets = {}
  for _, kit in ipairs(rules.kits or {}) do kitSets[kit.set] = true end
  -- the kit market cards in play: listed by a kit (kit.market), or all of a
  -- kit set's market cards for a kit given only by its set
  local inKit, kitMarket = {}, {}
  for _, kit in pairs(kits) do
    if kit.market then
      for _, id in ipairs(kit.market) do kitMarket[id] = true end
    elseif kit.set then
      inKit[kit.set] = true
    end
  end
  local function inDeck(deck)
    local out = {}
    for _, card in ipairs(cards:inDeck(deck)) do
      local ok
      if card.set and kitSets[card.set] then
        ok = deck == "market" and (inKit[card.set] or kitMarket[card.id]) -- a kit's trade cards, when the kit is played
      else
        ok = not sets or not card.set or sets[card.set]
      end
      if ok then out[#out + 1] = card end
    end
    return out
  end
  for seat, player in ipairs(state.players) do
    local kit = kits[seat]
    local starters = inDeck("starter")
    if kit then
      -- a kit lists its cards (kit.starters, kit.dealt: card ids), or names
      -- its set, whose starter and dealt cards it then uses
      local function kitCards(deck, ids)
        local out = {}
        if ids then
          for _, id in ipairs(ids) do out[#out + 1] = cards:get(id) end
        else
          for _, card in ipairs(cards:inDeck(deck)) do
            if card.set == kit.set then out[#out + 1] = card end
          end
        end
        return out
      end
      starters = kitCards("starter", kit.starters)
      for _, card in ipairs(kitCards("dealt", kit.dealt)) do
        for _ = 1, card.copies do player.bases[#player.bases + 1] = State.newCard(state, card.id) end
      end
      for key, value in pairs(kit.stats or {}) do player.stats[key] = value end
      player.handSize = kit.handSize
      player.kit = kit.key
    end
    for _, card in ipairs(starters) do
      for _ = 1, card.copies do
        player.deck[#player.deck + 1] = State.newCard(state, card.id)
      end
    end
    -- the `starting` column: copies of a pile's card in every starting deck
    if not kit then
      for _, card in ipairs(cards.list) do
        if card.starting > 0 and not (card.set and kitSets[card.set]) and (not sets or not card.set or sets[card.set]) then
          for _ = 1, card.starting do player.deck[#player.deck + 1] = State.newCard(state, card.id) end
        end
      end
    end
    Util.shuffle(player.deck, random)
  end

  -- Objectives: each player gets rules.objectives.count at random, face down.
  local goals = {}
  for _, card in ipairs(inDeck("objective")) do
    for _ = 1, card.copies do goals[#goals + 1] = card.id end
  end
  if #goals > 0 and rules.objectives then
    Util.shuffle(goals, random)
    for _, player in ipairs(state.players) do
      for _ = 1, rules.objectives.count or 3 do
        if #goals > 0 then player.objectives[#player.objectives + 1] = State.newCard(state, table.remove(goals)) end
      end
    end
  end

  -- Cards dealt into play: each player gets rules.deal.count at random.
  local pool = {}
  for _, card in ipairs(inDeck("dealt")) do
    for _ = 1, card.copies do pool[#pool + 1] = card.id end
  end
  if #pool > 0 and rules.deal then
    Util.shuffle(pool, random)
    for _, player in ipairs(state.players) do
      for _ = 1, rules.deal.count or 1 do
        if #pool > 0 then player.bases[#player.bases + 1] = State.newCard(state, table.remove(pool)) end
      end
    end
  end

  for _, m in ipairs(State.rows(state)) do
    for _, card in ipairs(inDeck(m.key and ("market:" .. m.key) or "market")) do
      for _ = 1, card.copies do
        m.deck[#m.deck + 1] = State.newCard(state, card.id)
      end
    end
    Util.shuffle(m.deck, random)
  end

  local count = #state.players
  local function makePile(card)
    local pile = {}
    for _ = 1, Turn.pileSize(rules, card, count) do pile[#pile + 1] = State.newCard(state, card.id) end
    state.market.fixed[card.id] = pile
  end
  for _, card in ipairs(inDeck("fixed")) do makePile(card) end
  state.market.supply = Turn.chooseSupply(rules, inDeck("supply"), random, supplyChoice)
  for _, id in ipairs(state.market.supply) do makePile(cards:get(id)) end

  Turn.fillMarket(state)

  local first = math.min(rules.firstSeat or 1, count)
  state.turn.first = first -- a round ends when play comes back round to this seat
  for order = 1, count do
    local seat = (first + order - 2) % count + 1
    Turn.draw(state, seat, Turn.openingHandSize(opening or rules.openingHand, order, count, rules.handSize))
  end

  state.turn.active = first
  state.turn.number = 1
  state.started = true
end

-- How many cards a fixed or supply pile starts with: rules.pileSizes[id]
-- (a number, { [players] = n, otherwise = n }, or function(players)), else
-- the card's copies.
function Turn.pileSize(rules, card, players)
  local size = rules.pileSizes and rules.pileSizes[card.id]
  if type(size) == "function" then size = size(players) end
  if type(size) == "table" then size = size[players] or size.otherwise end
  return size or card.copies
end

-- The supply piles for a game (rules.supply), as card ids sorted by cost
-- then name. `choice` 0 or nil picks rules.supply.count (default 10) of the
-- `supply` cards at random; choice i uses rules.supply.presets[i].cards
-- (rules.supply.default names the preset used when the host hasn't chosen).
-- A preset's card that isn't in the game (its set is off) is left out.
function Turn.chooseSupply(rules, pool, random, choice)
  local opts = rules.supply or {}
  if choice == nil then choice = opts.default or 0 end
  local picked = {}
  local preset = choice > 0 and opts.presets and opts.presets[choice]
  local byId = {}
  for _, card in ipairs(pool) do byId[card.id] = card end
  if preset then
    for _, id in ipairs(preset.cards or {}) do
      if byId[id] then picked[#picked + 1] = byId[id] end
    end
  else
    local list = {}
    for _, card in ipairs(pool) do list[#list + 1] = card end
    Util.shuffle(list, random)
    for i = 1, math.min(opts.count or 10, #list) do picked[i] = list[i] end
  end
  table.sort(picked, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)
  local ids = {}
  for i, card in ipairs(picked) do ids[i] = card.id end
  return ids
end

-- Draws n cards for a seat, reshuffling the discard pile into the deck when
-- the deck runs out. Returns the uids drawn (fewer than n if both are empty).
function Turn.draw(state, seat, n, random)
  local player = state.players[seat]
  local drawn = {}
  for _ = 1, n do
    if #player.deck == 0 then
      if #player.discard == 0 then break end
      Util.moveAll(player.discard, player.deck)
      Util.shuffle(player.deck, random)
    end
    local uid = table.remove(player.deck)
    player.hand[#player.hand + 1] = uid
    drawn[#drawn + 1] = uid
  end
  return drawn
end

-- Fills every market's empty slots from the top of its own deck. Returns
-- the slots that were filled: { { market = m, slot = i }, ... }.
function Turn.fillMarket(state)
  local filled = {}
  for _, m in ipairs(State.rows(state)) do
    local row = m.row
    for i = 1, #row do
      if row[i] == State.EMPTY and #m.deck > 0 then
        row[i] = table.remove(m.deck)
        filled[#filled + 1] = { market = m, slot = i }
      end
    end
  end
  return filled
end

function Turn.isPersistent(rules, card)
  local def = rules.cardTypes and rules.cardTypes[card.type]
  return def ~= nil and def.persistent == true and rules.mechanics.persistent ~= false
end

-- The seat after `seat` in turn order, skipping players who are out.
function Turn.nextSeat(state, seat)
  local count = #state.players
  for step = 1, count do
    local next = (seat + step - 1) % count + 1
    if not state.players[next].out then return next end
  end
  return seat
end

-- End-of-turn cleanup for the active seat: played cards and hand go to the
-- discard pile (persistent cards stay in play), resource pools reset, a new
-- hand is drawn, and play passes to the next seat still in the game.
-- rules.turn.keepHand keeps unplayed cards in the hand; rules.turn.drawUpTo
-- draws up to the hand size instead of a whole new hand.
function Turn.endTurn(state, rules, random)
  local seat = state.turn.active
  local player = state.players[seat]
  local t = rules.turn or {}
  Util.moveAll(player.play, player.discard)
  if not t.keepHand then Util.moveAll(player.hand, player.discard) end
  State.resetResources(player, rules)
  local size = player.handSize or rules.handSize
  Turn.draw(state, seat, t.drawUpTo and math.max(0, size - #player.hand) or size, random)

  state.turn.active = Turn.nextSeat(state, seat)
  state.turn.number = state.turn.number + 1
  return seat
end

return Turn
