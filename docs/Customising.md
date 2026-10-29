# Customising the Look of Your Game

Everything players see can be changed from `rules.lua`: the colours and
pictures on screen, the words, where each panel sits, and how the table is
laid out. Anything you leave out keeps its default, so change only what you
need.

## Table of Contents
1. [The Screen](#the-screen)
   - [Colours, Panels and the Title](#colours-panels-and-the-title)
   - [Symbols](#symbols)
   - [Where Each Panel Sits](#where-each-panel-sits)
   - [Words](#words)
   - [Buttons, Tooltips and Messages](#buttons-tooltips-and-messages)
   - [Your Own New Game Menu](#your-own-new-game-menu)
2. [The Table](#the-table)
   - [Areas](#areas)
   - [Seats](#seats)
   - [Outlines](#outlines)
   - [Play Mats](#play-mats)
3. [Using Card Art You Already Have](#using-card-art-you-already-have)

> **Pictures must be web links** (`https://…`, such as Steam Cloud): every
> player's TTS downloads them. A `file:///` picture only shows on the
> computer it's on. Mats and rulebooks only accept web links.

# The Screen

## Colours, Panels and the Title
Everything on screen takes its look from a theme, set in `ui.theme`:

```lua
ui = {
  theme = {
    accent = "#8FD4FF",       -- titles and messages
    text = "#FFFFFF",         -- other text
    buttons = {
      primary = { color = "#C8202A", text = "#FFFFFF" },   -- Play Game, Play all, End Turn, New Game
      secondary = { color = "#3A4A63", text = "#E6ECF2" }, -- every other button
      selected = { color = "#2FA4E7", text = "#04111C" },  -- the chosen option in a menu row
    },
    panels = {
      menu = { color = "#050A16", image = "https://…/menu.png", border = "#C8202A", borderSize = 3, padding = 16 },
      choice = { color = "#050A16EE", borderSize = 0, padding = 12 },
      title = { color = "#050A16", padding = 4 },
      info = false,
    },
    title = { image = "https://…/logo.png", height = 74, width = 180 },
    grid = { label = 110, cell = 140, columns = 4, size = 14 },
    primary = { ["cz-playall"] = true, ["cz-end"] = true, ["cz-new"] = true },
  },
},
```

- **Buttons:** give a `color`, and the hover and pressed shades are worked out
  for you (or give TTS's full `colors = "normal|highlighted|pressed|disabled"`).
  `primary` lists which buttons, by id, get the primary look.
- **Panels:** `menu` is the New Game menu, Settings, the tutorial and the
  game-over screen; `choice` is a choice in the middle of the screen; `title`
  is a box round the title; `info` is the whole info panel. Each can have a
  background `color`, a background `image` (tinted by `imageColor`), a
  `border` colour with `borderSize` in pixels (0 for none), and `padding`.
  `false` draws no panel.
- **Title:** your game's `name` as text (`size`), or a picture: `image`, drawn
  `height` pixels tall, in a box `width` wide.
- **Menu grid:** menus line their buttons up on a grid: a `label` column, then
  `columns` cells `cell` pixels wide. A label too long for one cell takes two.

[Back to Top](#customising-the-look-of-your-game)

## Symbols
Counters are a symbol with a number on it: each player's stats (a heart for
health), a shield for each building's defense, and the turn's resources (a
coin for buying, a target for attacking). Change them with `symbols`:

```lua
theme = {
  symbols = {
    pictures = { heart = "https://…/life.png", tower = "https://…/tower.png" }, -- replace a built-in, or add your own
    defense = "tower",        -- the symbol in front of each building's defense
    tint = "#FFFFFF",         -- tints every symbol picture
    text = "#FFFFFF",         -- the number's colour
    textSize = 0.45,          -- the number's size, as a share of the symbol's
    textStyle = "Bold",       -- Normal, Bold, Italic or BoldAndItalic
    outline = "#000000E0",    -- the number's outline, or false
    number = "center",        -- "center": on the symbol; "right": beside it
    sizes = { seat = 34, base = 30, turn = 52 },
  },
},
```

- The built-in symbols are `coin`, `reticle`, `heart` and `shield`.
- `folder` points at a web folder holding all of them as `<name>.png`. Draw
  your own with `tools/make_icons.py`. (`ui.iconBaseUrl` does the same.)
- A resource or stat picks its symbol with `icon`: a symbol's name or a
  picture's link. By default, the buying resource is a coin, the attack
  resource a target, and the stat that decides the game a heart. Anything
  else is shown as text.

[Back to Top](#customising-the-look-of-your-game)

## Where Each Panel Sits
`positions` places each panel with an `anchor` (a corner or edge of the
screen: `UpperLeft`, `MiddleCenter`, `LowerRight` and so on) and `x`, `y`
offsets in pixels from it:

```lua
theme = {
  positions = {
    info = { anchor = "LowerRight", x = -12 },               -- no y: just above the main buttons
    corner = { anchor = "LowerRight", x = -12, y = 70 },     -- the main buttons
    bar = { anchor = "LowerCenter", x = 0, y = 210 },        -- the action bar
    counters = nil,                                          -- nil: just above the action bar
    menus = { anchor = "MiddleCenter", x = 0, y = 0 },       -- menus, choices, game over
  },
},
```

A panel anchored on the left reads from the left. Each player can still
move their own action bar up or down in Settings, on top of `bar.y`.

[Back to Top](#customising-the-look-of-your-game)

## Words
Every word Cardalyzer shows (button labels, the info panel, menus, messages,
questions, the Buy button) can be renamed with `ui.words`, for your game's
own terms or a translation. The full list is in `src/engine/words.lua`.
`{name}` parts are filled in when the text is shown, and a word can also be a
function.

```lua
ui = {
  words = {
    playAll = "Deploy all ({n})",
    endTurn = "Pass",
    theMarketRow = "the Bazaar",
    notEnough = "You need {n} {resource} for {card}.",
    ["effect.draw"] = "Draw {n} cards",     -- how an effect keyword describes itself
  },
},
```

[Back to Top](#customising-the-look-of-your-game)

## Buttons, Tooltips and Messages

| Setting | What it does |
| --- | --- |
| `ui.buttons` | Your own buttons, with the main ones: `{ {label="Scores", onClick=function(game, color) end} }` |
| `ui.tooltips` | Every button has a tooltip saying what it does. Replace one by button id, or remove it with `false`: `{ ["cz-tidy"] = "Straighten the table", ["cz-rulebooks"] = false }` |
| `ui.describeCard` | `function(game, card, text) return text end` changes a card's tooltip on the table; `text` is Cardalyzer's own |
| `ui.buyButton` | The look of the Buy button on market cards: `{ color="#1A1A1A", textColor="#FFD95A", fontSize=150, width=900, height=260, position={0, 0.6, 1.7} }` |
| `ui.messages` | `{ count=3, chat=true }`: how many messages the info panel shows (0 for none), and whether they're copied to chat |
| `ui.scrapButton` | The **Scrap** button on cards in play that have a scrap ability: a see-through button across the card, like **Buy**, clicked by its owner. TTS leaves it out of the card's Alt-zoom preview, so the whole card can still be read. `{ at = 0.9, color, textColor, fontSize, width, height }`: `at` is how far down the card (as it reads) its middle goes, for example level with a scrap ability printed on the cards. A card type's `scrapAt` (a number, or a `function(card)` returning one) overrides `at` for its cards. Cards lying sideways (`playYaw`, or turned when used) get it across them the way they read. `false` puts Scrap buttons in the action bar instead |
| `ui.turnUsedCards` | `false` stops cards that were used with their **Use** button from turning sideways |

[Back to Top](#customising-the-look-of-your-game)

## Your Own New Game Menu
`ui.setupMenu(game, color, menu, UI)` runs each time the New Game menu is
drawn. Change `menu` to adjust it:

- `menu.title`;
- `menu.rows`: rows of XML, `menu.rowHeight` (30) pixels tall each. Build a
  row of options with `UI.optionRow(id, label, options)`, where options is
  `{ {id, label, on}, ... }`;
- `menu.buttons`: `{ {id, label}, ... }`.

```lua
setupMenu = function(game, color, menu, UI)
  menu.title = "Prepare for battle"
  menu.rows[#menu.rows + 1] = UI.optionRow("my_mode", "Mode", {
    { id = "cz-button-1", label = "Quick game", on = game.state.view.quick == true },
  })
end,
buttons = {
  { label = "Quick game", onClick = function(game, color) game.state.view.quick = not game.state.view.quick end },
},
```

Or return a string of XML to draw instead. Give its panel `visibility` set to
`color`, so only that player sees it. Buttons call Cardalyzer by their id:

| Button id | What it does |
| --- | --- |
| `cz-new` | Deals the game |
| `cz-setupclose` | Closes the menu |
| `cz-players-<n>` | Picks the number of players |
| `cz-opening-<i>` | Picks an opening-hand rule |
| `cz-kits-random`, `cz-kits-off` | Turns kits on or off |
| `cz-set-<key>` | Switches a card set |
| `cz-button-<i>` | Runs `ui.buttons[i]` |

`UI.button(id, label, size, kind, width)` draws a button in your theme's
look, and `UI.framed(id, panelStyle, innerXml, width, height, attrs)` a
themed panel.

[Back to Top](#customising-the-look-of-your-game)

# The Table

## Areas
Every area on the table has a place and a size you can change in
`layout.areas`. A player's areas are measured from where they sit:
`along` runs to the player's right, and `out` toward the middle of the
table, in table units. `width` is measured along and `depth` out. Each seat
faces the middle, so one setting fits every player.

```lua
layout = {
  areas = {
    play = { out = 3, width = 20 },  -- a wider play area, a little further in
    bases = false,                   -- no separate area for buildings
    market = { z = 4 },              -- the market a little toward the far seats
  },
},
```

| Area | Default | Can it be turned off? |
| --- | --- | --- |
| `play` | `{along=0, out=2, width=6 × cardSpacing, depth=4}` | no |
| `bases` | `{along=4.5 × cardSpacing, out=2, width=2.5 × cardSpacing, depth=4}` | yes: buildings then sit at the end of the play row |
| `deck` | `{along=-2 × cardSpacing, out=-3, width=2.6, depth=3.6}` | no |
| `discard` | `{along=2 × cardSpacing, out=-3, width=2.6, depth=3.6}` | no |
| `hand` | `{along=0, out=-9, width=7 × cardSpacing, depth=4}` | no |
| `objectives` | `{along=0, out=-3, width=3 × cardSpacing, depth=4}`: between the deck and discard pile | yes: objectives are only listed in the action bar |
| `market` | `{x=0, z=0}`: where the middle of the market row goes | set `market.rowSize = 0` for no row |
| `marketDeck` | left of the row | yes: the market deck isn't shown |
| `scrap` | right of the piles | yes: scrapped cards leave the table (nothing can be dropped there) |

- `play`, `bases` and `objectives` also take `column = true`: their cards then run in a
  column toward the player instead of a row across, for a tall strip such as
  buildings down the side of a mat.
- `marketDeck`, `scrap` and each fixed pile (by its card id, such as
  `hireling = { along = 9, out = 0 }`) take `{along, out}` from the middle of
  the market row. Use this to line them up with slots printed on a market
  mat.
- An area turned off has no outline and no zone. Its cards still follow the
  rules; they just aren't shown on the table.

**Spacing.** `layout.cardSpacing` (2.8) is the distance between cards in a
row, `layout.seatDistance` how far seats are from the middle, and
`layout.seatSpread` how far apart two seats on the same side sit (10 ×
`cardSpacing`). Adjust them if piles hang off your table's edge.
`layout.surfaceY` is the table's surface height, if outlines float above it.

[Back to Top](#customising-the-look-of-your-game)

## Seats
`layout.seating` says where players sit:

| Value | Where the seats go |
| --- | --- |
| `"sides"` (default) | Along the two long sides, facing the market. Seats fill the bottom from left to right, then back along the top |
| `"around"` | Evenly round the market, seat 1 at the bottom and the rest going clockwise, `seatDistance` away (20 unless set), or on an oval with `seatRadius = { x = 30, z = 18 }` |
| `"oneSide"` | Side by side along the bottom, `seatSpread` apart |
| exact spots | Per player count: `{ [2] = { {x=-20, z=0, yaw=90}, {x=20, z=0, yaw=270} } }`. Counts it doesn't list use `"sides"`. A `function(seat, count, rules)` returning `{ x, z, yaw }` works too. Yaw 0 faces +z, and 90 faces +x |

Each player's areas, hand and outlines turn with their seat, and so do the
market's cards on their turn.

**Cardalyzer replaces the table's own seats.** Each playing seat gets a hand
zone where the layout puts it, and every other hand zone on the table is
removed. (TTS's tables bring their own: the custom table has eight, and one
sitting near a player would catch their cards.) The message panel lists the
colours removed. Seats that aren't playing in this game are removed too, and
come back when the player count grows.

[Back to Top](#customising-the-look-of-your-game)

## Outlines
Cardalyzer draws an outline round every area: each player's in their seat
colour, and the market's in gold. `outlines` changes them:

```lua
outlines = { seat = "#FFFFFF", market = "#E8B84A", thickness = 1.5, hide = { deck = true } },
```

- `seat`: one colour for every player's outlines (default: their own colour).
- `market`: the market's colour.
- `thickness`: a multiplier.
- `hide`: areas to leave without an outline: `play`, `bases`, `deck`,
  `discard`, `row` (round the whole market row), `slots` (each card in it),
  `marketDeck`, `fixed` and `scrap`. Handy when a mat already prints its own
  frames.
- `outlines = false` turns them all off.

[Back to Top](#customising-the-look-of-your-game)

## Play Mats
Mats are pictures laid flat under the areas. They're locked so they can't be
knocked around, and the outlines are drawn on top.

```lua
layout = {
  mats = {
    seat = { image = { White = "https://…/white.png", default = "https://…/mat.png" } },
    market = { image = "https://…/market.png" },
    extra = { { image = "https://…/logo.png", x = 0, z = 25, width = 12, depth = 6, yaw = 0 } },
    thickness = 0.1,
  },
  tableImage = "https://…/table.jpg",
},
```

- **`seat`:** a mat under each player's areas, with a `margin` (1) all round.
  It turns with the seat, so it reads the right way up for that player.
  `image` is one picture for everyone, or one per seat colour with a
  `default` for the rest. `width`, `depth`, `along` and `out` change its size
  and place. `label = true` (or `{ size = 60, color = "#FFFFFF" }`) writes
  each player's name on their mat.
- **`market`:** a mat under the market row and its piles. `x`, `z`, `width`,
  `depth` and `yaw` change it.
- **`extra`:** any number of other mats anywhere on the table.
- **`tableImage`:** the table's own picture, when the save uses TTS's custom
  table.

**Mats players choose.** Give `seat` (or `market`) a list of `sets` instead of
an `image`, and players pick with **Change mat**. Each set can come in
several `styles`, one picture each:

```lua
seat = {
  width = 22, depth = 22 * 1562 / 2048, -- the pictures' own shape, so they aren't stretched
  styles = { "Emblem", "Battle" },
  sets = {
    { name = "Blue Guild", color = "Blue", images = { "https://…/blue-emblem.jpg", "https://…/blue-battle.jpg" } },
    { name = "Red Guild", color = "Red", images = { "https://…/red-emblem.jpg", "https://…/red-battle.jpg" } },
  },
},
```

- Each player picks their own seat mat. A set's `color` makes it that seat
  colour's mat to start with; other seats start on the sets in order.
- The market mat is shared: any player can change it. It starts on the first
  set, or the one with `default = true`. Rename its menu rows with
  `ui.words.marketMat` and `ui.words.marketStyle`.
- Choices are saved with the game.
- Give `width` and `depth` in the pictures' own proportions: a mat is laid at
  exactly that size, so other proportions stretch the picture.

Mats are laid again when the number of players changes.

[Back to Top](#customising-the-look-of-your-game)

# Using Card Art You Already Have
`art.json` says which image sheet and slot each card's picture is in.
`make_sheets.py` writes one with placeholder art, but if your game already
has TTS card sheets (for example on Steam Cloud), write `art.json` yourself,
and don't run `make_sheets.py`: it would overwrite it.

```json
{
  "back": "https://steamusercontent-a.akamaihd.net/ugc/…/back/",
  "sheets": [
    { "file": "https://steamusercontent-a.akamaihd.net/ugc/…/sheet1/", "numWidth": 10, "numHeight": 7 },
    { "file": "https://…/sheet2/", "numWidth": 10, "numHeight": 7, "back": "https://…/other-back/" }
  ],
  "cards": {
    "apprentice": { "sheet": 1, "index": 0 },
    "squire": { "sheet": 1, "index": 1 }
  }
}
```

| Field | What it is |
| --- | --- |
| `back` | The card back. A sheet can set its own `back` |
| `sheets[n].file` | The sheet image: a full `https://` link, or a path added to `art.baseUrl` |
| `sheets[n].numWidth`, `numHeight` | How many cards across and down the sheet holds |
| `cards.<id>` | The card's sheet number (counting from 1) and slot (counting from 0, left to right, then down) |
| `hiddenFace` | What other players see of a card in your hand: `"back"` (default) shows the card back; `"last_slot"` shows the sheet's last slot, as TTS does when "Back is hidden" is off. Set it at the top or per sheet. With `"last_slot"`, no card may use that slot |

When the game loads, Cardalyzer checks `art.json` and lists any card with no
slot, a slot outside its sheet, or a card in a reserved last slot.

[Back to Top](#customising-the-look-of-your-game)
