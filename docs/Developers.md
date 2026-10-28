# For Developers

How Cardalyzer works inside, how to run its tests, and where everything is.
You don't need any of this to make a game.

## Table of Contents
1. [How It Works](#how-it-works)
2. [Running the Tests](#running-the-tests)
3. [Debugging in TTS](#debugging-in-tts)
4. [Project Layout](#project-layout)

## How It Works
- **The game state is the truth.** Every card is an instance with an id like
  `c12`, and each pile is a list of those ids. Each card on the table carries
  its id in its GM Notes.
- **The table is a picture of the state.** To redraw a pile, Cardalyzer
  removes what it put there and lays it out again, so a card dragged to the
  wrong place can't break the game. Only piles whose contents changed are
  redrawn.
- **Player actions are requests.** Dropping a card on your play area,
  pressing Buy or answering a prompt asks the engine to change the state. The
  engine checks it (whose turn, enough Gold, a guard in the way) and either
  applies it or says why not.
- **Saving is safe at any moment.** `onSave` stores the whole state, so
  loading a save carries on the same game, even in the middle of a choice.
- **TTS runs MoonSharp, not standard Lua.** A few things behave differently:
  write `local x = nil` rather than a bare `local x` in a loop (MoonSharp keeps
  the last iteration's value), don't rely on the order of multiple
  assignment, and don't use `//`. Code can pass the tests and still break in
  TTS, so try UI changes in the game itself.

[Back to Top](#for-developers)

## Running the Tests
The tests need Lua 5.2. They run the real bundled script against a fake TTS.

```sh
python tools/bundle.py games/sample
lua tests/run.lua      # the engine: setup, buying, playing, allies, prompts, attacks, saving
lua tests/fuzz.lua     # 200 random games: no errors, no lost cards, no leftover objects
python tools/bundle.py games/lantern -o build/lantern/Global.lua
lua tests/lantern.lua  # Lantern Fair, including whole games played by simple bots
```

Each prints how many tests passed (none should fail), and the fuzz test
prints `fuzz ok`. `tests/smoke.lua` plays 30 turns of any build: set
`CZ_BUILD=<path to Global.lua>` first.

On macOS and Linux, `make all` rebuilds everything and runs the tests. The
same checks run on GitHub for every pull request.

[Back to Top](#for-developers)

## Debugging in TTS
The running game is `Cardalyzer.game`. From TTS's Lua console:

```lua
print(#Cardalyzer.game.state.players[1].hand)    -- cards in seat 1's hand
print(Cardalyzer.game.state.market.row[1])       -- the card in the first market slot
```

[Back to Top](#for-developers)

## Project Layout

```
src/
  main.lua           Global entry: onLoad, onSave, button handlers
  engine/
    cards.lua        card library, effect-string parsing
    effects.lua      keyword registry (resources, stats, draw, custom:...)
    state.lua        game state tables (saved with onSave)
    turn.lua         setup, draw/reshuffle, market refill, end-of-turn cleanup
    actions.lua      buy, play, allies, scrap, attack, prompts, turn start/end
    zones.lua        table layout maths, seating, areas, outlines
    board.lua        lays the state out as TTS objects
    mats.lua         play mats
    kits.lua         per-player starting kits
    rulebooks.lua    the Rulebooks button's PDFs
    ui.lua           XML panels: info panel, menus, the action bar
    theme.lua        looks, symbols, positions
    words.lua        every word players see
    tutorial.lua     the in-game tutorial
    game.lua         the facade custom effects call
    util.lua         small shared helpers
games/sample/        Ember Guilds, the trade-row sample
  cards.csv          the card spreadsheet (edit this)
  rules.lua          everything game-specific (edit this)
  cards.json         written by csv2json.py
  art/, art.json     written by make_sheets.py
games/lantern/       Lantern Fair, the supply sample
games/template/      a blank game to copy
docs/                these guides
tools/               csv2json.py, make_sheets.py, bundle.py, make_icons.py
assets/icons/        the counter symbols (coin, reticle, heart, shield)
tests/               the tests and a fake TTS API
```

`bundle.py` includes every file in `src/engine/` automatically.

If making a game needs any change to `src/`, that's a gap in Cardalyzer:
please [open an issue](https://github.com/Oreo12/Cardalyzer/issues).

[Back to Top](#for-developers)
