# Playing a Cardalyzer Game

This page is for players: what's on the screen, how to take a turn, and how
to set things up the way you like. Examples use Ember Guilds, the sample
game; your game's words and symbols may differ.

## Table of Contents
1. [What's on the Screen](#whats-on-the-screen)
2. [Starting a Game](#starting-a-game)
3. [Taking a Turn](#taking-a-turn)
4. [Your Settings](#your-settings)
5. [Getting at TTS's Own Menus](#getting-at-ttss-own-menus)
6. [Moving Cards by Hand](#moving-cards-by-hand)
7. [The Tutorial](#the-tutorial)

## What's on the Screen
**The info panel** sits at the bottom right. It shows the game's title, then
every player: their name in their seat colour, their health as a heart with
the number on it (with a shield in front for each building they have in
play, showing its defense), and how many cards are in their deck and discard
pile.

Under it are the main buttons, two to a row:

| Button | What it does |
| --- | --- |
| **Settings** | Your own settings (see [Your Settings](#your-settings)) |
| **New Game** | Opens the setup menu. Only the host can deal |
| **Rulebooks** | Lays the game's rulebook PDFs out beside the table, and puts them away again (only in games that have them) |
| **Tidy table** | Lays every card out again where it belongs |
| **Change mat** | Pick your own play mat, and the market's (only in games with mats to choose from) |
| **Hide UI** | Hides all of Cardalyzer's panels, for you only |

```
                 Ember Guilds
      Press New Game to set up a game.
            White        [♥ 40]
                   Deck 0 · Discard 0
              Red        [♥ 40]
                   Deck 0 · Discard 0
           [Settings] [New Game]
         [Rulebooks] [Tidy table]
                      [Hide UI]
```

**Messages**, such as "It's not your turn" or "Ember Smith ally: +2 Might",
appear in the info panel: the last three for everyone, plus a private line
just for you. They're copied to chat as well.

**The action bar** appears just above your hand when it's your turn, with
**Play all** and **End Turn** larger than the rest. Just above it, everyone
sees the current player's resources (in Ember Guilds, Gold as a coin and
Might as a target) once they're above 0.

**Choices** a card asks you to make appear in the middle of the screen:

```
             Choose one                     <- middle of the screen
      [+3 Gold] [+3 Might]

                (3) (5)                     <- Gold and Might
[PLAY ALL (3)] [Attack Red (5 Might)] [Scrap Hireling] [END TURN]
                                            <- just above your hand
```

[Back to Top](#playing-a-cardalyzer-game)

## Starting a Game
1. Sit at a seat. The host presses **New Game**.
2. The setup menu opens in the middle of the host's screen:
   ```
   New Game
   Players [2] [3] [4]
   [Play Game] [Tutorial] [Close]
   ```
   Games can add more rows here, such as which card sets to use or how
   starting hands are dealt. Hover over an option to see what it means.
3. Pick the number of players. The table is laid out for them straight away.
4. Press **Play Game**. Everyone gets their starting deck, draws their first
   hand, and the market is dealt.

The menu remembers your choices for next time.

[Back to Top](#playing-a-cardalyzer-game)

## Taking a Turn
- **Play a card** by dragging it from your hand into your play area (the row
  in front of you), or press **Play all**. Its effects happen at once, and
  the info panel shows your new totals.
- **Buy a card** with the **Buy** button on a market card or pile. It goes to
  your discard pile, and an empty market slot is refilled.
- **Answer a choice.** When a card needs a decision (pick an option, a card to
  scrap, a card to discard), your options appear as buttons.
- **Attack** with the **Attack** button for an opponent: all your attack power
  goes against them. Guard buildings have to be destroyed first. In Ember
  Guilds, a player at 0 Health is out, and the last player left wins.
- **End Turn.** Your played cards and your hand go to your discard pile,
  buildings stay, you draw a new hand, and play passes on. When your deck
  runs out, your discard pile is shuffled to make a new one.

In games with phases, a **Next** button moves on to the next phase, and
**End Turn** works in any phase.

The market turns to face whoever's turn it is, so its cards always read the
right way up.

When an opponent attacks you and you hold a reaction card, you're asked on
your own screen whether to reveal it. The attacker carries on meanwhile; if
you haven't answered by the end of their turn, it counts as not revealed.

[Back to Top](#playing-a-cardalyzer-game)

## Your Settings
**Settings** opens your own settings. Nobody else sees or shares them, and
they're kept with the save.

| Setting | What it does |
| --- | --- |
| **UI size** | Makes all of Cardalyzer's panels and buttons smaller or bigger, from 70% to 155% |
| **Action bar** | Moves your action bar up or down, to clear your on-screen hand, or resets it |
| **Menus** | Puts menus and choices in the middle of the screen, or on the left, right or top |

There's no screen resolution setting: TTS already scales panels to each
player's screen.

[Back to Top](#playing-a-cardalyzer-game)

## Getting at TTS's Own Menus
TTS always draws a mod's panels on top of its own menus (Games, Options, the
Escape menu), and mods can't change that. So that nothing of Cardalyzer's can
get in your way:

- Every panel in the middle of the screen (New Game, Settings, a choice, the
  winner, the tutorial) has a **Hide** button. It tucks the panel into a
  **Show** button beside the main buttons. A choice you tuck away still waits
  for your answer.
- **Hide UI** hides all of Cardalyzer's panels for you, leaving only a **Show
  Cardalyzer** button. You can also give it a key in TTS's **Options → Game
  Keys** ("Cardalyzer: hide or show the UI").
- **Menus** in Settings moves your menus away from the middle.

Panels can't be dragged around: TTS puts a dragged panel back each time the
screen is redrawn.

[Back to Top](#playing-a-cardalyzer-game)

## Moving Cards by Hand
Cardalyzer keeps track of the game itself, not by where cards sit on the
table. It understands a few drags:

- a card from your hand onto your play area is **played**;
- a market card, or one of yours in play, dropped on the scrap pile is
  **scrapped** (removed from the game).

Any other drag is undone, and the card goes back where it belongs. If cards
ever end up somewhere odd, press **Tidy table**.

Cardalyzer also sets up the seats itself. It removes the table's own hand
zones that aren't part of the game, so no stray hand zone can catch your
cards; the message panel says which ones it removed.

[Back to Top](#playing-a-cardalyzer-game)

## The Tutorial
New to the table? Press **Tutorial** in the New Game menu. A short guide
opens in the middle of your screen, just for you, covering what Cardalyzer
does, where everything is, and how the table is laid out.

**Hide button** in the tutorial removes the Tutorial button for you (it stays
hidden after a reload). Type `!tutorial` in chat to get it back.

[Back to Top](#playing-a-cardalyzer-game)
