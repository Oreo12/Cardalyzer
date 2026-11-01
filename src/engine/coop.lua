-- Co-operative games (rules.coop): the players win or lose together against
-- an automated enemy with its own life, deck and turns, while defending a
-- home with its own life. Pure state changes, like actions.lua; game.lua
-- paces the enemy's turn and redraws after each step.
--
-- rules.coop = {
--   life = "life",                  the players' stat that is their life
--   home = { label = "Keep", life = 30 },
--   enemyTurns = "round",           "round": after the last seat's turn; "each": after every turn
--   pause = 1.2,                    seconds between the enemy's steps
--   exhaustedDamage = 2,            damage to an exhausted player hits the home this many times over
--   onExhausted = function(game, seat) end,  instead of the default (the enemy unleashes twice)
--   tiers = { [players] = { tier1, tier2, tier3 }, otherwise = {...} },
--                                   basic enemy cards per tier (left out: all of them)
--   decks = { { key = "strike", label = "Strike" } },  the enemies' extra decks
--   difficulties = { { label, about, homeLife, enemyLife, playerLife, harder } },
--   difficulty = 2,                 the one picked by default
--   check = function(game) return "win"|"lose", reason end,
--   enemies = { { key, name, life, text, counters, maxLife, deckOutWins,
--                 setup, unleash, atTurnStart, atTurnEnd, whenDamaged,
--                 check, onExhausted, onDeckEmpty } },
-- }
--
-- Enemy cards are rows with deck = enemy (its deck) or enemy:<key> (an extra
-- deck), a tier (1-3), and an enemy column naming the enemy they belong to
-- (blank: a basic card any enemy uses). Their kind is their type (attack,
-- minion or power; a card type's `enemy` field can say instead):
--   attack  resolves its effects when drawn, then is discarded
--   minion  stays in play with `life`; its effects run each enemy turn
--   power   stays in play with `power` tokens; loses one each enemy turn and
--           at 0 runs its effects and is discarded. With a cost, a player
--           may pay that much (the buy resource) on their turn to discard it.
-- now_effects run when any of them is drawn.
local Util = require("engine.util")
local Words = require("engine.words")

local Coop = {}

local function say(game, key, vars) return Words.say(game.rules, key, vars) end
local function notify(game, msg) if game.notify then game:notify(msg) end end

function Coop.on(rules) return rules.coop ~= nil end

-- The players' life stat.
function Coop.lifeKey(rules)
  return rules.coop and (rules.coop.life or (rules.win and rules.win.stat)) or nil
end

function Coop.homeLabel(rules)
  return rules.coop and rules.coop.home and rules.coop.home.label or say({ rules = rules }, "home")
end

-- The enemy playing this game: its rules.coop.enemies entry (nil before setup).
function Coop.enemyDef(game)
  local c = game.state.coop
  if not c then return nil end
  for _, def in ipairs(game.rules.coop.enemies or {}) do
    if def.key == c.enemy.key then return def end
  end
  return nil
end

function Coop.enemyName(game)
  local c = game.state.coop
  return c and c.enemy.name or say(game, "theEnemy")
end

-- What an enemy card is: "attack", "minion" or "power".
function Coop.kind(game, c)
  local def = require("engine.cards").typeDef(game.rules, c)
  if def.enemy then return def.enemy end
  for _, t in ipairs(require("engine.cards").typesOf(c)) do
    if t == "attack" or t == "minion" or t == "power" then return t end
  end
  return "attack"
end

-- A difficulty from rules.coop.difficulties (choice: its number).
function Coop.difficulty(rules, choice)
  local list = rules.coop and rules.coop.difficulties or {}
  return list[choice or rules.coop.difficulty or 1] or {}, (#list > 0 and (choice or rules.coop.difficulty or 1) or nil)
end

-- How many basic cards of each tier go in the enemy deck for `players`.
local function tierCounts(rules, players)
  local t = rules.coop.tiers
  if not t then return nil end
  if type(t) == "function" then return t(players) end
  return t[players] or t.otherwise
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- Deals the enemy, the home and the players' life for a new game. `enemyChoice`
-- 0 or nil is a random enemy, i is rules.coop.enemies[i]; `diffChoice` picks a
-- difficulty; `sets` limits the cards like Turn.setup.
function Coop.setup(game, enemyChoice, diffChoice, sets, random)
  local rules, state = game.rules, game.state
  local State = require("engine.state")
  random = random or math.random
  local enemies = rules.coop.enemies or {}
  if #enemies == 0 then error("rules.coop.enemies lists no enemies", 0) end
  local def = enemies[enemyChoice or 0]
  if not def then def = enemies[random(#enemies)] end
  local diff, diffIndex = Coop.difficulty(rules, diffChoice)

  local homeLife = ((rules.coop.home and rules.coop.home.life) or 30) + (diff.homeLife or 0)
  local enemyLife = (def.life or 50) + (diff.enemyLife or 0)
  local c = {
    home = homeLife, homeMax = homeLife,
    difficulty = diffIndex, harder = diff.harder == true,
    enemy = {
      key = def.key, name = def.name or def.key, life = enemyLife, maxLife = enemyLife,
      deck = {}, discard = {}, play = {},
      hp = {}, power = {}, silenced = {}, counters = {}, decks = {},
    },
    turns = 0,
  }
  state.coop = c
  for _, counter in ipairs(def.counters or {}) do c.enemy.counters[counter.key] = counter.start or 0 end

  local lifeKey = Coop.lifeKey(rules)
  for _, p in ipairs(state.players) do
    if lifeKey then
      p.stats[lifeKey] = (p.stats[lifeKey] or 0) + (diff.playerLife or 0)
      p.maxLife = p.stats[lifeKey]
    end
    p.down = false
  end

  local function ok(card)
    if card.enemy and card.enemy ~= def.key then return false end
    return not sets or not card.set or sets[card.set]
  end
  -- The enemy deck: each tier shuffled on its own and stacked, tier 1 on top.
  local basic, own, maxTier = {}, {}, 1
  for _, card in ipairs(game.cards:inDeck("enemy")) do
    if ok(card) then
      local tier = card.tier or 1
      maxTier = math.max(maxTier, tier)
      local into = card.enemy and own or basic
      into[tier] = into[tier] or {}
      for _ = 1, card.copies do into[tier][#into[tier] + 1] = card.id end
    end
  end
  local counts = tierCounts(rules, #state.players)
  for tier = maxTier, 1, -1 do
    local pool = basic[tier] or {}
    Util.shuffle(pool, random)
    local list = {}
    local take = counts and counts[tier] or #pool
    for i = 1, math.min(take, #pool) do list[#list + 1] = pool[i] end
    for _, id in ipairs(own[tier] or {}) do list[#list + 1] = id end
    Util.shuffle(list, random)
    for _, id in ipairs(list) do c.enemy.deck[#c.enemy.deck + 1] = State.newCard(state, id) end
  end
  -- Extra decks (rules.coop.decks): cards with deck = enemy:<key>.
  for _, d in ipairs(rules.coop.decks or {}) do
    local pile = { deck = {}, discard = {} }
    for _, card in ipairs(game.cards:inDeck("enemy:" .. d.key)) do
      if ok(card) then
        for _ = 1, card.copies do pile.deck[#pile.deck + 1] = State.newCard(state, card.id) end
      end
    end
    Util.shuffle(pile.deck, random)
    c.enemy.decks[d.key] = pile
  end
  if def.setup then def.setup(game) end
end

---------------------------------------------------------------------------
-- Life and damage
---------------------------------------------------------------------------

-- How much of a life gain a player gets: none while exhausted, and never past
-- the life they started with.
function Coop.lifeGain(game, seat, amount)
  local p = game.state.players[seat]
  if amount <= 0 or not game.state.coop then return amount end
  if p.down then return 0 end
  local key = Coop.lifeKey(game.rules)
  if p.maxLife then amount = math.max(0, math.min(amount, p.maxLife - (p.stats[key] or 0))) end
  return amount
end

function Coop.damageHome(game, n, why)
  local c = game.state.coop
  if not c or n <= 0 or c.result then return end
  c.home = c.home - n
  notify(game, say(game, "homeHit", { home = Coop.homeLabel(game.rules), n = n, left = math.max(0, c.home) }))
  Coop.check(game)
end

function Coop.healHome(game, n)
  local c = game.state.coop
  if not c or n <= 0 then return end
  c.home = math.min(c.homeMax, c.home + n)
end

-- A player suffers n damage. An exhausted player's damage hits the home
-- instead, rules.coop.exhaustedDamage (default 2) times over.
function Coop.damagePlayer(game, seat, n)
  local c = game.state.coop
  local p = game.state.players[seat]
  if not c or not p or n <= 0 or c.result then return end
  if p.down then
    return Coop.damageHome(game, n * (game.rules.coop.exhaustedDamage or 2))
  end
  local key = Coop.lifeKey(game.rules)
  p.stats[key] = (p.stats[key] or 0) - n
  notify(game, say(game, "playerHit", { name = p.name, n = n, left = math.max(0, p.stats[key]) }))
  if p.stats[key] <= 0 then
    p.stats[key] = 0
    Coop.exhaust(game, seat)
  end
  Coop.check(game)
end

-- A player at 0 life is exhausted: they play on, but can't gain life and
-- their damage hits the home. The enemy's onExhausted, or the rules', runs;
-- by default the enemy unleashes twice.
function Coop.exhaust(game, seat)
  local p = game.state.players[seat]
  if p.down then return end
  p.down = true
  notify(game, say(game, "exhaustedNow", { name = p.name }))
  local def = Coop.enemyDef(game)
  if def and def.onExhausted then return def.onExhausted(game, seat) end
  if game.rules.coop.onExhausted then return game.rules.coop.onExhausted(game, seat) end
  Coop.unleash(game, 2)
end

-- The enemy's signature move, n times (its unleash hook).
function Coop.unleash(game, n)
  local def = Coop.enemyDef(game)
  for _ = 1, n or 1 do
    if game.state.coop.result then return end
    notify(game, say(game, "unleashes", { enemy = Coop.enemyName(game) }))
    if def and def.unleash then def.unleash(game, {}) end
  end
end

-- The enemy's minions in play.
function Coop.minions(game)
  local out = {}
  local c = game.state.coop
  if not c then return out end
  for _, uid in ipairs(c.enemy.play) do
    if Coop.kind(game, game:cardOf(uid)) == "minion" then out[#out + 1] = uid end
  end
  return out
end

-- Runs a hook on a minion's own custom effects (whenDamaged and the like).
local function minionHook(game, uid, hook, ...)
  local card = game:cardOf(uid)
  for _, effect in ipairs(card.effects) do
    local def = effect.key == "custom" and game.effects.custom[effect.fn]
    if def and def[hook] then return def[hook](game, { uid = uid, card = card }, ...) end
  end
  return nil
end

-- Deals n damage to the enemy ("enemy") or one of its minions (a uid) from
-- `seat`. The enemy's whenDamaged(game, amount, target) or a minion card's
-- whenDamaged(game, ctx, amount) may change the amount. Returns what was dealt.
function Coop.damageEnemy(game, seat, target, n)
  local c = game.state.coop
  if not c or n <= 0 or c.result then return 0 end
  local who = seat and game.state.players[seat] and game.state.players[seat].name or ""
  if target == "enemy" or target == nil then
    local def = Coop.enemyDef(game)
    if def and def.whenDamaged then n = def.whenDamaged(game, n, "enemy") or n end
    n = math.max(0, n)
    c.enemy.life = c.enemy.life - n
    notify(game, say(game, "enemyHit", { name = who, enemy = c.enemy.name, n = n, left = math.max(0, c.enemy.life) }))
  else
    if not Util.indexOf(c.enemy.play, target) or c.enemy.hp[target] == nil then return 0 end
    local changed = minionHook(game, target, "whenDamaged", n)
    if changed then n = changed end
    n = math.max(0, n)
    c.enemy.hp[target] = c.enemy.hp[target] - n
    local card = game:cardOf(target)
    if c.enemy.hp[target] <= 0 then
      Coop.discard(game, target)
      notify(game, say(game, "minionDefeated", { name = who, card = card.name }))
    else
      notify(game, say(game, "minionHit", { name = who, card = card.name, n = n, left = c.enemy.hp[target] }))
    end
  end
  Coop.check(game)
  return n
end

-- An enemy card leaves play for the enemy discard pile.
function Coop.discard(game, uid)
  local e = game.state.coop.enemy
  Util.removeValue(e.play, uid)
  e.hp[uid], e.power[uid], e.silenced[uid] = nil, nil, nil
  e.discard[#e.discard + 1] = uid
end

-- Puts an enemy card into play or resolves it (drawn from its deck, or from
-- an extra deck by a game's own code): its now_effects run, then an attack's
-- effects; a minion or power stays.
function Coop.enter(game, uid)
  local c = game.state.coop
  local card = game:cardOf(uid)
  local kind = Coop.kind(game, card)
  local seat = game.state.turn.active
  local ctx = { uid = uid, card = card, enemy = true }
  notify(game, say(game, "enemyPlays", { enemy = c.enemy.name, card = card.name,
    effects = card.text ~= "" and card.text or game.effects:describe(card.effects) }))
  if kind == "minion" then
    c.enemy.play[#c.enemy.play + 1] = uid
    c.enemy.hp[uid] = card.life or 1
  elseif kind == "power" then
    c.enemy.play[#c.enemy.play + 1] = uid
    c.enemy.power[uid] = card.power or 1
  end
  game.effects:apply(game, seat, card.nowEffects or {}, ctx)
  if kind == "attack" then
    game.effects:apply(game, seat, card.effects, ctx)
    c.enemy.discard[#c.enemy.discard + 1] = uid
  end
end

-- Draws the top card of an extra deck (rules.coop.decks) and resolves it like
-- an attack; it goes to that deck's discard pile. With `reshuffle` it's
-- shuffled back into its deck instead (a Strike).
function Coop.drawExtra(game, key, reshuffle)
  local c = game.state.coop
  local pile = c.enemy.decks[key]
  if not pile then error("no enemy deck '" .. tostring(key) .. "' in rules.coop.decks", 0) end
  if #pile.deck == 0 then
    Util.moveAll(pile.discard, pile.deck)
    Util.shuffle(pile.deck, game.random)
  end
  local uid = table.remove(pile.deck)
  if not uid then return nil end
  local card = game:cardOf(uid)
  notify(game, say(game, "enemyPlays", { enemy = c.enemy.name, card = card.name,
    effects = card.text ~= "" and card.text or game.effects:describe(card.effects) }))
  game.effects:apply(game, game.state.turn.active, card.effects, { uid = uid, card = card, enemy = true })
  if reshuffle then
    pile.deck[#pile.deck + 1] = uid
    Util.shuffle(pile.deck, game.random)
  else
    pile.discard[#pile.discard + 1] = uid
  end
  return uid
end

-- The enemy's counters (its rules' `counters`): add n (negative to take
-- away), kept between the counter's min and max.
function Coop.addCounter(game, key, n)
  local e = game.state.coop.enemy
  local def = Coop.enemyDef(game)
  local spec = {}
  for _, s in ipairs(def and def.counters or {}) do if s.key == key then spec = s end end
  local v = (e.counters[key] or 0) + n
  if spec.min then v = math.max(spec.min, v) end
  if spec.max then v = math.min(spec.max, v) end
  e.counters[key] = v
  return v
end

---------------------------------------------------------------------------
-- The result
---------------------------------------------------------------------------

-- Has the game been won or lost? Sets state.coop.result ("won" or "lost")
-- and its reason, and ends the game for everyone (state.winner, and on a win
-- state.winners = every seat).
function Coop.finish(game, result, reason)
  local s = game.state
  if not s.coop or s.coop.result then return end
  s.coop.result, s.coop.reason = result, reason
  s.coop.turn = nil
  s.winner = 1
  if result == "won" then
    local all = {}
    for seat in ipairs(s.players) do all[#all + 1] = seat end
    s.winners = #all > 1 and all or nil
  end
end

function Coop.check(game)
  local s = game.state
  local c = s.coop
  if not c or c.result then return end
  local def = Coop.enemyDef(game) or {}
  for _, check in pairs({ enemy = def.check or false, rules = game.rules.coop.check or false }) do
    if check then
      local result, reason = check(game)
      if result == "win" or result == "won" then return Coop.finish(game, "won", reason) end
      if result == "lose" or result == "lost" then return Coop.finish(game, "lost", reason) end
    end
  end
  if c.home <= 0 then return Coop.finish(game, "lost", say(game, "homeFell", { home = Coop.homeLabel(game.rules) })) end
  local up = 0
  for _, p in ipairs(s.players) do if not p.down then up = up + 1 end end
  if up == 0 then return Coop.finish(game, "lost", say(game, "allExhausted")) end
  if c.enemy.life <= 0 then return Coop.finish(game, "won", say(game, "enemyDefeated", { enemy = c.enemy.name })) end
  if def.deckOutWins ~= false and #c.enemy.deck == 0 and #c.enemy.play == 0 and not c.turn then
    return Coop.finish(game, "won", say(game, "enemyExhausted", { enemy = c.enemy.name }))
  end
end

---------------------------------------------------------------------------
-- The enemy's turn: a queue of steps kept in state.coop.turn (so a save in
-- the middle of it carries on), run one at a time by game.lua with a pause
-- between them. A step that asks the players something (a vote) waits for
-- the answer before the next.
---------------------------------------------------------------------------

-- Is the enemy's turn due after a player's turn? (roundOver: play is back
-- to the first seat.)
function Coop.due(game, roundOver)
  local c = game.state.coop
  if not c or c.result then return false end
  local when = game.rules.coop.enemyTurns or "round"
  return when == "each" or roundOver
end

function Coop.beginTurn(game)
  local c = game.state.coop
  local queue = { { step = "start" } }
  for _, uid in ipairs(c.enemy.play) do
    local kind = Coop.kind(game, game:cardOf(uid))
    if kind == "minion" then queue[#queue + 1] = { step = "persist", uid = uid } end
    if kind == "power" then queue[#queue + 1] = { step = "power", uid = uid } end
  end
  queue[#queue + 1] = { step = "draw" }
  queue[#queue + 1] = { step = "end" }
  c.turn = { queue = queue }
  c.turns = (c.turns or 0) + 1
  notify(game, say(game, "enemyTurn", { enemy = c.enemy.name }))
end

-- A question the players must answer before the enemy goes on.
function Coop.waiting(game)
  for _, p in ipairs(game.state.players) do
    for _, prompt in ipairs(p.prompts) do
      if prompt.enemy then return true end
    end
  end
  return false
end

-- Runs the next step. Returns "more" (steps left), "wait" (the players are
-- answering something) or "done" (the enemy's turn is over and the next
-- player's has started, or the game is over).
function Coop.step(game)
  local c = game.state.coop
  if not c or not c.turn then return "done" end
  if c.result then c.turn = nil; return "done" end
  if Coop.waiting(game) then return "wait" end
  local job = table.remove(c.turn.queue, 1)
  if job then
    local def = Coop.enemyDef(game) or {}
    local e = c.enemy
    local seat = game.state.turn.active
    if job.step == "start" then
      if def.atTurnStart then def.atTurnStart(game) end
    elseif job.step == "persist" and Util.indexOf(e.play, job.uid) then
      local card = game:cardOf(job.uid)
      if e.silenced[job.uid] then
        e.silenced[job.uid] = nil
        notify(game, say(game, "silencedSkip", { card = card.name }))
      else
        notify(game, say(game, "minionActs", { card = card.name, effects = game.effects:describe(card.effects, card.text) }))
        game.effects:apply(game, seat, card.effects, { uid = job.uid, card = card, enemy = true })
      end
    elseif job.step == "power" and Util.indexOf(e.play, job.uid) then
      local card = game:cardOf(job.uid)
      e.power[job.uid] = (e.power[job.uid] or 1) - 1
      if e.power[job.uid] <= 0 then
        Coop.discard(game, job.uid)
        notify(game, say(game, "powerFires", { card = card.name, effects = game.effects:describe(card.effects, card.text) }))
        game.effects:apply(game, seat, card.effects, { uid = job.uid, card = card, enemy = true })
      else
        notify(game, say(game, "powerTicks", { card = card.name, n = e.power[job.uid] }))
      end
    elseif job.step == "draw" then
      local uid = table.remove(e.deck)
      if uid then
        Coop.enter(game, uid)
      elseif def.onDeckEmpty then
        def.onDeckEmpty(game)
      end
    elseif job.step == "end" then
      if def.atTurnEnd then def.atTurnEnd(game) end
    end
  end
  for seat = 1, #game.state.players do require("engine.actions").settle(game, seat) end
  Coop.check(game)
  if c.result then c.turn = nil; return "done" end
  if Coop.waiting(game) then return "wait" end
  if #c.turn.queue > 0 then return "more" end
  c.turn = nil
  Coop.check(game) -- (an empty enemy deck wins once its turn is over)
  if c.result then return "done" end
  require("engine.actions").startTurn(game, game.state.turn.active)
  return "done"
end

-- Runs the whole enemy turn at once (tests, bots), answering nothing: stops
-- at a question and returns "wait".
function Coop.runTurn(game)
  for _ = 1, 200 do
    local status = Coop.step(game)
    if status ~= "more" then return status end
  end
  return "done"
end

---------------------------------------------------------------------------
-- What players do to the enemy on their turn
---------------------------------------------------------------------------

-- What each enemy card in play shows on the table: { [uid] = { text, cost } }:
-- a minion's life, a power's tokens, and a power's discard cost.
function Coop.labels(game)
  local out = {}
  local c = game.state.coop
  if not c then return out end
  for _, uid in ipairs(c.enemy.play) do
    local card = game:cardOf(uid)
    if c.enemy.hp[uid] then
      out[uid] = { text = say(game, "minionLife", { n = c.enemy.hp[uid] }) .. (c.enemy.silenced[uid] and say(game, "silencedMark") or "") }
    elseif c.enemy.power[uid] then
      out[uid] = { text = say(game, "powerLeft", { n = c.enemy.power[uid] }), cost = card.cost > 0 and card.cost or nil }
    end
  end
  return out
end

return Coop
