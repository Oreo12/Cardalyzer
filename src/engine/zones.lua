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

-- A seat's frame from where it sits and which way it faces: yaw 0 faces +z
-- (seat 1 at the bottom of the table), and TTS turns clockwise seen from
-- above, so yaw 90 faces +x.
local function frameAt(x, z, yaw)
  local r = math.rad(yaw)
  local function tidy(v) return math.floor(v * 1e6 + 0.5) / 1e6 end
  return {
    origin = { x = x, z = z },
    forward = { x = tidy(math.sin(r)), z = tidy(math.cos(r)) }, -- toward the table centre
    right = { x = tidy(math.cos(r)), z = tidy(-math.sin(r)) },
    yaw = yaw % 360,
  }
end
Zones.frameAt = frameAt

-- Where each seat sits: rules.layout.seating.
--   "sides" (the default): the two long sides of the table, facing the
--     market in the centre, so a rectangular table fits four. Seat 1 is at
--     the bottom (-z) left, and play goes along the bottom from left to
--     right, then back along the top, so each player's neighbours are next
--     in turn order. Two seats on a side sit the same distance either side
--     of the market; a seat alone on its side is in line with it.
--   "around": evenly round the market, seat 1 at the bottom and the rest
--     going clockwise, on a circle seatDistance away (20 unless set), or an
--     oval: layout.seatRadius = { x = 30, z = 18 }.
--   "oneSide": every seat side by side along the bottom, seatSpread apart.
--   A function(seat, count, rules) returning { x, z, yaw }, or a table by
--     player count: seating = { [2] = { {x=0, z=-10, yaw=0}, {x=0, z=10, yaw=180} }, ... }
--     (counts it doesn't list fall back to "sides").
local function seatFrame(seat, count, distance, spread, rules, grow)
  grow = grow or 0
  local seating = rules and rules.layout and rules.layout.seating or "sides"
  local own = nil
  if type(seating) == "function" then
    own = seating(seat, count, rules)
  elseif type(seating) == "table" then
    own = seating[count] and seating[count][seat]
  end
  if own then return frameAt(own.x or 0, own.z or 0, own.yaw or 0) end
  if seating == "around" then
    local yaw = (seat - 1) * 360 / count
    -- side seats need to clear the market row, so the circle is wider than
    -- the long sides' distance unless the rules give one
    local d = (rules.layout.seatDistance or 20) + grow
    local radius = rules.layout.seatRadius or {}
    local r = math.rad(yaw)
    return frameAt(-math.sin(r) * (radius.x or d), -math.cos(r) * (radius.z or d), yaw)
  end
  if seating == "oneSide" then
    return frameAt((seat - (count + 1) / 2) * spread, -distance, 0)
  end
  local bottom = math.ceil(count / 2)
  local top = seat > bottom
  local n = top and count - bottom or bottom
  local i = top and seat - bottom or seat
  local along = (i - (n + 1) / 2) * spread
  local s = top and -1 or 1
  return frameAt(s * along, -s * distance, top and 180 or 0)
end

-- Each seat's areas, in that seat's frame: `along` its row (to the
-- player's right), `out` toward the table centre, `width` along and `depth`
-- out, all in table units. rules.layout.areas changes any of these
-- ({ play = { out = 3 } }), or turns an area off with false: its cards are
-- then not shown on the table. With bases off, cards that stay in play sit
-- in the play area instead. `column = true` lays the play or bases area's
-- cards in a column down the area instead of a row across it.
function Zones.seatAreas(rules)
  local gap = layoutValue(rules, "cardSpacing")
  local areas = {
    play = { along = 0, out = 2, width = gap * 6, depth = 4 },
    bases = { along = gap * 4.5, out = 2, width = gap * 2.5, depth = 4 },
    deck = { along = -gap * 2, out = -3, width = 2.6, depth = 3.6 },
    discard = { along = gap * 2, out = -3, width = 2.6, depth = 3.6 },
    hand = { along = 0, out = -9, width = gap * 7, depth = 4 },
    -- objectives (rules.objectives) lie face up between the deck and
    -- discard pile, hidden from the other players until completed
    objectives = { along = 0, out = -3, width = gap * 3, depth = 4 },
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
  -- the rules' set-aside areas, by key, as given (Zones.layout places them)
  areas.extra = {}
  for _, a in ipairs(rules.areas or {}) do areas.extra[a.key] = over[a.key] end
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
-- `facing` is the seat the market faces (rules.market.turnsWithPlayer: the
-- player whose turn it is); default seat 1.
-- The fixed piles sit in one line to the right of the row, or, with
-- rules.layout.areas.fixed = { columns = n }, in rows of up to n piles
-- (centred, when there's no market row); `breaks` ({ [i] = true }) starts a
-- new row at pile i (the supply after the fixed piles).
function Zones.layout(rules, fixedIds, count, facing, breaks)
  local y = layoutValue(rules, "surfaceY") + 0.4
  local gap = layoutValue(rules, "cardSpacing")
  local yaw = layoutValue(rules, "cardYaw")
  local distance = layoutValue(rules, "seatDistance")
  -- Seats sharing a side are this far apart (piles span -3.5 to +5.75 gaps).
  local spread = (rules.layout and rules.layout.seatSpread) or gap * 10
  count = count or Zones.defaultCount(rules)
  -- Extra markets (rules.markets) stack their rows beside the main one,
  -- `pitch` apart, and the seats move back to make room.
  local extras = rules.markets or {}
  local pitch = 3.4 * layoutValue(rules, "cardScale") + 1.2
  local over = rules.layout and rules.layout.areas or {}
  local columns = type(over.fixed) == "table" and over.fixed.columns
  local pileRows, line = {}, {}
  for i, id in ipairs(fixedIds or {}) do
    if columns and #line > 0 and (#line >= columns or (breaks and breaks[i])) then
      pileRows[#pileRows + 1] = line
      line = {}
    end
    line[#line + 1] = id
  end
  pileRows[#pileRows + 1] = line
  -- lanes: the market row (with the first row of piles), further rows of
  -- piles, then the extra markets, `pitch` apart and centred
  local lanes = #pileRows + #extras
  local grow = (lanes - 1) * pitch / 2
  distance = distance + grow
  local mainOut = -(lanes - 1) * pitch / 2

  local result = { seats = {}, market = { row = {}, fixed = {} }, markets = {} }
  local areas = Zones.seatAreas(rules)
  local function area(f, name, height, ownYaw)
    local a = areas[name]
    local s = spot(f, name == "hand" and y + 2 or y, a.along, a.out, ownYaw or yaw, { a.width, height, a.depth })
    s.hidden = a.hidden
    s.column = a.column
    s.wrap = a.wrap
    return s
  end
  for seat = 1, count do
    local f = seatFrame(seat, count, distance, spread, rules, grow)
    -- set-aside areas (rules.areas): beside the discard pile, one after
    -- another; rules.layout.areas[key] = { along, out } moves one, false hides it
    local setAside = {}
    for i, a in ipairs(rules.areas or {}) do
      local o = areas.extra[a.key]
      local spotOf = spot(f, y, type(o) == "table" and o.along or gap * (2 + 1.1 * i), type(o) == "table" and o.out or -3, yaw,
        { 2.6, 3, 3.6 })
      spotOf.hidden = o == false or a.shown == false or nil
      setAside[a.key] = spotOf
    end
    result.seats[seat] = {
      areas = setAside,
      play = area(f, "play", 3),
      bases = area(f, "bases", 3),
      deck = area(f, "deck", 3),
      discard = area(f, "discard", 3),
      objectives = area(f, "objectives", 3),
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
  local mo = type(over.market) == "table" and over.market or {}
  -- built in the facing seat's frame, so the whole market (row, piles and
  -- outlines) reads for that player
  local facingYaw = 0
  if facing and facing > 1 then facingYaw = seatFrame(facing, count, distance, spread, rules, grow).yaw end
  local centre = frameAt(mo.x or 0, mo.z or 0, facingYaw)
  local n = rules.market.rowSize or 0
  local first = -(n - 1) / 2 * gap
  for i = 1, n do
    result.market.row[i] = spot(centre, y, first + (i - 1) * gap, mainOut, yaw)
  end
  local function piece(name, along)
    local o = over[name]
    local s = spot(centre, y, type(o) == "table" and o.along or along, type(o) == "table" and o.out or mainOut, yaw)
    s.hidden = o == false or nil
    return s
  end
  result.market.deck = piece("marketDeck", first - gap * 1.5)
  if n == 0 then result.market.deck.hidden = true end
  local widest = 0
  for _, r in ipairs(pileRows) do widest = math.max(widest, #r) end
  local x0 = first + (n - 1) * gap + gap * 1.5
  if n == 0 then x0 = columns and -(widest - 1) / 2 * gap or 0 end
  -- rules.layout.areas[id] = { along, out } moves one fixed pile (by card id)
  for r, ids in ipairs(pileRows) do
    for j, id in ipairs(ids) do
      local o = type(over[id]) == "table" and over[id] or {}
      result.market.fixed[id] = spot(centre, y, o.along or x0 + (j - 1) * gap, o.out or mainOut + (r - 1) * pitch, yaw)
    end
  end
  result.market.scrap = piece("scrap", x0 + widest * gap + gap * 0.5)
  result.market.area = spot(centre, y, 0, mainOut, yaw, { n * gap + 1, 3, 4.5 })
  -- Each extra market: its row, with its deck to the left, the next row out.
  -- rules.layout.areas[key] = { along, out } moves one.
  for k, m in ipairs(extras) do
    local o = type(over[m.key]) == "table" and over[m.key] or {}
    local size = m.rowSize or 0
    local out = (o.out or (mainOut + (#pileRows - 1 + k) * pitch))
    local start = (o.along or 0) - (size - 1) / 2 * gap
    local row = {}
    for i = 1, size do row[i] = spot(centre, y, start + (i - 1) * gap, out, yaw) end
    result.markets[m.key] = {
      row = row,
      deck = spot(centre, y, start - gap * 1.5, out, yaw),
      area = spot(centre, y, o.along or 0, out, yaw, { size * gap + 1, 3, 4.5 }),
    }
  end
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
    for _, a in pairs(s.areas or {}) do box("areas", a, rgb, 0.08, 0) end
  end
  local m = layout.market
  if #m.row > 0 then box("row", m.area, marketRgb, 0.12, 0) end
  for _, slot in ipairs(m.row) do box("slots", slot, marketRgb) end
  box("marketDeck", m.deck, marketRgb)
  for _, s in pairs(m.fixed) do box("fixed", s, marketRgb) end
  box("scrap", m.scrap, marketRgb)
  for _, extra in pairs(layout.markets or {}) do
    if #extra.row > 0 then box("row", extra.area, marketRgb, 0.12, 0) end
    for _, slot in ipairs(extra.row) do box("slots", slot, marketRgb) end
    box("marketDeck", extra.deck, marketRgb)
  end
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
  for key, m in pairs(layout.markets or {}) do
    if #m.row > 0 then list[#list + 1] = { key = "market.row." .. key, spot = m.area } end
  end
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

  -- Every other hand zone (a table's own seats: TTS's custom table brings
  -- eight) is removed. Cardalyzer seats its players itself, and a stray hand
  -- zone overlapping a player's would take their cards and hide them.
  -- (the rules' own seats not playing were removed just above)
  local ours, removed = {}, {}
  for _, def in ipairs(game.rules.seats) do ours[def.color] = true end
  for _, obj in ipairs(getObjects()) do
    if obj.type == "Hand" and not ours[obj.getValue()] then
      removed[#removed + 1] = obj.getValue()
      obj.destruct()
    end
  end
  if #removed > 0 and game.notify then
    table.sort(removed)
    game:notify(require("engine.words").say(game.rules, "removedHands", { colors = table.concat(removed, ", ") }))
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
