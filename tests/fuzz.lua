-- Random-play soak test: 200 seeded games (2 to 4 players) of random clicks and buys against
-- the bundled build. Checks for script errors, cards lost or duplicated
-- between piles, and spawned objects that leak.
-- Usage: python tools/bundle.py games/sample && lua tests/fuzz.lua
local tts = dofile("tests/tts_stub.lua")
for seed = 1, 200 do
  tts.reset(); math.randomseed(seed)
  dofile("build/Global.lua"); onLoad("")
  -- 2, 3 and 4 players in turn
  Cardalyzer_onUI({color="White", host=true}, "-1", "cz-players-" .. (2 + seed % 3))
  Cardalyzer_onStartGame({color="White", host=true})
  local g = Cardalyzer.game
  local Actions = Cardalyzer.require("engine.actions")
  local UI = Cardalyzer.require("engine.ui")
  for step = 1, 400 do
    if g.state.winner then break end
    local seat = g.state.turn.active
    local color = g.state.players[seat].color
    local acts = UI.actions(g).buttons
    local b = acts[math.random(#acts)]
    -- End Turn less often, so turns get played out
    if b.id == "cz-end" and math.random() < 0.7 and #acts > 1 then b = acts[math.random(#acts)] end
    Cardalyzer_onUI({color=color}, "-1", b.id)
    -- buy something affordable sometimes
    for i, uid in ipairs(g.state.market.row) do
      if uid ~= "" and math.random() < 0.3 then g:buy(seat, uid) end
    end
  end
  for _, b in ipairs(tts.broadcasts) do if b:find("%[Cardalyzer%]") then print("seed", seed, b) os.exit(1) end end
  -- conservation
  local seen, total = {}, 0
  local function visit(l) for _, u in ipairs(l) do if u ~= "" then assert(not seen[u], "dup "..u); seen[u]=true; total=total+1 end end end
  for _, p in ipairs(g.state.players) do visit(p.deck); visit(p.hand); visit(p.discard); visit(p.play); visit(p.bases) end
  local m = g.state.market; visit(m.deck); visit(m.row); visit(m.scrap); for _, pl in pairs(m.fixed) do visit(pl) end
  local n = 0; for _ in pairs(g.state.cards) do n = n + 1 end
  assert(n == total, "lost cards seed "..seed)
  -- physical objects match piles roughly: each pile drawn
  for key, guids in pairs(g.state.view.piles) do for _, gd in ipairs(guids) do assert(tts.objects[gd], "missing obj "..key) end end
  local tracked = 0; for _, guids in pairs(g.state.view.piles) do tracked = tracked + #guids end
  local live = #tts.live(function(o) return o.tags.cz_card end)
  assert(live == tracked, "leaked objects seed "..seed.." live "..live.." tracked "..tracked)
  assert(#g.state.players == 2 + seed % 3, "player count seed "..seed)
  if not g.state.winner then assert(not g.state.players[g.state.turn.active].out, "active player is out seed "..seed) end
  if seed % 50 == 0 then print("seed", seed, "players", #g.state.players, "turns", g.state.turn.number, "winner", tostring(g.state.winner)) end
end
print("fuzz ok")
