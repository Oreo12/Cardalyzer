-- Rulebooks: PDFs listed in rules.rulebooks, spawned on the table beside the
-- play areas when a player presses Rulebooks, and removed when it's pressed
-- again.
--
--   rules.rulebooks = { { name = "Rules", url = "https://.../rules.pdf" }, ... }
--   rules.layout.rulebooks = { x = 40, z = 0, spacing = 9.5, scale = 2, yaw = 180, locked = false }
--
-- Every field of layout.rulebooks is optional. By default the books stand in a
-- line along the table's depth, just past the furthest play area on the +x
-- side, at the largest player count, so they never sit on a game.
local Zones = require("engine.zones")

local Rulebooks = {}

-- Only web addresses: a rulebook is fetched by every player's TTS.
local function webUrl(url)
  return type(url) == "string" and (url:match("^https://") or url:match("^http://")) and true or false
end

-- The furthest x any pile reaches, at the most seats the rules allow.
local function farthestX(rules)
  local layout = Zones.layout(rules, nil, #rules.seats)
  local most = 0
  local function reach(s)
    local half = s.size and math.max(s.size[1], s.size[3]) / 2 or 2
    most = math.max(most, math.abs(s.position[1]) + half)
  end
  for _, seat in ipairs(layout.seats) do
    for _, name in ipairs({ "play", "bases", "deck", "discard", "hand" }) do reach(seat[name]) end
  end
  for _, s in ipairs(layout.market.row) do reach(s) end
  reach(layout.market.deck)
  reach(layout.market.scrap)
  return most
end

-- Where each rulebook goes: { { name, url, position, rotation, scale } }.
-- Entries without an http(s) url are left out.
function Rulebooks.spots(rules)
  local books = {}
  for _, b in ipairs(rules.rulebooks or {}) do
    if webUrl(b.url) then books[#books + 1] = b end
  end
  local cfg = rules.layout and rules.layout.rulebooks or {}
  local x = cfg.x or (farthestX(rules) + 6)
  local spacing = cfg.spacing or 9.5
  local scale = cfg.scale or 2
  local y = ((rules.layout and rules.layout.surfaceY) or 1.1) + 1
  local first = (cfg.z or 0) - (#books - 1) / 2 * spacing
  local out = {}
  for i, b in ipairs(books) do
    out[i] = {
      name = b.name or ("Rulebook " .. i),
      url = b.url,
      position = { x, y, first + (i - 1) * spacing },
      rotation = { 0, cfg.yaw or 180, 0 },
      scale = { scale, 1, scale },
    }
  end
  return out
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

-- Are any of this game's rulebooks on the table?
function Rulebooks.shown(game)
  for _, guid in ipairs(game.state.view.rulebooks or {}) do
    if getObjectFromGUID(guid) then return true end
  end
  return false
end

-- Spawns the rulebooks, or removes them when they're already out.
function Rulebooks.toggle(game)
  local view = game.state.view
  if Rulebooks.shown(game) then
    for _, guid in ipairs(view.rulebooks) do
      local obj = getObjectFromGUID(guid)
      if obj then obj.destruct() end
    end
    view.rulebooks = nil
    return false
  end
  local locked = game.rules.layout and game.rules.layout.rulebooks and game.rules.layout.rulebooks.locked
  view.rulebooks = {}
  for _, spot in ipairs(Rulebooks.spots(game.rules)) do
    local obj = spawnObjectData({
      data = {
        Name = "Custom_PDF",
        Nickname = spot.name,
        Locked = locked == true,
        Tags = { "cz_rulebook" },
        Transform = {
          posX = spot.position[1], posY = spot.position[2], posZ = spot.position[3],
          rotX = spot.rotation[1], rotY = spot.rotation[2], rotZ = spot.rotation[3],
          scaleX = spot.scale[1], scaleY = spot.scale[2], scaleZ = spot.scale[3],
        },
        CustomPDF = { PDFUrl = spot.url, PDFPassword = "", PDFPage = 0, PDFPageOffset = 0 },
      },
      position = spot.position,
      rotation = spot.rotation,
    })
    view.rulebooks[#view.rulebooks + 1] = obj.getGUID()
  end
  return true
end

return Rulebooks
