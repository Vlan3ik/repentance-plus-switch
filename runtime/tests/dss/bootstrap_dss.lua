-- Isolated host fixture for the exact DSS sources bundled by Repentance Plus.
-- This intentionally does not load the full mod or provide engine objects.
local stock = assert(arg[1], "stock scripts_v2 path required")
local modroot = assert(arg[2], "mod path required")

package.path = stock .. "/?.lua;" .. modroot .. "/?.lua;" .. package.path
local bit = require("bit")

local function load_host_compatible(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    -- LuaJIT (used by the host regression suite) predates Lua 5.3's
    -- infix bitwise operators.  This is a syntax-only compatibility rewrite
    -- of a branch inside DSS's deferred IsMenuSafe callback; source files
    -- remain untouched and the callback is not invoked by this bootstrap.
    source = source:gsub(
        "entity:ToProjectile%(%)%.ProjectileFlags & ProjectileFlags%.CANT_HIT_PLAYER",
        "bit.band(entity:ToProjectile().ProjectileFlags, ProjectileFlags.CANT_HIT_PLAYER)"
    )
    local chunk, err = loadstring(source, "@" .. path)
    assert(chunk, err)
    return chunk
end

local trace = { calls = {}, callbacks = 0 }
local function note(name, ...)
    trace.calls[#trace.calls + 1] = { name = name, argc = select("#", ...) }
end

local function object(name)
    local methods = {}
    return setmetatable(methods, {
        __index = function(_, key)
            if key == "__name" then return name end
            return function(self, ...)
                note(name .. "." .. tostring(key), ...)
                return nil
            end
        end,
    })
end

local function enum(name)
    return setmetatable({}, {
        __index = function(_, key)
            local value = #trace.calls + 1
            note(name .. "." .. tostring(key))
            return value
        end,
    })
end

local function make_vector(x, y)
    return { X = x or 0, Y = y or 0 }
end
Vector = setmetatable({ One = make_vector(1, 1) }, { __call = function(_, x, y) return make_vector(x, y) end })
local function make_color(r, g, b, a)
    return { R = r or 0, G = g or 0, B = b or 0, A = a or 1 }
end
Color = setmetatable({}, { __call = function(_, r, g, b, a) return make_color(r, g, b, a) end })

local font = object("Font")
function font:Load(...) note("Font.Load", ...) end
function font:GetStringWidth(text) return #(tostring(text or "")) * 8 end
function font:DrawStringScaled(...) note("Font.DrawStringScaled", ...) end
function Font() return font end

local sprite = object("Sprite")
function sprite:Load(...) note("Sprite.Load", ...) end
function sprite:Play(...) note("Sprite.Play", ...) end
function sprite:Render(...) note("Sprite.Render", ...) end
function sprite:SetFrame(...) note("Sprite.SetFrame", ...) end
function Sprite() return sprite end

local keyboard = enum("Keyboard")
keyboard.KEY_F1 = 112
keyboard.KEY_C = 99
Keyboard = keyboard
ModCallbacks = enum("ModCallbacks")
ModCallbacks.MC_POST_RENDER = 1
REPENTANCE = false
Options = { HUDOffset = 0 }

local sfx = object("SFXManager")
function sfx:Play(...) note("SFXManager.Play", ...) end
function SFXManager() return sfx end

local game = object("Game")
function game:GetFrameCount() return 0 end
function Game() return game end

local isaac = {}
function isaac.GetSoundIdByName(name)
    note("Isaac.GetSoundIdByName", name)
    return #trace.calls
end
function isaac.SaveModData(mod, data)
    note("Isaac.SaveModData", mod, data)
end
Isaac = isaac

local function new_mod(name)
    local mod = { Name = name }
    function mod:AddCallback(callback, fn, entity)
        trace.callbacks = trace.callbacks + 1
        note("RegisterMod.AddCallback", callback, entity)
    end
    function mod:AddPriorityCallback(callback, priority, fn, entity)
        return self:AddCallback(callback, fn, entity)
    end
    return mod
end
function RegisterMod(name)
    note("RegisterMod", name)
    return new_mod(name)
end

-- The real mod supplies this table before loading deadseascrolls.lua.
local settings = {
    MenuPalette = 1, HudOffset = 0, GamepadToggle = 1, MenuKeybind = 99,
    MenuHint = 1, MenuBuzzer = 1, MenusNotified = {}, MenusPoppedUp = {},
}
CustomData = { DssSettings = settings, Unlocks = { Special = {} } }
RepentancePlusMod = new_mod("Repentance Plus")

-- deadseascrolls.lua only needs the menu registry during bootstrap.  The
-- complete menu implementation is intentionally not faked here.
DeadSeaScrollsMenu = {
    CoreVersion = 0,
    Palettes = {}, ExistingPalettes = {}, Menus = {},
    Changelogs = { Key = "changelogs", Name = "changelogs", List = {} },
    ChangelogItems = {}, QueuedMenus = {},
}
function DeadSeaScrollsMenu.RemoveCallbacks() note("DeadSeaScrollsMenu.RemoveCallbacks") end
function DeadSeaScrollsMenu.AddPalettes(palettes)
    note("DeadSeaScrollsMenu.AddPalettes", #palettes)
    for _, palette in ipairs(palettes) do
        if palette.Name and not DeadSeaScrollsMenu.ExistingPalettes[palette.Name] then
            DeadSeaScrollsMenu.ExistingPalettes[palette.Name] = true
            DeadSeaScrollsMenu.Palettes[#DeadSeaScrollsMenu.Palettes + 1] = palette
        end
    end
end
function DeadSeaScrollsMenu.AddMenu(name, menu)
    note("DeadSeaScrollsMenu.AddMenu", name)
    DeadSeaScrollsMenu.Menus[name] = menu
end

function include(path)
    local candidate = path:gsub("^scripts%.", "scripts/")
    candidate = candidate:gsub("%.", "/")
    if not candidate:match("%.lua$") then candidate = candidate .. ".lua" end
    local file = assert(io.open(modroot .. "/" .. candidate, "rb"))
    file:close()
    local chunk = load_host_compatible(modroot .. "/" .. candidate)
    setfenv(chunk, getfenv(2))
    return chunk()
end

local chunk = load_host_compatible(modroot .. "/scripts/deadseascrolls.lua")
local ok, err = xpcall(function() chunk() end, debug.traceback)
if not ok then
    local first = tostring(err):match(":%d+: (.*)") or tostring(err):gsub("\n.*", "")
    io.stdout:write("DSS_FIRST_MISSING ", first, "\n")
    os.exit(0)
end

io.stdout:write("DSS_BOOTSTRAP_READY callbacks=", tostring(trace.callbacks),
    " calls=", tostring(#trace.calls), " menus=", tostring(#(DeadSeaScrollsMenu.Menus or {})), "\n")
