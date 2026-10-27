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
local Kits = require("engine.kits")
local Words = require("engine.words")

local UI_ = {}

-- The rules being drawn, so the small helpers below can read the theme.
-- UI_.xml (and every panel builder called on its own) sets it first.
local current = {}
local currentGame = nil
local function use(game)
  current = game.rules
  currentGame = game
end
local function accent() return Theme.of(current).accent end
-- The game's word for `key` (engine/words.lua; rules.ui.words renames them).
local function say(key, vars) return Words.say(current, key, vars) end

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
  use(game)
  local state = game.state
  if not state.started then return say("notStarted") end
  if state.winner then return say("wins", { name = Actions.winnerNames(game) }) end
  local active = state.players[state.turn.active]
  local phase = Actions.phase(game)
  if phase then return say("phaseLine", { n = state.turn.number, name = active.name, phase = phase.label or phase.key }) end
  return say("turnLine", { n = state.turn.number, name = active.name })
end

-- A seat's first waiting choice: its text and its option buttons (nil if none).
-- Any player can have one: events ask every player.
function UI_.promptFor(game, seat)
  local p = game.state.players[seat]
  local prompt = p.prompts[1]
  local choices = {}
  if not prompt then return nil, choices end
  use(game)
  local more = #p.prompts > 1 and say("more", { n = #p.prompts - 1 }) or ""
  for _, t in ipairs(Actions.targets(game, seat, prompt)) do
    choices[#choices + 1] = { id = "cz-pick-" .. t.value, label = t.label }
  end
  if prompt.optional then
    local word = prompt.kind == "reminder" and "done" or "skip"
    if prompt.kind == "react" then word = prompt.picked and "done" or "noReveal" end
    choices[#choices + 1] = { id = "cz-done", label = say(word) }
  end
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

  local canPlay = Actions.playAllCount(game, seat)
  if canPlay > 0 and not Actions.handBlocked(game, seat) then add(out.buttons, "cz-playall", say("playAll", { n = canPlay })) end

  local key, label = Actions.resourceFor(game.rules, "attack")
  local pool = key and Actions.phaseAllows(game, "attack") and p.resources[key] or 0
  if pool > 0 then
    for _, other in ipairs(game:opponentsOf(seat)) do
      local guards = Actions.guards(game, other)
      local victim = state.players[other]
      if #guards == 0 then
        add(out.buttons, "cz-attack-" .. other, say("attack", { name = victim.name, n = pool, resource = label }))
      end
      for _, uid in ipairs(victim.bases) do
        local c = game.cards:get(State.cardId(state, uid))
        local open = #guards == 0 or Util.indexOf(guards, uid)
        local defense = Actions.defenseOf(game, other, uid)
        if open and pool >= defense and Actions.typeDef(game, c).target ~= false then
          add(out.buttons, "cz-hit-" .. other .. "-" .. uid, say("destroy", { card = c.name, n = defense }))
        end
      end
    end
  end

  for _, uid in ipairs(Actions.inPlay(p)) do
    local c = game:cardOf(uid) -- a card copying another this turn shows that card's scrap ability
    if Actions.canScrap(game, seat, uid) then -- (some need an ally in play first)
      add(out.buttons, "cz-scrap-" .. uid, say("scrap", { card = c.name, effects = game.effects:describe(c.scrapEffects, c.text) }))
    end
  end

  for _, c in ipairs(Actions.callable(game, seat)) do
    add(out.buttons, "cz-call-" .. c.uid, say("call", { card = game:cardOf(c.uid).name }))
  end
  for _, a in ipairs(Actions.activatable(game, seat)) do
    local name = game:cardOf(a.uid).name
    add(out.buttons, "cz-use-" .. a.uid, a.def.text and say("useWith", { card = name, text = a.def.text }) or say("use", { card = name }))
  end
  local goalLabel = game.rules.objectives and game.rules.objectives.label or "goal"
  for _, uid in ipairs(Actions.completable(game, seat)) do
    add(out.buttons, "cz-goal-" .. uid, say("complete", { card = game:cardOf(uid).name }))
  end
  local phases = game.rules.turn and game.rules.turn.phases
  if phases and (state.turn.phase or 1) < #phases then
    local nextPhase = phases[(state.turn.phase or 1) + 1]
    add(out.buttons, "cz-phase", say("nextPhase", { phase = nextPhase.label or nextPhase.key }))
  end
  add(out.buttons, "cz-end", say("endTurn"))
  if #p.objectives > 0 then
    local names = {}
    for _, uid in ipairs(p.objectives) do names[#names + 1] = game:cardOf(uid).name end
    out.goals = say("yourGoals", { label = goalLabel:lower(), list = table.concat(names, ", ") })
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

-- Built-in symbols, hosted with the engine. The theme's symbols.folder (or
-- the older rules.ui.iconBaseUrl) points elsewhere: a folder holding
-- coin.png, reticle.png, heart.png and shield.png. symbols.pictures replaces
-- any one of them, or adds a symbol of its own: { [name] = URL }.
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
  local sym = Theme.of(rules).symbols
  local base = sym.folder or (rules.ui and rules.ui.iconBaseUrl) or UI_.ICON_BASE
  local out, seen = {}, {}
  local function add(icon)
    if icon and not seen[icon] then
      seen[icon] = true
      local full = (icon:match("^https?://") or icon:match("^file://")) and icon
        or sym.pictures[icon] or (base .. icon .. ".png")
      out[#out + 1] = { name = assetName(icon), url = full }
    end
  end
  for _, name in ipairs(UI_.ICONS) do add(name) end
  for name in pairs(sym.pictures) do add(name) end
  add(sym.defense)
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

-- A counter in the theme's symbol style: its number over the symbol, or
-- (symbols.number = "right") beside it. Returns XML.
local function counter(id, icon, value, size)
  local sym = Theme.of(current).symbols
  local fx = sym.outline and (' outline="' .. sym.outline .. '" outlineSize="1.5 -1.5"') or ""
  local image = '<Image image="' .. assetName(icon) .. '" color="' .. sym.tint .. '" preserveAspect="true"'
  local function number(extra)
    return string.format('<Text id="%s_n" fontSize="%d" fontStyle="%s" color="%s"%s%s>%s</Text>',
      id, math.floor(size * sym.textSize), sym.textStyle, sym.text, extra, fx, escape(value))
  end
  if sym.number == "right" then
    local w = math.floor(size * sym.textSize * 0.62 * #tostring(value)) + 6
    return '<HorizontalLayout id="' .. id .. '" spacing="2" preferredWidth="' .. (size + w + 2) .. '" preferredHeight="' .. size
      .. '" childForceExpandWidth="false">' .. image .. ' preferredWidth="' .. size .. '" />'
      .. number(' alignment="MiddleLeft" preferredWidth="' .. w .. '"') .. '</HorizontalLayout>'
  end
  return '<Panel id="' .. id .. '" preferredWidth="' .. size .. '" preferredHeight="' .. size .. '">'
    .. image .. ' />' .. number(' alignment="MiddleCenter"') .. '</Panel>'
end
local function symbolSize(which) return Theme.of(current).symbols.sizes[which] end

-- What each button does, shown when the mouse is over it. rules.ui.tooltips
-- adds or replaces any of them ({ [id] = text }; false for none). A button
-- given its own tooltip (an option's `about`) uses that instead.
local function kitName() return current.kitName or "kit" end
local TIPS = {
  ["cz-setup"] = function() return "Set up and deal a new game (host only)." end,
  ["cz-settings"] = function() return "Your own UI size and action bar height." end,
  ["cz-new"] = function() return "Deal a new game with these choices." end,
  ["cz-tutorial"] = function() return "A short guide to playing here." end,
  ["cz-setupclose"] = function() return "Close this menu. Your choices are kept." end,
  ["cz-tidy"] = function() return "Put every card back where the game has it, if any got knocked around." end,
  ["cz-rulebooks"] = function() return "Put the rulebooks on the table beside the game, or put them away." end,
  ["cz-playall"] = function() return "Play every card in your hand." end,
  ["cz-end"] = function() return "End your turn: discard your cards in play and your hand, then draw a new hand." end,
  ["cz-again"] = function() return "Set up the next game." end,
  ["cz-settingsclose"] = function() return "Close Settings." end,
  ["cz-uismaller"] = function() return "Make all of the UI smaller, just for you." end,
  ["cz-uibigger"] = function() return "Make all of the UI bigger, just for you." end,
  ["cz-barup"] = function() return "Move your action bar up." end,
  ["cz-bardown"] = function() return "Move your action bar down." end,
  ["cz-barreset"] = function() return "Put your action bar back where it started." end,
  ["cz-kits-off"] = function() return "Everyone starts with the same starting deck." end,
  ["cz-kits-on"] = function()
    return "Each player picks their own " .. kitName() .. ": a premade one, a random one, or a custom mix."
  end,
  ["cz-kitmenu"] = function() return "Pick your own " .. kitName() .. " for the next game." end,
  ["cz-kitsave"] = function() return "Keep this choice and go back." end,
  ["cz-kitcancel"] = function() return "Go back without changing your choice." end,
  ["cz-kitmode-premade"] = function() return "Pick one of the premade " .. kitName() .. "s." end,
  ["cz-kitmode-random"] = function()
    return "Get a random premade " .. kitName() .. " (one nobody else picked) when the game starts."
  end,
  ["cz-kitmode-custom"] = function() return "Build your own from the parts of the premade " .. kitName() .. "s." end,
  ["cz-hideui"] = function()
    return "Hide Cardalyzer's panels, just for you, to get at TTS's own menus. Show Cardalyzer brings them back;"
      .. " so does a key you can set in Options → Game Keys."
  end,
  ["cz-menuat-middle"] = function() return "Menus and choices in the middle of your screen." end,
  ["cz-menuat-left"] = function() return "Menus and choices on the left of your screen, clear of TTS's own menus." end,
  ["cz-menuat-right"] = function() return "Menus and choices on the right of your screen, clear of TTS's own menus." end,
  ["cz-menuat-top"] = function() return "Menus and choices at the top of your screen." end,
}
for _, kind in ipairs({ "setup", "kit", "settings", "tutorial", "winner", "choice" }) do
  TIPS["cz-tuck-" .. kind] = function() return "Tuck this away, just for you. A Show button by Tidy table brings it back." end
end
local function tipFor(id)
  local own = current.ui and current.ui.tooltips and current.ui.tooltips[id]
  if own ~= nil then return own or nil end
  return TIPS[id] and TIPS[id]() or nil
end

-- A standalone button, as wide as its label needs. Its look comes from the
-- theme: primary for the main actions (the theme's primary ids), `kind` if
-- given ("selected" for a chosen option), else secondary. Returns XML and width.
local function smallButton(id, label, size, kind, width, tooltip)
  size = size or 12
  kind = kind or (Theme.isPrimary(current, id) and "primary" or "secondary")
  local colors, textColor = Theme.button(current, kind)
  width = width or math.max(60, math.floor(#label * size * 0.6) + 24)
  tooltip = tooltip or tipFor(id)
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
local INFO_BOTTOM = 112 -- the info panel's bottom edge
UI_.ACTION_BAR_Y = 210 -- the action bar's bottom edge by default: just above the on-screen hand
UI_.BAR_STEP = 30 -- how far one press of Up / Down in Settings moves a player's bar

-- A panel's place (theme positions): its rectAlignment and offsetXY,
-- `dy` added to its y.
local function place(which, dy)
  local at = Theme.of(current).positions[which]
  return ' rectAlignment="' .. at.anchor .. '" offsetXY="' .. (at.x or 0) .. ' ' .. ((at.y or 0) + (dy or 0)) .. '"'
end
UI_.place = place

-- Content of a panel anchored on the left reads from the left.
local function leftSide(xml, which)
  if not Theme.of(current).positions[which].anchor:find("Left") then return xml end
  return (xml:gsub('alignment="MiddleRight"', 'alignment="MiddleLeft"'):gsub('Alignment="MiddleRight"', 'Alignment="MiddleLeft"'))
end

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
  local name = (active and "▶ " or "") .. p.name .. (p.out and say("out") or "")
  local xml = text("cz_seat_" .. seat, name, 16, 'color="' .. (UI_.seatColors[p.color] or "#FFFFFF") .. '"'
    .. (active and ' fontStyle="Bold"' or "") .. ' preferredWidth="110"' .. FX)
  if not p.out then
    for i, uid in ipairs(p.bases) do
      local c = game.cards:get(State.cardId(state, uid))
      if c.defense then
        xml = xml .. counter("cz_base_" .. seat .. "_" .. i, Theme.of(rules).symbols.defense, Actions.defenseOf(game, seat, uid), symbolSize("base"))
      end
    end
    for _, st in ipairs(rules.stats or {}) do
      local icon = UI_.iconFor(rules, st, "stat")
      local value = p.stats[st.key] or 0
      xml = xml .. (icon and counter("cz_stat_" .. seat .. "_" .. st.key, icon, value, symbolSize("seat"))
        or text("cz_stat_" .. seat .. "_" .. st.key, (st.label or Util.titleCase(st.key)) .. " " .. value, 14, FX))
    end
  end
  -- only in a game that dealt objectives (their set may be switched off)
  local goals = rules.objectives and #p.completed + #p.objectives > 0 and say("goalsCount", { label = rules.objectives.label or "Goals",
    done = #p.completed, total = rules.objectives.toWin or #p.completed + #p.objectives }) or ""
  local score = rules.win and rules.win.type == "points" and say(Actions.score(game, seat) == 1 and "scoreOne" or "score", { n = Actions.score(game, seat) }) or ""
  local piles = text("cz_seat_" .. seat .. "_piles", say("piles", { deck = #p.deck, discard = #p.discard }) .. goals .. score, 11,
    'color="#C8CED6" alignment="MiddleRight" preferredHeight="14"' .. FX)
  local h = math.max(symbolSize("seat"), symbolSize("base"), 20)
  return '<HorizontalLayout spacing="4" preferredHeight="' .. h .. '" childForceExpandWidth="false" childAlignment="MiddleRight">'
    .. xml .. '</HorizontalLayout>' .. piles, h + 14 + 4
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
      xml = xml .. (icon and counter(id, icon, value, symbolSize("turn"))
        or text(id, (r.label or Util.titleCase(r.key)) .. " " .. value, 18, 'fontStyle="Bold"' .. FX))
    end
  end
  if xml == "" then return nil end
  return '<HorizontalLayout spacing="12" preferredHeight="' .. symbolSize("turn") .. '" childForceExpandWidth="false" childAlignment="MiddleCenter">'
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
  local pool = game.rules.win and game.rules.win.endWhen and game.rules.win.endWhen.pool
  if pool and state.started and state.pool then
    local label = pool.key
    for _, st in ipairs(game.rules.stats or {}) do if st.key == pool.key then label = st.label or st.key end end
    row(text("cz_pool", say("pool", { n = math.max(0, state.pool), label = label }), 13, 'alignment="MiddleRight" color="' .. accent()
      .. '" preferredHeight="18"' .. FX), 18)
  end
  for seat = 1, #state.players do row(seatRow(game, seat)) end
  for i, msg in ipairs(game.notices and game.notices.all or {}) do
    local h = wrappedHeight(msg, 12)
    row(text("cz_notice_" .. i, msg, 12, 'color="' .. accent() .. '" fontStyle="Italic" alignment="MiddleRight" preferredHeight="'
      .. h .. '"' .. FX), h)
  end
  if game.rules.kits and game:kitsOn() then
    row('<HorizontalLayout preferredHeight="28" childForceExpandWidth="false" childAlignment="MiddleRight">'
      .. smallButton("cz-kitmenu", say("yourKit", { kit = game.rules.kitName or "kit" }), 14) .. '</HorizontalLayout>', 28)
  end
  row('<HorizontalLayout spacing="6" preferredHeight="28" childForceExpandWidth="false" childAlignment="MiddleRight">'
    .. smallButton("cz-settings", say("settings"), 14) .. smallButton("cz-setup", say("newGame"), 14) .. '</HorizontalLayout>', 28)

  local at = Theme.of(current).positions.info
  local y = at.y or bottom or INFO_BOTTOM
  local xml, _, h = UI_.framed("cz_panel" .. (suffix or ""), "info", table.concat(rows), UI_.INFO_WIDTH, height - 4,
    (attrs or "") .. ' rectAlignment="' .. at.anchor .. '" offsetXY="' .. (at.x or 0) .. ' ' .. y .. '"')
  return leftSide(xml, "info"), h
end

-- The title at the top of the info panel: the theme's title picture, or the
-- game's name, in the theme's "title" panel style. Returns XML and height.
function UI_.titleBox(game)
  use(game)
  local theme = Theme.of(game.rules)
  local t = theme.title
  local inner, h = nil, nil
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

-- Where a player's menus and choices go (Settings → Menus): the theme's
-- `menus` position (middle), or the left, right or top of the screen, clear
-- of TTS's own menus, which open in the middle.
UI_.MENU_SPOTS = {
  left = { anchor = "MiddleLeft", x = 80, y = 0 },
  right = { anchor = "UpperRight", x = -20, y = -130 },
  top = { anchor = "UpperCenter", x = 0, y = -80 },
}
function UI_.menuSpot(game, color)
  local where = game.state.view.menuAt and game.state.view.menuAt[color]
  return where and UI_.MENU_SPOTS[where] and where or "middle"
end
local function menuPlace(visibility)
  local where = currentGame and not visibility:find("|", 1, true) and UI_.menuSpot(currentGame, visibility)
  local at = where and UI_.MENU_SPOTS[where]
  if not at then return place("menus") end
  return ' rectAlignment="' .. at.anchor .. '" offsetXY="' .. at.x .. ' ' .. at.y .. '"'
end

-- Is a panel of this kind tucked away by this player (its Hide button)?
function UI_.tucked(game, color, kind)
  local t = game.state.view.tucked and game.state.view.tucked[color]
  return t and t[kind] == true or false
end
-- Has this player hidden all of Cardalyzer's UI (Hide UI, or their hotkey)?
function UI_.hidden(game, color)
  return game.state.view.uiHidden and game.state.view.uiHidden[color] == true or false
end
local function hideButton(kind) return { id = "cz-tuck-" .. kind, label = say("hide") } end

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
    ' visibility="' .. visibility .. '"' .. menuPlace(visibility), 8)), scale)
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
  for n = range.min, range.max do
    list[#list + 1] = { id = "cz-players-" .. n, label = tostring(n), on = n == chosen, tooltip = "Deal the next game for " .. n .. " players." }
  end
  return UI_.optionRow("cz_players", say("players"), list)
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
-- The grid's full width: the label column and every cell (`columns`
-- cells, default the theme's).
function UI_.gridWidth(columns)
  local g = Theme.of(current).grid
  return g.label + 6 + cellWidth(columns or g.columns)
end

-- Options laid out on the grid over as many rows as they need, `label` on
-- the first. Returns a list of rows.
function UI_.optionRows(id, label, options, columns)
  columns = columns or Theme.of(current).grid.columns
  local rows, row, used = {}, {}, 0
  for _, o in ipairs(options) do
    local n = math.min(cellsFor(o.label), columns)
    if used > 0 and used + n > columns then rows[#rows + 1] = row; row = {}; used = 0 end
    row[#row + 1] = o
    used = used + n
  end
  if #row > 0 then rows[#rows + 1] = row end
  local out = {}
  for i, r in ipairs(rows) do out[i] = UI_.optionRow(id .. "_" .. i, i == 1 and label or "", r) end
  return out
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
  return UI_.optionRow("cz_opening", game.rules.openingLabel or say("startingHands"), list)
end

-- The set toggles (cz-set-<key>), when the rules list sets, four to a row.
-- Returns a list of rows.
function UI_.setRows(game)
  local sets = game.rules.sets or {}
  if #sets < 2 then return {} end
  local inPlay = game:setsInPlay()
  local list = {}
  for _, set in ipairs(sets) do
    local tip = set.about or ((set.always and "Always in: " or "Shuffle in ") .. "the " .. set.label .. " cards.")
    list[#list + 1] = { id = "cz-set-" .. set.key, label = set.label, on = inPlay[set.key] == true, tooltip = tip }
  end
  return UI_.optionRows("cz_sets", say("sets"), list)
end

-- The supply choice (cz-supply-<i>; 0 is random), when rules.supply lists presets.
function UI_.supplyRows(game)
  local supply = game.rules.supply
  if not supply or not supply.presets or #supply.presets == 0 then return {} end
  local chosen = game:setupChoice("supply") or supply.default or 0
  local list = { { id = "cz-supply-0", label = say("random"), on = chosen == 0,
    tooltip = "Lay out " .. (supply.count or 10) .. " piles picked at random." } }
  for i, preset in ipairs(supply.presets) do
    list[#list + 1] = { id = "cz-supply-" .. i, label = preset.label, on = chosen == i, tooltip = preset.about }
  end
  return UI_.optionRows("cz_supply", supply.label or say("supply"), list)
end

function UI_.setupPanel(game, color)
  use(game)
  local buttons = { { id = "cz-new", label = say("playGame") } }
  if Tutorial.buttonShown(game, color) then buttons[#buttons + 1] = { id = "cz-tutorial", label = say("tutorial") } end
  buttons[#buttons + 1] = { id = "cz-setupclose", label = say("close") }
  buttons[#buttons + 1] = hideButton("setup")
  local rows, height = {}, 0
  local function add(r)
    if not r then return end
    rows[#rows + 1] = r
    height = height + 30 + (#rows > 1 and 8 or 0)
  end
  add(UI_.playersRow(game))
  add(UI_.openingRow(game))
  if game.rules.kits and #game.rules.kits > 0 then
    local on = game:kitsOn()
    add(UI_.optionRow("cz_kits", game.rules.kitLabel or say("startingDecks"), {
      { id = "cz-kits-off", label = say("standard"), on = not on },
      { id = "cz-kits-on", label = game.rules.kitName or "Kit", on = on },
    }))
    if on then add(UI_.kitSummaryRow(game)) end
  end
  for _, r in ipairs(UI_.setRows(game)) do add(r) end
  for _, r in ipairs(UI_.supplyRows(game)) do add(r) end
  -- rules.ui.setupMenu(game, color, menu, UI) may change the menu (its
  -- title, its rows of XML, each rowHeight tall, and its buttons) or return
  -- XML of its own to draw instead. See README, "Customising the UI".
  local menu = { title = say("setupTitle"), rows = rows, rowHeight = 30, buttons = buttons }
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

-- Who's playing which kit next game: "White: The Union · Red: Random".
function UI_.kitSummaryRow(game)
  use(game)
  local count = game.state.nextPlayers or #game.state.players
  local parts = {}
  for seat = 1, count do
    local color = game.rules.seats[seat].color
    parts[#parts + 1] = color .. ": " .. Kits.summary(game, Kits.choiceOf(game, color))
  end
  local g = Theme.of(current).grid
  return '<HorizontalLayout spacing="6" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleLeft">'
    .. text("cz_kits_who_label", "", 13, 'preferredWidth="' .. g.label .. '"')
    .. text("cz_kits_who", table.concat(parts, "  ·  "), 13, 'color="#C8CED6" preferredWidth="' .. cellWidth(g.columns) .. '"' .. FX)
    .. '</HorizontalLayout>'
end

-- Rough height of `words` wrapped to `width` pixels at font `size`.
local function textHeight(words, width, size)
  local lines = 0
  for line in (words .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + math.max(1, math.ceil(#line * size * 0.5 / width))
  end
  return lines * (size + 5)
end

-- A player's kit menu (rules.kitName, e.g. "Command Deck"): premade, random
-- or custom, then the kits or the custom parts to pick from, then Save and
-- go back. Drawn on the menu grid, six cells wide.
UI_.KIT_COLUMNS = 6
function UI_.kitPanel(game, color)
  use(game)
  local rules = game.rules
  local draft = Kits.draft(game, color)
  local columns = UI_.KIT_COLUMNS
  local gridWidth = UI_.gridWidth(columns)
  local rows, height = {}, 0
  local function add(xml, h)
    rows[#rows + 1] = xml
    height = height + (h or 30) + (#rows > 1 and 8 or 0)
  end
  local function addRows(list) for _, r in ipairs(list) do add(r) end end
  local function note(id, words)
    local w = cellWidth(columns)
    local h = textHeight(words, w, 13)
    local g = Theme.of(current).grid
    add('<HorizontalLayout spacing="6" preferredHeight="' .. h .. '" childForceExpandWidth="false" childAlignment="UpperLeft">'
      .. text(id .. "_label", "", 13, 'preferredWidth="' .. g.label .. '"')
      .. text(id, words, 13, 'alignment="UpperLeft" color="#C8CED6" preferredWidth="' .. w .. '" preferredHeight="' .. h .. '"' .. FX)
      .. '</HorizontalLayout>', h)
  end

  local modes = { { id = "cz-kitmode-premade", label = say("premade"), on = draft.mode == "premade" },
    { id = "cz-kitmode-random", label = say("random"), on = draft.mode == "random" } }
  if rules.kitParts then modes[#modes + 1] = { id = "cz-kitmode-custom", label = say("custom"), on = draft.mode == "custom" } end
  addRows(UI_.optionRows("cz_kitmode", say("choose"), modes, columns))

  if draft.mode == "premade" then
    local list = {}
    for _, kit in ipairs(rules.kits) do
      list[#list + 1] = { id = "cz-kitpick-" .. kit.key, label = kit.label, on = draft.kit == kit.key, tooltip = Kits.describe(game, kit) }
    end
    addRows(UI_.optionRows("cz_kitpick", rules.kitName or "Kit", list, columns))
    local kit = Kits.byKey(rules, draft.kit)
    if kit then note("cz_kit_about", kit.label .. ". " .. Kits.describe(game, kit)) end
  elseif draft.mode == "random" then
    note("cz_kit_about", say("kitRandomNote", { kit = kitName() }))
  else
    for i, part in ipairs(rules.kitParts) do
      local chosen = draft.parts[part.key]
      local list = {}
      for _, o in ipairs(Kits.partOptions(game, part)) do
        local on = part.by == "kit" and chosen == o.value or (type(chosen) == "table" and Util.indexOf(chosen, o.value) ~= nil)
        list[#list + 1] = { id = "cz-kitpart-" .. i .. "-" .. o.value, label = o.label, on = on and true or false, tooltip = o.tooltip }
      end
      local label = part.label .. ((part.count or 1) > 1 and (" (" .. part.count .. ")") or "")
      addRows(UI_.optionRows("cz_kitpart_" .. i, label, list, columns))
    end
    note("cz_kit_about", say("kitCustomNote"))
  end
  addRows({ UI_.optionRow("cz_kit_buttons_" .. color, "", {
    { id = "cz-kitsave", label = say("saveAndBack") }, { id = "cz-kitcancel", label = say("cancel") }, hideButton("kit") }) })

  local width = gridWidth + 20
  local inset = math.floor((width - gridWidth) / 2)
  local extra = { '<VerticalLayout padding="' .. inset .. ' 0 0 0" spacing="8" preferredHeight="' .. height
    .. '" childForceExpandHeight="false">' .. table.concat(rows) .. '</VerticalLayout>', height }
  return centrePanel("cz_kitmenu_" .. color, color, rules.kitName or "Kit", accent(), 22, extra, {}, UI_.scaleOf(game, color), "menu", width)
end

-- The settings menu, just for the player who opened it: their UI size and
-- where their action bar sits (to clear their own on-screen hand).
function UI_.settingsPanel(game, color)
  use(game)
  local scale = UI_.scaleOf(game, color)
  local moved = game.state.view.barOffset and game.state.view.barOffset[color] or 0
  local function settingRow(id, label, value, buttons)
    local xml = text(id, label, 15, 'preferredWidth="130" alignment="MiddleRight"' .. FX)
    for _, b in ipairs(buttons) do xml = xml .. smallButton(b[1], b[2], 14, b[3]) end
    if value then xml = xml .. text(id .. "_value", value, 15, 'preferredWidth="70" alignment="MiddleLeft" fontStyle="Bold"' .. FX) end
    return '<HorizontalLayout spacing="6" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleCenter">'
      .. xml .. '</HorizontalLayout>'
  end
  local rows = settingRow("cz_set_ui_" .. color, say("uiSize"), math.floor(scale * 100 + 0.5) .. "%",
      { { "cz-uismaller", "−" }, { "cz-uibigger", "+" } })
    .. settingRow("cz_set_bar_" .. color, say("actionBar"), (moved > 0 and "+" or "") .. moved,
      { { "cz-barup", say("up") }, { "cz-bardown", say("down") }, { "cz-barreset", say("reset") } })
  local at = UI_.menuSpot(game, color)
  local spots = {}
  for _, where in ipairs({ "middle", "left", "right", "top" }) do
    spots[#spots + 1] = { "cz-menuat-" .. where, say(where), at == where and "selected" or "secondary" }
  end
  rows = rows .. settingRow("cz_set_menus_" .. color, say("menus"), nil, spots)
  return centrePanel("cz_settings_" .. color, color, say("settings"), accent(), 22, { rows, 114 },
    { { id = "cz-settingsclose", label = say("close") }, hideButton("settings") }, scale)
end

function UI_.xml(game)
  use(game)
  local state = game.state
  local parts = {}

  -- The info panel and Tidy table (bottom right), once per UI size in use.
  -- Tidy table sits clear of TTS's own Notes button; the info panel above it.
  local hiddenFor = {}
  for _, color in ipairs(Tutorial.allColors) do
    if UI_.hidden(game, color) then hiddenFor[color] = true end
  end
  local function shown(color) return not hiddenFor[color] end
  local groups = UI_.scaleGroups(game, next(hiddenFor) and hiddenFor or nil)
  local infoTop = {}
  local positions = Theme.of(game.rules).positions
  local corner = positions.corner
  for i, g in ipairs(groups) do
    local vis, suffix = groupAttrs(groups, i)
    -- the info panel: at its own y, or just above the corner buttons
    local infoBottom = positions.info.y or ((corner.y or 0) + math.ceil(42 * g.scale))
    local info, h = UI_.infoPanel(game, suffix, vis, infoBottom)
    parts[#parts + 1] = sized(info, g.scale)
    parts[#parts + 1] = sized(leftSide('<Panel id="cz_tidy' .. suffix .. '"' .. vis .. ' width="' .. UI_.INFO_WIDTH .. '" height="30"'
      .. place("corner") .. PANEL .. '><HorizontalLayout spacing="6" childForceExpandWidth="false" childAlignment="MiddleRight">'
      .. UI_.cornerButtons(game) .. '</HorizontalLayout></Panel>', "corner"), g.scale)
    for _, color in ipairs(g.colors) do infoTop[color] = { bottom = infoBottom, top = infoBottom + math.ceil(h * g.scale) } end
  end

  -- A private message for one player, just above the info panel.
  local byColor = game.notices and game.notices.byColor or {}
  local colors = {}
  for color in pairs(byColor) do
    if shown(color) then colors[#colors + 1] = color end
  end
  table.sort(colors)
  local info = positions.info
  for _, color in ipairs(colors) do
    local h = wrappedHeight(byColor[color], 13) + 6
    -- just past the info panel: above it when it hangs from the bottom of the
    -- screen, below it when it hangs from the top
    local at = infoTop[color] or { bottom = INFO_BOTTOM, top = INFO_BOTTOM }
    local y = info.anchor:find("Upper") and (at.bottom - (at.top - at.bottom) - 6) or (at.top + 6)
    parts[#parts + 1] = sized(leftSide('<Panel id="cz_notice_' .. color .. '" visibility="' .. color .. '"'
      .. ' width="' .. UI_.INFO_WIDTH .. '" height="' .. h .. '" rectAlignment="' .. info.anchor .. '" offsetXY="' .. (info.x or 0) .. ' '
      .. y .. '"' .. PANEL .. '>'
      .. text("cz_notice_text_" .. color, byColor[color], 13, 'alignment="MiddleRight" color="' .. accent() .. '"' .. FX)
      .. '</Panel>', "info"), UI_.scaleOf(game, color))
  end

  -- The setup, kit and settings menus, for each player who opened one. A
  -- player's kit menu covers their setup menu until they go back.
  local kitOpen = game.kitMenuOpen or {}
  local setupOpen = {}
  for color in pairs(game.setupOpen or {}) do
    if not kitOpen[color] then setupOpen[color] = true end
  end
  for _, which in ipairs({ { setupOpen, UI_.setupPanel, "setup" }, { kitOpen, UI_.kitPanel, "kit" },
    { game.settingsOpen, UI_.settingsPanel, "settings" } }) do
    local open = {}
    for color in pairs(which[1] or {}) do
      if shown(color) and not UI_.tucked(game, color, which[3]) then open[#open + 1] = color end
    end
    table.sort(open)
    for _, color in ipairs(open) do parts[#parts + 1] = which[2](game, color) end
  end

  -- Game over: the winner, in the middle of the screen for everyone (except
  -- whoever has the setup menu open there), with Play Again? to set up the next.
  -- One per player, so each can tuck it away or have it where they keep menus.
  if state.winner then
    local winner = state.players[state.winner]
    for _, color in ipairs(Tutorial.allColors) do
      if not (game.setupOpen and game.setupOpen[color]) and shown(color) and not UI_.tucked(game, color, "winner") then
        parts[#parts + 1] = centrePanel("cz_winner_" .. color, color, say("wins", { name = Actions.winnerNames(game) }),
          UI_.seatColors[winner.color] or accent(), 34, nil, { { id = "cz-again", label = say("playAgain") }, hideButton("winner") },
          UI_.scaleOf(game, color))
      end
    end
  end

  -- The tutorial, in the middle of the screen, for each player reading it.
  -- It keeps a dark backing: its pages are long reads.
  local open = game.tutorialOpen or {}
  local readers = {}
  for color in pairs(open) do
    if shown(color) and not UI_.tucked(game, color, "tutorial") then readers[#readers + 1] = color end
  end
  table.sort(readers)
  if #readers > 0 then
    local pages = Tutorial.pages(game)
    for _, color in ipairs(readers) do
      local n = open[color]
      local page = pages[n]
      local nav = {}
      if n > 1 then nav[#nav + 1] = { id = "cz-tutback", label = say("back") } end
      if n < #pages then nav[#nav + 1] = { id = "cz-tutnext", label = say("next") } end
      nav[#nav + 1] = { id = "cz-tutclose", label = say("close") }
      nav[#nav + 1] = { id = "cz-tuthide", label = say("hideButton") }
      nav[#nav + 1] = hideButton("tutorial")
      local navXml = buttonRows(nav, 13, 640)
      -- in the theme's menu style: its pages are long reads, so never clear
      local inner = text("cz_tut_title_" .. color, page[1], 22, 'fontStyle="Bold" color="' .. accent() .. '" preferredHeight="34"')
        .. text("cz_tut_body_" .. color, page[2], 16, 'alignment="UpperLeft" preferredHeight="330"')
        .. text("cz_tut_page_" .. color, say("page", { n = n, total = #pages }), 12, 'alignment="MiddleRight" color="#9AA4AE" preferredHeight="16"')
        .. navXml
      parts[#parts + 1] = sized((UI_.framed("cz_tutorial_" .. color, "menu", inner, 650, 430,
        ' visibility="' .. color .. '"' .. menuPlace(color), 8)), UI_.scaleOf(game, color))
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
    local function choice(id, who, words, choices, k)
      if not shown(who) or UI_.tucked(game, who, "choice") then return end
      local list = {}
      for _, c in ipairs(choices) do list[#list + 1] = c end
      list[#list + 1] = hideButton("choice")
      parts[#parts + 1] = centrePanel(id, who, words, accent(), 18, nil, list, k, "choice")
    end
    if acts.prompt then choice("cz_choice", color, acts.prompt, acts.choices, scale) end
    -- Other players' waiting choices (from events), each on their own screen.
    for seat, p in ipairs(state.players) do
      if seat ~= state.turn.active then
        local text, choices = UI_.promptFor(game, seat)
        if text then choice("cz_choice_" .. p.color, p.color, text, choices, UI_.scaleOf(game, p.color)) end
      end
    end
    local bar, barHeight = buttonRows(acts.buttons, 12, 1100, { ["cz-playall"] = 17, ["cz-end"] = 17 })
    if acts.goals then -- the active player's secret goals, on their bar only
      bar = text("cz_goals", acts.goals, 12, 'alignment="MiddleCenter" color="#C8CED6" preferredHeight="18"' .. FX) .. bar
      barHeight = barHeight + 22
    end
    local barAt = positions.bar
    if shown(color) then parts[#parts + 1] = sized('<Panel id="cz_actions" visibility="' .. color .. '" width="1120" height="'
      .. barHeight .. '" rectAlignment="' .. barAt.anchor .. '" offsetXY="' .. (barAt.x or 0) .. ' ' .. UI_.barY(game, color) .. '"' .. PANEL
      .. '><VerticalLayout spacing="4" childForceExpandHeight="false">' .. bar .. '</VerticalLayout></Panel>', scale) end
    for _, p in ipairs(state.players) do
      local counters = shown(p.color) and turnCounters(game, p.color)
      if counters then
        local s = UI_.scaleOf(game, p.color)
        -- at their own place, or just above that player's action bar
        local where = nil
        if positions.counters then
          where = place("counters")
        else
          local y = UI_.barY(game, p.color) + (p.color == color and math.ceil(barHeight * s) or 0) + 8
          where = ' rectAlignment="' .. positions.bar.anchor .. '" offsetXY="' .. (positions.bar.x or 0) .. ' ' .. y .. '"'
        end
        parts[#parts + 1] = sized('<Panel id="cz_counters_' .. p.color .. '" visibility="' .. p.color .. '"'
          .. ' width="400" height="' .. symbolSize("turn") .. '"' .. where .. PANEL .. '>' .. counters .. '</Panel>', s)
      end
    end
  end
  for _, color in ipairs(Tutorial.allColors) do
    local tabs = UI_.tabsFor(game, color)
    if #tabs > 0 then
      local xml = ""
      for _, t in ipairs(tabs) do xml = xml .. smallButton(t.id, t.label, 12, t.kind) end
      local at = positions.corner
      -- just past the corner buttons, toward the middle of the screen
      local leftward = at.anchor:find("Left") and 1 or -1
      parts[#parts + 1] = sized('<Panel id="cz_tabs_' .. color .. '" visibility="' .. color .. '" width="' .. UI_.INFO_WIDTH
        .. '" height="30" rectAlignment="' .. at.anchor .. '" offsetXY="' .. ((at.x or 0) + leftward * (UI_.INFO_WIDTH + 12)) .. ' '
        .. (at.y or 0) .. '"' .. PANEL .. '><HorizontalLayout spacing="6" childForceExpandWidth="false" childAlignment="'
        .. (leftward == 1 and "MiddleLeft" or "MiddleRight") .. '">' .. xml .. '</HorizontalLayout></Panel>', UI_.scaleOf(game, color))
    end
  end
  UI_.lastParts = parts
  return table.concat(parts)
end

-- The buttons each colour can see in these top-level panels, with the
-- opening tag of the panel each sits in (its place and size):
-- { [color] = { [id] = tag } }. A panel with no visibility is everyone's.
function UI_.buttonsByColor(parts)
  local out = {}
  for _, color in ipairs(Tutorial.allColors) do out[color] = {} end
  for _, part in ipairs(parts) do
    local tag = part:match("^%s*<[^>]*>") or ""
    local vis = tag:match('visibility="([^"]*)"')
    local colors = {}
    if vis and vis ~= "" then
      for c in vis:gmatch("[^|]+") do colors[#colors + 1] = c end
    else
      colors = Tutorial.allColors
    end
    for id in part:gmatch('<Button id="([^"]+)"') do
      for _, c in ipairs(colors) do if out[c] then out[c][id] = tag end end
    end
  end
  return out
end

-- What a player has put away, as Show buttons beside the corner buttons:
-- everything, if they hid the UI (Show Cardalyzer); else each panel they
-- tucked away that is still open.
function UI_.tabsFor(game, color)
  use(game)
  if UI_.hidden(game, color) then return { { id = "cz-showui", label = say("showUI"), kind = "primary" } } end
  local state, out = game.state, {}
  local seat = game:seatOfColor(color)
  local open = {
    setup = game.setupOpen and game.setupOpen[color] and not (game.kitMenuOpen and game.kitMenuOpen[color]),
    kit = game.kitMenuOpen and game.kitMenuOpen[color],
    settings = game.settingsOpen and game.settingsOpen[color],
    tutorial = game.tutorialOpen and game.tutorialOpen[color],
    winner = state.winner ~= nil,
    choice = state.started and not state.winner and seat ~= nil and state.players[seat].prompts[1] ~= nil,
  }
  local names = { setup = say("newGame"), kit = game.rules.kitName or "Kit", settings = say("settings"),
    tutorial = say("tutorial"), winner = say("result"), choice = say("yourChoice") }
  for _, kind in ipairs({ "choice", "winner", "setup", "kit", "settings", "tutorial" }) do
    if open[kind] and UI_.tucked(game, color, kind) then
      out[#out + 1] = { id = "cz-untuck-" .. kind, label = say("showPanel", { name = names[kind] }),
        kind = kind == "choice" and "primary" or nil }
    end
  end
  return out
end

-- The buttons in the bottom-right corner: Rulebooks (when the rules list
-- some), the rules' own buttons (rules.ui.buttons), then Tidy table.
function UI_.cornerButtons(game)
  use(game)
  local xml = ""
  if game.rules.rulebooks and #game.rules.rulebooks > 0 then xml = xml .. smallButton("cz-rulebooks", say("rulebooks"), 12) end
  for i, b in ipairs(game.rules.ui and game.rules.ui.buttons or {}) do
    xml = xml .. smallButton("cz-button-" .. i, b.label, 12)
  end
  return xml .. smallButton("cz-hideui", say("hideUI"), 12) .. smallButton("cz-tidy", say("tidy"), 12)
end

-- Where a colour's action bar sits: the default, moved in their Settings.
function UI_.barY(game, color)
  local moved = game.state.view.barOffset and game.state.view.barOffset[color] or 0
  local y = Theme.of(game.rules).positions.bar.y
  return (y or UI_.ACTION_BAR_Y) + moved
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
  game.lastXml = UI_.xml(game)
  game.buttonsShown = UI_.buttonsByColor(UI_.lastParts)
  UI.setXml(game.lastXml)
end

return UI_
