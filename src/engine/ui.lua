-- XML UI: an info panel everyone sees (top centre), and an action panel only the active
-- player sees (prompts, Play all, attacks, scrap abilities, End Turn).
-- The whole XML is rebuilt on every refresh. Every button calls
-- Cardalyzer_onUI in main.lua, which reads the action from the button id:
--   cz-new  cz-tidy  cz-end  cz-playall  cz-done  cz-players-<n>
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

local function button(id, label)
  return string.format('<Button id="%s" onClick="Cardalyzer_onUI" preferredHeight="28">%s</Button>', id, escape(label))
end

-- One status line per seat, e.g. "▶ White: Gold 3 · Might 1 · Health 40 · Deck 5 · Discard 2".
function UI_.seatLine(game, seat)
  local p = game.state.players[seat]
  local parts = {}
  for _, res in ipairs(game.rules.resources or {}) do
    parts[#parts + 1] = (res.label or Util.titleCase(res.key)) .. " " .. (p.resources[res.key] or 0)
  end
  for _, stat in ipairs(game.rules.stats or {}) do
    parts[#parts + 1] = (stat.label or Util.titleCase(stat.key)) .. " " .. (p.stats[stat.key] or 0)
  end
  parts[#parts + 1] = "Deck " .. #p.deck
  parts[#parts + 1] = "Discard " .. #p.discard
  local marker = (game.state.started and game.state.turn.active == seat) and "▶ " or "   "
  if p.out then return marker .. p.name .. ": out" end
  return marker .. p.name .. ": " .. table.concat(parts, " · ")
end

-- Player-count buttons (cz-players-<n>) for games that seat more than one
-- number of players. Only the host's clicks count (see main.lua).
function UI_.playersRow(game)
  local range = game.playerRange(game.rules)
  if range.min >= range.max then return nil end
  local state = game.state
  local current = state.nextPlayers or #state.players
  local label = state.started and state.nextPlayers and ("Next game: " .. current .. " players") or "Players"
  local xml = text("cz_players", label, 14, 'preferredWidth="190"')
  for n = range.min, range.max do
    local id = "cz-players-" .. n
    local b = button(id, tostring(n)):gsub("<Button ", '<Button preferredWidth="60" ')
    if n == current then b = b:gsub("<Button ", '<Button fontStyle="Bold" textColor="#E8B84A" ') end
    xml = xml .. b
  end
  return '<HorizontalLayout spacing="8" preferredHeight="28" childForceExpandWidth="false" childAlignment="MiddleCenter">'
    .. xml .. '</HorizontalLayout>'
end

function UI_.turnLine(game)
  local state = game.state
  if not state.started then return "Press New Game to deal." end
  if state.winner then return state.players[state.winner].name .. " wins!" end
  local active = state.players[state.turn.active]
  return "Turn " .. state.turn.number .. " · " .. active.name .. " to play"
end

-- The active player's options, as { {id, label}, ... } groups, plus the prompt line.
function UI_.actions(game)
  local state = game.state
  local seat = state.turn.active
  local p = state.players[seat]
  local out = { prompt = nil, buttons = {} }
  local function add(id, label) out.buttons[#out.buttons + 1] = { id = id, label = label } end

  local prompt = p.prompts[1]
  if prompt then
    local more = #p.prompts > 1 and (" (+" .. (#p.prompts - 1) .. " more)") or ""
    out.prompt = Actions.promptText(game, prompt) .. more
    for _, t in ipairs(Actions.targets(game, seat, prompt)) do add("cz-pick-" .. t.value, t.label) end
    if prompt.optional then add("cz-done", prompt.kind == "reminder" and "Done" or "Skip / done") end
  end

  if #p.hand > 0 then add("cz-playall", "Play all (" .. #p.hand .. ")") end

  local key, label = Actions.resourceFor(game.rules, "attack")
  local pool = key and p.resources[key] or 0
  if pool > 0 then
    for _, other in ipairs(game:opponentsOf(seat)) do
      local guards = Actions.guards(game, other)
      local victim = state.players[other]
      if #guards == 0 then add("cz-attack-" .. other, "Attack " .. victim.name .. " (" .. pool .. " " .. label .. ")") end
      for _, uid in ipairs(victim.bases) do
        local c = game.cards:get(State.cardId(state, uid))
        local open = #guards == 0 or Util.indexOf(guards, uid)
        if open and pool >= (c.defense or 0) then
          add("cz-hit-" .. other .. "-" .. uid, "Destroy " .. c.name .. " (" .. (c.defense or 0) .. ")")
        end
      end
    end
  end

  for _, uid in ipairs(Actions.inPlay(p)) do
    local c = game.cards:get(State.cardId(state, uid))
    if #c.scrapEffects > 0 then
      add("cz-scrap-" .. uid, "Scrap " .. c.name .. ": " .. game.effects:describe(c.scrapEffects, c.text))
    end
  end

  add("cz-end", "End Turn")
  return out
end

-- Hex values of the TTS seat colours, for tinting each player's status line.
UI_.seatColors = {
  White = "#FFFFFF", Brown = "#A0653A", Red = "#E5413F", Orange = "#F4741D", Yellow = "#E7E52C",
  Green = "#4CC845", Teal = "#21B19B", Blue = "#3C96FF", Purple = "#B04CF0", Pink = "#F570CE",
}

local ACCENT = "#E8B84A"
local PANEL = ' color="#0E1620F2" outline="' .. ACCENT .. '" outlineSize="2 -2" padding="14 14 12 12"'

-- The info panel sits alone at the top centre, below the TTS menu bar. Messages
-- are shown inside it (see Game:notify) instead of as broadcasts, which TTS
-- draws behind custom UI. Returns its XML and its height in pixels.
function UI_.infoPanel(game)
  local state = game.state
  local rows, height = {}, 28
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 4 end

  row(text("cz_title", game.rules.name or "Cardalyzer", 20, 'fontStyle="Bold" alignment="MiddleCenter" color="' .. ACCENT .. '"'), 26)
  row(text("cz_turn", UI_.turnLine(game), 16, 'fontStyle="Bold" alignment="MiddleCenter"'), 22)
  for seat = 1, #state.players do
    local p = state.players[seat]
    local active = state.started and state.turn.active == seat
    row(text("cz_seat_" .. seat, UI_.seatLine(game, seat), 15,
      'color="' .. (UI_.seatColors[p.color] or "#FFFFFF") .. '"' .. (active and ' fontStyle="Bold"' or "")), 22)
  end
  for i, msg in ipairs(game.notices and game.notices.all or {}) do
    row(text("cz_notice_" .. i, msg, 13, 'color="' .. ACCENT .. '" fontStyle="Italic"'), 18)
  end
  local buttons = button("cz-new", "New Game") .. button("cz-tidy", "Tidy table")
  local who = Tutorial.visibility(game)
  if who ~= "" then
    buttons = buttons .. button("cz-tutorial", "Tutorial"):gsub("<Button ", '<Button visibility="' .. who .. '" ')
  end
  row('<HorizontalLayout spacing="8" preferredHeight="28" childForceExpandWidth="false" childAlignment="MiddleCenter">'
    .. buttons:gsub("<Button ", '<Button preferredWidth="150" ') .. '</HorizontalLayout>', 28)
  local players = UI_.playersRow(game)
  if players then row(players, 28) end

  return '<Panel id="cz_panel" width="620" height="' .. height .. '" rectAlignment="UpperCenter" offsetXY="0 -50"'
    .. PANEL .. '><VerticalLayout spacing="4" childForceExpandHeight="false">' .. table.concat(rows)
    .. '</VerticalLayout></Panel>', height
end

function UI_.xml(game)
  local state = game.state
  local info, infoHeight = UI_.infoPanel(game)
  local parts = { info }

  -- A private message for one player, just under the info panel.
  local byColor = game.notices and game.notices.byColor or {}
  local colors = {}
  for color in pairs(byColor) do colors[#colors + 1] = color end
  table.sort(colors)
  for _, color in ipairs(colors) do
    parts[#parts + 1] = '<Panel id="cz_notice_' .. color .. '" visibility="' .. color .. '" width="620" height="40"'
      .. ' rectAlignment="UpperCenter" offsetXY="0 ' .. -(50 + infoHeight + 6) .. '"' .. PANEL .. '>'
      .. text("cz_notice_text_" .. color, byColor[color], 14, 'alignment="MiddleCenter" color="' .. ACCENT .. '"')
      .. '</Panel>'
  end

  -- The tutorial, in the middle of the screen, for each player reading it.
  local open = game.tutorialOpen or {}
  local readers = {}
  for color in pairs(open) do readers[#readers + 1] = color end
  table.sort(readers)
  if #readers > 0 then
    local pages = Tutorial.pages(game)
    for _, color in ipairs(readers) do
      local n = open[color]
      local page = pages[n]
      local nav = (n > 1 and button("cz-tutback", "Back") or "")
        .. (n < #pages and button("cz-tutnext", "Next") or "")
        .. button("cz-tutclose", "Close") .. button("cz-tuthide", "Hide button")
      parts[#parts + 1] = '<Panel id="cz_tutorial_' .. color .. '" visibility="' .. color .. '" width="680" height="400"'
        .. ' rectAlignment="MiddleCenter"' .. PANEL .. '><VerticalLayout spacing="8" childForceExpandHeight="false">'
        .. text("cz_tut_title_" .. color, page[1], 22, 'fontStyle="Bold" color="' .. ACCENT .. '" preferredHeight="34"')
        .. text("cz_tut_body_" .. color, page[2], 16, 'alignment="UpperLeft" preferredHeight="270"')
        .. text("cz_tut_page_" .. color, "Page " .. n .. " of " .. #pages, 12, 'alignment="MiddleRight" color="#9AA4AE" preferredHeight="16"')
        .. '<HorizontalLayout spacing="8" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleCenter">'
        .. nav:gsub("<Button ", '<Button preferredWidth="140" ') .. '</HorizontalLayout></VerticalLayout></Panel>'
    end
  end

  if state.started and not state.winner then
    local acts = UI_.actions(game)
    local rows = {}
    if acts.prompt then rows[#rows + 1] = text("cz_prompt", acts.prompt, 14, 'fontStyle="Bold" color="' .. ACCENT .. '"') end
    for _, b in ipairs(acts.buttons) do rows[#rows + 1] = button(b.id, b.label) end
    local color = state.players[state.turn.active].color
    parts[#parts + 1] = '<Panel id="cz_actions" visibility="' .. color .. '" width="360" height="' .. (28 + 32 * #rows) .. '"'
    parts[#parts + 1] = ' rectAlignment="UpperRight" offsetXY="-10 -60"' .. PANEL .. '>'
    parts[#parts + 1] = '<VerticalLayout spacing="4" childForceExpandHeight="false">' .. table.concat(rows) .. '</VerticalLayout></Panel>'
  end
  return table.concat(parts)
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

function UI_.refresh(game)
  UI.setXml(UI_.xml(game))
end

return UI_
