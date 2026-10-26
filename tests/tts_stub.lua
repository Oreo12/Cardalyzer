-- Fake TTS globals: enough of the API for the engine to run headless.
local json = dofile("tests/json.lua")

local tts = { objects = {}, order = {}, nextGuid = 1, broadcasts = {}, ui = { values = {} }, flights = {}, timers = {} }

local function newObject(kind, extra)
  local guid = string.format("%06x", tts.nextGuid)
  tts.nextGuid = tts.nextGuid + 1
  local obj = { type = kind, tags = {}, value = nil }
  for k, v in pairs(extra or {}) do obj[k] = v end
  obj.getGUID = function() return guid end
  obj.destruct = function() tts.objects[guid] = nil end
  obj.setPosition = function(p) obj.position = p end
  obj.getPosition = function()
    local p = obj.position or { 0, 0, 0 }
    return { x = p[1], y = p[2], z = p[3] }
  end
  obj.setPositionSmooth = function(p)
    obj.position = p
    tts.flights[#tts.flights + 1] = {
      guid = guid, to = p, at = tts.now or 0, rotation = obj.rotation,
      uid = obj.data and obj.data.GMNotes, locked = obj.locked, interactable = obj.interactable,
    }
  end
  obj.setRotationSmooth = function(r) obj.rotation = r end
  obj.setLock = function(v) obj.locked = v end
  obj.getLock = function() return obj.locked == true end
  obj.setRotation = function(r) obj.rotation = r end
  obj.setScale = function(s) obj.scale = s end
  obj.setName = function(n) obj.name = n end
  obj.addTag = function(t) obj.tags[t] = true end
  obj.hasTag = function(t) return obj.tags[t] == true end
  obj.setValue = function(v) obj.value = v end
  obj.getValue = function() return obj.value end
  obj.buttons = {}
  obj.createButton = function(b) obj.buttons[#obj.buttons + 1] = b end
  obj.getGMNotes = function() return obj.data and obj.data.GMNotes or "" end
  obj.zones = {}
  obj.getZones = function() return obj.zones end
  tts.objects[guid] = obj
  tts.order[#tts.order + 1] = guid
  return obj
end
tts.newObject = newObject

function tts.reset()
  tts.objects, tts.order, tts.broadcasts, tts.ui = {}, {}, {}, { values = {} }
  tts.flights, tts.timers, tts.deferTimers, tts.lines = {}, {}, false, nil
  tts.empty = {}
end

-- Wait.time runs at once unless tts.deferTimers is set; then callbacks wait
-- in tts.timers until tts.runTimers() runs them in time order. runTimers(t)
-- stops at time t, leaving later callbacks waiting (and the clock at t).
function tts.runTimers(untilTime)
  while #tts.timers > 0 do
    table.sort(tts.timers, function(a, b) return a.at < b.at end)
    if untilTime and tts.timers[1].at > untilTime then
      tts.now = untilTime
      return
    end
    local t = table.remove(tts.timers, 1)
    tts.now = t.at
    t.fn()
  end
  tts.now = 0
end

function tts.live(filter)
  local out = {}
  for _, guid in ipairs(tts.order) do
    local obj = tts.objects[guid]
    if obj and (not filter or filter(obj)) then out[#out + 1] = obj end
  end
  return out
end

function spawnObject(params)
  return newObject(params.type, { position = params.position, rotation = params.rotation, scale = params.scale })
end

function spawnObjectData(params)
  local data = params.data
  local obj = newObject(data.Name, { data = data, position = params.position, rotation = params.rotation, locked = data.Locked == true })
  for _, t in ipairs(data.Tags or {}) do obj.tags[t] = true end
  if params.callback_function then params.callback_function(obj) end
  return obj
end

function getObjectFromGUID(guid) return tts.objects[guid] end
function getObjects() return tts.live() end
function getObjectsWithTag(tag) return tts.live(function(o) return o.tags[tag] end) end

function broadcastToAll(msg) tts.broadcasts[#tts.broadcasts + 1] = msg end
function broadcastToColor(msg, color)
  if tts.empty[color] then error("Error in broadcastToColor: Player " .. color .. " does not exist.") end
  tts.broadcasts[#tts.broadcasts + 1] = color .. ": " .. msg
end
function printToAll(msg) tts.broadcasts[#tts.broadcasts + 1] = msg end
-- Like TTS: messaging an empty seat is an error.
function printToColor(msg, color)
  if tts.empty[color] then error("Error in printToColor: Player " .. color .. " does not exist.") end
  tts.broadcasts[#tts.broadcasts + 1] = color .. ": " .. msg
end

UI = {
  setXml = function(xml) tts.ui.xml = xml end,
  setValue = function(id, v) tts.ui.values[id] = v end,
  setCustomAssets = function(list) tts.ui.assets = list end,
}
Wait = {
  frames = function(fn) fn() end,
  time = function(fn, delay)
    if not tts.deferTimers then return fn() end
    tts.timers[#tts.timers + 1] = { at = (tts.now or 0) + delay, fn = fn }
  end,
}
-- Every colour is seated unless a test empties it: tts.empty[color] = true.
tts.empty = {}
Player = setmetatable({}, { __index = function(_, color)
  return { color = color, seated = not tts.empty[color], getHandObjects = function() return {} end }
end })
Global = { name = "Global", setVectorLines = function(lines) tts.lines = lines end }
JSON = { encode = json.encode, decode = json.decode }

return tts
