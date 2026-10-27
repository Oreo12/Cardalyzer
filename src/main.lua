-- Global script entry point. tools/bundle.py bundles this file, the engine
-- modules and the chosen game's rules and data into build/Global.lua.
local Game = require("engine.game")

local game = nil

-- Errors and refusals go to the info panel, not broadcasts: TTS draws
-- broadcast text behind custom UI, so it would get hidden.
local function report(err)
  print("[Cardalyzer] " .. tostring(err))
  if game then return game:notify("Error: " .. tostring(err)) end
  broadcastToAll("[Cardalyzer] " .. tostring(err), { 1, 0.4, 0.4 })
end

local function tell(color, msg)
  if game then return game:notify(msg, color) end
  if Game.seated(color) then broadcastToColor(msg, color, { 1, 0.8, 0.4 }) end
end

-- The game's word for `key` (engine/words.lua).
local function say(key) return require("engine.words").say(game and game.rules, key) end

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
  -- A key each player can set in Options → Game Keys to hide or show the UI.
  if addHotkey then
    addHotkey("Cardalyzer: hide or show the UI", function(color)
      if game then run(color, game.setUiHidden, color) end
    end)
  end
end

function onSave()
  if not game then return "" end
  return game:save()
end

-- Play Game in the setup menu: deals a new game and closes the menu.
function Cardalyzer_onStartGame(player)
  if not game then return end
  if not player.host and not player.promoted then
    return tell(player.color, say("hostOnlyNewGame"))
  end
  game:setup(player.color, false)
  local ok, err = pcall(game.newGame, game)
  if not ok then report(err) end
end

function Cardalyzer_onEndTurn(player)
  if not game then return end
  local seat = game:seatOfColor(player.color)
  if not seat then return tell(player.color, say("takeASeat")) end
  run(player.color, game.endTurn, seat)
end

-- TTS leaves a button's tooltip stuck on screen when a click removes that
-- button (Close, Play Game, End Turn) or moves it (its panel moves or
-- changes size). Drawing the UI afresh a moment later clears it, so that's
-- done after such a click on a button with a tooltip.
local function hadTooltip(xml, id)
  local tag = xml and xml:match('<Button id="' .. id:gsub("%p", "%%%0") .. '"[^>]*>')
  return tag ~= nil and tag:find('tooltip="', 1, true) ~= nil
end
local function clearStuckTooltip(color, before, wasAt, id)
  if not hadTooltip(before, id) then return end
  Wait.time(function()
    local shown = game and game.buttonsShown and game.buttonsShown[color]
    if not game or (shown and shown[id] and shown[id] == wasAt) then return end
    UI.setXml("")
    Wait.frames(function() game:refreshUI() end, 2)
  end, 0.5)
end

local handleUI = nil

-- Every XML button; the action is in the button id (see engine/ui.lua).
function Cardalyzer_onUI(player, value, id)
  if not game then return end
  local before = game.lastXml
  local wasAt = game.buttonsShown and game.buttonsShown[player.color] and game.buttonsShown[player.color][id]
  local ok, err = pcall(handleUI, player, value, id)
  clearStuckTooltip(player.color, before, wasAt, id)
  if not ok then report(err) end
end

function handleUI(player, _, id)
  local action, arg = id:match("^cz%-(%a+)%-?(.*)$")
  if action == "new" then return Cardalyzer_onStartGame(player) end
  if action == "setup" or action == "again" then -- New Game, or Play Again? after a win
    if not player.host and not player.promoted then
      return tell(player.color, say("hostOnlyNewGame"))
    end
    return game:setup(player.color, true)
  end
  if action == "setupclose" then return game:setup(player.color, false) end
  -- Anyone can put panels away, hide the UI or choose where their menus go.
  if action == "tuck" then return game:tuck(player.color, arg, true) end
  if action == "untuck" then return game:tuck(player.color, arg, false) end
  if action == "hideui" then return game:setUiHidden(player.color, true) end
  if action == "showui" then return game:setUiHidden(player.color, false) end
  if action == "menuat" then return run(player.color, game.setMenuAt, player.color, arg) end
  -- Settings: anyone can change their own UI size and action bar height.
  if action == "settings" then return game:settings(player.color, true) end
  if action == "settingsclose" then return game:settings(player.color, false) end
  if action == "uismaller" then return game:setUiScale(player.color, -1) end
  if action == "uibigger" then return game:setUiScale(player.color, 1) end
  if action == "barup" then return game:moveBar(player.color, 1) end
  if action == "bardown" then return game:moveBar(player.color, -1) end
  if action == "barreset" then return game:moveBar(player.color, 0) end
  if action == "tidy" then return run(player.color, game.tidy) end
  if action == "rulebooks" then return run(player.color, game.toggleRulebooks) end
  if action == "button" then return run(player.color, game.pressButton, tonumber(arg), player.color) end
  if action == "end" then return Cardalyzer_onEndTurn(player) end
  if action == "players" then
    if not player.host and not player.promoted then
      return tell(player.color, say("hostOnlyPlayers"))
    end
    return run(player.color, game.setPlayers, tonumber(arg))
  end
  if action == "set" then
    if not player.host and not player.promoted then
      return tell(player.color, say("hostOnlySets"))
    end
    return run(player.color, game.toggleSet, arg)
  end
  if action == "supply" then
    if not player.host and not player.promoted then
      return tell(player.color, say("hostOnlySupply"))
    end
    return run(player.color, game.setSupply, tonumber(arg))
  end
  if action == "kits" then
    -- The kit option: the host turns kits on (and gets their own kit menu);
    -- once they're on, anyone pressing it opens their own kit menu.
    if arg ~= "off" and game:kitsOn() then return run(player.color, game.kitMenu, player.color, true) end
    if not player.host and not player.promoted then
      return tell(player.color, say("hostOnlyKits"))
    end
    run(player.color, game.setKits, arg)
    if arg ~= "off" then run(player.color, game.kitMenu, player.color, true) end
    return
  end
  -- Each player's own kit menu: anyone may open it and change only their own choice.
  if action == "kitmenu" then return run(player.color, game.kitMenu, player.color, true) end
  if action == "kitcancel" then return run(player.color, game.kitMenu, player.color, false) end
  if action == "kitsave" then return run(player.color, game.kitSave, player.color) end
  if action == "kitmode" then return run(player.color, game.kitEdit, player.color, "mode", arg) end
  if action == "kitpick" then return run(player.color, game.kitEdit, player.color, "kit", arg) end
  if action == "kitpart" then
    local i, value = arg:match("^(%d+)%-(.+)$")
    return run(player.color, game.kitEdit, player.color, i, value)
  end
  if action == "opening" then
    if not player.host and not player.promoted then
      return tell(player.color, say("hostOnlyHands"))
    end
    return run(player.color, game.setOpening, tonumber(arg))
  end
  if action:sub(1, 3) == "tut" then return game:tutorial(player.color, action) end

  local seat = game:seatOfColor(player.color)
  if not seat then return tell(player.color, say("takeASeat")) end
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
  elseif action == "phase" then
    run(player.color, game.nextPhase, seat)
  elseif action == "use" then
    run(player.color, game.activate, seat, arg)
  elseif action == "call" then
    run(player.color, game.call, seat, arg)
  elseif action == "goal" then
    run(player.color, game.completeObjective, seat, arg)
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
  if not seat then return tell(color, say("takeASeat")) end
  run(color, game.buyObject, seat, obj.getGUID(), obj.getGMNotes())
end

-- Hire buttons on market cards to hire for a turn (types with hire = true).
function Cardalyzer_onHire(obj, color)
  if not game then return end
  local seat = game:seatOfColor(color)
  if not seat then return tell(color, say("takeASeat")) end
  run(color, game.hire, seat, obj.getGMNotes())
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
