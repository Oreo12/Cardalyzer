# Custom Effects: Lua for Unusual Cards

Most cards only need keywords. When a card does something no keyword covers,
write a **custom effect**: a small Lua function in `rules.customEffects`,
which the card names with `custom:<name>`.

## Table of Contents
1. [A First Custom Effect](#a-first-custom-effect)
2. [What the Function Gets](#what-the-function-gets)
3. [Asking the Player Something](#asking-the-player-something)
4. [Changing the Next Card Bought](#changing-the-next-card-bought)
5. [Hooks: Reacting to What Happens](#hooks-reacting-to-what-happens)
6. [Helpers](#helpers)
7. [What a Turn Remembers](#what-a-turn-remembers)

## A First Custom Effect
A card with `custom:counting` in its `effects` column runs this:

```lua
customEffects = {
  -- Gain 1 Gold for every card in your hand.
  counting = {
    text = "Gain 1 Gold per card in your hand",   -- shown on the card's tooltip
    apply = function(game, seat, ctx)
      local p = game.state.players[seat]
      p.resources.gold = p.resources.gold + #p.hand
    end,
  },

  -- A bare function works too; the card's text column is used as its description.
  tax = function(game, seat, ctx)
    for _, other in ipairs(game:opponentsOf(seat)) do
      game.state.players[other].stats.health = game.state.players[other].stats.health - 1
    end
  end,
},
```

**The one rule:** a custom effect only changes `game.state`. Cardalyzer
redraws the table from the state, so your function never needs to move
cards itself.

A custom effect with `text = ""` is a hidden helper: it isn't listed when the
card's effects are described.

[Back to Top](#custom-effects-lua-for-unusual-cards)

## What the Function Gets
`apply(game, seat, ctx)` gets three things:

- **`game`**, the running game:
  - `game.state.players[seat]` holds a player's `hand`, `deck`, `discard`,
    `play`, `bases`, `resources`, `stats`, `areas` and `flags`;
  - `game:draw(seat, n)` draws cards;
  - `game:opponentsOf(seat)` lists the other players still in the game;
  - `game:prompt(seat, prompt)` asks a player something (see below).
- **`seat`**, the number of the player who played the card.
- **`ctx`**, the card the effect came from: `ctx.uid` (this copy's id) and
  `ctx.card` (its name, cost, factions and so on). A card with `next_effects`
  sees `ctx.nextTurn = true` when they happen, a defeated monster's
  effects see `ctx.defeated = true`, and a face-down card's effects see
  `ctx.revealed = true` when its owner reveals it ("when you reveal this...").

[Back to Top](#custom-effects-lua-for-unusual-cards)

## Asking the Player Something
Queue a **prompt**, and its question appears on that player's screen. A
prompt can go to any player, not just the one whose turn it is.

| To… | Write |
| --- | --- |
| Take a market card free | `game:prompt(seat, { kind = "free_buy", maxCost = 4, optional = true })` |
| Scrap from hand or discard pile | `game:prompt(seat, { kind = "scrap", count = 2, optional = true, from = {"hand", "discard"} })` |
| Discard | `game:prompt(seat, { kind = "discard", count = 1 })` |
| Scrap from the market row | `game:prompt(seat, { kind = "scrap_row", count = 1, optional = true })` |
| Destroy a building | `game:prompt(seat, { kind = "destroy_base", count = 1, optional = true })` |
| Show a note | `game:prompt(seat, { kind = "reminder", text = "Look at your opponent's hand" })` |
| Pick an opponent who owes something next turn | `game:prompt(seat, { kind = "opponent", owe = { discard = 1 } })` |
| Pick one of your cards | `game:prompt(seat, { kind = "pick", custom = "myEffect" })`, answered by `onPick` |

Extra fields narrow or change a prompt:

| Field | Works with | What it does |
| --- | --- | --- |
| `maxCost` | `free_buy`, `scrap`, `pick` | Only cards costing this much or less (leave it out for any cost) |
| `cardType` | `free_buy`, `scrap`, `pick` | Only this type (or list of types) |
| `factions` | `free_buy`, `scrap`, `pick` | Only cards of one of these factions |
| `includeFixed = true` | `free_buy` | Fixed piles count too |
| `toTop = true` | `free_buy` | The card goes on top of the deck instead of the discard pile |
| `from` | `scrap` | Where from: `"hand"`, `"discard"` and/or `"row"` (the market row) |
| `drawPerPick = 1` | `scrap`, `discard` | Draw that many cards for each card picked, once the prompt ends |
| `scope` | `pick` | Where from: `"play"` (default), `"bases"` (every building in play), `"discard"`, `"opponentDiscard"`, `"hand"` or `"deck"` |
| `only`, `exclude` | `pick` | A list of card ids to choose from, or one to leave out |
| `bounce = true` | `destroy_base` | Return the building to its owner's hand instead |
| `custom = "<name>"` | any | Calls that custom effect's `afterPick(game, seat, uid, prompt)` after each card picked, and `afterPrompt(game, seat, prompt)` when it ends (`prompt.picked` is how many) |

While a required choice takes cards from the hand (an owed discard, or "scrap
a card from your hand"), no card can be played until it's answered.

[Back to Top](#custom-effects-lua-for-unusual-cards)

## Changing the Next Card Bought
Set a flag on the player, `game.state.players[seat].flags`, and it applies to
their next card bought. Each takes `true`, a type such as `"ship"`, or a list
of types (to wait for a card of that type), and is used up when it applies.
Flags clear at the end of the turn.

| Flag | The next card bought goes… |
| --- | --- |
| `buyToTop` | on top of the deck |
| `mayBuyToTop` | on top of the deck or to the discard pile: the player picks |
| `mayBuyToPlay` | straight into play or to the discard pile: the player picks |
| `buyToHand` | into the hand |
| `buyToDeck` | shuffled into the deck |
| `buyToPlay` | straight into play, its effects happening |

`flags.discount = { faction = "forge", amount = 1 }` makes the next matching
card cheaper (`type` works too; leave both out for any card).

[Back to Top](#custom-effects-lua-for-unusual-cards)

## Hooks: Reacting to What Happens
Besides `apply`, a custom effect can have hooks that Cardalyzer calls when
something happens. Most run while the card is in play.

**When this card…**

| Hook | Runs when |
| --- | --- |
| `onAcquire(game, seat, ctx)` | this card is bought |
| `activate(game, seat, ctx)` | its owner presses its **Use** button (once each turn while it's in play). The card then lies sideways until its owner's next turn |
| `whenTurnEnds(game, seat, ctx)` | the turn ends with it in play. Return `"hand"` to keep it, back in the hand after the new hand is drawn |
| `onCall(game, seat, ctx)` | it's called out of a set-aside area with `at = "call"` |
| `onPick(game, seat, uid, prompt)` | a `pick` prompt is answered |

**While this card is in play, when its owner…**

| Hook | Runs when |
| --- | --- |
| `whenYouPlay(game, seat, ctx, played)` | plays another card (`played` is `{ uid, card }`): "whenever you play a unit, gain 1 Might" |
| `whenYouGain(game, seat, ctx, gain)` | gains a resource or stat on their turn (`gain` is `{ key, amount, first }`; `first` is true for the first gain of that key this turn) |
| `whenYouScrap(game, seat, ctx, scrapped)` | scraps a card from hand or discard pile |
| `whenYouUseScrap(game, seat, ctx, used)` | uses a card's scrap ability (`used` is `{ uid, card }`) |
| `whenYouUseAlly(game, seat, ctx, used)` | has a faction bonus fire (`used` is `{ uid, card, faction }`) |
| `whenYouDefeat(game, seat, ctx, defeated)` | defeats a monster in the market (`defeated` is `{ uid, card }`) |
| `whenAttacked(game, seat, ctx, hit)` | is attacked (not their buildings). It can lower `hit.damage` |
| `defenseMod(game, seat, ctx, base)` | any building's defense is worked out: return a change to it (`base` is `{ uid, owner }`): "your buildings gain +1 Defense" |

**Attacks and later jobs**

| Hook | Runs when |
| --- | --- |
| `eachOpponent(game, seat, victim, ctx)` | Makes the effect an attack: runs once for each opponent it reaches, after they've had the chance to react. A blocked opponent is skipped. `apply`, if there is one too, runs first, once |
| `atTurnEnd(game, seat, job)` | at the end of the turn, for jobs queued with `game:atTurnEnd({ custom = "<name>", ... })` |
| `atNextTurn(game, seat, job)` | at the start of that player's next turn, for jobs queued with `game:atNextTurn(seat, { custom = "<name>", ... })`: "at the start of your next turn, gain 2 Gold" |

[Back to Top](#custom-effects-lua-for-unusual-cards)

## Helpers

| Call | What it does |
| --- | --- |
| `game:draw(seat, n)` | Draws cards |
| `game:prompt(seat, prompt)` | Asks a player something |
| `game:opponentsOf(seat)` | The other players still in the game |
| `game:gainFromPile(seat, id)` | Gains the top card of a pile, like `gain:<id>` |
| `game:setAside(seat, uid, key)` | Puts a card from the player's hand, play or discard pile into their area `key` (`players[seat].areas[key]` lists what's there) |
| `game:grantAllies(seat, faction)` | Every faction bonus of that faction counts as met for the rest of the turn; `"all"` meets every one |
| `game:addFaction(seat, uid, faction)` | Gives a card an extra faction until the end of the turn, and checks bonuses |
| `game:copyCard(seat, uid, id)` | Makes card `uid` act as card `id` until the end of the turn, with both cards' factions, and applies the copied card's effects |
| `game:cardOf(uid)` | What a card acts as right now, copies included |
| `game:atTurnEnd(job)`, `game:atNextTurn(seat, job)` | Queue a job for the end of this turn or the start of a player's next turn |

[Back to Top](#custom-effects-lua-for-unusual-cards)

## What a Turn Remembers
`game.state.turn` holds what the current player has done this turn:

| Field | What it holds |
| --- | --- |
| `played` | The cards played, in order |
| `gained` | What was gained, per resource or stat (`gained.gold`) |
| `allyFactions` | Which factions' bonuses fired (`allyFactions.forge`) |
| `scrapped` | How many cards were scrapped: `total`, and `handOrDiscard` |
| `defeated` | How many monsters were defeated |

[Back to Top](#custom-effects-lua-for-unusual-cards)
