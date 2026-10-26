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

local function button(id, label)
  return string.format('<Button id="%s" onClick="Cardalyzer_onUI" preferredHeight="28">%s</Button>', id, escape(label))
end

-- Player-count buttons (cz-players-<n>) for games that seat more than one
-- number of players. Only the host's clicks count (see main.lua).
function UI_.playersRow(game)
  local range = game.playerRange(game.rules)
  if range.min >= range.max then return nil end
  local state = game.state
  local current = state.nextPlayers or #state.players
  local xml = text("cz_players", "Players", 15, 'preferredWidth="110"')
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
  if not state.started then return "Press New Game to set up a game." end
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

  if #p.hand > 0 and not Actions.handBlocked(game, seat) then add("cz-playall", "Play all (" .. #p.hand .. ")") end

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
    local c = game:cardOf(uid) -- a card copying another this turn shows that card's scrap ability
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

-- The right-hand column: the action panel at the top (engine/ui actions), the
-- info panel above the Tidy table button at the bottom, and a private
-- message for one player just above the info panel.
UI_.INFO_WIDTH = 320
local INFO_BOTTOM = 66 -- the info panel's bottom edge, in pixels above the screen's
local TIDY_HEIGHT = 48

-- Rough pixel height of a message wrapped to the info panel's width.
local function wrappedHeight(msg, size)
  local perLine = math.floor((UI_.INFO_WIDTH - 28) / (size * 0.52))
  return math.max(1, math.ceil(#msg / perLine)) * (size + 6)
end

-- A seat's block in the info panel: its name, then its resources and stats,
-- then its deck and discard counts (or "out").
function UI_.seatLines(game, seat)
  local p = game.state.players[seat]
  local marker = (game.state.started and game.state.turn.active == seat) and "▶ " or ""
  if p.out then return { marker .. p.name .. ": out" } end
  local parts = {}
  for _, res in ipairs(game.rules.resources or {}) do
    parts[#parts + 1] = (res.label or Util.titleCase(res.key)) .. " " .. (p.resources[res.key] or 0)
  end
  for _, stat in ipairs(game.rules.stats or {}) do
    parts[#parts + 1] = (stat.label or Util.titleCase(stat.key)) .. " " .. (p.stats[stat.key] or 0)
  end
  return { marker .. p.name, table.concat(parts, " · "), "Deck " .. #p.deck .. " · Discard " .. #p.discard }
end

-- The info panel, on the right: title, turn, one block per seat, the last
-- few messages (see Game:notify; TTS draws broadcasts behind custom UI, so
-- they're shown here instead) and the New Game button, which opens the setup
-- menu. Returns its XML and its height in pixels.
function UI_.infoPanel(game)
  local state = game.state
  local rows, height = {}, 26
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 4 end

  row(text("cz_title", game.rules.name or "Cardalyzer", 18, 'fontStyle="Bold" alignment="MiddleCenter" color="' .. ACCENT .. '"'), 24)
  local turn = UI_.turnLine(game)
  row(text("cz_turn", turn, 15, 'fontStyle="Bold" alignment="MiddleCenter" preferredHeight="' .. wrappedHeight(turn, 15) .. '"'),
    wrappedHeight(turn, 15))
  for seat = 1, #state.players do
    local p = state.players[seat]
    local active = state.started and state.turn.active == seat
    local tint = 'color="' .. (UI_.seatColors[p.color] or "#FFFFFF") .. '"'
    for i, line in ipairs(UI_.seatLines(game, seat)) do
      local first = i == 1
      row(text("cz_seat_" .. seat .. (first and "" or ("_" .. i)), line, first and 15 or 13,
        tint .. ((first and active) and ' fontStyle="Bold"' or "") .. ' preferredHeight="' .. (first and 20 or 17) .. '"'),
        first and 20 or 17)
    end
  end
  for i, msg in ipairs(game.notices and game.notices.all or {}) do
    local h = wrappedHeight(msg, 12)
    row(text("cz_notice_" .. i, msg, 12, 'color="' .. ACCENT .. '" fontStyle="Italic" preferredHeight="' .. h .. '"'), h)
  end
  row(button("cz-setup", "New Game"), 28)

  return '<Panel id="cz_panel" width="' .. UI_.INFO_WIDTH .. '" height="' .. height .. '" rectAlignment="LowerRight" offsetXY="-10 '
    .. INFO_BOTTOM .. '"' .. PANEL .. '><VerticalLayout spacing="4" childForceExpandHeight="false">' .. table.concat(rows)
    .. '</VerticalLayout></Panel>', height
end

-- The setup menu, in the middle of the screen for the player who pressed New
-- Game: the player count, Play Game (deals and closes the menu), Tutorial and
-- Close. Choices made here are kept for next time.
function UI_.setupPanel(game, color)
  local rows, height = {}, 26
  local function row(xml, h) rows[#rows + 1] = xml; height = height + h + 8 end
  row(text("cz_setup_title_" .. color, "New Game", 20, 'fontStyle="Bold" alignment="MiddleCenter" color="' .. ACCENT .. '"'), 26)
  local players = UI_.playersRow(game)
  if players then row(players, 28) end
  local buttons = button("cz-new", "Play Game")
  if Tutorial.buttonShown(game, color) then buttons = buttons .. button("cz-tutorial", "Tutorial") end
  buttons = buttons .. button("cz-setupclose", "Close")
  row('<HorizontalLayout spacing="8" preferredHeight="30" childForceExpandWidth="false" childAlignment="MiddleCenter">'
    .. buttons:gsub("<Button ", '<Button preferredWidth="120" ') .. '</HorizontalLayout>', 30)
  return '<Panel id="cz_setup_' .. color .. '" visibility="' .. color .. '" width="440" height="' .. height
    .. '" rectAlignment="MiddleCenter"' .. PANEL .. '><VerticalLayout spacing="8" childForceExpandHeight="false">'
    .. table.concat(rows) .. '</VerticalLayout></Panel>'
end

function UI_.xml(game)
  local state = game.state
  local info, infoHeight = UI_.infoPanel(game)
  local parts = { info }

  -- Tidy table on its own, in the bottom right corner.
  parts[#parts + 1] = '<Panel id="cz_tidy" width="170" height="' .. TIDY_HEIGHT .. '" rectAlignment="LowerRight" offsetXY="-10 10"'
    .. PANEL .. '>' .. button("cz-tidy", "Tidy table") .. '</Panel>'

  -- A private message for one player, just above the info panel.
  local byColor = game.notices and game.notices.byColor or {}
  local colors = {}
  for color in pairs(byColor) do colors[#colors + 1] = color end
  table.sort(colors)
  for _, color in ipairs(colors) do
    local h = wrappedHeight(byColor[color], 13) + 24
    parts[#parts + 1] = '<Panel id="cz_notice_' .. color .. '" visibility="' .. color .. '" width="' .. UI_.INFO_WIDTH
      .. '" height="' .. h .. '" rectAlignment="LowerRight" offsetXY="-10 ' .. (INFO_BOTTOM + infoHeight + 6) .. '"' .. PANEL .. '>'
      .. text("cz_notice_text_" .. color, byColor[color], 13, 'alignment="MiddleCenter" color="' .. ACCENT .. '"')
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
    parts[#parts + 1] = '<Panel id="cz_winner" visibility="' .. table.concat(who, "|") .. '" width="420" height="150"'
      .. ' rectAlignment="MiddleCenter"' .. PANEL .. '><VerticalLayout spacing="10" childForceExpandHeight="false">'
      .. text("cz_winner_text", winner.name .. " wins!", 30,
        'fontStyle="Bold" alignment="MiddleCenter" preferredHeight="44" color="' .. (UI_.seatColors[winner.color] or ACCENT) .. '"')
      .. '<HorizontalLayout preferredHeight="34" childForceExpandWidth="false" childAlignment="MiddleCenter">'
      .. button("cz-again", "Play Again?"):gsub("<Button ", '<Button preferredWidth="200" ')
      .. '</HorizontalLayout></VerticalLayout></Panel>'
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
