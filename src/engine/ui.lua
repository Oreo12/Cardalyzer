-- XML UI: a status panel everyone sees, and an action panel only the active
-- player sees (prompts, Play all, attacks, scrap abilities, End Turn).
-- The whole XML is rebuilt on every refresh. Every button calls
-- Cardalyzer_onUI in main.lua, which reads the action from the button id:
--   cz-new  cz-tidy  cz-end  cz-playall  cz-done
--   cz-pick-<value>  cz-attack-<seat>  cz-hit-<seat>-<uid>  cz-scrap-<uid>
local Util = require("engine.util")
local State = require("engine.state")
local Actions = require("engine.actions")

local UI_ = {}

local function escape(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function text(id, words, size, extra)
  return string.format('<Text id="%s" fontSize="%d" color="#FFFFFF" alignment="MiddleLeft" %s>%s</Text>',
    id, size or 14, extra or "", escape(words))
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
  return marker .. p.name .. ": " .. table.concat(parts, " · ")
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

function UI_.xml(game)
  local state = game.state
  local status = { text("cz_title", game.rules.name or "Cardalyzer", 18, 'fontStyle="Bold"'), text("cz_turn", UI_.turnLine(game)) }
  for seat = 1, #state.players do status[#status + 1] = text("cz_seat_" .. seat, UI_.seatLine(game, seat)) end
  local parts = {
    '<Panel id="cz_panel" width="480" height="' .. (80 + 26 * #status) .. '" rectAlignment="UpperLeft" offsetXY="10 -60"',
    ' color="#000000B0" padding="10 10 10 10"><VerticalLayout spacing="4" childForceExpandHeight="false">',
    table.concat(status),
    '<HorizontalLayout spacing="8" preferredHeight="28">', button("cz-new", "New Game"), button("cz-tidy", "Tidy table"),
    '</HorizontalLayout></VerticalLayout></Panel>',
  }

  if state.started and not state.winner then
    local acts = UI_.actions(game)
    local rows = {}
    if acts.prompt then rows[#rows + 1] = text("cz_prompt", acts.prompt, 14, 'fontStyle="Bold"') end
    for _, b in ipairs(acts.buttons) do rows[#rows + 1] = button(b.id, b.label) end
    local color = state.players[state.turn.active].color
    parts[#parts + 1] = '<Panel id="cz_actions" visibility="' .. color .. '" width="360" height="' .. (24 + 32 * #rows) .. '"'
    parts[#parts + 1] = ' rectAlignment="UpperRight" offsetXY="-10 -60" color="#000000B0" padding="10 10 10 10">'
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
