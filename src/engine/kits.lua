-- Kits: each player's own starting pack (rules.kits), chosen per player.
--
-- With Starting decks set to the kit option in the New Game menu, every
-- player picks theirs in a kit menu: a premade kit, a random premade one, or
-- a custom kit mixed from the premade kits' parts (rules.kitParts). Choices
-- are kept per colour in state.view.setup.kitChoice:
--   { mode = "premade", kit = "<key>" }
--   { mode = "random" }   (also anyone who never picks)
--   { mode = "custom", parts = { [partKey] = "<kit key>" or { "<card id>", ... } } }
--
-- rules.kitParts lists what a custom kit is made of. Each part takes cards of
-- one `deck` (and `type`, if given) from the kits' sets:
--   by = "kit": pick which kit supplies this part (all its matching cards).
--     `stats = true` also brings that kit's stats and hand size.
--   count = n: pick n single cards from every kit's matching cards.
-- Without kitParts there's no custom option.
local Util = require("engine.util")
local Board = require("engine.board")

local Kits = {}

function Kits.byKey(rules, key)
  for _, kit in ipairs(rules.kits or {}) do
    if kit.key == key then return kit end
  end
  return nil
end

-- A colour's saved choice (random until they pick).
function Kits.choiceOf(game, color)
  local all = game.state.view.setup and game.state.view.setup.kitChoice
  return all and all[color] or { mode = "random" }
end

-- Cards of a kit's set in `deck`, of `cardType` if given.
function Kits.cardsOf(game, kit, deck, cardType)
  local out = {}
  for _, card in ipairs(game.cards:inDeck(deck)) do
    if card.set == kit.set and (not cardType or card.type == cardType) then out[#out + 1] = card end
  end
  return out
end

local function names(list)
  local out = {}
  for _, card in ipairs(list) do out[#out + 1] = (card.copies > 1 and (card.copies .. " ") or "") .. card.name end
  return table.concat(out, ", ")
end

-- A premade kit in a sentence: stats, hand size and every card it brings.
function Kits.describe(game, kit)
  local parts = {}
  if kit.handSize then parts[#parts + 1] = "Hand size " .. kit.handSize end
  for key, value in pairs(kit.stats or {}) do
    local label = key
    for _, st in ipairs(game.rules.stats or {}) do
      if st.key == key then label = st.label or key end
    end
    parts[#parts + 1] = "starts with " .. value .. " " .. label
  end
  local lines = { table.concat(parts, ", ") .. "." }
  local dealt, market = Kits.cardsOf(game, kit, "dealt"), Kits.cardsOf(game, kit, "market")
  if #dealt > 0 then lines[#lines + 1] = "In play: " .. names(dealt) .. "." end
  lines[#lines + 1] = "Starting cards: " .. names(Kits.cardsOf(game, kit, "starter")) .. "."
  if #market > 0 then lines[#lines + 1] = "Adds to the market: " .. names(market) .. "." end
  return table.concat(lines, "\n")
end

-- The choices for part i of rules.kitParts: { { value, label, tooltip } }.
function Kits.partOptions(game, part)
  local out = {}
  for _, kit in ipairs(game.rules.kits or {}) do
    local cards = Kits.cardsOf(game, kit, part.deck, part.type)
    if part.by == "kit" then
      if #cards > 0 then
        local tip = names(cards)
        if part.stats then
          tip = tip .. ". Hand size " .. (kit.handSize or game.rules.handSize)
          for key, value in pairs(kit.stats or {}) do tip = tip .. ", " .. value .. " " .. Util.titleCase(key) end
        end
        -- one card (a leader): its name; several: the kit's name
        out[#out + 1] = { value = kit.key, label = #cards == 1 and cards[1].name or kit.label, tooltip = tip }
      end
    else
      for _, card in ipairs(cards) do
        out[#out + 1] = { value = card.id, label = card.name, tooltip = Board.describe(game, card) }
      end
    end
  end
  return out
end

-- Fills in a custom choice's missing parts at random.
local function completed(game, parts, random)
  local out = {}
  for _, part in ipairs(game.rules.kitParts or {}) do
    local options = Kits.partOptions(game, part)
    local value = parts and parts[part.key]
    if part.by == "kit" then
      out[part.key] = value or (#options > 0 and options[math.floor(random() * #options) + 1].value)
    else
      local picked, taken = {}, {}
      for _, id in ipairs(value or {}) do picked[#picked + 1] = id; taken[id] = true end
      local pool = {}
      for _, o in ipairs(options) do if not taken[o.value] then pool[#pool + 1] = o.value end end
      Util.shuffle(pool, random)
      while #picked < (part.count or 1) and #pool > 0 do picked[#picked + 1] = table.remove(pool) end
      out[part.key] = picked
    end
  end
  return out
end

-- The kit Turn.setup deals for a premade kit: its cards as id lists.
function Kits.premade(game, kit)
  local function ids(deck)
    local out = {}
    for _, card in ipairs(Kits.cardsOf(game, kit, deck)) do out[#out + 1] = card.id end
    return out
  end
  return { key = kit.key, label = kit.label, starters = ids("starter"), dealt = ids("dealt"), market = ids("market"),
    stats = kit.stats, handSize = kit.handSize }
end

-- The kit Turn.setup deals for a custom choice.
function Kits.custom(game, parts, random)
  parts = completed(game, parts, random)
  local kit = { key = "custom", label = "Custom", starters = {}, dealt = {}, market = {} }
  local into = { starter = kit.starters, dealt = kit.dealt, market = kit.market }
  for _, part in ipairs(game.rules.kitParts or {}) do
    local list = into[part.deck]
    if part.by == "kit" then
      local source = Kits.byKey(game.rules, parts[part.key])
      if source then
        for _, card in ipairs(Kits.cardsOf(game, source, part.deck, part.type)) do list[#list + 1] = card.id end
        if part.stats then kit.stats, kit.handSize = source.stats, source.handSize end
      end
    else
      for _, id in ipairs(parts[part.key]) do list[#list + 1] = id end
    end
  end
  return kit
end

-- Kits for the next game, { [seat] = kit }, from each seat colour's choice.
-- Random players get premade kits nobody picked, while there are any.
function Kits.forSeats(game, count)
  local rules = game.rules
  if not rules.kits or #rules.kits == 0 then return nil end
  local out, taken, random = {}, {}, {}
  for seat = 1, count do
    local color = rules.seats[seat].color
    local choice = Kits.choiceOf(game, color)
    local kit = choice.mode == "premade" and Kits.byKey(rules, choice.kit)
    if kit then
      out[seat] = Kits.premade(game, kit)
      taken[kit.key] = true
    elseif choice.mode == "custom" and rules.kitParts then
      out[seat] = Kits.custom(game, choice.parts, game.random)
    else
      random[#random + 1] = seat
    end
  end
  local free = {}
  for _, kit in ipairs(rules.kits) do if not taken[kit.key] then free[#free + 1] = kit end end
  Util.shuffle(free, game.random)
  for _, seat in ipairs(random) do
    local kit = table.remove(free) or rules.kits[math.floor(game.random() * #rules.kits) + 1]
    out[seat] = Kits.premade(game, kit)
  end
  return out
end

-- The sets a choice needs switched on: rules.kitRequires for any kit, plus
-- each kit's own `requires` (every kit a custom one draws from).
function Kits.requiredSets(game, choice)
  local out = {}
  for _, key in ipairs(game.rules.kitRequires or {}) do out[#out + 1] = key end
  local function from(kit)
    for _, key in ipairs(kit and kit.requires or {}) do out[#out + 1] = key end
  end
  if choice.mode == "premade" then from(Kits.byKey(game.rules, choice.kit)) end
  if choice.mode == "custom" then
    for _, value in pairs(choice.parts or {}) do
      if type(value) == "string" then from(Kits.byKey(game.rules, value)) end
    end
  end
  return out
end

-- A short summary of a choice for menus: "The Union", "Random", "Custom".
function Kits.summary(game, choice)
  if choice.mode == "premade" then
    local kit = Kits.byKey(game.rules, choice.kit)
    return kit and kit.label or "Random"
  end
  return choice.mode == "custom" and "Custom" or "Random"
end

---------------------------------------------------------------------------
-- The kit menu: each player edits a draft of their choice (not saved until
-- they press Save), held on the game as kitMenuOpen[color].
---------------------------------------------------------------------------

local function copy(choice)
  local out = { mode = choice.mode, kit = choice.kit, parts = {} }
  for key, value in pairs(choice.parts or {}) do
    if type(value) == "table" then
      local list = {}
      for i, v in ipairs(value) do list[i] = v end
      out.parts[key] = list
    else
      out.parts[key] = value
    end
  end
  return out
end

function Kits.open(game, color)
  game.kitMenuOpen = game.kitMenuOpen or {}
  game.kitMenuOpen[color] = copy(Kits.choiceOf(game, color))
end

function Kits.close(game, color)
  if game.kitMenuOpen then game.kitMenuOpen[color] = nil end
end

function Kits.draft(game, color)
  return game.kitMenuOpen and game.kitMenuOpen[color]
end

-- Changes the draft: mode ("premade", "random", "custom"), a premade kit, or
-- a custom part (by kit: its kit key; by card: toggles the card, dropping the
-- oldest pick when the part is full).
function Kits.edit(game, color, what, value)
  local draft = Kits.draft(game, color)
  if not draft then return false, "Open the menu first." end
  if what == "mode" then
    if value ~= "premade" and value ~= "random" and value ~= "custom" then return false, "Unknown choice." end
    if value == "custom" and not game.rules.kitParts then return false, "These rules have no custom option." end
    draft.mode = value
    if value == "premade" and not draft.kit then draft.kit = game.rules.kits[1].key end
    return true
  end
  if what == "kit" then
    if not Kits.byKey(game.rules, value) then return false, "Unknown choice." end
    draft.mode, draft.kit = "premade", value
    return true
  end
  local part = (game.rules.kitParts or {})[tonumber(what) or 0]
  if not part then return false, "Unknown choice." end
  local valid = false
  for _, o in ipairs(Kits.partOptions(game, part)) do
    if o.value == value then valid = true end
  end
  if not valid then return false, "Unknown choice." end
  draft.mode = "custom"
  if part.by == "kit" then
    draft.parts[part.key] = value
  else
    local list = draft.parts[part.key] or {}
    local at = Util.indexOf(list, value)
    if at then
      table.remove(list, at)
    else
      list[#list + 1] = value
      if #list > (part.count or 1) then table.remove(list, 1) end
    end
    draft.parts[part.key] = list
  end
  return true
end

-- Saves the draft as the colour's choice, switching on any sets it needs.
-- Returns the sets switched on.
function Kits.save(game, color)
  local draft = Kits.draft(game, color)
  if not draft then return false, "Open the menu first." end
  local setup = game.state.view.setup or {}
  game.state.view.setup = setup
  setup.kitChoice = setup.kitChoice or {}
  setup.kitChoice[color] = draft
  Kits.close(game, color)
  return true
end

return Kits
