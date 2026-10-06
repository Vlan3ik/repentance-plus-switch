-- Repentance Plus Switch persistence acceptance test.
--
-- This file is deliberately a console-only test.  Do not run it through the
-- host LuaJIT tests: the four Isaac data APIs below are the first blocker
-- whose persistence semantics require a real game process and a full restart.

local MOD_NAME = "rplus-persistence-acceptance"
local MARKER = "RPLUS_PERSISTENCE_ACCEPTANCE_V1_20261006"
local mod = RegisterMod(MOD_NAME, 1)

local function log(message)
    local line = "RPLUS_PERSISTENCE_ACCEPTANCE " .. message
    print(line)
    if Isaac and Isaac.DebugString then
        pcall(Isaac.DebugString, line)
    end
end

local function fail(reason)
    log("FAIL " .. reason)
end

local function on_game_started(_, continued)
    -- `continued` describes the save slot, not whether the process was
    -- restarted.  The operator supplies the restart boundary between the two
    -- launches, so it must not be inferred from this callback argument.
    log("BEGIN")

    local has_data = Isaac.HasModData(mod)
    log("INITIAL_STATE has=" .. tostring(has_data))

    if not has_data then
        Isaac.SaveModData(mod, MARKER)
        if not Isaac.HasModData(mod) then
            fail("save_not_visible")
            return
        end
        if Isaac.LoadModData(mod) ~= MARKER then
            fail("load_after_save_mismatch")
            return
        end
        log("SAVE_OK")
        log("RESTART_REQUIRED exit_game_and_launch_again")
        return
    end

    if Isaac.LoadModData(mod) ~= MARKER then
        fail("unexpected_existing_data")
        return
    end
    log("LOAD_AFTER_RESTART_OK")

    Isaac.RemoveModData(mod)
    if Isaac.HasModData(mod) then
        fail("remove_not_visible")
        return
    end
    log("REMOVE_OK")
    log("COMPLETE")
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, on_game_started)
