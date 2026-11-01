-- Rules for "Hollow Keep", the co-operative sample game. One to four
-- wardens defend the Keep against an enemy that takes its own turns: they
-- win together when it falls (or runs out of cards), and lose together when
-- the Keep falls or every warden is exhausted. It shows the engine's co-op
-- features (rules.coop): the home, the enemy's deck in tiers, minions and
-- powers, its signature move, its counters and extra deck, damage to the
-- enemy, and votes. Everything here is original; see docs/Rules.md, "Co-op games".
local rules = {
  name = "Hollow Keep",

  seats = {
    { color = "White" },
    { color = "Red" },
    { color = "Blue" },
    { color = "Green" },
  },
  players = { min = 1, default = 2 },

  -- Ember buys cards from the piles; Might is spent on the enemy or its
  -- minions with the Attack buttons. Spells deal damage themselves.
  resources = {
    { key = "ember", label = "Ember", spend = "buy" },
    { key = "might", label = "Might", spend = "attack" },
  },
  stats = {
    { key = "life", label = "Life", start = 10, icon = "heart" },
  },

  handSize = 5,
  openingHand = 5,
  market = { rowSize = 0, buyTo = "discard" },

  coop = {
    life = "life",
    home = { label = "The Keep", life = 30 },
    enemyTurns = "round", -- the enemy takes a turn after every round
    pause = 1.0,
    -- basic enemy cards in each tier, by number of players
    tiers = { [1] = { 2, 2, 2 }, [2] = { 3, 2, 2 }, [3] = { 4, 3, 3 }, otherwise = { 5, 4, 3 } },
    decks = { { key = "wave", label = "Wave" } },
    difficulties = {
      { label = "Gentle", about = "The Keep has 10 more life and the enemy 10 less.", homeLife = 10, enemyLife = -10 },
      { label = "Normal", about = "The game as written." },
      { label = "Hard", about = "The enemy has 10 more life, and its harder rules apply.", enemyLife = 10, harder = true },
    },
    difficulty = 2,
    enemies = {
      {
        key = "tide",
        name = "The Drowned Tide",
        life = 50,
        text = "Unleash: the Tide gains 1 Swell. At the end of its turn, with 3 or more Swell, a Wave crashes "
          .. "(the top card of the Wave deck, shuffled back) and it loses 3 Swell (Hard: 2).",
        counters = { { key = "swell", label = "Swell", start = 0, max = 6 } },
        unleash = function(game) game:addEnemyCounter("swell", 1) end,
        atTurnEnd = function(game)
          if game:enemyCounter("swell") >= 3 then
            game:drawEnemyCard("wave", true)
            game:addEnemyCounter("swell", game.state.coop.harder and -2 or -3)
          end
        end,
      },
      {
        key = "wyrm",
        name = "The Ash Wyrm",
        life = 45,
        text = "Unleash: the Keep suffers 3 damage, or any player suffers 2 (the players vote). "
          .. "While it has Scales, each hit on it is 1 less and costs it a Scale.",
        counters = { { key = "scales", label = "Scales", start = 3, min = 0 } },
        unleash = function(game)
          game:prompt(game.state.turn.active, { kind = "choice", vote = true, optional = false,
            text = "The Ash Wyrm unleashes: choose one",
            options = { { key = "home_damage", amount = 3 }, { key = "damage_any", amount = 2 } } })
        end,
        whenDamaged = function(game, amount)
          if game:enemyCounter("scales") > 0 then
            game:addEnemyCounter("scales", -1)
            return math.max(0, amount - 1)
          end
          return amount
        end,
      },
    },
  },

  factions = {
    ember = { label = "Ember", color = "#D8742A" },
    steel = { label = "Steel", color = "#6E7C8C" },
    arcane = { label = "Arcane", color = "#5A4FC0" },
    hearth = { label = "Hearth", color = "#3E8E5A" },
    dark = { label = "Dark", color = "#3A2E40" },
    tide = { label = "Tide", color = "#24607A" },
    ash = { label = "Ash", color = "#8A3A2A" },
  },

  cardTypes = { gem = {}, blade = {}, spell = {}, attack = {}, minion = {}, power = {} },
  mechanics = { allies = false, persistent = false, scrap = false },

  art = {
    baseUrl = "https://raw.githubusercontent.com/Oreo12/Cardalyzer/main/games/keep/",
  },

  layout = {
    surfaceY = 1.1,
    cardSpacing = 2.8,
    areas = { fixed = { columns = 6 }, bases = false },
  },

  ui = {
    theme = {
      accent = "#9FD3E8",
      buttons = {
        primary = { color = "#2A5C7A", text = "#EAF6FF" },
        secondary = { color = "#22262E", text = "#DDE6EE" },
        selected = { color = "#9FD3E8", text = "#0E1A22" },
      },
    },
  },

  tutorialPages = {
    {
      title = "Hollow Keep",
      body = "You play together against the enemy beside the market. You all win when its life reaches 0, or when it has "
        .. "no cards left to play. You all lose when the Keep falls or every warden is exhausted.\n\n"
        .. "On your turn play your cards: Ember buys cards from the piles, spells deal damage (to the enemy, or a minion "
        .. "you pick), and Might is spent with the Attack buttons.\n\n"
        .. "After every round the enemy takes a turn: its minions and powers act, then it plays the top card of its deck.",
    },
    {
      title = "Minions, powers and votes",
      body = "Minions stay until their life is gone, and act every enemy turn. Powers count down and go off at 0; pay the "
        .. "cost on the Discard button on your turn to throw one away.\n\n"
        .. "When the enemy hurts \"any player\", everyone votes on who. The most votes wins; a tie goes to the player whose "
        .. "turn is next. A warden at 0 life is exhausted: they play on, but their damage hits the Keep twice over.",
    },
  },

  customEffects = {
    -- Cinder Whelp: damage dealt to it is 1 less.
    scaled = {
      text = "",
      whenDamaged = function(_, _, amount) return math.max(0, amount - 1) end,
    },
  },
}

return rules
