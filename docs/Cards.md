# Cards: the Spreadsheet and Effect Keywords

Every card in a Cardalyzer game is one row of `cards.csv`. This page lists
the columns, the piles a card can start in, and every effect keyword.

## Table of Contents
1. [The Columns](#the-columns)
2. [Where a Card Starts](#where-a-card-starts)
3. [Writing Effects](#writing-effects)
4. [Effect Keywords](#effect-keywords)
5. [Effects That Need a Level](#effects-that-need-a-level)
6. [Faction Bonuses](#faction-bonuses)

## The Columns
One row per card. The columns can be in any order, but their names matter.
Only the first few are needed for most cards.

### The essentials

| Column | Needed? | What it is | Example |
| --- | --- | --- | --- |
| `id` | yes | A unique name for the card, used by the rules and other cards: lowercase letters, digits and `_` | `war_anvil` |
| `name` | yes | The name shown on the card | `War Anvil` |
| `cost` | yes | Its price | `4` |
| `copies` | yes | How many copies there are (see [Where a Card Starts](#where-a-card-starts)) | `1` |
| `effects` | yes (can be empty) | What happens when it's played | `might:3` |
| `deck` | no (`market`) | Where it starts (see [Where a Card Starts](#where-a-card-starts)) | `starter` |
| `faction` | no (`none`) | Its faction, for faction bonuses and its frame colour | `forge` |
| `type` | no (`unit`) | Its type, one of the `cardTypes` in your rules | `building` |
| `text` | no | Extra rules text shown on the card | `Ally: take a free card.` |

### Extra effects

| Column | What it is | Example |
| --- | --- | --- |
| `ally_effects` | Extra effects when another card of its faction is in play, once a turn (see [Faction Bonuses](#faction-bonuses)) | `draw:1` |
| `double_ally_effects` | The same, but needing two other cards of its faction in play | `might:3` |
| `scrap_effects` | Effects when you scrap it (remove it from the game) from play. With a faction in front (`forge=might:8`), it can only be scrapped while a card of that faction is in play | `might:2` |
| `next_effects` | Effects at the start of your next turn. The card stays in play until then, and is discarded at the end of that turn | `draw:2` |
| `react_effects` | Makes it a reaction: when an opponent's attack hits you, you may reveal it from your hand for these effects. `block` makes the attack miss you | `block` |

### Other columns

| Column | What it is | Example |
| --- | --- | --- |
| `defense` | How much damage destroys it, for a card that stays in play | `5` |
| `points` | Points it's worth at the end of a points game. Negative for a card that costs points | `3` |
| `starting` | Copies in each player's starting deck, for a card that is also in a pile (`fixed` or `supply`) | `6` |
| `set` | Which card set it belongs to (a `key` from `sets` in your rules). The host turns sets on and off in the New Game menu | `expansion1` |
| `condition` | For an `objective` card: the custom effect that checks whether its goal is met | `sevenShips` |

**Two factions or types.** Put a `/` between them: `forge/grove`, or
`action/attack`. A card with two types has everything both types give: a
`unit/wall` stays in play *and* guards. The faction `any` counts as every
faction, and `anyname` counts as having any card's name (for same-name
bonuses).

> Saving from Excel? Choose **CSV UTF-8**.

[Back to Top](#cards-the-spreadsheet-and-effect-keywords)

## Where a Card Starts
The `deck` column says which pile a card starts in, and what `copies` means:

| `deck` | Where the card goes |
| --- | --- |
| `starter` | Every player gets `copies` of it in their starting deck |
| `market` | `copies` are shuffled into the market deck, which refills the market row |
| `market:<key>` | The same, for one of the extra markets in your rules (`markets`) |
| `fixed` | A pile of `copies` beside the market that's always for sale, like Ember Guilds' Hireling. `pileSizes` in the rules can size it by the number of players |
| `supply` | One of a pool of piles. Each game, some of them are laid out as piles, picked at random or from a preset the host chooses (Lantern Fair's action cards). See `supply` in [Rules](Rules.md#piles-and-the-supply) |
| `dealt` | At the start, each player is dealt some of these at random, straight into play. `deal` in the rules says how many |
| `objective` | Secret goals: each player is dealt some face down. When the card's `condition` is met, a **Complete** button appears, and completing it gives the card's `effects` as the reward |

[Back to Top](#cards-the-spreadsheet-and-effect-keywords)

## Writing Effects
An effect is `keyword:amount`:

| You write | It means |
| --- | --- |
| `gold:2` | +2 Gold this turn |
| `gold:2; draw:1` | Both: put `;` between effects |
| `gold:3 \| might:3` | The player picks one: put `\|` between the options |
| `custom:luckyParrot` | Run the custom effect `luckyParrot` from your rules (see [Custom effects](CustomEffects.md)) |

Spaces are fine. Every resource and stat in your rules is a keyword too:
with a `gold` resource and a `health` stat, `gold:2` gains 2 Gold and
`health:-3` loses 3 Health.

[Back to Top](#cards-the-spreadsheet-and-effect-keywords)

## Effect Keywords

### Drawing and discarding

| Keyword | What it does |
| --- | --- |
| `draw:1` | Draw a card (reshuffling if needed) |
| `discard:1` | Discard a card (you must) |
| `cycle:2` | Discard up to 2 cards, then draw that many |
| `draw_discard:1` | Draw a card, then discard a card |
| `opponent_discard:1` | An opponent discards a card at the start of their next turn (with several opponents, you pick who) |
| `look_top:3` | Look at your top 3 cards and put them back in any order (the first one you pick goes on top) |

### Scrapping (removing cards from the game)

| Keyword | What it does |
| --- | --- |
| `scrap_hand:1` | You may scrap a card from your hand or discard pile |
| `scrap_required:1` | You must scrap a card from your hand or discard pile, if you have one |
| `scrap_from_hand:1`, `scrap_from_discard:1` | You may scrap from just your hand, or just your discard pile. Add `_required` to make it a must |
| `scrap_row:1` | You may scrap a card from the market row (it's refilled) |

### Getting cards

| Keyword | What it does |
| --- | --- |
| `free_buy:4` | Take a card costing 4 or less from the market row, free |
| `free_buy_hand:4` | The same, into your hand |
| `free_buy_top:4` | The same, onto the top of your deck |
| `free_ship_top:4` | Take a card of type `ship` costing 4 or less onto the top of your deck |
| `gain:silk` | Gain the top card of the `silk` pile into your discard pile |
| `gain_card:4` | Gain a card costing 4 or less from any pile or market row |
| `defeat_free:4` | Defeat a monster costing 4 or less, free, and get its reward |

### Attacking other players

| Keyword | What it does |
| --- | --- |
| `destroy_base:1` | You may destroy an opponent's building, ignoring guards |
| `bounce_base:1` | Return an opponent's building to its owner's hand |
| `opponents_damage:3` | Each opponent loses 3 of the stat that decides the game (`win.stat` in your rules) |
| `opponents_gain:gossip` | Each opponent gains the top card of the `gossip` pile |
| `opponents_discard_to:3` | Each opponent discards down to 3 cards in hand, straight away |

Opponents holding a reaction card may reveal it first (see
[Attacks and reactions](Rules.md#attacks-and-reactions)).

### Reactions (in `react_effects`)

| Keyword | What it does |
| --- | --- |
| `block` | The attack doesn't affect you |
| `prevent:3` | The attack does 3 less damage to you |

### Setting cards aside

| Keyword | What it does |
| --- | --- |
| `set_aside:tavern` | Put this card into your `tavern` area (one of the `areas` in your rules) |
| `set_aside_hand:later` | Put a card from your hand into your `later` area |

### Other

| Keyword | What it does |
| --- | --- |
| `reminder` | Shows the card's `text` to the player until they click Done, for a rule that isn't automated |

`gain` and `opponents_gain` take a card's `id` instead of a number, and
`set_aside` and `set_aside_hand` take an area's `key`.

[Back to Top](#cards-the-spreadsheet-and-effect-keywords)

## Effects That Need a Level
Any effect, in any column, can need a level first:

```
mastery>=10=might:5
```

gives 5 Might, but only while the player has 10 or more Mastery. The card's
tooltip shows it as "(Mastery 10+) +5 Might".

- The left side is any resource or stat, or a count of cards: `hand`,
  `deck`, `discard`, `played` (cards played this turn) or `defeated`
  (monsters defeated this turn).
- The comparison is `>=`, `<=`, `>` or `<`.
- A typo on the left side is reported when the game loads.

[Back to Top](#cards-the-spreadsheet-and-effect-keywords)

## Faction Bonuses
An `ally_effects` effect fires when another card that shares one of the
card's factions is in play. Each one fires at most once a turn.

In `ally_effects`, an effect can name the faction it needs in front:

| You write | It fires when… |
| --- | --- |
| `draw:1` | another card sharing one of this card's factions is in play |
| `veil=scrap_row:1` | a Veil card is in play, whatever this card's own faction |
| `samename=draw:1` | another card with the same name (or with faction `anyname`) is in play |

[Back to Top](#cards-the-spreadsheet-and-effect-keywords)
