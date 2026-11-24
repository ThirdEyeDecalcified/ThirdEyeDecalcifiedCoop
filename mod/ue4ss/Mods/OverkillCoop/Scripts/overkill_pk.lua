--[[
    Overkill Coop - PK overhaul (loaded by main.lua)
    Brings remake PK closer to the 2005 feel:
      * L3 pulls the held target in, R3 pushes it out, without throwing
      * Floating IN / OUT label on the held target
      * Speed/mass-based collision damage for held NPCs and held objects

    F9 = discovery dump (run while holding something with PK)
    F6 = toggle mod on/off
    F5 = list input mappings (for InputGate)

    Settings: overkill_pk_settings.lua
]]

local UEHelpers = require("UEHelpers")
local Config = require("overkill_pk_settings")
if OverkillCoop and OverkillCoop.state then OverkillCoop.state.pkConfig = Config end
local InputGate = require("overkill_pk_inputgate")

local MOD = "[OverkillCoop PK] "
-- Also written to overkill_pk_log.txt next to the game exe (previous run kept as
-- overkill_pk_log_prev.txt), so it survives a crash and a restart.
local LogFile = nil
pcall(function()
    os.remove("overkill_pk_log_prev.txt")
    os.rename("overkill_pk_log.txt", "overkill_pk_log_prev.txt")
    LogFile = io.open("overkill_pk_log.txt", "w")
    if LogFile then LogFile:setvbuf("line") end
end)
local function log(msg)
    print(MOD .. tostring(msg) .. "\n")
    if LogFile then pcall(function() LogFile:write(os.date("%H:%M:%S ") .. tostring(msg) .. "\n"); LogFile:flush() end) end
end
local function dbg(msg) if Config.Debug then log(msg) end end

------------------------------------------------------------------------
-- Small vector helpers (UE vectors come back as userdata with X/Y/Z)
------------------------------------------------------------------------
local function V(x, y, z) return { X = x, Y = y, Z = z } end
local function vcopy(a) return V(a.X, a.Y, a.Z) end
local function vadd(a, b) return V(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function vsub(a, b) return V(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function vscale(a, s) return V(a.X * s, a.Y * s, a.Z * s) end
local function vlen(a) return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
local function vnorm(a) local l = vlen(a); if l < 1e-4 then return V(0, 0, 0) end return vscale(a, 1 / l) end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

------------------------------------------------------------------------
-- Safe UObject access
------------------------------------------------------------------------
local function valid(o)
    if o == nil or type(o) ~= "userdata" then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r
end

local function tryGet(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v end
    return nil
end

local function trySet(obj, name, value)
    return pcall(function() obj[name] = value end)
end

local function className(o)
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

local function addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or tostring(o)
end

------------------------------------------------------------------------
-- Cached engine objects
------------------------------------------------------------------------
local Classes = {}
local function cls(path)
    local c = Classes[path]
    if not valid(c) then
        c = StaticFindObject(path)
        Classes[path] = c
    end
    return c
end

local function GS() return UEHelpers.GetGameplayStatics() end
local function KSL() return UEHelpers.GetKismetSystemLibrary() end
local function KML() return UEHelpers.GetKismetMathLibrary() end

------------------------------------------------------------------------
-- Input (polled so it works for gamepad, which RegisterKeyBind doesn't cover)
------------------------------------------------------------------------
local KeyStructs = {}
local function key(name)
    if not name then return nil end
    if not KeyStructs[name] then KeyStructs[name] = { KeyName = FName(name) } end
    return KeyStructs[name]
end

local function isDown(pc, keyName)
    if not keyName then return false end
    local ok, r = pcall(function() return pc:IsInputKeyDown(key(keyName)) end)
    return ok and r == true
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
-- One state table per player (P1 = 1, P2 = 2). `State` is switched to the right one before
-- each player's tick, so every function below works on that player's state.
local function newState()
    return {
        lastTime = nil,
        pkComp = nil, pkOwner = nil,
        distProp = nil,          -- name of the hold-distance property once found
        heldProp = nil,          -- name of the held-actor property once found
        warnedNoHeld = false,
        target = nil, targetAddr = nil,
        prevVel = nil, prevSpeed = 0,
        pullWasDown = false, pushWasDown = false,
        hudActor = nil, hudText = nil,
        cooldown = {},           -- addr -> time
        bodyTick = 0,
        label = "P1",
    }
end
local States = { newState(), newState() }
States[2].label = "P2"
local State = States[1]
local ModEnabled = true

------------------------------------------------------------------------
-- PK component / held target discovery
------------------------------------------------------------------------
local function matchesList(name, list)
    local n = string.lower(name)
    for _, h in ipairs(list) do
        if string.find(n, string.lower(h), 1, true) then return true end
    end
    return false
end

local function matchesHint(name) return matchesList(name, Config.PKComponentClassHints) end

-- Walk every reflected property on obj's class chain, stopping before stopAt
local function forEachProp(obj, stopAt, fn)
    local ok0, s = pcall(function() return obj:GetClass() end)
    if not ok0 then return end
    while valid(s) do
        local sname = s:GetFName():ToString()
        if sname == stopAt then break end
        local ok, err = pcall(function()
            s:ForEachProperty(function(prop) fn(prop, sname) end)
        end)
        if not ok then log("ForEachProperty failed on " .. sname .. ": " .. tostring(err)) end
        local ok2, sup = pcall(function() return s:GetSuperStruct() end)
        s = ok2 and sup or nil
    end
end

local function propName(prop)
    local ok, n = pcall(function() return prop:GetFName():ToString() end)
    return ok and n or nil
end

local function propType(prop)
    local ok, n = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

-- Components found through the actor's own object properties
-- (works on 4.22, where K2_GetComponentsByClass came back empty)
local function forEachComponent(actor, fn)
    local ac = cls("/Script/Engine.ActorComponent")
    if not valid(ac) then return end
    local seen = {}
    forEachProp(actor, "Object", function(prop)
        local n = propName(prop)
        if not n or not string.find(propType(prop), "ObjectProperty", 1, true) then return end
        local v = tryGet(actor, n)
        if valid(v) then
            local ok, isComp = pcall(function() return v:IsA(ac) end)
            local a = addr(v)
            if ok and isComp and not seen[a] then
                seen[a] = true
                fn(v, n)
            end
        end
    end)
    -- Secondary route, in case some components have no property pointing at them
    pcall(function()
        local comps = actor:K2_GetComponentsByClass(ac)
        comps:ForEach(function(_, elem)
            local c = elem:get()
            if valid(c) and not seen[addr(c)] then
                seen[addr(c)] = true
                fn(c, "(unnamed)")
            end
        end)
    end)
end

local function findPKComponent(pawn)
    local pawnAddr = addr(pawn)
    if valid(State.pkComp) and State.pkOwner == pawnAddr then return State.pkComp end
    -- Don't rescan components every tick if nothing matched
    local t = os.time()
    if State.pkMissAt and State.pkMissOwner == pawnAddr and (t - State.pkMissAt) < 3 then return nil end
    State.pkComp, State.pkOwner = nil, nil
    -- Exact property names first (from the F9 dump)
    for _, pname in ipairs(Config.PKComponentProps) do
        local c = tryGet(pawn, pname)
        if valid(c) then
            -- In this game PK is one of the abilities inside the mental-abilities component:
            -- use that ability object (it holds the grabbed thing in m_pActiveTarget).
            local abilities = tryGet(c, "m_aPlayerMentalAbilities")
            local found = nil
            pcall(function()
                abilities:ForEach(function(_, e)
                    local okg, a = pcall(function() return e:get() end)
                    if okg and valid(a) and not found and matchesList(className(a), Config.PKAbilityHints or {}) then found = a end
                end)
            end)
            State.pkComp, State.pkOwner = found or c, pawnAddr
            State.pkPawn = pawn
            log(State.label .. " PK object: " .. (found and className(found) or (pname .. " (" .. className(c) .. ")")))
            return State.pkComp
        end
    end
    forEachComponent(pawn, function(c, pname)
        local cn = className(c)
        if not State.pkComp and cn ~= "SpringArmComponent" and (matchesHint(cn) or matchesHint(pname)) then
            State.pkComp, State.pkOwner = c, pawnAddr
            log("PK component: " .. pname .. " (" .. className(c) .. ")")
        end
    end)
    if not State.pkComp then State.pkMissAt, State.pkMissOwner = t, pawnAddr end
    return State.pkComp
end

local function asActor(o)
    if not valid(o) then return nil end
    local actorClass = cls("/Script/Engine.Actor")
    local ok, isActor = pcall(function() return o:IsA(actorClass) end)
    if ok and isActor then return o end
    -- Might be a grabbed component: use its owner
    local ok2, owner = pcall(function() return o:GetOwner() end)
    if ok2 and valid(owner) then return owner end
    return nil
end

-- BFG code names members m_pFoo (pointers) and m_fFoo (floats); try those too
local function nameVariants(name, prefix)
    return { name, prefix .. name }
end

local function getHeldActor(pk)
    if State.heldProp then
        return asActor(tryGet(pk, State.heldProp))
    end
    for _, base in ipairs(Config.HeldActorProps) do
        for _, name in ipairs(nameVariants(base, "m_p")) do
            local v = tryGet(pk, name)
            if valid(v) then
                State.heldProp = name
                log(State.label .. " held-actor property: " .. name)
                return asActor(v)
            end
        end
    end
    return nil
end

local function findDistProp(pk)
    if State.distProp then return State.distProp end
    -- The character's PK spring arm sets how far away held things float.
    if Config.HoldArm and valid(State.pkPawn) then
        local arm = tryGet(State.pkPawn, Config.HoldArm.Component)
        if valid(arm) and type(tryGet(arm, Config.HoldArm.Length)) == "number" then
            State.distObj, State.distProp = arm, Config.HoldArm.Length
            log(State.label .. " hold distance: " .. Config.HoldArm.Component .. "." .. Config.HoldArm.Length)
            return State.distProp
        end
    end
    for _, base in ipairs(Config.HoldDistanceProps) do
        for _, name in ipairs(nameVariants(base, "m_f")) do
            local v = tryGet(pk, name)
            if type(v) == "number" then
                State.distProp = name
                log("Hold-distance property: " .. name .. " (" .. string.format("%.0f", v) .. ")")
                return name
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Camera
------------------------------------------------------------------------
local function cameraInfo(pc)
    local cam = tryGet(pc, "PlayerCameraManager")
    if not valid(cam) then return nil end
    local ok, loc, rot = pcall(function() return cam:GetCameraLocation(), cam:GetCameraRotation() end)
    if not ok then return nil end
    local fwd = KML():GetForwardVector(rot)
    return vcopy(loc), rot, vcopy(fwd)
end

------------------------------------------------------------------------
-- HUD: world-space TextRenderActor that floats above the target
------------------------------------------------------------------------
local function identityTransform(loc)
    return {
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = loc or V(0, 0, 0),
        Scale3D = V(1, 1, 1),
    }
end

local function ensureHud()
    if valid(State.hudActor) and valid(State.hudText) then return true end
    local trClass = cls("/Script/Engine.TextRenderActor")
    if not valid(trClass) then return false end
    if State.hudFailed then return false end
    log(State.label .. ": creating the distance label...")
    local ok, actor = pcall(function()
        local xf = identityTransform()
        local a = GS():BeginDeferredActorSpawnFromClass(UEHelpers.GetWorld(), trClass, xf, 1, nil) -- 1 = AlwaysSpawn
        return GS():FinishSpawningActor(a, xf)
    end)
    if not ok or not valid(actor) then State.hudFailed = true; log(State.label .. ": distance label failed: " .. tostring(actor)); return false end
    log(State.label .. ": distance label created")
    local tr = tryGet(actor, "TextRender")
    if not valid(tr) then return false end
    pcall(function() actor:SetActorEnableCollision(false) end)
    pcall(function() tr:SetWorldSize(Config.Hud.TextSize) end)
    pcall(function() tr:SetHorizontalAlignment(1) end) -- EHTA_Center
    pcall(function() tr:SetTextRenderColor({ R = 120, G = 255, B = 140, A = 255 }) end)
    State.hudActor, State.hudText = actor, tr
    return true
end

local function hudHide()
    if valid(State.hudActor) then pcall(function() State.hudActor:SetActorHiddenInGame(true) end) end
end

local HUD_COLORS = { green = { R = 120, G = 255, B = 140, A = 255 }, red = { R = 255, G = 60, B = 50, A = 255 },
                     blue = { R = 70, G = 200, B = 255, A = 255 } }
local function hudShow(targetLoc, camLoc, camRot, text, color)
    if not Config.Hud.Enabled or not ensureHud() then return end
    color = color or "green"
    if State.hudColor ~= color then
        State.hudColor = color
        pcall(function() State.hudText:SetTextRenderColor(HUD_COLORS[color] or HUD_COLORS.green) end)
    end
    local pos = vadd(targetLoc, V(0, 0, Config.Hud.HeightOffset))
    local faceCam = { Pitch = 0, Yaw = camRot.Yaw + 180.0, Roll = 0 }
    pcall(function()
        State.hudActor:SetActorHiddenInGame(false)
        State.hudActor:K2_SetActorLocation(pos, false, {}, true)
        State.hudActor:K2_SetActorRotation(faceCam, true)
        State.hudText:K2_SetText(FText(text))
    end)
end

------------------------------------------------------------------------
-- Damage
------------------------------------------------------------------------
local function now()
    local ok, t = pcall(function() return GS():GetTimeSeconds(UEHelpers.GetWorld()) end)
    return ok and t or 0
end

local function onCooldown(actor, t)
    local a = addr(actor)
    local last = State.cooldown[a]
    if last and (t - last) < Config.Damage.PerTargetCooldown then return true end
    State.cooldown[a] = t
    return false
end

-- The game keeps health in a stat object on the pawn's stats component (m_pHealthStat).
local function healthStatOf(victim)
    for _, n in ipairs(Config.Damage.StatsComponentProps) do
        local sc = tryGet(victim, n)
        if valid(sc) then
            local st = tryGet(sc, "m_pHealthStat")
            if not valid(st) then
                local ok, r = pcall(function() return sc:GetHealthStat() end)
                st = ok and r or nil
            end
            if valid(st) then return st end
        end
    end
    local found = nil
    forEachComponent(victim, function(c)
        if found then return end
        local st = tryGet(c, "m_pHealthStat")
        if valid(st) then found = st end
    end)
    return found
end

local function statValue(st)
    local ok, v = pcall(function() return st:GetValue() end)
    if ok and type(v) == "number" then return v end
    local ok2, v2 = pcall(function() return st.m_fValue end)
    return (ok2 and type(v2) == "number") and v2 or nil
end

local loggedStat = 0 -- first hits are logged
local loggedTries = 0
local StatSetter = nil -- index of the call shape that worked
local statParamsLogged = false
local function logFnParams(path)
    local f = StaticFindObject(path)
    if not valid(f) then log("  " .. path .. ": not found"); return end
    local parts = {}
    pcall(function()
        f:ForEachProperty(function(p) parts[#parts + 1] = propType(p) .. " " .. (propName(p) or "?") end)
    end)
    log("  " .. path:match("[^:]+$") .. "(" .. table.concat(parts, ", ") .. ")")
end
local function logStatParams()
    if statParamsLogged then return end
    statParamsLogged = true
    log("Parameters of the game's health / damage functions:")
    for _, fpath in ipairs({
        "/Script/BFGCore.BFGActorStat_Float:SetValue", "/Script/BFGCore.BFGActorStat_Float:AddValue",
        "/Script/BFGCore.BFGActorStat_Float:SetRatio",
        "/Script/BFGCore.BFGActorComponent_PawnDamage:ApplyAndReportDamage",
        "/Script/BFGCore.BFGActorComponent_PawnDamage:ApplyAndReportPointDamage" }) do
        logFnParams(fpath)
    end
end
-- mode: "held" (scraped while PK holds it: hurts, never kills), "dropped" (let go gently),
-- "thrown" (let go fast: full damage), nil = someone else hit by the held thing (full).
local function applyDamage(victim, amount, pc, pawn, mode)
    if amount <= 0 or not valid(victim) then return end
    local M = Config.Damage.Modes
    local scale = (mode and M[mode] and M[mode].Scale) or 1.0
    local floor = (mode and M[mode] and M[mode].KeepHealth) or 0.0
    amount = amount * scale
    local D = Config.Damage
    local st = healthStatOf(victim)
    if st then
        local before = statValue(st)
        local okM, mx = pcall(function() return st.m_fMaxValue end)
        mx = (okM and type(mx) == "number" and mx > 0) and mx or nil
        -- amount is "damage points"; scale to this NPC's health so a hard slam can kill
        local dmg = mx and (amount / 100.0) * mx * D.StatDamageScale or amount
        if before then
            local after = math.max(0, before - dmg)
            if floor > 0 and mx then
                if before <= mx * floor then return end
                after = math.max(after, mx * floor)
                dmg = before - after
            end
            logStatParams()
            -- The stat setters take more than one parameter in this game; try the likely shapes,
            -- so the game's own "health changed" event fires (that's what kills / ragdolls).
            local how, check = nil, nil
            local tries = {
                -- the game's own damage path: kills, ragdolls and reports like a real hit
                { "ApplyAndReportDamage", function()
                    local dc = tryGet(victim, "m_pDamageComponent")
                    if not valid(dc) then error("no damage component") end
                    dc:ApplyAndReportDamage(victim, dmg, pawn, pawn, cls("/Script/Engine.DamageType"), true)
                end },
                { "SetValue(broadcast)", function() st:SetValue(after, true, true, false) end },
                { "AddValue(broadcast)", function() st:AddValue(-dmg, true, true) end },
                { "SetRatio(broadcast)", function() st:SetRatio(after / (mx or 1), true, true, false) end },
            }
            local order = {}
            if StatSetter then order[1] = StatSetter end
            for i = 1, #tries do order[#order + 1] = i end
            for _, i in ipairs(order) do
                local ok, err = pcall(tries[i][2])
                check = statValue(st)
                if ok and check and check <= after + 0.01 then how = tries[i][1]; StatSetter = i; break end
                if not ok and loggedTries < 12 then loggedTries = loggedTries + 1; log("  " .. tries[i][1] .. ": " .. tostring(err)) end
            end
            if not how then
                how = "write (game not told)"
                pcall(function() st.m_fValue = after end)
                check = statValue(st)
            end
            if after <= 0 then
                -- make sure the game notices the death
                local dead = nil
                for _, n in ipairs(Config.Damage.StatsComponentProps) do
                    local sc = tryGet(victim, n)
                    if valid(sc) then dead = tryGet(sc, "m_pIsDeadStat") break end
                end
                if valid(dead) and check and check <= 0.01 then pcall(function() dead:SetValue(true) end) end
            end
            if loggedStat < 30 then
                loggedStat = loggedStat + 1
                log(string.format("%s hit %s: health %.1f -> %.1f (max %s, %s)", State.label, className(victim), before,
                    check or -1, mx and string.format("%.0f", mx) or "?", how))
            end
            return
        end
    end
    local dmgType = cls("/Script/Engine.DamageType")
    pcall(function() GS():ApplyDamage(victim, amount, pc, pawn, dmgType) end)
    dbg(string.format("ApplyDamage %.1f -> %s", amount, className(victim)))
end

local function isPawn(actor)
    local pawnClass = cls("/Script/Engine.Character") -- people only (vehicles are pawns too)
    local ok, r = pcall(function() return actor:IsA(pawnClass) end)
    return ok and r
end

local function heldMass(actor)
    local root = tryGet(actor, "RootComponent")
    if not valid(root) then return nil end
    local ok, sim = pcall(function() return root:IsSimulatingPhysics(FName("None")) end)
    if not (ok and sim) then return nil end
    local ok2, m = pcall(function() return root:GetMass() end)
    if ok2 and type(m) == "number" and m > 0 then return m end
    return nil
end

-- Line trace along the previous velocity to confirm a real surface was hit
local function confirmSurface(world, fromLoc, dir, dist, ignore)
    if not Config.Damage.WallImpact.UseLineTraceConfirm then return true end
    local ok, hit = pcall(function()
        local outHit = {}
        local endLoc = vadd(fromLoc, vscale(dir, dist))
        return KSL():LineTraceSingle(world, fromLoc, endLoc, 0, false, ignore, 0, outHit, true,
            { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0.0)
    end)
    if not ok then return true end -- trace API mismatch: fall back to decel-only detection
    return hit == true
end

-- Impact sounds: the first loaded sound whose name matches Config.Sounds (logged once).
local Sounds = {}
local function findSound(kind)
    if Sounds[kind] ~= nil then return Sounds[kind] or nil end
    local words = (Config.Sounds and Config.Sounds[kind]) or {}
    local found, candidates = nil, {}
    local found_rank = nil
    for _, cname in ipairs({ "SoundCue", "AkAudioEvent", "SoundWave" }) do
        for _, o in ipairs(FindAllOf(cname) or {}) do
            local okN, n = pcall(function() return o:GetFName():ToString() end)
            if okN and n then
                local ln = n:lower()
                for wi, w in ipairs(words) do
                    if ln:find(w:lower(), 1, true) and (not found or wi < (found_rank or 99)) then found, found_rank = o, wi end
                end
                if #candidates < 40 and (ln:find("impact", 1, true) or ln:find("crash", 1, true) or ln:find("thud", 1, true) or ln:find("hit", 1, true)) then
                    candidates[#candidates + 1] = cname .. ":" .. n
                end
            end
        end
        if found and found_rank == 1 then break end
    end
    Sounds[kind] = found or false
    log(string.format("%s sound: %s", kind, found and (className(found) .. " " .. found:GetFName():ToString()) or "none found"))
    if #candidates > 0 then log("  sounds with impact/crash/hit in the name: " .. table.concat(candidates, ", ")) end
    return found
end
local function playSound(kind, loc)
    if not (Config.Sounds and Config.Sounds.Enabled) then return end
    local snd = findSound(kind)
    if not snd then return end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    if className(snd) == "AkAudioEvent" then
        local ak = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
        pcall(function() ak:PostEventAtLocation(snd, loc, rot, "", UEHelpers.GetWorld()) end)
    else
        pcall(function() GS():PlaySoundAtLocation(UEHelpers.GetWorld(), snd, loc, rot, 1.0, 1.0, 0.0, nil, nil, nil) end)
    end
end

local function checkWallImpact(target, loc, vel, speed, dt, pc, pawn, t)
    local W = Config.Damage.WallImpact
    if not W.Enabled or not isPawn(target) then return end
    if State.prevSpeed < W.MinSpeed then return end
    if speed > State.prevSpeed * (1.0 - W.DecelFraction) then return end
    local dir = vnorm(State.prevVel)
    local probe = State.prevSpeed * dt * 2.0 + 120.0
    if not confirmSurface(UEHelpers.GetWorld(), loc, dir, probe, { target, pawn }) then return end
    if onCooldown(target, t) then return end
    local impact = State.prevSpeed - speed
    local dmg = clamp(W.BaseDamage + (impact - W.MinSpeed) * W.DamagePerSpeed, 0, W.MaxDamage)
    local mode = "held"
    if State.flyingNow then mode = (State.releaseSpeed or 0) >= Config.Damage.ThrowSpeed and "thrown" or "dropped" end
    dbg(string.format("Wall impact %.0f cm/s -> %.1f dmg (%s)", impact, dmg, mode))
    applyDamage(target, dmg, pc, pawn, mode)
    -- a hard knock sends a person tumbling
    playSound("Wall", loc)
    if impact > (Config.Damage.RagdollImpactSpeed or 1200) and (State.flyingNow or Config.Damage.RagdollWhileHeld) then
        pcall(function() target.Mesh:SetSimulatePhysics(true) end)
    end
end

local NPCCache = { at = -100, list = {} }
local function npcList(t)
    if t - NPCCache.at < 1.0 then return NPCCache.list end
    NPCCache.at = t
    local list = {}
    local charClass = cls("/Script/Engine.Character")
    local ok = pcall(function()
        local out = {}
        GS():GetAllActorsOfClass(UEHelpers.GetWorld(), charClass, out)
        for _, a in ipairs(out) do
            local v = a
            if type(a) == "userdata" and a.get then local okg, g = pcall(function() return a:get() end); if okg then v = g end end
            if valid(v) and className(v) ~= "BP_CharacterPlayer_C" then list[#list + 1] = v end
        end
    end)
    if not ok or #list == 0 then
        for _, cname in ipairs(Config.Damage.NPCClassNames) do
            for _, a in ipairs(FindAllOf(cname) or {}) do
                if valid(a) and className(a) ~= "BP_CharacterPlayer_C" then list[#list + 1] = a end
            end
        end
    end
    NPCCache.list = list
    return list
end

local function checkBodyImpact(target, loc, vel, speed, pc, pawn, t)
    local B = Config.Damage.BodyImpact
    if not B.Enabled or speed < B.MinSpeed then return end
    State.bodyTick = State.bodyTick + 1
    if State.bodyTick % 2 ~= 0 then return end -- every other tick is plenty

    local mass = heldMass(target)
    local massFactor = mass and clamp(mass / B.ReferenceMass, B.MassFactorMin, B.MassFactorMax) or 1.0
    local targetAddr, pawnAddr = addr(target), addr(pawn)
    local r = B.HitRadius
    local up = B.HitRadius
    local centre = loc
    -- big held things (cars): their own size, flat (not a giant ball reaching under them)
    if not isPawn(target) then
        r = B.VehicleRadius or 250.0
        up = 150.0
        local okB, o, ext = pcall(function()
            local o_, e_ = {}, {}
            target:GetActorBounds(true, o_, e_)
            return o_, e_
        end)
        if okB and type(ext) == "table" and ext.X and type(o) == "table" and o.X then
            r = clamp(math.max(ext.X, ext.Y) * 0.85, 150.0, B.VehicleRadius or 250.0)
            up = clamp(ext.Z, 60.0, 160.0) + 50.0
            centre = V(o.X, o.Y, o.Z)
        end
    end
    local r2 = r * r
    local tcn = className(target)
    if State.lastBodyClass ~= tcn then
        State.lastBodyClass = tcn
        log(string.format("%s: %s can hit people within %.0f cm across, %.0f cm up/down", State.label, tcn, r, up + 90.0))
    end

    do
        local npcs = npcList(t)
        if npcs then
            for _, npc in ipairs(npcs) do
                if valid(npc) then
                    local a = addr(npc)
                    if a ~= targetAddr and a ~= pawnAddr then
                        local ok, nloc = pcall(function() return npc:K2_GetActorLocation() end)
                        if ok then
                            local d = vsub(nloc, centre)
                            if (d.X * d.X + d.Y * d.Y) <= r2 and math.abs(d.Z) <= up + 90.0 and not onCooldown(npc, t) then
                                local dmg = clamp((B.BaseDamage + (speed - B.MinSpeed) * B.DamagePerSpeed) * massFactor, 0, B.MaxDamage)
                                dbg(string.format("Body impact %.0f cm/s x%.2f mass -> %.1f dmg on %s", speed, massFactor, dmg, className(npc)))
                                applyDamage(npc, dmg, pc, pawn)
                                playSound(isPawn(target) and "Body" or "Car", nloc)
                                local kb = isPawn(target) and B.Knockback or (B.VehicleKnockback or 0)
                                if kb > 0 then
                                    local push = vscale(vel, kb)
                                    local pl = vlen(push)
                                    if pl > 1500 then push = vscale(push, 1500 / pl) end
                                    push.Z = math.max(push.Z, 250)
                                    pcall(function() npc:LaunchCharacter(push, true, true) end)
                                end
                                -- Held NPC used as a club takes some of the hit too
                                if isPawn(target) then applyDamage(target, dmg * 0.5, pc, pawn, State.flyingNow and "thrown" or "held") end
                            end
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Push / pull
------------------------------------------------------------------------
-- Is there a wall/floor right in front of the held thing (along the camera)? Pushing further
-- would shove it through. false when the trace can't run.
local function wallAhead(target, camFwd)
    local okL, from = pcall(function() return target:K2_GetActorLocation() end)
    if not okL then return false end
    local ok, hit = pcall(function()
        local outHit = {}
        local to = vadd(from, vscale(camFwd, Config.Push.WallCheckDistance or 160.0))
        return KSL():LineTraceSingle(UEHelpers.GetWorld(), from, to, 0, false, { target }, 0, outHit, true,
            { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0.0)
    end)
    return ok and hit == true
end

local function pushPull(pk, target, dir, justPressed, dt, camFwd)
    local P = Config.Push
    local result = nil
    if dir > 0 and wallAhead(target, camFwd) then
        if not State.wallLogged then State.wallLogged = true; log(State.label .. ": push stopped at a wall (no clipping through)") end
        return nil
    end
    local distName = findDistProp(pk)
    if distName then
        local holder = State.distObj or pk
        local d = tryGet(holder, distName)
        if type(d) == "number" then
            local step = dir * P.Speed * dt
            if justPressed then step = step + dir * P.TapStep end
            local minD = isPawn(target) and (P.MinDistancePeople or P.MinDistance) or P.MinDistance
            local nd = clamp(d + step, minD, P.MaxDistance)
            if nd ~= d then trySet(holder, distName, nd); dbg(string.format("Distance %.0f", nd)) end
            if not P.AlsoNudge then return nd end
            result = nd
        end
    end
    if not P.FallbackNudgeEnabled then return result end
    -- Fallback: physically nudge along the camera ray
    local root = tryGet(target, "RootComponent")
    local push = vscale(camFwd, dir * P.FallbackNudgeStrength * dt)
    local ok, sim = pcall(function() return root:IsSimulatingPhysics(FName("None")) end)
    if ok and sim then
        pcall(function() root:SetPhysicsLinearVelocity(push, true, FName("None")) end)
    else
        pcall(function() target:K2_AddActorWorldOffset(vscale(camFwd, dir * P.Speed * dt), false, {}, true) end)
    end
    return result
end

------------------------------------------------------------------------
-- Main tick
------------------------------------------------------------------------
local function resetTarget()
    if State.ride and State.endRide then pcall(State.endRide) end
    State.target, State.targetAddr = nil, nil
    State.prevVel, State.prevSpeed, State.prevLoc = nil, 0, nil
    hudHide()
end

-- R3 = BFGInputAction_CameraHandleDefaultRotation in the game's own action list. While PK holds
-- something, that slot in the player's action list points at a harmless action instead
-- (tutorial dismiss), and it is put back when PK lets go. Only swapped while R3 is up.
local function setCameraR3Blocked(pawn, pc, blocked)
    if not Config.BlockCameraR3 then blocked = false end
    if (State.r3Blocked or false) == blocked then return end
    if isDown(pc, "Gamepad_RightThumbstick") then return end
    local ia = tryGet(pawn, "m_pInputActionsComponent")
    if not valid(ia) then return end
    local ok = pcall(function()
        local arr = ia.m_aCurrentActions
        if blocked then
            local camIdx, sub, cam = nil, nil, nil
            local i = 0
            arr:ForEach(function(_, e)
                i = i + 1
                local a = e:get()
                local cn = className(a)
                if cn == "BFGInputAction_CameraHandleDefaultRotation" then camIdx, cam = i, a end
                if cn == "BFGInputAction_PlayerTutorialDismiss" then sub = a end
            end)
            if camIdx and sub then
                State.r3Saved = cam
                State.r3Index = camIdx
                arr[camIdx] = sub
                State.r3Blocked = true
                if not State.r3Logged then State.r3Logged = true; log(State.label .. ": R3 camera turn blocked while PK holds something") end
            else
                State.r3Blocked = true -- nothing to swap; don't retry every tick
            end
        else
            if State.r3Index and valid(State.r3Saved) then
                local cur = arr[State.r3Index]
                if type(cur) == "userdata" and not valid(cur) then pcall(function() cur = cur:get() end) end
                if valid(cur) and className(cur) == "BFGInputAction_PlayerTutorialDismiss" then arr[State.r3Index] = State.r3Saved end
            end
            State.r3Saved, State.r3Index, State.r3Blocked = nil, nil, false
        end
    end)
    if not ok then State.r3Blocked = blocked end
end

local function Tick(pc)
    if not ModEnabled then return end
    if not valid(pc) then return end
    local pawn = tryGet(pc, "Pawn")
    if not valid(pawn) then resetTarget(); return end

    local rbDown = isDown(pc, Config.Keys.PKHold)
    local pk = findPKComponent(pawn)
    -- PK is on whenever the ability holds something: tap RB (blue, stays on) or hold RB (red).
    local target = valid(pk) and getHeldActor(pk) or nil
    if valid(pk) then
        local okS, st = pcall(function() return pk.m_eAbilityState end)
        st = okS and st or nil
        local tk = valid(target) and className(target) or "nothing"
        local line = tostring(st) .. "|" .. tk .. "|" .. tostring(rbDown)
        if line ~= State.lastPKLine then
            State.lastPKLine = line
            log(string.format("%s PK: ability state %s, holding %s, RB %s", State.label, tostring(st), tk, rbDown and "down" or "up"))
        end
    end

    -- Holding RB with something grabbed: "HOLD TO THROW" (red). LB turns it blue: let go of
    -- RB and it's dropped where it is instead of thrown. Tap RB (the game's blue PK) as before.
    State.holdingRB = rbDown and valid(target)
    local lbDown = isDown(pc, "Gamepad_LeftShoulder")
    if State.holdingRB and lbDown and not State.lbWasDown then
        State.dropMode = not State.dropMode
        log(State.label .. (State.dropMode and ": PK release mode (let go of RB to drop)" or ": PK throw mode"))
    end
    State.lbWasDown = lbDown
    if not valid(target) and not rbDown then
        if State.dropMode and valid(State.target) and not State.cancelUntil then
            State.cancelUntil = now() + 0.3     -- just let go in release mode: stop the throw
            State.gentleUntil = now() + 3.0     -- ...and set it down: no impact damage, a slow fall
        end
        State.dropMode = false
    end

    -- Block the game's own R3/L3 actions while PK is active (runs even when paused)
    local gateWanted = rbDown and (Config.InputGate.When == "RBDown" or valid(target))
    InputGate.Update(gateWanted, function(k) return isDown(pc, k) end)

    local t = now()
    local dt = State.lastTime and clamp(t - State.lastTime, 0, 0.1) or 0
    State.lastTime = t
    if dt <= 0 then return end -- paused or first tick

    setCameraR3Blocked(pawn, pc, valid(target))

    -- Just let go (dropped or thrown): keep watching it for a few seconds so hitting the
    -- ground or a wall still counts. No push/pull or label while it flies.
    local flying = false
    if not valid(target) then
        if valid(State.target) and State.flyUntil == nil then
            State.flyUntil = t + Config.Damage.AfterReleaseSeconds
        end
        if valid(State.target) and State.flyUntil and t < State.flyUntil then
            target, flying = State.target, true
        else
            State.flyUntil = nil
            resetTarget()
            return
        end
    else
        State.flyUntil = nil
    end

    -- a dropped (not thrown) thing comes down slowly, so people don't die from the fall
    if flying and State.gentleUntil and t < State.gentleUntil then
        pcall(function()
            local cm = target.CharacterMovement
            local v = cm.Velocity
            if v.Z < -350 then cm.Velocity = { X = v.X * 0.5, Y = v.Y * 0.5, Z = -350 } end
        end)
        pcall(function()
            local m = target.Mesh
            local v = m:GetPhysicsLinearVelocity(FName("None"))
            if v and v.Z < -350 then m:SetAllPhysicsLinearVelocity({ X = v.X * 0.5, Y = v.Y * 0.5, Z = -350 }, false) end
        end)
    elseif State.gentleUntil and (not flying or t >= State.gentleUntil) then
        State.gentleUntil = nil
    end
    if flying and State.cancelUntil then
        if t < State.cancelUntil then
            pcall(function() target:LaunchCharacter(V(0, 0, 0), true, true) end)
            pcall(function() target:K2_GetRootComponent():SetPhysicsLinearVelocity(V(0, 0, 0), false, FName("None")) end)
            pcall(function() target.Mesh:SetAllPhysicsLinearVelocity(V(0, 0, 0), false) end)
        else
            State.cancelUntil = nil
        end
    elseif not flying then
        State.cancelUntil = nil
    end

    local ta = addr(target)
    if ta ~= State.targetAddr then
        State.target, State.targetAddr = target, ta
        State.prevVel, State.prevSpeed, State.prevLoc = nil, 0, nil
        State.grabAt = t
        State.fxReported = false
        State.rideLogs = 0
    end
    -- Magic carpet: Crypto standing on the thing he lifts. The thing stops blocking him (so PK
    -- moves it like anything else: in, out, release), and the mod carries him on top of it.
    -- Jumping or letting go ends the ride.
    if Config.CarpetRide ~= false then
        local tl = nil
        pcall(function() tl = target:K2_GetActorLocation() end)
        if not State.ride and not flying and tl then
            local base = nil
            pcall(function() base = pawn:GetMovementBase() end)
            local owner = nil
            if valid(base) then pcall(function() owner = base:GetOwner() end) end
            if valid(owner) and addr(owner) == addr(target) then
                local root = nil
                pcall(function() root = target:K2_GetRootComponent() end)
                State.ride = { target = target, root = root, last = vcopy(tl), pawn = pawn }
                pcall(function() root:SetCollisionResponseToChannel(2, 0) end)   -- Pawn: ignore
                pcall(function() pawn.CharacterMovement:SetMovementMode(5, 0) end)  -- held up by the mod
                State.endRide = function()
                    local r = State.ride
                    State.ride = nil
                    if not r then return end
                    if valid(r.root) then pcall(function() r.root:SetCollisionResponseToChannel(2, 2) end) end   -- Pawn: block again
                    if valid(r.pawn) then pcall(function() r.pawn.CharacterMovement:SetMovementMode(3, 0) end) end   -- falling, lands normally
                    log(State.label .. ": magic carpet ride over")
                end
                log(State.label .. ": magic carpet ride on " .. className(target))
            end
        end
        local r = State.ride
        if r then
            if flying or not tl or addr(r.target) ~= addr(target) or isDown(pc, "Gamepad_FaceButton_Bottom") then
                pcall(State.endRide)
            else
                local d = vsub(tl, r.last)
                r.last = vcopy(tl)
                pcall(function()
                    local pl = pawn:K2_GetActorLocation()
                    pawn:K2_SetActorLocation(vadd(pl, d), false, {}, true)
                    pawn.CharacterMovement.Velocity = V(0, 0, 0)
                end)
            end
        end
    end
    -- held things don't spin (a held car or crate could start turning on its own)
    if not flying and Config.NoSpin ~= false then
        pcall(function() target.Mesh:SetAllPhysicsAngularVelocityInDegrees({ X = 0, Y = 0, Z = 0 }, false) end)
        pcall(function() target:K2_GetRootComponent():SetPhysicsAngularVelocityInDegrees({ X = 0, Y = 0, Z = 0 }, false, FName("None")) end)
    end
    -- (temporary) what the PK glow is made of on this player's held thing, once per grab
    if Config.FxReport and not flying and not State.fxReported and t - (State.grabAt or t) > 0.4 then
        State.fxReported = true
        State.fxReports = (State.fxReports or 0) + 1
        if State.fxReports <= 6 then
            local parts = {}
            local function note(owner, c, n)
                local cn = className(c)
                if cn:find("Particle") or cn:find("Niagara") or cn:find("Effect") or cn:find("Decal")
                   or tostring(n):find("PK") or cn:find("PK") then
                    local okV, vis = pcall(function() return c:IsVisible() end)
                    local okR, r = pcall(function() return c:K2_GetComponentRotation() end)
                    local tmpl = ""
                    pcall(function() local tp = c.Template; if valid(tp) then tmpl = " " .. tp:GetFName():ToString() end end)
                    parts[#parts + 1] = string.format("%s.%s(%s%s vis=%s rot=%s)", owner, tostring(n), cn, tmpl, tostring(okV and vis),
                        okR and string.format("%.0f/%.0f/%.0f", r.Pitch, r.Yaw, r.Roll) or "?")
                end
            end
            pcall(function() forEachComponent(target, function(c, n) note("held", c, n) end) end)
            pcall(function() forEachComponent(pawn, function(c, n) note("crypto", c, n) end) end)
            pcall(function()
                local out = {}
                target:GetAttachedActors(out)
                for _, a in ipairs(out) do
                    local v = a
                    if type(a) == "userdata" and a.get then pcall(function() v = a:get() end) end
                    if valid(v) then
                        parts[#parts + 1] = "attached actor " .. className(v)
                        pcall(function() forEachComponent(v, function(c, n) note(className(v), c, n) end) end)
                    end
                end
            end)
            log(string.format("%s PK glow on %s: %s", State.label, className(target), #parts > 0 and table.concat(parts, "; ") or "nothing found"))
        end
    end
    -- (temporary) riding a held thing ("magic carpet"): is Crypto standing on it?
    if Config.RideReport and not flying and (State.rideLogs or 0) < 12 then
        local okB, base = pcall(function() return pawn:GetMovementBase() end)
        local baseOwner = nil
        if okB and valid(base) then pcall(function() baseOwner = base:GetOwner() end) end
        if valid(baseOwner) and addr(baseOwner) == ta and t - (State.rideAt or 0) > 0.5 then
            State.rideAt = t
            State.rideLogs = (State.rideLogs or 0) + 1
            local okL, tl = pcall(function() return target:K2_GetActorLocation() end)
            local okP, pl = pcall(function() return pawn:K2_GetActorLocation() end)
            local okV, tv = pcall(function() return target:GetVelocity() end)
            local okS, sim = pcall(function() return base:IsSimulatingPhysics(FName("None")) end)
            local arm = tryGet(State.distObj or pk, State.distProp or "")
            log(string.format("%s riding %s: car z %.0f, Crypto z %.0f, car speed %.0f (up %.0f), physics %s, hold distance %s",
                State.label, className(target), okL and tl.Z or 0, okP and pl.Z or 0,
                okV and vlen(tv) or 0, okV and tv.Z or 0, tostring(okS and sim), tostring(arm)))
        end
    end

    -- Input
    local pullDown = isDown(pc, Config.Keys.PullIn) or isDown(pc, Config.Keys.PullInKB)
    local pushDown = isDown(pc, Config.Keys.PushOut) or isDown(pc, Config.Keys.PushOutKB)
    local dir, justPressed = 0, false
    if pullDown and not pushDown then
        dir = -1; justPressed = not State.pullWasDown
    elseif pushDown and not pullDown then
        dir = 1; justPressed = not State.pushWasDown
    end
    State.pullWasDown, State.pushWasDown = pullDown, pushDown
    if flying then dir = 0 end
    State.flyingNow = flying
    if flying and State.releaseSpeed == nil then State.releaseSpeed = State.prevSpeed or 0 end
    if not flying then State.releaseSpeed = nil end

    local camLoc, camRot, camFwd = cameraInfo(pc)
    local dist = nil
    local blue = not rbDown or State.dropMode
    local resize = dir ~= 0 and blue and Config.BlueResize and not flying
    if resize then
        -- shrink ray / growth ray: L3 shrinks, R3 grows (smoothly while held)
        pcall(function()
            local sc = target:GetActorScale3D()
            local k = (dir < 0) and (1 - 1.2 * dt) or (1 + 1.2 * dt)
            local nsx = clamp(sc.X * k, 0.15, 6.0)
            local f = nsx / sc.X
            target:SetActorScale3D(V(sc.X * f, sc.Y * f, sc.Z * f))
        end)
    elseif dir ~= 0 and camFwd then
        dist = pushPull(pk, target, dir, justPressed, dt, camFwd)
    elseif State.distProp then
        dist = tryGet(State.distObj or pk, State.distProp)
    end

    -- Kinematics for damage
    local okL, loc = pcall(function() return target:K2_GetActorLocation() end)
    local okV, vel = pcall(function() return target:GetVelocity() end)
    -- A ragdolled NPC's capsule stays put while its body flies: follow the physics mesh.
    local mesh = tryGet(target, "Mesh")
    if valid(mesh) then
        local okS, sim = pcall(function() return mesh:IsSimulatingPhysics(FName("None")) end)
        if okS and sim then
            local okML, ml = pcall(function() return mesh:K2_GetComponentLocation() end)
            local okMV, mv = pcall(function() return mesh:GetPhysicsLinearVelocity(FName("None")) end)
            if okML and okMV then okL, loc, okV, vel = true, ml, true, mv end
        end
    end
    if okL then
        loc = vcopy(loc)
        -- Velocity from how far it actually moved (PK carries things without physics velocity)
        if State.prevLoc then
            vel = vscale(vsub(loc, State.prevLoc), 1.0 / dt)
        elseif okV then
            vel = vcopy(vel)
        else
            vel = V(0, 0, 0)
        end
        State.prevLoc = loc
        local speed = vlen(vel)
        if Config.Damage.Enabled and State.prevVel and (t - (State.grabAt or 0)) > 0.4 then
            if not State.gentleUntil then
                checkWallImpact(target, loc, vel, speed, dt, pc, pawn, t)
                checkBodyImpact(target, loc, vel, speed, pc, pawn, t)
            end
        end
        State.prevVel, State.prevSpeed = vel, speed

        -- HUD
        if flying then hudHide()
        elseif camRot then
            local text, color = nil, "green"
            if resize then text = dir < 0 and Config.Hud.TextShrink or Config.Hud.TextGrow; color = "blue"
            elseif dir < 0 then text = Config.Hud.TextIn
            elseif dir > 0 then text = Config.Hud.TextOut
            elseif State.holdingRB and State.dropMode then text, color = Config.Hud.TextRelease, "blue"
            elseif State.holdingRB then text, color = Config.Hud.TextThrow, "red"
            elseif Config.Hud.ShowDistanceWhenIdle and type(dist) == "number" then
                text = string.format("%.0fm", dist / 100.0)
            end
            if text then
                -- under the held thing's lowest point (its bounds), checked twice a second
                if State.boundsFor ~= target or t - (State.boundsAt or -10) > 0.5 then
                    State.boundsFor, State.boundsAt = target, t
                    State.belowBy = nil
                    pcall(function()
                        local origin, extent = {}, {}
                        target:GetActorBounds(true, origin, extent)
                        if type(extent.Z) == "number" and extent.Z > 0 and type(origin.Z) == "number" then
                            State.belowBy = (origin.Z - extent.Z) - loc.Z
                        end
                    end)
                end
                local at = V(loc.X, loc.Y, loc.Z - 80)
                if State.belowBy then at = V(loc.X, loc.Y, loc.Z + State.belowBy) end
                hudShow(at, camLoc, camRot, text, color)
            else hudHide() end
        end
    end
end

-- Run Tick from the game thread itself (the player character's tick), at most every
-- Config.TickMs. The old LoopAsync + ExecuteInGameThread at 60 Hz ran Lua on a timer thread at
-- the same time as the game thread, which corrupts UE4SS ("Ref was not function") and crashes.
-- The timer below only runs until the hook is in place, then stops for good.
local tickHooked, lastTick = false, -1000
local DumpRequested = false
local runDump -- set below (F9)
local function players()
    local list = {}
    local world = UEHelpers.GetWorld()
    for i = 0, 1 do
        local ok, pc = pcall(function() return GS():GetPlayerController(world, i) end)
        list[i + 1] = (ok and valid(pc)) and pc or nil
    end
    return list
end
local function runTick()
    local now = os.clock()
    if (now - lastTick) * 1000 < Config.TickMs then return end
    lastTick = now
    local pcs = players()
    for i = 1, 2 do
        -- a different controller in this slot (Player 2 left and came back): start that player
        -- fresh, so nothing from the old body is used on the new one
        local key = nil
        if pcs[i] then pcall(function() key = tostring(pcs[i]:GetAddress()) end) end
        if States[i].pcKey ~= key then
            if States[i].pcKey ~= nil then
                local old = States[i]
                if valid(old.hudActor) then pcall(function() old.hudActor:K2_DestroyActor() end) end
                States[i] = newState()
                States[i].label = i == 2 and "P2" or "P1"
            end
            States[i].pcKey = key
        end
        State = States[i]
        if pcs[i] then
            local ok, err = pcall(Tick, pcs[i])
            if not ok then dbg("Tick error: " .. tostring(err)) end
        else
            resetTarget()
        end
        if OverkillCoop and OverkillCoop.state then
            OverkillCoop.state.pkHolding = OverkillCoop.state.pkHolding or {}
            OverkillCoop.state.pkHolding[i] = State.holdingRB and true or false
        end
    end
    State = States[1]
    if DumpRequested then
        DumpRequested = false
        -- dump whoever is holding RB (P2 if only P2 is), else P1
        local who = 1
        if pcs[2] and isDown(pcs[2], Config.Keys.PKHold) and not (pcs[1] and isDown(pcs[1], Config.Keys.PKHold)) then who = 2 end
        State = States[who]
        pcall(runDump, pcs[who])
        State = States[1]
    end
end
local function tryHookTick()
    if tickHooked then return end
    local ok = pcall(function()
        RegisterHook("/Game/Blueprints/Character/Player/BP_CharacterPlayer.BP_CharacterPlayer_C:ReceiveTick", runTick)
    end)
    tickHooked = ok
end
LoopAsync(1000, function()
    if tickHooked then return true end
    ExecuteInGameThread(tryHookTick)
    return false
end)

------------------------------------------------------------------------
-- F9: discovery dump
------------------------------------------------------------------------
local function describeValue(v)
    if type(v) == "number" then return string.format(" = %.3f", v) end
    if type(v) == "boolean" then return " = " .. tostring(v) end
    if valid(v) then return " -> " .. className(v) end
    if type(v) == "userdata" then
        local okN, nm = pcall(function() return v:ToString() end)
        if okN and type(nm) == "string" then return " = " .. nm end
        local okK, kn = pcall(function() return v.KeyName:ToString() end)
        if okK and type(kn) == "string" then return " = key " .. kn end
    end
    if valid(v) then return " -> " .. className(v) end
    return ""
end

local function isActorObj(o)
    local ok, r = pcall(function() return o:IsA(cls("/Script/Engine.Actor")) end)
    return ok and r
end

local function structName(prop)
    local ok, n = pcall(function() return prop:GetStruct():GetFName():ToString() end)
    return ok and n or "?"
end

-- Print the fields of a struct value (one level)
local function dumpStruct(sval, prop, indent)
    pcall(function()
        prop:GetStruct():ForEachProperty(function(f)
            local fn = propName(f)
            if fn then
                local ok, fv = pcall(function() return sval[fn] end)
                log(string.format("%s.%s : %s%s", indent, fn, propType(f), ok and describeValue(fv) or ""))
            end
        end)
    end)
end

-- Deep dump: every property, plus one level into matching sub-objects,
-- object arrays and structs. filter = only names matching Config.DumpKeywords.
local function dumpObject(obj, stopAt, filter, depth, seen, indent)
    seen = seen or {}
    indent = indent or "    "
    local a = addr(obj)
    if seen[a] then log(indent .. "(already dumped)"); return end
    seen[a] = true
    local count = 0
    forEachProp(obj, stopAt, function(prop, owner)
        local n = propName(prop)
        if not n then return end
        if filter and not matchesList(n, Config.DumpKeywords) then return end
        count = count + 1
        local ptype = propType(prop)
        local v = tryGet(obj, n)

        if ptype == "StructProperty" then
            local sn = structName(prop)
            log(string.format("%s[%s] %s : struct %s", indent, owner, n, sn))
            if depth > 0 and (matchesList(n, Config.DeepDumpHints) or matchesList(sn, Config.DeepDumpHints)) then
                dumpStruct(v, prop, indent .. "    ")
            end
        elseif ptype == "ArrayProperty" then
            local len, elems = 0, {}
            pcall(function()
                v:ForEach(function(_, e)
                    len = len + 1
                    local ev = e:get()
                    if #elems < 40 then table.insert(elems, ev) end
                end)
            end)
            log(string.format("%s[%s] %s : array (%d)", indent, owner, n, len))
            -- array of structs: print each element's fields
            local okI, innerSt = pcall(function()
                local inner = prop:GetInner()
                if propType(inner) ~= "StructProperty" then return nil end
                return inner:GetStruct()
            end)
            if okI and innerSt and depth > 0 then
                local idx = 0
                pcall(function()
                    v:ForEach(function(_, e)
                        idx = idx + 1
                        if idx > 40 then return end
                        local ev = e:get()
                        local parts = {}
                        innerSt:ForEachProperty(function(f)
                            local fn = propName(f)
                            local ft = propType(f)
                            local scalar = ft == "FloatProperty" or ft == "IntProperty" or ft == "BoolProperty"
                                or ft == "ByteProperty" or ft == "NameProperty" or ft == "EnumProperty" or ft == "ObjectProperty"
                            if fn and not scalar then parts[#parts + 1] = fn .. " : " .. ft end
                            if fn and scalar then
                                local okf, fv = pcall(function() return ev[fn] end)
                                if okf then parts[#parts + 1] = fn .. describeValue(fv) end
                            end
                        end)
                        log(string.format("%s    [%d] {%s}", indent, idx, table.concat(parts, "; ")))
                    end)
                end)
                elems = {}
            end
            for i, ev in ipairs(elems) do
                if valid(ev) then
                    log(string.format("%s    [%d] -> %s", indent, i, className(ev)))
                    if depth > 0 and not isActorObj(ev) and matchesList(className(ev), Config.DeepDumpHints) then
                        dumpObject(ev, "Object", nil, depth - 1, seen, indent .. "        ")
                    end
                elseif type(ev) == "number" or type(ev) == "boolean" then
                    log(string.format("%s    [%d] = %s", indent, i, tostring(ev)))
                end
            end
        else
            log(string.format("%s[%s] %s : %s%s", indent, owner, n, ptype, describeValue(v)))
            if depth > 0 and valid(v) and not isActorObj(v)
                and (matchesList(n, Config.DeepDumpHints) or matchesList(className(v), Config.DeepDumpHints)) then
                dumpObject(v, "Object", nil, depth - 1, seen, indent .. "    ")
            end
        end
    end)
    if count == 0 then log(indent .. "(nothing)") end
end

local function dumpProps(obj, stopAt, filter) dumpObject(obj, stopAt, filter, 0) end

runDump = function(pc)
    do
        local pawn = valid(pc) and tryGet(pc, "Pawn") or nil
        if not valid(pawn) then log("No pawn."); return end
        log("==== DISCOVERY v4, " .. State.label .. " (hold something with PK when you press F9) ====")
        log("Pawn class: " .. className(pawn))

        -- Full deep dump of the components that matter
        for _, pname in ipairs(Config.DeepDumpComponents) do
            local c = tryGet(pawn, pname)
            if valid(c) then
                log("---- " .. pname .. " : " .. className(c) .. " ----")
                dumpObject(c, "ActorComponent", nil, 2)
            else
                log("---- " .. pname .. " : not found ----")
            end
        end

        -- The game's own input layer: every action object, the locked groups and the scheme
        local ia = tryGet(pawn, "m_pInputActionsComponent")
        if valid(ia) then
            log("---- input scheme ----")
            local okS, scheme = pcall(function() return ia:GetCurrentInputScheme() end)
            if okS and valid(scheme) then
                log("scheme: " .. className(scheme))
                dumpObject(scheme, "Object", nil, 2)
            else
                log("scheme: none (" .. tostring(scheme) .. ")")
            end
            forEachProp(ia, "ActorComponent", function(prop)
                if propName(prop) == "m_aLockedGroups" then
                    local okI, inner = pcall(function() return prop:GetInner() end)
                    log("m_aLockedGroups element type: " .. (okI and propType(inner) or "?"))
                    pcall(function() log("  enum: " .. inner:GetEnum():GetFName():ToString()) end)
                end
            end)
        end

        State.pkComp, State.pkMissAt, State.heldProp, State.distProp = nil, nil, nil, nil
        local pk = findPKComponent(pawn)
        local held = valid(pk) and getHeldActor(pk) or nil
        if valid(held) then
            log("Held actor class: " .. className(held))
            log("Held actor properties matching keywords:")
            dumpProps(held, "Object", true)
        else
            log("No held actor found through HeldActorProps (expected until we pick the right name).")
        end
        log("==== END ====")
    end
end
-- The key callback runs off the game thread, so it only sets a flag; the dump runs in the tick.
RegisterKeyBind(Key.F9, function() DumpRequested = true end)


-- F6 toggle (F10 is the console key in ConsoleEnablerMod)
RegisterKeyBind(Key.F6, function()
    ModEnabled = not ModEnabled
    log("Enabled = " .. tostring(ModEnabled))
end)

-- F5 input mapping list (F7/F8 are used with Ctrl by DAH2P)
RegisterKeyBind(Key.F5, function()
    ExecuteInGameThread(InputGate.DumpMappings)
end)

log("Loaded. F5 = input mappings, F6 = toggle, F9 = discovery dump.")
