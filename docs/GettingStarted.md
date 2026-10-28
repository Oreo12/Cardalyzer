# Getting Started with Cardalyzer

## Table of Contents
1. [Introduction](#introduction)
2. [What You Need](#what-you-need)
3. [Play the Sample Game](#play-the-sample-game)
4. [Install the Tools](#install-the-tools)
5. [Build the Sample Yourself](#build-the-sample-yourself)
6. [Load a Build into Tabletop Simulator](#load-a-build-into-tabletop-simulator)
7. [Make Your First Game](#make-your-first-game)
8. [Rebuild After a Change](#rebuild-after-a-change)
9. [Troubleshooting](#troubleshooting)
10. [Where to Go Next](#where-to-go-next)

## Introduction
Cardalyzer is a deck-building card game engine for Tabletop Simulator (TTS).
A Cardalyzer game is just two files you write:

- **`cards.csv`**: a spreadsheet with one row per card: its name, cost, how
  many copies, and what it does.
- **`rules.lua`**: a settings file that says how your game works: how many
  players, what the resources are called, how big the market is, how you win.

Cardalyzer's tools check those files and bundle them, with the engine, into
one script (`Global.lua`). You paste that script into TTS and the game is
ready to play.

Most games need no programming. Card effects are written as short keywords,
like `gold:2; draw:1`, and `rules.lua` is mostly filling in values. Lua code
is only needed for the odd card that does something no keyword covers.

[Back to Top](#getting-started-with-cardalyzer)

## What You Need

**To play:**
- [Tabletop Simulator](https://store.steampowered.com/app/286160/Tabletop_Simulator/) on Steam.

**To make your own game:**
- **Python 3.** Download it from [python.org](https://www.python.org/downloads/).
  On Windows, tick *Add python.exe to PATH* in the installer.
- **Pillow**, a Python library the tools use to draw placeholder card art.
- **A spreadsheet program or text editor** for `cards.csv` (Excel, Google
  Sheets, LibreOffice, or any text editor), and a text editor for `rules.lua`
  (VS Code is a good free choice).
- **Somewhere to host images** TTS can download, for your card art: Steam
  Cloud (built into TTS) or a public GitHub repository.

**Optional:**
- **Lua 5.2**, only if you want to run Cardalyzer's automated tests.

[Back to Top](#getting-started-with-cardalyzer)

## Play the Sample Game
The quickest way to see what Cardalyzer does is to play **Ember Guilds**, the
sample game.

1. Subscribe to [Cardalyzer on the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3829026544).
2. Start TTS and choose **Create → Singleplayer** (or host a multiplayer game).
3. Open **Games → Workshop**, and load **Cardalyzer**.
4. Sit at **White**, and press **New Game** in the panel on the right.
5. Pick the number of players and press **Play Game**.

To learn the buttons, press **Tutorial** in the New Game menu, or read
[Playing a game](Playing.md). In singleplayer you can switch seats from the
player list at the top right to take every player's turn yourself.

[Back to Top](#getting-started-with-cardalyzer)

## Install the Tools
1. Install Python 3 (see [What You Need](#what-you-need)).
2. Open a terminal: on Windows, *Command Prompt* or *PowerShell*; on macOS,
   *Terminal*.
3. Install Pillow:
   ```sh
   pip install pillow
   ```
4. Download Cardalyzer. Either click **Code → Download ZIP** on the
   [GitHub page](https://github.com/Oreo12/Cardalyzer) and unzip it, or use Git:
   ```sh
   git clone https://github.com/Oreo12/Cardalyzer.git
   ```
5. Move into the folder:
   ```sh
   cd Cardalyzer
   ```

> **Windows:** type `py` wherever this guide says `python`.

The folders you'll use:

| Folder | What's in it |
| --- | --- |
| `games/` | One folder per game. `sample` is Ember Guilds, `lantern` is Lantern Fair, `template` is a blank game to copy |
| `tools/` | The scripts that check and build a game |
| `build/` | Where built scripts land, ready to paste into TTS |
| `docs/` | These guides |
| `src/` | The engine itself. You shouldn't need to change it |

[Back to Top](#getting-started-with-cardalyzer)

## Build the Sample Yourself
Building any game takes the same three commands. Run them from the
Cardalyzer folder:

```sh
python tools/csv2json.py games/sample/cards.csv   # 1. check the spreadsheet
python tools/make_sheets.py games/sample          # 2. draw placeholder card art
python tools/bundle.py games/sample               # 3. bundle it into build/Global.lua
```

You should see:

```
wrote 19 cards to games/sample/cards.json
wrote 1 sheet(s) for 19 cards to games/sample/art
wrote .../build/Global.lua
```

What each one does:

1. **`csv2json.py`** reads your spreadsheet, checks every card, and writes
   `cards.json`. If anything is wrong, it lists the problems instead.
2. **`make_sheets.py`** draws plain placeholder cards, laid out as TTS card
   sheets (one image holding a grid of card faces), in the game's `art`
   folder. Skip it if you have your own art (see
   [Using card art you already have](Customising.md#using-card-art-you-already-have)).
3. **`bundle.py`** packs the engine, your rules and your cards into one
   script, `build/Global.lua`.

### Host the card images
TTS downloads card images from the web, so they need a web address:

1. In TTS, open **Modding → Cloud Manager** and upload
   `games/sample/art/sheet_1.jpg` and `games/sample/art/back.jpg`.
2. Steam Cloud gives each file its own address. Open `games/sample/art.json`
   and replace `"art/sheet_1.jpg"` and `"art/back.jpg"` with those two
   addresses.
3. Run `python tools/bundle.py games/sample` again.

If your files are in a **public** GitHub repository, you can skip uploading:
set `art.baseUrl` in `rules.lua` to the folder's raw address, and Cardalyzer
adds `art/sheet_1.jpg` and `art/back.jpg` to the end of it:

```lua
art = {
  baseUrl = "https://raw.githubusercontent.com/<you>/<repo>/main/games/sample/",
},
```

> Running `make_sheets.py` again resets `art.json`, so paste your Steam Cloud
> addresses in again afterwards.

Lantern Fair builds the same way, into its own file. Its art already points
at this repository:

```sh
python tools/csv2json.py games/lantern/cards.csv
python tools/make_sheets.py games/lantern --title "Lantern Fair"
python tools/bundle.py games/lantern -o build/lantern/Global.lua
```

[Back to Top](#getting-started-with-cardalyzer)

## Load a Build into Tabletop Simulator
1. Start a new game in TTS on an empty table.
2. Open **Modding → Scripting** and select **Global**.
3. Replace everything there with the contents of `build/Global.lua`.
4. Click **Save & Play**.

The Cardalyzer panel appears at the bottom right. Sit at White and press
**New Game** to deal.

To keep your game, save it in TTS (**Games → Save & Load**). The game's
progress is saved with it, so loading the save carries on where you left off.

> **Tip:** the [TTS Editor extension](https://marketplace.visualstudio.com/items?itemName=sebaestschjin.tts-editor)
> for VS Code can send the script to TTS for you, instead of copying and pasting.

[Back to Top](#getting-started-with-cardalyzer)

## Make Your First Game
This walk-through builds a tiny pirate game called **Pirate Port**. Players
earn *Doubloons* to buy cards, fire *Cannons* to attack, and each ship has
*Hull* points. When a ship's Hull reaches 0, it sinks.

### Step 1: Copy the sample
Copy the `games/sample` folder and name the copy `games/pirate`. In a
terminal:

```sh
cp -r games/sample games/pirate
```

On Windows, copy and rename the folder in File Explorer instead.

### Step 2: Write the cards
Open `games/pirate/cards.csv` in a spreadsheet program or text editor, and
replace everything in it with:

```csv
id,name,deck,faction,type,cost,copies,effects,ally_effects,scrap_effects,defense,text
deckhand,Deckhand,starter,none,unit,0,7,doubloons:1,,,,
gunner,Gunner,starter,none,unit,0,3,cannons:1,,,,
smuggler,Smuggler,market,rogue,unit,2,4,doubloons:2,draw:1,,,
broadside,Broadside,market,navy,unit,4,3,cannons:4,cannons:2,,,
fort,Harbor Fort,market,navy,building,5,2,cannons:2;hull:1,,,6,
parrot,Lucky Parrot,market,rogue,unit,3,2,custom:luckyParrot,,,,"Draw 2 if your hull is below 10."
```

How to read a few of those rows:

- **Deckhand**: `deck` is `starter`, so every player starts with 7 of them.
  Playing one gives 1 Doubloon.
- **Smuggler**: 4 copies are shuffled into the market deck, and it costs 2.
  It gives 2 Doubloons. If another Rogue card is in play too, it also draws a
  card (that's its `ally_effects`).
- **Harbor Fort**: a `building`, so it stays in play from turn to turn. It
  takes 6 damage to destroy, gives 2 Cannons and repairs 1 Hull. A `;`
  separates two effects.
- **Lucky Parrot**: its effect is too unusual for a keyword, so it names a
  custom effect, which you'll write in step 4.

> Saving from Excel? Choose **CSV UTF-8**.

Every column and keyword is listed in [Cards](Cards.md).

### Step 3: Write the rules
Replace everything in `games/pirate/rules.lua` with:

```lua
return {
  name = "Pirate Port",
  seats = { { color = "Blue" }, { color = "Green" } },

  -- Each key becomes an effect keyword: doubloons:2, cannons:4.
  -- spend says what the Buy and Attack buttons use.
  resources = {
    { key = "doubloons", label = "Doubloons", spend = "buy" },
    { key = "cannons", label = "Cannons", spend = "attack" },
  },
  -- Stats last from turn to turn, and are keywords too: hull:1
  stats = { { key = "hull", label = "Hull", start = 20 } },
  -- Attacks lower Hull; a ship at 0 is sunk.
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

No engine code changed: `doubloons`, `cannons` and `hull` became keywords
just because the rules list them. Every setting is explained in
[Rules](Rules.md).

### Step 4: Add the custom effect
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

More about this in [Custom effects](CustomEffects.md).

### Step 5: Build it
```sh
python tools/csv2json.py games/pirate/cards.csv
python tools/make_sheets.py games/pirate --title "Pirate Port"
python tools/bundle.py games/pirate
```

`make_sheets.py` colours each card's frame by its faction, using the colours
in `rules.lua`. Host the card images (see
[Host the card images](#host-the-card-images)), rebuild, and
[load it into TTS](#load-a-build-into-tabletop-simulator).

[Back to Top](#getting-started-with-cardalyzer)

## Rebuild After a Change
After every change, rebuild and paste the new `build/Global.lua` into TTS.
Which commands you need depends on what you changed:

| You changed | Run |
| --- | --- |
| `cards.csv` | all three: `csv2json.py`, `make_sheets.py`, `bundle.py` |
| `rules.lua` only | `bundle.py` (plus `make_sheets.py` if you changed faction colours) |
| your own card art | `bundle.py` |

A saved game keeps its progress when you load a new build into it.

[Back to Top](#getting-started-with-cardalyzer)

## Troubleshooting
Cardalyzer checks your cards twice: when you convert the spreadsheet, and
again when the game loads in TTS.

**The spreadsheet has a mistake.** `csv2json.py` doesn't write anything and
lists every problem instead:

```
games/pirate/cards.csv: 2 problem(s)
  card 'kraken': cost must be a whole number, got 'five'
  card 'kraken': effects entry 'cannons 6' should look like keyword:amount
```

**A card uses a keyword your rules don't have.** The game doesn't start, and
TTS chat says:

```
[Cardalyzer] card data problems:
  card 'kraken' uses unknown keyword 'tentacles'
```

Add `tentacles` to `resources` or `stats` in `rules.lua`, or fix the card.

**Cards show as white or blank squares.** TTS couldn't download the images.
Check that `art.baseUrl` ends with `/`, and that each image address opens in
a web browser while you're signed out. Raw GitHub addresses only work for
public repositories.

**Cards ended up in odd places.** Press **Tidy table**. It lays every card
out again where the game says it belongs.

**Cardalyzer's panels cover TTS's menus.** Every panel in the middle of the
screen has a **Hide** button, and **Hide UI** hides all of them for you. See
[Getting at TTS's own menus](Playing.md#getting-at-ttss-own-menus).

**Still stuck?** [Open an issue](https://github.com/Oreo12/Cardalyzer/issues)
with what you did and what TTS showed.

[Back to Top](#getting-started-with-cardalyzer)

## Where to Go Next
- **[Porting a game](PORTING.md)**: bring a deck-builder you already know to TTS.
- **[Cards](Cards.md)**: every spreadsheet column and effect keyword.
- **[Rules](Rules.md)**: phases, points, kits, sets, extra markets and more.
- **[Customising](Customising.md)**: colours, mats, seating, your own card art.
- **[Custom effects](CustomEffects.md)**: Lua for unusual cards.
- **[Limits and compatibility](Limits.md)**: what Cardalyzer can't do yet.

[Back to Top](#getting-started-with-cardalyzer)
