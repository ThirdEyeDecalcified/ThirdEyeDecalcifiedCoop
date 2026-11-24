--[[
    Overkill Coop controller link - tells the DAHPadRouter xinput DLL where the game's viewport is and what
    the gamepad key names' internal IDs are. It writes padrouter_handshake.txt into the
    UE4SS folder; the DLL reads it from there.

    (loaded by main.lua)
]]

local UEHelpers = require("UEHelpers")

local MOD = "OverkillCoop pad link"
local FILE = "padrouter_handshake.txt"

local KEYS = {
    "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
    "Gamepad_Special_Right", "Gamepad_Special_Left", "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick",
    "Gamepad_LeftShoulder", "Gamepad_RightShoulder",
    "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
    "Gamepad_LeftStick_Up", "Gamepad_LeftStick_Down", "Gamepad_LeftStick_Left", "Gamepad_LeftStick_Right",
    "Gamepad_RightStick_Up", "Gamepad_RightStick_Down", "Gamepad_RightStick_Left", "Gamepad_RightStick_Right",
    "Gamepad_LeftX", "Gamepad_LeftY", "Gamepad_RightX", "Gamepad_RightY",
    "Gamepad_LeftTriggerAxis", "Gamepad_RightTriggerAxis",
}

local function log(fmt, ...)
    print(string.format("[%s] " .. fmt .. "\n", MOD, ...))
end

-- Remove the previous session's handshake so the DLL never reads a stale address.
os.remove(FILE)

local lastWritten = nil
local keyLines = nil
local failedOnce = false

local function buildKeyLines()
    local lines = {}
    for _, name in ipairs(KEYS) do
        local ok, idx = pcall(function() return FName(name):GetComparisonIndex() end)
        if not ok or type(idx) ~= "number" or idx <= 0 then
            if not failedOnce then
                failedOnce = true
                log("ERROR: could not get the ID of key '%s' (%s). Send UE4SS.log.", name, tostring(idx))
            end
            return nil
        end
        lines[#lines + 1] = string.format("key %s=%d", name, idx)
    end
    return lines
end

-- Address of player N's PlayerInput object (0 = none). Index 0 = Player 1, 1 = Player 2.
local function playerInputAddress(index)
    local ok, addr = pcall(function()
        local world = UEHelpers.GetWorld()
        local statics = UEHelpers.GetGameplayStatics()
        if not (world and world:IsValid() and statics and statics:IsValid()) then return 0 end
        local pc = statics:GetPlayerController(world, index)
        if not (pc and pc:IsValid()) then return 0 end
        local input = pc.PlayerInput
        if not (input and input:IsValid()) then return 0 end
        return input:GetAddress()
    end)
    if ok and type(addr) == "number" then return addr end
    return 0
end

-- Address of player N's aiming component (the character's TargetComponent), 0 = none.
-- The DLL uses it to tell whose aim point the game is asking for.
local function targetComponentAddress(index)
    local ok, addr = pcall(function()
        local world = UEHelpers.GetWorld()
        local statics = UEHelpers.GetGameplayStatics()
        if not (world and world:IsValid() and statics and statics:IsValid()) then return 0 end
        local pc = statics:GetPlayerController(world, index)
        if not (pc and pc:IsValid()) then return 0 end
        local pawn = pc.Pawn
        if not (pawn and pawn:IsValid()) then return 0 end
        local tc = pawn.m_pTargetComponent
        if not (tc and tc:IsValid()) then return 0 end
        return tc:GetAddress()
    end)
    if ok and type(addr) == "number" then return addr end
    return 0
end

-- Everything that belongs to player N: controller, character, its components, weapons and
-- mental abilities. The DLL uses these to tell which player the game's code is working for.
local function addr(o)
    if not (o and o:IsValid()) then return nil end
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok and type(a) == "number" and a ~= 0 then return a end
    return nil
end
local function forEachIn(arr, fn)
    if not arr then return end
    pcall(function() arr:ForEach(function(_, e) local okg, v = pcall(function() return e:get() end); fn(okg and v or e) end) end)
end
-- The HUD part below walks every UI widget in the game (thousands) and reads their
-- properties: far too slow to do every second (it was a frame hitch). It is cached, and
-- rebuilt only when the mod moves the HUDs, a player joins or leaves, or every 15 seconds.
local widgetCache = {}   -- [index] = { at, pc, hudAt, list }
local function hudStamp()
    local st = OverkillCoop and OverkillCoop.state
    return st and st.hudPlacedAt or 0
end
local function playerObjects(index)
    local out, seen = {}, {}
    local function add(o)
        local a = addr(o)
        if a and not seen[a] then seen[a] = true; out[#out + 1] = a end
    end
    pcall(function()
        local world = UEHelpers.GetWorld()
        local statics = UEHelpers.GetGameplayStatics()
        local pc = statics:GetPlayerController(world, index)
        if not (pc and pc:IsValid()) then return end
        add(pc)
        pcall(function() add(pc.PlayerState) end)
        pcall(function() add(pc.PlayerCameraManager) end)
        pcall(function() add(pc.MyHUD) end)
        pcall(function() add(pc.PlayerInput) end)
        local pawn = pc.Pawn
        if not (pawn and pawn:IsValid()) then return end
        add(pawn)
        -- The character's components by name (always works), then every component (if supported).
        for _, f in ipairs({ "m_pTargetComponent", "m_pLockOnComponent", "m_pFocusComponent", "m_pMentalAbilityComponent",
                             "m_pCameraHandle", "m_pWeaponComponent", "m_pEquipmentManagerComponent", "m_pStatsComponent",
                             "m_pDamageComponent", "m_pInteractionsComponent", "m_pAITargetComponent",
                             "m_pWeaponAndAbilitySelection", "m_pInputActionsComponent", "m_pJetpackPilotComponent",
                             "m_pDashComponent", "m_pMissionGameplayComponent", "m_pEffectComponent",
                             "m_pGameplayEffectTagsComponent", "m_pAnimationComponent", "m_pFollowCamera",
                             "m_pPKSpringArmComponent", "CharacterMovement", "Mesh", "CapsuleComponent" }) do
            pcall(function() add(pawn[f]) end)
        end
        pcall(function() add(pc.m_pGameplayToHud) end)
        local compClass = StaticFindObject("/Script/Engine.ActorComponent")
        pcall(function() forEachIn(pawn:K2_GetComponentsByClass(compClass), add) end)
        pcall(function() forEachIn(pc:K2_GetComponentsByClass(compClass), add) end)
        local eq = pawn.m_pEquipmentManagerComponent
        if eq and eq:IsValid() then
            pcall(function() forEachIn(eq.m_aWeaponList, add) end)
            pcall(function() forEachIn(eq:GetCurrentWeapons(), add) end)
        end
        local mental = pawn.m_pMentalAbilityComponent
        if mental and mental:IsValid() then pcall(function() forEachIn(mental.m_aPlayerMentalAbilities, add) end) end
    end)
    -- The player's own HUD pieces (health bar, weapon slot...), so they read their own player.
    local wc = widgetCache[index]
    local okPc, pcNow = pcall(function() return UEHelpers.GetGameplayStatics():GetPlayerController(UEHelpers.GetWorld(), index) end)
    local pcNowAddr = okPc and addr(pcNow) or nil
    if wc and wc.pc == pcNowAddr and wc.hudAt == hudStamp() and os.clock() - wc.at < 15 then
        for _, a in ipairs(wc.list) do if not seen[a] then seen[a] = true; out[#out + 1] = a end end
        table.sort(out)
        return out
    end
    local before = #out
    pcall(function()
        local pc = pcNow
        local pcAddr = pcNowAddr
        if not pcAddr then return end
        for _, w in ipairs(FindAllOf("UserWidget") or {}) do
            local okO, owner = pcall(function() return w:GetOwningPlayer() end)
            if okO and addr(owner) == pcAddr then
                add(w)
                -- and the pieces inside it (brackets, images, slots, its widget tree), since the
                -- game often asks "who is the player?" from one of those
                pcall(function() add(w.WidgetTree) end)
                pcall(function() add(w.Slot) end)
                pcall(function()
                    local c = w:GetClass()
                    local depth = 0
                    while c and c:IsValid() and depth < 3 do
                        local cn = c:GetFName():ToString()
                        if cn == "UserWidget" then break end
                        c:ForEachProperty(function(pp)
                            if pp:GetClass():GetFName():ToString() == "ObjectProperty" then
                                local okV, v = pcall(function() return w[pp:GetFName():ToString()] end)
                                if okV and v and type(v) == "userdata" and v.IsValid and v:IsValid() then
                                    add(v)
                                    pcall(function() add(v.Slot) end)
                                end
                            end
                        end)
                        c = c:GetSuperStruct()
                        depth = depth + 1
                    end
                end)
            end
        end
    end)
    local list = {}
    for k = before + 1, #out do list[#list + 1] = out[k] end
    widgetCache[index] = { at = os.clock(), pc = pcNowAddr, hudAt = hudStamp(), list = list }
    table.sort(out)
    return out
end

local function controllerAddress(index)
    local ok, a = pcall(function()
        local pc = UEHelpers.GetGameplayStatics():GetPlayerController(UEHelpers.GetWorld(), index)
        return addr(pc) or 0
    end)
    return (ok and a) or 0
end

-- "vertical" = left/right halves, "horizontal" = top/bottom.
local function splitLayout()
    local ok, v = pcall(function()
        local gms = StaticFindObject("/Script/EngineSettings.Default__GameMapsSettings")
        if not (gms and gms:IsValid()) then return 1 end
        return gms.TwoPlayerSplitscreenLayout
    end)
    if ok and tonumber(v) == 0 then return "horizontal" end
    return "vertical"
end

local function writeHandshake()
    local vp = FindFirstOf("GameViewportClient")
    if not vp or not vp:IsValid() then return end
    local okA, address = pcall(function() return vp:GetAddress() end)
    if not okA or type(address) ~= "number" then
        if not failedOnce then
            failedOnce = true
            log("ERROR: could not read the viewport address (%s)", tostring(address))
        end
        return
    end
    local p1 = playerInputAddress(0)
    local p2 = playerInputAddress(1)
    -- Players 3 and 4 (groundwork: the DLL doesn't route pads 3 and 4 to them yet)
    local p3 = playerInputAddress(2)
    local p4 = playerInputAddress(3)

    local t1 = targetComponentAddress(0)
    local t2 = p2 ~= 0 and targetComponentAddress(1) or 0
    local layout = splitLayout()
    local o1 = playerObjects(0)
    local o2 = p2 ~= 0 and playerObjects(1) or {}
    local c2 = p2 ~= 0 and controllerAddress(1) or 0
    local function join(list) local t = {} for i, a in ipairs(list) do t[i] = string.format("%X", a) end return table.concat(t, ",") end
    local signature = string.format("%X/%X/%X/%X/%X/%s/%X/%s/%s/%X/%X", address, p1, p2, t1, t2, layout, c2, join(o1), join(o2), p3, p4)
    if signature == lastWritten then return end

    keyLines = keyLines or buildKeyLines()
    if not keyLines then return end

    local out = {
        string.format("viewport=0x%X", address),
        string.format("p1input=0x%X", p1),
        string.format("p2input=0x%X", p2),
        string.format("p1target=0x%X", t1),
        string.format("p2target=0x%X", t2),
        "layout=" .. layout,
        string.format("p2ctrl=0x%X", c2),
        string.format("p3input=0x%X", p3),
        string.format("p4input=0x%X", p4),
    }
    for _, a in ipairs(o1) do out[#out + 1] = string.format("p1obj=0x%X", a) end
    for _, a in ipairs(o2) do out[#out + 1] = string.format("p2obj=0x%X", a) end
    for _, l in ipairs(keyLines) do out[#out + 1] = l end
    out[#out + 1] = "end"

    local tmp = FILE .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then
        log("ERROR: could not write %s", tmp)
        return
    end
    f:write(table.concat(out, "\n"), "\n")
    f:close()
    os.remove(FILE)
    os.rename(tmp, FILE)

    lastWritten = signature
    log("Handshake written: viewport 0x%X, P1 input 0x%X, P2 input 0x%X, aim P1 0x%X P2 0x%X (%s), %d+%d player objects, %d key IDs",
        address, p1, p2, t1, t2, layout, #o1, #o2, #keyLines)
end

-- The handshake is written from a game-thread hook (the character's tick), once a second.
-- A LoopAsync timer only runs until that hook is in place: Lua running on the timer thread
-- at the same time as the game thread is what corrupts UE4SS ("Ref was not function").
local hooked, lastWrite = false, -1000
local function safeWrite()
    local ok, err = pcall(writeHandshake)
    if not ok and not failedOnce then
        failedOnce = true
        log("ERROR: %s", tostring(err))
    end
end
local function tryHook()
    if hooked then return end
    local ok = pcall(function()
        RegisterHook("/Game/Blueprints/Character/Player/BP_CharacterPlayer.BP_CharacterPlayer_C:ReceiveTick", function()
            local now = os.clock()
            if now - lastWrite >= 1.0 then
                lastWrite = now
                safeWrite()
            end
        end)
    end)
    hooked = ok
    if ok then log("Writing the handshake from the game thread now.") end
end

LoopAsync(1000, function()
    if hooked then return true end   -- stop the timer for good
    ExecuteInGameThread(function()
        safeWrite()
        tryHook()
    end)
    return false
end)

log("Loaded. Waiting for the game viewport...")
