-- Board: renders game state as physical TTS objects.
--
-- The state is the truth. Each pile (a deck, a hand, a market slot) is drawn
-- by destroying the objects it spawned last time and spawning fresh ones, so
-- a card a player dropped in the wrong place can never desync the game.
-- Spawned GUIDs are kept in state.view.piles so a reloaded save can clean up.
local Util = require("engine.util")
local State = require("engine.state")

local Board = {}

local FACE_DOWN = 180

---------------------------------------------------------------------------
-- Pure helpers (no TTS calls)
---------------------------------------------------------------------------

function Board.imageUrl(rules, file)
  if file:match("^https?://") then return file end
  return (rules.art and rules.art.baseUrl or "") .. file
end

-- A card's tooltip text. rules.ui.describeCard(game, card, text) may return
-- the game's own (`text` is the engine's).
function Board.describe(game, card)
  local text = Board.defaultDescription(game, card)
  local own = game.rules.ui and game.rules.ui.describeCard
  return own and own(game, card, text) or text
end

function Board.defaultDescription(game, card)
  local fx = game.effects
  local lines = {}
  local Cards = require("engine.cards")
  local def = Cards.typeDef(game.rules, card)
  local header = (def.defeat and "Defeat " or "Cost ") .. card.cost
  if card.faction ~= "none" then
    local names = {}
    for _, f in ipairs(card.factions) do names[#names + 1] = Util.titleCase(f) end
    header = header .. " · " .. table.concat(names, " / ")
  end
  local typeNames = {}
  for _, t in ipairs(Cards.typesOf(card)) do typeNames[#typeNames + 1] = Util.titleCase(t) end
  lines[#lines + 1] = header .. " · " .. table.concat(typeNames, " – ")
  if #card.effects > 0 then lines[#lines + 1] = fx:describe(card.effects, card.text) end
  if #card.allyEffects > 0 then
    lines[#lines + 1] = "Ally: " .. fx:describe(card.allyEffects, card.text)
  end
  if #card.scrapEffects > 0 then
    lines[#lines + 1] = "Scrap: " .. fx:describe(card.scrapEffects, card.text)
  end
  if card.nextEffects and #card.nextEffects > 0 then
    lines[#lines + 1] = "Next turn: " .. fx:describe(card.nextEffects, card.text)
  end
  if card.reactEffects and #card.reactEffects > 0 then
    lines[#lines + 1] = "Reaction: " .. fx:describe(card.reactEffects, card.text)
  end
  if card.defense then lines[#lines + 1] = "Defense " .. card.defense end
  if card.points and card.points ~= 0 then lines[#lines + 1] = card.points .. (card.points == 1 and " point" or " points") end
  if card.text ~= "" then lines[#lines + 1] = card.text end
  return table.concat(lines, "\n")
end

-- What other players see of a hidden card (one in someone's hand, or face
-- down): "back" shows the back image; "last_slot" shows the sheet's last
-- slot, which then can't hold a card. A sheet's setting overrides art.json's.
local function hiddenFace(art, sheet)
  return sheet.hiddenFace or art.hiddenFace or "back"
end

-- A sheet may set its own `back`; otherwise art.json's `back` is used.
local function customDeck(game, sheetNo)
  local rules, art = game.rules, game.art
  local sheet = art.sheets[sheetNo]
  return {
    FaceURL = Board.imageUrl(rules, sheet.file),
    BackURL = Board.imageUrl(rules, sheet.back or art.back),
    NumWidth = sheet.numWidth,
    NumHeight = sheet.numHeight,
    BackIsHidden = hiddenFace(art, sheet) == "back",
    UniqueBack = false,
    Type = 0,
  }
end

-- Problems with art.json for these cards, e.g. a card with no slot, a slot
-- outside its sheet, or a card in the slot reserved for the hidden face.
function Board.checkArt(art, cards)
  local problems = {}
  local function bad(msg) problems[#problems + 1] = "art.json: " .. msg end
  if type(art) ~= "table" or type(art.sheets) ~= "table" or type(art.cards) ~= "table" then
    bad("needs sheets and cards (run tools/make_sheets.py or write it by hand)")
    return problems
  end
  for i, sheet in ipairs(art.sheets) do
    if not sheet.file or not (sheet.back or art.back) then bad("sheet " .. i .. " needs a file and a back") end
    local hidden = hiddenFace(art, sheet)
    if hidden ~= "back" and hidden ~= "last_slot" then
      bad("sheet " .. i .. " hiddenFace must be \"back\" or \"last_slot\", got \"" .. tostring(hidden) .. "\"")
    end
  end
  for _, card in ipairs(cards.list) do
    local where = art.cards[card.id]
    local sheet = where and art.sheets[where.sheet]
    if not where then
      bad("card '" .. card.id .. "' has no entry in cards")
    elseif not sheet then
      bad("card '" .. card.id .. "' is on sheet " .. tostring(where.sheet) .. ", which isn't listed")
    else
      local slots = (sheet.numWidth or 0) * (sheet.numHeight or 0)
      if type(where.index) ~= "number" or where.index < 0 or where.index >= slots then
        bad("card '" .. card.id .. "' slot " .. tostring(where.index) .. " is outside sheet " .. where.sheet
          .. " (slots 0 to " .. (slots - 1) .. ")")
      elseif hiddenFace(art, sheet) == "last_slot" and where.index == slots - 1 then
        bad("card '" .. card.id .. "' is in sheet " .. where.sheet .. "'s last slot, which shows hidden cards")
      end
    end
  end
  return problems
end

local function transform(scale)
  return {
    posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0,
    scaleX = scale, scaleY = 1, scaleZ = scale,
  }
end

-- TTS object data for one card instance. GMNotes carries the uid so a
-- physical card can always be traced back to the state.
function Board.cardData(game, uid)
  local id = State.cardId(game.state, uid)
  local card = game.cards:get(id)
  local where = game.art.cards[id]
  if not where then error("card '" .. id .. "' has no art entry; run tools/make_sheets.py", 0) end
  local scale = (game.rules.layout and game.rules.layout.cardScale) or 1
  return {
    Name = "Card",
    Nickname = card.name,
    Description = Board.describe(game, card),
    GMNotes = uid,
    Tags = { "cz_card" },
    CardID = where.sheet * 100 + where.index,
    CustomDeck = { [where.sheet] = customDeck(game, where.sheet) },
    Transform = transform(scale),
  }
end

-- One object for a whole pile: a Card for one uid, a Deck for more.
-- Our piles keep the top card last; a TTS deck lists its top card first.
function Board.stackData(game, uids)
  if #uids == 1 then return Board.cardData(game, uids[1]) end
  local deck = {
    Name = "Deck",
    Tags = { "cz_card" },
    DeckIDs = {},
    CustomDeck = {},
    ContainedObjects = {},
    Transform = transform((game.rules.layout and game.rules.layout.cardScale) or 1),
  }
  for i = #uids, 1, -1 do
    local data = Board.cardData(game, uids[i])
    deck.DeckIDs[#deck.DeckIDs + 1] = data.CardID
    deck.ContainedObjects[#deck.ContainedObjects + 1] = data
    for k, v in pairs(data.CustomDeck) do deck.CustomDeck[k] = v end
  end
  return deck
end

-- Every pile the board draws: key -> { uids, spot, style, faceUp, buyable?, source? }.
-- style: "stack" (one deck object), "row" (cards side by side), "hand".
-- source: where a card new to this pile is dealt from when it has never
-- been drawn before (a hand from its deck, the market row from the market deck).
function Board.piles(game)
  local state, layout = game.state, game.layout
  local gap = (game.rules.layout and game.rules.layout.cardSpacing) or 2.8
  local cardWidth = 2.4 * ((game.rules.layout and game.rules.layout.cardScale) or 1)
  local list = {}
  -- Areas turned off in rules.layout.areas (spot.hidden) show no cards.
  local function add(key, uids, spot, style, faceUp, buyable, source)
    if spot.hidden then return end
    list[#list + 1] = { key = key, uids = uids, spot = spot, style = style, faceUp = faceUp, gap = gap,
      buyable = buyable, source = source, cardWidth = cardWidth }
  end
  for seat, p in ipairs(state.players) do
    local s = layout.seats[seat]
    add(seat .. ".deck", p.deck, s.deck, "stack", false)
    add(seat .. ".discard", p.discard, s.discard, "stack", true)
    -- cards kept from last turn (next_effects) sit at the start of the play row
    local played = {}
    for _, uid in ipairs(p.lasting or {}) do played[#played + 1] = uid end
    for _, uid in ipairs(p.play) do played[#played + 1] = uid end
    for _, a in ipairs(game.rules.areas or {}) do
      add(seat .. ".area." .. a.key, p.areas and p.areas[a.key] or {}, s.areas[a.key], "stack", true)
    end
    -- face-down cards (not yet revealed) sit first in the bases row, hidden
    -- from everyone but their owner
    local bases = {}
    for _, uid in ipairs(p.facedown or {}) do bases[#bases + 1] = uid end
    for _, uid in ipairs(p.bases) do bases[#bases + 1] = uid end
    if s.bases.hidden then
      -- no bases area: cards that stay in play sit at the end of the play row
      local both = {}
      for _, uid in ipairs(played) do both[#both + 1] = uid end
      for _, uid in ipairs(bases) do both[#both + 1] = uid end
      add(seat .. ".play", both, s.play, "row", true)
    else
      add(seat .. ".play", played, s.play, "row", true)
      add(seat .. ".bases", bases, s.bases, "row", true)
    end
    local holder = seat .. (s.bases.hidden and ".play" or ".bases")
    if p.facedown and #p.facedown > 0 and list[#list] and list[#list].key == holder then
      local secret = {}
      for _, uid in ipairs(p.facedown) do secret[uid] = p.color end
      list[#list].secret = secret
    end
    -- How far each card in play is turned: its type's playYaw (cards printed
    -- sideways, such as bases, read the right way up in play but not in the
    -- market), plus a quarter turn when used this round (a Use button),
    -- unless rules.ui.turnUsedCards = false.
    local turnUsed = not (game.rules.ui and game.rules.ui.turnUsedCards == false)
    for _, pile in ipairs(list) do
      if pile.key == seat .. ".play" or pile.key == seat .. ".bases" then
        local turned = nil
        for _, uid in ipairs(pile.uids) do
          local def = require("engine.cards").typeDef(game.rules, game.cards:get(State.cardId(state, uid)))
          local deg = (def.playYaw or 0) + (turnUsed and p.exhausted and p.exhausted[uid] and 90 or 0)
          if deg % 360 ~= 0 then
            turned = turned or {}
            turned[uid] = deg % 360
          end
        end
        pile.turned = turned
      end
    end
    add(seat .. ".hand", p.hand, s.hand, "hand", true, nil, s.deck.position)
  end
  -- The market's cards face the player whose turn it is, so they always read
  -- the right way up for them (rules.market.faceActive = false keeps them
  -- facing seat 1).
  local m = state.market
  local yaw = Board.marketYaw(game)
  local function facing(spot)
    return { position = spot.position, rotation = { 0, yaw, 0 }, right = spot.right, forward = spot.forward, size = spot.size,
      hidden = spot.hidden }
  end
  local first = #list + 1
  add("market.deck", m.deck, facing(layout.market.deck), "stack", false)
  for i, uid in ipairs(m.row) do
    add("market.row." .. i, uid == State.EMPTY and {} or { uid }, facing(layout.market.row[i]), "stack", true, true,
      layout.market.deck.position)
  end
  for _, id in ipairs(game.fixedIds) do
    add("fixed." .. id, m.fixed[id] or {}, facing(layout.market.fixed[id]), "stack", true, true)
  end
  add("market.scrap", m.scrap, facing(layout.market.scrap), "stack", true)
  -- extra markets (rules.markets): "market.deck.<key>", "market.row.<key>.<i>"
  for _, extra in ipairs(state.markets or {}) do
    local spots = layout.markets and layout.markets[extra.key]
    if spots then
      add("market.deck." .. extra.key, extra.deck, facing(spots.deck), "stack", false)
      for i, uid in ipairs(extra.row) do
        add("market.row." .. extra.key .. "." .. i, uid == State.EMPTY and {} or { uid }, facing(spots.row[i]), "stack", true, true,
          spots.deck.position)
      end
    end
  end
  for i = first, #list do list[i].facing = yaw end
  return list
end

-- The yaw the market's cards use: the card yaw of the active player's seat.
function Board.marketYaw(game)
  local seat = 1
  if game.rules.market.faceActive ~= false and game.state.started then seat = game.state.turn.active end
  local s = game.layout.seats[seat] or game.layout.seats[1]
  return s.play.rotation[2]
end

-- Positions for n cards laid side by side, centred on the spot.
-- With `cardWidth`, a row that would run past its spot's width closes up to
-- fit: the cards overlap, each a little higher than the last so they rest on
-- one another instead of colliding.
function Board.rowPositions(spot, n, gap, cardWidth, sideways)
  local rx, rz = spot.right[1], spot.right[2]
  local length = spot.size and spot.size[1]
  if spot.column then
    -- a column (rules.layout.areas.x.column): cards run down the area, from
    -- the table centre toward the player, a card's depth apart
    rx, rz = -spot.forward[1], -spot.forward[2]
    length = spot.size and spot.size[3]
    -- (cards all lying sideways take up only their width)
    if not sideways then cardWidth = cardWidth and cardWidth * 3.4 / 2.4 end
    gap = (cardWidth or (sideways and 2.4 or 3.4)) + 0.4
  end
  if cardWidth and length and n > 1 then
    local fit = (length - cardWidth) / (n - 1)
    if fit < gap then gap = math.max(fit, cardWidth * 0.2) end
  end
  local rise = (cardWidth and gap < cardWidth) and 0.05 or 0
  local out = {}
  for i = 1, n do
    local along = (i - (n + 1) / 2) * gap
    out[i] = { spot.position[1] + rx * along, spot.position[2] + (i - 1) * rise, spot.position[3] + rz * along }
  end
  return out
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

-- Cards use the spot's own yaw, except in a hand, whose zone faces the seat
-- but whose cards still need the card yaw (see Zones.layout).
local function rotation(spot, faceUp)
  local yaw = (spot.cardRotation or spot.rotation)[2]
  return { 0, yaw, faceUp and 0 or FACE_DOWN }
end

-- Buy button on a market card or fixed pile; clicks go to Cardalyzer_onBuy in main.lua.
-- The Buy button on market cards. rules.ui.buyButton changes its look:
-- { color, textColor ("#RRGGBB" or {r, g, b, a}), fontSize, width, height,
--   position = {x, y, z} on the card }. Its label is the "buy" word, or the
-- "defeat" word for a card to defeat (a type with defeat = true).
-- A card to hire (a type with hire = true) also gets a Hire button at the
-- other end of the card (click: Cardalyzer_onHire).
local function addBuyButton(game, obj, cost, word, hire)
  local look = game.rules.ui and game.rules.ui.buyButton or {}
  local position = look.position or { 0, 0.6, 1.7 }
  if hire then
    obj.createButton({
      click_function = "Cardalyzer_onHire",
      function_owner = Global,
      label = require("engine.words").say(game.rules, "hire", { n = cost }),
      position = { position[1], position[2], -position[3] },
      width = look.width or 900, height = look.height or 260, font_size = look.fontSize or 150,
      color = Util.color(look.color) or { 0.1, 0.1, 0.1, 0.9 },
      font_color = Util.color(look.textColor) or { 1, 0.85, 0.35 },
    })
  end
  obj.createButton({
    click_function = "Cardalyzer_onBuy",
    function_owner = Global,
    label = require("engine.words").say(game.rules, word or "buy", { n = cost }),
    position = position,
    width = look.width or 900, height = look.height or 260, font_size = look.fontSize or 150,
    color = Util.color(look.color) or { 0.1, 0.1, 0.1, 0.9 },
    font_color = Util.color(look.textColor) or { 1, 0.85, 0.35 },
  })
end

-- The Scrap button on a card in play with a scrap ability: the scrap symbol
-- (theme symbols, "scrap") stuck on the card, with a clear button over it
-- (Cardalyzer_onScrapIcon). rules.ui.scrapButton: false for none (Scrap
-- buttons go in the action bar instead), or
--   size    the symbol's width in table units, the same on every card (0.38)
--   corner  where the symbol's top-right corner goes, as fractions of the
--           printed card from its left and top edges: { right, top }
--           (default near the bottom-left corner, hanging a little over)
-- A card type's scrapCorner = { right, top } overrides corner for its cards
-- (a game whose bases print the scrap symbol somewhere else); it can also be
-- function(card) returning one (cards of one type printed differently by set). "Printed"
-- means as the card reads: a type turned by playYaw (printed sideways)
-- counts its left and top as they read in play.
Board.CARD_W, Board.CARD_H = 2.19, 3.06
function Board.addScrapButton(game, obj, uid)
  local look = game.rules.ui and game.rules.ui.scrapButton
  if look == false then return end
  look = type(look) == "table" and look or {}
  local c = game:cardOf(uid)
  if not c or #c.scrapEffects == 0 then return end
  local def = require("engine.cards").typeDef(game.rules, c)
  local yaw = (def.playYaw or 0) % 360
  local turned = yaw == 90 or yaw == 270
  local size = look.size or 0.38
  local w, h = Board.CARD_W, Board.CARD_H
  if turned then w, h = h, w end -- the printed card's width and height
  local corner = def.scrapCorner
  if type(corner) == "function" then corner = corner(c) end
  corner = corner or look.corner or { right = (size - 0.05) / w, top = 1 - (size - 0.05) / h }
  -- the symbol's centre, measured from the printed card's left and top
  local across = corner.right * w - size / 2
  local down = corner.top * h + size / 2
  -- to the card object's own position: +x is its left, +z its bottom
  local x, z
  if turned then
    x, z = Board.CARD_W / 2 - down, Board.CARD_H / 2 - across
  else
    x, z = Board.CARD_W / 2 - across, down - Board.CARD_H / 2
  end
  if yaw == 180 or yaw == 270 then x, z = -x, -z end
  -- the symbol turns with the print, so it reads upright
  obj.setDecals({ { name = "cz_scrap", url = require("engine.ui").symbolUrl(game.rules, "scrap"),
    position = { x, 0.25, z }, rotation = { 90, (180 - yaw) % 360, 0 }, scale = { size, size, 1 } } })
  local words = require("engine.words")
  obj.createButton({
    click_function = "Cardalyzer_onScrapIcon", function_owner = Global, label = "",
    position = { -x, 0.3, z }, width = math.floor(size * 470), height = math.floor(size * 470),
    color = { 0, 0, 0, 0 }, hover_color = { 1, 1, 1, 0.25 }, press_color = { 1, 1, 1, 0.45 },
    tooltip = words.say(game.rules, "scrap", { card = c.name, effects = game.effects:describe(c.scrapEffects, c.text) }),
  })
end

-- onReady(obj) runs once TTS has finished spawning the object.
local function spawn(game, data, position, rot, onReady)
  local obj = spawnObjectData({
    data = data, position = position, rotation = rot, callback_function = onReady,
  })
  return obj.getGUID()
end

-- Destroys the objects a pile spawned last time.
local function destroyObjects(game, key)
  local guids = game.state.view.piles[key]
  if guids then
    for _, guid in ipairs(guids) do
      local obj = getObjectFromGUID(guid)
      if obj then obj.destruct() end
    end
  end
  game.state.view.piles[key] = nil
end

function Board.clearPile(game, key)
  destroyObjects(game, key)
  game.state.view.sig[key] = nil
end

-- A pile's signature: its uids in order. Unchanged signature = nothing to redraw.
local function signature(uids, turned, secret)
  if (not turned or not next(turned)) and not secret then return table.concat(uids, ",") end
  local parts = {}
  for i, uid in ipairs(uids) do
    parts[i] = (turned and turned[uid] and (uid .. "*" .. turned[uid]) or uid) .. (secret and secret[uid] and "~" or "")
  end
  return table.concat(parts, ",")
end

-- Every player colour but the owner's (and the GM's): who mustn't see a
-- face-down card. TTS shows them its hidden face, as for a card in a hand.
local COLORS = { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Grey" }
local function hideFrom(obj, owner)
  local others = {}
  for _, c in ipairs(COLORS) do if c ~= owner then others[#others + 1] = c end end
  obj.setHiddenFrom(others)
end

-- Whether every card of a pile lies sideways (a quarter turn either way).
local function sideways(pile, uids)
  if not pile.turned or #uids == 0 then return false end
  for _, uid in ipairs(uids) do
    if (pile.turned[uid] or 0) % 180 ~= 90 then return false end
  end
  return true
end

local function rowGap(pile)
  return pile.style == "hand" and pile.gap * 0.8 or pile.gap
end

-- Where each of a pile's cards sits on the table, in uid order. Hand cards
-- count as sitting at the hand's landing spot, just in front of the hand
-- zone, so a card leaving a hand starts its flight outside the zone.
local function places(pile, uids)
  local out = {}
  if pile.style == "stack" then
    for i = 1, #uids do out[i] = pile.spot.position end
  elseif pile.style == "hand" then
    for i = 1, #uids do out[i] = pile.spot.landing or pile.spot.position end
  else
    out = Board.rowPositions(pile.spot, #uids, rowGap(pile), pile.cardWidth, sideways(pile, uids))
  end
  return out
end

-- Spawns the objects for `uids` in a pile's spot, replacing the pile's old
-- objects, and remembers where each card now is (view.at) so its next move
-- can start from there.
--
-- The old objects stay until every new one has finished spawning (TTS takes a
-- few frames to show a new object), so a pile never blinks out while it is
-- redrawn. Outside a hand the new objects spawn locked, so they don't knock
-- into the old ones while both are there, and unlock once those are gone.
-- (Hand cards spawn unlocked: a hand zone may not take in a locked card.)
local function draw(game, pile, uids)
  local view = game.state.view
  local old = view.piles[pile.key] or {}
  local function removeOld()
    for _, guid in ipairs(old) do
      local obj = getObjectFromGUID(guid)
      if obj then obj.destruct() end
    end
  end
  local n = #uids
  view.piles[pile.key] = {}
  for i, at in ipairs(places(pile, uids)) do view.at[uids[i]] = at end
  if n == 0 then return removeOld() end

  local lock = pile.style ~= "hand"
  local cost, word, hire = nil, nil, nil
  if pile.buyable and pile.style == "stack" then
    local top = game.cards:get(State.cardId(game.state, uids[n]))
    local def = require("engine.cards").typeDef(game.rules, top)
    cost = top.cost
    word = def.defeat and "defeat" or "buy"
    hire = def.hire and pile.key:find("^market%.row") ~= nil
  end
  local waiting, readied = (pile.style == "stack") and 1 or n, {}
  local inPlay = pile.style == "row" and (pile.key:find("^%d+%.play$") or pile.key:find("^%d+%.bases$"))
  local function ready(obj)
    if cost then addBuyButton(game, obj, cost, word, hire) end
    local uid = inPlay and obj.getGMNotes()
    if uid and not (pile.secret and pile.secret[uid]) then Board.addScrapButton(game, obj, uid) end
    readied[#readied + 1] = obj
    if #readied == waiting then
      removeOld()
      if lock then for _, o in ipairs(readied) do o.setLock(false) end end
    end
  end
  local function data(d)
    d.Locked = lock
    return d
  end

  local guids = view.piles[pile.key]
  local rot = rotation(pile.spot, pile.faceUp)
  if pile.style == "stack" then
    guids[1] = spawn(game, data(Board.stackData(game, uids)), pile.spot.position, rot, ready)
  else
    local positions = Board.rowPositions(pile.spot, n, rowGap(pile), pile.style == "row" and pile.cardWidth or nil,
      sideways(pile, uids))
    for i, uid in ipairs(uids) do
      local r = rot
      if pile.turned and pile.turned[uid] then r = { rot[1], (rot[2] + pile.turned[uid]) % 360, rot[3] } end
      guids[i] = spawn(game, data(Board.cardData(game, uid)), positions[i], r, ready)
      if pile.secret and pile.secret[uid] then
        local obj = getObjectFromGUID(guids[i])
        if obj then hideFrom(obj, pile.secret[uid]) end
      end
    end
  end
end

function Board.renderPile(game, pile)
  game.state.view.at = game.state.view.at or {}
  draw(game, pile, pile.uids)
  game.state.view.sig[pile.key] = signature(pile.uids, pile.turned, pile.secret)
end

-- Animation timing in seconds. rules.animate = false turns animation off;
-- rules.animation = { stagger, linger, lift } changes these (TRAVEL is how
-- long TTS itself takes to move a card, so it can't be changed).
Board.TRAVEL = 0.45 -- one card's flight
Board.STAGGER = 0.12 -- gap between cards dealt one after another
Board.LINGER = 0.4 -- a landed card stays this long, until the real card has appeared under it
Board.LIFT = 1.2 -- cards fly this far above the table
local function timing(game, key, default)
  local a = game.rules.animation
  return a and a[key] or default
end

-- Runs fn after `delay` seconds (straight away for no delay).
local function after(delay, fn)
  if delay > 0 then Wait.time(fn, delay) else fn() end
end

-- A short-lived copy of a card that flies from one place to another. It's
-- locked and can't be picked up. When it lands the pile draws the real card
-- beneath it, and the copy is removed a moment later, once that has appeared.
local function fly(game, uid, from, to, rot, delay, owner)
  after(delay, function()
    local obj = spawnObjectData({
      data = Board.cardData(game, uid),
      position = { from[1], from[2] + timing(game, "lift", Board.LIFT), from[3] },
      rotation = rot,
    })
    if owner then hideFrom(obj, owner) end
    obj.setLock(true)
    obj.interactable = false
    obj.setPositionSmooth({ to[1], to[2] + timing(game, "lift", Board.LIFT) * 0.4, to[3] }, false, true)
    local guid = obj.getGUID()
    after(Board.TRAVEL + timing(game, "linger", Board.LINGER), function()
      local landed = getObjectFromGUID(guid)
      if landed then landed.destruct() end
    end)
  end)
end

-- Redraws only the piles whose contents changed since they were last drawn.
-- A card new to a pile flies there from where it was last drawn (or from the
-- pile's source when it has never been drawn, e.g. a hand being dealt from
-- its deck); the pile shows it once it lands. Cards flown in one sync go one
-- after another, like dealing. Cards flying to a hand are face down.
-- opts.instant draws everything straight away (Tidy table).
function Board.sync(game, opts)
  local view = game.state.view
  view.at, view.gen = view.at or {}, view.gen or {}
  local animate = game.rules.animate ~= false and not (opts and opts.instant)
  local dealt = 0
  view.facing = view.facing or {}
  for _, pile in ipairs(Board.piles(game)) do
    local key = pile.key
    local sig = signature(pile.uids, pile.turned, pile.secret)
    local old = view.sig[key]
    -- Same cards, but the pile itself moved (the market turning to face a new
    -- player): glide its objects to the new spot.
    view.spotAt = view.spotAt or {}
    local where = string.format("%.2f,%.2f", pile.spot.position[1], pile.spot.position[3])
    local moved = old == sig and view.spotAt[key] and view.spotAt[key] ~= where
    view.spotAt[key] = where
    if moved then
      local targets = places(pile, pile.uids)
      for _, guid in ipairs(view.piles[key] or {}) do
        local obj = getObjectFromGUID(guid)
        if obj then
          local to = targets[#targets] or pile.spot.position
          obj.setPositionSmooth({ to[1], to[2], to[3] }, false, false)
        end
      end
      for i, uid in ipairs(pile.uids) do view.at[uid] = targets[i] end
    end
    if old == sig and pile.facing and view.facing[key] ~= pile.facing then
      -- Same cards, new reader: turn them in place.
      for _, guid in ipairs(view.piles[key] or {}) do
        local obj = getObjectFromGUID(guid)
        if obj then obj.setRotationSmooth(rotation(pile.spot, pile.faceUp), false, false) end
      end
    end
    view.facing[key] = pile.facing
    if old ~= sig then
      -- Bumping the pile's generation cancels a draw still waiting on an earlier flight.
      view.gen[key] = (view.gen[key] or 0) + 1
      view.sig[key] = sig
      local before, beforeCount = {}, 0
      for uid in (old or ""):gmatch("[^,]+") do before[uid] = true; beforeCount = beforeCount + 1 end
      local uids, staying, arriving = {}, {}, {}
      for i, uid in ipairs(pile.uids) do
        uids[i] = uid
        if before[uid] then staying[#staying + 1] = uid else arriving[#arriving + 1] = i end
      end

      local flights = {}
      if animate then
        local targets = places(pile, uids)
        for _, i in ipairs(arriving) do
          local from = view.at[uids[i]] or pile.source
          if from then flights[#flights + 1] = { uid = uids[i], from = from, to = targets[i] } end
        end
      end

      if #flights == 0 then
        draw(game, pile, uids)
      else
        -- Show what stayed now (if anything left); the rest once it lands.
        if #staying < beforeCount then draw(game, pile, staying) end
        local rot = rotation(pile.spot, pile.faceUp and pile.style ~= "hand")
        local landed = 0
        for _, f in ipairs(flights) do
          local delay = dealt * timing(game, "stagger", Board.STAGGER)
          dealt = dealt + 1
          fly(game, f.uid, f.from, f.to, rot, delay, pile.secret and pile.secret[f.uid])
          view.at[f.uid] = f.to
          landed = math.max(landed, delay + Board.TRAVEL)
        end
        local gen = view.gen[key]
        after(landed, function()
          if view.gen[key] == gen then draw(game, pile, uids) end
        end)
      end
    end
  end
end

-- The pile key ("fixed.hireling") that spawned the object with this GUID.
function Board.pileOf(game, guid)
  for key, guids in pairs(game.state.view.piles) do
    for _, g in ipairs(guids) do
      if g == guid then return key end
    end
  end
  return nil
end

-- Destroys every card the engine ever spawned, including strays that were
-- merged into other decks by physics and lost their tracked GUID.
-- Signatures are cleared, so the next sync redraws every pile and cancels
-- any draw still waiting on a flight (generations keep counting up).
function Board.sweep(game)
  for _, obj in ipairs(getObjectsWithTag("cz_card")) do obj.destruct() end
  game.state.view.piles = {}
  game.state.view.sig = {}
end

-- Draws one pile again from the state, straight away, and removes stray
-- copies of its cards: a card pulled off one of its decks by hand, or the
-- last card TTS leaves behind when a two-card deck is split.
function Board.redraw(game, key)
  for _, pile in ipairs(Board.piles(game)) do
    if pile.key == key then
      local mine, tracked = {}, {}
      for _, uid in ipairs(pile.uids) do mine[uid] = true end
      for _, guids in pairs(game.state.view.piles) do
        for _, g in ipairs(guids) do tracked[g] = true end
      end
      for _, obj in ipairs(getObjectsWithTag("cz_card")) do
        if not tracked[obj.getGUID()] and not obj.getLock() and mine[obj.getGMNotes()] then obj.destruct() end
      end
      Board.renderPile(game, pile)
      return
    end
  end
end

-- Forgets where cards were drawn, for a new game whose uids start again.
function Board.forgetPlaces(game)
  game.state.view.at = {}
end

return Board
