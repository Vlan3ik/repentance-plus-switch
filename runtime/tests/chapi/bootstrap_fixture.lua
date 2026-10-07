-- Host-only CHAPI 0.946 fixture.
-- This intentionally loads the bundled CHAPI files without Repentance Plus main.lua.
-- It records the first unsupported leaf instead of making native/hardware claims.
local ffi = require("ffi")
local stock = assert(arg[1], "stock scripts_v2 path required")
local modroot = assert(arg[2], "mod path required")
assert(ffi.load(assert(arg[3], "stub library required"), true))

package.path = stock .. "/?.lua;" .. modroot .. "/?.lua;" ..
               modroot .. "/?/init.lua;" .. package.path

local events = {}
local first_unsupported
local function record(kind, name, detail)
    events[#events + 1] = { kind = kind, name = name, detail = detail }
end

local function unsupported(name)
    if not first_unsupported then
        first_unsupported = name
    end
    record("unsupported", name)
end

local function proxy(name)
    local object = {}
    return setmetatable(object, {
        __index = function(_, key)
            local leaf = name .. "." .. tostring(key)
            unsupported(leaf)
            return function(...)
                record("call", leaf, select("#", ...))
                return proxy(leaf)
            end
        end,
        __newindex = function(_, key, value)
            rawset(object, key, value)
            record("set", name .. "." .. tostring(key))
        end,
        __tostring = function() return "<" .. name .. ">" end,
    })
end

function include(path)
    local candidates = { stock .. "/" .. path, modroot .. "/" .. path }
    if not path:match("%.lua$") then
        candidates[#candidates + 1] = modroot .. "/" .. path:gsub("%.", "/") .. ".lua"
    end
    for _, candidate in ipairs(candidates) do
        local file = io.open(candidate, "rb")
        if file then
            file:close()
            local chunk = assert(loadfile(candidate))
            setfenv(chunk, getfenv(2))
            local results = { chunk() }
            if path == "bindings.lua" then
                __ISAAC_PORT_ENTITY_CLASSES = {
                    Entity = luahelper.GetEntityRegisterData("Entity"),
                    EntityPlayer = luahelper.GetEntityRegisterData("Entity_Player"),
                }
            end
            return unpack(results)
        end
    end
    error("include not found: " .. path)
end

assert(loadfile(stock .. "/main.lua"))()

-- The CHAPI load phase registers callbacks and defines helpers.  No callback is
-- dispatched in this fixture, so all engine objects can remain recording fakes.
local real_register_mod = RegisterMod
local fake_game = proxy("Game")
local fake_sfx = proxy("SFX")
-- compat.lua wraps these tables into the version-1 constructors.
Game = fake_game
SFX = fake_sfx
-- scripts_v2 intentionally keeps the legacy enum set; CHAPI 0.946 references
-- Repentance player IDs that the Switch compatibility layer must expose.
local repentance_players = {
    PLAYER_BLUEBABY = 4, PLAYER_BETHANY = 18, PLAYER_JACOB = 19,
    PLAYER_ISAAC_B = 21, PLAYER_MAGDALENE_B = 22, PLAYER_CAIN_B = 23,
    PLAYER_JUDAS_B = 24, PLAYER_BLUEBABY_B = 25, PLAYER_EVE_B = 26,
    PLAYER_AZAZEL_B = 28, PLAYER_LAZARUS_B = 29, PLAYER_EDEN_B = 30,
    PLAYER_THELOST_B = 31, PLAYER_KEEPER_B = 33, PLAYER_THEFORGOTTEN_B = 35,
    PLAYER_BETHANY_B = 36, PLAYER_LAZARUS2_B = 38, PLAYER_JACOB2_B = 39,
    PLAYER_THESOUL_B = 40,
}
for name, value in pairs(repentance_players) do _G[name] = value end
CallbackPriority = { IMPORTANT = -200, EARLY = -100, DEFAULT = 0, LATE = 100 }
local function expose_class(name)
    local data = (name == "Entity" and __ISAAC_PORT_ENTITY_CLASSES.Entity)
        or __ISAAC_PORT_ENTITY_CLASSES.EntityPlayer
    local meta = data.meta
    for key, value in pairs(data.functions) do rawset(meta, key, value) end
    return setmetatable({}, { __class = meta })
end
Entity = expose_class("Entity")
EntityPlayer = expose_class("Entity_Player")
HUD = setmetatable({}, { __class = {} })
local stock_isaac_add_callback = Isaac.AddCallback
function Isaac.AddPriorityCallback(callbackId, priority, fn, entityId)
    record("register_priority_callback", tostring(callbackId), priority)
    return stock_isaac_add_callback(callbackId, "chapi-priority-" .. tostring(#events), fn, entityId)
end
function RNG() return proxy("RNG") end
function KColor(...) return proxy("KColor") end
local sprite_methods = {
    Load = function() end, Play = function() end, SetFrame = function() end,
    SetLastFrame = function() end, GetFrame = function() return 3 end,
}
function Font() return proxy("Font") end
function Sprite() return setmetatable({}, { __index = sprite_methods }) end

local ok, err = xpcall(function()
    -- Keep the version-1 compatibility environment supplied by stock scripts.
    CustomHealthAPI = {
        PersistentData = {
            CharactersThatCantHaveRedHealth = {},
            CharactersThatConvertMaxHealth = {},
        },
    }
    local chunk = assert(loadfile(modroot .. "/scripts/customhealthapi/core.lua"))
    chunk()
end, debug.traceback)

local result = {
    schema = 1,
    api = "Custom Health API",
    version = 0.946,
    status = ok and "host_bootstrap_complete" or "host_bootstrap_blocked",
    first_unsupported = first_unsupported or false,
    event_count = #events,
    events = events,
}
if not ok then
    result.error = tostring(err)
end

local function json_string(value)
    if value == nil then return "null" end
    if type(value) == "boolean" then return value and "true" or "false" end
    if type(value) == "number" then return tostring(value) end
    if type(value) == "string" then
        local escaped = value:gsub("[\\\"\n\r\t]", {
            ["\\"] = "\\\\", ["\""] = "\\\"",
            ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
        })
        return "\"" .. escaped .. "\""
    end
    if type(value) == "table" then
        local parts = {}
        for i, item in ipairs(value) do
            parts[#parts + 1] = json_string(item)
        end
        if #parts > 0 then return "[" .. table.concat(parts, ",") .. "]" end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            parts[#parts + 1] = json_string(tostring(key)) .. ":" .. json_string(value[key])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return json_string(tostring(value))
end

io.write(json_string(result), "\n")
if not ok then os.exit(0) end
