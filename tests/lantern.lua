-- Headless checks for the Lantern Fair sample game. From the repo root:
--   python tools/bundle.py games/lantern -o build/lantern/Global.lua
--   lua tests/lantern.lua
local BUILD = "build/lantern/Global.lua"
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
local function click(player, id) Cardalyzer_onUI(player, "-1", id) end

local function boot(seed, saved)
  tts.reset()
  math.randomseed(seed or 7)
  dofile(BUILD)
  onLoad(saved or "")
  if not Cardalyzer then error("onLoad failed: " .. table.concat(tts.broadcasts, "; ")) end
  return Cardalyzer.game
end

-- A new game for `players`, with supply preset `preset` (0 for random).
local function start(players, preset, seed)
  local game = boot(seed)
  if players and players ~= 2 then click(HOST, "cz-players-" .. players) end
  if preset then click(HOST, "cz-supply-" .. preset) end
  Cardalyzer_onStartGame(HOST)
  return game
end

local function count(list, game, id)
  local n = 0
  for _, uid in ipairs(list) do if game.state.cards[uid] == id then n = n + 1 end end
  return n
end

-- Puts a new card of `id` in a player's hand.
local function give(game, seat, id)
  local uid = Cardalyzer.require("engine.state").newCard(game.state, id)
  local hand = game.state.players[seat].hand
  hand[#hand + 1] = uid
  return uid
end

-- Every card instance is in exactly one pile.
local function assertConserved(game)
  local s, seen, total = game.state, {}, 0
  local function visit(list)
    for _, uid in ipairs(list) do
      if uid ~= "" then
        if seen[uid] then error("card " .. uid .. " is in two piles") end
        seen[uid], total = true, total + 1
      end
    end
  end
  for _, p in ipairs(s.players) do
    visit(p.deck); visit(p.hand); visit(p.discard); visit(p.play); visit(p.bases)
  end
  visit(s.market.deck); visit(s.market.row); visit(s.market.scrap)
  for _, pile in pairs(s.market.fixed) do visit(pile) end
  for _, m in ipairs(s.markets) do visit(m.deck); visit(m.row) end
  local instances = 0
  for _ in pairs(s.cards) do instances = instances + 1 end
  eq(total, instances, "cards in piles")
end

test("a new game: starting decks, the supply, pile sizes and the Peddlers row", function()
  local game = start(2, 1)
  local s = game.state
  for seat, p in ipairs(s.players) do
    local all = {}
    for _, list in ipairs({ p.deck, p.hand }) do for _, uid in ipairs(list) do all[#all + 1] = uid end end
    eq(#all, 10, "seat " .. seat .. " starts with 10 cards")
    eq(count(all, game, "ribbon"), 6, "6 Ribbons")
    eq(count(all, game, "small_lantern"), 2, "2 Small Lanterns")
    eq(count(all, game, "hawker"), 2, "2 Hawkers")
    eq(#p.hand, 5, "a hand of 5")
  end
  eq(#s.market.supply, 8, "8 supply piles")
  eq(s.market.supply[1], "rag_picker", "the First Fair preset, cheapest first")
  eq(#s.market.fixed.ribbon, 40, "the Ribbon pile is separate from the starting decks")
  eq(#s.market.fixed.sky_lantern, 8, "8 Sky Lanterns for 2 players")
  eq(#s.market.fixed.gossip, 10, "10 Gossip per opponent")
  eq(#s.market.fixed.juggler, 10, "10 of a supply card")
  eq(#s.market.row, 0, "no main market row")
  local peddlers = s.markets[1]
  eq(#peddlers.row, 3, "3 Peddlers for sale")
  for _, uid in ipairs(peddlers.row) do assert(uid ~= "", "the Peddlers row is full") end
  assertConserved(game)
  -- the table: two rows of piles, every pile placed, no pile on top of another
  local spots = {}
  for _, id in ipairs(game.fixedIds) do
    local p = game.layout.market.fixed[id].position
    local key = string.format("%.1f,%.1f", p[1], p[3])
    assert(not spots[key], id .. " overlaps another pile")
    spots[key] = true
  end
  eq(#game.fixedIds, 15, "7 basic piles and 8 supply piles")
  -- 4 players: more renown and gossip
  game = start(4, 1)
  eq(#game.state.market.fixed.sky_lantern, 12, "12 Sky Lanterns for 4 players")
  eq(#game.state.market.fixed.gossip, 30, "30 Gossip for 4 players")
end)

test("a turn: action phase, goods move on to the Buy phase, buying", function()
  local game = start(2, 1)
  local s, p = game.state, game.state.players[1]
  p.hand = {}
  local hawker = give(game, 1, "hawker")
  local ribbon = give(game, 1, "ribbon")
  local lantern = give(game, 1, "small_lantern")
  local ok, why = game:play(1, lantern)
  assert(not ok, "renown can't be played: " .. tostring(why))
  assert(game:play(1, hawker), "a Hawker in the Action phase")
  eq(p.resources.actions, 1, "Hawker gives back its Action")
  eq(p.resources.coin, 1, "and 1 Coin")
  assert(game:play(1, ribbon), "Ribbon played in the Action phase")
  eq(s.turn.phase, 2, "moves on to the Buy phase")
  eq(p.resources.coin, 2, "Ribbon's Coin")
  local juggler = s.market.fixed.juggler[#s.market.fixed.juggler]
  ok = game:buy(1, juggler)
  assert(not ok, "Juggler costs 3")
  p.resources.coin = 3
  assert(game:buy(1, juggler), "bought")
  eq(p.resources.buys, 0, "the Buy is spent")
  eq(s.cards[p.discard[#p.discard]], "juggler", "into the discard pile")
  assert(not game:buy(1, s.market.fixed.ribbon[1]), "no Buys left, even for a free card")
  Cardalyzer_onEndTurn(HOST)
  eq(#p.hand, 5, "a new hand")
  eq(p.resources.actions, 1, "Actions back to 1")
  eq(s.turn.active, 2, "Red's turn")
end)

test("supply cards: gain, gain up to a cost, choose one, scrap, the Pawnbroker", function()
  local game = start(2, 1)
  local s, p = game.state, game.state.players[1]
  p.hand, p.discard = {}, {}
  local trader = give(game, 1, "silk_trader")
  p.resources.actions = 3
  assert(game:play(1, trader), "Silk Trader")
  eq(count(p.discard, game, "silk"), 1, "gained a Silk")
  eq(p.resources.coin, 1, "+1 Coin")
  local maker = give(game, 1, "lantern_maker")
  assert(game:play(1, maker), "Lantern Maker")
  local Actions = Cardalyzer.require("engine.actions")
  local options = {}
  for _, t in ipairs(Actions.targets(game, 1, p.prompts[1])) do options[s.cards[t.value]] = t.value end
  assert(options.storyteller and not options.silk_trader, "up to 4 from the supply")
  assert(options.small_lantern, "renown piles too")
  assert(game:pick(1, options.storyteller), "gained a Storyteller")
  eq(count(p.discard, game, "storyteller"), 1, "into the discard pile")
  eq(p.resources.coin, 1, "for free")
  local teller = give(game, 1, "fortune_teller")
  assert(game:play(1, teller), "Fortune Teller")
  eq(p.prompts[1].kind, "choice", "Coin or cards")
  assert(game:pick(1, "1"), "+2 Coin")
  eq(p.resources.coin, 3, "chose Coin")
  -- Pawnbroker (Rowdy Night preset)
  game = start(2, 2)
  s, p = game.state, game.state.players[1]
  p.hand = {}
  local broker = give(game, 1, "pawnbroker")
  local ribbon = give(game, 1, "ribbon")
  give(game, 1, "silk")
  assert(game:play(1, broker), "Pawnbroker")
  local targets = Actions.targets(game, 1, p.prompts[1])
  eq(#targets, 1, "only the Ribbon can be scrapped")
  assert(game:pick(1, ribbon), "scrapped the Ribbon")
  eq(p.resources.coin, 3, "+3 Coin")
  eq(s.cards[s.market.scrap[#s.market.scrap]], "ribbon", "on the scrap pile")
end)

test("attacks and reactions in the Rowdy Night supply", function()
  local game = start(3, 2)
  local s = game.state
  local white, red, blue = s.players[1], s.players[2], s.players[3]
  for _, uid in ipairs(white.hand) do white.deck[#white.deck + 1] = uid end
  white.hand = {}
  white.resources.actions = 5
  local charm = give(game, 2, "paper_charm")
  -- Town Crier: Red may block with Paper Charm, Blue gains a Gossip
  local crier = give(game, 1, "town_crier")
  local gossip = #s.market.fixed.gossip
  assert(game:play(1, crier), "Town Crier")
  eq(red.prompts[1].kind, "react", "Red holds a reaction")
  eq(#blue.prompts, 0, "Blue doesn't")
  eq(count(blue.discard, game, "gossip"), 1, "Blue gained a Gossip at once")
  game:refreshUI()
  assert(tts.ui.xml:find("Reveal Paper Charm", 1, true), "Red sees the reveal button")
  assert(game:pick(2, charm), "Red reveals Paper Charm")
  eq(count(red.discard, game, "gossip"), 0, "blocked")
  eq(#s.market.fixed.gossip, gossip - 1, "only one Gossip taken")
  -- Pickpocket: discard down to 3, answered on White's turn
  local pocket = give(game, 1, "pickpocket")
  assert(game:play(1, pocket), "Pickpocket")
  assert(game:done(2), "Red doesn't reveal this time")
  eq(red.prompts[1].kind, "discard", "Red discards")
  eq(red.prompts[1].count, #red.hand - 3, "down to 3")
  while red.prompts[1] do assert(game:pick(2, red.hand[1]), "Red discards, keeping the Paper Charm") end
  eq(#red.hand, 3, "Red has 3")
  while blue.prompts[1] do assert(game:pick(3, blue.hand[#blue.hand]), "Blue discards") end
  eq(#blue.hand, 3, "Blue has 3")
  -- Night Watch draws first, then the attack lands
  local watch = give(game, 3, "night_watch")
  local heckler = give(game, 1, "heckler")
  assert(game:play(1, heckler), "Heckler")
  assert(game:done(2), "Red doesn't reveal")
  eq(#red.prompts, 0, "Red has only 3 cards: untouched")
  assert(game:pick(3, watch), "Blue reveals Night Watch")
  eq(#blue.hand, 5, "drew a card: now 5")
  eq(blue.prompts[1] and blue.prompts[1].kind, "discard", "so Heckler makes Blue discard")
  -- an unanswered reaction is passed at the end of White's turn
  local cryAgain = give(game, 1, "town_crier")
  assert(game:play(1, cryAgain), "another Town Crier")
  eq(red.prompts[1].kind, "react", "Red is asked again")
  Cardalyzer_onEndTurn(HOST)
  eq(count(red.discard, game, "gossip"), 1, "the Gossip landed")
  assertConserved(game)
end)

test("scores, and the game ending when the Sky Lanterns run out", function()
  local game = start(2, 1)
  local s = game.state
  local Actions = Cardalyzer.require("engine.actions")
  eq(Actions.score(game, 1), 2, "2 Small Lanterns")
  local p2 = s.players[2]
  p2.discard[#p2.discard + 1] = Cardalyzer.require("engine.state").newCard(s, "heirloom_fan")
  p2.discard[#p2.discard + 1] = Cardalyzer.require("engine.state").newCard(s, "gossip")
  eq(Actions.score(game, 2), 2, "+1 for the Heirloom Fan, -1 for the Gossip")
  -- White takes the last Sky Lantern: Red still gets a turn
  local pile = s.market.fixed.sky_lantern
  while #pile > 1 do table.remove(pile) end
  s.players[1].resources.coin = 9
  click(HOST, "cz-phase")
  assert(game:buy(1, pile[1]), "the last Sky Lantern")
  Cardalyzer_onEndTurn(HOST)
  assert(s.ending and not s.winner, "Red plays the round out")
  Cardalyzer_onEndTurn({ color = "Red" })
  eq(s.winner, 1, "White wins with the Sky Lantern")
  assert(tts.ui.xml:find("White wins!", 1, true), "announced")
end)

-- A simple player: plays its actions, then its goods, buys the dearest card
-- it can afford (renown once it's rich), answers every choice with the first
-- option, and ends its turn. Opponents answer attacks the same way.
local function answerAll(game)
  local Actions = Cardalyzer.require("engine.actions")
  for _ = 1, 50 do
    local any = false
    for seat, p in ipairs(game.state.players) do
      local prompt = p.prompts[1]
      if prompt then
        any = true
        local targets = Actions.targets(game, seat, prompt)
        if prompt.optional and (#targets == 0 or prompt.kind == "scrap" or prompt.kind == "react" and prompt.picked) then
          assert(game:done(seat))
        elseif #targets > 0 then
          assert(game:pick(seat, targets[1].value))
        else
          assert(game:done(seat))
        end
      end
    end
    if not any then return end
  end
  error("prompts never settled")
end

local function botTurn(game)
  local s = game.state
  local seat = s.turn.active
  local p = s.players[seat]
  answerAll(game)
  game:playAll(seat)
  answerAll(game)
  if s.turn.phase == 1 then game:nextPhase(seat) end
  game:playAll(seat)
  answerAll(game)
  for _ = 1, 4 do
    if (p.resources.buys or 0) < 1 then break end
    local best, bestCost
    local function consider(uid)
      if uid and uid ~= "" then
        local c = game:cardOf(uid)
        local wanted = c.cost <= p.resources.coin and c.id ~= "gossip" and c.id ~= "ribbon"
        if c.type == "renown" and c.id ~= "sky_lantern" and p.resources.coin >= 9 then wanted = false end
        if wanted and (not bestCost or c.cost > bestCost) then best, bestCost = uid, c.cost end
      end
    end
    for _, id in ipairs(game.fixedIds) do local pile = s.market.fixed[id]; consider(pile[#pile]) end
    for _, m in ipairs(s.markets) do for _, uid in ipairs(m.row) do consider(uid) end end
    if not best or bestCost < 2 then break end
    assert(game:buy(seat, best))
    answerAll(game)
  end
  assert(game:endTurn(seat))
end

for _, players in ipairs({ 2, 3, 4 }) do
  test("bots play a whole game to the end: " .. players .. " players", function()
    for seed = 1, 3 do
      local game = start(players, seed % 3, seed)
      local s = game.state
      local turns = 0
      while not s.winner and turns < 400 do
        botTurn(game)
        turns = turns + 1
        if turns % 25 == 0 then assertConserved(game) end
      end
      assert(s.winner, "the game ended within 400 turns (seed " .. seed .. ")")
      assertConserved(game)
      -- saved and loaded at the end
      local restored = boot(seed, game:save())
      eq(restored.state.winner, s.winner, "the result survives a reload")
    end
  end)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
