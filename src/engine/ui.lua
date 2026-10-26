-- XML UI, down the right of the screen: an action panel only the active player
-- sees (prompts, Play all, attacks, scrap abilities, End Turn) at the top, an
-- info panel everyone sees, and Tidy table in the corner. New Game opens a
-- setup menu in the middle (player count, Play Game, Tutorial).
-- The whole XML is rebuilt on every refresh. Every button calls
-- Cardalyzer_onUI in main.lua, which reads the action from the button id:
--   cz-setup  cz-setupclose  cz-new (Play Game)  cz-again (Play Again?)  cz-tidy  cz-end  cz-playall
--   cz-done  cz-players-<n>
--   cz-pick-<value>  cz-attack-<seat>  cz-hit-<seat>-<uid>  cz-scrap-<uid>
local Util = require("engine.util")
local State = require("engine.state")
local Actions = require("engine.actions")
local Tutorial = require("engine.tutorial")
local Theme = require("engine.theme")

local UI_ = {}

-- The rules being drawn, so the small helpers below can read the theme.
-- UI_.xml (and every panel builder called on its own) sets it first.
local current = {}
local function use(game) current = game.rules end
local function accent() return Theme.of(current).accent end

local function escape(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- extra may set color= or alignment= itself; otherwise white, left-aligned.
local function text(id, words, size, extra)
  extra = extra or ""
  if not extra:find("color=", 1, true) then extra = extra .. ' color="' .. Theme.of(current).text .. '"' end
  if not extra:find("alignment=", 1, true) then extra = extra .. ' alignment="MiddleLeft"' end
  return string.format('<Text id="%s" fontSize="%d" %s>%s</Text>', id, size or 14, extra, escape(words))
end

function UI_.turnLine(game)
  local state = game.state
  if not state.started then return "Press New Game to set up a game." end
  if state.winner then return state.players[state.winner].name .. " wins!" end
  local active = state.players[state.turn.active]
  return "Turn " .. state.turn.number .. " · " .. active.name .. " to play"
end

-- A seat's first waiting choice: its text and its option buttons (nil if none).
-- Any player can have one: events ask every player.
function UI_.promptFor(game, seat)
  local p = game.state.players[seat]
  local prompt = p.prompts[1]
  local choices = {}
  if not prompt then return nil, choices end
  local more = #p.prompts > 1 and (" (+" .. (#p.prompts - 1) .. " more)") or ""
  for _, t in ipairs(Actions.targets(game, seat, prompt)) do
    choices[#choices + 1] = { id = "cz-pick-" .. t.value, label = t.label }
  end
  if prompt.optional then choices[#choices + 1] = { id = "cz-done", label = prompt.kind == "reminder" and "Done" or "Skip / done" } end
  return Actions.promptText(game, prompt) .. more, choices
end

-- The active player's options. `prompt` is the first choice waiting (with
-- `choices`, its buttons), and `buttons` everything else they can do now.
function UI_.actions(game)
  local state = game.state
  local seat = state.turn.active
  local p = state.players[seat]
  local out = { prompt = nil, choices = {}, buttons = {} }
  local function add(list, id, label) list[#list + 1] = { id = id, label = label } end

  out.prompt, out.choices = UI_.promptFor(game, seat)

  if #p.hand > 0 and not Actions.handBlocked(game, seat) then add(out.buttons, "cz-playall", "Play all (" .. #p.hand .. ")") end

  local key, label = Actions.resourceFor(game.rules, "attack")
  local pool = key and p.resources[key] or 0
  if pool > 0 then
    for _, other in ipairs(game:opponentsOf(seat)) do
      local guards = Actions.guards(game, other)
      local victim = state.players[other]
      if #guards == 0 then add(out.buttons, "cz-attack-" .. other, "Attack " .. victim.name .. " (" .. pool .. " " .. label .. ")") end
      for _, uid in ipairs(victim.bases) do
        local c = game.cards:get(State.cardId(state, uid))
        local open = #guards == 0 or Util.indexOf(guards, uid)
        local defense = Actions.defenseOf(game, other, uid)
        if open and pool >= defense and Actions.typeDef(game, c).target ~= false then
          add(out.buttons, "cz-hit-" .. other .. "-" .. uid, "Destroy " .. c.name .. " (" .. defense .. ")")
        end
      end
    end
  end

  for _, uid in ipairs(Actions.inPlay(p)) do
    local c = game:cardOf(uid) -- a card copying another this turn shows that card's scrap ability
    if Actions.canScrap(game, seat, uid) then -- (some need an ally in play first)
      add(out.buttons, "cz-scrap-" .. uid, "Scrap " .. c.name .. ": " .. game.effects:describe(c.scrapEffects, c.text))
    end
  end

  for _, a in ipairs(Actions.activatable(game, seat)) do
    add(out.buttons, "cz-use-" .. a.uid, "Use " .. game:cardOf(a.uid).name .. (a.def.text and (": " .. a.def.text) or ""))
  end
  local goalLabel = game.rules.objectives and game.rules.objectives.label or "goal"
  for _, uid in ipairs(Actions.completable(game, seat)) do
    add(out.buttons, "cz-goal-" .. uid, "Complete " .. game:cardOf(uid).name)
  end
  add(out.buttons, "cz-end", "End Turn")
  if #p.objectives > 0 then
    local names = {}
    for _, uid in ipairs(p.objectives) do names[#names + 1] = game:cardOf(uid).name end
    out.goals = "Your " .. goalLabel:lower() .. ": " .. table.concat(names, ", ")
  end
  -- Everything in one list, for callers that don't care where it's shown.
  out.all = {}
  for _, b in ipairs(out.choices) do out.all[#out.all + 1] = b end
  for _, b in ipairs(out.buttons) do out.all[#out.all + 1] = b end
  return out
end

-- Hex values of the TTS seat colours, for tinting each player's name.
UI_.seatColors = {
  White = "#FFFFFF", Brown = "#A0653A", Red = "#E5413F", Orange = "#F4741D", Yellow = "#E7E52C",
  Green = "#4CC845", Teal = "#21B19B", Blue = "#3C96FF", Purple = "#B04CF0", Pink = "#F570CE",
}

-- Panels with no style of their own are clear: text and standalone buttons sit straight on the screen.
local PANEL = ' color="#00000000"'
-- Shadowed text, readable straight over the table.
local FX = ' outline="#000000E0" outlineSize="1.5 -1.5"'

---------------------------------------------------------------------------
-- Icons: a counter is its symbol with the number laid over it.
---------------------------------------------------------------------------

-- Built-in symbols, hosted with the engine. rules.ui.iconBaseUrl points
-- elsewhere: a folder holding coin.png, reticle.png, heart.png and shield.png.
UI_.ICONS = { "coin", "reticle", "heart", "shield" }
UI_.ICON_BASE = "https://raw.githubusercontent.com/Oreo12/Cardalyzer/main/assets/icons/"

-- The symbol for a resource or stat: its `icon` (a built-in name or a full
-- URL), else coin for the buy resource, reticle for the attack resource and
-- heart for the win stat. nil means its label is shown as text.
function UI_.iconFor(rules, entry, kind)
  if entry.icon then return entry.icon end
  if kind == "resource" and entry.spend == "buy" then return "coin" end
  if kind == "resource" and entry.spend == "attack" then return "reticle" end
  if kind == "stat" and rules.win and rules.win.stat == entry.key then return "heart" end
  return nil
end

local function assetName(icon)
  if icon:match("^https?://") or icon:match("^file://") then
    return "cz_icon_" .. icon:gsub("[^%w]", ""):sub(-24)
  end
  return "cz_" .. icon
end

-- Every image the UI uses, for UI.setCustomAssets.
function UI_.assets(rules)
  local base = (rules.ui and rules.ui.iconBaseUrl) or UI_.ICON_BASE
  local out, seen = {}, {}
  local function add(icon)
    if icon and not seen[icon] then
      seen[icon] = true
      local full = (icon:match("^https?://") or icon:match("^file://")) and icon or (base .. icon .. ".png")
      out[#out + 1] = { name = assetName(icon), url = full }
    end
  end
  for _, name in ipairs(UI_.ICONS) do add(name) end
  for _, r in ipairs(rules.resources or {}) do add(UI_.iconFor(rules, r, "resource")) end
  for _, st in ipairs(rules.stats or {}) do add(UI_.iconFor(rules, st, "stat")) end
  for _, url in ipairs(Theme.images(rules)) do
    if not seen[url] then
      seen[url] = true
      out[#out + 1] = { name = Theme.assetName(url), url = url }
    end
  end
  return out
end

local function counter(id, icon, value, size)
  return '<Panel id="' .. id .. '" preferredWidth="' .. size .. '" preferredHeight="' .. size .. '">'
    .. '<Image image="' .. assetName(icon) .. '" preserveAspect="true" />'
    .. string.format('<Text id="%s_n" fontSize="%d" fontStyle="Bold" color="#FFFFFF" alignment="MiddleCenter"%s>%s</Text>',
      id, math.floor(size * 0.45), FX, escape(value))
    .. '</Panel>'
end

-- A standalone button, as wide as its label needs. Its look comes from the
-- theme: primary for the main actions (the theme's primary ids), `kind` if
-- given ("selected" for a chosen option), else secondary. Returns XML and width.
local function smallButton(id, label, size, kind, width, tooltip)
  size = size or 12
  kind = kind or (Theme.isPrimary(current, id) and "primary" or "secondary")
  local colors, textColor = Theme.button(current, kind)
  width = width or math.max(60, math.floor(#label * size * 0.6) + 24)
  local tip = tooltip and (' tooltip="' .. escape(tooltip) .. '" tooltipPosition="Above" tooltipWidth="320"') or ""
  return string.format('<Button id="%s" onClick="Cardalyzer_onUI" preferredHeight="%d" preferredWidth="%d" fontSize="%d"'
    .. ' fontStyle="Bold" colors="%s" textColor="%s"%s>%s</Button>',
    id, size + 14, width, size, colors, textColor, tip, escape(label)), width
end
UI_.button = smallButton

-- A panel drawn in theme style `name` (see Theme.panel): `inner` is a
-- VerticalLayout's children, w and h their size. Returns XML, and the
-- panel's size grown by its padding.
function UI_.framed(id, name, inner, w, h, attrs, spacing)
  local look, image, pad = Theme.panel(current, name)
  return '<Panel id="' .. id .. '"' .. (attrs or "") .. ' width="' .. (w + 2 * pad) .. '" height="' .. (h + 2 * pad) .. '"' .. look .. '>'
    .. image .. '<VerticalLayout spacing="' .. (spacing or 4) .. '" padding="' .. pad .. ' ' .. pad .. ' ' .. pad .. ' ' .. pad
    .. '" childForceExpandHeight="false">' .. inner .. '</VerticalLayout></Panel>', w + 2 * pad, h + 2 * pad
end

-- Buttons in centred rows no wider than maxWidth. `bigger` lists ids drawn at
-- a larger size. Returns XML and its height.
local function buttonRows(list, size, maxWidth, bigger)
  local rows, row, used, rowSize = {}, {}, 0, size
  local sizes = {}
  -- One statement per table: TTS's Lua (MoonSharp) doesn't evaluate
  -- `a[#a + 1], b[#a + 1] = x, y` the way standard Lua does.
  local function closeRow()
    local n = #rows + 1
    rows[n] = row
    sizes[n] = rowSize
  end
  for _, b in ipairs(list) do
    local s = (bigger and bigger[b.id]) and bigger[b.id] or size
    local xml, w = smallButton(b.id, b.label, s, nil, b.width)
    if used > 0 and used + w > maxWidth then
      closeRow()
      row, used, rowSize = {}, 0, size
    end
    row[#row + 1] = xml
    used = used + w + 6
    rowSize = math.max(rowSize, s)
  end
  if #row > 0 then closeRow() end
  local out, height = {}, 0
  for i, r in ipairs(rows) do
    out[#out + 1] = '<HorizontalLayout spacing="6" preferredHeight="' .. (sizes[i] + 14) .. '" childForceExpandWidth="false"'
      .. ' childForceExpandHeight="false" childAlignment="MiddleCenter">' .. table.concat(r) .. '</HorizontalLayout>'
    height = height + sizes[i] + 20
  end
  return table.concat(out), height
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

-- The right-hand column: the info panel above the Tidy table button at the
-- bottom, and a private message for one player just above the info panel.
UI_.INFO_WIDTH = 300
-- Both sit clear of TTS's own Notes button in the bottom right corner.
local TIDY_Y = 70 -- the Tidy table button's bottom edge, in pixels above the screen's
local INFO_BOTTOM = 112 -- the info panel's bottom edge
UI_.ACTION_BAR_Y = 210 -- the action bar's bottom edge by default: just above the on-screen hand
UI_.BAR_STEP = 30 -- how far one press of Up / Down in Settings moves a player's bar

-- Rough pixel height of a message wrapped to the info panel's width.
local function wrappedHeight(msg, size)
  local perLine = math.floor((UI_.INFO_WIDTH - 8) / (size * 0.52))
  return math.max(1, math.ceil(#msg / perLine)) * (size + 6)
end

-- A seat's row: name (bold with a marker on its turn), then a shield per
-- base in play with its defense, then its stats, e.g. the heart and Authority.
-- Returns XML and height.
local function seatRow(game, seat)
  local state, rules = game.state, game.rules
  local p = state.players[seat]
  local active = state.started and state.turn.active == seat
  local name = (active and "▶ " or "") .. p.name .. (p.out and ": out" or "")
  local xml = text("cz_seat_" .. seat, name, 16, 'color="' .. (UI_.seatColors[p.color] or "#FFFFFF") .. '"'
    .. (active and ' fontStyle="Bold"' or "") .. ' preferredWidth="110"' .. FX)
  if not p.out then
    for i, uid in ipairs(p.bases) do
      local c = game.cards:get(State.cardId(state, uid))
      if c.defense then xml = xml .. counter("cz_base_" .. seat .. "_" .. i, "shield", Actions.defenseOf(game, seat, uid), 30) end
    end
    for _, st in ipairs(rules.stats or {}) do
      local icon = UI_.iconFor(rules, st, "stat")
      local value = p.stats[st.key] or 0
      xml = xml .. (icon and counter("cz_stat_" .. seat .. "_" .. st.key, icon, value, 34)
        or text("cz_stat_" .. seat .. "_" .. st.key, (st.label or Util.titleCase(st.key)) .. " " .. value, 14, FX))
    end
  end
  -- only in a game that dealt objectives (their set may be switched off)
  local goals = rules.objectives and #p.completed + #p.objectives > 0 and (" · " .. (rules.objectives.label or "Goals") .. " " .. #p.completed
    .. "/" .. (rules.objectives.toWin or #p.completed + #p.objectives)) or ""
  local piles = text("cz_seat_" .. seat .. "_piles", "Deck " .. #p.deck .. " · Discard " .. #p.discard .. goals, 11,
    'color="#C8CED6" alignment="MiddleRight" preferredHeight="14"' .. FX)
  return '<HorizontalLayout spacing="4" preferredHeight="34" childForceExpandWidth="false" childAlignment="MiddleRight">'
    .. xml .. '</HorizontalLayout>' .. piles, 34 + 14 + 4
end

-- The active player's per-turn counters (Trade, Combat) that are above 0, for
-- the row just above the action bar. nil when there's nothing to count.
local function turnCounters(game, color)
  local state, rules = game.state, game.rules
  if not state.started or state.winner then return nil end
  local p = state.players[state.turn.active]
  local xml = ""
  for _, r in ipairs(rules.resources or {}) do
    local value = p.resources[r.key] or 0
    if value > 0 then
      local icon = UI_.iconFor(rules, r, "resource")
      local id = "cz_res_" .. color .. "_" .. r.key
      xml = xml .. (icon and counter(id, icon, value, 52)
        or text(id, (r.label or Util.titleCase(r.key)) .. " " .. value, 18, 'fontStyle="Bold"' .. FX))
    end
  end
  if xml == "" then return nil end
  return '<HorizontalLayout spacing="12" preferredHeight="52" childForceExpandWidth="false" childAlignment="MiddleCenter">'
    .. xml .. '</HorizontalLayout>'
end

---------------------------------------------------------------------------
-- Per-player settings: UI size and action bar height (Settings menu)
---------------------------------------------------------------------------

-- The UI sizes a player can pick, smallest to largest (1 is normal).
UI_.SCALES = { 0.7, 0.8, 0.9, 1, 1.1, 1.25, 1.4, 1.55 }

-- A colour's UI size (state.view.uiScale, saved with the game).
function UI_.scaleOf(game, color)
  return game.state.view.uiScale and game.state.view.uiScale[color] or 1
end

-- A panel's XML at UI size k: every font size, width, height, spacing and
-- padding multiplied by k. Panels are drawn at their real size rather than
-- with TTS's scale attribute, which lost button backgrounds and panels in TTS.
local SIZED = { fontSize = true, preferredWidth = true, preferredHeight = true, width = true, height = true,
  spacing = true, padding = true }
local function sized(xml, k)
  if not k or k == 1 then return xml end
  return (xml:gsub('( (%a+)="([%d%. %-]+)")', function(whole, attr, value)
    if not SIZED[attr] then return whole end
    local nums = {}
    for n in value:gmatch("%-?[%d%.]+") do
      nums[#nums + 1] = string.format("%d", math.floor(tonumber(n) * k + 0.5))
    end
    return " " .. attr .. '="' .. table.concat(nums, " ") .. '"'
  end))
end

-- Every TTS colour (except those in `skip`) grouped by UI size, normal size
-- first. Panels everyone sees are drawn once per group, each scaled for it.
-- `single` is set when everyone shares one size and nobody is skipped.
function UI_.scaleGroups(game, skip)
  local byScale, order = {}, {}
  for _, color in ipairs(Tutorial.allColors) do
    if not (skip and skip[color]) then
      local s = UI_.scaleOf(game, color)
      if not byScale[s] then
        byScale[s] = { scale = s, colors = {} }
        order[#order + 1] = s
      end
      local list = byScale[s].colors
      list[#list + 1] = color
    end
  end
  table.sort(order, function(a, b)
    if a == 1 or b == 1 then return a == 1 and b ~= 1 end
    return a < b
  end)
  local groups = {}
  for _, s in ipairs(order) do groups[#groups + 1] = byScale[s] end
  groups.single = #groups == 1 and not skip
  return groups
end

-- The visibility attribute for group i, and the id suffix that keeps copies
-- apart (none for the first).
local function groupAttrs(groups, i)
  local g = groups[i]
  local vis = groups.single and "" or (' visibility="' .. table.concat(g.colors, "|") .. '"')
  return vis, i == 1 and "" or ("_" .. i)
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

-- The info panel, on the right: title, turn, the players, the last few
-- messages (see Game:notify; TTS draws broadcasts behind custom UI, so
-- they're shown here instead), then Settings and New Game (which opens the
-- setup menu). Returns its XML and its unscaled height in pixels.
function UI_.infoPanel(game, suffix, attrs, bottom)
  use(game)
  local state = game.state
  local rows, height = {}, 0
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 4 end

  row(UI_.titleBox(game))
  local turn = UI_.turnLine(game)
  local th = wrappedHeight(turn, 14)
  row(text("cz_turn", turn, 14, 'fontStyle="Bold" alignment="MiddleRight" preferredHeight="' .. th .. '"' .. FX), th)
  for seat = 1, #state.players do row(seatRow(game, seat)) end
  for i, msg in ipairs(game.notices and game.notices.all or {}) do
    local h = wrappedHeight(msg, 12)
    row(text("cz_notice_" .. i, msg, 12, 'color="' .. accent() .. '" fontStyle="Italic" alignment="MiddleRight" preferredHeight="'
      .. h .. '"' .. FX), h)
  end
  row('<HorizontalLayout spacing="6" preferredHeight="28" childForceExpandWidth="false" childAlignment="MiddleRight">'
    .. smallButton("cz-settings", "Settings", 14) .. smallButton("cz-setup", "New Game", 14) .. '</HorizontalLayout>', 28)

  local xml, _, h = UI_.framed("cz_panel" .. (suffix or ""), "info", table.concat(rows), UI_.INFO_WIDTH, height - 4,
    (attrs or "") .. ' rectAlignment="LowerRight" offsetXY="-12 ' .. (bottom or INFO_BOTTOM) .. '"')
  return xml, h
end

-- The title at the top of the info panel: the theme's title picture, or the
-- game's name, in the theme's "title" panel style. Returns XML and height.
function UI_.titleBox(game)
  use(game)
  local theme = Theme.of(game.rules)
  local t = theme.title
  local inner, h
  if t.image then
    h = t.height
    inner = '<Image id="cz_title" image="' .. Theme.assetName(t.image) .. '" preserveAspect="true" preferredHeight="' .. h .. '" />'
  else
    h = t.size + 6
    inner = text("cz_title", game.rules.name or "Cardalyzer", t.size, 'fontStyle="Bold" alignment="MiddleRight" color="'
      .. accent() .. '" preferredHeight="' .. h .. '"' .. FX)
  end
  local look = theme.panels.title
  if not look then return inner, h end
  local pad = look.padding or 0
  local box, _, bh = UI_.framed("cz_title_box", "title", inner, (t.width or UI_.INFO_WIDTH - 2 * pad), h, ' rectAlignment="MiddleRight"')
  return '<Panel preferredHeight="' .. bh .. '" color="#00000000">' .. box .. '</Panel>', bh
end

-- A centred panel in theme style `style` (default "menu"): a title,
-- optional extra rows and rows of standalone buttons. The setup menu,
-- settings, choices and game over use it. extra = { xml, height }.
local function centrePanel(id, visibility, title, titleColor, titleSize, extra, buttons, scale, style, width)
  width = width or 660
  local rows, height = {}, 0
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 8 end
  local th = math.max(1, math.ceil(#title / 48)) * (titleSize + 8)
  row(text(id .. "_title", title, titleSize, 'fontStyle="Bold" alignment="MiddleCenter" preferredHeight="' .. th
    .. '" color="' .. titleColor .. '"' .. FX), th)
  if extra then row(extra[1], extra[2]) end
  if #buttons > 0 then
    local bx, bh = buttonRows(buttons, 13, width - 40)
    row(bx, bh)
  end
  return sized((UI_.framed(id, style or "menu", table.concat(rows), width, height - 8,
    ' visibility="' .. visibility .. '" rectAlignment="MiddleCenter"', 8)), scale)
end
UI_.centrePanel = centrePanel

-- Player-count buttons (cz-players-<n>) for games that seat more than one
-- number of players. Only the host's clicks count (see main.lua).
function UI_.playersRow(game)
  local range = game.playerRange(game.rules)
  if range.min >= range.max then return nil end
  local state = game.state
  local chosen = state.nextPlayers or #state.players
  local list = {}
  for n = range.min, range.max do list[#list + 1] = { id = "cz-players-" .. n, label = tostring(n), on = n == chosen } end
  return UI_.optionRow("cz_players", "Players", list)
end

-- The menu grid (theme grid): how many cells a button with this label
-- takes, and the width of n cells.
local function cellsFor(label)
  local g = Theme.of(current).grid
  local natural = math.floor(#label * g.size * 0.55) + 24
  return math.max(1, math.ceil((natural + 6) / (g.cell + 6)))
end
local function cellWidth(n)
  local g = Theme.of(current).grid
  return n * g.cell + (n - 1) * 6
end
-- The grid's full width: the label column and every cell.
function UI_.gridWidth()
  local g = Theme.of(current).grid
  return g.label + 6 + cellWidth(g.columns)
end

-- The setup menu, in the middle of the screen for the player who pressed New
-- Game: the player count, Play Game (deals and closes the menu), Tutorial and
-- Close. Choices made here are kept for next time.
-- A row of the setup menu: a label, then one button per option, the chosen
-- ones in gold. options = { {id, label, on}, ... }.
-- Its buttons sit on the menu grid (theme grid), so the rows line up.
function UI_.optionRow(id, label, options)
  local g = Theme.of(current).grid
  local xml = text(id, label, 15, 'preferredWidth="' .. g.label .. '" alignment="MiddleRight"' .. FX)
  for _, o in ipairs(options) do
    -- an option is selected or not; a plain button (on = nil) takes its usual look
    local kind = o.kind
    if not kind and o.on ~= nil then kind = o.on and "selected" or "secondary" end
    xml = xml .. smallButton(o.id, o.label, g.size, kind, cellWidth(cellsFor(o.label)), o.tooltip)
  end
  return '<HorizontalLayout spacing="6" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleLeft">'
    .. xml .. '</HorizontalLayout>'
end

-- The starting-hand choice (cz-opening-<i>), when the rules offer more than
-- one. Each option's `about` is its tooltip (and is in the tutorial).
function UI_.openingRow(game)
  local options = game.rules.openingHands or {}
  if #options < 2 then return nil end
  local chosen = game:setupChoice("opening") or 1
  local list = {}
  for i, o in ipairs(options) do
    list[#list + 1] = { id = "cz-opening-" .. i, label = o.label, on = i == chosen, tooltip = o.about }
  end
  return UI_.optionRow("cz_opening", game.rules.openingLabel or "Starting hands", list)
end

-- The set toggles (cz-set-<key>), when the rules list sets, four to a row.
-- Returns a list of rows.
function UI_.setRows(game)
  local sets = game.rules.sets or {}
  if #sets < 2 then return {} end
  local inPlay = game:setsInPlay()
  local columns = Theme.of(current).grid.columns
  local rows, row, used = {}, {}, 0
  for _, set in ipairs(sets) do
    local n = cellsFor(set.label)
    if used > 0 and used + n > columns then rows[#rows + 1] = row; row = {}; used = 0 end
    row[#row + 1] = { id = "cz-set-" .. set.key, label = set.label, on = inPlay[set.key] == true }
    used = used + n
  end
  if #row > 0 then rows[#rows + 1] = row end
  local out = {}
  for i, r in ipairs(rows) do out[i] = UI_.optionRow("cz_sets_" .. i, i == 1 and "Sets" or "", r) end
  return out
end

function UI_.setupPanel(game, color)
  use(game)
  local buttons = { { id = "cz-new", label = "Play Game" } }
  if Tutorial.buttonShown(game, color) then buttons[#buttons + 1] = { id = "cz-tutorial", label = "Tutorial" } end
  buttons[#buttons + 1] = { id = "cz-setupclose", label = "Close" }
  local rows, height = {}, 0
  local function add(r)
    if not r then return end
    rows[#rows + 1] = r
    height = height + 30 + (#rows > 1 and 8 or 0)
  end
  add(UI_.playersRow(game))
  add(UI_.openingRow(game))
  if game.rules.kits and #game.rules.kits > 0 then
    local mode = game:setupChoice("kits") or "off"
    add(UI_.optionRow("cz_kits", game.rules.kitLabel or "Starting decks", {
      { id = "cz-kits-off", label = "Standard", on = mode ~= "random" },
      { id = "cz-kits-random", label = "Random " .. (game.rules.kitName or "kit"), on = mode == "random" },
    }))
  end
  for _, r in ipairs(UI_.setRows(game)) do add(r) end
  -- rules.ui.setupMenu(game, color, menu, UI) may change the menu (its
  -- title, its rows of XML, each rowHeight tall, and its buttons) or return
  -- XML of its own to draw instead. See README, "Customising the UI".
  local menu = { title = "New Game", rows = rows, rowHeight = 30, buttons = buttons }
  local custom = game.rules.ui and game.rules.ui.setupMenu
  if custom then
    local own = custom(game, color, menu, UI_)
    if type(own) == "string" then return own end
    rows, buttons = menu.rows, menu.buttons
  end
  -- the menu's own buttons go on the grid too, under the options
  rows[#rows + 1] = UI_.optionRow("cz_setup_buttons_" .. color, "", buttons)
  height = 0
  for i in ipairs(rows) do height = height + menu.rowHeight + (i > 1 and 8 or 0) end
  local extra = #rows > 0 and { '<VerticalLayout spacing="8" preferredHeight="' .. height .. '" childForceExpandHeight="false">'
    .. table.concat(rows) .. '</VerticalLayout>', height } or nil
  -- the grid's rows are left-aligned: pad them in so the grid is centred
  local width = math.max(660, UI_.gridWidth() + 20)
  local inset = math.floor((width - UI_.gridWidth()) / 2)
  if extra then extra[1] = extra[1]:gsub('^<VerticalLayout ', '<VerticalLayout padding="' .. inset .. ' 0 0 0" ', 1) end
  return centrePanel("cz_setup_" .. color, color, menu.title, accent(), 22, extra, {}, UI_.scaleOf(game, color), "menu", width)
end

-- The settings menu, just for the player who opened it: their UI size and
-- where their action bar sits (to clear their own on-screen hand).
function UI_.settingsPanel(game, color)
  use(game)
  local scale = UI_.scaleOf(game, color)
  local moved = game.state.view.barOffset and game.state.view.barOffset[color] or 0
  local function settingRow(id, label, value, buttons)
    local xml = text(id, label, 15, 'preferredWidth="130" alignment="MiddleRight"' .. FX)
    for _, b in ipairs(buttons) do xml = xml .. smallButton(b[1], b[2], 14) end
    if value then xml = xml .. text(id .. "_value", value, 15, 'preferredWidth="70" alignment="MiddleLeft" fontStyle="Bold"' .. FX) end
    return '<HorizontalLayout spacing="6" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleCenter">'
      .. xml .. '</HorizontalLayout>'
  end
  local rows = settingRow("cz_set_ui_" .. color, "UI size", math.floor(scale * 100 + 0.5) .. "%",
      { { "cz-uismaller", "−" }, { "cz-uibigger", "+" } })
    .. settingRow("cz_set_bar_" .. color, "Action bar", (moved > 0 and "+" or "") .. moved,
      { { "cz-barup", "Up" }, { "cz-bardown", "Down" }, { "cz-barreset", "Reset" } })
  return centrePanel("cz_settings_" .. color, color, "Settings", accent(), 22, { rows, 76 },
    { { id = "cz-settingsclose", label = "Close" } }, scale)
end

function UI_.xml(game)
  use(game)
  local state = game.state
  local parts = {}

  -- The info panel and Tidy table (bottom right), once per UI size in use.
  -- Tidy table sits clear of TTS's own Notes button; the info panel above it.
  local groups = UI_.scaleGroups(game)
  local infoTop = {}
  for i, g in ipairs(groups) do
    local vis, suffix = groupAttrs(groups, i)
    local infoBottom = TIDY_Y + math.ceil(42 * g.scale)
    local info, h = UI_.infoPanel(game, suffix, vis, infoBottom)
    parts[#parts + 1] = sized(info, g.scale)
    parts[#parts + 1] = sized('<Panel id="cz_tidy' .. suffix .. '"' .. vis .. ' width="' .. UI_.INFO_WIDTH .. '" height="30" rectAlignment="LowerRight" offsetXY="-12 '
      .. TIDY_Y .. '"' .. PANEL .. '><HorizontalLayout spacing="6" childForceExpandWidth="false" childAlignment="MiddleRight">'
      .. UI_.cornerButtons(game) .. '</HorizontalLayout></Panel>', g.scale)
    for _, color in ipairs(g.colors) do infoTop[color] = infoBottom + math.ceil(h * g.scale) end
  end

  -- A private message for one player, just above the info panel.
  local byColor = game.notices and game.notices.byColor or {}
  local colors = {}
  for color in pairs(byColor) do colors[#colors + 1] = color end
  table.sort(colors)
  for _, color in ipairs(colors) do
    local h = wrappedHeight(byColor[color], 13) + 6
    parts[#parts + 1] = sized('<Panel id="cz_notice_' .. color .. '" visibility="' .. color .. '"'
      .. ' width="' .. UI_.INFO_WIDTH .. '" height="' .. h .. '" rectAlignment="LowerRight" offsetXY="-12 '
      .. ((infoTop[color] or INFO_BOTTOM) + 6) .. '"' .. PANEL .. '>'
      .. text("cz_notice_text_" .. color, byColor[color], 13, 'alignment="MiddleRight" color="' .. accent() .. '"' .. FX)
      .. '</Panel>', UI_.scaleOf(game, color))
  end

  -- The setup and settings menus, for each player who opened one.
  for _, which in ipairs({ { game.setupOpen, UI_.setupPanel }, { game.settingsOpen, UI_.settingsPanel } }) do
    local open = {}
    for color in pairs(which[1] or {}) do open[#open + 1] = color end
    table.sort(open)
    for _, color in ipairs(open) do parts[#parts + 1] = which[2](game, color) end
  end

  -- Game over: the winner, in the middle of the screen for everyone (except
  -- whoever has the setup menu open there), with Play Again? to set up the next.
  if state.winner then
    local winner = state.players[state.winner]
    local skip = {}
    for color in pairs(game.setupOpen or {}) do skip[color] = true end
    local wg = UI_.scaleGroups(game, skip)
    for i, g in ipairs(wg) do
      local _, suffix = groupAttrs(wg, i, "0.5 0.5")
      parts[#parts + 1] = centrePanel("cz_winner" .. suffix, table.concat(g.colors, "|"), winner.name .. " wins!",
        UI_.seatColors[winner.color] or accent(), 34, nil, { { id = "cz-again", label = "Play Again?" } }, g.scale)
    end
  end

  -- The tutorial, in the middle of the screen, for each player reading it.
  -- It keeps a dark backing: its pages are long reads.
  local open = game.tutorialOpen or {}
  local readers = {}
  for color in pairs(open) do readers[#readers + 1] = color end
  table.sort(readers)
  if #readers > 0 then
    local pages = Tutorial.pages(game)
    for _, color in ipairs(readers) do
      local n = open[color]
      local page = pages[n]
      local nav = {}
      if n > 1 then nav[#nav + 1] = { id = "cz-tutback", label = "Back" } end
      if n < #pages then nav[#nav + 1] = { id = "cz-tutnext", label = "Next" } end
      nav[#nav + 1] = { id = "cz-tutclose", label = "Close" }
      nav[#nav + 1] = { id = "cz-tuthide", label = "Hide button" }
      local navXml = buttonRows(nav, 13, 640)
      -- in the theme's menu style: its pages are long reads, so never clear
      local inner = text("cz_tut_title_" .. color, page[1], 22, 'fontStyle="Bold" color="' .. accent() .. '" preferredHeight="34"')
        .. text("cz_tut_body_" .. color, page[2], 16, 'alignment="UpperLeft" preferredHeight="330"')
        .. text("cz_tut_page_" .. color, "Page " .. n .. " of " .. #pages, 12, 'alignment="MiddleRight" color="#9AA4AE" preferredHeight="16"')
        .. navXml
      parts[#parts + 1] = sized((UI_.framed("cz_tutorial_" .. color, "menu", inner, 650, 430,
        ' visibility="' .. color .. '" rectAlignment="MiddleCenter"', 8)), UI_.scaleOf(game, color))
    end
  end

  -- On your turn: a choice waiting goes in the middle of the screen; the
  -- rest of what you can do sits in a bar just above your hand (its height is
  -- in Settings). The active player's Trade and Combat sit just above the
  -- bar, for every player at their own bar height and UI size, and only
  -- while there's something to count.
  if state.started and not state.winner then
    local acts = UI_.actions(game)
    local color = state.players[state.turn.active].color
    local scale = UI_.scaleOf(game, color)
    if acts.prompt then
      parts[#parts + 1] = centrePanel("cz_choice", color, acts.prompt, accent(), 18, nil, acts.choices, scale, "choice")
    end
    -- Other players' waiting choices (from events), each on their own screen.
    for seat, p in ipairs(state.players) do
      if seat ~= state.turn.active then
        local text, choices = UI_.promptFor(game, seat)
        if text then
          parts[#parts + 1] = centrePanel("cz_choice_" .. p.color, p.color, text, accent(), 18, nil, choices, UI_.scaleOf(game, p.color), "choice")
        end
      end
    end
    local bar, barHeight = buttonRows(acts.buttons, 12, 1100, { ["cz-playall"] = 17, ["cz-end"] = 17 })
    if acts.goals then -- the active player's secret goals, on their bar only
      bar = text("cz_goals", acts.goals, 12, 'alignment="MiddleCenter" color="#C8CED6" preferredHeight="18"' .. FX) .. bar
      barHeight = barHeight + 22
    end
    local barY = UI_.barY(game, color)
    parts[#parts + 1] = sized('<Panel id="cz_actions" visibility="' .. color .. '" width="1120" height="'
      .. barHeight .. '" rectAlignment="LowerCenter" offsetXY="0 ' .. barY .. '"' .. PANEL
      .. '><VerticalLayout spacing="4" childForceExpandHeight="false">' .. bar .. '</VerticalLayout></Panel>', scale)
    for _, p in ipairs(state.players) do
      local counters = turnCounters(game, p.color)
      if counters then
        local s = UI_.scaleOf(game, p.color)
        local y = UI_.barY(game, p.color) + (p.color == color and math.ceil(barHeight * s) or 0) + 8
        parts[#parts + 1] = sized('<Panel id="cz_counters_' .. p.color .. '" visibility="' .. p.color .. '"'
          .. ' width="400" height="52" rectAlignment="LowerCenter" offsetXY="0 ' .. y .. '"' .. PANEL .. '>' .. counters .. '</Panel>', s)
      end
    end
  end
  return table.concat(parts)
end

-- The buttons in the bottom-right corner: Rulebooks (when the rules list
-- some), the rules' own buttons (rules.ui.buttons), then Tidy table.
function UI_.cornerButtons(game)
  use(game)
  local xml = ""
  if game.rules.rulebooks and #game.rules.rulebooks > 0 then xml = xml .. smallButton("cz-rulebooks", "Rulebooks", 12) end
  for i, b in ipairs(game.rules.ui and game.rules.ui.buttons or {}) do
    xml = xml .. smallButton("cz-button-" .. i, b.label, 12)
  end
  return xml .. smallButton("cz-tidy", "Tidy table", 12)
end

-- Where a colour's action bar sits: the default, moved in their Settings.
function UI_.barY(game, color)
  local moved = game.state.view.barOffset and game.state.view.barOffset[color] or 0
  return UI_.ACTION_BAR_Y + moved
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

-- The icon images are registered once, before the first XML that uses them.
function UI_.refresh(game)
  if not game.assetsSet then
    UI.setCustomAssets(UI_.assets(game.rules))
    game.assetsSet = true
  end
  UI.setXml(UI_.xml(game))
end

return UI_
