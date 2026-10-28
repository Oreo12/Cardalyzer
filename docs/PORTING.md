# Porting a deck-builder to Cardalyzer

This guide takes a deck-builder you already know and turns it into a
Cardalyzer game you can play in Tabletop Simulator (TTS). You'll write two
files: a card spreadsheet and a rules file. Most cards need no code at all.

The repo has three games to copy from:

- `games/template`: a blank game with every common field explained. Start here.
- `games/sample` (Ember Guilds): a **trade-row** game, with a row of cards for
  sale that keeps changing, attacks on players and their buildings, and the
  last player standing wins.
- `games/lantern` (Lantern Fair): a **supply** game, with piles that are
  always for sale, Action and Buy phases, attacks and reactions, and the most
  points win.

## Before you start

**Check that the game fits.** Cardalyzer runs games where you play cards from
your hand, they give you resources or effects, you spend those, then you clean
up and draw. Read [Limits and compatibility](Limits.md)
first. If most of the game's cards would need code, it isn't a good fit yet.

**Check that you may share it.** A port of a published game is for your own
table unless you have the rights to its cards, names and art. Only publish a
port on the Steam Workshop if you have them.

**Have these ready:**

- A list of every card: name, cost, how many copies, and what it does. A
  spreadsheet is easiest.
- Card images, if you have them, as TTS card sheets (a grid of card faces in
  one image), hosted somewhere TTS can download from, such as Steam Cloud.
  Without them, Cardalyzer draws plain placeholder cards for you.
- The rulebook, for the turn structure and how the game ends.

## 1. Copy the template

```sh
cp -r games/template games/mygame
```

On Windows, copy the folder in Explorer. Then check that it builds as it is:

```sh
python tools/csv2json.py games/mygame/cards.csv
python tools/make_sheets.py games/mygame --title "My Game"
python tools/bundle.py games/mygame -o build/mygame/Global.lua
```

## 2. Map the game onto Cardalyzer

Go through the rulebook and write down what each part of the game is in
Cardalyzer's terms. This table covers most deck-builders:

| In the game | In Cardalyzer |
| --- | --- |
| Money, trade, gold (spent each turn) | a `resources` entry with `spend = "buy"` |
| Combat, power, damage (spent each turn) | a `resources` entry with `spend = "attack"` |
| Actions and Buys you start each turn with | `resources` entries with `start = 1`, spent by `turn.playCost` and `turn.buyCost` |
| Health, authority, life (lasts all game) | a `stats` entry; `win = { type = "stat_depleted", stat = … }` |
| Victory points on cards | the `points` column; `win = { type = "points", … }` |
| Your starting deck | cards with `deck = starter`, or the `starting` column for a card that is also in a pile |
| A changing row of cards for sale | `market.rowSize`; cards with `deck = market` |
| Piles that are always for sale (basic money, points) | cards with `deck = fixed` |
| A set of piles chosen for each game | cards with `deck = supply`; `rules.supply` |
| A second row of special cards | `rules.markets`; cards with `deck = market:<key>` |
| Play this phase, then that phase | `rules.turn.phases` |
| "Trash", "banish", "exile", remove from the game | scrap (`scrap_from_hand:1` and friends) |
| Cards that stay in play (bases, locations) | a card type with `persistent = true` and the `defense` column |
| Faction or colour bonuses | the `faction` and `ally_effects` columns |
| "Each other player…" | an attack: `opponents_gain`, `opponents_discard_to`, or a custom `eachOpponent` |
| "When another player attacks, you may reveal this…" | the `react_effects` column |
| The game ends when piles run out | `win.endWhen = { pileEmpty = "id", fixedEmpty = 3 }` |

Use the game's own words: a resource's `label` is what players see, and
`rules.ui.words` renames anything else the engine shows (End Turn, the market
row, the Buy button).

## 3. Write the card spreadsheet

`cards.csv` has one row per **different** card; `copies` says how many there
are. The [Card spreadsheet reference](Cards.md)
lists every column. Some tips:

- **Ids** are lowercase with `_`: `royal_guard`. Keywords that name a card,
  like `gain:royal_guard`, use them.
- **Effects** are `keyword:amount`, separated by `;`: `draw:2; coin:1`. A
  choice is `coin:2 | draw:2`. The keywords are your resource and stat keys
  plus the built-in ones in
  [Writing effects](Cards.md#writing-effects).
- **Write what you can't automate in `text`.** A card whose effect has no
  keyword can use `reminder`: the card's text is shown to the player, who
  resolves it by hand. That lets you play the whole game first and automate
  the odd card later.
- **Unusual cards** name a custom effect, `custom:myCard`, which you write in
  Lua in step 5. Give the card a `text` so its tooltip makes sense.
- **A big game?** Write a small script that turns your own card list into
  `cards.csv`, rather than typing hundreds of rows. `csv2json.py` checks the
  result and lists every problem it finds.

Save the file as CSV (in Excel, **CSV UTF-8**), then run `csv2json.py`. It
refuses to write `cards.json` until every row is valid.

## 4. Write the rules

Open `rules.lua`. Set the name, the seats and player counts, the resources and
stats from step 2, the hand size and how the game is won. Then pick the
shape of the market.

**A trade-row game** (like Ember Guilds) has a row of cards for sale that
refills from a shuffled deck:

```lua
market = { rowSize = 5, buyTo = "discard" },
win = { type = "stat_depleted", stat = "life", atOrBelow = 0 },
```

**A supply game** (like Lantern Fair) has no row. Its basic piles are `fixed`
cards, and the rest are `supply` cards, from which each game uses some:

```lua
market = { rowSize = 0 },
supply = {
  count = 10,
  presets = { { label = "First game", cards = { "village_hall", "market_day" } } },
},
pileSizes = { victory = { [2] = 8, otherwise = 12 } },
layout = { seating = "around", areas = { fixed = { columns = 10 } } },
win = { type = "points", endWhen = { pileEmpty = "big_prize", fixedEmpty = 3 }, finishRound = true },
turn = {
  phases = {
    { key = "action", label = "Action", play = "action", buy = false },
    { key = "buy", label = "Buy", play = "treasure" },
  },
  playCost = { action = { key = "actions", amount = 1 } },
  buyCost = { key = "buys", amount = 1 },
  skipAhead = true,
},
```

A card type that no phase lets you play (victory cards, curses) simply can't
be played. The [Rules file reference](Rules.md)
lists every field, and [How a turn runs](Rules.md#how-a-turn-runs) covers
phases, attacks and reactions.

## 5. Write the custom effects

Each `custom:<name>` in the spreadsheet needs an entry in
`rules.customEffects`. A custom effect changes `game.state`; the table redraws
itself. To ask the player something, queue a prompt. From Lantern Fair:

```lua
-- "You may scrap a Ribbon from your hand for +3 Coin"
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
```

An attack written in Lua uses `eachOpponent`, which runs once for each
opponent the attack reaches; the engine handles their reactions:

```lua
heckle = {
  text = "Each opponent with 5 or more cards in hand discards 1",
  eachOpponent = function(game, seat, victim)
    if #game.state.players[victim].hand >= 5 then
      game:prompt(victim, { kind = "discard", count = 1, optional = false })
    end
  end,
},
```

[Custom effects](CustomEffects.md) lists the prompts and the hooks
for cards in play ("whenever you play…", "at the end of your turn…").

## 6. Card images

**Using your own sheets.** Write `art.json` yourself and don't run
`make_sheets.py`, which would overwrite it. It names each sheet's URL and size
and which slot each card id uses; see
[Using card art you already have](Customising.md#using-card-art-you-already-have).
The engine lists any card with no slot when the game loads.

**Using placeholders.** `make_sheets.py` draws a plain card for every row,
coloured by faction. Upload `art/sheet_*.jpg` and `art/back.jpg` (TTS:
**Modding → Cloud Manager**) and point `art.baseUrl` at them, or paste each
URL into `art.json`.

Only `http(s)` links work for other players; a `file:///` image shows only on
your computer.

## 7. Test it

Build and run the quick check, which deals a game and plays 30 turns with
simple automatic players, looking for errors and lost cards:

```sh
python tools/csv2json.py games/mygame/cards.csv
python tools/bundle.py games/mygame -o build/mygame/Global.lua
CZ_BUILD=build/mygame/Global.lua lua tests/smoke.lua
```

(On Windows, `set CZ_BUILD=build/mygame/Global.lua` first, then
`lua tests/smoke.lua`.) For your own checks, copy `tests/lantern.lua`, which
tests one card at a time and plays whole games.

Then play it: paste `build/mygame/Global.lua` into Global's script in TTS on
an empty table (see [Load a Build into Tabletop Simulator](GettingStarted.md#load-a-build-into-tabletop-simulator))
and press **New Game**.

## Checklist

- [ ] Every card in the spreadsheet, with the right copies (`csv2json.py` passes).
- [ ] Every resource and stat players see has the game's own name.
- [ ] The starting deck, opening hands and hand size match the rulebook.
- [ ] The market (row, piles, supply) matches the rulebook for each player count.
- [ ] The game ends when the rulebook says, and the right player wins.
- [ ] Every card that isn't automated says so in its `text` (`reminder`).
- [ ] The card images load for another player (web links only).
- [ ] The smoke test passes, and you've played a whole game in TTS.

If something your game needs can't be written with keywords, the rules file
or a custom effect, that's a gap in Cardalyzer: please open an issue.
