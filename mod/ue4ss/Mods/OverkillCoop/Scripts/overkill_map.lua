--[[
    Third Eye Decalcified Co-op - the map (Trainer > World > Map)
    An aerial picture of the map you're on (Mods/OverkillCoop/maps/<Map>.jpg), with pins for
    both players and everything worth finding, read live from the game: DNA probes, brains,
    challenges, saucer landing pads and ammo. Your own pins too.

    Lining it up: the pictures come without coordinates, so each map is lined up once by
    standing somewhere you recognise, putting the cursor on that spot and pressing Y; then
    the same somewhere far away. It's saved in maps/calibration.txt (and shipped with the
    mod once a map is done). Until then the pins are placed by a rough guess.

    Pad 1:  left stick / D-pad up-down: move the cursor     D-pad left/right: which pins
            Y: "I'm standing here" (lines the map up)        X: drop / remove your own pin
            A: teleport Player 1 to the cursor (once lined up)    B: close
]]

local OK = OverkillCoop
if not OK then return end
local state, CFG, log, valid = OK.state, OK.CFG, OK.log, OK.valid
local function mlog(fmt, ...) log("Map: " .. fmt, ...) end

local DIR = "ue4ss/Mods/OverkillCoop/maps/"
local IMG_W, IMG_H = 1920, 1080
-- map name (from the world's name) -> picture
local PICTURES = {
    { "TurnipseedFarm", "TurnipseedFarm.jpg" }, { "Rockwell", "Rockwell.jpg" },
    { "SantaModesta", "SantaModesta.jpg" }, { "UnionTown", "UnionTown.jpg" },
    { "Area42", "Area42.jpg" }, { "CapitolCity", "CapitolCity.jpg" }, { "Capitol", "CapitolCity.jpg" },
}
-- what gets a pin: { label, colour, class names (found with FindAllOf) }
local KINDS = {
    { key = "probe", label = "DNA probes", short = "PROBE", col = { R = 0.2, G = 1.0, B = 0.3, A = 1 }, classes = { "BP_Proxy_Collect_Probe_C" } },
    { key = "brain", label = "Brains", short = "BRAIN", col = { R = 1.0, G = 0.45, B = 0.75, A = 1 }, classes = { "BP_ItemDNABrain_C" } },
    { key = "challenge", label = "Challenges", short = "CHALLENGE", col = { R = 1.0, G = 0.8, B = 0.1, A = 1 }, classes = { "BP_Challenge_StartingPoint_C" } },
    { key = "pad", label = "Landing pads", short = "PAD", col = { R = 0.35, G = 0.85, B = 1.0, A = 1 }, classes = { "BP_UFOLandingSite_C" } },
    { key = "ammo", label = "Ammo", short = "AMMO", col = { R = 1.0, G = 0.55, B = 0.15, A = 1 },
      classes = { "BP_ItemDisintegratorRayAmmo_C", "BP_ItemIonDetonatorAmmo_C", "BP_ItemSaucerDeconstructorAmmo_C", "BP_ItemSaucerSonicBoomAmmo_C" } },
    { key = "mine", label = "My pins", short = "PIN", col = { R = 1, G = 1, B = 1, A = 1 } },
}
local FILTERS = { "Everything", "DNA probes", "Brains", "Challenges", "Landing pads", "Ammo", "My pins", "Players only" }

local function mapKey()
    local n = ""
    pcall(function() n = OK.nameOf(OK.getWorld()) end)
    n = n:match("([%w_]+)%.[%w_]+$") or n
    return (n:gsub("_Main$", ""))
end
local function pictureFor(key)
    for _, e in ipairs(PICTURES) do if key:lower():find(e[1]:lower(), 1, true) then return e[2] end end
    return key .. ".jpg"
end

------------------------------------------------------------------------------------------
-- lining up: picture = a * world + b, with complex numbers (X + iY -> px + i py). Two spots
-- give scale, turn and shift. Saved per map.
------------------------------------------------------------------------------------------
local calib = {}       -- map key -> { ar, ai, br, bi }
local points = {}      -- map key -> { {wx, wy, px, py}, ... } (this session)
local myPins = {}      -- map key -> { {wx, wy}, ... }
local function loadFiles()
    local f = io.open(DIR .. "calibration.txt", "r")
    if f then
        for line in f:lines() do
            local k, ar, ai, br, bi = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
            if k and tonumber(ar) then calib[k] = { tonumber(ar), tonumber(ai), tonumber(br), tonumber(bi) } end
        end
        f:close()
    end
    f = io.open(DIR .. "pins.txt", "r")
    if f then
        for line in f:lines() do
            local k, x, y = line:match("^(%S+)%s+(%S+)%s+(%S+)")
            if k and tonumber(x) then myPins[k] = myPins[k] or {}; table.insert(myPins[k], { tonumber(x), tonumber(y) }) end
        end
        f:close()
    end
end
local function saveFiles()
    local f = io.open(DIR .. "calibration.txt", "w")
    if f then
        f:write("# map  a(real) a(imag) b(real) b(imag): picture pixel = a * (X + iY) + b\n")
        for k, c in pairs(calib) do f:write(string.format("%s %.9g %.9g %.9g %.9g\n", k, c[1], c[2], c[3], c[4])) end
        f:close()
    end
    f = io.open(DIR .. "pins.txt", "w")
    if f then
        for k, list in pairs(myPins) do for _, p in ipairs(list) do f:write(string.format("%s %.1f %.1f\n", k, p[1], p[2])) end end
        f:close()
    end
end
loadFiles()

local function toPix(c, x, y)
    local ar, ai, br, bi = c[1], c[2], c[3], c[4]
    return ar * x - ai * y + br, ai * x + ar * y + bi
end
local function toWorld(c, px, py)
    local ar, ai, br, bi = c[1], c[2], c[3], c[4]
    local zr, zi = px - br, py - bi
    local d = ar * ar + ai * ai
    if d == 0 then return 0, 0 end
    return (zr * ar + zi * ai) / d, (zi * ar - zr * ai) / d
end
-- a rough guess until the map is lined up: everything found fits the middle of the picture,
-- world +X pointing up
local function guessCalib(pins)
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(pins) do
        minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
        minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
    end
    if minX == math.huge or maxX - minX < 1000 then return { 0, -0.01, IMG_W / 2, IMG_H / 2 } end
    -- from Area 42, lined up in game: the pictures have world X running right and Y down,
    -- at about 0.0174 pixels per cm (the same debug camera took them all). Centred on what
    -- was found, at that scale, unless that wouldn't fit.
    local s = CFG.MAP_GUESS_SCALE or 0.0174
    s = math.min(s, (IMG_W * 0.9) / (maxX - minX), (IMG_H * 0.9) / (maxY - minY))
    local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
    return { s, 0, IMG_W / 2 - s * cx, IMG_H / 2 - s * cy }
end
local function solve(key)
    local pts = points[key]
    if not pts or #pts < 2 then return false end
    -- the two spots furthest apart
    local best, bi, bj = 0, nil, nil
    for i = 1, #pts do for j = i + 1, #pts do
        local d = (pts[i][1] - pts[j][1]) ^ 2 + (pts[i][2] - pts[j][2]) ^ 2
        if d > best then best, bi, bj = d, i, j end
    end end
    if not bi or best < 3000 * 3000 then return false end
    local w1r, w1i, p1r, p1i = pts[bi][1], pts[bi][2], pts[bi][3], pts[bi][4]
    local w2r, w2i, p2r, p2i = pts[bj][1], pts[bj][2], pts[bj][3], pts[bj][4]
    -- a = (p2 - p1) / (w2 - w1)
    local nr, ni = p2r - p1r, p2i - p1i
    local dr, di = w2r - w1r, w2i - w1i
    local dd = dr * dr + di * di
    local ar, ai = (nr * dr + ni * di) / dd, (ni * dr - nr * di) / dd
    local br, bim = p1r - (ar * w1r - ai * w1i), p1i - (ai * w1r + ar * w1i)
    calib[key] = { ar, ai, br, bim }
    saveFiles()
    return true
end

------------------------------------------------------------------------------------------
-- finding things
------------------------------------------------------------------------------------------
local function locOf(a)
    local ok, l = pcall(function() return a:K2_GetActorLocation() end)
    if ok and l then return { x = l.X, y = l.Y, z = l.Z } end
    return nil
end
local function scan(key)
    local pins = {}
    for _, kind in ipairs(KINDS) do
        if kind.classes then
            for _, cn in ipairs(kind.classes) do
                pcall(function()
                    for _, a in ipairs(FindAllOf(cn) or {}) do
                        local hidden = false
                        pcall(function() hidden = a.bHidden == true end)
                        local l = valid(a) and not hidden and locOf(a)
                        if l then pins[#pins + 1] = { kind = kind, x = l.x, y = l.y, z = l.z } end
                    end
                end)
            end
        end
    end
    for _, p in ipairs(myPins[key] or {}) do pins[#pins + 1] = { kind = KINDS[#KINDS], x = p[1], y = p[2], mine = p } end
    return pins
end

------------------------------------------------------------------------------------------
-- the screen
------------------------------------------------------------------------------------------
local uid = 0
local function U(cn, tree, base) uid = uid + 1; return StaticConstructObject(StaticFindObject("/Script/UMG." .. cn), tree, FName(string.format("OKMap_%s_%d", base or cn, uid))) end
local function text(tree, str, size, col)
    local t = U("TextBlock", tree, "T")
    pcall(function() t:SetText(FText(str)) end)
    if not (state.applyGameFont and state.applyGameFont(t, size)) then pcall(function() local f = t.Font; f.Size = size; t:SetFont(f) end) end
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col or { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }) end)
    pcall(function() t:SetShadowOffset({ X = 1, Y = 1 }) end)
    pcall(function() t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.9 }) end)
    return t
end
local function box(tree, col)
    local b = U("Border", tree, "B")
    pcall(function() b:SetBrushColor(col) end)
    pcall(function() b:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    return b
end
local function place(canvas, w, x, y, sw, sh, center)
    local ok, sl = pcall(function() return canvas:AddChildToCanvas(w) end)
    if not (ok and sl) then return nil end
    pcall(function()
        if sw then sl:SetAutoSize(false); sl:SetSize({ X = sw, Y = sh }) else sl:SetAutoSize(true) end
        if center then sl:SetAlignment({ X = 0.5, Y = 0.5 }) end
        sl:SetPosition({ X = x, Y = y })
    end)
    return sl
end

local M = nil   -- the open map
local texCache = {}
local function close()
    if not M then return end
    pcall(function() M.widget:RemoveFromParent() end)
    local pc = OK.player1Controller()
    local pw = OK.getPawn(pc)
    if valid(pw) then pcall(function() pw:EnableInput(pc) end) end
    M = nil
    state.mapOpen = false
end
OK.onWorldChange(close)

local openInner
local function open()
    if M then return end
    local ok, err = pcall(openInner)
    if not ok then mlog("opening failed: %s", tostring(err)); M = nil end
end
openInner = function()
    local pc = OK.player1Controller()
    if not valid(pc) then mlog("can't open: no Player 1") return end
    local key = mapKey()
    local file = pictureFor(key)
    local tex = texCache[file]
    if not valid(tex) then
        local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
        pcall(function() tex = krl:ImportFileAsTexture2D(OK.getWorld(), DIR .. file) end)
        if valid(tex) then texCache[file] = tex end
    end
    -- a widget host: the same trick the wheel uses (one of the HUD's own simple widgets)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, w in ipairs(OK.hudWidgetsOf(pc)) do
        local note = OK.subObj(w, "BPW_HUD_TextNotification")
        if note then template = note break end
    end
    if not (valid(wbl) and template) then mlog("no widget host found (open the map once in a level)") return end
    local okC, w = pcall(function() return wbl:Create(OK.getWorld(), template:GetClass(), pc) end)
    if not (okC and valid(w)) then mlog("can't open: the widget wasn't made (%s)", tostring(w)) return end
    local tree = OK.subObj(w, "WidgetTree")
    if not tree then mlog("can't open: no widget tree") return end
    -- screen size in UMG units; the picture fits it, keeping its shape
    local vw, vh = 1920, 1080
    pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs = wll:GetViewportSize(OK.getWorld())
        local dpi = wll:GetViewportScale(OK.getWorld())
        dpi = (type(dpi) == "number" and dpi > 0) and dpi or 1
        vw, vh = vs.X / dpi, vs.Y / dpi
    end)
    local k = math.min(vw / IMG_W, vh / IMG_H)
    local ox, oy = (vw - IMG_W * k) / 2, (vh - IMG_H * k) / 2
    local canvas = U("CanvasPanel", tree, "Canvas")
    place(canvas, box(tree, { R = 0, G = 0, B = 0, A = 0.92 }), 0, 0, vw, vh)
    if valid(tex) then
        local img = U("Image", tree, "Pic")
        pcall(function() img:SetBrushFromTexture(tex, false) end)
        place(canvas, img, ox, oy, IMG_W * k, IMG_H * k)
    else
        place(canvas, text(tree, "No picture for this map yet (" .. DIR .. file .. ")", 20, { R = 1, G = 0.8, B = 0.2, A = 1 }), vw / 2, vh / 2, nil, nil, true)
    end
    local pins = scan(key)
    local c = calib[key]
    local lined = c ~= nil
    if not c then c = guessCalib(pins) end
    M = { widget = w, tree = tree, canvas = canvas, key = key, k = k, ox = ox, oy = oy, pins = pins, c = c, lined = lined,
          filter = 1, cx = IMG_W / 2, cy = IMG_H / 2, down = {}, pinSlots = {}, file = file }
    -- the pins
    local counts = {}
    for _, p in ipairs(pins) do
        local px, py = toPix(c, p.x, p.y)
        local dot = box(tree, p.kind.col)
        p.slot = place(canvas, dot, ox + px * k, oy + py * k, 10, 10, true)
        p.widget = dot
        counts[p.kind.key] = (counts[p.kind.key] or 0) + 1
    end
    -- the players (yellow P1, cyan P2)
    M.players = {}
    for slot, col in ipairs({ { R = 1, G = 0.85, B = 0.1, A = 1 }, { R = 0.3, G = 0.95, B = 1, A = 1 } }) do
        local t = text(tree, "P" .. slot, 16, col)
        local d = box(tree, col)
        M.players[slot] = { dot = place(canvas, d, -100, -100, 14, 14, true), label = place(canvas, t, -100, -100, nil, nil, true), dw = d, tw = t }
    end
    -- the cursor
    local cur = box(tree, { R = 1, G = 1, B = 1, A = 0.9 })
    M.curH = place(canvas, cur, 0, 0, 28, 2, true)
    local cur2 = box(tree, { R = 1, G = 1, B = 1, A = 0.9 })
    M.curV = place(canvas, cur2, 0, 0, 2, 28, true)
    -- title and help
    local title = text(tree, "", 20, { R = 1, G = 0.85, B = 0.2, A = 1 })
    place(canvas, title, 24, 16)
    M.title = title
    local parts = {}
    for _, kind in ipairs(KINDS) do parts[#parts + 1] = string.format("%s %d", kind.label, counts[kind.key] or 0) end
    local legend = text(tree, table.concat(parts, "     "), 14, { R = 0.85, G = 0.95, B = 1, A = 1 })
    place(canvas, legend, 24, vh - 62)
    local help = text(tree, "Stick: cursor     D-pad left / right: which pins     Y: I'm standing here (lines the map up)     X: my pin     A: teleport here     B: close", 13, { R = 0.36, G = 0.92, B = 1, A = 1 })
    place(canvas, help, 24, vh - 36)
    local info = text(tree, "", 14, { R = 1, G = 1, B = 1, A = 1 })
    M.info = place(canvas, info, 0, 0)
    M.infoW = info
    pcall(function() tree.RootWidget = canvas end)
    -- the borrowed widget class starts (and keeps setting itself) hidden: made visible here
    -- and every frame while the map is open (the wheel needs the same)
    pcall(function() w:SetVisibility(4) end)
    pcall(function() w:SetRenderOpacity(1.0) end)
    local okV, errV = pcall(function() w:AddToViewport(160) end)
    if not okV then mlog("can't show it: %s", tostring(errV)) end
    local pw = OK.getPawn(pc)
    if valid(pw) then pcall(function() pw:DisableInput(pc) end) end
    for _, kn in ipairs({ "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Top", "Gamepad_FaceButton_Left", "Gamepad_DPad_Left", "Gamepad_DPad_Right" }) do
        M.down[kn] = OK.kbDown(pc, kn)
    end
    state.mapOpen = true
    mlog("%s: picture %s %s, %d pins%s", key, file, valid(tex) and "loaded" or "not found", #pins, lined and "" or " (not lined up yet: rough guess)")
end
state.mapOpen = false
state.closeMap = function() close() end
state.openMap = function() OK.later(0.15, "mapOpen", function() if state.trainerCloseMenu then pcall(state.trainerCloseMenu) end; open() end) end

local function edge(pc, kn)
    local d = OK.kbDown(pc, kn)
    local was = M.down[kn]
    M.down[kn] = d
    return d and not was
end
local function axis(pc, kn)
    local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(kn) }) end)
    return (ok and type(v) == "number") and v or 0
end
local function shown(p)
    local f = FILTERS[M.filter]
    if f == "Everything" then return true end
    if f == "Players only" then return false end
    return p.kind.label == f
end
local function refreshPins()
    for _, p in ipairs(M.pins) do
        if p.widget then pcall(function() p.widget:SetVisibility(shown(p) and 4 or 1) end) end
    end
end
local function teleport(pc, wx, wy)
    local pw = OK.getPawn(pc)
    local l = valid(pw) and locOf(pw)
    if not l then return end
    -- high above the spot: Crypto falls (or jetpacks) down onto it
    pcall(function() pw:K2_SetActorLocation({ X = wx, Y = wy, Z = l.z + 2500 }, false, {}, true) end)
    mlog("teleported Player 1 to %.0f, %.0f", wx, wy)
end

local lastT = os.clock()
OK.addTickJob("mapView", 0.0, function()
    if not M then lastT = os.clock() return end
    local now = os.clock()
    local dt = math.min(0.1, now - lastT)
    lastT = now
    local pc = OK.player1Controller()
    if not valid(pc) or not valid(M.widget) then close() return end
    pcall(function()
        local w = M.widget
        if not w:IsVisible() then w:SetVisibility(4) end
        w:SetRenderOpacity(1.0)
        if M.canvas then M.canvas:SetVisibility(4); M.canvas:SetRenderOpacity(1.0) end
    end)
    -- cursor
    local ax, ay = axis(pc, "Gamepad_LeftX"), axis(pc, "Gamepad_LeftY")
    if math.abs(ax) < 0.15 then ax = 0 end
    if math.abs(ay) < 0.15 then ay = 0 end
    if OK.kbDown(pc, "Gamepad_DPad_Up") then ay = 1 end
    if OK.kbDown(pc, "Gamepad_DPad_Down") then ay = -1 end
    local speed = 700 * dt
    M.cx = math.max(0, math.min(IMG_W, M.cx + ax * speed))
    M.cy = math.max(0, math.min(IMG_H, M.cy - ay * speed))
    local sx, sy = M.ox + M.cx * M.k, M.oy + M.cy * M.k
    pcall(function() M.curH:SetPosition({ X = sx, Y = sy }) end)
    pcall(function() M.curV:SetPosition({ X = sx, Y = sy }) end)
    -- players
    for slot, pl in ipairs(M.players) do
        local cc = (slot == 1) and pc or state.p2
        local pw = valid(cc) and OK.getPawn(cc)
        local l = valid(pw) and locOf(pw)
        if l then
            local px, py = toPix(M.c, l.x, l.y)
            pcall(function() pl.dot:SetPosition({ X = M.ox + px * M.k, Y = M.oy + py * M.k }) end)
            pcall(function() pl.label:SetPosition({ X = M.ox + px * M.k, Y = M.oy + py * M.k - 20 }) end)
            pcall(function() pl.dw:SetVisibility(4); pl.tw:SetVisibility(4) end)
        else
            pcall(function() pl.dw:SetVisibility(1); pl.tw:SetVisibility(1) end)
        end
    end
    -- what's under the cursor
    local near, nd = nil, (14 / M.k) ^ 2
    for _, p in ipairs(M.pins) do
        if shown(p) then
            local px, py = toPix(M.c, p.x, p.y)
            local d = (px - M.cx) ^ 2 + (py - M.cy) ^ 2
            if d < nd then near, nd = p, d end
        end
    end
    local wx, wy = toWorld(M.c, M.cx, M.cy)
    pcall(function() M.infoW:SetText(FText(near and near.kind.short or "")) end)
    pcall(function() M.info:SetPosition({ X = sx + 14, Y = sy + 10 }) end)
    pcall(function() M.title:SetText(FText(string.format("%s     pins: %s%s", M.key, FILTERS[M.filter],
        M.lined and "" or "     (not lined up yet: press Y where you're standing, then again far away)"))) end)
    -- buttons
    if edge(pc, "Gamepad_DPad_Right") then M.filter = M.filter % #FILTERS + 1; refreshPins() end
    if edge(pc, "Gamepad_DPad_Left") then M.filter = (M.filter - 2) % #FILTERS + 1; refreshPins() end
    if edge(pc, "Gamepad_FaceButton_Top") then
        local pw = OK.getPawn(pc)
        local l = valid(pw) and locOf(pw)
        if l then
            points[M.key] = points[M.key] or {}
            table.insert(points[M.key], { l.x, l.y, M.cx, M.cy })
            if solve(M.key) then
                mlog("%s lined up (%d spots)", M.key, #points[M.key])
                close(); open()          -- redraw everything in the right place
                return
            else
                mlog("%s: spot %d noted at %.0f, %.0f -> picture %.0f, %.0f; now one far from here (30 m or more)", M.key, #points[M.key], l.x, l.y, M.cx, M.cy)
            end
        end
    end
    if edge(pc, "Gamepad_FaceButton_Left") then
        if near and near.mine then
            for i, p in ipairs(myPins[M.key] or {}) do if p == near.mine then table.remove(myPins[M.key], i) break end end
        else
            myPins[M.key] = myPins[M.key] or {}
            table.insert(myPins[M.key], { wx, wy })
        end
        saveFiles()
        close(); open()
        return
    end
    if edge(pc, "Gamepad_FaceButton_Bottom") then
        if M.lined then close(); teleport(pc, wx, wy) return end
        mlog("line the map up first (Y where you're standing, twice) before teleporting")
    end
    if edge(pc, "Gamepad_FaceButton_Right") then close() end
end)

-- the trainer row (World page)
state.trainerExtras = state.trainerExtras or {}
table.insert(state.trainerExtras, { key = "x_map", page = 4, label = "Map: aerial view with pins (probes, brains, challenges, pads, ammo, players)",
    options = { "(closed)", "Open the map" },
    get = function() return "(closed)" end,
    -- only from the open trainer (a saved "open" must never pop the map up on its own)
    set = function(v)
        mlog("trainer row: %s (trainer open: %s)", tostring(v), tostring(state.trainerOpen))
        if v == "Open the map" and (state.trainerOpen or os.clock() - (state.mapWorldAt or 0) > 15) then state.openMap() end
    end })
OK.onWorldChange(function() state.mapWorldAt = os.clock() end)

-- Hold Select on pad 1 for 7 seconds (nothing else pressed) to open the map; Select again closes
local HOLD_KEYS = { "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
    "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
    "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick", "Gamepad_Special_Right" }
local selAt, selFired = nil, false
OK.addTickJob("mapSelectHold", 0.1, function()
    local pc = OK.player1Controller()
    if not valid(pc) or state.trainerOpen then selAt = nil return end
    local sel = OK.kbDown(pc, "Gamepad_Special_Left")
    if not sel then selAt, selFired = nil, false return end
    for _, k in ipairs(HOLD_KEYS) do if OK.kbDown(pc, k) then selAt = nil; selFired = true return end end
    if selFired then return end
    selAt = selAt or os.clock()
    if os.clock() - selAt >= (CFG.MAP_SELECT_HOLD or 7) then
        selFired = true
        if state.mapOpen then mlog("Select held: closing") ; state.closeMap() else mlog("Select held: opening"); open() end
    end
end)
mlog("ready (Trainer > World > Map)")
