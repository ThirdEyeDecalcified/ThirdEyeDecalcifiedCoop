--[[
    Third Eye Decalcified Co-op - free camera for filming (hidden key: Ctrl+Shift+F12)
    A free-flying camera that goes through anything, shown over the WHOLE screen (split screen
    or not), with every HUD (the game's and the mod's) hidden. Nobody's view or controls are
    touched: however many players there are, they all keep playing underneath. The camera
    films into a picture that covers the screen; Ctrl+Shift+F12 again takes it away.
    Keys (free while the camera is on; only Player 2's optional keyboard mode also uses them):
      NumPad 8 / 5 / 4 / 6   forward / back / left / right
      Page Up / Page Down    up / down
      Mouse, or NumPad 7 / 9 and 1 / 3   look around (turn / tilt)
      NumPad + / -           faster / slower (hold Left Shift: 4x)
      NumPad * / /           zoom in / out
]]

local OK = OverkillCoop
if not OK then return end
local state, log, valid = OK.state, OK.log, OK.valid
local CFG = OK.CFG or {}

local cam = nil          -- the scene capture (the free camera)
local reticle = nil      -- the reticle viewer's widget (NumPad -)
local screen = nil       -- the full-screen picture it films into
local fc = { on = false, speed = 900, fov = 90, yaw = 0, pitch = 0, hidden = {}, texts = {} }

local function key(pc, name) return OK.kbDown(pc, name) end
local function axis(pc, name)
    local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(name) }) end)
    return (ok and type(v) == "number") and v or 0
end

-- every HUD off: the game's widgets, the mod's, and the words floating in the world
local function hideAll()
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(w) then
            local k = OK.keyOf(w)
            if screen and k == OK.keyOf(screen) then
                -- the free camera's own picture stays
            elseif reticle and k == OK.keyOf(reticle) then
                -- the reticle viewer stays too
            elseif valid(state.trainerWidget) and k == OK.keyOf(state.trainerWidget) then
                -- and the trainer menu (that's where you switch this off)
            elseif fc.hidden[k] == nil then
                local okS, vis = pcall(function() return w:GetVisibility() end)
                -- anything showing (0 visible, 3/4 visible but not clickable), wherever it sits
                if okS and (vis == 0 or vis == 3 or vis == 4) then
                    fc.hidden[k] = { w = w, vis = vis }
                    pcall(function() w:SetVisibility(2) end)
                end
            elseif fc.hidden[k] then
                pcall(function() w:SetVisibility(2) end)
            end
        end
    end
    for _, a in ipairs(FindAllOf("TextRenderActor") or {}) do
        if valid(a) then
            local k = OK.keyOf(a)
            if not fc.texts[k] then
                local okH, h = pcall(function() return a.bHidden end)
                fc.texts[k] = { a = a, was = okH and h or false }
            end
            pcall(function() a:SetActorHiddenInGame(true) end)
        end
    end
end
local function showAll()
    for _, e in pairs(fc.hidden) do
        if e and valid(e.w) then pcall(function() e.w:SetVisibility(e.vis) end) end
    end
    for _, e in pairs(fc.texts) do
        if valid(e.a) then pcall(function() e.a:SetActorHiddenInGame(e.was == true) end) end
    end
    fc.hidden, fc.texts = {}, {}
end

-- a widget to hold the picture: an empty copy of one of the game's own HUD widgets
local function makeScreen(rt)
    local pc = OK.player1Controller()
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, hud in ipairs(OK.hudWidgetsOf(pc)) do
        local note = OK.subObj(hud, "BPW_HUD_TextNotification")
        if note then template = note break end
        template = template or hud
    end
    if not (valid(wbl) and template) then return nil end
    local ok, w = pcall(function() return wbl:Create(OK.getWorld(), template:GetClass(), pc) end)
    if not (ok and valid(w)) then return nil end
    local tree = OK.subObj(w, "WidgetTree")
    local img = tree and StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("OK_FreecamImage"))
    if not valid(img) then return nil end
    pcall(function() img:SetBrushResourceObject(rt) end)
    pcall(function() tree.RootWidget = img end)
    -- on the viewport itself (not a player's part of it): the whole screen, above everything
    pcall(function() w:AddToViewport(10000) end)
    return w
end

local function start()
    local pc = OK.player1Controller()
    if not valid(pc) then return end
    local loc, rot = nil, nil
    pcall(function()
        local cm = pc.PlayerCameraManager
        loc, rot = cm:GetCameraLocation(), cm:GetCameraRotation()
    end)
    if not loc then return end
    -- the picture is the size of the whole window
    local w, h = 1920, 1080
    pcall(function()
        local v = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(OK.getWorld())
        if v.X > 100 and v.Y > 100 then w, h = math.floor(v.X), math.floor(v.Y) end
    end)
    local okR, rt = pcall(function()
        local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
        local black = { R = 0, G = 0, B = 0, A = 1 }
        -- this engine wants the clear colour too (and some builds the mip-map flag)
        local okA, r = pcall(function() return krl:CreateRenderTarget2D(OK.getWorld(), w, h, 2, black) end)
        if okA and valid(r) then return r end
        return krl:CreateRenderTarget2D(OK.getWorld(), w, h, 2, black, false)  -- RGBA8
    end)
    if not (okR and valid(rt)) then log("Free camera: couldn't make the picture (%s)", tostring(rt)) return end
    local ok, a = pcall(function() return OK.getWorld():SpawnActor(StaticFindObject("/Script/Engine.SceneCapture2D"), loc, rot) end)
    if not (ok and valid(a)) then log("Free camera: couldn't be made") return end
    cam = a
    local cc = a.CaptureComponent2D
    pcall(function() cc.TextureTarget = rt end)
    pcall(function() cc.CaptureSource = 2 end)          -- the finished picture, like the game's own view
    pcall(function() cc.bCaptureEveryFrame = true end)
    pcall(function() cc.FOVAngle = fc.fov end)
    screen = makeScreen(rt)
    if not screen then log("Free camera: couldn't put the picture on screen"); pcall(function() a:K2_DestroyActor() end); cam = nil; return end
    fc.on, fc.yaw, fc.pitch = true, rot.Yaw, rot.Pitch
    state.hudAllHidden = true
    hideAll()
    state.freecamOn = true
    log("Free camera on, whole screen %dx%d (Ctrl+Shift+F12 to leave). NumPad 8/5/4/6 move, PgUp/PgDn up/down, mouse or NumPad 7/9/1/3 look, +/- speed, * / zoom", w, h)
end

local function stop()
    state.hudAllHidden = fc.hudOff
    fc.on = false
    state.freecamOn = false
    if valid(screen) then pcall(function() screen:RemoveFromParent() end) end
    screen = nil
    if valid(cam) then pcall(function() cam:K2_DestroyActor() end) end
    cam = nil
    if not fc.hudOff then showAll() end
    log("Free camera off")
end

-- Trainer: every HUD off (the game's and the mod's), without the free camera
fc.hudOff = false
state.trainerExtras = state.trainerExtras or {}
state.trainerExtras[#state.trainerExtras + 1] = {
    key = "x_hideall", page = 3, label = "TEST  Hide every HUD (game's and mod's; for filming)", options = { "Off", "On" },
    get = function() return fc.hudOff and "On" or "Off" end,
    set = function(v)
        fc.hudOff = v == "On"
        state.hudAllHidden = fc.hudOff
        if fc.hudOff then hideAll() elseif not fc.on then showAll() end
        log("Trainer: every HUD %s", fc.hudOff and "hidden" or "back")
    end,
    reset = function() state.hudAllHidden = false; if fc.hudOff then fc.hudOff = false; if not fc.on then showAll() end end end,
}

-- Reticle viewer: NumPad - steps through the game's unused placeholder crosshairs, shown in
-- the middle of Player 1's screen with their name (to pick ones for powers and auras)
local RETICLES = {
    "Crosshair_GRD_Abducto_Beam", "Crosshair_GRD_Anal_Probe", "Crosshair_GRD_Disintegrator", "Crosshair_GRD_Ion_Detonator",
    "Crosshair_GRD_Quantum_Deconstructor", "Crosshair_GRD_Sonic_Boom", "Crosshair_GRD_Zap_o_Matic", "Crosshair_PSI_Action",
    "Crosshair_PSI_Lock", "Crosshair_UFO_Death_Ray", "PLACEHOLDER_Crosshair_AnalProbe", "PLACEHOLDER_Crosshair_DeathRay",
    "PLACEHOLDER_Crosshair_Disintegrator", "PLACEHOLDER_Crosshair_IonDetonator", "PLACEHOLDER_Crosshair_ZapOMatic",
    "PLACEHOLDER_TargetMarkerAnalProbe", "PSI_Marker", "SHOOT_Marker", "Tex2D_sucess_flare_DUMMY",
}
local retIdx = 0
local retImg, retText = nil, nil
local function reticleTexture(name)
    local path = "/Game/UI/PLACEHOLDERS/" .. name .. "." .. name
    local t = StaticFindObject(path)
    if not valid(t) then pcall(function() t = LoadAsset(path) end) end
    return valid(t) and t or nil
end
local function showReticle()
    -- the next one that exists (some names may be cut short in the list)
    local tex, name = nil, nil
    for _ = 1, #RETICLES do
        retIdx = retIdx + 1
        if retIdx > #RETICLES then retIdx = 0; break end
        tex = reticleTexture(RETICLES[retIdx])
        if tex then name = RETICLES[retIdx] break end
    end
    if not tex then
        if valid(reticle) then pcall(function() reticle:RemoveFromParent() end) end
        reticle, retImg, retText = nil, nil, nil
        log("Reticle viewer: off")
        return
    end
    if not valid(reticle) then
        local pc = OK.player1Controller()
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local template = nil
        for _, hud in ipairs(OK.hudWidgetsOf(pc)) do
            local note = OK.subObj(hud, "BPW_HUD_TextNotification")
            if note then template = note break end
        end
        if not (valid(wbl) and template) then return end
        local okW, w = pcall(function() return wbl:Create(OK.getWorld(), template:GetClass(), pc) end)
        if not (okW and valid(w)) then return end
        local tree = OK.subObj(w, "WidgetTree")
        local box = tree and StaticConstructObject(StaticFindObject("/Script/UMG.VerticalBox"), tree, FName("OK_RetBox"))
        local sb = tree and StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName("OK_RetSize"))
        retImg = tree and StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("OK_RetImg"))
        retText = tree and StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, FName("OK_RetText"))
        if not (valid(box) and valid(sb) and valid(retImg) and valid(retText)) then return end
        pcall(function() sb:SetWidthOverride(CFG.RETICLE_VIEW_SIZE or 72); sb:SetHeightOverride(CFG.RETICLE_VIEW_SIZE or 72) end)
        pcall(function() sb:AddChild(retImg) end)
        pcall(function() local sl = box:AddChildToVerticalBox(sb); sl:SetHorizontalAlignment(2) end)
        pcall(function() local f = retText.Font; f.Size = 11; retText:SetFont(f) end)
        pcall(function() local sl = box:AddChildToVerticalBox(retText); sl:SetHorizontalAlignment(2) end)
        pcall(function() retText:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 0.85, B = 0.3, A = 1 }, ColorUseRule = 0 }) end)
        pcall(function() tree.RootWidget = box end)
        -- the borrowed widget hides itself by default (the trainer had the same): show it
        pcall(function() box:SetVisibility(4) end)
        pcall(function() w:SetVisibility(4) end)
        pcall(function() w:SetRenderOpacity(1.0) end)
        pcall(function() w:AddToPlayerScreen(500) end)
        pcall(function() w:SetAnchorsInViewport({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } }) end)
        -- the picture's middle (not the label's) goes on the crosshair
        pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 * (CFG.RETICLE_VIEW_SIZE or 72) / ((CFG.RETICLE_VIEW_SIZE or 72) + 18) }) end)
        reticle = w
    end
    pcall(function() reticle:SetVisibility(4) end)
    pcall(function() reticle:SetRenderOpacity(1.0) end)
    pcall(function() retImg:SetBrushFromTexture(tex, false) end)
    pcall(function() retImg:SetBrushSize({ X = CFG.RETICLE_VIEW_SIZE or 72, Y = CFG.RETICLE_VIEW_SIZE or 72 }) end)
    pcall(function() retText:SetText(FText(string.format("%d/%d  %s   (NumPad - : next)", retIdx, #RETICLES, name))) end)
    log("Reticle viewer: %s", name)
end
if Key.SUBTRACT ~= nil then
    RegisterKeyBind(Key.SUBTRACT, function()
        -- the free camera uses NumPad - for its speed, and Player 2's keyboard mode for weapons
        if fc.on or state.kbOn then return end
        OK.runGame("reticleViewer", showReticle)
    end)
end

-- where Player 1's real crosshair is on screen (pixels), from the game's own crosshair widget
local SBL = nil
local function crosshairPixel()
    local pc = OK.player1Controller()
    if not valid(pc) then return nil end
    SBL = SBL or StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary")
    if not valid(SBL) then return nil end
    local list = {}
    if valid(state.retCross) and state.retCross:IsVisible() then list = { state.retCross }
    elseif os.clock() >= (state.retScanAt or 0) then
        state.retScanAt = os.clock() + 3.0
        list = FindAllOf("UserWidget") or {}
    end
    for _, w in ipairs(list) do
        local okN, nm = pcall(function() return w:GetClass():GetFName():ToString() end)
        if okN and nm:find("Crosshair") and valid(w) then
            local okO, own = pcall(function() return w:GetOwningPlayer() end)
            local okV, vis = pcall(function() return w:IsVisible() end)
            if okV and vis and (not okO or not valid(own) or OK.keyOf(own) == OK.keyOf(pc)) then
                local img = nil
                pcall(function()
                    w:GetClass():ForEachProperty(function(pp)
                        if img then return end
                        local n = pp:GetFName():ToString()
                        local okI, v = pcall(function() return w[n] end)
                        if okI and valid(v) and OK.nameOf(v):find("^Image") then img = v end
                    end)
                end)
                local target = img or w
                local out = nil
                pcall(function()
                    local geo = target:GetCachedGeometry()
                    local size = SBL:GetLocalSize(geo)
                    if not (size and size.X > 0) then return end
                    local pix, vp = {}, {}
                    SBL:LocalToViewport(OK.getWorld(), geo, { X = size.X / 2, Y = size.Y / 2 }, pix, vp)
                    if type(pix.X) == "number" and pix.X > 0 then out = { X = pix.X, Y = pix.Y } end
                end)
                if out then state.retCross = w; return out end
            end
        end
    end
    return nil
end
local placeAt = 0

local last = os.clock()
local rehideAt = 0
OK.addTickJob("freecam", 0.0, function()
    local now = os.clock()
    local dt = math.min(0.1, now - last)
    last = now
    -- the borrowed widget class keeps hiding itself: keep the reticle viewer showing
    if valid(reticle) then pcall(function() if not reticle:IsVisible() then reticle:SetVisibility(4) end; reticle:SetRenderOpacity(1.0) end) end
    if valid(reticle) and now >= placeAt then
        placeAt = now + 0.5
        local px = crosshairPixel()
        if px then
            pcall(function() reticle:SetPositionInViewport(px, true) end)
            if not state.retPlacedLogged then state.retPlacedLogged = true; log("Reticle viewer: on the game's crosshair at %.0f, %.0f", px.X, px.Y) end
        else
            -- no crosshair showing: the middle of Player 1's view
            pcall(function()
                local vs = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(OK.getWorld())
                local half = (state.p2 and 0.25 or 0.5)
                reticle:SetPositionInViewport({ X = vs.X * 0.5, Y = vs.Y * half }, true)
            end)
        end
    end
    if fc.hudOff and not fc.on and now >= rehideAt then rehideAt = now + 1.5; hideAll() end
    if not fc.on then return end
    local pc = OK.player1Controller()
    if not (valid(pc) and valid(cam) and valid(screen)) then stop() return end
    -- new HUD pieces (alerts, tags...) stay hidden too
    if now >= rehideAt then rehideAt = now + 1.5; hideAll() end
    -- look
    local turn = axis(pc, "MouseX") * 0.15 + ((key(pc, "NumPadNine") and 1 or 0) - (key(pc, "NumPadSeven") and 1 or 0)) * 90 * dt
    local tilt = axis(pc, "MouseY") * 0.15 + ((key(pc, "NumPadThree") and 1 or 0) - (key(pc, "NumPadOne") and 1 or 0)) * 60 * dt
    fc.yaw = fc.yaw + turn
    fc.pitch = math.max(-89, math.min(89, fc.pitch + tilt))
    -- speed and zoom
    if key(pc, "Add") then fc.speed = math.min(8000, fc.speed * (1 + dt)) end
    if key(pc, "Subtract") then fc.speed = math.max(50, fc.speed / (1 + dt)) end
    if key(pc, "Multiply") then fc.fov = math.max(10, fc.fov - 30 * dt); pcall(function() cam.CaptureComponent2D.FOVAngle = fc.fov end) end
    if key(pc, "Divide") then fc.fov = math.min(140, fc.fov + 30 * dt); pcall(function() cam.CaptureComponent2D.FOVAngle = fc.fov end) end
    -- move (through anything)
    local f = (key(pc, "NumPadEight") and 1 or 0) - (key(pc, "NumPadFive") and 1 or 0)
    local r = (key(pc, "NumPadSix") and 1 or 0) - (key(pc, "NumPadFour") and 1 or 0)
    local u = (key(pc, "PageUp") and 1 or 0) - (key(pc, "PageDown") and 1 or 0)
    local sp = fc.speed * (key(pc, "LeftShift") and 4 or 1) * dt
    local y, p = math.rad(fc.yaw), math.rad(fc.pitch)
    local fx, fy, fz = math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p)
    local rx, ry = -math.sin(y), math.cos(y)
    pcall(function()
        local l = cam:K2_GetActorLocation()
        cam:K2_SetActorLocation({ X = l.X + (fx * f + rx * r) * sp, Y = l.Y + (fy * f + ry * r) * sp, Z = l.Z + (fz * f + u) * sp }, false, {}, true)
        cam:K2_SetActorRotation({ Pitch = fc.pitch, Yaw = fc.yaw, Roll = 0 }, false)
    end)
end)

OK.onWorldChange(function()
    fc.on, fc.hudOff = false, false
    state.hudAllHidden = false
    state.freecamOn = false
    cam, screen, reticle = nil, nil, nil
    fc.hidden, fc.texts = {}, {}
end)

RegisterKeyBind(Key.F12, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
    OK.runGame("freecam", function() if fc.on then stop() else start() end end)
end)

-- A small picture from /Game/UI/PLACEHOLDERS that follows a spot in the world on one
-- player's screen (the sentry drone marks its target with the Zap-O-Matic crosshair).
-- state.texMarkerAt(id, pc, texName, worldLoc, size) shows / moves it; state.texMarkerHide(id).
local texMarkers = {}
local texMarkN = 0
OK.onWorldChange(function() texMarkers = {} end)
local function markFail(why)
    if not state["markFail" .. why] then state["markFail" .. why] = true; log("Target marker: couldn't be made (%s)", why) end
    return nil
end
local function buildTexMarker(pc, texName, size)
    local tex = reticleTexture(texName)
    if not tex then return markFail("no picture " .. tostring(texName)) end
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, hud in ipairs(OK.hudWidgetsOf(pc)) do
        local note = OK.subObj(hud, "BPW_HUD_TextNotification")
        if note then template = note break end
    end
    if not (valid(wbl) and template) then return markFail("no HUD to borrow from") end
    local okW, w = pcall(function() return wbl:Create(OK.getWorld(), template:GetClass(), pc) end)
    if not (okW and valid(w)) then return markFail("widget: " .. tostring(w)) end
    local tree = OK.subObj(w, "WidgetTree")
    texMarkN = (texMarkN or 0) + 1
    local sb = tree and StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName("OK_TexMarkSize" .. texMarkN))
    local img = tree and StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("OK_TexMarkImg" .. texMarkN))
    if not (valid(sb) and valid(img)) then return markFail("parts") end
    pcall(function() sb:SetWidthOverride(size); sb:SetHeightOverride(size) end)
    pcall(function() sb:AddChild(img) end)
    pcall(function() img:SetBrushFromTexture(tex, false) end)
    pcall(function() img:SetBrushSize({ X = size, Y = size }) end)
    pcall(function() tree.RootWidget = sb end)
    pcall(function() sb:SetVisibility(4) end)
    pcall(function() w:SetVisibility(4) end)
    pcall(function() w:SetRenderOpacity(1.0) end)
    pcall(function() w:AddToPlayerScreen(400) end)
    if not state.texMarkLogged then state.texMarkLogged = true; log("Target marker %s: made", texName) end
    pcall(function() w:SetAnchorsInViewport({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } }) end)
    pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
    return w
end
state.texMarkerAt = function(id, pc, texName, loc, size)
    -- not in split screen for now: both crashes with the drone and Overload in 2 players
    -- happened with these on-screen markers (the word labels are used instead)
    if valid(state.p2) and not CFG.TEX_MARKERS_SPLIT then return false end
    local m = texMarkers[id]
    if not (m and valid(m.w)) then
        local w = buildTexMarker(pc, texName, size or 64)
        if not w then return false end
        m = { w = w }
        texMarkers[id] = m
    end
    local out = {}
    local okP, on = pcall(function() return pc:ProjectWorldLocationToScreen(loc, out, true) end)
    local x, y = nil, nil
    pcall(function() x, y = out.X, out.Y end)
    local show = okP and on and type(x) == "number"
    if show then pcall(function() m.w:SetPositionInViewport({ X = x, Y = y }, true) end) end
    pcall(function()
        if show then
            -- the borrowed widget class hides itself: keep it showing (as the reticle viewer does)
            if not m.w:IsVisible() then m.w:SetVisibility(4) end
            m.w:SetRenderOpacity(1.0)
        else m.w:SetVisibility(2) end
    end)
    return true
end
state.texMarkerHide = function(id)
    local m = texMarkers[id]
    if m and valid(m.w) then pcall(function() m.w:RemoveFromParent() end) end
    texMarkers[id] = nil
end

-- A line of text at the top of Player 1's screen for a few seconds (effect catalog names)
local toastW, toastText, toastUntil = nil, nil, 0
state.toast = function(msg, seconds)
    local pc = OK.player1Controller()
    if not valid(toastW) then
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local template = nil
        for _, hud in ipairs(OK.hudWidgetsOf(pc)) do
            local note = OK.subObj(hud, "BPW_HUD_TextNotification")
            if note then template = note break end
        end
        if not (valid(wbl) and template) then return end
        local okW, w = pcall(function() return wbl:Create(OK.getWorld(), template:GetClass(), pc) end)
        if not (okW and valid(w)) then return end
        local tree = OK.subObj(w, "WidgetTree")
        local tb = tree and StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, FName("OK_ToastText"))
        if not valid(tb) then return end
        pcall(function() local f = tb.Font; f.Size = 22; tb:SetFont(f) end)
        pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 0.85, B = 0.3, A = 1 }, ColorUseRule = 0 }) end)
        pcall(function() tb:SetShadowOffset({ X = 2, Y = 2 }) end)
        pcall(function() tree.RootWidget = tb end)
        pcall(function() w:AddToViewport(600) end)
        pcall(function() w:SetAnchorsInViewport({ Minimum = { X = 0.5, Y = 0.08 }, Maximum = { X = 0.5, Y = 0.08 } }) end)
        pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
        toastW, toastText = w, tb
    end
    pcall(function() toastText:SetText(FText(msg)) end)
    pcall(function() toastW:SetVisibility(4); toastW:SetRenderOpacity(1.0) end)
    toastUntil = os.clock() + (seconds or 3)
end
OK.addTickJob("toast", 0.1, function()
    if not valid(toastW) then return end
    if os.clock() > toastUntil then pcall(function() toastW:SetVisibility(2) end)
    else pcall(function() if not toastW:IsVisible() then toastW:SetVisibility(4) end; toastW:SetRenderOpacity(1.0) end) end
end)
