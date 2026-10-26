-- In-game tutorial: a few pages, opened per player from the Tutorial button in
-- the info panel. Each player can hide that button; typing !tutorial in chat
-- brings it back. Page text is built from the game's rules (resource names,
-- win condition), so it fits any game.
local Util = require("engine.util")
local Actions = require("engine.actions")

local Tutorial = {}

local function statLabel(rules, key)
  for _, stat in ipairs(rules.stats or {}) do
    if stat.key == key then return stat.label or Util.titleCase(key) end
  end
  return Util.titleCase(key or "")
end

-- Returns { {title, body}, ... }.
function Tutorial.pages(game)
  local rules = game.rules
  local _, buy = Actions.resourceFor(rules, "buy")
  local _, attack = Actions.resourceFor(rules, "attack")
  buy, attack = buy or "buy points", attack or "attack points"
  local win = rules.win and rules.win.stat
    and ("Bring an opponent's " .. statLabel(rules, rules.win.stat) .. " down to " .. (rules.win.atOrBelow or 0) .. " to win.")
    or "The game's rules decide how to win."

  return {
    { "Welcome to " .. (rules.name or "Cardalyzer"),
      "Cardalyzer reads every card's effects and applies them for you. Play a card and its "
      .. buy .. ", " .. attack .. ", draws and other effects happen on their own, and the totals are always "
      .. "up to date. You just choose what to play, buy and attack.\n\n" .. win },
    { "The info panel (top centre)",
      "Everyone sees this panel. It shows whose turn it is and one line per player, in their seat colour: "
      .. "their resources, stats, and how many cards are in their deck and discard pile. The active player's "
      .. "line is bold.\n\nMessages appear here too. The last three are shown to everyone, and a message just "
      .. "for you (like \"It's not your turn\") appears on a line under the panel. All messages are also in chat." },
    { "Your turn (top right)",
      "On your turn an action panel appears at the top right. Only you can see it.\n\n"
      .. "- Play cards by dragging them from your hand onto your play area, or press Play all.\n"
      .. "- Buy a card by pressing the Buy button on it in the market.\n"
      .. "- Spend " .. attack .. " with the Attack and Destroy buttons.\n"
      .. "- When a card asks you to choose, the question and its options appear at the top of this panel.\n"
      .. "- Press End Turn when you're done. Your cards are discarded and you draw a new hand." },
    { "The table",
      "Your hand is at the edge of the table in front of you. In front of it are your play area (cards played "
      .. "this turn), your bases (cards that stay in play), and your deck and discard pile.\n\n"
      .. "The market is in the middle: the market deck, the row of cards for sale, any piles that are always "
      .. "for sale, and the scrap pile for removed cards." },
    { "Tips",
      "- If cards get knocked around, press Tidy table. The game is tracked in the script, not by where cards "
      .. "sit, so nothing is lost.\n"
      .. "- New Game deals a fresh game (host only).\n"
      .. "- Don't want the Tutorial button? Press Hide button below. Type !tutorial in chat to bring it back." },
  }
end

-- Per-player state. Open pages live on the game (not saved); hidden buttons
-- are saved in state.view so they stay hidden after a reload.
local function hidden(game)
  game.state.view.tutorialHidden = game.state.view.tutorialHidden or {}
  return game.state.view.tutorialHidden
end

function Tutorial.buttonShown(game, color)
  if game.rules.tutorial == false then return false end
  return not hidden(game)[color]
end

function Tutorial.open(game, color, page)
  game.tutorialOpen = game.tutorialOpen or {}
  local count = #Tutorial.pages(game)
  game.tutorialOpen[color] = math.max(1, math.min(page or 1, count))
end

function Tutorial.close(game, color)
  if game.tutorialOpen then game.tutorialOpen[color] = nil end
end

function Tutorial.turn(game, color, by)
  local page = game.tutorialOpen and game.tutorialOpen[color]
  if page then Tutorial.open(game, color, page + by) end
end

function Tutorial.setHidden(game, color, value)
  hidden(game)[color] = value or nil
end

-- Every colour TTS has, for the Tutorial button's visibility list.
Tutorial.allColors = { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Grey", "Black" }

-- The colours that see the Tutorial button, as a TTS visibility string.
function Tutorial.visibility(game)
  local out = {}
  for _, color in ipairs(Tutorial.allColors) do
    if Tutorial.buttonShown(game, color) then out[#out + 1] = color end
  end
  return table.concat(out, "|")
end

return Tutorial
