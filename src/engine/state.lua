-- Game state lives in plain Lua tables so it can be saved with onSave and
-- restored on load. Physical objects on the table are only a view of it.
--
-- Every physical card is an instance with a uid ("c12"); state.cards maps the
-- uid to its card id. Piles are lists of uids, and the LAST element is the top.
local State = {}

State.VERSION = 1
State.EMPTY = "" -- marks an empty market slot (JSON can't hold holes in arrays)

function State.new(rules)
  local state = {
    version = State.VERSION,
    started = false,
    nextUid = 1,
    cards = {},
    players = {},
    market = { deck = {}, row = {}, fixed = {}, scrap = {} },
    turn = { active = 1, number = 1 },
    view = { piles = {}, zones = {}, hands = {} }, -- GUIDs of spawned objects, owned by board/zones
  }
  for seat, def in ipairs(rules.seats) do
    local player = {
      seat = seat,
      color = def.color,
      name = def.name or def.color,
      deck = {}, hand = {}, discard = {}, play = {}, bases = {},
      resources = {}, stats = {}, pending = {},
    }
    State.resetResources(player, rules)
    for _, stat in ipairs(rules.stats or {}) do
      player.stats[stat.key] = stat.start or 0
    end
    state.players[seat] = player
  end
  for i = 1, rules.market.rowSize do state.market.row[i] = State.EMPTY end
  return state
end

function State.resetResources(player, rules)
  for _, res in ipairs(rules.resources or {}) do
    player.resources[res.key] = 0
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
