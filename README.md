# Cardalyzer

**Make your own deck-building card game for Tabletop Simulator, without writing code.**

You list your cards in a spreadsheet and write what each one does in a short
form like `gold:2; draw:1`. Cardalyzer deals the cards, runs every card's
effects, keeps track of whose turn it is, and lays out the table and the
on-screen buttons for you. You only need code (Lua) for the rare card that
does something unusual.

![Four placeholder cards from the Ember Guilds sample game](docs/sample-cards.png)

**[Get started »](docs/GettingStarted.md)** · [Play a game](docs/Playing.md) ·
[Port a game you know](docs/PORTING.md) · [All documentation](#documentation)

---

## What you can make

Cardalyzer runs **deck-builders**: games where you play cards from your hand,
the cards give you things (money, attack power, extra cards), you spend them,
and then you clean up and draw a new hand. It covers both common kinds:

- **Trade-row games**, where a row of cards for sale keeps changing.
- **Supply games**, where the same piles of cards are for sale all game.

It comes with two small original games to play and copy from:

| Game | Kind | What it shows |
| --- | --- | --- |
| **Ember Guilds** (`games/sample`) | Trade row | Buying from a changing row, attacking players and their buildings, last player standing wins |
| **Lantern Fair** (`games/lantern`) | Supply | Piles always for sale, Action and Buy phases, attacks and reactions, most points win |

There's also a blank game, `games/template`, with every common setting
explained, to start your own from.

## Features

**Cards and effects**
- Write effects in plain keywords: gain money or attack power, draw, discard,
  remove cards from your deck ("scrap"), take a free card, and "choose one".
- Name your own resources and stats (Gold, Might, Health, Honor, anything) and
  they become keywords straight away.
- Faction bonuses when cards of the same faction are played together.
- Cards that stay in play (buildings), and guards that must be destroyed first.
- Cards with several types, abilities that unlock at a level ("with 10+
  Mastery, +5 Might"), and effects that wait until your next turn.
- Lua for the occasional card no keyword covers, with many hooks to build on.

**Turns and winning**
- 2 to 4 players. The host picks how many in the New Game menu.
- Turns split into phases (for example Action, then Buy), with costs for
  playing and buying cards.
- Win by knocking everyone else out, or by points: end when piles run out,
  after a number of rounds, or when a shared pool is used up.
- Attacks on every other player, and reactions they can reveal from their hand
  to block or soften them.
- Monsters in the market that players defeat instead of buying, and cards they
  can hire for one turn.
- Secret objectives, starting kits each player picks, card sets the host turns
  on and off, and cards dealt out at the start.

**The table and the screen**
- Everything on screen can be restyled: colours, panel backgrounds, button
  looks, symbols, the title picture, and where each panel sits.
- Every word the game shows can be renamed, for your game's own terms or a
  translation.
- Play mats under each player's area and the market. Players can pick their
  own mats from sets you provide.
- Seats along the sides of the table, round it, along one side, or at exact
  spots you choose.
- Card art from sheets you already host (for example on Steam Cloud), or
  placeholder art drawn for you.
- Rulebook PDFs one button lays out beside the table.
- Each player can resize the on-screen buttons, move them, or hide them, so
  nothing gets in the way of Tabletop Simulator's own menus.
- Save and reload at any moment, even in the middle of a choice.

**What it doesn't do (yet):** no instants or interrupts on other players'
turns beyond reactions, no combat between individual cards, no boards or
tokens, no more than four players and no teams. See
[Limits and compatibility](docs/Limits.md) before you start a big port.

## Documentation

| Page | Read it when you want to… |
| --- | --- |
| [Getting Started](docs/GettingStarted.md) | Install the tools, play the sample, and build your first game step by step |
| [Playing a game](docs/Playing.md) | Learn the buttons, menus and settings players see in Tabletop Simulator |
| [Porting a game](docs/PORTING.md) | Bring a deck-builder you already know to Tabletop Simulator |
| [Cards](docs/Cards.md) | Look up a spreadsheet column or an effect keyword |
| [Rules](docs/Rules.md) | Set up your game: players, resources, the market, turns, winning |
| [Customising](docs/Customising.md) | Change the look of the screen and the table, or use your own card art |
| [Custom effects](docs/CustomEffects.md) | Write Lua for unusual cards |
| [Limits and compatibility](docs/Limits.md) | Check whether your game fits |
| [For developers](docs/Developers.md) | Run the tests and see how the engine works inside |

## Roadmap

| Milestone | State |
| --- | --- |
| 1. The table: seats, decks, hands, play areas and the market row | Done |
| 2. The core loop: starting decks, drawing, ending a turn, reshuffling | Done |
| 3. The market and buying | Done |
| 4. Effects: keywords, faction bonuses, buildings and guards, attacks | Done |
| 5. A first full game, playable by 2 to 4 players | Done |
| 6. A second, different game (Lantern Fair), a porting guide and a blank template | Done |
| 7. Steam Workshop release | In progress |
| 8. Co-operative games: players win or lose together against an automated enemy with its own turns and deck, plus a shuffled turn-order deck | Planned |
| 9. Several games in one save, switched from a menu, each keeping its own progress | Planned |

## Contributing

Found a bug or a card you can't express? [Open an issue](https://github.com/Oreo12/Cardalyzer/issues).
If making your game needs any change to the engine code in `src/`, that's a
gap in Cardalyzer, and worth reporting.

## License

MIT. Both sample games' cards and placeholder art are original.
