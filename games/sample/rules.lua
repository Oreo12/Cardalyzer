-- Rules for "Ember Guilds", the sample game that ships with the engine.
-- Everything game-specific lives here or in cards.csv; the engine reads it.
local rules = {
  name = "Ember Guilds",

  seats = {
    { color = "White", name = "White" },
    { color = "Red", name = "Red" },
  },

  -- Per-turn pools. Each key becomes an effect keyword ("gold:2").
  resources = {
    { key = "gold", label = "Gold", spend = "buy" },
    { key = "might", label = "Might", spend = "attack" },
  },

  -- Values that persist across turns. Each key is also a keyword ("health:3").
  stats = {
    { key = "health", label = "Health", start = 40 },
  },

  -- A player whose stat drops to `atOrBelow` loses (used from milestone 4).
  win = { type = "stat_depleted", stat = "health", atOrBelow = 0 },

  handSize = 5,
  openingHand = { 3, 5 }, -- first player draws 3, second draws 5
  firstSeat = 1,

  market = {
    rowSize = 5,
    buyTo = "discard", -- or "deck_top"
  },

  factions = {
    forge = { label = "Forge", color = "#C8502D" },
    grove = { label = "Grove", color = "#4E9A3E" },
    tide = { label = "Tide", color = "#2F6FB0" },
    veil = { label = "Veil", color = "#7A4BA6" },
  },

  -- Card types; persistent ones stay in play between turns and have defense.
  cardTypes = {
    unit = { persistent = false },
    building = { persistent = true },
    wall = { persistent = true, guard = true }, -- must be destroyed before anything else
  },

  mechanics = {
    allies = true,
    persistent = true,
    scrap = true,
  },

  -- Where card images are hosted. tools/make_sheets.py writes the sheets to
  -- games/sample/art/; upload them (or push them to GitHub) and point this at them.
  art = {
    baseUrl = "",
  },

  layout = {
    surfaceY = 1.1,
    seatDistance = 10,
    cardSpacing = 2.8,
  },

  -- Effects too unusual for a keyword. Cards use them as custom:<name>.
  customEffects = {
    freeRecruit = {
      text = "Take a card costing 4 or less from the market row for free",
      apply = function(game, seat, ctx)
        game:prompt(seat, { kind = "free_buy", maxCost = 4, optional = true })
      end,
    },
  },
}

return rules
