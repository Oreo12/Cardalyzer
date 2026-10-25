-- XML UI: a status panel with each seat's resource pools and stats, plus the
-- Start Game and End Turn buttons. The XML is built here so the whole mod is
-- one Global script; button clicks call the Cardalyzer_on* globals in main.lua.
local Util = require("engine.util")

local UI_ = {}

local function escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

function UI_.xml(game)
  local rows = {}
  for seat = 1, #game.state.players do
    rows[#rows + 1] = string.format(
      '<Text id="cz_seat_%d" alignment="MiddleLeft" fontSize="16" color="#FFFFFF"></Text>', seat)
  end
  return table.concat({
    '<Panel id="cz_panel" width="460" height="' .. (110 + 28 * #rows) .. '"',
    ' rectAlignment="UpperLeft" offsetXY="10 -60" color="#000000B0" padding="10 10 10 10">',
    '<VerticalLayout spacing="4" childForceExpandHeight="false">',
    '<Text id="cz_title" fontSize="18" fontStyle="Bold" color="#FFFFFF" alignment="MiddleLeft">',
    escape(game.rules.name or "Cardalyzer"), '</Text>',
    '<Text id="cz_turn" fontSize="14" color="#DDDDDD" alignment="MiddleLeft"></Text>',
    table.concat(rows),
    '<HorizontalLayout spacing="8" preferredHeight="32">',
    '<Button id="cz_start" onClick="Cardalyzer_onStartGame">New Game</Button>',
    '<Button id="cz_end" onClick="Cardalyzer_onEndTurn">End Turn</Button>',
    '</HorizontalLayout>',
    '</VerticalLayout></Panel>',
  })
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
  if not game.state.started then return "Press New Game to deal." end
  local active = game.state.players[game.state.turn.active]
  return "Turn " .. game.state.turn.number .. " · " .. active.name .. " to play"
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

function UI_.build(game)
  UI.setXml(UI_.xml(game))
end

function UI_.refresh(game)
  UI.setValue("cz_turn", UI_.turnLine(game))
  for seat = 1, #game.state.players do
    UI.setValue("cz_seat_" .. seat, UI_.seatLine(game, seat))
  end
end

return UI_
