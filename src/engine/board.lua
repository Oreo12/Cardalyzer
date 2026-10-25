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

function Board.describe(game, card)
  local fx = game.effects
  local lines = {}
  local header = "Cost " .. card.cost
  if card.faction ~= "none" then header = header .. " · " .. Util.titleCase(card.faction) end
  lines[#lines + 1] = header .. " · " .. Util.titleCase(card.type)
  if #card.effects > 0 then lines[#lines + 1] = fx:describe(card.effects, card.text) end
  if #card.allyEffects > 0 then
    lines[#lines + 1] = "Ally: " .. fx:describe(card.allyEffects, card.text)
  end
  if #card.scrapEffects > 0 then
    lines[#lines + 1] = "Scrap: " .. fx:describe(card.scrapEffects, card.text)
  end
  if card.defense then lines[#lines + 1] = "Defense " .. card.defense end
  if card.text ~= "" then lines[#lines + 1] = card.text end
  return table.concat(lines, "\n")
end

local function customDeck(game, sheetNo)
  local rules, art = game.rules, game.art
  local sheet = art.sheets[sheetNo]
  return {
    FaceURL = Board.imageUrl(rules, sheet.file),
    BackURL = Board.imageUrl(rules, art.back),
    NumWidth = sheet.numWidth,
    NumHeight = sheet.numHeight,
    BackIsHidden = true,
    UniqueBack = false,
    Type = 0,
  }
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
    Tags = { "dbe_card" },
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
    Tags = { "dbe_card" },
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

-- Every pile the board draws: key -> { uids, spot, style, faceUp }.
-- style: "stack" (one deck object), "row" (cards side by side), "hand".
function Board.piles(game)
  local state, layout = game.state, game.layout
  local gap = (game.rules.layout and game.rules.layout.cardSpacing) or 2.8
  local list = {}
  local function add(key, uids, spot, style, faceUp)
    list[#list + 1] = { key = key, uids = uids, spot = spot, style = style, faceUp = faceUp, gap = gap }
  end
  for seat, p in ipairs(state.players) do
    local s = layout.seats[seat]
    add(seat .. ".deck", p.deck, s.deck, "stack", false)
    add(seat .. ".discard", p.discard, s.discard, "stack", true)
    add(seat .. ".play", p.play, s.play, "row", true)
    add(seat .. ".bases", p.bases, s.bases, "row", true)
    add(seat .. ".hand", p.hand, s.hand, "hand", true)
  end
  local m = state.market
  add("market.deck", m.deck, layout.market.deck, "stack", false)
  for i, uid in ipairs(m.row) do
    add("market.row." .. i, uid == State.EMPTY and {} or { uid }, layout.market.row[i], "stack", true)
  end
  for _, id in ipairs(game.fixedIds) do
    add("fixed." .. id, m.fixed[id] or {}, layout.market.fixed[id], "stack", true)
  end
  add("market.scrap", m.scrap, layout.market.scrap, "stack", true)
  return list
end

-- Positions for n cards laid side by side, centred on the spot.
function Board.rowPositions(spot, n, gap)
  local rx, rz = spot.right[1], spot.right[2]
  local out = {}
  for i = 1, n do
    local along = (i - (n + 1) / 2) * gap
    out[i] = { spot.position[1] + rx * along, spot.position[2], spot.position[3] + rz * along }
  end
  return out
end

---------------------------------------------------------------------------
-- TTS side
---------------------------------------------------------------------------

local function rotation(spot, faceUp)
  return { 0, spot.rotation[2], faceUp and 0 or FACE_DOWN }
end

local function spawn(game, data, position, rot)
  local obj = spawnObjectData({ data = data, position = position, rotation = rot })
  return obj.getGUID()
end

function Board.clearPile(game, key)
  local guids = game.state.view.piles[key]
  if not guids then return end
  for _, guid in ipairs(guids) do
    local obj = getObjectFromGUID(guid)
    if obj then obj.destruct() end
  end
  game.state.view.piles[key] = nil
end

function Board.renderPile(game, pile)
  Board.clearPile(game, pile.key)
  local guids = {}
  local n = #pile.uids
  if n > 0 then
    local rot = rotation(pile.spot, pile.faceUp)
    if pile.style == "stack" then
      guids[1] = spawn(game, Board.stackData(game, pile.uids), pile.spot.position, rot)
    else
      local gap = pile.style == "hand" and pile.gap * 0.8 or pile.gap
      local positions = Board.rowPositions(pile.spot, n, gap)
      for i, uid in ipairs(pile.uids) do
        guids[i] = spawn(game, Board.cardData(game, uid), positions[i], rot)
      end
    end
  end
  game.state.view.piles[pile.key] = guids
end

-- Redraws the piles whose key starts with one of the given prefixes, or
-- every pile when `prefixes` is nil. Example: Board.render(game, {"1.", "market."}).
function Board.render(game, prefixes)
  for _, pile in ipairs(Board.piles(game)) do
    local match = prefixes == nil
    for _, prefix in ipairs(prefixes or {}) do
      if pile.key:sub(1, #prefix) == prefix then match = true end
    end
    if match then Board.renderPile(game, pile) end
  end
end

-- Destroys every card the engine ever spawned, including strays that were
-- merged into other decks by physics and lost their tracked GUID.
function Board.sweep(game)
  for _, obj in ipairs(getObjectsWithTag("dbe_card")) do obj.destruct() end
  game.state.view.piles = {}
end

return Board
