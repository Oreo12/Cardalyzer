-- A quick check that any game folder builds and plays: deals a game and
-- plays 30 turns (play everything, buy the dearest affordable card, answer
-- every choice), checking that no card is lost. From the repo root:
--   python tools/bundle.py games/template -o build/template/Global.lua
--   CZ_BUILD=build/template/Global.lua lua tests/smoke.lua
local BUILD = os.getenv("CZ_BUILD") or "build/Global.lua"
local tts = dofile("tests/tts_stub.lua")

tts.reset()
math.randomseed(3)
dofile(BUILD)
onLoad("")
if not Cardalyzer then error("onLoad failed: " .. table.concat(tts.broadcasts, "; ")) end
local game = Cardalyzer.game
local Actions = Cardalyzer.require("engine.actions")
Cardalyzer_onStartGame({ color = game.rules.seats[1].color, host = true })
local s = game.state
assert(s.started, "the game was dealt")

local function answerAll()
  for _ = 1, 50 do
    local any = false
    for seat, p in ipairs(s.players) do
      if p.prompts[1] then
        any = true
        local targets = Actions.targets(game, seat, p.prompts[1])
        if #targets > 0 and not (p.prompts[1].optional and p.prompts[1].picked) then
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

local function count()
  local seen, total = {}, 0
  local function visit(list)
    for _, uid in ipairs(list) do
      if uid ~= "" then
        assert(not seen[uid], "card " .. uid .. " is in two piles")
        seen[uid], total = true, total + 1
      end
    end
  end
  for _, p in ipairs(s.players) do visit(p.deck); visit(p.hand); visit(p.discard); visit(p.play); visit(p.bases) end
  visit(s.market.deck); visit(s.market.row); visit(s.market.scrap)
  for _, pile in pairs(s.market.fixed) do visit(pile) end
  for _, m in ipairs(s.markets or {}) do visit(m.deck); visit(m.row) end
  local instances = 0
  for _ in pairs(s.cards) do instances = instances + 1 end
  assert(total == instances, "cards lost: " .. total .. " in piles, " .. instances .. " made")
end

local buyKey = Actions.resourceFor(game.rules, "buy")
for _ = 1, 30 do
  if s.winner then break end
  local seat = s.turn.active
  local p = s.players[seat]
  answerAll()
  local phases = game.rules.turn and game.rules.turn.phases or {}
  for _ = 1, math.max(1, #phases) do
    game:playAll(seat)
    answerAll()
    if (s.turn.phase or 1) < #phases then game:nextPhase(seat) end
  end
  for _ = 1, 3 do
    local best, bestCost
    local function consider(uid)
      if uid and uid ~= "" then
        local c = game:cardOf(uid)
        if c.cost > 0 and c.cost <= (p.resources[buyKey] or 0) and (not bestCost or c.cost > bestCost) then best, bestCost = uid, c.cost end
      end
    end
    for _, m in ipairs(Cardalyzer.require("engine.state").rows(s)) do for _, uid in ipairs(m.row) do consider(uid) end end
    for _, id in ipairs(game.fixedIds) do local pile = s.market.fixed[id]; consider(pile[#pile]) end
    if not best or not game:buy(seat, best) then break end
    answerAll()
  end
  for _, other in ipairs(game:opponentsOf(seat)) do game:attack(seat, other) end
  answerAll()
  if not s.winner then assert(game:endTurn(seat)) end
  count()
end
print("smoke ok: " .. game.rules.name .. ", " .. s.turn.number .. " turns")
