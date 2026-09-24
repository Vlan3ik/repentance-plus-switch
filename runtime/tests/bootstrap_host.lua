local ffi = require("ffi")
local stock = assert(arg[1], "stock scripts_v2 path required")
local modroot = assert(arg[2], "mod path required")
assert(ffi.load(assert(arg[3], "stub library required"), true))

package.path = stock .. "/?.lua;" .. modroot .. "/?.lua;" ..
               modroot .. "/?/init.lua;" .. package.path

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

local hudClass = {}
function hudClass:ShowItemText(...) end
function hudClass:ShowFortuneText(...) end
function hudClass:IsVisible() return true end
function hudClass:Render(...) end
hudClass.__index = function(_, key) return rawget(hudClass, key) end
local hud = setmetatable({}, hudClass)
Game.GetHUD = function() return hud end
setmetatable(Game, { __call = function(self) return self end })
PILLEFFECT_SHOT_SPEED_DOWN = -1001
PILLEFFECT_SHOT_SPEED_UP = -1002
PICKUP_HEART_ROTTEN = 12
PICKUP_COIN_GOLDEN = 7
DMG_NO_MODIFIERS = 0x2000000
DMG_NO_PENALTIES = 0x10000000
NO_DIRECTION = -1
PLAYER_MAGDALENE = 1
PLAYER_BLUEBABY = 4
PLAYER_BETHANY = 18
PLAYER_JACOB = 19
PLAYER_ISAAC_B = 21
PLAYER_MAGDALENE_B = 22
PLAYER_CAIN_B = 23
PLAYER_JUDAS_B = 24
PLAYER_BLUEBABY_B = 25
PLAYER_EVE_B = 26
PLAYER_AZAZEL_B = 28
PLAYER_LAZARUS_B = 29
PLAYER_EDEN_B = 30
PLAYER_THELOST_B = 31
PLAYER_KEEPER_B = 33
PLAYER_THEFORGOTTEN_B = 35
PLAYER_BETHANY_B = 36
PLAYER_LAZARUS2_B = 38
PLAYER_JACOB2_B = 39
PLAYER_THESOUL_B = 40
BatterySubType = {
    BATTERY_NORMAL = 1,
    BATTERY_MICRO = 2,
    BATTERY_MEGA = 3,
    BATTERY_GOLDEN = 4,
}
CallbackPriority = {
    IMPORTANT = -200,
    EARLY = -100,
    DEFAULT = 0,
    LATE = 100,
}
local repentanceFamiliars = {
    INTRUDER = 200, DIP = 201, BLOOD_OATH = 203, PSY_FLY = 204,
    WISP = 206, BOILED_BABY = 208, FREEZER_BABY = 209, LOST_SOUL = 211,
    LIL_DUMPY = 212, TINYTOMA = 216, BOT_FLY = 218, PASCHAL_CANDLE = 221,
    FRUITY_PLUM = 225, MINISAAC = 228, LIL_ABADDON = 230,
    ABYSS_LOCUST = 231, LIL_PORTAL = 232, WORM_FRIEND = 233,
    BONE_SPUR = 234, TWISTED_BABY = 235, STAR_OF_BETHLEHEM = 236,
    BLOOD_BABY = 238, CUBE_BABY = 239, BLOOD_PUPPY = 241,
    VANISHING_TWIN = 242,
}
for name, value in pairs(repentanceFamiliars) do
    _G["FAMILIAR_" .. name] = value
end

local spriteMethods = {}
function spriteMethods:Load(...) end
function spriteMethods:Play(...) end
function spriteMethods:Render(...) end
function spriteMethods:Update(...) end
function spriteMethods:IsFinished(...) return false end
function spriteMethods:IsPlaying(...) return false end
function spriteMethods:GetFrame(...) return 0 end
function spriteMethods:SetFrame(...) end
function spriteMethods:ReplaceSpritesheet(...) end
function spriteMethods:LoadGraphics(...) end
function Sprite()
    return setmetatable({}, { __index = spriteMethods })
end

local fontMethods = {}
function fontMethods:Load(...) return true end
function fontMethods:GetStringWidth(text)
    return #(tostring(text or "")) * 8
end
function fontMethods:DrawStringScaled(...) end
function Font()
    return setmetatable({}, { __index = fontMethods })
end

local stockRegisterMod = RegisterMod
local stockIsaac = Isaac
local stockIsaacAddCallback = stockIsaac.AddCallback
local nextCompatCallback = 0
local compatActiveMod
function stockIsaac.AddCallback(callbackId, fn, entityId)
    return compatActiveMod:AddCallback(callbackId, fn, entityId)
end
function stockIsaac.AddPriorityCallback(callbackId, priority, fn, entityId)
    return compatActiveMod:AddPriorityCallback(callbackId, priority, fn, entityId)
end
function RegisterMod(name, apiVersion)
    local mod = stockRegisterMod(name, apiVersion)
    if apiVersion == 1 then
        compatActiveMod = mod
        local compat = getfenv(1)
        compat.Direction.NO_DIRECTION = -1
        local classes = rawget(_G, "__ISAAC_PORT_ENTITY_CLASSES")
        if classes then
            local function exposeClass(classData)
                for key, value in pairs(classData.functions) do
                    rawset(classData.meta, key, value)
                end
                return setmetatable({}, { __class = classData.meta })
            end
            compat.Entity = exposeClass(classes.Entity)
            compat.EntityPlayer = exposeClass(classes.EntityPlayer)
        end
        compat.HUD = setmetatable({}, { __class = hudClass })
        setfenv(2, compat)
        local wrappedCallbacks = {}
        function mod:AddCallback(callbackId, fn, entityId)
            local wrapped = function(...) return fn(self, ...) end
            wrappedCallbacks[fn] = wrapped
            stockIsaacAddCallback(callbackId,
                "host-v1-" .. tostring(nextCompatCallback), wrapped,
                entityId, self)
            nextCompatCallback = nextCompatCallback + 1
        end
        function mod:AddPriorityCallback(callbackId, priority, fn, entityId)
            self:AddCallback(callbackId, fn, entityId)
        end
        function mod:RemoveCallback(callbackId, fn)
            local wrapped = wrappedCallbacks[fn]
            if wrapped then
                stockIsaac.RemoveCallback(callbackId, wrapped)
                wrappedCallbacks[fn] = nil
            end
        end
    end
    return mod
end

assert(loadfile(modroot .. "/main.lua"))()
io.stdout:write("REPENTANCE_PLUS_HOST_BOOTSTRAP_READY\n")
