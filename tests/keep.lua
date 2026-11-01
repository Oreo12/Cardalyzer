-- Headless checks for Hollow Keep, the co-op sample game, and the engine's
-- co-op features (engine/coop.lua). From the repo root:
--   python tools/bundle.py games/keep -o build/keep/Global.lua
--   lua tests/keep.lua
local BUILD = "build/keep/Global.lua"
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
local RED = { color = "Red", host = false }
local COLORS = { "White", "Red", "Blue", "Green" }
local function click(player, id) Cardalyzer_onUI(player, "-1", id) end

local function boot(seed, saved)
  tts.reset()
  math.randomseed(seed or 7)
  dofile(BUILD)
  onLoad(saved or "")
  if not Cardalyzer then error("onLoad failed: " .. table.concat(tts.broadcasts, "; ")) end
  return Cardalyzer.game
end

-- A new game: `players`, enemy number `enemy` (0 random), difficulty `diff`.
local function start(players, enemy, diff, seed)
  local game = boot(seed)
  if players and players ~= 2 then click(HOST, "cz-players-" .. players) end
  if enemy then click(HOST, "cz-enemy-" .. enemy) end
  if diff then click(HOST, "cz-difficulty-" .. diff) end
  Cardalyzer_onStartGame(HOST)
  return game
end

local function C() return Cardalyzer.require("engine.coop") end
local function newCard(game, id) return Cardalyzer.require("engine.state").newCard(game.state, id) end

-- Every card instance is in exactly one pile, the enemy's included.
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
  local e = game.state.coop.enemy
  visit(e.deck); visit(e.discard); visit(e.play)
  for _, d in pairs(e.decks) do visit(d.deck); visit(d.discard) end
  local instances = 0
  for _ in pairs(game.state.cards) do instances = instances + 1 end
  eq(total, instances, "cards in piles")
end

-- Ends every player's turn in the round, so the enemy takes its turn.
local function endRound(game)
  for _ = 1, #game.state.players do
    local seat = game.state.turn.active
    assert(game:endTurn(seat), "end turn")
    if game.state.winner or game.state.coop.turn then return end
  end
end

test("New Game deals the enemy, the Keep and the wardens' life", function()
  local game = start(2, 1, 2)
  local s, c = game.state, game.state.coop
  eq(c.enemy.key, "tide", "enemy chosen")
  eq(c.enemy.life, 50, "enemy life")
  eq(c.home, 30, "Keep")
  eq(s.players[1].stats.life, 10, "life")
  eq(c.enemy.counters.swell, 0, "Swell")
  -- 2 players: 3 + 2 + 2 basic cards, plus the Tide's own 3
  eq(#c.enemy.deck, 10, "enemy deck")
  eq(#c.enemy.decks.wave.deck, 2, "the Wave deck")
  -- tier 1 on top, tier 3 at the bottom
  local function tier(i) return game:cardOf(c.enemy.deck[i]).tier end
  eq(tier(#c.enemy.deck), 1, "top")
  eq(tier(1), 3, "bottom")
  for i = 2, #c.enemy.deck do assert(tier(i) <= tier(i - 1), "tiers stacked in order") end
  for _, uid in ipairs(c.enemy.deck) do
    local card = game:cardOf(uid)
    assert(card.enemy == nil or card.enemy == "tide", "only the Tide's own cards")
  end
  eq(#s.players[1].deck + #s.players[1].hand, 10, "starting deck")
  assert(s.view.piles["enemy.deck"], "the enemy deck is on the table")
  assert(s.view.piles["enemy.deck.wave"], "and its Wave deck")
  game:refreshUI()
  assert(tts.ui.xml:find("The Keep", 1, true) and tts.ui.xml:find("The Drowned Tide", 1, true), "the info panel shows both")
  assertConserved(game)
end)

test("the setup menu offers the enemy and the difficulty", function()
  local game = boot()
  click(HOST, "cz-setup")
  assert(tts.ui.xml:find("cz-enemy-2", 1, true) and tts.ui.xml:find("cz-difficulty-3", 1, true), "the rows")
  click(RED, "cz-difficulty-3")
  eq(game:setupChoice("difficulty"), nil, "only the host")
  click(HOST, "cz-difficulty-3")
  click(HOST, "cz-enemy-2")
  Cardalyzer_onStartGame(HOST)
  eq(game.state.coop.enemy.key, "wyrm", "the Wyrm")
  eq(game.state.coop.enemy.life, 55, "Hard: 10 more life")
  eq(game.state.coop.harder, true, "harder rules")
end)

test("damage goes to the enemy, or a minion the player picks", function()
  local game = start(2, 1)
  local c, p = game.state.coop, game.state.players[1]
  local Cards = Cardalyzer.require("engine.cards")
  game.effects:apply(game, 1, Cards.parseEffects("damage:3"), {})
  eq(c.enemy.life, 47, "straight to the enemy")
  local reed = newCard(game, "grasping_reed")
  C().enter(game, reed)
  eq(c.enemy.hp[reed], 5, "the minion's life")
  game.effects:apply(game, 1, Cards.parseEffects("damage:3"), {})
  eq(p.prompts[1].kind, "target", "asks where")
  eq(#Cardalyzer.require("engine.actions").targets(game, 1, p.prompts[1]), 2, "enemy or minion")
  assert(game:pick(1, reed))
  eq(c.enemy.hp[reed], 2, "the minion took it")
  game.effects:apply(game, 1, Cards.parseEffects("damage:3"), {})
  assert(game:pick(1, reed))
  eq(c.enemy.hp[reed], nil, "defeated")
  eq(c.enemy.discard[#c.enemy.discard], reed, "to the enemy discard pile")
  assertConserved(game)
end)

test("Might is spent on the enemy or a minion with the Attack buttons", function()
  local game = start(2, 1)
  local c, p = game.state.coop, game.state.players[1]
  local reed = newCard(game, "grasping_reed")
  C().enter(game, reed)
  p.resources.might = 7
  game:refreshUI()
  assert(tts.ui.xml:find("cz-strike-enemy", 1, true) and tts.ui.xml:find("cz-strike-" .. reed, 1, true), "both buttons")
  click(HOST, "cz-strike-" .. reed)
  eq(c.enemy.hp[reed], nil, "the minion is gone")
  eq(p.resources.might, 2, "only its life was spent")
  click(HOST, "cz-strike-enemy")
  eq(c.enemy.life, 48, "the rest on the enemy")
  eq(p.resources.might, 0, "spent")
  eq(#game:opponentsOf(1), 0, "other players aren't opponents")
end)

test("the enemy takes a turn after each round, and nobody can act meanwhile", function()
  local game = start(2, 1)
  local c = game.state.coop
  tts.deferTimers = true
  local top = c.enemy.deck[#c.enemy.deck]
  assert(game:endTurn(1))
  eq(c.turn, nil, "not after the first player")
  assert(game:endTurn(2))
  assert(c.turn, "the enemy's turn begins")
  game:refreshUI()
  assert(tts.ui.xml:find("The Drowned Tide's turn", 1, true), "the turn line says so")
  assert(not tts.ui.xml:find('id="cz_actions"', 1, true), "no action bar")
  local ok, why = game:endTurn(1)
  eq(ok, false, "players wait")
  assert(why:find("taking its turn", 1, true), why)
  tts.runTimers()
  tts.deferTimers = false
  eq(c.turn, nil, "over")
  eq(game.state.turn.active, 1, "White's turn again")
  assert(game.state.turn.played, "and it has started")
  assert(not Cardalyzer.require("engine.util").indexOf(c.enemy.deck, top), "the enemy played its top card")
  assertConserved(game)
end)

test("an attack resolves; a minion acts each turn; a power counts down, or is paid off", function()
  local game = start(2, 1)
  local c, s = game.state.coop, game.state
  local function put(id) local uid = newCard(game, id); c.enemy.deck[#c.enemy.deck + 1] = uid; return uid end
  put("undertow")
  endRound(game)
  eq(c.home, 27, "Undertow hit the Keep")
  local warden = put("gloom_warden")
  endRound(game)
  eq(c.enemy.hp[warden], 8, "the minion is in play")
  local home = c.home
  put("undertow")
  endRound(game)
  eq(c.home, home - 2 - 3, "the minion acted, then the attack")
  local murk = put("rising_murk")
  endRound(game)
  eq(c.enemy.power[murk], 2, "a power with 2")
  put("undertow")
  endRound(game)
  eq(c.enemy.power[murk], 1, "1 to go")
  -- paid off: 6 Ember on the active player's turn
  game:refreshUI()
  local p = s.players[s.turn.active]
  p.resources.ember = 6
  local obj = getObjectFromGUID(s.view.piles["enemy.play"][#s.view.piles["enemy.play"]])
  eq(obj.getGMNotes(), murk, "its card")
  local labels = {}
  for _, b in ipairs(obj.buttons) do labels[#labels + 1] = b.label end
  assert(table.concat(labels, "|"):find("Power 1", 1, true), "shows its power")
  assert(table.concat(labels, "|"):find("Discard · 6", 1, true), "and its cost")
  Cardalyzer_onEnemyCard(obj, s.players[s.turn.active].color)
  eq(c.enemy.power[murk], nil, "discarded")
  eq(p.resources.ember, 0, "paid")
  assertConserved(game)
end)

test("a power that runs out goes off", function()
  local game = start(2, 1)
  local c = game.state.coop
  local siege = newCard(game, "siege_tide")
  C().enter(game, siege)
  c.enemy.deck[#c.enemy.deck + 1] = newCard(game, "undertow")
  c.enemy.deck[#c.enemy.deck + 1] = newCard(game, "undertow")
  endRound(game) -- 2 -> 1, then Undertow
  eq(c.home, 27, "only Undertow")
  endRound(game) -- 1 -> 0: 7 damage, then Undertow
  eq(c.home, 17, "Siege Tide went off")
  eq(c.enemy.power[siege], nil, "and is discarded")
end)

test("any player suffers damage: everyone votes, and the vote decides", function()
  local game = start(3, 1)
  local s, c = game.state, game.state.coop
  c.enemy.deck[#c.enemy.deck + 1] = newCard(game, "rising_murk")
  local murk = c.enemy.deck[#c.enemy.deck]
  c.enemy.power[murk] = nil
  -- a power with 1 left goes off at the start of the enemy's turn: any player suffers 4
  table.remove(c.enemy.deck)
  C().enter(game, murk)
  c.enemy.power[murk] = 1
  endRound(game)
  assert(c.turn, "the enemy waits")
  local Actions = Cardalyzer.require("engine.actions")
  local owner, prompt = Actions.openVote(game)
  assert(prompt and prompt.vote, "a vote is open")
  eq(owner, s.turn.active, "it belongs to the player whose turn is next")
  game:refreshUI()
  for _, color in ipairs({ "White", "Red", "Blue" }) do
    assert(tts.ui.xml:find('id="cz_vote_' .. color .. '"', 1, true), color .. " sees the vote")
  end
  assert(tts.ui.xml:find("Who suffers 4 damage?", 1, true), "the question")
  click(HOST, "cz-vote-2")
  click(RED, "cz-vote-3")
  game:refreshUI()
  assert(tts.ui.xml:find("Waiting for: Blue", 1, true), "who's left")
  click(RED, "cz-closevote")
  assert(Actions.openVote(game), "only the host can close it")
  click({ color = "Blue" }, "cz-vote-3")
  eq(Actions.openVote(game), nil, "closed once everyone voted")
  eq(s.players[3].stats.life, 6, "Blue: 2 votes")
  eq(s.players[2].stats.life, 10, "Red untouched")
  eq(c.turn, nil, "the enemy carried on and finished")
end)

test("a tied vote goes to the player whose turn it is; the host can close it early", function()
  local game = start(2, 1)
  local s = game.state
  local Actions = Cardalyzer.require("engine.actions")
  local Cards = Cardalyzer.require("engine.cards")
  game.effects:apply(game, 1, Cards.parseEffects("damage_any:3"), {})
  click(HOST, "cz-vote-1")
  click(RED, "cz-vote-2")
  eq(Actions.openVote(game), nil, "closed")
  eq(s.players[1].stats.life, 7, "White's own vote broke the tie")
  game.effects:apply(game, 1, Cards.parseEffects("damage_any:3"), {})
  click(RED, "cz-vote-2")
  click(HOST, "cz-closevote")
  eq(s.players[2].stats.life, 7, "closed with Red's vote")
end)

test("one player: no vote, a normal choice", function()
  local game = start(1, 1)
  local Cards = Cardalyzer.require("engine.cards")
  game.effects:apply(game, 1, Cards.parseEffects("damage_any:3"), {})
  eq(game.state.players[1].stats.life, 7, "it just happens")
  game.effects:apply(game, 1, Cards.parseEffects("damage_lowest:1"), {})
  eq(game.state.players[1].stats.life, 6)
end)

test("a warden at 0 life is exhausted: the enemy unleashes twice, and their damage hits the Keep", function()
  local game = start(2, 1)
  local s, c = game.state, game.state.coop
  local red = s.players[2]
  C().damagePlayer(game, 2, 12)
  eq(red.down, true, "exhausted")
  eq(red.stats.life, 0, "at 0")
  eq(c.enemy.counters.swell, 2, "unleashed twice")
  C().damagePlayer(game, 2, 3)
  eq(c.home, 24, "3 damage hit the Keep twice over")
  local Cards = Cardalyzer.require("engine.cards")
  game.effects:apply(game, 2, Cards.parseEffects("life:2"), {})
  eq(red.stats.life, 0, "no life gained")
  game:refreshUI()
  assert(tts.ui.xml:find("Red, exhausted", 1, true), "shown")
  -- and nobody goes past their starting life
  game.effects:apply(game, 1, Cards.parseEffects("life:5"), {})
  eq(s.players[1].stats.life, 10, "capped")
  -- the lowest-life player skips the exhausted
  game.effects:apply(game, 1, Cards.parseEffects("damage_lowest:1"), {})
  eq(s.players[1].stats.life, 9, "White, not Red")
  C().damagePlayer(game, 1, 20)
  eq(c.result, "lost", "everyone exhausted")
end)

test("the players win when the enemy falls, and lose when the Keep does", function()
  local game = start(2, 1)
  local c, s = game.state.coop, game.state
  C().damageEnemy(game, 1, "enemy", 60)
  eq(c.result, "won", "won")
  eq(#s.winners, 2, "everyone shares it")
  game:refreshUI()
  assert(tts.ui.xml:find("You win! The Drowned Tide is defeated.", 1, true), "the result")
  game = start(2, 1)
  C().damageHome(game, 30)
  eq(game.state.coop.result, "lost", "lost")
  game:refreshUI()
  assert(tts.ui.xml:find("You lose: The Keep has fallen.", 1, true), "the result")
  -- an enemy with no cards left loses once its turn is over
  game = start(2, 1)
  game.state.coop.enemy.deck = {}
  endRound(game)
  eq(game.state.coop.result, "won", "deck run out")
end)

test("the Tide: Swell builds, then a Wave crashes from its own deck", function()
  local game = start(2, 1)
  local c = game.state.coop
  c.enemy.counters.swell = 3
  c.enemy.deck[#c.enemy.deck + 1] = newCard(game, "undertow")
  local home = c.home
  endRound(game)
  eq(c.enemy.counters.swell, 0, "3 Swell spent")
  assert(c.home < home - 3 or game.state.players[1].stats.life < 10, "a Wave hit too")
  eq(#c.enemy.decks.wave.deck, 2, "the Wave is shuffled back")
  assertConserved(game)
end)

test("the Wyrm: Scales soften hits, and its unleash is put to a vote", function()
  local game = start(2, 2)
  local c, s = game.state.coop, game.state
  C().damageEnemy(game, 1, "enemy", 5)
  eq(c.enemy.life, 41, "1 less")
  eq(c.enemy.counters.scales, 2, "a Scale lost")
  local whelp = newCard(game, "cinder_whelp")
  C().enter(game, whelp)
  C().damageEnemy(game, 1, whelp, 4)
  eq(c.enemy.hp[whelp], 4, "the whelp takes 1 less too")
  C().unleash(game, 1)
  local Actions = Cardalyzer.require("engine.actions")
  local _, prompt = Actions.openVote(game)
  eq(prompt.kind, "choice", "the players choose")
  click(HOST, "cz-vote-1")
  click(RED, "cz-vote-1")
  eq(c.home, 27, "the Keep took 3")
end)

test("step by step: the enemy waits for Continue after each step", function()
  local game = start(2, 1)
  local c = game.state.coop
  click(RED, "cz-enemystep-on")
  eq(game.state.view.enemyStep, nil, "host only")
  click(HOST, "cz-enemystep-on")
  eq(game.state.view.enemyStep, true, "on")
  endRound(game)
  assert(c.turn and c.turn.paused, "paused after the first step")
  game:refreshUI()
  assert(tts.ui.xml:find("cz-continue", 1, true), "a Continue button")
  local steps = #c.turn.queue
  click(RED, "cz-continue")
  eq(#c.turn.queue, steps - 1, "one more step")
  for _ = 1, 10 do if c.turn then click(RED, "cz-continue") end end
  eq(c.turn, nil, "done")
  eq(game.state.turn.active, 1, "White's turn")
end)

test("a game saved during the enemy's turn carries on after loading", function()
  local game = start(2, 1)
  click(HOST, "cz-enemystep-on")
  endRound(game)
  assert(game.state.coop.turn, "mid-turn")
  local saved = game:save()
  game = boot(7, saved)
  assert(game.state.coop.turn and game.state.coop.turn.paused, "still mid-turn")
  click(HOST, "cz-enemystep-off")
  eq(game.state.coop.turn, nil, "and it finishes")
  eq(game.state.turn.active, 1)
  assertConserved(game)
end)

-- Plays whole games with simple bots: each plays everything, attacks with its
-- Might, pays off powers it can, buys what it can afford, and answers every
-- choice and vote at random. Every card is checked to be in one pile each step.
local function botGame(players, enemy, seed)
  local game = start(players, enemy, nil, seed)
  local s = game.state
  local Actions = Cardalyzer.require("engine.actions")
  local function answer()
    for _ = 1, 50 do
      local owner, prompt = Actions.openVote(game)
      if prompt then
        local options = Actions.voteTally(game)
        for seat in ipairs(s.players) do
          if Actions.openVote(game) then game:castVote(seat, options[math.random(#options)].value) end
        end
      else
        local any = false
        for seat, p in ipairs(s.players) do
          local pr = p.prompts[1]
          if pr then
            any = true
            local targets = Actions.targets(game, seat, pr)
            if #targets > 0 and (not pr.optional or math.random() < 0.7) then
              game:pick(seat, targets[math.random(#targets)].value)
            else
              game:done(seat)
            end
          end
        end
        if not any then return end
      end
    end
  end
  for _ = 1, 400 do
    if s.winner then break end
    answer()
    if s.winner then break end
    local seat = s.turn.active
    local p = s.players[seat]
    game:playAll(seat)
    answer()
    if (p.resources.might or 0) > 0 then
      local minions = C().minions(game)
      game:attackEnemy(seat, #minions > 0 and minions[1] or "enemy")
      answer()
    end
    for _, uid in ipairs(s.coop and s.coop.enemy.play or {}) do
      if s.coop.enemy.power[uid] and game:cardOf(uid).cost <= (p.resources.ember or 0) then game:payPower(seat, uid) end
    end
    for _ = 1, 3 do
      local best = nil
      for _, id in ipairs(game.fixedIds) do
        local pile = s.market.fixed[id]
        if #pile > 0 and game:cardOf(pile[#pile]).cost <= (p.resources.ember or 0) then best = pile[#pile] end
      end
      if best then game:buy(seat, best) end
    end
    answer()
    if not s.winner then
      local ok, why = game:endTurn(seat)
      if not ok then error("end turn refused: " .. tostring(why)) end
    end
    answer()
    assertConserved(game)
  end
  assert(s.winner, "the game ended")
  return game
end

test("whole bot games against both enemies, 1 to 4 players", function()
  local results = {}
  for players = 1, 4 do
    for enemy = 1, 2 do
      local game = botGame(players, enemy, players * 10 + enemy)
      results[#results + 1] = players .. "p " .. game.state.coop.enemy.key .. ": " .. game.state.coop.result
        .. " (turn " .. game.state.turn.number .. ")"
    end
  end
  print("     " .. table.concat(results, "; "))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
