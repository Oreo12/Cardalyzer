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

local UI_ = {}

local function escape(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- extra may set color= or alignment= itself; otherwise white, left-aligned.
local function text(id, words, size, extra)
  extra = extra or ""
  if not extra:find("color=", 1, true) then extra = extra .. ' color="#FFFFFF"' end
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

-- The active player's options. `prompt` is the first choice waiting (with
-- `choices`, its buttons), and `buttons` everything else they can do now.
function UI_.actions(game)
  local state = game.state
  local seat = state.turn.active
  local p = state.players[seat]
  local out = { prompt = nil, choices = {}, buttons = {} }
  local function add(list, id, label) list[#list + 1] = { id = id, label = label } end

  local prompt = p.prompts[1]
  if prompt then
    local more = #p.prompts > 1 and (" (+" .. (#p.prompts - 1) .. " more)") or ""
    out.prompt = Actions.promptText(game, prompt) .. more
    for _, t in ipairs(Actions.targets(game, seat, prompt)) do add(out.choices, "cz-pick-" .. t.value, t.label) end
    if prompt.optional then add(out.choices, "cz-done", prompt.kind == "reminder" and "Done" or "Skip / done") end
  end

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
        if open and pool >= (c.defense or 0) then
          add(out.buttons, "cz-hit-" .. other .. "-" .. uid, "Destroy " .. c.name .. " (" .. (c.defense or 0) .. ")")
        end
      end
    end
  end

  for _, uid in ipairs(Actions.inPlay(p)) do
    local c = game:cardOf(uid) -- a card copying another this turn shows that card's scrap ability
    if #c.scrapEffects > 0 then
      add(out.buttons, "cz-scrap-" .. uid, "Scrap " .. c.name .. ": " .. game.effects:describe(c.scrapEffects, c.text))
    end
  end

  add(out.buttons, "cz-end", "End Turn")
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

local ACCENT = "#E8B84A"
-- No panel backgrounds or borders: text and standalone buttons sit straight on the screen.
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
  return out
end

local function counter(id, icon, value, size)
  return '<Panel id="' .. id .. '" preferredWidth="' .. size .. '" preferredHeight="' .. size .. '">'
    .. '<Image image="' .. assetName(icon) .. '" preserveAspect="true" />'
    .. string.format('<Text id="%s_n" fontSize="%d" fontStyle="Bold" color="#FFFFFF" alignment="MiddleCenter"%s>%s</Text>',
      id, math.floor(size * 0.45), FX, escape(value))
    .. '</Panel>'
end

-- Button looks, bright enough to stand out on a dark table: gold for the main
-- action (Play all, End Turn, Play Game), light grey-blue for the rest.
-- normal|highlighted|pressed|disabled, then the text colour.
local STYLES = {
  primary = { "#E8B84A|#F6D27A|#C99A2E|#E8B84A80", "#1A1206" },
  secondary = { "#D6DEE8|#F0F4F8|#AEB9C6|#D6DEE880", "#14202C" },
}
-- The ids that get the primary look.
UI_.PRIMARY = { ["cz-playall"] = true, ["cz-end"] = true, ["cz-new"] = true, ["cz-again"] = true }

-- A standalone button, as wide as its label needs. Returns XML and width.
local function smallButton(id, label, size)
  size = size or 12
  local style = STYLES[UI_.PRIMARY[id] and "primary" or "secondary"]
  local width = math.max(60, math.floor(#label * size * 0.6) + 24)
  return string.format('<Button id="%s" onClick="Cardalyzer_onUI" preferredHeight="%d" preferredWidth="%d" fontSize="%d"'
    .. ' fontStyle="Bold" colors="%s" textColor="%s">%s</Button>',
    id, size + 14, width, size, style[1], style[2], escape(label)), width
end

-- Buttons in centred rows no wider than maxWidth. `bigger` lists ids drawn at
-- a larger size. Returns XML and its height.
local function buttonRows(list, size, maxWidth, bigger)
  local rows, row, used, rowSize = {}, {}, 0, size
  local sizes = {}
  for _, b in ipairs(list) do
    local s = (bigger and bigger[b.id]) and bigger[b.id] or size
    local xml, w = smallButton(b.id, b.label, s)
    if used > 0 and used + w > maxWidth then
      rows[#rows + 1], sizes[#rows + 1] = row, rowSize
      row, used, rowSize = {}, 0, size
    end
    row[#row + 1] = xml
    used = used + w + 6
    rowSize = math.max(rowSize, s)
  end
  if #row > 0 then rows[#rows + 1], sizes[#rows + 1] = row, rowSize end
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
UI_.BAR_STEP = 30 -- how far one press of a player's ▲/▼ moves their bar

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
      if c.defense then xml = xml .. counter("cz_base_" .. seat .. "_" .. i, "shield", c.defense, 30) end
    end
    for _, st in ipairs(rules.stats or {}) do
      local icon = UI_.iconFor(rules, st, "stat")
      local value = p.stats[st.key] or 0
      xml = xml .. (icon and counter("cz_stat_" .. seat .. "_" .. st.key, icon, value, 34)
        or text("cz_stat_" .. seat .. "_" .. st.key, (st.label or Util.titleCase(st.key)) .. " " .. value, 14, FX))
    end
  end
  local piles = text("cz_seat_" .. seat .. "_piles", "Deck " .. #p.deck .. " · Discard " .. #p.discard, 11,
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

-- The info panel, on the right: title, turn, the players, the last few
-- messages (see Game:notify; TTS draws
-- broadcasts behind custom UI, so they're shown here instead) and New Game,
-- which opens the setup menu. Returns its XML and its height in pixels.
function UI_.infoPanel(game)
  local state = game.state
  local rows, height = {}, 0
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 4 end

  row(text("cz_title", game.rules.name or "Cardalyzer", 18, 'fontStyle="Bold" alignment="MiddleRight" color="' .. ACCENT .. '"' .. FX), 24)
  local turn = UI_.turnLine(game)
  local th = wrappedHeight(turn, 14)
  row(text("cz_turn", turn, 14, 'fontStyle="Bold" alignment="MiddleRight" preferredHeight="' .. th .. '"' .. FX), th)
  for seat = 1, #state.players do row(seatRow(game, seat)) end
  for i, msg in ipairs(game.notices and game.notices.all or {}) do
    local h = wrappedHeight(msg, 12)
    row(text("cz_notice_" .. i, msg, 12, 'color="' .. ACCENT .. '" fontStyle="Italic" alignment="MiddleRight" preferredHeight="'
      .. h .. '"' .. FX), h)
  end
  row('<HorizontalLayout preferredHeight="28" childForceExpandWidth="false" childAlignment="MiddleRight">'
    .. smallButton("cz-setup", "New Game", 14) .. '</HorizontalLayout>', 28)

  return '<Panel id="cz_panel" width="' .. UI_.INFO_WIDTH .. '" height="' .. height .. '" rectAlignment="LowerRight" offsetXY="-12 '
    .. INFO_BOTTOM .. '"' .. PANEL .. '><VerticalLayout spacing="4" childForceExpandHeight="false">' .. table.concat(rows)
    .. '</VerticalLayout></Panel>', height
end

-- A plain centred panel (no background): a title, an optional extra row and
-- rows of standalone buttons. The setup menu, choices and game over use it.
local function centrePanel(id, visibility, title, titleColor, titleSize, extra, buttons)
  local rows, height = {}, 0
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 8 end
  local th = math.max(1, math.ceil(#title / 48)) * (titleSize + 8)
  row(text(id .. "_title", title, titleSize, 'fontStyle="Bold" alignment="MiddleCenter" preferredHeight="' .. th
    .. '" color="' .. titleColor .. '"' .. FX), th)
  if extra then row(extra[1], extra[2]) end
  local bx, bh = buttonRows(buttons, 13, 620)
  row(bx, bh)
  return '<Panel id="' .. id .. '" visibility="' .. visibility .. '" width="660" height="'
    .. height .. '" rectAlignment="MiddleCenter"' .. PANEL .. '><VerticalLayout spacing="8" childForceExpandHeight="false">'
    .. table.concat(rows) .. '</VerticalLayout></Panel>'
end

-- Player-count buttons (cz-players-<n>) for games that seat more than one
-- number of players. Only the host's clicks count (see main.lua).
function UI_.playersRow(game)
  local range = game.playerRange(game.rules)
  if range.min >= range.max then return nil end
  local state = game.state
  local current = state.nextPlayers or #state.players
  local xml = text("cz_players", "Players", 15, 'preferredWidth="80"' .. FX)
  for n = range.min, range.max do
    local b = smallButton("cz-players-" .. n, tostring(n), 14)
    if n == current then b = b:gsub('colors="[^"]*" textColor="[^"]*"', 'colors="' .. STYLES.primary[1] .. '" textColor="' .. STYLES.primary[2] .. '"') end
    xml = xml .. b
  end
  return '<HorizontalLayout spacing="6" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleCenter">'
    .. xml .. '</HorizontalLayout>'
end

-- The setup menu, in the middle of the screen for the player who pressed New
-- Game: the player count, Play Game (deals and closes the menu), Tutorial and
-- Close. Choices made here are kept for next time.
function UI_.setupPanel(game, color)
  local buttons = { { id = "cz-new", label = "Play Game" } }
  if Tutorial.buttonShown(game, color) then buttons[#buttons + 1] = { id = "cz-tutorial", label = "Tutorial" } end
  buttons[#buttons + 1] = { id = "cz-setupclose", label = "Close" }
  local players = UI_.playersRow(game)
  return centrePanel("cz_setup_" .. color, color, "New Game", ACCENT, 22, players and { players, 30 }, buttons)
end

function UI_.xml(game)
  local state = game.state
  local info, infoHeight = UI_.infoPanel(game)
  local parts = { info }

  -- Tidy table on its own, in the bottom right corner.
  parts[#parts + 1] = '<Panel id="cz_tidy" width="120" height="30" rectAlignment="LowerRight" offsetXY="-12 ' .. TIDY_Y .. '"' .. PANEL .. '>'
    .. '<HorizontalLayout childForceExpandWidth="false" childAlignment="MiddleRight">' .. smallButton("cz-tidy", "Tidy table", 12)
    .. '</HorizontalLayout></Panel>'

  -- A private message for one player, just above the info panel.
  local byColor = game.notices and game.notices.byColor or {}
  local colors = {}
  for color in pairs(byColor) do colors[#colors + 1] = color end
  table.sort(colors)
  for _, color in ipairs(colors) do
    local h = wrappedHeight(byColor[color], 13) + 6
    parts[#parts + 1] = '<Panel id="cz_notice_' .. color .. '" visibility="' .. color .. '" width="' .. UI_.INFO_WIDTH
      .. '" height="' .. h .. '" rectAlignment="LowerRight" offsetXY="-12 ' .. (INFO_BOTTOM + infoHeight + 6) .. '"' .. PANEL .. '>'
      .. text("cz_notice_text_" .. color, byColor[color], 13, 'alignment="MiddleRight" color="' .. ACCENT .. '"' .. FX)
      .. '</Panel>'
  end

  -- The setup menu, for each player who opened it.
  local setup = {}
  for color in pairs(game.setupOpen or {}) do setup[#setup + 1] = color end
  table.sort(setup)
  for _, color in ipairs(setup) do parts[#parts + 1] = UI_.setupPanel(game, color) end

  -- Game over: the winner, in the middle of the screen for everyone (except
  -- whoever has the setup menu open there), with Play Again? to set up the next.
  if state.winner then
    local who = {}
    for _, color in ipairs(Tutorial.allColors) do
      if not (game.setupOpen or {})[color] then who[#who + 1] = color end
    end
    local winner = state.players[state.winner]
    parts[#parts + 1] = centrePanel("cz_winner", table.concat(who, "|"), winner.name .. " wins!",
      UI_.seatColors[winner.color] or ACCENT, 34, nil, { { id = "cz-again", label = "Play Again?" } })
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
      parts[#parts + 1] = '<Panel id="cz_tutorial_' .. color .. '" visibility="' .. color .. '" width="680" height="400"'
        .. ' rectAlignment="MiddleCenter" color="#0E1620E6" padding="16 16 12 12"><VerticalLayout spacing="8" childForceExpandHeight="false">'
        .. text("cz_tut_title_" .. color, page[1], 22, 'fontStyle="Bold" color="' .. ACCENT .. '" preferredHeight="34"')
        .. text("cz_tut_body_" .. color, page[2], 16, 'alignment="UpperLeft" preferredHeight="270"')
        .. text("cz_tut_page_" .. color, "Page " .. n .. " of " .. #pages, 12, 'alignment="MiddleRight" color="#9AA4AE" preferredHeight="16"')
        .. navXml .. '</VerticalLayout></Panel>'
    end
  end

  -- On your turn: a choice waiting goes in the middle of the screen; the
  -- rest of what you can do sits in a bar just above your hand, with ▲/▼ to
  -- move it to suit your own hand size (remembered per colour). The active
  -- player's Trade and Combat sit just above the bar, for every player, each
  -- at their own bar height, and only while there's something to count.
  if state.started and not state.winner then
    local acts = UI_.actions(game)
    local color = state.players[state.turn.active].color
    if acts.prompt then
      parts[#parts + 1] = centrePanel("cz_choice", color, acts.prompt, ACCENT, 18, nil, acts.choices)
    end
    local buttons = {}
    for _, b in ipairs(acts.buttons) do buttons[#buttons + 1] = b end
    buttons[#buttons + 1] = { id = "cz-barup", label = "▲" }
    buttons[#buttons + 1] = { id = "cz-bardown", label = "▼" }
    local bar, barHeight = buttonRows(buttons, 12, 1100, { ["cz-playall"] = 17, ["cz-end"] = 17 })
    local barY = UI_.barY(game, color)
    parts[#parts + 1] = '<Panel id="cz_actions" visibility="' .. color .. '" width="1120" height="' .. barHeight
      .. '" rectAlignment="LowerCenter" offsetXY="0 ' .. barY .. '"' .. PANEL
      .. '><VerticalLayout spacing="4" childForceExpandHeight="false">' .. bar .. '</VerticalLayout></Panel>'
    for _, p in ipairs(state.players) do
      local counters = turnCounters(game, p.color)
      if counters then
        local y = UI_.barY(game, p.color) + (p.color == color and barHeight or 0) + 8
        parts[#parts + 1] = '<Panel id="cz_counters_' .. p.color .. '" visibility="' .. p.color .. '" width="400" height="52"'
          .. ' rectAlignment="LowerCenter" offsetXY="0 ' .. y .. '"' .. PANEL .. '>' .. counters .. '</Panel>'
      end
    end
  end
  return table.concat(parts)
end

-- Where a colour's action bar sits: the default, moved by their ▲/▼ presses.
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
