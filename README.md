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
| 3. Market and buying | done; needs in-game testing |
| 4. Effects: keyword effects, ally triggers, bases with defense, attacks | done; needs in-game testing |
| 5. First real game fully playable | next: 2 to 4 players, reusing existing card art |
| 6. Generalize and build a second tiny game | |
| 7. Workshop template and release | |

So today you can play a full two-player game:

- deal it from your spreadsheet,
- play cards by dragging them from your hand into your play area, and get their effects,
- trigger ally effects, including cards with two factions and wild cards,
- buy from the market row and fixed piles,
- answer choices like "2 Gold or 2 Might" and "scrap a card" from an action panel,
- attack your opponent and their buildings, with guard buildings that must fall first,
- win, and save and reload at any point, including mid-choice.

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
   as-is. Re-running `make_sheets.py` resets these, so paste the URLs in again
   after you regenerate the art.
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
   [New Game] [Tidy table]
   ```
4. Sit at White and press **New Game** (only the host can). Each seat
   gets its starter deck, the first player draws 3 cards and the second draws
   5, and five cards fill the market row.
5. Play your turn. A second panel at the top right shows only to the
   player whose turn it is:
   ```
   Choose one                        <- a card asked you something
   [+3 Gold or +3 Might]
   [Play all (3)]
   [Attack Red (4 Might)]
   [Scrap Hireling: +2 Might]
   [End Turn]
   ```
   - **Play a card** by dragging it from your hand into your play area (the
     row in front of you), or press **Play all**. Its effects apply at once,
     and the status panel shows your new totals.
   - **Buy** with the **Buy** button on a market card or the Hireling pile.
     It goes to your discard pile, and the empty slot refills.
   - **Answer prompts.** When a card needs a choice, such as picking an option,
     a card to scrap or a card to discard, the action panel lists your options
     as buttons.
   - **Attack** with the Attack button: all your Might goes to the opponent's
     Health. Guard buildings (the sample's Stone Wall) have to be destroyed first.
   - **End Turn**. Your played cards and your hand go to your discard pile,
     buildings stay, you draw 5, and play passes to Red. When a deck runs out,
     the discard pile is shuffled into it automatically.
6. If cards end up somewhere odd after a drag, press **Tidy table**. It redraws
   every pile from the game state.

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
  -- spend says what the Buy and Attack buttons use.
  resources = {
    { key = "doubloons", label = "Doubloons", spend = "buy" },
    { key = "cannons", label = "Cannons", spend = "attack" },
  },
  -- Stats persist between turns and are keywords too: hull:1
  stats = { { key = "hull", label = "Hull", start = 20 } },
  -- Attacks lower Hull; a captain at 0 is sunk.
  win = { type = "stat_depleted", stat = "hull", atOrBelow = 0 },

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
| `faction` | no (default `none`) | Faction for ally effects and frame colour. Two factions: `forge/grove`. `any` counts as every faction | `forge` |
| `type` | no (default `unit`) | A type from `cardTypes` in the rules | `building` |
| `cost` | yes | Price in the market | `4` |
| `copies` | yes | How many copies exist (see `deck`) | `1` |
| `effects` | yes (may be empty) | What happens when it's played | `might:3` |
| `ally_effects` | no | Extra effects when another card sharing a faction is in play; once per turn | `draw:1` |
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
| `opponent_discard:1` | Each opponent discards a card at the start of their next turn |
| `scrap_hand:1` | You may scrap a card from your hand or discard pile |
| `scrap_row:1` | You may scrap a card from the market row (it refills) |
| `destroy_base:1` | You may destroy an opponent's building, ignoring guards |
| `draw_discard:1` | Draw a card, then discard a card |
| `reminder` | Show the card's `text` to the player until they click Done (for rules not automated yet) |
| `gold:2; draw:1` | Both |
| `gold:3 \| might:3` | The player picks one |
| `custom:luckyParrot` | Run `rules.customEffects.luckyParrot` |

In `ally_effects` only, an effect can name the faction it needs:
`veil=scrap_row:1` fires when a Veil card is in play, whatever the card's own
faction. Without a prefix, an ally effect needs any card that shares one of
its factions. Each ally effect fires at most once per turn.

Some keywords are always available:

- `draw`, `opponent_discard`, `scrap_hand`, `scrap_row`, `destroy_base`,
  `draw_discard` and `reminder`.
- `custom:<name>`.
- One keyword per resource and stat in your rules, using its `key`.

## Rules file reference

These are the fields in `games/<yours>/rules.lua`:

| Field | Example | Meaning |
| --- | --- | --- |
| `name` | `"Ember Guilds"` | Title shown on the panel |
| `seats` | `{ {color="White"}, {color="Red"} }` | Player colours in turn order; optional `name` per seat |
| `resources` | `{ {key="gold", label="Gold", spend="buy"} }` | Per-turn pools, reset at end of turn. `spend = "buy"` pays for cards, `spend = "attack"` powers attacks |
| `stats` | `{ {key="health", label="Health", start=40} }` | Values that persist between turns |
| `handSize` | `5` | Cards drawn at the end of each turn |
| `openingHand` | `{3, 5}` or `5` | First hand per player in turn order; one number means everyone draws that many |
| `firstSeat` | `1` | Which seat goes first |
| `market.rowSize` | `5` | Face-up market slots |
| `market.buyTo` | `"discard"` or `"deck_top"` | Where bought cards go |
| `factions` | `forge = {label="Forge", color="#C8502D"}` | Faction labels and frame colours |
| `cardTypes` | `wall = {persistent=true, guard=true}` | Types. Persistent ones stay in play and apply their effects again each turn; guard ones must be destroyed before their owner or other buildings can be attacked |
| `mechanics` | `{allies=true, persistent=true, scrap=true}` | Turn whole mechanics on or off |
| `win` | `{type="stat_depleted", stat="health", atOrBelow=0}` | Attacks lower this stat; the last player above it wins |
| `art.baseUrl` | `"https://…/games/sample/"` | Where the card images are hosted |
| `layout` | `{seatDistance=10, cardSpacing=2.8}` | Table spacing; adjust if piles overlap your table's edge |
| `customEffects` | see below | Lua for unusual cards |

## Custom effects

A custom effect is a Lua function in `rules.customEffects`. Cards call it
with `custom:<name>`. The function gets three things:

- **`game`**: the running game.
  - `game.state.players[seat]` holds a player's `hand`, `deck`, `discard`,
    `play`, `bases`, `resources`, `stats` and `flags`.
  - `game:draw(seat, n)` draws cards.
  - `game:opponentsOf(seat)` lists the other seats.
  - `game:prompt(seat, prompt)` asks the player something (see below).
- **`seat`**: the number of the player who played the card.
- **`ctx`**: the card the effect came from: `ctx.uid` and `ctx.card` (its
  name, cost, factions and so on).

To ask the player something, queue a prompt. It appears on their action
panel. These kinds are built in:

| Prompt | Example |
| --- | --- |
| Take a market card for free | `game:prompt(seat, { kind = "free_buy", maxCost = 4, optional = true })` |
| Scrap from hand or discard | `game:prompt(seat, { kind = "scrap", count = 2, optional = true, from = {"hand", "discard"} })` |
| Discard | `game:prompt(seat, { kind = "discard", count = 1 })` |
| Scrap from the market row | `game:prompt(seat, { kind = "scrap_row", count = 1, optional = true })` |
| Destroy a building | `game:prompt(seat, { kind = "destroy_base", count = 1, optional = true })` |
| Show a note | `game:prompt(seat, { kind = "reminder", text = "Look at your opponent's hand" })` |

Setting `game.state.players[seat].flags.buyToTop = true` puts the next card
that player buys on top of their deck, as in "put the next ship you acquire
on top of your deck". Flags clear at the end of the turn.

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
python tools/bundle.py games/sample
lua tests/run.lua    # 35 tests of setup, buying, playing, allies, prompts, attacks, saving
lua tests/fuzz.lua   # 200 random games: no errors, no lost cards, no leaked objects
```

Both run the real bundled script against a fake TTS. You should see
`35 passed, 0 failed` and `fuzz ok`. On macOS and Linux, `make all` rebuilds everything and
then runs the tests.

## How it works

- **The state is the truth.** Every card is an instance with an id like
  `c12`, and each pile is a list of those ids. Each physical card carries
  its id in its GM Notes.
- **The table is a picture of the state.** To redraw a pile, Cardalyzer
  removes what it spawned there and spawns it again. A card dragged to the
  wrong place therefore can't break the game. Only piles whose contents
  changed are redrawn.
- **Player actions are requests.** Dropping a card into your play area,
  clicking Buy or answering a prompt asks the engine to change the state. The
  engine checks it (whose turn, enough Gold, a guard in the way) and either
  applies it or tells you why not.
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
    actions.lua      buy, play, allies, scrap, attack, prompts, turn start/end
    zones.lua        table layout maths + spawning scripting/hand zones
    board.lua        renders state as TTS objects
    ui.lua           XML status panel and the active player's action panel
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
