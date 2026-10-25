-- Headless tests: run the bundled build/Global.lua against fake TTS globals.
-- Usage (from the repo root): python tools/bundle.py games/sample && lua tests/run.lua
local tts = dofile("tests/tts_stub.lua")

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("ok   " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

local function eq(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local HOST = { color = "White", host = true }
local GUEST = { color = "Red", host = false }

local function boot(saved)
  tts.reset()
  math.randomseed(7)
  dofile("build/Global.lua")
  onLoad(saved or "")
  if not Cardalyzer then error("onLoad failed: " .. table.concat(tts.broadcasts, "; ")) end
  return Cardalyzer.game
end

local function count(filter) return #tts.live(filter) end
local function ofType(kind) return function(o) return o.type == kind end end

-- Every card instance must be in exactly one pile.
local function assertConserved(game)
  local seen, total = {}, 0
  local function visit(list)
    for _, uid in ipairs(list) do
      if uid ~= "" then
        if seen[uid] then error("card " .. uid .. " is in two piles") end
        seen[uid] = true
        total = total + 1
      end
    end
  end
  for _, p in ipairs(game.state.players) do
    visit(p.deck); visit(p.hand); visit(p.discard); visit(p.play); visit(p.bases)
  end
  local m = game.state.market
  visit(m.deck); visit(m.row); visit(m.scrap)
  for _, pile in pairs(m.fixed) do visit(pile) end
  local instances = 0
  for _ in pairs(game.state.cards) do instances = instances + 1 end
  eq(total, instances, "cards in piles")
end

test("effect strings parse", function()
  boot()
  local Cards = Cardalyzer.require("engine.cards")
  local list = Cards.parseEffects("gold:2; draw:1;custom:freeRecruit")
  eq(#list, 3, "effects")
  eq(list[1].key, "gold"); eq(list[1].amount, 2)
  eq(list[3].fn, "freeRecruit")
  eq(#Cards.parseEffects(""), 0, "empty")
  eq(pcall(Cards.parseEffects, "gold"), false, "missing amount rejected")
  eq(pcall(Cards.parseEffects, "gold:x"), false, "non-number rejected")
end)

test("boot builds zones, hands and the UI", function()
  boot()
  eq(count(ofType("ScriptingTrigger")), 9, "scripting zones (4 per seat + market)")
  eq(count(ofType("HandTrigger")), 2, "hand zones")
  eq(count(function(o) return o.tags.cz_card end), 0, "no cards before New Game")
  assert(tts.ui.xml:find("Cardalyzer_onEndTurn"), "End Turn button in XML")
  assert(tts.ui.values.cz_turn:find("New Game"), "prompt to start")
end)

test("layout mirrors the two seats across the table", function()
  local game = boot()
  local a, b = game.layout.seats[1], game.layout.seats[2]
  for _, name in ipairs({ "play", "deck", "discard", "hand", "bases" }) do
    assert(math.abs(a[name].position[1] + b[name].position[1]) < 1e-9, name .. " x mirrored")
    assert(math.abs(a[name].position[3] + b[name].position[3]) < 1e-9, name .. " z mirrored")
  end
  assert(a.hand.position[3] < a.play.position[3], "seat 1 hand is behind its play area")
  eq(#game.layout.market.row, 5, "market slots")
end)

test("only the host can start a game", function()
  local game = boot()
  Cardalyzer_onStartGame(GUEST)
  eq(game.state.started, false, "started")
end)

test("New Game deals starter decks and fills the market", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  eq(s.started, true, "started")
  eq(#s.players[1].hand, 3, "first player opening hand")
  eq(#s.players[1].deck, 7, "first player deck")
  eq(#s.players[2].hand, 5, "second player opening hand")
  eq(#s.players[2].deck, 5, "second player deck")
  for i = 1, 5 do assert(s.market.row[i] ~= "", "market slot " .. i .. " filled") end
  eq(#s.market.deck, 29 - 5, "market deck")
  eq(#s.market.fixed.hireling, 10, "fixed pile")
  assertConserved(game)
  eq(s.turn.active, 1, "active seat")
end)

test("New Game spawns the right physical objects", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local decks = tts.live(ofType("Deck"))
  -- 2 player decks, market deck, hireling pile
  eq(#decks, 4, "deck objects")
  local cards = tts.live(ofType("Card"))
  eq(#cards, 3 + 5 + 5, "loose cards (hands + market row)")
  for _, deck in ipairs(decks) do
    eq(#deck.data.ContainedObjects, #deck.data.DeckIDs, "deck ids match contents")
    assert(deck.rotation[3] == 180 or deck.data.ContainedObjects[1].Nickname == "Hireling", "draw piles face down")
  end
  local card = cards[1].data
  assert(game.state.cards[card.GMNotes], "GMNotes holds a uid")
  assert(card.CustomDeck[1].FaceURL:find("art/sheet_1.jpg", 1, true), "face sheet url")
  assert(card.Description:find("Cost"), "description")
end)

test("the market deck's top card is the deck object's first card", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local top = game.state.market.deck[#game.state.market.deck]
  local guid = game.state.view.piles["market.deck"][1]
  eq(getObjectFromGUID(guid).data.ContainedObjects[1].GMNotes, top, "top card")
end)

test("End Turn is refused for the wrong player", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  Cardalyzer_onEndTurn(GUEST)
  eq(game.state.turn.active, 1, "still seat 1")
  assert(tts.broadcasts[#tts.broadcasts]:find("turn"), "told why")
end)

test("End Turn discards, draws a new hand and passes play", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  game.state.players[1].resources.gold = 4
  Cardalyzer_onEndTurn(HOST)
  local p = game.state.players[1]
  eq(#p.hand, 5, "new hand")
  eq(#p.discard, 3, "old hand discarded")
  eq(#p.deck, 2, "deck")
  eq(p.resources.gold, 0, "pools reset")
  eq(game.state.turn.active, 2, "active seat")
  eq(game.state.turn.number, 2, "turn number")
  eq(count(ofType("Card")), 5 + 5 + 5, "seat 1 hand re-rendered, old cards removed")
  assertConserved(game)
end)

test("drawing reshuffles the discard pile when the deck runs out", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  Cardalyzer_onEndTurn(HOST) -- seat 1: deck 2, discard 3
  Cardalyzer_onEndTurn(GUEST)
  local p = game.state.players[1]
  local drawn = game:draw(1, 4)
  eq(#drawn, 4, "drew through the reshuffle")
  eq(#p.discard, 0, "discard shuffled in")
  assertConserved(game)
  -- Empty deck and discard: draw stops instead of failing.
  for i = #p.hand, 1, -1 do p.hand[i] = nil end
  p.deck, p.discard = {}, {}
  eq(#game:draw(1, 3), 0, "nothing to draw")
end)

test("keyword and custom effects change state", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local Cards = Cardalyzer.require("engine.cards")
  local p1, p2 = game.state.players[1], game.state.players[2]
  local handBefore = #p1.hand
  game.effects:apply(game, 1, Cards.parseEffects("gold:2;might:3;health:4;draw:1;opponent_discard:1;custom:freeRecruit"))
  eq(p1.resources.gold, 2, "gold")
  eq(p1.resources.might, 3, "might")
  eq(p1.stats.health, 44, "health")
  eq(#p1.hand, handBefore + 1, "drew")
  eq(p2.pending.discard, 1, "opponent must discard")
  eq(p1.pending.freeRecruit.maxCost, 4, "custom effect ran")
  eq(game.effects:describe(Cards.parseEffects("gold:2;draw:1")), "+2 Gold, Draw 1", "describe")
end)

test("card data with an unknown keyword is reported", function()
  local Game = Cardalyzer.require("engine.game")
  local rules = Cardalyzer.require("game.rules")
  local ok, err = pcall(Game.new, {
    rules = rules,
    art = Cardalyzer.require("game.art"),
    cards = { { id = "bad", name = "Bad", cost = 1, copies = 1, effects = "teleport:2" } },
  })
  eq(ok, false, "rejected")
  assert(tostring(err):find("teleport"), "names the keyword")
end)

test("save and reload restores the game without respawning zones", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  Cardalyzer_onEndTurn(HOST)
  local saved = onSave()
  local zonesBefore = game.state.view.zones["1.play"]
  local hand = table.concat(game.state.players[1].hand, ",")

  -- Reload with the same objects still on the table.
  local objects, order = tts.objects, tts.order
  dofile("build/Global.lua")
  tts.objects, tts.order = objects, order
  local before = count(ofType("ScriptingTrigger"))
  onLoad(saved)
  local restored = Cardalyzer.game
  eq(count(ofType("ScriptingTrigger")), before, "no new zones")
  eq(restored.state.view.zones["1.play"], zonesBefore, "zone guid kept")
  eq(table.concat(restored.state.players[1].hand, ","), hand, "hand restored")
  eq(restored.state.turn.active, 2, "turn restored")
  assertConserved(restored)
end)

test("a corrupt save starts fresh instead of crashing", function()
  local game = boot("{not json")
  eq(game.state.started, false, "fresh state")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
