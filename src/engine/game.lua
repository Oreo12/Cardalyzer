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
  for _, p in ipairs(Board.checkArt(self.art, self.cards)) do problems[#problems + 1] = p end
  local range = Game.playerRange(self.rules)
  if range.min > range.max then
    problems[#problems + 1] = "rules.players.min is " .. range.min .. " but rules.seats only lists " .. range.max
  end
  if #problems > 0 then error("card data problems:\n  " .. table.concat(problems, "\n  "), 0) end

  self.fixedIds = {}
  for _, card in ipairs(self.cards:inDeck("fixed")) do self.fixedIds[#self.fixedIds + 1] = card.id end
  self.state = State.new(self.rules, Zones.defaultCount(self.rules))
  self:relayout()
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

-- The other seats still in the game (players who are out are left out).
function Game:opponentsOf(seat)
  local out = {}
  for other, p in ipairs(self.state.players) do
    if other ~= seat and not p.out then out[#out + 1] = other end
  end
  return out
end

-- How many players a game can seat: { min, max }. max is #rules.seats.
function Game.playerRange(rules)
  local players = rules.players or {}
  return { min = players.min or #rules.seats, max = #rules.seats }
end

-- Positions every pile for the number of seats in the current state.
function Game:relayout()
  self.layout = Zones.layout(self.rules, self.fixedIds, #self.state.players)
end

function Game:draw(seat, n)
  return Turn.draw(self.state, seat, n, self.random)
end

-- The card a uid acts as right now: its own card, or, while it copies
-- another card this turn (see Game:copyCard), that card's effects, allies
-- and scrap ability, with both cards' factions and its own name.
function Game:cardOf(uid)
  local own = self.cards:get(State.cardId(self.state, uid))
  local copied = self.state.turn.copies and self.state.turn.copies[uid]
  if not copied then return own end
  local merged = setmetatable({ name = own.name, factions = {} }, { __index = self.cards:get(copied) })
  for _, list in ipairs({ own.factions, self.cards:get(copied).factions }) do
    for _, f in ipairs(list) do
      if f ~= "none" then merged.factions[#merged.factions + 1] = f end
    end
  end
  merged.faction = merged.factions[1] or "none"
  return merged
end

-- Makes `uid` act as card `id` until the end of the turn ("copy another
-- ship you've played"), applies that card's effects, then checks allies.
function Game:copyCard(seat, uid, id)
  self.state.turn.copies = self.state.turn.copies or {}
  self.state.turn.copies[uid] = id
  local c = self:cardOf(uid)
  self.effects:apply(self, seat, c.effects, { uid = uid, card = c })
  Actions.checkAllies(self, seat)
end

-- Queues a choice for a player; custom effects use this too, e.g.
-- game:prompt(seat, { kind = "free_buy", maxCost = 4 }). See engine/actions.lua.
function Game:prompt(seat, prompt)
  Actions.prompt(self, seat, prompt)
end

-- Deals a new game for state.nextPlayers seats (set by Game:setPlayers),
-- or as many as are playing now.
function Game:setupState()
  local view = self.state.view
  local count = self.state.nextPlayers or #self.state.players
  self.state = State.new(self.rules, count)
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
  local players = type(data.players) == "table" and #data.players or 0
  if players < 1 or players > #self.rules.seats then return false end
  self.state = data
  self:relayout()
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

-- Opens or closes the setup menu (New Game) for one player. Not saved.
function Game:setup(color, open)
  self.setupOpen = self.setupOpen or {}
  self.setupOpen[color] = open or nil
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

-- Deals a new game; hands and the market row are dealt out from their decks.
function Game:newGame()
  Board.sweep(self)
  Board.forgetPlaces(self)
  self:setupState()
  self:relayout()
  Zones.build(self, self.layout)
  Board.sync(self)
  self:refreshUI()
end

-- Sets how many players the next New Game deals for. Before the first game
-- the table is laid out for them straight away.
function Game:setPlayers(n)
  local range = Game.playerRange(self.rules)
  if not n or n < range.min or n > range.max then
    return false, "This game seats " .. range.min .. " to " .. range.max .. " players."
  end
  if self.state.started then
    self.state.nextPlayers = n ~= #self.state.players and n or nil
    self:refreshUI()
    return true
  end
  local view = self.state.view
  self.state = State.new(self.rules, n)
  self.state.view = view
  self:relayout()
  Zones.build(self, self.layout)
  self:refreshUI()
  return true
end

-- Destroys and respawns every pile from the state, e.g. after cards were
-- dragged somewhere the engine doesn't read.
function Game:tidy()
  Board.sweep(self)
  Board.sync(self, { instant = true })
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

-- The seat whose play or bases area holds table point (x, z), if any.
function Game:playSeatAt(x, z)
  return Zones.playSeatAt(self.layout, x, z)
end

-- The key of the pile that holds this uid ("1.hand", "market.row.3"), if any.
function Game:pileHolding(uid)
  if uid == nil or uid == "" then return nil end
  for _, pile in ipairs(Board.piles(self)) do
    for _, u in ipairs(pile.uids) do
      if u == uid then return pile.key end
    end
  end
  return nil
end

-- Puts a pile back the way the state says (next frame, outside the drop
-- event): the dropped object is removed and the pile drawn again.
function Game:putBack(key, guid)
  Wait.frames(function()
    local obj = getObjectFromGUID(guid)
    if obj then obj.destruct() end
    Board.redraw(self, key)
  end, 1)
end

-- A player dropped an engine card (or a whole pile) at `pos`. Moves the
-- engine understands become actions:
--   a card from your hand on your play or bases area -> played
--   a card dropped on the scrap pile -> scrapped (see Game:scrapDropped)
--   a card rearranged within your hand -> left alone
-- Anything else, or a move that's refused, goes back where it belongs.
function Game:dropped(color, guid, uid, pos, inOwnPlayZone)
  local key = self:pileHolding(uid) or Board.pileOf(self, guid)
  if not key then return false end
  local seat = self:seatOfColor(color)
  local x, z = pos[1], pos[3]
  local ok, why = false, nil
  local fromHand = seat and key == seat .. ".hand"
  if fromHand and (inOwnPlayZone or self:playSeatAt(x, z) == seat) then
    self:cardDroppedAt(uid, pos) -- the card animates from where it was dropped
    ok, why = self:play(seat, uid)
  elseif seat and Zones.onScrap(self.layout, x, z) then
    ok, why = self:scrapDropped(seat, uid, key)
  elseif fromHand and Zones.contains(self.layout.seats[seat].hand, x, z, 1) then
    return false
  end
  if ok then return true end
  self:putBack(key, guid)
  return false, why
end

-- A card dropped on the scrap pile by `seat`, on their turn:
--   from the market row -> answers a "scrap from the market row" choice if one
--     is waiting, otherwise scraps it (announced) and the slot refills
--   from your play area or bases -> uses its scrap ability
--   from your hand or discard pile -> answers a waiting scrap choice
function Game:scrapDropped(seat, uid, key)
  local player = self.state.players[seat]
  local prompt = player.prompts[1]
  local c = uid ~= "" and self:cardOf(uid)
  if not c then return false, "Drop one card at a time on the scrap pile." end
  if key:match("^market%.row%.") then
    if prompt and prompt.kind == "scrap_row" then return self:pick(seat, uid) end
    local ok, why = self:act(Actions.scrapFromRow, seat, uid)
    if ok then self:notify(player.name .. " scrapped " .. c.name .. " from the market row.") end
    return ok, why
  elseif key == seat .. ".play" or key == seat .. ".bases" then
    return self:scrapFromPlay(seat, uid)
  elseif (key == seat .. ".hand" or key == seat .. ".discard") and prompt and prompt.kind == "scrap" then
    return self:pick(seat, uid)
  end
  return false, c.name .. " can't be scrapped now."
end

-- Records where a player dropped a card, so it animates from there.
function Game:cardDroppedAt(uid, position)
  local view = self.state.view
  view.at = view.at or {}
  view.at[uid] = position
end

-- The seat whose play or bases zone has this GUID, if any.
function Game:playZoneSeat(guid)
  local key = Zones.keyOf(self, guid)
  local seat = key and key:match("^(%d+)%.play$") or key and key:match("^(%d+)%.bases$")
  return tonumber(seat)
end

return Game
