# Limits and Compatibility

Cardalyzer is built for one kind of card game. It's worth checking that your
game fits before you start.

## What It's Made For
Games where, on your turn, you **play cards from your hand**, the cards give
you **resources or effects**, you **spend** those resources, and then you
**clean up and draw**. That covers both common kinds of deck-builder:

- **trade-row games**, where a row of cards for sale keeps changing, and
- **supply games**, where the same piles are for sale all game.

It also covers the card play in deck-building board games.

## What It Handles
- Resources that reset each turn (for buying, attacking, or anything you
  name) and stats that last, like health or points.
- Keyword effects written in the spreadsheet: gain, draw, make an opponent
  discard, scrap from your hand or the market, destroy a building, and
  "choose one".
- Faction bonuses, cards that stay in play (buildings), and guards that must
  be destroyed first.
- A market row of any size (or none), extra market rows, piles that are always
  for sale, a supply of piles picked for each game, and bought cards going to
  your discard pile or the top of your deck.
- Turns split into phases, with Actions and Buys (or anything you name) to
  spend on playing and buying.
- Points games: points on cards, ending when piles run out, after a number of
  rounds, or when a shared pool is used up.
- Attacks that hit every other player, and reactions they reveal from their
  hand to block or soften them.
- Monsters and villains in the market that players defeat for a reward
  instead of buying them, and cards hired for a single turn.
- Abilities that unlock at a level: "with 10+ Mastery, +5 Might".
- Cards whose effects come on your next turn, and set-aside areas of each
  player's own for cards kept out of the deck.
- Turning whole mechanics on or off (faction bonuses, buildings, scrapping).
- Lua for the occasional card no keyword covers.

## What It Doesn't Handle Yet
- **Acting on another player's turn**, beyond reactions. Players can reveal a
  reaction when an attack hits them and answer choices an effect puts to
  them, but there's no stack: no instants, counter-spells or other
  interrupts.
- **Triggered or always-on abilities** beyond faction bonuses and buildings,
  such as "whenever an opponent draws" or "your other cards cost 1 less".
  (Some can be written as custom effects.)
- **Combat between cards.** Attacks go at a player or at their buildings.
  Reactions can block or reduce damage, but there are no blocking creatures.
- **Coloured or typed costs.** A card costs one number of one buying resource.
- **Targeting** beyond the built-in choices (a card to scrap or discard, a
  building to destroy).
- **Different kinds of market.** You can resize or remove the row, add rows,
  and use piles, but not change how a row works: a shop that refreshes each
  round, a draft, or bidding would need new engine code.
- **Boards, tokens and maps.** Only cards are tracked.
- **Hidden roles, trick-taking, bidding, or real-time play.**
- **More than four players, or teams.** Every game is a free-for-all for 2 to
  4 players (co-operative games are planned). Four seats need a table about
  60 units wide; on a smaller one, lower `layout.seatSpread`.
- **The table's own seats.** Cardalyzer removes every hand zone the table
  came with and seats its players itself (see
  [Customising the table](Customising.md#seats)).
- **Moving cards by hand.** Cardalyzer keeps track of the game in its script,
  not by where cards sit. It understands a card dragged from your hand onto
  your play area (played) and a card dropped on the scrap pile (scrapped).
  Any other drag is undone.

## Games That Don't Fit
**Magic: The Gathering and similar games** aren't a good fit. They rely on
the stack, instants, triggered and always-on abilities, coloured mana,
blocking and targeting, none of which Cardalyzer has.

**Other games** can work if their turn looks like "play cards, gain things,
spend them". Each mechanic lives in its own part of the engine that a game
turns on or off, so Cardalyzer can grow to cover more over time.

## Sharing a Port
Porting a published game is your responsibility: only share a port on the
Steam Workshop if you have the rights to its cards, names and art. The
[porting guide](PORTING.md) covers the steps.
