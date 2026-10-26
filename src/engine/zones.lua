-- Table layout and scripting zones.
--
-- Zones.layout is pure math: it turns rules.layout into world positions for
-- every pile, so it can be tested outside TTS. Zones.build spawns (or reuses)
-- the TTS scripting zones and hand zones at those positions.
local Zones = {}

local DEFAULT_LAYOUT = {
  surfaceY = 1.1,      -- table surface height; piles spawn just above it
  seatDistance = 10,   -- from table centre to a seat's play row
  cardSpacing = 2.8,   -- gap between cards in a row
  cardScale = 1.0,
  cardYaw = 180,       -- card yaw that reads upright for seat 1
}

local function layoutValue(rules, key)
  local layout = rules.layout or {}
  if layout[key] ~= nil then return layout[key] end
  return DEFAULT_LAYOUT[key]
end

-- How many seats a new game deals for: rules.players.default, else its min,
-- else every seat in rules.seats.
function Zones.defaultCount(rules)
  local players = rules.players or {}
  return math.min(players.default or players.min or #rules.seats, #rules.seats)
end

-- Seats sit on the two long sides of the table, facing the centre, so a
-- rectangular table fits four. Seat 1 is at the bottom (-z) left, and play
-- goes along the bottom from left to right, then back along the top, so each
-- player's neighbours are next in turn order. Two seats face each other
-- across the centre.
local function seatFrame(seat, count, distance, spread, shift)
  local bottom = math.ceil(count / 2)
  local top = seat > bottom
  local n = top and count - bottom or bottom
  local i = top and seat - bottom or seat
  -- A seat's piles reach further to its right (bases) than its left, so a
  -- shared side is shifted to keep the pair centred on the table.
  local along = (i - (n + 1) / 2) * spread - (n > 1 and shift or 0)
  local s = top and -1 or 1
  return {
    origin = { x = s * along, z = -s * distance },
    forward = { x = 0, z = s }, -- toward the table centre
    right = { x = s, z = 0 },
    yaw = top and 180 or 0,
  }
end

local function spot(frame, y, along, out, yaw, size)
  return {
    position = {
      frame.origin.x + frame.right.x * along + frame.forward.x * out,
      y,
      frame.origin.z + frame.right.z * along + frame.forward.z * out,
    },
    rotation = { 0, (yaw + frame.yaw) % 360, 0 },
    right = { frame.right.x, frame.right.z }, -- direction rows of cards run in
    size = size,
  }
end

-- Returns { seats = { [seat] = { play, bases, deck, discard, hand } },
--           market = { deck, row = {...}, fixed = { [id] = spot }, scrap, area } }
-- `fixedIds` lists the fixed-pile card ids in display order; `count` is how
-- many seats are playing (default Zones.defaultCount).
function Zones.layout(rules, fixedIds, count)
  local y = layoutValue(rules, "surfaceY") + 0.4
  local gap = layoutValue(rules, "cardSpacing")
  local yaw = layoutValue(rules, "cardYaw")
  local distance = layoutValue(rules, "seatDistance")
  -- Seats sharing a side are this far apart (piles span -3.5 to +5.75 gaps).
  local spread = (rules.layout and rules.layout.seatSpread) or gap * 10
  count = count or Zones.defaultCount(rules)

  local result = { seats = {}, market = { row = {}, fixed = {} } }
  for seat = 1, count do
    local f = seatFrame(seat, count, distance, spread, gap * 1.125)
    result.seats[seat] = {
      play = spot(f, y, 0, 2, yaw, { gap * 6, 3, 4 }),
      bases = spot(f, y, gap * 4.5, 2, yaw, { gap * 2.5, 3, 4 }),
      deck = spot(f, y, -gap * 2, -3, yaw, { 2.6, 3, 3.6 }),
      discard = spot(f, y, gap * 2, -3, yaw, { 2.6, 3, 3.6 }),
      -- A hand zone faces its seat at the seat's own yaw. TTS keeps a card's
      -- yaw relative to the hand zone, so cards dealt into it still use the
      -- card yaw (as in a stock TTS table: hand zone 0, held cards 180).
      hand = spot(f, y + 2, 0, -9, 0, { gap * 7, 5, 4 }),
    }
    result.seats[seat].hand.cardRotation = { 0, (yaw + f.yaw) % 360, 0 }
  end

  -- The market runs along the x axis through the table centre, read by seat 1.
  local centre = seatFrame(1, 1, 0, 0, 0)
  local n = rules.market.rowSize
  local first = -(n - 1) / 2 * gap
  for i = 1, n do
    result.market.row[i] = spot(centre, y, first + (i - 1) * gap, 0, yaw)
  end
  result.market.deck = spot(centre, y, first - gap * 1.5, 0, yaw)
  local x = first + (n - 1) * gap + gap * 1.5
  for _, id in ipairs(fixedIds or {}) do
    result.market.fixed[id] = spot(centre, y, x, 0, yaw)
    x = x + gap
  end
  result.market.scrap = spot(centre, y, x + gap * 0.5, 0, yaw)
  result.market.area = spot(centre, y, 0, 0, yaw, { n * gap + 1, 3, 4.5 })
  return result
end

-- Keys of the scripting zones Zones.build creates, with their layout spot.
function Zones.zoneSpots(layout)
  local list = {}
  for seat, s in ipairs(layout.seats) do
    for _, name in ipairs({ "play", "bases", "deck", "discard" }) do
      list[#list + 1] = { key = seat .. "." .. name, spot = s[name] }
    end
  end
  list[#list + 1] = { key = "market.row", spot = layout.market.area }
  return list
end

---------------------------------------------------------------------------
-- TTS side. Everything below calls the TTS API.
---------------------------------------------------------------------------

local function findHand(color)
  for _, obj in ipairs(getObjects()) do
    if obj.type == "Hand" and obj.getValue() == color then return obj end
  end
  return nil
end

local function place(obj, s)
  obj.setPosition(s.position)
  obj.setRotation(s.rotation)
  if s.size then obj.setScale(s.size) end
end

-- Spawns any scripting zone that is missing, reuses the ones whose GUIDs are
-- saved in state.view.zones, removes those of seats no longer playing, and
-- moves each seat's hand zone into place.
function Zones.build(game, layout)
  local view = game.state.view
  local wanted = {}
  for _, entry in ipairs(Zones.zoneSpots(layout)) do wanted[entry.key] = true end
  for key, guid in pairs(view.zones) do
    if not wanted[key] then
      local obj = getObjectFromGUID(guid)
      if obj then obj.destruct() end
      view.zones[key] = nil
    end
  end
  for _, entry in ipairs(Zones.zoneSpots(layout)) do
    local obj = view.zones[entry.key] and getObjectFromGUID(view.zones[entry.key])
    if obj then
      place(obj, entry.spot)
    else
      obj = spawnObject({
        type = "ScriptingTrigger",
        position = entry.spot.position,
        rotation = entry.spot.rotation,
        scale = entry.spot.size,
      })
      obj.setName("cz:" .. entry.key)
      obj.addTag("cz_zone")
      view.zones[entry.key] = obj.getGUID()
    end
  end

  for seat, s in ipairs(layout.seats) do
    local color = game.state.players[seat].color
    local hand = view.hands[color] and getObjectFromGUID(view.hands[color]) or findHand(color)
    if hand then
      place(hand, s.hand)
    else
      hand = spawnObject({
        type = "HandTrigger",
        position = s.hand.position,
        rotation = s.hand.rotation,
        scale = s.hand.size,
      })
      hand.setValue(color)
    end
    view.hands[color] = hand.getGUID()
  end
end

-- Returns the zone key ("1.play", "market.row") for a scripting zone GUID.
function Zones.keyOf(game, guid)
  for key, g in pairs(game.state.view.zones) do
    if g == guid then return key end
  end
  return nil
end

return Zones
