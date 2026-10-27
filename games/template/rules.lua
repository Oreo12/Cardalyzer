-- A blank game to start from. Copy this folder (games/template) to
-- games/<yours>, then change cards.csv and this file. The README's "Rules
-- file reference" lists every field; docs/PORTING.md walks through porting a
-- deck-builder you already know. Fields you don't need can be deleted: the
-- engine uses sensible defaults.
local rules = {
  name = "My Game",

  -- Seats in turn order, and how many of them can play.
  seats = {
    { color = "White" },
    { color = "Red" },
    { color = "Blue" },
    { color = "Green" },
  },
  players = { min = 2, default = 2 },

  -- Per-turn pools. Each key is an effect keyword in cards.csv ("money:2").
  -- spend = "buy" pays for cards; spend = "attack" attacks other players.
  -- start = 1 gives the pool 1 at the start of each turn (Actions, Buys).
  resources = {
    { key = "money", label = "Money", spend = "buy" },
    { key = "power", label = "Power", spend = "attack" },
  },

  -- Values that last between turns, also keywords ("life:3").
  stats = {
    { key = "life", label = "Life", start = 30 },
  },

  -- How the game is won:
  --   last player standing: { type = "stat_depleted", stat = "life", atOrBelow = 0 }
  --   most points: { type = "points", endWhen = { pileEmpty = "big_prize", fixedEmpty = 3 }, finishRound = true }
  win = { type = "stat_depleted", stat = "life", atOrBelow = 0 },

  handSize = 5,
  openingHand = 5, -- or { 3, 5 }: the first player draws 3, the rest 5

  -- The market row. For a supply game (piles always for sale, no row), set
  -- rowSize = 0, give the piles deck = supply in cards.csv and add
  --   supply = { count = 10 },
  -- (see games/lantern/rules.lua).
  market = { rowSize = 5, buyTo = "discard" },

  -- A phased turn (Action, then Buy) with Actions and Buys to spend:
  -- turn = {
  --   phases = {
  --     { key = "action", label = "Action", play = "action", buy = false },
  --     { key = "buy", label = "Buy", play = "treasure" },
  --   },
  --   playCost = { action = { key = "actions", amount = 1 } },
  --   buyCost = { key = "buys", amount = 1 },
  --   skipAhead = true,
  -- },

  -- Factions give ally effects and colour the placeholder cards.
  factions = {
    red = { label = "Red", color = "#B83A3A" },
    blue = { label = "Blue", color = "#3A62B8" },
  },

  -- Card types. persistent: stays in play between turns (needs defense in
  -- cards.csv); guard: must be destroyed before its owner can be attacked.
  cardTypes = {
    unit = {},
    base = { persistent = true },
  },
  mechanics = { allies = true, persistent = true, scrap = true },

  -- Where the card images are. make_sheets.py draws placeholders into art/;
  -- upload them and point this at the folder (see the README), or list
  -- your own sheets' URLs in art.json.
  art = {
    baseUrl = "https://raw.githubusercontent.com/Oreo12/Cardalyzer/main/games/template/",
  },

  layout = {
    surfaceY = 1.1,
    seatDistance = 10,
    cardSpacing = 2.8,
  },

  -- Lua for cards no keyword covers. A card uses one with custom:<name>.
  customEffects = {
    example = {
      text = "Draw a card for each other card you've played this turn",
      apply = function(game, seat, ctx)
        game:draw(seat, #game.state.turn.played - 1)
      end,
    },
  },
}

return rules
