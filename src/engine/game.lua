-- Game facade: wires the modules together and is what main.lua, effect
-- handlers and custom effects talk to. Holds rules, cards, effects, art,
-- layout and the saved state.
local Cards = require("engine.cards")
local Effects = require("engine.effects")
local State = require("engine.state")
local Turn = require("engine.turn")
local Zones = require("engine.zones")
local Board = require("engine.board")
local UI_ = require("engine.ui")

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

function Game:setupState()
  local view = self.state.view
  self.state = State.new(self.rules)
  self.state.view = view -- keep zone GUIDs so zones aren't respawned
  Turn.setup(self.state, self.rules, self.cards, self.random)
end

function Game:endTurnState()
  return Turn.endTurn(self.state, self.rules, self.random)
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
  UI_.build(self)
  -- setXml is applied on the next frame, so values are set after it.
  Wait.frames(function() self:refreshUI() end, 1)
end

function Game:refreshUI()
  UI_.refresh(self)
end

function Game:newGame()
  Board.sweep(self)
  self:setupState()
  Board.render(self)
  self:refreshUI()
end

function Game:endTurn(color)
  if not self.state.started then return false, "The game hasn't started." end
  local seat = self:seatOfColor(color)
  if seat ~= self.state.turn.active then
    return false, "It's " .. self.state.players[self.state.turn.active].name .. "'s turn."
  end
  self:endTurnState()
  Board.render(self, { seat .. "." })
  self:refreshUI()
  return true
end

return Game
