--[[
    Third Eye Decalcified Co-op (Destroy All Humans! 2020)
    Two-player split screen, a PK overhaul and an in-game trainer for Destroy All Humans! (2020).
    Created by Keaton and Claude.

    This file only loads the parts of the mod:
      overkill_coop.lua      split screen, Player 2, HUD, trainer
      overkill_pk.lua        PK overhaul (settings in overkill_pk_settings.lua)
      overkill_padlink.lua   tells the controller DLL (xinput1_3/1_4/9_1_0.dll) about the game
      overkill_extras.lua    extra trainer options
      overkill_map.lua       the aerial map with pins (Trainer > World)
      overkill_wheel.lua     the mind & weapons wheel (hold LB), the power panel and the mind powers
      overkill_jukebox.lua   the radio stations in the trainer (game music or the mod's songs)
      overkill_party.lua     Players 3 and 4 (groundwork)
      overkill_freecam.lua   free camera for filming (Ctrl+Shift+F12)
]]

local function load(name)
    local ok, err = pcall(require, name)
    if not ok then print(string.format("[OverkillCoop] couldn't load %s: %s\n", name, tostring(err))) end
end

-- The split-screen part filters its own hotkeys; give the other parts the normal key binding back.
local realBind = RegisterKeyBind
load("overkill_coop")
RegisterKeyBind = realBind
load("overkill_pk")
load("overkill_padlink")
load("overkill_extras")
load("overkill_map")
load("overkill_wheel")
load("overkill_jukebox")
load("overkill_party")
load("overkill_freecam")
