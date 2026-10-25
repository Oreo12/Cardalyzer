-- Global script entry point. tools/bundle.py bundles this file, the engine
-- modules and the chosen game's rules and data into build/Global.lua.
local Game = require("engine.game")

local game

local function report(err)
  broadcastToAll("[Deck Builder] " .. tostring(err), { 1, 0.4, 0.4 })
  print("[Deck Builder] " .. tostring(err))
end

function onLoad(saved)
  local ok, result = pcall(Game.new, {
    rules = require("game.rules"),
    cards = require("game.cards"),
    art = require("game.art"),
  })
  if not ok then return report(result) end
  game = result
  -- Handy from the in-game Lua console: DBE.game.state, DBE.require("engine.turn").
  DBE = { game = game, require = require }
  local booted, err = pcall(game.boot, game, saved)
  if not booted then report(err) end
end

function onSave()
  if not game then return "" end
  return game:save()
end

function DBE_onStartGame(player)
  if not game then return end
  if not player.host and not player.promoted then
    return broadcastToColor("Only the host can start a new game.", player.color, { 1, 0.8, 0.4 })
  end
  local ok, err = pcall(game.newGame, game)
  if not ok then report(err) end
end

function DBE_onEndTurn(player)
  if not game then return end
  local ok, done, why = pcall(game.endTurn, game, player.color)
  if not ok then return report(done) end
  if not done then broadcastToColor(why, player.color, { 1, 0.8, 0.4 }) end
end
