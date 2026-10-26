-- Small helpers shared by the engine modules. No TTS API calls here.
local Util = {}

-- A colour as TTS's { r, g, b, a } (0 to 1), from "#RRGGBB", "#RRGGBBAA" or
-- a table that's already one. nil stays nil.
function Util.color(c)
  if type(c) ~= "string" then return c end
  local r, g, b, a = c:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  if not r then return nil end
  local function f(x) return tonumber(x, 16) / 255 end
  return { f(r), f(g), f(b), a ~= "" and f(a) or 1 }
end

function Util.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.split(s, sep)
  local parts = {}
  local start = 1
  while true do
    local i = s:find(sep, start, true)
    if not i then
      parts[#parts + 1] = s:sub(start)
      return parts
    end
    parts[#parts + 1] = s:sub(start, i - 1)
    start = i + #sep
  end
end

function Util.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Util.copy(v) end
  return out
end

-- Fisher-Yates shuffle in place. `random` defaults to math.random.
function Util.shuffle(list, random)
  random = random or math.random
  for i = #list, 2, -1 do
    local j = random(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

function Util.indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return nil
end

-- Removes the first occurrence of value; returns true if it was found.
function Util.removeValue(list, value)
  local i = Util.indexOf(list, value)
  if i then table.remove(list, i) end
  return i ~= nil
end

-- Moves every element of `from` onto the end of `to`, emptying `from`.
function Util.moveAll(from, to)
  for i = 1, #from do to[#to + 1] = from[i] end
  for i = #from, 1, -1 do from[i] = nil end
end

function Util.titleCase(s)
  return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

return Util
