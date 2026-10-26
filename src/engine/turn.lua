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
function Turn.setup(state, rules, cards, random, opening, sets)
  local function inDeck(deck)
    local out = {}
    for _, card in ipairs(cards:inDeck(deck)) do
      if not sets or not card.set or sets[card.set] then out[#out + 1] = card end
    end
    return out
  end
  for _, player in ipairs(state.players) do
    for _, card in ipairs(inDeck("starter")) do
      for _ = 1, card.copies do
        player.deck[#player.deck + 1] = State.newCard(state, card.id)
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

  for _, card in ipairs(inDeck("market")) do
    for _ = 1, card.copies do
      state.market.deck[#state.market.deck + 1] = State.newCard(state, card.id)
    end
  end
  Util.shuffle(state.market.deck, random)

  for _, card in ipairs(inDeck("fixed")) do
    local pile = {}
    for _ = 1, card.copies do pile[#pile + 1] = State.newCard(state, card.id) end
    state.market.fixed[card.id] = pile
  end

  Turn.fillMarket(state)

  local count = #state.players
  local first = math.min(rules.firstSeat or 1, count)
  for order = 1, count do
    local seat = (first + order - 2) % count + 1
    Turn.draw(state, seat, Turn.openingHandSize(opening or rules.openingHand, order, count, rules.handSize))
  end

  state.turn.active = first
  state.turn.number = 1
  state.started = true
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

-- Fills empty market slots from the top of the market deck. Returns the
-- indexes of the slots that were filled.
function Turn.fillMarket(state)
  local filled = {}
  local row = state.market.row
  for i = 1, #row do
    if row[i] == State.EMPTY and #state.market.deck > 0 then
      row[i] = table.remove(state.market.deck)
      filled[#filled + 1] = i
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
function Turn.endTurn(state, rules, random)
  local seat = state.turn.active
  local player = state.players[seat]
  Util.moveAll(player.play, player.discard)
  Util.moveAll(player.hand, player.discard)
  State.resetResources(player, rules)
  Turn.draw(state, seat, rules.handSize, random)

  state.turn.active = Turn.nextSeat(state, seat)
  state.turn.number = state.turn.number + 1
  return seat
end

return Turn
