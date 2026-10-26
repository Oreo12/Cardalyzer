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
local function press(player, id) Cardalyzer_onUI(player, "-1", id) end

local function boot(saved)
  tts.reset()
  math.randomseed(7)
  dofile("build/Global.lua")
  onLoad(saved or "")
  if not Cardalyzer then error("onLoad failed: " .. table.concat(tts.broadcasts, "; ")) end
  return Cardalyzer.game
end

local function DBE_start() Cardalyzer_onStartGame(HOST) end

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
  assert(tts.ui.xml:find("cz-setup", 1, true), "New Game button in XML")
  assert(not tts.ui.xml:find("cz-new", 1, true), "setup menu closed until New Game is pressed")
  assert(tts.ui.xml:find("Press New Game"), "prompt to start")
  assert(not tts.ui.xml:find("cz-end", 1, true), "no action panel before the game starts")
end)

test("layout mirrors the two seats across the table", function()
  local game = boot()
  local a, b = game.layout.seats[1], game.layout.seats[2]
  for _, name in ipairs({ "play", "deck", "discard", "hand", "bases" }) do
    assert(math.abs(a[name].position[1] + b[name].position[1]) < 1e-9, name .. " x mirrored")
    assert(math.abs(a[name].position[3] + b[name].position[3]) < 1e-9, name .. " z mirrored")
  end
  assert(a.hand.position[3] < a.play.position[3], "seat 1 hand is behind its play area")
  -- Hand zones face their seat (yaw 0 for seat 1); a card-yaw hand shows cards upside down.
  eq(a.hand.rotation[2], 0, "seat 1 hand zone yaw")
  eq(b.hand.rotation[2], 180, "seat 2 hand zone yaw")
  eq(a.play.rotation[2], 180, "seat 1 table cards keep the card yaw")
  eq(a.hand.cardRotation[2], 180, "seat 1 hand cards use the card yaw")
  eq(b.hand.cardRotation[2], 0, "seat 2 hand cards use the card yaw")
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
  eq(#s.market.deck, 34 - 5, "market deck")
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

test("the UI: info panel on the right, action bar above the hand, Tidy table in the corner", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local xml = tts.ui.xml
  assert(xml:find('id="cz_panel" width="300" height="%d+" rectAlignment="LowerRight"'), "info panel on the right")
  assert(xml:find('id="cz_actions"[^>]*rectAlignment="LowerCenter" offsetXY="0 210"'), "action bar just above the hand")
  assert(xml:find('id="cz_tidy"[^>]*rectAlignment="LowerRight" offsetXY="%-12 70"'), "Tidy table above TTS's Notes button")
  assert(xml:find('id="cz_panel"[^>]*offsetXY="%-12 112"'), "info panel above it")
  assert(not xml:find('outline="#E8B84A"', 1, true), "no yellow borders")
  assert(not xml:find('color="#0E1620F2"', 1, true), "no panel backgrounds")
  assert(xml:find('id="cz%-end"[^>]*fontSize="17"[^>]*colors="#E8B84A'), "End Turn: bigger, gold")
  assert(xml:find('id="cz%-playall"[^>]*fontSize="17"[^>]*colors="#E8B84A'), "Play all: bigger, gold")
  assert(xml:find('id="cz%-tidy"[^>]*colors="#D6DEE8'), "other buttons light")
  assert(xml:find('id="cz_seat_2"[^>]*color="#E5413F"'), "seat names tinted")
  assert(not xml:find('color="[^"]*"[^>]-color="'), "no duplicate color attributes")
  eq(#tts.ui.assets, 4, "four symbols registered")

  -- Stats sit beside each name as symbols with the number over them.
  assert(xml:find('id="cz_stat_2_health"[^>]*><Image image="cz_heart"'), "health as a heart")
  assert(xml:find('id="cz_stat_2_health_n"[^>]*>40<'), "with the number on it")
  -- The active player's Trade/Combat sit above the action bar, only when above 0.
  assert(not xml:find("cz_res_", 1, true), "nothing to count at the start of the turn")
  game.state.players[1].resources.gold = 3
  game:refreshUI()
  xml = tts.ui.xml
  assert(xml:find('id="cz_res_White_gold"[^>]*><Image image="cz_coin"'), "gold as a coin")
  assert(xml:find('id="cz_res_White_gold_n"[^>]*>3<'), "showing 3")
  assert(not xml:find("cz_res_White_might", 1, true), "might hidden while it's 0")
  assert(xml:find('id="cz_res_Red_gold"', 1, true), "the other player sees it too")
  local barY = tonumber(xml:match('id="cz_actions"[^>]*offsetXY="0 (%d+)"'))
  local countersY = tonumber(xml:match('id="cz_counters_White"[^>]*offsetXY="0 (%d+)"'))
  assert(countersY > barY, "counters just above the bar")
  assert(not xml:match('<Panel id="cz_panel".-</Panel>'):find("cz_res_", 1, true), "not in the info panel")
  -- Each player can move their bar to sit above their own hand; it's remembered.
  press(HOST, "cz-barup")
  press(HOST, "cz-barup")
  local moved = tonumber(tts.ui.xml:match('id="cz_actions"[^>]*offsetXY="0 (%d+)"'))
  eq(moved, barY + 60, "two steps up")
  local restored = boot(game:save())
  eq(Cardalyzer.require("engine.ui").barY(restored, "White"), barY + 60, "kept after a reload")
  game = restored
  game.state.players[1].bases = {}
  -- A base in play shows a shield with its defense, in front of the heart.
  local State = Cardalyzer.require("engine.state")
  local vault = State.newCard(game.state, "seed_vault") -- defense from cards.csv
  game.state.players[1].bases[1] = vault
  game:refreshUI()
  xml = tts.ui.xml
  local def = game.cards:get("seed_vault").defense
  if def then
    assert(xml:find('id="cz_base_1_1"[^>]*><Image image="cz_shield"'), "a shield for the base")
    assert(xml:find("cz_base_1_1", 1, true) < xml:find("cz_stat_1_health", 1, true), "in front of the heart")
  end

  -- Choices go in the middle of the screen; the bar keeps the rest.
  game:prompt(1, { kind = "choice", options = { { key = "gold", amount = 1 }, { key = "might", amount = 1 } } })
  game:refreshUI()
  xml = tts.ui.xml
  assert(xml:find('id="cz_choice" visibility="White"[^>]*rectAlignment="MiddleCenter"'), "choice in the middle")
  local choice = xml:match('<Panel id="cz_choice".-</Panel>')
  assert(choice:find("cz-pick-1", 1, true), "its options there")
  assert(not choice:find("cz-end", 1, true), "End Turn stays in the bar")

  Cardalyzer_onEndTurn(GUEST)
  xml = tts.ui.xml
  assert(xml:find('id="cz_notice_' .. GUEST.color .. '" visibility="' .. GUEST.color .. '"', 1, true), "private notice")
  game:notify("Hello table")
  assert(tts.ui.xml:find("Hello table", 1, true), "public notice in the info panel")
  for i = 1, 5 do game:notify("msg " .. i) end
  assert(not tts.ui.xml:find("Hello table", 1, true), "only the latest three kept")
end)

test("New Game opens a setup menu; Play Game deals and closes it", function()
  local game = boot()
  local xml = tts.ui.xml
  assert(xml:find('id="cz%-setup"[^>]*>New Game<'), "the info panel only has New Game")
  assert(not xml:find("cz-tutorial", 1, true) and not xml:find("cz-players", 1, true), "settings are in the menu")
  press(GUEST, "cz-setup")
  assert(not tts.ui.xml:find("cz_setup_", 1, true), "only the host can open it")
  press(HOST, "cz-setup")
  xml = tts.ui.xml
  assert(xml:find('id="cz_setup_White" visibility="White"[^>]*rectAlignment="MiddleCenter"'), "menu in the middle, for the host")
  assert(xml:find('id="cz%-new"[^>]*>Play Game<'), "Play Game")
  assert(xml:find("cz-tutorial", 1, true) and xml:find("cz-players-3", 1, true), "Tutorial and player count")
  press(HOST, "cz-setupclose")
  assert(not tts.ui.xml:find("cz_setup_White", 1, true), "Close shuts it")
  press(HOST, "cz-setup")
  press(HOST, "cz-players-3")
  press(HOST, "cz-new")
  eq(game.state.started, true, "Play Game deals")
  eq(#game.state.players, 3, "with the chosen player count")
  assert(not tts.ui.xml:find("cz_setup_White", 1, true), "and closes the menu")
end)

test("cards dealt into a hand are turned 180 from the hand zone", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  for seat = 1, 2 do
    local hand = getObjectFromGUID(game.state.view.hands[game.state.players[seat].color])
    local guids = game.state.view.piles[seat .. ".hand"]
    assert(guids and #guids > 0, "hand cards spawned")
    for _, guid in ipairs(guids) do
      local card = getObjectFromGUID(guid)
      eq((card.rotation[2] - hand.rotation[2]) % 360, 180, "seat " .. seat .. " card yaw relative to hand")
      eq(card.rotation[3], 0, "face up")
    end
  end
end)

test("the tutorial opens, pages, closes and its button can be hidden", function()
  local game = boot()
  local BLUE_HOST = { color = "Blue", promoted = true }
  press(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz_setup_White".-cz%-tutorial'), "Tutorial button in the setup menu")
  press(HOST, "cz-tutorial")
  local xml = tts.ui.xml
  assert(xml:find('id="cz_tutorial_White" visibility="White"', 1, true), "tutorial only for its reader")
  assert(xml:find('rectAlignment="MiddleCenter"', 1, true), "middle of the screen")
  assert(xml:find("Welcome to Ember Guilds", 1, true), "page 1")
  assert(not xml:find("cz-tutback", 1, true), "no Back on page 1")
  press(HOST, "cz-tutnext")
  assert(tts.ui.xml:find("The info panel (right side)", 1, true), "page 2")
  for _ = 1, 10 do press(HOST, "cz-tutnext") end
  assert(tts.ui.xml:find("Page 5 of 5", 1, true), "stops at the last page")
  assert(not tts.ui.xml:find("cz-tutnext", 1, true), "no Next on the last page")
  press(HOST, "cz-tutback")
  assert(tts.ui.xml:find("Page 4 of 5", 1, true), "back a page")
  press(HOST, "cz-tutclose")
  assert(not tts.ui.xml:find("cz_tutorial_White", 1, true), "closed")

  press(HOST, "cz-tutorial")
  press(HOST, "cz-tuthide")
  xml = tts.ui.xml
  assert(not xml:find("cz_tutorial_White", 1, true), "hide also closes")
  assert(not xml:find('id="cz_setup_White".-cz%-tutorial'), "button hidden for White")
  press(BLUE_HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz_setup_Blue".-cz%-tutorial'), "still shown to others")
  assert(tts.ui.xml:find("!tutorial", 1, true), "told how to bring it back")

  local restored = boot(game:save())
  press(HOST, "cz-setup")
  assert(not tts.ui.xml:find("cz-tutorial", 1, true), "stays hidden after reload")
  eq(onChat("!tutorial", HOST), false, "chat command swallowed")
  assert(tts.ui.xml:find('id="cz_setup_White".-cz%-tutorial'), "button back")
  assert(tts.ui.xml:find("cz_tutorial_White", 1, true), "and the tutorial opens")
  eq(onChat("hello", HOST), true, "other chat passes through")
  assert(restored)
end)

test("a game can turn the Tutorial button off", function()
  local game = boot()
  game.rules.tutorial = false
  press(HOST, "cz-setup")
  assert(not tts.ui.xml:find("cz-tutorial", 1, true), "no Tutorial button")
  game.rules.tutorial = nil
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
  DBE_start()
  local Cards = Cardalyzer.require("engine.cards")
  local p1, p2 = game.state.players[1], game.state.players[2]
  local handBefore = #p1.hand
  game.effects:apply(game, 1, Cards.parseEffects("gold:2;might:3;health:4;draw:1;opponent_discard:1;custom:freeRecruit"))
  eq(p1.resources.gold, 2, "gold")
  eq(p1.resources.might, 3, "might")
  eq(p1.stats.health, 44, "health")
  eq(#p1.hand, handBefore + 1, "drew")
  eq(p2.owed.discard, 1, "opponent owes a discard")
  eq(p1.prompts[1].kind, "free_buy", "custom effect queued a prompt")
  eq(game.effects:describe(Cards.parseEffects("gold:2;draw:1")), "+2 Gold, Draw 1", "describe")
  eq(game.effects:describe(Cards.parseEffects("gold:3 | might:3")), "+3 Gold or +3 Might", "describe choice")
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

---------------------------------------------------------------------------
-- Actions: buying, playing, allies, prompts, attacks
---------------------------------------------------------------------------

local WHITE, RED = HOST, GUEST

-- A started game with every pile emptied, so a test places exactly the cards it needs.
local function blank()
  local game = boot()
  DBE_start()
  local State = Cardalyzer.require("engine.state")
  for _, p in ipairs(game.state.players) do
    p.deck, p.hand, p.discard, p.play, p.bases, p.prompts, p.owed = {}, {}, {}, {}, {}, {}, {}
    for k in pairs(p.resources) do p.resources[k] = 0 end
  end
  game.state.market.deck = {}
  for i = 1, #game.state.market.row do game.state.market.row[i] = "" end
  game.state.turn.allyFired = {}
  local function put(seat, pile, id)
    local uid = State.newCard(game.state, id)
    local list = game.state.players[seat][pile]
    list[#list + 1] = uid
    return uid
  end
  local function putRow(slot, id)
    local uid = State.newCard(game.state, id)
    game.state.market.row[slot] = uid
    return uid
  end
  local function putMarketDeck(id)
    local uid = State.newCard(game.state, id)
    game.state.market.deck[#game.state.market.deck + 1] = uid
    return uid
  end
  return game, put, putRow, putMarketDeck
end

local function click(player, id) Cardalyzer_onUI(player, "-1", id) end
local function has(list, v) return Cardalyzer.require("engine.util").indexOf(list, v) ~= nil end
local function lastBroadcast() return tts.broadcasts[#tts.broadcasts] or "" end

test("Buy button on a market card buys it and refills the slot", function()
  local game, _, putRow, putMarketDeck = blank()
  local smith = putRow(1, "ember_smith")
  local refill = putMarketDeck("tide_runner")
  game.state.players[1].resources.gold = 5
  game:tidy()
  local obj = getObjectFromGUID(game.state.view.piles["market.row.1"][1])
  eq(obj.buttons[1].click_function, "Cardalyzer_onBuy", "buy button")
  eq(obj.buttons[1].label, "Buy · 1", "button shows the cost")
  Cardalyzer_onBuy(obj, "White")
  local p = game.state.players[1]
  eq(p.resources.gold, 4, "paid")
  assert(has(p.discard, smith), "bought card in discard")
  eq(game.state.market.row[1], refill, "slot refilled from the market deck")
  eq(count(function(o) return o.data and o.data.GMNotes == smith end), 1, "bought card drawn once, in the discard pile")
end)

test("buying without enough gold is refused", function()
  local game, _, putRow = blank()
  local admiral = putRow(2, "fleet_admiral")
  game.state.players[1].resources.gold = 3
  local ok, why = game:buy(1, admiral)
  eq(ok, false, "refused")
  assert(why:find("costs 7", 1, true), why)
  eq(game.state.market.row[2], admiral, "still in the row")
  eq(game.state.players[1].resources.gold, 3, "nothing spent")
end)

test("buying from a fixed pile takes its top card, by the pile's deck object", function()
  local game = blank()
  game.state.players[1].resources.gold = 2
  game:tidy()
  local pile = game.state.market.fixed.hireling
  local top = pile[#pile]
  local deckObj = getObjectFromGUID(game.state.view.piles["fixed.hireling"][1])
  eq(deckObj.buttons[1].label, "Buy · 2", "pile has a buy button")
  Cardalyzer_onBuy(deckObj, "White")
  eq(#game.state.market.fixed.hireling, 9, "pile shrank")
  assert(has(game.state.players[1].discard, top), "top card bought")
end)

test("flags.buyToTop puts the next bought card on top of the deck", function()
  local game, _, putRow = blank()
  local smith = putRow(1, "ember_smith")
  local p = game.state.players[1]
  p.resources.gold = 1
  p.flags.buyToTop = true
  assert(game:buy(1, smith))
  eq(p.deck[#p.deck], smith, "on top of deck")
  eq(p.flags.buyToTop, nil, "flag used up")
end)

test("dropping a hand card into your play zone plays it", function()
  local game, put = blank()
  local uid = put(1, "hand", "apprentice")
  game:tidy()
  local obj = getObjectFromGUID(game.state.view.piles["1.hand"][1])
  obj.zones = { getObjectFromGUID(game.state.view.zones["1.play"]) }
  onObjectDrop("White", obj)
  local p = game.state.players[1]
  assert(has(p.play, uid), "in play")
  eq(#p.hand, 0, "left the hand")
  eq(p.resources.gold, 1, "effect applied")
  eq(getObjectFromGUID(obj.getGUID()), nil, "dropped object replaced by the play row's copy")
  -- Dropping into the other seat's zone, or when it isn't your turn, does nothing.
  local other = put(2, "hand", "apprentice")
  game:tidy()
  local theirs = getObjectFromGUID(game.state.view.piles["2.hand"][1])
  theirs.zones = { getObjectFromGUID(game.state.view.zones["2.play"]) }
  onObjectDrop("Red", theirs)
  assert(has(game.state.players[2].hand, other), "not Red's turn")
end)

test("Play all plays the whole hand", function()
  local game, put = blank()
  put(1, "hand", "apprentice"); put(1, "hand", "apprentice"); put(1, "hand", "squire")
  click(WHITE, "cz-playall")
  local p = game.state.players[1]
  eq(#p.play, 3, "all in play")
  eq(p.resources.gold, 2, "gold"); eq(p.resources.might, 1, "might")
end)

test("buildings stay in play and apply their effects again each turn", function()
  local game, put = blank()
  put(1, "hand", "seed_vault")
  game:playAll(1)
  local p = game.state.players[1]
  eq(#p.bases, 1, "in bases"); eq(#p.play, 0, "not in play row")
  eq(p.stats.health, 42, "played")
  click(WHITE, "cz-end"); click(RED, "cz-end")
  eq(#p.bases, 1, "survived cleanup")
  eq(p.stats.health, 44, "applied again at turn start")
end)

test("ally effects fire once per card when another card of its faction is in play", function()
  local game, put = blank()
  local a = put(1, "hand", "ember_smith")
  local b = put(1, "hand", "ember_smith")
  local p = game.state.players[1]
  game:play(1, a)
  eq(p.resources.might, 2, "no ally yet")
  game:play(1, b)
  eq(p.resources.might, 8, "both allies fired: 2 + 2 + 2 + 2")
  game:play(1, put(1, "hand", "war_anvil"))
  eq(p.resources.might, 11, "a third Forge card doesn't fire them again")
end)

test("two-faction cards, wild cards and faction-prefixed ally effects", function()
  local game, put = blank()
  local p = game.state.players[1]
  -- Stone Wall is Forge/Grove, so it is a Grove ally for Grove Tender.
  game:play(1, put(1, "hand", "grove_tender"))
  game:play(1, put(1, "hand", "stone_wall"))
  eq(p.stats.health, 40 + 2 + 3, "Grove Tender's ally fired")
  eq(p.prompts[1].kind, "choice", "Stone Wall's choice is waiting")
  -- Wild Shrine counts as every faction: Tide Runner's ally draws a card.
  put(1, "deck", "apprentice")
  game:play(1, put(1, "hand", "tide_runner"))
  eq(#p.hand, 0, "no ally yet")
  game:play(1, put(1, "hand", "wild_shrine"))
  eq(#p.hand, 1, "drew from the wild ally")
  -- Storm Caller (Tide) has veil=scrap_row:1: only a Veil card triggers it.
  local game2, put2, putRow2 = blank()
  putRow2(1, "ember_smith")
  local q = game2.state.players[1]
  game2:play(1, put2(1, "hand", "storm_caller"))
  game2:play(1, put2(1, "hand", "tide_runner"))
  for _, pr in ipairs(q.prompts) do assert(pr.kind ~= "scrap_row", "a Tide card is not a Veil ally") end
  game2:play(1, put2(1, "hand", "veil_cutpurse"))
  local kinds = {}
  for _, pr in ipairs(q.prompts) do kinds[pr.kind] = true end
  assert(kinds.scrap_row, "Veil card fired the prefixed ally")
end)

test("a choice is answered from the action panel and blocks End Turn until then", function()
  local game, put = blank()
  game:play(1, put(1, "hand", "harbor_broker"))
  local p = game.state.players[1]
  assert(tts.ui.xml:find("Choose one", 1, true), "prompt shown")
  assert(tts.ui.xml:find('id="cz-pick-2"', 1, true), "option buttons")
  assert(tts.ui.xml:find('visibility="White"', 1, true), "panel only for the active player")
  click(WHITE, "cz-end")
  eq(game.state.turn.active, 1, "End Turn refused")
  assert(lastBroadcast():find("Finish this first", 1, true), lastBroadcast())
  click(WHITE, "cz-pick-2")
  eq(p.resources.might, 3, "picked +3 Might")
  eq(p.resources.gold, 0, "not the other option")
  eq(#p.prompts, 0, "prompt answered")
end)

test("scrap_hand lets the player scrap cards from hand or discard", function()
  local game, put = blank()
  local junk = put(1, "hand", "squire")
  local old = put(1, "discard", "apprentice")
  game:play(1, put(1, "hand", "herbalist"))
  local p = game.state.players[1]
  eq(p.prompts[1].kind, "scrap", "prompt")
  assert(tts.ui.xml:find("Squire (hand)", 1, true), "lists hand cards")
  assert(tts.ui.xml:find("Apprentice (discard)", 1, true), "lists discard cards")
  click(WHITE, "cz-pick-" .. old)
  assert(has(game.state.market.scrap, old), "scrapped")
  eq(#p.prompts, 0, "up to 1: done after one")
  assert(has(p.hand, junk), "the other card stays")
end)

test("an opponent discard is owed until their turn, then must be answered", function()
  local game, put = blank()
  local red = game.state.players[2]
  local keep = put(2, "hand", "apprentice")
  local lose = put(2, "hand", "squire")
  game:play(1, put(1, "hand", "veil_cutpurse"))
  game:play(1, put(1, "hand", "veil_cutpurse"))
  eq(red.owed.discard, 2, "two owed")
  for _ = 1, 3 do put(1, "deck", "apprentice") end
  click(WHITE, "cz-end")
  eq(red.prompts[1].kind, "discard", "Red must discard")
  eq(red.prompts[1].count, 2, "two of them")
  assert(not tts.ui.xml:find("Skip", 1, true), "not optional")
  click(RED, "cz-end")
  eq(game.state.turn.active, 2, "can't end turn first")
  click(RED, "cz-pick-" .. lose)
  click(RED, "cz-pick-" .. keep)
  eq(#red.prompts, 0, "done")
  eq(#red.hand, 0, "both discarded")
end)

test("draw_discard draws, then asks for a discard", function()
  local game, put = blank()
  local drawn = put(1, "deck", "squire")
  game:play(1, put(1, "hand", "shade_scout"))
  local p = game.state.players[1]
  assert(has(p.hand, drawn), "drew")
  eq(p.prompts[1].kind, "discard", "then discard")
  click(WHITE, "cz-pick-" .. drawn)
  assert(has(p.discard, drawn), "discarded")
end)

test("destroy_base removes an opponent's base, even past guards", function()
  local game, put = blank()
  put(2, "bases", "stone_wall")
  local vault = put(2, "bases", "seed_vault")
  game:play(1, put(1, "hand", "storm_caller"))
  click(WHITE, "cz-pick-" .. vault)
  assert(has(game.state.players[2].discard, vault), "base went to its owner's discard")
  eq(#game.state.players[2].bases, 1, "the wall stays")
end)

test("a reminder shows the card text until the player clicks Done", function()
  local game, put = blank()
  game:play(1, put(1, "hand", "oracle"))
  local p = game.state.players[1]
  eq(p.resources.might, 1, "its other effect still applies")
  assert(tts.ui.xml:find("Oracle: Look at the top card", 1, true), "card text shown")
  click(WHITE, "cz-done")
  eq(#p.prompts, 0, "cleared")
end)

test("attacking spends the whole might pool on the opponent's health", function()
  local game = blank()
  local p, red = game.state.players[1], game.state.players[2]
  p.resources.might = 5
  game:refreshUI()
  assert(tts.ui.xml:find("Attack Red (5 Might)", 1, true), "attack button")
  click(WHITE, "cz-attack-2")
  eq(red.stats.health, 35, "hit")
  eq(p.resources.might, 0, "pool spent")
  click(WHITE, "cz-attack-2")
  assert(lastBroadcast():find("no Might", 1, true), lastBroadcast())
end)

test("guard buildings must fall before the player or other buildings", function()
  local game, put = blank()
  local wall = put(2, "bases", "stone_wall")
  local vault = put(2, "bases", "seed_vault")
  local p, red = game.state.players[1], game.state.players[2]
  p.resources.might = 9
  local ok, why = game:attack(1, 2)
  eq(ok, false, "player protected"); assert(why:find("guard", 1, true), why)
  ok = game:attack(1, 2, vault)
  eq(ok, false, "other base protected")
  game:refreshUI()
  assert(not tts.ui.xml:find("cz-attack-2", 1, true), "no attack-player button while guarded")
  assert(tts.ui.xml:find("cz-hit-2-" .. wall, 1, true), "can hit the wall")
  click(WHITE, "cz-hit-2-" .. wall)
  assert(has(red.discard, wall), "wall destroyed")
  eq(p.resources.might, 4, "spent its defense of 5")
  assert(game:attack(1, 2, vault), "vault is open now")
  eq(p.resources.might, 0)
end)

test("reducing the last opponent to 0 health wins the game", function()
  local game = blank()
  game.state.players[2].stats.health = 3
  game.state.players[1].resources.might = 5
  click(WHITE, "cz-attack-2")
  eq(game.state.winner, 1, "winner")
  assert(tts.ui.xml:find("White wins!", 1, true), "announced")
  assert(not tts.ui.xml:find("cz-end", 1, true), "action panel gone")
  local ok = game:endTurn(1)
  eq(ok, false, "game over")
end)

test("scrapping a card from play applies its scrap effect", function()
  local game, put = blank()
  local hireling = put(1, "hand", "hireling")
  game:play(1, hireling)
  click(WHITE, "cz-scrap-" .. hireling)
  local p = game.state.players[1]
  eq(p.resources.might, 2, "scrap effect")
  eq(p.resources.gold, 2, "play effect kept")
  assert(has(game.state.market.scrap, hireling), "in the scrap pile")
  eq(#p.play, 0, "left play")
end)

test("a custom effect can queue a free buy", function()
  local game, put, putRow = blank()
  local cheap = putRow(1, "seed_vault")
  putRow(2, "fleet_admiral")
  game.effects:apply(game, 1, { { key = "custom", fn = "freeRecruit" } })
  game:refreshUI()
  assert(tts.ui.xml:find("cz-pick-" .. cheap, 1, true), "cheap card offered")
  assert(not tts.ui.xml:find("Fleet Admiral", 1, true), "7-cost card not offered")
  click(WHITE, "cz-pick-" .. cheap)
  assert(has(game.state.players[1].discard, cheap), "taken for free")
  eq(game.state.players[1].resources.gold, 0, "nothing spent")
end)

test("prompts and owed discards survive save and reload", function()
  local game, put = blank()
  game:play(1, put(1, "hand", "harbor_broker"))
  game.state.players[2].owed.discard = 1
  local saved = onSave()
  local objects, order = tts.objects, tts.order
  dofile("build/Global.lua")
  tts.objects, tts.order = objects, order
  onLoad(saved)
  local restored = Cardalyzer.game.state
  eq(restored.players[1].prompts[1].kind, "choice", "prompt kept")
  eq(#restored.players[1].prompts[1].options, 2, "options kept")
  eq(restored.players[2].owed.discard, 1, "owed kept")
  click(WHITE, "cz-pick-1")
  eq(restored.players[1].resources.gold, 3, "answerable after reload")
end)

---------------------------------------------------------------------------
-- 2 to 4 players
---------------------------------------------------------------------------

local BLUE = { color = "Blue", host = false }

-- A game dealt for n seats, picked from the info panel as the host would.
local function startFor(n)
  local game = boot()
  click(HOST, "cz-players-" .. n)
  DBE_start()
  return game
end

-- Do two sized spots overlap on the table? Every yaw is 0 or 180, so a
-- spot's size maps straight onto the world x and z axes.
local function overlap(a, b)
  return math.abs(a.position[1] - b.position[1]) < (a.size[1] + b.size[1]) / 2
    and math.abs(a.position[3] - b.position[3]) < (a.size[3] + b.size[3]) / 2
end

test("3 and 4 seats sit on the two long sides without overlapping", function()
  local game = boot()
  local Zones = Cardalyzer.require("engine.zones")
  for _, n in ipairs({ 3, 4 }) do
    local layout = Zones.layout(game.rules, game.fixedIds, n)
    eq(#layout.seats, n, n .. " seats")
    local boxes = { { seat = 0, name = "market", spot = layout.market.area } }
    for seat, s in ipairs(layout.seats) do
      local bottom = seat <= math.ceil(n / 2)
      assert((s.play.position[3] < 0) == bottom, n .. " seats: seat " .. seat .. " is on the wrong side")
      assert(s.hand.position[3] * (bottom and 1 or -1) < s.play.position[3] * (bottom and 1 or -1), "hand behind play")
      eq(s.hand.rotation[2], bottom and 0 or 180, "seat " .. seat .. " hand zone faces its seat")
      for _, name in ipairs({ "play", "bases", "deck", "discard", "hand" }) do
        boxes[#boxes + 1] = { seat = seat, name = name, spot = s[name] }
      end
    end
    for i = 1, #boxes do
      for j = i + 1, #boxes do
        local a, b = boxes[i], boxes[j]
        if a.seat ~= b.seat and overlap(a.spot, b.spot) then
          error(n .. " seats: seat " .. a.seat .. " " .. a.name .. " overlaps seat " .. b.seat .. " " .. b.name)
        end
      end
    end
  end
  -- Seats are spaced evenly around the market at the centre: a pair sits the
  -- same distance either side of it, and a seat alone on its side is in line with it.
  local function x(seat, n) return Zones.layout(game.rules, game.fixedIds, n).seats[seat].play.position[1] end
  local market = Zones.layout(game.rules, game.fixedIds, 3).market.area.position[1]
  eq(market, 0, "market at the centre")
  eq(x(3, 3), 0, "3 seats: the lone seat is in line with the market")
  eq(x(1, 3) + x(2, 3), 0, "3 seats: the pair is centred on the market")
  assert(x(1, 3) < 0 and x(2, 3) > 0, "3 seats: one either side")
  eq(x(1, 4) + x(2, 4), 0, "4 seats: bottom pair centred")
  eq(x(3, 4) + x(4, 4), 0, "4 seats: top pair centred")
  eq(x(2, 4), x(3, 4), "4 seats: seats 2 and 3 face each other")
  eq(x(1, 4), x(4, 4), "4 seats: seats 1 and 4 face each other")
  -- Turn order runs along the bottom, then back along the top.
  local four = Zones.layout(game.rules, game.fixedIds, 4).seats
  assert(four[1].play.position[1] < four[2].play.position[1], "seat 2 is right of seat 1")
  -- Like two seats, the four sit point-symmetrically: seat 3 is seat 1 turned 180 degrees about the centre.
  for _, name in ipairs({ "play", "bases", "deck", "discard", "hand" }) do
    assert(math.abs(four[1][name].position[1] + four[3][name].position[1]) < 1e-9, name .. " x")
    assert(math.abs(four[1][name].position[3] + four[3][name].position[3]) < 1e-9, name .. " z")
  end
end)

test("the host picks 2 to 4 players and the table is laid out for them", function()
  local game = boot()
  assert(not tts.ui.xml:find('id="cz-players-4"', 1, true), "player count lives in the setup menu")
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz-players-4"', 1, true), "player-count buttons")
  click(GUEST, "cz-players-3")
  eq(#game.state.players, 2, "guests can't change it")
  click(HOST, "cz-players-4")
  eq(#game.state.players, 4, "four seats")
  eq(count(ofType("ScriptingTrigger")), 17, "4 zones per seat + market")
  eq(count(ofType("HandTrigger")), 4, "hand zones")
  click(HOST, "cz-players-3")
  eq(count(ofType("ScriptingTrigger")), 13, "the fourth seat's zones are removed")
  eq(count(ofType("HandTrigger")), 3, "and its hand zone")
  eq(game.state.view.hands.Green, nil, "Green's hand is forgotten")
  click(HOST, "cz-players-5")
  eq(#game.state.players, 3, "out of range refused")

  DBE_start()
  local s = game.state
  eq(#s.players, 3, "dealt for three")
  eq(#s.players[1].hand, 3, "first player draws 3")
  eq(#s.players[2].hand, 5, "second draws 5")
  eq(#s.players[3].hand, 5, "third draws 5")
  assertConserved(game)
  assert(tts.ui.xml:find('id="cz_seat_3"', 1, true), "a line per seat")

  -- During a game the choice waits for the next New Game.
  click(HOST, "cz-players-2")
  eq(#s.players, 3, "current game unchanged")
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz%-players%-2"[^>]*colors="#E8B84A'), "the setup menu remembers the choice")
  DBE_start()
  eq(#game.state.players, 2, "next game seats 2")
  eq(count(ofType("ScriptingTrigger")), 9, "back to two seats of zones")
end)

test("with three players, turns go round and a player at 0 health is out", function()
  local game = startFor(3)
  local s = game.state
  click(HOST, "cz-end"); eq(s.turn.active, 2, "seat 2")
  click(GUEST, "cz-end"); eq(s.turn.active, 3, "seat 3")
  click(BLUE, "cz-end"); eq(s.turn.active, 1, "back to seat 1")

  s.players[2].stats.health = 2
  s.players[2].owed.discard = 1
  s.players[1].resources.might = 5
  click(HOST, "cz-attack-2")
  eq(s.players[2].out, true, "Red is out")
  eq(s.winner, nil, "two players left")
  eq(s.players[2].owed.discard, nil, "owes nothing once out")
  assert(tts.ui.xml:find("Red: out", 1, true), "shown as out")
  s.players[1].resources.might = 3
  game:refreshUI()
  assert(not tts.ui.xml:find("cz-attack-2", 1, true), "no attack button for a player who is out")
  eq(game:attack(1, 2), false, "can't attack a player who is out")
  click(HOST, "cz-end"); eq(s.turn.active, 3, "Red's turn is skipped")

  s.players[1].stats.health = 1
  s.players[3].resources.might = 1
  click(BLUE, "cz-attack-1")
  eq(s.winner, 3, "last player left wins")
  assert(tts.ui.xml:find("Blue wins!", 1, true), "announced")
end)

test("with more than one opponent, an opponent discard asks which one", function()
  local game = startFor(3)
  local p1 = game.state.players[1]
  game.effects:apply(game, 1, Cardalyzer.require("engine.cards").parseEffects("opponent_discard:1"))
  game:refreshUI()
  eq(p1.prompts[1].kind, "opponent", "asks")
  assert(tts.ui.xml:find("Choose an opponent to discard 1 card next turn", 1, true), "prompt text")
  assert(tts.ui.xml:find('id="cz-pick-2"', 1, true) and tts.ui.xml:find('id="cz-pick-3"', 1, true), "both opponents offered")
  click(HOST, "cz-end")
  eq(game.state.turn.active, 1, "must choose first")
  click(HOST, "cz-pick-3")
  eq(game.state.players[3].owed.discard, 1, "Blue owes it")
  eq(game.state.players[2].owed.discard, nil, "Red doesn't")
  eq(#p1.prompts, 0, "answered")
end)

test("a three-player game saves and reloads with its layout", function()
  local game = startFor(3)
  click(HOST, "cz-end")
  local saved = onSave()
  local objects, order = tts.objects, tts.order
  dofile("build/Global.lua")
  tts.objects, tts.order = objects, order
  local before = count(ofType("ScriptingTrigger"))
  onLoad(saved)
  local restored = Cardalyzer.game
  eq(#restored.state.players, 3, "three players")
  eq(#restored.layout.seats, 3, "laid out for three")
  eq(count(ofType("ScriptingTrigger")), before, "no new zones")
  eq(restored.state.turn.active, 2, "turn restored")
  assertConserved(restored)
  assert(game)
end)

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------

test("a sheet can use its own back and the last slot as the hidden face", function()
  local game = boot()
  DBE_start()
  local Board = Cardalyzer.require("engine.board")
  local uid = game.state.market.row[1]
  local deck = Board.cardData(game, uid).CustomDeck[1]
  eq(deck.BackURL, "art/back.jpg", "art.json back by default")
  eq(deck.BackIsHidden, true, "hidden cards show the back by default")
  game.art.sheets[1].back = "https://example.com/other-back.jpg"
  game.art.sheets[1].hiddenFace = "last_slot"
  deck = Board.cardData(game, uid).CustomDeck[1]
  eq(deck.BackURL, "https://example.com/other-back.jpg", "the sheet's own back")
  eq(deck.BackIsHidden, false, "hidden cards show the sheet's last slot")
  game.art.sheets[1].back, game.art.sheets[1].hiddenFace = nil, nil
end)

test("art.json problems are reported when the game loads", function()
  boot()
  local Board = Cardalyzer.require("engine.board")
  local Game = Cardalyzer.require("engine.game")
  local game = Cardalyzer.game
  local art = {
    back = "back.jpg",
    sheets = { { file = "s.jpg", numWidth = 2, numHeight = 2, hiddenFace = "last_slot" } },
    cards = { apprentice = { sheet = 1, index = 3 }, squire = { sheet = 1, index = 4 }, hireling = { sheet = 2, index = 0 } },
  }
  local found = table.concat(Board.checkArt(art, game.cards), "\n")
  assert(found:find("'apprentice' is in sheet 1's last slot", 1, true), "last slot reserved")
  assert(found:find("'squire' slot 4 is outside sheet 1", 1, true), "slot out of range")
  assert(found:find("'hireling' is on sheet 2", 1, true), "unknown sheet")
  assert(found:find("'ember_smith' has no entry", 1, true), "missing card")
  local ok, err = pcall(Game.new, { rules = game.rules, cards = Cardalyzer.require("game.cards"), art = art })
  eq(ok, false, "Game.new refuses bad art")
  assert(tostring(err):find("art.json", 1, true), "says why")
end)

---------------------------------------------------------------------------
-- Hooks for unusual cards: triggers, copies, prompt options
---------------------------------------------------------------------------

test("a card in play can react to its owner playing another card", function()
  local game, put = blank()
  local seen = {}
  game.effects:registerCustom("watcher", {
    whenYouPlay = function(g, seat, ctx, played)
      seen[#seen + 1] = played.card.id
      local pools = g.state.players[seat].resources
      pools.might = pools.might + 1
    end,
  })
  local vault = game.cards:get("seed_vault")
  vault.effects[#vault.effects + 1] = { key = "custom", fn = "watcher" }
  local a1, b, a2 = put(1, "hand", "apprentice"), put(1, "hand", "seed_vault"), put(1, "hand", "apprentice")
  game:play(1, a1) -- before the watcher is in play
  game:play(1, b)
  game:play(1, a2)
  eq(#seen, 1, "fires only for cards played while it's in play, not for itself")
  eq(seen[1], "apprentice", "told which card")
  eq(game.state.players[1].resources.might, 1, "trigger applied")
  eq(table.concat(game.state.turn.played, ","), a1 .. "," .. b .. "," .. a2, "turn.played lists this turn's plays in order")
  for _ = 1, 5 do put(1, "deck", "apprentice") end
  click(WHITE, "cz-end")
  eq(#game.state.turn.played, 0, "cleared for the next turn")
end)

test("drawPerPick draws for each card picked once the prompt ends", function()
  local game, put = blank()
  local p = game.state.players[1]
  local s1, s2 = put(1, "hand", "squire"), put(1, "hand", "squire")
  put(1, "hand", "squire")
  for _ = 1, 3 do put(1, "deck", "apprentice") end
  game:prompt(1, { kind = "scrap", count = 2, optional = true, from = { "hand" }, drawPerPick = 1 })
  click(WHITE, "cz-pick-" .. s1)
  eq(#p.hand, 2, "no draw until the prompt ends")
  click(WHITE, "cz-pick-" .. s2)
  eq(#p.hand, 3, "drew one for each card scrapped")
  game:prompt(1, { kind = "discard", count = 2, optional = true, drawPerPick = 1 })
  click(WHITE, "cz-pick-" .. p.hand[1])
  click(WHITE, "cz-done")
  eq(#p.hand, 3, "stopping early draws for what was picked")
  eq(#p.deck, 0, "deck used")
end)

test("free buys can be limited to a card type, include fixed piles and go on top", function()
  local game, _, putRow = blank()
  local Actions = Cardalyzer.require("engine.actions")
  local admiral = putRow(1, "fleet_admiral")
  local oak = putRow(2, "old_oak")
  game:prompt(1, { kind = "free_buy", cardType = "unit", includeFixed = true, toTop = true, optional = true })
  game:refreshUI()
  local offered = {}
  for _, t in ipairs(Actions.targets(game, 1, game.state.players[1].prompts[1])) do offered[t.value] = true end
  assert(offered[admiral], "any cost when maxCost is left out")
  assert(not offered[oak], "other card types left out")
  local hirelings = game.state.market.fixed.hireling
  assert(offered[hirelings[#hirelings]], "top of a fixed pile offered")
  assert(tts.ui.xml:find("Take a unit from the market for free, onto your deck", 1, true), "prompt text")
  click(WHITE, "cz-pick-" .. admiral)
  local p = game.state.players[1]
  eq(p.deck[#p.deck], admiral, "on top of the deck")
  eq(p.resources.gold, 0, "nothing spent")
end)

test("flags.buyToTop can name a card type and waits for one", function()
  local game, _, putRow = blank()
  local vault, runner = putRow(1, "seed_vault"), putRow(2, "tide_runner")
  local p = game.state.players[1]
  p.resources.gold = 10
  p.flags.buyToTop = "unit"
  game:buy(1, vault)
  eq(p.discard[#p.discard], vault, "a building still goes to the discard pile")
  eq(p.flags.buyToTop, "unit", "flag kept for the next unit")
  game:buy(1, runner)
  eq(p.deck[#p.deck], runner, "the unit goes on top")
  eq(p.flags.buyToTop, nil, "flag used up")
end)

test("a card can copy another in play for the turn, with both cards' factions", function()
  local game, put = blank()
  local State = Cardalyzer.require("engine.state")
  game.effects:registerCustom("mimic", {
    apply = function(g, seat, ctx)
      g:prompt(seat, { kind = "pick", custom = "mimic", exclude = ctx.uid, cardType = "unit", text = "Copy a unit" })
    end,
    onPick = function(g, seat, uid, prompt)
      g:copyCard(seat, prompt.exclude, State.cardId(g.state, uid))
    end,
  })
  game.cards:get("veil_cutpurse").effects = { { key = "custom", fn = "mimic" } }
  local smith = put(1, "hand", "ember_smith")
  local mimic = put(1, "hand", "veil_cutpurse")
  game:play(1, smith)
  game:play(1, mimic)
  game:refreshUI()
  assert(tts.ui.xml:find("Copy a unit", 1, true), "asks what to copy")
  assert(tts.ui.xml:find("cz-pick-" .. smith, 1, true), "offers the other unit")
  assert(not tts.ui.xml:find("cz-pick-" .. mimic, 1, true), "not itself")
  click(WHITE, "cz-pick-" .. smith)
  local c = game:cardOf(mimic)
  eq(c.name, "Veil Cutpurse", "keeps its own name")
  eq(c.id, "ember_smith", "acts as the copied card")
  local factions = table.concat(c.factions, "/")
  assert(factions:find("veil", 1, true) and factions:find("forge", 1, true), "both factions: " .. factions)
  -- Smith 2 + copy 2, and both forge allies fire (each sees the other): 2 + 2.
  eq(game.state.players[1].resources.might, 8, "copied effects and allies")
  for _ = 1, 5 do put(1, "deck", "apprentice") end
  click(WHITE, "cz-end")
  eq(game:cardOf(mimic).id, "veil_cutpurse", "back to itself next turn")
end)

---------------------------------------------------------------------------
-- Dropping, animation and outlines
---------------------------------------------------------------------------

test("a card dropped while still lifted above the play area is played", function()
  local game, put = blank()
  local uid = put(1, "hand", "apprentice")
  game:tidy()
  local obj = getObjectFromGUID(game.state.view.piles["1.hand"][1])
  local area = game.layout.seats[1].play.position
  obj.position = { area[1] + 3, area[2] + 6, area[3] + 1 } -- high above the zone; TTS reports no zones
  obj.zones = {}
  onObjectDrop("White", obj)
  local p = game.state.players[1]
  assert(has(p.play, uid), "in play")
  eq(p.resources.gold, 1, "its effect applied")
  -- Dropped on the table outside the play area: nothing happens.
  local other = put(1, "hand", "squire")
  game:tidy()
  local stray = getObjectFromGUID(game.state.view.piles["1.hand"][1])
  stray.position = { 0, 2, 0 } -- the market, at the centre
  onObjectDrop("White", stray)
  assert(has(p.hand, other), "still in hand")
end)

local function liveCards() return count(function(o) return o.tags.cz_card end) end
local function ghosts() return tts.live(function(o) return o.tags.cz_card and o.locked end) end

test("New Game deals the market row and hands from their decks, one card after another", function()
  local game = boot()
  tts.deferTimers = true
  DBE_start()
  local layout = game.layout
  eq(game.state.view.piles["market.row.1"], nil, "row slot waits for its card to land")
  assert(#ghosts() > 0, "cards are in flight")
  tts.runTimers()
  eq(#ghosts(), 0, "flying cards removed when they land")
  local function to(f, p) return math.abs(f.to[1] - p[1]) < 1e-9 and math.abs(f.to[3] - p[3]) < 1e-9 end
  local slot1, last, handFlights, toSlot1 = layout.market.row[1].position, -1, 0, nil
  for _, f in ipairs(tts.flights) do
    eq(f.locked, true, "flying cards are locked")
    eq(f.interactable, false, "and can't be picked up")
    assert(f.at > last, "cards are dealt one after another")
    last = f.at
    if to(f, slot1) then toSlot1 = f end
    if to(f, layout.seats[1].hand.landing) then
      handFlights = handFlights + 1
      eq(f.rotation[3], 180, "a card dealt to a hand flies face down")
    end
  end
  eq(handFlights, 3, "three cards dealt to seat 1")
  assert(toSlot1, "a card flies to market slot 1")
  eq(toSlot1.uid, game.state.market.row[1], "the slot's own card")
  for i = 1, 5 do eq(#game.state.view.piles["market.row." .. i], 1, "row slot " .. i .. " drawn") end
  local tracked = 0
  for _, guids in pairs(game.state.view.piles) do tracked = tracked + #guids end
  eq(liveCards(), tracked, "nothing left over")
end)

test("a bought card flies from its slot to the discard pile, and a new one is dealt in", function()
  local game, _, putRow, putMarketDeck = blank()
  local bought = putRow(1, "tide_runner")
  putMarketDeck("seed_vault")
  game:tidy()
  game.state.players[1].resources.gold = 5
  tts.deferTimers, tts.flights = true, {}
  local slotAt = game.layout.market.row[1].position
  game:buy(1, bought)
  eq(#(game.state.view.piles["1.discard"] or {}), 0, "discard pile waits for the card to land")
  tts.runTimers()
  local discard = game.layout.seats[1].discard.position
  local toDiscard, toSlot = false, false
  for _, f in ipairs(tts.flights) do
    if math.abs(f.to[1] - discard[1]) < 1e-9 and math.abs(f.to[3] - discard[3]) < 1e-9 then toDiscard = f.uid == bought end
    if math.abs(f.to[1] - slotAt[1]) < 1e-9 and math.abs(f.to[3] - slotAt[3]) < 1e-9 then toSlot = f.uid == game.state.market.row[1] end
  end
  assert(toDiscard, "bought card flies to the discard pile")
  assert(toSlot, "replacement flies into the empty slot")
  eq(#game.state.view.piles["1.discard"], 1, "discard drawn after landing")
  eq(#game.state.view.piles["market.row.1"], 1, "slot refilled")
end)

test("a dropped card animates from where it was dropped, and Tidy table doesn't animate", function()
  local game, put = blank()
  local uid = put(1, "hand", "apprentice")
  game:tidy()
  local obj = getObjectFromGUID(game.state.view.piles["1.hand"][1])
  local area = game.layout.seats[1].play.position
  obj.position = { area[1] + 4, area[2] + 3, area[3] }
  tts.deferTimers, tts.flights = true, {}
  onObjectDrop("White", obj)
  local ghost = getObjectFromGUID(tts.flights[1].guid)
  eq(ghost.position[1], area[1], "lands on the play row")
  tts.runTimers()
  eq(#game.state.view.piles["1.play"], 1, "played card drawn")
  tts.flights = {}
  game:tidy()
  eq(#tts.flights, 0, "Tidy table draws instantly")
  assert(uid)
end)

test("a newer change to a pile cancels a draw still waiting on a flight", function()
  local game, put = blank()
  for _ = 1, 3 do put(1, "deck", "apprentice") end
  game:tidy()
  tts.deferTimers = true
  game:draw(1, 1)
  local Board = Cardalyzer.require("engine.board")
  Board.sync(game)
  game:draw(1, 1)
  Board.sync(game)
  tts.runTimers()
  eq(#game.state.view.piles["1.hand"], 2, "hand shows both cards, not the stale one-card draw")
  eq(#ghosts(), 0, "no flying cards left")
end)

test("play areas, decks, discards, the market and the scrap pile are outlined", function()
  local game = boot()
  local lines = tts.lines
  assert(lines, "vector lines set")
  -- 4 per seat, the market area, 5 row slots, market deck, 1 fixed pile, scrap
  eq(#lines, 2 * 4 + 1 + 5 + 1 + 1 + 1, "outlines")
  for _, l in ipairs(lines) do
    eq(#l.points, 4, "a rectangle")
    eq(l.loop, true, "closed")
  end
  eq(lines[1].color[1], 1, "White's play area in white")
  eq(lines[5].color[1], 0.9, "Red's in red")
  click(HOST, "cz-players-4")
  eq(#tts.lines, 4 * 4 + 9, "redrawn for four seats")
  game.rules.outlines = false
  click(HOST, "cz-players-2")
  eq(#tts.lines, 0, "rules.outlines = false turns them off")
end)

---------------------------------------------------------------------------
-- Moving cards by hand
---------------------------------------------------------------------------

-- Drops the object drawn for `uid` at table point (x, z), lifted as TTS does.
local function dropAt(game, color, uid, x, z)
  local obj
  for _, guids in pairs(game.state.view.piles) do
    for _, g in ipairs(guids) do
      local o = getObjectFromGUID(g)
      if o and o.data.GMNotes == uid then obj = o end
    end
  end
  assert(obj, "no object drawn for " .. uid)
  obj.position, obj.zones = { x, 4, z }, {}
  onObjectDrop(color, obj)
  return obj
end

test("engine cards never merge into decks", function()
  local game, put = blank()
  put(1, "discard", "apprentice"); put(1, "discard", "squire")
  game:tidy()
  local deck = getObjectFromGUID(game.state.view.piles["1.discard"][1])
  local card = spawnObjectData({ data = { Name = "Card", Tags = { "cz_card" } } })
  eq(tryObjectEnterContainer(deck, card), false, "an engine card can't join an engine deck")
  local other = spawnObjectData({ data = { Name = "Card" } })
  local bag = spawnObjectData({ data = { Name = "Bag" } })
  eq(tryObjectEnterContainer(bag, other), true, "other objects are left alone")
end)

test("dragging a market row card onto the scrap pile scraps it and refills the slot", function()
  local game, _, putRow, putMarketDeck = blank()
  local junk = putRow(1, "tide_runner")
  local next = putMarketDeck("seed_vault")
  game:tidy()
  local scrap = game.layout.market.scrap.position
  dropAt(game, "White", junk, scrap[1] + 0.5, scrap[3] - 0.5)
  local m = game.state.market
  assert(has(m.scrap, junk), "in the scrap pile")
  eq(m.row[1], next, "slot refilled from the market deck")
  eq(#game.state.view.piles["market.row.1"], 1, "and drawn")
  assert(tts.ui.xml:find("White scrapped Tide Runner from the market row.", 1, true), "announced to everyone")
  -- Not your turn: it goes back.
  local keep = m.row[1]
  dropAt(game, "Red", keep, scrap[1], scrap[3])
  eq(m.row[1], keep, "Red can't scrap on White's turn")
  eq(#game.state.view.piles["market.row.1"], 1, "card back in its slot")
  eq(getObjectFromGUID(game.state.view.piles["market.row.1"][1]).position[1], game.layout.market.row[1].position[1], "at its spot")
end)

test("dragging answers a waiting 'scrap from the market row' choice", function()
  local game, put, putRow = blank()
  local target = putRow(1, "tide_runner")
  game:play(1, put(1, "hand", "herbalist")) -- any card; then queue the choice directly
  game:prompt(1, { kind = "scrap_row", count = 1, optional = true })
  game:tidy()
  local scrap = game.layout.market.scrap.position
  dropAt(game, "White", target, scrap[1], scrap[3])
  assert(has(game.state.market.scrap, target), "scrapped")
  for _, pr in ipairs(game.state.players[1].prompts) do assert(pr.kind ~= "scrap_row", "choice answered") end
end)

test("dragging a card in play onto the scrap pile uses its scrap ability", function()
  local game, put = blank()
  local hireling = put(1, "hand", "hireling")
  game:play(1, hireling)
  game:tidy()
  local scrap = game.layout.market.scrap.position
  dropAt(game, "White", hireling, scrap[1], scrap[3])
  eq(game.state.players[1].resources.might, 2, "scrap ability applied")
  assert(has(game.state.market.scrap, hireling), "scrapped")
  -- A card without a scrap ability goes back to play.
  local smith = put(1, "hand", "ember_smith")
  game:play(1, smith)
  game:tidy()
  dropAt(game, "White", smith, scrap[1], scrap[3])
  assert(has(game.state.players[1].play, smith), "still in play")
  assert(lastBroadcast():find("has no scrap ability", 1, true), "told why")
end)

test("a card dropped somewhere the engine doesn't read goes back", function()
  local game, put = blank()
  local played = put(1, "hand", "apprentice")
  game:play(1, played)
  put(1, "deck", "squire"); put(1, "deck", "squire")
  game:tidy()
  dropAt(game, "White", played, 25, 25) -- off in a corner
  eq(#game.state.view.piles["1.play"], 1, "redrawn in the play area")
  -- A card pulled off a two-card deck: TTS leaves one loose card and a moved one.
  local deck = game.state.players[1].deck
  local pulled = spawnObjectData({ data = { Name = "Card", GMNotes = deck[2], Tags = { "cz_card" } } })
  local leftover = spawnObjectData({ data = { Name = "Card", GMNotes = deck[1], Tags = { "cz_card" } } })
  getObjectFromGUID(game.state.view.piles["1.deck"][1]).destruct() -- TTS removes the deck object
  pulled.position, pulled.zones = { 20, 3, -20 }, {}
  onObjectDrop("White", pulled)
  eq(getObjectFromGUID(pulled.getGUID()), nil, "the pulled card is removed")
  eq(getObjectFromGUID(leftover.getGUID()), nil, "and so is the loose leftover")
  eq(#game.state.view.piles["1.deck"], 1, "the deck is drawn again whole")
  local tracked = 0
  for _, guids in pairs(game.state.view.piles) do tracked = tracked + #guids end
  eq(count(function(o) return o.tags.cz_card end), tracked, "no stray cards")
end)

test("a hand card dropped on your play area on someone else's turn goes back to your hand", function()
  local game, put = blank()
  local uid = put(2, "hand", "apprentice")
  game:tidy()
  local area = game.layout.seats[2].play.position
  dropAt(game, "Red", uid, area[1], area[3])
  assert(has(game.state.players[2].hand, uid), "still in Red's hand")
  eq(#game.state.view.piles["2.hand"], 1, "drawn back in the hand")
  local tracked = 0
  for _, guids in pairs(game.state.view.piles) do tracked = tracked + #guids end
  eq(count(function(o) return o.tags.cz_card end), tracked, "no copy left in the play area")
end)

test("each ally ability that fires is announced", function()
  local game, put = blank()
  game:play(1, put(1, "hand", "ember_smith"))
  game:play(1, put(1, "hand", "ember_smith"))
  assert(tts.ui.xml:find("Ember Smith ally: +2 Might", 1, true), "shown in the info panel")
end)

---------------------------------------------------------------------------
-- No blinking, full play areas, "may" choices, blocked plays, game over
---------------------------------------------------------------------------

test("a landed card stays until the real one is drawn under it; redrawn piles never blink", function()
  local game, put = blank()
  local played = put(1, "hand", "apprentice")
  game:tidy()
  tts.deferTimers, tts.flights = true, {}
  game:play(1, played)
  local Board = Cardalyzer.require("engine.board")
  tts.runTimers(Board.TRAVEL + 0.01) -- just after landing
  eq(#game.state.view.piles["1.play"], 1, "the play row is drawn on landing")
  local ghost = getObjectFromGUID(tts.flights[1].guid)
  assert(ghost, "the flying copy is still there, covering the moment the real card takes to appear")
  tts.runTimers()
  eq(getObjectFromGUID(tts.flights[1].guid), nil, "then removed")
  local card = getObjectFromGUID(game.state.view.piles["1.play"][1])
  eq(card.locked, false, "the real card is unlocked once its pile is ready")
  eq(card.data.Locked, true, "it spawned locked, so it couldn't knock the old objects about")

  -- The old objects of a redrawn pile go only once the new ones are ready.
  local p = game.state.players[1]
  put(1, "discard", "squire")
  game:tidy()
  local oldPile = game.state.view.piles["1.discard"][1]
  p.discard[#p.discard + 1] = Cardalyzer.require("engine.state").newCard(game.state, "squire")
  local held = {}
  local real = spawnObjectData
  spawnObjectData = function(params) -- hold back TTS's "finished spawning" callbacks
    local cb = params.callback_function
    params.callback_function = function(o) held[#held + 1] = function() cb(o) end end
    return real(params)
  end
  Board.sync(game, { instant = true })
  spawnObjectData = real
  local newPile = game.state.view.piles["1.discard"][1]
  assert(newPile ~= oldPile, "a new discard pile was spawned")
  assert(getObjectFromGUID(oldPile), "the old pile stays while the new one is still appearing")
  eq(getObjectFromGUID(newPile).locked, true, "the new pile waits locked")
  for _, fire in ipairs(held) do fire() end
  eq(getObjectFromGUID(oldPile), nil, "the old pile goes once the new one is ready")
  eq(getObjectFromGUID(newPile).locked, false, "and the new one unlocks")
end)

test("a full play area closes up so every card stays inside it", function()
  local game, put = blank()
  for _ = 1, 10 do game:play(1, put(1, "hand", "apprentice")) end
  local spot = game.layout.seats[1].play
  local half = spot.size[1] / 2
  local lastY = -math.huge
  for _, guid in ipairs(game.state.view.piles["1.play"]) do
    local p = getObjectFromGUID(guid).position
    local along = (p[1] - spot.position[1]) * spot.right[1] + (p[3] - spot.position[3]) * spot.right[2]
    assert(math.abs(along) + 1.2 <= half + 1e-9, "card at " .. along .. " runs past the play area")
    assert(p[2] > lastY, "overlapping cards rest one above the next")
    lastY = p[2]
  end
  -- Five cards still sit side by side at the normal spacing.
  local game2, put2 = blank()
  for _ = 1, 5 do game2:play(1, put2(1, "hand", "apprentice")) end
  local a = getObjectFromGUID(game2.state.view.piles["1.play"][1]).position
  local b = getObjectFromGUID(game2.state.view.piles["1.play"][2]).position
  eq(math.abs(b[1] - a[1]) > 2.7, true, "normal spacing when there's room")
  eq(a[2], b[2], "and flat")
end)

test("flags.mayBuyToTop asks where the bought card goes", function()
  local game, _, putRow = blank()
  local first, second = putRow(1, "tide_runner"), putRow(2, "harbor_broker")
  local p = game.state.players[1]
  p.resources.gold = 10
  p.flags.mayBuyToTop = "unit"
  game:buy(1, first)
  game:refreshUI()
  assert(tts.ui.xml:find("Where should Tide Runner go?", 1, true), "asks")
  assert(tts.ui.xml:find("Top of your deck", 1, true) and tts.ui.xml:find("Your discard pile", 1, true), "both options")
  click(WHITE, "cz-pick-top")
  eq(p.deck[#p.deck], first, "on top of the deck")
  game:buy(1, second)
  eq(p.discard[#p.discard], second, "only the next one asks")
  eq(#p.prompts, 0, "no question for the second")
  -- Choosing the discard pile leaves it there.
  local g2, _, row2 = blank()
  local c = row2(1, "tide_runner")
  local p2 = g2.state.players[1]
  p2.resources.gold, p2.flags.mayBuyToTop = 5, "unit"
  g2:buy(1, c)
  click(WHITE, "cz-pick-discard")
  eq(p2.discard[#p2.discard], c, "left in the discard pile")
  eq(#p2.prompts, 0, "answered")
end)

test("an owed discard must be made before any card is played", function()
  local game, put = blank()
  local red = game.state.players[2]
  local a, b = put(2, "hand", "apprentice"), put(2, "hand", "squire")
  red.owed.discard = 1
  for _ = 1, 5 do put(1, "deck", "apprentice") end
  click(WHITE, "cz-end")
  eq(game.state.turn.active, 2, "Red's turn")
  assert(not tts.ui.xml:find("cz-playall", 1, true), "no Play all while the discard waits")
  click(RED, "cz-playall")
  eq(#red.hand, 2, "Play all refused")
  game:tidy()
  local area = game.layout.seats[2].play.position
  dropAt(game, "Red", a, area[1], area[3])
  assert(has(red.hand, a), "dragging a card into play is refused too")
  assert(lastBroadcast():find("First: Discard 1 card", 1, true), "told why")
  click(RED, "cz-pick-" .. b)
  assert(tts.ui.xml:find("cz-playall", 1, true), "Play all is back")
  click(RED, "cz-playall")
  assert(has(red.play, a), "and works")
end)

test("the winner is announced, with Play Again? to set up the next game", function()
  local game = blank()
  game.state.players[2].stats.health = 3
  game.state.players[1].resources.might = 5
  click(WHITE, "cz-attack-2")
  local xml = tts.ui.xml
  assert(xml:find('id="cz_winner"[^>]*rectAlignment="MiddleCenter"'), "winner panel in the middle")
  assert(xml:find(">White wins!<", 1, true), "names the winner")
  assert(xml:find('id="cz%-again"[^>]*>Play Again%?<'), "Play Again? button")
  local said = false
  for _, b in ipairs(tts.broadcasts) do if b == "White wins!" then said = true end end
  assert(said, "announced in chat too")
  click(RED, "cz-again")
  assert(not tts.ui.xml:find("cz_setup_", 1, true), "only the host can set up the next game")
  click(WHITE, "cz-again")
  xml = tts.ui.xml
  assert(xml:find('id="cz_setup_White"', 1, true), "Play Again? opens the setup menu")
  assert(not xml:find('id="cz_winner" visibility="White', 1, true), "the winner panel steps aside for it")
  click(WHITE, "cz-new")
  eq(game.state.winner, nil, "a new game")
  assert(not tts.ui.xml:find("cz_winner", 1, true), "winner panel gone")
end)

test("the market turns to face the player whose turn it is", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local function marketYaws()
    local out = {}
    for _, key in ipairs({ "market.row.1", "market.row.5", "market.deck", "fixed.hireling" }) do
      out[#out + 1] = getObjectFromGUID(game.state.view.piles[key][1]).rotation[2]
    end
    return out
  end
  for _, yaw in ipairs(marketYaws()) do eq(yaw, 180, "faces White (seat 1)") end
  local slot = game.state.view.piles["market.row.1"][1]
  Cardalyzer_onEndTurn(HOST)
  for _, yaw in ipairs(marketYaws()) do eq(yaw, 0, "faces Red across the table") end
  eq(game.state.view.piles["market.row.1"][1], slot, "turned in place, not respawned")
  Cardalyzer_onEndTurn(GUEST)
  for _, yaw in ipairs(marketYaws()) do eq(yaw, 180, "back to White") end
  game.rules.market.faceActive = false
  Cardalyzer_onEndTurn(HOST)
  for _, yaw in ipairs(marketYaws()) do eq(yaw, 180, "faceActive = false keeps it facing seat 1") end
  game.rules.market.faceActive = nil
end)

test("Settings: each player sets their own UI size and action bar height", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local xml = tts.ui.xml
  assert(xml:find('id="cz%-settings"[^>]*>Settings<'), "Settings button in the info panel")
  assert(not xml:find("cz-barup", 1, true), "the bar's arrows moved into Settings")
  click(GUEST, "cz-settings")
  xml = tts.ui.xml
  assert(xml:find('id="cz_settings_Red" visibility="Red"', 1, true), "opens for the player who asked, guests too")
  assert(xml:find('id="cz_set_ui_Red_value"[^>]*>100%%<'), "UI size starts at 100%")
  assert(xml:find("cz-uibigger", 1, true) and xml:find("cz-barreset", 1, true), "size and bar controls")

  -- Bigger UI for Red only: Red gets their own scaled copies of shared panels.
  click(GUEST, "cz-uibigger")
  click(GUEST, "cz-uibigger")
  xml = tts.ui.xml
  assert(xml:find('id="cz_set_ui_Red_value"[^>]*>125%%<'), "two steps up: 125%")
  assert(xml:find('id="cz_panel_2" visibility="Red" width="375"', 1, true), "Red's own info panel, drawn 25% bigger")
  assert(not xml:find(' scale="', 1, true), "drawn at real size, not with TTS's scale attribute")
  local from = xml:find('id="cz_panel_2"', 1, true)
  assert(xml:find('id="cz%-setup"[^>]*fontSize="18"', from), "its buttons' text 25% bigger too (14 -> 18)")
  assert(xml:find('id="cz%-setup"[^>]*colors="#D6DEE8', from), "buttons keep their look")
  assert(xml:find('id="cz_panel" visibility="White|Brown|Orange', 1, true), "everyone else keeps the normal one")
  assert(xml:find('id="cz_tidy_2" visibility="Red" width="150"', 1, true), "and Tidy table")
  assert(xml:find('id="cz_settings_Red" visibility="Red" width="825"', 1, true), "menus too")
  local normalBottom = tonumber(xml:match('id="cz_panel"[^>]*offsetXY="%-12 (%d+)"'))
  local redBottom = tonumber(xml:match('id="cz_panel_2"[^>]*offsetXY="%-12 (%d+)"'))
  assert(redBottom > normalBottom, "Red's info panel sits higher, above the bigger Tidy button")
  for _ = 1, 10 do click(GUEST, "cz-uibigger") end
  assert(tts.ui.xml:find('id="cz_set_ui_Red_value"[^>]*>155%%<'), "stops at the largest")

  -- The action bar: White's own height, in White's settings.
  click(HOST, "cz-settings")
  local before = Cardalyzer.require("engine.ui").barY(game, "White")
  click(HOST, "cz-barup")
  eq(Cardalyzer.require("engine.ui").barY(game, "White"), before + 30, "Up")
  assert(tts.ui.xml:find('id="cz_set_bar_White_value"[^>]*>%+30<'), "shown")
  click(HOST, "cz-barreset")
  eq(Cardalyzer.require("engine.ui").barY(game, "White"), before, "Reset")
  click(HOST, "cz-uismaller")
  assert(tts.ui.xml:find('id="cz_actions" visibility="White" width="1008"', 1, true), "White's bar drawn at 90%")

  -- Kept after a reload; menus closed.
  local restored = boot(game:save())
  local UI = Cardalyzer.require("engine.ui")
  eq(UI.scaleOf(restored, "Red"), 1.55, "Red's size kept")
  eq(UI.scaleOf(restored, "White"), 0.9, "White's size kept")
  click(GUEST, "cz-settingsclose")
  assert(not tts.ui.xml:find("cz_settings_Red", 1, true), "Close shuts it")
end)

test("messages to an empty seat don't stop the game", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  tts.empty.Red = true -- the host is playing Red's turns, or Red left
  Cardalyzer_onEndTurn(HOST)
  eq(game.state.turn.active, 2, "Red's turn")
  click(GUEST, "cz-playall")
  click(GUEST, "cz-playall") -- the hand is empty now: a private "Your hand is empty."
  assert(tts.ui.xml:find('id="cz_notice_Red"', 1, true), "still shown on Red's screen")
  click(GUEST, "cz-end")
  eq(game.state.turn.active, 1, "and the turn carried on")
  for _, b in ipairs(tts.broadcasts) do assert(not b:find("%[Cardalyzer%]"), "no script error: " .. b) end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
