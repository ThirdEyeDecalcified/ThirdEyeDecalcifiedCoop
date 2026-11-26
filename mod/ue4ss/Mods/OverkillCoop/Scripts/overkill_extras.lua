--[[
    Third Eye Decalcified Co-op - extra trainer options (loaded by main.lua)
    Each one is marked TEST in the menu until it's been tried in the game.
    Like the rest of the trainer, everything goes back to normal when you leave a map.
]]

local OK = OverkillCoop
if not OK then return end
local state, CFG, log, valid = OK.state, OK.CFG, OK.log, OK.valid
local subObj, getPawn = OK.subObj, OK.getPawn

state.trainerExtras = state.trainerExtras or {}
local function add(e) state.trainerExtras[#state.trainerExtras + 1] = e end

local function players()
    local list = { OK.player1Controller() }
    if valid(state.p2) then list[#list + 1] = state.p2 end
    for slot = 3, 4 do   -- Players 3 and 4 get the same trainer settings
        local xp = state.extraPlayers and state.extraPlayers[slot]
        if valid(xp) then list[#list + 1] = xp end
    end
    return list
end

local function npcs(maxDist)
    local list = {}
    local center = nil
    pcall(function() center = getPawn(OK.player1Controller()):K2_GetActorLocation() end)
    local pk = {}
    for _, pc in ipairs(players()) do local pw = getPawn(pc); if valid(pw) then pk[OK.keyOf(pw)] = true end end
    pcall(function()
        local out = {}
        OK.getStatics():GetAllActorsOfClass(OK.getWorld(), StaticFindObject("/Script/Engine.Character"), out)
        for _, a in ipairs(out) do
            local v = a
            if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
            if valid(v) and not pk[OK.keyOf(v)] then
                local near = true
                if maxDist and center then
                    local okL, l = pcall(function() return v:K2_GetActorLocation() end)
                    if okL and l then
                        local dx, dy, dz = l.X - center.X, l.Y - center.Y, l.Z - center.Z
                        near = dx * dx + dy * dy + dz * dz < maxDist * maxDist
                    end
                end
                if near then list[#list + 1] = v end
            end
        end
    end)
    return list
end

------------------------------------------------------------------------------------------
-- TEST Run speed (both players)
------------------------------------------------------------------------------------------
local SPEED_FIELDS = { "MaxWalkSpeed", "MaxWalkSpeedCrouched", "MaxSwimSpeed", "MaxFlySpeed", "MaxAcceleration" }
local runFactor, runBase = 1.0, {}
local RUN = { ["Normal"] = 1.0, ["x1.5"] = 1.5, ["x2"] = 2.0, ["x3"] = 3.0 }
local function applyRun()
    for _, pc in ipairs(players()) do
        local pw = getPawn(pc)
        local cm = subObj(pw, "CharacterMovement")
        if cm then
            local k = OK.keyOf(cm)
            if not runBase[k] then
                runBase[k] = {}
                for _, f in ipairs(SPEED_FIELDS) do pcall(function() runBase[k][f] = cm[f] end) end
            end
            for _, f in ipairs(SPEED_FIELDS) do
                local b = runBase[k][f]
                if type(b) == "number" then pcall(function() cm[f] = b * runFactor end) end
            end
        end
    end
end
add({ key = "x_run", page = 3, label = "Run speed (both players)", options = { "Normal", "x1.5", "x2", "x3" },
    get = function() return state.trRun or "Normal" end,
    set = function(v) state.trRun = v; runFactor = RUN[v] or 1.0; applyRun(); log("Trainer: run speed %s", v) end,
    reset = function() if runFactor ~= 1.0 then runFactor = 1.0; applyRun() end; state.trRun = nil; runBase = {} end })
OK.addTickJob("x_runKeep", 1.0, function() if runFactor ~= 1.0 then applyRun() end end)   -- new bodies too
OK.onWorldChange(function() runBase = {}; runFactor = 1.0; state.trRun = nil end)

------------------------------------------------------------------------------------------
-- TEST Camera field of view on foot (both players)
------------------------------------------------------------------------------------------
local FOVS = { ["Game default"] = nil, ["80"] = 80, ["100"] = 100, ["120"] = 120 }
local fovWanted = nil
local fovBase = {}   -- camera address -> its own field of view
local function applyFov()
    for _, pc in ipairs(players()) do
        local cam = subObj(pc, "PlayerCameraManager")
        if cam then
            if fovWanted then pcall(function() cam:SetFOV(fovWanted) end) else pcall(function() cam:UnlockFOV() end) end
        end
        -- the game draws through Crypto's own follow camera
        local fc = subObj(getPawn(pc), "m_pFollowCamera")
        if fc then
            local k = OK.keyOf(fc)
            if fovBase[k] == nil then
                local okF, f = pcall(function() return fc.FieldOfView end)
                fovBase[k] = (okF and type(f) == "number") and f or 90
                log("Trainer: field of view: Crypto's camera %s (was %.0f)", OK.shortName(fc), fovBase[k])
            end
            local want = fovWanted or fovBase[k]
            pcall(function() fc:SetFieldOfView(want) end)
            pcall(function() fc.FieldOfView = want end)
        end
        -- the game's own camera system (m_pCameraHandle) may set it every frame: find its FOV
        -- numbers once (logged), then push ours into them too
        local ch = subObj(getPawn(pc), "m_pCameraHandle")
        if ch then
            local k = "h" .. OK.keyOf(ch)
            if fovBase[k] == nil then
                fovBase[k] = {}
                pcall(function()
                    local c = ch:GetClass()
                    while c and valid(c) do
                        c:ForEachProperty(function(pp)
                            local n = pp:GetFName():ToString()
                            if n:lower():find("fov") or n:lower():find("fieldofview") then
                                local okV, v = pcall(function() return ch[n] end)
                                fovBase[k][#fovBase[k] + 1] = { n = n, v = okV and v or nil }
                                log("Trainer: field of view: camera handle %s.%s = %s", OK.shortName(ch), n, tostring(okV and v))
                            end
                        end)
                        local okS, sup = pcall(function() return c:GetSuperStruct() end)
                        c = okS and sup or nil
                    end
                end)
                if #fovBase[k] == 0 then log("Trainer: field of view: camera handle %s has no FOV setting", OK.shortName(ch)) end
            end
            for _, e in ipairs(fovBase[k]) do
                if type(e.v) == "number" then
                    local n = e.n
                    pcall(function() ch[n] = fovWanted or e.v end)
                end
            end
        end
        if cam then
            if fovWanted then pcall(function() cam.DefaultFOV = fovWanted end) end
        end
    end
end
OK.onWorldChange(function() fovBase = {} end)
add({ key = "x_fov", page = 4, label = "TEST  Camera field of view (both players)", options = { "Game default", "80", "100", "120" },
    get = function() return state.trFov or "Game default" end,
    set = function(v) state.trFov = v; fovWanted = FOVS[v]; applyFov(); log("Trainer: field of view %s", v) end,
    reset = function() if fovWanted then fovWanted = nil; applyFov() end; state.trFov = nil end })
OK.addTickJob("x_fovKeep", 0.0, function() if fovWanted then applyFov() end end)   -- every frame: the game sets it back

------------------------------------------------------------------------------------------
-- TEST NPC size (giant / tiny people)
------------------------------------------------------------------------------------------
local NPC_SIZES = { ["Normal"] = 1.0, ["Giant (x2)"] = 2.0, ["Huge (x3)"] = 3.0, ["Colossal (x10)"] = 10.0,
    ["Tiny (x0.5)"] = 0.5, ["Smallest (x0.1)"] = 0.1 }
local npcScale, npcTouched = 1.0, {}
-- growing lifts them by the extra capsule height first, so their feet don't end up in the
-- ground (the Colossal player sank into it the same way)
local function liftFor(a, from, to)
    if to <= from then return end
    local hh = 90
    pcall(function() hh = a.CapsuleComponent:GetUnscaledCapsuleHalfHeight() end)
    pcall(function()
        local l = a:K2_GetActorLocation()
        a:K2_SetActorLocation({ X = l.X, Y = l.Y, Z = l.Z + hh * (to - from) + 5 }, false, {}, true)
    end)
end
local function applyNpcSize()
    for _, n in ipairs(npcs(npcScale >= 5 and 15000 or 8000)) do
        local k = OK.keyOf(n)
        local was = npcTouched[k] or 1.0
        if was ~= npcScale then
            liftFor(n, was, npcScale)
            pcall(function() n:SetActorScale3D({ X = npcScale, Y = npcScale, Z = npcScale }) end)
            npcTouched[k] = npcScale ~= 1.0 and npcScale or nil
        end
    end
end
add({ key = "x_npcsize", page = 4, label = "People's size (NPCs near you)", options = { "Normal", "Giant (x2)", "Huge (x3)", "Colossal (x10)", "Tiny (x0.5)", "Smallest (x0.1)" },
    get = function() return state.trNpcSize or "Normal" end,
    set = function(v) state.trNpcSize = v; npcScale = NPC_SIZES[v] or 1.0; applyNpcSize(); log("Trainer: NPC size %s", v) end,
    reset = function() if npcScale ~= 1.0 then npcScale = 1.0; applyNpcSize() end; state.trNpcSize = nil; npcTouched = {} end })
OK.addTickJob("x_npcSizeKeep", 2.0, function() if npcScale ~= 1.0 then applyNpcSize() end end)
OK.onWorldChange(function() npcScale, npcTouched = 1.0, {}; state.trNpcSize = nil end)

------------------------------------------------------------------------------------------
-- TEST NPCs can't die
------------------------------------------------------------------------------------------
local noDeath = false
add({ key = "x_nodeath", page = 4, label = "TEST  People can't die (they heal back up)", options = { "Off", "On" },
    get = function() return state.trNoDeath or "Off" end,
    set = function(v) state.trNoDeath = v; noDeath = v == "On"; log("Trainer: NPCs can't die %s", v) end,
    reset = function() noDeath = false; state.trNoDeath = nil end })
OK.addTickJob("x_noDeath", 0.25, function()
    if not noDeath then return end
    for _, n in ipairs(npcs(6000)) do
        local r = OK.healthRatio(n)
        if type(r) == "number" and r > 0 and r < 0.35 then
            pcall(function() OK.setRatio(OK.stat(n, "m_pHealthStat"), 1.0) end)
        end
    end
end)
OK.onWorldChange(function() noDeath = false; state.trNoDeath = nil end)

------------------------------------------------------------------------------------------
-- TEST Hide the HUD per player
------------------------------------------------------------------------------------------
local hudHidden = { false, false }
-- Hiding: each of the player's HUD widgets is set hidden, remembering how it was; showing puts
-- every one back (and full opacity), including widgets the game made while it was hidden.
local hudWas = {}   -- widget key -> visibility before we hid it
local function setHud(i, hidden)
    local pc = players()[i]
    if not valid(pc) then return end
    for _, w in ipairs(OK.hudWidgetsOf(pc)) do
        local k = OK.keyOf(w)
        if hidden then
            if hudWas[k] == nil then
                local okV, v = pcall(function() return w:GetVisibility() end)
                hudWas[k] = (okV and type(v) == "number" and v ~= 1 and v ~= 2) and v or 3
            end
            pcall(function() w:SetVisibility(2) end)
        else
            local v = hudWas[k]
            if v ~= nil then pcall(function() w:SetVisibility(v) end); hudWas[k] = nil end
            pcall(function() w:SetRenderOpacity(1.0) end)
        end
    end
end
OK.onWorldChange(function() hudWas = {} end)
state.setHudHidden = function(i, hidden) setHud(i, hidden or hudHidden[i]) end   -- (the wheel uses this too)
add({ key = "x_hud", page = 3, label = "TEST  Hide the HUD", options = { "Off", "Player 1", "Player 2", "Both" },
    get = function() return state.trHud or "Off" end,
    set = function(v)
        state.trHud = v
        hudHidden = { v == "Player 1" or v == "Both", v == "Player 2" or v == "Both" }
        setHud(1, hudHidden[1]); setHud(2, hudHidden[2])
        log("Trainer: hide HUD %s", v)
    end,
    reset = function() if hudHidden[1] or hudHidden[2] then hudHidden = { false, false }; setHud(1, false); setHud(2, false) end; state.trHud = nil end })
OK.addTickJob("x_hudKeep", 0.5, function()
    for i = 1, 2 do if hudHidden[i] then setHud(i, true) end end
end)
state.hudHiddenByTrainer = function(i) return hudHidden[i] end
OK.onWorldChange(function() hudHidden = { false, false }; state.trHud = nil end)

------------------------------------------------------------------------------------------
-- TEST Vehicle size
------------------------------------------------------------------------------------------
local carScale, carTouched = 1.0, {}
local CAR_SIZES = { ["Normal"] = 1.0, ["Giant (x2)"] = 2.0, ["Colossal (x10)"] = 10.0, ["Tiny (x0.5)"] = 0.5,
    ["Toy (x0.25)"] = 0.25, ["Smallest (x0.1)"] = 0.1 }
-- the lowest point of a vehicle (so a grown one can be lifted out of the road)
local function bottomOf(v)
    local z = nil
    pcall(function()
        local o, e = {}, {}
        v:GetActorBounds(true, o, e)
        if o.Z and e.Z then z = o.Z - e.Z end
    end)
    return z
end
local function applyCarSize()
    pcall(function()
        for _, v in ipairs(FindAllOf("BFGBasicVehicle") or {}) do
            if valid(v) then
                local k = OK.keyOf(v)
                local was = carTouched[k] or 1.0
                if was ~= carScale then
                    local b0 = carScale > was and bottomOf(v)
                    pcall(function() v:SetActorScale3D({ X = carScale, Y = carScale, Z = carScale }) end)
                    local b1 = b0 and bottomOf(v)
                    if b0 and b1 and b1 < b0 then
                        pcall(function()
                            local l = v:K2_GetActorLocation()
                            v:K2_SetActorLocation({ X = l.X, Y = l.Y, Z = l.Z + (b0 - b1) + 10 }, false, {}, true)
                        end)
                    end
                    carTouched[k] = carScale ~= 1.0 and carScale or nil
                end
            end
        end
    end)
end
add({ key = "x_carsize", page = 4, label = "Vehicle size", options = { "Normal", "Giant (x2)", "Colossal (x10)", "Tiny (x0.5)", "Toy (x0.25)", "Smallest (x0.1)" },
    get = function() return state.trCarSize or "Normal" end,
    set = function(v) state.trCarSize = v; carScale = CAR_SIZES[v] or 1.0; applyCarSize(); log("Trainer: vehicle size %s", v) end,
    reset = function() if carScale ~= 1.0 then carScale = 1.0; applyCarSize() end; state.trCarSize = nil; carTouched = {} end })
OK.addTickJob("x_carSizeKeep", 2.0, function() if carScale ~= 1.0 then applyCarSize() end end)
OK.onWorldChange(function() carScale, carTouched = 1.0, {}; state.trCarSize = nil end)

------------------------------------------------------------------------------------------
-- TEST Zap-O-Matic chain length (both players)
------------------------------------------------------------------------------------------
local CHAINS = { ["Game default"] = nil, ["5 jumps"] = 5, ["10 jumps"] = 10, ["20 jumps (chaos)"] = 20 }
local chainWanted, chainBase = nil, {}
local function zapBeams()
    local list = {}
    for _, pc in ipairs(players()) do
        local eq = subObj(getPawn(pc), "m_pEquipmentManagerComponent")
        pcall(function()
            for _, w in ipairs(OK.arrayToList(eq.m_aWeaponList)) do
                if valid(w) and OK.nameOf(w):find("Zap%-O%-Matic") then
                    local b = w.m_pBeam
                    if valid(b) then list[#list + 1] = b end
                end
            end
        end)
    end
    return list
end
local function applyChain()
    for _, b in ipairs(zapBeams()) do
        local k = OK.keyOf(b)
        if not chainBase[k] then
            chainBase[k] = {}
            pcall(function() chainBase[k].n = b.m_iIridiumSpreaderNumberOfJumps end)
            pcall(function() chainBase[k].n2 = b.m_iIRIDIUM_NumberPossibleJumps end)
            pcall(function() chainBase[k].r = b.m_fIRIDIUM_InitialJumpDistance end)
        end
        local base = chainBase[k]
        if chainWanted then
            pcall(function() b.m_iIridiumSpreaderNumberOfJumps = chainWanted end)
            pcall(function() b.m_iIRIDIUM_NumberPossibleJumps = chainWanted end)
            pcall(function() b.m_fIRIDIUM_InitialJumpDistance = math.max(base.r or 500, 900) end)
        else
            if base.n then pcall(function() b.m_iIridiumSpreaderNumberOfJumps = base.n end) end
            if base.n2 then pcall(function() b.m_iIRIDIUM_NumberPossibleJumps = base.n2 end) end
            if base.r then pcall(function() b.m_fIRIDIUM_InitialJumpDistance = base.r end) end
        end
    end
end
add({ key = "x_chain", page = 3, label = "Zap-O-Matic chain length (both players)", options = { "Game default", "5 jumps", "10 jumps", "20 jumps (chaos)" },
    get = function() return state.trChain or "Game default" end,
    set = function(v) state.trChain = v; chainWanted = CHAINS[v]; applyChain(); state.p2ZapCfgReset = true; log("Trainer: zap chain %s", v) end,
    reset = function() if chainWanted then chainWanted = nil; applyChain() end; state.trChain = nil; chainBase = {} end })
OK.addTickJob("x_chainKeep", 2.0, function() if chainWanted then applyChain() end end)
OK.onWorldChange(function() chainWanted, chainBase = nil, {}; state.trChain = nil end)

------------------------------------------------------------------------------------------
-- TEST PK: things stay weightless after you let go
------------------------------------------------------------------------------------------
local pkFloat, floatList = false, {}
local function heldBy(pc)
    local t = nil
    pcall(function()
        local mental = subObj(getPawn(pc), "m_pMentalAbilityComponent")
        for _, ab in ipairs(state.p2Abilities(mental)) do
            if valid(ab) and OK.nameOf(ab):find("kinesis") then
                local a = ab.m_pActiveTarget
                if valid(a) then t = a end
            end
        end
    end)
    return t
end
local function setGravity(actor, on)
    pcall(function()
        local root = actor:K2_GetRootComponent()
        root:SetEnableGravity(on)
    end)
    pcall(function() actor.Mesh:SetEnableGravity(on) end)
    pcall(function() actor.CharacterMovement.GravityScale = on and 1.0 or 0.0 end)
end
add({ key = "x_pkfloat", page = 3, label = "TEST  PK: thrown things float, weightless, for 10 s", options = { "Off", "On" },
    get = function() return state.trPkFloat or "Off" end,
    set = function(v) state.trPkFloat = v; pkFloat = v == "On"; log("Trainer: PK float %s", v) end,
    reset = function()
        pkFloat = false; state.trPkFloat = nil
        for k, e in pairs(floatList) do if valid(e.a) then setGravity(e.a, true) end; floatList[k] = nil end
    end })
OK.addTickJob("x_pkFloat", 0.1, function()
    local now = os.clock()
    if pkFloat then
        for _, pc in ipairs(players()) do
            local a = heldBy(pc)
            if a then
                local k = OK.keyOf(a)
                if not floatList[k] then setGravity(a, false) end
                floatList[k] = { a = a, untilT = now + 10.0 }
            end
        end
    end
    for k, e in pairs(floatList) do
        if now >= e.untilT or not valid(e.a) then
            if valid(e.a) then setGravity(e.a, true) end
            floatList[k] = nil
        end
    end
end)
OK.onWorldChange(function() pkFloat, floatList = false, {}; state.trPkFloat = nil end)

------------------------------------------------------------------------------------------
-- TEST Leash: keep the two players together
------------------------------------------------------------------------------------------
local LEASH = { ["Off"] = nil, ["50 m"] = 5000, ["100 m"] = 10000, ["25 m"] = 2500 }
local leash = nil
add({ key = "x_leash", page = 3, label = "TEST  Leash: Player 2 is pulled back to Player 1 past this distance", options = { "Off", "25 m", "50 m", "100 m" },
    p2only = true,
    get = function() return state.trLeash or "Off" end,
    set = function(v) state.trLeash = v; leash = LEASH[v]; log("Trainer: leash %s", v) end,
    reset = function() leash = nil; state.trLeash = nil end })
OK.addTickJob("x_leash", 0.5, function()
    if not (leash and valid(state.p2)) then return end
    local p1, p2 = getPawn(OK.player1Controller()), getPawn(state.p2)
    if not (valid(p1) and valid(p2)) then return end
    local ok1, a = pcall(function() return p1:K2_GetActorLocation() end)
    local ok2, b = pcall(function() return p2:K2_GetActorLocation() end)
    if not (ok1 and ok2) then return end
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d > leash then
        -- yank Player 2 towards Player 1 (a strong pull rather than a teleport)
        local f = 2200 / d
        pcall(function() p2:LaunchCharacter({ X = -dx * f, Y = -dy * f, Z = 600 }, true, true) end)
    end
end)
OK.onWorldChange(function() leash = nil; state.trLeash = nil end)

log("Extra trainer options loaded (marked TEST)")

------------------------------------------------------------------------------------------
-- Player 2's skin, picked from a list (best done on the mothership, like the game's own)
------------------------------------------------------------------------------------------
local SKINS = {
    { "Default", "Skin.Crypto.Default" }, { "Damaged", "Skin.Crypto.Damaged" }, { "Retro Pulp", "Skin.Crypto.Pulp" },
    { "Clown", "Skin.Crypto.Clown" }, { "Clown (dark)", "Skin.Crypto.ClownDark" }, { "OG137", "Skin.Crypto.OG137" },
    { "Elvis", "Skin.Crypto.Elvis" }, { "Cowboy", "Skin.Crypto.Cowboy" }, { "Darksiders", "Skin.Crypto.Darksiders" },
    { "Xenowolf", "Skin.Crypto.Xenowolf" }, { "Krampus", "Skin.Crypto.Krampus" }, { "Frozen", "Skin.Crypto.Frozen" },
    { "24 Karat", "Skin.Crypto.24kt" }, { "Camouflage 1", "Skin.Crypto.Camouflage1" }, { "Camouflage 2", "Skin.Crypto.Camouflage2" },
}
local skinNames = { "(keep current)" }
for _, e in ipairs(SKINS) do skinNames[#skinNames + 1] = e[1] end
add({ key = "x_p2skin", page = 3, p2only = true, label = "Player 2 skin (safest on the mothership)", options = skinNames,
    get = function() return skinNames[1] end,
    set = function(v)
        for _, e in ipairs(SKINS) do
            if e[1] == v and state.setP2Skin then state.setP2Skin(e[2]) end
        end
    end })

------------------------------------------------------------------------------------------
-- Shield bar placement, concentration meter colours, PK blue mode
------------------------------------------------------------------------------------------
-- two players: each player's own bar by the split line (the default), unless picked otherwise
state.barPlace = state.barPlace or "By the split line"
add({ key = "x_bars", page = 3, label = "Split-screen shield bars", options = { "By the split line", "Outer edges", "Game's own only" },
    get = function() return state.barPlace or "By the split line" end,
    set = function(v) state.barPlace = v end })
add({ key = "x_meter", page = 3, label = "Concentration meter colours", options = { "Cyan & white", "Classic yellow" },
    get = function() return state.meterStyle or "Cyan & white" end,
    set = function(v) state.meterStyle = v end })
add({ key = "x_pkblue", page = 3, label = "Shrink / grow ray (blue PK: L3 / R3 shrink and grow instead of in / out)", options = { "Off", "On" },
    get = function() return (state.pkConfig and state.pkConfig.BlueResize) and "On" or "Off" end,
    set = function(v) if state.pkConfig then state.pkConfig.BlueResize = (v == "On" or v == "Shrink / grow") end end })

------------------------------------------------------------------------------------------
-- TEST Raining people: people drop out of the sky around the players
------------------------------------------------------------------------------------------
local rain = { mode = "Off", list = {}, at = 0 }
local RAIN = { ["Off"] = 0, ["Light"] = 1.2, ["Heavy"] = 0.35 }
OK.onWorldChange(function() rain.list = {} end)
add({ key = "x_rain", page = 4, label = "TEST  Raining people", options = { "Off", "Light", "Heavy" },
    get = function() return rain.mode end,
    set = function(v) rain.mode = v; log("Trainer: raining people %s", v) end,
    reset = function() rain.mode = "Off" end })
OK.addTickJob("x_rain", 0.1, function()
    local every = RAIN[rain.mode] or 0
    if every <= 0 or not state.spawnNpcAt or os.clock() < rain.at then return end
    rain.at = os.clock() + every
    -- only ordinary people (civilians, police, soldiers, agents), not planes, bosses or robots
    local types = {}
    for _, t in ipairs(state.npcTypes and state.npcTypes() or {}) do
        local l = t:lower()
        local person = l:find("civilian") or l:find("police") or l:find("soldier") or l:find("military")
            or l:find("agent") or l:find("majestic") or l:find("scientist") or l:find("farmer")
        local odd = l:find("plane") or l:find("pilot") or l:find("boss") or l:find("armquist") or l:find("robot")
            or l:find("mutant") or l:find("vehicle") or l:find("tank") or l:find("heli") or l:find("drone")
        if person and not odd then types[#types + 1] = t end
    end
    if #types == 0 then return end
    local list = players()
    local pc = list[math.random(#list)]
    local pw = getPawn(pc)
    if not valid(pw) then return end
    local okL, l = pcall(function() return pw:K2_GetActorLocation() end)
    if not okL then return end
    local a = math.random() * 2 * math.pi
    local r = 300 + math.random() * 1500
    local pos = { X = l.X + math.cos(a) * r, Y = l.Y + math.sin(a) * r, Z = l.Z + 1800 + math.random() * 800 }
    local npc = state.spawnNpcAt(types[math.random(#types)], pos, math.random() * 360)
    if npc then
        rain.list[#rain.list + 1] = npc
        -- keep it to a sensible number: the oldest go
        while #rain.list > 40 do
            local old = table.remove(rain.list, 1)
            if valid(old) then pcall(function() old:K2_DestroyActor() end) end
        end
    end
end)

------------------------------------------------------------------------------------------
-- TEST No-clip: fly through anything. A goes up, B goes down, the stick flies.
------------------------------------------------------------------------------------------
local noclip = { mode = "Off", on = {} }
local function setNoclip(pc, on)
    local pw = getPawn(pc)
    if not valid(pw) then return end
    local cm = subObj(pw, "CharacterMovement")
    pcall(function() pw:SetActorEnableCollision(not on) end)
    if cm then pcall(function() cm:SetMovementMode(on and 5 or 1, 0) end) end   -- 5 = flying, 1 = walking
    noclip.on[OK.keyOf(pw)] = on or nil
end
add({ key = "x_noclip", page = 3, label = "No-clip (A up, B down)", options = { "Off", "Player 1", "Player 2", "Both" },
    get = function() return noclip.mode end,
    set = function(v)
        noclip.mode = v
        local list = { OK.player1Controller(), state.p2 }
        for i, pc in ipairs(list) do
            if valid(pc) then setNoclip(pc, v == "Both" or v == ("Player " .. i)) end
        end
        log("Trainer: no-clip %s", v)
    end,
    reset = function()
        for i, pc in ipairs({ OK.player1Controller(), state.p2 }) do if valid(pc) then setNoclip(pc, false) end end
        noclip.mode = "Off"
    end })
OK.addTickJob("x_noclip", 0.0, function()
    if noclip.mode == "Off" then return end
    for i, pc in ipairs({ OK.player1Controller(), state.p2 }) do
        if valid(pc) and (noclip.mode == "Both" or noclip.mode == ("Player " .. i)) then
            local pw = getPawn(pc)
            local cm = subObj(pw, "CharacterMovement")
            if cm then
                local okM, mode = pcall(function() return cm.MovementMode end)
                if okM and mode ~= 5 then setNoclip(pc, true) end
                local up = OK.kbDown(pc, "Gamepad_FaceButton_Bottom") and 900 or (OK.kbDown(pc, "Gamepad_FaceButton_Right") and -900 or 0)
                pcall(function()
                    local v = cm.Velocity
                    cm.Velocity = { X = v.X, Y = v.Y, Z = up }
                end)
            end
        end
    end
end)

------------------------------------------------------------------------------------------
-- TEST Skate in the air: while Crypto skates, he keeps his height instead of dropping.
-- No collision change (it's not no-clip), no buttons: let go of skate and he falls as usual.
------------------------------------------------------------------------------------------
local skateAir = { mode = "Off", held = {} }
add({ key = "x_skateair", page = 3, label = "Skate in the air (no drop while skating)", options = { "Off", "On" },
    get = function() return skateAir.mode end,
    set = function(v) skateAir.mode = v; log("Trainer: skate in the air %s", v) end,
    reset = function()
        skateAir.mode = "Off"
        for k, e in pairs(skateAir.held) do if valid(e.cm) then pcall(function() e.cm.GravityScale = e.g end) end end
        skateAir.held = {}
    end })
OK.addTickJob("x_skateair", 0.0, function()
    if skateAir.mode == "Off" and next(skateAir.held) == nil then return end
    for _, pc in ipairs(players()) do
        local pw = getPawn(pc)
        local cm = subObj(pw, "CharacterMovement")
        local jp = subObj(pw, "m_pJetpackPilotComponent")
        if cm and jp then
            local k = OK.keyOf(cm)
            local okS, skating = pcall(function() return jp:GetSkateActive() end)
            local on = skateAir.mode == "On" and okS and skating
            local e = skateAir.held[k]
            if on then
                if not e then
                    local okG, g = pcall(function() return cm.GravityScale end)
                    e = { cm = cm, g = okG and g or 1.0 }
                    skateAir.held[k] = e
                end
                pcall(function() cm.GravityScale = 0.0 end)
                pcall(function() local v = cm.Velocity; if v.Z < 0 then cm.Velocity = { X = v.X, Y = v.Y, Z = 0 } end end)
            elseif e then
                pcall(function() cm.GravityScale = e.g end)
                skateAir.held[k] = nil
            end
        end
    end
end)

------------------------------------------------------------------------------------------
-- TEST Endless concentration (the mind-power meter never runs out)
------------------------------------------------------------------------------------------
add({ key = "x_conc", page = 3, label = "TEST  Endless concentration (mind powers)", options = { "Off", "On" },
    get = function() return state.endlessConc and "On" or "Off" end,
    set = function(v) state.endlessConc = v == "On"; log("Trainer: endless concentration %s", v) end,
    reset = function() state.endlessConc = false end })

------------------------------------------------------------------------------------------
-- TEST Fragile people: everyone near you goes down from one hit (one-hit kills)
------------------------------------------------------------------------------------------
local fragile = { mode = "Off", touched = {} }
add({ key = "x_fragile", page = 4, label = "TEST  One-hit kills (people near you are fragile)", options = { "Off", "On" },
    get = function() return fragile.mode end,
    set = function(v) fragile.mode = v; log("Trainer: one-hit kills %s", v) end,
    reset = function() fragile.mode = "Off"; fragile.touched = {} end })
OK.addTickJob("x_fragile", 1.0, function()
    if fragile.mode ~= "On" then return end
    for _, n in ipairs(npcs(6000)) do
        local st = OK.stat(n, "m_pHealthStat")
        local r = OK.healthRatio(n)
        if st and type(r) == "number" and r > 0.02 then pcall(function() OK.setRatio(st, 0.02) end) end
    end
end)
OK.onWorldChange(function() fragile.mode = "Off" end)

------------------------------------------------------------------------------------------
-- TEST Bullet time: people near you move in slow motion (you don't)
------------------------------------------------------------------------------------------
local SLOWS = { ["Off"] = 1.0, ["Half speed"] = 0.5, ["Slow"] = 0.25, ["Crawl"] = 0.1 }
local slow = { mode = "Off", touched = {} }
local function applySlow()
    local f = SLOWS[slow.mode] or 1.0
    local seen = {}
    for _, n in ipairs(npcs(8000)) do
        local k = OK.keyOf(n)
        seen[k] = true
        if f ~= 1.0 or slow.touched[k] then
            pcall(function() n.CustomTimeDilation = f end)
            slow.touched[k] = f ~= 1.0 and n or nil
        end
    end
end
add({ key = "x_slow", page = 4, label = "TEST  Bullet time for people near you", options = { "Off", "Half speed", "Slow", "Crawl" },
    get = function() return slow.mode end,
    set = function(v) slow.mode = v; applySlow(); log("Trainer: bullet time %s", v) end,
    reset = function()
        slow.mode = "Off"
        for _, n in pairs(slow.touched) do if valid(n) then pcall(function() n.CustomTimeDilation = 1.0 end) end end
        slow.touched = {}
    end })
OK.addTickJob("x_slowKeep", 1.0, function() if slow.mode ~= "Off" then applySlow() end end)
OK.onWorldChange(function() slow.mode, slow.touched = "Off", {} end)

------------------------------------------------------------------------------------------
-- TEST Bouncing traffic: cars near you hop into the air now and then
------------------------------------------------------------------------------------------
local bounce = { mode = "Off" }
add({ key = "x_bounce", page = 4, label = "TEST  Bouncing traffic", options = { "Off", "Hops", "Moon launch" },
    get = function() return bounce.mode end,
    set = function(v) bounce.mode = v; log("Trainer: bouncing traffic %s", v) end,
    reset = function() bounce.mode = "Off" end })
OK.addTickJob("x_bounce", 1.5, function()
    if bounce.mode == "Off" then return end
    local center = nil
    pcall(function() center = getPawn(OK.player1Controller()):K2_GetActorLocation() end)
    if not center then return end
    local up = bounce.mode == "Moon launch" and 2600 or 900
    for _, v in ipairs(FindAllOf("BFGBasicVehicle") or {}) do
        if valid(v) and math.random() < 0.35 then
            local okL, l = pcall(function() return v:K2_GetActorLocation() end)
            if okL and l then
                local dx, dy = l.X - center.X, l.Y - center.Y
                if dx * dx + dy * dy < 4000 * 4000 then
                    pcall(function()
                        local root = v:K2_GetRootComponent()
                        root:SetSimulatePhysics(true)
                        pcall(function() root:SetEnableGravity(true) end)
                        root:SetPhysicsLinearVelocity({ X = 0, Y = 0, Z = up }, true, FName("None"))
                    end)
                    -- traffic cars float once they're physics objects: pull them back down
                    local car = v
                    OK.later(up > 1000 and 1.6 or 0.7, "bounceDown", function()
                        if not valid(car) then return end
                        pcall(function()
                            local root = car:K2_GetRootComponent()
                            local g = math.max(1200, up)
                            root:SetPhysicsLinearVelocity({ X = 0, Y = 0, Z = -g }, false, FName("None"))
                        end)
                        -- landing on someone hurts: anyone under it when it comes down
                        for _, wait in ipairs({ 0.35, 0.7 }) do
                            OK.later(wait, "bounceLand", function()
                                if not valid(car) then return end
                                local okC, cl = pcall(function() return car:K2_GetActorLocation() end)
                                if not (okC and cl) then return end
                                local by = getPawn(OK.player1Controller())
                                for _, n in ipairs(npcs and npcs(4500) or {}) do
                                    local okN, nl = pcall(function() return n:K2_GetActorLocation() end)
                                    if okN and nl then
                                        local dx, dy, dz = nl.X - cl.X, nl.Y - cl.Y, nl.Z - cl.Z
                                        if dx * dx + dy * dy < 330 * 330 and math.abs(dz) < 260 then
                                            local hp = OK.healthRatio(n)
                                            if state.gameDamage then pcall(state.gameDamage, n, 99999, by) end
                                            if type(hp) == "number" then pcall(function() OK.setRatio(OK.stat(n, "m_pHealthStat"), 0) end) end
                                        end
                                    end
                                end
                            end)
                        end
                    end)
                end
            end
        end
    end
end)

------------------------------------------------------------------------------------------
-- Aura: a coloured glow that follows a player, set for each player on their own
------------------------------------------------------------------------------------------
local AURAS = { ["Off"] = nil, ["Cyan"] = { R = 0.2, G = 0.9, B = 1.0 }, ["Green"] = { R = 0.3, G = 1.0, B = 0.2 },
                ["Purple"] = { R = 0.6, G = 0.2, B = 1.0 }, ["Red"] = { R = 1.0, G = 0.15, B = 0.1 },
                ["Gold"] = { R = 1.0, G = 0.75, B = 0.15 }, ["White"] = { R = 1.0, G = 1.0, B = 1.0 } }
local AURA_NAMES = { "Off", "Cyan", "Green", "Purple", "Red", "Gold", "White", "Purple embers" }
-- "Purple embers": the ion skeleton embers (effect 95 in the catalog) on the player, plus a purple glow
AURAS["Purple embers"] = { R = 0.6, G = 0.2, B = 1.0, fx = "/Game/VFX/PFX/Gameplay/Weapons/CharacterDesintegration/PFX_EmbersIonSkeleteonHorizontal.PFX_EmbersIonSkeleteonHorizontal" }
local aura = { mode = {}, lights = {} }     -- [slot] = colour name / light actor
local function auraPlayer(slot)
    if slot == 1 then return OK.player1Controller() end
    if slot == 2 then return state.p2 end
    return state.extraPlayers and state.extraPlayers[slot] or nil
end
local function clearAura(slot)
    local l = aura.lights[slot]
    if valid(l) then pcall(function() l:K2_DestroyActor() end) end
    aura.lights[slot] = nil
end
for slot = 1, 4 do
    add({ key = "x_aura" .. slot, page = 3, p2only = slot == 2,
        show = slot > 2 and function() return valid(auraPlayer(slot)) end or nil, label = "Aura: Player " .. slot .. " (glow around them)", options = AURA_NAMES,
        get = function() return aura.mode[slot] or "Off" end,
        set = function(v) aura.mode[slot] = v; clearAura(slot); log("Trainer: aura P%d %s", slot, v) end,
        reset = function() aura.mode[slot] = nil; clearAura(slot) end })
end
OK.addTickJob("x_aura", 1.0, function()
    for slot = 1, 4 do
        local c = AURAS[aura.mode[slot] or "Off"]
        local pw = c and getPawn(auraPlayer(slot))
        if not c or not valid(pw) then
            if aura.lights[slot] and not c then clearAura(slot) end
        else
            -- a new body (respawn, rejoin): the glow moves onto it
            local l = aura.lights[slot]
            local okP, parent = false, nil
            if valid(l) then okP, parent = pcall(function() return l:GetAttachParentActor() end) end
            if valid(l) and okP and parent and OK.keyOf(parent) ~= OK.keyOf(pw) then clearAura(slot); l = nil end
            if c.fx and state.playFx and os.clock() >= (aura["fxAt" .. slot] or 0) then
                aura["fxAt" .. slot] = os.clock() + (CFG.AURA_FX_EVERY or 1.0)
                pcall(state.playFx, c.fx, nil, CFG.AURA_FX_SCALE or 1.0, subObj(pw, "Mesh"))
            end
            if not valid(l) then
                pcall(function()
                    local a = OK.getWorld():SpawnActor(StaticFindObject("/Script/Engine.PointLight"), pw:K2_GetActorLocation(), { Pitch = 0, Yaw = 0, Roll = 0 })
                    local lc = a.PointLightComponent or a.LightComponent
                    lc:SetMobility(2)
                    lc:SetLightColor({ R = c.R, G = c.G, B = c.B, A = 1 }, true)
                    lc:SetIntensity(4000)
                    pcall(function() lc:SetAttenuationRadius(300) end)
                    a:K2_AttachToActor(pw, FName("None"), 2, 1, 1, false)
                    aura.lights[slot] = a
                end)
            end
        end
    end
end)
OK.onWorldChange(function() aura.lights = {}; aura.mode = {} end)

------------------------------------------------------------------------------------------
-- TEST Hats (Crypto's own attachment meshes, found in FModel): every player wears it
------------------------------------------------------------------------------------------
local HATS = {
    ["Sombrero"] = "/Game/Meshes/Characters/Attachments/Crypto_sombrero.Crypto_sombrero",
    ["Antenna helmet"] = "/Game/Meshes/Characters/Attachments/Crypto_Antenna_Helmet.Crypto_Antenna_Helmet",
}
local hatWanted, hatWorn = nil, {}   -- hatWorn[pawn key] = { actor, name }
local function takeHatsOff()
    for k, h in pairs(hatWorn) do if valid(h.a) then pcall(function() h.a:K2_DestroyActor() end) end hatWorn[k] = nil end
end
local function hatTick()
    if not hatWanted then return end
    local path = HATS[hatWanted]
    local mesh = StaticFindObject(path)
    if not valid(mesh) then pcall(function() LoadAsset(path) end); mesh = StaticFindObject(path) end
    if not valid(mesh) then return end
    for _, pc in ipairs(players()) do
        local pw = getPawn(pc)
        local body = subObj(pw, "Mesh")
        if body then
            local k = OK.keyOf(pw)
            local h = hatWorn[k]
            if not (h and valid(h.a) and h.name == hatWanted) then
                if h and valid(h.a) then pcall(function() h.a:K2_DestroyActor() end) end
                pcall(function()
                    local a = OK.getWorld():SpawnActor(StaticFindObject("/Script/Engine.StaticMeshActor"), pw:K2_GetActorLocation(), { Pitch = 0, Yaw = 0, Roll = 0 })
                    local smc = a.StaticMeshComponent
                    smc:SetMobility(2)
                    smc:SetStaticMesh(mesh)
                    smc:SetCollisionEnabled(0)
                    a:SetActorEnableCollision(false)
                    -- the hats are modelled where they sit on Crypto, so they go on at the body's origin
                    a:K2_AttachToComponent(body, FName(CFG.HAT_SOCKET or "None"), 0, 0, 0, false)
                    a:K2_SetActorRelativeLocation({ X = 0, Y = 0, Z = CFG.HAT_RAISE or 0 }, false, {}, true)
                    a:K2_SetActorRelativeRotation({ Pitch = 0, Yaw = CFG.HAT_YAW or 0, Roll = 0 }, false, {}, true)
                    hatWorn[k] = { a = a, name = hatWanted }
                end)
            end
        end
    end
end
OK.onWorldChange(function() hatWorn = {} end)
add({ key = "x_hat", page = 3, label = "TEST  Hat (every player)", options = { "None", "Sombrero", "Antenna helmet" },
    get = function() return hatWanted or "None" end,
    set = function(v) takeHatsOff(); hatWanted = HATS[v] and v or nil; log("Trainer: hat %s", v) end,
    reset = function() takeHatsOff(); hatWanted = nil end })
OK.addTickJob("x_hats", 1.0, hatTick)

------------------------------------------------------------------------------------------
-- Mod features (Welcome page): every part of the mod that works outside the menus can be
-- switched off here, for a near-vanilla game. CO-OP marks the ones split screen needs.
-- These stay as set across maps (save with X to keep them between sessions).
------------------------------------------------------------------------------------------
local function feature(key, label, flags, coop, note)
    local function isOn()
        for _, f in ipairs(flags) do if CFG[f] == false then return false end end
        return true
    end
    add({ key = key, page = 1, label = label .. (coop and "   [CO-OP]" or "") .. (note and ("   (" .. note .. ")") or ""),
        options = { "On", "Off" },
        get = function() return isOn() and "On" or "Off" end,
        set = function(v)
            local on = v ~= "Off"
            for _, f in ipairs(flags) do CFG[f] = on end
            log("Mod features: %s %s%s", label, on and "on" or "off", (coop and not on and valid(state.p2)) and " (WARNING: split screen needs this)" or "")
        end })
end
feature("f_wheel", "Mind & weapons wheel on LB (off: the game's own wheel)", { "MIND_WHEEL" }, true)
feature("f_saucerwheel", "Saucer weapon wheel on LB (each player their own; off: the game's)", { "SAUCER_WHEEL" }, true)
feature("f_powers", "Mind powers on LT (the mod's new powers)", { "MIND_POWERS" })
feature("f_panel", "Power panel and concentration meter", { "WHEEL_PANEL" })
add({ key = "f_pk", page = 1, label = "PK overhaul (hold / push / pull, sizes, throws)", options = { "On", "Off" },
    get = function() return (state.pkIsEnabled and not state.pkIsEnabled()) and "Off" or "On" end,
    set = function(v) if state.pkSetEnabled then state.pkSetEnabled(v ~= "Off") end; log("Mod features: PK overhaul %s", v) end })
feature("f_downed", "Downed and revive (a partner can pick you up)", { "DOWNED_SYSTEM" }, true)
feature("f_pickups", "Player 2's pickups go to Player 1 (shared brains and ammo)", { "P2_PICKUPS" }, true)
feature("f_tags", "Partner tags over heads", { "PARTNER_MARKERS" })
feature("f_bars", "Each player's own shield bar by the split line", { "PLAYER_BARS" }, true)
feature("f_vignette", "Red hurt screen only for the player who was hurt", { "OWN_DAMAGE_VIGNETTE" }, true)
feature("f_lod", "Split-screen detail range (keeps detail further out)", { "SPLIT_LOD_PROFILE" }, true)
feature("f_p2zap", "Player 2's Zap-O-Matic chain, bracket and arcs", { "P2_ZAP_CHAIN", "P2_ZAP_BRACKET", "P2_ZAP_ARCS" }, true)
feature("f_p2health", "Player 2 sees the health bar of their target", { "P2_TARGET_HEALTH" }, true)
feature("f_recorder", "Test recorder (Guide button writes the last 12 s to the log)", { "TEST_RECORDER" })
