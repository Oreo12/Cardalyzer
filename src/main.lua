-- Global script entry point. tools/bundle.py bundles this file, the engine
-- modules and the chosen game's rules and data into build/Global.lua.
local Game = require("engine.game")

local game

-- Errors and refusals go to the info panel, not broadcasts: TTS draws
-- broadcast text behind custom UI, so it would get hidden.
local function report(err)
  print("[Cardalyzer] " .. tostring(err))
  if game then return game:notify("Error: " .. tostring(err)) end
  broadcastToAll("[Cardalyzer] " .. tostring(err), { 1, 0.4, 0.4 })
end

local function tell(color, msg)
  if game then return game:notify(msg, color) end
  broadcastToColor(msg, color, { 1, 0.8, 0.4 })
end

-- Runs a game method for a player; shows them why if it was refused.
local function run(color, method, ...)
  local ok, done, why = pcall(method, game, ...)
  if not ok then return report(done) end
  if done then
    game:clearNotice(color)
  elseif why then
    tell(color, why)
  end
end

function onLoad(saved)
  local ok, result = pcall(Game.new, {
    rules = require("game.rules"),
    cards = require("game.cards"),
    art = require("game.art"),
  })
  if not ok then return report(result) end
  game = result
  -- Handy from the in-game Lua console: Cardalyzer.game.state, Cardalyzer.require("engine.turn").
  Cardalyzer = { game = game, require = require }
  local booted, err = pcall(game.boot, game, saved)
  if not booted then report(err) end
end

function onSave()
  if not game then return "" end
  return game:save()
end

-- Play Game in the setup menu: deals a new game and closes the menu.
function Cardalyzer_onStartGame(player)
  if not game then return end
  if not player.host and not player.promoted then
    return tell(player.color, "Only the host can start a new game.")
  end
  game:setup(player.color, false)
  local ok, err = pcall(game.newGame, game)
  if not ok then report(err) end
end

function Cardalyzer_onEndTurn(player)
  if not game then return end
  local seat = game:seatOfColor(player.color)
  if not seat then return tell(player.color, "Take a seat to play.") end
  run(player.color, game.endTurn, seat)
end

-- Every XML button; the action is in the button id (see engine/ui.lua).
function Cardalyzer_onUI(player, _, id)
  if not game then return end
  local action, arg = id:match("^cz%-(%a+)%-?(.*)$")
  if action == "new" then return Cardalyzer_onStartGame(player) end
  if action == "setup" then
    if not player.host and not player.promoted then
      return tell(player.color, "Only the host can start a new game.")
    end
    return game:setup(player.color, true)
  end
  if action == "setupclose" then return game:setup(player.color, false) end
  if action == "tidy" then return run(player.color, game.tidy) end
  if action == "end" then return Cardalyzer_onEndTurn(player) end
  if action == "players" then
    if not player.host and not player.promoted then
      return tell(player.color, "Only the host can change the number of players.")
    end
    return run(player.color, game.setPlayers, tonumber(arg))
  end
  if action:sub(1, 3) == "tut" then return game:tutorial(player.color, action) end

  local seat = game:seatOfColor(player.color)
  if not seat then return tell(player.color, "Take a seat to play.") end
  if action == "playall" then
    run(player.color, game.playAll, seat)
  elseif action == "attack" then
    run(player.color, game.attack, seat, tonumber(arg))
  elseif action == "hit" then
    local target, uid = arg:match("^(%d+)%-(.+)$")
    run(player.color, game.attack, seat, tonumber(target), uid)
  elseif action == "scrap" then
    run(player.color, game.scrapFromPlay, seat, arg)
  elseif action == "pick" then
    run(player.color, game.pick, seat, arg)
  elseif action == "done" then
    run(player.color, game.done, seat)
  end
end

-- Typing !tutorial in chat shows the Tutorial button again and opens it.
function onChat(message, player)
  if not game or message:lower() ~= "!tutorial" then return true end
  game:tutorial(player.color, "tutorial")
  return false
end

-- Buy buttons on market cards and fixed piles.
function Cardalyzer_onBuy(obj, color)
  if not game then return end
  local seat = game:seatOfColor(color)
  if not seat then return tell(color, "Take a seat to play.") end
  run(color, game.buyObject, seat, obj.getGUID(), obj.getGMNotes())
end

-- A player dropped something. Engine cards are handled by Game:dropped: a
-- hand card on your play area is played, a card dropped on the scrap pile is
-- scrapped, and anything else goes back where it belongs.
function onObjectDrop(color, obj)
  if not game or not game.state.started or not obj.hasTag("cz_card") then return end
  local p = obj.getPosition()
  local inOwnPlayZone = false
  local seat = game:seatOfColor(color)
  for _, zone in ipairs(obj.getZones()) do
    if seat and game:playZoneSeat(zone.getGUID()) == seat then inOwnPlayZone = true end
  end
  run(color, game.dropped, color, obj.getGUID(), obj.getGMNotes() or "", { p.x, p.y, p.z }, inOwnPlayZone)
end

-- Engine cards never merge into decks with each other: the engine draws its
-- piles itself, and a merged deck would hide cards from it.
function tryObjectEnterContainer(container, obj)
  if container.hasTag("cz_card") or obj.hasTag("cz_card") then return false end
  return true
end
