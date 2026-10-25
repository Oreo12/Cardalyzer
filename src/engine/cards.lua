-- Card library: turns the rows from cards.json into card definitions and
-- looks them up by id. Effects are parsed here; whether each keyword exists
-- is checked later by the effects registry, which knows the game's rules.
local Util = require("engine.util")

local Cards = {}
Cards.__index = Cards

Cards.DECKS = { starter = true, market = true, fixed = true }

-- Effects with no amount. Everything else needs "keyword:amount".
Cards.BARE = { reminder = true }

local function parseOne(part)
  local key, value = part:match("^([%w_]+)%s*:%s*([%w_%-]+)$")
  if not key then
    if Cards.BARE[part] then return { key = part, amount = 1 } end
    error("bad effect '" .. part .. "' (expected keyword:amount)", 0)
  end
  if key == "custom" then return { key = "custom", fn = value } end
  local amount = tonumber(value)
  if not amount then error("effect '" .. part .. "' needs a number after ':'", 0) end
  return { key = key, amount = amount }
end

-- "trade:2; draw:1; custom:myFn" -> { {key="trade", amount=2}, {key="draw", amount=1}, {key="custom", fn="myFn"} }
-- "trade:2 | combat:2"           -> { {key="choice", options={ {key="trade",...}, {key="combat",...} }} }
-- "blob=combat:2"                -> { {key="combat", amount=2, ally="blob"} } (ally effects only)
function Cards.parseEffects(str)
  local list = {}
  if str == nil or str == "" then return list end
  for _, part in ipairs(Util.split(str, ";")) do
    part = Util.trim(part)
    if part ~= "" then
      local faction, rest = part:match("^([%w_]+)%s*=%s*(.+)$")
      if faction then part = Util.trim(rest) end
      local effect
      if part:find("|", 1, true) then
        effect = { key = "choice", options = {} }
        for _, option in ipairs(Util.split(part, "|")) do
          effect.options[#effect.options + 1] = parseOne(Util.trim(option))
        end
      else
        effect = parseOne(part)
      end
      effect.ally = faction
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
  if not Cards.DECKS[deck] then fail("deck must be starter, market or fixed, got '" .. deck .. "'") end

  local ok, effects = pcall(Cards.parseEffects, row.effects)
  if not ok then fail(effects) end
  local okAlly, ally = pcall(Cards.parseEffects, row.ally_effects)
  if not okAlly then fail(ally) end
  local okScrap, scrap = pcall(Cards.parseEffects, row.scrap_effects)
  if not okScrap then fail(scrap) end

  local factions = {}
  for _, f in ipairs(Util.split(blank(row.faction) and "none" or row.faction, "/")) do
    factions[#factions + 1] = Util.trim(f)
  end

  return {
    id = id,
    index = index,
    name = blank(row.name) and id or row.name,
    deck = deck,
    faction = factions[1],
    factions = factions, -- "blob/machine_cult" is in both; "any" counts as every faction
    allyGroups = Cards.allyGroups(ally),
    type = blank(row.type) and "unit" or row.type,
    cost = tonumber(row.cost) or 0,
    copies = tonumber(row.copies) or 1,
    effects = effects,
    allyEffects = ally,
    scrapEffects = scrap,
    defense = tonumber(row.defense),
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
