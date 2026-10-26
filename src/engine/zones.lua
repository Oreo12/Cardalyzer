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

-- Seats sit on the two long sides of the table, facing the market in the
-- centre, so a rectangular table fits four. Seat 1 is at the bottom (-z)
-- left, and play goes along the bottom from left to right, then back along
-- the top, so each player's neighbours are next in turn order. Two seats on
-- a side sit the same distance either side of the market; a seat alone on
-- its side is in line with it.
local function seatFrame(seat, count, distance, spread)
  local bottom = math.ceil(count / 2)
  local top = seat > bottom
  local n = top and count - bottom or bottom
  local i = top and seat - bottom or seat
  local along = (i - (n + 1) / 2) * spread
  local s = top and -1 or 1
  return {
    origin = { x = s * along, z = -s * distance },
    forward = { x = 0, z = s }, -- toward the table centre
    right = { x = s, z = 0 },
    yaw = top and 180 or 0,
  }
end

-- Each seat's areas, in that seat's frame: `along` its row (to the
-- player's right), `out` toward the table centre, `width` along and `depth`
-- out, all in table units. rules.layout.areas changes any of these
-- ({ play = { out = 3 } }), or turns an area off with false: its cards are
-- then not shown on the table. With bases off, cards that stay in play sit
-- in the play area instead.
function Zones.seatAreas(rules)
  local gap = layoutValue(rules, "cardSpacing")
  local areas = {
    play = { along = 0, out = 2, width = gap * 6, depth = 4 },
    bases = { along = gap * 4.5, out = 2, width = gap * 2.5, depth = 4 },
    deck = { along = -gap * 2, out = -3, width = 2.6, depth = 3.6 },
    discard = { along = gap * 2, out = -3, width = 2.6, depth = 3.6 },
    hand = { along = 0, out = -9, width = gap * 7, depth = 4 },
  }
  local over = rules.layout and rules.layout.areas or {}
  for name, area in pairs(areas) do
    local o = over[name]
    if o == false then
      area.hidden = true
    elseif type(o) == "table" then
      for k, v in pairs(o) do area[k] = v end
    end
  end
  -- the hand and the deck and discard pile can't be turned off
  areas.hand.hidden, areas.deck.hidden, areas.discard.hidden = nil, nil, nil
  return areas
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
    forward = { frame.forward.x, frame.forward.z }, -- toward the table centre
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
  local areas = Zones.seatAreas(rules)
  local function area(f, name, height, ownYaw)
    local a = areas[name]
    local s = spot(f, name == "hand" and y + 2 or y, a.along, a.out, ownYaw or yaw, { a.width, height, a.depth })
    s.hidden = a.hidden
    return s
  end
  for seat = 1, count do
    local f = seatFrame(seat, count, distance, spread)
    result.seats[seat] = {
      play = area(f, "play", 3),
      bases = area(f, "bases", 3),
      deck = area(f, "deck", 3),
      discard = area(f, "discard", 3),
      -- A hand zone faces its seat at the seat's own yaw. TTS keeps a card's
      -- yaw relative to the hand zone, so cards dealt into it still use the
      -- card yaw (as in a stock TTS table: hand zone 0, held cards 180).
      hand = area(f, "hand", 5, 0),
    }
    local hand = result.seats[seat].hand
    hand.cardRotation = { 0, (yaw + f.yaw) % 360, 0 }
    -- Where cards flying to this hand stop: just in front of the hand zone,
    -- so the moving card is never caught by the zone itself.
    hand.landing = { hand.position[1] + f.forward.x * 3.5, y, hand.position[3] + f.forward.z * 3.5 }
  end

  -- The market runs along the x axis through the table centre, read by
  -- seat 1. rules.layout.areas.market = { x, z } moves all of it;
  -- marketDeck and scrap take { along, out } from that centre, or false to
  -- leave them off the table. A market with rowSize 0 has no row and no deck.
  local over = rules.layout and rules.layout.areas or {}
  local mo = type(over.market) == "table" and over.market or {}
  local centre = seatFrame(1, 1, 0, 0)
  centre.origin = { x = mo.x or 0, z = mo.z or 0 }
  local n = rules.market.rowSize or 0
  local first = -(n - 1) / 2 * gap
  for i = 1, n do
    result.market.row[i] = spot(centre, y, first + (i - 1) * gap, 0, yaw)
  end
  local function piece(name, along)
    local o = over[name]
    local s = spot(centre, y, type(o) == "table" and o.along or along, type(o) == "table" and o.out or 0, yaw)
    s.hidden = o == false or nil
    return s
  end
  result.market.deck = piece("marketDeck", first - gap * 1.5)
  if n == 0 then result.market.deck.hidden = true end
  local x = first + (n - 1) * gap + gap * 1.5
  if n == 0 then x = 0 end
  for _, id in ipairs(fixedIds or {}) do
    result.market.fixed[id] = spot(centre, y, x, 0, yaw)
    x = x + gap
  end
  result.market.scrap = piece("scrap", x + gap * 0.5)
  result.market.area = spot(centre, y, 0, 0, yaw, { n * gap + 1, 3, 4.5 })
  return result
end

-- How thick the play mats are (rules.layout.mats), so outlines lie on top.
function Zones.matThickness(rules)
  local mats = rules.layout and rules.layout.mats
  if not mats then return 0 end
  return mats.thickness or 0.1
end

-- Is table point (x, z) inside a sized spot (plus `margin`)? Height is
-- ignored: a card being dropped is still lifted above the table.
function Zones.contains(s, x, z, margin)
  if not s.size then return false end
  local dx, dz = x - s.position[1], z - s.position[3]
  local along = dx * s.right[1] + dz * s.right[2]
  local out = dx * s.forward[1] + dz * s.forward[2]
  margin = margin or 0
  return math.abs(along) <= s.size[1] / 2 + margin and math.abs(out) <= s.size[3] / 2 + margin
end

-- The seat whose play or bases area holds table point (x, z), if any.
function Zones.playSeatAt(layout, x, z)
  for seat, s in ipairs(layout.seats) do
    if Zones.contains(s.play, x, z, 0.5) or (not s.bases.hidden and Zones.contains(s.bases, x, z, 0.5)) then return seat end
  end
  return nil
end

-- Is table point (x, z) on the scrap pile (a card's footprint, generously)?
function Zones.onScrap(layout, x, z)
  local s = layout.market.scrap
  if s.hidden then return false end
  return Zones.contains({ position = s.position, right = s.right, forward = s.forward, size = { 4, 0, 5 } }, x, z, 0)
end

-- The four corners of a spot on the table (for outlines), `pad` wider all round.
-- A spot with no size is one card.
function Zones.corners(s, y, pad, cardSize)
  local w = (s.size and s.size[1] or cardSize[1]) / 2 + pad
  local d = (s.size and s.size[3] or cardSize[2]) / 2 + pad
  local r, f, p = s.right, s.forward, s.position
  local out = {}
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
    out[#out + 1] = { p[1] + r[1] * w * c[1] + f[1] * d * c[2], y, p[3] + r[2] * w * c[1] + f[2] * d * c[2] }
  end
  return out
end

-- TTS seat colours as RGB, for outlining each seat's areas.
Zones.SEAT_RGB = {
  White = { 1, 1, 1 }, Brown = { 0.63, 0.4, 0.23 }, Red = { 0.9, 0.25, 0.25 }, Orange = { 0.96, 0.45, 0.11 },
  Yellow = { 0.9, 0.9, 0.17 }, Green = { 0.3, 0.78, 0.27 }, Teal = { 0.13, 0.69, 0.61 }, Blue = { 0.24, 0.59, 1 },
  Purple = { 0.69, 0.3, 0.94 }, Pink = { 0.96, 0.44, 0.81 }, Grey = { 0.5, 0.5, 0.5 }, Black = { 0.25, 0.25, 0.25 },
}
local GOLD = { 0.91, 0.72, 0.29 }

-- Outlines of every area on the table, as TTS vector lines: each seat's play
-- area, bases, deck and discard pile in its colour, and the market row,
-- market deck, fixed piles and scrap pile in gold. rules.outlines = false
-- turns them off; a table changes them:
--   { seat = "#FFFFFF" (one colour for every seat; default its own colour),
--     market = "#E8B84A", thickness = 1 (times the usual),
--     hide = { deck = true, slots = true } }
-- Area names for `hide`: play, bases, deck, discard, row (round the whole
-- market row), slots (each card in it), marketDeck, fixed, scrap.
function Zones.outlines(rules, layout, colors)
  if rules.outlines == false then return {} end
  local opts = type(rules.outlines) == "table" and rules.outlines or {}
  local hide = opts.hide or {}
  local Util = require("engine.util")
  local marketRgb = Util.color(opts.market) or GOLD
  local seatRgb = Util.color(opts.seat)
  local k = opts.thickness or 1
  local y = layoutValue(rules, "surfaceY") + 0.02 + Zones.matThickness(rules)
  local scale = layoutValue(rules, "cardScale")
  local card = { 2.4 * scale, 3.4 * scale }
  local lines = {}
  local function box(name, s, rgb, thickness, pad)
    if s.hidden or hide[name] then return end
    lines[#lines + 1] = {
      points = Zones.corners(s, y, pad or 0.15, card),
      color = rgb, thickness = (thickness or 0.08) * k, loop = true, square = true,
    }
  end
  for seat, s in ipairs(layout.seats) do
    local rgb = seatRgb or Zones.SEAT_RGB[colors[seat]] or GOLD
    box("play", s.play, rgb, 0.1, 0)
    box("bases", s.bases, rgb, 0.1, 0)
    box("deck", s.deck, rgb, 0.08, 0)
    box("discard", s.discard, rgb, 0.08, 0)
  end
  local m = layout.market
  if #m.row > 0 then box("row", m.area, marketRgb, 0.12, 0) end
  for _, slot in ipairs(m.row) do box("slots", slot, marketRgb) end
  box("marketDeck", m.deck, marketRgb)
  for _, s in pairs(m.fixed) do box("fixed", s, marketRgb) end
  box("scrap", m.scrap, marketRgb)
  return lines
end

-- Keys of the scripting zones Zones.build creates, with their layout spot.
function Zones.zoneSpots(layout)
  local list = {}
  for seat, s in ipairs(layout.seats) do
    for _, name in ipairs({ "play", "bases", "deck", "discard" }) do
      if not s[name].hidden then list[#list + 1] = { key = seat .. "." .. name, spot = s[name] } end
    end
  end
  if #layout.market.row > 0 then list[#list + 1] = { key = "market.row", spot = layout.market.area } end
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
-- saved in state.view.zones, moves each seat's hand zone into place, and
-- removes the zones and hand zones of seats no longer playing.
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

  -- Hand zones of seats in the rules that aren't playing are removed, so
  -- they can't overlap the hands of a smaller table.
  for i = #layout.seats + 1, #game.rules.seats do
    local color = game.rules.seats[i].color
    local hand = view.hands[color] and getObjectFromGUID(view.hands[color]) or findHand(color)
    if hand then hand.destruct() end
    view.hands[color] = nil
  end

  local colors = {}
  for seat, p in ipairs(game.state.players) do colors[seat] = p.color end
  Global.setVectorLines(Zones.outlines(game.rules, layout, colors))
  require("engine.mats").build(game)
end

-- Returns the zone key ("1.play", "market.row") for a scripting zone GUID.
function Zones.keyOf(game, guid)
  for key, g in pairs(game.state.view.zones) do
    if g == guid then return key end
  end
  return nil
end

return Zones
