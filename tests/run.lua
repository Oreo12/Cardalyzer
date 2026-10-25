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
  assert(tts.ui.xml:find("cz-new", 1, true), "New Game button in XML")
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

test("the info panel stands alone at the top centre and holds messages", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local xml = tts.ui.xml
  assert(xml:find('id="cz_panel" width="620" height="%d+" rectAlignment="UpperCenter"'), "info panel centred")
  assert(xml:find('id="cz_actions"[^>]*rectAlignment="UpperRight"'), "action panel kept to the side")
  assert(xml:find('id="cz_seat_2" fontSize="15" color="#E5413F"', 1, true), "seat lines tinted")
  assert(not xml:find('color="[^"]*"[^>]-color="'), "no duplicate color attributes")

  Cardalyzer_onEndTurn(GUEST)
  xml = tts.ui.xml
  assert(xml:find('id="cz_notice_' .. GUEST.color .. '" visibility="' .. GUEST.color .. '"', 1, true), "private notice panel")
  assert(xml:find("turn", 1, true), "reason shown in the UI")

  game:notify("Hello table")
  assert(tts.ui.xml:find("Hello table", 1, true), "public notice in the info panel")
  for i = 1, 5 do game:notify("msg " .. i) end
  assert(not tts.ui.xml:find("Hello table", 1, true), "only the latest three kept")
  assert(tts.ui.xml:find("msg 5", 1, true), "newest kept")

  Cardalyzer_onEndTurn(HOST)
  assert(tts.ui.xml:find('id="cz_notice_' .. GUEST.color .. '"', 1, true), "guest notice stays until the guest acts")
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

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
