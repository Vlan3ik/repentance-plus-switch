-- Host-side Repentance Plus frontier recorder.
-- This is deliberately a small observation harness: it records the Lua-facing
-- boundary and does not emulate engine state or copy any upstream harness.
local ffi = require("ffi")
local bit = require("bit")
local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end
local function canonical_path(value)
    local input = assert(value)
    local pipe = io.popen("realpath -e -- " .. shell_quote(input), "r")
    if not pipe then return input end
    local resolved = pipe:read("*l")
    pipe:close()
    return resolved and resolved ~= "" and resolved or input
end
local stock = canonical_path(assert(arg[1], "stock scripts_v2 path required"))
local modroot = canonical_path(assert(arg[2], "mod path required"))
local outpath = assert(arg[3], "output JSON path required")
local projectroot = modroot:gsub("/[^/]+$", "")
assert(ffi.load(assert(arg[4], "stub library required"), true))

local function portable_string(value)
    return tostring(value):gsub("^@", ""):gsub(modroot, "<modroot>")
        :gsub(stock, "<stock>"):gsub(projectroot, "<projectroot>")
        :gsub("^/home/[^/]+/.*", "<absolute-path>")
end

package.path = stock .. "/?.lua;" .. modroot .. "/?.lua;" ..
    modroot .. "/?/init.lua;" .. package.path

local ops, callbacks = {}, {}
local firstUnsupported
local function scalar(v, depth)
    depth = depth or 0
    if depth > 2 then return "<nested>" end
    local t = type(v)
    if t == "nil" or t == "boolean" or t == "number" then return v end
    if t == "string" then
        -- Do not leak this checkout's absolute path into the checked-in
        -- frontier.  The placeholders also keep repeated runs portable.
        return portable_string(v)
    end
    if t == "cdata" then return "<cdata:" .. tostring(ffi.typeof(v)) .. ">" end
    if t == "function" then return "<function>" end
    if t == "table" then
        local keys, ret = {}, {}
        for k in pairs(v) do if type(k) == "string" or type(k) == "number" then keys[#keys+1] = k end end
        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do ret[tostring(k)] = scalar(v[k], depth + 1) end
        return ret
    end
    return "<" .. t .. ">"
end
local function compact(v)
    if type(v) == "table" then return "<table>" end
    return scalar(v)
end
local function compact_args(args)
    local result = {}
    for i, value in ipairs(args or {}) do result[i] = compact(value) end
    return result
end
local function caller(level)
    local i = debug.getinfo((level or 2) + 1, "Sl") or {}
    return { source = portable_string(i.source or i.short_src or "?"), line = i.currentline or 0 }
end
local function record(kind, name, args, level)
    local c = caller((level or 2) + 1)
    ops[#ops + 1] = { seq = #ops + 1, kind = kind, name = name,
        source = c.source, line = c.line, args = compact_args(args) }
end
local function unsupported(name, level)
    local c = caller((level or 2) + 1)
    if not firstUnsupported then
        firstUnsupported = { name = name, source = c.source, line = c.line,
            args = {}, reason = "missing_lua_api" }
    end
    error("recording oracle: unsupported Lua API " .. name, (level or 2) + 1)
end

local function wrap_table(label, object)
    if type(object) ~= "table" then return object end
    local old = getmetatable(object) or {}
    local oldindex = old.__index
    local mt = {}
    for k, v in pairs(old) do mt[k] = v end
    mt.__index = function(t, key)
        local value
        if type(oldindex) == "function" then value = oldindex(t, key)
        elseif type(oldindex) == "table" then value = oldindex[key] end
        if value ~= nil then return value end
        return function(...)
            record("unsupported", label .. "." .. tostring(key), {...}, 2)
            return unsupported(label .. "." .. tostring(key), 2)
        end
    end
    setmetatable(object, mt)
    return object
end

function include(path)
    local candidates = { stock .. "/" .. path, modroot .. "/" .. path }
    if not path:match("%.lua$") then candidates[#candidates + 1] = modroot .. "/" .. path:gsub("%.", "/") .. ".lua" end
    for _, candidate in ipairs(candidates) do
        local f = io.open(candidate, "rb")
        if f then
            f:close()
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

-- The stock script layer is the only source of baseline API objects.
assert(loadfile(stock .. "/main.lua"))()
local stockRegisterMod, stockIsaac = RegisterMod, Isaac
local stockGame, stockSfx, stockRng = Game, SFXManager, RNG

-- The bootstrap probe has no gameplay state.  For the next deterministic
-- stage provide exactly one player and one active game slot, then let the
-- first unimplemented player operation fail through the recording boundary.
-- This is an observation fixture, not an API implementation.
-- Match the stock Lua entity wrapper's userdata-side state: each cached
-- handle owns one stable table, and GetData returns that exact table on every
-- call.  This is a host fixture contract, not an EntityPlayer native ABI
-- implementation.
local function make_fake_player()
    return { __pending_cache_flags = 0, __data = {} }
end
local fakePlayer = make_fake_player()
function fakePlayer:AddCacheFlags(flags)
    record("call", "EntityPlayer.AddCacheFlags", {flags}, 2)
    self.__pending_cache_flags = bit.bor(self.__pending_cache_flags,
                                         tonumber(flags) or 0)
end
function fakePlayer:EvaluateItems()
    record("call", "EntityPlayer.EvaluateItems", {}, 2)
end
local function fake_get_data(self)
    local data = rawget(self, "__data")
    record("fixture_satisfied", "EntityPlayer.GetData", {
        "stable_identity", "retained_value", "player_isolation"
    }, 2)
    return data
end
fakePlayer.GetData = fake_get_data
local fakeSprite = {}
setmetatable(fakeSprite, { __index = function(_, key)
    record("unsupported", "Sprite." .. tostring(key), {}, 2)
    return unsupported("Sprite." .. tostring(key), 2)
end })
function fakePlayer:GetSprite()
    record("call", "EntityPlayer.GetSprite", {}, 2)
    return fakeSprite
end
function fakePlayer:GetBabySkin()
    record("call", "EntityPlayer.GetBabySkin", {}, 2)
    return 0
end
setmetatable(fakePlayer, { __index = function(_, key)
    return function(...)
        record("unsupported", "EntityPlayer." .. tostring(key), {...}, 2)
        return unsupported("EntityPlayer." .. tostring(key), 2)
    end
end })
-- Guard the fixture itself so a future refactor cannot silently turn GetData
-- into a fresh table or share state between independent entity handles.
do
    local secondPlayer = make_fake_player()
    secondPlayer.GetData = fake_get_data
    local firstData = fakePlayer:GetData()
    firstData.__oracle_sentinel = "retained"
    assert(fakePlayer:GetData() == firstData, "GetData must preserve table identity")
    assert(fakePlayer:GetData().__oracle_sentinel == "retained",
        "GetData must retain values in the handle table")
    assert(secondPlayer:GetData() ~= firstData,
        "different players must have distinct GetData tables")
    firstData.__oracle_sentinel = nil
end
stockGame.GetNumPlayers = function()
    record("call", "Game.GetNumPlayers", {}, 2)
    return 1
end
-- Game.GetRoom is now a verified non-owning pointer boundary. Keep the
-- pointer identity stable for the whole host run, but intentionally expose
-- no Room methods: the next oracle blocker must be the first Room operation.
local fakeRoom = {}
setmetatable(fakeRoom, { __index = function(_, key)
    return function(...)
        record("unsupported", "Room." .. tostring(key), {...}, 2)
        return unsupported("Room." .. tostring(key), 2)
    end
end })
stockGame.GetRoom = function()
    record("call", "Game.GetRoom", {}, 2)
    return fakeRoom
end

-- Keep construction inert while still exposing the calls the mod performs
-- before any game state exists.  Missing members are recorded by wrap_table.
local hudClass = {}
function hudClass:ShowItemText(...) end
function hudClass:ShowFortuneText(...) end
function hudClass:IsVisible() return true end
function hudClass:Render(...) end
hudClass.__index = function(_, key) return rawget(hudClass, key) end
local hud = setmetatable({}, hudClass)
stockGame.GetHUD = function() return hud end
-- Keep the next missing Game member observable instead of letting Lua turn a
-- nil method lookup into a generic callback error.
stockGame = wrap_table("Game", stockGame)
local stockGameMeta = getmetatable(stockGame) or {}
stockGameMeta.__call = function(self) return self end
setmetatable(stockGame, stockGameMeta)
Game = stockGame
local spriteMethods = {}
for _, method in ipairs({"Load", "Play", "Render", "Update", "SetFrame", "ReplaceSpritesheet", "LoadGraphics"}) do
    spriteMethods[method] = function() end
end
spriteMethods.IsFinished = function() return false end
spriteMethods.IsPlaying = function() return false end
spriteMethods.GetFrame = function() return 0 end
function Sprite() return setmetatable({}, { __index = spriteMethods }) end
local fontMethods = { Load = function() return true end,
    GetStringWidth = function(_, text) return #(tostring(text or "")) * 8 end,
    DrawStringScaled = function() end }
function Font() return setmetatable({}, { __index = fontMethods }) end
-- Compatibility values present in the Switch bridge but absent from this
-- older stock script snapshot. Keeping them here makes the frontier describe
-- the mod/API boundary instead of stopping on a known enum skew.
PILLEFFECT_SHOT_SPEED_DOWN, PILLEFFECT_SHOT_SPEED_UP = -1001, -1002
PICKUP_HEART_ROTTEN, PICKUP_COIN_GOLDEN = 12, 7
DMG_NO_MODIFIERS, DMG_NO_PENALTIES = 0x2000000, 0x10000000
NO_DIRECTION = -1
PLAYER_MAGDALENE, PLAYER_BLUEBABY = 1, 4
PLAYER_BETHANY, PLAYER_JACOB = 18, 19
PLAYER_ISAAC_B, PLAYER_MAGDALENE_B, PLAYER_CAIN_B = 21, 22, 23
PLAYER_JUDAS_B, PLAYER_BLUEBABY_B, PLAYER_EVE_B = 24, 25, 26
PLAYER_AZAZEL_B, PLAYER_LAZARUS_B, PLAYER_EDEN_B = 28, 29, 30
PLAYER_THELOST_B, PLAYER_KEEPER_B = 31, 33
PLAYER_THEFORGOTTEN_B, PLAYER_BETHANY_B = 35, 36
PLAYER_LAZARUS2_B, PLAYER_JACOB2_B, PLAYER_THESOUL_B = 38, 39, 40
BatterySubType = { BATTERY_NORMAL = 1, BATTERY_MICRO = 2, BATTERY_MEGA = 3, BATTERY_GOLDEN = 4 }
CallbackPriority = { IMPORTANT=-200, EARLY=-100, DEFAULT=0, LATE=100 }
local fam = { INTRUDER=200, DIP=201, BLOOD_OATH=203, PSY_FLY=204, WISP=206,
    BOILED_BABY=208, FREEZER_BABY=209, LOST_SOUL=211, LIL_DUMPY=212,
    TINYTOMA=216, BOT_FLY=218, PASCHAL_CANDLE=221, FRUITY_PLUM=225,
    MINISAAC=228, LIL_ABADDON=230, ABYSS_LOCUST=231, LIL_PORTAL=232,
    WORM_FRIEND=233, BONE_SPUR=234, TWISTED_BABY=235,
    STAR_OF_BETHLEHEM=236, BLOOD_BABY=238, CUBE_BABY=239,
    BLOOD_PUPPY=241, VANISHING_TWIN=242 }
for n, v in pairs(fam) do _G["FAMILIAR_" .. n] = v end

local function intercept_method(object, label, method)
    if type(object) ~= "table" then return end
    local old = object[method]
    if type(old) ~= "function" then return end
    object[method] = function(self, ...)
        record("call", label .. "." .. method, {...}, 2)
        return old(self, ...)
    end
end

Isaac = wrap_table("Isaac", stockIsaac)
for k, v in pairs(stockIsaac) do if type(v) == "function" then
    stockIsaac[k] = function(...)
        record("call", "Isaac." .. tostring(k), {...}, 2)
        return v(...)
    end
end end

-- Keep the native lookup visible in the trace while returning only the
-- minimal fake state needed to advance POST_GAME_STARTED.
stockIsaac.GetPlayer = function(index)
    record("call", "Isaac.GetPlayer", {index}, 2)
    return fakePlayer
end

-- The Switch stock script omits the retail Isaac.* mod-data helpers. Inject
-- the same Lua-facing shape as the runtime compatibility chunk so the oracle
-- can continue past the first real dependency without claiming persistence.
function Isaac.LoadModData(mod)
    if not mod or not mod.Path then return nil end
    return nil
end
function Isaac.SaveModData(mod, data) end
function Isaac.HasModData(mod) return false end
function Isaac.RemoveModData(mod) end

-- Keep constructor tables intact: compat.lua enumerates G.Game/G.SFX.
local function callable(label, object)
    if type(object) ~= "table" then return end
    local old = getmetatable(object) or {}
    local mt = {}
    for k, v in pairs(old) do mt[k] = v end
    mt.__call = function(self, ...)
        record("construct", label, {...}, 2)
        local result = old.__call and old.__call(self, ...) or self
        return wrap_table(label, result)
    end
    setmetatable(object, mt)
end
callable("Game", stockGame)
callable("SFXManager", stockSfx)
callable("RNG", stockRng)

local compatActiveMod
RegisterMod = function(name, api)
    record("register_mod", "RegisterMod", {name, api}, 2)
    local mod = stockRegisterMod(name, api)
    if type(mod) == "table" then
        compatActiveMod = mod
        -- Registration is the boundary being observed. Do not enter the old
        -- retail registry: its API-v1 implementation overwrites handlers and
        -- invokes native L_EnableCallback, neither of which is useful here.
        mod.AddCallback = function(self, callback, fn, entity)
            callbacks[#callbacks + 1] = { callback = callback, entity = entity, priority = 0, fn = fn }
            record("register_callback", "Mod.AddCallback", {callback, entity}, 2)
        end
        mod.AddPriorityCallback = function(self, callback, priority, fn, entity)
            callbacks[#callbacks + 1] = { callback = callback, entity = entity, priority = priority, fn = fn }
            record("register_callback", "Mod.AddPriorityCallback", {callback, priority, entity}, 2)
        end
    end
    return mod
end

-- The shipping compatibility chunk lacks the priority helper used by CHAPI.
-- Mirror the bridge already embedded in the Switch runtime so the oracle
-- reports the next unimplemented boundary, not an endpoint we already supply.
stockIsaac.AddCallback = function(callbackId, fn, entityId)
    return compatActiveMod:AddCallback(callbackId, fn, entityId)
end
stockIsaac.AddPriorityCallback = function(callbackId, priority, fn, entityId)
    return compatActiveMod:AddPriorityCallback(callbackId, priority, fn, entityId)
end

local compat_env = include("compat.lua")
compat_env.Direction.NO_DIRECTION = -1
local classes = rawget(_G, "__ISAAC_PORT_ENTITY_CLASSES")
if classes then
    local function exposeClass(classData)
        for key, value in pairs(classData.functions) do
            rawset(classData.meta, key, value)
        end
        return setmetatable({}, { __class = classData.meta })
    end
    compat_env.Entity = exposeClass(classes.Entity)
    compat_env.EntityPlayer = exposeClass(classes.EntityPlayer)
end
compat_env.HUD = setmetatable({}, { __class = hudClass })
-- `game` in the mod is the object returned by Game(), not the constructor
-- table above. Wrap that concrete compatibility object so a missing method is
-- recorded at the Lua boundary.
local compatGameConstructor = compat_env.Game or _G.Game
if type(compatGameConstructor) == "function" then
    local compatGame = compatGameConstructor()
    if type(compatGame) == "table" then
        wrap_table("Game", compatGame)
        compat_env.Game = function() return compatGame end
    end
end
local mod_chunk = assert(loadfile(modroot .. "/main.lua"))
setfenv(mod_chunk, compat_env)
local ok, err = xpcall(mod_chunk, debug.traceback)
if ok and #callbacks > 0 then
    -- Probe the earliest useful lifecycle callbacks in order.  The game-start
    -- probe establishes the first player/cache boundary; one update probe then
    -- advances the same minimal state to the next real missing operation.
    local probes = {}
    for _, wanted in ipairs({15, 1}) do
        for _, item in ipairs(callbacks) do
            if item.callback == wanted then probes[#probes + 1] = item; break end
        end
    end
    for _, probe in ipairs(probes) do
        local label = probe.callback == 15 and "POST_GAME_STARTED" or "POST_UPDATE"
        record("callback_probe", label, {probe.callback}, 1)
        local probeOk, probeErr = xpcall(function()
            if probe.callback == 15 then return probe.fn(false) end
            return probe.fn()
        end, debug.traceback)
        if not probeOk then
            err = probeErr
            ok = false
            if not firstUnsupported then
                local source, line = tostring(probeErr):match("([^\n:]+):(%d+):")
                firstUnsupported = { name = "callback_error", source = source or "?",
                    line = tonumber(line) or 0, args = {probe.callback}, reason = tostring(probeErr) }
            end
            break
        end
    end
end
if not ok and not firstUnsupported then
    local source, line = tostring(err):match("([^\n:]+):(%d+):")
    firstUnsupported = { name = "lua_error", source = source or "?", line = tonumber(line) or 0,
        args = {}, reason = tostring(err):match("%]: (.*)") or tostring(err) }
end
-- The Lua error boundary can report a synthetic [C] frame.  Prefer the
-- already-recorded unsupported operation so the frontier points to the real
-- mod call site and keeps its compact arguments.
if firstUnsupported and (firstUnsupported.line or 0) < 0 then
    for i = #ops, 1, -1 do
        local operation = ops[i]
        if operation.kind == "unsupported" and operation.name == firstUnsupported.name then
            firstUnsupported.source = operation.source
            firstUnsupported.line = operation.line
            firstUnsupported.args = operation.args
            break
        end
    end
end

local function json_string(v)
    local s, out = tostring(v), {'"'}
    for i = 1, #s do
        local b, c = s:byte(i), s:sub(i, i)
        if c == '"' then out[#out+1] = string.char(92, 34)
        elseif c == '\\' then out[#out+1] = string.char(92, 92)
        elseif c == '\n' then out[#out+1] = string.char(92, 110)
        elseif c == '\r' then out[#out+1] = string.char(92, 114)
        elseif c == '\t' then out[#out+1] = string.char(92, 116)
        elseif b < 32 or b >= 127 then out[#out+1] = string.format(string.char(92) .. 'u%04x', b)
        else out[#out+1] = c end
    end
    out[#out+1] = '"'
    return table.concat(out)
end
local function json(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" or t == "number" then return tostring(v) end
    if t == "string" then return json_string(v) end
    if t ~= "table" then return json_string("<" .. t .. ">") end
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    local array, maxkey = true, 0
    for _, k in ipairs(keys) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then array = false; break end
        if k > maxkey then maxkey = k end
    end
    if array and maxkey ~= #keys then array = false end
    local out = {}
    if array then
        for i = 1, #keys do out[#out+1] = json(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    for _, k in ipairs(keys) do out[#out+1] = json(tostring(k)) .. ":" .. json(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local publicCallbacks = {}
for i, item in ipairs(callbacks) do
    publicCallbacks[i] = { callback = compact(item.callback), entity = compact(item.entity), priority = item.priority }
end
local report = { schema = 1, status = ok and "host_bootstrap_complete" or "host_bootstrap_blocked",
    verification_level = "host_only", first_unsupported = firstUnsupported,
    stage = "post_game_started_then_post_update_minimal_state", callbacks = publicCallbacks, operations = ops }
local file = assert(io.open(outpath, "wb")); file:write(json(report), "\n"); file:close()
io.stdout:write("RECORDING_ORACLE_" .. report.status:upper() .. "\n")
if not ok then io.stderr:write(tostring(err), "\n") end
