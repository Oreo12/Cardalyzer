-- Minimal JSON encode/decode standing in for TTS's built-in JSON global.
local json = {}

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

function json.encode(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return encodeString(v) end
  if t == "table" then
    local out = {}
    if isArray(v) then
      for _, x in ipairs(v) do out[#out + 1] = json.encode(x) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do out[#out + 1] = encodeString(tostring(k)) .. ":" .. json.encode(x) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("can't encode " .. t)
end

function json.decode(s)
  local pos = 1
  local function ws() pos = s:find("[^%s]", pos) or #s + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if e == "u" then out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16) % 256); i = i + 6
        else out[#out + 1] = map[e]; i = i + 2 end
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local obj = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws(); local k = str(); ws(); pos = pos + 1
        obj[k] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
      end
    elseif c == "[" then
      local arr = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return arr end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num then error("bad JSON at " .. pos) end
      pos = pos + #num
      return tonumber(num)
    end
  end
  return value()
end

return json
