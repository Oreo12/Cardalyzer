-- Play mats: pictures laid flat under the play areas (TTS custom tiles,
-- locked so they can't be knocked about), and the table's own picture.
--
--   rules.layout.mats = {
--     seat = { image = "https://…/mat.png" },     -- under each player's areas
--     market = { image = "https://…/market.png" }, -- under the market
--     extra = { { image = "https://…", x = 0, z = 20, width = 10, depth = 6, yaw = 0 } },
--     thickness = 0.1,
--   }
--   rules.layout.tableImage = "https://…/table.jpg"  -- a custom table's picture
--
-- A seat mat's `image` can also be a table by seat colour ({ White = "…",
-- Red = "…", default = "…" }). Seat and market mats cover their areas plus `margin` (default
-- 1) unless given `width` and `depth`; `along` and `out` move a seat mat in
-- its seat's frame (as in rules.layout.areas), `x` and `z` move the market
-- mat. A seat mat turns with its seat, so its picture reads upright for that
-- player. Only http(s) pictures are used: every player's TTS fetches them.
--
-- Mats players choose between (Settings → Mat and Mat style):
--
--   seat = {
--     styles = { "Emblem", "Battle" },          -- style names, in order
--     sets = {
--       { name = "Blue Guild", color = "Blue", images = { "https://…", "https://…" } }, -- one per style
--       …
--     },
--   }
--
-- Each player picks a set and a style for their own mat (saved with the
-- game). A set's `color` makes it that seat colour's mat to start with;
-- otherwise seats start on the sets in order.
local Mats = {}

local function webUrl(url)
  return type(url) == "string" and (url:match("^https://") or url:match("^http://")) and true or false
end

-- The box around a set of spots, in the frame of the first: centre along and
-- out, width and depth.
local function around(spots, origin, right, forward, margin)
  local lo_a, hi_a, lo_o, hi_o = nil, nil, nil, nil
  for _, s in ipairs(spots) do
    if not s.hidden then
      local dx, dz = s.position[1] - origin[1], s.position[3] - origin[2]
      local a = dx * right[1] + dz * right[2]
      local o = dx * forward[1] + dz * forward[2]
      local w = (s.size and s.size[1] or 2.6) / 2
      local d = (s.size and s.size[3] or 3.6) / 2
      lo_a = math.min(lo_a or math.huge, a - w)
      hi_a = math.max(hi_a or -math.huge, a + w)
      lo_o = math.min(lo_o or math.huge, o - d)
      hi_o = math.max(hi_o or -math.huge, o + d)
    end
  end
  if not lo_a then return nil end
  return (lo_a + hi_a) / 2, (lo_o + hi_o) / 2, hi_a - lo_a + 2 * margin, hi_o - lo_o + 2 * margin
end

-- The seat mat sets players choose between, or nil.
function Mats.sets(rules)
  local seat = rules.layout and rules.layout.mats and rules.layout.mats.seat
  return seat and type(seat.sets) == "table" and #seat.sets > 0 and seat or nil
end

-- A seat's mat choice: { set = i, style = j }, from `picks` (state.view.matPick)
-- or its starting one.
function Mats.pickOf(rules, color, seatIndex, picks)
  local seat = Mats.sets(rules)
  if not seat then return nil end
  local pick = picks and picks[color] or {}
  local set = pick.set
  if not set then
    for i, s in ipairs(seat.sets) do
      if s.color == color then set = i end
    end
  end
  set = seat.sets[set or 0] and set or ((seatIndex - 1) % #seat.sets + 1)
  local count = #(seat.sets[set].images or {})
  local style = pick.style and pick.style >= 1 and pick.style <= count and pick.style or 1
  return { set = set, style = style }
end

-- Every mat to lay: { key, image, position, yaw, width, depth }.
-- `colors` lists the seat colours in seat order; `picks` is state.view.matPick.
function Mats.spots(rules, layout, colors, picks)
  local mats = rules.layout and rules.layout.mats
  if not mats then return {} end
  -- TTS sets a spawned tile's bottom at this height: on the table.
  local y = (rules.layout and rules.layout.surfaceY) or 1.1
  local out = {}
  local seat = mats.seat
  if seat then
    for i, s in ipairs(layout.seats) do
      local image = type(seat.image) == "table" and (seat.image[colors[i]] or seat.image.default) or seat.image
      local pick = Mats.pickOf(rules, colors[i], i, picks)
      if pick then image = (seat.sets[pick.set].images or {})[pick.style] end
      -- the seat's frame, from its play area
      local origin = { s.play.position[1], s.play.position[3] }
      local right, forward = s.play.right, s.play.forward
      local a, o, w, d = around({ s.play, s.bases, s.deck, s.discard }, origin, right, forward, seat.margin or 1)
      if a and webUrl(image) then
        a, o = a + (seat.along or 0), o + (seat.out or 0)
        out[#out + 1] = {
          key = "seat." .. i, image = image,
          position = { origin[1] + right[1] * a + forward[1] * o, y, origin[2] + right[2] * a + forward[2] * o },
          yaw = s.play.rotation[2], -- turned like the seat's cards, so it reads upright for that player
          width = seat.width or w, depth = seat.depth or d,
        }
      end
    end
  end
  local market = mats.market
  if market and webUrl(market.image) then
    local m = layout.market
    local spots = { m.deck, m.scrap }
    for _, s in ipairs(m.row) do spots[#spots + 1] = s end
    for _, s in pairs(m.fixed) do spots[#spots + 1] = s end
    for _, extra in pairs(layout.markets or {}) do
      spots[#spots + 1] = extra.deck
      for _, s in ipairs(extra.row) do spots[#spots + 1] = s end
    end
    local a, o, w, d = around(spots, { 0, 0 }, { 1, 0 }, { 0, 1 }, market.margin or 1)
    if a then
      out[#out + 1] = { key = "market", image = market.image, position = { a + (market.x or 0), y, o + (market.z or 0) },
        yaw = market.yaw or 0, width = market.width or w, depth = market.depth or d }
    end
  end
  for i, e in ipairs(mats.extra or {}) do
    if webUrl(e.image) then
      out[#out + 1] = { key = "extra." .. i, image = e.image, position = { e.x or 0, y, e.z or 0 }, yaw = e.yaw or 0,
        width = e.width or 10, depth = e.depth or 10 }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

-- A TTS custom tile with no stretching is 2 by 2 at scale 1.
local TILE = 2

local function signature(m)
  return string.format("%s|%.2f|%.2f|%.2f|%.1f|%.2f|%.2f", m.image, m.position[1], m.position[2], m.position[3],
    m.yaw, m.width, m.depth)
end

-- Lays the mats for the current layout: keeps the ones already right,
-- replaces the ones that moved or changed picture, removes the rest. Also
-- sets the table's picture (a custom table only) when the rules give one.
function Mats.build(game)
  local view = game.state.view
  view.mats = view.mats or {}
  local colors = {}
  for i, p in ipairs(game.state.players) do colors[i] = p.color end
  local thickness = game.rules.layout and game.rules.layout.mats and game.rules.layout.mats.thickness or 0.1
  local wanted = {}
  for _, m in ipairs(Mats.spots(game.rules, game.layout, colors, view.matPick)) do
    wanted[m.key] = true
    local sig = signature(m)
    local have = view.mats[m.key]
    local obj = have and getObjectFromGUID(have.guid)
    if not (obj and have.sig == sig) then
      if obj then obj.destruct() end
      obj = spawnObjectData({
        data = {
          Name = "Custom_Tile",
          Nickname = "",
          Locked = true,
          Tags = { "cz_mat" },
          Transform = {
            posX = m.position[1], posY = m.position[2], posZ = m.position[3],
            rotX = 0, rotY = m.yaw, rotZ = 0,
            scaleX = m.width / TILE, scaleY = 1, scaleZ = m.depth / TILE,
          },
          CustomImage = {
            ImageURL = m.image, ImageSecondaryURL = "", ImageScalar = 1, WidthScale = 0,
            CustomTile = { Type = 0, Thickness = thickness, Stackable = false, Stretch = false },
          },
        },
        position = m.position,
        rotation = { 0, m.yaw, 0 },
      })
      view.mats[m.key] = { guid = obj.getGUID(), sig = sig }
    end
  end
  for key, have in pairs(view.mats) do
    if not wanted[key] then
      local obj = getObjectFromGUID(have.guid)
      if obj then obj.destruct() end
      view.mats[key] = nil
    end
  end
  local tableImage = game.rules.layout and game.rules.layout.tableImage
  if webUrl(tableImage) and Tables and Tables.getTable and Tables.getTable() == "Table_Custom"
    and Tables.getCustomURL() ~= tableImage then
    Tables.setCustomURL(tableImage)
  end
end

return Mats
