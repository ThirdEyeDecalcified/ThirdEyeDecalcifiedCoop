--[[
    Third Eye Decalcified Co-op - the mind & weapons wheel (loaded by main.lua)

    Hold LB (each player on their own controller):
      * that player's half of the screen gets a see-through overlay; the game keeps running
        at full speed (the game's own wheel is still opened underneath, hidden, so the face
        buttons don't make Crypto jump or dash while choosing)
      * A / B / X / Y pick a weapon by its direction (Y up = Disintegrator, B right = Ion
        Detonator, A down = Zap-O-Matic, X left = Anal Probe); it's switched to on letting go
      * the D-pad moves through the 4x4 grid of mind powers; slot 1 (Lock-on) is the game's
        normal LT. The rest are shown as "coming soon" until they're built.
    A small panel above the weapon icon shows the chosen power and the concentration meter;
    "LT" appears on it when a power other than Lock-on is chosen.
]]

local OK = OverkillCoop
if not OK then
    print("[OverkillCoop wheel] the split-screen part didn't load; the wheel is off\n")
    return
end
local state, CFG, log, valid = OK.state, OK.CFG, OK.log, OK.valid
local subObj, getPawn, kbDown = OK.subObj, OK.getPawn, OK.kbDown

local function wlog(fmt, ...) log("Wheel: " .. fmt, ...) end
-- beta power tuning (defaults if the main file doesn't set them)
local function default(k, v) if CFG[k] == nil then CFG[k] = v end end
default("BLACK_HOLE_RANGE", 1600)     -- how far Black Hole PK reaches (cm)
default("BLACK_HOLE_PULL", 2200)      -- pull speed
default("FREE_LOVE_PER_LEVEL", 3)     -- dancers needed per wanted level to clear it
default("FROZEN_OUTLINE", 2)          -- outline colour index on frozen people
default("BLACK_HOLE_SECONDS", 3.5)   -- how long Black Hole PK pulls before it blows
default("PYRO_SECONDS", 7)            -- how long a person burns
default("PYRO_DPS", 14)               -- fire damage per second
default("PYRO_SPREAD", 170)           -- how close someone has to be to catch fire (touching)
default("PYRO_MAX", 6)                -- most people on fire at once
default("BALL_SIZE", 2.2)             -- bowling ball size (1 = 1 metre)
default("BALL_SPEED", 1500)           -- how fast it rolls (cm/s)
default("BALL_SECONDS", 3.0)          -- how long it rolls
default("BALL_DAMAGE", 45)            -- damage to each person it hits
default("PYRO_KILLS", true)
default("HYSTERIA_MAX", 8)            -- most people berserk at once
default("SNATCH_DOT_SECONDS", 4)      -- Body Snatch: one dot every this many seconds
default("OVERLOAD_SECONDS", 90)       -- Overload Mutation: how long the green glow lasts (they blow up if they die in that time)
default("OVERLOAD_RADIUS", 700)        -- Overload Mutation: blast radius (cm) when they die
default("OVERLOAD_GLOW", 6000)         -- Overload Mutation: brightness of the green glow
default("CLOAK_SECONDS", 10)          -- Cloak: seconds invisible
default("CLOAK_MATERIAL", "/Game/VFX/Materials/Meshes/M_Hologram_01.M_Hologram_01") -- Cloak look (the game's hologram); "" = only you see yourself
default("CLOAK_OPACITY", 0.6)          -- Cloak: how see-through (0 = gone, 0.48 = the game's hologram)
default("CLOAK_LINES", 0.8)            -- Cloak: brightness of the moving scan lines
default("CLOAK_GLOW", 6.0)             -- Cloak: glow (the game's hologram uses 100)
default("CLOAK_TINT", { R = 0.2, G = 0.85, B = 1.0, A = 1 })
default("CLOAK_FULL_SECONDS", 30)      -- Cloak: a full concentration bar lasts this long (tap LT again to stop)
default("DEFLECT_SLICE", 0.35)         -- Deflector: share of the shooter's health a bounced shot takes
default("DEFLECT_DAMAGE", 30)         -- Deflector: damage a bounced-back shot does to whoever fired it
default("TETHER_RANGE", 6000)         -- Psychic Tether (grapple): how far it reaches (cm)
default("TETHER_SPEED", 4500)         -- Psychic Tether (grapple): top swing speed
default("TETHER_REEL", 1100)          -- Psychic Tether: how fast the rope shortens (cm/s)
default("TETHER_SECONDS", 8)          -- Psychic Tether: longest swing before it lets go
default("SENTRY_SCALE", 0.8)           -- Sentry Probe: size of the Orthopox drone model
default("SENTRY_YAW", 0)              -- Sentry Probe: turn the model if it faces sideways (90, 180, -90)
default("SENTRY_SECONDS", 25)         -- Sentry Probe: seconds it stays
default("SENTRY_RANGE", 1500)
default("SENTRY_DAMAGE", 15)
default("SENTRY_ZAP_SLICE", 0.12)     -- Sentry Probe: share of a person's health each zap takes (every 0.5 s)
default("MARK_TEXT_SIZE", 26)         -- size of the word over affected people
default("POWER_ARCS", false)          -- lightning from Crypto to whoever a power hits
default("MARK_HEIGHT", 120)           -- how far above their middle it floats (cm)
default("MARK_RANGE", 4000)           -- shown within this distance
default("MARK_MAX", 10)               -- most icons at once per screen
default("WHEEL_PROTECT", true)         -- invincible and unseen while the LB menu is open
default("FREE_LOVE_SPLIT", true)      -- Free Love with Player 2 in too (its party / hearts extras stay single player)
default("FREE_RANGE", 2600)           -- how far Free Love / Free Fear reach (cm)
default("FEAR_SECONDS", 10)           -- how long Free Fear lasts
default("WAVE_ORBS", 9)               -- orbs in the cone wave
default("WAVE_SECONDS", 0.6)
default("HYSTERIA_HIDES_PLAYERS", true) -- berserk people don't see the players (so they fight each other)
default("SCAN_REFILL_DOTS", 3)        -- reading a mind gives back this many of the 6 dots (2005 style)
default("SCAN_SECONDS", 0.5)          -- how long Y has to stay on a person to count as a read
default("SCAN_SAME_PERSON", 30)       -- seconds before the same person can be read again
default("SCAN_REPORT", true)          -- (testing) write down what the game's scan ability does

------------------------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------------------------
-- Weapon directions: face button, label, words that appear in the weapon's class name
local WEAPONS = {
    { key = "Gamepad_FaceButton_Top",    btn = "Y", label = "Disintegrator Ray", match = { "Disinteg" },
      icon = { { "icon_weapon", "desinteg" }, { "icon_weapon", "disinteg" }, { "icon", "disinteg" } } },
    { key = "Gamepad_FaceButton_Right",  btn = "B", label = "Ion Detonator",     match = { "Ion" },
      icon = { { "icon", "ion" , "deto" }, { "weapon", "ion" }, { "iondeto" }, { "ion_deto" } } },
    { key = "Gamepad_FaceButton_Bottom", btn = "A", label = "Zap-O-Matic",       match = { "Zap" },
      icon = { { "icon", "zap" }, { "weapon", "zap" }, { "zap" } } },
    { key = "Gamepad_FaceButton_Left",   btn = "X", label = "Anal Probe",        match = { "Probe" },
      icon = { { "icon", "probe" }, { "weapon", "probe" }, { "analprobe" }, { "anal" } } },
}

-- The game's own mind abilities, shown down the sides like the vanilla wheel (icon and
-- its controller button)
local SIDE_ABILITIES = {
    { icon = "icon_holobob01", btn = "durango_dpad_up_png", left = true },
    { icon = "icon_psy_follow01", btn = "durango_dpad_down_png", left = true },
    { icon = "icon_psy_distract01", btn = "durango_dpad_left_png", left = true },
    { icon = "icon_psy_forget01", btn = "durango_dpad_right_png", left = true },
    { icon = "icon_psy_pk01", btn = "durango_rb_png" },
    { icon = "icon_psy_scan01", btn = "durango_y_png" },
    { icon = "icon_psy_extract01", btn = "durango_x_png" },
}

-- The mind powers (4 x 4 grid). ready = usable now; the rest say "coming soon".
local POWERS = {
    { name = "Lock-on",            cost = "free",      ready = true,  desc = "The game's normal LT lock-on." },
    { name = "Free Love",          cost = "free",         ready = true, beta = true, cast = "freelove",
      desc = "Hold LT: a love beam like the second game's. Keep people in it and they fall for you, then dance. Enough dancers clear the wanted level." },
    { name = "Free Fear",          cost = "free",         ready = true, beta = true, cast = "freefear",
      desc = "LT: instant terror. Everyone in front of you drops the fight and runs. With a dot spare, a Mind Flash too: people near you are knocked back and stunned, and drivers jump out of their cars." },
    { name = "Riot Hysteria",     cost = "2",         ready = true, beta = true, cast = "hysteria",
      desc = "LT: drive someone berserk. They lash out at whoever is nearest, and anyone they hurt catches it too." },
    { name = "Body Snatch",        cost = "1",         ready = true, beta = true, cast = "bodysnatch",
      desc = "LT on someone: take their body and look. Full heal, faster run. Your disguise wears down over time, faster when you're wanted or hit. LT again to jump out." },
    { name = "Cryokinesis",        cost = "1 per second", ready = true, beta = true, cast = "cryo",
      desc = "Hold LT: a freezing cone slows people, then freezes them solid. Shoot a frozen one to shatter it." },
    { name = "Pyrokinesis",        cost = "2",         ready = true, beta = true, cast = "pyro",
      desc = "LT: set the person in front of you ablaze. They run screaming, and anyone they touch catches fire too." },
    { name = "Mutant Shockwave",   cost = "2-3",       ready = true, beta = true, cast = "shockwave",
      desc = "Hold LT to charge (3 stages), let go: a ground wave rolls out and launches everyone skyward. (To become the psi mutants' own shockwave.)" },
    { name = "Psi-Barrage",        cost = "2",         ready = true, beta = true, cast = "psibarrage",
      desc = "LT: the psi mutants' own psychic grenades, thrown at up to 3 enemies in front of you. (Meet a psi mutant once first.)" },
    { name = "Super Baller Disc",  cost = "2",         ready = true, beta = true, cast = "baller",
      desc = "LT: a purple disc like the second game's Dislocator. It skims to your target, latches on and drags them, bowling over anyone in the way, then bounces to the next one." },
    { name = "Black Hole PK",      cost = "3",         ready = true, beta = true, cast = "blackhole",
      desc = "LT while holding something with PK: it becomes a black hole. Everything nearby slams into it, then it blows." },
    { name = "Cloak & Deflector",  cost = "drain",     ready = true, beta = true, cast = "cloak",
      desc = "Tap LT: cloak on (uses the bar up as it goes), tap again: off. Hold LT: Crypto's shield as a dome." },
    { name = "Overload Mutation",  cost = "3",         ready = true, beta = true, cast = "overload",
      desc = "LT: someone glows radioactive green like the mutant cows, and blows up like one when they die." },
    { name = "Furon Sentry Probe", cost = "drain",         ready = true, beta = true, cast = "sentry",
      desc = "LT: a drone hovers over your shoulder and shoots enemies near you, like the second game's Gastro. Tap LT at someone: it flies over and goes after them. Hold LT: rapid fire (1 dot). Tap LT at nobody: send it home." },
}

-- Colours in the game's HUD palette
local COL = {
    cyan    = { R = 0.36, G = 0.92, B = 1.0, A = 1 },
    cyanDim = { R = 0.25, G = 0.55, B = 0.62, A = 1 },
    yellow  = { R = 1.0, G = 0.82, B = 0.22, A = 1 },
    white   = { R = 0.92, G = 0.96, B = 1.0, A = 1 },
    grey    = { R = 0.55, G = 0.62, B = 0.66, A = 1 },
    bg      = { R = 0.0, G = 0.05, B = 0.07, A = 0.45 },
    card    = { R = 0.02, G = 0.12, B = 0.15, A = 0.82 },
    cardOn  = { R = 0.06, G = 0.3, B = 0.36, A = 0.92 },
    cardSel = { R = 0.42, G = 0.32, B = 0.04, A = 0.95 },
    cell    = { R = 0.0, G = 0.1, B = 0.12, A = 0.4 },
    cellOn  = { R = 0.08, G = 0.42, B = 0.5, A = 0.6 },
}

------------------------------------------------------------------------------------------
-- Little UMG helpers
------------------------------------------------------------------------------------------
local function U(cn, tree, name) return StaticConstructObject(StaticFindObject("/Script/UMG." .. cn), tree, FName(name)) end
local uid = 0
local function nm(base) uid = uid + 1; return string.format("OKW_%s_%d", base, uid) end

local function textBlock(tree, str, size, col)
    local t = U("TextBlock", tree, nm("T"))
    pcall(function() t:SetText(FText(str)) end)
    if not (state.applyGameFont and state.applyGameFont(t, size)) then
        pcall(function() local f = t.Font; f.Size = size; t:SetFont(f) end)
    end
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col or COL.white, ColorUseRule = 0 }) end)
    pcall(function() t:SetJustification(1) end)   -- centred
    return t
end
local function setText(t, str) pcall(function() t:SetText(FText(str)) end) end
local function setColor(t, col) pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col, ColorUseRule = 0 }) end) end
local function border(tree, col, pad)
    local b = U("Border", tree, nm("B"))
    pcall(function() b:SetBrushColor(col) end)
    pad = pad or 8
    pcall(function() b:SetPadding({ Left = pad, Top = pad, Right = pad, Bottom = pad }) end)
    return b
end
local function sized(tree, child, w, h)
    local sb = U("SizeBox", tree, nm("S"))
    if w then pcall(function() sb:SetWidthOverride(w) end) end
    if h then pcall(function() sb:SetHeightOverride(h) end) end
    pcall(function() sb:SetContent(child) end)
    return sb
end

-- Add to a UniformGridPanel at a row / column (this engine version sets them on the slot)
local gridLogged = false
local function gridAdd(grid, child, r, c)
    local ok, slot = pcall(function() return grid:AddChildToUniformGrid(child) end)
    if not (ok and slot) then ok, slot = pcall(function() return grid:AddChild(child) end) end
    if ok and slot then
        pcall(function() slot:SetRow(r) end)
        pcall(function() slot:SetColumn(c) end)
        pcall(function() slot:SetHorizontalAlignment(2) end)
        pcall(function() slot:SetVerticalAlignment(2) end)
    elseif not gridLogged then
        gridLogged = true
        wlog("couldn't add to a grid: %s", tostring(slot))
    end
end

-- A widget to build in: one of the game's own small HUD widget classes, emptied out
local function newHost(pc)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, w in ipairs(OK.hudWidgetsOf(OK.player1Controller())) do
        local note = subObj(w, "BPW_HUD_TextNotification")
        if note then template = note break end
    end
    if not (valid(wbl) and template) then return nil end
    local okC, w = pcall(function() return wbl:Create(OK.getWorld(), template:GetClass(), pc) end)
    if not (okC and valid(w)) then return nil end
    local tree = subObj(w, "WidgetTree")
    if not tree then return nil end
    return w, tree
end

------------------------------------------------------------------------------------------
-- The game's own UI images (PaperSprites), found by name while the game runs
------------------------------------------------------------------------------------------
local sprites = nil   -- { {obj, name(lower), full} }
local function spriteList()
    if sprites then return sprites end
    sprites = {}
    local lines = {}
    pcall(function()
        for _, sp in ipairs(FindAllOf("PaperSprite") or {}) do
            if valid(sp) then
                local full = OK.nameOf(sp)
                local short = full:match("%.([^%.]+)$") or full
                sprites[#sprites + 1] = { obj = sp, name = short:lower(), full = full }
                if full:find("/Game/UI/", 1, true) then lines[#lines + 1] = full end
            end
        end
    end)
    table.sort(lines)
    if CFG.WHEEL_REPORT then
        local f = io.open("dump_ui_sprites.txt", "w")
        if f then f:write(table.concat(lines, "\n")); f:close() end
    end
    wlog("found %d game UI images (%d under /Game/UI)", #sprites, #lines)
    return sprites
end
-- first sprite whose name has every word of one of the patterns (patterns tried in order)
local spriteCache = {}
local function findSprite(key, patterns)
    if spriteCache[key] ~= nil then return spriteCache[key] or nil end
    local found = false
    for _, pat in ipairs(patterns) do
        for _, e in ipairs(spriteList()) do
            local ok = true
            for _, word in ipairs(pat) do if not e.name:find(word, 1, true) then ok = false break end end
            if ok and valid(e.obj) then found = e.obj break end
        end
        if found then break end
    end
    spriteCache[key] = found
    wlog("image for %s: %s", key, found and OK.shortName(found) or "none found")
    return found or nil
end
local function setSprite(img, sprite)
    if not (img and sprite) then return false end
    local ok = pcall(function() img:SetBrushFromAtlasInterface(sprite, false) end)
    if not ok then ok = pcall(function() img:SetBrushResourceObject(sprite) end) end
    return ok
end
OK.onWorldChange(function() sprites = nil; spriteCache = {} end)

------------------------------------------------------------------------------------------
-- Per player
------------------------------------------------------------------------------------------
local P = { {}, {}, {}, {} }   -- [1] Player 1, [2] Player 2, [3] / [4] Players 3 and 4
OK.onWorldChange(function()
    for _, p in ipairs(P) do
        p.overlay, p.panel, p.cards, p.cells = nil, nil, nil, nil
        p.open, p.pending, p.inputOff = false, nil, nil
    end
end)

-- Power icons: PNG files in the mod's Icons folder, loaded with the engine's own image import
local ICON_FILE = {
    ["Lock-on"] = "lockon", ["Psychic Ragdoll"] = "ragdoll", ["Free Love"] = "freelove", ["Free Fear"] = "freefear",
    ["Cryokinesis"] = "cryo", ["Zero-G Cone"] = "zerog", ["Mutant Shockwave"] = "shockwave", ["Pyrokinesis"] = "pyro",
    ["Riot Hysteria"] = "hysteria", ["Body Snatch"] = "bodysnatch", ["Overload Mutation"] = "overload",
    ["Cloak & Deflector"] = "cloak", ["Psychic Tether"] = "tether", ["Kinetic Overload"] = "kinetic",
    ["Black Hole PK"] = "blackhole", ["Furon Sentry Probe"] = "sentry",
    ["Psi-Barrage"] = "psibarrage", ["Super Baller Disc"] = "baller",
}
local iconDir = nil
local function findIconDir()
    if iconDir then return iconDir end
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("/", "\\")
    local base = src:match("^(.*\\)Scripts\\[^\\]+$")
    -- try the script's own folder first, then the usual places (relative to the game's folder)
    local tries = {}
    if base then tries[#tries + 1] = base; tries[#tries + 1] = "ue4ss\\" .. base end
    tries[#tries + 1] = "ue4ss\\Mods\\OverkillCoop\\"
    tries[#tries + 1] = "Mods\\OverkillCoop\\"
    for _, t in ipairs(tries) do
        local f = io.open(t .. "Icons\\power_lockon.png", "rb")
        if f then
            f:close()
            iconDir = t .. "Icons\\"
            wlog("power icons found in %s", iconDir)
            return iconDir
        end
    end
    iconDir = tries[1] .. "Icons\\"
    wlog("power icons folder not found (looked from %s)", src)
    return iconDir
end
local iconTex = {}
local function powerTexture(name)
    local key = ICON_FILE[name]
    if not key then return nil end
    local t = iconTex[key]
    if t and valid(t) then return t end
    local path = findIconDir() .. "power_" .. key .. ".png"
    local ok, tex = pcall(function()
        local lib = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
        return lib:ImportFileAsTexture2D(OK.getWorld(), path)
    end)
    if ok and valid(tex) then
        iconTex[key] = tex
        return tex
    end
    if not state.iconFailLogged then
        state.iconFailLogged = true
        wlog("couldn't load power icon %s (%s)", path, tostring(tex))
    end
    iconTex[key] = false
    return nil
end
OK.onWorldChange(function() for k, v in pairs(iconTex) do if v == false then iconTex[k] = nil end end end)
local function setPowerIcon(img, name)
    local tex = powerTexture(name)
    if not tex then return false end
    local ok = pcall(function() img:SetBrushFromTexture(tex, false) end)
    if not ok then ok = pcall(function() img:SetBrushResourceObject(tex) end) end
    return ok
end

local function controllers()
    local list = { OK.player1Controller() }
    if valid(state.p2) then
        list[2] = state.p2
        -- Players 3 and 4 (only ever in the game after Player 2)
        for slot = 3, 4 do
            local xp = state.extraPlayers and state.extraPlayers[slot]
            if valid(xp) and #list == slot - 1 then list[slot] = xp end
        end
    end
    return list
end
-- each player's part of the screen (UMG units): 1-2 players halves, 3 players (P1 on top),
-- 4 players quarters
local function areaOf(i, size)
    local n = #controllers()
    local w, h = size.X, size.Y
    if n == 2 then
        if state.splitVertical ~= false then w = w / 2 else h = h / 2 end
    elseif n == 3 then
        h = h / 2
        if i ~= 1 then w = w / 2 end
    elseif n >= 4 then
        w, h = w / 2, h / 2
    end
    return w, h
end
state.wheelAreaOf = areaOf

local function onFoot(pawn)
    return valid(pawn) and OK.nameOf(pawn):find("CharacterPlayer") ~= nil
end

local function weaponsOf(pawn)
    local eq = subObj(pawn, "m_pEquipmentManagerComponent")
    if not eq then return {}, nil, nil end
    local list = {}
    pcall(function() list = OK.arrayToList(eq.m_aWeaponList) end)
    local cur = nil
    pcall(function() cur = eq:GetCurrentWeapon() end)
    if not valid(cur) then pcall(function() cur = OK.arrayToList(eq:GetCurrentWeapons())[1] end) end
    return list, cur, eq
end

local function findWeapon(list, entry)
    for _, w in ipairs(list) do
        if valid(w) then
            local n = OK.nameOf(w)
            for _, m in ipairs(entry.match) do
                if n:find(m, 1, true) and not n:find("/UFO/", 1, true) then return w end
            end
        end
    end
    return nil
end

local function ammoText(w)
    local a, m = nil, nil
    pcall(function() a = w:GetAmmo() end)
    pcall(function() m = w:GetMaxAmmo() end)
    if type(a) == "number" and type(m) == "number" and m > 0 then return string.format("%d / %d", a, m) end
    return ""
end

-- The game's own wheel keeps a hint widget per mind ability (icon + controller button). Read
-- them: left wing = the first 4 (Holobob and the hypnosis commands), right = the rest.
state.abilityHints = function()
    if state.hintCache then return state.hintCache end
    local by = {}
    local order = {}
    local function inst(path)
        return path:match("(BPW_WeaponSelectorAbilityHint_C_%d+)%.")
    end
    pcall(function()
        for _, img in ipairs(FindAllOf("Image") or {}) do
            local okP, path = pcall(function() return img:GetFullName() end)
            local id = okP and path and path:find("/Engine/Transient", 1, true) and inst(path)
            if id then
                if not by[id] then by[id] = {}; order[#order + 1] = id end
                local okB, res = pcall(function() return img.Brush.ResourceObject end)
                local rn = (okB and valid(res)) and OK.nameOf(res) or ""
                if path:find("IMG_Ability", 1, true) and valid(res) then by[id].icon = res
                elseif rn:find("Durango", 1, true) or rn:find("Buttons", 1, true) then by[id].prompt = res end
            end
        end
        for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
            for _, t in ipairs(FindAllOf(cls) or {}) do
                local okP, path = pcall(function() return t:GetFullName() end)
                local id = okP and path and path:find("/Engine/Transient", 1, true) and inst(path)
                if id and by[id] then
                    local okT, txt = pcall(function() return t:GetText():ToString() end)
                    if okT and txt and #txt > 0 and #txt < 40 then by[id].promptText = by[id].promptText or txt end
                end
            end
        end
    end)
    table.sort(order, function(a, b) return tonumber(a:match("_(%d+)$")) < tonumber(b:match("_(%d+)$")) end)
    -- the vanilla controller buttons for each ability (the game keeps these in its input
    -- setup files, out of reach): D-pad for Holobob and the hypnosis commands, RB / X / Y
    local BUTTONS = {
        { "holobob", "durango_dpad_up_png" }, { "psy_distract", "durango_dpad_left_png" },
        { "psy_forget", "durango_dpad_right_png" }, { "psy_follow", "durango_dpad_down_png" },
        { "psy_pk", "durango_rb_png" }, { "psy_extract", "durango_x_png" }, { "psy_scan", "durango_y_png" },
    }
    local res = { left = {}, right = {} }
    for k, id in ipairs(order) do
        local h = by[id]
        if h.icon and not h.prompt then
            local iname = OK.nameOf(h.icon):lower()
            for _, b in ipairs(BUTTONS) do
                if iname:find(b[1], 1, true) then h.prompt = findSprite("button " .. b[2], { { b[2] } }) end
            end
        end
        if h.icon then
            local side = (k <= 4) and res.left or res.right
            side[#side + 1] = h
            wlog("ability hint %s: %s, button %s %s", id, OK.shortName(h.icon), h.prompt and OK.shortName(h.prompt) or "-", h.promptText or "")
        end
    end
    if #res.left + #res.right > 0 then state.hintCache = res end
    return res
end
OK.onWorldChange(function() state.hintCache = nil end)

------------------------------------------------------------------------------------------
-- The overlay (one per player, on that player's half of the screen)
------------------------------------------------------------------------------------------
local function buildOverlay(i, pc)
    local w, tree = newHost(pc)
    if not w then return nil end
    local root = U("Overlay", tree, nm("Root"))
    local bg = border(tree, COL.bg, 0)
    pcall(function()
        local s = root:AddChildToOverlay(bg)
        s:SetHorizontalAlignment(0); s:SetVerticalAlignment(0)   -- fill
    end)
    local col = U("VerticalBox", tree, nm("Col"))
    pcall(function()
        local s = root:AddChildToOverlay(col)
        s:SetHorizontalAlignment(2); s:SetVerticalAlignment(2)   -- centre
    end)
    local function addV(parent, child, pad)
        local ok, s = pcall(function() return parent:AddChildToVerticalBox(child) end)
        if ok and s then
            pcall(function() s:SetHorizontalAlignment(2) end)
            if pad then pcall(function() s:SetPadding({ Left = 0, Top = pad, Right = 0, Bottom = pad }) end) end
        end
    end
    addV(col, textBlock(tree, "MIND  &  WEAPONS", 26, COL.cyan), 6)
    local stripSlot = U("VerticalBox", tree, nm("StripSlot"))
    addV(col, stripSlot, 4)

    local row = U("HorizontalBox", tree, nm("Row"))
    addV(col, row, 8)

    -- weapons: a plus shape (Y up, X left, B right, A down)
    local cross = U("UniformGridPanel", tree, nm("Cross"))
    pcall(function() cross:SetSlotPadding({ Left = 4, Top = 4, Right = 4, Bottom = 4 }) end)
    local cards = {}
    local spots = { Y = { 0, 1 }, X = { 1, 0 }, B = { 1, 2 }, A = { 2, 1 } }
    for wi, e in ipairs(WEAPONS) do
        local b = border(tree, { R = 0, G = 0, B = 0, A = 0 }, 4)   -- no box, just the icon
        local v = U("VerticalBox", tree, nm("CardV"))
        local label = textBlock(tree, e.label, 12, COL.white)
        local ammo = textBlock(tree, "", 12, COL.cyanDim)
        local sp = findSprite(e.label, e.icon)
        local btnSp = findSprite("button " .. e.btn, { { "durango_" .. e.btn:lower() .. "_png" } })
        if btnSp then
            local bi = U("Image", tree, nm("Btn"))
            setSprite(bi, btnSp)
            addV(v, sized(tree, bi, 30, 30))
        else
            addV(v, textBlock(tree, e.btn, 18, COL.yellow))
        end
        local icon = nil
        if sp then
            icon = U("Image", tree, nm("Icon"))
            setSprite(icon, sp)
            addV(v, sized(tree, icon, 72, 72))
        end
        addV(v, label); addV(v, ammo)
        pcall(function() b:SetContent(v) end)
        local sb = sized(tree, b, 150, 138)
        gridAdd(cross, sb, spots[e.btn][1], spots[e.btn][2])
        cards[wi] = { border = b, label = label, ammo = ammo, icon = icon }
    end
    gridAdd(cross, sized(tree, U("SizeBox", tree, nm("Mid")), 40, 40), 1, 1)
    -- the game's own mind-ability hints (yellow icons) on the left of the weapons, the rest on
    -- the right of the powers grid, with their controller buttons
    local hints = { left = {}, right = {} }
    for _, e in ipairs(SIDE_ABILITIES) do
        local ic = findSprite("ability " .. e.icon, { { e.icon } })
        if ic then
            local side = e.left and hints.left or hints.right
            side[#side + 1] = { icon = ic, prompt = findSprite("button " .. e.btn, { { e.btn } }) }
        end
    end
    local function hintColumn(list)
        local hv = U("VerticalBox", tree, nm("Hints"))
        for _, h in ipairs(list) do
            local hb = U("HorizontalBox", tree, nm("Hint"))
            if h.prompt then
                local pi2 = U("Image", tree, nm("HintBtn"))
                setSprite(pi2, h.prompt)
                pcall(function() local sl = hb:AddChildToHorizontalBox(sized(tree, pi2, 30, 30)); sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }) end)
            elseif h.promptText then
                pcall(function() local sl = hb:AddChildToHorizontalBox(textBlock(tree, h.promptText, 12, COL.cyan)); sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }) end)
            end
            local ii = U("Image", tree, nm("HintIcon"))
            setSprite(ii, h.icon)
            pcall(function() local sl = hb:AddChildToHorizontalBox(sized(tree, ii, 56, 56)); sl:SetVerticalAlignment(2) end)
            pcall(function() local sl = hv:AddChildToVerticalBox(hb); sl:SetPadding({ Left = 0, Top = 6, Right = 0, Bottom = 6 }) end)
        end
        return hv
    end
    if #hints.left > 0 then
        pcall(function()
            local sl = row:AddChildToHorizontalBox(hintColumn(hints.left))
            sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 26, Bottom = 0 })
        end)
    end
    pcall(function()
        local s = row:AddChildToHorizontalBox(cross)
        s:SetVerticalAlignment(2)
        s:SetPadding({ Left = 0, Top = 0, Right = 28, Bottom = 0 })
    end)

    -- mind powers: 4 x 4
    local grid = U("UniformGridPanel", tree, nm("Grid"))
    pcall(function() grid:SetSlotPadding({ Left = 3, Top = 3, Right = 3, Bottom = 3 }) end)
    local cells = {}
    for pi, pw in ipairs(POWERS) do
        local b = border(tree, COL.cell, 4)
        local t = textBlock(tree, pw.name .. (pw.beta and "  BETA" or ""), 9, pw.ready and COL.white or COL.grey)
        pcall(function() t:SetAutoWrapText(true) end)
        pcall(function() t:SetJustification(1) end)
        local img = U("Image", tree, nm("PowIcon"))
        local hasIcon = setPowerIcon(img, pw.name)
        if hasIcon then
            local cv = U("VerticalBox", tree, nm("PowCell"))
            pcall(function() local sl = cv:AddChildToVerticalBox(sized(tree, img, 58, 58)); sl:SetHorizontalAlignment(2) end)
            pcall(function() local sl = cv:AddChildToVerticalBox(t); sl:SetHorizontalAlignment(2); sl:SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 0 }) end)
            pcall(function() b:SetContent(cv) end)
        else
            pcall(function() b:SetContent(t) end)
        end
        local sb = sized(tree, b, 104, hasIcon and 92 or 52)
        gridAdd(grid, sb, (pi - 1) // 4, (pi - 1) % 4)
        cells[pi] = { border = b, text = t, icon = hasIcon and img or nil }
    end
    local gv = U("VerticalBox", tree, nm("GridV"))
    do
        local gh = U("HorizontalBox", tree, nm("GridHead"))
        local dp = findSprite("button dpad", { { "durango_dpad_all" } })
        if dp then
            local di = U("Image", tree, nm("DpadImg"))
            setSprite(di, dp)
            pcall(function() local sl = gh:AddChildToHorizontalBox(sized(tree, di, 24, 24)); sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }) end)
        end
        pcall(function() local sl = gh:AddChildToHorizontalBox(textBlock(tree, "choose     ", 12, COL.cyanDim)); sl:SetVerticalAlignment(2) end)
        local ltSp = findSprite("button lt", { { "durango_lt_png" } })
        if ltSp then
            local ti = U("Image", tree, nm("LTImg"))
            setSprite(ti, ltSp)
            pcall(function() local sl = gh:AddChildToHorizontalBox(sized(tree, ti, 24, 24)); sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }) end)
        end
        pcall(function() local sl = gh:AddChildToHorizontalBox(textBlock(tree, "use     MIND POWERS", 12, COL.cyanDim)); sl:SetVerticalAlignment(2) end)
        addV(gv, gh, 2)
    end
    addV(gv, grid)
    pcall(function()
        local s = row:AddChildToHorizontalBox(gv)
        s:SetVerticalAlignment(2)
    end)
    if #hints.right > 0 then
        pcall(function()
            local sl = row:AddChildToHorizontalBox(hintColumn(hints.right))
            sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 26, Top = 0, Right = 0, Bottom = 0 })
        end)
    end

    -- the banner: chosen power's name, cost and what it does
    -- the info strip, like the mothership's: thin cyan rules above and below a dark glass
    -- band of a fixed size (long descriptions wrap inside it, the strip never resizes)
    local strip = U("VerticalBox", tree, nm("Strip"))
    local function rule()
        local l = border(tree, { R = 0.36, G = 0.92, B = 1.0, A = 0.7 }, 0)
        return sized(tree, l, 860, 1)
    end
    local banner = border(tree, { R = 0.0, G = 0.06, B = 0.08, A = 0.55 }, 0)
    pcall(function() banner:SetPadding({ Left = 24, Top = 8, Right = 24, Bottom = 8 }) end)
    local bv = U("VerticalBox", tree, nm("BannerV"))
    local bName = textBlock(tree, "", 18, COL.yellow)
    local bCost = textBlock(tree, "", 11, COL.cyan)
    local bDesc = textBlock(tree, "", 13, COL.white)
    -- wrap at the strip's width (less its padding), so text always fits inside it
    pcall(function() bDesc:SetAutoWrapText(false) end)
    pcall(function() bDesc.WrapTextAt = 800 end)
    pcall(function() bDesc:SetWrapTextAt(800) end)
    addV(bv, bName); addV(bv, bCost, 1); addV(bv, bDesc, 2)
    pcall(function() banner:SetContent(bv) end)
    addV(strip, rule())
    addV(strip, sized(tree, banner, 860, 100))
    addV(strip, rule())
    addV(stripSlot, strip)
    addV(col, textBlock(tree, "Let go of LB to switch", 12, COL.cyanDim), 2)

    pcall(function() tree.RootWidget = root end)
    pcall(function() w:SetVisibility(4) end)   -- visible, clicks go through
    pcall(function() w:SetRenderOpacity(1.0) end)
    -- smaller on the smaller screens of 3-4 player split screen
    -- full size, unless it wouldn't fit the player's part of the screen (3-4 players)
    pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs = wll:GetViewportSize(OK.getWorld())
        local dpi = wll:GetViewportScale(OK.getWorld())
        dpi = (type(dpi) == "number" and dpi > 0) and dpi or 1
        local aw, ah = areaOf(i, { X = vs.X / dpi, Y = vs.Y / dpi })
        local dw, dh = CFG.WHEEL_DESIGN_W or 940, CFG.WHEEL_DESIGN_H or 760
        pcall(function()
            root:ForceLayoutPrepass()
            local ds = root:GetDesiredSize()
            if ds and ds.X > 100 and ds.Y > 100 then dw, dh = ds.X, ds.Y end
        end)
        local k = math.min(1.0, aw * 0.96 / dw, ah * 0.96 / dh)
        if k < 0.999 then
            pcall(function() root:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
            pcall(function() root:SetRenderScale({ X = k, Y = k }) end)
            if not state.wheelScaleLogged then state.wheelScaleLogged = true; wlog("Wheel scaled to %.0f%% to fit a %dx%d screen part (menu %dx%d)", k * 100, aw, ah, dw, dh) end
        end
    end)
    local okA = pcall(function() w:AddToPlayerScreen(150) end)
    if not okA then return nil end
    return { widget = w, cards = cards, cells = cells, bName = bName, bCost = bCost, bDesc = bDesc }
end

local function refreshOverlay(p, pawn)
    local o = p.overlay
    if not o then return end
    local list, cur = weaponsOf(pawn)
    for wi, e in ipairs(WEAPONS) do
        local c = o.cards[wi]
        local w = findWeapon(list, e)
        local isCur = w and valid(cur) and OK.keyOf(w) == OK.keyOf(cur)
        local picked = p.pending == wi
        setColor(c.label, not w and COL.grey or (picked and COL.yellow or (isCur and COL.cyan or COL.white)))
        if c.icon then
            local tint = picked and COL.yellow or (isCur and COL.cyan or { R = 0.85, G = 0.9, B = 0.95, A = 0.85 })
            pcall(function() c.icon:SetColorAndOpacity(tint) end)
            local sc = picked and 1.15 or 1.0
            pcall(function() c.icon:SetRenderScale({ X = sc, Y = sc }) end)
        end
        setText(c.ammo, w and ammoText(w) or "not found")
    end
    local sel = p.sel or 1
    for pi, cell in ipairs(o.cells) do
        local on = pi == sel
        pcall(function() cell.border:SetBrushColor(on and COL.cellOn or COL.cell) end)
        setColor(cell.text, on and COL.yellow or (POWERS[pi].ready and COL.white or COL.grey))
        if cell.icon then
            local a = POWERS[pi].ready and 1.0 or 0.4
            pcall(function() cell.icon:SetColorAndOpacity({ R = a, G = a, B = a, A = on and 1.0 or (POWERS[pi].ready and 0.9 or 0.55) }) end)
            local sc = on and 1.12 or 1.0
            pcall(function() cell.icon:SetRenderScale({ X = sc, Y = sc }) end)
        end
    end
    local pw = POWERS[sel]
    setText(o.bName, pw.name)
    setText(o.bCost, "Concentration: " .. pw.cost .. (pw.beta and "     |     BETA" or (pw.ready and "" or "     |     coming soon")))
    setText(o.bDesc, pw.desc)
end

local function closeOverlay(p)
    if p.overlay and valid(p.overlay.widget) then pcall(function() p.overlay.widget:RemoveFromParent() end) end
    p.overlay = nil
end

------------------------------------------------------------------------------------------
-- The power panel above the weapon icon (bottom right of each player's screen)
------------------------------------------------------------------------------------------
-- The concentration meter in the 2005 game's style: a row of glowing pills in a frame,
-- cyan filling into yellow at the top end.
local PILLS = 24
local function buildPanel(i, pc)
    local w, tree = newHost(pc)
    if not w then return nil end
    local v = U("VerticalBox", tree, nm("PanelV"))
    local top = U("HorizontalBox", tree, nm("PanelTop"))
    local ltChip = border(tree, COL.cyan, 0)
    pcall(function() ltChip:SetPadding({ Left = 6, Top = 0, Right = 6, Bottom = 0 }) end)
    local lt = textBlock(tree, "LT", 13, { R = 0.0, G = 0.1, B = 0.12, A = 1 })
    pcall(function() ltChip:SetContent(lt) end)
    local name = textBlock(tree, "Lock-on", 14, COL.yellow)
    pcall(function() local sl = top:AddChildToHorizontalBox(ltChip); sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 0 }) end)
    local picon = U("Image", tree, nm("PanelIcon"))
    pcall(function() local sl = top:AddChildToHorizontalBox(sized(tree, picon, 30, 30)); sl:SetVerticalAlignment(2); sl:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }) end)
    pcall(function() picon:SetVisibility(2) end)
    pcall(function() local sl = top:AddChildToHorizontalBox(name); sl:SetVerticalAlignment(2) end)
    -- frame: a light violet-blue rim around a dark glass strip, like the old HUD
    -- slanted like the 2005 bar: a pale lavender rim round a dark navy strip
    local rim = border(tree, { R = 0.36, G = 0.92, B = 1.0, A = 0.95 }, 2)
    local glass = border(tree, { R = 0.04, G = 0.05, B = 0.16, A = 0.88 }, 0)
    pcall(function() glass:SetPadding({ Left = 16, Top = 5, Right = 14, Bottom = 5 }) end)
    pcall(function() rim:SetRenderShear({ X = -CFG.WHEEL_BAR_SLANT, Y = 0 }) end)
    local row = U("HorizontalBox", tree, nm("Pills"))
    local pills = {}
    for k = 1, PILLS do
        local pb = border(tree, COL.cyan, 0)
        pills[k] = pb
        pcall(function()
            local sl = row:AddChildToHorizontalBox(sized(tree, pb, 6, 15))
            sl:SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 0 })
        end)
    end
    pcall(function() row:SetRenderShear({ X = CFG.WHEEL_BAR_SLANT, Y = 0 }) end)   -- pills stay upright
    pcall(function() glass:SetContent(row) end)
    pcall(function() rim:SetContent(glass) end)
    local function addV(child, pad)
        local ok, sl = pcall(function() return v:AddChildToVerticalBox(child) end)
        if ok and sl then
            pcall(function() sl:SetHorizontalAlignment(3) end)
            if pad then pcall(function() sl:SetPadding({ Left = 0, Top = pad, Right = 0, Bottom = 0 }) end) end
        end
    end
    addV(top); addV(rim, 3)
    pcall(function() tree.RootWidget = v end)
    pcall(function() w:SetVisibility(4) end)
    if not pcall(function() w:AddToPlayerScreen(5) end) then return nil end
    pcall(function() w:SetAlignmentInViewport({ X = 1, Y = 1 }) end)
    return { widget = w, lt = ltChip, name = name, icon = picon, pills = pills, lastFill = -1 }
end
-- Like the 2005 bar: yellow pills = concentration you have; a spent pill flashes white and
-- fades away (from the right); a refilled pill comes in pale and warms to yellow.
local PILL_FULL = { R = 1.0, G = 0.86, B = 0.12, A = 1 }
local PILL_CYAN = { R = 0.36, G = 0.92, B = 1.0, A = 1 }      -- default look: cyan and white only
local PALE_CYAN = { R = 0.9, G = 1.0, B = 1.0, A = 1 }
local SPEND_TIME, FRESH_TIME = 0.55, 0.8
local function mix(a, b, t)
    return { R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t, A = a.A + (b.A - a.A) * t }
end
local WHITE, GONE, PALE = { R = 1, G = 1, B = 1, A = 1 }, { R = 1, G = 1, B = 1, A = 0 }, { R = 1, G = 1, B = 0.85, A = 1 }
local function setMeter(panel, pct)
    local fill = math.floor(math.max(0, math.min(1, pct)) * PILLS + 0.5)
    local now = os.clock()
    panel.burnAt = panel.burnAt or {}
    panel.freshAt = panel.freshAt or {}
    panel.shown = panel.shown or {}
    local last = panel.lastFill
    if last and last >= 0 then
        for k = fill + 1, last do panel.burnAt[k] = now end
        for k = last + 1, fill do panel.freshAt[k] = now end
    end
    panel.lastFill = fill
    for k, pb in ipairs(panel.pills) do
        local col, key
        local classic = state.meterStyle == "Classic yellow"
        local full = classic and PILL_FULL or PILL_CYAN
        local pale = classic and PALE or PALE_CYAN
        if k <= fill then
            panel.burnAt[k] = nil
            local t = panel.freshAt[k] and (now - panel.freshAt[k]) / FRESH_TIME or 1
            if t < 1 then col, key = mix(pale, full, t), "f" .. math.floor(t * 10) else col, key = full, classic and "full" or "fullc" end
        else
            local t = panel.burnAt[k] and (now - panel.burnAt[k]) / SPEND_TIME or 1
            if t < 1 then col, key = mix(WHITE, GONE, t), "b" .. math.floor(t * 10) else col, key = GONE, "gone" end
        end
        if panel.shown[k] ~= key then
            panel.shown[k] = key
            pcall(function() pb:SetBrushColor(col) end)
        end
    end
end

-- Concentration: the game's own meter (it's kept by the Holobob ability). While Holobob is
-- on, the panel shows the game's value; otherwise it shows the mod's own pool for the new
-- powers, which works with the same numbers (full = the game's maximum).
local function concentration(pawn, p)
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    if mental then
        local holo = nil
        for _, ab in ipairs(state.p2Abilities and state.p2Abilities(mental) or {}) do
            if valid(ab) and OK.nameOf(ab):find("Holobob") then holo = ab break end
        end
        if not holo and not p.holoMissLogged then p.holoMissLogged = true; wlog("Holobob ability not found for the meter") end
        if holo then
            local okP, pct = pcall(function() return holo:GetCurrentConcentrationPercent(false) end)
            if okP and type(pct) == "number" then
                if pct > 1.5 then pct = pct / 100 end      -- in case it comes as 0..100
                if not p.concLogged then p.concLogged = true; wlog("concentration from the game: %.2f", pct) end
                if pct > 0.001 and pct < 0.999 then return math.min(pct, p.pool or 1.0) end
            end
        end
    end
    return p.pool or 1.0
end

local function placePanel(i, p)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local okS, size = pcall(function() return wbl:GetViewportSize(OK.getWorld()) end)
    local okD, dpi = pcall(function() return wbl:GetViewportScale(OK.getWorld()) end)
    if not (okS and size and size.X and size.X > 0) then return end
    local scale = (okD and type(dpi) == "number" and dpi > 0) and dpi or 1
    local areaW, areaH = areaOf(i, size)
    -- just above the big weapon icon in the bottom-right corner
    local x = areaW - CFG.WHEEL_PANEL_RIGHT * scale
    local y = areaH - CFG.WHEEL_PANEL_BOTTOM * scale
    pcall(function() p.panel.widget:SetPositionInViewport({ X = x, Y = y }, true) end)
end

------------------------------------------------------------------------------------------
-- The game's own wheel underneath: kept open (so the face buttons are free) but hidden,
-- and the slow motion it brings is undone.
------------------------------------------------------------------------------------------
local SPEEDS = { ["Normal"] = 1.0, ["Slow motion 25%"] = 0.25, ["Half speed"] = 0.5, ["Fast 150%"] = 1.5, ["Double speed"] = 2.0 }
local function wantedSpeed() return SPEEDS[state.trSpeed or "Normal"] or 1.0 end

-- The game's own wheel is never used on foot: if it opens anyway it's closed at once (the
-- old split-screen way), and the button that opens it is taken away while the mod's wheel
-- is on. While LB is held, the game's other button actions (jump, dash, fire, PK...) are
-- swapped for a harmless one, so A / B / X / Y only pick weapons; the sticks still move.
local function closeGameWheel(pawn)
    local sel = subObj(pawn, "m_pWeaponAndAbilitySelection")
    local menu = sel and subObj(sel, "m_pMenu")
    if menu then
        local okV, inVp = pcall(function() return menu:IsInViewport() end)
        local okS, vis = pcall(function() return menu:IsVisible() end)
        if okV and inVp and okS and vis then
            pcall(function() sel:OnSelectionMenuClosed(menu) end)
            pcall(function() menu:RemoveFromParent() end)
            return true
        end
    end
    return false
end

-- Closing the game's wheel after it opened still showed it for a frame or two, every time.
-- Now it's made see-through before it can show: its widget is kept fully transparent (and
-- pushed off screen) while you're on foot and the mod's wheel is on, and the moment the
-- game opens it (its HUD event, on the game thread) it's hidden again before it draws.
-- The tick still closes it straight after so its slow motion and buttons don't stay.
local function setGameMenuHidden(menu, hide)
    if not valid(menu) then return end
    local a = hide and 0 or 1
    pcall(function() menu:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = a }) end)
    pcall(function() menu:SetRenderOpacity(a) end)
    pcall(function() menu:SetRenderTranslation({ X = hide and -30000 or 0, Y = 0 }) end)
end
local function hideGameMenuOf(pawn)
    local sel = subObj(pawn, "m_pWeaponAndAbilitySelection")
    local menu = sel and subObj(sel, "m_pMenu")
    local want = CFG.MIND_WHEEL and CFG.HIDE_GAME_WHEEL ~= false and onFoot(pawn) or false
    if menu then
        local k = OK.keyOf(menu)
        state.gameMenuHidden = state.gameMenuHidden or {}
        -- set again each time it's in the viewport (the game may reset it when it opens)
        local okV, inVp = pcall(function() return menu:IsInViewport() end)
        if state.gameMenuHidden[k] ~= want or (want and okV and inVp) then
            setGameMenuHidden(menu, want)
            state.gameMenuHidden[k] = want
        end
    end
    return menu
end
state.hideGameMenuOf = hideGameMenuOf
OK.onWorldChange(function() state.gameMenuHidden = {} end)
if not state.gameMenuHook then
    state.gameMenuHook = true
    local okH = pcall(function()
        RegisterHook("/Game/Blueprints/UI/HUD/BPW_HUD_Base.BPW_HUD_Base_C:Event_OnSelectionMenuStateChanged", function(Context)
            if not CFG.MIND_WHEEL then return end
            pcall(function()
                local hud = Context:get()
                local pawn = hud:GetOwningPlayerPawn()
                if valid(pawn) and onFoot(pawn) then
                    local sel = subObj(pawn, "m_pWeaponAndAbilitySelection")
                    local menu = sel and subObj(sel, "m_pMenu")
                    if menu then setGameMenuHidden(menu, true) end
                end
            end)
        end)
    end)
    wlog("Game wheel: hidden the moment it opens (%s)", okH and "hooked" or "hook not available, closing it instead")
end

-- while the LB menu is open the player can't be seen (the game's own "invisible" state)
local function wheelProtect(pawn, on)
    local inv = OK.stat(pawn, "m_pIsInvisibleStat")
    if inv then
        pcall(function() inv:SetValue(on, true, true, false) end)
        pcall(function() inv:SetValue(on) end)
        pcall(function() inv.m_bValue = on end)
    end
    local ai = subObj(pawn, "m_pAITargetComponent")
    if ai then if on then pcall(function() ai:Deactivate() end) else pcall(function() ai:Activate(true) end) end end
end
local loggedDilation = false
local function keepFullSpeed()
    local st = OK.getStatics()
    local okG, d = pcall(function() return st:GetGlobalTimeDilation(OK.getWorld()) end)
    local want = wantedSpeed()
    if okG and type(d) == "number" and math.abs(d - want) > 0.01 then
        if not loggedDilation then loggedDilation = true; wlog("the game slowed time to %.2f for its wheel; set back to %.2f", d, want) end
        pcall(function() st:SetGlobalTimeDilation(OK.getWorld(), want) end)
    end
end


------------------------------------------------------------------------------------------
-- Mind powers (BETA): cast with LT when chosen on the wheel. Concentration: 6 dots in the
-- meter (each dot = 4 pills); one dot comes back every 6 seconds.
------------------------------------------------------------------------------------------
local DOT = 1 / 6
local npcCache, npcAt = {}, -10
local function npcList()
    if os.clock() - npcAt < 0.5 then return npcCache end
    npcAt = os.clock()
    local list, pk = {}, {}
    for _, pc in ipairs(controllers()) do local pw = getPawn(pc); if valid(pw) then pk[OK.keyOf(pw)] = true end end
    pcall(function()
        local out = {}
        OK.getStatics():GetAllActorsOfClass(OK.getWorld(), StaticFindObject("/Script/Engine.Character"), out)
        for _, a in ipairs(out) do
            local v = a
            if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
            if valid(v) and not pk[OK.keyOf(v)] then list[#list + 1] = v end
        end
    end)
    npcCache = list
    return list
end
-- people in front of a player: within range, inside a cone (cosine of its half-angle)
local function cone(pc, pawn, range, cosMin)
    local res = {}
    local okL, me = pcall(function() return pawn:K2_GetActorLocation() end)
    local okR, rot = pcall(function() return pc.PlayerCameraManager:GetCameraRotation() end)
    if not (okL and okR and me and rot) then return res end
    local yaw = math.rad(rot.Yaw)
    local fx, fy = math.cos(yaw), math.sin(yaw)
    for _, n in ipairs(npcList()) do
        if valid(n) and not (state.deadChar and state.deadChar(n)) then
            local okN, l = pcall(function() return n:K2_GetActorLocation() end)
            if okN and l then
                local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                local d = math.sqrt(dx * dx + dy * dy)
                if d < range and math.abs(dz) < 400 and d > 1 and (dx * fx + dy * fy) / d >= cosMin then
                    res[#res + 1] = { n = n, fx = dx / d, fy = dy / d }
                end
            end
        end
    end
    return res, fx, fy
end

local timers = {}   -- things to put back later: { at, fn }
local function after(sec, fn) timers[#timers + 1] = { at = os.clock() + sec, fn = fn } end
OK.onWorldChange(function() timers = {}; npcCache = {} end)

local frozen = {}   -- key -> { n, untilT }
local floating = {} -- key -> true
local function spend(p, dots)
    if (p.pool or 1) + 1e-6 < dots * DOT then return false end
    p.pool = (p.pool or 1) - dots * DOT
    return true
end

-- Visible power: the game's own Zap-O-Matic lightning, from Crypto to each person hit
local arcClass = nil
local liveArcs = {}   -- { actor, untilT, target, fromPawn }
local function getArcClass(pawn)
    if arcClass then return arcClass end
    pcall(function()
        local eq = subObj(pawn, "m_pEquipmentManagerComponent")
        for _, w in ipairs(OK.arrayToList(eq.m_aWeaponList)) do
            local nm = valid(w) and OK.nameOf(w):lower() or ""
            if nm:find("zap") then
                -- the gun's own lightning actor (its beam), under whichever name this build uses
                for _, f in ipairs({ "m_pBeam", "m_pBeamActor", "Beam" }) do
                    local okB, b = pcall(function() return w[f] end)
                    if okB and valid(b) then
                        local okF, fx = pcall(function() return b.BeamEffect end)
                        if okF and valid(fx) then
                            arcClass = fx:GetClass()
                            pcall(function() state.arcBlackboard = fx.m_pBlackboard end)
                        elseif not arcClass then arcClass = b:GetClass() end
                    end
                    if arcClass then break end
                end
                if not arcClass then
                    pcall(function() w:GetClass():ForEachProperty(function(pp)
                        if arcClass then return end
                        local n = pp:GetFName():ToString()
                        if n:lower():find("beam") then
                            local okV, v = pcall(function() return w[n] end)
                            if okV and valid(v) and OK.nameOf(v):lower():find("beam") then
                                local okF, fx = pcall(function() return v.BeamEffect end)
                                arcClass = (okF and valid(fx)) and fx:GetClass() or v:GetClass()
                            end
                        end
                    end) end)
                end
                if not state.arcClassLogged then state.arcClassLogged = true; wlog("Zap beam: %s (from %s)", arcClass and OK.shortName(arcClass) or "not found", OK.shortName(w)) end
            end
        end
    end)
    return arcClass
end
local MAX_ARCS = 28
-- arcTo(from, target, seconds [, opts]): lightning from an actor (or opts.fromFn() point) to an
-- actor (or opts.toFn() point; an invisible anchor carries the end of the beam)
local function arcTo(from, target, seconds, opts)
    -- no Zap-O-Matic lightning from the mod's powers at all (the powers still do their damage)
    opts = opts or {}
    if not CFG.POWER_ARCS and not opts.force then return nil end
    if #liveArcs >= MAX_ARCS then return nil end
    local cls = getArcClass(from)
    if not cls then
        for _, pc in ipairs(controllers()) do
            local pw = getPawn(pc)
            if valid(pw) then cls = getArcClass(pw) end
            if cls then break end
        end
    end
    if not cls then return nil end
    opts = opts or {}
    local start = opts.fromFn and opts.fromFn() or nil
    if not start then
        local okL, l = pcall(function() return from:K2_GetActorLocation() end)
        if not (okL and l) then return nil end
        start = { X = l.X, Y = l.Y, Z = l.Z + 40 }
    end
    local ok, a = pcall(function() return OK.getWorld():SpawnActor(cls, start, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
    if not (ok and valid(a)) then return nil end
    pcall(function() a.audio_weaponloop:Stop() end)
    -- the game normally switches the beam on through its effect system (as the co-op zap does)
    if state.arcBlackboard then pcall(function() a:SetBlackboard(state.arcBlackboard) end) end
    pcall(function() a:TriggerEffect() end)
    pcall(function() a:SetActorHiddenInGame(false) end)
    for _, part in ipairs({ "Lightning_Beam", "Lightning_Beam_2" }) do
        pcall(function() a[part]:SetHiddenInGame(false, true) end)
        pcall(function() a[part]:SetVisibility(true, true) end)
    end
    for _, part in ipairs({ "PFX_Zap-o-Matic_permanent_01", "PFX_hit_loop_01" }) do pcall(function() a[part]:Activate(true) end) end
    if valid(target) then pcall(function() a:SetTargetActor(target) end) end
    pcall(function() a:StartBeam() end)
    liveArcs[#liveArcs + 1] = { actor = a, untilT = os.clock() + seconds, target = target, fromPawn = from,
                                fromFn = opts.fromFn, toFn = opts.toFn }
    return a
end
local function updateArcs()
    local now = os.clock()
    for k = #liveArcs, 1, -1 do
        local e = liveArcs[k]
        local dead = now >= e.untilT or not valid(e.actor)
            or (not e.toFn and not valid(e.target)) or (not e.fromFn and not valid(e.fromPawn))
        local from, to = nil, nil
        if not dead then
            if e.fromFn then from = e.fromFn() else
                local okF, f = pcall(function() return e.fromPawn:K2_GetActorLocation() end)
                if okF and f then from = { X = f.X, Y = f.Y, Z = f.Z + 40 } end
            end
            if e.toFn then to = e.toFn() else
                local okT, t = pcall(function() return state.targetPoint and state.targetPoint(e.target) or e.target:K2_GetActorLocation() end)
                if okT then to = t end
            end
            dead = not (from and to)
        end
        if dead then
            if valid(e.actor) then pcall(function() e.actor:StopBeam() end); pcall(function() e.actor:K2_DestroyActor() end) end
            table.remove(liveArcs, k)
        else
            pcall(function()
                local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
                e.actor:K2_SetActorLocation(from, false, {}, false)
                e.actor:K2_SetActorRotation({ Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }, false)
                e.actor:SetTargetLocation(to)
                if valid(e.target) then e.actor:SetTargetActor(e.target) end
                e.actor:UpdateBeam()
            end)
            if CFG.ARC_FORCE_UPDATE then
                pcall(function() e.actor:ForceBeamUpdate() end)
                pcall(function() e.actor:UpdateBeamFVX() end)
            end
        end
    end
end
OK.onWorldChange(function() liveArcs = {}; arcClass = nil end)
-- show where a power reaches: a short arc to a few of the people it hit
local function showHits(pawn, hit, seconds, maxArcs)
    if not CFG.POWER_ARCS then return end
    for k, e in ipairs(hit) do
        if k > (maxArcs or 5) then break end
        arcTo(pawn, e.n or e, seconds or 0.35)
    end
end

local function mentalClass(path)
    local c = StaticFindObject(path)
    if valid(c) then return c end
    local ok, l = pcall(function() return LoadAsset(path) end)
    if ok and valid(l) then return l end
    return nil
end

local mark, unmark   -- (set further down) labels over affected people
local coneWave   -- (set further down) a wave of glowing orbs showing where a cone power reaches
local CAST = {}
local psiClass, fireProjectile   -- (set further down) the psi mutants' borrowed attacks
-- Psychic Ragdoll: the game's own PK grab-and-let-go (that's what makes people go limp),
-- with a push away from Crypto
CAST.ragdoll = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    if not spend(p, 1) then wlog("P%d: not enough concentration", i) return end
    local hit = cone(pc, pawn, 1100, 0.6)
    showHits(pawn, hit, 0.3)
    for _, e in ipairs(hit) do
        local n = e.n
        local okU = pcall(function() n:OnPKPickUp() end)
        after(0.05, function()
            if not valid(n) then return end
            local okD = pcall(function() n:OnPKDrop() end)
            pcall(function() n.Mesh:AddImpulse({ X = e.fx * 900, Y = e.fy * 900, Z = 450 }, FName("None"), true) end)
            pcall(function() n:LaunchCharacter({ X = e.fx * 900, Y = e.fy * 900, Z = 450 }, true, true) end)
            if not state.ragLogged then state.ragLogged = true; wlog("ragdoll by PK pick-up/drop: %s / %s", tostring(okU), tostring(okD)) end
        end)
    end
    wlog("P%d Psychic Ragdoll: %d", i, #hit)
end
CAST.zerog = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    if not spend(p, 3) then wlog("P%d: not enough concentration", i) return end
    local hit = cone(pc, pawn, 1500, 0.45)
    showHits(pawn, hit, 0.4)
    for _, e in ipairs(hit) do
        local n = e.n
        local k = OK.keyOf(n)
        if not floating[k] then
            local cm = subObj(n, "CharacterMovement")
            local okG, g = pcall(function() return cm.GravityScale end)
            if cm and okG then
                floating[k] = true
                mark(n, "Zero-G Cone", 7)
                pcall(function() cm.GravityScale = 0.03 end)
                pcall(function() n:LaunchCharacter({ X = e.fx * 80, Y = e.fy * 80, Z = 380 }, false, true) end)
                after(7.0, function()
                    floating[k] = nil
                    if valid(cm) then pcall(function() cm.GravityScale = g end) end
                end)
            end
        end
    end
    wlog("P%d Zero-G Cone: %d floating", i, #hit)
end
-- Cryokinesis: hold LT. Lightning shows the cone; people slow down, then freeze: their AI
-- and guns stop, an outline marks them, and a frozen person shatters (dies) when hit.
local iceSaved = {}
local function setFrozen(n, on)
    pcall(function() n.CustomTimeDilation = on and 0.0 or 1.0 end)
    -- an ice look: icy see-through blue over the whole body while frozen, their own look after
    pcall(function()
        local mesh = n.Mesh
        local k = OK.keyOf(n)
        if on and not iceSaved[k] then
            local holo = StaticFindObject(CFG.CLOAK_MATERIAL ~= "" and CFG.CLOAK_MATERIAL or "/Game/VFX/Materials/Meshes/M_Hologram_01.M_Hologram_01")
            if not valid(holo) then return end
            local saved = {}
            local okN, cnt = pcall(function() return mesh:GetNumMaterials() end)
            for slot = 0, (okN and cnt or 1) - 1 do
                local okM, m = pcall(function() return mesh:GetMaterial(slot) end)
                saved[slot] = okM and m or nil
                local okD, mid = pcall(function() return mesh:CreateDynamicMaterialInstance(slot, holo) end)
                if okD and valid(mid) then
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Opacity"), CFG.ICE_OPACITY or 0.85) end)
                    pcall(function() mid:SetScalarParameterValue(FName("HoloLine_Opacity"), 0.3) end)
                    pcall(function() mid:SetScalarParameterValue(FName("HoloLine_GapOpacity"), CFG.ICE_OPACITY or 0.85) end)
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Emissive"), CFG.ICE_GLOW or 2.5) end)
                    pcall(function() mid:SetVectorParameterValue(FName("Holo_TintColor"), { R = 0.6, G = 0.9, B = 1.0, A = 1 }) end)
                end
            end
            iceSaved[k] = { mesh = mesh, mats = saved }
            -- and the game's stun stars over them, so frozen is plain to see
            if state.playFx then iceSaved[k].fx = state.playFx(CFG.FROZEN_FX or "/Game/VFX/PFX/Gameplay/MentalAbilities/Hypno/Distract/PFX_Loop_Stun.PFX_Loop_Stun", nil, 1.0, mesh) end
        elseif not on and iceSaved[k] then
            local e = iceSaved[k]
            iceSaved[k] = nil
            for slot, m in pairs(e.mats) do if valid(m) then pcall(function() e.mesh:SetMaterial(slot, m) end) end end
            if e.fx and valid(e.fx) then pcall(function() e.fx:DeactivateSystem() end); pcall(function() e.fx:K2_DestroyComponent(e.fx) end) end
        end
    end)
    pcall(function()
        local out = {}
        n:GetAttachedActors(out)
        for _, a in ipairs(out) do
            local v = a
            if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
            if valid(v) then pcall(function() v.CustomTimeDilation = on and 0.0 or 1.0 end) end
        end
    end)
    pcall(function()
        local ctl = n:GetController()
        local brain = ctl.BrainComponent
        if on then brain:StopLogic("Frozen") else brain:RestartLogic() end
    end)
    pcall(function()
        n.Mesh:SetRenderCustomDepth(on)
        if on then n.Mesh:SetCustomDepthStencilValue(CFG.FROZEN_OUTLINE) end
    end)
end
CAST.cryo = function(i, p, pc, pawn, pressed, held, dt)
    if not held then return end
    if not spend(p, dt * (CFG.CRYO_COST or 0.4)) then return end   -- 0.4 of a dot per second while held
    p.cryoTick = (p.cryoTick or 0) + dt
    if p.cryoTick < 0.2 then return end
    local step = p.cryoTick
    p.cryoTick = 0
    p.cryoAcc = p.cryoAcc or {}
    local hit = cone(pc, pawn, 1000, 0.75)
    showHits(pawn, hit, 0.25, 4)
    for _, e in ipairs(hit) do
        local k = OK.keyOf(e.n)
        if not frozen[k] then
            local acc = (p.cryoAcc[k] or 0) + step
            p.cryoAcc[k] = acc
            local dil = math.max(0.0, 1.0 - acc / 1.6)
            pcall(function() e.n.CustomTimeDilation = math.max(dil, 0.05) end)
            if dil <= 0 then
                setFrozen(e.n, true)
                mark(e.n, "Cryokinesis", 8)
                wlog("P%d Cryokinesis froze %s", i, OK.nameOf(e.n))
                local realHp = OK.healthRatio(e.n)
                pcall(function() OK.setRatio(OK.stat(e.n, "m_pHealthStat"), 0.02) end)
                frozen[k] = { n = e.n, untilT = os.clock() + 8.0, hp = OK.healthRatio(e.n) or 0.02, realHp = realHp, by = pawn }
            end
        end
    end
end
-- The game's own effects, by path (from the effect banks Keaton found in FModel)
local GAME_FX = {
    mutantWave   = "/Game/VFX/PFX/Gameplay/PSY_Mutan/PFX_MutanWave.PFX_MutanWave",
    mutantCharge = "/Game/VFX/PFX/Gameplay/PSY_Mutan/PFX_MutanChanelingTarget_Anticipation.PFX_MutanChanelingTarget_Anticipation",
    cowBlast     = "/Game/VFX/PFX/Gameplay/Misc/Cows/PFX_CowExplosion.PFX_CowExplosion",
    loveHearts   = "/Game/VFX/PFX/Gameplay/MentalAbilities/Hypno/Follow/PFX_Loop_Follow.PFX_Loop_Follow",
    psiShield    = "/Game/VFX/Blueprints/PSY/BP_PSY_Shield.BP_PSY_Shield_C",
    boomSound    = "/Game/Audio/Cues/Weapon/NPC/s_weap_explosion_cue.s_weap_explosion_cue",
    pulseSound   = "/Game/Audio/Cues/Weapon/NPC/s_weap_mutant_pulse_cue.s_weap_mutant_pulse_cue",
    loveMusic    = "/Game/Audio/Waves/Music/m_mm04_poolparty_loop.m_mm04_poolparty_loop",
}
state.GAME_FX = GAME_FX
local function gameAsset(path)
    local a = StaticFindObject(path)
    if not valid(a) then pcall(function() LoadAsset(path:gsub("_C$", "")) end); a = StaticFindObject(path) end
    if not valid(a) then pcall(function() LoadAsset(path) end); a = StaticFindObject(path) end
    return valid(a) and a or nil
end
-- play a particle effect once at a spot (or attached to a component when attachTo is given)
local function playFx(key, at, scale, attachTo)
    local tpl = (type(key) == "userdata") and key or gameAsset(GAME_FX[key] or key)
    if type(key) == "userdata" then key = "template" end
    if not tpl then
        if not state["fxMiss" .. key] then state["fxMiss" .. key] = true; wlog("Effect %s: not found", key) end
        return nil
    end
    local gs = OK.getStatics()
    local sc = { X = scale or 1, Y = scale or 1, Z = scale or 1 }
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    local ok, c = false, nil
    -- this engine's calls: SpawnEmitterAtLocation takes 7 values, SpawnEmitterAttached 9
    -- (the other counts are tried after, for other builds)
    local zero = { X = 0, Y = 0, Z = 0 }
    if attachTo then
        for _, call in ipairs({
            function() return gs:SpawnEmitterAttached(tpl, attachTo, FName("None"), zero, rot, sc, 0, true, 0) end,
            function() return gs:SpawnEmitterAttached(tpl, attachTo, FName("None"), zero, rot, sc, 0, true, 0, true) end,
            function() return gs:SpawnEmitterAttached(tpl, attachTo, FName("None"), zero, rot, sc, 0, true) end,
        }) do
            ok, c = pcall(call)
            if ok and valid(c) then break end
        end
    else
        for _, call in ipairs({
            function() return gs:SpawnEmitterAtLocation(OK.getWorld(), tpl, at, rot, sc, true, 0) end,
            function() return gs:SpawnEmitterAtLocation(OK.getWorld(), tpl, at, rot, sc, true, 0, true) end,
            function() return gs:SpawnEmitterAtLocation(OK.getWorld(), tpl, at, rot, sc, true) end,
        }) do
            ok, c = pcall(call)
            if ok and valid(c) then break end
        end
    end
    if not state["fxLog" .. key] then state["fxLog" .. key] = true; wlog("Effect %s: %s", key, (ok and valid(c)) and "playing" or ("failed: " .. tostring(c))) end
    return (ok and valid(c)) and c or nil
end
local function playSound(key, at, volume)
    local snd = gameAsset(GAME_FX[key] or key)
    if not snd then return nil end
    local gs = OK.getStatics()
    if at then
        local ok, c = pcall(function() return gs:SpawnSoundAtLocation(OK.getWorld(), snd, at, { Pitch = 0, Yaw = 0, Roll = 0 }, volume or 1, 1, 0, nil, nil, true) end)
        if ok and valid(c) then return c end
        pcall(function() gs:PlaySoundAtLocation(OK.getWorld(), snd, at, { Pitch = 0, Yaw = 0, Roll = 0 }, volume or 1, 1, 0, nil, nil, nil) end)
        return nil
    end
    local ok, c = pcall(function() return gs:SpawnSound2D(OK.getWorld(), snd, volume or 1, 1, 0, nil, false, true) end)
    if not (ok and valid(c)) then ok, c = pcall(function() return gs:SpawnSound2D(OK.getWorld(), snd, volume or 1) end) end
    return (ok and valid(c)) and c or nil
end
state.playFx, state.playSound = playFx, playSound

-- Free Love: the game's own "distract" hypnosis on everyone in front of you; enough
-- dancers clear the wanted level (more needed the higher it is)
local DISTRACT = "/Game/Blueprints/MentalAbilities/BP_MentalAbility_Hypnotize_Distract.BP_MentalAbility_Hypnotize_Distract_C"
local function loveBurst(i, p, pc, pawn, hit)
    local cls = mentalClass(DISTRACT)
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    local n = 0
    for _, e in ipairs(hit) do
        local ok = cls and mental and pcall(function() mental:ActivateAbilityEffectOnTarget(cls, e.n) end)
        if ok then
            n = n + 1
            mark(e.n, "Free Love", 10)
            local mesh = subObj(e.n, "Mesh")
            local hearts = mesh and (CFG.FREE_LOVE_HEARTS_SPLIT or not valid(state.p2)) and playFx("loveHearts", nil, 1.0, mesh)
            if hearts then after(10, function() if valid(hearts) then pcall(function() hearts:DeactivateSystem() end); pcall(function() hearts:K2_DestroyComponent(hearts) end) end end) end
            state.dancers = state.dancers or {}
            state.dancers[OK.keyOf(e.n)] = os.clock()
        end
    end
    -- the pool party song while people dance (starts once, stops 12 s after the last Free Love)
    if n > 0 and CFG.FREE_LOVE_MUSIC ~= false then
        if not (state.loveMusic and valid(state.loveMusic)) then
            state.loveMusic = playSound("loveMusic", nil, CFG.FREE_LOVE_MUSIC_VOLUME or 0.8)
            if state.loveMusic then wlog("Free Love: pool party music on") end
        end
        state.loveMusicUntil = os.clock() + 12
        if not state.loveMusicJob then
            state.loveMusicJob = true
            state.wheelAddJob("loveMusic", function()
                if os.clock() < (state.loveMusicUntil or 0) and state.loveMusic and valid(state.loveMusic) then return true end
                return false
            end, function()
                state.loveMusicJob = nil
                if state.loveMusic and valid(state.loveMusic) then pcall(function() state.loveMusic:FadeOut(1.5, 0, 0) end); pcall(function() state.loveMusic:Stop() end) end
                state.loveMusic = nil
            end)
        end
    end
    -- dancers in the last 30 seconds count towards clearing the wanted level
    local count, now = 0, os.clock()
    for k, t in pairs(state.dancers or {}) do if now - t < 30 then count = count + 1 else state.dancers[k] = nil end end
    -- 5 or more dancing: it catches on. For 30 s everyone around starts dancing too
    -- (the party spread is new and a 2-player game crashed during Free Love: 1 player only for now)
    if (CFG.FREE_LOVE_PARTY_SPLIT or not valid(state.p2)) and count >= (CFG.FREE_LOVE_SPREAD_AT or 5) and (state.lovePartyUntil or 0) < os.clock() and cls and mental then
        state.lovePartyUntil = os.clock() + (CFG.FREE_LOVE_SPREAD_SECONDS or 30)
        state.loveMusicUntil = state.lovePartyUntil
        wlog("P%d Free Love: it's a party! everyone near joins in for %d s", i, CFG.FREE_LOVE_SPREAD_SECONDS or 30)
        local nextAt = 0
        state.wheelAddJob("loveParty", function()
            if os.clock() > state.lovePartyUntil or not valid(pawn) or not state.wLocOf then return false end
            if os.clock() < nextAt then return true end
            nextAt = os.clock() + 2.0
            local me = state.wLocOf(pawn)
            if not me then return true end
            local done = 0
            for _, n2 in ipairs(npcList()) do
                if done >= 25 then break end
                local l = valid(n2) and state.wLocOf(n2)
                local k2 = l and OK.keyOf(n2)
                if l and state.wDist(l, me) < (CFG.FREE_LOVE_SPREAD_RANGE or 3500) and not (state.deadChar and state.deadChar(n2))
                    and (state.dancers[k2] or 0) < os.clock() - 9 then
                    if pcall(function() mental:ActivateAbilityEffectOnTarget(cls, n2) end) then
                        state.dancers[k2] = os.clock()
                        done = done + 1
                    end
                end
            end
            return true
        end)
    end
    local level = 0
    local mgr = nil
    pcall(function() mgr = FindFirstOf("GameStateBase"):GetAlertSystemManager() end)
    pcall(function() level = mgr:GetCurrentResponseLevelIndex() end)
    local needed = (level or 0) * CFG.FREE_LOVE_PER_LEVEL
    if level and level > 0 and count >= needed then
        pcall(function() mgr:SetResponseLevelIndex(0, true) end)
        state.dancers = {}
        wlog("P%d Free Love: %d dancing, wanted level cleared", i, count)
    else
        wlog("P%d Free Love: %d dancing now (%d of %d to clear wanted level %d)%s", i, n, count, needed, level or 0,
            cls and "" or " - the dance ability wasn't found")
    end
end
-- Shared helpers for the bigger powers ------------------------------------------------------
local function locOf(a)
    local ok, l = pcall(function() return a:K2_GetActorLocation() end)
    if ok and l then return { X = l.X, Y = l.Y, Z = l.Z } end
    return nil
end
local function isNPC(a) return valid(a) and OK.nameOf(a):find("NPC") ~= nil end
local function kill(n, pawn)
    if state.gameDamage then pcall(state.gameDamage, n, 100000, pawn) return end
    pcall(function() OK.getStatics():ApplyDamage(n, 100000, pawn:GetController(), pawn, StaticFindObject("/Script/Engine.DamageType")) end)
end
local function hurt(n, amount, pawn)
    local before = (amount < 10000) and OK.healthRatio(n) or nil
    if state.gameDamage then pcall(state.gameDamage, n, amount, pawn) end
    -- when the game's damage didn't take (most powers' hits did nothing to people), take it
    -- off their health directly: about 120 damage = a whole person
    if type(before) == "number" and amount > 1 then
        local after = OK.healthRatio(n)
        if type(after) == "number" and after >= before - 0.001 then
            local left = before - math.min(0.9, amount / (CFG.HURT_FULL_HEALTH or 120))
            if left > 0.02 then pcall(function() OK.setRatio(OK.stat(n, "m_pHealthStat"), left) end)
            elseif state.gameDamage then pcall(state.gameDamage, n, 99999, pawn) end
        end
    end
end
-- damage that always shows: take a share of their health; the last share kills through the game
local function sliceHurt(n, frac, pawn)
    local hp = OK.healthRatio(n)
    if type(hp) == "number" and hp - frac > 0.02 then
        pcall(function() OK.setRatio(OK.stat(n, "m_pHealthStat"), hp - frac) end)
        hurt(n, 1, pawn)   -- so they react and know who did it
    else
        hurt(n, 99999, pawn)
    end
end

-- the trick that makes people go limp: the game's own PK grab and instant let-go
local limpAt = {}
local function goLimp(n)
    local k = OK.keyOf(n)
    if limpAt[k] and os.clock() - limpAt[k] < 2.5 then return end
    limpAt[k] = os.clock()
    pcall(function() n:OnPKPickUp() end)
    after(0.05, function() if valid(n) then pcall(function() n:OnPKDrop() end) end end)
end
local isLimp
isLimp = function(n)
    local ok, sim = pcall(function() return n.Mesh:IsSimulatingPhysics(FName("None")) end)
    if ok and sim then return true end
    ok, sim = pcall(function() return n.Mesh:IsSimulatingPhysics() end)
    return ok and sim or false
end
state.wIsLimp = isLimp
-- throw a person or a car with a speed (cm/s); people go limp so they really fly
local function fling(a, v, car)
    if car then
        pcall(function()
            local root = a:K2_GetRootComponent()
            root:SetSimulatePhysics(true)
            root:SetPhysicsLinearVelocity(v, false, FName("None"))
        end)
        return
    end
    if isLimp(a) then
        pcall(function() a.Mesh:SetAllPhysicsLinearVelocity(v, false) end)
    else
        goLimp(a)
        pcall(function() a:LaunchCharacter(v, true, true) end)
    end
end
local carCache, carAt = {}, -10
local function carList()
    if os.clock() - carAt > 1.0 then
        carAt = os.clock()
        carCache = {}
        pcall(function() for _, v in ipairs(FindAllOf("BFGBasicVehicle") or {}) do if valid(v) then carCache[#carCache + 1] = v end end end)
    end
    return carCache
end
-- Everything the bigger powers keep running: each job is a function(dt) that returns true to
-- keep going. Cleanups run when a job ends or the map changes.
local fx = { jobs = {}, fires = {} }
local function addJob(name, fn, cleanup) fx.jobs[#fx.jobs + 1] = { name = name, fn = fn, cleanup = cleanup } end
state.wheelAddJob = addJob
OK.onWorldChange(function() fx = { jobs = {}, fires = {} }; limpAt = {}; carCache = {} end)

-- the engine's plain sphere, used for the black hole, the bowling ball, the sentry drone and
-- the invisible "anchors" that carry the end of a lightning arc
local SPHERE = "/Engine/BasicShapes/Sphere.Sphere"
local SHAPE_MAT = "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"
local function spawnMeshActor(at, mesh)
    local ok, a = pcall(function()
        return OK.getWorld():SpawnActor(StaticFindObject("/Script/Engine.StaticMeshActor"), at, { Pitch = 0, Yaw = 0, Roll = 0 })
    end)
    if not (ok and valid(a)) then return nil end
    pcall(function()
        local smc = a.StaticMeshComponent
        smc:SetMobility(2)
        if mesh then smc:SetStaticMesh(mesh) end
        smc:SetCollisionEnabled(0)
    end)
    return a
end
local function sphereMesh()
    local m = StaticFindObject(SPHERE)
    if not valid(m) then pcall(function() m = LoadAsset(SPHERE) end) end
    return valid(m) and m or nil
end
local function spawnSphere(at, scale, color)
    local mesh = sphereMesh()
    if not mesh then return nil end
    local a = spawnMeshActor(at, mesh)
    if not a then return nil end
    pcall(function() a:SetActorScale3D({ X = scale, Y = scale, Z = scale }) end)
    pcall(function() a.StaticMeshComponent:SetCollisionEnabled(0) end)
    -- the plain shapes only ever showed up black or grey: kept for the powers' workings but
    -- not drawn, unless SHOW_SPHERES is switched on
    if not CFG.SHOW_SPHERES then pcall(function() a:SetActorHiddenInGame(true) end) end
    local holo = color and StaticFindObject(CFG.CLOAK_MATERIAL ~= "" and CFG.CLOAK_MATERIAL or "/Game/VFX/Materials/Meshes/M_Hologram_01.M_Hologram_01")
    if color and valid(holo) and CFG.GLOW_SPHERES ~= false then
        pcall(function()
            local mid = a.StaticMeshComponent:CreateDynamicMaterialInstance(0, holo)
            local glowC = (color.R + color.G + color.B < 0.1) and { R = 0.5, G = 0.1, B = 1.0, A = 1 } or color   -- "black" = deep purple
            mid:SetScalarParameterValue(FName("Hologram_Opacity"), CFG.SPHERE_OPACITY or 0.55)
            mid:SetScalarParameterValue(FName("HoloLine_Opacity"), 1.0)
            mid:SetScalarParameterValue(FName("HoloLine_GapOpacity"), CFG.SPHERE_OPACITY or 0.55)
            mid:SetScalarParameterValue(FName("Hologram_Emissive"), CFG.SPHERE_GLOW or 15)
            mid:SetVectorParameterValue(FName("Holo_TintColor"), glowC)
            pcall(function() mid:SetVectorParameterValue(FName("Holo_BaseColor"), glowC) end)
            local plain = StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
            if valid(plain) then pcall(function() mid:SetTextureParameterValue(FName("Holo_BaseColor"), plain) end) end
        end)
    elseif color then
        pcall(function()
            local smc = a.StaticMeshComponent
            local parent = StaticFindObject(SHAPE_MAT)
            if not valid(parent) then pcall(function() parent = LoadAsset(SHAPE_MAT) end) end
            if not valid(parent) then parent = smc:GetMaterial(0) end
            local mid = smc:CreateDynamicMaterialInstance(0, parent)
            mid:SetVectorParameterValue(FName("Color"), color)
        end)
    end
    return a
end
local function scaleTo(a, s) if valid(a) then pcall(function() a:SetActorScale3D({ X = s, Y = s, Z = s }) end) end end
local function moveTo(a, l) if valid(a) and l then pcall(function() a:K2_SetActorLocation(l, false, {}, true) end) end end
local function destroy(a) if valid(a) then pcall(function() a:K2_DestroyActor() end) end end
local function anchor(at) return spawnMeshActor(at, nil) end
local PURPLE = { R = 0.55, G = 0.1, B = 1.0, A = 1 }
local CYANC = { R = 0.1, G = 0.9, B = 1.0, A = 1 }
local BLACK = { R = 0.0, G = 0.0, B = 0.0, A = 1 }

local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
state.wLocOf, state.wDist = locOf, dist   -- for the powers written above these helpers
local function camDir(pc)
    local okR, rot = pcall(function() return pc.PlayerCameraManager:GetCameraRotation() end)
    if not okR then return 1, 0 end
    return math.cos(math.rad(rot.Yaw)), math.sin(math.rad(rot.Yaw))
end
-- a fan of glowing orbs flying out from Crypto: where a cone power reaches
coneWave = function(pc, pawn, range, cosMin, color)
    local me = locOf(pawn)
    if not me then return end
    local fx0, fy0 = camDir(pc)
    local half = math.acos(math.max(-1, math.min(1, cosMin)))
    local base = math.atan(fy0, fx0)
    local orbs = {}
    for k = 1, CFG.WAVE_ORBS do
        local ang = base - half + (k - 1) / math.max(1, CFG.WAVE_ORBS - 1) * 2 * half
        local o = spawnSphere({ X = me.X, Y = me.Y, Z = me.Z + 20 }, 0.22, color)
        if o then orbs[#orbs + 1] = { a = o, dx = math.cos(ang), dy = math.sin(ang) } end
    end
    local t0 = os.clock()
    addJob("wave", function()
        local f = (os.clock() - t0) / CFG.WAVE_SECONDS
        if f >= 1 then return false end
        for _, o in ipairs(orbs) do
            moveTo(o.a, { X = me.X + o.dx * range * f, Y = me.Y + o.dy * range * f, Z = me.Z + 20 + math.sin(f * 3.14) * 60 })
            scaleTo(o.a, 0.22 + f * 0.25)
        end
        return true
    end, function() for _, o in ipairs(orbs) do destroy(o.a) end end)
end

-- the person nearest the middle of the screen, in front of you
local function aimedNPC(pc, pawn, range)
    local hit = cone(pc, pawn, range or 1600, 0.94)
    if #hit == 0 then return nil end
    local fx0, fy0 = camDir(pc)
    table.sort(hit, function(a, b) return a.fx * fx0 + a.fy * fy0 > b.fx * fx0 + b.fy * fy0 end)
    return hit[1].n
end
local function nearestNPC(at, range, skip)
    local best, bd = nil, range
    for _, n in ipairs(npcList()) do
        if valid(n) and not (skip and skip[OK.keyOf(n)]) and not (state.deadChar and state.deadChar(n)) then
            local l = locOf(n)
            if l then
                local d = dist(l, at)
                if d < bd then best, bd = n, d end
            end
        end
    end
    return best, bd
end
local ENEMY_WORDS = { "Enemy", "Police", "Soldier", "Military", "Agent", "Majestic", "Army", "Cop", "Guard" }
local function isEnemy(n)
    local nmn = OK.nameOf(n)
    for _, w in ipairs(ENEMY_WORDS) do if nmn:find(w) then return true end end
    return false
end
local function playerKeys()
    local t = {}
    for _, pc in ipairs(controllers()) do local pw = getPawn(pc); if valid(pw) then t[OK.keyOf(pw)] = true end end
    return t
end
-- make someone actually run off (the AI's own move order left them running on the spot):
-- push them along the ground away from a point, facing where they run
-- an animation may only play on a body with the same skeleton (a male animation on a female
-- body crashed the game)
local function animFits(n, anim)
    local ok, same = pcall(function()
        local sk1 = n.Mesh.SkeletalMesh.Skeleton
        local sk2 = anim:GetSkeleton()
        if not (valid(sk1) and valid(sk2)) then return false end
        return OK.keyOf(sk1) == OK.keyOf(sk2)
    end)
    if not ok then
        ok, same = pcall(function() return OK.keyOf(n.Mesh.SkeletalMesh.Skeleton) == OK.keyOf(anim.Skeleton) end)
    end
    return ok and same or false
end
state.wAnimFits = animFits
local function runAway(n, from, seconds)
    local t0 = os.clock()
    addJob("runAway", function()
        if not valid(n) or os.clock() - t0 > seconds or (state.deadChar and state.deadChar(n)) then return false end
        if state.wIsLimp and state.wIsLimp(n) then return false end
        local l = locOf(n)
        if not (l and from) then return false end
        local dx, dy = l.X - from.X, l.Y - from.Y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        local dir = { X = dx / d, Y = dy / d, Z = 0 }
        pcall(function() n:AddMovementInput(dir, 1.0, true) end)
        pcall(function() n:K2_SetActorRotation({ Pitch = 0, Yaw = math.deg(math.atan(dir.Y, dir.X)), Roll = 0 }, false) end)
        pcall(function()
            local cm = n.CharacterMovement
            local v = cm.Velocity
            if (v.X * v.X + v.Y * v.Y) < 200 * 200 then
                local sp = CFG.RUN_AWAY_SPEED or 550
                cm.Velocity = { X = dir.X * sp, Y = dir.Y * sp, Z = v.Z }
            end
        end)
        return true
    end)
end
state.runAway = runAway
local function makeCoward(n)
    local ok = pcall(function() n:ForceCoward() end)
    if not ok then ok = pcall(function() n:ForceCoward(true) end) end
    if not state.cowardLogged then state.cowardLogged = true; wlog("make someone flee (ForceCoward): %s", tostring(ok)) end
    return ok
end
local function setOutline(n, on)
    pcall(function()
        n.Mesh:SetRenderCustomDepth(on)
        if on then n.Mesh:SetCustomDepthStencilValue(CFG.FROZEN_OUTLINE) end
    end)
end
-- a blast: everything near goes flying outward; people close in die
local function blast(c, by, radius, skipKey)
    local skip = playerKeys()
    if skipKey then skip[skipKey] = true end
    local n = 0
    local function one(a, car)
        local l = locOf(a)
        if not l then return end
        local d = math.max(1, dist(l, c))
        if d > radius then return end
        local sp = 2600 * (1.2 - d / radius)
        local dx, dy, dz = l.X - c.X, l.Y - c.Y, l.Z - c.Z
        fling(a, { X = dx / d * sp, Y = dy / d * sp, Z = 900 }, car)
        if car then hurt(a, d < radius * 0.5 and 100000 or 200, by)
        elseif d < radius * 0.5 then kill(a, by) else hurt(a, 60, by) end
        n = n + 1
    end
    for _, a in ipairs(npcList()) do if valid(a) and not skip[OK.keyOf(a)] then one(a, false) end end
    for _, v in ipairs(carList()) do if valid(v) and not skip[OK.keyOf(v)] then one(v, true) end end
    return n
end
-- a ring of lightning: arcs from a centre to anchors spinning round it
local function lightningRing(centerFn, count, radiusFn, seconds, height, stopFn)
    local anchors = {}
    local c = centerFn()
    if not c then return end
    for k = 1, count do
        local a = anchor(c)
        if a then
            anchors[#anchors + 1] = a
            arcTo(nil, a, seconds, { fromFn = centerFn, attack = true })   -- the effect itself (shockwave, black hole)
        end
    end
    local t0 = os.clock()
    addJob("ring", function(dt)
        local now = os.clock() - t0
        local cc = centerFn()
        if not cc or now > seconds or (stopFn and stopFn()) then return false end
        local r = radiusFn(now / seconds)
        for k, a in ipairs(anchors) do
            local ang = (k / #anchors) * 2 * math.pi + now * 4
            moveTo(a, { X = cc.X + math.cos(ang) * r, Y = cc.Y + math.sin(ang) * r, Z = cc.Z + (height or 0) + math.sin(now * 6 + k) * 40 })
        end
        return true
    end, function() for _, a in ipairs(anchors) do destroy(a) end end)
end

------------------------------------------------------------------------------------------
-- Who's under a power: the power's icon floats over their head on both players' screens,
-- and a coloured lightning link runs from Crypto to them while it lasts.
------------------------------------------------------------------------------------------
local POWER_COLOR = {
    ["Riot Hysteria"] = { R = 1.0, G = 0.15, B = 0.1 },  ["Overload Mutation"] = { R = 0.3, G = 1.0, B = 0.2 },
    ["Kinetic Overload"] = { R = 0.6, G = 0.2, B = 1.0 }, ["Cryokinesis"] = { R = 0.3, G = 0.9, B = 1.0 },
    ["Pyrokinesis"] = { R = 1.0, G = 0.5, B = 0.05 },     ["Free Love"] = { R = 1.0, G = 0.4, B = 0.8 },
    ["Free Fear"] = { R = 1.0, G = 0.9, B = 0.1 },        ["Zero-G Cone"] = { R = 0.9, G = 0.9, B = 1.0 },
    ["Psychic Tether"] = { R = 1.0, G = 0.75, B = 0.2 },  ["Body Snatch"] = { R = 0.2, G = 1.0, B = 0.6 },
    ["Smitten"] = { R = 1.0, G = 0.6, B = 0.85 },         ["Mind Flash"] = { R = 1.0, G = 1.0, B = 0.6 },
    ["Super Baller Disc"] = { R = 0.6, G = 0.2, B = 1.0 }, ["Furon Sentry Probe"] = { R = 0.3, G = 0.9, B = 1.0 },
}
local function tintArc(a, c)
    if not (valid(a) and c) then return end
    local lc = { R = c.R, G = c.G, B = c.B, A = 1.0 }
    for _, part in ipairs({ "Lightning_Beam", "Lightning_Beam_2", "PFX_Zap-o-Matic_permanent_01", "PFX_hit_loop_01" }) do
        local comp = nil
        pcall(function() comp = a[part] end)
        if comp and valid(comp) then
            for _, pn in ipairs({ "Color", "BeamColor", "Colour", "Tint", "LightningColor", "ColorParam" }) do
                pcall(function() comp:SetColorParameter(FName(pn), lc) end)
                pcall(function() comp:SetVectorParameter(FName(pn), { X = c.R, Y = c.G, Z = c.B }) end)
            end
        end
    end
end
local function isPlayerPawn(a)
    for _, pc in ipairs(controllers()) do if valid(a) and OK.keyOf(getPawn(pc)) == OK.keyOf(a) then return true end end
    return false
end
-- Lightning from Crypto to whoever a power hit is off (it got confusing); the labels over
-- heads say who's affected. Lightning between two NPCs (Hysteria spreading) stays.
local function link(from, n, seconds, power)
    if not CFG.POWER_ARCS and isPlayerPawn(from) then return nil end
    local a = arcTo(from, n, seconds)
    tintArc(a, POWER_COLOR[power])
    return a
end
-- Labels over affected people: a word in the world (the engine's text actor), one per
-- player, each seen only by that player and turned to face their camera.
local MARK_TEXT = {
    ["Riot Hysteria"] = "BERSERK", ["Overload Mutation"] = "OVERLOAD", ["Kinetic Overload"] = "BOUNCY",
    ["Pyrokinesis"] = "BURNING", ["Free Fear"] = "SCARED", ["Free Love"] = "GROOVY", ["Cryokinesis"] = "FROZEN",
    ["Zero-G Cone"] = "FLOATING", ["Psychic Tether"] = "TETHERED", ["Psychic Ragdoll"] = "LIMP",
    ["Smitten"] = "SMITTEN", ["Mind Flash"] = "STUNNED", ["Super Baller Disc"] = "DISLOCATED", ["Furon Sentry Probe"] = "MARKED",
}
local marks = {}       -- npc key -> { n, power, untilT, labels = { [slot] = textActor } }
local textClass = nil
local function destroyLabels(m)
    for _, a in pairs(m.labels or {}) do if valid(a) then pcall(function() a:K2_DestroyActor() end) end end
    m.labels = {}
end
OK.onWorldChange(function() marks = {}; textClass = nil end)
-- Player 2 leaves: take down Player 2's menu pieces and labels so a rejoin starts clean
if OK.state.onP2Leave then
    OK.state.onP2Leave(function()
        local p = P[2]
        for _, w in ipairs({ p.overlay, p.panel }) do
            if w and valid(w) then pcall(function() w:RemoveFromParent() end) end
        end
        p.overlay, p.panel, p.cards, p.cells = nil, nil, nil, nil
        p.open, p.pending, p.inputOff = false, nil, nil
        -- and everything that pointed at Player 2's old body
        p.lockSaved, p.sentry, p.dome, p.cloakT, p.cloakOn = nil, nil, nil, nil, nil
        p.cloakStop = true
        p.tetherFirst, p.powerLabel, p.ltWas, p.down = nil, nil, nil, nil
        for k, v in pairs(p) do
            if type(v) == "userdata" then p[k] = nil end
        end
        for _, m in pairs(marks) do
            local a = m.labels and m.labels[2]
            if a and valid(a) then pcall(function() a:K2_DestroyActor() end) end
            if m.labels then m.labels[2] = nil end
        end
    end)
end
local function newLabel(owner, text, color)
    textClass = textClass or StaticFindObject("/Script/Engine.TextRenderActor")
    if not valid(textClass) then return nil end
    local ok, a = pcall(function() return OK.getWorld():SpawnActor(textClass, { X = 0, Y = 0, Z = -100000 }, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
    if not (ok and valid(a)) then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    pcall(function() a:SetOwner(owner) end)
    local tr = subObj(a, "TextRender")
    if tr then
        pcall(function() tr:SetOnlyOwnerSee(true) end)
        pcall(function() tr:SetWorldSize(CFG.MARK_TEXT_SIZE) end)
        pcall(function() tr:SetHorizontalAlignment(1) end)
        pcall(function() tr:SetTextRenderColor({ R = math.floor(color.R * 255), G = math.floor(color.G * 255), B = math.floor(color.B * 255), A = 255 }) end)
        pcall(function() tr:K2_SetText(FText(text)) end)
    end
    return a
end
mark = function(n, power, seconds)
    if not valid(n) then return end
    local k = OK.keyOf(n)
    local m = marks[k]
    local untilT = os.clock() + seconds
    if m and m.power == power then m.untilT = math.max(m.untilT, untilT) return end
    if m then destroyLabels(m) end
    local count = 0
    for _ in pairs(marks) do count = count + 1 end
    if count >= CFG.MARK_MAX then return end
    marks[k] = { n = n, power = power, untilT = untilT, labels = {} }
end
unmark = function(n)
    if not valid(n) then return end
    local k = OK.keyOf(n)
    if marks[k] then destroyLabels(marks[k]); marks[k] = nil end
end
local function marksTick()
    local now = os.clock()
    local views = {}
    for slot, pc in ipairs(controllers()) do
        local okR, rot = pcall(function() return pc.PlayerCameraManager:GetCameraRotation() end)
        views[slot] = { pc = pc, pawn = getPawn(pc), yaw = okR and rot.Yaw or 0 }
    end
    for k, m in pairs(marks) do
        if now >= m.untilT or not valid(m.n) or (state.deadChar and state.deadChar(m.n)) then
            destroyLabels(m)
            marks[k] = nil
        else
            local l = locOf(m.n)
            if l then
                local pos = { X = l.X, Y = l.Y, Z = l.Z + CFG.MARK_HEIGHT }
                for slot, v in ipairs(views) do
                    local a = m.labels[slot]
                    if not valid(a) and valid(v.pawn) then
                        a = newLabel(v.pawn, MARK_TEXT[m.power] or m.power, POWER_COLOR[m.power] or { R = 1, G = 1, B = 1 })
                        m.labels[slot] = a
                    end
                    if valid(a) then
                        pcall(function()
                            a:K2_SetActorLocation(pos, false, {}, true)
                            a:K2_SetActorRotation({ Pitch = 0, Yaw = v.yaw + 180, Roll = 0 }, false)
                        end)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------------------------
-- Black Hole PK: whatever you hold with PK becomes the black hole. It's let go and pinned
-- where it is; a black sphere and a whirl of lightning mark it; people, cars and junk slam
-- into it; then it blows.
local function pkAbility(pawn)
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    if not mental then return nil end
    for _, ab in ipairs(state.p2Abilities(mental)) do
        if valid(ab) and OK.nameOf(ab):find("kinesis") then return ab end
    end
    return nil
end
local function letGo(ab, target)
    if not pcall(function() ab:ForceStop() end) then pcall(function() ab:OnObjectReleased() end) end
    if isNPC(target) then pcall(function() target:OnPKDrop() end) end
end
local function pin(t, c)
    pcall(function()
        local root = t:K2_GetRootComponent()
        root:SetPhysicsLinearVelocity({ X = 0, Y = 0, Z = 0 }, false, FName("None"))
        root:SetPhysicsAngularVelocity({ X = 0, Y = 0, Z = 0 }, false, FName("None"))
    end)
    pcall(function() t.Mesh:SetAllPhysicsLinearVelocity({ X = 0, Y = 0, Z = 0 }, false) end)
    pcall(function() t:K2_SetActorLocation(c, false, {}, true) end)
    pcall(function() t.Mesh:K2_SetWorldLocation(c, false, {}, true) end)
end
CAST.blackhole = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    local ab = pkAbility(pawn)
    local t = nil
    if ab then pcall(function() local h = ab.m_pActiveTarget; if valid(h) then t = h end end) end
    if not t then wlog("P%d Black Hole PK: hold something with PK first", i) return end
    if not spend(p, 3) then wlog("P%d: not enough concentration", i) return end
    local c = locOf(t)
    if not c then return end
    letGo(ab, t)
    pcall(function() subObj(t, "CharacterMovement"):DisableMovement() end)
    local hk = OK.keyOf(t)
    local core = spawnSphere(c, 0.4, BLACK)
    -- the Quantum Deconstructor's purple swirl on the core
    -- the look (Keaton's picks from the effect catalog): the Ion Detonator's trail (145) big,
    -- with the brain-extract ripple (32) pulsing round it; it blows with the PSI brain blast (37) x10
    if core then
        local comp = core.StaticMeshComponent
        local trail = playFx("/Game/VFX/PFX/Gameplay/Weapons/PFX_IonDetoProjectileTrail.PFX_IonDetoProjectileTrail", nil, CFG.BLACK_HOLE_TRAIL_SCALE or 4.0, comp)
        -- the long trail must never outlive the black hole: gone after 7 s whatever happens
        after(CFG.BLACK_HOLE_FX_MAX or 7.0, function()
            if trail and valid(trail) then
                pcall(function() trail:DeactivateSystem() end)
                pcall(function() trail:SetVisibility(false, true) end)
                pcall(function() trail:SetHiddenInGame(true, true) end)
                pcall(function() trail:Deactivate() end)
                pcall(function() trail:SetTemplate(nil) end)
                pcall(function() trail:K2_DestroyComponent(trail) end)
            end
        end)
        local pulseAt, bh0 = 0, os.clock()
        addJob("blackholeLook", function()
            if not valid(core) or os.clock() - bh0 > CFG.BLACK_HOLE_SECONDS + 1.5 then
                if trail and valid(trail) then
                    pcall(function() trail:DeactivateSystem() end); pcall(function() trail:Deactivate() end)
                    pcall(function() trail:SetTemplate(nil) end); pcall(function() trail:K2_DestroyComponent(trail) end)
                end
                return false
            end

            return true
        end)
    end
    local t0, hits, arcsAt = os.clock(), 0, 0
    local function centerFn() return c end
    lightningRing(centerFn, 6, function(f) return 420 * (1 - f) + 90 end, CFG.BLACK_HOLE_SECONDS, 0)
    wlog("P%d Black Hole PK on %s%s", i, OK.nameOf(t), core and "" or " (no sphere model)")
    addJob("blackhole", function(dt)
        local now = os.clock()
        local age = now - t0
        if valid(t) then pin(t, c) end
        scaleTo(core, 0.9 + 0.25 * math.sin(age * 14) + age * 0.25)
        if valid(core) then pcall(function() core:K2_SetActorRotation({ Pitch = age * 300, Yaw = age * 520, Roll = 0 }, false) end) end
        local R = CFG.BLACK_HOLE_RANGE
        local pulled = {}
        local skip = playerKeys()
        local function pull(a, car)
            local l = locOf(a)
            if not l then return end
            local d = dist(l, c)
            if d > R then return end
            if d < (car and 320 or 170) then hits = hits + (car and 3 or 1); if not car then hurt(a, 30, pawn) end; return end
            local speed = CFG.BLACK_HOLE_PULL * (0.6 + 0.8 * (1 - d / R))
            local dx, dy, dz = c.X - l.X, c.Y - l.Y, c.Z - l.Z
            fling(a, { X = dx / d * speed, Y = dy / d * speed, Z = dz / d * speed + (d > 400 and 200 or 0) }, car)
            pulled[#pulled + 1] = a
        end
        for _, n in ipairs(npcList()) do if valid(n) and OK.keyOf(n) ~= hk and not skip[OK.keyOf(n)] then pull(n, false) end end
        for _, v in ipairs(carList()) do if valid(v) and OK.keyOf(v) ~= hk then pull(v, true) end end
        if valid(t) and hits > 0 then hurt(t, hits * 25, pawn); hits = 0 end
        if now >= arcsAt then
            arcsAt = now + 0.4
            for k, a in ipairs(pulled) do if k <= 4 then arcTo(nil, a, 0.35, { fromFn = centerFn }) end end
        end
        if age < CFG.BLACK_HOLE_SECONDS then return true end
        -- it blows: the core swells and bursts, everything near goes flying
        local n = blast(c, pawn, 1000, hk)
        if valid(t) then
            pcall(function() subObj(t, "CharacterMovement"):SetMovementMode(3, 0) end)
            kill(t, pawn)
            pcall(function() t:K2_GetRootComponent():SetSimulatePhysics(true) end)
        end
        local burst = 0
        addJob("blackholeBurst", function(dt2)
            burst = burst + dt2
            scaleTo(core, 1.5 + burst * 30)
            return burst < 0.25
        end, function() destroy(core) end)
        lightningRing(centerFn, 8, function(f) return 100 + f * 900 end, 0.5, 0)
        pcall(function() local bc = centerFn(); if bc then playFx("/Game/VFX/PFX/Gameplay/MentalAbilities/BrainExtract/PFX_BrainExtractPSI_Explode.PFX_BrainExtractPSI_Explode", bc, CFG.BLACK_HOLE_BLAST_SCALE or 10.0) end end)
        wlog("Black Hole PK blew: %d thrown", n)
        return false
    end, function() end)
end

------------------------------------------------------------------------------------------
-- Pyrokinesis: set the person in front of you on fire; they panic and run, burn down, and
-- the fire spreads to anyone close to them
-- Uses the game's own fire on people (it does the damage and the flames). They panic and
-- run screaming; anyone who comes close catches it; after a while the fire goes out.
local function ignite(n, by)
    local k = OK.keyOf(n)
    if fx.fires[k] then return false end
    pcall(function() n.m_fFireDamagePerSecond = CFG.PYRO_DPS end)   -- gentler than the game's own
    pcall(function() n:OnSetOnFire() end)   -- the game's own burning (they run and flail)
    -- flames left on the ground where it started (catalog 27, the Armquist mech's flames), at most
    -- one every 2 s so crowds stay smooth
    if CFG.PYRO_GROUND_FLAMES and os.clock() >= (state.pyroGroundAt or 0) then
        state.pyroGroundAt = os.clock() + 2.0
        local l = state.wLocOf and state.wLocOf(n)
        if l then pcall(playFx, "/Game/VFX/PFX/Gameplay/Weapons/Mech/PFX_ArmquistRemainingFlames.PFX_ArmquistRemainingFlames", { X = l.X, Y = l.Y, Z = l.Z - 80 }, CFG.PYRO_GROUND_SCALE or 1.0) end
    end
    mark(n, "Pyrokinesis", CFG.PYRO_SECONDS)
    fx.fires[k] = { n = n, by = by, untilT = os.clock() + CFG.PYRO_SECONDS, spreadAt = os.clock() + 0.3 }
    return true
end
CAST.pyro = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    local n = aimedNPC(pc, pawn, 1600)
    if not n then wlog("P%d Pyrokinesis: nobody in front of you", i) return end
    if not spend(p, 2) then wlog("P%d: not enough concentration", i) return end
    link(pawn, n, 0.8, "Pyrokinesis")
    ignite(n, pawn)
    wlog("P%d Pyrokinesis on %s", i, OK.nameOf(n))
end
local function fireTick(f, dt)
    local now = os.clock()
    if not valid(f.n) then return false end
    if state.deadChar and state.deadChar(f.n) then return false end
    -- the burn itself: a share of health every second (the game's fire alone barely hurt them)
    if now >= (f.burnAt or 0) then
        f.burnAt = now + 1.0
        sliceHurt(f.n, CFG.PYRO_BURN_SLICE or 0.15, f.by)
    end
    if now >= f.spreadAt then
        f.spreadAt = now + 1.0   -- once a second (every 0.3 s per burning person was too heavy in crowds)
        local c = locOf(f.n)
        local count = 0
        for _ in pairs(fx.fires) do count = count + 1 end
        if c and count < CFG.PYRO_MAX then
            -- catching it by touch: anyone right next to a burning person
            for _, n2 in ipairs(npcList()) do
                if valid(n2) and not fx.fires[OK.keyOf(n2)] and not isPlayerPawn(n2) and not (state.deadChar and state.deadChar(n2)) then
                    local l = locOf(n2)
                    if l and dist(l, c) < CFG.PYRO_SPREAD then ignite(n2, f.by) end
                end
            end
        end
    end
    if now >= f.untilT then
        -- burnt out: the flames go out (the game's own "extinguished")
        pcall(function() f.n:OnFireExinguished() end)
        return false
    end
    return true
end

------------------------------------------------------------------------------------------
-- Kinetic Overload. Tap LT: bouncy curse (the person you aim at can't stop bouncing).
-- Hold LT: a purple psychic bowling ball grows in front of you; let go to roll it. People
-- in its way fall like pins.
CAST.kinetic = function(i, p, pc, pawn, pressed, held, dt)
    local me = locOf(pawn)
    if not me then return end
    local fx0, fy0 = camDir(pc)
    if pressed then p.kin = { t = 0 } end
    local k = p.kin
    if not k then return end
    if held then
        k.t = k.t + dt
        if k.t > 0.3 then
            local size = math.min(CFG.BALL_SIZE, 0.6 + (k.t - 0.3) * 1.8)
            k.size = size
            local at = { X = me.X + fx0 * (120 + 50 * size), Y = me.Y + fy0 * (120 + 50 * size), Z = me.Z - 40 + 50 * size }
            if not valid(k.ball) then k.ball = spawnSphere(at, size, PURPLE) end
            moveTo(k.ball, at); scaleTo(k.ball, size)
            p.powerLabel = string.format("Kinetic Overload  %s", string.rep("|", math.floor(size / CFG.BALL_SIZE * 6 + 0.5)))
        end
        return
    end
    -- let go
    p.kin, p.powerLabel = nil, nil
    if k.t <= 0.3 then
        -- tap: bouncy curse
        local n = aimedNPC(pc, pawn, 1800)
        if not n then wlog("P%d bouncy curse: nobody in front of you", i) return end
        if not spend(p, 2) then wlog("P%d: not enough concentration", i) return end
        link(pawn, n, 1.0, "Kinetic Overload")
        mark(n, "Kinetic Overload", 6)
        setOutline(n, true)
        local t0, nextB, bounces = os.clock(), 0, 0
        addJob("bouncy", function()
            local now = os.clock()
            if not valid(n) then return false end
            if now >= t0 + nextB then
                nextB = nextB + 0.75
                bounces = bounces + 1
                local a = math.random() * 2 * math.pi
                pcall(function() n:LaunchCharacter({ X = math.cos(a) * 250, Y = math.sin(a) * 250, Z = 950 }, true, true) end)
                if bounces > 1 then hurt(n, 12, pawn) end
            end
            return now - t0 < 6
        end, function() if valid(n) then setOutline(n, false) end end)
        wlog("P%d bouncy curse on %s", i, OK.nameOf(n))
        return
    end
    if not spend(p, 3) then destroy(k.ball); wlog("P%d: not enough concentration", i) return end
    local size = k.size or 1
    local pos = { X = me.X + fx0 * (120 + 50 * size), Y = me.Y + fy0 * (120 + 50 * size), Z = me.Z - 40 + 50 * size }
    local ball = valid(k.ball) and k.ball or spawnSphere(pos, size, PURPLE)
    local hitAt, spin, t0, n, arcsAt = {}, 0, os.clock(), 0, 0
    local skip = playerKeys()
    local speed = CFG.BALL_SPEED * (0.8 + size / CFG.BALL_SIZE * 0.5)
    wlog("P%d Kinetic Overload: ball rolling (size %.1f)", i, size)
    addJob("ball", function(dt2)
        local now = os.clock()
        pos.X = pos.X + fx0 * speed * dt2
        pos.Y = pos.Y + fy0 * speed * dt2
        spin = spin - speed * dt2 / (50 * size) * 57.3
        moveTo(ball, pos)
        if valid(ball) then pcall(function() ball:K2_SetActorRotation({ Pitch = spin, Yaw = math.deg(math.atan(fy0, fx0)), Roll = 0 }, false) end) end
        local reach = 50 * size + 70
        local function strike(a, car)
            local key = OK.keyOf(a)
            if hitAt[key] or skip[key] then return end
            local l = locOf(a)
            if not l then return end
            local dx, dy = l.X - pos.X, l.Y - pos.Y
            local r = car and reach + 200 or reach
            if dx * dx + dy * dy > r * r or math.abs(l.Z - pos.Z) > 250 + 50 * size then return end
            hitAt[key] = true
            n = n + 1
            local side = (dx * -fy0 + dy * fx0) >= 0 and 1 or -1
            if car then
                fling(a, { X = fx0 * 900 - fy0 * side * 500, Y = fy0 * 900 + fx0 * side * 500, Z = 350 }, true)
            else
                -- knocked over like a pin: limp, tipped forward and to the side, not launched
                goLimp(a)
                after(0.08, function()
                    if valid(a) then fling(a, { X = fx0 * 500 - fy0 * side * 350, Y = fy0 * 500 + fx0 * side * 350, Z = 220 }, false) end
                end)
                hurt(a, CFG.BALL_DAMAGE, pawn)
            end
            if valid(ball) and now >= arcsAt then arcsAt = now + 0.15; arcTo(ball, a, 0.25) end
        end
        for _, a in ipairs(npcList()) do if valid(a) then strike(a, false) end end
        for _, v in ipairs(carList()) do if valid(v) then strike(v, true) end end
        if now - t0 < CFG.BALL_SECONDS then return true end
        wlog("Kinetic Overload: %s %d knocked down", n >= 6 and "STRIKE!" or "", n)
        return false
    end, function() destroy(ball) end)
end

-- Free Love, the second game's way: hold LT for a love beam. Everyone in it fills up with
-- love (closer = faster); full, they fall for you and dance. Let go and the unfinished
-- ones slowly lose interest.
local LOVE_PINK = { R = 1.0, G = 0.35, B = 0.8, A = 1 }
default("FREE_LOVE_BEAM", true)          -- false = the old tap-for-a-cone Free Love
default("FREE_LOVE_FILL_SECONDS", 1.2)   -- how long in the beam (up close) until someone's in love
default("FREE_LOVE_CONE", 0.8)           -- how wide the beam is (cosine of the half-angle)
CAST.freelove = function(i, p, pc, pawn, pressed, held, dt)
    -- 1 player only when switched off for split screen (it crashed 2-player games once)
    if valid(state.p2) and not CFG.FREE_LOVE_SPLIT then
        if pressed and (p.loveNoteAt or 0) < os.clock() then p.loveNoteAt = os.clock() + 5; wlog("P%d Free Love: single player only for now", i) end
        return
    end
    if CFG.FREE_LOVE_BEAM == false then
        if not pressed or (p.loveAt or 0) > os.clock() then return end
        p.loveAt = os.clock() + 1.0
        pcall(coneWave, pc, pawn, CFG.FREE_RANGE, 0.55, LOVE_PINK)
        loveBurst(i, p, pc, pawn, (cone(pc, pawn, CFG.FREE_RANGE, 0.55)))
        return
    end
    local L = p.love
    if not held then
        if L then
            p.love, p.powerLabel = nil, nil
            -- what's left wears off over a few seconds
            local left = L.meter
            addJob("loveFade", function(dt2)
                local any = false
                for k, m in pairs(left) do
                    m = m - (dt2 or 0.1) * 0.4
                    left[k] = (m > 0) and m or nil
                    any = any or m > 0
                end
                return any and (p.love == nil)
            end)
            state.loveLeft = left
        end
        return
    end
    if not L then
        L = { meter = state.loveLeft or {}, waveAt = 0, labelAt = 0, fell = 0 }
        state.loveLeft = nil
        p.love = L
    end
    local now = os.clock()
    local cosMin = CFG.FREE_LOVE_CONE or 0.8
    if now >= L.waveAt then L.waveAt = now + 0.3; pcall(coneWave, pc, pawn, CFG.FREE_RANGE, cosMin, LOVE_PINK) end
    local me = locOf(pawn)
    local hit = cone(pc, pawn, CFG.FREE_RANGE, cosMin)
    local fell, filling = {}, 0
    state.dancers = state.dancers or {}
    for _, e in ipairs(hit) do
        local k = OK.keyOf(e.n)
        if (state.dancers[k] or -100) < now - 9 then     -- not dancing already
            local l = me and locOf(e.n)
            local d = (l and me) and math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2) or CFG.FREE_RANGE
            local speed = 1.6 - math.min(1, d / CFG.FREE_RANGE)        -- 1.6x up close, 0.6x at the edge
            local m = (L.meter[k] or 0) + (dt or 0.03) * speed / (CFG.FREE_LOVE_FILL_SECONDS or 1.2)
            if m >= 1 then
                L.meter[k] = nil
                fell[#fell + 1] = e
            else
                L.meter[k] = m
                filling = filling + 1
                if m > 0.15 then mark(e.n, "Smitten", 0.5) end
            end
        end
    end
    if #fell > 0 then
        L.fell = L.fell + #fell
        for _, e in ipairs(fell) do unmark(e.n) end
        loveBurst(i, p, pc, pawn, fell)
    end
    if now >= L.labelAt then
        L.labelAt = now + 0.25
        p.powerLabel = string.format("Free Love beam  %d falling for you, %d in love", filling, L.fell)
    end
end
-- Mind Flash (the second game's): a burst around you. People near are knocked back and
-- stunned, then run; cars near are knocked off their way and the people inside jump out.
default("MIND_FLASH", true)
default("MIND_FLASH_COST", 1)            -- dots
default("MIND_FLASH_RADIUS", 900)        -- cm
default("MIND_FLASH_STUN", 3)            -- seconds stunned
default("MIND_FLASH_PUSH", 750)          -- knockback speed
default("MIND_FLASH_COOLDOWN", 3)
local function attachedTo(n)
    local ok, par = pcall(function() return n:GetAttachParentActor() end)
    return (ok and valid(par)) and par or nil
end
local function mindFlash(i, p, pawn)
    if CFG.MIND_FLASH == false or (p.flashAt or 0) > os.clock() then return nil end
    local c = locOf(pawn)
    if not c then return nil end
    if not spend(p, CFG.MIND_FLASH_COST or 1) then return nil end
    p.flashAt = os.clock() + (CFG.MIND_FLASH_COOLDOWN or 3)
    local R = CFG.MIND_FLASH_RADIUS or 900
    pcall(lightningRing, function() local l = locOf(pawn); return l and { X = l.X, Y = l.Y, Z = l.Z - 40 } end, 6,
        function() return R * 0.5 end, 0.45, 0)
    local skip = playerKeys()
    local cars, stunned, out = {}, 0, 0
    for _, v in ipairs(carList()) do
        local l = valid(v) and not skip[OK.keyOf(v)] and locOf(v)
        if l and dist(l, c) < R + 200 then cars[OK.keyOf(v)] = { v = v, l = l } end
    end
    local stunFor = CFG.MIND_FLASH_STUN or 3
    for _, n in ipairs(npcList()) do
        if valid(n) and not skip[OK.keyOf(n)] and not (state.deadChar and state.deadChar(n)) then
            local par = attachedTo(n)
            local car = par and cars[OK.keyOf(par)]
            local l = locOf(n)
            if car then
                -- out of the car: beside it, on their feet, and off running
                local side = { X = car.l.X + (l and (l.X - car.l.X) or 0) * 0.2 + math.random(-1, 1) * 60, Y = car.l.Y + 220, Z = car.l.Z + 60 }
                pcall(function() n:K2_DetachFromActor(1, 1, 1) end)
                pcall(function() n:SetActorHiddenInGame(false) end)
                pcall(function() n:SetActorEnableCollision(true) end)
                moveTo(n, side)
                pcall(function() subObj(n, "CharacterMovement"):SetMovementMode(1, 0) end)
                makeCoward(n)
                runAway(n, c, CFG.FEAR_SECONDS or 8)
                mark(n, "Free Fear", CFG.FEAR_SECONDS or 8)
                out = out + 1
            elseif l and dist(l, c) < R then
                local dx, dy = l.X - c.X, l.Y - c.Y
                local d = math.max(1, math.sqrt(dx * dx + dy * dy))
                local sp = (CFG.MIND_FLASH_PUSH or 750) * (1.3 - d / R)
                pcall(function() n:LaunchCharacter({ X = dx / d * sp, Y = dy / d * sp, Z = 280 }, true, true) end)
                mark(n, "Mind Flash", stunFor)
                stunned = stunned + 1
                after(0.5, function()
                    if not valid(n) then return end
                    pcall(function() subObj(n, "CharacterMovement"):DisableMovement() end)
                    pcall(function() n:GetController().BrainComponent:StopLogic("Mind Flash") end)
                end)
                after(0.5 + stunFor, function()
                    if not valid(n) or (state.deadChar and state.deadChar(n)) or isLimp(n) then return end
                    pcall(function() subObj(n, "CharacterMovement"):SetMovementMode(1, 0) end)
                    pcall(function() n:GetController().BrainComponent:RestartLogic() end)
                    makeCoward(n)
                    local me = locOf(pawn)
                    if me then runAway(n, me, CFG.FEAR_SECONDS or 8) end
                end)
            end
        end
    end
    -- the cars themselves: knocked off their way (they stop driving)
    local nc = 0
    for _, car in pairs(cars) do
        local dx, dy = car.l.X - c.X, car.l.Y - c.Y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        fling(car.v, { X = dx / d * 400, Y = dy / d * 400, Z = 150 }, true)
        nc = nc + 1
    end
    wlog("P%d Mind Flash: %d stunned, %d cars hit, %d jumped out", i, stunned, nc, out)
    return stunned + out
end
state.mindFlash = mindFlash

------------------------------------------------------------------------------------------
-- Super Baller Disc: the second game's Dislocator. A purple disc skims along the ground to
-- the person you aim at, latches on and drags them along, bowling over anyone it passes,
-- then flings them and bounces to the next one nearby (harder with each bounce).
default("DISC_SPEED", 1500)          -- cm/s skimming
default("DISC_RANGE", 3000)          -- first target
default("DISC_SWITCH_RADIUS", 1500)  -- how far it looks for the next target
default("DISC_BOUNCES", 5)
default("DISC_DRAG_SECONDS", 1.0)
default("DISC_BOWL_RADIUS", 260)
default("DISC_DAMAGE", 35)           -- per bounce, +25% every bounce
default("DISC_SIZE", 0.9)
local CYLINDER = "/Engine/BasicShapes/Cylinder.Cylinder"
local function spawnDisc(at)
    local m = StaticFindObject(CYLINDER)
    if not valid(m) then pcall(function() m = LoadAsset(CYLINDER) end) end
    local a = spawnMeshActor(at, valid(m) and m or sphereMesh())
    if not a then return nil end
    local sz = CFG.DISC_SIZE or 0.9
    pcall(function() a:SetActorScale3D({ X = sz, Y = sz, Z = 0.08 }) end)
    local holo = StaticFindObject("/Game/VFX/Materials/Meshes/M_Hologram_01.M_Hologram_01")
    if valid(holo) then
        pcall(function()
            local mid = a.StaticMeshComponent:CreateDynamicMaterialInstance(0, holo)
            mid:SetScalarParameterValue(FName("Hologram_Opacity"), 0.85)
            mid:SetScalarParameterValue(FName("HoloLine_Opacity"), 1.0)
            mid:SetScalarParameterValue(FName("Hologram_Emissive"), 25)
            mid:SetVectorParameterValue(FName("Holo_TintColor"), PURPLE)
            pcall(function() mid:SetVectorParameterValue(FName("Holo_BaseColor"), PURPLE) end)
        end)
    end
    return a
end
CAST.baller = function(i, p, pc, pawn, pressed)
    if not pressed or (p.discAt or 0) > os.clock() then return end
    local me = locOf(pawn)
    if not me then return end
    if not spend(p, 2) then wlog("P%d: not enough concentration", i) return end
    p.discAt = os.clock() + 0.8
    local fx0, fy0 = camDir(pc)
    local target = aimedNPC(pc, pawn, CFG.DISC_RANGE or 3000)
    local pos = { X = me.X + fx0 * 140, Y = me.Y + fy0 * 140, Z = me.Z - 50 }
    local disc = spawnDisc(pos)
    if not disc then wlog("P%d Super Baller Disc: couldn't make the disc", i) return end
    pcall(arcTo, pawn, disc, 0.35)
    local skip = playerKeys()
    local done = {}                      -- people it already latched on to
    local bowled = {}                    -- key -> time last bowled
    local hx, hy = fx0, fy0
    local carry, bounces, spin, t0, arcAt = nil, 0, 0, os.clock(), 0
    local speed = CFG.DISC_SPEED or 1500
    local function nextTarget(from)
        local best, bd = nil, CFG.DISC_SWITCH_RADIUS or 1500
        for _, n in ipairs(npcList()) do
            local k = valid(n) and OK.keyOf(n)
            if k and not skip[k] and not done[k] and not (state.deadChar and state.deadChar(n)) then
                local l = locOf(n)
                local d = l and dist(l, from)
                if d and d < bd and math.abs(l.Z - from.Z) < 500 then best, bd = n, d end
            end
        end
        return best
    end
    wlog("P%d Super Baller Disc: off%s", i, target and (" at " .. OK.nameOf(target)) or "")
    addJob("disc", function(dt2)
        dt2 = dt2 or 0.03
        local now = os.clock()
        if now - t0 > 12 or not valid(disc) then return false end
        spin = (spin + dt2 * 900) % 360
        pcall(function() disc:K2_SetActorRotation({ Pitch = 0, Yaw = spin, Roll = 0 }, false) end)
        if carry then
            -- dragging: keep going the same way, the person stuck to the disc
            carry.t = carry.t + dt2
            pos.X, pos.Y = pos.X + hx * speed * 0.55 * dt2, pos.Y + hy * speed * 0.55 * dt2
            moveTo(disc, pos)
            if valid(carry.n) then moveTo(carry.n, { X = pos.X, Y = pos.Y, Z = pos.Z + 100 }) end
            if now >= arcAt and valid(carry.n) then arcAt = now + 0.3; pcall(link, disc, carry.n, 0.3, "Super Baller Disc") end
            -- bowling: everyone it passes gets knocked flying
            for _, n in ipairs(npcList()) do
                local k = valid(n) and OK.keyOf(n)
                if k and not skip[k] and k ~= carry.k and (bowled[k] or 0) < now - 1.0 then
                    local l = locOf(n)
                    if l and dist(l, pos) < (CFG.DISC_BOWL_RADIUS or 260) then
                        bowled[k] = now
                        local dx, dy = l.X - pos.X, l.Y - pos.Y
                        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
                        fling(n, { X = (dx / d + hx) * 700, Y = (dy / d + hy) * 700, Z = 650 }, false)
                        hurt(n, (CFG.DISC_DAMAGE or 35) * 0.5, pawn)
                    end
                end
            end
            if carry.t >= (CFG.DISC_DRAG_SECONDS or 1.0) or not valid(carry.n) then
                -- let go: fling them on, then bounce to the next one
                if valid(carry.n) then
                    pcall(function() subObj(carry.n, "CharacterMovement"):SetMovementMode(1, 0) end)
                    fling(carry.n, { X = hx * 1200, Y = hy * 1200, Z = 900 }, false)
                    hurt(carry.n, (CFG.DISC_DAMAGE or 35) * (1 + 0.25 * bounces), pawn)
                end
                carry = nil
                bounces = bounces + 1
                if bounces >= (CFG.DISC_BOUNCES or 5) then return false end
                target = nextTarget(pos)
                if not target then return false end
            end
            return true
        end
        -- skimming to the target (or straight on, picking up anyone it reaches)
        if target and (not valid(target) or (state.deadChar and state.deadChar(target))) then target = nextTarget(pos) end
        local tl = target and locOf(target)
        if tl then
            local dx, dy = tl.X - pos.X, tl.Y - pos.Y
            local d = math.max(1, math.sqrt(dx * dx + dy * dy))
            hx, hy = dx / d, dy / d
            pos.Z = pos.Z + ((tl.Z - 70) - pos.Z) * math.min(1, dt2 * 6)
            if d < 110 then
                local k = OK.keyOf(target)
                done[k] = true
                carry = { n = target, k = k, t = 0 }
                pcall(function() subObj(target, "CharacterMovement"):DisableMovement() end)
                mark(target, "Super Baller Disc", 2)
                return true
            end
        else
            target = nextTarget(pos)
            if target and dist(locOf(target) or pos, pos) > 500 and now - t0 > 0.3 then target = nil end
        end
        pos.X, pos.Y = pos.X + hx * speed * dt2, pos.Y + hy * speed * dt2
        moveTo(disc, pos)
        return now - t0 < (target and 12 or 3)
    end, function() destroy(disc) end)
end

------------------------------------------------------------------------------------------
-- Free Fear: everyone in front of you panics and runs, soldiers and agents included
CAST.freefear = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    if (p.fearAt or 0) > os.clock() then return end
    p.fearAt = os.clock() + 1.0                        -- free, but not every frame
    pcall(coneWave, pc, pawn, CFG.FREE_RANGE, 0.5, { R = 0.6, G = 0.05, B = 0.1, A = 1 })
    local hit = cone(pc, pawn, CFG.FREE_RANGE, 0.5)
    local flashed = mindFlash(i, p, pawn)
    if #hit == 0 then if not flashed then wlog("P%d Free Fear: nobody in front of you", i) end return end
    for _, e in ipairs(hit) do
        local n = e.n
        makeCoward(n)
        mark(n, "Free Fear", CFG.FEAR_SECONDS)
        -- really run: away from Crypto, with the game's own scared run (not the crouch)
        local me, nl = state.wLocOf and state.wLocOf(pawn), state.wLocOf and state.wLocOf(n)
        if me and nl then
            local dx, dy = nl.X - me.X, nl.Y - me.Y
            local d = math.max(1, math.sqrt(dx * dx + dy * dy))
            local goal = { X = nl.X + dx / d * 2500, Y = nl.Y + dy / d * 2500, Z = nl.Z }
            pcall(function() StaticFindObject("/Script/AIModule.Default__AIBlueprintHelperLibrary"):SimpleMoveToLocation(n:GetController(), goal) end)
            runAway(n, me, CFG.FEAR_SECONDS or 8)
        end
        local female = OK.nameOf(n):find("Female") ~= nil
        local runPath = female and "/Game/Animation/Characters/_human_animations/female/Alert/F_alert_run_0" .. math.random(1, 4) .. ".F_alert_run_0"
            or "/Game/Animation/Characters/_human_animations/male/alert/M_alert_run_0" .. math.random(1, 4) .. ".M_alert_run_0"
        local num = runPath:match("_0(%d)%.")
        runPath = runPath .. num
        local anim = StaticFindObject(runPath)
        if not valid(anim) then pcall(function() LoadAsset(runPath) end); anim = StaticFindObject(runPath) end
        if valid(anim) and CFG.FEAR_RUN_ANIM ~= false and state.wAnimFits and state.wAnimFits(n, anim) then pcall(function() n.Mesh:PlayAnimation(anim, true) end) end
        if not state.fearAnimLogged then state.fearAnimLogged = true; wlog("Free Fear: run animation %s", valid(anim) and OK.shortName(anim) or ("not found: " .. runPath)) end
        -- the fear wears off: their AI starts over, their own animations back (back to normal)
        after(CFG.FEAR_SECONDS, function()
            if valid(n) and not (state.deadChar and state.deadChar(n)) and not isLimp(n) then
                pcall(function() n.Mesh:SetAnimationMode(0) end)
                pcall(function() n:GetController().BrainComponent:RestartLogic() end)
            end
        end)
    end
    wlog("P%d Free Fear: %d running scared", i, #hit)
end

------------------------------------------------------------------------------------------
-- Mutant Shockwave. Hold LT to charge (3 stages); let go: a ground wave rolls out from you
-- and throws everyone it reaches into the sky.
CAST.shockwave = function(i, p, pc, pawn, pressed, held, dt)
    if pressed then p.shock = { t = 0 } end
    local s = p.shock
    if not s then return end
    if held then
        s.t = math.min(1.5, s.t + dt)
        local stage = s.t < 0.5 and 1 or (s.t < 1.0 and 2 or 3)
        if stage ~= s.stage then
            s.stage = stage
            local me = locOf(pawn)
            if me then lightningRing(function() local l = locOf(pawn); return l and { X = l.X, Y = l.Y, Z = l.Z - 60 } end, 2 + stage, function() return 80 + stage * 40 end, 0.5, 0) end
        end
        p.powerLabel = "Mutant Shockwave  " .. string.rep("|", stage * 2) .. string.rep(".", 6 - stage * 2)
        return
    end
    p.shock, p.powerLabel = nil, nil
    local stage = s.stage or 1
    if not spend(p, stage == 3 and 3 or 2) then wlog("P%d: not enough concentration", i) return end
    local c = locOf(pawn)
    if not c then return end
    c = { X = c.X, Y = c.Y, Z = c.Z - 60 }
    local maxR = 500 + stage * 350
    local up = 700 + stage * 400
    local t0, done = os.clock(), {}
    local skip = playerKeys()
    lightningRing(function() return c end, 10, function(f) return 100 + f * maxR end, 0.6, 0)
    -- something you can see: a glowing psychic dome that swells out to the blast's edge,
    -- bigger and brighter with each charge stage
    -- the psi mutants' own wave, bigger each stage; the glowing dome only if it's missing
    local wave = playFx("mutantWave", { X = c.X, Y = c.Y, Z = c.Z + 40 }, (CFG.SHOCK_WAVE_SCALE or 1.0) * (0.7 + stage * 0.6))
    playSound("pulseSound", c, 1.0)
    -- the psi mutants' ground ring is an effect actor (BP_PSYPulse_Link, their pulse's "telegraph"),
    -- not a particle file: spawn it on the spot for a moment
    pcall(function()
        local cls = gameAsset("/Game/Blueprints/Weapon/PSI/BP_PSYPulse_Link.BP_PSYPulse_Link_C")
        if not cls then if not state.ringLogged then state.ringLogged = true; wlog("Shockwave ring: BP_PSYPulse_Link not found") end return end
        local ring = OK.getWorld():SpawnActor(cls, c, { Pitch = 0, Yaw = 0, Roll = 0 })
        if not valid(ring) then return end
        local k = (CFG.SHOCK_RING_SCALE or 1.0) * (0.8 + stage * 0.5)
        pcall(function() ring:SetActorScale3D({ X = k, Y = k, Z = k }) end)
        for _, f in ipairs({ "TriggerEffect", "StartEffect", "ActivateEffect", "Activate" }) do pcall(function() ring[f](ring) end) end
        pcall(function() ring:SetTargetLocation(c) end)
        if not state.ringLogged then state.ringLogged = true; wlog("Shockwave ring: BP_PSYPulse_Link spawned") end
        after(2.5, function() if valid(ring) then pcall(function() ring:K2_DestroyActor() end) end end)
    end)
    local dome = (not wave or CFG.SHOCK_DOME) and spawnSphere(c, 1.0, { R = 0.6, G = 0.15, B = 1.0, A = 1 }) or nil
    if dome then
        pcall(function()
            local holo = StaticFindObject(CFG.CLOAK_MATERIAL ~= "" and CFG.CLOAK_MATERIAL or "/Game/VFX/Materials/Meshes/M_Hologram_01.M_Hologram_01")
            if not valid(holo) then return end
            local smc = dome.StaticMeshComponent
            smc:SetCollisionEnabled(0)
            local mid = smc:CreateDynamicMaterialInstance(0, holo)
            local tint = stage == 3 and { R = 1.0, G = 0.2, B = 0.9, A = 1 } or (stage == 2 and { R = 0.7, G = 0.2, B = 1.0, A = 1 } or { R = 0.45, G = 0.3, B = 1.0, A = 1 })
            mid:SetScalarParameterValue(FName("Hologram_Opacity"), 0.35 + stage * 0.15)
            mid:SetScalarParameterValue(FName("HoloLine_Opacity"), 1.0)
            mid:SetScalarParameterValue(FName("Hologram_Emissive"), 10 + stage * 15)
            mid:SetVectorParameterValue(FName("Holo_TintColor"), tint)
            pcall(function() mid:SetVectorParameterValue(FName("Holo_BaseColor"), tint) end)
        end)
        local d0 = os.clock()
        addJob("shockDome", function()
            local f = (os.clock() - d0) / 0.6
            if f >= 1.15 or not valid(dome) then return false end
            scaleTo(dome, math.max(0.2, math.min(1, f)) * maxR / 50)
            return true
        end, function() destroy(dome) end)
    end
    addJob("shockwave", function()
        local r = math.min(maxR, (os.clock() - t0) / 0.6 * maxR)
        local function hitIt(a, car)
            local key = OK.keyOf(a)
            if done[key] or skip[key] then return end
            local l = locOf(a)
            if not l then return end
            local dx, dy = l.X - c.X, l.Y - c.Y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > r or math.abs(l.Z - c.Z) > 400 then return end
            done[key] = true
            d = math.max(d, 1)
            fling(a, { X = dx / d * 300, Y = dy / d * 300, Z = car and up * 0.7 or up }, car)
            if not car then hurt(a, 15 + stage * 15, pawn) end
        end
        for _, a in ipairs(npcList()) do if valid(a) then hitIt(a, false) end end
        for _, v in ipairs(carList()) do if valid(v) then hitIt(v, true) end end
        return r < maxR
    end)
    local pf = psiClass("pulsefield")
    if pf then pcall(fireProjectile, pf, { X = c.X, Y = c.Y, Z = c.Z + 60 }, { X = c.X, Y = c.Y, Z = c.Z - 200 }, pawn) end
    -- what comes out of the psi mutants' grenade when it blows (not the grenade or its red
    -- warning circle): a psi grenade made right on the ground and set off at once
    pcall(function()
        local gcls = state.projClassFor and state.projClassFor("BP_ProjectilePsiGrenade_C", {}) or psiClass("psigrenade")
        if not valid(gcls) then return end
        for k = 1, stage do
            local at = { X = c.X, Y = c.Y, Z = c.Z + 20 }
            local g = OK.getWorld():SpawnActor(gcls, at, { Pitch = -90, Yaw = 0, Roll = 0 })
            if valid(g) then
                pcall(function() g:SetOwner(pawn) end)
                pcall(function() g.Instigator = pawn end)
                -- only the grenade's own body is hidden (its blast effects stay)
                pcall(function()
                    for _, m in ipairs(OK.arrayToList(g:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.MeshComponent")))) do
                        pcall(function() m:SetVisibility(false, false) end)
                    end
                end)
                local okE = pcall(function() g:OnProjectileExplosion(at, maxR) end)
                if not okE then pcall(function() g:FireProjectile(40, nil, { X = 0, Y = 0, Z = -1 }) end) end
                after(3.0, function() if valid(g) then pcall(function() g:K2_DestroyActor() end) end end)
                if not state.shockBlastLogged then state.shockBlastLogged = true; wlog("Shockwave: psi grenade blast %s", okE and "set off" or "dropped") end
            end
        end
    end)
    wlog("P%d Mutant Shockwave, stage %d%s", i, stage, pf and " (with the psi mutants' pulse field)" or "")
end

------------------------------------------------------------------------------------------
-- Chain Hysteria: the person you aim at goes berserk (switches sides and lashes out at
-- whoever is nearest); anyone they hurt goes berserk too
local berserk = {}
-- while anyone is berserk, the players are out of sight (the game's "invisible" state), so the
-- berserk ones go for each other instead of Crypto
local playersHidden = false
local function hidePlayersForHysteria(on)
    if not CFG.HYSTERIA_HIDES_PLAYERS or on == playersHidden then return end
    playersHidden = on
    if not on and state.trIgnore == "On" then return end
    for _, pc in ipairs(controllers()) do
        local pw = getPawn(pc)
        if valid(pw) then
            local inv = OK.stat(pw, "m_pIsInvisibleStat")
            if inv then
                pcall(function() inv:SetValue(on, true, true, false) end)
                pcall(function() inv:SetValue(on) end)
                pcall(function() inv.m_bValue = on end)
            end
            local ai = subObj(pw, "m_pAITargetComponent")
            if ai then if on then pcall(function() ai:Deactivate() end) else pcall(function() ai:Activate(true) end) end end
        end
    end
end
OK.onWorldChange(function() berserk = {}; playersHidden = false end)
local function goBerserk(n, by, depth)
    local key = OK.keyOf(n)
    if berserk[key] then return end
    -- never on the dead or on a limp (ragdoll) body: animating those crashed the game
    if not valid(n) or (state.deadChar and state.deadChar(n)) or isLimp(n) then return end
    local hp0 = OK.healthRatio(n)
    if type(hp0) == "number" and hp0 <= 0.01 then return end
    local count = 0
    for _ in pairs(berserk) do count = count + 1 end
    if count >= CFG.HYSTERIA_MAX then return end
    local okF, f = pcall(function() return n.m_faction end)
    local vals = {}
    pcall(function() vals = state.factionValues() or {} end)
    if okF and f ~= nil and #vals > 1 then
        -- a random side other than their own, so berserk people turn on each other too
        local pick = f
        for _ = 1, 8 do pick = vals[math.random(#vals)]; if pick ~= f then break end end
        pcall(function() n.m_faction = pick end)
    end
    hidePlayersForHysteria(true)
    setOutline(n, true)
    mark(n, "Riot Hysteria", 8)
    -- their own AI off while berserk (unarmed people only ran away), back on afterwards
    if CFG.HYSTERIA_BRAWL then pcall(function() n:GetController().BrainComponent:StopLogic("Berserk") end) end
    berserk[key] = { n = n, f = okF and f or nil }
    local t0, nextHit = os.clock(), 0.4
    addJob("berserk", function()
        local now = os.clock() - t0
        if not valid(n) or (state.deadChar and state.deadChar(n)) then return false end
        if now >= nextHit then
            nextHit = now + 0.9
            local c = locOf(n)
            local skip = playerKeys()
            skip[key] = true
            local v = c and nearestNPC(c, 900, skip)
            if v then
                link(n, v, 0.3, "Riot Hysteria")
                -- a real swing: run at them and throw the pistol men's close-up melee strike
                -- go at them: pushed toward the target for a moment (their AI is switched off)
                -- (the brawl parts crashed the game in testing: off until fixed, HYSTERIA_BRAWL)
                if CFG.HYSTERIA_BRAWL then pcall(function()
                    local vl, nl2 = locOf(v), locOf(n)
                    if vl and nl2 and dist(vl, nl2) > 120 then
                        runAway(n, { X = nl2.X - (vl.X - nl2.X), Y = nl2.Y - (vl.Y - nl2.Y), Z = nl2.Z }, 0.6)
                    end
                end) end
                local mp = CFG.HYSTERIA_SWING or "/Game/Animation/Characters/_human_animations/male/pistol_01/M_pistol_aim_melee_close.M_pistol_aim_melee_close"
                local swing = CFG.HYSTERIA_BRAWL and StaticFindObject(mp) or nil
                if CFG.HYSTERIA_BRAWL and not valid(swing) then pcall(function() LoadAsset(mp) end); swing = StaticFindObject(mp) end
                local alive = function(a) return valid(a) and not (state.deadChar and state.deadChar(a)) and not isLimp(a) end
                state.swinging = state.swinging or {}
                if CFG.HYSTERIA_BRAWL and valid(swing) and alive(n) and not state.swinging[key] and animFits(n, swing) then
                    state.swinging[key] = true
                    pcall(function() n.Mesh:PlayAnimation(swing, false) end)
                    after(0.6, function()
                        state.swinging[key] = nil
                        if valid(n) then
                            if alive(n) then pcall(function() n.Mesh:SetAnimationMode(0) end) end
                        end
                    end)
                end
                if not state.swingLogged then state.swingLogged = true; wlog("Riot Hysteria: melee swing %s", valid(swing) and "on" or "not found") end
                hurt(v, CFG.HYSTERIA_HIT or 8, by)   -- a punch, not a killing blow
                if depth < 4 and valid(v) and not (state.deadChar and state.deadChar(v)) then goBerserk(v, by, depth + 1) end
            end
        end
        return now < 8
    end, function()
        if valid(n) then
            setOutline(n, false)
            if CFG.HYSTERIA_BRAWL then pcall(function() n:GetController().BrainComponent:RestartLogic() end) end
            if berserk[key] and berserk[key].f ~= nil then pcall(function() n.m_faction = berserk[key].f end) end
        end
        berserk[key] = nil
        if next(berserk) == nil then hidePlayersForHysteria(false) end
    end)
end
CAST.hysteria = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    local n = aimedNPC(pc, pawn, 1600)
    if not n then wlog("P%d Chain Hysteria: nobody in front of you", i) return end
    if not spend(p, 2) then wlog("P%d: not enough concentration", i) return end
    link(pawn, n, 2.0, "Riot Hysteria")
    goBerserk(n, pawn, 0)
    wlog("P%d Chain Hysteria on %s", i, OK.nameOf(n))
end

------------------------------------------------------------------------------------------
-- Body Snatch: LT on someone: you take their body (the game's own Holobob disguise of
-- them) and they vanish. It drains concentration; LT again (or running dry) jumps out, and
-- they drop out next to you.
local HOLOBOB = "/Game/Blueprints/MentalAbilities/BP_MentalAbility_Holobob.BP_MentalAbility_Holobob_C"
local function hideBody(n, hide)
    pcall(function() n:SetActorHiddenInGame(hide) end)
    pcall(function() n:SetActorEnableCollision(not hide) end)
    pcall(function() local ctl = n:GetController(); if hide then ctl.BrainComponent:StopLogic("Snatched") else ctl.BrainComponent:RestartLogic() end end)
end
local function unsnatch(i, p, pawn)
    local s = p.snatch
    p.snatch = nil
    if not s then return end
    if valid(s.n) then
        local me = pawn and locOf(pawn)
        if me then moveTo(s.n, { X = me.X + 120, Y = me.Y, Z = me.Z + 40 }) end
        hideBody(s.n, false)
        goLimp(s.n)
    end
    -- the snatched body's sprint off again
    if s.walk then pcall(function() local cm = subObj(pawn, "CharacterMovement"); if cm then cm.MaxWalkSpeed = cm.MaxWalkSpeed / s.walk end end) end
    p.powerLabel = nil
    pcall(function()
        local mental = subObj(pawn, "m_pMentalAbilityComponent")
        for _, ab in ipairs(state.p2Abilities(mental)) do
            if valid(ab) and OK.nameOf(ab):find("Holo") then pcall(function() ab:ForceStop() end) end
        end
    end)
    wlog("P%d Body Snatch: jumped out", i)
end
-- Body Snatch, the second game's way: you take their look, get healed up and run faster.
-- The disguise has its own health: it wears down over time, faster while you're wanted,
-- and hits you take come off it instead of you. When it's gone, you're out.
default("SNATCH_DISGUISE_SECONDS", 75)   -- how long a disguise lasts when nobody's after you
default("SNATCH_SEEN_SECONDS", 15)       -- ...and while you're wanted
default("SNATCH_HIT_COST", 2.0)          -- disguise lost per bit of health a hit would take
default("SNATCH_SPRINT", 1.5)            -- run speed while snatched
default("SNATCH_FULL_HEAL", true)
local function wantedLevel()
    local level = 0
    pcall(function() level = FindFirstOf("GameStateBase"):GetAlertSystemManager():GetCurrentResponseLevelIndex() end)
    return level or 0
end
CAST.bodysnatch = function(i, p, pc, pawn, pressed, held, dt)
    if p.snatch then
        if pressed then unsnatch(i, p, pawn) end
        return
    end
    if not pressed then return end
    local n = aimedNPC(pc, pawn, 1200)
    if not n then wlog("P%d Body Snatch: nobody in front of you", i) return end
    if not spend(p, 1) then wlog("P%d: not enough concentration", i) return end
    local cls = mentalClass(HOLOBOB)
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    local ok = cls and mental and pcall(function() mental:ActivateAbilityEffectOnTarget(cls, n) end)
    arcTo(pawn, n, 0.6)
    after(0.4, function() if valid(n) then hideBody(n, true) end end)
    local sn = { n = n, disguise = 1.0 }
    p.snatch = sn
    local hs = OK.stat(pawn, "m_pHealthStat")
    if CFG.SNATCH_FULL_HEAL ~= false and hs then pcall(function() OK.setRatio(hs, 1.0) end) end
    local cm = subObj(pawn, "CharacterMovement")
    if cm and (CFG.SNATCH_SPRINT or 1) ~= 1 then
        local f = CFG.SNATCH_SPRINT
        if pcall(function() cm.MaxWalkSpeed = cm.MaxWalkSpeed * f end) then sn.walk = f end
    end
    local lastHP = OK.healthRatio(pawn)
    local labelAt, checkAt, wanted = 0, 0, 0
    addJob("snatch", function(dt2)
        dt2 = dt2 or 0.03
        if p.snatch ~= sn then return false end
        if not (valid(pawn) and valid(n)) then unsnatch(i, p, pawn) return false end
        local now = os.clock()
        if now >= checkAt then checkAt = now + 0.5; wanted = wantedLevel() end
        local life = (wanted > 0) and (CFG.SNATCH_SEEN_SECONDS or 15) or (CFG.SNATCH_DISGUISE_SECONDS or 75)
        sn.disguise = sn.disguise - dt2 / life
        -- hits land on the disguise, not on you
        local hp = OK.healthRatio(pawn)
        if type(hp) == "number" and type(lastHP) == "number" and hp < lastHP - 0.001 then
            sn.disguise = sn.disguise - (lastHP - hp) * (CFG.SNATCH_HIT_COST or 2.0)
            if hs then pcall(function() OK.setRatio(hs, lastHP) end) end
            hp = lastHP
        end
        lastHP = hp
        if sn.disguise <= 0 then
            wlog("P%d Body Snatch: disguise worn out", i)
            unsnatch(i, p, pawn)
            return false
        end
        if now >= labelAt then
            labelAt = now + 0.2
            local bars = math.max(0, math.floor(sn.disguise * 10 + 0.5))
            p.powerLabel = "Disguise  " .. string.rep("|", bars) .. string.rep(".", 10 - bars) .. (wanted > 0 and "  (wanted!)" or "")
        end
        return true
    end)
    wlog("P%d Body Snatch on %s (look: %s, sprint x%.1f)", i, OK.nameOf(n), tostring(ok), sn.walk or 1)
end

------------------------------------------------------------------------------------------
-- Overload Mutation: the person you aim at glows, grows, sprints off in a panic... and
-- blows up a few seconds later
-- Overload Mutation: the target glows radioactive green like Rockwell's mutant cows, and when
-- they die (however that happens) they blow up like one.
local OVERLOAD_BOOMS = {   -- the game's own explosives, tried in order; the first loaded one is used
    -- the radioactive cow: its death is the green gas blast that hurts everyone near
    "/Game/Blueprints/Character/Animals/BP_Animal_Cow_Radioactive.BP_Animal_Cow_Radioactive_C",
    "/Game/Blueprints/Items/Destructibles_Explosives/BP_Item_Explosive_RadioactiveHaybale.BP_Item_Explosive_RadioactiveHaybale_C",
    "/Game/Blueprints/Items/Destructibles_Explosives/BP_Item_Explosive_RadioactiveHaystack.BP_Item_Explosive_RadioactiveHaystack_C",
    "/Game/Blueprints/Items/Destructibles_Explosives/BP_Item_Explosive_GasBottle.BP_Item_Explosive_GasBottle_C",
    "/Game/Blueprints/Items/Destructibles_Explosives/BP_Item_Explosive_OilBarrel.BP_Item_Explosive_OilBarrel_C",
}
-- load a blueprint class by its path (tries the asset, then the class)
local function loadClass(path)
    local cls = StaticFindObject(path)
    if valid(cls) then return cls end
    pcall(function() LoadAsset(path:gsub("_C$", "")) end)
    cls = StaticFindObject(path)
    if not valid(cls) then pcall(function() LoadAsset(path) end); cls = StaticFindObject(path) end
    return valid(cls) and cls or nil
end
state.loadClass = loadClass
local function gameExplosion(at, by)
    for k, path in ipairs(OVERLOAD_BOOMS) do
        local cls = (k <= 3) and loadClass(path) or StaticFindObject(path)   -- the green ones are worth loading
        if valid(cls) then
            local ok, item = pcall(function() return OK.getWorld():SpawnActor(cls, at, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
            if ok and valid(item) then
                local hit = false
                pcall(function()
                    local dc = subObj(item, "m_pDamageComponent")
                    dc:ApplyAndReportDamage(item, 100000, by, by, StaticFindObject("/Script/Engine.DamageType"), true)
                    hit = true
                end)
                pcall(function() OK.getStatics():ApplyDamage(item, 100000, nil, by, StaticFindObject("/Script/Engine.DamageType")) end)
                if state.gameDamage then pcall(state.gameDamage, item, 100000, by) end
                -- set off its explosive part directly too (the bale only sat there before)
                pcall(function()
                    item:GetClass():ForEachProperty(function(pp)
                        local n = pp:GetFName():ToString()
                        local okV, v = pcall(function() return item[n] end)
                        if okV and valid(v) and OK.nameOf(v):find("Explosive") then
                            pcall(function() v:OnEventExplosion(false) end)
                            pcall(function() v:Explode() end)
                        end
                    end)
                end)
                if k == 1 then pcall(function() item:SetActorHiddenInGame(true) end) end   -- just the blast, not a cow
                -- whatever is left of it a moment later goes
                after(4.0, function() if valid(item) then pcall(function() item:K2_DestroyActor() end) end end)
                return path:match("([%w_]+)_C$")
            end
        end
    end
    return nil
end
local function radioactiveGlow(n)
    local light = nil
    pcall(function()
        local cls = StaticFindObject("/Script/Engine.PointLight")
        light = OK.getWorld():SpawnActor(cls, locOf(n), { Pitch = 0, Yaw = 0, Roll = 0 })
        local lc = light.PointLightComponent or light.LightComponent
        lc:SetMobility(2)
        lc:SetLightColor({ R = 0.35, G = 1.0, B = 0.2, A = 1 }, true)
        lc:SetIntensity(CFG.OVERLOAD_GLOW)
        pcall(function() lc:SetAttenuationRadius(350) end)
        light:K2_AttachToActor(n, FName("None"), 2, 1, 1, false)
    end)
    -- the cows' own green look, when a radioactive cow is around to borrow it from
    pcall(function()
        local cow = FindFirstOf("BP_Animal_Cow_Radioactive_C")
        if not valid(cow) then return end
        local cm = subObj(cow, "Mesh") or subObj(cow, "m_pSkeletonMesh")
        local mat = cm and cm:GetMaterial(0)
        if valid(mat) then
            local okN, cnt = pcall(function() return n.Mesh:GetNumMaterials() end)
            for k = 0, (okN and cnt or 1) - 1 do pcall(function() n.Mesh:SetMaterial(k, mat) end) end
            if not state.cowLookLogged then state.cowLookLogged = true; wlog("Overload: borrowed the radioactive cow's look (%s)", OK.shortName(mat)) end
        end
    end)
    return light
end
CAST.overload = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    local n = aimedNPC(pc, pawn, 1600)
    if not n then wlog("P%d Overload Mutation: nobody in front of you", i) return end
    if not spend(p, 3) then wlog("P%d: not enough concentration", i) return end
    if not state.texMarkerAt then mark(n, "Overload Mutation", CFG.OVERLOAD_SECONDS) end   -- the crosshair picture replaces the words
    setOutline(n, true)
    local light = radioactiveGlow(n)
    -- they panic and run (the scared run), then go off after OVERLOAD_FUSE seconds
    pcall(function() makeCoward(n) end)
    pcall(function()
        local me, nl = locOf(pawn), locOf(n)
        local dx, dy = nl.X - me.X, nl.Y - me.Y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        StaticFindObject("/Script/AIModule.Default__AIBlueprintHelperLibrary"):SimpleMoveToLocation(n:GetController(), { X = nl.X + dx / d * 2000, Y = nl.Y + dy / d * 2000, Z = nl.Z })
        runAway(n, me, CFG.OVERLOAD_FUSE or 5)
    end)
    local key = OK.keyOf(n)
    local t0, lastAt = os.clock(), nil
    addJob("overload", function()
        if not valid(n) then return false end
        local c = locOf(n)
        if c then lastAt = c end
        -- glowing until they die; then they go off like a mutant cow
        if state.deadChar and state.deadChar(n) then
            local at = lastAt or c
            if at then
                local fx = playFx("cowBlast", at, CFG.OVERLOAD_FX_SCALE or 1.6)
                playSound("boomSound", at, 1.0)
                local how = fx and "the radioactive cow's green blast" or gameExplosion(at, pawn)
                local cnt = blast(at, pawn, CFG.OVERLOAD_RADIUS, key)
                wlog("Overload Mutation went off (%s): %d caught in it", how or "mod blast", cnt)
            end
            return false
        end
        if os.clock() - t0 > (CFG.OVERLOAD_FUSE or 5) and not (state.deadChar and state.deadChar(n)) then
            -- the fuse runs out: they die, which sets off the blast (next frame)
            if state.gameDamage then pcall(state.gameDamage, n, 99999, pawn) end
            pcall(function() OK.setRatio(OK.stat(n, "m_pHealthStat"), 0) end)
        end
        if os.clock() - t0 > CFG.OVERLOAD_SECONDS then return false end   -- the glow fades after a while
        -- the crosshair picture (PLACEHOLDER_Crosshair_AnalProbe, viewer no. 11) on their body,
        -- on every player's screen, instead of the word label
        local shown = false
        if c and state.texMarkerAt then
            for vi, vpc in ipairs(controllers()) do
                local okM, made = pcall(state.texMarkerAt, "overload" .. key .. "_" .. vi, vpc, CFG.OVERLOAD_MARKER or "PLACEHOLDER_Crosshair_AnalProbe",
                    { X = c.X, Y = c.Y, Z = c.Z + 20 }, CFG.OVERLOAD_MARKER_SIZE or 64)
                if okM and made then shown = true end
            end
        end
        if not shown then mark(n, "Overload Mutation", 2) end
        return true
    end, function()
        if state.texMarkerHide then for vi = 1, 4 do pcall(state.texMarkerHide, "overload" .. key .. "_" .. vi) end end
        if valid(light) then pcall(function() light:K2_DestroyActor() end) end
        if valid(n) then setOutline(n, false) end
    end)
    wlog("P%d Overload Mutation on %s (glowing; blows up when they die)", i, OK.nameOf(n))
end

------------------------------------------------------------------------------------------
-- Cloak / Deflector. Tap LT: invisible for a while (enemies lose you). Hold LT: a lightning
-- dome: you take no damage and enemies shooting nearby get it reflected back. Drains while held.
local function setInvisible(pawn, on)
    local inv = OK.stat(pawn, "m_pIsInvisibleStat")
    if inv then
        pcall(function() inv:SetValue(on, true, true, false) end)
        pcall(function() inv:SetValue(on) end)
        pcall(function() inv.m_bValue = on end)
    end
    local ai = subObj(pawn, "m_pAITargetComponent")
    if ai then if on then pcall(function() ai:Deactivate() end) else pcall(function() ai:Activate(true) end) end end
    if not on then pcall(function() pawn.Mesh:SetVisibility(true, true) end) end
end
-- cloaked look, no blinking. With CFG.CLOAK_MATERIAL set (a see-through material from the
-- game, like the hologram one), Crypto wears it. Otherwise Crypto's body is drawn only in
-- your own view: you still see yourself, your partner and the people around you don't.
local cloakSaved = {}
local function cloakLook(pawn, on)
    local mesh = valid(pawn) and subObj(pawn, "Mesh")
    if not mesh then return end
    local key = OK.keyOf(pawn)
    if on then
        local mat = nil
        if CFG.CLOAK_MATERIAL ~= "" then
            mat = StaticFindObject(CFG.CLOAK_MATERIAL)
            if not valid(mat) then mat = nil end
        end
        if mat then
            local saved = {}
            local okN, n = pcall(function() return mesh:GetNumMaterials() end)
            -- a plain texture, so the hologram doesn't show the texture it was made with (a chicken)
            local plain = StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
            for k = 0, (okN and n or 1) - 1 do
                local okM, m = pcall(function() return mesh:GetMaterial(k) end)
                saved[k] = okM and m or nil
                -- Crypto's own colour texture, when his material says which it is
                local own = nil
                pcall(function()
                    local vals = m.TextureParameterValues
                    for j = 1, #vals do
                        local e = vals[j]
                        local nm = e.ParameterInfo.Name:ToString():lower()
                        if (nm:find("base") or nm:find("diff") or nm:find("albedo") or nm:find("color")) and not nm:find("normal") and not nm:find("mask") then
                            own = e.ParameterValue
                            break
                        end
                    end
                end)
                local okD, mid = pcall(function() return mesh:CreateDynamicMaterialInstance(k, mat) end)
                if not (okD and valid(mid)) then
                    -- second route: make the copy first, then put it on
                    okD, mid = pcall(function()
                        local m2 = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary"):CreateDynamicMaterialInstance(OK.getWorld(), mat, FName("None"))
                        mesh:SetMaterial(k, m2)
                        return m2
                    end)
                end
                if okD and valid(mid) then
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Opacity"), CFG.CLOAK_OPACITY) end)
                    pcall(function() mid:SetScalarParameterValue(FName("HoloLine_Opacity"), CFG.CLOAK_LINES) end)
                    pcall(function() mid:SetScalarParameterValue(FName("HoloLine_GapOpacity"), CFG.CLOAK_OPACITY) end)
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Emissive"), CFG.CLOAK_GLOW) end)
                    pcall(function() mid:SetVectorParameterValue(FName("Holo_TintColor"), CFG.CLOAK_TINT) end)
                    -- no shine: no reflection, a very thin edge, no bending of what's behind
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_BaseReflectFraction"), 0.0) end)
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Fresnel_Exponent"), 20.0) end)
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Refraction_Index"), 1.0) end)
                    if k == 0 and not state.cloakReadLogged then
                        state.cloakReadLogged = true
                        local okR, v = pcall(function() return mid:K2_GetScalarParameterValue(FName("Hologram_Opacity")) end)
                        local okE, e = pcall(function() return mid:K2_GetScalarParameterValue(FName("Hologram_Emissive")) end)
                        wlog("Cloak: hologram opacity now %s, glow %s (asked for %s, %s)", okR and tostring(v) or "?", okE and tostring(e) or "?",
                            tostring(CFG.CLOAK_OPACITY), tostring(CFG.CLOAK_GLOW))
                    end
                    local tex = (own and valid(own)) and own or plain
                    if tex and valid(tex) then pcall(function() mid:SetTextureParameterValue(FName("Holo_BaseColor"), tex) end) end
                    if k == 0 and not state.cloakTexLogged then
                        state.cloakTexLogged = true
                        wlog("Cloak: hologram colour from %s", (own and valid(own)) and OK.shortName(own) or "a plain texture")
                    end
                else
                    saved.failed = true
                end
            end
            -- the see-through copy couldn't be made: never put the bright original on, hide instead
            if saved.failed then
                for kk, m in pairs(saved) do if kk ~= "failed" and valid(m) then pcall(function() mesh:SetMaterial(kk, m) end) end end
                saved = {}
                pcall(function() mesh:SetOnlyOwnerSee(true) end)
                if not state.cloakFailLogged then state.cloakFailLogged = true; wlog("Cloak: couldn't dim the hologram; only you can see yourself instead") end
            end
            cloakSaved[key] = saved
            -- the weapon in hand gets the same see-through look
            local wsaved = {}
            pcall(function()
                local eq = subObj(pawn, "m_pEquipmentManagerComponent")
                for _, w in ipairs(OK.arrayToList(eq:GetCurrentWeapons())) do
                    for _, nm in ipairs({ "Mesh", "m_pMesh", "WeaponMesh", "m_pWeaponMesh", "SkeletalMesh" }) do
                        local wm = valid(w) and subObj(w, nm)
                        if wm then
                            local okN2, n2 = pcall(function() return wm:GetNumMaterials() end)
                            for k = 0, (okN2 and n2 or 1) - 1 do
                                local okM2, m2 = pcall(function() return wm:GetMaterial(k) end)
                                local okD2, mid2 = pcall(function() return wm:CreateDynamicMaterialInstance(k, mat) end)
                                if okD2 and valid(mid2) then
                                    wsaved[#wsaved + 1] = { mesh = wm, k = k, m = okM2 and m2 or nil }
                                    pcall(function() mid2:SetScalarParameterValue(FName("Hologram_Opacity"), CFG.CLOAK_OPACITY) end)
                                    pcall(function() mid2:SetScalarParameterValue(FName("HoloLine_Opacity"), CFG.CLOAK_LINES) end)
                                    pcall(function() mid2:SetScalarParameterValue(FName("HoloLine_GapOpacity"), CFG.CLOAK_OPACITY) end)
                                    pcall(function() mid2:SetScalarParameterValue(FName("Hologram_Emissive"), CFG.CLOAK_GLOW) end)
                                    pcall(function() mid2:SetVectorParameterValue(FName("Holo_TintColor"), CFG.CLOAK_TINT) end)
                                    pcall(function() mid2:SetScalarParameterValue(FName("Hologram_BaseReflectFraction"), 0.0) end)
                                    pcall(function() mid2:SetScalarParameterValue(FName("Hologram_Refraction_Index"), 1.0) end)
                                    if plain and valid(plain) then pcall(function() mid2:SetTextureParameterValue(FName("Holo_BaseColor"), plain) end) end
                                end
                            end
                            break
                        end
                    end
                end
            end)
            cloakSaved[key .. "w"] = wsaved
            if not state.cloakWeaponLogged then state.cloakWeaponLogged = true; wlog("Cloak: weapon in hand see-through too (%d material(s))", #wsaved) end
            if not state.cloakLogged then state.cloakLogged = true; wlog("Cloak: see-through material on (%s)", CFG.CLOAK_MATERIAL) end
        else
            pcall(function() mesh:SetOnlyOwnerSee(true) end)
            if not state.cloakLogged then state.cloakLogged = true; wlog("Cloak: drawn only in your own view (set CLOAK_MATERIAL for a see-through look)") end
        end
    else
        local saved = cloakSaved[key]
        if saved then
            for k, m in pairs(saved) do if k ~= "failed" and valid(m) then pcall(function() mesh:SetMaterial(k, m) end) end end
            cloakSaved[key] = nil
        end
        for _, e in ipairs(cloakSaved[key .. "w"] or {}) do
            if valid(e.mesh) and valid(e.m) then pcall(function() e.mesh:SetMaterial(e.k, e.m) end) end
        end
        cloakSaved[key .. "w"] = nil
        pcall(function() mesh:SetOnlyOwnerSee(false) end)
        pcall(function() mesh:SetVisibility(true, true) end)
    end
end
CAST.cloak = function(i, p, pc, pawn, pressed, held, dt)
    if pressed then p.cloakT = 0 end
    if p.cloakT == nil then return end
    if held then
        p.cloakT = p.cloakT + dt
        if p.cloakT > 0.3 then
            -- deflector dome
            if not p.dome then
                if not spend(p, 1) then p.cloakT = nil; wlog("P%d: not enough concentration", i) return end
                p.dome = { drain = 0, zapAt = 0 }
                local dome = p.dome
                if p.cloakOn then p.cloakStop = true end   -- the dome takes over from the cloak
                -- the dome: Crypto's own shield bubble (the effect the game plays when the shield
                -- takes a hit), kept switched on while the dome is up
                local fxList = {}
                pcall(function()
                    local arr = pawn.Array_AllFX_Shield
                    for k = 1, #arr do local c = arr[k]; if valid(c) then fxList[#fxList + 1] = c end end
                end)
                if not state.domeFxLogged then
                    state.domeFxLogged = true
                    local names = {}
                    for _, c in ipairs(fxList) do
                        local tn = ""
                        pcall(function() tn = " (" .. OK.shortName(c.Template) .. ")" end)
                        names[#names + 1] = OK.shortName(c) .. tn
                    end
                    wlog("Deflector: Crypto's shield effects: %s", #names > 0 and table.concat(names, ", ") or "none found")
                end
                local function shieldOn()
                    for _, c in ipairs(fxList) do
                        pcall(function() c:SetVisibility(true, true) end)
                        pcall(function() c:SetHiddenInGame(false, true) end)
                        pcall(function() c:Activate(true) end)
                    end
                end
                shieldOn()
                -- the psi mutant boss's protective bubble, worn by Crypto while the dome is up
                local bubble = nil
                pcall(function()
                    local cls = gameAsset(GAME_FX.psiShield)
                    if not cls then return end
                    bubble = OK.getWorld():SpawnActor(cls, locOf(pawn), { Pitch = 0, Yaw = 0, Roll = 0 })
                    if valid(bubble) then
                        bubble:K2_AttachToActor(pawn, FName("None"), 2, 2, 1, false)
                        pcall(function() bubble:SetActorEnableCollision(false) end)
                        local k = CFG.DEFLECT_BUBBLE_SCALE or 1.0
                        pcall(function() bubble:SetActorScale3D({ X = k, Y = k, Z = k }) end)
                        for _, f in ipairs({ "TriggerEffect", "StartEffect", "Activate", "ReceiveBeginPlay" }) do pcall(function() bubble[f](bubble) end) end
                    end
                end)
                if not state.bubbleLogged then state.bubbleLogged = true; wlog("Deflector: psi shield bubble %s", valid(bubble) and "on" or "not available") end
                -- and a glowing cyan dome you can always see, riding on Crypto
                local glow = spawnSphere(locOf(pawn) or { X = 0, Y = 0, Z = 0 }, CFG.DEFLECT_DOME_SCALE or 3.4, { R = 0.2, G = 0.85, B = 1.0, A = 1 })
                if glow then pcall(function() glow:K2_AttachToActor(pawn, FName("None"), 2, 1, 1, false) end) end
                local again = os.clock() + 1.0
                addJob("dome", function()
                    if p.dome ~= dome or not valid(pawn) then return false end
                    if os.clock() >= again then
                        again = os.clock() + 1.0
                        shieldOn()   -- the effect is short: play it again
                        -- something you can see: the psi mutants' charge-up glow around Crypto
                        -- (the big ripple effect crashed 2-player games: only with DEFLECT_FX set)
                        if CFG.DEFLECT_FX then pcall(function()
                            local e = playFx(CFG.DEFLECT_FX, nil, CFG.DEFLECT_FX_SCALE or 4.0, pawn.Mesh)
                            if e then dome.fx = dome.fx or {}; dome.fx[#dome.fx + 1] = e end
                        end) end
                    end
                    return true
                end, function()
                    for _, c in ipairs(fxList) do pcall(function() c:Deactivate() end) end
                    if valid(bubble) then pcall(function() bubble:K2_DestroyActor() end) end
                    if valid(glow) then pcall(function() glow:K2_DestroyActor() end) end
                    for _, e in ipairs(dome.fx or {}) do
                        if valid(e) then pcall(function() e:DeactivateSystem() end); pcall(function() e:K2_DestroyComponent(e) end) end
                    end
                    dome.fx = nil
                end)
                wlog("P%d Deflector dome up", i)
            end
            local d = p.dome
            d.drain = d.drain + dt
            if d.drain >= 1.0 then d.drain = 0; if not spend(p, 1) then held = false end end
            -- bullets (no projectile to turn round): any hit since last frame goes back to the
            -- nearest enemy who could have fired it
            local shNow = nil
            pcall(function() shNow = OK.stat(pawn, "m_pShieldStat"):GetRatio() end)
            if type(shNow) == "number" and shNow < 0.999 and os.clock() >= (d.bulletAt or 0) then
                d.bulletAt = os.clock() + 0.2
                local me0 = locOf(pawn)
                local foe, fd = nil, CFG.DEFLECT_BULLET_RANGE or 10000
                for _, n in ipairs(me0 and npcList() or {}) do
                    if valid(n) and isEnemy(n) and not (state.deadChar and state.deadChar(n)) then
                        local nl = locOf(n)
                        if nl then local dd = dist(nl, me0); if dd < fd then foe, fd = n, dd end end
                    end
                end
                if foe then
                    sliceHurt(foe, CFG.DEFLECT_BULLET_SLICE or 0.2, pawn)
                    d.returned = (d.returned or 0) + 1
                    if not state.bulletBackLogged then state.bulletBackLogged = true; wlog("Deflector: bullets go back to %s", OK.shortName(foe)) end
                end
            end
            pcall(function() OK.setRatio(OK.stat(pawn, "m_pShieldStat"), 1.0) end)
            pcall(function() OK.setRatio(OK.stat(pawn, "m_pHealthStat"), 1.0) end)
            if os.clock() >= d.zapAt then
                d.zapAt = os.clock() + 0.1
                -- return fire: shots coming at Crypto bounce back the way they came
                local me = locOf(pawn)
                if me then
                    for _, pm in ipairs(FindAllOf("ProjectileMovementComponent") or {}) do
                        if valid(pm) then
                            pcall(function()
                                local owner = pm:GetOwner()
                                local l = owner:K2_GetActorLocation()
                                local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                                local cr = CFG.DEFLECT_CATCH_RADIUS or 650
                                if dx * dx + dy * dy + dz * dz < cr * cr then
                                    local v = pm.Velocity
                                    -- only ones heading in (not ours going out)
                                    if v.X * dx + v.Y * dy + v.Z * dz < 0 then
                                        -- whoever fired it gets it back: hurt them when it would arrive
                                        local shooter = nil
                                        pcall(function() shooter = owner.Instigator end)
                                        if not (valid(shooter) and shooter.m_pStatsComponent) then shooter = nil end
                                        if not shooter then
                                            -- no owner on the bolt: the nearest enemy back along the line it came in on
                                            local sp0 = math.max(1, math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z))
                                            local bx, by, bz = -v.X / sp0, -v.Y / sp0, -v.Z / sp0
                                            local bestD = 6000
                                            for _, n in ipairs(npcList()) do
                                                if valid(n) and isEnemy(n) and not (state.deadChar and state.deadChar(n)) then
                                                    local nl = locOf(n)
                                                    if nl then
                                                        local ex, ey, ez = nl.X - me.X, nl.Y - me.Y, nl.Z - me.Z
                                                        local el = math.sqrt(ex * ex + ey * ey + ez * ez)
                                                        if el > 1 and el < bestD and (ex * bx + ey * by + ez * bz) / el > 0.85 then shooter, bestD = n, el end
                                                    end
                                                end
                                            end
                                        end
                                        if valid(shooter) and OK.keyOf(shooter) ~= OK.keyOf(pawn) then
                                            local sl = locOf(shooter)
                                            local spd = math.max(500, math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z))
                                            local tt = sl and math.min(2.0, dist(sl, me) / spd) or 0.3
                                            local who = shooter
                                            after(tt, function() if valid(who) then sliceHurt(who, CFG.DEFLECT_SLICE or 0.35, pawn) end end)
                                        end
                                        pm.Velocity = { X = -v.X, Y = -v.Y, Z = -v.Z }
                                        pcall(function() owner:SetOwner(pawn) end)
                                        pcall(function() owner.Instigator = pawn end)
                                        d.returned = (d.returned or 0) + 1
                                    end
                                end
                            end)
                        end
                    end
                end
            end
            if held then p.powerLabel = "Deflector  (hold)" return end
        else
            return
        end
    end
    -- let go
    local wasDome = p.dome ~= nil
    p.cloakT, p.dome, p.powerLabel = nil, nil, nil
    if wasDome then
        wlog("P%d Deflector dome down", i)
        return
    end
    -- tap while cloaked: switch it off
    if p.cloakOn then
        p.cloakStop = true
        return
    end
    if (p.pool or 0) < DOT then wlog("P%d: not enough concentration", i) return end
    setInvisible(pawn, true)
    local myPawn = pawn
    cloakLook(pawn, true)
    p.cloakOn, p.cloakStop = true, nil
    local last = os.clock()
    addJob("cloak", function()
        if not valid(myPawn) or p.cloakStop then return false end
        local now = os.clock()
        local step = math.min(0.1, now - last)
        last = now
        -- uses the bar up as it goes (a full bar lasts CLOAK_FULL_SECONDS), on top of the refill
        p.pool = (p.pool or 0) - step * (1 / CFG.CLOAK_FULL_SECONDS + DOT / CFG.POWER_DOT_SECONDS)
        if p.pool <= 0 then p.pool = 0; wlog("P%d Cloak: out of concentration", i) return false end
        p.powerLabel = "Cloak on  (LT: off)"
        return true
    end,
        function()
            if valid(myPawn) then setInvisible(myPawn, false); cloakLook(myPawn, false) end
            p.cloakOn, p.cloakStop = nil, nil
            p.powerLabel = nil
            wlog("P%d visible again", i)
        end)
    wlog("P%d Cloak on (tap LT to switch off)", i)
end

------------------------------------------------------------------------------------------
-- Psychic Tether. LT on someone: yank them to you. LT on a second person within a few
-- seconds: the two are tied together and slam into each other. (Swinging comes later.)
-- Psi-Barrage / the psi mutants' attacks. The mutants' weapons say which projectile they fire;
-- the mod notes those classes whenever a psi mutant is around and keeps the list in
-- overkill_power_classes.txt, so the power works on other maps too.
local PSI_FILE = "overkill_power_classes.txt"
local psiClasses = {     -- name -> class path (the pulse field's is known from the Rockwell scan)
    pulsefield = "/Game/Blueprints/Projectiles/BP_ProjectileMindLinkPulseField.BP_ProjectileMindLinkPulseField_C",
}
do
    local f = io.open(PSI_FILE, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^([%w_]+)=(.+)$")
            if k then psiClasses[k] = v end
        end
        f:close()
    end
end
local function savePsiClasses()
    local f = io.open(PSI_FILE, "w")
    if not f then return end
    f:write("# projectile classes borrowed from enemy weapons (found in-game)\n")
    for k, v in pairs(psiClasses) do f:write(k, "=", v, "\n") end
    f:close()
end
OK.addTickJob("psiClassWatch", 5.0, function()
    for key, wcls in pairs({ psigrenade = "BP_Weapon_PsiGrenade_C", pulsefield = "BP_WeaponEnemyMindLinkPulseField_C" }) do
        if not psiClasses[key] then
            local w = FindFirstOf(wcls)
            local ok, c = pcall(function() return w.m_pCachedProjectileClass end)
            if valid(w) and ok and valid(c) then
                local path = OK.nameOf(c):match("^%S+%s+(.+)$") or OK.nameOf(c)
                psiClasses[key] = path
                savePsiClasses()
                wlog("Psi powers: found the psi mutants' %s: %s", key, path)
            end
        end
    end
end)
psiClass = function(key)
    local path = psiClasses[key]
    if not path then return nil end
    local c = StaticFindObject(path)
    return valid(c) and c or nil
end
fireProjectile = function(cls, from, to, pawn, speed, lob)
    local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
    local yaw = math.deg(math.atan(dy, dx))
    local pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
    local ok, pr = pcall(function() return OK.getWorld():SpawnActor(cls, from, { Pitch = pitch, Yaw = yaw, Roll = 0 }) end)
    if not (ok and valid(pr)) then return nil end
    pcall(function() pr:SetOwner(pawn) end)
    pcall(function() pr.Instigator = pawn end)
    -- give it its flight (it hung in the air): the projectile part's speed toward the target
    local d = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
    local spd = speed or CFG.PSI_SHOT_SPEED or 2200
    local v = { X = dx / d * spd, Y = dy / d * spd, Z = dz / d * spd + (lob or CFG.PSI_SHOT_LOB or 250) }
    local pm = nil
    for _, nm in ipairs({ "ProjectileMovement", "m_pProjectileMovement", "ProjectileMovementComponent", "MovementComponent" }) do
        pm = subObj(pr, nm)
        if pm then break end
    end
    if not pm then
        pcall(function() pr:GetClass():ForEachProperty(function(pp)
            if pm then return end
            local n = pp:GetFName():ToString()
            local okV, val = pcall(function() return pr[n] end)
            if okV and valid(val) and OK.nameOf(val):find("ProjectileMovement") then pm = val end
        end) end)
    end
    if pm then
        pcall(function() pm:SetUpdatedComponent(pr:K2_GetRootComponent()) end)
        pcall(function() pm.Velocity = v end)
        pcall(function() pm:SetVelocityInLocalSpace({ X = spd, Y = 0, Z = 0 }) end)
        pcall(function() pm.Velocity = v end)
        pcall(function() pm:Activate(true) end)
    end
    pcall(function() pr:Activate() end)
    if not state.psiFlightLogged then state.psiFlightLogged = true; wlog("Psi shot: flight %s", pm and "set" or "no projectile part found") end
    return pr
end
state.fireProjectile = fireProjectile
CAST.psibarrage = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    local cls = psiClass("psigrenade")
    if not cls then wlog("P%d Psi-Barrage: meet a psi mutant first (the mod borrows their grenades)", i) return end
    local hit = cone(pc, pawn, 2500, 0.6)
    local targets = {}
    for _, e in ipairs(hit) do if isEnemy(e.n) and #targets < 3 then targets[#targets + 1] = e.n end end
    if #targets == 0 then for _, e in ipairs(hit) do if #targets < 3 then targets[#targets + 1] = e.n end end end
    if #targets == 0 then wlog("P%d Psi-Barrage: nobody in front of you", i) return end
    if not spend(p, 2) then wlog("P%d: not enough concentration", i) return end
    for k, n in ipairs(targets) do
        after(0.2 * (k - 1), function()
            local me, l = locOf(pawn), valid(n) and locOf(n)
            if not (me and l) then return end
            local fx0, fy0 = camDir(pc)
            local from = { X = me.X + fx0 * 80, Y = me.Y + fy0 * 80, Z = me.Z + 110 }
            local pr = fireProjectile(cls, from, { X = l.X, Y = l.Y, Z = l.Z + 40 }, pawn)
            -- the hit, when it would land (the grenade's own damage may not count for the player)
            local tt = math.min(2.0, dist(me, l) / (CFG.PSI_SHOT_SPEED or 2200))
            after(tt, function() if valid(n) then sliceHurt(n, CFG.PSI_BARRAGE_SLICE or 0.4, pawn) end end)
            if not state.psiLogged then state.psiLogged = true; wlog("Psi-Barrage: grenade %s", pr and "thrown" or "couldn't be made") end
        end)
    end
    wlog("P%d Psi-Barrage at %d", i, #targets)
end

-- Psychic Tether. LT on someone: they're pulled to you. LT on a second person or a car within
-- a few seconds: the first one is snapped onto it (two people slam together; on a car they
-- stick to it and ride along).
local function aimedCar(pc, pawn, range)
    local me = locOf(pawn)
    if not me then return nil end
    local fx0, fy0 = camDir(pc)
    local best, bestDot = nil, 0.94
    for _, v in ipairs(carList()) do
        local l = valid(v) and locOf(v)
        if l then
            local dx, dy = l.X - me.X, l.Y - me.Y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 50 and d < range then
                local dot = (dx * fx0 + dy * fy0) / d
                if dot > bestDot then best, bestDot = v, dot end
            end
        end
    end
    return best
end
-- drive a limp body toward a moving point until it gets there (or time runs out)
local function pullTo(n, pointFn, seconds, onArrive)
    goLimp(n)
    local t0 = os.clock()
    addJob("pull", function()
        if not valid(n) then return false end
        local l, at = locOf(n), pointFn()
        if not (l and at) then return false end
        local d = dist(l, at)
        if d < 130 then
            pcall(function() n.Mesh:SetAllPhysicsLinearVelocity({ X = 0, Y = 0, Z = 0 }, false) end)
            if onArrive then pcall(onArrive) end
            return false
        end
        local sp = math.min(2200, 300 + d * 4)
        local v = { X = (at.X - l.X) / d * sp, Y = (at.Y - l.Y) / d * sp, Z = (at.Z - l.Z) / d * sp + 120 }
        fling(n, v, false)
        return os.clock() - t0 < (seconds or 2.0)
    end)
end
-- Psychic Tether = a psychic grapple: LT fires it straight where you're looking (no lock-on),
-- up to TETHER_RANGE away, and pulls Crypto to whatever it hits. LT again lets go.
CAST.tether = function(i, p, pc, pawn, pressed)
    if not pressed then return end
    if p.grapple then p.grapple.stop = true return end
    local from, dir = nil, nil
    pcall(function()
        local cm = pc.PlayerCameraManager
        from = cm:GetCameraLocation()
        local r = cm:GetCameraRotation()
        local y, pt = math.rad(r.Yaw), math.rad(r.Pitch)
        dir = { X = math.cos(pt) * math.cos(y), Y = math.cos(pt) * math.sin(y), Z = math.sin(pt) }
    end)
    if not (from and dir) then return end
    local to = { X = from.X + dir.X * CFG.TETHER_RANGE, Y = from.Y + dir.Y * CFG.TETHER_RANGE, Z = from.Z + dir.Z * CFG.TETHER_RANGE }
    local hit = {}
    local okT, got = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):LineTraceSingle(OK.getWorld(), from, to, 0, false, { pawn }, 0, hit, true,
            { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    local at = nil
    if okT and got then
        pcall(function() at = hit.ImpactPoint or hit.Location end)
        if at and type(at.X) ~= "number" then at = nil end
    end
    if not at then wlog("P%d Psychic Tether: nothing to grab within reach", i) return end
    if not spend(p, 1) then wlog("P%d: not enough concentration", i) return end
    local hook = spawnSphere(at, 0.35, { R = 0.3, G = 0.9, B = 1.0, A = 1 })   -- where it caught
    local g = { stop = false }
    p.grapple = g
    local t0 = os.clock()
    local function hand()
        local l = locOf(pawn)
        return l and { X = l.X, Y = l.Y, Z = l.Z + 60 } or nil
    end
    -- the rope: the Zap-O-Matic beam held from Crypto to the hook, or a thin cyan cylinder
    g.beam = arcTo(pawn, nil, 30, { force = true, fromFn = hand, toFn = function() return at end })
    if not g.beam then
        local cyl = StaticFindObject("/Engine/BasicShapes/Cylinder.Cylinder")
        if not valid(cyl) then pcall(function() cyl = LoadAsset("/Engine/BasicShapes/Cylinder.Cylinder") end) end
        if valid(cyl) then
            g.rope = spawnMeshActor(at, cyl)
            pcall(function()
                local smc = g.rope.StaticMeshComponent
                smc:SetCollisionEnabled(0)
                -- glowing psychic cyan: the game's hologram material, bright; plain shape material if that's missing
                local holo = StaticFindObject(CFG.CLOAK_MATERIAL ~= "" and CFG.CLOAK_MATERIAL or "/Game/VFX/Materials/Meshes/M_Hologram_01.M_Hologram_01")
                if valid(holo) then
                    local mid = smc:CreateDynamicMaterialInstance(0, holo)
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Opacity"), 0.9) end)
                    pcall(function() mid:SetScalarParameterValue(FName("HoloLine_Opacity"), 1.0) end)
                    pcall(function() mid:SetScalarParameterValue(FName("HoloLine_GapOpacity"), 0.9) end)
                    pcall(function() mid:SetScalarParameterValue(FName("Hologram_Emissive"), 25.0) end)
                    pcall(function() mid:SetVectorParameterValue(FName("Holo_TintColor"), { R = 0.2, G = 0.9, B = 1.0, A = 1 }) end)
                    pcall(function() mid:SetVectorParameterValue(FName("Holo_BaseColor"), { R = 0.2, G = 0.9, B = 1.0, A = 1 }) end)
                else
                    local parent = StaticFindObject(SHAPE_MAT)
                    if not valid(parent) then parent = smc:GetMaterial(0) end
                    smc:CreateDynamicMaterialInstance(0, parent):SetVectorParameterValue(FName("Color"), { R = 0.3, G = 0.9, B = 1.0, A = 1 })
                end
            end)
        end
    end
    -- swing physics: a rope of fixed length that slowly reels in. Gravity and your own air
    -- control keep working; the rope only stops you flying further away than its length.
    local me0 = locOf(pawn) or from
    local L = dist(me0, at)
    local cm = nil
    pcall(function() cm = pawn.CharacterMovement end)
    pcall(function() cm:SetMovementMode(3, 0) end)   -- falling (so gravity swings you)
    -- a small kick toward the hook to start the swing
    pcall(function()
        local d0 = math.max(1, L)
        local k0 = CFG.TETHER_KICK or 2200
        pawn:LaunchCharacter({ X = (at.X - me0.X) / d0 * k0, Y = (at.Y - me0.Y) / d0 * k0, Z = math.max(900, (at.Z - me0.Z) / d0 * k0) }, false, false)
    end)
    addJob("grapple", function(dt)
        if g.stop or not valid(pawn) then return false end
        local me = locOf(pawn)
        if not me then return false end
        local elapsed = os.clock() - t0
        if elapsed > (CFG.TETHER_SECONDS or 8) then return false end
        L = math.max(150, L - (CFG.TETHER_REEL or 350) * dt)
        local dx, dy, dz = me.X - at.X, me.Y - at.Y, me.Z - at.Z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d < 170 then return false end
        local nx, ny, nz = dx / d, dy / d, dz / d          -- out from the hook
        -- stay in the air the whole swing (walking friction on landing made it stutter)
        pcall(function() if cm.MovementMode ~= 3 then cm:SetMovementMode(3, 0) end end)
        -- the rope (cylinder) from hand to hook
        if g.rope and valid(g.rope) then
            pcall(function()
                local h = hand() or me
                local rx, ry, rz = at.X - h.X, at.Y - h.Y, at.Z - h.Z
                local rl = math.max(1, math.sqrt(rx * rx + ry * ry + rz * rz))
                g.rope:K2_SetActorLocation({ X = (h.X + at.X) / 2, Y = (h.Y + at.Y) / 2, Z = (h.Z + at.Z) / 2 }, false, {}, true)
                g.rope:K2_SetActorRotation({ Pitch = math.deg(math.atan(rz, math.sqrt(rx * rx + ry * ry))) - 90, Yaw = math.deg(math.atan(ry, rx)), Roll = 0 }, false)
                g.rope:SetActorScale3D({ X = 0.05, Y = 0.05, Z = rl / 100 })
            end)
        end
        if d <= L then
            -- slack: a strong pull toward the hook so you keep flying
            pcall(function()
                local gv = pawn:GetVelocity()
                local pull = (CFG.TETHER_PULL or 3500) * dt
                local v2 = { X = gv.X - nx * pull, Y = gv.Y - ny * pull, Z = gv.Z - nz * pull + (CFG.TETHER_LIFT or 900) * dt }
                -- the game's own launch (writing the speed straight into the movement didn't stick)
                pawn:LaunchCharacter(v2, true, true)
            end)
            return true
        end
        local v = nil
        pcall(function() local gv = pawn:GetVelocity(); v = { X = gv.X, Y = gv.Y, Z = gv.Z } end)
        if not v then return true end
        -- take away the part of the speed that pulls the rope longer, then pull back to length
        local out = v.X * nx + v.Y * ny + v.Z * nz
        if out > 0 then v = { X = v.X - out * nx, Y = v.Y - out * ny, Z = v.Z - out * nz } end
        local fix = math.min(900, (d - L) * 3)   -- gentle: a hard snap back made it jerky
        v = { X = v.X - nx * fix, Y = v.Y - ny * fix, Z = v.Z - nz * fix }
        local sp = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
        if sp > CFG.TETHER_SPEED then local k = CFG.TETHER_SPEED / sp; v = { X = v.X * k, Y = v.Y * k, Z = v.Z * k } end
        pcall(function() pawn:LaunchCharacter(v, true, true) end)
        return true
    end, function()
        destroy(hook); destroy(g.rope)
        if g.beam and valid(g.beam) then pcall(function() g.beam:StopBeam() end); pcall(function() g.beam:K2_DestroyActor() end) end
        if p.grapple == g then p.grapple = nil end
    end)
    wlog("P%d Psychic Tether: grappling to a point %.0f m away", i, dist(locOf(pawn) or from, at) / 100)
end

------------------------------------------------------------------------------------------
-- Game assets the powers borrow are loaded a while after a map starts, never in the middle of
-- casting (loading while a mission streams in crashed the game when the drone came out).
local DRONE_MESH = "/Game/Meshes/Furon_Tech/Orthopox_Drone.Orthopox_Drone"
local DRONE_FX = "/Game/VFX/CutScenes/Generic/PFX_PoxDroneEngine.PFX_PoxDroneEngine"
local DRONE_SHOT = "/Game/Blueprints/Projectiles/BP_ProjectileDisintegrationRay_Smaller.BP_ProjectileDisintegrationRay_Smaller_C"
-- A loaded asset nothing uses is thrown away by the engine again, so a hidden "keeper"
-- object uses each of them for as long as the map is loaded.
local keeper = nil
local function preloadPowerAssets()
    -- (the psi mutants' attacks too, once the mod has seen them)
    local extra = {}
    for _, v in pairs(psiClasses or {}) do extra[#extra + 1] = v end
    pcall(function() if state.loadClass then wlog("Power assets: green haybale explosion %s", (state.loadClass(OVERLOAD_BOOMS[1]) and state.loadClass(OVERLOAD_BOOMS[2])) and "loaded" or "partly found") end end)
    for _, path in ipairs({ DRONE_MESH, DRONE_FX, CFG.CLOAK_MATERIAL, DRONE_SHOT, extra[1], extra[2] }) do
        if path and path ~= "" and not valid(StaticFindObject(path)) then
            local ok = pcall(function() LoadAsset(path) end)
            wlog("Power assets: %s %s", path:match("[^/]+$"), ok and valid(StaticFindObject(path)) and "loaded" or "not found")
        end
    end
    if valid(keeper) then return end
    local ok, a = pcall(function()
        return OK.getWorld():SpawnActor(StaticFindObject("/Script/Engine.StaticMeshActor"), { X = 0, Y = 0, Z = -50000 }, { Pitch = 0, Yaw = 0, Roll = 0 })
    end)
    if not (ok and valid(a)) then wlog("Power assets: keeper not made") return end
    keeper = a
    pcall(function() a:SetActorHiddenInGame(true) end)
    pcall(function() a:SetActorEnableCollision(false) end)
    local smc = a.StaticMeshComponent
    pcall(function() smc:SetMobility(2) end)
    local mesh = StaticFindObject(DRONE_MESH)
    if valid(mesh) then pcall(function() smc:SetStaticMesh(mesh) end) end
    local mat = CFG.CLOAK_MATERIAL ~= "" and StaticFindObject(CFG.CLOAK_MATERIAL) or nil
    if valid(mat) then pcall(function() smc:SetMaterial(0, mat) end) end
    local fx = StaticFindObject(DRONE_FX)
    if valid(fx) then
        pcall(function()
            local c = OK.getStatics():SpawnEmitterAttached(fx, smc, FName("None"), { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = 1, Y = 1, Z = 1 }, 0, false, 0)
            if valid(c) then c:Deactivate() end
        end)
    end
    wlog("Power assets: kept loaded (drone %s, effect %s, cloak %s)", tostring(valid(mesh)), tostring(valid(fx)), tostring(valid(mat)))
end
OK.onWorldChange(function() keeper = nil end)
OK.onWorldChange(function() if OK.later then OK.later(12, "powerAssets", preloadPowerAssets) end end)
if OK.later then OK.later(12, "powerAssets", preloadPowerAssets) end

-- Furon Sentry Probe: a little drone over your shoulder that zaps enemies near you
default("SENTRY_MARK_SECONDS", 8)      -- Gastro mark: how long the drone goes after who you marked
default("SENTRY_MARK_RANGE", 4000)
default("SENTRY_ORBIT", 380)           -- how far round the marked person it circles (cm)
default("SENTRY_HOVER", 320)           -- ...and how high above them
default("SENTRY_CHARGE_SECONDS", 0.9)  -- hold LT this long for rapid fire
default("SENTRY_RAPID_SECONDS", 3)
default("SENTRY_RAPID_INTERVAL", 0.12)
default("SENTRY_RAPID_SLICE", 0.05)
CAST.sentry = function(i, p, pc, pawn, pressed, held, dt)
    -- with the drone out, LT works like the second game's Gastro launcher
    if p.sentry then
        local s0 = p.sentry
        if s0.skipHold then if not held then s0.skipHold = nil end return end   -- the press that called it
        if held then
            s0.holdT = (s0.holdT or 0) + (dt or 0.03)
            if s0.holdT >= (CFG.SENTRY_CHARGE_SECONDS or 0.9) and not s0.charged then
                s0.charged = true
                if (p.pool or 0) + 1e-6 >= DOT then
                    p.pool = p.pool - DOT
                    s0.rapidUntil = os.clock() + (CFG.SENTRY_RAPID_SECONDS or 3)
                    s0.zapAt = 0
                    wlog("P%d Sentry Probe: rapid fire!", i)
                else wlog("P%d: not enough concentration for rapid fire", i) end
            end
            return
        end
        local tap = s0.holdT and s0.holdT < 0.35
        s0.holdT, s0.charged = nil, nil
        if not tap then return end
        local n = aimedNPC(pc, pawn, CFG.SENTRY_MARK_RANGE or 4000)
        if n and n ~= s0.mark then
            s0.mark, s0.markUntil = n, os.clock() + (CFG.SENTRY_MARK_SECONDS or 8)
            mark(n, "Furon Sentry Probe", CFG.SENTRY_MARK_SECONDS or 8)
            wlog("P%d Sentry Probe: marked %s", i, OK.nameOf(n))
        elseif n then
            s0.mark = nil
            wlog("P%d Sentry Probe: mark off", i)
        else
            s0.untilT = 0; wlog("P%d Sentry Probe: sent home", i)
        end
        return
    end
    if not pressed then return end
    if (p.pool or 0) < DOT then wlog("P%d: not enough concentration", i) return end
    local me = locOf(pawn)
    if not me then return end
    -- the game's own Orthopox drone model; the cyan ball stays as a fallback
    local drone
    pcall(function()
        local m = StaticFindObject(DRONE_MESH)
        if valid(m) then
            drone = spawnMeshActor(me, m)
            if drone then pcall(function() drone:SetActorScale3D({ X = CFG.SENTRY_SCALE, Y = CFG.SENTRY_SCALE, Z = CFG.SENTRY_SCALE }) end) end
        end
    end)
    if not state.droneMeshLogged then state.droneMeshLogged = true; wlog("Sentry drone: %s", drone and "Orthopox model" or "model not found, using the cyan ball") end
    if not drone then drone = spawnSphere(me, 0.3, CYANC) end
    -- Pox's drone engine glow from the game's own effects, stuck to the drone
    if drone then
        pcall(function()
            local ps = StaticFindObject(DRONE_FX)
            if valid(ps) then
                local comp = OK.getStatics():SpawnEmitterAttached(ps, drone.StaticMeshComponent, FName("None"),
                    { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = 1, Y = 1, Z = 1 }, 0, true, 0)
                if not state.droneFxLogged then state.droneFxLogged = true; wlog("Sentry drone: Pox engine effect %s", valid(comp) and "on" or "didn't start") end
            end
        end)
    end
    local s = { untilT = os.clock() + CFG.SENTRY_SECONDS, zapAt = 0, drone = drone, skipHold = true }
    p.sentry = s
    local myPawn = pawn
    -- ride along on the player (the engine moves it with Crypto every frame, so no stutter);
    -- the mod only adds the little bob
    if drone then
        -- on Crypto's body mesh (it moves smoothly; the collision capsule under it moves in steps)
        s.onMesh = pcall(function() drone:K2_AttachToComponent(myPawn.Mesh, FName("None"), 1, 1, 1, false) end)
        s.attached = s.onMesh or pcall(function() drone:K2_AttachToActor(myPawn, FName("None"), 1, 1, 1, false) end)
        if not state.droneAttachLogged then state.droneAttachLogged = true; wlog("Sentry drone: %s", s.attached and "rides on the player" or "follows by moving (attach failed)") end
    end
    local lastT = os.clock()
    addJob("sentry", function()
        if not valid(myPawn) or os.clock() >= s.untilT then return false end
        -- it runs on the concentration bar (a full bar lasts SENTRY_SECONDS)
        local nowT = os.clock()
        local step = math.min(0.1, nowT - lastT)
        lastT = nowT
        p.pool = (p.pool or 0) - step * (1 / CFG.SENTRY_SECONDS + DOT / CFG.POWER_DOT_SECONDS)
        if p.pool <= 0 then p.pool = 0; wlog("P%d Sentry Probe: out of concentration", i) return false end
        local t = os.clock()
        local rapid = (s.rapidUntil or 0) > t
        if s.holdT and s.holdT > 0.2 and not s.charged then
            local f = math.min(1, s.holdT / (CFG.SENTRY_CHARGE_SECONDS or 0.9))
            p.powerLabel = "Sentry Probe  charging " .. string.rep("|", math.floor(f * 6 + 0.5)) .. string.rep(".", 6 - math.floor(f * 6 + 0.5))
        else
            p.powerLabel = rapid and "Sentry Probe  RAPID FIRE" or (s.mark and "Sentry Probe  after your mark" or "Sentry Probe  (tap LT: mark, hold: rapid)")
        end
        local l = locOf(myPawn)
        if not l then return false end
        local fx0, fy0 = camDir(pc)
        local pos
        -- Gastro style: a marked person gets the drone. It leaves your shoulder, circles above
        -- them and keeps on them until the mark runs out, then flies back.
        local markOn = s.mark
        if markOn and (not valid(markOn) or t >= (s.markUntil or 0) or (state.deadChar and state.deadChar(markOn))) then
            s.mark, markOn = nil, nil
        end
        if markOn and valid(drone) then
            if s.attached then
                pcall(function() drone:K2_DetachFromActor(1, 1, 1) end)
                s.attached, s.onMesh, s.flying = false, false, true
                s.pos = locOf(drone)
            end
            s.flying = true
            local ml = locOf(markOn)
            if ml then
                local dtt = math.min(0.1, t - (s.at or t)); s.at = t
                s.orbit = (s.orbit or math.random() * 6.28) + dtt * 0.9
                local r = CFG.SENTRY_ORBIT or 380
                local want2 = { X = ml.X + math.cos(s.orbit) * r, Y = ml.Y + math.sin(s.orbit) * r, Z = ml.Z + (CFG.SENTRY_HOVER or 320) + math.sin(t * 2.3) * 40 }
                s.pos = s.pos or want2
                local k = math.min(1, dtt * 3)
                s.pos = { X = s.pos.X + (want2.X - s.pos.X) * k, Y = s.pos.Y + (want2.Y - s.pos.Y) * k, Z = s.pos.Z + (want2.Z - s.pos.Z) * k }
                pos = s.pos
                moveTo(drone, pos)
                local yaw = math.deg(math.atan(ml.Y - pos.Y, ml.X - pos.X)) + CFG.SENTRY_YAW
                pcall(function() drone:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
            end
        end
        if s.attached and valid(drone) then
            -- over the right shoulder, in the player's own space
            pcall(function()
                local root = drone.StaticMeshComponent
                local bob = math.sin(t * 3) * 12
                if s.onMesh then
                    -- the body mesh is turned a quarter round and sits at the feet: its X is
                    -- Crypto's right, its Y his forward
                    root:K2_SetRelativeLocation({ X = 70, Y = -40, Z = 200 + bob }, false, {}, true)
                    root:K2_SetRelativeRotation({ Pitch = 0, Yaw = 90 + CFG.SENTRY_YAW, Roll = 0 }, false, {}, true)
                else
                    root:K2_SetRelativeLocation({ X = -40, Y = 70, Z = 110 + bob }, false, {}, true)
                    root:K2_SetRelativeRotation({ Pitch = 0, Yaw = CFG.SENTRY_YAW, Roll = 0 }, false, {}, true)
                end
            end)
            pos = locOf(drone) or l
        end
        local want = { X = l.X - fx0 * 40 + fy0 * 70, Y = l.Y - fy0 * 40 - fx0 * 70, Z = l.Z + 110 + math.sin(t * 3) * 12 }
        if not pos then
        -- glide after the shoulder spot instead of snapping to it every frame
        s.pos = s.pos or want
        local dtt = math.min(0.1, t - (s.at or t)); s.at = t
        local k = math.min(1, dtt * 7)
        s.pos = { X = s.pos.X + (want.X - s.pos.X) * k, Y = s.pos.Y + (want.Y - s.pos.Y) * k, Z = s.pos.Z + (want.Z - s.pos.Z) * k }
        pos = s.pos
        moveTo(drone, pos)
        -- back from a mark: on the shoulder again once it's there
        if s.flying and valid(drone) and dist(pos, want) < 120 then
            s.onMesh = pcall(function() drone:K2_AttachToComponent(myPawn.Mesh, FName("None"), 1, 1, 1, false) end)
            s.attached = s.onMesh or pcall(function() drone:K2_AttachToActor(myPawn, FName("None"), 1, 1, 1, false) end)
            s.flying = false
        end
        -- face where the player is looking
        if valid(drone) then
            local yaw = math.deg(math.atan(fy0, fx0)) + CFG.SENTRY_YAW
            pcall(function() drone:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
        end
        end
        -- the Zap-O-Matic crosshair over whoever the drone is zapping (on its owner's screen)
        if state.texMarkerAt then
            local tl = valid(s.markOn) and locOf(s.markOn)
            if tl then pcall(state.texMarkerAt, "drone" .. i, pc, CFG.SENTRY_MARKER or "PLACEHOLDER_Crosshair_ZapOMatic", { X = tl.X, Y = tl.Y, Z = tl.Z + 60 }, CFG.SENTRY_MARKER_SIZE or 56)
            elseif state.texMarkerHide then pcall(state.texMarkerHide, "drone" .. i) end
        end
        if t >= s.zapAt then
            local best, bd = nil, CFG.SENTRY_RANGE
            for _, n in ipairs(npcList()) do
                -- anyone (civilians too), never a player
                if valid(n) and (CFG.SENTRY_ENEMIES_ONLY and isEnemy(n) or not CFG.SENTRY_ENEMIES_ONLY) and not isPlayerPawn(n)
                    and not (state.deadChar and state.deadChar(n)) then
                    local nl = locOf(n)
                    if nl then local d = dist(nl, pos); if d < bd then best, bd = n, d end end
                end
            end
            -- keep zapping the same person while they're alive and in range
            if valid(s.target) and not (state.deadChar and state.deadChar(s.target)) then
                local tl = locOf(s.target)
                if tl and dist(tl, pos) < CFG.SENTRY_RANGE * 1.15 then best = s.target end
            end
            if markOn then best = markOn end
            if best then
                s.zapAt = t + (rapid and (CFG.SENTRY_RAPID_INTERVAL or 0.12) or 0.5)
                if best ~= s.target or not (s.arc and valid(s.arc)) then
                    if s.arc and valid(s.arc) then pcall(function() s.arc:StopBeam() end); pcall(function() s.arc:K2_DestroyActor() end) end
                    s.target = best
                    -- one Zap-O-Matic bolt from the drone to them (no chaining), held while it zaps
                    -- the held beam never showed and cost frames: only with SENTRY_BEAM on
                    s.arc = CFG.SENTRY_BEAM and arcTo(myPawn, best, 600, { force = true, fromFn = function()
                        -- from the drone itself (riding on Crypto it has no glide spot, which ended the beam at once)
                        local dl = valid(drone) and locOf(drone)
                        return dl or s.pos or locOf(myPawn)
                    end })
                    if not state.droneShotLogged then state.droneShotLogged = true; wlog("Sentry drone: zapping with the Zap-O-Matic beam (%s)", s.arc and "on" or "no beam") end
                end
                -- real damage: take a slice off their health; the last slice goes through the game's death path
                sliceHurt(best, rapid and (CFG.SENTRY_RAPID_SLICE or 0.05) or (CFG.SENTRY_ZAP_SLICE or 0.12), myPawn)
                s.markOn = best
                -- a bolt you can see, Zap-O-Matic style: a blue streak (the Ion Detonator's trail,
                -- catalog 145) flies from the drone to them on an invisible carrier
                if CFG.SENTRY_BOLT then pcall(function()
                    local bl = locOf(best)
                    if not (bl and pos) then return end
                    local carrier = spawnSphere(pos, 0.1, nil)
                    if not carrier then return end
                    pcall(function() carrier:SetActorHiddenInGame(false); carrier.StaticMeshComponent:SetVisibility(false, false) end)
                    playFx(CFG.SENTRY_BOLT_FX or "/Game/VFX/PFX/Gameplay/Weapons/PFX_IonDetoProjectileTrail.PFX_IonDetoProjectileTrail", nil, CFG.SENTRY_BOLT_SCALE or 0.6, carrier.StaticMeshComponent)
                    local from0, to0, b0 = { X = pos.X, Y = pos.Y, Z = pos.Z }, { X = bl.X, Y = bl.Y, Z = bl.Z + 50 }, os.clock()
                    addJob("droneBolt", function()
                        local f = (os.clock() - b0) / 0.18
                        if f >= 1.25 or not valid(carrier) then return false end
                        local k = math.min(1, f)
                        moveTo(carrier, { X = from0.X + (to0.X - from0.X) * k, Y = from0.Y + (to0.Y - from0.Y) * k, Z = from0.Z + (to0.Z - from0.Z) * k })
                        return true
                    end, function() destroy(carrier) end)
                end) end
                -- the zap's own hit sparks on them (the Zap-O-Matic beam's hit effect)
                pcall(function()
                    local src = valid(s.arc) and s.arc or nil
                    if not src then pcall(function() local ac = getArcClass(myPawn); if ac then src = ac:GetCDO() end end) end
                    if not s.hitTpl and src then
                        for _, nm in ipairs({ "PFX_hit_loop_01", "PFX_Zap-o-Matic_permanent_01" }) do
                            local okC, comp = pcall(function() return src[nm] end)
                            if okC and valid(comp) then
                                local okT, t = pcall(function() return comp.Template end)
                                if okT and valid(t) then s.hitTpl = t; break end
                            end
                        end
                        if not state.droneHitLogged then state.droneHitLogged = true; wlog("Sentry drone: hit sparks %s", s.hitTpl and OK.shortName(s.hitTpl) or "not found") end
                    end
                    local bl = locOf(best)
                    s.sparkN = (s.sparkN or 0) + 1
                    if s.hitTpl and bl and s.sparkN % 2 == 1 then playFx(s.hitTpl, { X = bl.X, Y = bl.Y, Z = bl.Z + 50 }, 1.0) end   -- every other zap: lighter
                end)
            else
                s.zapAt = t + 0.3
                if s.arc and valid(s.arc) then pcall(function() s.arc:StopBeam() end); pcall(function() s.arc:K2_DestroyActor() end) end
                s.arc, s.target = nil, nil
                s.markOn = nil
            end
        end
        return true
    end, function() destroy(drone); if state.texMarkerHide then pcall(state.texMarkerHide, "drone" .. i) end; if s.arc and valid(s.arc) then pcall(function() s.arc:K2_DestroyActor() end) end; if p.sentry == s then p.sentry = nil; p.powerLabel = nil end; wlog("P%d Sentry Probe gone", i) end)
    wlog("P%d Sentry Probe out (runs on the bar; LT sends it home)%s", i, drone and "" or " (no drone model)")
end

OK.addTickJob("mindPowerFx", 0.0, function()
    local now = os.clock()
    local dt = math.min(0.1, now - (fx.at or now))
    fx.at = now
    if dt <= 0 then return end
    pcall(updateArcs)
    pcall(marksTick)
    local k = 1
    while k <= #fx.jobs do
        local j = fx.jobs[k]
        local ok, keep = pcall(j.fn, dt)
        if not ok then wlog("%s failed: %s", j.name, tostring(keep)) end
        if ok and keep then
            k = k + 1
        else
            table.remove(fx.jobs, k)
            if j.cleanup then pcall(j.cleanup) end
        end
    end
    for key, f in pairs(fx.fires) do
        local ok, keep = pcall(fireTick, f, dt)
        if not (ok and keep) then fx.fires[key] = nil end
    end
end)

-- Reading minds refills concentration, like the 2005 game: hold Y (Cortex Scan) on a living
-- person; once the read lands, several dots come back. One read per person every so often.
local readAt = {}   -- npc key -> time it was last read
OK.onWorldChange(function() readAt = {} end)
local function scanTarget(pc, pawn)
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    local t = nil
    if mental then pcall(function() t = mental:GetCurrentAimTarget() end) end
    if valid(t) and OK.keyOf(t) ~= OK.keyOf(pawn) and t:IsA(StaticFindObject("/Script/Engine.Character")) then
        return t
    end
    -- fall back to whoever is nearest the middle of the screen, close by
    local hit = cone(pc, pawn, 1800, 0.93)
    local best, bd = nil, -1
    local okR, rot = pcall(function() return pc.PlayerCameraManager:GetCameraRotation() end)
    if not okR then return hit[1] and hit[1].n end
    local fx, fy = math.cos(math.rad(rot.Yaw)), math.sin(math.rad(rot.Yaw))
    for _, e in ipairs(hit) do
        local d = e.fx * fx + e.fy * fy
        if d > bd then best, bd = e.n, d end
    end
    return best
end
local scanCache = {}
local function scanAbility(pawn)
    local key = OK.keyOf(pawn)
    local c = scanCache[key]
    if c and os.clock() - c.at < 2.0 and (c.ab == false or valid(c.ab)) then return c.ab or nil end
    local found = nil
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    if mental then
        for _, ab in ipairs(state.p2Abilities(mental)) do
            if valid(ab) and OK.nameOf(ab):find("CortexScan") then found = ab; break end
        end
    end
    scanCache[key] = { ab = found or false, at = os.clock() }
    return found
end
local function readMinds(i, p, pc, pawn, dt)
    -- the game's own Cortex Scan: the moment it locks onto a new mind, that's a read
    local ab = scanAbility(pawn)
    if ab then
        local t = nil
        pcall(function() local a = ab.m_pActiveTarget; if valid(a) then t = a end end)
        local k = t and OK.keyOf(t) or nil
        if k and k ~= p.scanKey then
            local now = os.clock()
            if not (readAt[k] and now - readAt[k] < CFG.SCAN_SAME_PERSON) then
                readAt[k] = now
                local before = p.pool or 1.0
                p.pool = math.min(1.0, before + CFG.SCAN_REFILL_DOTS * DOT)
                wlog("P%d read a mind: concentration %d -> %d dots", i, math.floor(before / DOT + 0.5), math.floor(p.pool / DOT + 0.5))
            end
        end
        p.scanKey = k
        return
    end
    local y = kbDown(pc, "Gamepad_FaceButton_Top")
    if not y then p.readOn, p.readT = nil, 0 return end
    local t = scanTarget(pc, pawn)
    if not (valid(t) and not (state.deadChar and state.deadChar(t))) then p.readOn, p.readT = nil, 0 return end
    local k = OK.keyOf(t)
    if p.readOn ~= k then p.readOn, p.readT = k, 0 end
    p.readT = (p.readT or 0) + dt
    if p.readT < CFG.SCAN_SECONDS then return end
    local now = os.clock()
    if readAt[k] and now - readAt[k] < CFG.SCAN_SAME_PERSON then return end
    readAt[k] = now
    local before = p.pool or 1.0
    p.pool = math.min(1.0, before + CFG.SCAN_REFILL_DOTS * DOT)
    wlog("P%d read a mind: concentration %d -> %d dots", i, math.floor(before / DOT + 0.5), math.floor(p.pool / DOT + 0.5))
end

-- powers that aim by themselves: while one is picked, the game's LT lock-on finds nothing
-- (its search radius is set to 0, and put back when another power is picked)
local NO_LOCK = { ["Cloak & Deflector"] = true, ["Furon Sentry Probe"] = true, ["Psychic Tether"] = true,
                  ["Free Love"] = true, ["Free Fear"] = true }
local function lockOnFor(p, pawn)
    local pw = POWERS[p.power or 1]
    -- only while LT is down: PK's yellow arcs use the same search, so it stays on otherwise
    local off = pw and NO_LOCK[pw.name] and p.ltWas or false
    local fm = subObj(pawn, "m_pFocusComponent")
    if not fm then return end
    if off and not p.lockSaved then
        local okR, r = pcall(function() return fm.m_fAutoLockRadius end)
        local okA, a = pcall(function() return fm.m_fFirstAutoLockMaxAngle end)
        p.lockSaved = { fm = fm, r = okR and r or nil, a = okA and a or nil }
        pcall(function() fm.m_fAutoLockRadius = 0.0 end)
        pcall(function() fm.m_fFirstAutoLockMaxAngle = 0.0 end)
    end
    if off then
        -- drop any lock the game already picked up this press
        pcall(function() if fm.m_pCurrentAutoLockTarget ~= nil and valid(fm.m_pCurrentAutoLockTarget) then fm.m_pCurrentAutoLockTarget = nil end end)
    end
    if off then
    elseif (not off or p.lockSaved and p.lockSaved.fm ~= fm) and p.lockSaved then
        local sv = p.lockSaved
        p.lockSaved = nil
        if valid(sv.fm) then
            if sv.r then pcall(function() sv.fm.m_fAutoLockRadius = sv.r end) end
            if sv.a then pcall(function() sv.fm.m_fFirstAutoLockMaxAngle = sv.a end) end
        end
    end
end

local function powersTick(i, p, pc, pawn)
    pcall(lockOnFor, p, pawn)
    local now = os.clock()
    local dt = math.min(0.1, now - (p.powAt or now))
    p.powAt = now
    p.pool = math.min(1.0, (p.pool or 1.0) + dt * DOT / CFG.POWER_DOT_SECONDS)   -- a dot every few seconds
    if state.endlessConc then p.pool = 1.0 end   -- trainer: endless concentration
    pcall(readMinds, i, p, pc, pawn, dt)
    local pw = POWERS[p.power or 1]
    local lt = kbDown(pc, "Gamepad_LeftTrigger")
    local pressed = lt and not p.ltWas
    p.ltWas = lt
    if not (pw and pw.cast and CAST[pw.cast]) or CFG.MIND_POWERS == false then return end
    local ok, err = pcall(CAST[pw.cast], i, p, pc, pawn, pressed, lt, dt)
    if not ok and not p.castErr then p.castErr = true; wlog("P%d %s failed: %s", i, pw.name, tostring(err)) end
end

OK.addTickJob("mindPowerTimers", 0.1, function()
    local now = os.clock()
    for k = #timers, 1, -1 do
        if now >= timers[k].at then
            local t = table.remove(timers, k)
            pcall(t.fn)
        end
    end
    for k, f in pairs(frozen) do
        local hp = valid(f.n) and OK.healthRatio(f.n) or nil
        if valid(f.n) and type(hp) == "number" and type(f.hp) == "number" and hp < f.hp - 0.0001 then
            -- hit while frozen: shatter
            setFrozen(f.n, false)
            pcall(function()
                local dc = subObj(f.n, "m_pDamageComponent")
                dc:ApplyAndReportDamage(f.n, 100000, f.by, f.by, StaticFindObject("/Script/Engine.DamageType"), true)
            end)
            if state.gameDamage then pcall(state.gameDamage, f.n, 99999, f.by) end   -- make sure they go
            pcall(function() f.n.Mesh:AddImpulse({ X = 0, Y = 0, Z = 300 }, FName("None"), true) end)
            frozen[k] = nil
            wlog("a frozen person shattered")
        elseif now >= f.untilT or not valid(f.n) then
            if valid(f.n) then
                setFrozen(f.n, false)
                -- thawed unhurt: their health back
                if type(f.realHp) == "number" and (OK.healthRatio(f.n) or 0) > 0 then
                    pcall(function() OK.setRatio(OK.stat(f.n, "m_pHealthStat"), f.realHp) end)
                end
            end
            frozen[k] = nil
            for _, pp in ipairs(P) do if pp.cryoAcc then pp.cryoAcc[k] = nil end end
        end
    end
    -- people slowed but not frozen thaw once nobody is freezing them
    for _, pp in ipairs(P) do
        if pp.cryoAcc and not pp.ltWas then
            for k, _ in pairs(pp.cryoAcc) do
                if not frozen[k] then
                    for _, n in ipairs(npcCache) do
                        if valid(n) and OK.keyOf(n) == k then pcall(function() n.CustomTimeDilation = 1.0 end) end
                    end
                    pp.cryoAcc[k] = nil
                end
            end
        end
    end
end)

------------------------------------------------------------------------------------------
-- Every frame
------------------------------------------------------------------------------------------
local function edge(p, pc, key)
    p.down = p.down or {}
    local d = kbDown(pc, key)
    local was = p.down[key]
    p.down[key] = d
    return d and not was
end

local function equip(i, pawn, wi)
    local list, cur, eq = weaponsOf(pawn)
    local w = findWeapon(list, WEAPONS[wi])
    if not (eq and w) then wlog("P%d: %s not found", i, WEAPONS[wi].label) return end
    if valid(cur) and OK.keyOf(cur) == OK.keyOf(w) then return end
    -- remember the one in hand, for the LB quick swap
    for wj, e in ipairs(WEAPONS) do
        local wv = findWeapon(list, e)
        if wv and valid(cur) and OK.keyOf(wv) == OK.keyOf(cur) then P[i].prevWi = wj end
    end
    local ok = pcall(function() eq:RequestWeaponEquipped(w) end)
    if not ok then
        ok = pcall(function() eq:RequestWeaponEquippedByClass(w:GetClass()) end)
    end
    wlog("P%d switches to %s (%s)", i, WEAPONS[wi].label, ok and "ok" or "the game refused")
end

-- Tap LB (shorter than LB_TAP_TIME): swap to the weapon used before, like the game's own
-- quick swap. Hold LB: the wheel.
local function quickSwap(i, pawn)
    local list, cur = weaponsOf(pawn)
    local curWi = nil
    for wi, e in ipairs(WEAPONS) do
        local w = findWeapon(list, e)
        if w and valid(cur) and OK.keyOf(w) == OK.keyOf(cur) then curWi = wi end
    end
    local p = P[i]
    local want = p.prevWi
    if not (want and want ~= curWi and findWeapon(list, WEAPONS[want])) then
        want = nil
        for step = 1, #WEAPONS do
            local wi = ((curWi or 0) + step - 1) % #WEAPONS + 1
            if wi ~= curWi and findWeapon(list, WEAPONS[wi]) then want = wi break end
        end
    end
    wlog("P%d LB tap: quick swap to %s", i, want and WEAPONS[want].label or "nothing (no other weapon found)")
    if want then equip(i, pawn, want) end
end

OK.addTickJob("mindWheel", 0.0, function()
    if not CFG.MIND_WHEEL then
        -- the mod's wheel switched off: the game's own wheel shows again
        local any = false
        for _, v in pairs(state.gameMenuHidden or {}) do any = any or v end
        if any then for _, pc in ipairs(controllers()) do local pw = getPawn(pc); if valid(pw) then pcall(hideGameMenuOf, pw) end end end
        return
    end
    local anyOpen = false
    for i, pc in ipairs(controllers()) do
        local p = P[i]
        local pawn = getPawn(pc)
        local lb = valid(pc) and kbDown(pc, "Gamepad_LeftShoulder")
        if valid(pawn) then pcall(hideGameMenuOf, pawn) end
        -- the game's wheel button stays taken away on foot (per body: a new body gets it again)
        if onFoot(pawn) and OK.keyOf(pawn) == p.panelPawn and os.clock() >= (p.panelWait or math.huge) then
            local pk = OK.keyOf(pawn)
            if closeGameWheel(pawn) then
                p.gameWheelAt = os.clock()
                if not p.closeLogged then p.closeLogged = true; wlog("P%d: closed the game's own wheel", i) end
            end
        end
        local pkBusy = state.pkHolding and state.pkHolding[i]
        -- the game's own weapon wheel never stays up on foot (it could flash open on LB)
        if onFoot(pawn) and (lb or (p.lbUpAt and os.clock() - p.lbUpAt < 1.0)) then pcall(closeGameWheel, pawn) end
        if not lb and p.lbDownAt then p.lbUpAt = os.clock() end
        local tapT = CFG.LB_TAP_TIME or 0.25
        if lb then
            p.lbDownAt = p.lbDownAt or os.clock()
            if not p.lbPressAt then p.lbPressAt, p.lbPicked = os.clock(), false end
            -- Crypto's own buttons pause from the moment LB goes down (the game's own wheel
            -- flashed open during the short wait for a tap)
            if onFoot(pawn) and not state.trainerOpen and not pkBusy and not p.inputOff then
                pcall(function() pawn:DisableInput(pc) end)
                p.inputOff = { pawn = pawn, pc = pc }
            end
            if onFoot(pawn) then pcall(closeGameWheel, pawn) end
        else
            if p.lbDownAt and not p.overlay and not p.inputOff and os.clock() - p.lbDownAt < tapT
               and onFoot(pawn) and not state.trainerOpen and not pkBusy then
                quickSwap(i, pawn)
                p.lbPressAt = nil
            end
            p.lbDownAt = nil
        end
        local lbHeld = lb and (p.overlay or os.clock() - p.lbDownAt >= tapT)
        if lbHeld and onFoot(pawn) and not state.trainerOpen and not pkBusy then
            anyOpen = true
            -- while choosing, Crypto's own buttons are paused (the trainer menu does the same);
            -- the mod still reads the pad directly. The game's button list is never edited.
            if not p.inputOff then
                pcall(function() pawn:DisableInput(pc) end)
                p.inputOff = { pawn = pawn, pc = pc }
                if CFG.WHEEL_PROTECT then wheelProtect(pawn, true) end
            end
            -- frozen in place while choosing, also in the air or on the jetpack
            local cm = subObj(pawn, "CharacterMovement")
            if cm then
                if not p.frozenGrav then
                    local okG, g = pcall(function() return cm.GravityScale end)
                    p.frozenGrav = { cm = cm, g = okG and g or 1.0 }
                    pcall(function() cm.GravityScale = 0.0 end)
                end
                pcall(function() cm.Velocity = { X = 0, Y = 0, Z = 0 } end)
            end
            if CFG.WHEEL_PROTECT then
                -- standing still in the menu: nobody can hurt you (or see you)
                pcall(function() OK.setRatio(OK.stat(pawn, "m_pShieldStat"), 1.0) end)
                pcall(function() OK.setRatio(OK.stat(pawn, "m_pHealthStat"), 1.0) end)
            end
            if not (p.overlay and valid(p.overlay.widget)) then
                if state.setHudHidden then pcall(state.setHudHidden, i, true) end
                p.overlay = buildOverlay(i, pc)
                p.pending = nil
                p.down = {}
                for _, e in ipairs(WEAPONS) do p.down[e.key] = kbDown(pc, e.key) end
                if p.overlay and not p.logged then p.logged = true; wlog("P%d's wheel works", i) end
            end
            for wi, e in ipairs(WEAPONS) do
                if edge(p, pc, e.key) then p.pending = wi; p.lbPicked = true end
            end
            local sel = p.sel or 1
            local r, c = (sel - 1) // 4, (sel - 1) % 4
            if edge(p, pc, "Gamepad_DPad_Up") then r = (r + 3) % 4 end
            if edge(p, pc, "Gamepad_DPad_Down") then r = (r + 1) % 4 end
            if edge(p, pc, "Gamepad_DPad_Left") then c = (c + 3) % 4 end
            if edge(p, pc, "Gamepad_DPad_Right") then c = (c + 1) % 4 end
            local newSel = r * 4 + c + 1
            if newSel > #POWERS then newSel = #POWERS end  -- the grid's last square can be empty
            if newSel ~= sel then
                p.lbPicked = true
                p.sel = newSel
                -- only ready powers become the LT power; the rest are just shown
                if POWERS[newSel].ready then p.power = newSel end
            end
            refreshOverlay(p, pawn)
            -- the borrowed widget class hides itself now and then: keep it showing
            pcall(function()
                local w = p.overlay and p.overlay.widget
                if w and not w:IsVisible() then w:SetVisibility(4) end
                if w then w:SetRenderOpacity(1.0) end
            end)
        elseif p.overlay or p.inputOff then
            if p.inputOff then
                local io2 = p.inputOff
                p.inputOff = nil
                if valid(io2.pawn) then pcall(function() io2.pawn:EnableInput(io2.pc) end) end
                if CFG.WHEEL_PROTECT and valid(io2.pawn) and not (p.cloakUntil and os.clock() < p.cloakUntil) and state.trIgnore ~= "On" then
                    wheelProtect(io2.pawn, false)
                end
            end
            if p.frozenGrav then
                local fg = p.frozenGrav
                p.frozenGrav = nil
                if valid(fg.cm) then pcall(function() fg.cm.GravityScale = fg.g end) end
            end
            closeOverlay(p)
            if state.setHudHidden then
                pcall(state.setHudHidden, i, false)
                -- and once more a moment later: the game can redraw parts of the HUD after the menu
                OK.later(0.4, "wheelHudBack", function() pcall(state.setHudHidden, i, false) end)
            end
            local wi = p.pending
            p.pending = nil
            -- a short press that only flashed the wheel open (nothing picked): still a quick swap
            if not wi and not p.lbPicked and p.lbPressAt and os.clock() - p.lbPressAt < (CFG.LB_TAP_MAX or 0.5) and onFoot(pawn) then
                OK.later(0.15, "wheelQuickSwap", function() quickSwap(i, pawn) end)
            end
            p.lbPressAt = nil
            if wi and onFoot(pawn) then
                -- after the game has closed its own (hidden) wheel, so it doesn't undo the switch
                OK.later(0.15, "wheelEquip", function() equip(i, pawn, wi) end)
            end
        end

        -- the power panel
        if onFoot(pawn) and not p.overlay and not state.trainerOpen then powersTick(i, p, pc, pawn) end
        -- the panel waits a few seconds after a new body appears (the game is still busy
        -- setting up its own HUD right after a map loads)
        local pk2 = onFoot(pawn) and OK.keyOf(pawn) or nil
        if pk2 ~= p.panelPawn then p.panelPawn, p.panelWait = pk2, os.clock() + (CFG.WHEEL_START_DELAY or 0) end
        if CFG.WHEEL_PANEL and onFoot(pawn) and os.clock() >= (p.panelWait or 0) then
            if not (p.panel and valid(p.panel.widget)) then p.panel = buildPanel(i, pc) end
            if p.panel then
                local pw = POWERS[p.power or 1]
                setText(p.panel.name, p.powerLabel or (((p.power or 1) == 1) and "" or pw.name))
                if p.panel.iconFor ~= pw.name then
                    p.panel.iconFor = pw.name
                    local shown = (p.power or 1) ~= 1 and setPowerIcon(p.panel.icon, pw.name)
                    pcall(function() p.panel.icon:SetVisibility(shown and 4 or 2) end)
                end
                pcall(function() p.panel.lt:SetVisibility((p.power or 1) ~= 1 and 4 or 2) end)
                setMeter(p.panel, concentration(pawn, p))
                placePanel(i, p)
                pcall(function()
                    local w = p.panel.widget
                    if p.overlay or state.hudAllHidden then w:SetVisibility(2)   -- only the wheel shows while it's open; nothing while every HUD is hidden
                    else
                        if not w:IsVisible() then w:SetVisibility(4) end
                        w:SetRenderOpacity(1.0)
                    end
                end)
            end
        elseif p.panel and valid(p.panel.widget) then
            pcall(function() p.panel.widget:SetVisibility(2) end)
        end
    end
    -- leftovers for a player who left
    local present = #controllers()
    for slot = 2, 4 do
        if slot > present then
            if P[slot].overlay then closeOverlay(P[slot]) end
            if P[slot].panel and valid(P[slot].panel.widget) then pcall(function() P[slot].panel.widget:RemoveFromParent() end) end
            P[slot].panel = nil
        end
    end
    if anyOpen then keepFullSpeed() end
end)

wlog("loaded (hold LB)")

-- Effect catalog: NumPad . plays the next of EVERY particle effect the game has (Shift+NumPad .
-- goes back), in front of Player 1, with its number and name on screen. The whole list, with
-- numbers, is written to overkill_fx_catalog.txt next to the game, so effects can be named by
-- number ("put 214 on the shockwave").
local fxCat, fxCatIdx = nil, 0
local function buildFxCatalog()
    local list, seen = {}, {}
    local function addPath(path)
        if path and path ~= "" and not seen[path] then seen[path] = true; list[#list + 1] = path end
    end
    -- everything on disk in the whole game, from the game's asset registry: by class first,
    -- then by folder (whichever this build answers)
    local reg = nil
    pcall(function() reg = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers"):GetAssetRegistry() end)
    local function take(out)
        for _, ad in ipairs(out) do
            pcall(function()
                local cls = ad.AssetClass:ToString()
                if cls == "ParticleSystem" then addPath(ad.ObjectPath:ToString()) end
            end)
        end
    end
    if reg then
        pcall(function() local out = {}; reg:GetAssetsByClass(FName("ParticleSystem"), out, true); take(out) end)
        if #list == 0 then pcall(function() local out = {}; reg:GetAssetsByPath(FName("/Game"), out, true, false); take(out) end) end
        if #list == 0 then pcall(function() local out = {}; reg:GetAssetsByPath(FName("/Game/VFX"), out, true, false); take(out) end) end
    end
    if not reg then wlog("Effect catalog: the game's asset registry isn't available, using loaded effects only") end
    local fromRegistry = #list
    -- plus whatever is loaded right now (in case the registry gave nothing)
    pcall(function()
        for _, ps in ipairs(FindAllOf("ParticleSystem") or {}) do
            pcall(function()
                local full = ps:GetFullName()
                local path = full:match("^%S+%s+(.+)$") or full
                if not path:find(":") then addPath(path) end
            end)
        end
    end)
    table.sort(list, function(a, b) return (a:match("[^/]+$") or a):lower() < (b:match("[^/]+$") or b):lower() end)
    pcall(function()
        local f = io.open("overkill_fx_catalog.txt", "w")
        if f then
            f:write("# Every particle effect the mod could find (number, name, path). NumPad . plays them in order,\n# Shift+NumPad . goes back. Tell Claude a number or a name to put an effect on a power.\n")
            for k, path in ipairs(list) do f:write(string.format("%4d  %s  %s\n", k, path:match("([^%.]+)$") or path, path)) end
            f:close()
        end
    end)
    wlog("Effect catalog: %d effects (%d from the asset registry), written to overkill_fx_catalog.txt", #list, fromRegistry)
    return list
end
local function playCatalog(step)
    fxCat = fxCat or buildFxCatalog()
    if #fxCat == 0 then return end
    fxCatIdx = ((fxCatIdx - 1 + step) % #fxCat) + 1
    local pawn = getPawn(OK.player1Controller())
    local l = valid(pawn) and locOf(pawn)
    if not l then return end
    local fx0, fy0 = camDir(OK.player1Controller())
    local at = { X = l.X + fx0 * 450, Y = l.Y + fy0 * 450, Z = l.Z - 40 }
    local path = fxCat[fxCatIdx]
    local name = path:match("([^%.]+)$") or path
    local folder = path:match("/([^/]+)/[^/]+$") or ""   -- e.g. PSY_Mutan, so the name says where it's from
    if folder ~= "" then name = folder .. " / " .. name end
    local c = state.playFx(path, at, 1.0)
    local msg = string.format("Effect %d / %d:  %s%s", fxCatIdx, #fxCat, name, c and "" or "  (didn't play)")
    if state.toast then pcall(state.toast, msg, 4.0) end
    wlog("%s  (%s)", msg, path)
end
if Key.DECIMAL ~= nil then
    RegisterKeyBind(Key.DECIMAL, function()
        if state.freecamOn or state.kbOn then return end
        OK.runGame("fxCatalog", function() playCatalog(1) end)
    end)
    pcall(function()
        RegisterKeyBind(Key.DECIMAL, { ModifierKey.SHIFT }, function()
            if state.freecamOn or state.kbOn then return end
            OK.runGame("fxCatalogBack", function() playCatalog(-1) end)
        end)
    end)
    -- Ctrl+NumPad . skips ahead 10 (the list is long)
    pcall(function()
        RegisterKeyBind(Key.DECIMAL, { ModifierKey.CONTROL }, function()
            if state.freecamOn or state.kbOn then return end
            OK.runGame("fxCatalogSkip", function() playCatalog(10) end)
        end)
    end)
end
