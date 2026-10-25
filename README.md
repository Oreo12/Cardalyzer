# Cardalyzer

Cardalyzer reads your card data and turns each card's effects into gameplay
in Tabletop Simulator (TTS). You list your cards in a spreadsheet and write
their effects in a short keyword form, like `gold:2; draw:1`. Cardalyzer
checks every card against your game's rules, builds the table, and runs the
effects and the turn structure around them.

You don't need to write Lua for a typical card. Lua is only needed for the
rare card that does something unusual.

The first rules Cardalyzer ships with are for deck-builders: starter decks, a
market row, drawing, turn cleanup and reshuffling. It comes with **Ember
Guilds**, a small original sample game with placeholder art:

![Four placeholder cards from the Ember Guilds sample game](docs/sample-cards.png)

## Contents

- [What works today](#what-works-today)
- [Install](#install)
- [Try the sample game](#try-the-sample-game)
- [Tutorial: make your own game](#tutorial-make-your-own-game)
- [Card spreadsheet reference](#card-spreadsheet-reference)
- [Rules file reference](#rules-file-reference)
- [Custom effects](#custom-effects)
- [When something is wrong](#when-something-is-wrong)
- [How it works](#how-it-works)
- [Project layout](#project-layout)

## What works today

Cardalyzer is early. Here's where each milestone stands:

| Milestone | State |
| --- | --- |
| 1. Table and zones: two seats, deck/hand/play/discard zones, market row | done |
| 2. Core loop: starter decks, draw, End Turn cleanup and reshuffle | done; needs in-game testing |
| 3. Market and buying | next |
| 4. Effects: keyword effects, ally triggers, bases with defense | the keyword parser and registry are done; playing a card from your hand doesn't trigger its effects yet |
| 5. First real game fully playable | |
| 6. Generalize and build a second tiny game | |
| 7. Workshop template and release | |

So today you can:

- deal a full game from your spreadsheet,
- see the market row filled,
- press **End Turn** to discard, draw a new hand and reshuffle,
- save and reload the game.

Buying cards and playing them for their effects come in the next milestones.

## Install

You need:

- **Python 3** and the Pillow library, used to build the mod and draw placeholder card art:
  ```sh
  pip install pillow
  ```
  On Windows, use `py` wherever this README says `python`.
- **Tabletop Simulator**, to play.
- **Lua 5.2** (optional), only to run the automated tests.

Then download the project:

```sh
git clone https://github.com/Oreo12/Cardalyzer.git
cd Cardalyzer
```

## Try the sample game

Building a game always takes the same three commands. Each one reads the
previous one's output:

```sh
python tools/csv2json.py games/sample/cards.csv   # 1. check the spreadsheet, write cards.json
python tools/make_sheets.py games/sample          # 2. draw placeholder card sheets into art/
python tools/bundle.py games/sample               # 3. bundle everything into build/Global.lua
```

You should see:

```
wrote 19 cards to games/sample/cards.json
wrote 1 sheet(s) for 19 cards to games/sample/art
wrote .../build/Global.lua
```

Before loading it in TTS, the card images need a web address TTS can
download from:

1. In TTS, go to **Modding → Cloud Manager** and upload
   `games/sample/art/sheet_1.jpg` and `games/sample/art/back.jpg`. If the repo
   is public, you can skip uploading and use GitHub instead.
2. Open `games/sample/rules.lua` and set `art.baseUrl` to the folder those
   files live in. The engine adds `art/sheet_1.jpg` and `art/back.jpg` to
   the end of it:
   ```lua
   art = {
     -- GitHub (public repos only):
     baseUrl = "https://raw.githubusercontent.com/Oreo12/Cardalyzer/main/games/sample/",
   },
   ```
   Steam Cloud gives every file its own address, so for those you put the full
   URLs in `games/sample/art.json` instead: replace `"art/sheet_1.jpg"` and
   `"art/back.jpg"` with the two URLs. Any value starting with `http` is used
   as-is.
3. Run `python tools/bundle.py games/sample` again.

To play:

1. Start a new game in TTS on an empty table.
2. Open **Modding → Scripting**, select **Global**, and paste in the contents of
   `build/Global.lua`. If you use VS Code, the
   [TTS Editor extension](https://marketplace.visualstudio.com/items?itemName=sebaestschjin.tts-editor)
   can push it for you.
3. Click **Save & Play**. A panel appears at the top left:
   ```
   Ember Guilds
   Press New Game to deal.
      White: Gold 0 · Might 0 · Health 40 · Deck 0 · Discard 0
      Red: Gold 0 · Might 0 · Health 40 · Deck 0 · Discard 0
   [New Game] [End Turn]
   ```
4. Sit at White and press **New Game** (only the host can). Each seat
   gets its starter deck, the first player draws 3 cards and the second draws
   5, and five cards fill the market row.
5. Press **End Turn** on your turn. Your hand goes to your discard pile, you draw
   5, and play passes to Red. When a deck runs out, the discard pile is
   shuffled into it automatically.

## Tutorial: make your own game

This walk-through builds a tiny pirate game called **Pirate Port**. Players
earn *Doubloons* to buy cards, fire *Cannons* to attack, and each ship has
*Hull* points. Every snippet below was run through the real tools.

### 1. Copy the sample

```sh
cp -r games/sample games/pirate
```

On Windows, copy the folder in Explorer instead.

### 2. Write the cards

Open `games/pirate/cards.csv` in Excel, Google Sheets or a text editor, and
replace its contents with:

```csv
id,name,deck,faction,type,cost,copies,effects,ally_effects,scrap_effects,defense,text
deckhand,Deckhand,starter,none,unit,0,7,doubloons:1,,,,
gunner,Gunner,starter,none,unit,0,3,cannons:1,,,,
smuggler,Smuggler,market,rogue,unit,2,4,doubloons:2,draw:1,,,
broadside,Broadside,market,navy,unit,4,3,cannons:4,cannons:2,,,
fort,Harbor Fort,market,navy,building,5,2,cannons:2;hull:1,,,6,
parrot,Lucky Parrot,market,rogue,unit,3,2,custom:luckyParrot,,,,"Draw 2 if your hull is below 10."
```

Here's how to read a few of those rows:

- **Deckhand**: every player starts with 7 copies (`deck` is `starter`). It
  gives 1 Doubloon when played.
- **Smuggler**: 4 copies go into the market deck, and it costs 2. It gives
  2 Doubloons. If another Rogue card is in play, it also draws a card
  (`ally_effects`).
- **Harbor Fort**: a `building`, so it stays in play between turns. It has
  6 defense, gives 2 Cannons and repairs 1 Hull. The `;` separates the two
  effects.
- **Lucky Parrot**: its effect is too unusual for a keyword, so it names a
  custom effect. You'll write that in step 4.

If you save the sheet from Excel, choose **CSV UTF-8**.

### 3. Write the rules

Replace `games/pirate/rules.lua` with:

```lua
return {
  name = "Pirate Port",
  seats = { { color = "Blue" }, { color = "Green" } },

  -- Each key becomes an effect keyword: doubloons:2, cannons:4
  resources = {
    { key = "doubloons", label = "Doubloons" },
    { key = "cannons", label = "Cannons" },
  },
  -- Stats persist between turns and are keywords too: hull:1
  stats = { { key = "hull", label = "Hull", start = 20 } },

  handSize = 5,
  openingHand = 5,
  market = { rowSize = 4, buyTo = "discard" },

  factions = {
    rogue = { label = "Rogue", color = "#B8862B" },
    navy = { label = "Navy", color = "#2B4FB8" },
  },
  cardTypes = { unit = { persistent = false }, building = { persistent = true } },
  mechanics = { allies = true, persistent = true, scrap = true },
  art = { baseUrl = "" }, -- fill in once the images are uploaded

  customEffects = {
    -- step 4
  },
}
```

Notice that no engine code changed. The names `doubloons`, `cannons` and `hull`
are new keywords simply because the rules list them.

### 4. Add the custom effect

Fill in `customEffects` with the Lucky Parrot:

```lua
customEffects = {
  luckyParrot = {
    text = "Draw 2 if your hull is below 10", -- shown on the card's tooltip
    apply = function(game, seat, ctx)
      if game.state.players[seat].stats.hull < 10 then
        game:draw(seat, 2)
      end
    end,
  },
},
```

### 5. Build it

```sh
python tools/csv2json.py games/pirate/cards.csv
python tools/make_sheets.py games/pirate --title "Pirate Port"
python tools/bundle.py games/pirate
```

The second command colours each card's frame by its faction, using the
colours from `rules.lua`. Upload the sheets, set `art.baseUrl`, rebuild, and
load `build/Global.lua` into TTS as in [Try the sample game](#try-the-sample-game).
After **New Game**, the panel shows your game's own names:

```
Turn 1 · Blue to play
▶ Blue: Doubloons 0 · Cannons 0 · Hull 20 · Deck 5 · Discard 0
   Green: Doubloons 0 · Cannons 0 · Hull 20 · Deck 5 · Discard 0
```

### 6. Change things and rebuild

Run the same three commands after every change:

| You changed | Re-run |
| --- | --- |
| `cards.csv` | all three |
| `rules.lua` only | `bundle.py` (and `make_sheets.py` if you changed faction colours) |
| engine code in `src/` | `bundle.py` |

Then paste the new `build/Global.lua` into TTS. A saved game keeps its state
across a reload.

## Card spreadsheet reference

One row per card. The column order doesn't matter, but the names do.

| Column | Required | Meaning | Example |
| --- | --- | --- | --- |
| `id` | yes | Unique id: lowercase letters, digits, `_` | `war_anvil` |
| `name` | yes | Name shown on the card | `War Anvil` |
| `deck` | no (default `market`) | Which pile the card starts in: `starter`, `market` or `fixed` (see below) | `market` |
| `faction` | no (default `none`) | Faction for ally effects and frame colour | `forge` |
| `type` | no (default `unit`) | A type from `cardTypes` in the rules | `building` |
| `cost` | yes | Price in the market | `4` |
| `copies` | yes | How many copies exist (see `deck`) | `1` |
| `effects` | yes (may be empty) | What happens when it's played | `might:3` |
| `ally_effects` | no | Extra effects when another card of its faction is in play | `draw:1` |
| `scrap_effects` | no | Effects when you scrap it (remove it from the game) | `might:2` |
| `defense` | no | Damage needed to destroy a persistent card | `5` |
| `text` | no | Extra rules text shown on the card | `Ally: take a free card.` |

The `deck` values work like this:

- **`starter`**: every player gets `copies` of it in their starting deck.
- **`market`**: `copies` are shuffled into the market deck, which refills the row.
- **`fixed`**: a pile of `copies` that's always available next to the row.
  The sample's Hireling works this way.

### Writing effects

An effect is `keyword:amount`. Put `;` between several effects. Spaces are
fine.

| You write | It means |
| --- | --- |
| `gold:2` | +2 to the `gold` resource this turn |
| `health:-3` | Lose 3 from the `health` stat |
| `draw:1` | Draw a card (reshuffling if needed) |
| `opponent_discard:1` | Each opponent discards a card on their turn |
| `scrap_hand:1` | You may scrap a card from your hand or discard pile |
| `gold:2; draw:1` | Both |
| `custom:luckyParrot` | Run `rules.customEffects.luckyParrot` |

Some keywords are always available:

- `draw`, `opponent_discard` and `scrap_hand`.
- `custom:<name>`.
- One keyword per resource and stat in your rules, using its `key`.

`opponent_discard` and `scrap_hand` only record what's owed for now. The
prompts that let a player choose a card come in milestone 4.

## Rules file reference

These are the fields in `games/<yours>/rules.lua`:

| Field | Example | Meaning |
| --- | --- | --- |
| `name` | `"Ember Guilds"` | Title shown on the panel |
| `seats` | `{ {color="White"}, {color="Red"} }` | Player colours in turn order; optional `name` per seat |
| `resources` | `{ {key="gold", label="Gold"} }` | Per-turn pools, reset at end of turn |
| `stats` | `{ {key="health", label="Health", start=40} }` | Values that persist between turns |
| `handSize` | `5` | Cards drawn at the end of each turn |
| `openingHand` | `{3, 5}` or `5` | First hand per player in turn order; one number means everyone draws that many |
| `firstSeat` | `1` | Which seat goes first |
| `market.rowSize` | `5` | Face-up market slots |
| `market.buyTo` | `"discard"` | Where bought cards go (milestone 3) |
| `factions` | `forge = {label="Forge", color="#C8502D"}` | Faction labels and frame colours |
| `cardTypes` | `building = {persistent=true}` | Types; persistent ones stay in play |
| `mechanics` | `{allies=true, persistent=true, scrap=true}` | Turn whole mechanics on or off |
| `win` | `{type="stat_depleted", stat="health", atOrBelow=0}` | Win condition (milestone 4) |
| `art.baseUrl` | `"https://…/games/sample/"` | Where the card images are hosted |
| `layout` | `{seatDistance=10, cardSpacing=2.8}` | Table spacing; adjust if piles overlap your table's edge |
| `customEffects` | see below | Lua for unusual cards |

## Custom effects

A custom effect is a Lua function in `rules.customEffects`. Cards call it
with `custom:<name>`. The function gets three things:

- **`game`**: the running game.
  - `game.state.players[seat]` holds a player's `hand`, `deck`, `discard`,
    `play`, `resources`, `stats` and `pending`.
  - `game:draw(seat, n)` draws cards.
  - `game:opponentsOf(seat)` lists the other seats.
- **`seat`**: the number of the player who played the card.
- **`ctx`**: extra information about the play. It's an empty table for now.

```lua
customEffects = {
  -- Gain 1 gold for every card in your hand.
  counting = {
    text = "Gain 1 Gold per card in your hand",
    apply = function(game, seat, ctx)
      local p = game.state.players[seat]
      p.resources.gold = p.resources.gold + #p.hand
    end,
  },

  -- A bare function works too; the card's `text` column is used as its description.
  tax = function(game, seat, ctx)
    for _, other in ipairs(game:opponentsOf(seat)) do
      game.state.players[other].stats.health = game.state.players[other].stats.health - 1
    end
  end,
},
```

A custom effect should only change `game.state`. The table redraws itself
from the state, so the function never needs to move cards on the table.

## When something is wrong

Cardalyzer checks your cards twice: once when you convert the spreadsheet,
and again when the mod loads.

**A typo in the spreadsheet.** `csv2json.py` refuses to write the file and
lists every problem:

```
games/pirate/cards.csv: 2 problem(s)
  card 'kraken': cost must be a whole number, got 'five'
  card 'kraken': effects entry 'cannons 6' should look like keyword:amount
```

**A keyword your rules don't define.** The mod doesn't start, and it
broadcasts in TTS chat:

```
[Cardalyzer] card data problems:
  card 'kraken' uses unknown keyword 'tentacles'
```

To fix it, either add `tentacles` to `resources` or `stats`, or correct the
card.

**Cards show as white or blank squares.** TTS couldn't download the images.
Check that `art.baseUrl` ends with `/` and that the URLs open in a browser
while signed out. Raw GitHub links don't work while the repo is private.

**Debugging from the TTS console.** The game is exposed as `Cardalyzer.game`:

```lua
print(#Cardalyzer.game.state.players[1].hand)    -- cards in seat 1's hand
print(Cardalyzer.game.state.market.row[1])       -- uid in the first market slot
```

### Running the tests

```sh
python tools/bundle.py games/sample && lua tests/run.lua
```

This runs the real bundled script against a fake TTS. You should see
`14 passed, 0 failed`. On macOS and Linux, `make all` rebuilds everything and
then runs the tests.

## How it works

- **The state is the truth.** Every card is an instance with an id like
  `c12`, and each pile is a list of those ids. Each physical card carries
  its id in its GM Notes.
- **The table is a picture of the state.** To redraw a pile, Cardalyzer
  removes what it spawned there and spawns it again. A card dragged to the
  wrong place therefore can't break the game. Later milestones will treat
  player actions, like dragging a card into the play zone, as requests that
  update the state.
- **Reload-safe.** `onSave` stores the whole state, so loading a save
  continues the same game.

## Project layout

```
src/
  main.lua           Global entry: onLoad, onSave, button handlers
  engine/
    cards.lua        card library, effect-string parsing
    effects.lua      keyword registry (resources, stats, draw, custom:...)
    state.lua        game state tables (saved with onSave)
    turn.lua         setup, draw/reshuffle, market refill, end-of-turn cleanup
    zones.lua        table layout maths + spawning scripting/hand zones
    board.lua        renders state as TTS objects
    ui.lua           XML status panel and buttons
    game.lua         facade that wires the modules together
games/sample/
  cards.csv          the card spreadsheet (edit this)
  rules.lua          everything game-specific (edit this)
  cards.json         generated by csv2json.py
  art/, art.json     generated by make_sheets.py
tools/               csv2json.py, make_sheets.py, bundle.py
tests/               run.lua + fake TTS API
```

If making your game requires changing anything in `src/`, that's a bug in
Cardalyzer. Please open an issue.

## License

MIT. The sample game's cards and placeholder art are original.
