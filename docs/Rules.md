# Rules: Setting Up Your Game

`rules.lua` says how your game works. It's one Lua table of settings, and
anything you leave out uses a sensible default. The blank game in
`games/template/rules.lua` has the common settings filled in with comments;
copy it and change what you need.

The look of the screen and the table (colours, mats, seating, where areas
sit) is covered separately, in [Customising](Customising.md).

## Table of Contents
1. [The Basics](#the-basics)
2. [Resources and Stats](#resources-and-stats)
3. [Factions, Card Types and Mechanics](#factions-card-types-and-mechanics)
4. [The Market](#the-market)
5. [Piles and the Supply](#piles-and-the-supply)
6. [How a Turn Runs](#how-a-turn-runs)
7. [Attacks and Reactions](#attacks-and-reactions)
8. [Winning](#winning)
9. [Card Sets, Kits, Dealt Cards and Objectives](#card-sets-kits-dealt-cards-and-objectives)
10. [Set-Aside Areas](#set-aside-areas)
11. [Art, Rulebooks, Tutorial and Animation](#art-rulebooks-tutorial-and-animation)

## The Basics

```lua
name = "Ember Guilds",
seats = { { color = "White" }, { color = "Red" }, { color = "Blue" }, { color = "Green" } },
players = { min = 2, default = 2 },
handSize = 5,
openingHand = { 3, 5 },
```

| Setting | What it does |
| --- | --- |
| `name` | The title shown on the info panel |
| `seats` | The player colours, in turn order. Each can have a `name`. A game for fewer players uses the first ones |
| `players` | How many can play: the host picks from `min` up to the number of seats; `default` is picked to start with. Leave it out to always use every seat |
| `handSize` | Cards drawn at the end of each turn |
| `openingHand` | Each player's first hand, in turn order: `{3, 5}` means the first player draws 3 and the rest 5 (the last number repeats). One number gives everyone the same. To depend on the player count: `{ players = { [2] = {3, 5} }, otherwise = {3, 4, 5} }` |
| `openingHands` | Several opening-hand rules for the host to choose from in the New Game menu, for example `{ {label="Rulebook", hands={3, 5}}, {label="Everyone 5", hands=5} }`. The first is the default. Each can have an `about` explaining it (shown as a tooltip and in the tutorial). `openingLabel` renames the menu row (default "Starting hands") |
| `firstSeat` | Which seat goes first (default 1) |
| `reshuffle` | Leave it out to shuffle the discard pile into a new deck when a deck runs out. `false` turns the discard pile over in order instead, so the first card discarded is the first drawn |

[Back to Top](#rules-setting-up-your-game)

## Resources and Stats
**Resources** are spent during a turn and reset at the end of it, like Gold
or Might. **Stats** last from turn to turn, like Health or Honor. Each one's
`key` becomes an effect keyword: `gold:2`, `health:-3`.

```lua
resources = {
  { key = "gold", label = "Gold", spend = "buy" },       -- pays for cards
  { key = "might", label = "Might", spend = "attack" },  -- powers the Attack button
  { key = "actions", label = "Actions", start = 1 },     -- each turn starts with 1
},
stats = { { key = "health", label = "Health", start = 40 } },
```

| Field | What it does |
| --- | --- |
| `key` | The keyword for cards |
| `label` | The name players see |
| `spend` | Resources only: `"buy"` pays for cards, `"attack"` powers attacks |
| `start` | The value it starts at (resources: at the start of every turn). Default 0 |
| `icon` | The symbol it's shown with (see [Symbols](Customising.md#symbols)) |

[Back to Top](#rules-setting-up-your-game)

## Factions, Card Types and Mechanics

```lua
factions = {
  forge = { label = "Forge", color = "#C8502D" },
  grove = { label = "Grove", color = "#3E8E41" },
},
cardTypes = {
  unit = { persistent = false },
  building = { persistent = true },
  wall = { persistent = true, guard = true },
},
mechanics = { allies = true, persistent = true, scrap = true },
```

**`factions`** gives each faction a name and a frame colour (used by
`make_sheets.py`).

**`cardTypes`** lists the types a card's `type` column can use, and what each
type does. A type can have any of these:

| Flag | What it does |
| --- | --- |
| `persistent = true` | Its cards stay in play from turn to turn (buildings), and apply their effects again each turn |
| `replay = false` | With `persistent`: the card doesn't apply its effects again each turn |
| `guard = true` | Its cards must be destroyed before their owner, or their owner's other buildings, can be attacked |
| `target = false` | Its cards can't be attacked or destroyed (a hero that stays until you scrap it) |
| `event = true` | When dealt into the market row, it happens at once for the current player, then goes to the scrap pile and the slot is refilled |
| `defeat = true` | A monster or villain. In the market it has a **Defeat** button instead of **Buy**: defeating it costs its `cost` in the attack resource, gives its `effects` as the reward, and sends it to the scrap pile. It can't be bought or taken free |
| `hire = true` | In a market row it also has a **Hire** button: hiring pays its cost and puts it straight into play for its effects, and at the end of the turn it goes to the bottom of the market deck instead of to the player |
| `faceDown = true` | Its cards are dealt face down (see [Dealt cards](#dealt-cards)): only their owner sees them, and they do nothing until the owner presses **Reveal** on their turn. Then they go into play and their effects apply |
| `buyTo = "play"` | When bought (or taken free), its cards go straight into play instead of the discard pile, and their effects apply at once (a hero that joins you) |
| `scrapAt = 0.9` | Puts the **Scrap** button on its cards, this far down (see `ui.scrapButton` in [Customising](Customising.md)) |
| `playYaw = 90` | Its cards turn 90 degrees (or `270`) once they're in a player's play area, for cards printed sideways. They're upright in the market |

**`mechanics`** turns whole mechanics on or off: `allies` (faction bonuses),
`persistent` (cards that stay in play) and `scrap`.

[Back to Top](#rules-setting-up-your-game)

## The Market
The market is the row of face-up cards for sale, refilled from the market
deck.

```lua
market = { rowSize = 5, buyTo = "discard" },
```

| Setting | What it does |
| --- | --- |
| `market.rowSize` | How many cards are face up for sale. `0` for a game with no market row (and no market deck) |
| `market.buyTo` | Where bought cards go: `"discard"` or `"deck_top"` |
| `market.returnScrapped` | `true`: a scrapped card that came from a fixed pile goes back to its pile instead of the scrap pile |
| `market.faceActive` | Leave it out to turn the market's cards to face the current player. `false` keeps them facing seat 1 |
| `market.turnsWithPlayer` | `true`: the whole market (row, piles and outlines) turns to face the current player, with its cards gliding round. Best with `layout.seating = "around"` |

**Extra markets.** `markets` adds more rows, each with its own deck. A card
joins one with `deck` set to `market:<key>` in the spreadsheet:

```lua
markets = { { key = "heroes", label = "Heroes", rowSize = 3 } },
```

The extra rows stack beside the main one, and the seats move back to make
room. They share the main market's scrap pile. Place one with
`layout.areas.heroes = { along, out }` (see
[Customising the table](Customising.md#areas)).

[Back to Top](#rules-setting-up-your-game)

## Piles and the Supply
**Fixed piles** (`deck` = `fixed`) are always for sale beside the market.
**The supply** is a pool of piles (`deck` = `supply`); each game, some of them
are laid out.

```lua
supply = {
  count = 8,
  label = "Supply",
  presets = {
    { label = "First game", cards = { "juggler", "tea_house" }, about = "A gentle start" },
  },
  default = 1,
},
pileSizes = {
  gossip = function(players) return 10 * (players - 1) end,
  banner = { [2] = 8, otherwise = 12 },
},
```

| Setting | What it does |
| --- | --- |
| `supply.count` | How many supply piles each game uses |
| `supply.presets` | Named sets of piles the host can pick in the New Game menu, besides Random. `about` is a preset's tooltip |
| `supply.default` | Which preset is picked until the host chooses (leave it out for Random) |
| `pileSizes` | How many cards a pile starts with, by card id: a number, a table by player count, or a function of the player count. Other piles use the card's `copies` |
| `layout.areas.fixed` | `{ columns = 8 }` lays the piles out in rows of up to 8, with the supply starting its own row. With no market row, they're centred |

Supply piles are laid out cheapest first.

[Back to Top](#rules-setting-up-your-game)

## How a Turn Runs
By default a turn is: play cards, buy, attack, then **End Turn** discards
everything in play and in hand and draws a new hand. `turn` changes that.

```lua
resources = {
  { key = "coins", label = "Coins", spend = "buy" },
  { key = "actions", label = "Actions", start = 1 },
  { key = "buys", label = "Buys", start = 1 },
},
turn = {
  phases = {
    { key = "action", label = "Action", play = "action", buy = false, attack = false },
    { key = "buy", label = "Buy", play = "treasure" },
  },
  playCost = { action = { key = "actions", amount = 1 } }, -- playing an action card spends an Action
  buyCost = { key = "buys", amount = 1 },                  -- each card bought spends a Buy
  keepHand = false,       -- true: unplayed cards stay in your hand
  drawUpTo = false,       -- true: draw up to the hand size instead of a new hand
  keepResources = false,  -- true, or a list of keys: those resources carry over
  skipAhead = false,      -- true: playing or buying something a later phase allows moves on to it
  onStart = function(game, seat) end,
  onEnd = function(game, seat) end,
},
```

- **Phases** run in order. A **Next** button moves on, and **End Turn** works
  in any phase. A phase's `play` says which card types it allows: one type, a
  list, `true` for any, or `false` for none. `buy = false` and
  `attack = false` turn those off. The phase shows on the info panel, and
  **Play all** only plays what the phase and your resources allow.
- **Costs**: `playCost` makes playing a type of card spend a resource, and
  `buyCost` does the same for every card bought (free cards from effects don't
  spend it).
- **Skipping ahead**: with `skipAhead`, playing a treasure or pressing Buy in
  the Action phase moves straight on to the Buy phase, so players don't have
  to press Next first. There's no going back to an earlier phase.
- **Hooks**: `onStart` and `onEnd` run Lua at the start and end of each turn.
- Players can't act on someone else's turn, except to answer a choice an
  effect puts to them, or to reveal a reaction.

[Back to Top](#rules-setting-up-your-game)

## Attacks and Reactions
An **attack** is an effect that hits each opponent: `opponents_gain:gossip`,
`opponents_discard_to:3`, `opponents_damage:3`, or a custom effect with
`eachOpponent` (see [Custom effects](CustomEffects.md)). It reaches the other
players one at a time, starting on the attacker's left. Using the **Attack**
button on a player is an attack too.

A card with `react_effects` is a **reaction**. When an attack reaches a
player holding one:

1. The attack waits, and that player is asked on their own screen whether to
   reveal it.
2. Its react effects happen at once (so `draw:1` draws before the attack
   lands), and they may reveal another reaction.
3. Then the attack lands, unless a reaction had `block`. `prevent:N` lowers
   the damage of an Attack-button attack. The card stays in their hand.

The attacker carries on playing meanwhile. A reaction still unanswered when
the attacker ends their turn counts as not revealed, so nobody can hold up
the game. Choices the attack gives the defender, such as which cards to
discard, are answered straight away.

[Back to Top](#rules-setting-up-your-game)

## Winning
**Last player standing.** Attacks lower a stat; a player who drops to the
limit is out (no more turns, can't be attacked), and the last player left
wins.

```lua
win = { type = "stat_depleted", stat = "health", atOrBelow = 0 },
```

**Most points.** The highest score wins when the game ends. A score is the
`points` on every card a player owns, plus their `stat` if one is given.

```lua
win = {
  type = "points",
  stat = "honor",
  endWhen = { pool = { key = "honor", amount = 60 }, marketEmpty = true },
  finishRound = true,
},
```

The game ends when any `endWhen` condition is met:

| Condition | Ends the game when… |
| --- | --- |
| `marketEmpty = true` | the market row and deck run out |
| `fixedEmpty = 3` | 3 fixed piles are empty |
| `pileEmpty = "id"` | that pile (or any pile in a list) runs out |
| `pool = { key, amount }` | a shared pool of that stat runs out (players take from it as they gain it; it's shown on the right) |
| `rounds = 10` | 10 rounds have been played |
| `custom = function(game)` | your function returns true |

With `finishRound = true`, the round is played out so everyone has the same
number of turns. Equal top scores share the win. Scores show on the right.

**Your own check.** Either kind can add `check = function(game)`, returning
the winning seat, a list of seats (a shared win), or nil to play on.

[Back to Top](#rules-setting-up-your-game)

## Card Sets, Kits, Dealt Cards and Objectives

### Card sets
Group cards into sets (the `set` column) that the host switches on or off in
the New Game menu. Cards with no `set` are always in.

```lua
sets = {
  { key = "base", label = "Base Game", always = true },
  { key = "exp1", label = "Expansion", default = true, about = "Adds 20 new cards" },
},
```

`always` sets can't be switched off; `default` ones start on; `about` is the
set's tooltip.

### Dealt cards
`deal = { count = 2 }` deals each player 2 of the `dealt` cards at random,
straight into play, at the start of the game. If their type has
`faceDown = true` they're dealt face down instead: other players see only
their backs, and their owner has a **Reveal** button for each, usable on
their turn. A card's effects apply when it's revealed (custom effects see
`ctx.revealed = true`), and each turn after if its type is `persistent`.

### Objectives
`objectives = { count = 3, perTurn = 1, toWin = 3, label = "Missions" }`
deals each player 3 secret `objective` cards. Each turn they can complete 1,
and completing 3 wins the game. They lie face up in each player's
`objectives` area (see Customising, Areas), hidden from everyone else, who
see their backs. A completed one is shown to all.

### Starting kits
Kits are premade starting setups: a deck, cards in play, stats and hand
size. When the host turns kits on in the New Game menu, every player picks
their own from a kit menu: a premade kit, a random one, or a custom mix.
Anyone who doesn't pick gets a random one.

```lua
kits = {
  { key = "red", set = "red_kit", label = "Red", handSize = 6, stats = { health = 60 }, requires = { "exp1" } },
},
kitParts = {
  { key = "leader", label = "Leader", deck = "dealt", type = "leader", by = "kit", stats = true },
  { key = "tricks", label = "Tricks", deck = "dealt", type = "trick", count = 2 },
},
kitRequires = { "exp1" },
```

- **A kit's `set`** holds its cards: its `starter` cards make the player's
  deck, its `dealt` cards start in play, and its `market` cards join the
  market deck. A kit's set is never dealt otherwise.
- **`stats` and `handSize`** replace the player's own.
- **`requires`** lists card sets switched on when the kit is picked;
  **`kitRequires`** lists sets switched on when the host turns kits on.
- **`kitParts`** says what a custom kit is mixed from. Each part takes cards
  of one `deck` (and `type`) from the kits' sets: `by = "kit"` picks which kit
  supplies that part (`stats = true` also brings that kit's stats and hand
  size), and `count = n` picks n single cards from all the kits. Leave it out
  for no custom option.
- **`kitLabel`** renames the menu row (default "Starting decks"), and
  **`kitName`** the kit option in it (default "Kit"). The **Your kit** button
  on the right reopens the kit menu.

[Back to Top](#rules-setting-up-your-game)

## Set-Aside Areas
Areas are piles of each player's own, beside their discard pile, for cards
out of their deck but still theirs (they count for points).

```lua
areas = {
  { key = "exile", label = "Exile" },
  { key = "later", label = "Set aside", at = "nextTurn" },
  { key = "tavern", label = "Tavern", at = "call", returns = "play" },
},
```

| Field | What it does |
| --- | --- |
| `at` | What brings cards back: `"nextTurn"` (the start of the owner's next turn), `"call"` (a **Call** button on the owner's turn), or nothing (they stay) |
| `returns` | Where they go back to: `"hand"` (default), `"play"` (their effects apply) or `"discard"` |
| `shown = false` | Keeps the area off the table |

Cards go in with the `set_aside` and `set_aside_hand` keywords.
`layout.areas.<key> = { along, out }` moves an area.

[Back to Top](#rules-setting-up-your-game)

## Art, Rulebooks, Tutorial and Animation

| Setting | What it does |
| --- | --- |
| `art.baseUrl` | The web folder your card images are in (see [Host the card images](GettingStarted.md#host-the-card-images)) |
| `rulebooks` | PDFs the **Rulebooks** button lays out beside the table: `{ {name="Rules", url="https://…/rules.pdf"} }`. Only `http(s)` links |
| `layout.rulebooks` | Where they go: `{ x=40, z=0, spacing=9.5, scale=2, yaw=180, locked=false }`, all optional. By default they stand in a line just past the furthest play area |
| `tutorial` | `false` removes the Tutorial button for everyone |
| `tutorialPages` | Pages added after the tutorial's own, `{ {title="Our rules", body="…"} }`, or a `function(game, pages)` that returns the pages to show |
| `animate` | `false` makes cards jump to their places instead of flying there. **Tidy table** is always instant |
| `animation` | `{ stagger=0.12, linger=0.4, lift=1.2 }`: seconds between cards dealt one after another, seconds a landed card lingers, and how high cards fly |
| `customEffects` | Lua for unusual cards (see [Custom effects](CustomEffects.md)) |

Everything about the screen and the table (`ui`, `layout`, `outlines`) is in
[Customising](Customising.md).

[Back to Top](#rules-setting-up-your-game)
