-- Game facade: wires the modules together and is what main.lua, effect
-- handlers and custom effects talk to. Holds rules, cards, effects, art,
-- layout and the saved state.
local Cards = require("engine.cards")
local Effects = require("engine.effects")
local State = require("engine.state")
local Turn = require("engine.turn")
local Actions = require("engine.actions")
local Zones = require("engine.zones")
local Board = require("engine.board")
local UI_ = require("engine.ui")
local Tutorial = require("engine.tutorial")

local Game = {}
Game.__index = Game

-- opts = { rules = <rules module>, cards = <rows from cards.json>, art = <art.json> }
function Game.new(opts)
  local self = setmetatable({}, Game)
  self.rules = opts.rules
  self.art = opts.art
  self.cards = Cards.new(opts.cards)
  self.effects = Effects.new(self.rules)
  self.random = opts.random or math.random

  local problems = self.effects:validate(self.cards)
  if #problems > 0 then error("card data problems:\n  " .. table.concat(problems, "\n  "), 0) end

  self.fixedIds = {}
  for _, card in ipairs(self.cards:inDeck("fixed")) do self.fixedIds[#self.fixedIds + 1] = card.id end
  self.layout = Zones.layout(self.rules, self.fixedIds)
  self.state = State.new(self.rules)
  -- Messages shown inside the UI (not saved): the latest few for everyone,
  -- and the latest one for each player colour.
  self.notices = { all = {}, byColor = {} }
  return self
end

---------------------------------------------------------------------------
-- State API (used by effects and tests; no TTS calls)
---------------------------------------------------------------------------

function Game:seatOfColor(color)
  for seat, p in ipairs(self.state.players) do
    if p.color == color then return seat end
  end
  return nil
end

function Game:opponentsOf(seat)
  local out = {}
  for other = 1, #self.state.players do
    if other ~= seat then out[#out + 1] = other end
  end
  return out
end

function Game:draw(seat, n)
  return Turn.draw(self.state, seat, n, self.random)
end

-- Queues a choice for a player; custom effects use this too, e.g.
-- game:prompt(seat, { kind = "free_buy", maxCost = 4 }). See engine/actions.lua.
function Game:prompt(seat, prompt)
  Actions.prompt(self, seat, prompt)
end

function Game:setupState()
  local view = self.state.view
  self.state = State.new(self.rules)
  self.state.view = view -- keep zone GUIDs so zones aren't respawned
  Turn.setup(self.state, self.rules, self.cards, self.random)
  Actions.startTurn(self, self.state.turn.active)
end

function Game:save()
  return JSON.encode(self.state)
end

-- Restores a saved state. Returns false when there is nothing usable to load.
function Game:loadState(saved)
  if saved == nil or saved == "" then return false end
  local ok, data = pcall(JSON.decode, saved)
  if not ok or type(data) ~= "table" or data.version ~= State.VERSION then return false end
  self.state = data
  return true
end

---------------------------------------------------------------------------
-- Table API (state change + redraw; these call the TTS API)
---------------------------------------------------------------------------

function Game:boot(saved)
  self:loadState(saved)
  Zones.build(self, self.layout)
  self:refreshUI()
end

function Game:refreshUI()
  UI_.refresh(self)
end

-- Shows a message in the info panel (or only to one colour) and copies it to
-- the chat log. Used instead of broadcasts, which TTS draws behind the UI.
function Game:notify(msg, color)
  msg = tostring(msg)
  if color then
    self.notices.byColor[color] = msg
    printToColor(msg, color, { 1, 0.8, 0.4 })
  else
    local all = self.notices.all
    all[#all + 1] = msg
    while #all > 3 do table.remove(all, 1) end
    printToAll(msg, { 1, 0.8, 0.4 })
  end
  self:refreshUI()
end

-- Tutorial buttons: "tutorial" opens it (and unhides the button), then
-- "tutnext", "tutback", "tutclose" and "tuthide" (closes it and hides the button).
function Game:tutorial(color, action)
  if action == "tutorial" then
    Tutorial.setHidden(self, color, false)
    Tutorial.open(self, color, 1)
  elseif action == "tutnext" then
    Tutorial.turn(self, color, 1)
  elseif action == "tutback" then
    Tutorial.turn(self, color, -1)
  elseif action == "tutclose" then
    Tutorial.close(self, color)
  elseif action == "tuthide" then
    Tutorial.close(self, color)
    Tutorial.setHidden(self, color, true)
    return self:notify("Tutorial button hidden. Type !tutorial in chat to bring it back.", color)
  end
  self:refreshUI()
  return true
end

-- Clears a colour's private message once that player does something that works.
function Game:clearNotice(color)
  if self.notices.byColor[color] then
    self.notices.byColor[color] = nil
    self:refreshUI()
  end
end

function Game:newGame()
  Board.sweep(self)
  self:setupState()
  Board.sync(self)
  self:refreshUI()
end

-- Destroys and respawns every pile from the state, e.g. after cards were
-- dragged somewhere the engine doesn't read.
function Game:tidy()
  Board.sweep(self)
  Board.sync(self)
  self:refreshUI()
  return true
end

-- Runs an action, then redraws the piles that changed (next frame, so a card
-- the player just dropped isn't destroyed inside its own drop event).
function Game:act(action, ...)
  local ok, why = action(self, ...)
  if ok then
    Actions.settle(self, self.state.turn.active)
    Wait.frames(function()
      Board.sync(self)
      self:refreshUI()
    end, 1)
  end
  return ok, why
end

function Game:play(seat, uid) return self:act(Actions.play, seat, uid) end
function Game:playAll(seat) return self:act(Actions.playAll, seat) end
function Game:buy(seat, uid) return self:act(Actions.buy, seat, uid) end
function Game:scrapFromPlay(seat, uid) return self:act(Actions.scrapFromPlay, seat, uid) end
function Game:attack(seat, target, baseUid) return self:act(Actions.attack, seat, target, baseUid) end
function Game:pick(seat, value) return self:act(Actions.pick, seat, value) end
function Game:done(seat) return self:act(Actions.done, seat) end
function Game:endTurn(seat) return self:act(Actions.endTurn, seat) end

-- A Buy button was clicked on a market card or a fixed pile's deck object.
function Game:buyObject(seat, guid, uid)
  if uid == nil or uid == "" then
    local key = Board.pileOf(self, guid)
    local id = key and key:match("^fixed%.(.+)$")
    local pile = id and self.state.market.fixed[id]
    uid = pile and pile[#pile]
  end
  if not uid then return false, "That card can't be bought." end
  return self:buy(seat, uid)
end

-- The seat whose play or bases zone has this GUID, if any.
function Game:playZoneSeat(guid)
  local key = Zones.keyOf(self, guid)
  local seat = key and key:match("^(%d+)%.play$") or key and key:match("^(%d+)%.bases$")
  return tonumber(seat)
end

return Game
