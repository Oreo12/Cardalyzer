-- Card library: turns the rows from cards.json into card definitions and
-- looks them up by id. Effects are parsed here; whether each keyword exists
-- is checked later by the effects registry, which knows the game's rules.
local Util = require("engine.util")

local Cards = {}
Cards.__index = Cards

-- dealt: each player is dealt rules.deal.count of these at setup, into play.
-- objective: each player is dealt rules.objectives.count face down (secret goals).
-- supply: a pool of piles; each game rules.supply.count of them are laid out
-- beside the fixed piles (at random, or a preset picked in the New Game menu).
Cards.DECKS = { starter = true, market = true, fixed = true, dealt = true, objective = true, supply = true }

-- Effects with no amount. Everything else needs "keyword:amount".
-- block: in react_effects, the attack doesn't affect the player who revealed it.
Cards.BARE = { reminder = true, block = true }

-- Keywords that name something instead of an amount: a card (gain:silk,
-- opponents_gain:gossip) or a set-aside area from rules.areas (set_aside:tavern).
Cards.ARG = { gain = "card", opponents_gain = "card", set_aside = "area", set_aside_hand = "area" }

local function parseOne(part)
  local key, value = part:match("^([%w_]+)%s*:%s*([%w_%-]+)$")
  if not key then
    if Cards.BARE[part] then return { key = part, amount = 1 } end
    error("bad effect '" .. part .. "' (expected keyword:amount)", 0)
  end
  if key == "custom" then return { key = "custom", fn = value } end
  if Cards.ARG[key] then return { key = key, id = value, amount = 1 } end
  local amount = tonumber(value)
  if not amount then error("effect '" .. part .. "' needs a number after ':'", 0) end
  return { key = key, amount = amount }
end

-- "trade:2; draw:1; custom:myFn" -> { {key="trade", amount=2}, {key="draw", amount=1}, {key="custom", fn="myFn"} }
-- "trade:2 | combat:2"           -> { {key="choice", options={ {key="trade",...}, {key="combat",...} }} }
-- "blob=combat:2"                -> { {key="combat", amount=2, ally="blob"} } (ally effects only)
-- "mastery>=10=combat:5"         -> { {key="combat", amount=5, cond={key="mastery", op=">=", n=10}} }
--                                   (only while the player has 10 or more mastery; any column)
function Cards.parseEffects(str)
  local list = {}
  if str == nil or str == "" then return list end
  for _, part in ipairs(Util.split(str, ";")) do
    part = Util.trim(part)
    if part ~= "" then
      -- (= nil matters: in TTS's MoonSharp a bare `local x` in a loop keeps
      -- the previous iteration's value)
      local cond = nil
      local ckey, op, n, after = part:match("^([%w_]+)%s*([<>]=?)%s*(%-?%d+)%s*=%s*(.+)$")
      if ckey then
        cond = { key = ckey, op = op, n = tonumber(n) }
        part = Util.trim(after)
      end
      local faction, rest = part:match("^([%w_]+)%s*=%s*(.+)$")
      if faction then part = Util.trim(rest) end
      local effect = nil
      if part:find("|", 1, true) then
        effect = { key = "choice", options = {} }
        for _, option in ipairs(Util.split(part, "|")) do
          effect.options[#effect.options + 1] = parseOne(Util.trim(option))
        end
      else
        effect = parseOne(part)
      end
      effect.ally = faction
      effect.cond = cond
      list[#list + 1] = effect
    end
  end
  return list
end

-- Ally effects grouped by the faction they need. A group with faction nil
-- fires for any of the card's own factions. Each group fires once a turn.
function Cards.allyGroups(effects)
  local groups, byFaction = {}, {}
  for _, effect in ipairs(effects) do
    local key = effect.ally or ""
    local group = byFaction[key]
    if not group then
      group = { faction = effect.ally, effects = {} }
      byFaction[key] = group
      groups[#groups + 1] = group
    end
    group.effects[#group.effects + 1] = effect
  end
  return groups
end

local function blank(v)
  return v == nil or v == ""
end

local function parseRow(row, index)
  local id = row.id
  if blank(id) then error("row " .. index .. " has no id", 0) end
  local function fail(msg) error("card '" .. id .. "': " .. msg, 0) end

  local deck = blank(row.deck) and "market" or row.deck
  -- "market:<key>" puts a card in one of the extra markets (rules.markets)
  if not Cards.DECKS[deck] and not deck:match("^market:[%w_]+$") then
    fail("deck must be starter, market, market:<key>, fixed, dealt, objective or supply, got '" .. deck .. "'")
  end

  local ok, effects = pcall(Cards.parseEffects, row.effects)
  if not ok then fail(effects) end
  local okAlly, ally = pcall(Cards.parseEffects, row.ally_effects)
  if not okAlly then fail(ally) end
  local okScrap, scrap = pcall(Cards.parseEffects, row.scrap_effects)
  if not okScrap then fail(scrap) end
  local okDouble, double = pcall(Cards.parseEffects, row.double_ally_effects)
  if not okDouble then fail(double) end
  local okReact, react = pcall(Cards.parseEffects, row.react_effects)
  if not okReact then fail(react) end
  local okNext, nextFx = pcall(Cards.parseEffects, row.next_effects)
  if not okNext then fail(nextFx) end

  local factions = {}
  for _, f in ipairs(Util.split(blank(row.faction) and "none" or row.faction, "/")) do
    factions[#factions + 1] = Util.trim(f)
  end
  -- "action/attack": the card has every one of these types (type is the first)
  local types = {}
  for _, t in ipairs(Util.split(blank(row.type) and "unit" or row.type, "/")) do
    types[#types + 1] = Util.trim(t)
  end

  -- Double ally effects fire when two other cards of the faction are in play.
  local groups = Cards.allyGroups(ally)
  for _, g in ipairs(Cards.allyGroups(double)) do
    g.need = 2
    groups[#groups + 1] = g
  end

  return {
    id = id,
    index = index,
    name = blank(row.name) and id or row.name,
    deck = deck,
    set = not blank(row.set) and row.set or nil, -- which set (expansion) the card belongs to
    faction = factions[1],
    factions = factions, -- "blob/machine_cult" is in both; "any" counts as every faction
    allyGroups = groups,
    doubleAllyEffects = double,
    condition = not blank(row.condition) and row.condition or nil, -- objective: custom effect whose check() says it's met
    type = types[1],
    types = types,
    cost = tonumber(row.cost) or 0,
    copies = tonumber(row.copies) or 1,
    effects = effects,
    allyEffects = ally,
    scrapEffects = scrap,
    reactEffects = react, -- revealed from the hand when an opponent's attack hits this player
    nextEffects = nextFx, -- at the start of the owner's next turn; the card stays in play until then
    defense = tonumber(row.defense),
    points = tonumber(row.points) or 0, -- victory points, for rules.win.type = "points"
    starting = tonumber(row.starting) or 0, -- copies in each player's starting deck, whatever its deck
    text = row.text or "",
  }
end

function Cards.new(rows)
  local lib = setmetatable({ byId = {}, list = {} }, Cards)
  for i, row in ipairs(rows) do
    local card = parseRow(row, i)
    if lib.byId[card.id] then error("duplicate card id '" .. card.id .. "'", 0) end
    lib.byId[card.id] = card
    lib.list[#lib.list + 1] = card
  end
  return lib
end

-- A card's types: { "action", "attack" } ("action/attack"), or its one type.
-- (A type changed from Lua, card.type = "monster", wins over the list.)
function Cards.typesOf(card)
  if card.types and card.types[1] == card.type then return card.types end
  return { card.type }
end

-- Does the card have this type?
function Cards.hasType(card, t)
  for _, own in ipairs(Cards.typesOf(card)) do
    if own == t then return true end
  end
  return false
end

-- The card's entry in rules.cardTypes, its types' entries combined: a flag
-- set by any of its types counts (persistent, guard, defeat, event...), the
-- first type to give a value wins otherwise. An empty table if none.
function Cards.typeDef(rules, card)
  local types = Cards.typesOf(card)
  local defs = rules.cardTypes or {}
  if #types == 1 then return defs[types[1]] or {} end
  local merged = {}
  for _, t in ipairs(types) do
    for k, v in pairs(defs[t] or {}) do
      if merged[k] == nil or v == true then merged[k] = v end
    end
  end
  return merged
end

function Cards:get(id)
  local card = self.byId[id]
  if not card then error("unknown card id '" .. tostring(id) .. "'", 0) end
  return card
end

function Cards:inDeck(deck)
  local out = {}
  for _, card in ipairs(self.list) do
    if card.deck == deck then out[#out + 1] = card end
  end
  return out
end

return Cards
