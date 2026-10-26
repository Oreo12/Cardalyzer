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
- [Limits and compatibility](#limits-and-compatibility)
- [Install](#install)
- [Try the sample game](#try-the-sample-game)
- [Tutorial: make your own game](#tutorial-make-your-own-game)
- [Card spreadsheet reference](#card-spreadsheet-reference)
- [Rules file reference](#rules-file-reference)
- [Using card art you already have](#using-card-art-you-already-have)
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
| 5. First real game fully playable | 2 to 4 players and reusing existing card art done; needs in-game testing. Next: porting a real game |
| 6. Generalize and build a second tiny game | |
| 7. Workshop template and release | |

So today you can play a full game for 2 to 4 players:

- deal it from your spreadsheet, for the number of players the host picks,
- play cards by dragging them from your hand into your play area, and get their effects,
- trigger ally effects, including cards with two factions and wild cards,
- buy from the market row and fixed piles,
- answer choices like "2 Gold or 2 Might" and "scrap a card" from an action panel,
- attack any opponent and their buildings, with guard buildings that must fall first,
- knock players out until one is left, who wins,
- use card sheets you already host, such as ones on Steam Cloud,
- save and reload at any point, including mid-choice.

## Limits and compatibility

Cardalyzer is built for one kind of card game, and it's best to know that
before you start.

**What it's made for.** Games where, on your turn, you play cards from your
hand, the cards give you resources or effects, you spend those resources, and
then you clean up and draw. That covers deck-builders like Star Realms, Hero
Realms, Ascension, Dominion, and the card play in Clank-style games.

**What it handles:**

- Resources that reset each turn (for buying, attacking, or anything you name)
  and stats that last, like health or points.
- Keyword effects written in the spreadsheet: gain, draw, make an opponent
  discard, scrap from hand or the market, destroy a base, and "choose one".
- Faction ally bonuses, cards that stay in play (bases), and guard cards that
  must be destroyed first.
- A market row with any number of slots (0 removes it), piles that are always
  for sale, and bought cards going to your discard pile or the top of your deck.
- Turning whole mechanics on or off (allies, bases, scrapping).
- Lua for the occasional card that does something no keyword covers.

**What it doesn't handle yet:**

- **Acting on another player's turn.** There is no stack and no responses, so
  there are no instants, counter-spells or interrupts. Effects happen when a
  card is played, on its owner's turn.
- **Triggered or always-on abilities** beyond ally bonuses and bases, such as
  "whenever an opponent draws" or "your other cards cost 1 less".
- **Combat between cards.** Attacks go at a player or at their bases. There's
  no blocking and no damage to individual creatures.
- **Coloured or typed costs.** A card costs one number of one buy resource.
- **Targeting** beyond the built-in choices (a card to scrap or discard, a
  base to destroy).
- **Different market behaviour.** You can resize or remove the row, but not
  change how it works: a shop that refreshes each round, a draft, or bidding
  would need new engine code. With the row removed, its empty zones still sit
  on the table.
- **Boards, tokens and maps.** Only cards are tracked.
- **Hidden roles, trick-taking, bidding, or real-time play.**
- **More than four players, or teams.** Up to four seats fit on the two long
  sides of a rectangular table, and every game is a free-for-all: the last
  player left wins. Three- and four-player games pass the automated tests but
  haven't been played in TTS yet. Four seats need a table about 60 units wide;
  on a smaller one, lower `layout.seatSpread`.
- **Cards moved by hand.** Cardalyzer tracks the game in its script, not by
  where cards sit. It understands a few drags: a card from your hand onto your
  play area is played, and a market row card, or one you have in play, dropped
  on the scrap pile is scrapped. Any other drag is undone: the card goes back
  where it belongs. Engine cards never merge into decks. Moving a card on
  someone else's behalf, or between players, isn't possible by hand.

**Magic: The Gathering and similar games** aren't a good fit. They rely on the
stack, instants, triggered and static abilities, coloured mana, blocking and
targeting, none of which Cardalyzer has. Only a small share of simple cards
would map to the current keywords; the rest would all be custom Lua.

**Other games** can work if their turn looks like "play cards, gain things,
spend them". Each mechanic lives in its own module that a game turns on or
off, so the engine can grow to cover more kinds of game over time.

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
3. Click **Save & Play**. The info panel appears on the right of the screen,
   with no background: each player's name in their seat colour, their Health
   as a heart with the number on it (and, once they have buildings in play, a
   shield in front of it for each one, showing its defense), and their deck
   and discard counts. **Tidy table** is a lone button below it, both clear of
   TTS's own Notes button in the corner:
   ```
                     Ember Guilds
          Press New Game to set up a game.
                White        [♥ 40]
                       Deck 0 · Discard 0
                  Red        [♥ 40]
                       Deck 0 · Discard 0
               [Settings] [New Game]
   ```
   Messages, such as "It's not your turn" or "Ember Smith ally: +2 Might",
   appear inside this panel (the last three for everyone, plus a private line
   just above it for the player they concern), and are copied to chat.
   Cardalyzer doesn't use TTS broadcasts for them, because TTS draws broadcast
   text behind custom UI.
4. Sit at White and press **New Game** (only the host can). A setup menu opens
   in the middle of your screen:
   ```
   New Game
   Players [2] [3] [4]
   [Play Game] [Tutorial] [Close]
   ```
   Pick how many play (the table is laid out for them straight away before
   the first game) and press **Play Game**. The menu closes, each seat gets
   its starter deck, the first player draws 3 cards and everyone else draws
   5, and five cards are dealt into the market row. The menu remembers your
   choices for next time.
5. Play your turn. A row of buttons appears just above your hand, only for
   the player whose turn it is, with Play all and End Turn larger and in gold.
   Just above it, everyone sees the active player's Gold (a coin) and Might (a
   reticle) whenever they're above 0. When a card asks you something, the
   question and its options appear in the middle of the screen:
   ```
                 Choose one                     <- middle of the screen
          [+3 Gold] [+3 Might]

                    (3) (5)                     <- Gold and Might
   [PLAY ALL (3)] [Attack Red (5 Might)] [Scrap Hireling] [END TURN]
                                                <- just above your hand
   ```
   **Settings**, next to New Game, is each player's own: **UI size** makes
   all of Cardalyzer's UI smaller or bigger (70% to 155%) for you alone, and
   **Action bar** moves your bar up or down to clear your on-screen hand
   (TTS doesn't tell scripts how big that is), or resets it. Settings are
   kept with the save. There's no resolution setting: TTS already scales
   custom UI to each player's screen.
   The market turns to face whoever's turn it is, so its cards always read
   the right way up.
   - **Play a card** by dragging it from your hand into your play area (the
     row in front of you), or press **Play all**. Its effects apply at once,
     and the info panel shows your new totals.
   - **Buy** with the **Buy** button on a market card or the Hireling pile.
     It goes to your discard pile, and the empty slot refills.
   - **Answer prompts.** When a card needs a choice, such as picking an option,
     a card to scrap or a card to discard, the action panel lists your options
     as buttons.
   - **Attack** with an opponent's Attack button: all your Might goes to that
     player's Health. Guard buildings (the sample's Stone Wall) have to be
     destroyed first. A player at 0 Health is out, and the last one left wins.
   - **End Turn**. Your played cards and your hand go to your discard pile,
     buildings stay, you draw 5, and play passes to the next seat. When a deck runs out,
     the discard pile is shuffled into it automatically.
6. If cards end up somewhere odd, press **Tidy table**. It redraws every pile
   from the game state.
7. New to the table? Press **Tutorial** in the setup menu. It opens a short
   guide in the middle of your screen, only for you, covering what Cardalyzer
   does, where the info panel, action panel and messages are, and how the table
   is laid out. **Hide button** removes the Tutorial button for you (it stays
   hidden after a reload); type `!tutorial` in chat to get it back.

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
| `seats` | `{ {color="White"}, {color="Red"} }` | Player colours in turn order; optional `name` per seat. Seats sit along the bottom of the table from left to right, then back along the top. A game for fewer players uses the first ones |
| `players` | `{min=2, default=2}` | How many of the seats can play. The host picks from `min` to the number of seats in the info panel. Leave out to always use every seat |
| `resources` | `{ {key="gold", label="Gold", spend="buy"} }` | Per-turn pools, reset at end of turn. `spend = "buy"` pays for cards, `spend = "attack"` powers attacks. Optional `icon` (see `ui.iconBaseUrl`) |
| `stats` | `{ {key="health", label="Health", start=40} }` | Values that persist between turns. Optional `icon` |
| `handSize` | `5` | Cards drawn at the end of each turn |
| `openingHand` | `{3, 5}` or `5` | First hand per player in turn order; one number means everyone draws that many |
| `firstSeat` | `1` | Which seat goes first |
| `market.rowSize` | `5` | Face-up market slots |
| `market.buyTo` | `"discard"` or `"deck_top"` | Where bought cards go |
| `market.faceActive` | `false` | Leave out to turn the market's cards to face the player whose turn it is; `false` keeps them facing seat 1 |
| `factions` | `forge = {label="Forge", color="#C8502D"}` | Faction labels and frame colours |
| `cardTypes` | `wall = {persistent=true, guard=true}` | Types. Persistent ones stay in play and apply their effects again each turn; guard ones must be destroyed before their owner or other buildings can be attacked |
| `mechanics` | `{allies=true, persistent=true, scrap=true}` | Turn whole mechanics on or off |
| `win` | `{type="stat_depleted", stat="health", atOrBelow=0}` | Attacks lower this stat. A player who drops to it is out (no more turns, can't be attacked); the last player left wins |
| `art.baseUrl` | `"https://…/games/sample/"` | Where the card images are hosted (see [Using card art you already have](#using-card-art-you-already-have)) |
| `layout` | `{seatDistance=10, cardSpacing=2.8, seatSpread=28}` | Table spacing; adjust if piles overlap your table's edge. `seatSpread` is how far apart two seats on the same side sit (default 10 × `cardSpacing`) |
| `tutorial` | `false` | Leave out to show the Tutorial button; `false` removes it for everyone |
| `animate` | `false` | Leave out to animate cards: each card flies to its new pile (dealt one after another; face down into a hand). `false` makes piles change instantly. Tidy table is always instant |
| `ui.iconBaseUrl` | `"https://…/icons/"` | Where the counter symbols are: a folder with `coin.png`, `reticle.png`, `heart.png` and `shield.png` (draw them with `tools/make_icons.py`). Defaults to the ones in this repo. The buy resource shows as a coin, the attack resource as a reticle and the win stat as a heart; set `icon = "coin"` (or a full image URL) on any resource or stat to choose, and anything without one shows as text |
| `outlines` | `false` | Leave out to outline every play area, deck, discard pile, the market row, market deck, fixed piles and scrap pile on the table (in seat colours and gold). Outlines are drawn at `layout.surfaceY`; set that to your table's surface height if they float. `false` turns them off |
| `customEffects` | see below | Lua for unusual cards |

## Using card art you already have

`art.json` tells the engine which image sheet and slot each card uses.
`make_sheets.py` writes one with placeholder art, but if your game already
has TTS card sheets (for example on Steam Cloud), write `art.json` yourself
and don't run `make_sheets.py`, which would overwrite it:

```json
{
  "back": "https://steamusercontent-a.akamaihd.net/ugc/…/back/",
  "sheets": [
    { "file": "https://steamusercontent-a.akamaihd.net/ugc/…/sheet1/", "numWidth": 10, "numHeight": 7 },
    { "file": "https://…/sheet2/", "numWidth": 10, "numHeight": 7, "back": "https://…/other-back/" }
  ],
  "cards": {
    "scout": { "sheet": 1, "index": 0 },
    "viper": { "sheet": 1, "index": 1 }
  }
}
```

| Field | Meaning |
| --- | --- |
| `back` | The card back. A sheet can set its own `back` to override it |
| `sheets[n].file` | The sheet image: a full `http(s)://` URL, or a path added to `rules.art.baseUrl` |
| `sheets[n].numWidth`, `numHeight` | How many cards across and down the sheet holds |
| `cards.<id>` | The card's sheet number (counting from 1) and slot (counting from 0, left to right, then down) |
| `hiddenFace` | What other players see of a card in your hand: `"back"` (default) shows the card back, `"last_slot"` shows the sheet's last slot instead, as TTS does when "Back is hidden" is off. Set it at the top or per sheet. With `"last_slot"`, no card may use that slot |

The engine checks `art.json` when the game loads and lists every card with
no slot, a slot outside its sheet, or a card in a reserved last slot.

## Custom effects

A custom effect is a Lua function in `rules.customEffects`. Cards call it
with `custom:<name>`. The function gets three things:

- **`game`**: the running game.
  - `game.state.players[seat]` holds a player's `hand`, `deck`, `discard`,
    `play`, `bases`, `resources`, `stats` and `flags`.
  - `game:draw(seat, n)` draws cards.
  - `game:opponentsOf(seat)` lists the other seats still in the game.
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
| Pick an opponent who owes something next turn | `game:prompt(seat, { kind = "opponent", owe = { discard = 1 } })` |

With more than one opponent left, `opponent_discard` uses that last prompt,
so the player chooses who discards.

Prompts take a few extra fields:

- `free_buy`: `maxCost` (leave out for any cost), `cardType = "ship"` (only
  that type), `includeFixed = true` (fixed piles too) and `toTop = true`
  (onto the deck instead of the discard pile).
- `scrap` and `discard`: `drawPerPick = 1` draws that many cards for each
  card picked, once the prompt ends ("scrap up to two cards, then draw a card
  for each").
- `pick`: choose a card you have in play (`cardType` and `exclude = uid`
  narrow it), then the custom effect named by `custom` runs its `onPick`.

Setting `game.state.players[seat].flags.buyToTop = true` puts the next card
that player buys on top of their deck. Set it to a card type, such as
`"ship"`, to wait for the next card of that type, as in "put the next ship you
acquire on top of your deck". For "you *may* put the next ship...", set
`flags.mayBuyToTop = "ship"` instead: when they buy one, the player picks the
top of their deck or their discard pile. Flags clear at the end of the turn.

While a required choice takes cards from the hand (an owed discard, or "scrap
a card from your hand"), no card can be played until it's answered, so Play
all can't play the cards away first.

Besides `apply`, a custom effect can have:

- `whenYouPlay = function(game, seat, ctx, played)`: runs each time the
  card's owner plays another card while this one is in play. `played` is
  `{ uid, card }`. Use it for "whenever you play a ship, gain 1 Combat".
- `onPick = function(game, seat, uid, prompt)`: answers a `pick` prompt.

`game.state.turn.played` lists the cards played this turn, in order.
`game:copyCard(seat, uid, id)` makes card `uid` act as card `id` until the
end of the turn, with both cards' factions, and applies the copied card's
effects ("copy another ship you've played this turn").
`game:cardOf(uid)` returns what a card acts as right now, copy included.

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
    ui.lua           XML info panel, messages and the active player's action panel
    tutorial.lua     the in-game Tutorial pages and its hide/show option
    game.lua         facade that wires the modules together
games/sample/
  cards.csv          the card spreadsheet (edit this)
  rules.lua          everything game-specific (edit this)
  cards.json         generated by csv2json.py
  art/, art.json     generated by make_sheets.py
tools/               csv2json.py, make_sheets.py, bundle.py, make_icons.py
assets/icons/        the UI's counter symbols (coin, reticle, heart, shield)
tests/               run.lua + fake TTS API
```

If making your game requires changing anything in `src/`, that's a bug in
Cardalyzer. Please open an issue.

## License

MIT. The sample game's cards and placeholder art are original.
