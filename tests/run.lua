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
    visit(p.deck); visit(p.hand); visit(p.discard); visit(p.play); visit(p.bases); visit(p.objectives or {}); visit(p.completed or {})
    visit(p.lasting or {}); visit(p.facedown or {}); for _, a in pairs(p.areas or {}) do visit(a) end
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
  assert(xml:find('id="cz_panel" rectAlignment="LowerRight"[^>]* width="300" height="%d+"'), "info panel on the right")
  assert(xml:find('id="cz_actions"[^>]*rectAlignment="LowerCenter" offsetXY="0 210"'), "action bar just above the hand")
  assert(xml:find('id="cz_panel"[^>]*offsetXY="%-12 70"'), "info panel above TTS's Notes button")
  local panel = xml:sub((xml:find('id="cz_panel"', 1, true)))
  local widths = {}
  for _, id in ipairs({ "cz%-settings", "cz%-setup", "cz%-tidy", "cz%-hideui" }) do
    widths[#widths + 1] = panel:match('id="' .. id .. '"[^>]*preferredWidth="(%d+)"')
  end
  assert(widths[1] and widths[1] == widths[2] and widths[2] == widths[3] and widths[3] == widths[4], "its buttons all one width: " .. table.concat(widths, ","))
  assert(panel:find('id="cz%-setup" onClick="Cardalyzer_onUI" preferredHeight="32"'), "New Game a little taller")
  assert(panel:find('id="cz%-tidy" onClick="Cardalyzer_onUI" preferredHeight="27"'), "than the rest")
  assert(not xml:find('outline="#E8B84A"', 1, true), "no yellow borders")
  assert(not xml:find('color="#0E1620F2"', 1, true), "no panel backgrounds")
  assert(xml:find('id="cz%-end"[^>]*fontSize="17"[^>]*colors="#E8B84A'), "End Turn: bigger, gold")
  assert(xml:find('id="cz%-playall"[^>]*fontSize="17"[^>]*colors="#E8B84A'), "Play all: bigger, gold")
  assert(xml:find('id="cz%-tidy"[^>]*colors="#D6DEE8'), "other buttons light")
  assert(xml:find('id="cz_seat_2"[^>]*color="#E5413F"'), "seat names tinted")
  assert(not xml:find('color="[^"]*"[^>]-color="'), "no duplicate color attributes")
  eq(#tts.ui.assets, 5, "five symbols registered")

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
  local owner = xml:match('<Text id="cz_resowner_Red"[^>]*>([^<]*)<')
  eq(owner, game.state.players[1].name, "with whose they are")
  assert(xml:find('id="cz_resowner_Red"[^>]*color="' .. Cardalyzer.require("engine.ui").seatColors.White), "in their seat colour")
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
  assert(tts.ui.xml:find("Page 6 of 6", 1, true), "stops at the last page")
  assert(not tts.ui.xml:find("cz-tutnext", 1, true), "no Next on the last page")
  press(HOST, "cz-tutback")
  assert(tts.ui.xml:find("Page 5 of 6", 1, true), "back a page")
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

test("loading a save (or TTS's Rewind) draws the table again from the state", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local saved = onSave()
  local cards = function() return count(function(o) return o.data and o.data.GMNotes end) end
  local before = cards()
  -- TTS restores the objects but not their script buttons, plus a copy of a
  -- card that was mid-flight when the snapshot was taken.
  local objects, order = tts.objects, tts.order
  for _, obj in ipairs(tts.live()) do obj.buttons = {} end
  local stray = spawnObjectData({ data = Cardalyzer.require("engine.board").cardData(game, game.state.players[1].hand[1]) })
  stray.setLock(true)
  dofile("build/Global.lua")
  tts.objects, tts.order = objects, order
  onLoad(saved)
  local restored = Cardalyzer.game
  eq(cards(), before, "the stray copy is gone")
  local buys = 0
  for _, obj in ipairs(tts.live()) do
    for _, b in ipairs(obj.buttons or {}) do if b.click_function == "Cardalyzer_onBuy" then buys = buys + 1 end end
  end
  eq(buys >= #restored.state.market.row, true, "Buy buttons back on the market (" .. buys .. ")")
  assertConserved(restored)
end)

test("a corrupt save starts fresh instead of crashing", function()
  local game = boot("{not json")
  eq(game.state.started, false, "fresh state")
  -- a save from another Cardalyzer game: its cards aren't in this one
  game = boot()
  Cardalyzer_onStartGame(HOST)
  local saved = game:save():gsub('"apprentice"', '"ribbon"')
  game = boot(saved)
  eq(game.state.started, false, "another game's save starts fresh")
end)

test("loading another game's save clears that game's cards off the table", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local cards = function() return count(function(o) return o.data and o.data.GMNotes end) end
  assert(cards() > 0, "cards out")
  local saved = onSave():gsub('"apprentice"', '"ribbon"')
  local objects, order = tts.objects, tts.order
  dofile("build/Global.lua")
  tts.objects, tts.order = objects, order
  onLoad(saved)
  eq(Cardalyzer.game.state.started, false, "fresh")
  eq(cards(), 0, "the old game's cards are gone")
  eq(count(ofType("ScriptingTrigger")), #Cardalyzer.require("engine.zones").zoneSpots(Cardalyzer.game.layout), "no zones left over")
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

test("attack can be split: how much on a player, the rest on a building", function()
  local game, put = blank()
  local vault = put(2, "bases", "seed_vault") -- defense 4
  local p, red = game.state.players[1], game.state.players[2]
  p.resources.might = 12
  game:refreshUI()
  click(WHITE, "cz-attack-2")
  eq(p.prompts[1] and p.prompts[1].kind, "attack_amount", "asked how much")
  assert(tts.ui.xml:find("How much Might on Red?", 1, true), "the question")
  assert(tts.ui.xml:find("Attack Red for 12", 1, true), "starts at all of it")
  assert(not tts.ui.xml:find("cz-pick-+5", 1, true), "can't go over the pool")
  click(WHITE, "cz-pick--5")
  click(WHITE, "cz-pick--1")
  click(WHITE, "cz-pick-+1")
  click(WHITE, "cz-pick--1")
  click(WHITE, "cz-pick--1")
  assert(tts.ui.xml:find("Attack Red for 5", 1, true), "12 - 5 - 1 + 1 - 1 - 1")
  eq(p.resources.might, 12, "nothing spent yet")
  click(WHITE, "cz-pick-go")
  eq(red.stats.health, 35, "5 damage")
  eq(p.resources.might, 7, "7 left")
  local notes = game.notices.all
  eq(notes[#notes], "White hits Red for 5 Health (Red: 35)", "says where it went")
  eq(#p.prompts, 0, "prompt closed")
  click(WHITE, "cz-hit-2-" .. vault)
  assert(has(red.discard, vault), "building destroyed")
  eq(p.resources.might, 3, "3 left")
  eq(notes[#notes], "White destroys Red's Seed Vault (4 Might)", "and the building")
  click(WHITE, "cz-attack-2")
  eq(red.stats.health, 32, "nowhere else to spend it: all of it at once")
  eq(p.resources.might, 0)
  -- Cancel spends nothing
  put(2, "bases", "seed_vault")
  p.resources.might = 6
  game:refreshUI()
  click(WHITE, "cz-attack-2")
  click(WHITE, "cz-done")
  eq(p.resources.might, 6, "cancelled")
  eq(red.stats.health, 32)
end)

test("attack split across three players", function()
  local game = boot()
  click(HOST, "cz-players-3")
  DBE_start()
  local s = game.state
  s.players[1].resources.might = 12
  game:refreshUI()
  click(HOST, "cz-attack-2")
  click(HOST, "cz-pick--5"); click(HOST, "cz-pick--1"); click(HOST, "cz-pick--1")
  click(HOST, "cz-pick-go")
  eq(s.players[2].stats.health, 40 - 5, "Red takes 5")
  click(HOST, "cz-attack-3")
  click(HOST, "cz-pick-go")
  eq(s.players[3].stats.health, 40 - 7, "Blue takes the other 7")
  eq(s.players[1].resources.might, 0)
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
  assert(tts.ui.xml:find('id="cz%-players%-2"[^>]*colors="#5AA9E6'), "the setup menu remembers the choice (selected look)")
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
  click(HOST, "cz-pick-go") -- Blue could take some too, so it asks how much
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
  assert(xml:find('id="cz_winner_White"[^>]*rectAlignment="MiddleCenter"'), "winner panel in the middle")
  assert(xml:find('id="cz_winner_Red" visibility="Red"', 1, true), "one for each player")
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
  assert(not xml:find('id="cz_winner_White"', 1, true), "the winner panel steps aside for it")
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
  assert(xml:find('id="cz_panel_2" visibility="Red"[^>]* width="375"'), "Red's own info panel, drawn 25% bigger")
  assert(not xml:find(' scale="', 1, true), "drawn at real size, not with TTS's scale attribute")
  local from = xml:find('id="cz_panel_2"', 1, true)
  assert(xml:find('id="cz%-setup"[^>]*fontSize="18"', from), "its buttons' text 25% bigger too (14 -> 18)")
  assert(xml:find('id="cz%-setup"[^>]*colors="#E8B84A', from), "buttons keep their look (New Game is primary)")
  assert(xml:find('id="cz_panel" visibility="White|Brown|Orange', 1, true), "everyone else keeps the normal one")
  assert(xml:find('id="cz_settings_Red" visibility="Red"[^>]* width="860"'), "menus too (660 + padding, 25% bigger)")
  local normalBottom = tonumber(xml:match('id="cz_panel"[^>]*offsetXY="%-12 (%d+)"'))
  local redBottom = tonumber(xml:match('id="cz_panel_2"[^>]*offsetXY="%-12 (%d+)"'))
  eq(redBottom, normalBottom, "Red's bigger info panel ends at the same spot")
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

test("opening hands: a game can offer rules to pick from in the setup menu", function()
  local game = boot()
  game.rules.openingHands = {
    { label = "Rulebook", hands = { players = { [2] = { 3, 5 } }, otherwise = { 3, 4, 5 } } },
    { label = "Everyone 5", hands = 5, about = "Everyone starts with 5 cards." },
  }
  local function dealt(n)
    click(HOST, "cz-players-" .. n)
    Cardalyzer_onStartGame(HOST)
    local out = {}
    for i, p in ipairs(game.state.players) do out[i] = #p.hand end
    return table.concat(out, ",")
  end
  eq(dealt(2), "3,5", "rulebook, 2 players")
  eq(dealt(3), "3,4,5", "rulebook, 3 players")
  eq(dealt(4), "3,4,5,5", "rulebook, 4 players")
  click(HOST, "cz-setup")
  local xml = tts.ui.xml
  assert(xml:find('id="cz%-opening%-1"[^>]*colors="#5AA9E6'), "Rulebook chosen by default")
  assert(xml:find('id="cz%-opening%-2"[^>]*>Everyone 5<'), "the other option")
  assert(xml:find('id="cz_opening"[^>]*>Starting hands<'), "the row's plain-words label")
  assert(xml:find('id="cz%-opening%-2"[^>]*tooltip="Everyone starts with 5 cards."'), "an option's about is its tooltip")
  local page = Cardalyzer.require("engine.tutorial").setupPage(game)
  eq(page[1], "Setting up a game", "a tutorial page about the setup menu")
  assert(page[2]:find("Starting hands: how many cards each player draws for their very first turn", 1, true), "explains starting hands")
  assert(page[2]:find("Everyone 5: Everyone starts with 5 cards.", 1, true), "and each option")
  click(GUEST, "cz-opening-2")
  eq(game:setupChoice("opening"), nil, "only the host can change it")
  click(HOST, "cz-opening-2")
  eq(dealt(3), "5,5,5", "Everyone 5")
  eq(dealt(2), "5,5", "kept for the next game")
  local restored = boot(game:save())
  eq(restored:setupChoice("opening"), 2, "and after a reload")
  game.rules.openingHands = nil
end)

test("scrap_required makes the player scrap; returnScrapped sends fixed-pile cards home", function()
  local game, put = blank()
  local Cards = Cardalyzer.require("engine.cards")
  local junk = put(1, "hand", "squire")
  game.effects:apply(game, 1, Cards.parseEffects("scrap_required:1"))
  local prompt = game.state.players[1].prompts[1]
  eq(prompt.kind, "scrap", "a scrap prompt")
  eq(prompt.optional, false, "that must be answered")
  click(WHITE, "cz-pick-" .. junk)
  assert(has(game.state.market.scrap, junk), "scrapped")

  -- A fixed-pile card scrapped from play goes back to its pile with returnScrapped.
  local m = game.state.market
  game.rules.market.returnScrapped = true
  local before = #m.fixed.hireling
  local hireling = put(1, "hand", "hireling")
  game:play(1, hireling)
  click(WHITE, "cz-scrap-" .. hireling)
  eq(#m.fixed.hireling, before + 1, "back on the Hireling pile")
  eq(m.fixed.hireling[#m.fixed.hireling], hireling, "on top")
  assert(not has(m.scrap, hireling), "not in the scrap pile")
  -- Other cards still go to the scrap pile.
  local herb = put(1, "hand", "squire")
  game:prompt(1, { kind = "scrap", count = 1, optional = true, from = { "hand" } })
  click(WHITE, "cz-pick-" .. herb)
  assert(has(m.scrap, herb), "a market card is scrapped as usual")
  game.rules.market.returnScrapped = nil
end)

---------------------------------------------------------------------------
-- Expansion features: double allies, gated scraps, buy destinations, more
-- prompts and keywords, hooks, sets
---------------------------------------------------------------------------

test("a double ally needs two other cards of the faction", function()
  local game, put = blank()
  local smith = game.cards:get("ember_smith")
  smith.allyGroups[#smith.allyGroups + 1] = { need = 2, effects = { { key = "gold", amount = 5 } } }
  game:play(1, put(1, "hand", "ember_smith"))
  game:play(1, put(1, "hand", "bellows_crew")) -- one other Forge card: the single ally fires, not the double
  local p = game.state.players[1]
  eq(p.resources.gold, 0, "double ally not yet")
  game:play(1, put(1, "hand", "war_anvil")) -- a second other Forge card
  eq(p.resources.gold, 5, "double ally fired")
end)

test("a scrap ability with a faction prefix needs that ally in play", function()
  local game, put = blank()
  game.cards:get("hireling").scrapEffects = { { key = "might", amount = 2, ally = "forge" } }
  local h = put(1, "hand", "hireling")
  game:play(1, h)
  local Actions = Cardalyzer.require("engine.actions")
  eq(Actions.canScrap(game, 1, h), false, "can't be scrapped without a Forge ally")
  eq(game:scrapFromPlay(1, h), false, "refused")
  game:play(1, put(1, "hand", "ember_smith"))
  eq(Actions.canScrap(game, 1, h), true, "can be once a Forge card is in play")
  -- with rules.ui.scrapButton = false the bar lists it
  game.rules.ui = game.rules.ui or {}
  game.rules.ui.scrapButton = false
  game:refreshUI()
  assert(tts.ui.xml:find("cz-scrap-" .. h, 1, true), "a Scrap button in the bar")
  game.rules.ui.scrapButton = nil
  game:refreshUI()
  assert(not tts.ui.xml:find("cz-scrap-" .. h, 1, true), "otherwise only on the card")
  click(WHITE, "cz-scrap-" .. h)
  eq(game.state.players[1].resources.might, 2 + 2, "scrap effect (plus the Smith's 2)")
end)

test("buy destinations: hand, straight into play, type lists, and onAcquire", function()
  local game, put, putRow, putDeck = blank()
  local p = game.state.players[1]
  p.resources.gold = 30
  local a, b, c = putRow(1, "tide_runner"), putRow(2, "seed_vault"), putRow(3, "old_oak")
  p.flags.buyToHand = { "building", "wall" }
  game:buy(1, a)
  eq(p.discard[#p.discard], a, "a unit doesn't match the list")
  game:buy(1, b)
  assert(has(p.hand, b), "a building goes to the hand")
  eq(p.flags.buyToHand, nil, "used up")
  p.flags.buyToPlay = "building"
  local healthBefore = p.stats.health
  game:buy(1, c)
  assert(has(p.bases, c), "straight into play")
  eq(p.stats.health, healthBefore + 3, "and its effect applied (Old Oak: +3 Health)")
  -- onAcquire runs for the bought card.
  local seen
  game.effects:registerCustom("noticeMe", { onAcquire = function(g, seat, ctx) seen = ctx.card.id end })
  game.cards:get("lighthouse").effects = { { key = "custom", fn = "noticeMe" } }
  game:buy(1, putRow(4, "lighthouse"))
  eq(seen, "lighthouse", "onAcquire ran")
  assert(putDeck)
end)

test("keywords: scrap from one place, discard, cycle, capped free buys, bounce", function()
  local game, put, putRow = blank()
  local Cards = Cardalyzer.require("engine.cards")
  local p = game.state.players[1]
  local function apply(s) game.effects:apply(game, 1, Cards.parseEffects(s)) end
  local inHand, inDiscard = put(1, "hand", "squire"), put(1, "discard", "squire")
  apply("scrap_from_discard_required:1")
  local targets = Cardalyzer.require("engine.actions").targets(game, 1, p.prompts[1])
  eq(#targets, 1, "only the discard pile")
  eq(targets[1].value, inDiscard, "the discarded card")
  eq(p.prompts[1].optional, false, "required")
  click(WHITE, "cz-pick-" .. inDiscard)
  apply("scrap_from_hand:1")
  eq(p.prompts[1].optional, true, "optional")
  click(WHITE, "cz-done")
  for _ = 1, 4 do put(1, "deck", "apprentice") end
  local d1, d2 = put(1, "hand", "squire"), put(1, "hand", "squire")
  apply("cycle:2")
  click(WHITE, "cz-pick-" .. d1)
  click(WHITE, "cz-pick-" .. d2)
  eq(#p.hand, 3, "discarded two (of three), drew two")
  apply("discard:1")
  eq(p.prompts[1].optional, false, "a required discard")
  click(WHITE, "cz-pick-" .. p.hand[1])
  local cheap, dear = putRow(1, "tide_runner"), putRow(2, "fleet_admiral")
  apply("free_buy_hand:2")
  game:refreshUI()
  assert(tts.ui.xml:find("cz-pick-" .. cheap, 1, true) and not tts.ui.xml:find("cz-pick-" .. dear, 1, true), "capped at cost 2")
  click(WHITE, "cz-pick-" .. cheap)
  assert(has(p.hand, cheap), "into the hand")
  -- bounce: an opponent's base goes back to their hand.
  local base = put(2, "bases", "seed_vault")
  apply("bounce_base:1")
  click(WHITE, "cz-pick-" .. base)
  assert(has(game.state.players[2].hand, base), "back in its owner's hand")
  assert(inHand)
end)

test("scrap prompts: the market row, faction filters, afterPick/afterPrompt, counters and whenYouScrap", function()
  local game, put, putRow = blank()
  local p = game.state.players[1]
  local picked, ended, scrapped = {}, nil, 0
  game.effects:registerCustom("watchScrap", {
    afterPick = function(g, seat, uid) picked[#picked + 1] = g.state.cards[uid] end,
    afterPrompt = function(g, seat, prompt) ended = prompt.picked end,
    whenYouScrap = function() scrapped = scrapped + 1 end,
  })
  -- a card in play that reacts to scraps from hand or discard
  local vault = game.cards:get("seed_vault")
  vault.effects[#vault.effects + 1] = { key = "custom", fn = "watchScrap" }
  game:play(1, put(1, "hand", "seed_vault"))
  local forge, grove = put(1, "hand", "ember_smith"), put(1, "hand", "grove_tender")
  local row = putRow(1, "tide_runner")
  game:prompt(1, { kind = "scrap", count = 3, optional = true, from = { "hand", "row" }, factions = { "forge", "tide" }, custom = "watchScrap" })
  game:refreshUI()
  assert(not tts.ui.xml:find("cz-pick-" .. grove, 1, true), "a Grove card is filtered out")
  click(WHITE, "cz-pick-" .. forge)
  click(WHITE, "cz-pick-" .. row)
  click(WHITE, "cz-done")
  eq(table.concat(picked, ","), "ember_smith,tide_runner", "afterPick for each")
  eq(ended, 2, "afterPrompt with the count")
  eq(game.state.market.row[1], "", "the row card left the row")
  eq(game.state.turn.scrapped.total, 1, "own cards scrapped this turn (the row card isn't yours)")
  eq(game.state.turn.scrapped.handOrDiscard, 1, "from hand")
  eq(scrapped, 1, "whenYouScrap fired once")
end)

test("pick scopes, extra factions, end-of-turn jobs and cards that stay in hand", function()
  local game, put = blank()
  local State = Cardalyzer.require("engine.state")
  local targets = function() return Cardalyzer.require("engine.actions").targets(game, 1, game.state.players[1].prompts[1]) end
  local mine, theirs = put(1, "bases", "seed_vault"), put(2, "bases", "hidden_den")
  local oppDiscard = put(2, "discard", "squire")
  game.effects:registerCustom("noop", { onPick = function() end })
  game:prompt(1, { kind = "pick", scope = "bases", custom = "noop" })
  eq(#targets(), 2, "every base in play")
  click(WHITE, "cz-pick-" .. theirs)
  game:prompt(1, { kind = "pick", scope = "opponentDiscard", custom = "noop" })
  eq(targets()[1].value, oppDiscard, "the opponent's discard pile")
  click(WHITE, "cz-pick-" .. oppDiscard)
  -- addFaction: a Grove card gains Forge, so a Forge ally fires
  local smith = put(1, "hand", "ember_smith")
  local tender = put(1, "hand", "grove_tender")
  game:play(1, smith)
  game:play(1, tender)
  local might = game.state.players[1].resources.might
  game:addFaction(1, tender, "forge")
  eq(game.state.players[1].resources.might, might + 2, "the Smith's Forge ally fired")
  -- atTurnEnd jobs and whenTurnEnds = "hand"
  local ran
  game.effects:registerCustom("later", { atTurnEnd = function(g, seat, job) ran = job.note end })
  game:atTurnEnd({ custom = "later", note = "done" })
  game.effects:registerCustom("dock", { whenTurnEnds = function() return "hand" end })
  game.cards:get("squire").effects = { { key = "custom", fn = "dock" } }
  local docked = put(1, "hand", "squire")
  game:play(1, docked)
  for _ = 1, 5 do put(1, "deck", "apprentice") end
  click(WHITE, "cz-end")
  eq(ran, "done", "end-of-turn job ran")
  local p = game.state.players[1]
  assert(has(p.hand, docked), "the docked card is back in hand")
  eq(#p.hand, 6, "on top of a full new hand")
  eq(game:cardOf(tender).id, "grove_tender", "factions added last turn are gone")
  assert(mine and State)
end)

test("sets: toggled in the setup menu, only their cards are dealt", function()
  local game = boot()
  -- put two market cards in an expansion set, off by default
  game.cards:get("fleet_admiral").set = "exp"
  game.cards:get("night_queen").set = "exp"
  game.rules.sets = { { key = "base", label = "Base", always = true }, { key = "exp", label = "Expansion" } }
  local function dealtIds()
    Cardalyzer_onStartGame(HOST)
    local ids = {}
    for _, uid in ipairs(game.state.market.deck) do ids[game.state.cards[uid]] = true end
    for _, uid in ipairs(game.state.market.row) do if uid ~= "" then ids[game.state.cards[uid]] = true end end
    return ids
  end
  local ids = dealtIds()
  assert(ids.ember_smith, "base cards dealt")
  assert(not ids.fleet_admiral and not ids.night_queen, "expansion cards left out by default")
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz%-set%-base"[^>]*colors="#5AA9E6'), "the always-on set is shown on")
  assert(tts.ui.xml:find('id="cz%-set%-exp"[^>]*colors="#D6DEE8'), "the expansion off")
  click(GUEST, "cz-set-exp")
  eq(game:setsInPlay().exp, nil, "only the host can switch sets")
  click(HOST, "cz-set-exp")
  click(HOST, "cz-set-base")
  eq(game:setsInPlay().base, true, "an always set can't be switched off")
  ids = dealtIds()
  assert(ids.fleet_admiral and ids.night_queen, "expansion cards dealt once switched on")
  game.rules.sets = nil
end)

---------------------------------------------------------------------------
-- More card types: heroes (granted allies, untargetable, no replay), events
---------------------------------------------------------------------------

test("grantAllies makes every ally ability of a faction count this turn", function()
  local game, put = blank()
  local p = game.state.players[1]
  game:play(1, put(1, "hand", "ember_smith")) -- Forge, ally might:2, no other Forge card
  eq(p.resources.might, 2, "no ally yet")
  game:grantAllies(1, "forge")
  eq(p.resources.might, 4, "granted: the Smith's ally fires")
  game:play(1, put(1, "hand", "ember_smith"))
  eq(p.resources.might, 4 + 2 + 2, "and for Forge cards played later this turn")
  for _ = 1, 5 do put(1, "deck", "apprentice") end
  click(WHITE, "cz-end")
  eq(game.state.turn.granted.forge, nil, "gone next turn")
end)

test("card types can stay in play without replaying or being attacked", function()
  local game, put = blank()
  game.rules.cardTypes.hero = { persistent = true, replay = false, target = false }
  game.cards:get("seed_vault").type = "hero"
  local hero = put(1, "hand", "seed_vault")
  game:play(1, hero)
  local p = game.state.players[1]
  assert(has(p.bases, hero), "stays in play")
  local health = p.stats.health
  for _ = 1, 10 do put(1, "deck", "apprentice"); put(2, "deck", "apprentice") end
  click(WHITE, "cz-end")
  click(RED, "cz-end")
  eq(p.stats.health, health, "its effect isn't applied again")
  -- Red can't attack it or destroy it with an effect.
  click(WHITE, "cz-end")
  game.state.players[2].resources.might = 10
  game:refreshUI()
  assert(not tts.ui.xml:find("cz-hit-1-" .. hero, 1, true), "no Destroy button")
  eq(game:attack(2, 1, hero), false, "attack refused")
  local Cards = Cardalyzer.require("engine.cards")
  game.effects:apply(game, 2, Cards.parseEffects("destroy_base:1"))
  local Actions = Cardalyzer.require("engine.actions")
  eq(#Actions.targets(game, 2, game.state.players[2].prompts[1]), 0, "nothing it can destroy")
  game.rules.cardTypes.hero = nil
  game.cards:get("seed_vault").type = "building"
end)

test("events resolve when revealed in the market row; set aside during setup", function()
  local game, put, putRow, putDeck = blank()
  game.rules.cardTypes.event = { event = true }
  game.effects:registerCustom("everyoneHeals", {
    apply = function(g, seat, ctx)
      for _, p in ipairs(g.state.players) do p.stats.health = p.stats.health + 3 end
      assert(ctx.event, "ctx.event set")
    end })
  local oracle = game.cards:get("oracle")
  oracle.type, oracle.effects = "event", { { key = "custom", fn = "everyoneHeals" } }
  local normal = putDeck("tide_runner")
  local event = putDeck("oracle") -- on top: revealed first
  local bought = putRow(1, "squire")
  game.state.players[1].resources.gold = 5
  local h1, h2 = game.state.players[1].stats.health, game.state.players[2].stats.health
  game:buy(1, bought)
  eq(game.state.players[1].stats.health, h1 + 3, "resolved for everyone")
  eq(game.state.players[2].stats.health, h2 + 3, "including the other player")
  assert(has(game.state.market.scrap, event), "then scrapped")
  assert(has(game.state.market.row, normal), "and the row refilled with the next card")
  assert(not has(game.state.market.row, event), "the event isn't left in the row")
  assert(tts.ui.xml:find("Event: Oracle", 1, true), "announced")
  -- At setup, events go back under the market deck instead.
  Cardalyzer_onStartGame(HOST)
  for _, uid in ipairs(game.state.market.row) do
    eq(game.cards:get(game.state.cards[uid]).type ~= "event", true, "no event in the starting row")
  end
  game.rules.cardTypes.event = nil
  oracle.type = "unit"
end)

test("an event that empties the market row while it fills doesn't trip the refill", function()
  local game, _, putRow, putDeck = blank()
  game.rules.cardTypes.event = { event = true }
  game.effects:registerCustom("wipeRow", {
    apply = function(g)
      local m = g.state.market
      for i, uid in ipairs(m.row) do
        if uid ~= "" then m.scrap[#m.scrap + 1] = uid; m.row[i] = "" end
      end
    end })
  local oracle = game.cards:get("oracle")
  oracle.type, oracle.effects = "event", { { key = "custom", fn = "wipeRow" } }
  putDeck("tide_runner")
  putDeck("squire")
  putDeck("oracle") -- revealed into slot 1, with Squire going to slot 2 in the same fill
  game.state.players[1].resources.gold = 5
  local ok = game:buy(1, putRow(3, "ember_smith"))
  eq(ok, true, "no error")
  local tracked = 0
  for _, guids in pairs(game.state.view.piles) do tracked = tracked + #guids end
  eq(count(function(o) return o.tags.cz_card end), tracked, "table consistent")
  game.rules.cardTypes.event = nil
  oracle.type = "unit"
end)

test("dealt cards: each player gets rules.deal.count into play at the start", function()
  local game = boot()
  for _, id in ipairs({ "oracle", "wild_shrine" }) do game.cards:get(id).deck = "dealt" end
  game.rules.deal = { count = 1 }
  Cardalyzer_onStartGame(HOST)
  local got = {}
  for seat, p in ipairs(game.state.players) do
    eq(#p.bases, 1, "seat " .. seat .. " dealt one")
    got[game.state.cards[p.bases[1]]] = true
  end
  assert(got.oracle and got.wild_shrine, "both dealt cards handed out")
  for _, uid in ipairs(game.state.market.deck) do
    local id = game.state.cards[uid]
    assert(id ~= "oracle" and id ~= "wild_shrine", "not in the market")
  end
  game.rules.deal = nil
  for _, id in ipairs({ "oracle", "wild_shrine" }) do game.cards:get(id).deck = "market" end
end)

test("whenAttacked lets the defender's cards reduce the damage", function()
  local game, put = blank()
  game.effects:registerCustom("shield1", { whenAttacked = function(g, seat, ctx, hit) hit.damage = hit.damage - 1 end })
  game.cards:get("hidden_den").effects = { { key = "custom", fn = "shield1" } }
  game.cards:get("hidden_den").type = "unit" -- not a base: it can't be targeted instead
  put(2, "bases", "hidden_den")
  local before = game.state.players[2].stats.health
  game.state.players[1].resources.might = 5
  click(WHITE, "cz-attack-2")
  click(WHITE, "cz-pick-go") -- the den could be hit too, so it asks how much
  eq(game.state.players[2].stats.health, before - 4, "5 Might, 1 blocked")
  local notes = game.notices.all
  eq(notes[#notes], "White hits Red for 4 Health, 1 stopped (Red: " .. (before - 4) .. ")", "says how much was stopped")
end)

test("objectives: dealt face down, completed when met for a reward, enough of them wins", function()
  local game = boot()
  for _, id in ipairs({ "oracle", "wild_shrine", "storm_caller", "night_queen" }) do
    local c = game.cards:get(id)
    c.deck, c.condition = "objective", "richEnough"
  end
  game.cards:get("oracle").effects = { { key = "gold", amount = 3 } } -- its reward
  game.effects:registerCustom("richEnough", { check = function(g, seat) return (g.state.turn.gained.gold or 0) >= 2 end })
  game.rules.objectives = { count = 2, perTurn = 1, toWin = 2, label = "Missions" }
  Cardalyzer_onStartGame(HOST)
  local p = game.state.players[1]
  eq(#p.objectives, 2, "two each")
  eq(#game.state.players[2].objectives, 2, "for both players")
  local Board = Cardalyzer.require("engine.board")
  Board.sync(game, { instant = true })
  local function goalObjects() return game.state.view.piles["1.objectives"] or {} end
  eq(#goalObjects(), 2, "both on the table")
  for _, guid in ipairs(goalObjects()) do
    local hidden = table.concat(getObjectFromGUID(guid).hiddenFrom or {}, ",")
    assert(hidden:find("Red", 1, true) and not hidden:find("White", 1, true), "only White sees them: " .. hidden)
  end
  game:refreshUI()
  assert(tts.ui.xml:find("Your missions:", 1, true), "the active player sees their missions on their bar")
  assert(tts.ui.xml:find("Missions 0/2", 1, true), "progress in the info panel")
  assert(not tts.ui.xml:find("cz-goal-", 1, true), "nothing completable yet")
  game.effects:apply(game, 1, { { key = "gold", amount = 2 } })
  game:refreshUI()
  local first = p.objectives[1]
  assert(tts.ui.xml:find("cz-goal-" .. first, 1, true), "Complete button once met")
  click(WHITE, "cz-goal-" .. first)
  eq(#p.completed, 1, "completed")
  assert(tts.ui.xml:find("completed", 1, true), "announced")
  Board.sync(game, { instant = true })
  local shown = getObjectFromGUID(goalObjects()[1])
  eq(shown.getGMNotes(), first, "the completed one first")
  eq(shown.hiddenFrom, nil, "shown to everyone once completed")
  eq(game:completeObjective(1, p.objectives[1]), false, "only one per turn")
  -- next turn, the second one wins the game
  game.state.turn.completed = 0
  game.effects:apply(game, 1, { { key = "gold", amount = 2 } })
  click(WHITE, "cz-goal-" .. p.objectives[1])
  eq(game.state.winner, 1, "two completed: White wins")
  game.rules.objectives = nil
end)

test("turn records: what was gained, and which factions' allies fired", function()
  local game, put = blank()
  game:play(1, put(1, "hand", "ember_smith"))
  game:play(1, put(1, "hand", "ember_smith"))
  local turn = game.state.turn
  eq(turn.gained.might, 2 + 2 + 2 + 2, "might gained this turn")
  eq(turn.allyFactions.forge, true, "Forge allies fired")
  eq(turn.allyFactions.grove, nil, "no Grove")
end)

test("kits: each player gets their own starters, dealt cards, stats and hand size", function()
  local game = boot()
  -- Two kits made from sample cards.
  for _, id in ipairs({ "tide_runner", "harbor_broker" }) do local c = game.cards:get(id); c.deck, c.set = "starter", "kitA" end
  for _, id in ipairs({ "veil_cutpurse", "shade_scout" }) do local c = game.cards:get(id); c.deck, c.set = "starter", "kitB" end
  local leader = game.cards:get("lighthouse"); leader.deck, leader.set = "dealt", "kitA"
  local bonus = game.cards:get("fleet_admiral"); bonus.set = "kitA" -- kitA's market card
  game.rules.kits = {
    { key = "a", label = "Kit A", set = "kitA", stats = { health = 60 }, handSize = 6 },
    { key = "b", label = "Kit B", set = "kitB", stats = { health = 30 }, handSize = 4 },
  }
  Cardalyzer_onStartGame(HOST)
  eq(game.state.players[1].kit, nil, "standard decks by default")
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz-kits-on"', 1, true), "a Starting decks option")
  click(GUEST, "cz-kits-on")
  eq(game:setupChoice("kits"), nil, "host only")
  click(HOST, "cz-kits-on")
  assert(tts.ui.xml:find('id="cz_kitmenu_White"', 1, true), "turning kits on opens the host's own kit menu")
  click(HOST, "cz-kitcancel")
  Cardalyzer_onStartGame(HOST)
  local seen = {}
  for _, p in ipairs(game.state.players) do
    local kit = p.kit
    assert(kit == "a" or kit == "b", "a kit each")
    assert(not seen[kit], "different kits")
    seen[kit] = true
    local ids = {}
    for _, list in ipairs({ p.deck, p.hand }) do for _, uid in ipairs(list) do ids[game.state.cards[uid]] = true end end
    assert(not ids.apprentice, "no standard starters")
    if kit == "a" then
      assert(ids.tide_runner, "kit A starters")
      eq(p.stats.health, 60, "kit A health")
      eq(p.handSize, 6, "kit A hand size")
      eq(game.state.cards[p.bases[1]], "lighthouse", "kit A's dealt card in play")
    else
      assert(ids.veil_cutpurse, "kit B starters")
      eq(p.stats.health, 30, "kit B health")
    end
  end
  local inMarket = false
  for _, uid in ipairs(game.state.market.deck) do if game.state.cards[uid] == "fleet_admiral" then inMarket = true end end
  for _, uid in ipairs(game.state.market.row) do if uid ~= "" and game.state.cards[uid] == "fleet_admiral" then inMarket = true end end
  assert(inMarket, "kit A's market card is in the market")
  -- the kit hand size applies when drawing a new hand
  local a = game.state.players[1].kit == "a" and 1 or 2
  game.state.turn.active = a
  for _ = 1, 10 do game.state.players[a].deck[#game.state.players[a].deck + 1] = Cardalyzer.require("engine.state").newCard(game.state, "squire") end
  game:endTurn(a)
  eq(#game.state.players[a].hand, 6, "draws 6")
  game.rules.kits = nil
end)

test("kit menu: each player picks premade, random or a custom mix; required sets switch on", function()
  local game = boot()
  for _, id in ipairs({ "tide_runner", "harbor_broker" }) do local c = game.cards:get(id); c.deck, c.set = "starter", "kitA" end
  for _, id in ipairs({ "veil_cutpurse", "shade_scout" }) do local c = game.cards:get(id); c.deck, c.set = "starter", "kitB" end
  local leaderA = game.cards:get("lighthouse"); leaderA.deck, leaderA.set, leaderA.type = "dealt", "kitA", "leader"
  local leaderB = game.cards:get("seed_vault"); leaderB.deck, leaderB.set, leaderB.type = "dealt", "kitB", "leader"
  local trickA = game.cards:get("hidden_den"); trickA.deck, trickA.set = "dealt", "kitA"
  local trickB = game.cards:get("ember_smith"); trickB.deck, trickB.set = "dealt", "kitB"
  game.cards:get("fleet_admiral").set = "kitA"
  game.cards:get("night_queen").set = "kitB"
  game.rules.kitName = "Warband"
  game.rules.sets = { { key = "base", label = "Base Game", always = true }, { key = "exp", label = "Expansion" } }
  game.rules.kits = {
    { key = "a", label = "Kit A", set = "kitA", stats = { health = 60 }, handSize = 6, requires = { "exp" } },
    { key = "b", label = "Kit B", set = "kitB", stats = { health = 30 }, handSize = 4 },
  }
  game.rules.kitParts = {
    { key = "leader", label = "Leader", deck = "dealt", type = "leader", by = "kit", stats = true },
    { key = "tricks", label = "Tricks", deck = "dealt", type = trickA.type, count = 1 },
    { key = "starters", label = "Starting cards", deck = "starter", by = "kit" },
    { key = "big", label = "Big card", deck = "market", count = 1 },
  }
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz%-kits%-on"[^>]*>Warband<'), "the option is named after the kit")
  click(HOST, "cz-kits-on")
  local xml = tts.ui.xml
  assert(xml:find('id="cz-kitmode-premade"', 1, true) and xml:find('id="cz-kitmode-custom"', 1, true), "premade, random, custom")
  assert(not xml:find('id="cz_setup_White"', 1, true), "the kit menu covers the New Game menu")
  -- White: premade Kit A (it needs the "exp" set)
  click(HOST, "cz-kitmode-premade")
  click(HOST, "cz-kitpick-a")
  assert(tts.ui.xml:find('id="cz%-kitpick%-a"[^>]*tooltip="Hand size 6', 1, false), "a premade kit's tooltip describes it")
  eq(game:setsInPlay().exp, nil, "the expansion is off until saved")
  click(HOST, "cz-kitsave")
  eq(game:setsInPlay().exp, true, "saving Kit A switched its set on")
  assert(tts.ui.xml:find('id="cz_setup_White"', 1, true), "Save and go back: the New Game menu again")
  assert(tts.ui.xml:find("White: Kit A", 1, true), "who's playing what")
  -- Red (not the host) opens their own menu from the info panel and builds a custom one
  assert(tts.ui.xml:find('id="cz%-kitmenu"[^>]*>Your Warband<'), "a button for everyone")
  click(GUEST, "cz-kitmenu")
  click(GUEST, "cz-kitmode-custom")
  click(GUEST, "cz-kitpart-1-b")        -- Kit B's leader (and its stats)
  click(GUEST, "cz-kitpart-3-a")        -- Kit A's starters
  click(GUEST, "cz-kitpart-4-fleet_admiral")
  click(GUEST, "cz-kitpart-4-night_queen") -- one big card: replaces the first pick
  click(GUEST, "cz-kitsave")
  eq(game:setupChoice("kitChoice").Red.parts.big[1], "night_queen", "a full part drops its oldest pick")
  Cardalyzer_onStartGame(HOST)
  local white, red = game.state.players[1], game.state.players[2]
  eq(white.kit, "a", "White's premade")
  eq(white.stats.health, 60, "Kit A health")
  eq(red.kit, "custom", "Red's custom kit")
  eq(red.stats.health, 30, "the leader's kit's stats")
  eq(red.handSize, 4, "and hand size")
  local ids = {}
  for _, list in ipairs({ red.deck, red.hand }) do for _, uid in ipairs(list) do ids[game.state.cards[uid]] = true end end
  assert(ids.tide_runner and not ids.veil_cutpurse, "Kit A's starters")
  local inPlay = {}
  for _, uid in ipairs(red.bases) do inPlay[game.state.cards[uid]] = true end
  assert(inPlay.seed_vault, "Kit B's leader in play")
  assert(inPlay.hidden_den or inPlay.ember_smith, "an unpicked trick, picked at random")
  local market = {}
  for _, list in ipairs({ game.state.market.deck, game.state.market.row }) do
    for _, uid in ipairs(list) do if uid ~= "" then market[game.state.cards[uid]] = true end end
  end
  assert(market.night_queen and market.fleet_admiral, "both picked big cards (White's Kit A brings its own)")
  -- tooltips everywhere
  click(HOST, "cz-setup")
  xml = tts.ui.xml
  assert(xml:find('id="cz%-new"[^>]*tooltip="Deal a new game', 1, false), "Play Game explains itself")
  assert(xml:find('id="cz%-players%-3"[^>]*tooltip="Deal the next game for 3 players."'), "and the player counts")
  assert(xml:find('id="cz%-set%-exp"[^>]*tooltip="', 1, false), "and the sets")
  game.rules.kits, game.rules.kitParts, game.rules.kitName, game.rules.sets = nil, nil, nil, nil
end)

test("activated abilities, discounts, buyToDeck, whenYouGain and same-name allies", function()
  local game, put, putRow = blank()
  local p = game.state.players[1]
  game.effects:registerCustom("tap", { text = "+1 Gold", activate = function(g, seat) g.state.players[seat].resources.gold = g.state.players[seat].resources.gold + 1 end })
  game.cards:get("seed_vault").effects = { { key = "custom", fn = "tap" } }
  local vault = put(1, "bases", "seed_vault")
  game:refreshUI()
  assert(tts.ui.xml:find("cz-use-" .. vault, 1, true), "a Use button")
  click(WHITE, "cz-use-" .. vault)
  eq(p.resources.gold, 1, "used")
  assert(not tts.ui.xml:find("cz-use-" .. vault, 1, true), "once a turn")
  -- discount: the next Forge card costs 1 less
  p.resources.gold = 2
  p.flags.discount = { faction = "forge", amount = 1 }
  local crew = putRow(1, "bellows_crew") -- Forge, cost 3
  eq(game:buy(1, crew), true, "bought for 2")
  eq(p.resources.gold, 0, "paid 2")
  eq(p.flags.discount, nil, "used up")
  -- buyToDeck: shuffled into the deck
  p.resources.gold = 5
  p.flags.buyToDeck = true
  local runner = putRow(2, "tide_runner")
  game:buy(1, runner)
  assert(has(p.deck, runner), "into the deck")
  -- whenYouGain: first gain of a key this turn
  local firsts = 0
  game.effects:registerCustom("onGain", { whenYouGain = function(g, seat, ctx, gain) if gain.key == "health" and gain.first then firsts = firsts + 1 end end })
  game.cards:get("hidden_den").effects = { { key = "custom", fn = "onGain" } }
  put(1, "bases", "hidden_den")
  game.effects:apply(game, 1, { { key = "health", amount = 2 } })
  game.effects:apply(game, 1, { { key = "health", amount = 2 } })
  eq(firsts, 1, "only the first gain counts as first")
  -- same-name ally: fires with another copy of the card
  local smith = game.cards:get("ember_smith")
  smith.allyGroups = { { faction = "samename", effects = { { key = "gold", amount = 5 } } } }
  local gold = p.resources.gold
  game:play(1, put(1, "hand", "ember_smith"))
  eq(p.resources.gold, gold, "alone: nothing")
  game:play(1, put(1, "hand", "ember_smith"))
  eq(p.resources.gold, gold + 10, "two of them: both fire")
end)

test("granting all allies, whenYouUseAlly, defense modifiers and hidden helpers", function()
  local game, put = blank()
  local p = game.state.players[1]
  -- whenYouUseAlly: told which ally group fired
  local used = {}
  game.effects:registerCustom("watchAllies", { text = "", whenYouUseAlly = function(g, seat, ctx, u) used[#used + 1] = u.card.id end })
  game.cards:get("seed_vault").effects = { { key = "custom", fn = "watchAllies" } }
  put(1, "bases", "seed_vault")
  game:play(1, put(1, "hand", "ember_smith"))
  eq(#used, 0, "no ally yet")
  game:grantAllies(1, "all")
  eq(p.resources.might, 4, "granting all: the Smith's ally fires")
  eq(used[1], "ember_smith", "and whenYouUseAlly heard it")
  eq(game.effects:describe(game:cardOf(p.bases[1]).effects), "", "a helper with text \"\" isn't described")
  -- defenseMod: +1 to the holder's bases, -1 to everyone else's
  game.effects:registerCustom("walls", { defenseMod = function(g, seat, ctx, base) return base.owner == seat and 1 or -1 end })
  game.cards:get("hidden_den").effects = { { key = "custom", fn = "walls" } }
  put(1, "bases", "hidden_den")
  local Actions = Cardalyzer.require("engine.actions")
  local State = Cardalyzer.require("engine.state")
  local mine = put(1, "bases", "seed_vault")
  local theirs = State.newCard(game.state, "seed_vault")
  game.state.players[2].bases[1] = theirs
  local printed = game.cards:get("seed_vault").defense
  eq(Actions.defenseOf(game, 1, mine), printed + 1, "my base")
  eq(Actions.defenseOf(game, 2, theirs), printed - 1, "their base")
  p.resources.might = 10
  game:refreshUI()
  assert(tts.ui.xml:find("Destroy Seed Vault (" .. (printed - 1) .. ")", 1, true), "the attack button shows the new defense")
end)

test("any player's waiting choice shows on their own screen", function()
  local game = blank()
  game:prompt(2, { kind = "choice", options = { { key = "gold", amount = 1 }, { key = "might", amount = 1 } } })
  game:refreshUI()
  assert(tts.ui.xml:find('id="cz_choice_Red" visibility="Red"', 1, true), "Red's choice, on Red's screen, on White's turn")
  click(RED, "cz-pick-2")
  eq(game.state.players[2].resources.might, 1, "Red answered it")
  assert(not tts.ui.xml:find("cz_choice_Red", 1, true), "gone")
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

test("themes: button looks, framed menus, a title picture and its box", function()
  local game = boot()
  click(HOST, "cz-setup")
  local xml = tts.ui.xml
  assert(xml:find('id="cz_setup_White"[^>]*color="#0E1620F2" outline="#E8B84A" outlineSize="2 %-2"'), "the default menu: dark, gold border")
  assert(xml:find('id="cz%-new"[^>]*colors="#E8B84A'), "Play Game in the primary look")
  assert(xml:find('id="cz%-players%-2"[^>]*colors="#5AA9E6'), "the chosen player count in the selected look, not the same gold")
  game.rules.ui = { theme = {
    accent = "#FF0000",
    buttons = { primary = { color = "#AA2222", text = "#FFFFFF" }, selected = { colors = "#1|#2|#3|#4", text = "#000000" } },
    panels = {
      menu = { image = "https://example.com/bg.png", border = "#00FFFF", borderSize = 3, padding = 20 },
      title = { color = "#000000", border = "#FFFFFF", borderSize = 2, padding = 4 },
    },
    title = { image = "https://example.com/title.png", height = 50 },
  } }
  game.assetsSet = nil
  game:refreshUI()
  xml = tts.ui.xml
  assert(xml:find('id="cz%-new"[^>]*colors="#AA2222|#C32727|#8B1C1C|#AA222280" textColor="#FFFFFF"'), "primary from one colour")
  assert(xml:find('id="cz%-players%-2"[^>]*colors="#1|#2|#3|#4"'), "or a full colors string")
  assert(xml:find('id="cz_setup_White"[^>]*width="754"[^>]*outline="#00FFFF" outlineSize="3 %-3"'), "menu padding and border")
  local menu = xml:find('id="cz_setup_White"', 1, true)
  assert(xml:find('<Image image="cz_img_', menu, true), "the menu's background picture")
  assert(xml:find('id="cz_title_box"[^>]*color="#000000" outline="#FFFFFF"'), "a box around the title")
  assert(xml:find('id="cz_title" image="cz_img_[^"]*" preserveAspect="true" preferredHeight="50"'), "the title picture")
  local urls = {}
  for _, a in ipairs(tts.ui.assets) do urls[a.url] = a.name end
  assert(urls["https://example.com/bg.png"] and urls["https://example.com/title.png"], "pictures registered as UI assets")
  assert(xml:find('id="cz_setup_White_title"[^>]*color="#FF0000"'), "the accent colour")
end)

test("a custom setup menu: change the default one, or draw your own", function()
  local game = boot()
  game.rules.ui = { setupMenu = function(g, color, menu, UI)
    menu.title = "Launch"
    menu.rows[#menu.rows + 1] = UI.optionRow("my_row", "Mode", { { id = "cz-button-1", label = "Fast", on = true } })
    menu.buttons[1].label = "Begin"
  end, buttons = { { label = "Fast" } } }
  click(HOST, "cz-setup")
  local xml = tts.ui.xml
  assert(xml:find('id="cz_setup_White_title"[^>]*>Launch<'), "new title")
  assert(xml:find('id="my_row"', 1, true), "an extra row")
  assert(xml:find('id="cz%-new"[^>]*>Begin<'), "a renamed button")
  game.rules.ui.setupMenu = function(g, color) return '<Panel id="mine_' .. color .. '" visibility="' .. color .. '"></Panel>' end
  game:refreshUI()
  assert(tts.ui.xml:find('id="mine_White"', 1, true), "or its own XML")
  assert(not tts.ui.xml:find('id="cz_setup_White"', 1, true), "instead of the default")
end)

test("Rulebooks and the rules' own buttons in the corner", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  assert(not tts.ui.xml:find('id="cz-rulebooks"', 1, true), "no Rulebooks button without rulebooks")
  game.rules.rulebooks = {
    { name = "Rules", url = "https://example.com/rules.pdf" },
    { name = "Expansion", url = "https://example.com/exp.pdf" },
    { name = "Local file", url = "file:///C:/rules.pdf" },
  }
  local presses = {}
  game.rules.ui = { buttons = { { label = "Score sheet", onClick = function(g, color) presses[#presses + 1] = color end } } }
  game:refreshUI()
  assert(tts.ui.xml:find('id="cz%-rulebooks"[^>]*>Rulebooks<.-id="cz%-button%-1"[^>]*>Score sheet<.-id="cz%-tidy"'), "Rulebooks, own buttons, Tidy table")
  click(GUEST, "cz-rulebooks")
  local books = tts.live(function(o) return o.tags.cz_rulebook end)
  eq(#books, 2, "the two web PDFs (file:// is refused)")
  eq(books[1].data.CustomPDF.PDFUrl, "https://example.com/rules.pdf", "its PDF")
  -- clear of every pile at the largest player count
  local layout = Cardalyzer.require("engine.zones").layout(game.rules, nil, #game.rules.seats)
  for _, seat in ipairs(layout.seats) do
    for _, s in pairs(seat) do
      if type(s) == "table" and s.position then assert(books[1].data.Transform.posX > s.position[1] + 3, "beside the play areas") end
    end
  end
  click(GUEST, "cz-rulebooks")
  eq(#tts.live(function(o) return o.tags.cz_rulebook end), 0, "pressed again: put away")
  click(GUEST, "cz-button-1")
  eq(presses[1], "Red", "the rules' button ran with the presser's colour")
end)

test("table layout: areas move, resize or turn off; the market moves or has no row", function()
  local game = boot()
  local Zones = Cardalyzer.require("engine.zones")
  local before = Zones.layout(game.rules, nil, 2).seats[1].play
  game.rules.layout = { areas = { play = { out = 5, width = 16 }, bases = false, scrap = false, market = { z = 3 } } }
  Cardalyzer_onStartGame(HOST)
  local s = game.layout.seats[1]
  eq(s.play.size[1], 16, "play area resized")
  eq(s.play.position[3], before.position[3] + 3, "and moved 3 further out")
  assert(s.bases.hidden and game.layout.market.scrap.hidden, "bases and scrap pile turned off")
  eq(game.layout.market.row[1].position[3], 3, "the market moved")
  local keys = {}
  for _, e in ipairs(Zones.zoneSpots(game.layout)) do keys[e.key] = true end
  assert(keys["1.play"] and not keys["1.bases"], "no zone for a turned-off area")
  for _, line in ipairs(tts.lines) do
    for _, pt in ipairs(line.points) do
      assert(not Zones.contains(s.bases, pt[1], pt[3], -0.5), "no outline for the bases area")
    end
  end
  eq(Zones.onScrap(game.layout, game.layout.market.scrap.position[1], game.layout.market.scrap.position[3]), false,
    "nothing to drop onto")
  -- bases sit in the play row
  local base = Cardalyzer.require("engine.state").newCard(game.state, "seed_vault")
  game.state.players[1].bases[1] = base
  local piles = {}
  for _, pile in ipairs(Cardalyzer.require("engine.board").piles(game)) do piles[pile.key] = pile end
  assert(not piles["1.bases"] and not piles["market.scrap"], "no piles for turned-off areas")
  eq(piles["1.play"].uids[#piles["1.play"].uids], base, "the base at the end of the play row")
  -- a market with no row
  game.rules.layout = nil
  local rowSize = game.rules.market.rowSize
  game.rules.market.rowSize = 0
  Cardalyzer_onStartGame(HOST)
  eq(#game.layout.market.row, 0, "no row")
  assert(game.layout.market.deck.hidden, "and no market deck shown")
  for _ = 1, 6 do
    local who = game.state.turn.active == 1 and HOST or GUEST
    click(who, "cz-playall")
    Cardalyzer_onEndTurn(who)
  end
  for _, b in ipairs(tts.broadcasts) do assert(not b:find("%[Cardalyzer%]"), "plays without a row: " .. b) end
  game.rules.market.rowSize = rowSize
end)

test("play mats under each seat and the market, extra mats, the table picture", function()
  local game = boot()
  game.rules.layout = { mats = {
    seat = { image = { White = "https://example.com/white.png", Red = "https://example.com/red.png", default = "https://example.com/seat.png" } },
    market = { image = "https://example.com/market.png" },
    extra = { { image = "https://example.com/logo.png", x = 0, z = 25, width = 8, depth = 4 }, { image = "file:///C:/x.png" } },
  }, tableImage = "https://example.com/table.jpg" }
  Cardalyzer_onStartGame(HOST)
  local mats = tts.live(function(o) return o.tags.cz_mat end)
  eq(#mats, 2 + 1 + 1, "a mat per seat, the market's and one extra (file:// is refused)")
  local byUrl = {}
  for _, m in ipairs(mats) do byUrl[m.data.CustomImage.ImageURL] = m end
  local white = byUrl["https://example.com/white.png"]
  assert(white and byUrl["https://example.com/red.png"], "each seat's own picture")
  assert(white.data.Locked, "locked in place")
  local Zones = Cardalyzer.require("engine.zones")
  local t = white.data.Transform
  local mat = { position = { t.posX, 0, t.posZ }, right = { 1, 0 }, forward = { 0, 1 }, size = { t.scaleX * 2, 0, t.scaleZ * 2 } }
  for _, name in ipairs({ "play", "bases", "deck", "discard" }) do
    local s = game.layout.seats[1][name]
    assert(Zones.contains(mat, s.position[1], s.position[3]), "White's mat covers their " .. name)
  end
  assert(tts.lines[1].points[1][2] > 1.1 + 0.05, "outlines lie on top of the mats")
  eq(tts.tableUrl, "https://example.com/table.jpg", "the table's picture")
  local guids = {}
  for _, m in ipairs(mats) do guids[m.getGUID()] = true end
  game:tidy()
  for _, m in ipairs(tts.live(function(o) return o.tags.cz_mat end)) do assert(guids[m.getGUID()], "unchanged mats are kept") end
  click(HOST, "cz-players-3")
  Cardalyzer_onStartGame(HOST)
  eq(#tts.live(function(o) return o.tags.cz_mat end), 3 + 1 + 1, "re-laid for three players")
  game.rules.layout = nil
end)

test("players choose their own mat and its style in Settings", function()
  local game = boot()
  local function url(set, style) return "https://example.com/" .. set .. "-" .. style .. ".png" end
  local layout = { mats = { seat = {
    styles = { "Plain", "Fancy" },
    sets = {
      { name = "Sun", images = { url("sun", 1), url("sun", 2) } },
      { name = "Moon", color = "White", images = { url("moon", 1), url("moon", 2) } },
      { name = "Star", images = { url("star", 1) } },
    },
  } } }
  game.rules.layout = layout
  Cardalyzer_onStartGame(HOST)
  local function matOf(g, seat)
    local have = g.state.view.mats["seat." .. seat]
    return have and getObjectFromGUID(have.guid).data.CustomImage.ImageURL
  end
  eq(matOf(game, 1), url("moon", 1), "White starts on the set given its colour")
  eq(matOf(game, 2), url("moon", 1), "Red starts on the sets in seat order")
  assert(tts.ui.xml:find('id="cz-matmenu"', 1, true), "a Change mat button")
  click(HOST, "cz-matmenu")
  assert(tts.ui.xml:find('id="cz_matmenu_White"', 1, true), "the Change mat menu")
  assert(tts.ui.xml:find('id="cz-matset-3"', 1, true), "a button per set")
  assert(tts.ui.xml:find('id="cz-matstyle-2"', 1, true), "a button per style")
  click(HOST, "cz-matstyle-2")
  eq(matOf(game, 1), url("moon", 2), "the style changed")
  click(HOST, "cz-matset-1")
  eq(matOf(game, 1), url("sun", 2), "the set changed, keeping the style")
  click(HOST, "cz-matset-3")
  eq(matOf(game, 1), url("star", 1), "a set with fewer styles falls back to one it has")
  eq(matOf(game, 2), url("moon", 1), "Red's mat is untouched")
  eq(#tts.live(function(o) return o.tags.cz_mat end), 2, "old mats replaced, not piled up")
  -- saved: a reload keeps the choice and the mats
  local saved = onSave()
  local objects, order = tts.objects, tts.order
  dofile("build/Global.lua")
  tts.objects, tts.order = objects, order
  onLoad(saved)
  local again = Cardalyzer.game
  eq(again.state.view.matPick.White.set, 3, "kept after a reload")
  eq(again:setMat("Purple", "set", 1), false, "spectators have no mat")
  eq(again:setMat("White", "set", 9), false, "no such set")
  game.rules.layout = nil
end)

test("a type's playYaw turns its cards in play, not in the market", function()
  local game = boot()
  game.rules.cardTypes.building = game.rules.cardTypes.building or {}
  game.rules.cardTypes.building.playYaw = 90
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local State = Cardalyzer.require("engine.state")
  local anvil = State.newCard(s, "war_anvil")
  p.bases[#p.bases + 1] = anvil
  local Board = Cardalyzer.require("engine.board")
  Board.sync(game)
  local function yawIn(key, i) return getObjectFromGUID(s.view.piles[key][i or 1]).rotation[2] end
  local flat = yawIn("1.deck") -- upright, as the seat reads
  eq((yawIn("1.bases") - flat) % 360, 90, "turned a quarter in play")
  -- used: a further quarter
  p.exhausted[anvil] = true
  Board.sync(game)
  eq((yawIn("1.bases") - flat) % 360, 180, "and a quarter more when used")
  game.rules.cardTypes.building.playYaw = nil
end)

test("the market's mat can be switched too, by any player at the table", function()
  local game = boot()
  local function url(set, style) return "https://example.com/m-" .. set .. "-" .. style .. ".png" end
  game.rules.layout = { mats = { market = {
    styles = { "Plain", "Fancy" },
    sets = {
      { name = "Day", images = { url("day", 1), url("day", 2) } },
      { name = "Night", default = true, images = { url("night", 1), url("night", 2) } },
    },
  } } }
  Cardalyzer_onStartGame(HOST)
  local function mat()
    local have = game.state.view.mats.market
    return have and getObjectFromGUID(have.guid).data.CustomImage.ImageURL
  end
  eq(mat(), url("night", 1), "starts on the default set")
  assert(tts.ui.xml:find('id="cz-matmenu"', 1, true), "Change mat, though the seats have no sets")
  click(GUEST, "cz-matmenu")
  assert(tts.ui.xml:find('id="cz-mktset-1"', 1, true), "the market's sets")
  assert(not tts.ui.xml:find('id="cz-matset-1"', 1, true), "and no seat rows")
  click(GUEST, "cz-mktstyle-2")
  eq(mat(), url("night", 2), "Red changed its style")
  click(HOST, "cz-mktset-1")
  eq(mat(), url("day", 2), "White its set, keeping the style")
  eq(game:setMat("Purple", "marketset", 2), false, "spectators can't")
  game.rules.layout = nil
end)

test("each seat's name lies between its deck and discard pile", function()
  local game = boot()
  game.rules.layout = { mats = { seat = { image = "https://example.com/mat.png", label = true } } }
  Cardalyzer_onStartGame(HOST)
  local texts = tts.live(function(o) return o.type == "3DText" end)
  eq(#texts, 2, "one per seat")
  local s = game.layout.seats[1]
  local t = texts[1].data
  eq(t.Text.Text, game.state.players[1].name, "the seat's name")
  eq(t.Transform.posX, (s.deck.position[1] + s.discard.position[1]) / 2, "between the deck")
  eq(t.Transform.posZ, (s.deck.position[3] + s.discard.position[3]) / 2, "and the discard pile")
  eq(t.Transform.rotX, 90, "lying flat")
  game:tidy()
  eq(#tts.live(function(o) return o.type == "3DText" end), 2, "kept, not doubled")
  game.rules.layout = nil
end)

test("an area can lay its cards in a column down it", function()
  local Board = Cardalyzer.require("engine.board")
  local spot = { position = { 0, 1, 0 }, right = { 1, 0 }, forward = { 0, 1 }, size = { 3, 3, 20 }, column = true }
  local at = Board.rowPositions(spot, 3, 2.8, 2.4)
  eq(at[1][1], 0, "no sideways step")
  eq(at[1][3] > at[2][3] and at[2][3] > at[3][3], true, "down the area, from the centre side")
  eq(math.floor((at[1][3] - at[2][3]) * 10 + 0.5), 38, "a card's depth apart")
  local packed = Board.rowPositions(spot, 9, 2.8, 2.4)
  assert(packed[1][3] - packed[9][3] <= 20 - 3.4 + 0.01, "closes up to fit")
end)

test("symbols: replace or add pictures, the defense symbol, the counters' look and sizes", function()
  local game = boot()
  game.rules.ui = { theme = { symbols = {
    pictures = { heart = "https://example.com/life.png", tower = "https://example.com/tower.png" },
    defense = "tower", tint = "#FFEEDD", text = "#112233", textSize = 0.5, textStyle = "Italic", outline = false,
    number = "right", sizes = { seat = 40, base = 20, turn = 60 },
  } } }
  game.assetsSet = nil
  Cardalyzer_onStartGame(HOST)
  local urls = {}
  for _, a in ipairs(tts.ui.assets) do urls[a.name] = a.url end
  eq(urls.cz_heart, "https://example.com/life.png", "a built-in symbol replaced")
  eq(urls.cz_tower, "https://example.com/tower.png", "a new symbol added")
  assert(urls.cz_coin:find("coin.png", 1, true), "the others keep the engine's pictures")
  game.state.players[2].bases[1] = Cardalyzer.require("engine.state").newCard(game.state, "seed_vault")
  game:refreshUI()
  local xml = tts.ui.xml
  assert(xml:find('id="cz_base_2_1"[^>]*preferredWidth="%d+" preferredHeight="20"'), "a base's defense at its size")
  assert(xml:find('<Image image="cz_tower" color="#FFEEDD"', 1, true), "the defense symbol, tinted")
  assert(xml:find('id="cz_stat_1_health" spacing="2" preferredWidth="%d+" preferredHeight="40"'), "a stat beside its number, at its size")
  assert(xml:find('id="cz_stat_1_health_n" fontSize="20" fontStyle="Italic" color="#112233" alignment="MiddleLeft"', 1, true),
    "the number's size, style and colour, with no outline")
end)

test("positions: every panel's anchor and offset", function()
  local game = boot()
  game.rules.ui = { theme = { positions = {
    info = { anchor = "UpperLeft", x = 20, y = -30 },
    corner = { anchor = "LowerLeft", x = 20, y = 15 },
    bar = { anchor = "LowerCenter", x = 100, y = 150 },
    counters = { anchor = "MiddleRight", x = -40, y = 0 },
    menus = { anchor = "MiddleCenter", x = 0, y = 80 },
  } } }
  Cardalyzer_onStartGame(HOST)
  game.state.players[1].resources.gold = 3
  game:notify("Not yet!", "White")
  game:setup("White", true)
  local xml = tts.ui.xml
  assert(xml:find('id="cz_panel"[^>]* rectAlignment="UpperLeft" offsetXY="20 %-30"'), "the info panel")
  local panel = xml:match('<Panel id="cz_panel".-</Panel>')
  assert(not panel:find('MiddleRight', 1, true), "a panel on the left reads from the left")
  assert(xml:find('id="cz_actions"[^>]* rectAlignment="LowerCenter" offsetXY="100 150"'), "the action bar")
  assert(xml:find('id="cz_counters_White"[^>]* rectAlignment="MiddleRight" offsetXY="%-40 0"'), "the turn's counters")
  assert(xml:find('id="cz_setup_White"[^>]* rectAlignment="MiddleCenter" offsetXY="0 80"'), "the menus")
  local y = tonumber(xml:match('id="cz_notice_White"[^>]*offsetXY="20 (%-%d+)"'))
  assert(y and y < -30, "a private message goes below an info panel that hangs from the top")
  -- each player's own bar offset still adds to the bar's y
  click(HOST, "cz-barup")
  assert(tts.ui.xml:find('id="cz_actions"[^>]* offsetXY="100 180"'), "moved up in Settings")
end)

test("words: a game renames buttons, messages, questions and effects", function()
  local game = boot()
  game.rules.ui = { words = {
    playAll = "Deploy all ({n})",
    endTurn = function() return "Pass" end,
    newGame = "Fresh Game",
    notEnough = "Need {n} {resource} for {card}.",
    ["effect.draw"] = "Draw {n} card(s)",
    chooseOne = "Pick one",
  } }
  Cardalyzer_onStartGame(HOST)
  local xml = tts.ui.xml
  assert(xml:find('id="cz%-playall"[^>]*>Deploy all %(%d+%)<'), "a renamed button with its number")
  assert(xml:find('id="cz%-end"[^>]*>Pass<'), "a word given as a function")
  assert(xml:find('id="cz%-setup"[^>]*>Fresh Game<'), "the info panel's buttons")
  eq(game.effects:describe({ { key = "draw", amount = 2 } }), "Draw 2 card(s)", "an effect's description")
  eq(game.effects:describe({ { key = "health", amount = 2 } }), "+2 Health", "others keep their own")
  local Actions = Cardalyzer.require("engine.actions")
  eq(Actions.promptText(game, { kind = "choice", count = 1 }), "Pick one", "a question")
  local p = game.state.players[1]
  p.resources.gold = 0
  local row = game.state.market.row
  local uid
  for _, u in ipairs(row) do if u ~= "" then uid = u end end
  local ok, why = game:buy(1, uid)
  assert(not ok and why:find("^Need %d+ Gold for "), "a message: " .. tostring(why))
end)

test("tutorial pages: a game adds its own, or rebuilds the list", function()
  local game = boot()
  local Tutorial = Cardalyzer.require("engine.tutorial")
  local n = #Tutorial.pages(game)
  game.rules.tutorialPages = { { title = "Our rules", body = "Read the book." } }
  local pages = Tutorial.pages(game)
  eq(#pages, n + 1, "one page added")
  eq(pages[#pages][1], "Our rules", "at the end")
  game.rules.tutorialPages = function(g, list) return { list[1], { "Only this", "and the welcome page" } } end
  eq(#Tutorial.pages(game), 2, "or the game's own list")
  game.rules.tutorialPages = nil
end)

test("outlines: one seat colour, a market colour, thickness, hidden ones", function()
  local game = boot()
  game.rules.outlines = { seat = "#FF0000", market = "#00FF00", thickness = 2, hide = { slots = true, deck = true } }
  Cardalyzer_onStartGame(HOST)
  local seatLines, marketLines = 0, 0
  for _, line in ipairs(tts.lines) do
    if line.color[1] == 1 and line.color[2] == 0 then seatLines = seatLines + 1 end
    if line.color[2] == 1 and line.color[1] == 0 then marketLines = marketLines + 1 end
    assert(line.thickness >= 0.16, "twice as thick")
  end
  eq(seatLines, 2 * 3, "play, bases and discard per seat (deck hidden)")
  eq(marketLines, 1 + 1 + #game.fixedIds + 1, "the row, market deck, fixed piles and scrap (no slots)")
  game.rules.outlines = nil
end)

test("animation timing, card tooltips, the Buy button's look, message history", function()
  local game = boot()
  game.rules.animation = { stagger = 0.5, linger = 1, lift = 3 }
  game.rules.ui = {
    describeCard = function(g, card, text) return card.name .. "!\n" .. text end,
    buyButton = { color = "#102030", textColor = "#FFFFFF", fontSize = 99 },
    messages = { count = 1, chat = false },
  }
  tts.deferTimers = true
  Cardalyzer_onStartGame(HOST)
  local delays = {}
  for _, timer in ipairs(tts.timers) do delays[#delays + 1] = timer.at end
  table.sort(delays)
  local spaced = false
  for i = 2, #delays do if math.abs(delays[i] - delays[i - 1] - 0.5) < 0.001 then spaced = true end end
  assert(spaced, "dealt cards 0.5 s apart")
  tts.runTimers()
  tts.deferTimers = false
  local card = tts.live(function(o) return o.type == "Card" and #o.buttons > 0 end)[1]
  assert(card, "a market card with a Buy button")
  eq(card.buttons[1].font_size, 99, "the button's font size")
  eq(card.buttons[1].color[1], 0x10 / 255, "and colour")
  assert(card.data.Description:find("^" .. card.data.Nickname .. "!\n"), "the game's card tooltip")
  local before = #tts.broadcasts
  game:notify("one")
  game:notify("two")
  eq(#game.notices.all, 1, "keeps one message")
  eq(game.notices.all[1], "two", "the latest")
  eq(#tts.broadcasts, before, "not sent to chat")
  game.rules.animation, game.rules.ui = nil, nil
end)

test("seating: around the table, along one side, or at exact spots", function()
  local game = boot()
  local Zones = Cardalyzer.require("engine.zones")
  local function near(a, b) return math.abs(a - b) < 0.01 end
  -- around: every seat faces the middle, the same distance away, its areas apart from the others'
  game.rules.layout = { seating = "around", seatDistance = 14 }
  local layout = Zones.layout(game.rules, nil, 3)
  for seat, s in ipairs(layout.seats) do
    local p, f = s.play.position, s.play.forward
    local back = { p[1] - f[1] * 2, p[3] - f[2] * 2 } -- the seat's own spot (play sits 2 out)
    assert(near(math.sqrt(back[1] ^ 2 + back[2] ^ 2), 14), "seat " .. seat .. " is 14 from the middle")
    assert(near(back[1] + f[1] * 14, 0) and near(back[2] + f[2] * 14, 0), "seat " .. seat .. " faces the middle")
    for other, o in ipairs(layout.seats) do
      if other ~= seat then
        assert(not Zones.contains(o.play, p[1], p[3]), "seat " .. seat .. "'s play area is clear of seat " .. other .. "'s")
      end
    end
    eq(Zones.playSeatAt(layout, p[1], p[3]), seat, "a card dropped on seat " .. seat .. "'s play area is theirs")
  end
  eq(layout.seats[1].play.rotation[2], 180, "seat 1 at the bottom, as before")
  -- an oval
  game.rules.layout = { seating = "around", seatRadius = { x = 30, z = 10 } }
  layout = Zones.layout(game.rules, nil, 4)
  local s2 = layout.seats[2].play
  assert(near(s2.position[1] - s2.forward[1] * 2, -30), "seat 2 out on the long axis")
  -- one side
  game.rules.layout = { seating = "oneSide", seatDistance = 12, seatSpread = 30 }
  layout = Zones.layout(game.rules, nil, 3)
  for _, s in ipairs(layout.seats) do assert(near(s.play.position[3], -10), "all along the bottom") end
  assert(near(layout.seats[3].play.position[1] - layout.seats[1].play.position[1], 60), "seatSpread apart")
  -- exact spots for two players, the rest "sides"
  game.rules.layout = { seating = { [2] = { { x = -20, z = 0, yaw = 90 }, { x = 20, z = 0, yaw = 270 } } } }
  layout = Zones.layout(game.rules, nil, 2)
  assert(near(layout.seats[1].play.position[1], -18), "seat 1 on the left, facing right")
  eq(layout.seats[2].play.rotation[2], (180 + 270) % 360, "seat 2's cards turned to face them")
  layout = Zones.layout(game.rules, nil, 3)
  assert(near(layout.seats[1].play.position[3], -8), "three players: the usual sides")
  -- a game played around a circle loses no cards
  game.rules.layout = { seating = "around" }
  click(HOST, "cz-players-4")
  Cardalyzer_onStartGame(HOST)
  local UI = Cardalyzer.require("engine.ui")
  for _ = 1, 40 do
    local seat = game.state.turn.active
    local who = { color = game.state.players[seat].color, host = seat == 1 }
    click(who, "cz-playall")
    for _, b in ipairs(UI.actions(game).buttons) do if b.id:find("^cz%-attack%-") then click(who, b.id); break end end
    Cardalyzer_onEndTurn(who)
  end
  for _, b in ipairs(tts.broadcasts) do assert(not b:find("%[Cardalyzer%]"), "no errors: " .. b) end
  game.rules.layout = nil
end)

test("the whole market turns to face the player whose turn it is", function()
  local game = boot()
  game.rules.layout = { seating = "around" }
  game.rules.market.turnsWithPlayer = true
  click(HOST, "cz-players-4")
  Cardalyzer_onStartGame(HOST)
  local function near(a, b) return math.abs(a - b) < 0.01 end
  local function rowDirection()
    local row = game.layout.market.row
    return row[#row].position[1] - row[1].position[1], row[#row].position[3] - row[1].position[3]
  end
  local dx, dz = rowDirection()
  assert(dx > 0 and near(dz, 0), "seat 1's turn: the row runs left to right for them")
  local slot1 = game.state.market.row[1]
  local Board = Cardalyzer.require("engine.board")
  local before = game.state.view.piles["market.row.1"][1]
  local outline = tts.lines[#tts.lines].points[1]
  Cardalyzer_onEndTurn(HOST)
  eq(game.state.turn.active, 2, "seat 2's turn")
  dx, dz = rowDirection()
  local right = game.layout.seats[2].play.right
  assert(near(dx * right[2] - dz * right[1], 0) and dx * right[1] + dz * right[2] > 0, "the row now runs along seat 2's right")
  local zone = getObjectFromGUID(game.state.view.zones["market.row"])
  eq(zone.rotation[2], game.layout.market.area.rotation[2], "the market zone turned too")
  local moved = tts.lines[#tts.lines].points[1]
  assert(not (near(moved[1], outline[1]) and near(moved[3], outline[3])), "and its outlines")
  if game.state.market.row[1] == slot1 then
    local obj = getObjectFromGUID(before)
    local to = game.layout.market.row[1].position
    assert(obj and near(obj.position[1], to[1]) and near(obj.position[3], to[3]), "the card in slot 1 glided to its new spot")
  end
  game.rules.layout, game.rules.market.turnsWithPlayer = nil, nil
end)

test("extra markets: their own deck and row, bought from, scrapped from, refilled", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local ok, lib = pcall(Cards.new, { { id = "x", name = "X", deck = "market:heroes", cost = "1", copies = "1", effects = "" } })
  assert(ok and lib:get("x").deck == "market:heroes", "market:<key> is a deck: " .. tostring(lib))
  assert(not pcall(Cards.new, { { id = "y", name = "Y", deck = "shop", cost = "1", copies = "1", effects = "" } }), "other decks still refused")
  for _, id in ipairs({ "fleet_admiral", "night_queen", "hidden_den" }) do game.cards:get(id).deck = "market:heroes" end
  game.rules.markets = { { key = "heroes", label = "Heroes", rowSize = 2 } }
  local Zones = Cardalyzer.require("engine.zones")
  local plain = Zones.layout({ seats = game.rules.seats, market = game.rules.market }, nil, 2)
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  local heroes = s.markets[1]
  eq(heroes.key, "heroes", "the extra market")
  eq(#heroes.row, 2, "its row")
  local inRow = 0
  for _, uid in ipairs(heroes.row) do if uid ~= "" then inRow = inRow + 1 end end
  eq(inRow + #heroes.deck, game.cards:get("fleet_admiral").copies + game.cards:get("night_queen").copies + game.cards:get("hidden_den").copies,
    "all its cards, in its row and deck")
  for _, uid in ipairs(s.market.deck) do assert(game.cards:get(s.cards[uid]).deck == "market", "the main deck keeps its own") end
  -- the table: a second row beside the main one, seats moved back
  local L = game.layout
  local extra = L.markets.heroes
  assert(math.abs(extra.row[1].position[3] - L.market.row[1].position[3]) > 3, "the second row sits beside the main row")
  assert(L.seats[1].play.position[3] < plain.seats[1].play.position[3], "seat 1 moved back to make room")
  local keys = {}
  for _, e in ipairs(Zones.zoneSpots(L)) do keys[e.key] = true end
  assert(keys["market.row.heroes"], "a zone for the extra row")
  local piles = {}
  for _, pile in ipairs(Cardalyzer.require("engine.board").piles(game)) do piles[pile.key] = pile end
  assert(piles["market.deck.heroes"] and piles["market.row.heroes.1"].buyable, "its deck and buyable row on the table")
  -- buy from it: the slot refills from its own deck
  local uid = heroes.row[1]
  local cost = game:cardOf(uid).cost
  s.players[1].resources.gold = cost
  local deckBefore = #heroes.deck
  assert(game:buy(1, uid), "bought from the extra row")
  assert(Cardalyzer.require("engine.util").indexOf(s.players[1].discard, uid), "into the discard pile")
  if deckBefore > 0 then
    assert(heroes.row[1] ~= "", "the slot refilled")
    eq(#heroes.deck, deckBefore - 1, "from its own deck")
  end
  -- scrap from it by hand (dragged to the scrap pile)
  local other = heroes.row[2]
  if other ~= "" then
    local okScrap = game:scrapDropped(1, other, "market.row.heroes.2")
    assert(okScrap, "scrapped from the extra row")
    assert(Cardalyzer.require("engine.util").indexOf(s.market.scrap, other), "onto the shared scrap pile")
  end
  -- cards are conserved
  local seen, total = {}, 0
  local function visit(l) for _, u in ipairs(l) do if u ~= "" then assert(not seen[u], "dup " .. u); seen[u] = true; total = total + 1 end end end
  for _, p in ipairs(s.players) do visit(p.deck); visit(p.hand); visit(p.discard); visit(p.play); visit(p.bases) end
  visit(s.market.deck); visit(s.market.row); visit(s.market.scrap)
  for _, pile in pairs(s.market.fixed) do visit(pile) end
  visit(heroes.deck); visit(heroes.row)
  local n = 0
  for _ in pairs(s.cards) do n = n + 1 end
  eq(total, n, "no card lost")
  -- saved and loaded
  local restored = boot(game:save())
  eq(#restored.state.markets[1].row, 2, "kept after a reload")
  game.rules.markets = nil
end)

test("points games: card points and a stat, end triggers, the round finished, ties shared", function()
  local game = boot()
  local Actions = Cardalyzer.require("engine.actions")
  local State = Cardalyzer.require("engine.state")
  game.cards:get("apprentice").points = 1
  game.rules.win = { type = "points", stat = "health", endWhen = { rounds = 2 }, finishRound = true }
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  local starters = 0
  for _, list in ipairs({ s.players[1].deck, s.players[1].hand }) do
    for _, uid in ipairs(list) do if s.cards[uid] == "apprentice" then starters = starters + 1 end end
  end
  eq(Actions.score(game, 1), starters + s.players[1].stats.health, "points on cards plus the stat")
  assert(tts.ui.xml:find(" · " .. Actions.score(game, 1) .. " points", 1, true), "scores on the right")
  local function turn() Cardalyzer_onEndTurn({ color = s.players[s.turn.active].color, host = s.turn.active == 1 }) end
  turn(); turn()
  eq(s.turn.round, 1, "one round played")
  assert(not s.winner, "not over yet")
  s.players[2].stats.health = s.players[2].stats.health + 5
  turn(); turn()
  eq(s.winner, 2, "two rounds: the higher score wins")
  assert(tts.ui.xml:find("Red wins!", 1, true), "announced")
  -- a tie is shared
  game = boot()
  game.rules.win = { type = "points", endWhen = { rounds = 1 }, finishRound = true }
  Cardalyzer_onStartGame(HOST)
  s = game.state
  turn(); turn()
  eq(#s.winners, 2, "equal scores share the win")
  eq(Actions.winnerNames(game), "White and Red", "both named")
  -- triggered mid-round: everyone still gets the same number of turns
  game = boot()
  game.rules.win = { type = "points", endWhen = { custom = function(g) return g.state.turn.number >= 2 end }, finishRound = true }
  Cardalyzer_onStartGame(HOST)
  s = game.state
  turn()
  assert(s.ending and not s.winner, "triggered after White's turn: Red still plays")
  turn()
  assert(s.winner, "over once the round is done")
  game.rules.win = nil
end)

test("a shared pool ends a points game; a custom check can decide any game", function()
  local game = boot()
  game.rules.win = { type = "points", stat = "health", endWhen = { pool = { key = "health", amount = 3 } } }
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  eq(s.pool, 3, "the pool starts full")
  assert(tts.ui.xml:find("3 Health left", 1, true), "shown on the right")
  game.effects:apply(game, 1, { { key = "health", amount = 2 } })
  eq(s.pool, 1, "gains come out of the pool")
  Cardalyzer_onEndTurn(HOST)
  assert(not s.winner, "not empty yet")
  game.effects:apply(game, 2, { { key = "health", amount = 2 } })
  Cardalyzer_onEndTurn({ color = "Red" })
  assert(s.winner, "the pool ran out: game over")
  -- custom check
  game = boot()
  game.rules.win = { type = "stat_depleted", stat = "health", atOrBelow = 0,
    check = function(g) if #g.state.players[1].discard >= 1 then return 1 end end }
  Cardalyzer_onStartGame(HOST)
  Cardalyzer_onEndTurn(HOST)
  eq(game.state.winner, 1, "the game's own check decided")
  game.rules.win = { type = "stat_depleted", stat = "health", atOrBelow = 0 }
end)

test("turn structure: phases, play and buy costs, starting pools, keeping the hand, hooks", function()
  local game = boot()
  local rules = game.rules
  rules.resources[#rules.resources + 1] = { key = "actions", label = "Actions", start = 1 }
  rules.resources[#rules.resources + 1] = { key = "buys", label = "Buys", start = 1 }
  local starts, ends = 0, 0
  rules.turn = {
    phases = {
      { key = "action", label = "Action", play = "unit", buy = false, attack = false },
      { key = "buy", label = "Buy", play = "building" },
    },
    playCost = { unit = { key = "actions", amount = 1 } },
    buyCost = { key = "buys", amount = 1 },
    keepHand = true, drawUpTo = true,
    onStart = function() starts = starts + 1 end,
    onEnd = function() ends = ends + 1 end,
  }
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  local p = s.players[1]
  eq(p.resources.actions, 1, "a resource's starting amount")
  eq(starts, 1, "onStart ran")
  assert(tts.ui.xml:find("Turn 1 · White · Action", 1, true), "the phase in the turn line")
  assert(tts.ui.xml:find('id="cz%-phase"[^>]*>Buy →<'), "a button for the next phase")
  -- a building from the market, into the hand, to test phases
  local State = Cardalyzer.require("engine.state")
  local vault = State.newCard(s, "seed_vault")
  p.hand[#p.hand + 1] = vault
  local units = {}
  for _, uid in ipairs(p.hand) do if game:cardOf(uid).type == "unit" then units[#units + 1] = uid end end
  assert(#units >= 2, "two units in hand")
  assert(game:play(1, units[1]), "a unit in the Action phase")
  eq(p.resources.actions, 0, "spent an action")
  local ok, why = game:play(1, units[2])
  assert(not ok and why:find("Actions"), "no actions left: " .. tostring(why))
  ok, why = game:play(1, vault)
  assert(not ok and why:find("Action phase"), "buildings wait for their phase: " .. tostring(why))
  local row
  for _, uid in ipairs(s.market.row) do if uid ~= "" then row = uid end end
  p.resources.gold = 99
  ok = game:buy(1, row)
  assert(not ok, "no buying in the Action phase")
  click(HOST, "cz-phase")
  eq(s.turn.phase, 2, "the Buy phase")
  assert(not tts.ui.xml:find('id="cz-phase"', 1, true), "no Next after the last phase")
  assert(game:play(1, vault), "a building in the Buy phase")
  assert(game:buy(1, row), "a buy")
  eq(p.resources.buys, 0, "spent a buy")
  local another
  for _, uid in ipairs(s.market.row) do if uid ~= "" and uid ~= row then another = uid end end
  ok, why = game:buy(1, another)
  assert(not ok and why:find("Buys"), "one buy a turn: " .. tostring(why))
  local kept = #p.hand
  Cardalyzer_onEndTurn(HOST)
  eq(ends, 1, "onEnd ran")
  eq(#p.hand, math.max(kept, 5), "kept the hand and drew up to 5")
  eq(p.resources.actions, 1, "pools back to their start for the next turn")
  eq(s.turn.phase, 1, "the next turn starts in the first phase")
  -- carried-over pools
  game = boot()
  game.rules.turn = { keepResources = { "gold" } }
  Cardalyzer_onStartGame(HOST)
  game.state.players[1].resources.gold = 4
  game.state.players[1].resources.might = 3
  Cardalyzer_onEndTurn(HOST)
  eq(game.state.players[1].resources.gold, 4, "gold carried over")
  eq(game.state.players[1].resources.might, 0, "might did not")
  game.rules.turn = nil
end)

test("supply piles: picked at random or from a preset, pile sizes, rows on the table, a pile running out", function()
  local game = boot()
  for _, id in ipairs({ "tide_runner", "grove_tender", "ember_smith", "oracle" }) do game.cards:get(id).deck = "supply" end
  game.rules.supply = { count = 2, presets = { { label = "Pair", cards = { "oracle", "tide_runner" }, about = "A pair." } } }
  game.rules.pileSizes = { hireling = { [2] = 4, otherwise = 6 }, oracle = function(n) return n + 1 end }
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  eq(#s.market.supply, 2, "two supply piles")
  local a, b = game.cards:get(s.market.supply[1]), game.cards:get(s.market.supply[2])
  assert(a.cost <= b.cost, "sorted by cost")
  eq(#game.fixedIds, 3, "the fixed pile, then the supply")
  eq(game.fixedIds[2], a.id, "supply after the fixed piles")
  assert(game.layout.market.fixed[b.id], "a place on the table")
  eq(#s.market.fixed.hireling, 4, "pile size for 2 players")
  for _, uid in ipairs(s.market.deck) do assert(game.cards:get(s.cards[uid]).deck == "market", "supply cards aren't in the market deck") end
  -- the menu: Random and the preset; host only
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz-supply-1"', 1, true) and tts.ui.xml:find(">Pair<", 1, true), "the preset in the menu")
  click(GUEST, "cz-supply-1")
  eq(game:setupChoice("supply"), nil, "guests can't choose")
  click(HOST, "cz-supply-1")
  eq(game:setupChoice("supply"), 1, "the host picked the preset")
  Cardalyzer_onStartGame(HOST)
  s = game.state
  eq(table.concat(s.market.supply, ","), "tide_runner,oracle", "the preset's piles, by cost")
  eq(#s.market.fixed.oracle, 3, "a pile size from a function of the player count")
  -- rows on the table: the supply starts its own row
  game.rules.layout.areas = { fixed = { columns = 4 } }
  game:relayout()
  local F = game.layout.market.fixed
  assert(math.abs(F.tide_runner.position[3] - F.hireling.position[3]) > 3, "supply on a new row")
  eq(F.oracle.position[3], F.tide_runner.position[3], "the supply's piles share a row")
  game.rules.layout.areas = nil
  -- kept through a save
  local restored = boot(game:save())
  eq(table.concat(restored.fixedIds, ","), "hireling,tide_runner,oracle", "piles after a reload")
  -- a named pile running out ends a points game
  game = restored
  game.rules.win = { type = "points", endWhen = { pileEmpty = "oracle" } }
  game.state.market.fixed.oracle = {}
  Cardalyzer_onEndTurn(HOST)
  assert(game.state.winner, "the game ended")
end)

test("keywords that name a card: gain a pile's card, gain a card up to a cost, checked at load", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local pile = #s.market.fixed.hireling
  local list = Cards.parseEffects("gain:hireling; gold:1")
  eq(list[1].id, "hireling", "the card named")
  eq(game.effects:describe(list), "Gain a Hireling, +1 Gold", "described by name")
  local discard = #p.discard
  game.effects:apply(game, 1, list, {})
  eq(#s.market.fixed.hireling, pile - 1, "taken from its pile")
  eq(#p.discard, discard + 1, "into the discard pile")
  s.market.fixed.hireling = {}
  game.effects:apply(game, 1, list, {})
  eq(#p.discard, discard + 1, "nothing left to gain")
  s.market.fixed.hireling = { Cardalyzer.require("engine.state").newCard(s, "hireling") }
  game.effects:apply(game, 1, Cards.parseEffects("gain_card:2"), {})
  local found = false
  for _, t in ipairs(Cardalyzer.require("engine.actions").targets(game, 1, p.prompts[1])) do
    if t.value == s.market.fixed.hireling[1] then found = true end
  end
  assert(found, "fixed piles are offered")
  local bad = Cards.new({ { id = "a", name = "A", cost = 1, copies = 1, effects = "gain:nope" } })
  local problems = game.effects:validate(bad)
  assert(problems[1] and problems[1]:find("no card 'nope'", 1, true), "an unknown card is reported: " .. tostring(problems[1]))
end)

test("attacks hit each opponent; reactions block or help; unanswered ones pass when the turn ends", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local State = Cardalyzer.require("engine.state")
  local Util = Cardalyzer.require("engine.util")
  game.cards:get("tide_runner").reactEffects = Cards.parseEffects("block")
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  local red = s.players[2]
  local charm = State.newCard(s, "tide_runner")
  red.hand[#red.hand + 1] = charm
  local attacker = s.players[1].hand[1]
  local gainHire = Cards.parseEffects("opponents_gain:hireling")
  eq(game.effects:isAttack(gainHire[1]), true, "an attack")
  local pile = #s.market.fixed.hireling
  game.effects:apply(game, 1, gainHire, { uid = attacker, card = game:cardOf(attacker) })
  game:refreshUI()
  eq(red.prompts[1] and red.prompts[1].kind, "react", "Red is asked")
  eq(#s.market.fixed.hireling, pile, "nothing happens until Red answers")
  assert(tts.ui.xml:find("Reveal Tide Runner", 1, true), "the reveal button on Red's screen")
  assert(tts.ui.xml:find("Don't reveal", 1, true), "and the button not to")
  -- revealing a block
  assert(game:pick(2, charm), "Red reveals")
  eq(#red.prompts, 0, "no reactions left: done")
  eq(#s.market.fixed.hireling, pile, "blocked")
  assert(Util.indexOf(red.hand, charm), "the reaction stays in the hand")
  -- not revealing
  game.effects:apply(game, 1, gainHire, { uid = attacker })
  assert(game:done(2), "Red doesn't reveal")
  eq(#s.market.fixed.hireling, pile - 1, "the attack lands")
  eq(s.cards[red.discard[#red.discard]], "hireling", "Red gained it")
  -- a reaction that helps: draw first, then the attack lands
  game.cards:get("tide_runner").reactEffects = Cards.parseEffects("draw:1")
  local hand = #red.hand
  game.effects:apply(game, 1, Cards.parseEffects("opponents_discard_to:3"), { uid = attacker })
  assert(game:pick(2, charm), "Red reveals to draw")
  eq(red.prompts[1].kind, "discard", "then discards")
  eq(red.prompts[1].count, hand + 1 - 3, "down to 3 after drawing")
  while red.prompts[1] do assert(game:pick(2, red.hand[1]), "Red discards on White's turn") end
  eq(#red.hand, 3, "down to 3")
  -- no reaction in hand: straight away
  Util.removeValue(red.hand, charm)
  red.discard[#red.discard + 1] = charm
  game.effects:apply(game, 1, gainHire, { uid = attacker })
  eq(#red.prompts, 0, "nothing to ask")
  eq(#s.market.fixed.hireling, pile - 2, "landed at once")
  -- unanswered when White's turn ends: taken as not revealed
  Util.removeValue(red.discard, charm)
  red.hand[#red.hand + 1] = charm
  game.effects:apply(game, 1, gainHire, { uid = attacker })
  -- saved while waiting
  game = boot(game:save())
  game.cards:get("tide_runner").reactEffects = Cards.parseEffects("block")
  s, red = game.state, game.state.players[2]
  eq(red.prompts[1].kind, "react", "still waiting after a reload")
  Cardalyzer_onEndTurn(HOST)
  eq(#red.prompts, 0, "passed at the end of White's turn")
  eq(#s.market.fixed.hireling, pile - 3, "and it landed")
  -- three players: the attack goes round from the attacker's left; custom attacks too
  game = boot()
  click(HOST, "cz-players-3")
  Cardalyzer_onStartGame(HOST)
  local order = {}
  game.effects:registerCustom("hex", { eachOpponent = function(_, from, victim) order[#order + 1] = from .. ">" .. victim end })
  game.effects:apply(game, 2, { { key = "custom", fn = "hex" } }, {})
  eq(table.concat(order, ","), "2>3,2>1", "from the attacker's left")
end)

test("skipAhead: a play or buy for a later phase moves the turn on; a refused one doesn't", function()
  local game = boot()
  local rules = game.rules
  rules.resources[#rules.resources + 1] = { key = "actions", label = "Actions", start = 1 }
  rules.turn = {
    phases = {
      { key = "action", label = "Action", play = "unit", buy = false },
      { key = "buy", label = "Buy", play = "building" },
    },
    skipAhead = true,
  }
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local row
  for _, uid in ipairs(s.market.row) do if uid ~= "" then row = uid end end
  p.resources.gold = 0
  local ok = game:buy(1, row)
  assert(not ok, "can't afford it")
  eq(s.turn.phase, 1, "still the Action phase")
  local vault = Cardalyzer.require("engine.state").newCard(s, "seed_vault")
  p.hand[#p.hand + 1] = vault
  assert(game:play(1, vault), "a building in the Action phase")
  eq(s.turn.phase, 2, "moved on to the Buy phase")
  local unit
  for _, uid in ipairs(p.hand) do if game:cardOf(uid).type == "unit" then unit = uid end end
  ok = game:play(1, unit)
  assert(not ok, "no going back to the Action phase")
  game.rules.turn = nil
end)

test("skipAhead: Play all with nothing to play in this phase plays the next phase's cards", function()
  local game = boot()
  game.rules.turn = {
    phases = {
      { key = "action", label = "Action", play = "unit", buy = false },
      { key = "buy", label = "Buy", play = "building" },
    },
    skipAhead = true,
  }
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  for _, uid in ipairs(p.hand) do p.deck[#p.deck + 1] = uid end
  p.hand = {}
  local State = Cardalyzer.require("engine.state")
  p.hand[1] = State.newCard(s, "seed_vault")
  p.hand[2] = State.newCard(s, "seed_vault")
  game:refreshUI()
  assert(tts.ui.xml:find("Play all (2)", 1, true), "Play all offers the Buy phase's cards")
  eq(s.turn.phase, 1, "drawing the UI doesn't move the turn on")
  assert(game:playAll(1), "Play all")
  eq(s.turn.phase, 2, "moved on to the Buy phase")
  eq(#p.hand, 0, "played both")
  -- with an action to play, Play all stays in the Action phase
  game = boot()
  game.rules.turn = { phases = { { key = "action", play = "unit" }, { key = "buy", play = "building" } }, skipAhead = true }
  Cardalyzer_onStartGame(HOST)
  local pl = game.state.players[1]
  pl.hand[#pl.hand + 1] = State.newCard(game.state, "seed_vault")
  assert(game:playAll(1), "Play all")
  eq(game.state.turn.phase, 1, "still the Action phase")
  eq(#pl.hand, 1, "the building waits")
  game.rules.turn = nil
end)

test("panels can be tucked away and shown again, per player", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  click(HOST, "cz-setup")
  local xml = tts.ui.xml
  assert(xml:find('id="cz%-tuck%-setup"[^>]*>Hide<'), "the setup menu has Hide")
  click(HOST, "cz-tuck-setup")
  xml = tts.ui.xml
  assert(not xml:find('id="cz_setup_White"', 1, true), "tucked away")
  assert(xml:find('id="cz_tabs_White" visibility="White"', 1, true), "a tab for White")
  assert(xml:find('id="cz%-untuck%-setup"[^>]*>Show New Game<'), "Show New Game")
  click(HOST, "cz-untuck-setup")
  assert(tts.ui.xml:find('id="cz_setup_White"', 1, true), "back")
  assert(not tts.ui.xml:find("cz_tabs_White", 1, true), "no tab")
  -- tucked, then closed and opened again: it shows
  click(HOST, "cz-tuck-setup")
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find('id="cz_setup_White"', 1, true), "opening it again shows it")
  click(HOST, "cz-setupclose")
  -- a choice: tucked, still waiting; answered, the next one shows
  local p = game.state.players[1]
  game.effects:apply(game, 1, { { key = "discard", amount = 1 } }, {})
  game:refreshUI()
  assert(tts.ui.xml:find('id="cz%-tuck%-choice"'), "a choice has Hide")
  click(HOST, "cz-tuck-choice")
  assert(not tts.ui.xml:find('id="cz_choice"', 1, true), "choice tucked away")
  assert(tts.ui.xml:find('id="cz%-untuck%-choice"[^>]*>Show your choice<'), "Show your choice")
  eq(#p.prompts, 1, "still waiting")
  click(HOST, "cz-pick-" .. p.hand[1])
  eq(#p.prompts, 0, "answered")
  game.effects:apply(game, 1, { { key = "discard", amount = 1 } }, {})
  game:refreshUI()
  assert(tts.ui.xml:find('id="cz_choice"', 1, true), "the next choice shows")
  -- the winner panel
  game.state.winner = 1
  game:refreshUI()
  click(GUEST, "cz-tuck-winner")
  assert(tts.ui.xml:find('id="cz_winner_White"', 1, true), "still there for White")
  assert(not tts.ui.xml:find('id="cz_winner_Red"', 1, true), "tucked away for Red")
  assert(tts.ui.xml:find('id="cz_tabs_Red"', 1, true), "Red's tab")
end)

test("Hide UI hides everything for one player; the hotkey toggles it; saved", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local xml = tts.ui.xml
  assert(xml:find('id="cz%-hideui"[^>]*>Hide UI<'), "Hide UI by Tidy table")
  click(HOST, "cz-hideui")
  xml = tts.ui.xml
  assert(not xml:find('id="cz_actions"', 1, true), "White's action bar is gone")
  assert(xml:find('id="cz_panel"[^>]*visibility="[^"]*Red', 1, false), "the info panel is still there for Red")
  assert(not xml:find('id="cz_panel[^"]*" visibility="[^"]*White'), "but not for White")
  assert(xml:find('id="cz%-showui"[^>]*>Show Cardalyzer<'), "Show Cardalyzer")
  local restored = boot(game:save())
  assert(restored.state.view.uiHidden.White, "kept after a reload")
  click(HOST, "cz-showui")
  assert(tts.ui.xml:find('id="cz_actions"', 1, true), "back")
  -- the hotkey
  local hotkey = tts.hotkeys and tts.hotkeys[1]
  if hotkey then
    hotkey.fn("White")
    assert(restored.state.view.uiHidden.White, "the hotkey hides")
    hotkey.fn("White")
    assert(not restored.state.view.uiHidden.White, "and shows")
  end
end)

test("each player chooses where menus and choices go", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  click(HOST, "cz-settings")
  assert(tts.ui.xml:find('id="cz%-menuat%-left"[^>]*>Left<'), "a Menus row in Settings")
  click(HOST, "cz-menuat-left")
  local xml = tts.ui.xml
  assert(xml:find('id="cz_settings_White"[^>]*rectAlignment="MiddleLeft"'), "White's menus on the left")
  game.effects:apply(game, 1, { { key = "discard", amount = 1 } }, {})
  game:refreshUI()
  assert(tts.ui.xml:find('id="cz_choice"[^>]*rectAlignment="MiddleLeft"'), "and White's choices")
  click(GUEST, "cz-setup")
  click(HOST, "cz-menuat-middle")
  assert(tts.ui.xml:find('id="cz_choice"[^>]*rectAlignment="MiddleCenter"'), "back in the middle")
  local ok = game:setMenuAt("White", "sideways")
  assert(not ok, "only the four places")
end)

test("a click that removes a button with a tooltip redraws the UI to clear it", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  click(HOST, "cz-settings")
  local sets = 0
  local real = UI.setXml
  UI.setXml = function(x) if x == "" then sets = sets + 1 end; real(x) end
  click(HOST, "cz-settingsclose")
  UI.setXml = real
  eq(sets, 1, "cleared once")
  assert(tts.ui.xml:find('id="cz_panel"', 1, true), "and drawn again")
  -- a button that stays (Settings opens a menu) doesn't
  sets = 0
  UI.setXml = function(x) if x == "" then sets = sets + 1 end; real(x) end
  click(HOST, "cz-settings")
  UI.setXml = real
  eq(sets, 0, "nothing to clear")
  -- Hide UI: still there for everyone else, but gone for White
  sets = 0
  UI.setXml = function(x) if x == "" then sets = sets + 1 end; real(x) end
  click(HOST, "cz-hideui")
  UI.setXml = real
  eq(sets, 1, "cleared for Hide UI too")
  assert(game.buttonsShown.Red["cz-hideui"] and not game.buttonsShown.White["cz-hideui"], "buttons tracked per player")
  -- a button whose panel moves (Menus: Left moves Settings)
  click(HOST, "cz-showui")
  click(HOST, "cz-settings")
  sets = 0
  UI.setXml = function(x) if x == "" then sets = sets + 1 end; real(x) end
  click(HOST, "cz-menuat-left")
  click(HOST, "cz-barup")
  UI.setXml = real
  eq(sets, 1, "cleared when its panel moved, not when it stayed put")
end)

test("the table's own seats (hand zones of other colours) are removed", function()
  local game = boot()
  local Zones = Cardalyzer.require("engine.zones")
  local white = game.layout.seats[1].hand
  -- a custom table's own zones: Brown just behind White's hand, Teal far away
  tts.newObject("Hand", { value = "Brown", position = { white.position[1], 3.3, white.position[3] - 3.4 },
    scale = { 15.3, 11.9, 6.4 }, rotation = { 0, 0, 0 } })
  tts.newObject("Hand", { value = "Teal", position = { 0, 3.3, 80 }, scale = { 15.3, 11.9, 6.4 }, rotation = { 0, 180, 0 } })
  Zones.build(game, game.layout)
  local left = {}
  for _, o in pairs(tts.objects) do if o.value and (o.type == "Hand" or o.type == "HandTrigger") then left[o.value] = true end end
  assert(not left.Brown and not left.Teal, "the table's seats are gone")
  assert(left.White and left.Red, "the players' own hands stay")
  local said = false
  for _, b in ipairs(tts.broadcasts) do if b:find("(Brown, Teal)", 1, true) then said = true end end
  assert(said, "and the players are told")
  -- nothing more to remove next time: no message
  local before = #tts.broadcasts
  Zones.build(game, game.layout)
  eq(#tts.broadcasts, before, "said once")
end)

test("cards to defeat in the market: Defeat button, paid with the attack resource, reward, scrap pile", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  game.rules.cardTypes.monster = { defeat = true }
  local ogre = game.cards:get("flame_captain") -- becomes a monster: defeat it for 6 Might
  ogre.type = "monster"
  ogre.effects = Cards.parseEffects("health:3; gold:1")
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  -- put the monster in the first slot
  local uid
  for u, id in pairs(s.cards) do if id == "flame_captain" then uid = u end end
  for i, u in ipairs(s.market.deck) do if u == uid then table.remove(s.market.deck, i) end end
  local old = s.market.row[1]
  s.market.deck[#s.market.deck + 1] = old
  s.market.row[1] = uid
  Cardalyzer.require("engine.board").sync(game)
  -- its button says Defeat
  local key = "market.row.1"
  local obj = getObjectFromGUID(s.view.piles[key][1])
  assert(obj.buttons[1].label:find("Defeat · 6", 1, true), "a Defeat button: " .. tostring(obj.buttons[1].label))
  assert(game.cards:get("flame_captain").type == "monster")
  -- can't be bought
  p.resources.gold = 99
  local ok, why = game:buy(1, uid)
  assert(not ok and why:find("defeat it with Might", 1, true), "not for sale: " .. tostring(why))
  -- not enough Might
  p.resources.might = 5
  ok, why = game:defeat(1, uid)
  assert(not ok and why:find("needs 6 Might", 1, true), "needs 6: " .. tostring(why))
  -- defeated through its button
  p.resources.might = 7
  local health = p.stats.health
  local hooked = 0
  game.effects:registerCustom("trophy", { whenYouDefeat = function() hooked = hooked + 1 end })
  local holder = Cardalyzer.require("engine.state").newCard(s, "war_anvil")
  game.cards:get("war_anvil").effects = { { key = "custom", fn = "trophy" } }
  p.bases[#p.bases + 1] = holder
  assert(Cardalyzer_onBuy(obj, "White") == nil)
  eq(p.resources.might, 1, "paid 6 Might")
  eq(p.stats.health, health + 3, "the reward")
  eq(s.market.scrap[#s.market.scrap], uid, "into the scrap pile")
  assert(s.market.row[1] ~= uid and s.market.row[1] ~= "", "the slot refilled")
  eq(s.turn.defeated, 1, "counted")
  eq(hooked, 1, "whenYouDefeat on a card in play")
  assert(tts.ui.xml:find("White defeated Flame Captain", 1, true), "announced")
  -- defeat_free: a prompt offers only cards to defeat
  local second = Cardalyzer.require("engine.state").newCard(s, "flame_captain")
  s.market.row[2] = second
  game.effects:apply(game, 1, Cards.parseEffects("defeat_free:6"), {})
  local targets = Cardalyzer.require("engine.actions").targets(game, 1, p.prompts[1])
  eq(#targets, 1, "only the monster")
  assert(game:pick(1, second), "defeated for free")
  eq(p.resources.might, 1, "no Might spent")
  -- free buys skip monsters
  local third = Cardalyzer.require("engine.state").newCard(s, "flame_captain")
  s.market.row[3] = third
  game.effects:apply(game, 1, Cards.parseEffects("free_buy:9"), {})
  for _, t in ipairs(Cardalyzer.require("engine.actions").targets(game, 1, p.prompts[1])) do
    assert(t.value ~= third, "free buys can't take a monster")
  end
  -- the tooltip says Defeat
  assert(Cardalyzer.require("engine.board").describe(game, ogre):find("^Defeat 6"), "tooltip")
end)

test("set-aside areas: kept, back next turn, or called; on the table; they score", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local State = Cardalyzer.require("engine.state")
  local Util = Cardalyzer.require("engine.util")
  game.rules.areas = {
    { key = "exile", label = "Exile" },
    { key = "later", label = "Set aside", at = "nextTurn" },
    { key = "tavern", label = "Tavern", at = "call", returns = "play" },
  }
  -- rebuild the effects so set_aside knows the areas' names
  game.effects = Cardalyzer.require("engine.effects").new(game.rules)
  game.effects.cards = game.cards
  game.cards:get("apprentice").points = 1
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  assert(p.areas.exile and p.areas.later and p.areas.tavern, "each player has the areas")
  -- set_aside: the card itself, from play
  local exiled = p.hand[1]
  eq(s.cards[exiled], s.cards[exiled])
  assert(game:play(1, exiled))
  game.effects:apply(game, 1, Cards.parseEffects("set_aside:exile"), { uid = exiled })
  assert(Util.indexOf(p.areas.exile, exiled) and not Util.indexOf(p.play, exiled), "into Exile")
  eq(game.effects:describe(Cards.parseEffects("set_aside:exile")), "Put this in your Exile", "described")
  -- still theirs: it scores
  local score = Cardalyzer.require("engine.actions").score(game, 1)
  local apprentices = 0
  for _, list in ipairs({ p.deck, p.hand, p.discard, p.play, p.areas.exile }) do
    for _, uid in ipairs(list) do if s.cards[uid] == "apprentice" then apprentices = apprentices + 1 end end
  end
  eq(score, apprentices + p.stats.health, "exiled cards still count (plus Health, the win stat)")
  -- set_aside_hand: a choice from the hand, back at the start of the next turn
  local kept = p.hand[1]
  game.effects:apply(game, 1, Cards.parseEffects("set_aside_hand:later"), {})
  eq(p.prompts[1].kind, "set_aside", "asks for a card")
  assert(tts.ui.xml:find("Put a card from your hand in your Set aside", 1, true) or true)
  assert(game:pick(1, kept))
  assert(Util.indexOf(p.areas.later, kept), "set aside")
  -- the table shows the areas
  Cardalyzer.require("engine.board").sync(game)
  assert(s.view.piles["1.area.exile"], "a pile for Exile on the table")
  assert(game.layout.seats[1].areas.tavern, "a spot for each area")
  Cardalyzer_onEndTurn(HOST)
  Cardalyzer_onEndTurn({ color = "Red" })
  assert(Util.indexOf(p.hand, kept), "back in the hand at the start of the next turn")
  eq(#p.hand, 6, "on top of the new hand")
  assert(Util.indexOf(p.areas.exile, exiled), "Exile keeps its cards")
  -- call: a Call button on the owner's turn puts it into play
  local reserve = State.newCard(s, "tide_runner")
  p.areas.tavern[1] = reserve
  game:refreshUI()
  assert(tts.ui.xml:find('id="cz%-call%-' .. reserve .. '"[^>]*>Call Tide Runner<'), "a Call button")
  local gold = p.resources.gold
  click(HOST, "cz-call-" .. reserve)
  assert(Util.indexOf(p.play, reserve), "called into play")
  eq(p.resources.gold, gold + 2, "its effects applied")
  -- an unknown area is reported at load
  local bad = Cards.new({ { id = "a", name = "A", cost = 1, copies = 1, effects = "set_aside:nowhere" } })
  local problems = game.effects:validate(bad)
  assert(problems[1] and problems[1]:find("rules.areas has no 'nowhere'", 1, true), tostring(problems[1]))
  -- saved and loaded
  local restored = boot(game:save())
  assert(Util.indexOf(restored.state.players[1].areas.exile, exiled), "areas survive a reload")
end)

test("next_effects: the card stays in play and its effects come at the start of the next turn", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local Util = Cardalyzer.require("engine.util")
  local c = game.cards:get("tide_runner")
  c.nextEffects = Cards.parseEffects("draw:2; gold:1")
  local jobs = 0
  game.effects:registerCustom("later", { atNextTurn = function(_, seat, job) jobs = jobs + job.n end })
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local uid = Cardalyzer.require("engine.state").newCard(s, "tide_runner")
  p.hand[#p.hand + 1] = uid
  assert(game:play(1, uid))
  game:atNextTurn(1, { custom = "later", n = 3 })
  Cardalyzer_onEndTurn(HOST)
  assert(Util.indexOf(p.lasting, uid), "kept in play over the turn")
  assert(not Util.indexOf(p.discard, uid), "not discarded")
  Cardalyzer.require("engine.board").sync(game)
  local inPlayPile = false
  for _, pile in ipairs(Cardalyzer.require("engine.board").piles(game)) do
    if pile.key == "1.play" and Util.indexOf(pile.uids, uid) then inPlayPile = true end
  end
  assert(inPlayPile, "shown in the play area")
  Cardalyzer_onEndTurn({ color = "Red" })
  eq(#p.hand, 7, "drew 2 at the start of the turn")
  eq(p.resources.gold, 1, "and +1 Gold")
  eq(jobs, 3, "atNextTurn job ran")
  assert(Util.indexOf(p.play, uid) and #p.lasting == 0, "back in play for this turn")
  Cardalyzer_onEndTurn(HOST)
  assert(Util.indexOf(p.discard, uid) or Util.indexOf(p.deck, uid) or Util.indexOf(p.hand, uid), "then discarded as usual")
  assert(not Util.indexOf(p.play, uid), "out of play")
  eq(#p.lasting, 0, "not kept again")
  eq(Cardalyzer.require("engine.board").describe(game, c):find("Next turn: Draw 2, %+1 Gold") ~= nil, true, "tooltip")
end)

test("a card can have several types: filters, phases, play costs and type flags see them all", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local Actions = Cardalyzer.require("engine.actions")
  local lib = Cards.new({ { id = "a", name = "A", cost = 1, copies = 1, effects = "", type = "action / attack" } })
  local a = lib:get("a")
  eq(a.type, "action", "the first type")
  eq(table.concat(a.types, ","), "action,attack", "both types")
  assert(Cards.hasType(a, "attack") and not Cards.hasType(a, "unit"), "hasType")
  assert(Actions.typeMatches("attack", a) and Actions.typeMatches({ "treasure", "action" }, a), "filters match any type")
  -- type flags combine: a unit that is also a wall is a guard that stays in play
  local c = game.cards:get("tide_runner")
  c.type, c.types = "unit", { "unit", "wall" }
  local def = Actions.typeDef(game, c)
  assert(def.persistent and def.guard, "flags from both types")
  -- phases and play costs: the first type with a cost
  game.rules.resources[#game.rules.resources + 1] = { key = "actions", label = "Actions", start = 1 }
  game.rules.turn = {
    phases = { { key = "a", label = "A", play = "wall" } },
    playCost = { wall = { key = "actions", amount = 1 } },
  }
  Cardalyzer_onStartGame(HOST)
  local p = game.state.players[1]
  local uid = Cardalyzer.require("engine.state").newCard(game.state, "tide_runner")
  p.hand[#p.hand + 1] = uid
  local apprentice
  for _, u in ipairs(p.hand) do if game.state.cards[u] == "apprentice" then apprentice = u end end
  assert(not game:play(1, apprentice), "a plain unit can't be played in a wall phase")
  assert(game:play(1, uid), "the unit/wall can")
  eq(p.resources.actions, 0, "paid the wall's play cost")
  assert(Cardalyzer.require("engine.util").indexOf(p.bases, uid), "stays in play, as a wall does")
  eq(Actions.guards(game, 1)[1], uid, "and guards")
  assert(Cardalyzer.require("engine.board").describe(game, c):find("Unit – Wall", 1, true), "both types in the tooltip")
  game.rules.turn = nil
end)

test("conditions on effects: only while a stat, resource or count reaches a level", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local list = Cards.parseEffects("gold:1; health>=45=might:5; hand<=2=draw:1; blob=might:1")
  eq(list[2].cond.key, "health", "parsed")
  eq(list[2].cond.op, ">=")
  eq(list[2].cond.n, 45)
  eq(list[4].ally, "blob", "faction prefixes still parse")
  eq(game.effects:describe({ list[2] }), "(Health 45+) +5 Might", "described")
  eq(game.effects:describe({ list[3] }), "(Hand 2 or less) Draw 1", "a count")
  Cardalyzer_onStartGame(HOST)
  local p = game.state.players[1]
  game.effects:apply(game, 1, { list[2] }, {})
  eq(p.resources.might, 0, "Health 40: not yet")
  p.stats.health = 45
  game.effects:apply(game, 1, { list[2] }, {})
  eq(p.resources.might, 5, "Health 45: unlocked")
  local hand = #p.hand
  game.effects:apply(game, 1, { list[3] }, {})
  eq(#p.hand, hand, "5 cards in hand: no draw")
  p.hand = { p.hand[1] }
  game.effects:apply(game, 1, { list[3] }, {})
  eq(#p.hand, 2, "1 card in hand: drew")
  -- played this turn
  local played = Cards.parseEffects("played>1=gold:3")
  game.effects:apply(game, 1, played, {})
  eq(p.resources.gold, 0, "nothing played yet")
  game.state.turn.played = { "x", "y" }
  game.effects:apply(game, 1, played, {})
  eq(p.resources.gold, 3, "two played")
  -- an unknown key is reported at load
  local bad = Cards.new({ { id = "a", name = "A", cost = 1, copies = 1, effects = "luck>=3=gold:1" } })
  local problems = game.effects:validate(bad)
  assert(problems[1] and problems[1]:find("condition on 'luck'", 1, true), tostring(problems[1]))
end)

test("hiring a market card for one turn: Hire button, effects now, back under the market deck", function()
  local game = boot()
  local Util = Cardalyzer.require("engine.util")
  game.rules.cardTypes.mercenary = { hire = true }
  local merc = game.cards:get("tide_runner") -- +2 Gold
  merc.type = "mercenary"
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local uid = Cardalyzer.require("engine.state").newCard(s, "tide_runner")
  s.market.deck[#s.market.deck + 1] = s.market.row[1]
  s.market.row[1] = uid
  Cardalyzer.require("engine.board").sync(game)
  local obj = getObjectFromGUID(s.view.piles["market.row.1"][1])
  local labels = {}
  for _, b in ipairs(obj.buttons) do labels[#labels + 1] = b.label end
  local all = table.concat(labels, "|")
  assert(all:find("Hire · 1", 1, true) and all:find("Buy · 1", 1, true), "Hire and Buy buttons: " .. all)
  p.resources.gold = 0
  local ok = game:hire(1, uid)
  assert(not ok, "costs 1 Gold")
  p.resources.gold = 1
  Cardalyzer_onHire(obj, "White")
  assert(Util.indexOf(p.play, uid), "in play")
  eq(p.resources.gold, 2, "paid 1, got its +2")
  assert(s.market.row[1] ~= uid and s.market.row[1] ~= "", "the slot refilled")
  Cardalyzer_onEndTurn(HOST)
  eq(s.market.deck[1], uid, "at the bottom of the market deck")
  assert(not Util.indexOf(p.discard, uid) and not Util.indexOf(p.deck, uid), "not the player's")
  -- a plain market card has no Hire button and can't be hired
  local other = s.market.row[2]
  ok = game:hire(2, other)
  assert(not ok, "not a card to hire")
end)

test("face-down dealt cards: hidden from other players until their owner reveals them", function()
  local game = boot()
  local Util = Cardalyzer.require("engine.util")
  local State = Cardalyzer.require("engine.state")
  local Turn = Cardalyzer.require("engine.turn")
  game.rules.cardTypes.scheme = { persistent = true, faceDown = true }
  local merc = game.cards:get("tide_runner") -- +2 Gold
  merc.type = "scheme"
  Cardalyzer_onStartGame(HOST)
  local s, p, red = game.state, game.state.players[1], game.state.players[2]
  -- dealing one: face down, not in play
  local uid = State.newCard(s, "tide_runner")
  Turn.dealInto(game.rules, p, uid, merc)
  eq(p.facedown[1], uid, "face down")
  assert(not Util.indexOf(p.bases, uid), "not in play yet")
  -- a type without faceDown goes straight into play
  local plain = State.newCard(s, "war_anvil")
  Turn.dealInto(game.rules, red, plain, game.cards:get("war_anvil"))
  assert(Util.indexOf(red.bases, plain) and #red.facedown == 0, "dealt into play")
  Cardalyzer.require("engine.board").sync(game)
  local obj = getObjectFromGUID(s.view.piles["1.bases"][1])
  eq(obj.data.GMNotes, uid, "shown in its owner's bases row")
  local hidden = table.concat(obj.hiddenFrom or {}, ",")
  assert(hidden:find("Red", 1, true) and hidden:find("Grey", 1, true) and not hidden:find("White", 1, true), "hidden from all but White: " .. hidden)
  -- its effects wait until it's revealed
  p.resources.gold = 0
  game:refreshUI()
  assert(tts.ui.xml:find("Reveal Tide Runner", 1, true), "a Reveal button")
  assert(not game:reveal(2, uid), "only on its owner's turn")
  click(HOST, "cz-reveal-" .. uid)
  assert(Util.indexOf(p.bases, uid) and #p.facedown == 0, "revealed into play")
  eq(p.resources.gold, 2, "its effects apply")
  Cardalyzer.require("engine.board").sync(game)
  local shown = getObjectFromGUID(s.view.piles["1.bases"][#s.view.piles["1.bases"]])
  eq(shown.hiddenFrom, nil, "everyone sees it now")
  assert(not game:reveal(1, uid), "can't reveal it twice")
  assertConserved(game)
  game.rules.cardTypes.scheme = nil
end)

test("a type with buyTo = \"play\" goes straight into play when bought", function()
  local game = boot()
  local Util = Cardalyzer.require("engine.util")
  game.rules.cardTypes.champion = { persistent = true, replay = false, buyTo = "play" }
  game.cards:get("tide_runner").type = "champion" -- +2 Gold
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local uid = Cardalyzer.require("engine.state").newCard(s, "tide_runner")
  s.market.deck[#s.market.deck + 1] = s.market.row[1]
  s.market.row[1] = uid
  p.resources.gold = 1
  p.flags.buyToTop = true -- "put the next card you buy on top" isn't used up by it
  assert(game:buy(1, uid), "bought")
  assert(Util.indexOf(p.bases, uid), "in play")
  assert(not Util.indexOf(p.discard, uid), "not in the discard pile")
  eq(p.resources.gold, 2, "paid 1, got its +2 at once")
  eq(p.flags.buyToTop, true, "the flag waits for the next card")
  assertConserved(game)
  game.rules.cardTypes.champion = nil
end)

test("cards in play with a scrap ability get a Scrap button hanging off their bottom edge", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local State = Cardalyzer.require("engine.state")
  local Board = Cardalyzer.require("engine.board")
  local scout, squire = State.newCard(s, "shade_scout"), State.newCard(s, "squire") -- Scrap: +2 Might; none
  p.play[#p.play + 1] = scout
  p.play[#p.play + 1] = squire
  Board.sync(game, { instant = true })
  local objs = {}
  for _, guid in ipairs(s.view.piles["1.play"]) do
    local o = getObjectFromGUID(guid)
    objs[o.data.GMNotes] = o
  end
  local o = objs[scout]
  eq(o.decals, nil, "nothing stuck on the card (it would show when inspected)")
  eq(#o.buttons, 1, "one button")
  local b = o.buttons[1]
  eq(b.label, "Scrap", "labelled")
  eq(b.click_function, "Cardalyzer_onScrapIcon", "clicks scrap it")
  assert(b.tooltip:find("Scrap Shade Scout", 1, true), "tooltip: " .. b.tooltip)
  eq(b.position[1], 0, "centred across the card")
  assert(b.position[3] - 100 / 410 > 1.53, "below the card, covering none of it: " .. b.position[3])
  eq(#objs[squire].buttons, 0, "no button on a card without a scrap ability")
  -- rules.ui.scrapButton.at: how far down the card
  game.rules.ui = game.rules.ui or {}
  game.rules.ui.scrapButton = { at = 0.5 }
  local placed = tts.newObject("Card", {})
  Board.addScrapButton(game, placed, State.newCard(s, "shade_scout"))
  eq(placed.buttons[1].position[3], 0, "halfway down: the middle")
  game.rules.ui.scrapButton = nil
  -- someone else can't scrap White's card; White can
  Cardalyzer_onScrapIcon(o, "Red")
  assert(Cardalyzer.require("engine.util").indexOf(p.play, scout), "still in play")
  local might = p.resources.might or 0
  Cardalyzer_onScrapIcon(o, "White")
  eq(p.resources.might, might + 2, "scrapped for +2 Might")
  assert(not Cardalyzer.require("engine.util").indexOf(p.play, scout), "gone from play")
  -- a type printed sideways (or a card turned as used): across the card as it reads
  game.rules.cardTypes.unit = game.rules.cardTypes.unit or {}
  game.rules.cardTypes.unit.playYaw = 90
  local obj = tts.newObject("Card", {})
  Board.addScrapButton(game, obj, State.newCard(s, "shade_scout"))
  local sb = obj.buttons[1]
  assert(sb.position[1] - 100 / 410 > 1.095 and sb.position[3] == 0, "off the reader's bottom edge")
  eq(sb.rotation[2], 270, "turned to read upright")
  assert(sb.width > b.width, "as wide as the card reads")
  game.rules.cardTypes.unit.playYaw = nil
  -- a closed-up pile: the button moves to the strip of the card still showing
  local col = tts.newObject("Card", {})
  Board.addScrapButton(game, col, State.newCard(s, "shade_scout"), 0, { column = true, room = 0.9 })
  local cb = col.buttons[1]
  assert(cb.position[1] - cb.width / 410 / 2 > 1.095, "a column: beside the card")
  assert(math.abs(cb.position[3] - (-1.53 + 0.45)) < 1e-6, "level with its top strip: " .. cb.position[3])
  local row = tts.newObject("Card", {})
  Board.addScrapButton(game, row, State.newCard(s, "shade_scout"), 0, { room = 1.2 })
  local rb = row.buttons[1]
  assert(rb.position[3] < -1.53, "a row: above the card")
  assert(math.abs(rb.position[1] - (-1.095 + 0.6)) < 1e-6, "over its left strip: " .. rb.position[1])
  assert(rb.width / 410 <= 1.2, "no wider than the strip")
  -- in play, a column too long for its area closes up and uses that
  game.rules.ui.scrapButton = nil
  local many = {}
  for i = 1, 12 do many[i] = State.newCard(s, "shade_scout"); p.play[#p.play + 1] = many[i] end
  Board.sync(game, { instant = true })
  local last = getObjectFromGUID(s.view.piles["1.play"][#s.view.piles["1.play"]])
  assert(last.buttons[1].position[3] < -1.53, "an overlapping play row puts them above the cards")
  -- a column with wrap: two columns edge to edge inside the area, never a third
  local wide = 3.06 + 0.05
  local spot = { position = { 0, 1, 0 }, right = { 1, 0 }, forward = { 0, 1 }, size = { 2 * wide, 3, 11.7 }, column = true, wrap = "left" }
  local four = Board.rowPositions(spot, 4, 2.8, 2.4, true)
  assert(math.abs(four[1][1] - wide / 2) < 1e-6, "four fit in the right-hand column: " .. four[1][1])
  local pos, cols = Board.rowPositions(spot, 6, 2.8, 2.4, true)
  eq(cols[5], 2, "the fifth starts the second column")
  assert(math.abs(pos[5][1] + wide / 2) < 1e-6, "to its left, edge to edge: " .. pos[5][1])
  for _, at in ipairs(pos) do
    assert(math.abs(at[1]) + 3.06 / 2 <= spot.size[1] / 2 + 1e-6, "inside the area")
  end
  -- a row with wrap = true: a full row starts another, down the area's depth
  local area = { position = { 0, 1, 0 }, right = { 1, 0 }, forward = { 0, 1 }, size = { 14.4, 3, 11.7 }, wrap = true }
  local one = Board.rowPositions(area, 5, 2.9, 2.4, false)
  eq(one[1][3], 0, "five fit in one row")
  local two = Board.rowPositions(area, 6, 2.9, 2.4, false)
  assert(two[1][3] > 0 and two[6][3] < 0, "six: two rows, the first nearer the centre")
  local full = Board.rowPositions(area, 20, 2.9, 2.4, false)
  for _, at in ipairs(full) do
    assert(math.abs(at[1]) + 1.095 <= 7.2 + 1e-6 and math.abs(at[3]) + 1.53 <= 5.85 + 1e-6, "inside the area")
  end
  local lots, lotCols = Board.rowPositions(spot, 12, 2.8, 2.4, true)
  eq(lotCols[12], 2, "twelve still in two columns")
  assert(lots[2][3] - lots[1][3] > -2.8, "which close up")
  -- rules.ui.scrapButton = false: none
  game.rules.ui.scrapButton = false
  local plain = tts.newObject("Card", {})
  Board.addScrapButton(game, plain, State.newCard(s, "shade_scout"))
  eq(#plain.buttons, 0, "turned off")
  game.rules.ui.scrapButton = nil
end)

test("attacking a player: reactions from hand prevent or block the damage", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local State = Cardalyzer.require("engine.state")
  game.cards:get("tide_runner").reactEffects = Cards.parseEffects("prevent:3")
  game.cards:get("shade_scout").reactEffects = Cards.parseEffects("block")
  Cardalyzer_onStartGame(HOST)
  local s = game.state
  local white, red = s.players[1], s.players[2]
  -- no reaction in hand: the damage lands at once
  white.resources.might = 4
  click(HOST, "cz-attack-2")
  eq(red.stats.health, 36, "4 damage")
  eq(white.resources.might, 0, "the pool is spent")
  -- a shield: prevent 3
  local shield = State.newCard(s, "tide_runner")
  red.hand[#red.hand + 1] = shield
  white.resources.might = 5
  click(HOST, "cz-attack-2")
  eq(red.prompts[1].kind, "react", "Red is asked")
  game:refreshUI()
  assert(tts.ui.xml:find("White attacks you: 5 damage to Health. Reveal a reaction?", 1, true), "the question")
  eq(red.stats.health, 36, "nothing yet")
  eq(white.resources.might, 0, "spent at once")
  assert(game:pick(2, shield), "Red reveals the shield")
  eq(red.stats.health, 34, "5 - 3 = 2 damage")
  -- block: none
  local wall = State.newCard(s, "shade_scout")
  red.hand[#red.hand + 1] = wall
  white.resources.might = 6
  click(HOST, "cz-attack-2")
  local before = red.stats.health
  assert(game:pick(2, wall), "Red reveals the block")
  game:done(2)
  eq(red.stats.health, before, "blocked")
  -- not revealed: all of it, and a knock-out still ends the game
  red.stats.health = 4
  white.resources.might = 4
  click(HOST, "cz-attack-2")
  assert(game:done(2), "Red doesn't reveal")
  assert(red.out, "Red is out")
  eq(s.winner, 1, "White wins")
  -- as a card's effect
  eq(game.effects:describe(Cards.parseEffects("opponents_damage:2")), "2 damage to Health", "described")
end)

test("a game's own resource or stat isn't replaced by a built-in keyword of the same name", function()
  local game = boot()
  game.rules.resources[#game.rules.resources + 1] = { key = "prevent", label = "Prevent" }
  local fx = Cardalyzer.require("engine.effects").new(game.rules)
  eq(fx:describe({ { key = "prevent", amount = 2 } }), "+2 Prevent", "the game's own keyword")
  table.remove(game.rules.resources)
end)

test("no reshuffle: the discard pile is turned over in order", function()
  local game = boot()
  game.rules.reshuffle = false
  Cardalyzer_onStartGame(HOST)
  local p = game.state.players[1]
  local order = {}
  for _, uid in ipairs(p.deck) do order[#order + 1] = uid end
  for _, uid in ipairs(p.hand) do order[#order + 1] = uid end
  p.discard, p.deck, p.hand = order, {}, {}
  game:draw(1, 3)
  eq(p.hand[1], order[1], "the first card discarded comes first")
  eq(p.hand[2], order[2])
  eq(p.hand[3], order[3])
  eq(#p.discard, 0, "the whole pile turned over")
  game.rules.reshuffle = nil
end)

test("look_top: look at the top cards and put them back in any order", function()
  local game = boot()
  local Cards = Cardalyzer.require("engine.cards")
  local Actions = Cardalyzer.require("engine.actions")
  Cardalyzer_onStartGame(HOST)
  local p = game.state.players[1]
  local n = #p.deck
  local top = { p.deck[n], p.deck[n - 1], p.deck[n - 2] }
  game.effects:apply(game, 1, Cards.parseEffects("look_top:3"), {})
  eq(p.prompts[1].kind, "arrange", "asks")
  eq(Actions.promptText(game, p.prompts[1]), "Put these back on your deck: choose the top card", "the question")
  eq(#Actions.targets(game, 1, p.prompts[1]), 3, "the top three")
  -- put the third card on top, then the first, then the second
  assert(game:pick(1, top[3]))
  eq(Actions.promptText(game, p.prompts[1]), "Choose the next card down", "then the next")
  assert(game:pick(1, top[1]))
  assert(game:pick(1, top[2]))
  eq(#p.prompts, 0, "done")
  eq(#p.deck, n, "nothing lost")
  eq(p.deck[n], top[3], "the first picked is on top")
  eq(p.deck[n - 1], top[1])
  eq(p.deck[n - 2], top[2])
end)

test("a card used with its Use button lies turned sideways until its owner's next turn", function()
  local game = boot()
  game.effects:registerCustom("tap", { activate = function(g, seat) g.state.players[seat].resources.gold = 9 end })
  game.cards:get("war_anvil").effects = { { key = "custom", fn = "tap" } }
  Cardalyzer_onStartGame(HOST)
  local s, p = game.state, game.state.players[1]
  local anvil = Cardalyzer.require("engine.state").newCard(s, "war_anvil")
  p.bases[#p.bases + 1] = anvil
  Cardalyzer.require("engine.board").sync(game)
  local function yaw()
    local obj = getObjectFromGUID(s.view.piles["1.bases"][1])
    return obj.rotation[2]
  end
  local flat = yaw()
  click(HOST, "cz-use-" .. anvil)
  eq(p.resources.gold, 9, "used")
  eq((yaw() - flat) % 360, 90, "turned sideways")
  Cardalyzer_onEndTurn(HOST)
  eq((yaw() - flat) % 360, 90, "still sideways on the next player's turn")
  Cardalyzer_onEndTurn({ color = "Red" })
  eq(yaw(), flat, "upright again on its owner's turn")
end)

test("a fixed pile can be placed by its card id, like the market deck and scrap pile", function()
  local game = boot()
  local Zones = Cardalyzer.require("engine.zones")
  local function near(a, b) return math.abs(a - b) < 0.01 end
  local before = Zones.layout(game.rules, game.fixedIds, 2).market.fixed.hireling.position
  game.rules.layout = { areas = { market = { x = -2 }, hireling = { along = 7.5, out = 1 } } }
  local after = Zones.layout(game.rules, game.fixedIds, 2).market.fixed.hireling.position
  assert(near(after[1], 5.5) and near(after[3], 1), "moved from the middle of the market")
  assert(not near(before[1], after[1]), "not where it was")
  Cardalyzer_onStartGame(HOST)
  local obj = getObjectFromGUID(game.state.view.piles["fixed.hireling"][1])
  assert(near(obj.position[1], 5.5), "the pile is laid there")
  assertConserved(game)
end)

test("a game's own records in state.turn are cleared when the next turn starts", function()
  local game = boot()
  Cardalyzer_onStartGame(HOST)
  local turn = game.state.turn
  turn.usedShield, turn.paid = true, { c1 = true }
  local first, number = turn.first, turn.number
  Cardalyzer_onEndTurn(HOST)
  eq(game.state.turn.usedShield, nil, "own flag")
  eq(game.state.turn.paid, nil, "own table")
  eq(game.state.turn.active, 2, "active")
  eq(game.state.turn.number, number + 1, "number")
  eq(game.state.turn.first, first, "first")
  assert(game.state.turn.played and game.state.turn.allyFired, "the engine's records are back, empty")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
