-- The look of the on-screen UI: button colours, panel backgrounds and
-- borders, and the title. rules.ui.theme overrides any part of
-- Theme.DEFAULT; whatever it leaves out keeps the default.
local Theme = {}

Theme.DEFAULT = {
  accent = "#E8B84A", -- titles and messages
  text = "#FFFFFF",
  -- Buttons: `color` and `text`, or a full TTS `colors` string
  -- ("normal|highlighted|pressed|disabled") instead of `color`.
  buttons = {
    primary = { color = "#E8B84A", text = "#1A1206" }, -- the main actions (Play Game, Play all, End Turn, New Game)
    secondary = { color = "#D6DEE8", text = "#14202C" }, -- everything else
    selected = { color = "#5AA9E6", text = "#06121E" }, -- the chosen option in a menu row
  },
  -- Panels: `color` (background), `image` (background picture, an asset URL),
  -- `imageColor` (tints the picture), `border` and `borderSize` (pixels),
  -- `padding` (pixels inside the border). false draws no panel at all.
  panels = {
    menu = { color = "#0E1620F2", border = "#E8B84A", borderSize = 2, padding = 14 }, -- New Game, Settings, game over
    choice = { color = "#0E1620E6", border = "#E8B84A", borderSize = 2, padding = 10 }, -- a choice in the middle of the screen
    title = false, -- the box around the title at the top of the info panel
    info = false, -- the whole info panel on the right
  },
  -- The info panel's title: the game's name as text, or `image` (an asset URL)
  -- drawn `height` pixels tall. `width` sizes its box (default: the panel's
  -- width); the box sits against the panel's right edge, like the rows below.
  title = { size = 18, image = nil, height = 64, width = nil },
  -- Menus lay their option buttons on a grid so rows line up: a `label`
  -- column, then `columns` cells `cell` pixels wide (a long label takes two
  -- cells). The menu's own buttons (Play Game, Close ...) are one cell wide.
  grid = { label = 110, cell = 140, columns = 4, size = 14 },
  -- Button ids drawn with the primary look.
  primary = { ["cz-playall"] = true, ["cz-end"] = true, ["cz-new"] = true, ["cz-again"] = true, ["cz-setup"] = true,
    ["cz-kitsave"] = true },
}

-- Copies `over` onto a copy of `base`, table by table. A false in `over`
-- replaces a whole table ("no panel").
local function merge(base, over)
  if type(base) ~= "table" or type(over) ~= "table" then
    if over == nil then return base end
    return over
  end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do out[k] = merge(base[k], v) end
  return out
end

-- The theme for these rules: the default with rules.ui.theme laid over it.
function Theme.of(rules)
  return merge(Theme.DEFAULT, rules.ui and rules.ui.theme or {})
end

-- "#RRGGBB" or "#RRGGBBAA" times f (lighter above 1), alpha kept.
local function shade(hex, f)
  local r, g, b, a = hex:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  if not r then return hex end
  local function ch(x) return string.format("%02X", math.max(0, math.min(255, math.floor(tonumber(x, 16) * f + 0.5)))) end
  return "#" .. ch(r) .. ch(g) .. ch(b) .. a
end
Theme.shade = shade

-- A button look's TTS `colors` string and text colour.
function Theme.button(rules, kind)
  local b = Theme.of(rules).buttons[kind] or Theme.of(rules).buttons.secondary
  local colors = b.colors
  if not colors then
    local base = b.color:sub(1, 7)
    colors = b.color .. "|" .. shade(base, 1.15) .. "|" .. shade(base, 0.82) .. "|" .. base .. "80"
  end
  return colors, b.text or "#000000"
end

-- Is this button id drawn with the primary look?
function Theme.isPrimary(rules, id)
  return Theme.of(rules).primary[id] == true
end

-- Every picture the theme uses: { url, ... }.
function Theme.images(rules)
  local t, out = Theme.of(rules), {}
  for _, p in pairs(t.panels) do
    if p and p.image then out[#out + 1] = p.image end
  end
  if t.title.image then out[#out + 1] = t.title.image end
  return out
end

-- The UI asset name for a picture URL.
function Theme.assetName(url)
  return "cz_img_" .. url:gsub("[^%w]", ""):sub(-24)
end

-- A panel's look: the attributes for its outer <Panel> (background colour and
-- border), the XML of its background picture (first child), and its padding.
-- No panel style: a clear panel.
function Theme.panel(rules, name)
  local p = Theme.of(rules).panels[name]
  if not p then return ' color="#00000000"', "", 0 end
  local attrs = ' color="' .. (p.color or "#00000000") .. '"'
  -- borderSize = 0 (or border = false) draws no border
  if p.border and (p.borderSize or 0) > 0 then
    -- TTS's outline effect draws the panel's shape again around its edge: a border.
    attrs = attrs .. ' outline="' .. p.border .. '" outlineSize="' .. p.borderSize .. ' -' .. p.borderSize .. '"'
  end
  local image = ""
  if p.image then
    image = '<Image image="' .. Theme.assetName(p.image) .. '" color="' .. (p.imageColor or "#FFFFFF") .. '" raycastTarget="false" />'
  end
  return attrs, image, p.padding or 0
end

return Theme
