-- Game state lives in plain Lua tables so it can be saved with onSave and
-- restored on load. Physical objects on the table are only a view of it.
--
-- Every physical card is an instance with a uid ("c12"); state.cards maps the
-- uid to its card id. Piles are lists of uids, and the LAST element is the top.
local State = {}

State.VERSION = 2
State.EMPTY = "" -- marks an empty market slot (JSON can't hold holes in arrays)

-- `count` seats play: the first `count` entries of rules.seats (default all).
function State.new(rules, count)
  local state = {
    version = State.VERSION,
    started = false,
    nextUid = 1,
    cards = {},
    players = {},
    market = { deck = {}, row = {}, fixed = {}, scrap = {} },
    turn = { active = 1, number = 1, allyFired = {} },
    winner = nil, -- seat number once someone has won
    view = { piles = {}, sig = {}, zones = {}, hands = {} }, -- spawned objects, owned by board/zones
  }
  for seat = 1, count or #rules.seats do
    local def = rules.seats[seat]
    local player = {
      seat = seat,
      color = def.color,
      name = def.name or def.color,
      deck = {}, hand = {}, discard = {}, play = {}, bases = {},
      objectives = {}, completed = {}, -- secret goals still to do, and done (see Actions.completeObjective)
      resources = {}, stats = {},
      prompts = {}, -- choices waiting on this player, answered in order (engine/actions.lua)
      owed = {},    -- things owed at the start of their next turn, e.g. { discard = 1 }
      flags = {},   -- this turn only, e.g. flags.buyToTop for "put the next card you buy on top"
      out = false,  -- knocked out (see Actions.checkWin); turns skip them
    }
    State.resetResources(player, rules)
    for _, stat in ipairs(rules.stats or {}) do
      player.stats[stat.key] = stat.start or 0
    end
    state.players[seat] = player
  end
  for i = 1, rules.market.rowSize do state.market.row[i] = State.EMPTY end
  -- Extra markets (rules.markets): each its own deck and row. The main
  -- market keeps the fixed piles and the scrap pile.
  state.markets = {}
  for _, m in ipairs(rules.markets or {}) do
    local extra = { key = m.key, deck = {}, row = {} }
    for i = 1, m.rowSize or 0 do extra.row[i] = State.EMPTY end
    state.markets[#state.markets + 1] = extra
  end
  return state
end

-- Every market with a row, the main one first: { market, extra, ... }.
function State.rows(state)
  local out = { state.market }
  for _, m in ipairs(state.markets or {}) do out[#out + 1] = m end
  return out
end

-- The market whose row holds uid, and its slot.
function State.rowOf(state, uid)
  for _, m in ipairs(State.rows(state)) do
    for i, u in ipairs(m.row) do
      if u == uid then return m, i end
    end
  end
  return nil
end

-- Each resource back to its `start` (0 unless given) for the player's next
-- turn, except those rules.turn.keepResources carries over (true: all, or a
-- list of keys).
function State.resetResources(player, rules)
  local keep = rules.turn and rules.turn.keepResources
  for _, res in ipairs(rules.resources or {}) do
    local kept = keep == true
    if type(keep) == "table" then
      for _, k in ipairs(keep) do if k == res.key then kept = true end end
    end
    if not kept or player.resources[res.key] == nil then player.resources[res.key] = res.start or 0 end
  end
end

function State.newCard(state, id)
  local uid = "c" .. state.nextUid
  state.nextUid = state.nextUid + 1
  state.cards[uid] = id
  return uid
end

function State.cardId(state, uid)
  return state.cards[uid]
end

return State
