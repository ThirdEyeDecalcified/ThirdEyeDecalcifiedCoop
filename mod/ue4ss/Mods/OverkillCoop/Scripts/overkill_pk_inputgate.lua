--[[
    InputGate.lua  -  temporarily unbinds the game's own actions from chosen keys
    (R3 / L3 by default) while PK is holding something, then puts them back.

    How it works:
      * Unreal keeps "Action Mappings" (e.g. LookBack -> Gamepad_RightThumbstick)
        in the InputSettings object.
      * UInputSettings::RemoveActionMapping / AddActionMapping are Blueprint-
        callable, so Lua can pull the R3 mappings out at runtime and restore them.
      * Raw key state (PlayerController:IsInputKeyDown) is tracked regardless of
        mappings, so the PK overhaul still sees R3 while the game doesn't.
      * Nothing is saved to disk: if anything goes wrong, restarting the game
        restores the original bindings.

    Swaps only happen while the gated keys are physically released, so the game
    never sees a press without its matching release (no stuck actions).
]]

local Config = require("overkill_pk_settings")

local InputGate = {}

local MOD = "[OverkillCoop PK input] "
local function log(msg) print(MOD .. tostring(msg) .. "\n") end

local settings = nil
local removed = nil         -- list of mapping tables currently pulled out (nil = not gated)
local warnedNone = false

local function getSettings()
    if settings and settings:IsValid() then return settings end
    settings = StaticFindObject("/Script/Engine.Default__InputSettings")
    if not (settings and settings:IsValid()) then settings = nil end
    return settings
end

local function gatedKeySet()
    local set = {}
    for _, k in ipairs(Config.InputGate.Keys) do set[k] = true end
    return set
end

-- Copy a live FInputActionKeyMapping into a plain Lua table we can pass back later
local function copyMapping(m)
    return {
        ActionName = FName(m.ActionName:ToString()),
        bShift = m.bShift, bCtrl = m.bCtrl, bAlt = m.bAlt, bCmd = m.bCmd,
        Key = { KeyName = FName(m.Key.KeyName:ToString()) },
    }
end

local function collectGatedMappings(s)
    local keys = gatedKeySet()
    local found = {}
    local ok = pcall(function()
        s.ActionMappings:ForEach(function(_, elem)
            local m = elem:get()
            local keyName = m.Key.KeyName:ToString()
            if keys[keyName] then table.insert(found, copyMapping(m)) end
        end)
    end)
    if not ok then return nil end
    return found
end

local function engage()
    local s = getSettings()
    if not s then return end
    local list = collectGatedMappings(s)
    if not list then return end
    if #list == 0 then
        if not warnedNone then
            warnedNone = true
            log("No action mappings use the gated keys. The game may read R3/L3 through its own input layer; " ..
                "press F5 to list all mappings. If R3's action isn't there, the Blueprint route is needed.")
        end
        removed = {} -- treat as gated so we don't retry every tick
        return
    end
    for i, m in ipairs(list) do
        pcall(function() s:RemoveActionMapping(m, i == #list) end) -- rebuild keymaps on the last one
        if Config.Debug then log("Unbound " .. m.ActionName:ToString() .. " from " .. m.Key.KeyName:ToString()) end
    end
    removed = list
end

local function release()
    local s = getSettings()
    if s and removed then
        for i, m in ipairs(removed) do
            pcall(function() s:AddActionMapping(m, i == #removed) end)
            if Config.Debug then log("Restored " .. m.ActionName:ToString() .. " on " .. m.Key.KeyName:ToString()) end
        end
    end
    removed = nil
end

-- Call every tick. wanted = should the game's R3/L3 actions be blocked right now.
-- isDown(keyName) = raw key state from the player controller.
function InputGate.Update(wanted, isDown)
    if not Config.InputGate.Enabled then
        if removed then release() end
        return
    end
    local gated = removed ~= nil
    if wanted == gated then return end
    -- Only swap while every gated key is up, so no press/release pair gets split
    for _, k in ipairs(Config.InputGate.Keys) do
        if isDown(k) then return end
    end
    if wanted then engage() else release() end
end

-- Immediate restore (mod toggled off, pawn lost, etc.)
function InputGate.ForceRelease()
    if removed then release() end
end

function InputGate.IsGated() return removed ~= nil end

-- F5 helper: print every action mapping so you can see what R3/L3 do
function InputGate.DumpMappings()
    local s = getSettings()
    if not s then log("InputSettings not found."); return end
    log("==== ACTION MAPPINGS ====")
    pcall(function()
        s.ActionMappings:ForEach(function(_, elem)
            local m = elem:get()
            log(string.format("  %-32s %s", m.ActionName:ToString(), m.Key.KeyName:ToString()))
        end)
    end)
    log("==== AXIS MAPPINGS (gamepad) ====")
    pcall(function()
        s.AxisMappings:ForEach(function(_, elem)
            local m = elem:get()
            local k = m.Key.KeyName:ToString()
            if string.find(k, "Gamepad", 1, true) then
                log(string.format("  %-32s %s  x%.2f", m.AxisName:ToString(), k, m.Scale))
            end
        end)
    end)
    log("Gate currently " .. (removed and "ENGAGED" or "off"))
    log("==== END ====")
end

return InputGate
