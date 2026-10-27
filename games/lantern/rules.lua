-- Rules for "Lantern Fair", the second sample game. Merchants at a night
-- festival buy goods and helpers from a shared supply of piles, and the most
-- renowned merchant wins. It shows the engine running a points game with
-- phases, a supply chosen each game, attacks and reactions, an extra market
-- and players sitting round the table. Everything game-specific lives here or
-- in cards.csv; the engine reads it.
local rules = {
  name = "Lantern Fair",

  seats = {
    { color = "White" },
    { color = "Red" },
    { color = "Blue" },
    { color = "Green" },
  },
  players = { min = 2, default = 2 },

  -- Coin buys cards. Each turn starts with 1 Action (to play an action card)
  -- and 1 Buy (to buy a card).
  resources = {
    { key = "coin", label = "Coin", spend = "buy" },
    { key = "actions", label = "Actions", start = 1 },
    { key = "buys", label = "Buys", start = 1 },
  },

  turn = {
    phases = {
      { key = "action", label = "Action", play = "action", buy = false },
      { key = "buy", label = "Buy", play = "goods" },
    },
    playCost = { action = { key = "actions", amount = 1 } },
    buyCost = { key = "buys", amount = 1 },
    -- playing goods or buying in the Action phase moves on to the Buy phase
    skipAhead = true,
  },

  -- Renown points on the cards you own. The game ends once the Sky Lanterns
  -- or any three piles run out, after the round is played out.
  win = {
    type = "points",
    endWhen = { pileEmpty = "sky_lantern", fixedEmpty = 3 },
    finishRound = true,
  },

  handSize = 5,
  openingHand = 5,

  -- No market row: the supply piles are always for sale, beside a small
  -- row of one-off Peddlers.
  market = { rowSize = 0, buyTo = "discard" },
  markets = { { key = "peddlers", label = "Peddlers", rowSize = 3 } },

  -- 8 of the supply cards each game, at random or from a preset.
  supply = {
    count = 8,
    presets = {
      {
        label = "First Fair",
        about = "A gentle first game: extra actions, drawing, gaining and scrapping, no attacks.",
        cards = { "rag_picker", "juggler", "tea_house", "fortune_teller", "storyteller", "lantern_maker", "silk_trader", "night_market" },
      },
      {
        label = "Rowdy Night",
        about = "Attacks and the reactions that answer them.",
        cards = { "paper_charm", "fan_dancer", "night_watch", "heckler", "pickpocket", "pawnbroker", "town_crier", "acrobat" },
      },
    },
  },
  pileSizes = {
    small_lantern = { [2] = 8, otherwise = 12 },
    festival_banner = { [2] = 8, otherwise = 12 },
    sky_lantern = { [2] = 8, otherwise = 12 },
    gossip = function(players) return 10 * (players - 1) end,
  },

  -- Factions only colour the placeholder cards here: allies are off.
  factions = {
    goods = { label = "Goods", color = "#B8901E" },
    renown = { label = "Renown", color = "#3E8E5A" },
    craft = { label = "Craft", color = "#3C6FB4" },
    charm = { label = "Charm", color = "#2C9C92" },
    trick = { label = "Trick", color = "#8E4BB0" },
    gossip = { label = "Gossip", color = "#7A6A5A" },
    peddler = { label = "Peddler", color = "#C0602B" },
  },

  cardTypes = { action = {}, goods = {}, renown = {}, gossip = {} },
  mechanics = { allies = false, persistent = false, scrap = true },

  art = {
    baseUrl = "https://raw.githubusercontent.com/Oreo12/Cardalyzer/main/games/lantern/",
  },

  layout = {
    surfaceY = 1.1,
    cardSpacing = 2.8,
    seating = "around",
    seatDistance = 18,
    areas = { fixed = { columns = 8 }, bases = false },
  },

  ui = {
    theme = {
      accent = "#FFC861",
      buttons = {
        primary = { color = "#B8322A", text = "#FFF4DC" },
        secondary = { color = "#2E2A44", text = "#F2E8D5" },
        selected = { color = "#FFC861", text = "#2A1A05" },
      },
    },
  },

  tutorialPages = {
    {
      title = "Lantern Fair",
      body = "Each turn has two phases.\n\n"
        .. "Action: play action cards. Each one spends an Action, and you start the turn with 1. "
        .. "Cards that give +Actions let you keep going.\n\n"
        .. "Buy: play your goods for Coin, then buy cards from the piles or the Peddlers row. "
        .. "You start with 1 Buy. Bought cards go to your discard pile.\n\n"
        .. "Renown cards (Small Lantern, Festival Banner, Sky Lantern) do nothing in your hand but score at the end. "
        .. "Gossip costs you a point.",
    },
    {
      title = "Attacks and reactions",
      body = "Pickpocket, Heckler, Town Crier and Firecracker hit every other player.\n\n"
        .. "If you hold a reaction (Paper Charm, Night Watch) when someone attacks, you're asked on your own screen "
        .. "whether to reveal it. Paper Charm blocks the attack; Night Watch draws you a card first.\n\n"
        .. "The game ends once the Sky Lanterns or any three piles run out. The round is played out, then the most "
        .. "renown wins.",
    },
  },

  customEffects = {
    -- Pawnbroker: trade a Ribbon for 3 Coin.
    pawn = {
      text = "You may scrap a Ribbon from your hand for +3 Coin",
      apply = function(game, seat)
        local ribbons = {}
        for _, uid in ipairs(game.state.players[seat].hand) do
          if game:cardOf(uid).id == "ribbon" then ribbons[#ribbons + 1] = uid end
        end
        if #ribbons > 0 then
          game:prompt(seat, { kind = "scrap", from = { "hand" }, only = ribbons, optional = true, custom = "pawn" })
        end
      end,
      afterPick = function(game, seat)
        local pools = game.state.players[seat].resources
        pools.coin = pools.coin + 3
      end,
    },
    -- Heckler: an attack written in Lua. eachOpponent runs once per
    -- opponent the attack reaches (reactions are handled by the engine).
    heckle = {
      text = "Each opponent with 5 or more cards in hand discards 1",
      eachOpponent = function(game, seat, victim)
        if #game.state.players[victim].hand >= 5 then
          game:prompt(victim, { kind = "discard", count = 1, optional = false })
        end
      end,
    },
  },
}

return rules
