-- Turn loop over game state: setup, drawing (with reshuffle), market refill,
-- and end-of-turn cleanup. Pure state changes; the board re-renders after.
local Util = require("engine.util")
local State = require("engine.state")

local Turn = {}

local function openingHandSize(rules, order)
  local opening = rules.openingHand or rules.handSize
  if type(opening) == "table" then
    return opening[order] or opening[#opening]
  end
  return opening
end

function Turn.setup(state, rules, cards, random)
  for _, player in ipairs(state.players) do
    for _, card in ipairs(cards:inDeck("starter")) do
      for _ = 1, card.copies do
        player.deck[#player.deck + 1] = State.newCard(state, card.id)
      end
    end
    Util.shuffle(player.deck, random)
  end

  for _, card in ipairs(cards:inDeck("market")) do
    for _ = 1, card.copies do
      state.market.deck[#state.market.deck + 1] = State.newCard(state, card.id)
    end
  end
  Util.shuffle(state.market.deck, random)

  for _, card in ipairs(cards:inDeck("fixed")) do
    local pile = {}
    for _ = 1, card.copies do pile[#pile + 1] = State.newCard(state, card.id) end
    state.market.fixed[card.id] = pile
  end

  Turn.fillMarket(state)

  local first = rules.firstSeat or 1
  local count = #state.players
  for order = 1, count do
    local seat = (first + order - 2) % count + 1
    Turn.draw(state, seat, openingHandSize(rules, order))
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

-- End-of-turn cleanup for the active seat: played cards and hand go to the
-- discard pile (persistent cards stay in play), resource pools reset, a new
-- hand is drawn, and play passes to the next seat.
function Turn.endTurn(state, rules, random)
  local seat = state.turn.active
  local player = state.players[seat]
  Util.moveAll(player.play, player.discard)
  Util.moveAll(player.hand, player.discard)
  State.resetResources(player, rules)
  Turn.draw(state, seat, rules.handSize, random)

  state.turn.active = seat % #state.players + 1
  state.turn.number = state.turn.number + 1
  return seat
end

return Turn
