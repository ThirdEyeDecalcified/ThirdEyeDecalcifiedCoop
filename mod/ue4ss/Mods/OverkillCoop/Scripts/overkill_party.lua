--[[
    Third Eye Decalcified Co-op - Players 3 and 4 (groundwork, TEST)
    Adds a third and fourth local player next to Player 1, each with their own controller,
    body, part of the screen, HUD and name tag. Players 1 and 2 are left exactly as they are.
    Not there yet: pads 3 and 4 driving them (the controller DLL routes pad 2 only so far),
    and everything the mod adds for Player 2 (PK arcs, lock-on, wheel, skins...).
    Trainer > Players: "Players 3 and 4". Ctrl+Shift+F3 / Ctrl+Shift+F4 add or remove them too.
]]

local OK = OverkillCoop
if not OK then return end
local state, CFG, log, valid = OK.state, OK.CFG, OK.log, OK.valid
local getPawn = OK.getPawn

state.extraPlayers = state.extraPlayers or {}     -- [3] / [4] = controller
local TAG_COLORS = { [3] = { R = 255, G = 40, B = 40, A = 255 }, [4] = { R = 40, G = 110, B = 255, A = 255 } }   -- P3 red, P4 blue
local tags = {}                                     -- [slot] = text actor over that player's head

local function setLayout()
    -- three players: Player 1 gets the whole top half (the "favour top" layout)
    pcall(function()
        local gms = StaticFindObject("/Script/EngineSettings.Default__GameMapsSettings")
        gms.ThreePlayerSplitscreenLayout = 0
    end)
end

local function nextToP1(pc, slot, toPc)
    local p1 = getPawn(toPc or OK.player1Controller())
    local pw = getPawn(pc)
    if not (valid(p1) and valid(pw)) then return false end
    local ok = pcall(function()
        local l = p1:K2_GetActorLocation()
        local r = p1:K2_GetActorRotation()
        local side = slot == 3 and -250 or 250
        local yaw = math.rad(r.Yaw)
        local at = { X = l.X - math.sin(yaw) * side - math.cos(yaw) * 150, Y = l.Y + math.cos(yaw) * side - math.sin(yaw) * 150, Z = l.Z + 40 }
        pw:K2_SetActorLocation(at, false, {}, true)
        pw:K2_SetActorRotation(r, true)
    end)
    return ok
end

local function moveHud(pc)
    for i, w in ipairs(OK.hudWidgetsOf(pc)) do
        if valid(w) then
            pcall(function() w:RemoveFromParent() end)
            pcall(function() w:SetOwningPlayer(pc) end)
            pcall(function() w:AddToPlayerScreen(i - 1) end)
        end
    end
end

local function makeTag(slot, pw)
    -- the co-op tags (name, distance, skin icon) cover Players 3 and 4 now
    if OK.CFG.PARTNER_MARKERS then return end
    local cls = StaticFindObject("/Script/Engine.TextRenderActor")
    if not (valid(cls) and valid(pw)) then return end
    pcall(function()
        local a = OK.getWorld():SpawnActor(cls, pw:K2_GetActorLocation(), { Pitch = 0, Yaw = 0, Roll = 0 })
        local tr = a.TextRender
        tr:K2_SetText(FText("P" .. slot))
        tr:SetTextRenderColor(TAG_COLORS[slot])
        tr:SetHorizontalAlignment(1)
        pcall(function() tr:SetWorldSize(40) end)
        a:SetActorEnableCollision(false)
        pcall(function() a:SetOwner(pw) end)
        pcall(function() tr:SetOwnerNoSee(true) end)     -- not over your own head
        a:K2_AttachToActor(pw, FName("None"), 2, 1, 1, false)
        a:K2_SetActorRelativeLocation({ X = 0, Y = 0, Z = 130 }, false, {}, true)
        tags[slot] = a
    end)
end

local function addPlayer(slot)
    if valid(state.extraPlayers[slot]) then return end
    -- the game counts local players in order: without Player 2, a "Player 3" would take Player 2's
    -- place (and pad 2 would drive it), so Player 2 has to be in first
    if not valid(state.p2) then log("Player %d: bring in Player 2 first (Start on pad 2)", slot) return end
    if slot == 4 and not valid(state.extraPlayers[3]) then addPlayer(3) end
    local world, statics = OK.getWorld(), OK.getStatics()
    if not (world and statics) then return end
    setLayout()
    local ok, pc = pcall(function() return statics:CreatePlayer(world, slot - 1, true) end)
    if not (ok and valid(pc)) then log("Player %d: couldn't be created (%s)", slot, tostring(pc)) return end
    state.extraPlayers[slot] = pc
    log("=== Player %d joined (ControllerId %d, TEST: no pad yet) ===", slot, slot - 1)
    nextToP1(pc, slot)
    OK.later(0.1, "p" .. slot .. "NextToP1", function() if valid(pc) then nextToP1(pc, slot) end end)
    OK.later(1.0, "p" .. slot .. "Setup", function()
        if not valid(pc) then return end
        nextToP1(pc, slot)
        moveHud(pc)
        makeTag(slot, getPawn(pc))
        -- same look settings as Player 2 (up/down on the right stick was the wrong way round)
        if OK.CFG.P2_INVERT_LOOK_Y then
            pcall(function() StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(OK.getWorld(), "InvertAxisKey Gamepad_RightY", pc) end)
        end
        if OK.CFG.P2_INVERT_LOOK_X then
            pcall(function() StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(OK.getWorld(), "InvertAxisKey Gamepad_RightX", pc) end)
        end
        log("Player %d: body %s, HUD on their own part of the screen", slot, OK.shortName(getPawn(pc)))
        -- the same pass Player 2 gets: nothing of theirs may point at Player 1's things
        if state.rewirePlayer then pcall(state.rewirePlayer, pc, "Player " .. slot) end
        OK.later(2.0, "p" .. slot .. "Rewire", function() if valid(pc) and state.rewirePlayer then pcall(state.rewirePlayer, pc, "Player " .. slot .. " +2s") end end)
    end)
end

local function removePlayer(slot)
    if slot == 3 and valid(state.extraPlayers[4]) then removePlayer(4) end
    local pc = state.extraPlayers[slot]
    state.extraPlayers[slot] = nil
    if valid(tags[slot]) then pcall(function() tags[slot]:K2_DestroyActor() end) end
    tags[slot] = nil
    if not valid(pc) then return end
    pcall(function() OK.getStatics():RemovePlayer(pc, true) end)
    log("=== Player %d left ===", slot)
end
-- after a game over: a Player 3 / 4 with no living body gets a fresh one from the game
-- (RestartPlayer), then their HUD and tag are set up again
state.partyFixBodies = function()
    for slot = 3, 4 do
        local pc = state.extraPlayers and state.extraPlayers[slot]
        if valid(pc) then
            local pw = getPawn(pc)
            local hp = valid(pw) and OK.healthRatio(pw) or nil
            local dead = not valid(pw) or (type(hp) == "number" and hp <= 0.001)
            pcall(function() if valid(pw) and pw:IsDead() then dead = true end end)
            if dead then
                local gm = nil
                pcall(function() gm = OK.getStatics():GetGameMode(OK.getWorld()) end)
                if valid(pw) then pcall(function() pc:UnPossess() end); pcall(function() pw:K2_DestroyActor() end) end
                local ok = valid(gm) and pcall(function() gm:RestartPlayer(pc) end)
                log("Player %d had no living body after the game over: %s", slot, ok and "given a new one" or "couldn't restart them")
                OK.later(1.0, "p" .. slot .. "Reborn", function()
                    if not valid(pc) then return end
                    nextToP1(pc, slot)
                    moveHud(pc)
                    if valid(tags[slot]) then pcall(function() tags[slot]:K2_DestroyActor() end) end
                    makeTag(slot, getPawn(pc))
                end)
            else
                nextToP1(pc, slot)
            end
        end
    end
end
-- teleport combo: Players 3 and 4 come to whoever pressed it
state.partyBringTo = function(toPc)
    for slot = 3, 4 do
        local pc = state.extraPlayers and state.extraPlayers[slot]
        if valid(pc) and OK.keyOf(pc) ~= OK.keyOf(toPc) then nextToP1(pc, slot, toPc) end
    end
end
state.removeExtraPlayers = function() removePlayer(3) end

-- the tags turn to face Player 1's camera (they read backwards otherwise)
OK.addTickJob("partyTags", 0.1, function()
    if not (tags[3] or tags[4]) then return end
    local cam = nil
    pcall(function() cam = OK.player1Controller().PlayerCameraManager:GetCameraLocation() end)
    if not cam then return end
    for _, a in pairs(tags) do
        if valid(a) then
            pcall(function()
                local l = a:K2_GetActorLocation()
                local yaw = math.deg(math.atan(cam.Y - l.Y, cam.X - l.X))
                a:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false)
            end)
        end
    end
end)

-- Players 3 and 4 have no downed / revive system yet: instead of dying (the game has no way
-- back for them) they're knocked out: back to full and next to Player 1
OK.addTickJob("partyKnockout", 0.0, function()   -- every frame: one big hit must not get through
    if OK.CFG.DOWNED_SYSTEM then return end   -- the downed / revive system looks after Players 3 and 4 now
    local g = state.trGod
    local god = g == "On" or g == "Both players" or g == "All players"
    for slot = 3, 4 do
        local pc = state.extraPlayers[slot]
        local pw = valid(pc) and getPawn(pc) or nil
        if valid(pw) then
            local hp = OK.healthRatio(pw)
            if god then
                if type(hp) == "number" and hp < 1.0 then pcall(function() OK.setRatio(OK.stat(pw, "m_pHealthStat"), 1.0) end) end
                pcall(function() OK.setRatio(OK.stat(pw, "m_pShieldStat"), 1.0) end)
            elseif type(hp) == "number" and hp <= 0.35 then
                -- knocked out: never a real death (that's a game over for everyone).
                -- Back to full health, a few seconds of cover, next to Player 1
                pcall(function() OK.setRatio(OK.stat(pw, "m_pHealthStat"), 1.0) end)
                pcall(function() OK.setRatio(OK.stat(pw, "m_pShieldStat"), 1.0) end)
                state.partySafeUntil = state.partySafeUntil or {}
                state.partySafeUntil[slot] = os.clock() + 3.0
                nextToP1(pc, slot)
                log("Player %d was knocked out: back on their feet next to Player 1", slot)
            elseif state.partySafeUntil and os.clock() < (state.partySafeUntil[slot] or 0) then
                pcall(function() OK.setRatio(OK.stat(pw, "m_pHealthStat"), 1.0) end)
            end
        end
    end
end)

-- map changes: take them out first, like Player 2
OK.onWorldChange(function() state.extraPlayers = {}; tags = {} end)
if type(RegisterLoadMapPreHook) == "function" then
    pcall(function() RegisterLoadMapPreHook(function() pcall(removePlayer, 3) end) end)
end

for slot, key in pairs({ [3] = Key.F3, [4] = Key.F4 }) do
    RegisterKeyBind(key, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        OK.runGame("extraPlayer" .. slot, function()
            if valid(state.extraPlayers[slot]) then removePlayer(slot) else addPlayer(slot) end
        end)
    end)
end

state.trainerExtras = state.trainerExtras or {}
state.trainerExtras[#state.trainerExtras + 1] = {
    key = "x_party", page = 3, label = "TEST  Players 3 and 4 (groundwork: no pad control yet)",
    options = { "Off", "Player 3", "Players 3 + 4" },
    get = function()
        if valid(state.extraPlayers[4]) then return "Players 3 + 4" end
        if valid(state.extraPlayers[3]) then return "Player 3" end
        return "Off"
    end,
    set = function(v)
        if v == "Off" then removePlayer(3)
        elseif v == "Player 3" then removePlayer(4); addPlayer(3)
        else addPlayer(3); addPlayer(4) end
    end,
    reset = function() removePlayer(3) end,
}

log("Players 3 and 4: groundwork loaded (Trainer > Players, or Ctrl+Shift+F3 / Ctrl+Shift+F4)")

-- Player 1's lock-on crosshair (the game's focused-target widget) is a screen-space widget
-- component, and those draw on every split-screen view. Tie it to Player 1's view only.
OK.addTickJob("partyLockMarker", 1.0, function()
    -- 3-4 players only: with two this same widget is the PK yellow marker Player 2 needs
    local any = false
    for slot = 3, 4 do if valid(state.extraPlayers[slot]) then any = true end end
    if not any then return end
    local p1 = OK.player1Controller()
    local lp = nil
    pcall(function() lp = p1.Player end)
    if not valid(lp) then return end
    local gs = FindFirstOf("GameStateBase")
    local okM, mgr = pcall(function() return gs:GetHighlightableSceneObjectManager() end)
    if not (okM and valid(mgr)) then return end
    for _, name in ipairs({ "m_pFocusedOpportunityWidget_Mental", "m_pFocusedOpportunityWidget_Weapon", "m_pFocusedOpportunityWidget" }) do
        local comp = OK.subObj(mgr, name)
        if comp then
            local okO, cur = pcall(function() return comp:GetOwnerPlayer() end)
            if not (okO and valid(cur) and OK.keyOf(cur) == OK.keyOf(lp)) then
                local ok = pcall(function() comp:SetOwnerPlayer(lp) end)
                if not state["lockMarkerLogged" .. name] then
                    state["lockMarkerLogged" .. name] = true
                    log("Lock-on crosshair %s: only on Player 1's screen %s", name, ok and "(set)" or "(couldn't set)")
                end
            end
        end
    end
end)

-- Start on pad 3 / 4 (from the DLL): join, or hold it 2 s to drop out, like Player 2
OK.addTickJob("partyPadStart", 0.25, function()
    local f = io.open("padrouter_party_request.txt", "r")
    if not f then return end
    local text = f:read("*a") or ""
    f:close()
    os.remove("padrouter_party_request.txt")
    for word, who in text:gmatch("(%a+)(%d)") do
        local slot = tonumber(who)
        if slot == 3 or slot == 4 then
            if word == "join" then
                log("Start on pad %d: Player %d joins", slot, slot)
                OK.runGame("padJoin" .. slot, function() addPlayer(slot) end)
            elseif word == "drop" then
                log("Start held on pad %d: Player %d drops out", slot, slot)
                OK.runGame("padDrop" .. slot, function() removePlayer(slot) end)
            end
        end
    end
end)
