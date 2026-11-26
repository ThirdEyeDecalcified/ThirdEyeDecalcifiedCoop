--[[
    Destroy All Humans! 2020 Overkill Coop - split screen, second player and trainer
    (part of the Overkill Coop mod; loaded by main.lua)

    Keys (all with CTRL held):
        Ctrl+Y            spawn Player 2 (new local player + controller + pawn)
        Ctrl+T            teleport Player 2 to Player 1
        Ctrl+Shift+T      teleport Player 1 to Player 2
        Ctrl+I            remove Player 2
        Ctrl+K            dump debug info (controllers / pawns / local players)

    Everything logs to the UE4SS console with the prefix [OverkillCoop] and to
    overkill_coop_log.txt next to the game exe.
]]

local UEHelpers = require("UEHelpers")

local MOD = "OverkillCoop"

------------------------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------------------------
local CFG = {
    -- Controller IDs tried in order for Player 2. 0 is normally Player 1 (keyboard + pad 0),
    -- so 1 = second gamepad. If 1 is taken, 2 and 3 are tried.
    P2_CONTROLLER_IDS = { 1, 2, 3 },

    -- If the GameMode gives Player 2 a pawn of a different class than Player 1's (e.g. a
    -- spectator or nothing), spawn a copy of Player 1's pawn class (Crypto) and possess it.
    CLONE_P1_PAWN_CLASS = true,

    -- Wait this long after CreatePlayer for the GameMode to hand out a pawn before we
    -- check and (if needed) spawn our own.
    PAWN_CHECK_DELAY_MS = 750,

    -- Where the second pawn appears relative to Player 1 (Unreal units, 100 = 1 meter).
    SPAWN_OFFSET_RIGHT = 200.0,
    SPAWN_OFFSET_Z     = 80.0,

    -- GameplayStatics:SetForceDisableSplitscreen does not exist in this build (UE 4.22), and
    -- splitscreen already works, so this is off. If on, we only try to clear the viewport flag.
    FORCE_ENABLE_SPLITSCREEN = false,

    -- Keyboard fallback for Player 2 (Ctrl+B toggles it). Key names are UE FKey names.
    -- Pick keys the game doesn't use for Player 1.
    KB = {
        forward = "I", back = "K", left = "J", right = "L",
        -- (The arrow keys are used by Player 1 in-game, so Player 2 turns with the numpad aim keys below.)
        jump = "N",
        -- Numpad aiming for Player 2 (moves the camera, and so the crosshair)
        lookLeft = "NumPadSeven", lookRight = "NumPadNine",
        lookUp = "NumPadEight", lookDown = "NumPadFive",
        -- Numpad 1-4 (weapon select) and "/" (console) are used by the game, so they are avoided.
        -- Keep NumLock ON.
        fire = "NumPadZero",
        nextWeapon = "Add", prevWeapon = "Subtract",   -- numpad + and -
        dash = "Decimal",                              -- numpad .
        mental = "Multiply",                           -- numpad *
        ads = "NumPadSix",                             -- hold to aim down sights
    },
    -- Player 2 mental abilities (hold the key to use): { key, ability name fragment }. Numpad * = telekinesis.
    MENTAL_KEYS = {
        { "F1", "CortexScan" },      -- mind reading
        { "F2", "ExtractBrain" },
        { "F3", "Holobob" },
        { "F4", "Psycokinesis" },   -- telekinesis (also numpad *)
        { "F5", "Distract" },
        { "F6", "Follow" },
        { "F7", "Forget" },
        { "F8", "Transmogrify" },
        { "F9", "MentalInteraction" },
    },
    KB_INVERT_PITCH = false,  -- flip this if numpad 8/2 aim the wrong way
    KB_TURN_RATE = 1.0,   -- yaw input per tick while a turn key is held
    KB_TICK_MS   = 33,    -- polling interval (about 30 Hz)
    KB_SYNC_MOVEMENT_FROM_P1 = true,  -- on toggle, copy P1's movement tuning to P2 (speed, accel, jump)
    KB_WALK_SPEED_OVERRIDE = nil,     -- e.g. 600.0 forces P2's MaxWalkSpeed while a move key is held
    KB_LOG_SPEED = true,              -- print P2's real speed about once a second while moving
    KB_FALLBACK_MS = 8,               -- only used if the per-frame hook cannot be registered
    HUD_REBIND_AFTER_MOVE = false,
    HUD_RECONNECT = true,             -- after moving a HUD, let its pieces (radar, alerts...) reconnect to the game    -- (off: hooking the HUD's events twice made the threat display blink)
    RADAR_FEED = true,               -- (old) push radar updates ourselves; not needed with AUTO_HUD_MODE "anchors"     -- after moving a HUD to its half, let it re-hook its events (radar)
    AUTO_HUD_MODE = "per_half",        -- "anchors" (each HUD told to use its half, stays connected), "per_half" (old), "p1_only", "none"       -- after spawning P2: "per_half" (each player's HUD on their half), "p1_only", or "none"

    -- Swap which character the gamepad/keyboard drives (Ctrl+X, or hold this gamepad combo).
    SWAP_COMBO_ENABLED = false,       -- old workaround from before pad 2 worked; off now that both pads are real
    ALL_DEV_KEYS = false,             -- true = also the old experiment / diagnostic shortcuts
    SWAP_PAD_COMBO = { "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick" },  -- L3 + R3
    SWAP_HOLD_SECONDS = 0.7,
    SWAP_REREGISTER_HUD_PROVIDERS = true,  -- try to point the HUD's data at the character you drive

    AUTO_KEYBOARD = false,            -- keyboard driver for P2 (Ctrl+B). Off: pad 2 now drives P2 natively (DAHPadRouter)

    -- Pad features (need the DAHPadRouter xinput DLL):
    PAD_SPAWN_ON_START = true,        -- press Start on pad 2 to spawn Player 2 (same as Ctrl+Y)
    TELEPORT_COMBO = { "Gamepad_Special_Left", "Gamepad_LeftThumbstick" },  -- Select/View + L3: bring the other player to you
    -- Player 2's camera doesn't get the game's invert setting (it only goes to Player 1).
    -- true = flip that stick direction for Player 2 after spawning.
    P2_INVERT_LOOK_Y = true,          -- right stick up/down
    P2_INVERT_LOOK_X = false,         -- right stick left/right
    AUTO_SYNC_PROGRESS = true,        -- give Player 2 Player 1's upgrades/unlocks after spawning
    SPLIT_LAYOUT = "vertical",        -- "horizontal" = top/bottom, "vertical" = left/right (Ctrl+O toggles)
    SPLIT_AIM_FIX = false,
    -- Co-op downed system (instead of reloading the checkpoint when one player dies)
    DOWNED_SYSTEM = true,
    P2_PICKUPS = true,                -- brains/ammo Player 2 touches go to Player 1 (shared); stuck probes cleared
    P2_PICKUP_RADIUS = 180,
    P2_PROBE_RADIUS = 220,
    P2_PROBE_DEBUG = false,
    P2_PROBE_CLEAR = false,           -- (off: it removed the probes loaded in the gun, which jammed it)            -- log probes near Player 2 (to tune the clean-up)            -- a probe sitting this close to Player 2 for 1 s is cleared
    PARTNER_MARKERS = true,           -- "P1"/"P2" tag over the partner's head
    PARTNER_RADAR_DOT = false,        -- (off) the partner's dot on the radar
    PARTNER_TAG_RANGE = 1000000,      -- show the tag within this distance (game units; 100 = 1 m)
    PARTNER_TAG_HEIGHT = 140,
    RADAR_DOT_SIZE = 12,
    RADAR_DOT_TURN = 90,              -- degrees to turn the partner dot to match the radar (Ctrl+F11 cycles)
    RADAR_DOT_MIRROR = false,         -- flip left/right (Ctrl+Shift+F11)
    TAG_SIZE = 9,                     -- "P1"/"P2" text size
    TAG_DIST_SIZE = 8,                -- distance text size
    TAG_SKIN_ICON = true,             -- show the partner's skin icon (the game's menu art) over their head
    TAG_SKIN_ICON_SIZE = 56,
    TAG_SHOW_DISTANCE = true,
    PARTNER_LOD_RANGE = 5500,         -- distance turns red beyond this (55 m: NPCs around the far player get simplified)
    P2_SKIN_COMBO = true,             -- pad 2: hold Select + D-pad Right / Left = next / previous skin
    END_SPLIT_ON_MOTHERSHIP = true,
    MIND_WHEEL = true,
    WHEEL_REPORT = false,             -- (testing) write down the game's own wheel the first time it opens (dump_wheel.txt)
    WHEEL_START_DELAY = 3,            -- seconds the wheel waits after a map loads before setting itself up
    WHEEL_BAR_SLANT = 20,             -- how far the concentration bar leans, like the 2005 one (degrees)
    WHEEL_PANEL = true,               -- the chosen-power panel with the concentration meter, above the weapon icon
    WHEEL_PANEL_RIGHT = 70,           -- its right edge, from the right of the player's screen (at 1080p)
    WHEEL_PANEL_BOTTOM = 245,
    POWER_DOT_SECONDS = 3,            -- one dot of concentration (of 6) comes back every this many seconds         -- its bottom edge, from the bottom of the player's screen (at 1080p)                -- hold LB: the mod's mind & weapons wheel instead of the game's (no slow motion)
    NO_WEAPON_WHEEL_IN_SPLIT = true,  -- the hold-to-open weapon wheel is shared, so it's off in split screen   -- remove Player 2 when the mothership loads
    P1_COLOR = { 0.35, 1.0, 0.35 },   -- green
    P2_COLOR = { 1.0, 0.6, 0.15 },    -- orange
    P2_GAME_TARGET_MARKER = true,     -- move the game's own lock-on marker for Player 2 onto Player 2's screen
    WEAPON_ICON_FIX = true,
    P2_LOCK_RANGE = 3500,             -- how far (cm) Player 2's yellow lock-on reaches
    P2_LOCK_COS = 0.975,              -- how close to the crosshair a target must be (0.975 = about 13 degrees)
    P2_LOCK_REAL = false,             -- (test: off) the mod no longer writes Player 2's lock into the game
    P2_GUN_FOLLOW_GAME = true,
    P2_MOD_GUN_LOCK = false,          -- (off) the mod's own gun lock for Player 2 when the game has none (it made the ghost targets)
    SPLIT_VEHICLE_LOD_MULT = 1,       -- (off: tested, made no difference to empty cars)
    ALERT_CARD_SET = false,           -- (off: suspected crash) the "!!" card hook may change the level the game passes in     -- two players: cars keep their drivers and full detail this many times further from Player 1
    SPLIT_LOD_PROFILE = true,         -- two players: keep detail further out (each half-screen view is smaller, so the game drops detail sooner)
    SPLIT_LOD_COMMANDS = { "r.StaticMeshLODDistanceScale 0.6", "r.SkeletalMeshLODBias -1", "r.ViewDistanceScale 1.6", "foliage.LODDistanceScale 1.6" },
    SPLIT_LOD_RESET = { "r.StaticMeshLODDistanceScale 1", "r.SkeletalMeshLODBias 0", "r.ViewDistanceScale 1", "foliage.LODDistanceScale 1" },        -- Player 2's cyan bracket uses the game's own lock when it has one
    P2_PK_AIM_WIDEN = 2.0,
    P2_PK_GAP_HOLD = 0.25,
    PK_CROWD_PER_PLAYER = true,       -- (test, from Clone Carnage) the traffic/crowd system is told whose PK is holding something (it only knew Player 1's)
    P2_ZAP_NO_PROPS = true,           -- (test) Player 2's Zap-O-Matic doesn't take the PK target when that's a prop (it shot at far PK objects)             -- Player 2's arcs bridge the game's short PK-aim drop-outs (seconds)            -- Player 2's PK reach to the sides (the game's auto-target area x this)
    P2_TARGET_HEALTH = true,          -- Player 2 sees the health bar of what its gun is locked on to
    P2_ZAP_CHAIN = true,              -- the mod's zap chain for Player 2 (tested: the game alone doesn't chain for Player 2)
    P2_ZAP_BRACKET = true,
    P2_ZAP_ARCS = true,               -- draw the arcs of Player 2's zap chain with the game's beam effect            -- Player 2's cyan Zap-O-Matic bracket placed from Player 2's own view              -- Player 2's Zap-O-Matic arcs to the people next to its target
    P2_ZAP_TRUE_CHAIN = true,         -- jumps go person to person (from the last one hit), like the game's, not all from the first
    P2_ZAP_JUMP_EVERY = 0.4,          -- each extra jump joins after zapping the same person this much longer (seconds)
    P2_ZAP_SIDE_LIMIT = 0.2,          -- Player 2's zap won't take a shared (PK) target further to the side than this part of Player 2's view
    P2_ZAP_CHAIN_MAX = 3,             -- targets in Player 2's chain (main one included)
    P2_ZAP_CHAIN_RANGE = 900,
    P2_ZAP_CHAIN_DPS = 25,            -- arc damage per second if the main target's own loss can't be measured
    P2_YELLOW_ONLY_HOVERED = false,   -- off again (with it on, P2 hardly ever got arcs): arcs on PK's hovered thing, else the nearest target, like before
    P2_YELLOW_ONLY_PKABLE = true,     -- Player 2's yellow arcs only on things PK can really pick up
    P2_PK_RANGE = 3000,               -- most PK reach (cm) for Player 2's yellow arcs (the game's own reach is used if shorter)
    P2_ZAP_LOCK_RANGE = 1600,
    P2_WEAPON_LOCK_RANGE = 3000,      -- Player 2's lock reach (cm) for the other guns that lock on         -- Player 2's Zap-O-Matic lock reach (cm; the beam's length)
    P2_VIEW_ASPECT_H = 0.837,         -- height / width of Player 2's half of the screen
    P2_PK_AIM_ASSIST = false,         -- Player 2's PK grabs the yellow target (aim is turned onto it as RB goes down)
    P2_PK_AIM_ASSIST_TIME = 0.5,      -- for how long after RB goes down (seconds)
    P2_PK_AIM_ASSIST_SMOOTH = 0.5,
    P2_PK_CAMERA_ASSIST = false,      -- RB pulls Player 2's aim onto the arcs for a moment (the aim-point-only way didn't make PK grab)
    P2_PK_AIM_RAISE_COMP = true,      -- allow for the crosshair sitting above the aim point   -- share of the way to the target the aim moves each frame (lower = smoother)
    P2_CROSSHAIR_RAISE = -0.3,        -- the crosshair sits this far above the middle of the view (the game's m_fCrosshairOffsetY)
    P2_PK_USES_LOCK = false,          -- (off: setting PK's grab target crashed the game)
    ZAP_WATCH = true,                 -- log the Zap-O-Matic's locked targets while zapping (temporary)              -- Player 2's yellow lock is also the lock PK and the Zap-O-Matic use
    P2_MARKER_FOLLOW = true,          -- put Player 2's yellow lock-on marker over Player 2's target every frame           -- show each player's own equipped weapon in their HUD's big weapon icon
    ALERT_WATCH = false,              -- debug: log the alert system twice a second (slow, off for play)
    ALERT_CARD_HOOK = true,           -- co-op: never let the "!!" card drop while the seen hold is on
    ALERT_SEEN_HOLD = 3.0,            -- co-op: keep the "!!" seen card up this many seconds after last being seen               -- log the "!!" alert state in co-op (for bug hunting)
    HUD_HINT_SHIFT = 0,               -- (old) bottom hints moved right; now squeezed instead
    HUD_HINT_SCALE = 0.8,             -- split screen: bottom button hints shrunk toward the middle so they fit
    HUD_QUICKSLOT_SHIFT = 90,         -- split screen: bottom-right weapon buttons move this many pixels left
    GIANT_SPEED = 3.0,                -- giant Crypto moves this much faster (legs keep a normal pace)
    GIANT_FOV = 110,                  -- giant Crypto's camera field of view (wider = sees more)
    DEATHRAY_TILT = 90,               -- saucer Death Ray on foot: turned this many degrees so it fires forward
    TRAINER_PAD = true,               -- Player 1's Select + R3 opens the trainer menu (D-pad + A to use it)
    TRAINER_PAD_COMBO = { "Gamepad_Special_Left", "Gamepad_RightThumbstick" },   -- Select + R3 (Start stays the pause menu)
    P2_PROBE_RELOAD = true,
    P2_PROBE_RETURN_AFTER = 1.5,
    P2_PROBE_TIMER = 0.6,             -- seconds until a missed Player 2 probe comes back      -- seconds a missed Player 2 probe may hang around before it's sent home           -- Player 2's probe gun: reload it when a missed probe never comes back              -- log what both players' yellow lock-on markers are doing (for bug hunting)
    P2_LOCK_SIGNAL = true,            -- send Player 2's crosshair the game's "locked on" signal
    P2_MARKER = false,                -- (extra marker over Player 2's target; off while trying the game's own look)                 -- yellow diamond over Player 2's lock-on target
    MARKER_SIZE = 22,
    MARKER_USE_GAME_WIDGET = true,    -- use the game's own yellow marker look (falls back to a diamond)
    MARKER_HEIGHT = 120,
    P2_ARC_RAISE = 0,                 -- Player 2's yellow arcs: how far above the target's chest (game units)
    P2_ARC_NUDGE_X = 0,               -- ...and a screen nudge for the arcs picture (pixels)
    P2_ARC_NUDGE_Y = 0,
    P2_ARC_DIM = 0.55,
    P2_BRACKET_SHARED = false,        -- (off: it turned Player 2's cyan bracket gold)
    P2_ARCS_FOLLOW_GAME = true,       -- the arcs go on what the game's PK is aimed at for Player 2 (what RB grabs), when it has one
    CAM_WATCH_AUTO = false,           -- (test) once per session, 40 s after Player 2 joins: the DLL logs which game code reads Player 1's camera
    KEEP_PRIMARY_P1 = false,          -- keep the game's primary player on Player 1 (it moved to Player 2 after P1's jetpack: both radars followed P2)
    RADAR_OWN_CENTER = true,          -- (test) each radar is updated around its own player (P1's followed P2)
    RADAR_OWN_TURN = false,           -- (test, off) also turn each radar with its own player's camera
    TEST_RECORDER = true,             -- (test) remember the last 12 s of targeting; Guide button / Ctrl+F8 writes it to the log
    P2_TARGET_REPORT = false,         -- (test) log what the game and the mod pick for Player 2 every 2 s (Ctrl+F8 does it on demand)
    P2_BRACKET_NUDGE_X = 0,           -- Player 2's cyan lock-on bracket: screen nudge (pixels)
    P2_BRACKET_NUDGE_Y = 0,                -- arcs opacity while PK can't grab the target yet (1 when it can)
    BRACKET_HEIGHT = 20,              -- the lock-on bracket sits on the target's middle              -- how far above the target's middle (game units)
    OWN_HUD_SHIELD = false,           -- (old) drive each HUD's own shield bar (the game keeps overriding it)
    PLAYER_BARS = true,               -- split screen: each player gets their own hexagon shield bar by the split line
    HIDE_SHARED_HEALTH = true,        -- ...and the game's shared shield bar is hidden
    BAR_MARGIN = 14,
    BAR_DRAIN_PER_TICK = 0.04,        -- how fast the white "just lost" part of the bar catches up (per 0.1 s)
    OWN_DAMAGE_VIGNETTE = true,       -- the red "hurt" screen only shows for the player who was hurt
    VIGNETTE_HOLD_SECONDS = 2.0,
    VIGNETTE_LOW = 0.35,              -- below this much shield the red screen stays on for that player                  -- pixels between the bar and the split line
    HEX_SHIELD = true,                -- use the game's own hexagon shield look for the bars
    BAR_WIDTH = 34,                   -- bar thickness
    BAR_LENGTH = 380,
    DOWNED_AT_SHIELD = 0.05,          -- go down when the shield drops to this (10%), before health is hit
    DOWNED_GRACE_SECONDS = 4,         -- can't be hurt for this long after getting up
    DOWNED_BLACKOUT = 0.92,           -- how black the downed player's half gets (0..1)
    REVIVE_RADIUS = 350,              -- partner within this distance (game units, ~3.5 m) revives
    REVIVE_SECONDS = 3,               -- ...after standing there this long
    RESPAWN_MAX_SECONDS = 45,         -- nobody came: get back up next to the partner after this long
    RESPAWN_SHIELD = 0.25,            -- shield on coming back (the blue bar)            -- old Lua-only top/bottom aim trick; the DLL's aim fix replaces it
    WRITE_CROSSHAIR_VALUE = false,    -- old experiment: overwrite the HUD's crosshair value (no effect on aim)
    AIM_CENTER_FIX = true,            -- left/right split: keep each player's crosshair value at the centre of their own half
    CROSSHAIR_ABSOLUTE_COORDS = false, -- false: aim point measured from each player's own half
    RETICLE_SHIFT_MODE = 0,           -- 0 = off (the DLL aim fix already puts reticles right; shifting broke lock-on)           -- 0 off, 1 all reticles, 2 weapon reticles, 3 the 3-star reticle (Ctrl+Q cycles)
    FORCE_HIGH_LOD = false,           -- after spawning P2, force full mesh detail for all NPCs/cars (Ctrl+F3 re-applies)
    LOD_COMMANDS = { "r.ForceLOD 0", "r.SkeletalMeshLODBias -4", "r.StaticMeshLODDistanceScale 0.2" },
    SKIN_MARK_USER_CHANGED = false,   -- false = preview the skin without recording it as a player choice (safer for saves)
    POP_PREPOP_EVERY = 0,             -- seconds between "fill in the area around P2" calls while apart (0 = off; froze the game at ~90 m apart and caused the flashing cars)
    ALT_PRIMARY_MS = 500,             -- Ctrl+P (experimental): how often the game's "primary player" alternates
}

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local state = {
    p2 = nil, -- Player 2's PlayerController
}
-- Everything that remembers game objects registers a "forget" here. On a map change all the
-- old map's objects are freed, and touching a remembered one afterwards crashed the game
-- (Player 2 joining on the next map).
state.worldResets = {}
local function onWorldChange(fn) state.worldResets[#state.worldResets + 1] = fn end
-- caches that hold Player 2's objects: emptied when Player 2 leaves, so a rejoin starts clean
state.p2Leaves = {}
state.onP2Leave = function(fn) state.p2Leaves[#state.p2Leaves + 1] = fn end

-- Also written to overkill_coop_log.txt next to the game exe (the previous run is kept as
-- overkill_coop_log_prev.txt), so the log survives a crash and a restart.
local LogFile = nil
pcall(function()
    os.remove("overkill_coop_log_prev.txt")
    os.rename("overkill_coop_log.txt", "overkill_coop_log_prev.txt")
    LogFile = io.open("overkill_coop_log.txt", "w")
    if LogFile then LogFile:setvbuf("line") end
end)
local function log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    local line = ok and msg or tostring(fmt)
    print(string.format("[%s] %s\n", MOD, line))
    if LogFile then pcall(function() LogFile:write(os.date("%H:%M:%S ") .. line .. "\n"); LogFile:flush() end) end
end

local function valid(obj)
    if obj == nil then return false end
    local ok, res = pcall(function() return obj:IsValid() end)
    return ok and res == true
end

local function nameOf(obj)
    if not valid(obj) then return "<invalid>" end
    local ok, res = pcall(function() return obj:GetFullName() end)
    return ok and tostring(res) or "<unnamed>"
end

local function classNameOf(obj)
    if not valid(obj) then return "<invalid>" end
    local ok, res = pcall(function() return obj:GetClass():GetFullName() end)
    return ok and tostring(res) or "<unknown class>"
end

-- Run on the game thread with error reporting (CreatePlayer etc. must not run off-thread).
-- Only these keyboard shortcuts are active (the old experiments and diagnostics are
-- switched off). Set CFG.ALL_DEV_KEYS = true to get every old shortcut back.
do
    local keep = {
        "Y+C", "I+C", "T+C", "T+CS", "E+C",             -- spawn, remove, teleports, aim report (split is always left/right)
        "W+CS",                                          -- world scan (trainer research)
        "M+CS",                                          -- trainer menu
        "K+CS",                                          -- lock-on marker report (temporary)
        "DEL", "DELETE", "END", "F7+C", "F8+C",          -- Player 2 skin
    }
    local allowed = {}
    for _, k in ipairs(keep) do allowed[k] = true end
    local nameOfKey = {}
    for name, v in pairs(Key) do if type(v) == "number" or type(v) == "userdata" then nameOfKey[tostring(v)] = name end end
    local realBind = RegisterKeyBind
    RegisterKeyBind = function(key, a, b)
        if CFG.ALL_DEV_KEYS then return realBind(key, a, b) end
        local mods, fn = a, b
        if b == nil then mods, fn = nil, a end
        local tag = ""
        if type(mods) == "table" then
            local c, sh = false, false
            for _, m in ipairs(mods) do
                if m == ModifierKey.CONTROL then c = true elseif m == ModifierKey.SHIFT then sh = true end
            end
            tag = "+" .. (c and "C" or "") .. (sh and "S" or "")
        end
        local name = nameOfKey[tostring(key)] or "?"
        if not allowed[name .. tag] then return end
        if mods then return realBind(key, mods, fn) end
        return realBind(key, fn)
    end
end

local function runGame(label, fn)
    ExecuteInGameThread(function()
        local ok, err = pcall(fn)
        if not ok then
            log("%s: LUA ERROR: %s", label, tostring(err))
        end
    end)
end

-- Periodic jobs. They run inside a game-thread hook (the character's tick) instead of
-- LoopAsync + ExecuteInGameThread: Lua running on two threads at once is what crashes
-- UE4SS ("Ref was not function"). A single slow LoopAsync is the fallback when no
-- character is ticking (e.g. before the level loads, or while flying the saucer).
local tickJobs = {}
local function addTickJob(name, seconds, fn)
    tickJobs[#tickJobs + 1] = { name = name, interval = seconds, fn = fn, last = -1000 }
end
-- Each player's character ticks, so with two players this gets called twice a frame: the
-- second call in the same frame (under 4 ms later) is skipped. A job that keeps failing
-- writes its error once every 10 seconds, not every frame (a log write each frame stutters).
local function runTickJobs(now)
    if now - (state.lastJobsAt or -1) < 0.004 then return end
    state.lastJobsAt = now
    for _, j in ipairs(tickJobs) do
        if now - j.last >= j.interval then
            j.last = now
            local ok, err = pcall(j.fn)
            if not ok then
                j.errors = (j.errors or 0) + 1
                if now - (j.errAt or -100) >= 10 then
                    j.errAt = now
                    log("%s: LUA ERROR (%d so far): %s", j.name, j.errors, tostring(err))
                end
            end
        end
    end
end
state.runTickJobs = runTickJobs

-- "Do this in N seconds", run from the same game-thread hook (never from a timer thread).
local laterQueue = {}
local function later(seconds, label, fn)
    laterQueue[#laterQueue + 1] = { at = os.clock() + seconds, label = label, fn = fn }
end
addTickJob("later", 0, function()
    if #laterQueue == 0 then return end
    local now, due, keep = os.clock(), {}, {}
    for _, e in ipairs(laterQueue) do
        if now >= e.at then due[#due + 1] = e else keep[#keep + 1] = e end
    end
    laterQueue = keep
    for _, e in ipairs(due) do
        local ok, err = pcall(e.fn)
        if not ok then log("%s: LUA ERROR: %s", e.label, tostring(err)) end
    end
end)

local cachedStatics = nil
onWorldChange(function() cachedStatics = nil end)
local function getStatics()
    if valid(cachedStatics) then return cachedStatics end
    local ok, res = pcall(function() return UEHelpers.GetGameplayStatics() end)
    if ok and valid(res) then
        cachedStatics = res
        return res
    end
    local obj = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if valid(obj) then
        cachedStatics = obj
        return obj
    end
    return nil
end

local function getWorld()
    local ok, w = pcall(function() return UEHelpers.GetWorld() end)
    if ok and valid(w) then return w end
    local fw = FindFirstOf("World")
    if valid(fw) then return fw end
    return nil
end

-- The game state is looked up from many jobs, some every frame: remember it for a second
-- instead of searching all objects each time (one Lua state per mod, so this only affects ours).
do
    local realFindFirstOf = FindFirstOf
    local gsCache, gsAt = nil, -10
    FindFirstOf = function(name, ...)
        if name == "GameStateBase" then
            local now = os.clock()
            if now - gsAt < 1.0 and gsCache and valid(gsCache) then return gsCache end
            gsCache, gsAt = realFindFirstOf(name, ...), now
            return gsCache
        end
        return realFindFirstOf(name, ...)
    end
end

local function getPawn(controller)
    if not valid(controller) then return nil end
    local ok, pawn = pcall(function() return controller:K2_GetPawn() end)
    if ok and valid(pawn) then return pawn end
    ok, pawn = pcall(function() return controller.Pawn end)
    if ok and valid(pawn) then return pawn end
    return nil
end

local function getP1(world, statics)
    local ok, pc = pcall(function() return statics:GetPlayerController(world, 0) end)
    if ok and valid(pc) then return pc end
    return nil
end

-- Compute a point next to `target` (to its right, slightly up).
local function sideOf(target, rightOffset, zOffset)
    local loc = target:K2_GetActorLocation()
    local ok, right = pcall(function() return target:GetActorRightVector() end)
    local rx, ry, rz = 0.0, 1.0, 0.0
    if ok and right then rx, ry, rz = right.X, right.Y, right.Z end
    return {
        X = loc.X + rx * rightOffset,
        Y = loc.Y + ry * rightOffset,
        Z = loc.Z + rz * rightOffset + zOffset,
    }
end

local function teleportPawn(pawn, loc, rot)
    local ok, res = pcall(function() return pawn:K2_TeleportTo(loc, rot) end)
    if ok and res ~= false then return true end
    log("K2_TeleportTo failed (%s), trying K2_SetActorLocation...", tostring(res))
    ok, res = pcall(function() return pawn:K2_SetActorLocation(loc, false, {}, true) end)
    return ok and res ~= false
end

------------------------------------------------------------------------------------------
-- Pawn handling
------------------------------------------------------------------------------------------
local function spawnClonePawn(world, p1Pawn, p2Controller)
    local cls = nil
    local ok, res = pcall(function() return p1Pawn:GetClass() end)
    if ok and valid(res) then cls = res end
    if not cls then
        log("Could not read Player 1's pawn class - cannot clone.")
        return nil
    end

    local loc = sideOf(p1Pawn, CFG.SPAWN_OFFSET_RIGHT, CFG.SPAWN_OFFSET_Z)
    local r = p1Pawn:K2_GetActorRotation()
    local rot = { Pitch = 0.0, Yaw = r.Yaw, Roll = 0.0 }

    log("Spawning pawn of class %s at (%.0f, %.0f, %.0f)...", nameOf(cls), loc.X, loc.Y, loc.Z)
    local newPawn = nil
    ok, res = pcall(function() return world:SpawnActor(cls, loc, rot) end)
    if ok and valid(res) then
        newPawn = res
    else
        log("world:SpawnActor failed: %s", tostring(res))
        return nil
    end
    log("Spawned pawn: %s", nameOf(newPawn))
    return newPawn
end

-- Make sure Player 2 has a pawn of the right class and possesses it.
local function ensureP2Pawn()
    local world = getWorld()
    local statics = getStatics()
    if not (world and statics) then
        log("ensureP2Pawn: no world/statics.")
        return false
    end
    if not valid(state.p2) then
        log("ensureP2Pawn: Player 2 controller is gone.")
        return false
    end

    local p1 = getP1(world, statics)
    local p1Pawn = getPawn(p1)
    local p2Pawn = getPawn(state.p2)

    log("P1 pawn: %s", nameOf(p1Pawn))
    log("P2 pawn (from GameMode): %s", nameOf(p2Pawn))

    local needClone = false
    if not valid(p2Pawn) then
        needClone = true
        log("Player 2 has no pawn - will clone Player 1's pawn class.")
    elseif CFG.CLONE_P1_PAWN_CLASS and valid(p1Pawn)
        and classNameOf(p2Pawn) ~= classNameOf(p1Pawn) then
        needClone = true
        log("Player 2's pawn class (%s) differs from Player 1's (%s) - replacing.",
            classNameOf(p2Pawn), classNameOf(p1Pawn))
    end

    if not needClone then
        log("Player 2 already has a suitable pawn. Done.")
        return true
    end

    if not valid(p1Pawn) then
        log("Cannot clone: Player 1 has no valid pawn right now.")
        return false
    end
    if not CFG.CLONE_P1_PAWN_CLASS and not valid(p2Pawn) then
        log("CLONE_P1_PAWN_CLASS is false and no pawn was provided - nothing to do.")
        return false
    end

    local newPawn = spawnClonePawn(world, p1Pawn, state.p2)
    if not valid(newPawn) then
        log("FAILED: could not spawn a replacement pawn.")
        return false
    end

    -- Get rid of the unwanted default pawn, if any.
    if valid(p2Pawn) then
        pcall(function() state.p2:UnPossess() end)
        local okD = pcall(function() p2Pawn:K2_DestroyActor() end)
        log("Destroyed old P2 pawn: %s", tostring(okD))
    end

    local okP, errP = pcall(function() state.p2:Possess(newPawn) end)
    if not okP then
        log("Possess call FAILED: %s", tostring(errP))
        return false
    end

    local nowPawn = getPawn(state.p2)
    if valid(nowPawn) then
        log("SUCCESS: Player 2 now possesses %s", nameOf(nowPawn))
        return true
    end
    log("Possess returned without error, but Player 2 still has no pawn.")
    return false
end

------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------
local function spawnPlayer2()
    log("=== SPAWN PLAYER 2 requested ===")

    local world = getWorld()
    if not world then log("FAIL: no World found (are you in a map?)"); return end
    local statics = getStatics()
    if not statics then log("FAIL: GameplayStatics not found."); return end
    log("World: %s", nameOf(world))

    if valid(state.p2) or valid(state.p2Pending) then
        log("Player 2 already exists (%s). Remove it first with Ctrl+I.", nameOf(state.p2 or state.p2Pending))
        return
    end

    local p1 = getP1(world, statics)
    if not p1 then log("FAIL: Player 1 controller (index 0) not found."); return end
    log("Player 1 controller: %s", nameOf(p1))

    if CFG.FORCE_ENABLE_SPLITSCREEN then
        local vp = FindFirstOf("GameViewportClient")
        if valid(vp) then
            local ok, err = pcall(function() vp.bDisableSplitScreenOverride = false end)
            log("bDisableSplitScreenOverride=false: %s", ok and "ok" or ("failed (non-fatal): " .. tostring(err)))
        else
            log("No GameViewportClient found (non-fatal).")
        end
    end

    if state.applySplit then pcall(state.applySplit) end -- set the layout BEFORE the 2nd player exists
    local created, usedId = nil, nil
    for _, id in ipairs(CFG.P2_CONTROLLER_IDS) do
        log("Trying CreatePlayer(ControllerId=%d, bSpawnPlayerController=true)...", id)
        local ok, res = pcall(function() return statics:CreatePlayer(world, id, true) end)
        if not ok then
            log("  CreatePlayer threw: %s", tostring(res))
        elseif valid(res) then
            created, usedId = res, id
            log("  OK -> %s", nameOf(res))
            break
        else
            log("  CreatePlayer returned nil/invalid (ID in use, or game blocks extra local players).")
        end
    end

    if not created then
        log("FAIL: could not create a second local player.")
        log("  Hints: game may override GameInstance::CreateLocalPlayer, or the ControllerIds are taken.")
        log("  Try adding other IDs to CFG.P2_CONTROLLER_IDS, then press Ctrl+K and check the output.")
        return
    end

    -- The rest of the mod only sees Player 2 once the game has finished building them (in
    -- ensureP2Pawn): touching a half-made second player is what crashed the rejoin.
    state.p2Pending = created
    -- straight next to Player 1: the game puts the new body on the default landing pad
    if state.teleportP2ToP1 then pcall(state.teleportP2ToP1, created) end
    later(0.1, "p2NextToP1now", function() if valid(created) and state.teleportP2ToP1 then pcall(state.teleportP2ToP1, created) end end)

    -- Experiment: make sure Player 2's input "user" has focus on the game viewport. Without
    -- that, its gamepad events may never be delivered to Player 2's controller.
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if valid(wbl) then
        local okI, errI = pcall(function() wbl:SetInputMode_GameOnly(created) end)
        log("SetInputMode_GameOnly(Player 2): %s", okI and "ok" or ("failed: " .. tostring(errI)))
    else
        log("WidgetBlueprintLibrary not found - skipped SetInputMode_GameOnly.")
    end

    log("Player 2 controller created (ControllerId %d). Waiting %d ms for pawn...",
        usedId, CFG.PAWN_CHECK_DELAY_MS)

    later(CFG.PAWN_CHECK_DELAY_MS / 1000, "ensureP2Pawn", function()
        do
            if state.p2Pending ~= created or not valid(created) then
                state.p2Pending = nil
                log("Player 2 went away before setup finished.")
                return
            end
            state.p2, state.p2Pending = created, nil
            local ok = ensureP2Pawn()
            if ok then
                log("=== Player 2 READY (ControllerId %d). Press Ctrl+B to drive Player 2 from the keyboard; Ctrl+T teleports P2 to P1. ===", usedId)
                if state.afterSpawn then
                    local okA, errA = pcall(state.afterSpawn)
                    if not okA then log("afterSpawn error: %s", tostring(errA)) end
                end
            else
                log("=== Player 2 controller exists but pawn setup FAILED - see messages above. ===")
            end
        end
    end)
end

local function teleportP2ToP1(ctrl)
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("Teleport: no world."); return end
    local c = ctrl or state.p2
    if not valid(c) then log("Teleport: Player 2 doesn't exist (Ctrl+Y first)."); return end
    local p1Pawn, p2Pawn = getPawn(getP1(world, statics)), getPawn(c)
    if not valid(p1Pawn) then log("Teleport: Player 1 has no pawn."); return end
    if not valid(p2Pawn) then log("Teleport: Player 2 has no pawn."); return end

    local loc = sideOf(p1Pawn, CFG.SPAWN_OFFSET_RIGHT, 20.0)
    local rot = p1Pawn:K2_GetActorRotation()
    local ok = teleportPawn(p2Pawn, loc, rot)
    log("Teleport P2 -> P1: %s", ok and "OK" or "FAILED")
end

state.teleportP2ToP1 = teleportP2ToP1

local function teleportP1ToP2()
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("Teleport: no world."); return end
    if not valid(state.p2) then log("Teleport: Player 2 doesn't exist (Ctrl+Y first)."); return end
    local p1Pawn, p2Pawn = getPawn(getP1(world, statics)), getPawn(state.p2)
    if not valid(p1Pawn) then log("Teleport: Player 1 has no pawn."); return end
    if not valid(p2Pawn) then log("Teleport: Player 2 has no pawn."); return end

    local loc = sideOf(p2Pawn, CFG.SPAWN_OFFSET_RIGHT, 20.0)
    local rot = p2Pawn:K2_GetActorRotation()
    local ok = teleportPawn(p1Pawn, loc, rot)
    log("Teleport P1 -> P2: %s", ok and "OK" or "FAILED")
end

local function removePlayer2()
    log("=== REMOVE PLAYER 2 requested ===")
    -- Players 3 and 4 go first (otherwise they'd move up into Player 2's place)
    if state.removeExtraPlayers then pcall(state.removeExtraPlayers) end
    if not valid(state.p2) then
        log("No valid Player 2 to remove.")
        state.p2 = nil
        return
    end
    state.kbOn = false
    if state.swapBack then
        local okW, errW = pcall(state.swapBack)
        if not okW then log("Swap-back error: %s", tostring(errW)) end
    end
    if state.p2SaucerOff then pcall(state.p2SaucerOff) end -- back on foot before leaving
    if state.hudCleanup then
        local okC, errC = pcall(state.hudCleanup)
        if not okC then log("HUD cleanup error: %s", tostring(errC)) end
    end

    local statics = getStatics()
    local ctrl = state.p2
    local pawn = getPawn(ctrl)

    local removed = false
    if statics then
        local ok, err = pcall(function() statics:RemovePlayer(ctrl, true) end)
        log("GameplayStatics:RemovePlayer(controller, destroyPawn=true): %s",
            ok and "called" or ("failed: " .. tostring(err)))
        removed = ok
    end

    if not removed or valid(getPawn(ctrl)) then
        log("Falling back to manual cleanup (destroy pawn + controller)...")
        if valid(pawn) then pcall(function() pawn:K2_DestroyActor() end) end
        if valid(ctrl) then pcall(function() ctrl:K2_DestroyActor() end) end
    end

    state.p2 = nil
    state.p2LeftAt = os.clock()
    -- forget everything that pointed at Player 2's objects, so a rejoin starts clean
    local n = 0
    for _, fn in ipairs(state.p2Leaves) do if pcall(fn) then n = n + 1 end end
    log("Player 2 removed (state cleared, %d cache(s) emptied).", n)
    -- Player 1's HUD was set up for half the screen: put it back on the full screen once the
    -- split has closed
    later(0.5, "p1HudFull", function()
        if valid(state.p2) then return end
        if state.reseatP1Hud then pcall(state.reseatP1Hud) end
    end)
end

local function dumpInfo()
    log("=== DEBUG DUMP ===")
    log("World: %s", nameOf(getWorld()))
    local pcs = FindAllOf("PlayerController")
    if pcs then
        log("PlayerControllers: %d", #pcs)
        for i, pc in ipairs(pcs) do
            if valid(pc) then
                log("  [%d] %s  pawn=%s", i, nameOf(pc), nameOf(getPawn(pc)))
            end
        end
    else
        log("PlayerControllers: none found")
    end
    local lps = FindAllOf("LocalPlayer")
    if lps then
        log("LocalPlayers: %d", #lps)
        for i, lp in ipairs(lps) do
            if valid(lp) then log("  [%d] %s", i, nameOf(lp)) end
        end
    else
        log("LocalPlayers: none found")
    end
    log("Tracked Player 2: %s", valid(state.p2) and nameOf(state.p2) or "none")
end

------------------------------------------------------------------------------------------
-- Keybinds
------------------------------------------------------------------------------------------
RegisterKeyBind(Key.Y, { ModifierKey.CONTROL }, function()
    runGame("spawnPlayer2", spawnPlayer2)
end)

RegisterKeyBind(Key.T, { ModifierKey.CONTROL }, function()
    runGame("teleportP2ToP1", teleportP2ToP1)
end)

RegisterKeyBind(Key.T, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
    runGame("teleportP1ToP2", teleportP1ToP2)
end)

RegisterKeyBind(Key.I, { ModifierKey.CONTROL }, function()
    runGame("removePlayer2", removePlayer2)
end)

------------------------------------------------------------------------------------------
-- Diagnostics: input routing, HUD widgets, shared state (health), class dumps
------------------------------------------------------------------------------------------
local function shortName(obj)
    if not valid(obj) then return "<invalid>" end
    local ok, res = pcall(function() return obj:GetFName():ToString() end)
    return ok and tostring(res) or "<unnamed>"
end

-- Read a property and describe it (objects are shown by full name).
local function propStr(obj, field)
    local ok, v = pcall(function() return obj[field] end)
    if not ok then return "<n/a>" end
    if v == nil then return "nil" end
    if type(v) == "userdata" then
        local ok2, n = pcall(function() return v:GetFullName() end)
        return ok2 and tostring(n) or tostring(v)
    end
    return tostring(v)
end

-- Ctrl+K: per-controller details. Tells us whether P2 is really wired up like P1.
local function dumpDetailed()
    log("=== DETAILED DUMP ===")
    log("World: %s", nameOf(getWorld()))
    local pcs = FindAllOf("PlayerController")
    if not pcs then log("No PlayerControllers found."); return end
    for i, pc in ipairs(pcs) do
        if valid(pc) then
            local pawn = getPawn(pc)
            log("PC[%d] %s", i, nameOf(pc))
            log("    Player (LocalPlayer): %s", propStr(pc, "Player"))
            log("    PlayerState:          %s", propStr(pc, "PlayerState"))
            log("    MyHUD:                %s", propStr(pc, "MyHUD"))
            log("    Pawn:                 %s", nameOf(pawn))
            if valid(pawn) then
                log("    Pawn.Controller:      %s", propStr(pawn, "Controller"))
                log("    Pawn.InputComponent:  %s", propStr(pawn, "InputComponent"))
                local ok1, lc = pcall(function() return pawn:IsLocallyControlled() end)
                local ok2, pcd = pcall(function() return pawn:IsPlayerControlled() end)
                log("    IsLocallyControlled=%s IsPlayerControlled=%s",
                    ok1 and tostring(lc) or "<n/a>", ok2 and tostring(pcd) or "<n/a>")
            end
        end
    end
    -- Singletons that might hold state shared by both players (health, etc.)
    for _, cname in ipairs({ "GameStateBase", "GameInstance", "PlayerState" }) do
        local objs = FindAllOf(cname)
        if objs then
            for i, o in ipairs(objs) do
                if valid(o) then log("%s[%d]: %s", cname, i, nameOf(o)) end
            end
        else
            log("%s: none", cname)
        end
    end
end

-- Ctrl+L: for N seconds, ask EACH PlayerController which gamepad/keyboard keys it sees.
-- Move sticks / press buttons on each pad and watch which PC[n] reports them.
local ANALOG_KEYS = { "Gamepad_LeftX", "Gamepad_LeftY", "Gamepad_RightX", "Gamepad_RightY",
                      "Gamepad_LeftTriggerAxis", "Gamepad_RightTriggerAxis" }
local DIGITAL_KEYS = { "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right",
                       "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
                       "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "W", "SpaceBar" }
local probeRunning = false

local function probeInput(seconds)
    if probeRunning then log("Input probe already running."); return end
    probeRunning = true
    local stopAt = os.time() + seconds
    local lastPrint = {}
    local apiErrorLogged = false
    log("=== INPUT PROBE for %d s - move sticks / press buttons on EACH pad (and WASD) ===", seconds)

    local function tick()
        if os.time() >= stopAt then
            probeRunning = false
            log("=== INPUT PROBE finished ===")
            return
        end
        local pcs = FindAllOf("PlayerController")
        if pcs then
            for i, pc in ipairs(pcs) do
                if valid(pc) then
                    local function report(key, value)
                        local id = i .. key
                        if (lastPrint[id] or 0) + 0.5 <= os.clock() then
                            lastPrint[id] = os.clock()
                            log("  PC[%d] %s sees %s = %s", i, shortName(pc), key, tostring(value))
                        end
                    end
                    for _, k in ipairs(ANALOG_KEYS) do
                        local ok, v = pcall(function()
                            return pc:GetInputAnalogKeyState({ KeyName = FName(k) })
                        end)
                        if ok and type(v) == "number" then
                            if math.abs(v) > 0.3 then report(k, string.format("%.2f", v)) end
                        elseif not apiErrorLogged then
                            apiErrorLogged = true
                            log("  Probe API problem (GetInputAnalogKeyState): %s", tostring(v))
                        end
                    end
                    for _, k in ipairs(DIGITAL_KEYS) do
                        local ok, v = pcall(function()
                            return pc:IsInputKeyDown({ KeyName = FName(k) })
                        end)
                        if ok and v == true then report(k, "DOWN") end
                    end
                end
            end
        end
        later(0.1, "probeTick", tick)
    end
    tick()
end

-- Ctrl+H: list every UserWidget currently in the viewport with its owning player.
local function dumpWidgets()
    log("=== WIDGETS IN VIEWPORT ===")
    local ws = FindAllOf("UserWidget")
    if not ws then log("No UserWidgets found."); return end
    local n = 0
    for _, w in ipairs(ws) do
        if valid(w) then
            local okV, inVp = pcall(function() return w:IsInViewport() end)
            if okV and inVp then
                n = n + 1
                local okO, owner = pcall(function() return w:GetOwningPlayer() end)
                local okS, vis = pcall(function() return w:GetVisibility() end)
                log("  %s | class=%s | owner=%s | visibility=%s",
                    shortName(w), classNameOf(w),
                    okO and shortName(owner) or "<n/a>", okS and tostring(vis) or "<n/a>")
            end
        end
    end
    log("Widgets in viewport: %d", n)
end

-- Ctrl+J: write every property/function of the game's own classes to dump_<tag>.txt
-- (walks up the class chain until it reaches stock Engine classes).
local function dumpClassToFile(tag, obj)
    if not valid(obj) then log("dump %s: object invalid, skipped.", tag); return end
    local lines = {}
    local ok0, c = pcall(function() return obj:GetClass() end)
    local depth = 0
    while ok0 and valid(c) and depth < 12 do
        local cn = nameOf(c)
        lines[#lines + 1] = "## " .. cn
        if cn:find("/Script/Engine%.") or cn:find("/Script/CoreUObject%.") then break end
        local okP, errP = pcall(function()
            c:ForEachProperty(function(p) lines[#lines + 1] = "  P " .. p:GetFullName() end)
        end)
        if not okP then lines[#lines + 1] = "  (ForEachProperty failed: " .. tostring(errP) .. ")" end
        local okF = pcall(function()
            c:ForEachFunction(function(f)
                lines[#lines + 1] = "  F " .. f:GetFullName()
                -- parameter list (shows what arguments each function takes)
                pcall(function()
                    f:ForEachProperty(function(p) lines[#lines + 1] = "      param " .. p:GetFullName() end)
                end)
            end)
        end)
        if not okF then lines[#lines + 1] = "  (ForEachFunction unavailable)" end
        local okS, sup = pcall(function() return c:GetSuperStruct() end)
        if not okS then break end
        c = sup
        depth = depth + 1
    end

    local path = "Mods\\OverkillCoop\\dump_" .. tag .. ".txt"
    local f = io.open(path, "w")
    if not f then
        path = "dump_" .. tag .. ".txt"
        f = io.open(path, "w")
    end
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
        log("dump %s: %d lines -> %s", tag, #lines, path)
    else
        log("dump %s: could not open a file for writing (%d lines lost).", tag, #lines)
    end
end

local function dumpClasses()
    log("=== CLASS DUMPS (look for health / input / HUD variables) ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local p1 = getP1(world, statics)
    dumpClassToFile("P1_pawn", getPawn(p1))
    dumpClassToFile("P1_controller", p1)
    if valid(p1) then
        pcall(function() dumpClassToFile("PlayerState", p1.PlayerState) end)
        pcall(function() dumpClassToFile("HUD", p1.MyHUD) end)
    end
    dumpClassToFile("GameState", FindFirstOf("GameStateBase"))
    local okGI, gi = pcall(function() return UEHelpers.GetGameInstance() end)
    if okGI then dumpClassToFile("GameInstance", gi) end
end

-- Ctrl+G: compare Player 1's and Player 2's pawn sub-objects. "SAME OBJECT" means both
-- pawns point at one shared instance (a likely cause of shared health). Also dumps the
-- class layout of the key components to dump_comp_<name>.txt.
local SHARE_FIELDS = {
    "m_pStatsComponent", "m_pDamageComponent", "m_pInputActionsComponent",
    "m_pEquipmentManagerComponent", "m_pWeaponComponent", "m_pWeaponAndAbilitySelection",
    "m_pMentalAbilityComponent", "m_pJetpackPilotComponent", "m_pDashComponent",
    "m_pMissionGameplayComponent", "m_pInteractionsComponent", "m_pEffectComponent",
    "m_pGameplayEffectTagsComponent", "m_pGameplayEffectResponse", "m_pFollowCamera",
    "m_pCameraHandle", "m_pPKSpringArmComponent", "m_pTargetComponent",
    "m_pAITargetComponent", "m_pGameState",
}
local DUMP_FIELDS = {
    "m_pStatsComponent", "m_pDamageComponent", "m_pInputActionsComponent",
    "m_pEquipmentManagerComponent", "m_pWeaponAndAbilitySelection",
    "m_pMissionGameplayComponent", "m_pGameState",
    "m_pAnimationComponent", "m_pJetpackPilotComponent", "m_pWeaponComponent",
    "m_pMentalAbilityComponent", "m_pDashComponent", "m_pVariationComponent",
    "m_pInteractionsComponent", "m_pFocusComponent",
}

local function compareAndDumpComponents()
    log("=== P1 vs P2 COMPONENT COMPARISON ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local p1Pawn = getPawn(getP1(world, statics))
    local p2Pawn = getPawn(state.p2)
    if not (valid(p1Pawn) and valid(p2Pawn)) then
        log("Need both pawns - spawn Player 2 first (Ctrl+Y).")
        return
    end
    for _, field in ipairs(SHARE_FIELDS) do
        local ok1, a = pcall(function() return p1Pawn[field] end)
        local ok2, b = pcall(function() return p2Pawn[field] end)
        if not (ok1 and ok2) then
            log("  %-32s <not readable>", field)
        elseif not (valid(a) and valid(b)) then
            log("  %-32s P1=%s P2=%s", field, valid(a) and "set" or "nil", valid(b) and "set" or "nil")
        elseif nameOf(a) == nameOf(b) then
            log("  %-32s SAME OBJECT (shared!)  %s", field, nameOf(a))
        else
            log("  %-32s separate  (P1 %s | P2 %s)", field, shortName(a), shortName(b))
        end
    end
    for _, field in ipairs(DUMP_FIELDS) do
        local ok, obj = pcall(function() return p1Pawn[field] end)
        if ok then dumpClassToFile("comp_" .. field, obj) end
    end
    log("=== comparison done ===")
end

-- Compare a list of fields between two objects: prints SAME OBJECT / separate / raw values.
local function compareFields(prefix, objA, objB, fields)
    for _, field in ipairs(fields) do
        local ok1, a = pcall(function() return objA[field] end)
        local ok2, b = pcall(function() return objB[field] end)
        if not (ok1 and ok2) then
            log("  %s.%-26s <not readable>", prefix, field)
        elseif type(a) ~= "userdata" or type(b) ~= "userdata" then
            log("  %s.%-26s P1=%s P2=%s", prefix, field, tostring(a), tostring(b))
        elseif not (valid(a) and valid(b)) then
            log("  %s.%-26s P1=%s P2=%s", prefix, field,
                valid(a) and "set" or "nil", valid(b) and "set" or "nil")
        elseif nameOf(a) == nameOf(b) then
            log("  %s.%-26s SAME OBJECT (shared!)  %s", prefix, field, nameOf(a))
        else
            log("  %s.%-26s separate  (P1 %s | P2 %s)", prefix, field, shortName(a), shortName(b))
        end
    end
end

local function subObj(obj, field)
    local ok, o = pcall(function() return obj[field] end)
    if ok and valid(o) then return o end
    return nil
end

-- Second level of Ctrl+G: stat objects, input internals, controller->HUD bridge, and the
-- game-wide singletons (primary player pawn, HUD data hub, input device tracker).
local function compareDeep()
    log("=== DEEP COMPARISON (stats / input / HUD bridge) ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local p1 = getP1(world, statics)
    local p1Pawn, p2Pawn = getPawn(p1), getPawn(state.p2)
    if not (valid(p1Pawn) and valid(p2Pawn) and valid(state.p2)) then
        log("Need Player 2 spawned first (Ctrl+Y).")
        return
    end

    local s1, s2 = subObj(p1Pawn, "m_pStatsComponent"), subObj(p2Pawn, "m_pStatsComponent")
    if s1 and s2 then
        compareFields("Stats", s1, s2, { "m_pHealthStat", "m_pShieldStat", "m_pIsDeadStat",
                                         "m_pIsInvisibleStat", "m_pIsInWaterStat", "m_pGameState" })
        dumpClassToFile("stat_shield", subObj(s1, "m_pShieldStat"))
    else
        log("  Stats component missing on one pawn.")
    end

    local i1, i2 = subObj(p1Pawn, "m_pInputActionsComponent"), subObj(p2Pawn, "m_pInputActionsComponent")
    if i1 and i2 then
        compareFields("Input", i1, i2, { "m_pProcessingInputComponent", "m_pCustomWorldPointer",
                                         "m_pInputSchemeOverride", "m_iInputDeviceType",
                                         "m_eCurrentInputSchemeType" })
    else
        log("  InputActions component missing on one pawn.")
    end

    compareFields("Controller", p1, state.p2, { "m_pGameplayToHud", "m_pCheatManager", "MyHUD",
                                                "PlayerState", "PlayerCameraManager" })
    dumpClassToFile("GameplayToHud", subObj(p1, "m_pGameplayToHud"))

    -- Animation blueprint instance of Player 1's mesh (to see what drives the walk animation).
    local mesh = subObj(p1Pawn, "Mesh")
    if mesh then
        local okA, anim = pcall(function() return mesh:GetAnimInstance() end)
        if okA and valid(anim) then
            log("  P1 AnimInstance: %s", nameOf(anim))
            dumpClassToFile("AnimInstance", anim)
        else
            log("  P1 AnimInstance: not available")
        end
    end

    local okGI, gi = pcall(function() return UEHelpers.GetGameInstance() end)
    if okGI and valid(gi) then
        local tracker = subObj(gi, "m_pInputDeviceTracker")
        log("  GameInstance.m_pInputDeviceTracker: %s", nameOf(tracker))
        dumpClassToFile("InputDeviceTracker", tracker)
    end

    local gs = FindFirstOf("GameStateBase")
    if valid(gs) then
        log("  GameState.m_pLastKnownPrimaryPlayerPawn: %s", propStr(gs, "m_pLastKnownPrimaryPlayerPawn"))
        local okH, hub = pcall(function() return gs:GetHUDDataHub() end)
        if okH and valid(hub) then
            log("  GameState HUDDataHub: %s", nameOf(hub))
            dumpClassToFile("HUDDataHub", hub)
        end
    end
    log("=== deep comparison done ===")
end

RegisterKeyBind(Key.G, { ModifierKey.CONTROL }, function()
    runGame("compareAndDumpComponents", function()
        compareAndDumpComponents()
        compareDeep()
    end)
end)

-- Turn a TArray into a plain Lua list (tries ForEach first, then indexing).
local function arrayToList(arr)
    local list = {}
    if arr == nil then return list end
    pcall(function()
        arr:ForEach(function(_, elem)
            local okg, got = pcall(function() return elem:get() end)
            list[#list + 1] = (okg and got ~= nil) and got or elem
        end)
    end)
    if #list > 0 then return list end
    pcall(function()
        for i = 1, #arr do
            local elem = arr[i]
            local okg, got = pcall(function() return elem:get() end)
            list[#list + 1] = (okg and got ~= nil) and got or elem
        end
    end)
    return list
end

-- Part of Ctrl+H: which widgets does each HUD actor own, and who do they think owns them?
local function dumpHudInstances()
    log("=== HUD ACTOR INSTANCES ===")
    local pcs = FindAllOf("PlayerController")
    if not pcs then log("No PlayerControllers."); return end
    for i, pc in ipairs(pcs) do
        if valid(pc) then
            local hud = subObj(pc, "MyHUD")
            if hud then
                local ok, arr = pcall(function() return hud.m_apHUDInstances end)
                local list = ok and arrayToList(arr) or {}
                log("PC[%d] %s -> HUD %s: %d instance(s)", i, shortName(pc), shortName(hud), #list)
                for _, w in ipairs(list) do
                    if valid(w) then
                        local okO, owner = pcall(function() return w:GetOwningPlayer() end)
                        local okV, inVp = pcall(function() return w:IsInViewport() end)
                        log("    %s | owner=%s | inViewport=%s", shortName(w),
                            okO and shortName(owner) or "<n/a>", okV and tostring(inVp) or "<n/a>")
                    end
                end
            else
                log("PC[%d] %s has no HUD actor.", i, shortName(pc))
            end
        end
    end
end

-- Ctrl+M: which controller IDs do our players use, and which gamepad IDs does the engine see?
local function dumpGamepads()
    log("=== CONTROLLER / GAMEPAD IDS ===")
    -- Did the Engine.ini setting actually load? (reads the live engine settings object)
    local gms = StaticFindObject("/Script/EngineSettings.Default__GameMapsSettings")
    if valid(gms) then
        log("  GameMapsSettings.bOffsetPlayerGamepadIds = %s", propStr(gms, "bOffsetPlayerGamepadIds"))
        log("  GameMapsSettings.bUseSplitscreen = %s", propStr(gms, "bUseSplitscreen"))
    else
        log("  GameMapsSettings default object not found.")
    end
    -- Where might all gamepads be merged into one user? Dump the viewport class and the
    -- game's sign-in manager (console-style "active user" logic) to files.
    local vc = FindFirstOf("GameViewportClient")
    log("  GameViewportClient: %s", nameOf(vc))
    log("  GameViewportClient class: %s", classNameOf(vc))
    dumpClassToFile("ViewportClient", vc)
    local okG, gi = pcall(function() return UEHelpers.GetGameInstance() end)
    if okG and valid(gi) then
        local sim = subObj(gi, "m_pSignInManager")
        log("  GameInstance.m_pSignInManager: %s", nameOf(sim))
        dumpClassToFile("SignInManager", sim)
    end
    local statics = getStatics()
    local pcs = FindAllOf("PlayerController")
    if pcs and statics then
        for i, pc in ipairs(pcs) do
            if valid(pc) then
                local ok, id = pcall(function() return statics:GetPlayerControllerID(pc) end)
                log("  PC[%d] %s -> ControllerId %s", i, shortName(pc),
                    ok and tostring(id) or ("<error: " .. tostring(id) .. ">"))
            end
        end
    end
    local ksl = nil
    pcall(function() ksl = UEHelpers.GetKismetSystemLibrary() end)
    if not valid(ksl) then ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not valid(ksl) then log("  KismetSystemLibrary not found."); return end
    for id = 0, 3 do
        local okA, assigned = pcall(function() return ksl:IsControllerAssignedToGamepad(id) end)
        local okN, name = pcall(function() return ksl:GetGamepadControllerName(id) end)
        local nameStr = "<n/a>"
        if okN and name ~= nil then
            local okS, s = pcall(function() return name:ToString() end)
            nameStr = okS and tostring(s) or tostring(name)
        end
        log("  Gamepad ID %d: assigned=%s name=%s  (PC placeholder values - NOT real hardware state)",
            id, okA and tostring(assigned) or "<n/a>", nameStr)
    end
end

-- Ctrl+V: print shield/health for both pawns. Damage one player, press again, compare.
local function statValue(stat)
    if not valid(stat) then return "n/a" end
    local ok, v = pcall(function() return stat:GetValue() end)
    local ok2, r = pcall(function() return stat:GetRatio() end)
    return string.format("%s (ratio %s)", ok and tostring(v) or "?", ok2 and tostring(r) or "?")
end

local function dumpVitals()
    log("=== VITALS ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local pawns = { { "P1", getPawn(getP1(world, statics)) }, { "P2", getPawn(state.p2) } }
    for _, entry in ipairs(pawns) do
        local label, pawn = entry[1], entry[2]
        if valid(pawn) then
            local stats = subObj(pawn, "m_pStatsComponent")
            log("  %s shield=%s | health=%s", label,
                statValue(stats and subObj(stats, "m_pShieldStat")),
                statValue(stats and subObj(stats, "m_pHealthStat")))
        else
            log("  %s: no pawn", label)
        end
    end

    -- Skin info, for keyboard skin swapping later.
    local function tagStr(ps, field)
        local ok, tag = pcall(function() return ps[field] end)
        if not ok or tag == nil then return "<n/a>" end
        local ok2, name = pcall(function() return tag.TagName:ToString() end)
        return ok2 and tostring(name) or tostring(tag)
    end
    log("=== SKINS ===")
    for _, entry in ipairs({ { "P1", getP1(world, statics) }, { "P2", state.p2 } }) do
        local label, pc = entry[1], entry[2]
        local ps = subObj(pc, "PlayerState")
        if ps then
            log("  %s selected=%s default=%s", label,
                tagStr(ps, "m_oSelectedSkinTag"), tagStr(ps, "m_oDefaultSkinTag"))
        end
    end
    local tables = FindAllOf("DataTable")
    if tables then
        for _, t in ipairs(tables) do
            if valid(t) then
                local n = nameOf(t)
                local low = n:lower()
                if low:find("skin") or low:find("variation") or low:find("costume") then
                    log("  DataTable: %s", n)
                end
            end
        end
    end
end

------------------------------------------------------------------------------------------
-- Player 2 HUD helpers
------------------------------------------------------------------------------------------
local function p2HudWidgets()
    if not valid(state.p2) then return {} end
    local hud = subObj(state.p2, "MyHUD")
    if not hud then return {} end
    local ok, arr = pcall(function() return hud.m_apHUDInstances end)
    return ok and arrayToList(arr) or {}
end

-- Called when Player 2 is removed: pull their HUD widgets off the screen so repeated
-- spawn/remove cycles don't leave stacked leftover HUDs behind.
state.hudCleanup = function()
    local n = 0
    for _, w in ipairs(p2HudWidgets()) do
        if valid(w) and pcall(function() w:RemoveFromParent() end) then n = n + 1 end
    end
    log("Removed %d HUD widget(s) belonging to Player 2.", n)
end

local function describe(x)
    if x == nil then return "nil" end
    if type(x) ~= "userdata" then return tostring(x) end
    local ok, s = pcall(function() return x:GetFullName() end)
    if ok and s then return tostring(s) end
    ok, s = pcall(function() return x:ToString() end)
    if ok and s then return tostring(s) end
    return tostring(x)
end

-- Part of Ctrl+H: which objects feed data (health, ammo, radar...) into the HUD.
local function dumpDataHub()
    log("=== HUD DATA HUB (who provides HUD data) ===")
    local gs = FindFirstOf("GameStateBase")
    if not valid(gs) then log("No GameState."); return end
    local okH, hub = pcall(function() return gs:GetHUDDataHub() end)
    if not (okH and valid(hub)) then log("No HUD data hub."); return end
    for _, field in ipairs({ "m_aDataProviders", "m_aDataSubscribers" }) do
        local okM, map = pcall(function() return hub[field] end)
        local n = 0
        if okM and map ~= nil then
            local okE, errE = pcall(function()
                map:ForEach(function(k, v)
                    n = n + 1
                    if n <= 40 then
                        local okk, kk = pcall(function() return k:get() end)
                        local okv, vv = pcall(function() return v:get() end)
                        log("  %s[%d]: key=%s value=%s", field, n,
                            describe(okk and kk or k), describe(okv and vv or v))
                    end
                end)
            end)
            if not okE then log("  %s: could not iterate (%s)", field, tostring(errE)) end
        end
        log("  %s: %d entr%s", field, n, n == 1 and "y" or "ies")
    end
end

local function hudWidgetsOf(pc)
    if not valid(pc) then return {} end
    local hud = subObj(pc, "MyHUD")
    if not hud then return {} end
    local ok, arr = pcall(function() return hud.m_apHUDInstances end)
    return ok and arrayToList(arr) or {}
end

-- Ctrl+U (experimental): the game's HUD is laid out for the whole window, so both players'
-- HUDs stack on top of each other. Re-add each player's HUD widgets to that player's own
-- half of the screen, owned by that player's controller.
local function placeHudPerPlayer(p1Only)
    log(p1Only and "=== PLAYER 1'S HUD BACK ON THE FULL SCREEN ===" or "=== PUT EACH PLAYER'S HUD ON THEIR OWN SCREEN HALF (experimental) ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    if not p1Only and not valid(state.p2) then log("Spawn Player 2 first (Ctrl+Y)."); return end
    local p1 = getP1(world, statics)
    local entries = p1Only and { { "P1", p1 } } or { { "P1", p1 }, { "P2", state.p2 } }
    for _, entry in ipairs(entries) do
        local label, pc = entry[1], entry[2]
        local list = hudWidgetsOf(pc)
        state.hudPlacedAt = os.clock()
        if state.resetRadarState then state.resetRadarState() end
        if #list == 0 then log("  %s: no HUD widget instances found.", label) end
        for i, w in ipairs(list) do
            if valid(w) then
                local ok1 = pcall(function() w:RemoveFromParent() end)
                local ok2 = pcall(function() w:SetOwningPlayer(pc) end)
                -- The HUD's pieces connect to the game when their game-state pointer is empty.
                -- Empty them now so they connect again when the HUD goes back on screen.
                local inner = {}
                local function fullPath(o)
                    local okF, full = pcall(function() return o:GetFullName() end)
                    return okF and full and tostring(full):match("^%S+%s+(.+)$") or nil
                end
                local base = fullPath(w)
                if CFG.HUD_RECONNECT and base then
                    for _, c in ipairs(FindAllOf("UserWidget") or {}) do
                        local cp = valid(c) and fullPath(c)
                        if cp and cp:sub(1, #base + 1) == base .. "." then
                            inner[#inner + 1] = c
                            pcall(function() c.m_pGameState = nil end)
                            pcall(function() c.m_pRadarManager = nil end)
                        end
                    end
                end
                -- what area the HUD says it has (to find what squeezes it into part of the screen)
                pcall(function()
                    local an = w:GetAnchorsInViewport()
                    log("    %s area before: anchors %.2f,%.2f - %.2f,%.2f", label, an.Minimum.X, an.Minimum.Y, an.Maximum.X, an.Maximum.Y)
                end)
                -- one player: straight on the whole screen, the way the game put it there at first;
                -- two players: on that player's half
                local ok3, added
                if p1Only then
                    ok3, added = pcall(function() w:AddToViewport(i - 1); return true end)
                else
                    ok3, added = pcall(function() return w:AddToPlayerScreen(i - 1) end)
                end

                local again = 0
                for _, c in ipairs(inner) do
                    if pcall(function() c:ValidateData() end) then again = again + 1 end
                end
                if #inner > 0 then log("    reconnected %d of %d HUD pieces", again, #inner) end
                log("  %s %s: removed=%s owner=%s %s=%s", label, shortName(w), tostring(ok1), tostring(ok2),
                    p1Only and "addToViewport" or "addToPlayerScreen", ok3 and tostring(added) or "failed")
                -- Taking the HUD off the screen makes it drop its event hookups (the radar stops
                -- following the player). Let it hook up again.
                if CFG.HUD_REBIND_AFTER_MOVE then
                    local hadFlag = pcall(function() return w.bEventBinded end)
                    if hadFlag then
                        pcall(function() w.bEventBinded = false end)
                        local okS = pcall(function() w:SetupBindings() end)
                        local okR = pcall(function() w:OnRespawn() end)
                        log("    re-hooked HUD events: SetupBindings %s, OnRespawn %s", tostring(okS), tostring(okR))
                    end
                end
            end
        end
    end
end

-- Ctrl+E (experimental): P2's PlayerState starts empty (no upgrades/unlocks, so no jetpack).
-- Point it at P1's upgrade/unlock objects, then give P2 a fresh pawn so its components
-- initialise with them.
local function shareProgressAndRespawnP2()
    log("=== SHARE P1 UPGRADES/UNLOCKS WITH P2, THEN RESPAWN P2'S PAWN (experimental) ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    if not valid(state.p2) then log("Spawn Player 2 first (Ctrl+Y)."); return end
    local p1 = getP1(world, statics)
    local p1ps, p2ps = subObj(p1, "PlayerState"), subObj(state.p2, "PlayerState")
    if not (p1ps and p2ps) then log("A PlayerState is missing."); return end

    for _, f in ipairs({ "m_pUpgradesTable", "m_pUpgrades", "m_pUnlocks" }) do
        local ok, v = pcall(function() return p1ps[f] end)
        if ok and valid(v) then
            local ok2, err = pcall(function() p2ps[f] = v end)
            log("  PlayerState.%s <- P1's object: %s", f, ok2 and "ok" or ("failed: " .. tostring(err)))
        else
            log("  PlayerState.%s: P1 value not readable/nil", f)
        end
    end
    pcall(function() p2ps.m_iDNA = p1ps.m_iDNA end)

    local p1Pawn, oldPawn = getPawn(p1), getPawn(state.p2)
    if not valid(p1Pawn) then log("Player 1 has no pawn."); return end
    local newPawn = spawnClonePawn(world, p1Pawn, state.p2)
    if not valid(newPawn) then
        log("Could not spawn a replacement pawn - keeping P2's existing pawn.")
        return
    end
    if valid(oldPawn) then
        pcall(function() state.p2:UnPossess() end)
        pcall(function() oldPawn:K2_DestroyActor() end)
    end
    local okP, errP = pcall(function() state.p2:Possess(newPawn) end)
    log("  Possess new pawn: %s", okP and "ok" or ("failed: " .. tostring(errP)))
    log("  P2 pawn is now: %s", nameOf(getPawn(state.p2)))
end

-- (old, no longer bound) make Player 2's HUD widgets belong to Player 2's controller.
-- Watch whether the health bar / reticle changes.
local function reownP2Hud()
    log("=== RE-OWN PLAYER 2 HUD WIDGETS (experimental) ===")
    if not valid(state.p2) then log("No Player 2."); return end
    local list = p2HudWidgets()
    if #list == 0 then log("Player 2's HUD actor has no widget instances."); return end
    for _, w in ipairs(list) do
        if valid(w) then
            local ok, err = pcall(function() w:SetOwningPlayer(state.p2) end)
            local okO, owner = pcall(function() return w:GetOwningPlayer() end)
            log("  %s: SetOwningPlayer %s -> owner now %s", shortName(w),
                ok and "ok" or ("failed: " .. tostring(err)), okO and shortName(owner) or "<n/a>")
        end
    end
end

------------------------------------------------------------------------------------------
-- Keyboard fallback: drive Player 2's pawn from keyboard keys (movement only).
-- Keys are polled on Player 1's controller (which receives the keyboard).
------------------------------------------------------------------------------------------
state.kbOn = false
local kbGen = 0
local kbJumpHeld = false
local kbErrLogged = false

local kbLastSpeedLog = 0

local MOVE_FIELDS = { "MaxWalkSpeed", "MaxAcceleration", "BrakingDecelerationWalking", "GroundFriction",
                      "JumpZVelocity", "AirControl", "GravityScale", "BrakingDecelerationFalling" }

local function moveComp(pawn)
    return subObj(pawn, "CharacterMovement")
end

-- Copy P1's movement tuning (walk speed, acceleration, jump, ...) onto P2's movement component.
local function syncMovementFromP1()
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then return end
    local p1Pawn, p2Pawn = getPawn(getP1(world, statics)), getPawn(state.p2)
    local m1, m2 = moveComp(p1Pawn), moveComp(p2Pawn)
    if not (m1 and m2) then
        log("Movement sync: CharacterMovement not found on one of the pawns.")
        return
    end
    log("=== MOVEMENT SYNC (P1 -> P2) ===")
    for _, f in ipairs(MOVE_FIELDS) do
        local ok1, a = pcall(function() return m1[f] end)
        local ok2, b = pcall(function() return m2[f] end)
        if ok1 and ok2 and type(a) == "number" and type(b) == "number" then
            if a ~= b then
                local okS = pcall(function() m2[f] = a end)
                log("  %-28s P1=%s P2=%s -> %s", f, tostring(a), tostring(b), okS and "copied" or "FAILED")
            else
                log("  %-28s same (%s)", f, tostring(a))
            end
        else
            log("  %-28s <not readable>", f)
        end
    end
end

local function kbDown(controller, keyName)
    local ok, v = pcall(function() return controller:IsInputKeyDown({ KeyName = FName(keyName) }) end)
    return ok and v == true
end

local function kbTickLegacy(gen) -- old 30 Hz timer version, no longer used
    if not state.kbOn or gen ~= kbGen then return end
    if not valid(state.p2) then
        state.kbOn = false
        log("Keyboard control stopped: Player 2 no longer exists.")
        return
    end

    local world, statics = getWorld(), getStatics()
    local p1 = (world and statics) and getP1(world, statics) or nil
    local pawn = getPawn(state.p2)
    if valid(p1) and valid(pawn) then
        local K = CFG.KB
        local f = (kbDown(p1, K.forward) and 1 or 0) - (kbDown(p1, K.back) and 1 or 0)
        local r = (kbDown(p1, K.right) and 1 or 0) - (kbDown(p1, K.left) and 1 or 0)
        local t = (kbDown(p1, K.turnRight) and 1 or 0) - (kbDown(p1, K.turnLeft) and 1 or 0)
        local jump = kbDown(p1, K.jump)

        local ok, err = pcall(function()
            if t ~= 0 then state.p2:AddYawInput(t * CFG.KB_TURN_RATE) end
            if f ~= 0 or r ~= 0 then
                local rot = state.p2:GetControlRotation()
                local yaw = math.rad(rot.Yaw)
                local c, s = math.cos(yaw), math.sin(yaw)
                local dx = c * f - s * r
                local dy = s * f + c * r
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    if CFG.KB_WALK_SPEED_OVERRIDE then
                        local mc = moveComp(pawn)
                        if mc then mc.MaxWalkSpeed = CFG.KB_WALK_SPEED_OVERRIDE end
                    end
                    pawn:AddMovementInput({ X = dx / len, Y = dy / len, Z = 0.0 }, 1.0, false)
                end
            end
            if jump and not kbJumpHeld then
                pawn:Jump()
            elseif (not jump) and kbJumpHeld then
                pawn:StopJumping()
            end
        end)
        kbJumpHeld = jump
        if CFG.KB_LOG_SPEED and (f ~= 0 or r ~= 0) and (os.clock() - kbLastSpeedLog) > 1.0 then
            kbLastSpeedLog = os.clock()
            pcall(function()
                local v = pawn:GetVelocity()
                local m2 = moveComp(pawn)
                local m1 = moveComp(getPawn(p1))
                log("P2 real speed %.0f | P2 MaxWalkSpeed %s | P1 MaxWalkSpeed %s",
                    math.sqrt(v.X * v.X + v.Y * v.Y),
                    m2 and tostring(m2.MaxWalkSpeed) or "?", m1 and tostring(m1.MaxWalkSpeed) or "?")
            end)
        end
        if not ok and not kbErrLogged then
            kbErrLogged = true
            log("Keyboard control error (logged once): %s", tostring(err))
        end
    end

    ExecuteWithDelay(CFG.KB_TICK_MS, function()
        runGame("kbTick", function() kbTick(gen) end)
    end)
end

------------------------------------------------------------------------------------------
-- Per-frame keyboard driver. Movement input has to be applied EVERY game frame, because the
-- character movement component consumes it each frame. A slower timer made Player 2 crawl.
------------------------------------------------------------------------------------------
local KB_TICK_FN = "/Game/Blueprints/Character/Player/BP_CharacterPlayer.BP_CharacterPlayer_C:ReceiveTick"

local function refreshKbRefs()
    local world, statics = getWorld(), getStatics()
    if world and statics then state.p1ctrl = getP1(world, statics) end
end

local function samePawn(a, b)
    if not (valid(a) and valid(b)) then return false end
    local ok, r = pcall(function() return a:GetAddress() == b:GetAddress() end)
    if ok then return r end
    return nameOf(a) == nameOf(b)
end

local actionErrLogged = {}
local function runAction(name, fn)
    local ok, err = pcall(fn)
    if not ok and not actionErrLogged[name] then
        actionErrLogged[name] = true
        log("Action '%s' failed (logged once): %s", name, tostring(err))
    end
end

-- Run onPress when a key goes down and onRelease when it comes back up.
local function edge(name, down, onPress, onRelease)
    state.kbHeld = state.kbHeld or {}
    local was = state.kbHeld[name] or false
    if down and not was then
        runAction(name, onPress)
    elseif (not down) and was and onRelease then
        runAction(name .. "(release)", onRelease)
    end
    state.kbHeld[name] = down
end

local function crosshairFix()
    if not (CFG.AIM_CENTER_FIX and state.splitVertical and valid(state.p2) and valid(state.p1ctrl)) then return end
    for _, e in ipairs({ { "P1", state.p1ctrl, 0.25 }, { "P2", state.p2, 0.75 } }) do
        local g = subObj(e[2], "m_pGameplayToHud")
        if g then
            local okV, v = pcall(function() return g.m_vCrosshairScreenLocation end)
            local x, y = nil, nil
            if okV and v then
                local okX, xx, yy = pcall(function() return v.X, v.Y end)
                if okX then x, y = xx, yy end
            end
            if type(x) == "number" then
                -- remember the game's own full-screen centre the first time we see it
                state.fullCx = state.fullCx or x
                state.fullCy = state.fullCy or y
                local ov = (e[1] == "P2") and state.p2AimOverride or nil
                if ov and os.clock() < ov.untilT then
                    -- Player 2's PK is reaching for the yellow target: aim at it (camera stays put)
                    pcall(function() g.m_vCrosshairScreenLocation = { X = ov.x, Y = ov.y } end)
                elseif math.abs(x - state.fullCx * 2 * e[3]) > 1 or math.abs(y - state.fullCy) > 1 then
                    pcall(function() g.m_vCrosshairScreenLocation = { X = state.fullCx * 2 * e[3], Y = state.fullCy } end)
                end
            end
        end
    end
end

local function kbStep(pawn, dt)
    local p1 = state.p1ctrl
    if not valid(p1) then return end
    local K = CFG.KB
    local f = (kbDown(p1, K.forward) and 1 or 0) - (kbDown(p1, K.back) and 1 or 0)
    local r = (kbDown(p1, K.right) and 1 or 0) - (kbDown(p1, K.left) and 1 or 0)
    local t = (kbDown(p1, K.turnRight) and 1 or 0) - (kbDown(p1, K.turnLeft) and 1 or 0)
    local jump = kbDown(p1, K.jump)

    local scale = math.min(dt, 0.1) / 0.0333
    local yawIn = t + ((kbDown(p1, K.lookRight) and 1 or 0) - (kbDown(p1, K.lookLeft) and 1 or 0))
    if yawIn ~= 0 then
        state.p2:AddYawInput(yawIn * CFG.KB_TURN_RATE * scale)
    end
    -- Pitch: "look up" sends a negative value (the controller's pitch scale is negative).
    local pitchIn = (kbDown(p1, K.lookDown) and 1 or 0) - (kbDown(p1, K.lookUp) and 1 or 0)
    if pitchIn ~= 0 then
        local sign = CFG.KB_INVERT_PITCH and -1 or 1
        state.p2:AddPitchInput(pitchIn * sign * CFG.KB_TURN_RATE * scale)
    end

    if f ~= 0 or r ~= 0 then
        local rot = state.p2:GetControlRotation()
        local yaw = math.rad(rot.Yaw)
        local c, s = math.cos(yaw), math.sin(yaw)
        local dx = c * f - s * r
        local dy = s * f + c * r
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            if CFG.KB_WALK_SPEED_OVERRIDE then
                local mc = moveComp(pawn)
                if mc then mc.MaxWalkSpeed = CFG.KB_WALK_SPEED_OVERRIDE end
            end
            pawn:AddMovementInput({ X = dx / len, Y = dy / len, Z = 0.0 }, 1.0, false)
        end
    end

    -- Jump key: jump on press; also press/release the jetpack throttle (hold to boost).
    if jump and not kbJumpHeld then
        pawn:Jump()
        local jp = subObj(pawn, "m_pJetpackPilotComponent")
        if jp then pcall(function() jp:PressThrottle() end) end
    elseif (not jump) and kbJumpHeld then
        pawn:StopJumping()
        local jp = subObj(pawn, "m_pJetpackPilotComponent")
        if jp then pcall(function() jp:ReleaseThrottle() end) end
    end
    kbJumpHeld = jump

    -- Weapon / ability / dash actions (numpad). Each logs once if its function call fails.
    local wpn = subObj(pawn, "m_pWeaponComponent")
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    local dashC = subObj(pawn, "m_pDashComponent")
    local function fixWeaponOwners()
        local eq = subObj(pawn, "m_pEquipmentManagerComponent")
        local tc = subObj(pawn, "m_pTargetComponent")
        if not eq then return end
        local okW, ws = pcall(function() return eq:GetCurrentWeapons() end)
        if not (okW and ws) then return end
        for _, w in ipairs(arrayToList(ws)) do
            if valid(w) then
                local function same(prop, want)
                    local ok, v = pcall(function() return w[prop] end)
                    return ok and valid(v) and valid(want) and v:GetFullName() == want:GetFullName()
                end
                if not state.weaponChecked then
                    log("P2 weapon %s: holder=%s targetComp=%s equipMgr=%s", nameOf(w),
                        tostring(same("m_pHolder", pawn)), tostring(same("m_pOwnerTargetComponent", tc)),
                        tostring(same("m_pEquipmentManager", eq)))
                end
                if not same("m_pHolder", pawn) then pcall(function() w.m_pHolder = pawn end) end
                if tc and not same("m_pOwnerTargetComponent", tc) then pcall(function() w.m_pOwnerTargetComponent = tc end) end
                if not same("m_pEquipmentManager", eq) then pcall(function() w.m_pEquipmentManager = eq end) end
            end
        end
        state.weaponChecked = true
    end
    edge("fire", kbDown(p1, K.fire),
        function() pcall(fixWeaponOwners); wpn:StartShooting() end,
        function() wpn:StopShooting() end)
    edge("nextWeapon", kbDown(p1, K.nextWeapon), function() wpn:RequestNextWeaponEquip() end)
    edge("prevWeapon", kbDown(p1, K.prevWeapon), function() wpn:RequestPreviousWeaponEquip() end)
    local function mentalList()
        local okA, arr = pcall(function() return mental.m_aPlayerMentalAbilities end)
        return okA and arrayToList(arr) or {}
    end
    local function findAbility(pat)
        for _, a in ipairs(mentalList()) do
            if nameOf(a):find(pat, 1, true) then return a end
        end
        return nil
    end
    -- P2 has no yellow lock-on of its own, so pick the target nearest P2's aim line and hand it
    -- to the mental ability system.
    local function updateMentalTarget(range)
        local okR, rot = pcall(function() return state.p2:GetControlRotation() end)
        if not okR or not rot then return end
        local okL, ploc = pcall(function() return pawn:K2_GetActorLocation() end)
        if not okL then return end
        local cam = ploc
        pcall(function()
            local c = state.p2.PlayerCameraManager:GetCameraLocation()
            if c then cam = c end
        end)
        local yaw, pitch = math.rad(rot.Yaw), math.rad(rot.Pitch)
        local fx, fy, fz = math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)
        local best, bestScore = nil, nil
        local chars = FindAllOf("Character")
        if not chars then return end
        local p1pawn = nil
        local w_, st_ = getWorld(), getStatics()
        if w_ and st_ then p1pawn = getPawn(getP1(w_, st_)) end
        for _, c in ipairs(chars) do
            if valid(c) and c:GetFullName() ~= pawn:GetFullName()
               and not (valid(p1pawn) and c:GetFullName() == p1pawn:GetFullName()) then
                local okC, l = pcall(function() return c:K2_GetActorLocation() end)
                if okC and l then
                    local dx, dy, dz = l.X - cam.X, l.Y - cam.Y, l.Z - cam.Z
                    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if d > 50 and d < (range or 3000) then
                        local cosA = (dx * fx + dy * fy + dz * fz) / d
                        if cosA > 0.93 then -- within roughly 20 degrees of the aim line
                            local score = (1 - cosA) * 4 + d / 6000
                            if not bestScore or score < bestScore then best, bestScore = c, score end
                        end
                    end
                end
            end
        end
        if best then
            pcall(function() mental.m_pCurrentAimTarget = best end)
            for _, a in ipairs(mentalList()) do
                pcall(function() a.m_pCurrentAimTarget = best end)
            end
            if state.lastMentalTarget ~= best:GetFullName() then
                state.lastMentalTarget = best:GetFullName()
                log("P2 mental aim target: %s", nameOf(best))
            end
        end
    end
    local function pressAbility(pat, down)
        local a = findAbility(pat)
        if not a then
            if down then log("P2 mental: no ability matching '%s'", pat) end
            return
        end
        local okC, cls = pcall(function() return a:GetClass() end)
        cls = okC and cls or nil
        if down then
            pcall(updateMentalTarget, 6000)
            pcall(function() a.m_pUser = pawn end)
            pcall(function() a.m_pUserComponent = mental end)
        end
        local ok, r = pcall(function() return mental:Input_InteractState(down, cls, down) end)
        if down then log("P2 mental %s: ok=%s result=%s", pat, tostring(ok), tostring(r)) end
    end
    edge("mental", kbDown(p1, K.mental),
        function() pressAbility("Psycokinesis", true) end,
        function() pressAbility("Psycokinesis", false) end)
    local anyHeld = kbDown(p1, K.mental)
    for _, ab in ipairs(CFG.MENTAL_KEYS) do
        if kbDown(p1, ab[1]) then anyHeld = true end
    end
    if anyHeld then pcall(updateMentalTarget, 6000) end
    for i, ab in ipairs(CFG.MENTAL_KEYS) do
        edge("mental_" .. ab[1], kbDown(p1, ab[1]),
            function() pressAbility(ab[2], true) end,
            function() pressAbility(ab[2], false) end)
    end
    edge("ads", kbDown(p1, K.ads),
        function() pawn.m_bPlayerIsADS = true end,
        function() pawn.m_bPlayerIsADS = false end)
    edge("dash", kbDown(p1, K.dash), function()
        local rot = state.p2:GetControlRotation()
        local yaw = math.rad(rot.Yaw)
        local c, s = math.cos(yaw), math.sin(yaw)
        local dx, dy = c, s -- default: the way the camera faces
        if f ~= 0 or r ~= 0 then
            dx = c * f - s * r
            dy = s * f + c * r
        end
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then dx, dy = dx / len, dy / len end
        local okD = pcall(function() dashC:TriggerDash({ X = dx, Y = dy, Z = 0.0 }) end)
        if not okD then dashC:TriggerDash() end
        -- Holding the dash key also holds the skate (the upgraded, sustained dash) if unlocked.
        local jpS = subObj(pawn, "m_pJetpackPilotComponent")
        if jpS then pcall(function() jpS:PressSkate() end) end
    end, function()
        local jpS = subObj(pawn, "m_pJetpackPilotComponent")
        if jpS then pcall(function() jpS:ReleaseSkate() end) end
    end)

    if CFG.KB_LOG_SPEED and (f ~= 0 or r ~= 0) and (os.clock() - kbLastSpeedLog) > 1.0 then
        kbLastSpeedLog = os.clock()
        pcall(function()
            local v = pawn:GetVelocity()
            local m2 = moveComp(pawn)
            log("P2 real speed %.0f | P2 MaxWalkSpeed %s", math.sqrt(v.X * v.X + v.Y * v.Y),
                m2 and tostring(m2.MaxWalkSpeed) or "?")
        end)
    end
end

-- Runs every frame for every BP_CharacterPlayer; only acts on Player 2's pawn.
local function onPawnTick(context, deltaParam)
    if not state.kbOn then return end
    if not valid(state.p2) then
        state.kbOn = false
        log("Keyboard control stopped: Player 2 no longer exists.")
        return
    end
    local okP, pawn = pcall(function() return context:get() end)
    if not (okP and valid(pawn)) then return end
    if not samePawn(pawn, getPawn(state.p2)) then return end
    if not valid(state.p1ctrl) then refreshKbRefs() end
    local dt = 0.016
    local okD, d = pcall(function() return deltaParam:get() end)
    if okD and type(d) == "number" then dt = d end
    kbStep(pawn, dt)
end

local function kbFallbackLoop(gen)
    if not state.kbOn or gen ~= kbGen then return end
    local pawn = getPawn(state.p2)
    if valid(pawn) then
        if not valid(state.p1ctrl) then refreshKbRefs() end
        local ok, err = pcall(kbStep, pawn, CFG.KB_FALLBACK_MS / 1000.0)
        if not ok and not kbErrLogged then
            kbErrLogged = true
            log("Keyboard control error (logged once): %s", tostring(err))
        end
    end
    ExecuteWithDelay(CFG.KB_FALLBACK_MS, function()
        runGame("kbFallback", function() kbFallbackLoop(gen) end)
    end)
end

local function startKeyboardDriver()
    refreshKbRefs()

    -- Enable Player 2's dash component.
    local dashEnable = subObj(getPawn(state.p2), "m_pDashComponent")
    if dashEnable then
        local okD = pcall(function() dashEnable:EnableDash() end)
        local okQ, en = pcall(function() return dashEnable:IsDashEnabled() end)
        log("  Dash: EnableDash %s, IsDashEnabled=%s", okD and "ok" or "failed", okQ and tostring(en) or "?")
    end

    -- Try to enable Player 2's jetpack component.
    local jp = subObj(getPawn(state.p2), "m_pJetpackPilotComponent")
    if jp then
        local okE, errE = pcall(function() jp:EnableJetpack() end)
        local okI, en = pcall(function() return jp:IsJetpackEnabled() end)
        log("  Jetpack: EnableJetpack %s, IsJetpackEnabled=%s",
            okE and "ok" or ("failed: " .. tostring(errE)), okI and tostring(en) or "?")
        local okSk = pcall(function() jp:EnableSkate() end)
        local okG, sk = pcall(function() return jp:GetSkateActive() end)
        log("  Skate: EnableSkate %s, GetSkateActive=%s", okSk and "ok" or "failed", okG and tostring(sk) or "?")
    end

    if not state.kbHooked then
        local okH, errH = pcall(function()
            RegisterHook(KB_TICK_FN, function(Context, DeltaSeconds)
                local ok, err = pcall(onPawnTick, Context, DeltaSeconds)
                if not ok and not kbErrLogged then
                    kbErrLogged = true
                    log("Per-frame driver error (logged once): %s", tostring(err))
                end
            end)
        end)
        state.kbHooked = okH
        log("  Per-frame hook: %s", okH and "registered (input applied every frame)"
            or ("FAILED: " .. tostring(errH) .. " - using timer fallback"))
    end
    if not state.kbHooked then kbFallbackLoop(kbGen) end
end

local function toggleKeyboardP2()
    if state.kbOn then
        state.kbOn = false
        pcall(function()
            local w = subObj(getPawn(state.p2), "m_pWeaponComponent")
            if w then w:StopShooting() end
        end)
        log("Keyboard control of Player 2: OFF")
        return
    end
    if not valid(state.p2) then
        log("Keyboard control: spawn Player 2 first (Ctrl+Y).")
        return
    end
    state.kbOn = true
    kbGen = kbGen + 1
    kbErrLogged = false
    kbJumpHeld = false
    local K = CFG.KB
    log("Keyboard control of Player 2: ON  (move %s/%s/%s/%s, turn %s/%s, jump %s)",
        K.forward, K.left, K.back, K.right, K.turnLeft, K.turnRight, K.jump)
    if CFG.KB_SYNC_MOVEMENT_FROM_P1 then
        local okS, errS = pcall(syncMovementFromP1)
        if not okS then log("Movement sync error: %s", tostring(errS)) end
    end
    startKeyboardDriver()
end

------------------------------------------------------------------------------------------
-- Swap which pawn the physical gamepad + keyboard drive. All physical input reaches Player 1's
-- controller, so exchanging the pawns the two controllers possess changes who you control
-- (with the game's own animations, jetpack and weapons). The other pawn stays on the keyboard
-- driver (Ctrl+B).
------------------------------------------------------------------------------------------
state.swapped = false
local lastSwap = 0

-- The HUD reads its data from "providers" registered by one pawn. Try to point them at the
-- pawn you now drive, then print who the providers are so the log shows whether it took.
local function reregisterHudProviders(mainPawn)
    local gs = FindFirstOf("GameStateBase")
    if not valid(gs) then return end
    local okH, hub = pcall(function() return gs:GetHUDDataHub() end)
    if not (okH and valid(hub)) then log("  HUD providers: no data hub."); return end
    local fields = { PlayerStats = "m_pStatsComponent", PlayerWeapon = "m_pWeaponComponent",
                     InputScheme = "m_pInputActionsComponent" }
    for key, field in pairs(fields) do
        local comp = subObj(mainPawn, field)
        if comp then
            local ok, err = pcall(function() hub:RegisterDataProvider(FName(key), comp) end)
            log("  RegisterDataProvider(%s, %s): %s", key, shortName(comp),
                ok and "called" or ("failed: " .. tostring(err)))
        end
    end
    dumpDataHub()
end

local function swapControlledPawns()
    if os.clock() - lastSwap < 1.0 then return end
    lastSwap = os.clock()
    log("=== SWAP CONTROLLED PAWNS ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    if not valid(state.p2) then log("Spawn Player 2 first (Ctrl+Y)."); return end
    local c1, c2 = getP1(world, statics), state.p2
    local a, b = getPawn(c1), getPawn(c2)
    if not (valid(c1) and valid(a) and valid(b)) then log("Both players need a pawn."); return end
    log("  before: controller1 -> %s | controller2 -> %s", shortName(a), shortName(b))

    pcall(function() c1:UnPossess() end)
    pcall(function() c2:UnPossess() end)
    local ok1, e1 = pcall(function() c1:Possess(b) end)
    local ok2, e2 = pcall(function() c2:Possess(a) end)
    local na, nb = getPawn(c1), getPawn(c2)
    log("  after:  controller1 -> %s | controller2 -> %s  (possess calls: %s / %s)",
        shortName(na), shortName(nb), ok1 and "ok" or tostring(e1), ok2 and "ok" or tostring(e2))

    if not (samePawn(na, b) and samePawn(nb, a)) then
        log("  Swap did not take effect cleanly - restoring the original assignment.")
        pcall(function() c1:UnPossess() end)
        pcall(function() c2:UnPossess() end)
        pcall(function() c1:Possess(a) end)
        pcall(function() c2:Possess(b) end)
        log("  restored: controller1 -> %s | controller2 -> %s",
            shortName(getPawn(c1)), shortName(getPawn(c2)))
        return
    end

    state.swapped = not state.swapped
    local gs = FindFirstOf("GameStateBase")
    if valid(gs) then
        local okP = pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = na end)
        log("  GameState primary player pawn -> %s: %s", shortName(na), okP and "ok" or "failed")
    end
    if CFG.SWAP_REREGISTER_HUD_PROVIDERS then
        local okR, errR = pcall(reregisterHudProviders, na)
        if not okR then log("  HUD provider step error: %s", tostring(errR)) end
    end
    log("  You now drive %s with the gamepad/keyboard. Ctrl+B drives the other one.", shortName(na))
end

-- Undo a swap before Player 2 is removed, so the original pawn is the one that stays.
state.swapBack = function()
    if state.swapped then
        lastSwap = 0
        swapControlledPawns()
    end
end

-- Watch for the gamepad combo (hold all listed keys for SWAP_HOLD_SECONDS).
local comboGen = 0
local comboHeldSince = nil
local comboLatched = false

local function comboTick(gen)
    if gen ~= comboGen then return end
    if not valid(state.p2) then return end -- Player 2 gone: stop watching
    if not valid(state.p1ctrl) then refreshKbRefs() end
    local p1 = state.p1ctrl
    if valid(p1) then
        local all = true
        for _, k in ipairs(CFG.SWAP_PAD_COMBO) do
            if not kbDown(p1, k) then all = false; break end
        end
        if all then
            comboHeldSince = comboHeldSince or os.clock()
            if not comboLatched and (os.clock() - comboHeldSince) >= CFG.SWAP_HOLD_SECONDS then
                comboLatched = true
                swapControlledPawns()
            end
        else
            comboHeldSince = nil
            comboLatched = false
        end
    end
    later(0.04, "comboTick", function() comboTick(gen) end)
end

local function startComboWatcher()
    comboGen = comboGen + 1
    comboHeldSince, comboLatched = nil, false
    local gen = comboGen
    runGame("comboTick", function() comboTick(gen) end)
end

RegisterKeyBind(Key.X, { ModifierKey.CONTROL }, function()
    runGame("swapControlledPawns", swapControlledPawns)
end)

RegisterKeyBind(Key.B, { ModifierKey.CONTROL }, function()
    runGame("toggleKeyboardP2", toggleKeyboardP2)
end)

-- HUD mode "P1 only": Player 1's HUD on their own half, Player 2's HUD widgets removed.
-- (The game's HUD data hub has only Player 1's pawn registered as data provider, so any HUD
-- shows Player 1's health/ammo/weapon. A HUD for Player 2 would just show wrong numbers.)
local function hudP1Only()
    log("=== HUD: Player 1's HUD only, Player 2's HUD hidden ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local p1 = getP1(world, statics)
    for i, w in ipairs(hudWidgetsOf(p1)) do
        if valid(w) then
            pcall(function() w:RemoveFromParent() end)
            pcall(function() w:SetOwningPlayer(p1) end)
            local ok, added = pcall(function() return w:AddToPlayerScreen(i - 1) end)
            log("  P1 %s: addToPlayerScreen=%s", shortName(w), ok and tostring(added) or "failed")
        end
    end
    if valid(state.p2) then
        for _, w in ipairs(hudWidgetsOf(state.p2)) do
            if valid(w) then
                pcall(function() w:RemoveFromParent() end)
                log("  P2 %s: hidden", shortName(w))
            end
        end
    end
end

state.hudMode = 0
------------------------------------------------------------------------------------------
-- Keep the world populated around Player 2 too, and make Player 2 immune to the anal probe.
------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- Crosshair / aim bridge probe (Ctrl+F2 logs it, Ctrl+F1 recentres each player's crosshair).
------------------------------------------------------------------------------------------
local function readXY(v)
    if v == nil then return nil, nil end
    for _, names in ipairs({ { "X", "Y" }, { "x", "y" } }) do
        local ok, x, y = pcall(function() return v[names[1]], v[names[2]] end)
        if ok and type(x) == "number" then return x, y end
    end
    local ok, x, y = pcall(function() return v:GetPropertyValue("X"), v:GetPropertyValue("Y") end)
    if ok and type(x) == "number" then return x, y end
    return nil, nil
end

local function aimProbe(apply)
    log("=== CROSSHAIR / AIM PROBE%s ===", apply and " (recentring)" or "")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local p1 = getP1(world, statics)
    for _, e in ipairs({ { "P1", p1 }, { "P2", state.p2 } }) do
        local label, pc = e[1], e[2]
        if valid(pc) then
            local g = subObj(pc, "m_pGameplayToHud")
            local gx, gy
            if g then
                local okV, v = pcall(function() return g.m_vCrosshairScreenLocation end)
                gx, gy = readXY(okV and v or nil)
            end
            local vx, vy
            pcall(function()
                local a, b = pc:GetViewportSize()
                if type(a) == "number" then vx, vy = a, b end
                if vx == nil then
                    local out = {}
                    local r1, r2 = pc:GetViewportSize(0, 0)
                    if type(r1) == "number" then vx, vy = r1, r2 end
                end
            end)
            local rot = nil
            pcall(function() rot = pc:GetControlRotation() end)
            log("%s crosshair=(%s, %s) viewport=(%s, %s) controlRot=(P%s Y%s)", label,
                tostring(gx), tostring(gy), tostring(vx), tostring(vy),
                rot and tostring(rot.Pitch) or "?", rot and tostring(rot.Yaw) or "?")
            if apply and g and vx and vy then
                local cx, cy = vx * 0.5, vy * 0.5
                if state.splitVertical then cx = vx * 0.25 end
                if label == "P2" and state.splitVertical then cx = vx * 0.75 end
                local ok, err = pcall(function() g.m_vCrosshairScreenLocation = { X = cx, Y = cy } end)
                log("  set crosshair to (%s, %s): %s", tostring(cx), tostring(cy), ok and "ok" or tostring(err))
            end
        end
    end
end
state.aimProbe = aimProbe

------------------------------------------------------------------------------------------
-- Force the highest mesh detail everywhere (cars/NPCs never drop to low LOD).
------------------------------------------------------------------------------------------
local function runConsole(cmd)
    local lib = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local w = getWorld()
    if not (valid(lib) and w) then return false end
    local ok, err = pcall(function() lib:ExecuteConsoleCommand(w, cmd, nil) end)
    log("Console '%s': %s", cmd, ok and "ok" or tostring(err))
    return ok
end

local function forceHighLod()
    if state.lodForced then
        for _, c in ipairs({ "r.ForceLOD -1", "r.SkeletalMeshLODBias 0", "r.StaticMeshLODDistanceScale 1" }) do runConsole(c) end
        state.lodForced = false
        log("Forced high LOD: OFF (back to the game's normal LOD)")
    else
        for _, c in ipairs(CFG.LOD_COMMANDS) do runConsole(c) end
        state.lodForced = true
        log("Forced high LOD: ON")
    end
end
state.forceHighLod = forceHighLod

local popGen = 0
local function populationTick(gen)
    if gen ~= popGen or not valid(state.p2) then return end
    local gs = FindFirstOf("GameStateBase")
    local p2pawn = getPawn(state.p2)
    if valid(gs) and valid(p2pawn) then
        local okT, tm = pcall(function() return gs:GetTrafficCrowdManager() end)
        if okT and valid(tm) then
            if state.popProxyFor ~= p2pawn then
                local ok, err = pcall(function() tm:RegisterObstacleProxy(p2pawn, false, true) end)
                log("Population: register P2 as a player obstacle proxy: %s", ok and "ok" or tostring(err))
                state.popProxyFor = p2pawn
            end
            local w_, st_ = getWorld(), getStatics()
            local p1pawn = (w_ and st_) and getPawn(getP1(w_, st_)) or nil
            local okD, far = pcall(function()
                local a, b = p1pawn:K2_GetActorLocation(), p2pawn:K2_GetActorLocation()
                local dx, dy = a.X - b.X, a.Y - b.Y
                return (dx * dx + dy * dy) > (6000 * 6000)
            end)
            if okD and far then
                state.popTick = (state.popTick or 0) + 1
                if CFG.POP_PREPOP_EVERY > 0 and state.popTick % CFG.POP_PREPOP_EVERY == 1 then -- while apart
                    local okL, loc = pcall(function() return p2pawn:K2_GetActorLocation() end)
                    if okL then
                        local ok, err = pcall(function() tm:PrePopulateAroundPosition(loc, false, 0.05) end)
                        if state.popLogged ~= true then
                            state.popLogged = true
                            log("Population: PrePopulateAroundPosition around P2: %s", ok and "ok" or tostring(err))
                        end
                    end
                end
            end
        end
    end
    later(1.0, "popTick", function() populationTick(gen) end)
end

local function makeP2ImmuneToProbe()
    local pawn = getPawn(state.p2)
    if not valid(pawn) then return end
    local classes = {}
    local all = FindAllOf("Class")
    if all then
        for _, c in ipairs(all) do
            local n = nameOf(c)
            if n:find("Probe", 1, true) and (n:find("Damage", 1, true) or n:find("DT_", 1, true)) then
                classes[#classes + 1] = c
            end
        end
    end
    log("Probe immunity: %d probe-related damage class(es) found", #classes)
    for _, c in ipairs(classes) do log("    %s", nameOf(c)) end
    local dmg
    for _, f in ipairs({ "m_pPawnDamageComponent", "m_pDamageComponent", "m_pPawnDamage", "PawnDamageComponent" }) do
        dmg = subObj(pawn, f)
        if dmg then break end
    end
    if not dmg then log("Probe immunity: no pawn damage component found on P2."); return end
    local okA, arr = pcall(function() return dmg.m_aImmuneAgainstDamageTypes end)
    if okA and arr then
        for _, c in ipairs(classes) do
            pcall(function() arr[#arr + 1] = c end)
        end
        log("Probe immunity: added to P2's immune damage types.")
    end
end

------------------------------------------------------------------------------------------
-- Rewire Player 2: the game builds Player 2's character/weapons/abilities with some
-- references still pointing at Player 1's objects (e.g. a weapon aiming with Player 1's
-- target system). Walk everything Player 2 owns and repoint each reference to Player 1's
-- object at Player 2's matching object. Logs every change. Ctrl+R runs it again.
------------------------------------------------------------------------------------------
local function pathOf(obj)
    -- GetFullName() is "ClassName /Path/To.Object"; return the path part.
    local ok, full = pcall(function() return obj:GetFullName() end)
    if not ok or not full then return nil end
    return tostring(full):match("^%S+%s+(.+)$")
end

local function forEachObjectProperty(obj, fn)
    local okC, cls = pcall(function() return obj:GetClass() end)
    local depth = 0
    while okC and valid(cls) and depth < 16 do
        pcall(function()
            cls:ForEachProperty(function(prop)
                local okF, full = pcall(function() return prop:GetFullName() end)
                if okF and full then
                    local kind = tostring(full):match("^(%S+)")
                    if kind == "ObjectProperty" then
                        local okN, name = pcall(function() return prop:GetFName():ToString() end)
                        if okN and name then fn(tostring(name)) end
                    end
                end
            end)
        end)
        local okS, sup = pcall(function() return cls:GetSuperStruct() end)
        if not okS or not valid(sup) then break end
        cls = sup
        depth = depth + 1
    end
end

-- Fields the rewire must leave alone: Player 2 shares Player 1's upgrades and unlocks on
-- purpose (progress sync), so pointing those at Player 1's objects is not a bug.
local REWIRE_SKIP = { m_pUpgrades = true, m_pUnlocks = true }

local function rewireP2(reason, otherPc)
    local world, statics = getWorld(), getStatics()
    local p2 = otherPc or state.p2
    if not (world and statics and valid(p2)) then return end
    local p1 = getP1(world, statics)
    local p1Pawn, p2Pawn = getPawn(p1), getPawn(p2)
    if not (valid(p1) and valid(p1Pawn) and valid(p2Pawn)) then
        log("Rewire P2 (%s): need both players with characters", reason)
        return
    end

    -- Player 1 -> Player 2 path prefixes (actors, and everything inside them).
    local swaps = {}
    local function addSwap(a, b)
        local pa, pb = valid(a) and pathOf(a), valid(b) and pathOf(b)
        if pa and pb and pa ~= pb then swaps[#swaps + 1] = { pa, pb } end
    end
    addSwap(p1Pawn, p2Pawn)
    addSwap(p1, p2)
    addSwap(subObj(p1, "PlayerState"), subObj(p2, "PlayerState"))
    addSwap(subObj(p1, "MyHUD"), subObj(p2, "MyHUD"))
    addSwap(subObj(p1, "PlayerCameraManager"), subObj(p2, "PlayerCameraManager"))

    local function p2Counterpart(value)
        local path = pathOf(value)
        if not path then return nil end
        for _, sw in ipairs(swaps) do
            local from, to = sw[1], sw[2]
            if path == from then return StaticFindObject(to) end
            local rest = path:sub(#from + 1)
            if path:sub(1, #from) == from and (rest:sub(1, 1) == "." or rest:sub(1, 1) == ":") then
                return StaticFindObject(to .. rest)
            end
        end
        return nil
    end
    local function isP1Owned(obj)
        local path = pathOf(obj)
        if not path then return false end
        for _, sw in ipairs(swaps) do
            local from = sw[1]
            if path == from or path:sub(1, #from + 1) == from .. "." or path:sub(1, #from + 1) == from .. ":" then return true end
        end
        return false
    end

    -- Everything Player 2 owns.
    local targets, seen = {}, {}
    local function add(obj)
        if not valid(obj) then return end
        local path = pathOf(obj)
        if not path or seen[path] then return end
        seen[path] = true
        targets[#targets + 1] = obj
    end
    add(p2Pawn); add(p2)
    add(subObj(p2, "PlayerState")); add(subObj(p2, "MyHUD")); add(subObj(p2, "PlayerCameraManager"))
    local owners = {}
    for _, o in ipairs({ p2Pawn, p2 }) do
        local path = pathOf(o)
        if path then owners[#owners + 1] = path end
    end
    local comps = FindAllOf("ActorComponent")
    if comps then
        for _, c in ipairs(comps) do
            local path = valid(c) and pathOf(c)
            if path then
                for _, owner in ipairs(owners) do
                    if path:sub(1, #owner + 1) == owner .. "." then add(c); break end
                end
            end
        end
    end
    local eq = subObj(p2Pawn, "m_pEquipmentManagerComponent")
    if eq then
        for _, field in ipairs({ "m_aWeaponList", "m_aPrespawnedWeaponList", "m_apCurrentlyEquipWeapons" }) do
            local okA, arr = pcall(function() return eq[field] end)
            if okA then for _, w in ipairs(arrayToList(arr)) do add(w) end end
        end
        local okW, ws = pcall(function() return eq:GetCurrentWeapons() end)
        if okW then for _, w in ipairs(arrayToList(ws)) do add(w) end end
    end
    local mental = subObj(p2Pawn, "m_pMentalAbilityComponent")
    if mental then
        local okA, arr = pcall(function() return mental.m_aPlayerMentalAbilities end)
        if okA then for _, a in ipairs(arrayToList(arr)) do add(a) end end
    end
    for _, w in ipairs(hudWidgetsOf(p2)) do add(w) end  -- Player 2's HUD widgets

    local changed, shared = 0, 0
    for _, obj in ipairs(targets) do
        if isP1Owned(obj) then
            shared = shared + 1
            log("  Rewire: %s is listed for Player 2 but belongs to Player 1 (left alone)", shortName(obj))
        else
            forEachObjectProperty(obj, function(name)
                if REWIRE_SKIP[name] then return end
                local okV, value = pcall(function() return obj[name] end)
                if okV and valid(value) and isP1Owned(value) then
                    local replacement = p2Counterpart(value)
                    if valid(replacement) then
                        local okW = pcall(function() obj[name] = replacement end)
                        changed = changed + 1
                        log("  Rewire: %s.%s  %s -> %s%s", shortName(obj), name, shortName(value),
                            shortName(replacement), okW and "" or "  (WRITE FAILED)")
                    else
                        log("  Rewire: %s.%s points at Player 1's %s, but Player 2 has no matching object",
                            shortName(obj), name, shortName(value))
                    end
                end
            end)
        end
    end
    log("=== Rewire P2 (%s): scanned %d objects, fixed %d reference(s), %d shared object(s) ===",
        reason, #targets, changed, shared)
end
-- Players 3 and 4 get the same "no pointers into Player 1" pass
state.rewirePlayer = function(pc, reason) rewireP2(reason or "extra player", pc) end
state.rewireP2 = rewireP2

------------------------------------------------------------------------------------------
-- Ctrl+N: find "main player" references. Scans the game-wide objects (game state, game
-- instance, game mode, managers, HUD data hub) and every actor in the level for references
-- to Player 1's character/controller/components, and logs them. Those are the places that
-- make targeting, pickups and HUD follow Player 1 only.
------------------------------------------------------------------------------------------
local function findPrimaryPlayerRefs(includeActors)
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("Main-player scan: no world"); return end
    local p1 = getP1(world, statics)
    local p1Pawn = getPawn(p1)
    if not (valid(p1) and valid(p1Pawn)) then log("Main-player scan: Player 1 not found"); return end

    local p1Roots, playerRoots = {}, {}
    for _, o in ipairs({ p1Pawn, p1, subObj(p1, "PlayerState"), subObj(p1, "MyHUD"), subObj(p1, "PlayerCameraManager") }) do
        local path = valid(o) and pathOf(o)
        if path then p1Roots[#p1Roots + 1] = path; playerRoots[#playerRoots + 1] = path end
    end
    for _, o in ipairs({ getPawn(state.p2), state.p2 }) do
        local path = valid(o) and pathOf(o)
        if path then playerRoots[#playerRoots + 1] = path end
    end
    local function under(path, roots)
        for _, root in ipairs(roots) do
            if path == root or path:sub(1, #root + 1) == root .. "." then return true end
        end
        return false
    end

    local scanned, found, seen = 0, 0, {}
    local function scan(obj, label)
        if not valid(obj) then return end
        local path = pathOf(obj)
        if not path or seen[path] or under(path, playerRoots) then return end
        if path:find("Default__", 1, true) then return end  -- class defaults, not live objects
        seen[path] = true
        scanned = scanned + 1
        log("  scanning %s (%s)", shortName(obj), label)  -- if the game crashes, the last line names the culprit
        forEachObjectProperty(obj, function(name)
            local okV, value = pcall(function() return obj[name] end)
            if okV and valid(value) then
                local vpath = pathOf(value)
                if vpath and under(vpath, p1Roots) then
                    found = found + 1
                    log("  MAIN-PLAYER REF: %s (%s).%s -> %s", shortName(obj), label, name, shortName(value))
                end
            end
        end)
    end

    log("=== MAIN-PLAYER SCAN (%s) ===", includeActors and "game-wide objects + game actors" or "game-wide objects")
    local gs = FindFirstOf("GameStateBase")
    scan(gs, "game state")
    local okGI, gi = pcall(function() return UEHelpers.GetGameInstance() end)
    if okGI then scan(gi, "game instance") end
    scan(FindFirstOf("GameModeBase"), "game mode")
    if valid(gs) then
        for _, fn in ipairs({ "GetHUDDataHub", "GetAISystem", "GetObjectRespawnManager", "GetSpawnPoolManager" }) do
            local ok, obj = pcall(function() return gs[fn](gs) end)
            if ok then scan(obj, "GameState." .. fn) end
        end
    end
    if okGI and valid(gi) then
        for _, field in ipairs({ "m_pSignInManager", "m_pInputDeviceTracker" }) do
            scan(subObj(gi, field), "GameInstance." .. field)
        end
    end

    if includeActors then
        -- Only the game's own actor classes (BFG code and game Blueprints), not engine scenery.
        local actors = FindAllOf("Actor")
        for _, a in ipairs(actors or {}) do
            if valid(a) then
                local okC, cls = pcall(function() return a:GetClass():GetFullName() end)
                cls = okC and tostring(cls) or ""
                if cls:find("/Script/BFGCore.", 1, true) or cls:find("/Game/Blueprints/", 1, true) then
                    scan(a, "actor")
                end
            end
        end
    end
    log("=== MAIN-PLAYER SCAN done: %d objects scanned, %d reference(s) to Player 1 found ===", scanned, found)
end

------------------------------------------------------------------------------------------
-- Weapons: report (Ctrl+W) and per-player weapon reticles.
-- Each weapon makes its own reticle widget (m_CrosshairInstance) and puts it on the whole
-- screen. Move each weapon's reticle onto its holder's half of the screen.
------------------------------------------------------------------------------------------
local function weaponsOf(pawn)
    local list = {}
    local eq = subObj(pawn, "m_pEquipmentManagerComponent")
    if not eq then return list end
    local ok, ws = pcall(function() return eq:GetCurrentWeapons() end)
    if ok then for _, w in ipairs(arrayToList(ws)) do if valid(w) then list[#list + 1] = w end end end
    return list
end

local function weaponReport()
    log("=== WEAPON REPORT ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then return end
    for _, e in ipairs({ { "P1", getP1(world, statics) }, { "P2", state.p2 } }) do
        local label, pc = e[1], e[2]
        local pawn = getPawn(pc)
        if valid(pawn) then
            local eq = subObj(pawn, "m_pEquipmentManagerComponent")
            local wc = subObj(pawn, "m_pWeaponComponent")
            log("%s pawn %s | equipment manager %s | weapon component's manager %s", label, shortName(pawn),
                eq and nameOf(eq) or "nil", wc and propStr(wc, "m_pEquipmentManager") or "nil")
            for _, field in ipairs({ "m_aWeaponList", "m_aPrespawnedWeaponList", "m_apCurrentlyEquipWeapons" }) do
                local okA, arr = pcall(function() return eq[field] end)
                local items = okA and arrayToList(arr) or {}
                log("  %s: %d entr%s", field, #items, #items == 1 and "y" or "ies")
            end
            local list = weaponsOf(pawn)
            log("  current weapons: %d", #list)
            for _, w in ipairs(list) do
                local xh = subObj(w, "m_CrosshairInstance")
                local okO, owner = pcall(function() return xh and xh:GetOwningPlayer() end)
                local okV, inVp = pcall(function() return xh and xh:IsInViewport() end)
                log("    %s | holder=%s | aims with=%s | manager=%s | reticle=%s (owner %s, on screen %s)",
                    shortName(w), propStr(w, "m_pHolder"), propStr(w, "m_pOwnerTargetComponent"),
                    propStr(w, "m_pEquipmentManager"), xh and shortName(xh) or "none",
                    (okO and owner) and shortName(owner) or "?", okV and tostring(inVp) or "?")
            end
        else
            log("%s: no character", label)
        end
    end
end

RegisterKeyBind(Key.W, { ModifierKey.CONTROL }, function()
    runGame("weaponReport", weaponReport)
end)

local rehomed = {}  -- reticle widget name -> controller name it was moved to

local function rehomeReticles()
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then return end
    if not valid(state.p2) then
        -- Split screen ended: put Player 1's reticles back on the whole screen.
        if next(rehomed) then
            local p1 = getP1(world, statics)
            for _, w in ipairs(weaponsOf(getPawn(p1))) do
                local xh = subObj(w, "m_CrosshairInstance")
                if xh and rehomed[nameOf(xh)] then
                    pcall(function() xh:RemoveFromParent() end)
                    pcall(function() xh:AddToViewport(0) end)
                end
            end
            rehomed = {}
        end
        return
    end
    for _, pc in ipairs({ getP1(world, statics), state.p2 }) do
        local pawn = getPawn(pc)
        if valid(pc) and valid(pawn) then
            for _, w in ipairs(weaponsOf(pawn)) do
                local holder = subObj(w, "m_pHolder")
                local xh = subObj(w, "m_CrosshairInstance")
                -- Only weapons this player really holds; a shared weapon is left alone.
                if xh and holder and samePawn(holder, pawn) and rehomed[nameOf(xh)] ~= nameOf(pc) then
                    local okV, vis = pcall(function() return xh:GetVisibility() end)
                    pcall(function() xh:RemoveFromParent() end)
                    pcall(function() xh:SetOwningPlayer(pc) end)
                    local okA, added = pcall(function() return xh:AddToPlayerScreen(0) end)
                    if okV and vis ~= nil then pcall(function() xh:SetVisibility(vis) end) end
                    rehomed[nameOf(xh)] = nameOf(pc)
                    log("Reticle %s -> %s's half of the screen: %s", shortName(xh), shortName(pc),
                        okA and tostring(added) or "failed")
                end
            end
        end
    end
end

addTickJob("rehomeReticles", 0.5, rehomeReticles)

-- Ctrl+N: game-wide objects only (safe). Ctrl+Shift+N: also the game's own actors.
RegisterKeyBind(Key.N, { ModifierKey.CONTROL }, function()
    runGame("mainPlayerScan", function() findPrimaryPlayerRefs(false) end)
end)
RegisterKeyBind(Key.N, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
    runGame("mainPlayerScanActors", function() findPrimaryPlayerRefs(true) end)
end)

RegisterKeyBind(Key.R, { ModifierKey.CONTROL }, function()
    runGame("rewireP2", function() rewireP2("Ctrl+R") end)
end)

------------------------------------------------------------------------------------------
-- Split-screen crosshair: the game puts each player's crosshair at the centre of the WHOLE
-- screen. Move it to the centre of that player's own half, every frame, while Player 2
-- exists. (The crosshair position is also what the game aims with.)
------------------------------------------------------------------------------------------
local xhair = {}  -- [1] = Player 1, [2] = Player 2: { base = {x, y}, written = {x, y} }

local function player1Controller()
    local w, st = getWorld(), getStatics()
    return (w and st) and getP1(w, st) or nil
end

local function fixCrosshair(pc, slot)
    if not CFG.WRITE_CROSSHAIR_VALUE then return end
    local g = subObj(pc, "m_pGameplayToHud")
    if not g then return end
    local okV, v = pcall(function() return g.m_vCrosshairScreenLocation end)
    if not okV or not v then return end
    local x, y = readXY(v)
    if type(x) ~= "number" or type(y) ~= "number" then return end

    local st = xhair[slot] or {}
    -- A value we didn't write means the game set a fresh full-screen position.
    if not st.written or math.abs(x - st.written[1]) > 0.5 or math.abs(y - st.written[2]) > 0.5 then
        st.base = { x, y }
    end
    local bx, by = st.base[1], st.base[2]
    local isP2 = slot == 2
    local nx, ny
    -- The game measures this from the player's own half (same as its HUD), so the centre
    -- of each half is half the full-screen value for BOTH players. (Adding the half's
    -- offset for Player 2 pushed Player 2's aim point off their screen.)
    local addOffset = isP2 and CFG.CROSSHAIR_ABSOLUTE_COORDS
    if state.splitVertical then          -- left / right halves
        nx, ny = bx * 0.5 + (addOffset and bx or 0), by
    else                                 -- top / bottom halves
        nx, ny = bx, by * 0.5 + (addOffset and by or 0)
    end
    pcall(function() g.m_vCrosshairScreenLocation = { X = nx, Y = ny } end)
    st.written = { nx, ny }
    xhair[slot] = st
end

local function restoreCrosshair()
    local p1 = player1Controller()
    local st = xhair[1]
    if st and st.base and valid(p1) then
        local g = subObj(p1, "m_pGameplayToHud")
        if g then pcall(function() g.m_vCrosshairScreenLocation = { X = st.base[1], Y = st.base[2] } end) end
    end
    xhair = {}
end

local crosshairHooked = false
local function startCrosshairFix()
    if crosshairHooked or not CFG.AIM_CENTER_FIX then return end
    local ok, err = pcall(function()
        RegisterHook(KB_TICK_FN, function(Context)
            pcall(function()
                local now = os.clock()
                state.lastTick = now
                runTickJobs(now)
                if not valid(state.p2) then
                    if xhair[1] then restoreCrosshair() end
                    return
                end
                local pawn = Context:get()
                if samePawn(pawn, getPawn(state.p2)) then
                    if state.applyReticleShift then pcall(state.applyReticleShift) end
                    fixCrosshair(state.p2, 2)
                else
                    local p1 = player1Controller()
                    if samePawn(pawn, getPawn(p1)) then fixCrosshair(p1, 1) end
                end
            end)
        end)
    end)
    crosshairHooked = ok
    state.tickHooked = ok
    log("Split-screen crosshair fix: %s", ok and "on (each crosshair centred on its own half)" or ("FAILED: " .. tostring(err)))
end

-- Flip a gamepad axis for Player 2 only, with Unreal's InvertAxisKey command on P2's controller.
local function applyP2Invert()
    if not valid(state.p2) then return end
    local lib = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local w = getWorld()
    if not (valid(lib) and w) then log("P2 invert: KismetSystemLibrary/world not found"); return end
    for _, e in ipairs({ { CFG.P2_INVERT_LOOK_Y, "Gamepad_RightY" }, { CFG.P2_INVERT_LOOK_X, "Gamepad_RightX" } }) do
        if e[1] then
            local ok, err = pcall(function() lib:ExecuteConsoleCommand(w, "InvertAxisKey " .. e[2], state.p2) end)
            log("P2 invert %s: %s", e[2], ok and "applied" or ("failed: " .. tostring(err)))
        end
    end
end

state.afterSpawn = function()
    -- Player 2 was put next to Player 1 when created; only again if the body was swapped since
    pcall(function()
        local a = getPawn(player1Controller()):K2_GetActorLocation()
        local b = getPawn(state.p2):K2_GetActorLocation()
        local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
        if dx * dx + dy * dy + dz * dz > 800 * 800 then teleportP2ToP1() end
    end)
    if state.hookShieldWidget then pcall(state.hookShieldWidget) end
    if state.hookWeaponWheel then pcall(state.hookWeaponWheel) end
    pcall(applyP2Invert)
    pcall(startCrosshairFix)
    pcall(rewireP2, "spawn")
    -- Some parts (weapons, abilities) finish setting up a moment later; check again.
    later(2.0, "rewireP2", function() rewireP2("spawn +2s") end)
    if CFG.FORCE_HIGH_LOD then pcall(forceHighLod) end
    pcall(function() popGen = popGen + 1; populationTick(popGen) end)
    pcall(makeP2ImmuneToProbe)
    if CFG.SWAP_COMBO_ENABLED then pcall(startComboWatcher) end
    if state.applySplit then pcall(state.applySplit) end
    if CFG.AUTO_SYNC_PROGRESS and state.syncProgress then pcall(state.syncProgress) end
    if CFG.AUTO_KEYBOARD and not state.kbOn then pcall(toggleKeyboardP2) end
    local mode = CFG.AUTO_HUD_MODE
    local function apply()
        if mode == "anchors" then
            if state.placeHudByAnchors then state.placeHudByAnchors() end
            state.hudMode = 1
        elseif mode == "per_half" then
            placeHudPerPlayer()
            state.hudMode = 1
        elseif mode == "p1_only" then
            hudP1Only()
            state.hudMode = 2
        end
    end
    if mode == "per_half" or mode == "p1_only" or mode == "anchors" then
        local had = #hudWidgetsOf(state.p2)
        apply()
        -- Player 2's HUD may still be created a moment later; apply again only then
        later(1.5, "hudRetry", function()
            if valid(state.p2) and (had == 0 or #hudWidgetsOf(state.p2) ~= had) then apply() end
        end)
    end
end

-- Put each player's HUD on their half WITHOUT taking it off the screen: taking it off makes
-- it drop its connections (frozen radar, blinking threat card). The HUD stays where the
-- game put it and is only told which part of the screen to use.
-- after a game over Player 2 has a new body but the same controller: only what belongs to
-- the body is set up again (no new hooks: running the whole join setup again stacked hooks)
state.afterRespawn = function()
    -- (not the look invert: InvertAxisKey flips it, and the controller keeps it)
    pcall(rewireP2, "respawn")
    pcall(makeP2ImmuneToProbe)
    if state.applySplit then pcall(state.applySplit) end
    local mode = CFG.AUTO_HUD_MODE
    if mode == "per_half" then pcall(placeHudPerPlayer)
    elseif mode == "anchors" and state.placeHudByAnchors then pcall(state.placeHudByAnchors) end
end

local function halfAnchors(slot)
    if state.splitVertical then
        return slot == 1 and { 0, 0, 0.5, 1 } or { 0.5, 0, 1, 1 }
    end
    return slot == 1 and { 0, 0, 1, 0.5 } or { 0, 0.5, 1, 1 }
end
local function setHudArea(w, a)
    pcall(function() w:SetAnchorsInViewport({ Minimum = { X = a[1], Y = a[2] }, Maximum = { X = a[3], Y = a[4] } }) end)
    pcall(function() w:SetAlignmentInViewport({ X = 0, Y = 0 }) end)
    pcall(function() w:SetPositionInViewport({ X = 0, Y = 0 }, true) end)
    pcall(function() w:SetDesiredSizeInViewport({ X = 0, Y = 0 }) end)
end
local function placeHudByAnchors()
    log("=== EACH PLAYER'S HUD ON THEIR OWN HALF (kept on screen) ===")
    for slot, pc in ipairs({ player1Controller(), state.p2 }) do
        for _, w in ipairs(hudWidgetsOf(pc)) do
            if valid(w) then
                local okV, inVp = pcall(function() return w:IsInViewport() end)
                if not (okV and inVp) then pcall(function() w:AddToViewport(0) end) end
                setHudArea(w, halfAnchors(slot))
                log("  P%d %s -> its half", slot, shortName(w))
            end
        end
    end
end
state.placeHudByAnchors = placeHudByAnchors
state.reseatP1Hud = function() placeHudPerPlayer(true) end
state.restoreHudFull = function()
    for _, w in ipairs(hudWidgetsOf(player1Controller())) do
        if valid(w) then setHudArea(w, { 0, 0, 1, 1 }) end
    end
end

-- Ctrl+U toggles between "P1 only" and "each player's HUD on their own half".
local function cycleHud()
    if state.hudMode == 2 then
        state.hudMode = 1
        placeHudPerPlayer()
    else
        state.hudMode = 2
        hudP1Only()
    end
end

RegisterKeyBind(Key.U, { ModifierKey.CONTROL }, function()
    runGame("cycleHud", cycleHud)
end)

-- (Ctrl+E "share upgrades + respawn P2 pawn" removed: it had no visible effect.)

------------------------------------------------------------------------------------------
-- Skin cycling: Insert = Player 1 next, Home = Player 1 previous,
--               Delete = Player 2 next, End = Player 2 previous.
-- The skin list is read from the game's DT_PlayerSkinList data table (logged when first used).
------------------------------------------------------------------------------------------
local skinList = nil

local function tagNameOf(ps, field)
    local ok, tag = pcall(function() return ps[field] end)
    if not ok or tag == nil then return nil end
    local ok2, name = pcall(function() return tag.TagName:ToString() end)
    if ok2 then return tostring(name) end
    return nil
end

local function addName(list, e)
    if e == nil then return end
    local okg, v = pcall(function() return e:get() end)
    if okg and v ~= nil then e = v end
    local okS, str = pcall(function() return e:ToString() end)
    if okS and str and str ~= "" then
        list[#list + 1] = tostring(str)
    elseif type(e) == "string" and e ~= "" then
        list[#list + 1] = e
    end
end

local function rowNamesOf(tbl)
    local list = {}
    local how = "none"
    -- 1) RowMap:ForEach
    pcall(function()
        tbl.RowMap:ForEach(function(k, _) addName(list, k) end)
    end)
    if #list > 0 then log("Skins: rows read via RowMap:ForEach"); return list end
    -- 2) tbl:GetRowNames()
    pcall(function()
        local r = tbl:GetRowNames()
        for _, e in ipairs(arrayToList(r)) do addName(list, e) end
    end)
    if #list > 0 then log("Skins: rows read via GetRowNames"); return list end
    -- 3) the engine's data table function library (out param may come back as a return value or fill a table)
    local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    if valid(lib) then
        local out = {}
        local ok, r1, r2 = pcall(function() return lib:GetDataTableRowNames(tbl, out) end)
        local cands = { r1, r2, out, ok and out.OutRowNames or nil }
        for _, c in ipairs(cands) do
            if c ~= nil and type(c) ~= "boolean" then
                pcall(function()
                    for _, e in ipairs(arrayToList(c)) do addName(list, e) end
                end)
                if #list == 0 and type(c) == "table" then
                    for _, e in ipairs(c) do addName(list, e) end
                end
            end
            if #list > 0 then break end
        end
    end
    if #list > 0 then log("Skins: rows read via DataTableFunctionLibrary"); return list end
    -- 4) pairs() over RowMap
    pcall(function()
        for k, _ in pairs(tbl.RowMap) do addName(list, k) end
    end)
    if #list > 0 then log("Skins: rows read via pairs(RowMap)"); return list end
    return list
end

-- skin tags can also be listed by hand, one per line, in Mods\DAH2P\skins.txt
local function skinsFromFile()
    local list = {}
    for _, path in ipairs({ "Mods\\OverkillCoop\\skins.txt", "ue4ss\\Mods\\OverkillCoop\\skins.txt", "skins.txt" }) do
        local f = io.open(path, "r")
        if f then
            for line in f:lines() do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line ~= "" and line:sub(1, 1) ~= "#" then list[#list + 1] = line end
            end
            f:close()
            if #list > 0 then log("Skins: %d tag(s) read from %s", #list, path); return list end
        end
    end
    return list
end

local function loadSkinList()
    if skinList and #skinList > 0 then return skinList end
    skinList = {}
    local tables = FindAllOf("DataTable")
    if tables then
        for _, wanted in ipairs({ "DT_PlayerSkinList", "DT_GameplayTags_PlayerSkins" }) do
            for _, t in ipairs(tables) do
                if valid(t) and nameOf(t):find(wanted, 1, true) then
                    local names = rowNamesOf(t)
                    log("Skins: %d row(s) in %s", #names, wanted)
                    if #names > 0 then skinList = names; break end
                end
            end
            if #skinList > 0 then break end
        end
    end
    if #skinList == 0 then skinList = skinsFromFile() end
    for i, n in ipairs(skinList) do log("    [%d] %s", i, n) end
    -- always show the tags in use, so a skins.txt can be written if the table cannot be read
    if #skinList == 0 then
        local w, st = getWorld(), getStatics()
        local c = (w and st) and getP1(w, st) or nil
        local ps = c and subObj(c, "PlayerState")
        if ps then
            log("Skins: P1 selected tag = %s | default tag = %s",
                tostring(tagNameOf(ps, "m_oSelectedSkinTag")), tostring(tagNameOf(ps, "m_oDefaultSkinTag")))
        end
    end
    return skinList
end

local function cycleSkin(pc, dir, label)
    local list = loadSkinList()
    if #list == 0 then log("Skins: could not read the skin list."); return end
    if not valid(pc) then log("Skins: %s has no controller.", label); return end
    local ps = subObj(pc, "PlayerState")
    if not ps then log("Skins: %s has no player state.", label); return end
    state.skinIdx = state.skinIdx or {}
    local cur = tagNameOf(ps, "m_oSelectedSkinTag") or ""
    local idx = state.skinIdx[label]
    if not idx then
        idx = 0
        for i, n in ipairs(list) do
            if n == cur then idx = i; break end
        end
        if idx == 0 then idx = 1 end
    end
    idx = ((idx - 1 + dir) % #list) + 1
    state.skinIdx[label] = idx
    local name = list[idx]
    local tag = { TagName = FName(name) }
    local extra = label == "P3" or label == "P4" or label == "P1V"   -- P1V: Player 1's look only (no save)
    local ok, err = true, nil
    if extra then
        -- Players 3 and 4: the game's skin call also changed Player 1, so only their own body's
        -- look is changed (and remembered here)
        state.extraSkinName = state.extraSkinName or {}
        state.extraSkinName[label] = name
    else
        ok, err = pcall(function() ps:SetSelectedSkin(tag, false, CFG.SKIN_MARK_USER_CHANGED) end)
    end
    state.skinGen = (state.skinGen or 0) + 1  -- the icon over the head checks again
    log("Skins: %s '%s' -> '%s': SetSelectedSkin %s", label, cur, name,
        ok and "ok" or ("failed: " .. tostring(err)))
    local pawn = getPawn(pc)
    if valid(pawn) then
        local okE, errE = false, "skipped for Players 3 and 4"
        if not extra then
            okE, errE = pcall(function() pawn:OnSkinChanged(tag) end)
            if not okE then okE, errE = pcall(function() pawn:OnSkinChanged() end) end
            log("  pawn OnSkinChanged: %s", okE and "called" or ("failed: " .. tostring(errE)))
        end
        if (not okE) or label ~= "P1" then   -- P2, P3 and P4 need the variation pushed too
            local vc = subObj(pawn, "m_pVariationComponent")
            if vc then
                pcall(function() vc.m_VariationForStartup = FName(name) end)
                pcall(function() vc.m_ActiveVariation = FName(name) end)
                local okV, errV
                for n, call in ipairs({
                    function() vc:AssignVariation(FName(name)) end,
                    function() vc:AssignVariation(FName(name), 0) end,
                    function() vc:AssignVariation(FName(name), 0, true) end,
                    function() vc:AssignVariation(FName(name), true) end,
                }) do
                    okV, errV = pcall(call)
                    if okV then log("  variation AssignVariation: called (form %d)", n); break end
                end
                if not okV then log("  variation AssignVariation failed: %s", tostring(errV)) end
            else
                log("  no variation component on %s's pawn", label)
            end
        end
    end
    log("  selected skin tag is now: %s", tostring(tagNameOf(ps, "m_oSelectedSkinTag")))
end

local function p1Ctrl()
    local w, s = getWorld(), getStatics()
    if w and s then return getP1(w, s) end
    return nil
end

-- Bind to the first Key.<name> that exists (key names differ a little between UE4SS builds).
local function bindFirstAvailable(names, fn)
    for _, n in ipairs(names) do
        local k = Key[n]
        if k ~= nil then
            local ok = pcall(function() RegisterKeyBind(k, fn) end)
            if ok then return n end
        end
    end
    return nil
end

state.cycleP2Skin = function(dir) cycleSkin(state.p2, dir, "P2") end
-- pick a skin by its tag (the trainer's skin list)
state.setP2Skin = function(tag)
    if not valid(state.p2) then return end
    local list = loadSkinList()
    local want = nil
    for i, n in ipairs(list) do if n == tag then want = i end end
    if not want then log("Skins: %s isn't in the skin list", tostring(tag)) return end
    local ps = subObj(state.p2, "PlayerState")
    local cur = ps and tagNameOf(ps, "m_oSelectedSkinTag") or ""
    local idx = (state.skinIdx and state.skinIdx.P2) or nil
    if not idx then for i, n in ipairs(list) do if n == cur then idx = i end end end
    idx = idx or 1
    if idx ~= want then cycleSkin(state.p2, want - idx, "P2") end
end
-- Skin keys: one per player (Player 1 uses the game's own menu): Delete = Player 2,
-- End = Player 3, Insert = Player 4. Each press is the next skin. (Pads: Select + D-pad.)
state.extraSkin = function(slot, dir)
    local pc = state.extraPlayers and state.extraPlayers[slot]
    if valid(pc) then cycleSkin(pc, dir or 1, "P" .. slot) else log("Skin key: Player %d isn't in the game", slot) end
end
local skinKeys = {
    { { "DEL", "DELETE" },  function() cycleSkin(state.p2, 1, "P2") end },
    { { "END" },            function() state.extraSkin(3) end },
    { { "INSERT", "INS" },  function() state.extraSkin(4) end },
}
local boundNames = {}
for _, entry in ipairs(skinKeys) do
    local action = entry[2]
    local bound = bindFirstAvailable(entry[1], function()
        log("Skin key pressed: %s", tostring(entry[1][1]))
        runGame("skin", action)
    end)
    boundNames[#boundNames + 1] = bound or "(unavailable)"
end
log("Skin keys bound: Player 2 %s, Player 3 %s, Player 4 %s", boundNames[1], boundNames[2], boundNames[3])

------------------------------------------------------------------------------------------
-- Extra skin keys, in case the plain keys don't register:
-- Ctrl+F5 / Ctrl+F6 = Player 1 previous / next, Ctrl+F7 / Ctrl+F8 = Player 2 previous / next
------------------------------------------------------------------------------------------
do
    local chords = {
        { "F7", function() cycleSkin(state.p2, -1, "P2") end },
        { "F8", function() cycleSkin(state.p2, 1, "P2") end },
    }
    for _, e in ipairs(chords) do
        local k, action, nm = Key[e[1]], e[2], e[1]
        if k ~= nil then
            pcall(function()
                RegisterKeyBind(k, { ModifierKey.CONTROL }, function()
                    log("Skin chord pressed: Ctrl+%s", nm)
                    runGame("skin", action)
                end)
            end)
        end
    end
end

------------------------------------------------------------------------------------------
-- Ctrl+F9: write ONE file (dump_all.txt) with the class layouts, including every function's
-- parameters, of the pieces involved in abilities, shooting/aiming, skins and world streaming.
------------------------------------------------------------------------------------------
local function writeDumpFile(tag, lines)
    local path = "Mods\\OverkillCoop\\dump_" .. tag .. ".txt"
    local f = io.open(path, "w")
    if not f then
        path = "dump_" .. tag .. ".txt"
        f = io.open(path, "w")
    end
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
        log("dump %s: %d lines -> %s", tag, #lines, path)
    else
        log("dump %s: could not open a file for writing (%d lines lost).", tag, #lines)
    end
end

local function appendClassDump(lines, label, obj)
    lines[#lines + 1] = "######## " .. label .. " ########"
    if not valid(obj) then
        lines[#lines + 1] = "(nil / invalid)"
        return
    end
    lines[#lines + 1] = "object: " .. nameOf(obj)
    local ok0, c = pcall(function() return obj:GetClass() end)
    local depth = 0
    while ok0 and valid(c) and depth < 12 do
        local cn = nameOf(c)
        lines[#lines + 1] = "## " .. cn
        if cn:find("/Script/Engine%.") or cn:find("/Script/CoreUObject%.") then break end
        pcall(function()
            c:ForEachProperty(function(p) lines[#lines + 1] = "  P " .. p:GetFullName() end)
        end)
        pcall(function()
            c:ForEachFunction(function(f)
                lines[#lines + 1] = "  F " .. f:GetFullName()
                pcall(function()
                    f:ForEachProperty(function(p) lines[#lines + 1] = "      param " .. p:GetFullName() end)
                end)
            end)
        end)
        local okS, sup = pcall(function() return c:GetSuperStruct() end)
        if not okS then break end
        c = sup
        depth = depth + 1
    end
end

local function appendStructFields(lines, label, st)
    lines[#lines + 1] = "######## " .. label .. " ########"
    if not valid(st) then
        lines[#lines + 1] = "(nil / invalid)"
        return
    end
    pcall(function()
        st:ForEachProperty(function(p) lines[#lines + 1] = "  field " .. p:GetFullName() end)
    end)
end

------------------------------------------------------------------------------------------
-- Split-screen reticle position.
-- Each player's HUD sits on its own half of the screen, but the game still places the
-- reticle at the centre of the WHOLE screen, measured from that half's top-left corner.
-- That lands Player 1's reticle on the middle of the TV (the right edge of the left half)
-- and pushes Player 2's off the right edge of the TV, so it can't be seen.
-- Fix: slide every reticle widget back by a quarter of the screen (render translation),
-- on every frame, on top of whatever position the game gives it.
-- Ctrl+Q cycles which widgets get moved, so the right one can be found in-game.
------------------------------------------------------------------------------------------
local RETICLE_MODE_NAMES = { [0] = "off", [1] = "all reticles", [2] = "weapon reticles only",
                             [3] = "3-star reticle only" }
state.reticleMode = CFG.RETICLE_SHIFT_MODE or 1
local reticleWidgets = {}   -- list of widgets to move (refreshed twice a second)
local reticleState = {}     -- widget path -> { base = {x, y}, written = {x, y} }
local reticleShift = { 0, 0 }     -- Player 1's reticles
local reticleShiftP2 = { 0, 0 }   -- Player 2's reticles
local reticleLogged = {}
onWorldChange(function() reticleWidgets = {}; reticleState = {}; rehomed = {}; xhair = {} end); state.onP2Leave(function() reticleWidgets = {}; reticleState = {}; rehomed = {}; xhair = {} end)

local function reticleKind(w)
    local n = shortName(w)
    if n:find("^Default__") then return nil end
    if n:find("BPW_Crosshair_") then return "weapon" end
    if n:find("3StarCrosshair") then return "3star" end
    local l = n:lower()
    if l:find("crosshair") or l:find("reticle") then return "other" end
    return nil
end

local function reticleWanted(kind)
    local m = state.reticleMode
    if m == 1 then return kind ~= nil end
    if m == 2 then return kind == "weapon" end
    if m == 3 then return kind == "3star" end
    return false
end

local function getTranslation(w)
    local ok, t = pcall(function() return w.RenderTransform.Translation end)
    if ok and t then return readXY(t) end
    return nil, nil
end

local function setTranslation(w, x, y)
    return pcall(function() w:SetRenderTranslation({ X = x, Y = y }) end)
end

local function keyOf(w)
    local ok, a = pcall(function() return w:GetAddress() end)
    return ok and tostring(a) or nil
end

local function resetReticles()
    for _, e in ipairs(reticleWidgets) do
        local w = e.w
        local key = valid(w) and keyOf(w)
        local st = key and reticleState[key]
        if st and st.base then setTranslation(w, st.base[1], st.base[2]) end
    end
    reticleWidgets, reticleState = {}, {}
end

local function computeReticleShift()
    local world = getWorld()
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    if not (world and valid(lib)) then return false end
    local okS, size = pcall(function() return lib:GetViewportSize(world) end)
    local okC, scale = pcall(function() return lib:GetViewportScale(world) end)
    local w, h = nil, nil
    if okS then w, h = readXY(size) end
    if type(w) ~= "number" or w <= 0 then return false end
    if not (okC and type(scale) == "number" and scale > 0) then scale = 1 end
    -- Each reticle is drawn at the player's aim point (in whole-screen pixels), but measured
    -- from the corner of that player's half. Shift it so it lands in the middle of the half.
    -- Works with the stock aim point (middle of the TV) and with the DLL's aim fix (middle
    -- of each player's own half).
    local function aimPoint(pc)
        local g = valid(pc) and subObj(pc, "m_pGameplayToHud")
        local okV, v = pcall(function() return g and g.m_vCrosshairScreenLocation end)
        if okV and v then return readXY(v) end
        return nil, nil
    end
    local x1, y1 = aimPoint(player1Controller())
    local x2, y2 = aimPoint(state.p2)
    if type(x1) ~= "number" then x1, y1 = w / 2, h / 2 end
    if type(x2) ~= "number" then x2, y2 = x1, y1 end
    if state.splitVertical then
        reticleShift = { (w / 4 - x1) / scale, 0 }
        reticleShiftP2 = { (w / 4 - x2) / scale, 0 }
    else
        local dllFix = y2 > h / 2 + 1
        local function wantY(y) if dllFix then return y > h / 2 and y - h / 2 or y end return y / 2 end
        reticleShift = { 0, (wantY(y1) - y1) / scale }
        reticleShiftP2 = { 0, (wantY(y2) - y2) / scale }
    end
    return true
end

local function refreshReticleList()
    if not valid(state.p2) or state.reticleMode == 0 then
        if #reticleWidgets > 0 then resetReticles() end
        return
    end
    if not computeReticleShift() then return end
    local list = {}
    local all = FindAllOf("UserWidget") or {}
    for _, w in ipairs(all) do
        if valid(w) then
            local kind = reticleKind(w)
            if reticleWanted(kind) and not (state.modPlacedWidgets and state.modPlacedWidgets[keyOf(w) or ""]) then
                local path = pathOf(w) or ""
                -- Skip reticles that sit inside another reticle (the outer one already moves).
                local parentPath = path:match("^(.*)[%.:][^%.:]+$") or ""
                if not parentPath:lower():find("crosshair") then
                    local okO, owner = pcall(function() return w:GetOwningPlayer() end)
                    local sh = (okO and valid(owner) and samePawn(owner, state.p2)) and reticleShiftP2 or reticleShift
                    list[#list + 1] = { w = w, s = sh }
                    local tag = path .. string.format("|%.0f|%.0f", sh[1], sh[2])
                    if not reticleLogged[tag] then
                        reticleLogged[tag] = true
                        log("Reticle fix: moving %s (%s) by (%.0f, %.0f)", shortName(w), kind, sh[1], sh[2])
                    end
                end
            end
        end
    end
    reticleWidgets = list
end

local function applyReticleShift()
    if state.reticleMode == 0 then return end
    for _, e in ipairs(reticleWidgets) do
        local w, sh = e.w, e.s
        if valid(w) then
            local key = keyOf(w)
            local x, y = getTranslation(w)
            if key and type(x) == "number" then
                local st = reticleState[key] or {}
                -- A value we didn't write is the game's own position: keep it as the base.
                if not st.written or math.abs(x - st.written[1]) > 0.5 or math.abs(y - st.written[2]) > 0.5 then
                    st.base = { x, y }
                end
                local nx, ny = st.base[1] + sh[1], st.base[2] + sh[2]
                if not st.written or nx ~= st.written[1] or ny ~= st.written[2] or x ~= nx or y ~= ny then
                    setTranslation(w, nx, ny)
                end
                st.written = { nx, ny }
                reticleState[key] = st
            end
        end
    end
end
state.applyReticleShift = applyReticleShift

addTickJob("reticleList", 0.5, refreshReticleList)

------------------------------------------------------------------------------------------
-- Split-screen AIM fix (top/bottom layout).
-- The game aims every weapon, lock-on and ability at one screen point: the middle of the
-- WHOLE screen, raised by the target system's m_fCrosshairOffsetY (a fraction of the
-- screen height). With two views that point sits on the edge between them, which is why
-- shots fly to the centre of the TV. The game has no sideways offset, but it does have
-- this up/down one, so with the screen split top/bottom we can give each player an offset
-- that puts their aim point back in the middle of their own view:
--   top player:    offset = 0.25 + original / 2
--   bottom player: offset = original / 2 - 0.25
-- The game then aims, locks on and draws the reticle from the right point by itself.
------------------------------------------------------------------------------------------
local aimOrig = {}   -- target component address -> the game's own offset
local aimLogged = {}
onWorldChange(function() aimOrig = {}; aimLogged = {} end); state.onP2Leave(function() aimOrig = {}; aimLogged = {} end)

local function aimTargetComp(pc)
    return subObj(getPawn(pc), "m_pTargetComponent")
end

local function setAimOffset(tc, value, label)
    local key = keyOf(tc)
    if not key then return end
    if aimOrig[key] == nil then
        local ok, v = pcall(function() return tc.m_fCrosshairOffsetY end)
        if not (ok and type(v) == "number") then return end
        aimOrig[key] = v
    end
    local want = value(aimOrig[key])
    local ok, cur = pcall(function() return tc.m_fCrosshairOffsetY end)
    if ok and type(cur) == "number" and math.abs(cur - want) > 0.0001 then
        pcall(function() tc.m_fCrosshairOffsetY = want end)
    end
    if aimLogged[key] ~= want then
        aimLogged[key] = want
        log("Aim fix: %s aim offset %.3f -> %.3f", label, aimOrig[key], want)
    end
end

local function restoreAimOffsets()
    for _, pc in ipairs({ player1Controller(), state.p2 }) do
        local tc = valid(pc) and aimTargetComp(pc)
        local key = tc and keyOf(tc)
        if key and aimOrig[key] ~= nil then
            pcall(function() tc.m_fCrosshairOffsetY = aimOrig[key] end)
        end
    end
    aimLogged = {}
end

local function aimFixTick()
    if not CFG.SPLIT_AIM_FIX then return end
    if not valid(state.p2) or state.splitVertical then
        if next(aimLogged) then restoreAimOffsets() end
        return
    end
    local p1 = player1Controller()
    local tc1, tc2 = valid(p1) and aimTargetComp(p1), aimTargetComp(state.p2)
    if tc1 then setAimOffset(tc1, function(o) return 0.25 + o / 2 end, "Player 1 (top)") end
    if tc2 then setAimOffset(tc2, function(o) return o / 2 - 0.25 end, "Player 2 (bottom)") end
end
addTickJob("aimFix", 0.25, aimFixTick)

-- Weapon-wheel probe: log which HUD reacts when someone holds the weapon-select button.
local wheelHooked = false
local function hookWeaponWheel()
    if wheelHooked then return end
    local ok = pcall(function()
        RegisterHook("/Game/Blueprints/UI/HUD/BPW_HUD_Base.BPW_HUD_Base_C:Event_OnSelectionMenuStateChanged",
            function(Context)
                pcall(function()
                    local hud = Context:get()
                    local okO, owner = pcall(function() return hud:GetOwningPlayer() end)
                    log("Weapon wheel: %s (owner %s) got a selection-menu change", shortName(hud),
                        okO and shortName(owner) or "?")
                end)
            end)
    end)
    wheelHooked = ok
    log("Weapon wheel probe: %s", ok and "on" or "not available")
end
state.hookWeaponWheel = hookWeaponWheel



RegisterKeyBind(Key.Q, { ModifierKey.CONTROL }, function()
    runGame("cycleReticleMode", function()
        resetReticles()
        reticleLogged = {}
        state.reticleMode = (state.reticleMode + 1) % 4
        log("Reticle fix mode %d: %s", state.reticleMode, RETICLE_MODE_NAMES[state.reticleMode])
        refreshReticleList()
    end)
end)

------------------------------------------------------------------------------------------
-- Ctrl+E: AIM REPORT. For both players: where the held weapon is aiming and at what,
-- the lock-on / focus targets, the crosshair value the game aims with, and every reticle
-- widget with its position. Also writes dump_aim.txt with the class layouts involved.
------------------------------------------------------------------------------------------
local function objProps(obj)
    local out = {}
    forEachObjectProperty(obj, function(name)
        local okV, v = pcall(function() return obj[name] end)
        if okV and valid(v) then out[#out + 1] = name .. "=" .. shortName(v) end
    end)
    return table.concat(out, ", ")
end

local function structStr(s, depth)
    depth = depth or 0
    if s == nil then return "nil" end
    if type(s) ~= "userdata" then return tostring(s) end
    if valid(s) then return shortName(s) end
    local x, y = readXY(s)
    if type(x) == "number" then
        local okZ, z = pcall(function() return s.Z end)
        if okZ and type(z) == "number" then return string.format("(%.0f, %.0f, %.0f)", x, y, z) end
        return string.format("(%.1f, %.1f)", x, y)
    end
    -- A struct: list its fields.
    if depth > 1 then return describe(s) end
    local parts = {}
    local okT = pcall(function()
        local st = s:GetStruct()
        st:ForEachProperty(function(p)
            local n = p:GetFName():ToString()
            local okV, v = pcall(function() return s[n] end)
            parts[#parts + 1] = n .. "=" .. (okV and structStr(v, depth + 1) or "?")
        end)
    end)
    if okT and #parts > 0 then return "{" .. table.concat(parts, ", ") .. "}" end
    return describe(s)
end

local function callStr(obj, fn, ...)
    local args = { ... }
    local ok, r = pcall(function() return obj[fn](obj, table.unpack(args)) end)
    if not ok then return "<call failed>" end
    return structStr(r)
end

local function aimReport()
    log("=== AIM REPORT ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then return end
    local lines = {}
    for _, e in ipairs({ { "P1", getP1(world, statics) }, { "P2", state.p2 } }) do
        local label, pc = e[1], e[2]
        local pawn = getPawn(pc)
        if valid(pc) and valid(pawn) then
            local g = subObj(pc, "m_pGameplayToHud")
            local okV, v = pcall(function() return g and g.m_vCrosshairScreenLocation end)
            log("%s crosshair value=%s", label, okV and structStr(v) or "?")
            local xs = xhair[label == "P1" and 1 or 2]
            if xs and xs.base then log("  game wrote (%.1f, %.1f), we wrote (%.1f, %.1f)", xs.base[1], xs.base[2],
                xs.written and xs.written[1] or -1, xs.written and xs.written[2] or -1) end
            log("  aim offset (m_fCrosshairOffsetY) = %s", propStr(subObj(pawn, "m_pTargetComponent"), "m_fCrosshairOffsetY"))
            for _, f in ipairs({ "m_pTargetComponent", "m_pLockOnComponent", "m_pFocusComponent",
                                 "m_pCameraHandle", "m_pAITargetComponent" }) do
                local c = subObj(pawn, f)
                if c then log("  %s (%s): %s", f, shortName(c), objProps(c)) end
            end
            local lock = subObj(pawn, "m_pLockOnComponent")
            if lock then log("  lock-on target: %s", callStr(lock, "GetLockOnTarget")) end
            local mentalC = subObj(pawn, "m_pMentalAbilityComponent")
            if mentalC then
                log("  mental aim target: %s", propStr(mentalC, "m_pCurrentAimTarget"))
                local okA, arr = pcall(function() return mentalC.m_aPlayerMentalAbilities end)
                for _, a in ipairs(okA and arrayToList(arr) or {}) do
                    if valid(a) then
                        log("    %s: aim %s | active %s | user %s", shortName(a), propStr(a, "m_pCurrentAimTarget"),
                            propStr(a, "m_pActiveTarget"), propStr(a, "m_pUser"))
                    end
                end
            end
            local focusC = subObj(pawn, "m_pFocusComponent")
            if focusC then log("  focus auto-lock target: %s", propStr(focusC, "m_pCurrentAutoLockTarget")) end
            for _, w in ipairs(weaponsOf(pawn)) do
                log("  weapon %s: aim data %s", shortName(w), callStr(w, "GetCurrentAimData"))
                log("    locked target %s | first auto-locked %s | auto-target %s | locked list %d",
                    callStr(w, "GetCurrentLocketTarget"), callStr(w, "GetFirstAutolockedTarget"),
                    propStr(w, "m_bUsesAutoTargetSystem"),
                    #arrayToList((function() local ok, a = pcall(function() return w.m_apCurrentLockedTargets end); return ok and a or nil end)()))
                appendClassDump(lines, label .. " weapon " .. shortName(w), w)
            end
            if label == "P1" then
                appendClassDump(lines, "GameplayToHud", g)
                appendClassDump(lines, "Focus component", subObj(pawn, "m_pFocusComponent"))
                appendClassDump(lines, "Target component", subObj(pawn, "m_pTargetComponent"))
                appendClassDump(lines, "Mental abilities component", subObj(pawn, "m_pMentalAbilityComponent"))
                appendClassDump(lines, "Camera manager", subObj(pc, "PlayerCameraManager"))
                appendClassDump(lines, "HUD actor", subObj(pc, "MyHUD"))
            end
        else
            log("%s: no character", label)
        end
    end
    -- Every reticle-looking widget, and where it is.
    local seen3, seenW = false, false
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        local kind = valid(w) and reticleKind(w)
        if kind then
            local okO, owner = pcall(function() return w:GetOwningPlayer() end)
            local okI, inVp = pcall(function() return w:IsInViewport() end)
            local okS, vis = pcall(function() return w:GetVisibility() end)
            local tx, ty = getTranslation(w)
            log("  widget %s [%s] owner=%s inViewport=%s visibility=%s translation=(%s, %s) path=%s",
                shortName(w), kind, okO and shortName(owner) or "?", okI and tostring(inVp) or "?",
                okS and tostring(vis) or "?", tostring(tx), tostring(ty), pathOf(w) or "?")
            if kind == "3star" and not seen3 then seen3 = true; appendClassDump(lines, "3-star reticle", w) end
            if kind == "weapon" and not seenW then seenW = true; appendClassDump(lines, "weapon reticle", w) end
        end
    end
    -- The game-wide managers that pick the yellow lock-on target, aim assist and highlights.
    local gs = FindFirstOf("GameStateBase")
    if valid(gs) then
        for _, fn in ipairs({ "GetLockOnManager", "GetAimAssistManager", "GetHighlightableSceneObjectManager" }) do
            local okM, m = pcall(function() return gs[fn](gs) end)
            if okM and valid(m) then
                log("  %s -> %s | %s", fn, nameOf(m), objProps(m))
                appendClassDump(lines, fn, m)
            else
                log("  %s -> none", fn)
            end
        end
    end
    -- HUD pieces: health display, weapon slot, lock-on highlighter, and the selection component.
    local p1c = player1Controller()
    for _, hud in ipairs(hudWidgetsOf(p1c)) do
        for _, f in ipairs({ "BPW_UI_HUDPlayerStats", "BPW_UI_Slot_Weapon", "BPW_UI_HUD_SceneObjectHighlighter", "BPW_UI_Minimap" }) do
            local wdg = subObj(hud, f)
            if wdg then
                log("  P1 HUD %s: %s", f, objProps(wdg))
                appendClassDump(lines, "HUD " .. f, wdg)
            end
        end
    end
    for _, hud in ipairs(hudWidgetsOf(p1c)) do
        local mm = subObj(hud, "BPW_UI_Minimap")
        local radar = mm and subObj(mm, "BPW_UI_HUDRadar")
        if radar then
            log("  P1 radar: %s", objProps(radar))
            appendClassDump(lines, "Radar", radar)
        end
    end
    local gsr = FindFirstOf("GameStateBase")
    local okR, rmgr = pcall(function() return gsr:GetRadarManager() end)
    if okR and valid(rmgr) then log("  Radar manager: %s | %s", nameOf(rmgr), objProps(rmgr)); appendClassDump(lines, "Radar manager", rmgr) end
    local okHM, hmgr = pcall(function() return gsr:GetHighlightableSceneObjectManager() end)
    local oc = okHM and valid(hmgr) and subObj(hmgr, "m_pFocusedOpportunityWidget_Mental")
    if oc then log("  Opportunity widget: %s | %s | class %s", nameOf(oc), objProps(oc), propStr(oc, "WidgetClass")); appendClassDump(lines, "Opportunity widget", oc) end
    for _, cn in ipairs({ "BP_ProjectileAnalProbe_C", "BP_AnalProbe_Link_C" }) do
        local list = FindAllOf(cn) or {}
        if valid(list[1]) then
            log("  %s: %d around, first: %s", cn, #list, objProps(list[1]))
            appendClassDump(lines, cn, list[1])
        end
    end
    for _, w in ipairs(weaponsOf(getPawn(state.p2))) do
        if shortName(w):find("AnalProbe") then log("  P2 probe gun: %s", objProps(w)); appendClassDump(lines, "P2 probe gun", w) end
    end
    local p1pawn = getPawn(p1c)
    appendClassDump(lines, "Interactions component", subObj(p1pawn, "m_pInteractionsComponent"))
    appendClassDump(lines, "WeaponAndAbilitySelection", subObj(p1pawn, "m_pWeaponAndAbilitySelection"))
    appendClassDump(lines, "LockOn component", subObj(p1pawn, "m_pLockOnComponent"))
    local mental = subObj(p1pawn, "m_pMentalAbilityComponent")
    if mental then
        for _, a in ipairs(arrayToList((function() local ok, v = pcall(function() return mental.m_aPlayerMentalAbilities end); return ok and v or nil end)())) do
            if valid(a) and shortName(a):find("Psycokinesis") then appendClassDump(lines, "PK ability", a); log("  PK ability: %s", objProps(a)) end
        end
    end
    -- What's lying around Player 2 (to find the brain / ammo / probe classes).
    local p2pawn = getPawn(state.p2)
    if valid(p2pawn) then
        local okL, here = pcall(function() return p2pawn:K2_GetActorLocation() end)
        local counts = {}
        for _, a in ipairs(okL and (FindAllOf("Actor") or {}) or {}) do
            local okA, l = pcall(function() return a:K2_GetActorLocation() end)
            if okA and l then
                local dx, dy, dz = l.X - here.X, l.Y - here.Y, l.Z - here.Z
                if dx * dx + dy * dy + dz * dz < 600 * 600 then
                    local cn = classNameOf(a):match("([^%.]+)$") or "?"
                    counts[cn] = (counts[cn] or 0) + 1
                end
            end
        end
        local parts = {}
        for k, v in pairs(counts) do parts[#parts + 1] = string.format("%s x%d", k, v) end
        table.sort(parts)
        log("  Near Player 2: %s", table.concat(parts, ", "))
    end
    log("Reticle fix mode %d (%s), shift (%.0f, %.0f), %d widget(s) moved", state.reticleMode,
        RETICLE_MODE_NAMES[state.reticleMode], reticleShift[1], reticleShift[2], #reticleWidgets)
    writeDumpFile("aim", lines)
end

RegisterKeyBind(Key.E, { ModifierKey.CONTROL }, function()
    runGame("aimReport", aimReport)
end)

------------------------------------------------------------------------------------------
-- Ctrl+Shift+W: WORLD SCAN for the trainer menu. Lists every kind of actor in the map, the
-- streaming levels, and the full layout (properties + functions + current numbers) of
-- anything to do with sky, sun, time of day, fog, weather, lighting, landing pads and
-- spawn points. Writes dump_world.txt next to the game exe.
------------------------------------------------------------------------------------------
do
local WORLD_KEYWORDS = { "sky", "sun", "moon", "time", "day", "night", "fog", "weather", "rain", "cloud",
    "atmos", "light", "post", "wind", "pad", "landing", "saucer", "ufo", "spawn", "teleport", "travel",
    "season", "environment", "lighting", "storm", "star", "zone", "district", "level", "map", "world",
    "cow", "cattle", "bovine", "explo", "mutat", "psi", "psy", "pulse", "shock", "aoe", "orb" }
local function matchesWorld(name)
    local n = name:lower()
    for _, k in ipairs(WORLD_KEYWORDS) do if n:find(k, 1, true) then return true end end
    return false
end
local function appendValues(lines, obj)
    local okC, c = pcall(function() return obj:GetClass() end)
    local depth = 0
    while okC and valid(c) and depth < 6 do
        local cn = nameOf(c)
        if cn:find("/Script/CoreUObject%.") then break end
        pcall(function()
            c:ForEachProperty(function(p)
                local pn = p:GetFName():ToString()
                local pt = ""
                pcall(function() pt = p:GetClass():GetFName():ToString() end)
                -- read only simple values (reading some struct/delegate/map kinds crashed the game)
                local simple = pt == "FloatProperty" or pt == "IntProperty" or pt == "BoolProperty"
                    or pt == "ByteProperty" or pt == "ObjectProperty"
                local okV, v = false, nil
                if simple then okV, v = pcall(function() return obj[pn] end) end
                if okV then
                    local t = type(v)
                    if t == "number" then lines[#lines + 1] = string.format("    = %s %.4f", pn, v)
                    elseif t == "boolean" then lines[#lines + 1] = "    = " .. pn .. " " .. tostring(v)
                    elseif t == "userdata" and valid(v) then lines[#lines + 1] = "    = " .. pn .. " -> " .. shortName(v) end
                end
            end)
        end)
        local okS, sup = pcall(function() return c:GetSuperStruct() end)
        if not okS then break end
        c = sup
        depth = depth + 1
    end
end
local function worldScan()
    log("=== WORLD SCAN -> dump_world.txt ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local lines = { "world: " .. nameOf(world) }
    -- every actor, grouped by class
    local counts, firstOf, order = {}, {}, {}
    local actorClass = StaticFindObject("/Script/Engine.Actor")
    local out = {}
    pcall(function() statics:GetAllActorsOfClass(world, actorClass, out) end)
    for _, a in ipairs(out) do
        local v = a
        if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
        if valid(v) then
            local okC, c = pcall(function() return v:GetClass() end)
            local cn = okC and nameOf(c) or "?"
            if not counts[cn] then counts[cn] = 0; firstOf[cn] = v; order[#order + 1] = cn end
            counts[cn] = counts[cn] + 1
        end
    end
    table.sort(order)
    lines[#lines + 1] = string.format("#### %d actors, %d kinds", #out, #order)
    for _, cn in ipairs(order) do lines[#lines + 1] = string.format("  %5d  %s", counts[cn], cn) end
    -- streaming levels (other map pieces that can be loaded)
    lines[#lines + 1] = "#### streaming levels"
    pcall(function()
        for _, l in ipairs(arrayToList(world.StreamingLevels)) do
            local pkg = "?"
            pcall(function() pkg = l.PackageNameToLoad:ToString() end)
            local okW, wa = pcall(function() return l.WorldAsset end)
            local loaded = "?"
            pcall(function() loaded = tostring(l:IsLevelLoaded()) .. "/" .. tostring(l:IsLevelVisible()) end)
            lines[#lines + 1] = string.format("  %s | %s | loaded/visible %s", shortName(l), pkg, loaded)
        end
    end)
    -- details for the interesting kinds
    for _, cn in ipairs(order) do
        if matchesWorld(cn) then
            appendClassDump(lines, string.format("%s (x%d)", cn, counts[cn]), firstOf[cn])
            lines[#lines + 1] = "  current values of the first one:"
            appendValues(lines, firstOf[cn])
        end
    end
    -- what the cow-like things (and other mission props) are made of: meshes, materials, effects
    lines[#lines + 1] = "#### parts of cow / explosive / mutant / psi actors"
    local compClass = StaticFindObject("/Script/Engine.ActorComponent")
    for _, cn in ipairs(order) do
        local low = cn:lower()
        local short = low:match("[^/]+$") or low
        if short:find("cow") or short:find("cattle") or short:find("explo") or short:find("mutat") or short:find("mutant")
            or short:find("psi") or short:find("psy") or short:find("pulse") or short:find("shock") or short:find("aoe") or short:find("orb") then
            lines[#lines + 1] = string.format("  %s (x%d)", cn, counts[cn])
            local okL, comps = pcall(function() return firstOf[cn]:K2_GetComponentsByClass(compClass) end)
            for _, comp in ipairs(okL and arrayToList(comps) or {}) do
                if valid(comp) then
                    local kind = nameOf(comp:GetClass()):match("[^%.]+$") or "?"
                    local bits = {}
                    pcall(function() if valid(comp.Template) then bits[#bits + 1] = "effect " .. nameOf(comp.Template) end end)
                    pcall(function() if valid(comp.StaticMesh) then bits[#bits + 1] = "mesh " .. nameOf(comp.StaticMesh) end end)
                    pcall(function() if valid(comp.SkeletalMesh) then bits[#bits + 1] = "mesh " .. nameOf(comp.SkeletalMesh) end end)
                    pcall(function() if valid(comp.Sound) then bits[#bits + 1] = "sound " .. nameOf(comp.Sound) end end)
                    pcall(function()
                        local n = comp:GetNumMaterials()
                        for k = 0, n - 1 do
                            local m = comp:GetMaterial(k)
                            if valid(m) then bits[#bits + 1] = "material " .. nameOf(m) end
                        end
                    end)
                    lines[#lines + 1] = string.format("    %s %s %s", kind, shortName(comp), table.concat(bits, " | "))
                end
            end
        end
    end
    -- loaded classes (blueprints too) with interesting names, even if not placed in this map
    lines[#lines + 1] = "#### loaded classes with sky/time/weather/pad/... names"
    for _, kind in ipairs({ "BlueprintGeneratedClass", "Class" }) do
        local all = FindAllOf(kind) or {}
        for _, c in ipairs(all) do
            local n = nameOf(c)
            if matchesWorld(n:match("[^%.]+$") or n) and not n:find("/Script/UMG", 1, true) then lines[#lines + 1] = "  " .. kind .. " " .. n end
        end
    end
    -- game-state managers
    local gs = FindFirstOf("GameStateBase")
    if valid(gs) then
        appendClassDump(lines, "GameState", gs)
        appendValues(lines, gs)
    end
    local mapName = (nameOf(world):match("([%w_]+)$") or "map"):gsub("_Main$", "")
    -- one file per scan (map + time), so scans on several missions of one map don't overwrite each other
    writeDumpFile("world_" .. mapName .. "_" .. os.date("%H%M%S"), lines)
end
RegisterKeyBind(Key.W, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
    runGame("worldScan", worldScan)
end)
end

------------------------------------------------------------------------------------------
-- Ctrl+D (experiment): turn the game's auto-aim (the yellow lock) off/on for Player 2's
-- weapons. If Player 2's shots then go where Player 2 aims, the shared lock is the culprit.
------------------------------------------------------------------------------------------
state.p2AutoAimOff = false
local function setP2AutoAim()
    if not valid(state.p2) then return end
    for _, w in ipairs(weaponsOf(getPawn(state.p2))) do
        pcall(function() w.m_bUsesAutoTargetSystem = not state.p2AutoAimOff end)
    end
end
RegisterKeyBind(Key.D, { ModifierKey.CONTROL }, function()
    runGame("toggleP2AutoAim", function()
        state.p2AutoAimOff = not state.p2AutoAimOff
        setP2AutoAim()
        log("Player 2 auto-aim: %s", state.p2AutoAimOff and "OFF (shots go straight where P2 aims)" or "on (game default)")
    end)
end)
addTickJob("p2AutoAim", 1.0, function() if state.p2AutoAimOff then setP2AutoAim() end end)

------------------------------------------------------------------------------------------
-- Co-op "downed" system: while both players are on foot, a player whose shield is broken
-- goes down from the next hit instead of dying (which would reload the checkpoint). Their
-- character freezes where it fell, their half of the screen goes dark with a message, and
-- their partner revives them by standing next to them for a few seconds. If nobody comes,
-- they get back up next to the partner after a while. If both players go down, Player 1
-- dies for real and the game reloads the checkpoint as usual.
------------------------------------------------------------------------------------------
local down = {}    -- [slot] = { since, widget, text, reviveTime }
local armed = {}   -- [slot] = health ratio last tick
local hints = {}   -- [slot] = { widget, text } message on the partner's screen

local function stat(pawn, field)
    local stats = subObj(pawn, "m_pStatsComponent")
    return stats and subObj(stats, field)
end
local function ratioOf(st)
    if not st then return nil end
    local ok, r = pcall(function() return st:GetRatio() end)
    if ok and type(r) == "number" then return r end
    return nil
end
local function healthRatio(pawn) return ratioOf(stat(pawn, "m_pHealthStat")) end
-- Player 2's PK ability object, and "can PK pick this up?" asked the game's own way
-- (its PK-able part), so the yellow arcs only go on things PK will really take.
state.p2PKAbility = function()
    local now = os.clock()
    local c = state.p2PKCache
    if c and now - c.at < 2.0 and valid(c.ab) then return c.ab end
    local mental = subObj(getPawn(state.p2), "m_pMentalAbilityComponent")
    local found = nil
    if mental then
        for _, ab in ipairs(state.p2Abilities(mental)) do
            if valid(ab) and nameOf(ab):find("kinesis") then found = ab break end
        end
    end
    state.p2PKCache = { at = now, ab = found }
    return found
end
-- PK's reach, from the game's own PK ability (falls back to the setting)
state.p2PKRange = function()
    local ab = state.p2PKAbility()
    local r = nil
    if ab then pcall(function() r = tonumber(ab.m_fMaxRange) end) end
    if not r or r <= 0 then r = CFG.P2_PK_RANGE end
    if not state.pkRangeLogged then state.pkRangeLogged = true; log("P2 PK reach for the yellow arcs: %.0f cm", r) end
    return math.min(r, CFG.P2_PK_RANGE)
end
-- Where a person or body really is: the middle of its body (a body lying on the ground has
-- moved away from where its standing capsule was)
-- Test recorder: every quarter second, what each player is targeting (only kept when it
-- changes, last 12 s, in memory). A snapshot writes it to the log, so a split-second problem
-- is still caught a few seconds after it happened. Text only: cheap to read.
state.recBuf = {}
state.snapshot = function(why)
    state.snapN = (state.snapN or 0) + 1
    log("===== SNAPSHOT %d (%s): the last 12 seconds, oldest first =====", state.snapN, why or "?")
    local now = os.clock()
    for _, e in ipairs(state.recBuf) do log("  -%4.1fs  %s", now - e.t, e.s) end
    pcall(function()
        for _, w in ipairs(FindAllOf("UserWidget") or {}) do
            if valid(w) then
                local n = shortName(w)
                if n:find("Crosshair") and not n:find("^Default__") then
                    local okV, vis = pcall(function() return w:IsVisible() end)
                    local okO, own = pcall(function() return w:GetOwningPlayer() end)
                    local okP, op = pcall(function() return w:GetRenderOpacity() end)
                    local okI, inV = pcall(function() return w:IsInViewport() end)
                    if okV and vis and (not okP or op > 0.01) then
                        log("  crosshair %s: owner %s, opacity %.2f, on screen %s", n, (okO and valid(own)) and shortName(own) or "-",
                            okP and op or -1, tostring(okI and inV))
                    end
                end
            end
        end
    end)
    for _, f in ipairs({ "populationReport", "radarReport" }) do
        local okR, errR = pcall(function() state[f]() end)
        if not okR then log("  (%s failed: %s)", f, tostring(errR)) end
    end
    log("===== end of snapshot %d =====", state.snapN)
end
-- things the lock-ons must never pick: the players' saucer (its landing light), any player
state.notTargetable = function(a)
    local n = nameOf(a) or ""
    return n:find("PlayerUFO") ~= nil or n:find("BP_CharacterPlayer") ~= nil
end
-- The chest bone of a skeleton (found by name once per skeleton; it follows a ragdoll, so
-- the marks stay on a body lying on the ground)
state.boneCache = {}
state.bodyBoneOf = function(mesh)
    local okM, sk = pcall(function() return mesh.SkeletalMesh end)
    local key = (okM and valid(sk)) and nameOf(sk) or nil
    if not key then return nil end
    local hit = state.boneCache[key]
    if hit ~= nil then return hit or nil end
    local names = {}
    pcall(function()
        local n = mesh:GetNumBones()
        for i = 0, math.min(n - 1, 80) do
            local okB, b = pcall(function() return mesh:GetBoneName(i) end)
            if okB and b then names[#names + 1] = { n = b:ToString(), f = b } end
        end
    end)
    local pick = nil
    for _, want in ipairs({ "spine_03", "spine_02", "spine2", "spine_01", "spine1", "spine", "pelvis", "hips", "hip" }) do
        for _, e in ipairs(names) do
            if e.n:lower() == want then pick = e.f break end
        end
        if pick then break end
    end
    if not pick then
        for _, e in ipairs(names) do if e.n:lower():find("spine") then pick = e.f break end end
    end
    state.boneCache[key] = pick or false
    if (state.boneLogs or 0) < 8 then
        state.boneLogs = (state.boneLogs or 0) + 1
        log("Lock-on point for %s: %s (of %d bones)", shortName(sk), pick and pick:ToString() or "none, using the middle", #names)
    end
    return pick
end
state.targetPoint = function(c)
    -- (a missing bone gives back the mesh's origin, the feet: that's why Player 2's lock-ons
    -- sat low. Only use a bone the mesh really has.)
    local mesh = subObj(c, "Mesh")
    if mesh then
        local bone = state.bodyBoneOf(mesh)
        if bone then
            local ok, p = pcall(function() return mesh:GetSocketLocation(bone) end)
            if ok and p and type(p.X) == "number" then return { X = p.X, Y = p.Y, Z = p.Z } end
        end
    end
    -- the middle of its bounds (people: about the chest; cars and props: their middle)
    local okB = pcall(function()
        local o, e = {}, {}
        c:GetActorBounds(true, o, e)
        if type(o.X) == "number" and type(e.Z) == "number" and e.Z > 0 then
            state.tpOut = { X = o.X, Y = o.Y, Z = o.Z + e.Z * 0.2 }
        else
            state.tpOut = nil
        end
    end)
    if okB and state.tpOut then local r = state.tpOut; state.tpOut = nil; return r end
    local ok, l = pcall(function() return c:K2_GetActorLocation() end)
    return ok and l or nil
end
-- How far above the middle of Player 2's view the crosshair sits, as an angle (degrees)
state.p2CrosshairPitch = function()
    local cm = state.p2 and state.p2.PlayerCameraManager
    if not cm then return 0 end
    local fov = 90
    pcall(function() local f = cm:GetFOVAngle(); if type(f) == "number" and f > 10 then fov = f end end)
    local aspect = CFG.P2_VIEW_ASPECT_H
    return math.deg(math.atan(-CFG.P2_CROSSHAIR_RAISE * aspect * math.tan(math.rad(fov) / 2)))
end
state.p2PKAble = function(actor)
    if not CFG.P2_YELLOW_ONLY_PKABLE then return true end
    local ab = state.p2PKAbility()
    if not ab then return true end
    local ok, comp = pcall(function() return ab:GetPKAbleComponentFromActor(actor) end)
    if not ok then
        if not state.pkAbleWarned then state.pkAbleWarned = true; log("P2 yellow arcs: can't ask PK about targets (%s); showing them anyway", tostring(comp)) end
        return true
    end
    return valid(comp)
end
-- The game's own HUD font: copied from one of the HUD's text pieces, so the mod's menus
-- and labels look like the game's.
state.gameFontInfo = function()
    if state.gameFontCache and valid(state.gameFontCache.obj) then return state.gameFontCache end
    local found = nil
    pcall(function()
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            if valid(t) then
                local okP, path = pcall(function() return t:GetFullName() end)
                if okP and path and path:find("BPW_HUD") then
                    local okF, fo = pcall(function() return t.Font.FontObject end)
                    if okF and valid(fo) then
                        local okT, tf = pcall(function() return t.Font.TypefaceFontName end)
                        found = { obj = fo, face = okT and tf or nil, from = shortName(t) }
                        break
                    end
                end
            end
        end
    end)
    if found then
        state.gameFontCache = found
        log("Menus use the game's font %s (from %s)", shortName(found.obj), found.from)
    end
    return found
end
state.applyGameFont = function(t, size)
    local gf = state.gameFontInfo()
    if not gf then return false end
    local ok = pcall(function()
        local f = t.Font
        f.FontObject = gf.obj
        if gf.face then f.TypefaceFontName = gf.face end
        f.Size = size
        t:SetFont(f)
    end)
    return ok
end
-- Player 2's aim component (BFGActorComponent_TargetSystem)
state.p2TargetComponent = function()
    local pawn = getPawn(state.p2)
    if not valid(pawn) then return nil end
    local tc = subObj(pawn, "TargetComponent") or subObj(pawn, "m_pTargetComponent") or subObj(pawn, "m_pTargetSystemComponent")
    if tc then return tc end
    pcall(function()
        local eq = subObj(pawn, "m_pEquipmentManagerComponent")
        local w = eq:GetCurrentWeapon()
        if not valid(w) then w = arrayToList(eq:GetCurrentWeapons())[1] end
        local t = valid(w) and w.m_pOwnerTargetComponent
        if valid(t) then tc = t end
    end)
    if tc then return tc end
    pcall(function()
        local c = pawn:GetComponentByClass(StaticFindObject("/Script/BFGCore.BFGActorComponent_TargetSystem"))
        if valid(c) then tc = c end
    end)
    return tc
end
-- Does the pad router DLL understand aim-point overrides? (it says so in its log)
state.dllAimOverride = function()
    if state.dllAimOv ~= nil then return state.dllAimOv end
    state.dllAimOv = false
    for _, f in ipairs({ "DAHPadRouter_XINPUT1_3.log", "DAHPadRouter_XINPUT1_4.log", "DAHPadRouter_XINPUT9_1_0.log" }) do
        local h = io.open(f, "r")
        if h then
            local txt = h:read("*a") or ""
            h:close()
            if txt:find("Aim override channel: ready", 1, true) then state.dllAimOv = true break end
        end
    end
    log("Pad router aim override: %s", state.dllAimOv and "available" or "not in this DLL build (PK reach off)")
    return state.dllAimOv
end
-- Player 2's mind abilities (PK, hypnosis...).
state.p2Abilities = function(mental)
    local l = {}
    pcall(function() l = arrayToList(mental:GetAllAbilities()) end)
    if #l == 0 then pcall(function() l = arrayToList(mental.m_aPlayerMentalAbilities) end) end
    return l or {}
end
-- Is this person/animal dead (or a body lying around)?
state.deadChar = function(c)
    local r = healthRatio(c)
    if type(r) == "number" and r <= 0.001 then return true end
    local okC, ctl = pcall(function() return c:GetController() end)
    if okC and valid(ctl) then
        local okD, d = pcall(function() return ctl.m_bIsPawnDead end)
        if okD and d == true then return true end
    end
    return false
end
local function shieldRatio(pawn) return ratioOf(stat(pawn, "m_pShieldStat")) end
-- (the game's stat setters take 4 parameters: value, broadcast, register change, force init)
local function setRatio(st, r)
    if not st then return end
    if not pcall(function() st:SetRatio(r, true, true, false) end) then pcall(function() st:SetRatio(r) end) end
end

local function ctrlOf(slot) return slot == 1 and player1Controller() or state.p2 end

local function distance(a, b)
    local ok, d = pcall(function()
        local la, lb = a:K2_GetActorLocation(), b:K2_GetActorLocation()
        local dx, dy, dz = la.X - lb.X, la.Y - lb.Y, la.Z - lb.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return ok and d or math.huge
end

-- A panel with a message on one player's half of the screen only.
local function overlayFor(pc, opacity, valign)
    local world = getWorld()
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, w in ipairs(hudWidgetsOf(pc)) do
        local note = subObj(w, "BPW_HUD_TextNotification")
        if note then template = note break end
    end
    if not (world and valid(wbl) and template) then return nil end
    local okC, cls = pcall(function() return template:GetClass() end)
    if not okC then return nil end
    local okW, w = pcall(function() return wbl:Create(world, cls, pc) end)
    if not (okW and valid(w)) then return nil end
    local tree = subObj(w, "WidgetTree")
    if not tree then return nil end
    local border = StaticConstructObject(StaticFindObject("/Script/UMG.Border"), tree, FName("DAH2P_Panel"))
    local text = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, FName("DAH2P_Text"))
    if not (valid(border) and valid(text)) then return nil end
    pcall(function() border:SetBrushColor({ R = 0, G = 0, B = 0, A = opacity }) end)
    pcall(function() border:SetHorizontalAlignment(2) end)       -- centre
    pcall(function() border:SetVerticalAlignment(valign) end)    -- 1 top, 2 centre
    pcall(function() border:SetPadding({ Left = 20, Top = 60, Right = 20, Bottom = 20 }) end)
    pcall(function() text:SetJustification(1) end)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }) end)
    pcall(function() text:SetShadowOffset({ X = 2, Y = 2 }) end)
    pcall(function() border:SetContent(text) end)
    pcall(function() tree.RootWidget = border end)
    pcall(function() w:SetVisibility(4) end)                     -- HitTestInvisible: never blocks input
    pcall(function() w:AddToPlayerScreen(100) end)
    return w, text
end
local function setText(entry, msg)
    if not entry then return end
    if entry.text and valid(entry.text) then pcall(function() entry.text:SetText(FText(msg)) end) end
    if entry.widget and valid(entry.widget) then
        -- The widget we borrow can hide itself; keep it shown.
        pcall(function() entry.widget:SetVisibility(4) end)
        pcall(function() entry.widget:SetRenderOpacity(1.0) end)
    end
end
local function removeWidget(entry)
    if entry and entry.widget and valid(entry.widget) then pcall(function() entry.widget:RemoveFromParent() end) end
end

-- Downed: the character stays standing where it is (collision and gravity untouched),
-- it just can't be controlled.
local function setFrozen(pawn, pc, frozen)
    pcall(function() pawn.bCanBeDamaged = not frozen end)
    local move = subObj(pawn, "CharacterMovement")
    if frozen then
        pcall(function() pawn:DisableInput(pc) end)
        if move then pcall(function() move:StopMovementImmediately() end) end
    else
        pcall(function() pawn:EnableInput(pc) end)
    end
end

-- Fill a stat: try the ways the game's stat object offers, check that it worked.
local function fillStat(st, r)
    if not st then return end
    if not pcall(function() st:SetRatio(r, true, true, false) end) then pcall(function() st:SetRatio(r) end) end
    local now = ratioOf(st)
    if now and math.abs(now - r) < 0.01 then return end
    local okM, mx = pcall(function() return st.m_fMaxValue end)
    if okM and type(mx) == "number" and mx > 0 then
        if not pcall(function() st:SetValue(mx * r, true, true, false) end) then pcall(function() st:SetValue(mx * r) end) end
    end
    now = ratioOf(st)
    if now and math.abs(now - r) < 0.01 then return end
    if r >= 1 then pcall(function() st:AddValue(1000000) end) end
    now = ratioOf(st)
    if now and math.abs(now - r) < 0.01 then return end
    -- last resort: write the stored value directly (max worked out from value / ratio)
    local okV, v = pcall(function() return st:GetValue() end)
    local cur = ratioOf(st)
    if okV and type(v) == "number" and cur and cur > 0 then
        local maxV = v / cur
        pcall(function() st.m_fValue = maxV * r end)
        pcall(function() st.m_fLastValue = maxV * r end)
    end
end

-- Make enemies ignore a downed player (and point "the main player" at the partner).
local function setTargetable(pawn, on)
    -- The game's own "invisible" state (enemies don't see invisible players).
    local inv = stat(pawn, "m_pIsInvisibleStat")
    if inv then
        pcall(function() inv:SetValue(not on) end)
        pcall(function() inv.m_bValue = not on end)
        if not on then
            local okV, v = pcall(function() return inv:GetValue() end)
            log("Downed system: invisible to enemies = %s", okV and tostring(v) or "?")
        end
    end
    local ai = subObj(pawn, "m_pAITargetComponent")
    if ai then
        if on then pcall(function() ai:Activate(true) end) else pcall(function() ai:Deactivate() end) end
    end
    local gs = FindFirstOf("GameStateBase")
    if valid(gs) and not on then
        local partner = samePawn(pawn, getPawn(player1Controller())) and getPawn(state.p2) or getPawn(player1Controller())
        if valid(partner) then pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = partner end) end
    elseif valid(gs) and on then
        local p1pawn = getPawn(player1Controller())
        if valid(p1pawn) then pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = p1pawn end) end
    end
end

-- Players in the game, by slot (1 and 2, plus 3 and 4 when they've joined)
state.dsSlots = function()
    local r = { 1 }
    if valid(state.p2) then r[#r + 1] = 2 end
    for slot = 3, 4 do
        local pc = state.extraPlayers and state.extraPlayers[slot]
        if valid(pc) then r[#r + 1] = slot end
    end
    return r
end
state.dsCtrl = function(slot)
    if slot <= 2 then return ctrlOf(slot) end
    return state.extraPlayers and state.extraPlayers[slot] or nil
end
-- put a body next to another (used when nobody revives you in time)
state.dsMoveNextTo = function(pawn, to, side)
    pcall(function()
        local l = to:K2_GetActorLocation()
        local r = to:K2_GetActorRotation()
        local yaw = math.rad(r.Yaw)
        local sd = side or 200
        pawn:K2_SetActorLocation({ X = l.X - math.sin(yaw) * sd - math.cos(yaw) * 120, Y = l.Y + math.cos(yaw) * sd - math.sin(yaw) * 120, Z = l.Z + 40 }, false, {}, true)
    end)
end
-- lying on the ground while down (ragdoll), and standing again
state.dsRagdoll = function(pawn, on, entry)
    if CFG.DOWNED_RAGDOLL == false then return end
    local mesh = subObj(pawn, "Mesh")
    if not mesh then return end
    if on then
        pcall(function()
            local rl, rr = mesh.RelativeLocation, mesh.RelativeRotation
            entry.meshLoc = { X = rl.X, Y = rl.Y, Z = rl.Z }
            entry.meshRot = { Pitch = rr.Pitch, Yaw = rr.Yaw, Roll = rr.Roll }
        end)
        pcall(function() mesh:SetCollisionProfileName(FName("Ragdoll"), true) end)
        pcall(function() mesh:SetAllBodiesSimulatePhysics(true) end)
        pcall(function() mesh:SetSimulatePhysics(true) end)
        entry.ragdoll = true
    elseif entry and entry.ragdoll then
        entry.ragdoll = false
        pcall(function() mesh:SetSimulatePhysics(false) end)
        pcall(function() mesh:SetAllBodiesSimulatePhysics(false) end)
        pcall(function() mesh:SetCollisionProfileName(FName("CharacterMesh"), true) end)
        pcall(function() mesh:K2_AttachToComponent(pawn.CapsuleComponent, FName("None"), 0, 0, 0, false) end)
        if entry.meshLoc then
            pcall(function() mesh:K2_SetRelativeLocationAndRotation(entry.meshLoc, entry.meshRot, false, {}, true) end)
        end
    end
end
-- the nearest player who is still standing
state.dsBuddy = function(slot, pawns)
    local best, bd = nil, math.huge
    for _, o in ipairs(state.dsSlots()) do
        if o ~= slot and not down[o] and valid(pawns[o]) then
            local d = distance(pawns[o], pawns[slot])
            if d < bd then best, bd = o, d end
        end
    end
    return best, bd
end

local function goDown(slot)
    local pc = state.dsCtrl(slot)
    local pawn = getPawn(pc)
    if not valid(pawn) then return end
    local entry = { since = os.clock(), reviveTime = 0 }
    down[slot] = entry
    armed[slot] = nil
    log("Downed system: Player %d is down", slot)
    if state.trainerOnDown and valid(state.p2) then
        -- a player went down in co-op: close the menu, saucers / saucer weapons off (they crashed
        -- on respawn); everything else (size, god mode...) stays as chosen
        pcall(state.trainerOnDown)
    end
    setFrozen(pawn, pc, true)
    if slot == 1 then state.p1Down = true end
    setTargetable(pawn, false)
    pcall(state.dsRagdoll, pawn, true, entry)
    local okO, w, text = pcall(overlayFor, pc, CFG.DOWNED_BLACKOUT, 2)
    if okO and w then entry.widget, entry.text = w, text
    else log("Downed system: message panel not available") end
end

local function getUp(slot, revived)
    local entry = down[slot]
    down[slot] = nil
    removeWidget(entry)
    removeWidget(hints[slot]); hints[slot] = nil
    local pc = state.dsCtrl(slot)
    local pawn = getPawn(pc)
    if not valid(pawn) then return end
    pcall(state.dsRagdoll, pawn, false, entry)
    if not revived then
        local pawns = {}
        for _, o in ipairs(state.dsSlots()) do pawns[o] = getPawn(state.dsCtrl(o)) end
        local buddy = state.dsBuddy(slot, pawns)
        if buddy then state.dsMoveNextTo(pawn, pawns[buddy], (slot % 2 == 0) and 200 or -200) end
    end
    setFrozen(pawn, pc, false)
    if slot == 1 then state.p1Down = false end
    fillStat(stat(pawn, "m_pHealthStat"), 1.0)
    fillStat(stat(pawn, "m_pShieldStat"), CFG.RESPAWN_SHIELD)
    setTargetable(pawn, true)
    state.downProtect = state.downProtect or {}
    state.downProtect[slot] = os.clock() + CFG.DOWNED_GRACE_SECONDS   -- safety after getting up
    log("Downed system: Player %d is back (%s)", slot, revived and "revived" or "timer")
end

local function gameOver()
    log("Downed system: everyone is down -> normal game over")
    state.gameOverUntil = os.clock() + 15   -- let the game's own death / reload happen
    for _, slot in ipairs(state.dsSlots()) do
        removeWidget(down[slot]); removeWidget(hints[slot]); hints[slot] = nil
        local pc = state.dsCtrl(slot)
        local pawn = getPawn(pc)
        if valid(pawn) then
            pcall(state.dsRagdoll, pawn, false, down[slot])
            setFrozen(pawn, pc, false)
        end
    end
    down, armed = {}, {}
    local p1Pawn = getPawn(player1Controller())
    pcall(function() p1Pawn.bCanBeDamaged = true end)
    setRatio(stat(p1Pawn, "m_pShieldStat"), 0)
    setRatio(stat(p1Pawn, "m_pHealthStat"), 0)
    -- after the game's own reload: everyone fresh, at the saucer (where Player 1 respawns)
    for _, delay in ipairs({ 6.0, 10.0 }) do
        later(delay, "afterGameOver", function()
            local p1p = getPawn(player1Controller())
            for _, slot in ipairs(state.dsSlots()) do
                removeWidget(down[slot]); removeWidget(hints[slot]); hints[slot] = nil
                local pc = state.dsCtrl(slot)
                local pawn = getPawn(pc)
                if valid(pawn) then
                    setFrozen(pawn, pc, false)
                    fillStat(stat(pawn, "m_pHealthStat"), 1.0)
                    fillStat(stat(pawn, "m_pShieldStat"), 1.0)
                    setTargetable(pawn, true)
                    if slot >= 3 and valid(p1p) then state.dsMoveNextTo(pawn, p1p, slot == 3 and -250 or 250) end
                end
            end
            down, armed = {}, {}
            if valid(state.p2) then pcall(teleportP2ToP1) end
            state.downProtect = { [1] = os.clock() + 5, [2] = os.clock() + 5, [3] = os.clock() + 5, [4] = os.clock() + 5 }
            log("Downed system: after game over everyone is back at full health")
        end)
    end
end

local function downedTick()
    if not CFG.DOWNED_SYSTEM then return end
    if state.gameOverUntil and os.clock() < state.gameOverUntil then return end
    local slots = state.dsSlots()
    local pawns = {}
    for _, slot in ipairs(slots) do pawns[slot] = getPawn(state.dsCtrl(slot)) end
    local isChar = function(p) return valid(p) and subObj(p, "m_pStatsComponent") ~= nil and subObj(p, "CharacterMovement") ~= nil end
    local allChars = #slots >= 2
    for _, slot in ipairs(slots) do if not isChar(pawns[slot]) then allChars = false end end
    if not allChars then
        for slot = 1, 4 do if down[slot] then getUp(slot, false) end end
        armed = {}
        return
    end
    local now = os.clock()
    local g = state.trGod
    for _, slot in ipairs(slots) do
        local pawn = pawns[slot]
        local entry = down[slot]
        -- god mode: this player can't be downed at all (it used to end in a game over)
        local godOn = g == "On" or g == "Both players" or g == "All players"
            or (slot == 1 and g == "Player 1 only") or (slot == 2 and g == "Player 2 only")
        if godOn and not entry then
            fillStat(stat(pawn, "m_pShieldStat"), 1.0)
            fillStat(stat(pawn, "m_pHealthStat"), 1.0)
            armed[slot] = 1.0
        elseif not entry then
            local protected = state.downProtect and state.downProtect[slot] and now < state.downProtect[slot]
            local sh, hp = shieldRatio(pawn), healthRatio(pawn)
            if protected then
                -- grace period: shield stays where it was set on getting up
                local cur = shieldRatio(pawn)
                if cur and cur < CFG.RESPAWN_SHIELD then fillStat(stat(pawn, "m_pShieldStat"), CFG.RESPAWN_SHIELD) end
                fillStat(stat(pawn, "m_pHealthStat"), 1.0)
            elseif sh and hp then
                -- Down as soon as the shield is (nearly) gone, before health is touched,
                -- so the game itself never sees a death.
                local lostHealth = armed[slot] and hp < armed[slot] - 0.001
                if sh <= CFG.DOWNED_AT_SHIELD or lostHealth then goDown(slot) end
            end
            if hp and not down[slot] then armed[slot] = hp end   -- health last tick (any loss = down)
        else
            -- While down: can't be hurt.
            fillStat(stat(pawn, "m_pShieldStat"), 1.0)
            fillStat(stat(pawn, "m_pHealthStat"), 1.0)
        end
    end
    -- game over only when every player is down
    local standing = 0
    for _, slot in ipairs(slots) do if not down[slot] then standing = standing + 1 end end
    if standing == 0 then gameOver() return end
    for _, slot in ipairs(slots) do
        local entry = down[slot]
        if entry and entry.since ~= now then
            local buddy, bd = state.dsBuddy(slot, pawns)
            local near = buddy and bd <= CFG.REVIVE_RADIUS
            if near then entry.reviveTime = entry.reviveTime + (now - (entry.last or now)) else entry.reviveTime = 0 end
            entry.last = now
            -- the helper message goes on the nearest standing player's screen
            if buddy and (not hints[slot] or hints[slot].on ~= buddy) then
                removeWidget(hints[slot]); hints[slot] = nil
                local okH, hw, ht = pcall(overlayFor, state.dsCtrl(buddy), 0, 1)
                if okH and hw then hints[slot] = { widget = hw, text = ht, on = buddy } end
            end
            local waited = now - entry.since
            if entry.reviveTime >= CFG.REVIVE_SECONDS then
                getUp(slot, true)
            elseif waited >= CFG.RESPAWN_MAX_SECONDS then
                getUp(slot, false)
            else
                setText(entry, string.format(
                    "YOU ARE DOWN\n\nAnother player can revive you by standing next to you for %d seconds%s.\n" ..
                    "Otherwise you'll get back up next to them in %d s.\n\nIf everyone goes down, the game reloads the checkpoint.",
                    CFG.REVIVE_SECONDS,
                    near and string.format(" (reviving... %.1f s)", math.max(0, CFG.REVIVE_SECONDS - entry.reviveTime)) or "",
                    math.max(0, math.ceil(CFG.RESPAWN_MAX_SECONDS - waited))))
                setText(hints[slot], near
                    and string.format("Reviving Player %d... %.1f s", slot, math.max(0, CFG.REVIVE_SECONDS - entry.reviveTime))
                    or string.format("Player %d is down! Stand next to them for %d s to revive them.", slot, CFG.REVIVE_SECONDS))
            end
        end
    end
end
addTickJob("downed", 0, downedTick)
------------------------------------------------------------------------------------------
-- Per-player health/shield bars. The game's own health display reads one player only, so
-- in split screen each player gets two slim upright bars (shield, health) along the split
-- line of their own half, and the game's shared display is hidden.
------------------------------------------------------------------------------------------
local bars = {}   -- [slot] = { widget, shield (ProgressBar) or mid (hex material), param }

-- The game's own hexagon shield material, and the name of its "how full" parameter.
local hexInfo = nil
onWorldChange(function() bars = {}; hexInfo = nil; down = {}; armed = {}; hints = {} end)
local function findHexMaterial(pc)
    if hexInfo ~= nil then return hexInfo end
    for _, hud in ipairs(hudWidgetsOf(pc)) do
        local st = subObj(hud, "BPW_UI_HUDPlayerStats")
        local parent = st and (subObj(st, "MaterialShieldNew") or subObj(st, "MatInstance_Shield"))
        local live = st and subObj(st, "MatInstance_Shield")
        if parent then
            local names, pick = {}, nil
            local okA, arr = pcall(function() return live and live.ScalarParameterValues end)
            for _, e in ipairs(okA and arrayToList(arr) or {}) do
                local okN, n = pcall(function() return e.ParameterInfo.Name:ToString() end)
                local okV, v = pcall(function() return e.ParameterValue end)
                if okN and n then
                    names[#names + 1] = string.format("%s=%s", tostring(n), okV and tostring(v) or "?")
                    local l = tostring(n):lower()
                    if not pick and (l:find("percent") or l:find("fill") or l:find("ratio") or l:find("progress")
                        or l:find("current") or l:find("value") or l:find("amount")) and not l:find("max")
                        and not l:find("delta") then pick = tostring(n) end
                end
            end
            -- the game's own name for it (seen in earlier sessions), when the live copy can't be read
            if not pick then pick = "Percent" end
            log("Player bars: hexagon shield material %s, parameters: %s -> using '%s'", shortName(parent),
                #names > 0 and table.concat(names, ", ") or "none found", tostring(pick))
            hexInfo = pick and { parent = parent, live = live, param = pick } or false
            return hexInfo
        end
    end
    hexInfo = false
    return hexInfo
end

local function makeBars(pc, slot)
    local world = getWorld()
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, w in ipairs(hudWidgetsOf(pc)) do
        local note = subObj(w, "BPW_HUD_TextNotification")
        if note then template = note break end
    end
    if not (world and valid(wbl) and template) then return nil end
    local w = wbl:Create(world, template:GetClass(), pc)
    local tree = subObj(w, "WidgetTree")
    if not tree then return nil end
    local function make(className, name)
        return StaticConstructObject(StaticFindObject("/Script/UMG." .. className), tree, FName(name))
    end
    local root = make("Border", "DAH2P_BarsRoot")
    local size = make("SizeBox", "DAH2P_BarsSize")
    if not (valid(root) and valid(size)) then return nil end
    pcall(function() root:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
    local vertical = state.splitVertical
    -- Left/right split: an upright bar by the split line. Top/bottom: a flat bar by the split.
    pcall(function() root:SetHorizontalAlignment(vertical and (slot == 1 and 3 or 1) or 2) end)
    pcall(function() root:SetVerticalAlignment(vertical and 2 or (slot == 1 and 3 or 1)) end)
    pcall(function() root:SetPadding({ Left = 10, Top = 10, Right = 10, Bottom = 10 }) end)
    -- The bar is laid out flat (length x thickness) and turned upright for left/right.
    pcall(function() size:SetWidthOverride(CFG.BAR_LENGTH) end)
    pcall(function() size:SetHeightOverride(CFG.BAR_WIDTH) end)
    local entry = { widget = w, vertical = vertical }
    local hex = CFG.HEX_SHIELD and findHexMaterial(pc)
    local content = nil
    if hex then
        local mlib = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local okM, mid = pcall(function() return mlib:CreateDynamicMaterialInstance(world, hex.parent, FName("None")) end)
        local img = make("Image", "DAH2P_ShieldHex")
        if okM and valid(mid) and valid(img) then
            -- copy the game's current settings (segment count etc.), then we drive the fill
            local okA, arr = pcall(function() return hex.live and hex.live.ScalarParameterValues end)
            for _, e in ipairs(okA and arrayToList(arr) or {}) do
                pcall(function() mid:SetScalarParameterValue(e.ParameterInfo.Name, e.ParameterValue) end)
            end
            pcall(function() img:SetBrushFromMaterial(mid) end)
            entry.mid, entry.param = mid, FName(hex.param)
            content = img
        end
    end
    if not content then
        local pb = make("ProgressBar", "DAH2P_Shield")
        if not valid(pb) then return nil end
        pcall(function() pb:SetFillColorAndOpacity({ R = 0.2, G = 0.6, B = 1.0, A = 1 }) end)
        pcall(function() pb:SetPercent(1.0) end)
        entry.shield = pb
        content = pb
    end
    pcall(function() size:SetContent(content) end)
    pcall(function() tree.RootWidget = size end)
    pcall(function() w:AddToPlayerScreen(90) end)
    pcall(function() w:SetDesiredSizeInViewport({ X = CFG.BAR_LENGTH, Y = CFG.BAR_WIDTH }) end)
    pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
    entry.slot = slot
    entry.size = size
    return entry
end

local function setSharedHealthVisible(visible)
    for _, pc in ipairs({ player1Controller(), state.p2 }) do
        if valid(pc) then
            for _, hud in ipairs(hudWidgetsOf(pc)) do
                local stats = subObj(hud, "BPW_UI_HUDPlayerStats")
                if stats then pcall(function() stats:SetVisibility(visible and 4 or 1) end) end
            end
        end
    end
end

local function removeBars()
    for slot = 1, 2 do
        local b = bars[slot]
        if b and valid(b.widget) then pcall(function() b.widget:RemoveFromParent() end) end
    end
    bars = {}
end

local barsLogged = false
local function barsTick()
    local p1 = player1Controller()
    if not (CFG.PLAYER_BARS and valid(state.p2) and valid(p1)) or state.barPlace == "Game's own only" then
        if next(bars) then removeBars(); setSharedHealthVisible(true) end
        return
    end
    for slot, pc in ipairs({ p1, state.p2 }) do
        local b = bars[slot]
        if b and (not valid(b.widget) or b.vertical ~= state.splitVertical) then
            pcall(function() b.widget:RemoveFromParent() end)
            b = nil
        end
        if not b then
            local ok, made = pcall(makeBars, pc, slot)
            b = ok and made or nil
            bars[slot] = b
            if not barsLogged then
                barsLogged = true
                log("Player bars: %s", b and "on" or ("not available: " .. tostring(made)))
            end
        end
        if b then
            local pawn = getPawn(pc)
            local sh = shieldRatio(pawn)
            if sh then
                -- the white part shows shield just lost; let it catch up instead of staying
                b.prev = b.prev or sh
                if sh >= b.prev then b.prev = sh else b.prev = math.max(sh, b.prev - CFG.BAR_DRAIN_PER_TICK) end
                if b.mid then
                    pcall(function() b.mid:SetScalarParameterValue(FName("PercentPrevious"), b.prev) end)
                    pcall(function() b.mid:SetScalarParameterValue(FName("PercentPreviousGlow"), b.prev) end)
                end
                if b.mid then pcall(function() b.mid:SetScalarParameterValue(b.param, sh) end)
                elseif b.shield then pcall(function() b.shield:SetPercent(sh) end) end
            end
            pcall(function() b.widget:SetVisibility(4) end)
            -- Upright for left/right (turned every frame: the borrowed widget resets its own transform)
            if b.size then
                local ang = state.splitVertical and -90 or 0
                -- UE 4.22 calls it SetRenderAngle (later versions: SetRenderTransformAngle)
                local okA = pcall(function() b.size:SetRenderAngle(ang) end)
                if not okA then okA = pcall(function() b.size:SetRenderTransformAngle(ang) end) end
                if not okA then
                    pcall(function() b.size:SetRenderTransform({ Translation = { X = 0, Y = 0 }, Scale = { X = 1, Y = 1 },
                        Shear = { X = 0, Y = 0 }, Angle = ang }) end)
                end
            end
            -- Place it against the split line, in this player's own half (pixels).
            local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            local okS, vs = pcall(function() return lib:GetViewportSize(getWorld()) end)
            local okC, sc = pcall(function() return lib:GetViewportScale(getWorld()) end)
            local W, H = nil, nil
            if okS then W, H = readXY(vs) end
            sc = (okC and type(sc) == "number" and sc > 0) and sc or 1
            if type(W) == "number" then
                local half = (CFG.BAR_WIDTH * sc) / 2 + CFG.BAR_MARGIN
                local x, y
                local edge = state.barPlace == "Outer edges"
                if state.splitVertical then
                    if edge then x = (slot == 1) and half or (W / 2 - half) else x = (slot == 1) and (W / 2 - half) or half end
                    y = H / 2
                else
                    x = W / 2
                    if edge then y = (slot == 1) and half or (H / 2 - half) else y = (slot == 1) and (H / 2 - half) or half end
                end
                pcall(function() b.widget:SetPositionInViewport({ X = x, Y = y }, true) end)
            end
        end
    end
    if CFG.HIDE_SHARED_HEALTH then setSharedHealthVisible(false) end
end
addTickJob("playerBars", 0.1, barsTick)

-- Each HUD's own shield bar (the game's hexagons, in their usual spot) shows ITS player's
-- shield: the game feeds both from Player 1, so we set it ourselves every frame.
local hudShieldParams = { FName("Percent"), FName("PercentPrevious"), FName("PercentPreviousGlow") }
local function hudShieldTick()
    if not (CFG.OWN_HUD_SHIELD and valid(state.p2)) then return end
    for _, pc in ipairs({ player1Controller(), state.p2 }) do
        local sh = valid(pc) and shieldRatio(getPawn(pc))
        if sh then
            for _, hud in ipairs(hudWidgetsOf(pc)) do
                local stats = subObj(hud, "BPW_UI_HUDPlayerStats")
                local mid = stats and subObj(stats, "MatInstance_Shield")
                if mid then
                    for _, n in ipairs(hudShieldParams) do pcall(function() mid:SetScalarParameterValue(n, sh) end) end
                end
            end
        end
    end
end
addTickJob("hudShield", 0, hudShieldTick)

do
-- The game's shield widget refills itself from Player 1 every frame in its own Tick, so we
-- also set each widget's value right AFTER that Tick (a post-hook), for its own player.
local shieldHooked = false
local function hookShieldWidget()
    if shieldHooked then return end
    local ok, err = pcall(function()
        RegisterHook("/Game/Blueprints/UI/HUD/BPW_UI_HUDPlayerStats.BPW_UI_HUDPlayerStats_C:Tick", function() end,
            function(Context)
                if not (CFG.OWN_HUD_SHIELD and valid(state.p2)) then return end
                pcall(function()
                    local w = Context:get()
                    local owner = w:GetOwningPlayer()
                    local sh = shieldRatio(getPawn(owner))
                    local mid = subObj(w, "MatInstance_Shield")
                    if sh and mid then
                        for _, n in ipairs(hudShieldParams) do mid:SetScalarParameterValue(n, sh) end
                    end
                end)
            end)
    end)
    shieldHooked = ok
    log("Own shield bar per player: %s", ok and "on" or ("not available: " .. tostring(err)))
end
state.hookShieldWidget = hookShieldWidget

------------------------------------------------------------------------------------------
-- Player 2's yellow lock-on marker. The game draws its yellow marker for Player 1 only, so
-- Player 2 gets a yellow diamond over whatever their abilities are aimed at.
------------------------------------------------------------------------------------------
local marker = nil   -- { widget }
onWorldChange(function() marker = nil end); state.onP2Leave(function() if marker then pcall(function() marker.widget:RemoveFromParent() end) end; marker = nil end)
local markerLogged = false
local function makeMarker(pc)
    local world = getWorld()
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local template = nil
    for _, w in ipairs(hudWidgetsOf(pc)) do
        local note = subObj(w, "BPW_HUD_TextNotification")
        if note then template = note break end
    end
    if not (world and valid(wbl) and template) then return nil end
    -- Best: the lock-on bracket the game draws around Player 1's target (from Player 1's HUD).
    if CFG.MARKER_USE_GAME_WIDGET then
        local p1c = player1Controller()
        for _, hud in ipairs(hudWidgetsOf(p1c)) do
            local hl = subObj(hud, "BPW_UI_HUD_SceneObjectHighlighter")
            local okA, arr = pcall(function() return hl and hl.m_apHighlighters end)
            local list = okA and arrayToList(arr) or {}
            local names = {}
            local pick = nil
            for _, h in ipairs(list) do
                if valid(h) then
                    local cn = classNameOf(h):match("([^%.]+)$") or "?"
                    names[#names + 1] = cn
                    local okV, vis = pcall(function() return h:IsVisible() end)
                    if not pick or (okV and vis) then pick = h end
                end
            end
            if not markerLogged then log("Player 2 lock-on marker: Player 1's highlighters: %s", #names > 0 and table.concat(names, ", ") or "none") end
            if pick then
                local okC, cls = pcall(function() return pick:GetClass() end)
                local okW, gw = pcall(function() return wbl:Create(world, cls, pc) end)
                if okC and okW and valid(gw) then
                    pcall(function() gw:AddToPlayerScreen(80) end)
                    pcall(function() gw:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
                    log("Player 2 lock-on marker: using the game's lock-on %s", shortName(cls))
                    return { widget = gw, game = true, bracket = true }
                end
            end
        end
    end
    -- Next: the game's overhead marker.
    if CFG.MARKER_USE_GAME_WIDGET then
        local gs = FindFirstOf("GameStateBase")
        local okM, mgr = pcall(function() return gs:GetHighlightableSceneObjectManager() end)
        for _, f in ipairs({ "m_pFocusedOpportunityWidget_Mental", "m_pFocusedOpportunityWidget_Weapon" }) do
            local comp = okM and valid(mgr) and subObj(mgr, f)
            local okU, inner = pcall(function() return comp and comp:GetUserWidgetObject() end)
            local okWC, wcls = pcall(function() return comp and comp.WidgetClass end)
            if (okU and valid(inner)) or (okWC and valid(wcls)) then
                local okC, cls = true, wcls
                if not (okWC and valid(wcls)) then okC, cls = pcall(function() return inner:GetClass() end) end
                local okW, gw = pcall(function() return wbl:Create(world, cls, pc) end)
                if okC and okW and valid(gw) then
                    pcall(function() gw:AddToPlayerScreen(80) end)
                    pcall(function() gw:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
                    log("Player 2 lock-on marker: using the game's %s", shortName(cls))
                    return { widget = gw, game = true }
                end
            end
        end
        if not markerLogged then log("Player 2 lock-on marker: the game's marker widget isn't available yet, using a diamond for now") end
    end
    local w = wbl:Create(world, template:GetClass(), pc)
    local tree = subObj(w, "WidgetTree")
    if not tree then return nil end
    local size = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName("DAH2P_MarkSize"))
    local box = StaticConstructObject(StaticFindObject("/Script/UMG.Border"), tree, FName("DAH2P_Mark"))
    if not (valid(size) and valid(box)) then return nil end
    pcall(function() size:SetWidthOverride(CFG.MARKER_SIZE) end)
    pcall(function() size:SetHeightOverride(CFG.MARKER_SIZE) end)
    pcall(function() box:SetBrushColor({ R = 1.0, G = 0.85, B = 0.0, A = 0.85 }) end)
    pcall(function() size:SetContent(box) end)
    if not pcall(function() size:SetRenderAngle(45) end) then pcall(function() size:SetRenderTransformAngle(45) end) end
    pcall(function() tree.RootWidget = size end)
    pcall(function() w:AddToPlayerScreen(80) end)
    pcall(function() w:SetDesiredSizeInViewport({ X = CFG.MARKER_SIZE, Y = CFG.MARKER_SIZE }) end)
    pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
    return { widget = w, made = os.clock() }
end

local function p2Target()
    local pawn = getPawn(state.p2)
    local mental = subObj(pawn, "m_pMentalAbilityComponent")
    local t = mental and subObj(mental, "m_pCurrentAimTarget")
    if t then return t end
    for _, w in ipairs(weaponsOf(pawn)) do
        local okA, arr = pcall(function() return w.m_apCurrentLockedTargets end)
        local list = okA and arrayToList(arr) or {}
        if valid(list[1]) then return list[1] end
    end
    return nil
end

local function markerTick()
    if not (CFG.P2_MARKER and valid(state.p2)) then
        if marker and valid(marker.widget) then pcall(function() marker.widget:RemoveFromParent() end) end
        marker = nil
        return
    end
    -- Diamond for now: try the game's own marker again every few seconds.
    if marker and not marker.game and CFG.MARKER_USE_GAME_WIDGET and os.clock() - (marker.made or 0) > 5 then
        marker.made = os.clock()
        local gs = FindFirstOf("GameStateBase")
        local okM, mgr = pcall(function() return gs:GetHighlightableSceneObjectManager() end)
        local comp = okM and valid(mgr) and subObj(mgr, "m_pFocusedOpportunityWidget_Mental")
        local okU, inner = pcall(function() return comp and comp:GetUserWidgetObject() end)
        local okWC, wcls = pcall(function() return comp and comp.WidgetClass end)
        if (okU and valid(inner)) or (okWC and valid(wcls)) then   -- the game's marker exists now: switch to it
            pcall(function() marker.widget:RemoveFromParent() end)
            marker = nil
        end
    end
    if not (marker and valid(marker.widget)) then
        local ok, m = pcall(makeMarker, state.p2)
        marker = ok and m or nil
        if not markerLogged then markerLogged = true; log("Player 2 lock-on marker: %s", marker and "on" or ("not available: " .. tostring(m))) end
        if not marker then return end
    end
    local target = p2Target()
    local shown = false
    if valid(target) then
        local okL, loc = pcall(function() return target:K2_GetActorLocation() end)
        if okL and loc then
            local out = {}
            local okP, onScreen = pcall(function()
                local up = marker.bracket and CFG.BRACKET_HEIGHT or CFG.MARKER_HEIGHT
                return state.p2:ProjectWorldLocationToScreen({ X = loc.X, Y = loc.Y, Z = loc.Z + up }, out, true)
            end)
            local x, y = readXY(out)
            if okP and onScreen and type(x) == "number" then
                pcall(function() marker.widget:SetPositionInViewport({ X = x, Y = y }, true) end)
                shown = true
            end
        end
    end
    pcall(function() marker.widget:SetVisibility(shown and 4 or 2) end)   -- 2 = hidden
end
addTickJob("p2Marker", 0, markerTick)
end

-- Player 2's own yellow lock-on marker: the game makes one per player (the mental-abilities
-- component's m_pTargetMarker), but Player 2's is put on Player 1's screen. Move it to
-- Player 2's half.
do
    local moved = nil
    onWorldChange(function() moved = nil end); state.onP2Leave(function() moved = nil end)
    addTickJob("p2TargetMarker", 1.0, function()
        if not (CFG.P2_GAME_TARGET_MARKER and valid(state.p2)) then moved = nil return end
        local mental = subObj(getPawn(state.p2), "m_pMentalAbilityComponent")
        local mk = mental and subObj(mental, "m_pTargetMarker")
        local key = mk and keyOf(mk)
        if not key or key == moved then return end
        local okO, owner = pcall(function() return mk:GetOwningPlayer() end)
        pcall(function() mk:RemoveFromParent() end)
        pcall(function() mk:SetOwningPlayer(state.p2) end)
        local okA, added = pcall(function() return mk:AddToPlayerScreen(5) end)
        moved = key
        log("Player 2's lock-on marker %s: was owned by %s, moved to Player 2's screen: %s", shortName(mk),
            okO and valid(owner) and shortName(owner) or "?", okA and tostring(added) or "failed")
    end)
end

-- Player 2's lock-on marker, placed by the mod: the game positions it with Player 1's camera
-- (so it never lands on Player 2's target). Each frame it's put over Player 2's current target,
-- as seen by Player 2's camera, and shown only while there's a target.
do
    local function asActorObj(o)
        if not valid(o) then return nil end
        local okA, isA = pcall(function() return o:IsA(StaticFindObject("/Script/Engine.Actor")) end)
        if okA and isA then return o end
        local okO, ow = pcall(function() return o:GetOwner() end)
        return (okO and valid(ow)) and ow or nil
    end
    local shown = nil
    -- The game never gives Player 2 a lock-on target of its own (it works it out with Player 1's
    -- camera), so pick one the way the game does for Player 1: the nearest person or animal close
    -- to the middle of Player 2's crosshair.
    local chars, charsAt, own, ownAlive, ownAt = {}, -10, nil, nil, -10
    onWorldChange(function() chars = {}; charsAt = -10; own = nil; ownAlive = nil end); state.onP2Leave(function() chars = {}; charsAt = -10; own = nil; ownAlive = nil end)
    local function ownTarget(pawn)
        local now = os.clock()
        if now - ownAt < 0.1 then return own, ownAlive end
        ownAt = now
        if now - charsAt > 1.0 then
            charsAt = now
            local list = {}
            pcall(function()
                local out = {}
                getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
                for _, a in ipairs(out) do
                    local v = a
                    if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                    if valid(v) then list[#list + 1] = v end
                end
            end)
            chars = list
        end
        local okR, rot = pcall(function() return state.p2.PlayerCameraManager:GetCameraRotation() end)
        if not (okR and rot) then okR, rot = pcall(function() return state.p2:GetControlRotation() end) end
        local okC, cam = pcall(function() return state.p2.PlayerCameraManager:GetCameraLocation() end)
        if not (okR and rot and okC and cam) then own = nil; ownAlive = nil return nil end
        -- the crosshair sits above the middle of the view: aim along the line through it
        local raise = state.p2CrosshairPitch() or 0
        local yaw, pitch = math.rad(rot.Yaw), math.rad(rot.Pitch + raise)
        local fx, fy, fz = math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)
        local p1pawn = getPawn(player1Controller())
        local pk, p1k = keyOf(pawn), valid(p1pawn) and keyOf(p1pawn) or nil
        local okMe, me = pcall(function() return pawn:K2_GetActorLocation() end)
        if not okMe then me = cam end
        -- whatever Player 2's PK is holding is skipped, so the Zap-O-Matic lock (cyan) moves on
        -- to the next one, like Player 1's
        local heldK = nil
        pcall(function()
            local ab = state.p2PKAbility()
            local h = ab and ab.m_pActiveTarget
            if valid(h) then
                local okA, isActor = pcall(function() return h:IsA(StaticFindObject("/Script/Engine.Actor")) end)
                if not (okA and isActor) then
                    local okO, o = pcall(function() return h:GetOwner() end)
                    if okO and valid(o) then h = o end
                end
                heldK = keyOf(h)
            end
        end)
        local pkRange = state.p2PKRange()
        local best, bestScore, alive, aliveScore = nil, nil, nil, nil
        for _, c in ipairs(chars) do
            if valid(c) then
                local k = keyOf(c)
                if k ~= pk and k ~= p1k and k ~= heldK and not state.notTargetable(c) then
                    local l = state.targetPoint(c)
                    if l then
                        local dx, dy, dz = l.X - cam.X, l.Y - cam.Y, l.Z - cam.Z
                        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                        local ex, ey, ez = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                        local dMe = math.sqrt(ex * ex + ey * ey + ez * ez)
                        if d > 100 and dMe < CFG.P2_LOCK_RANGE then
                            local cosA = (dx * fx + dy * fy + dz * fz) / d
                            if cosA > CFG.P2_LOCK_COS then
                                -- the yellow arcs (PK) take bodies too, like Player 1's, within PK's
                                -- reach; the Zap-O-Matic only the living, within the beam's reach
                                local score = (1 - cosA) * 8 + dMe / CFG.P2_LOCK_RANGE
                                if (not bestScore or score < bestScore) and dMe <= pkRange and state.p2PKAble(c) then best, bestScore = c, score end
                                if (not aliveScore or score < aliveScore) and dMe <= (state.p2WeaponLockRange or CFG.P2_ZAP_LOCK_RANGE) and not state.deadChar(c) then
                                    -- not through walls
                                    local okS, seen = pcall(function() return state.p2:LineOfSightTo(c, cam, false) end)
                                    if not okS or seen ~= false then alive, aliveScore = c, score end
                                end
                            end
                        end
                    end
                end
            end
        end
        own, ownAlive = best, alive
        return best, alive
    end
    -- Player 2 gets its own copy of the yellow lock-on marker: the game's own copy for Player 2
    -- is faded out by the game every frame (it thinks Player 2 has no target), so the mod
    -- draws a separate one that only it controls.
    local copy, copyTarget, acquiredAt = nil, nil, 0
    local wroteLock = false
    onWorldChange(function() copy = nil; copyTarget = nil end); state.onP2Leave(function() if copy and valid(copy) then pcall(function() copy:RemoveFromParent() end) end; copy = nil; copyTarget = nil end)
    local function hideCopy()
        if copy and valid(copy) then pcall(function() copy:SetVisibility(1) end) end
        copyTarget = nil
    end
    addTickJob("p2MarkerFollow", 0.0, function()
        if not (CFG.P2_MARKER_FOLLOW and valid(state.p2)) then
            if copy and valid(copy) then pcall(function() copy:RemoveFromParent() end) end
            copy = nil
            return
        end
        local pawn = getPawn(state.p2)
        local mental = subObj(pawn, "m_pMentalAbilityComponent")
        local mk = mental and subObj(mental, "m_pTargetMarker")
        if not (copy and valid(copy)) then
            copy = nil
            if not mk then return end
            local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
            local okC, cls = pcall(function() return mk:GetClass() end)
            local okW, w = pcall(function() return wbl:Create(getWorld(), cls, state.p2) end)
            if not (okC and okW and valid(w)) then return end
            pcall(function() w:AddToPlayerScreen(6) end)
            pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
            pcall(function() w:SetVisibility(1) end)
            -- centre the arcs on the point: the widget's root is a canvas with no size of its
            -- own, so its picture hung down and to the right of the target. Give the widget a
            -- size and pin the picture to its middle.
            pcall(function()
                local img = w.Image_146
                local slot = img and img.Slot
                if slot then
                    pcall(function()
                        local p, z, al = slot:GetPosition(), slot:GetSize(), slot:GetAlignment()
                        log("Player 2 arcs picture was at (%.0f, %.0f), size %.0f x %.0f, alignment %.2f, %.2f",
                            p.X or 0, p.Y or 0, z.X or 0, z.Y or 0, al.X or 0, al.Y or 0)
                    end)
                    pcall(function() slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }) end)
                    pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
                    pcall(function() slot:SetPosition({ X = CFG.P2_ARC_NUDGE_X, Y = CFG.P2_ARC_NUDGE_Y }) end)
                end
            end)
            pcall(function() w:SetDesiredSizeInViewport({ X = 100, Y = 100 }) end)
            copy = w
            state.p2CopyPK = nil
            log("Player 2 lock-on marker: own copy made (%s)", shortName(w))
        end
        -- the auto-lock (yellow) target first, then whatever the aim is on, then the mod's pick
        -- Player 2's lock is picked from Player 2's own camera, and handed to the game as
        -- Player 2's real lock (the focus lock and the mind-ability aim target), so PK and the
        -- Zap-O-Matic use it like Player 1's.
        local focus = subObj(pawn, "m_pFocusComponent")
        local tgt, aliveTgt = ownTarget(pawn)
        -- what PK would grab right now (Player 2 looking straight at it): that's certain
        do
            local ab = state.p2PKAbility()
            local okH, hov = false, nil
            if ab then okH, hov = pcall(function() return ab:GetCurrentHoveredActor() end) end
            if okH and valid(hov) then
                local okI, isChar = pcall(function() return hov:IsA(StaticFindObject("/Script/Engine.Character")) end)
                if okI and isChar and keyOf(hov) ~= keyOf(pawn) then tgt = hov end
                state.p2Hovered = hov
            else
                state.p2Hovered = nil
            end
            -- yellow arcs only on what PK will certainly grab right now (what it has under
            -- Player 2's crosshair, within its reach): people, animals, props and cars
            if CFG.P2_YELLOW_ONLY_HOVERED then
                tgt = (okH and valid(hov) and keyOf(hov) ~= keyOf(pawn)) and hov or nil
            end
            -- what the game itself has PK aimed at for Player 2 (read before the mod writes
            -- anything): when there is one, the arcs go on it, bright, because that is what RB
            -- grabs. The mod's own pick is only shown (dimmer) when the game has nothing.
            local gameAim = nil
            if ab then
                local okG, g = pcall(function() return ab.m_pCurrentAimTarget end)
                if okG and valid(g) and keyOf(g) ~= keyOf(pawn) then gameAim = g end
            end
            local gamePK = (okH and valid(hov) and keyOf(hov) ~= keyOf(pawn)) and hov or gameAim
            if gamePK and state.notTargetable(gamePK) then gamePK = nil end
            state.p2GamePK = gamePK
            -- the game's PK aim for Player 2 drops out for a moment now and then (Player 1's
            -- doesn't): keep the last one for a short while, as long as it's still close
            if gamePK then
                state.p2PKLast, state.p2PKLastAt = gamePK, os.clock()
            elseif valid(state.p2PKLast) and os.clock() - (state.p2PKLastAt or 0) < CFG.P2_PK_GAP_HOLD
                   and not state.deadChar(state.p2PKLast) then
                gamePK = state.p2PKLast
            end
            if CFG.P2_ARCS_FOLLOW_GAME then tgt = gamePK end   -- nothing for PK = no arcs (like Player 1)
            local snap = os.clock() < (state.snapUntil or 0)
            if (snap or (CFG.P2_TARGET_REPORT and (state.p2TgtReps or 0) < 30)) and os.clock() >= (state.p2TgtRepAt or 0) then
                state.p2TgtRepAt = os.clock() + (snap and 0.5 or 2)
                state.p2TgtReps = (state.p2TgtReps or 0) + 1
                local function nm(x) return valid(x) and shortName(x) or "-" end
                local okF, f0 = pcall(function() return focus and focus.m_pCurrentAutoLockTarget end)
                log("P2 targets: PK hovered %s | PK aim %s | focus %s | mod pick %s | gun pick %s",
                    nm(okH and hov or nil), nm(gameAim), nm(okF and f0 or nil), nm(tgt), nm(aliveTgt))
            end
        end
        -- the gun's lock: the game's own for Player 2 when it has one (read before anything is
        -- written), else the mod's pick
        state.p2ModLock = aliveTgt
        state.p2Lock = aliveTgt
        state.p2PKLock = tgt
        if CFG.P2_LOCK_REAL then
            if tgt then
                if focus then pcall(function() focus.m_pCurrentAutoLockTarget = aliveTgt or tgt end) end
                if mental and not CFG.P2_ARCS_FOLLOW_GAME then pcall(function() mental.m_pCurrentAimTarget = tgt end) end
                -- PK grabs its "hovered" thing: make that the yellow target while not holding
                if CFG.P2_PK_USES_LOCK then
                    pcall(function()
                        for _, ab in ipairs(state.p2Abilities(mental)) do
                            if valid(ab) then
                                pcall(function() ab.m_pCurrentAimTarget = tgt end)
                                if nameOf(ab):find("Psy[c]?h?o?kinesis") or nameOf(ab):find("Psycokinesis") then
                                    local okA, held = pcall(function() return ab.m_pActiveTarget end)
                                    if not (okA and valid(held)) then ab.m_pHoveredActor = tgt end
                                end
                            end
                        end
                    end)
                end
                wroteLock = true
            elseif wroteLock then
                wroteLock = false
                if focus then pcall(function() focus.m_pCurrentAutoLockTarget = nil end) end
                if mental then pcall(function() mental.m_pCurrentAimTarget = nil end) end
            end
        end
        if not tgt then hideCopy() return end
        local loc = state.targetPoint(tgt)
        if not loc then hideCopy() return end
        loc = { X = loc.X, Y = loc.Y, Z = loc.Z + CFG.P2_ARC_RAISE }
        -- holding something with PK: no yellow arcs (like Player 1's)
        do
            local ab = state.p2PKAbility()
            local okA, held = false, nil
            if ab then okA, held = pcall(function() return ab.m_pActiveTarget end) end
            if okA and valid(held) then hideCopy() return end
        end
        -- PK picks what Player 2 is looking straight at: when Player 2 presses RB with the yellow
        -- arcs on something, turn Player 2's aim onto it for a moment so PK grabs that
        -- put Player 2's crosshair height back once the PK reach is over
        if state.p2OffOrig ~= nil and os.clock() - (state.p2AimOvAt or 0) > 0.05 then
            pcall(function() state.p2TargetComponent().m_fCrosshairOffsetY = state.p2OffOrig end)
            state.p2OffOrig = nil
        end
        if CFG.P2_PK_AIM_ASSIST then
            state.pkAssist = state.pkAssist or {}
            local pkAssist = state.pkAssist
            local rb = kbDown(state.p2, "Gamepad_RightShoulder")
            local now2 = os.clock()
            if rb and not pkAssist.down then
                pkAssist.at = now2
                state.pkAssistLogs = (state.pkAssistLogs or 0) + 1
                if state.pkAssistLogs <= 10 then
                    log("P2 PK reach: RB pressed, yellow on %s, PK has %s under the crosshair", shortName(tgt),
                        valid(state.p2Hovered) and shortName(state.p2Hovered) or "nothing")
                end
            end
            pkAssist.down = rb
            if rb and pkAssist.at and now2 - pkAssist.at < CFG.P2_PK_AIM_ASSIST_TIME then
                local holding = false
                for _, ab in ipairs(state.p2Abilities(mental)) do
                    if valid(ab) and nameOf(ab):find("kinesis") then
                        local okA, h = pcall(function() return ab.m_pActiveTarget end)
                        if okA and valid(h) then holding = true end
                    end
                end
                if holding then
                    pkAssist.at = nil
                    state.p2AimOverride = nil
                elseif valid(state.p2Hovered) and keyOf(state.p2Hovered) == keyOf(tgt) then
                    -- already under the crosshair: nothing to do
                else
                    if CFG.P2_PK_CAMERA_ASSIST then
                        -- old way: steer the camera so the target lands under the crosshair
                        pcall(function()
                            local cm = state.p2.PlayerCameraManager
                            local c, r = cm:GetCameraLocation(), cm:GetCameraRotation()
                            local yaw, pitch = math.rad(r.Yaw), math.rad(r.Pitch)
                            local far = { X = c.X + math.cos(pitch) * math.cos(yaw) * 5000,
                                          Y = c.Y + math.cos(pitch) * math.sin(yaw) * 5000,
                                          Z = c.Z + math.sin(pitch) * 5000 }
                            local mid, tp = {}, {}
                            if not (state.p2:ProjectWorldLocationToScreen(far, mid, true) and mid.X) then return end
                            if not (state.p2:ProjectWorldLocationToScreen(loc, tp, true) and tp.X) then return end
                            local cx, cy = mid.X, mid.Y
                            local aimY = cy * (1 + CFG.P2_CROSSHAIR_RAISE)
                            local fov = 90
                            pcall(function() local f = cm:GetFOVAngle(); if type(f) == "number" and f > 10 then fov = f end end)
                            local focal = cx / math.tan(math.rad(fov) / 2)
                            local yawErr = math.deg(math.atan((tp.X - cx) / focal))
                            local pitchErr = math.deg(math.atan((aimY - cy) / focal)) - math.deg(math.atan((tp.Y - cy) / focal))
                            local k = CFG.P2_PK_AIM_ASSIST_SMOOTH
                            local cr = state.p2:GetControlRotation()
                            state.p2:SetControlRotation({ Pitch = cr.Pitch + pitchErr * k, Yaw = cr.Yaw + yawErr * k, Roll = 0 })
                        end)
                    elseif state.dllAimOverride() then
                        -- new way: leave the camera alone and move only Player 2's aim point onto
                        -- the target for these moments, so PK reaches for it. The pad router DLL
                        -- reads the aim point from a coded value in Player 2's crosshair height.
                        pcall(function()
                            local cm = state.p2.PlayerCameraManager
                            local c, r = cm:GetCameraLocation(), cm:GetCameraRotation()
                            local yaw, pitch = math.rad(r.Yaw), math.rad(r.Pitch)
                            local far = { X = c.X + math.cos(pitch) * math.cos(yaw) * 5000,
                                          Y = c.Y + math.cos(pitch) * math.sin(yaw) * 5000,
                                          Z = c.Z + math.sin(pitch) * 5000 }
                            local mid, tp = {}, {}
                            if not (state.p2:ProjectWorldLocationToScreen(far, mid, true) and mid.X and mid.X > 0) then return end
                            if not (state.p2:ProjectWorldLocationToScreen(loc, tp, true) and tp.X) then return end
                            local tc = state.p2TargetComponent()
                            if not tc then
                                if not state.tcWarned then state.tcWarned = true; log("P2 PK reach: Player 2's aim component not found") end
                                return
                            end
                            local fx = math.max(0, math.min(1, tp.X / (2 * mid.X)))
                            local fy = math.max(0, math.min(1, tp.Y / (2 * mid.Y)))
                            if state.p2OffOrig == nil then
                                local o = tc.m_fCrosshairOffsetY
                                if type(o) == "number" and o < 50 then state.p2OffOrig = o end
                            end
                            local code = 100 + math.floor(fx * 999 + 0.5) + math.floor(fy * 999 + 0.5) / 1000
                            tc.m_fCrosshairOffsetY = code
                            state.p2AimOvAt = os.clock()
                            if not state.aimOvLogged then
                                state.aimOvLogged = true
                                log("P2 PK reach: aim point moved to %.2f, %.2f of Player 2's view for %s", fx, fy, shortName(tgt))
                            end
                        end)
                    end
                end
            end
        end
        local out = {}
        local okP, onScreen = pcall(function() return state.p2:ProjectWorldLocationToScreen({ X = loc.X, Y = loc.Y, Z = loc.Z }, out, true) end)
        if not (okP and onScreen and out.X and out.X >= 0 and out.Y >= 0) then hideCopy() return end
        local k = keyOf(tgt)
        local now = os.clock()
        if k ~= copyTarget then
            copyTarget = k
            acquiredAt = now
            -- the game's little "locked on" pop
            pcall(function() copy:PlayAnimation(copy.Blip, 0.0, 1, 0, 1.0, false) end)
        end
        pcall(function() copy:SetPositionInViewport({ X = out.X, Y = out.Y }, true) end)
        pcall(function() copy:SetVisibility(4) end)
        -- "PK can grab this": the game's marker has its own switch for when the mind
        -- abilities and the weapon share the target (PK has it under Player 2's aim).
        -- Flip it, pop the marker, and keep the arcs dimmer while PK can't grab it yet.
        local pkNow = (valid(state.p2Hovered) and keyOf(state.p2Hovered) == k)
            or (valid(state.p2GamePK) and keyOf(state.p2GamePK) == k)
        if pkNow ~= state.p2CopyPK then
            state.p2CopyPK = pkNow
            pcall(function() copy:WeaponAndAbilitySharedTargetChanged(pkNow) end)
            if pkNow then pcall(function() copy:PlayAnimation(copy.Blip, 0.0, 1, 0, 1.0, false) end) end
        end
        if now - acquiredAt > 0.35 then
            pcall(function() copy:SetRenderOpacity(1.0) end)
        end
        -- smaller when further away, like Player 1's (the game's 0.5 .. 1.3 range)
        local okC, cam = pcall(function() return state.p2.PlayerCameraManager:GetCameraLocation() end)
        if okC and cam then
            local dx, dy, dz = loc.X - cam.X, loc.Y - cam.Y, loc.Z - cam.Z
            local d = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
            local sc = math.max(0.5, math.min(1.3, 2000 / d))
            pcall(function() copy:SetRenderScale({ X = sc, Y = sc }) end)
        end
        if not state.markerFollowLogged then
            state.markerFollowLogged = true
            log("Player 2 lock-on marker following %s at (%.0f, %.0f)", shortName(tgt), out.X, out.Y)
        end
    end)
end

-- Player 2's Zap-O-Matic chain. The game picks a Zap-O-Matic's targets (the main one and the
-- ones the arc jumps to) with Player 1's camera, so Player 2's zap only ever hits what it
-- touches. While Player 2 zaps, the weapon's list of locked targets is filled from Player 2's
-- own lock (the yellow arcs) plus the nearest people next to it. The watcher logs what the
-- list looks like for both players while they zap, so it can be matched to Player 1's.
do
    local function weaponOf(pc)
        local eq = subObj(getPawn(pc), "m_pEquipmentManagerComponent")
        if not eq then return nil end
        local okW, w = pcall(function() return eq:GetCurrentWeapon() end)
        if okW and valid(w) then return w end
        local okL, ws = pcall(function() return eq:GetCurrentWeapons() end)
        local l = okL and arrayToList(ws) or {}
        return valid(l[1]) and l[1] or nil
    end
    local function isZap(w) return w and nameOf(w):find("Zap%-O%-Matic") ~= nil end
    local function shooting(w)
        local ok, v = pcall(function() return w:IsShooting() end)
        return ok and v == true
    end
    local function lockedNames(w)
        local names = {}
        pcall(function()
            for _, t in ipairs(arrayToList(w.m_apCurrentLockedTargets)) do names[#names + 1] = valid(t) and shortName(t) or "?" end
        end)
        return names
    end
    local function chainFrom(first, cfg)
        local maxExtra = cfg and cfg.n or (CFG.P2_ZAP_CHAIN_MAX - 1)
        local range = cfg and cfg.range or CFG.P2_ZAP_CHAIN_RANGE
        local list = { first }
        local at = state.targetPoint(first)
        if not at then return list end
        local p1k, p2k = keyOf(getPawn(player1Controller())), keyOf(getPawn(state.p2))
        local cands = {}
        pcall(function()
            local out = {}
            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) then
                    local k = keyOf(v)
                    if k ~= p1k and k ~= p2k and k ~= keyOf(first) then
                        local l = state.targetPoint(v)
                        local okP = l ~= nil
                        if not state.deadChar(v) and okP and l then
                            local dx, dy, dz = l.X - at.X, l.Y - at.Y, l.Z - at.Z
                            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                            if d < range then cands[#cands + 1] = { v, d } end
                        end
                    end
                end
            end
        end)
        if not CFG.P2_ZAP_TRUE_CHAIN then
            table.sort(cands, function(a, b) return a[2] < b[2] end)
            for i = 1, math.min(#cands, maxExtra) do list[#list + 1] = cands[i][1] end
            return list
        end
        -- each jump goes from the last one hit to the nearest new person within reach of it
        local used, from = {}, at
        for _ = 1, maxExtra do
            local best, bd = nil, nil
            for _, c in ipairs(cands) do
                local k = keyOf(c[1])
                if not used[k] then
                    local l = state.targetPoint(c[1])
                    if l then
                        local d = math.sqrt((l.X - from.X) ^ 2 + (l.Y - from.Y) ^ 2 + (l.Z - from.Z) ^ 2)
                        if d < range and (not bd or d < bd) then best, bd = c[1], d end
                    end
                end
            end
            if not best then break end
            used[keyOf(best)] = true
            list[#list + 1] = best
            from = state.targetPoint(best) or from
        end
        return list
    end
    local watchLines, lastWatch = 0, {}
    local zap = {}
    -- the visible arcs: one of the game's own Zap-O-Matic beam effects per jump, from the main
    -- target to each person the zap jumps to
    local arcs, arcClass = {}, nil
    local function clearArcs()
        for k, a in pairs(arcs) do
            if valid(a) then
                pcall(function() a:StopBeam() end)
                pcall(function() a:K2_DestroyActor() end)
            end
            arcs[k] = nil
        end
    end
    local function updateArcs(w, main, links)
        if not CFG.P2_ZAP_ARCS then return end
        if not arcClass then
            pcall(function()
                local fx = w.m_pBeam.BeamEffect
                if valid(fx) then arcClass = fx:GetClass() end
            end)
            if not arcClass then return end
        end
        local from = state.targetPoint(main)
        if not from then return end
        local want = {}
        for i = 2, #links do
            local v = links[i]
            local k = keyOf(v)
            want[k] = true
            local a = arcs[k]
            if not valid(a) then
                local ok, made = pcall(function() return getWorld():SpawnActor(arcClass, from, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
                if ok and valid(made) then
                    a = made
                    arcs[k] = a
                    pcall(function() a.audio_weaponloop:Stop() end)
                    -- the game normally sets these up through its effect system: switch the
                    -- pieces on directly
                    pcall(function() a:SetBlackboard(w.m_pBeam.BeamEffect.m_pBlackboard) end)
                    pcall(function() a:TriggerEffect() end)
                    pcall(function() a:SetActorHiddenInGame(false) end)
                    for _, part in ipairs({ "Lightning_Beam", "Lightning_Beam_2" }) do
                        pcall(function() a[part]:SetHiddenInGame(false, true) end)
                        pcall(function() a[part]:SetVisibility(true, true) end)
                    end
                    for _, part in ipairs({ "PFX_Zap-o-Matic_permanent_01", "PFX_hit_loop_01" }) do
                        pcall(function() a[part]:Activate(true) end)
                    end
                    pcall(function() a:SetTargetActor(v) end)
                    pcall(function() a:StartBeam() end)
                    if not zap.arcLogged then zap.arcLogged = true; log("P2 zap arcs: drawing with %s", shortName(a)) end
                elseif not zap.arcFail then
                    zap.arcFail = true
                    log("P2 zap arcs: couldn't make a beam effect: %s", tostring(made))
                end
            end
            if valid(a) then
                pcall(function() a:K2_SetActorLocation(from, false, {}, false) end)
                pcall(function()
                    local to = state.targetPoint(v)
                    local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
                    local yaw = math.deg(math.atan(dy, dx))
                    local pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
                    a:K2_SetActorRotation({ Pitch = pitch, Yaw = yaw, Roll = 0 }, false)
                    a:SetTargetLocation(to)
                end)
                pcall(function() a:SetTargetActor(v) end)
                pcall(function() a:UpdateBeam() end)
                pcall(function() a:ForceBeamUpdate() end)
                pcall(function() a:UpdateBeamFVX() end)
            end
        end
        for k, a in pairs(arcs) do
            if not want[k] then
                if valid(a) then pcall(function() a:StopBeam() end); pcall(function() a:K2_DestroyActor() end) end
                arcs[k] = nil
            end
        end
    end
    onWorldChange(function() zap = {}; arcs = {}; arcClass = nil end); state.onP2Leave(function() zap = {}; arcs = {}; arcClass = nil end)
    addTickJob("p2ZapChain", 0.0, function()
        if not valid(state.p2) then return end
        -- watcher (both players, a few lines only)
        if CFG.ZAP_WATCH and watchLines < 60 then
            for i, pc in ipairs({ player1Controller(), state.p2 }) do
                local w = weaponOf(pc)
                if isZap(w) and shooting(w) then
                    local line = table.concat(lockedNames(w), ", ")
                    if line ~= lastWatch[i] then
                        lastWatch[i] = line
                        watchLines = watchLines + 1
                        log("Zap watch P%d: shooting, locked targets [%s]", i, line)
                    end
                else
                    lastWatch[i] = nil
                end
            end
        end
        if not CFG.P2_ZAP_CHAIN or state.zapShotActive then return end
        local w = weaponOf(state.p2)
        if not (isZap(w) and shooting(w)) then
            zap.main = nil; zap.links = nil; clearArcs()
            if not isZap(w) then zap.cfg = nil end
            return
        end
        local tgt = state.p2Lock
        if not valid(tgt) then zap.main = nil; zap.links = nil; clearArcs() return end
        if zap.links and zap.main == keyOf(tgt) then updateArcs(w, tgt, zap.links) end
        -- the gun's lock: just the main target, like Player 1's
        pcall(function()
            local arr = w.m_apCurrentLockedTargets
            local n = arr:GetArrayNum()
            for i = 1, math.max(1, n) do arr[i] = tgt end
        end)
        -- the arc: the game won't jump Player 2's zap to anyone else, so the mod does. The people
        -- next to the target take the same damage the target is taking from the zap.
        local now = os.clock()
        local k = keyOf(tgt)
        local hs = stat(tgt, "m_pHealthStat")
        local okH, hv = pcall(function() return hs:GetValue() end)
        if zap.main ~= k then
            zap.main, zap.lastH, zap.lastT, zap.dps, zap.tickAt = k, okH and hv or nil, now, nil, now
            zap.dt = nil
            pcall(function()
                local b = w.m_pBeam
                local d = valid(b) and b.m_pDamageType
                if valid(d) then zap.dt = d end
            end)
            if not zap.dt then pcall(function() local d = w.m_pDamageType; if valid(d) then zap.dt = d end end) end
            return
        end
        if okH and type(hv) == "number" and zap.lastH and now - zap.lastT >= 0.25 then
            local drop = (zap.lastH - hv) / (now - zap.lastT)
            if drop > 0 then zap.dps = zap.dps and (zap.dps * 0.6 + drop * 0.4) or drop end
            zap.lastH, zap.lastT = hv, now
        end
        if now - zap.tickAt < 0.25 then return end
        local step = now - zap.tickAt
        zap.tickAt = now
        local dps = zap.dps or CFG.P2_ZAP_CHAIN_DPS
        -- jump count, reach and damage from the Zap-O-Matic beam's own (upgraded) settings
        if state.p2ZapCfgReset then state.p2ZapCfgReset = false; zap.cfg = nil end
        if not zap.cfg then
            zap.cfg = { n = CFG.P2_ZAP_CHAIN_MAX - 1, range = CFG.P2_ZAP_CHAIN_RANGE, mult = 1.0 }
            pcall(function()
                local b = w.m_pBeam
                if not valid(b) then return end
                local n = tonumber(b.m_iIridiumSpreaderNumberOfJumps) or 0
                local n2 = tonumber(b.m_iIRIDIUM_NumberPossibleJumps) or 0
                if math.max(n, n2) > 0 then zap.cfg.n = math.max(n, n2) end
                local r = tonumber(b.m_fIRIDIUM_InitialJumpDistance)
                if r and r > 0 then zap.cfg.range = r end
                local m = tonumber(b.m_fCompoundRIzer_DamagePercentPerJump) or tonumber(b.m_fIRIDIUM_DamagePercentPerJump)
                if m and m > 0 then zap.cfg.mult = m end
            end)
            log("P2 zap chain settings: %d jump(s), reach %.0f cm, %.0f%% damage per jump", zap.cfg.n, zap.cfg.range, zap.cfg.mult * 100)
        end
        local chain = chainFrom(tgt, zap.cfg)
        if zap.mainKey ~= keyOf(tgt) then zap.mainKey, zap.mainSince = keyOf(tgt), now end
        local allowed = math.floor((now - (zap.mainSince or now)) / CFG.P2_ZAP_JUMP_EVERY)
        while #chain > 1 + allowed do table.remove(chain) end
        zap.links = chain
        local pw = getPawn(state.p2)
        local dt = zap.dt or StaticFindObject("/Script/Engine.DamageType")
        for i = 2, #chain do
            local v = chain[i]
            local dc = subObj(v, "m_pDamageComponent") or subObj(pw, "m_pDamageComponent")
            if dc then pcall(function() dc:ApplyAndReportDamage(v, dps * step * zap.cfg.mult, pw, pw, dt, true) end) end
        end
        if (zap.logCount or 0) < 8 and #chain > 1 and zap.lastLogged ~= keyOf(tgt) then
            zap.logCount = (zap.logCount or 0) + 1
            zap.lastLogged = keyOf(tgt)
            local a, ds = state.targetPoint(tgt), {}
            for i = 2, #chain do
                local b = state.targetPoint(chain[i])
                if a and b then ds[#ds + 1] = string.format("%.0f", math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2)) end
            end
            log("P2 zap chain: %s -> %d more at %s cm (%.1f damage/s, damage type %s)", shortName(tgt), #chain - 1,
                table.concat(ds, ", "), dps, zap.dt and shortName(zap.dt) or "plain")
        end
    end)
end

-- Player 2's cyan Zap-O-Matic bracket. The game's one for Player 2 is placed from Player 1's
-- view, so it's hidden and Player 2 gets a copy the mod places: on Player 2's zap lock (full
-- strength) or, with nothing locked, at Player 2's aim point (faint, like the game's).
do
    local copy = nil
    onWorldChange(function() copy = nil end); state.onP2Leave(function() if copy and valid(copy) then pcall(function() copy:RemoveFromParent() end) end; copy = nil end)
    local function zapOf(pc)
        local eq = subObj(getPawn(pc), "m_pEquipmentManagerComponent")
        if not eq then return nil end
        local okW, w = pcall(function() return eq:GetCurrentWeapon() end)
        if not (okW and valid(w)) then
            local okL, ws = pcall(function() return eq:GetCurrentWeapons() end)
            w = okL and arrayToList(ws)[1] or nil
        end
        if not valid(w) then return nil end
        local n = nameOf(w)
        -- every gun that locks on (the Ion Detonator doesn't); the saucer guns on foot neither
        if n:find("Ion") or n:find("/UFO/") then return nil end
        local okA, auto = pcall(function() return w.m_bUsesAutoTargetSystem end)
        if okA and auto == false then return nil end
        return w
    end
    local copies = {}
    onWorldChange(function() copies = {} end); state.onP2Leave(function() for _, c in pairs(copies) do if type(c) == "userdata" and valid(c) then pcall(function() c:RemoveFromParent() end) end end; copies = {} end)
    local function hide()
        if copy and valid(copy) then pcall(function() copy:SetVisibility(1) end) end
    end
    addTickJob("p2ZapBracket", 0.0, function()
        if not (CFG.P2_ZAP_BRACKET and valid(state.p2)) then
            if copy and valid(copy) then pcall(function() copy:RemoveFromParent() end) end
            copy = nil
            return
        end
        local w = zapOf(state.p2)
        if not w then hide(); state.p2WeaponLockRange = nil return end
        local isZapGun = nameOf(w):find("Zap%-O%-Matic") ~= nil
        state.p2WeaponLockRange = isZapGun and CFG.P2_ZAP_LOCK_RANGE or CFG.P2_WEAPON_LOCK_RANGE
        local game = subObj(w, "m_CrosshairInstance")
        -- one copy per kind of crosshair; switch to the one for the gun in hand
        do
            local okC, cls = pcall(function() return game and game:GetClass() end)
            local cn = (okC and valid(cls)) and nameOf(cls) or nil
            if cn and copy and valid(copy) and copies[cn] ~= copy then
                pcall(function() copy:SetVisibility(1) end)
                copy = copies[cn]
                if copy and not valid(copy) then copy = nil end
            elseif cn and not copy then
                copy = copies[cn]
                if copy and not valid(copy) then copy = nil end
            end
            state.p2BracketClass = cn
            -- the Ion Detonator's (and the probe's) own reticle works on Player 2's half as it is:
            -- no copy for those (the copy of the Ion one showed on Player 1's screen)
            if cn and not (cn:find("ZapOMatic") or cn:find("Disintegrator")) then
                if copy and valid(copy) then pcall(function() copy:SetVisibility(1) end) end
                copy = nil
                if game and state.p2OwnReticleFor ~= keyOf(game) then
                    state.p2OwnReticleFor = keyOf(game)
                    pcall(function() game:SetRenderOpacity(1.0) end)
                    pcall(function() game:SetVisibility(4) end)
                end
                return
            end
        end
        -- the game's own lock for Player 2's gun (the Zap-O-Matic picks its own, correctly)
        do
            local g = nil
            pcall(function()
                local l = arrayToList(w.m_apCurrentLockedTargets)
                local n = 0
                for _, t in ipairs(l) do if valid(t) then n = n + 1; g = g or t end end
                state.p2GameGunN = n
            end)
            if g and state.notTargetable(g) then g = nil end
            state.p2GameGun = g
        end
        -- the gun's lock: Player 2's own target (homing shots use it) when the game has none
        if CFG.P2_MOD_GUN_LOCK and not isZapGun and valid(state.p2Lock) and not state.p2GameGun then
            local t = state.p2Lock
            pcall(function()
                local arr = w.m_apCurrentLockedTargets
                local n = arr:GetArrayNum()
                for i = 1, math.max(1, n) do arr[i] = t end
            end)
        end
        if game then
            pcall(function() game:SetRenderOpacity(0.0) end)
            pcall(function() game:SetVisibility(1) end)
        end
        if not (copy and valid(copy)) then
            copy = nil
            if not game then return end
            local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
            local okC, cls = pcall(function() return game:GetClass() end)
            local okW, c = pcall(function() return wbl:Create(getWorld(), cls, state.p2) end)
            if not (okC and okW and valid(c)) then return end
            pcall(function() c.m_pWeapon = w end)
            pcall(function() c:AddToPlayerScreen(4) end)
            pcall(function() c:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
            copy = c
            if state.p2BracketClass then copies[state.p2BracketClass] = c end
            state.modPlacedWidgets = state.modPlacedWidgets or {}
            state.modPlacedWidgets[keyOf(c) or ""] = true
            pcall(function() c:SetRenderTranslation({ X = 0, Y = 0 }) end)
            -- centre the bracket on the point (its picture hung below and right of it)
            pcall(function()
                local slot = c.Image_146 and c.Image_146.Slot
                if slot then
                    pcall(function()
                        local p, z, al = slot:GetPosition(), slot:GetSize(), slot:GetAlignment()
                        log("Player 2 bracket picture was at (%.0f, %.0f), size %.0f x %.0f, alignment %.2f, %.2f",
                            p.X or 0, p.Y or 0, z.X or 0, z.Y or 0, al.X or 0, al.Y or 0)
                    end)
                    pcall(function() slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }) end)
                    pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
                    pcall(function() slot:SetPosition({ X = CFG.P2_BRACKET_NUDGE_X, Y = CFG.P2_BRACKET_NUDGE_Y }) end)
                end
            end)
            pcall(function() c:SetDesiredSizeInViewport({ X = 100, Y = 100 }) end)
            log("Player 2 lock-on bracket: own copy made (%s, for %s)", shortName(c), shortName(w))
        end
        pcall(function() copy.m_pWeapon = w end)
        local tgt = (CFG.P2_GUN_FOLLOW_GAME and state.p2GameGun) or (CFG.P2_MOD_GUN_LOCK and state.p2Lock) or nil
        state.p2BracketOn = tgt
        local x, y, sc, op = nil, nil, 0.95, 0.25
        if valid(tgt) then
            local loc = state.targetPoint(tgt)
            local okL = loc ~= nil
            local out = {}
            local okP, on = false, false
            if okL then okP, on = pcall(function() return state.p2:ProjectWorldLocationToScreen(loc, out, true) end) end
            if okP and on and out.X and out.X >= 0 and out.Y >= 0 then
                x, y, op = out.X, out.Y, 1.0
                local okC, cam = pcall(function() return state.p2.PlayerCameraManager:GetCameraLocation() end)
                if okC and cam then
                    local dx, dy, dz = loc.X - cam.X, loc.Y - cam.Y, loc.Z - cam.Z
                    local d = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
                    sc = math.max(0.5, math.min(1.3, 2000 / d))
                end
            end
        end
        if not x then
            -- nothing locked: faint, around Player 2's aim point (straight ahead of Player 2's
            -- camera, at the crosshair's height)
            pcall(function()
                local cm = state.p2.PlayerCameraManager
                local c, r = cm:GetCameraLocation(), cm:GetCameraRotation()
                local yaw, pitch = math.rad(r.Yaw), math.rad(r.Pitch)
                local far = { X = c.X + math.cos(pitch) * math.cos(yaw) * 5000, Y = c.Y + math.cos(pitch) * math.sin(yaw) * 5000, Z = c.Z + math.sin(pitch) * 5000 }
                local out = {}
                if state.p2:ProjectWorldLocationToScreen(far, out, true) and out.X then
                    -- the crosshair sits above the middle of the view by the game's offset
                    x, y = out.X, out.Y * (1 + CFG.P2_CROSSHAIR_RAISE)
                end
            end)
        end
        if type(x) ~= "number" or type(y) ~= "number" then hide() return end
        do
            local shared = valid(tgt) and valid(state.p2PKLock) and keyOf(tgt) == keyOf(state.p2PKLock) or false
            if shared ~= state.p2BracketShared then
                state.p2BracketShared = shared
                if CFG.P2_BRACKET_SHARED then pcall(function() copy:WeaponAndAbilitySharedTargetChanged(shared) end) end
            end
        end
        pcall(function() copy:SetPositionInViewport({ X = x, Y = y }, true) end)
        pcall(function() copy:SetRenderScale({ X = sc, Y = sc }) end)
        pcall(function() copy:SetRenderOpacity(op) end)
        pcall(function() copy:SetVisibility(4) end)
    end)
end


-- Weapon wheel off in split screen (it's one shared wheel; tapping to switch weapons still
-- works). If either player opens it, it is closed again straight away.
addTickJob("noWeaponWheel", 0, function()
    if not (CFG.NO_WEAPON_WHEEL_IN_SPLIT and valid(state.p2)) then return end
    if CFG.MIND_WHEEL then return end   -- the mod's own wheel takes over (it hides the game's)
    for _, pc in ipairs({ player1Controller(), state.p2 }) do
        local sel = subObj(getPawn(pc), "m_pWeaponAndAbilitySelection")
        local menu = sel and subObj(sel, "m_pMenu")
        if menu then
            local okV, inVp = pcall(function() return menu:IsInViewport() end)
            local okS, vis = pcall(function() return menu:IsVisible() end)
            if okV and inVp and okS and vis then
                pcall(function() sel:OnSelectionMenuClosed(menu) end)
                pcall(function() menu:RemoveFromParent() end)
                if not state.wheelLogged then state.wheelLogged = true; log("Weapon wheel closed (off in split screen)") end
            end
        end
    end
end)

do
    local held = {}
    addTickJob("p2SkinCombo", 0.05, function()
        if not (CFG.P2_SKIN_COMBO and valid(state.p2)) then return end
        local sel = kbDown(state.p2, "Gamepad_Special_Left")
        for _, e in ipairs({ { "Gamepad_DPad_Right", 1 }, { "Gamepad_DPad_Left", -1 } }) do
            local down = sel and kbDown(state.p2, e[1])
            if down and not held[e[1]] and state.cycleP2Skin then
                local dir = e[2]
                runGame("p2SkinCombo", function() state.cycleP2Skin(dir) end)
            end
            held[e[1]] = down
        end
        -- drop out: hold Select + B on pad 2 for 2 seconds (Start on pad 2 joins again)
        local out = sel and kbDown(state.p2, "Gamepad_FaceButton_Right")
        if out then
            held.dropAt = held.dropAt or os.clock()
            if os.clock() - held.dropAt >= 2.0 and not held.dropped then
                held.dropped = true
                log("Player 2 dropped out (Select + B held)")
                runGame("p2DropOut", removePlayer2)
            end
        else
            held.dropAt, held.dropped = nil, nil
        end
    end)
    -- Any map change (mothership, another region, a mission load): take Player 2 out first.
    -- The second local player survives the trip but its controller doesn't, which left
    -- Player 2 uncontrollable and crashed the next Ctrl+Y / Start.
    if type(RegisterLoadMapPreHook) == "function" then
        local okH, errH = pcall(function()
            RegisterLoadMapPreHook(function()
                -- only when leaving a playable map (not again from the mothership / menus,
                -- where there's nothing to undo and touching game objects isn't safe)
                local wn = ""
                pcall(function() wn = nameOf(getWorld()) end)
                if state.trainerResetAll and not wn:find("/Menus/", 1, true) and not state.trResetDone then
                    state.trResetDone = true
                    local okR, errR = pcall(state.trainerResetAll)
                    if not okR then log("Map change: trainer reset failed: %s", tostring(errR)) end
                end
                if valid(state.p2) then
                    log("Map change: removing Player 2 first (press Start on pad 2 again after loading)")
                    local ok, err = pcall(removePlayer2)
                    if not ok then log("  remove failed: %s", tostring(err)) end
                end
                for _, fn in ipairs(state.worldResets) do pcall(fn) end
            end)
        end)
        log("Map-change guard: %s", okH and "on" or ("unavailable: " .. tostring(errH)))
    end
    local lastWorld = nil
    addTickJob("worldChangeGuard", 0.5, function()
        local w = getWorld()
        local name = w and nameOf(w) or nil
        if not name then return end
        if lastWorld and name ~= lastWorld then
            log("World changed: %s", name)
            for _, fn in ipairs(state.worldResets) do pcall(fn) end
            if not name:find("/Menus/", 1, true) then state.trResetDone = false end
            if state.p2 ~= nil and not valid(state.p2) then state.p2 = nil end
            -- a leftover second local player from the old map: remove it cleanly
            local statics = getStatics()
            local ok2, pc2 = pcall(function() return statics:GetPlayerController(w, 1) end)
            if ok2 and valid(pc2) and not valid(state.p2) then
                local ok, err = pcall(function() statics:RemovePlayer(pc2, true) end)
                log("  leftover Player 2 from the last map removed: %s", ok and "ok" or tostring(err))
            end
        end
        lastWorld = name
    end)
    addTickJob("mothershipCheck", 1.0, function()
        if not (CFG.END_SPLIT_ON_MOTHERSHIP and valid(state.p2)) then return end
        local w = getWorld()
        local name = w and nameOf(w) or ""
        if name:lower():find("mothership") then
            log("Mothership loaded: ending split screen")
            runGame("mothershipEnd", removePlayer2)
        end
    end)
    -- Player 2's weapon slot (icon + ammo) should read Player 2's own weapons.
    addTickJob("p2WeaponSlot", 1.0, function()
        if not valid(state.p2) then return end
        local eq = subObj(getPawn(state.p2), "m_pEquipmentManagerComponent")
        if not eq then return end
        for _, hud in ipairs(hudWidgetsOf(state.p2)) do
            local slotW = subObj(hud, "BPW_UI_Slot_Weapon")
            local cur = slotW and subObj(slotW, "m_pPlayerEquipmentManager")
            if slotW and not samePawn(cur, eq) then
                pcall(function() slotW.m_pPlayerEquipmentManager = eq end)
                if not state.slotLogged then
                    state.slotLogged = true
                    log("Player 2 weapon slot: pointed at Player 2's weapons (was %s)", cur and shortName(cur) or "nothing")
                end
            end
        end
    end)
end
-- Weapon icon per player. When the HUD is moved onto each player's half it is built a
-- second time: the game then updates a NEW active-slot widget (m_pActiveSlot), but the old
-- one is still the one on screen (inside SB_ActiveSlot), stuck on the Zap-O-Matic.
-- Put the live one back on screen.
do
    local logged = {}
    addTickJob("weaponIcons", 0.5, function()
        -- also in one player once the HUD has been moved (leaving rebuilds it the same way)
        if not (CFG.WEAPON_ICON_FIX and (valid(state.p2) or state.hudPlacedAt)) then return end
        for i, pc in ipairs({ player1Controller(), valid(state.p2) and state.p2 or nil }) do
            for _, hud in ipairs(hudWidgetsOf(pc)) do
                local slotW = subObj(hud, "BPW_UI_Slot_Weapon")
                local live = slotW and subObj(slotW, "m_pActiveSlot")
                local box = slotW and subObj(slotW, "SB_ActiveSlot")
                if live and box then
                    local okC, shown = pcall(function() return box:GetChildAt(0) end)
                    if not (okC and valid(shown) and keyOf(shown) == keyOf(live)) then
                        local ok1 = pcall(function() live:RemoveFromParent() end)
                        local ok2 = pcall(function() box:SetContent(live) end)
                        local okN, nowShown = pcall(function() return box:GetChildAt(0) end)
                        local fixed = okN and valid(nowShown) and keyOf(nowShown) == keyOf(live)
                        if not fixed then
                            pcall(function() slotW:SetActiveSlot(live) end)
                            okN, nowShown = pcall(function() return box:GetChildAt(0) end)
                            fixed = okN and valid(nowShown) and keyOf(nowShown) == keyOf(live)
                        end
                        local k = keyOf(slotW) or "?"
                        if (logged[k] or 0) < 3 then
                            logged[k] = (logged[k] or 0) + 1
                            log("Weapon icon P%d: big icon was %s, live one is %s -> fixed: %s", i,
                                okC and valid(shown) and shortName(shown) or "nothing", shortName(live), tostring(fixed))
                        end
                    end
                end
            end
        end
    end)
end


-- Player 2's probe gun: a missed probe is meant to come back after a short reload timer,
-- but for Player 2 it never does, so the gun runs dry. When it sits empty with nothing in
-- the air for a few seconds, reload it.
do
    local emptySince, lastLine = nil, nil
    addTickJob("p2ProbeReload", 0.5, function()
        if not (CFG.P2_PROBE_RELOAD and valid(state.p2)) then emptySince = nil return end
        local pawn = getPawn(state.p2)
        local eq = subObj(pawn, "m_pEquipmentManagerComponent")
        if not eq then return end
        local okW, w = pcall(function() return eq:GetCurrentWeapon() end)
        if not (okW and valid(w)) then
            local okL, ws = pcall(function() return eq:GetCurrentWeapons() end)
            local l = okL and arrayToList(ws) or {}
            w = l[1]
        end
        if not valid(w) then return end
        if not state.probeJobLogged then state.probeJobLogged = true; log("P2 probe gun watch: running (P2 holds %s)", shortName(w)) end
        if not nameOf(w):find("AnalProbe", 1, true) then emptySince = nil return end
        local okS, shots = pcall(function() return w:GetAvailableShotCount() end)
        local okM, maxS = pcall(function() return w:GetAvailableMaximumShotCount() end)
        local okA, inAir = pcall(function() return w:IsShotInAir() end)
        local okR, reloading = pcall(function() return w:IsReloading() end)
        local timers = {}
        pcall(function()
            for _, t in ipairs(arrayToList(w.m_fMissedReloadTimers)) do timers[#timers + 1] = string.format("%.2f", tonumber(t) or -1) end
        end)
        local line = string.format("shots=%s/%s inAir=%s reloading=%s missedTimers=[%s]",
            okS and tostring(shots) or "?", okM and tostring(maxS) or "?", okA and tostring(inAir) or "?",
            okR and tostring(reloading) or "?", table.concat(timers, ","))
        if line ~= lastLine and CFG.P2_PROBE_DEBUG then lastLine = line; log("P2 probe gun: %s", line) end
        local short = okS and okM and type(shots) == "number" and type(maxS) == "number" and shots < maxS
        -- A missed probe flies "back to the player" but the game checks against Player 1, so it
        -- hangs on Player 2 forever. Once a missed probe has been out a moment, finish its trip
        -- by moving it to Player 1 (where the game expects it); the gun then gets it back.
        -- The game gives a missed probe back after a short "missed shot" timer, but for
        -- Player 2 it often never starts one. When the gun is short and no timer is running,
        -- start them (one per missing probe): the game then puts the probes back itself.
        if short then
            local nTimers = #timers
            if nTimers == 0 then
                local now = os.clock()
                if now - (state.probeTimerAt or -100) > 1.0 then
                    state.probeTimerAt = now
                    local okT, err = pcall(function()
                        local arr = w.m_fMissedReloadTimers
                        local have = arr:GetArrayNum()
                        for i = 1, (maxS - shots) do arr[have + i] = CFG.P2_PROBE_TIMER or 0.6 end
                    end)
                    local after = 0
                    pcall(function() after = w.m_fMissedReloadTimers:GetArrayNum() end)
                    if CFG.P2_PROBE_DEBUG then log("P2 probe gun: started %d return timer(s): %s", after, okT and "ok" or tostring(err)) end
                end
            end
        end
        if false and short and okA and inAir then
            local p1pawn = getPawn(player1Controller())
            local okP, p1loc = pcall(function() return p1pawn:K2_GetActorLocation() end)
            local describeNow = CFG.P2_PROBE_DESCRIBE and os.clock() - (state.probeDescAt or -100) > 5
            if describeNow then state.probeDescAt = os.clock() end
            for _, pr in ipairs(FindAllOf("BP_ProjectileAnalProbe_C") or {}) do
                if valid(pr) and describeNow then
                    local f = {}
                    pcall(function() f[#f + 1] = "gun=" .. (valid(pr.m_pAnalProbe) and shortName(pr.m_pAnalProbe) or "none") end)
                    pcall(function() f[#f + 1] = "target=" .. (valid(pr.m_pTargetActor) and shortName(pr.m_pTargetActor) or "none") end)
                    pcall(function() f[#f + 1] = "parent=" .. (valid(pr:GetAttachParentActor()) and shortName(pr:GetAttachParentActor()) or "none") end)
                    pcall(function() f[#f + 1] = "hidden=" .. tostring(pr.bHidden) end)
                    pcall(function() f[#f + 1] = "flying=" .. tostring(pr.m_bIsFlying) end)
                    pcall(function()
                        local a, b = pr:K2_GetActorLocation(), getPawn(state.p2):K2_GetActorLocation()
                        f[#f + 1] = string.format("fromP2=%.0f", math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2))
                    end)
                    log("P2 probe gun: projectile %s %s", shortName(pr), table.concat(f, " "))
                end
                if valid(pr) then
                    local mine = false
                    pcall(function() mine = keyOf(pr.m_pAnalProbe) == keyOf(w) end)
                    local hasTarget = false
                    pcall(function() hasTarget = valid(pr.m_pTargetActor) end)
                    local flying = false
                    pcall(function() flying = pr.m_bIsFlying end)
                    local k = keyOf(pr) or "?"
                    -- probes loaded in the gun are attached to it: leave those alone
                    local loaded = false
                    pcall(function() loaded = keyOf(pr:GetAttachParentActor()) == keyOf(w) end)
                    local hidden = false
                    pcall(function() hidden = pr.bHidden end)
                    if mine and not hasTarget and not loaded and not hidden then
                        state.probeSeen = state.probeSeen or {}
                        state.probeSeen[k] = state.probeSeen[k] or os.clock()
                        if os.clock() - state.probeSeen[k] > (CFG.P2_PROBE_RETURN_AFTER or 1.5) and okP then
                            pcall(function() pr:K2_SetActorLocation(p1loc, false, {}, true) end)
                            state.probeSeen[k] = os.clock() + 2
                            if CFG.P2_PROBE_DEBUG then log("P2 probe gun: sent a missed probe home (flying=%s)", tostring(flying)) end
                        end
                    elseif state.probeSeen then
                        state.probeSeen[k] = nil
                    end
                end
            end
        end
        if short and not (okR and reloading) then
            local now = os.clock()
            emptySince = emptySince or now
            -- 3 s with nothing in the air, or 6 s even if the game still thinks one is flying
            if now - emptySince > 8.0 then
                emptySince = nil
                local ok, err = pcall(function() w:TriggerReload() end)
                log("P2 probe gun: missed probes never came back, reloading: %s", ok and "ok" or tostring(err))
            end
        else
            emptySince = nil
        end
    end)
end

-- Split screen: the bottom HUD row (D-pad hints on the left, weapon buttons on the right) is
-- laid out for a full-width screen and overlaps the radar / weapon icon on a half screen.
do
    local applied = {}
    addTickJob("hudRowShift", 1.0, function()
        local split = valid(state.p2)
        local list = { player1Controller(), state.p2 }
        -- Players 3 and 4 get the same squeeze (their screens are even narrower)
        for slot = 3, 4 do
            local x = state.extraPlayers and state.extraPlayers[slot]
            if valid(x) then list[#list + 1] = x end
        end
        for _, pc in pairs(list) do
            if valid(pc) then
                for _, hud in ipairs(hudWidgetsOf(pc)) do
                    local hints = subObj(hud, "BPW_UI_HUDGamepadHints")
                    local slotW = subObj(hud, "BPW_UI_Slot_Weapon")
                    local quick = slotW and subObj(slotW, "HB_QuickSlots")
                    local dxH = 0
                    local dxQ = split and -CFG.HUD_QUICKSLOT_SHIFT or 0
                    -- the hints row: squeezed toward its middle (left icons move right, right icons left)
                    if hints then
                        local sc = split and CFG.HUD_HINT_SCALE or 1.0
                        local hk = (keyOf(hints) or "?") .. "s"
                        if applied[hk] ~= sc then
                            pcall(function() hints:SetRenderTransformPivot({ X = 0.5, Y = 1.0 }) end)
                            pcall(function() hints:SetRenderScale({ X = sc, Y = sc }) end)
                            applied[hk] = sc
                        end
                    end
                    for _, e in ipairs({ { hints, dxH }, { quick, dxQ } }) do
                        local w, dx = e[1], e[2]
                        if w then
                            local k = keyOf(w) or "?"
                            if applied[k] ~= dx then
                                local ok = pcall(function() w:SetRenderTranslation({ X = dx, Y = 0 }) end)
                                applied[k] = dx
                                if not state.hudShiftLogged and dx ~= 0 then
                                    state.hudShiftLogged = true
                                    log("HUD bottom row: hints moved %+d px, weapon buttons %+d px: %s", dxH, dxQ, tostring(ok))
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- Alert ("!!") watch: logs the wanted system's seen/alert state and what each player's alert
-- widget shows, whenever it changes (to find why the bottom card won't stay on in co-op).
do
    local last, n = nil, 0
    addTickJob("alertWatch", 0.2, function()
        if not (CFG.ALERT_WATCH and valid(state.p2)) or n >= 600 then return end
        local gs = FindFirstOf("GameStateBase")
        local okM, mgr = pcall(function() return gs:GetAlertSystemManager() end)
        local parts = {}
        if okM and valid(mgr) then
            pcall(function() parts[#parts + 1] = "seen=" .. tostring(mgr:GetSeenState()) end)
            pcall(function() parts[#parts + 1] = "state=" .. tostring(mgr:GetCurrentAlertSystemState()) end)
            pcall(function() parts[#parts + 1] = "level=" .. tostring(mgr:GetCurrentResponseLevelIndex()) end)
            pcall(function() parts[#parts + 1] = "undetected=" .. tostring(mgr:IsUndetected()) end)
        end
        for i, pc in ipairs({ player1Controller(), state.p2 }) do
            for _, hud in ipairs(hudWidgetsOf(pc)) do
                local a = subObj(hud, "BPW_UI_HUD_AlertLevel")
                if a then
                    local vis = {}
                    for _, part in ipairs({ "Overlay_Seen", "Overlay_SeenHolobob", "SB_StealthAlert", "IMG_StealthAlert", "IMG_Seen" }) do
                        local w = subObj(a, part)
                        local okV, v = pcall(function() return w:GetVisibility() end)
                        local okO, o = pcall(function() return w:GetRenderOpacity() end)
                        vis[#vis + 1] = part:gsub("Overlay_", ""):gsub("IMG_", "") .. "=" .. (okV and tostring(v) or "?") .. "/" .. (okO and string.format("%.1f", o) or "?")
                    end
                    parts[#parts + 1] = "P" .. i .. "[" .. table.concat(vis, " ") .. "]"
                end
            end
        end
        local line = table.concat(parts, " ")
        if line ~= last then
            last = line
            n = n + 1
            log("Alert: %s", line)
        end
    end)
end

-- Co-op "!!" fix: the wanted system's "seen" state flips on/off every second in co-op (it
-- checks the players in turn), which throws the bottom card away and brings it back. Once seen,
-- it's held on for a few seconds after the last time either player was seen.
do
    local lastSeenAt = -100
    addTickJob("alertSeenHold", 0.0, function()
        if not (CFG.ALERT_SEEN_HOLD and valid(state.p2)) then return end
        local gs = FindFirstOf("GameStateBase")
        local okM, mgr = pcall(function() return gs:GetAlertSystemManager() end)
        if not (okM and valid(mgr)) then return end
        local okS, seen = pcall(function() return mgr:GetSeenState() end)
        if not okS then return end
        local now = os.clock()
        -- the alert state (calm / searching / fighting) flips the same way: keep the highest of
        -- the last few seconds while the wanted level is up
        local okA, aState = pcall(function() return mgr:GetCurrentAlertSystemState() end)
        if okA and type(aState) == "number" then
            if aState >= (state.heldAlert or 0) then state.heldAlert, state.heldAlertAt = aState, now
            elseif now - (state.heldAlertAt or -100) < CFG.ALERT_SEEN_HOLD then
                pcall(function() mgr.m_eCurrentAlertState = state.heldAlert end)
            else
                state.heldAlert = aState
            end
        end
        if seen and seen ~= 0 then lastSeenAt = now; state.seenValue = seen; state.seenHoldActive = true; return end
        -- both players share one wanted level, so "seen" is shared too: it stays on while the
        -- wanted level is up, and for a few seconds after either player was last seen
        local okL, level = pcall(function() return mgr:GetCurrentResponseLevelIndex() end)
        state.alertLevelNow = (okL and type(level) == "number") and level or 0
        local wanted = okL and type(level) == "number" and level > 0 and lastSeenAt > 0
        state.seenHoldActive = wanted or now - lastSeenAt < CFG.ALERT_SEEN_HOLD
        if not state.seenHoldActive then state.seenHigh = nil end
        if wanted or now - lastSeenAt < CFG.ALERT_SEEN_HOLD then
            pcall(function() mgr.m_currentSeenState = state.seenValue or 1 end)
            for _, pc in ipairs({ player1Controller(), state.p2 }) do
                for _, hud in ipairs(hudWidgetsOf(pc)) do
                    local a = subObj(hud, "BPW_UI_HUD_AlertLevel")
                    local o = a and subObj(a, "Overlay_Seen")
                    if o then pcall(function() o:SetVisibility(3) end) end
                end
            end
        end
    end)
end

-- Co-op "!!" card, at the card itself: the HUD tells the card how "seen" you are through
-- SetSeenLevel. While the seen hold is on (seen in the last few seconds, or wanted at all),
-- the card is never told a lower level than the highest it had, so it isn't thrown away.
do
    local hooked, tries, logged = false, 0, 0
    addTickJob("seenCardHook", 1.0, function()
        if hooked or not CFG.ALERT_CARD_HOOK or tries > 600 then return end
        tries = tries + 1
        local ok, err = pcall(function()
            RegisterHook("/Game/Blueprints/UI/HUD/BPW_UI_HUD_AlertLevel.BPW_UI_HUD_AlertLevel_C:SetSeenLevel", function(self, eState)
                local okG, v = pcall(function() return eState:get() end)
                if not (okG and type(v) == "number") then return end
                local coop = valid(state.p2)
                local out = v
                if coop then
                    local now = os.clock()
                    if v > 0 then
                        state.cardSeenAt = now
                        if not state.cardHigh or v > state.cardHigh then state.cardHigh = v end
                    end
                    -- held while either player was seen in the last few seconds, or while the
                    -- police / military are after you at all (both players share one wanted level)
                    local hold = state.cardHigh and (now - (state.cardSeenAt or -100) < CFG.ALERT_SEEN_HOLD
                                                     or (state.alertLevelNow or 0) > 0)
                    if hold and v < state.cardHigh and CFG.ALERT_CARD_SET then
                        out = state.cardHigh
                        local okS = pcall(function() eState:set(out) end)
                        if not okS and not state.cardSetFail then state.cardSetFail = true; log("Seen card: couldn't change the level") end
                    elseif not hold and v == 0 then
                        state.cardHigh = nil
                    end
                end
                if CFG.ALERT_WATCH and logged < 80 and coop and (out ~= v or logged < 20) then
                    logged = logged + 1
                    log("Seen card: told %d%s", v, out ~= v and string.format(" -> kept at %d", out) or "")
                end
            end)
        end)
        if ok then
            hooked = true
            log("Seen card: watching the card's level changes")
        elseif tries == 1 then
            log("Seen card: not hooked yet (%s); will retry", tostring(err))
        end
    end)
end


state.dotTurn = CFG.RADAR_DOT_TURN
state.dotMirror = CFG.RADAR_DOT_MIRROR
if Key.F11 ~= nil then
    RegisterKeyBind(Key.F11, { ModifierKey.CONTROL }, function()
        state.dotTurn = ((state.dotTurn or 0) + 90) % 360
        log("Partner radar dot: turned %d degrees", state.dotTurn)
    end)
    RegisterKeyBind(Key.F11, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        state.dotMirror = not state.dotMirror
        log("Partner radar dot: mirrored = %s", tostring(state.dotMirror))
    end)
end

-- Player 2's own crosshair gets the game's "locked on" signal (the yellow arcs), which the
-- game only sends for Player 1.
do
    local last = nil
    addTickJob("p2LockSignal", 0.1, function()
        if not (CFG.P2_LOCK_SIGNAL and valid(state.p2)) then last = nil; state.p2CrossCache = nil return end
        local pawn = getPawn(state.p2)
        local mental = subObj(pawn, "m_pMentalAbilityComponent")
        local has = (mental and subObj(mental, "m_pCurrentAimTarget")) ~= nil
        if not has then
            for _, w in ipairs(weaponsOf(pawn)) do
                local okA, arr = pcall(function() return w.m_apCurrentLockedTargets end)
                if okA and valid(arrayToList(arr)[1]) then has = true break end
            end
        end
        -- (re-sent every second while on: P2's crosshair widget is remade when the HUD moves,
        -- and a new one never heard the first signal)
        if has == last and not (has and os.clock() >= (state.p2LockResendAt or 0)) then return end
        state.p2LockResendAt = os.clock() + 1.0
        last = has
        local g = subObj(state.p2, "m_pGameplayToHud")
        if g then pcall(function() g.m_bWeaponAndAbilitySharedTarget = has end) end
        -- P2's crosshairs, found with one full widget search only when the cached ones are gone
        -- or every 10 s (a full search every second would hitch)
        local cache = state.p2CrossCache
        local stale = not cache or os.clock() >= (state.p2CrossScanAt or 0)
        if not stale then for _, w in ipairs(cache) do if not valid(w) then stale = true break end end end
        if stale then
            cache = {}
            state.p2CrossScanAt = os.clock() + 10.0
            for _, w in ipairs(FindAllOf("UserWidget") or {}) do
                local cn = valid(w) and shortName(w) or ""
                if cn:find("Crosshair") then
                    local okO, owner = pcall(function() return w:GetOwningPlayer() end)
                    if okO and samePawn(owner, state.p2) then cache[#cache + 1] = w end
                end
            end
            state.p2CrossCache = cache
        end
        for _, w in ipairs(cache) do
            if valid(w) then pcall(function() w:WeaponAndAbilitySharedTargetChanged(has) end) end
        end
    end)
end

------------------------------------------------------------------------------------------
-- Partner markers: a "P1" / "P2" tag over the other player's head (only on your own half),
-- and a dot for the other player on your radar.
------------------------------------------------------------------------------------------
do
    local tags = {}    -- viewer slot -> { widget, text }
    local dots = {}    -- viewer slot -> { img, canvas }
    onWorldChange(function() tags = {}; dots = {} end)
    local dotLogged = false
    local function makeTag(pc, label)
        local world = getWorld()
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local template = nil
        for _, w in ipairs(hudWidgetsOf(pc)) do
            local note = subObj(w, "BPW_HUD_TextNotification")
            if note then template = note break end
        end
        if not (world and valid(wbl) and template) then return nil end
        local w = wbl:Create(world, template:GetClass(), pc)
        local tree = subObj(w, "WidgetTree")
        local function newText(name, size)
            local t = tree and StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, FName(name))
            if not valid(t) then return nil end
            local c = label == "P1" and CFG.P1_COLOR or CFG.P2_COLOR
            pcall(function() t:SetColorAndOpacity({ SpecifiedColor = { R = c[1], G = c[2], B = c[3], A = 1 }, ColorUseRule = 0 }) end)
            pcall(function() t:SetShadowOffset({ X = 1, Y = 1 }) end)
            pcall(function() t:SetJustification(1) end)
            pcall(function() local f = t.Font; f.Size = size; t:SetFont(f) end)
            return t
        end
        local box = tree and StaticConstructObject(StaticFindObject("/Script/UMG.VerticalBox"), tree, FName("DAH2P_TagBox"))
        local text, dist = newText("DAH2P_Tag", CFG.TAG_SIZE), newText("DAH2P_TagDist", CFG.TAG_DIST_SIZE)
        if not (valid(box) and text and dist) then return nil end
        pcall(function() text:SetText(FText(label)) end)
        local icon = nil
        if CFG.TAG_SKIN_ICON then
            local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("DAH2P_TagSkin"))
            local sb = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName("DAH2P_TagSkinBox"))
            if valid(img) and valid(sb) then
                pcall(function() sb:SetWidthOverride(CFG.TAG_SKIN_ICON_SIZE); sb:SetHeightOverride(CFG.TAG_SKIN_ICON_SIZE) end)
                pcall(function() sb:AddChild(img) end)
                pcall(function() img:SetVisibility(2) end)
                local okS, sl = pcall(function() return box:AddChildToVerticalBox(sb) end)
                if okS and sl then pcall(function() sl:SetHorizontalAlignment(2) end) end
                icon = img
            end
        end
        for _, t in ipairs({ text, dist }) do
            local okS, sl = pcall(function() return box:AddChildToVerticalBox(t) end)
            if okS and sl then pcall(function() sl:SetHorizontalAlignment(2) end) end
        end
        pcall(function() tree.RootWidget = box end)
        pcall(function() w:AddToPlayerScreen(70) end)
        pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 1.0 }) end)
        return { widget = w, text = text, dist = dist, icon = icon }
    end
    -- which skin icon (icons-skins-N in the game's menu art) goes with a skin tag. Read from
    -- skin_icons.txt ("Tag.Name = N" per line) if it's there, else a guess from the skin list order.
    local iconMap = nil
    local function loadIconMap()
        if iconMap then return iconMap end
        iconMap = {}
        for _, path in ipairs({ "ue4ss\\Mods\\OverkillCoop\\skin_icons.txt", "Mods\\OverkillCoop\\skin_icons.txt" }) do
            local f = io.open(path, "r")
            if f then
                for line in f:lines() do
                    local tag, n = line:match("^%s*([^=#]-)%s*=%s*(%d+)")
                    if tag and n then iconMap[tag] = tonumber(n) end
                end
                f:close()
                log("Skin icons: read %s", path)
                break
            end
        end
        return iconMap
    end
    local skinSprites = {}
    local function skinSprite(n)
        if skinSprites[n] and valid(skinSprites[n]) then return skinSprites[n] end
        local path = string.format("/Game/UI/Textures/Menu/Frames/icons-skins-%d_png.icons-skins-%d_png", n, n)
        local sp = StaticFindObject(path)
        if not valid(sp) then pcall(function() sp = LoadAsset(path) end) end
        if valid(sp) then skinSprites[n] = sp; return sp end
        return nil
    end
    local iconLogged = {}
    local function skinIconIndex(pc)
        local ps = subObj(pc, "PlayerState")
        if not ps then return nil end
        local tag = tagNameOf(ps, "m_oSelectedSkinTag")
        -- Players 3 and 4 change only their body's look, kept here
        for slot = 3, 4 do
            local xp = state.extraPlayers and state.extraPlayers[slot]
            if valid(xp) and keyOf(xp) == keyOf(pc) and state.extraSkinName and state.extraSkinName["P" .. slot] then
                tag = state.extraSkinName["P" .. slot]
            end
        end
        if not tag or tag == "" or tag == "None" then tag = tagNameOf(ps, "m_oDefaultSkinTag") end
        if not tag then return nil end
        local map = loadIconMap()
        local n, how = map[tag], "skin_icons.txt"
        if not n then
            how = "guess from the skin list order"
            local list = loadSkinList()
            for i, name in ipairs(list) do
                if name == tag or tag:sub(-#name) == name or name:sub(-#tag) == tag then n = i; break end
            end
            n = n or 1
        end
        if not iconLogged[tag] then iconLogged[tag] = true; log("Skin icons: %s -> icons-skins-%d (%s)", tag, n, how) end
        return n, tag
    end
    local function updateSkinIcon(t, other)
        if not (t.icon and valid(t.icon)) then return end
        local n, tag = skinIconIndex(other)
        if not n or (t.iconN == n) then return end
        local sp = skinSprite(n)
        if not sp then return end
        t.iconN = n
        local ok = pcall(function() t.icon:SetBrushFromAtlasInterface(sp, false) end)
        if not ok then ok = pcall(function() t.icon:SetBrushResourceObject(sp) end) end
        pcall(function() t.icon:SetBrushSize({ X = CFG.TAG_SKIN_ICON_SIZE, Y = CFG.TAG_SKIN_ICON_SIZE }) end)
        pcall(function() t.icon:SetVisibility(ok and 4 or 2) end)
    end
    local function makeDot(pc)
        for _, hud in ipairs(hudWidgetsOf(pc)) do
            local mm = subObj(hud, "BPW_UI_Minimap")
            local radar = mm and subObj(mm, "BPW_UI_HUDRadar")
            local canvas = radar and subObj(radar, "m_pCanvasPanel")
            local tree = radar and subObj(radar, "WidgetTree")
            if canvas and tree then
                local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("DAH2P_PartnerDot"))
                if valid(img) then
                    local okS, sl = pcall(function() return canvas:AddChildToCanvas(img) end)
                    if okS and sl then
                        pcall(function() sl:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }) end)
                        pcall(function() sl:SetAlignment({ X = 0.5, Y = 0.5 }) end)
                        pcall(function() sl:SetSize({ X = CFG.RADAR_DOT_SIZE, Y = CFG.RADAR_DOT_SIZE }) end)
                        pcall(function() sl:SetZOrder(1000) end)
                        return { img = img, canvas = canvas, slot = sl, radar = radar }
                    end
                end
            end
        end
        return nil
    end
    addTickJob("partnerMarkers", 0, function()
        local players = { player1Controller(), state.p2 }
        if not (CFG.PARTNER_MARKERS and valid(players[1]) and valid(players[2])) then
            for k, t in pairs(tags) do if valid(t.widget) then pcall(function() t.widget:RemoveFromParent() end) end tags[k] = nil end
            for k, d in pairs(dots) do if valid(d.img) then pcall(function() d.img:RemoveFromParent() end) end dots[k] = nil end
            return
        end
        -- everyone sees a tag (and radar dot) for every other player, Players 3 and 4 too
        local pcs, ids = { players[1], players[2] }, { 1, 2 }
        for xs = 3, 4 do
            local xp = state.extraPlayers and state.extraPlayers[xs]
            if valid(xp) then pcs[xs] = xp; ids[#ids + 1] = xs end
        end
        local function colorFor(n)
            if n == 1 then return CFG.P1_COLOR elseif n == 2 then return CFG.P2_COLOR end
            return n == 3 and (CFG.P3_COLOR or { 1.0, 0.15, 0.15 }) or (CFG.P4_COLOR or { 0.2, 0.45, 1.0 })   -- P3 red, P4 blue
        end
        for k, t in pairs(tags) do
            if type(k) == "number" and k >= 10 and not (valid(pcs[k // 10]) and valid(pcs[k % 10])) then
                if valid(t.widget) then pcall(function() t.widget:RemoveFromParent() end) end
                tags[k] = nil
                local d = dots[k]
                if d and valid(d.img) then pcall(function() d.img:RemoveFromParent() end) end
                dots[k] = nil
            end
        end
        for _, vi in ipairs(ids) do for _, oi in ipairs(ids) do if vi ~= oi then
            local slot = vi * 10 + oi
            local viewer, other = pcs[vi], pcs[oi]
            local vp, op = getPawn(viewer), getPawn(other)
            if valid(vp) and valid(op) then
                local okA, a = pcall(function() return vp:K2_GetActorLocation() end)
                local okB, b = pcall(function() return op:K2_GetActorLocation() end)
                if okA and okB and a and b then
                    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                    -- tag over the partner's head
                    local t = tags[slot]
                    if not (t and valid(t.widget)) then local ok, m = pcall(makeTag, viewer, "P" .. oi); t = ok and m or nil; tags[slot] = t end
                    if t then
                        -- the skin icon: only after a skin change (and every 10 s just in case)
                        if CFG.TAG_SKIN_ICON and ((t.iconAt or 0) < os.clock() or t.skinGen ~= state.skinGen) then
                            t.iconAt = os.clock() + 10.0
                            t.skinGen = state.skinGen
                            later(0.4, "skinIcon", function() pcall(updateSkinIcon, t, other) end)
                        end
                        local shown = false
                        if dist <= CFG.PARTNER_TAG_RANGE then
                            local out = {}
                            local okP, on = pcall(function() return viewer:ProjectWorldLocationToScreen({ X = b.X, Y = b.Y, Z = b.Z + CFG.PARTNER_TAG_HEIGHT }, out, true) end)
                            local x, y = readXY(out)
                            if okP and on and type(x) == "number" then
                                pcall(function() t.widget:SetPositionInViewport({ X = x, Y = y }, true) end)
                                if CFG.TAG_SHOW_DISTANCE then
                                    local m = math.floor(dist / 100 + 0.5)
                                    if m ~= t.meters then
                                        t.meters = m
                                        pcall(function() t.dist:SetText(FText(string.format("%dm", m))) end)
                                    end
                                    local far = dist > CFG.PARTNER_LOD_RANGE
                                    if far ~= t.far then
                                        t.far = far
                                        local c = far and { 1.0, 0.15, 0.15 } or colorFor(oi)
                                        pcall(function() t.dist:SetColorAndOpacity({ SpecifiedColor = { R = c[1], G = c[2], B = c[3], A = 1 }, ColorUseRule = 0 }) end)
                                    end
                                end
                                shown = true
                            end
                        end
                        if shown ~= t.shown then
                            t.shown = shown
                            pcall(function() t.widget:SetVisibility(shown and 4 or 2) end)
                        end
                    end
                    -- dot on the radar
                    local d = CFG.PARTNER_RADAR_DOT and dots[slot] or nil
                    if not CFG.PARTNER_RADAR_DOT then dots[slot] = nil end
                    if d and (not valid(d.img) or not valid(d.canvas)) then d = nil end
                    if not d and CFG.PARTNER_RADAR_DOT then
                        local ok, m = pcall(makeDot, viewer)
                        d = ok and m or nil
                        dots[slot] = d
                        if not dotLogged then dotLogged = true; log("Partner radar dot: %s", d and "on" or ("not available: " .. tostring(m))) end
                    end
                    if d then
                        local okR, cr = pcall(function() return d.radar.m_fCanvasRadius end)
                        local okW, wr = pcall(function() return d.radar.m_fWorldRadius end)
                        cr = (okR and type(cr) == "number" and cr > 0) and cr or 100
                        wr = (okW and type(wr) == "number" and wr > 0) and wr or 5000
                        local scale = cr / wr
                        local okY, rot = pcall(function() return viewer:GetControlRotation() end)
                        local yaw = (okY and rot and rot.Yaw or 0) * math.pi / 180
                        local okAng, ang = pcall(function() return d.canvas.RenderTransform.Angle end)
                        local x, y
                        if okAng and type(ang) == "number" and math.abs(ang) > 0.01 then
                            x, y = dy * scale, -dx * scale                     -- the panel turns itself
                        else
                            local f = dx * math.cos(yaw) + dy * math.sin(yaw)     -- heading-up
                            local r = -dx * math.sin(yaw) + dy * math.cos(yaw)
                            x, y = r * scale, -f * scale
                        end
                        if state.dotMirror then x = -x end
                        local t = (state.dotTurn or 0) * math.pi / 180
                        x, y = x * math.cos(t) - y * math.sin(t), x * math.sin(t) + y * math.cos(t)
                        local len = math.sqrt(x * x + y * y)
                        local lim = cr * 0.92
                        if len > lim then x, y = x * lim / len, y * lim / len end
                        pcall(function() d.slot:SetPosition({ X = x, Y = y }) end)
                        local c = colorFor(oi)
                        pcall(function() d.img:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 }) end)
                    end
                end
            end
        end end end
    end)
end

-- The red "hurt" screen effect: the game shows it on every HUD when anyone is hit. Keep it
-- only on the half of the player who actually lost shield or health recently.
do
    local lastHit = {}     -- slot -> time of last loss
    local lastVal = {}     -- slot -> shield + health last tick
    local touched = false
    addTickJob("ownVignette", 0, function()
        if not (CFG.OWN_DAMAGE_VIGNETTE and valid(state.p2)) then
            if touched then   -- back to one player: give Player 1 the normal red screen again
                touched = false
                for _, hud in ipairs(hudWidgetsOf(player1Controller())) do
                    local vig = subObj(hud, "BPW_UI_HUDVignette")
                    if vig then pcall(function() vig:SetRenderOpacity(1.0) end) end
                end
            end
            return
        end
        touched = true
        local now = os.clock()
        for slot, pc in ipairs({ player1Controller(), state.p2 }) do
            local pawn = getPawn(pc)
            local v = (shieldRatio(pawn) or 0) + (healthRatio(pawn) or 0)
            if lastVal[slot] and v < lastVal[slot] - 0.0005 then lastHit[slot] = now end
            lastVal[slot] = v
            local hurt = lastHit[slot] and (now - lastHit[slot]) < CFG.VIGNETTE_HOLD_SECONDS
            -- the blue bar is the "health" players see (health itself stays full under the downed rules)
            local lowHealth = math.min(shieldRatio(pawn) or 1, healthRatio(pawn) or 1) < CFG.VIGNETTE_LOW
            for _, hud in ipairs(hudWidgetsOf(pc)) do
                local vig = subObj(hud, "BPW_UI_HUDVignette")
                if vig then pcall(function() vig:SetRenderOpacity((hurt or lowHealth) and 1.0 or 0.0) end) end
            end
        end
    end)
end

-- Radars: moving the HUDs onto each half disconnects the radar from the game's radar
-- manager, so it freezes. Feed it the manager's updates ourselves.
local radarState = {}   -- radar widget address -> "native" (reconnected itself) or "fed"
onWorldChange(function() radarState = {} end); state.onP2Leave(function() radarState = {} end)
state.resetRadarState = function() radarState = {} end
addTickJob("radarFeed", 0, function()
    -- keeps running after Player 2 leaves: the moved HUD stays disconnected until the level reloads
    if valid(state.p2) then state.hudMoved = true end
    if not (CFG.RADAR_FEED and state.hudMoved) then return end
    local pcs = { player1Controller(), state.p2 }
    local party = false
    for slot = 3, 4 do
        local xp = state.extraPlayers and state.extraPlayers[slot]
        if valid(xp) then
            party = true
            -- feeding Players 3 and 4's radars stopped them moving: off unless asked for
            if CFG.RADAR_FEED_EXTRA then pcs[#pcs + 1] = xp end
        end
    end
    if party ~= state.radarParty then state.radarParty = party; radarState = {} end   -- 3-4 players: look again
    for _, pc in ipairs(pcs) do
        for _, hud in ipairs(hudWidgetsOf(pc)) do
            local mm = subObj(hud, "BPW_UI_Minimap")
            local radar = mm and subObj(mm, "BPW_UI_HUDRadar")
            local key = radar and keyOf(radar)
            if key and state.hudPlacedAt and os.clock() - state.hudPlacedAt > 1.0 then
                local mgr = subObj(radar, "m_pRadarManager")
                -- with 3-4 players the small screens' radars keep a manager but stop updating: feed them all
                if party and radarState[key] == nil then radarState[key] = "fed"; log("Radar %s: fed by the mod (3-4 players)", shortName(hud)) end
                if CFG.RADAR_OWN_CENTER and radarState[key] ~= "fed" then radarState[key] = "fed" end
                if radarState[key] == nil then
                    -- first look after the move: if the radar found its manager again by itself it is
                    -- connected and must not be fed (double updates make the threat card jump)
                    radarState[key] = mgr and "native" or "fed"
                    log("Radar %s: %s", shortName(hud), radarState[key] == "native" and "reconnected by itself" or "fed by the mod")
                end
                if radarState[key] == "fed" then
                    if not mgr then
                        local gs = FindFirstOf("GameStateBase")
                        local okR, m = pcall(function() return gs:GetRadarManager() end)
                        if okR and valid(m) then pcall(function() radar.m_pRadarManager = m end); mgr = m end
                    end
                    if mgr then
                        -- each radar is worked out around the game's "primary player": make that
                        -- this radar's own player for the moment it is updated (both radars
                        -- followed Player 2 before)
                        local gs = CFG.RADAR_OWN_CENTER and FindFirstOf("GameStateBase") or nil
                        local own = getPawn(pc)
                        local was = nil
                        if gs and valid(own) then
                            pcall(function() was = gs.m_pLastKnownPrimaryPlayerPawn end)
                            pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = own end)
                        end
                        pcall(function() radar:OnRadarObjectsUpdated(mgr) end)
                        if gs and valid(was) then pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = was end) end
                        if CFG.RADAR_OWN_TURN then
                            local okR, r = pcall(function() return pc.PlayerCameraManager:GetCameraRotation() end)
                            if okR and r then pcall(function() radar:UpdateOrientation(r.Yaw) end) end
                        end
                    end
                end
            end
        end
    end
end)

------------------------------------------------------------------------------------------
-- Pickups for Player 2. The game only lets Player 1 collect brains and ammo, so anything
-- collectable that reaches Player 2 is moved onto Player 1 (shared inventory). Player 2's
-- own probes that come back and stick to Player 2 are cleared so the probe gun frees up.
------------------------------------------------------------------------------------------
do
    local pickupClasses = {}     -- class short name -> true
    local lastClassScan = -1000
    local cached = {}            -- list of actors to watch
    onWorldChange(function() cached = {} end); state.onP2Leave(function() cached = {} end)
    local function isPickupName(n)
        local l = n:lower()
        return (l:find("ammo") or l:find("brain"))
            and not l:find("saucer") and not l:find("explosive") and not l:find("weapon")
            and not l:find("widget") and not l:find("spawner") and not l:find("manager")
    end
    local function dist2(a, b)
        local okA, la = pcall(function() return a:K2_GetActorLocation() end)
        local okB, lb = pcall(function() return b:K2_GetActorLocation() end)
        if not (okA and okB and la and lb) then return math.huge end
        local dx, dy, dz = la.X - lb.X, la.Y - lb.Y, la.Z - lb.Z
        return dx * dx + dy * dy + dz * dz
    end
    local function refresh(now)
        if now - lastClassScan > 30 then
            lastClassScan = now
            for _, a in ipairs(FindAllOf("Actor") or {}) do
                local cn = classNameOf(a):match("([^%.]+)$")
                if cn and not pickupClasses[cn] and isPickupName(cn) then
                    pickupClasses[cn] = true
                    log("Pickups for Player 2: watching %s", cn)
                end
            end
        end
        local list = {}
        for cn in pairs(pickupClasses) do
            for _, a in ipairs(FindAllOf(cn) or {}) do if valid(a) then list[#list + 1] = a end end
        end
        for _, cn in ipairs({ "BP_ProjectileAnalProbe_C", "BP_AnalProbe_Link_C" }) do
            for _, a in ipairs(FindAllOf(cn) or {}) do
                if valid(a) then list[#list + 1] = { probe = a, cls = cn } end
            end
        end
        cached = list
    end
    local lastRefresh = -1000
    local probeSince = {}   -- probe address -> when it was first seen sitting on Player 2
    local probeLogged = {}
    onWorldChange(function() probeSince = {}; probeLogged = {} end); state.onP2Leave(function() probeSince = {}; probeLogged = {} end)
    addTickJob("p2Pickups", 0.1, function()
        if not (CFG.P2_PICKUPS and valid(state.p2)) then return end
        local p2pawn, p1pawn = getPawn(state.p2), getPawn(player1Controller())
        if not (valid(p2pawn) and valid(p1pawn)) then return end
        local now = os.clock()
        if now - lastRefresh > 1.0 then lastRefresh = now; pcall(refresh, now) end
        local r2 = CFG.P2_PICKUP_RADIUS * CFG.P2_PICKUP_RADIUS
        for _, e in ipairs(cached) do
            if type(e) == "table" and e.probe then
                local pr = e.probe
                local d2 = valid(pr) and dist2(pr, p2pawn) or math.huge
                if CFG.P2_PROBE_DEBUG and valid(pr) and d2 < 1000 * 1000 and now - (probeLogged[keyOf(pr) or ""] or -100) > 5 then
                    probeLogged[keyOf(pr) or ""] = now
                    local okP, parent = pcall(function() return pr:GetAttachParentActor() end)
                    log("Probe check: %s %.0f units from Player 2, attached to %s", e.cls, math.sqrt(d2),
                        okP and valid(parent) and shortName(parent) or "nothing")
                end
                local okPa, par = pcall(function() return pr:GetAttachParentActor() end)
                local inGun = okPa and valid(par) and classNameOf(par):find("AnalProbeBP") ~= nil
                if CFG.P2_PROBE_CLEAR and not inGun and valid(pr) and d2 < CFG.P2_PROBE_RADIUS * CFG.P2_PROBE_RADIUS then
                    local key = keyOf(pr)
                    probeSince[key] = probeSince[key] or now
                    if now - probeSince[key] > 1.0 then
                        probeSince[key] = nil
                        pcall(function() pr:K2_DestroyActor() end)
                        log("Pickups for Player 2: cleared a probe stuck on Player 2")
                    end
                elseif valid(pr) then
                    probeSince[keyOf(pr) or ""] = nil
                end
            elseif valid(e) and dist2(e, p2pawn) < r2 and dist2(e, p1pawn) > r2 then
                local okL, loc = pcall(function() return p1pawn:K2_GetActorLocation() end)
                if okL and loc then
                    pcall(function() e:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = loc.Z }, false, {}, true) end)
                end
            end
        end
    end)
end


local function dumpEverything()
    log("=== DUMP EVERYTHING -> dump_all.txt ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    local c1 = getP1(world, statics)
    local pawn = getPawn(c1)
    local lines = {}

    for _, f in ipairs({ "m_pDashComponent", "m_pJetpackPilotComponent", "m_pMentalAbilityComponent",
                         "m_pWeaponComponent", "m_pEquipmentManagerComponent", "m_pTargetComponent",
                         "m_pLockOnComponent", "m_pInteractionsComponent", "m_pCameraHandle",
                         "m_pPKSpringArmComponent" }) do
        appendClassDump(lines, "pawn." .. f, subObj(pawn, f))
    end
    appendClassDump(lines, "PlayerState (P1)", subObj(c1, "PlayerState"))
    appendClassDump(lines, "PlayerController (P1)", c1)

    -- the weapon currently held
    local eq = subObj(pawn, "m_pEquipmentManagerComponent")
    local okW, weapons = pcall(function() return eq:GetCurrentWeapons() end)
    if okW and weapons then
        for i, w in ipairs(arrayToList(weapons)) do
            if i > 3 then break end
            appendClassDump(lines, "CurrentWeapon[" .. i .. "]", w)
        end
    end
    appendClassDump(lines, "P1 pawn (all properties, for damage/aim components)", pawn)
    appendClassDump(lines, "P1 camera manager", subObj(c1, "PlayerCameraManager"))
    for _, cn in ipairs({ "GameplayToHud", "BFGGameplayToHud" }) do
        appendClassDump(lines, cn, FindFirstOf(cn))
    end

    -- each mental ability object
    local ment = subObj(pawn, "m_pMentalAbilityComponent")
    if ment then
        local okA, arr = pcall(function() return ment.m_aPlayerMentalAbilities end)
        local list = okA and arrayToList(arr) or {}
        lines[#lines + 1] = string.format("#### %d mental ability object(s)", #list)
        for i, a in ipairs(list) do
            if i > 8 then break end
            appendClassDump(lines, "MentalAbility[" .. i .. "]", a)
        end
    end

    -- world systems that decide what spawns / streams around the player
    local gs = FindFirstOf("GameStateBase")
    if valid(gs) then
        for _, fn in ipairs({ "GetVirtualCrowdManager", "GetTrafficCrowdManager", "GetActorActivationManager",
                              "GetBroadphaseManager", "GetStreamingLevelManager", "GetSpawnPoolManager",
                              "GetAISystem", "GetObjectRespawnManager" }) do
            local ok, obj = pcall(function() return gs[fn](gs) end)
            appendClassDump(lines, "GameState." .. fn, ok and obj or nil)
        end
    end

    do
        local g = FindFirstOf("GameStateBase")
        if valid(g) then
            local okT, tm = pcall(function() return g:GetTrafficCrowdManager() end)
            if okT and valid(tm) then
                appendClassDump(lines, "TrafficCrowdManager.m_pTrafficLodManager", subObj(tm, "m_pTrafficLodManager"))
                appendClassDump(lines, "TrafficCrowdManager.m_pRelativeDistanceCalculator", subObj(tm, "m_pRelativeDistanceCalculator"))
            end
        end
    end

    -- aim bridge: values of every property, P1 versus P2
    do
        local function valueDump(label, obj)
            lines[#lines + 1] = "######## VALUES " .. label .. " ########"
            if not valid(obj) then lines[#lines + 1] = "(nil / invalid)"; return end
            lines[#lines + 1] = "object: " .. tostring(obj:GetFullName())
            local okC, cls = pcall(function() return obj:GetClass() end)
            local depth = 0
            while okC and cls and depth < 6 do
                pcall(function()
                    cls:ForEachProperty(function(pr)
                        local okN, nm = pcall(function() return pr:GetFName():ToString() end)
                        if okN then
                            local okV, v = pcall(function() return obj[nm] end)
                            local str = tostring(v)
                            if okV and v ~= nil and type(v) ~= "number" and type(v) ~= "boolean" and type(v) ~= "string" then
                                local okX, x = pcall(function() return string.format("(%s, %s, %s)", tostring(v.X), tostring(v.Y), tostring(v.Z)) end)
                                if okX and tostring(v.X) ~= "nil" then str = x
                                else
                                    local okF, fn = pcall(function() return v:GetFullName() end)
                                    if okF then str = fn end
                                end
                            end
                            lines[#lines + 1] = string.format("  %s = %s", nm, okV and str or "<unreadable>")
                        end
                    end)
                end)
                local okS, sup = pcall(function() return cls:GetSuperStruct() end)
                if not okS or not sup or not valid(sup) then break end
                cls = sup
                depth = depth + 1
            end
        end
        valueDump("P1 controller.m_pGameplayToHud", subObj(c1, "m_pGameplayToHud"))
        if valid(state.p2) then
            valueDump("P2 controller.m_pGameplayToHud", subObj(state.p2, "m_pGameplayToHud"))
            valueDump("P2 camera manager", subObj(state.p2, "PlayerCameraManager"))
        end
        valueDump("P1 camera manager", subObj(c1, "PlayerCameraManager"))
        local pw = getPawn(state.p2)
        if valid(pw) then valueDump("P2 TargetComponent", subObj(pw, "m_pTargetComponent")) end
        valueDump("P1 TargetComponent", subObj(pawn, "m_pTargetComponent"))
    end

    -- layout of the skin data table rows
    local tables = FindAllOf("DataTable")
    if tables then
        for _, t in ipairs(tables) do
            if valid(t) then
                local n = nameOf(t)
                if n:find("DT_PlayerSkinList", 1, true) or n:find("DT_GameplayTags_PlayerSkins", 1, true) then
                    local okS, rs = pcall(function() return t.RowStruct end)
                    appendStructFields(lines, "RowStruct of " .. n, okS and rs or nil)
                end
            end
        end
    end
    loadSkinList() -- also prints the skin rows to the log

    writeDumpFile("all", lines)
end

------------------------------------------------------------------------------------------
-- Give Player 2 Player 1's upgrades/unlocks (so dash, jetpack, skate etc. match).
------------------------------------------------------------------------------------------
local function unlockSummary(pawn)
    local dashC = subObj(pawn, "m_pDashComponent")
    local jp = subObj(pawn, "m_pJetpackPilotComponent")
    local function q(obj, fn)
        if not obj then return "n/a" end
        local ok, v = pcall(function() return obj[fn](obj) end)
        return ok and tostring(v) or "err"
    end
    return string.format("dash2000=%s dash5000=%s echotron=%s jetpack=%s skate=%s",
        q(dashC, "IsThrustATron2000Unlocked"), q(dashC, "IsThrustATron5000Unlocked"),
        q(dashC, "IsEchotronRamjetsUnlocked"), q(jp, "IsJetpackEnabled"), q(jp, "GetSkateActive"))
end

local function syncProgressToP2()
    log("=== GIVE PLAYER 2 PLAYER 1'S UPGRADES/UNLOCKS ===")
    local world, statics = getWorld(), getStatics()
    if not (world and statics) then log("No world."); return end
    if not valid(state.p2) then log("No Player 2."); return end
    local c1 = getP1(world, statics)
    local p1ps, p2ps = subObj(c1, "PlayerState"), subObj(state.p2, "PlayerState")
    if not (p1ps and p2ps) then log("A PlayerState is missing."); return end

    log("  before: P1 %s", unlockSummary(getPawn(c1)))
    log("          P2 %s", unlockSummary(getPawn(state.p2)))
    for _, f in ipairs({ "m_pUpgradesTable", "m_pUpgrades", "m_pUnlocks" }) do
        local ok, v = pcall(function() return p1ps[f] end)
        if ok and valid(v) then
            local ok2, err = pcall(function() p2ps[f] = v end)
            log("  PlayerState.%s <- P1's object: %s", f, ok2 and "ok" or ("failed: " .. tostring(err)))
        else
            log("  PlayerState.%s: P1 value not readable", f)
        end
    end
    pcall(function() p2ps.m_iDNA = p1ps.m_iDNA end)

    local p2pawn = getPawn(state.p2)
    local jp = subObj(p2pawn, "m_pJetpackPilotComponent")
    if jp then
        pcall(function() jp:EnableJetpack() end)
        pcall(function() jp:EnableSkate() end)
    end
    local dc = subObj(p2pawn, "m_pDashComponent")
    if dc then pcall(function() dc:EnableDash() end) end
    log("  after:  P1 %s", unlockSummary(getPawn(c1)))
    log("          P2 %s", unlockSummary(p2pawn))
end
state.syncProgress = syncProgressToP2

------------------------------------------------------------------------------------------
-- Split-screen layout: top/bottom <-> left/right (Ctrl+O)
------------------------------------------------------------------------------------------
state.splitVertical = false

local function setSplitLayout(vertical)
    local gms = StaticFindObject("/Script/EngineSettings.Default__GameMapsSettings")
    if not valid(gms) then log("Split layout: GameMapsSettings not found."); return end
    local before = propStr(gms, "TwoPlayerSplitscreenLayout")
    local ok, err = pcall(function() gms.TwoPlayerSplitscreenLayout = vertical and 1 or 0 end)
    log("Split layout -> %s: %s (was %s, now %s)", vertical and "left/right" or "top/bottom",
        ok and "set" or ("failed: " .. tostring(err)), before, propStr(gms, "TwoPlayerSplitscreenLayout"))
    state.splitVertical = vertical
end
state.applySplit = function() setSplitLayout(CFG.SPLIT_LAYOUT == "vertical") end

------------------------------------------------------------------------------------------
-- Experiment (Ctrl+P): alternate which pawn the game treats as the "primary player", in case
-- NPC/traffic spawning and LOD follow it. Press again to stop (it resets to Player 1).
------------------------------------------------------------------------------------------
state.altPrimary = false
local altGen = 0
local altFlip = false

local function altPrimaryTick(gen)
    if not state.altPrimary or gen ~= altGen then return end
    if valid(state.p2) then
        local gs = FindFirstOf("GameStateBase")
        local a, b = getPawn(p1Ctrl()), getPawn(state.p2)
        if valid(gs) and valid(a) and valid(b) then
            altFlip = not altFlip
            pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = altFlip and b or a end)
        end
    end
    ExecuteWithDelay(CFG.ALT_PRIMARY_MS, function()
        runGame("altPrimary", function() altPrimaryTick(gen) end)
    end)
end

local function toggleAltPrimary()
    if state.altPrimary then
        state.altPrimary = false
        local gs = FindFirstOf("GameStateBase")
        local a = getPawn(p1Ctrl())
        if valid(gs) and valid(a) then pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = a end) end
        log("Alternating primary player: OFF (reset to Player 1)")
        return
    end
    if not valid(state.p2) then log("Spawn Player 2 first (Ctrl+Y)."); return end
    state.altPrimary = true
    altGen = altGen + 1
    log("Alternating primary player: ON every %d ms - watch whether far NPCs/traffic fill in near both players", CFG.ALT_PRIMARY_MS)
    local gen = altGen
    runGame("altPrimary", function() altPrimaryTick(gen) end)
end

RegisterKeyBind(Key.O, { ModifierKey.CONTROL }, function()
    runGame("splitLayout", function() setSplitLayout(not state.splitVertical) end)
end)

RegisterKeyBind(Key.P, { ModifierKey.CONTROL }, function()
    runGame("toggleAltPrimary", toggleAltPrimary)
end)

if Key.F2 ~= nil then
    RegisterKeyBind(Key.F2, { ModifierKey.CONTROL }, function() runGame("aimProbe", function() aimProbe(false) end) end)
end
if Key.F1 ~= nil then
    RegisterKeyBind(Key.F1, { ModifierKey.CONTROL }, function() runGame("aimApply", function() aimProbe(true) end) end)
end
if Key.F3 ~= nil then
    RegisterKeyBind(Key.F3, { ModifierKey.CONTROL }, function()
        runGame("forceLod", function() forceHighLod() end)
    end)
end
if Key.F9 ~= nil then
    -- Ctrl+F8 (or the Xbox Guide button, through the pad router DLL): "something looked wrong"
    RegisterKeyBind(Key.F8, { ModifierKey.CONTROL }, function() state.snapshot("Ctrl+F8") end)
    RegisterKeyBind(Key.F9, { ModifierKey.CONTROL }, function()
        runGame("dumpEverything", dumpEverything)
    end)
end

if Key.F4 ~= nil then
    RegisterKeyBind(Key.F4, { ModifierKey.CONTROL }, function()
        runGame("syncProgress", syncProgressToP2)
    end)
end

RegisterKeyBind(Key.M, { ModifierKey.CONTROL }, function()
    runGame("dumpGamepads", dumpGamepads)
end)

RegisterKeyBind(Key.V, { ModifierKey.CONTROL }, function()
    runGame("dumpVitals", dumpVitals)
end)

RegisterKeyBind(Key.K, { ModifierKey.CONTROL }, function()
    runGame("dumpDetailed", dumpDetailed)
end)

RegisterKeyBind(Key.L, { ModifierKey.CONTROL }, function()
    runGame("probeInput", function() probeInput(8) end)
end)

RegisterKeyBind(Key.H, { ModifierKey.CONTROL }, function()
    runGame("dumpWidgets", function()
        dumpWidgets()
        dumpHudInstances()
        dumpDataHub()
        -- Class layout of Player 1's HUD widget (to look into the swapped radars).
        local hw, hs = getWorld(), getStatics()
        if hw and hs then
            local hudList = hudWidgetsOf(getP1(hw, hs))
            if hudList[1] then dumpClassToFile("HUDWidget", hudList[1]) end
        end
    end)
end)

RegisterKeyBind(Key.J, { ModifierKey.CONTROL }, function()
    runGame("dumpClasses", dumpClasses)
end)

------------------------------------------------------------------------------------------
-- Pad features (with the DAHPadRouter xinput DLL, both pads are real controllers):
--   * Start on pad 2 spawns Player 2 (the DLL writes padrouter_spawn_request.txt)
--   * Select/View + L3 on either pad teleports the OTHER player next to you
------------------------------------------------------------------------------------------
local SPAWN_REQUEST_FILE = "padrouter_spawn_request.txt"
os.remove(SPAWN_REQUEST_FILE)  -- ignore a request left over from a previous session

os.remove("padrouter_dropout_request.txt")
addTickJob("padSpawn", 0.25, function()
    -- the DLL: Start held 2 s on pad 2 = Player 2 drops out
    local d = io.open("padrouter_dropout_request.txt", "r")
    if d then
        d:close()
        os.remove("padrouter_dropout_request.txt")
        if valid(state.p2) then
            log("Start held on pad 2: Player 2 drops out (Start again to rejoin)")
            runGame("padDropOut", removePlayer2)
        end
    end
    -- the DLL: Select + D-pad left/right on pad 2 = Player 2's skin (the D-pad is kept from the game)
    local sk = io.open("padrouter_skin_request.txt", "r")
    if sk then
        local text = sk:read("*a") or ""
        sk:close()
        os.remove("padrouter_skin_request.txt")
        for word, who in text:gmatch("(%a+)(%d?)") do
            local dir = word == "next" and 1 or (word == "prev" and -1 or nil)
            local slot = tonumber(who)
            if dir and slot and slot >= 3 then
                runGame("padSkin" .. slot, function() state.extraSkin(slot, dir) end)   -- pads 3 / 4
            elseif dir and valid(state.p2) and state.cycleP2Skin then
                runGame("padSkin", function() state.cycleP2Skin(dir) end)
            end
        end
    end
    if not CFG.PAD_SPAWN_ON_START then return end
    local f = io.open(SPAWN_REQUEST_FILE, "r")
    if not f then return end
    f:close()
    -- give the game a few seconds to finish taking the last Player 2 apart
    if state.p2LeftAt and os.clock() - state.p2LeftAt < 4.0 then
        if not state.rejoinWaitLogged then state.rejoinWaitLogged = true; log("Player 2 rejoin: waiting a moment after the last drop-out") end
        return
    end
    state.rejoinWaitLogged = nil
    os.remove(SPAWN_REQUEST_FILE)
    if valid(state.p2) or valid(state.p2Pending) then return end
    log("Start pressed on pad 2: spawning Player 2")
    runGame("padSpawn", function() if not (valid(state.p2) or valid(state.p2Pending)) then spawnPlayer2() end end)
end)

-- Game over -> Continue: the game makes new bodies but Player 2's controls don't follow.
-- When either player's body is replaced (the old one gone) without a map change, go back to
-- one player; Player 2 presses Start to come back in, which sets everything up fresh.
do
    local last = {}
    onWorldChange(function() last = {} end); state.onP2Leave(function() last = {} end)
    addTickJob("respawnWatch", 0.5, function()
        if not valid(state.p2) then last = {} return end
        for slot, pc in ipairs({ player1Controller(), state.p2 }) do
            local pw = getPawn(pc)
            local prev = last[slot]
            if valid(pw) then
                local k = keyOf(pw)
                if prev and prev.key ~= k and not valid(prev.pawn) and nameOf(pw):find("CharacterPlayer") then
                    last = {}
                    if CFG.GAMEOVER_KEEP_P2 == true then   -- off: after a game over it's one player again (Start on pad 2 to rejoin)
                        -- keep everyone in (taking Player 2 out in the middle of the game's
                        -- restart crashed): once the restart settles, everyone goes to
                        -- Player 1 and Player 2's screen is set up again on the new body
                        if state.respawnRegroupAt and os.clock() - state.respawnRegroupAt < 8 then return end
                        log("Player %d came back in a new body (game over / continue): keeping everyone, regrouping on Player 1 shortly", slot)
                        state.respawnRegroupAt = os.clock()
                        later(3.0, "respawnRegroup", function()
                            if not valid(state.p2) then return end
                            local pw2 = getPawn(state.p2)
                            if not (valid(pw2) and valid(getPawn(player1Controller()))) then return end
                            pcall(teleportP2ToP1, state.p2)
                            if state.partyFixBodies then pcall(state.partyFixBodies) end
                            if state.afterRespawn then
                                local okA, errA = pcall(state.afterRespawn)
                                log("Regroup after game over: %s", okA and "Player 2 set up on the new body" or ("setup error: " .. tostring(errA)))
                            end
                        end)
                    else
                        log("Player %d came back in a new body (game over / continue): back to one player in a moment, Start on pad 2 to rejoin", slot)
                        later(3.0, "respawnDropP2", function() runGame("respawnDropP2", removePlayer2) end)
                    end
                    return
                end
                last[slot] = { key = k, pawn = pw }
            end
        end
    end)
end

local teleportHeld = { p1 = false, p2 = false }

local function comboDown(controller)
    if not valid(controller) then return false end
    for _, k in ipairs(CFG.TELEPORT_COMBO) do
        if not kbDown(controller, k) then return false end
    end
    return true
end

local function teleportTick()
    if not valid(state.p2) then
        teleportHeld.p1, teleportHeld.p2 = false, false
        return
    end
    local p1 = p1Ctrl()
    local down1, down2 = comboDown(p1), comboDown(state.p2)
    if down1 and not teleportHeld.p1 then
        log("Pad 1 teleport combo: bringing everyone to Player 1")
        runGame("teleportP2ToP1", teleportP2ToP1)
        if state.partyBringTo then runGame("teleportPartyToP1", function() state.partyBringTo(p1) end) end
    end
    if down2 and not teleportHeld.p2 then
        log("Pad 2 teleport combo: bringing everyone to Player 2")
        runGame("teleportP1ToP2", teleportP1ToP2)
        if state.partyBringTo then runGame("teleportPartyToP2", function() state.partyBringTo(state.p2) end) end
    end
    -- Players 3 and 4 (their own pads, once the DLL routes them)
    for slot = 3, 4 do
        local pc = state.extraPlayers and state.extraPlayers[slot]
        local d = valid(pc) and comboDown(pc) or false
        if d and not teleportHeld["p" .. slot] then
            log("Pad %d teleport combo: bringing everyone to Player %d", slot, slot)
            runGame("teleportAllToP" .. slot, function()
                local me = getPawn(pc)
                local l = valid(me) and me:K2_GetActorLocation()
                if not l then return end
                for k, other in ipairs({ p1, state.p2 }) do
                    local op = valid(other) and getPawn(other)
                    if valid(op) then pcall(function() op:K2_SetActorLocation({ X = l.X + (k == 1 and 200 or -200), Y = l.Y, Z = l.Z + 40 }, false, {}, true) end) end
                end
                if state.partyBringTo then state.partyBringTo(pc) end
            end)
        end
        teleportHeld["p" .. slot] = d
    end
    teleportHeld.p1, teleportHeld.p2 = down1, down2
end

addTickJob("teleportCombo", 0.05, teleportTick)

-- The one LoopAsync: only does anything while no character tick is running the jobs.
LoopAsync(250, function()
    -- Once the character tick runs the jobs, this timer thread stops for good: any Lua running
    -- here at the same moment as the game thread is what corrupts UE4SS ("Ref was not function").
    if state.tickHooked then return true end
    runGame("tickJobs", function() runTickJobs(os.clock()) end)
    return false
end)

pcall(state.applySplit)
log("Loaded. Pads: Start on pad 2 = join | Select + L3 = bring the other player to you")
log("Keys: Ctrl+Y add Player 2 | Ctrl+I remove Player 2 | Ctrl+T bring P2 to P1 | Ctrl+Shift+T bring P1 to P2")
------------------------------------------------------------------------------------------
-- TRAINER MENU (Ctrl+Shift+M): drop-down lists clicked with the mouse. Player 1's controller
-- owns it; while it's open the mouse is shown and Player 1's game input pauses.
-- Uses the map's own sky actor (BP_Tool_Skydome: sun, sky light, height fog), the world
-- settings (gravity), global time dilation and the UFO landing sites.
------------------------------------------------------------------------------------------
;(function()
    local menu = nil            -- { widget, combos = { key = combo }, last = { key = text } }
    local SIZE_NAMES, applySize, UFO_ONLY_NAME
    -- (the Death Ray is left out: it's a beam fired straight down from under a saucer, so on foot it
    -- only charges at your feet)
    local UFO_CYCLE = { "BP_Weapon_UFO_DeathRay_C", "BP_Weapon_UFO_SonicBoom_C", "BP_Weapon_UFO_QuantumDecontructor_C" }
    local ufoSel, r3Held = {}, {}
    local saved = nil           -- the map's original sky settings, restored by "Game default"
    local function U(cn, tree, name) return StaticConstructObject(StaticFindObject("/Script/UMG." .. cn), tree, FName(name)) end
    local function skydome() return FindFirstOf("BP_Tool_Skydome_C") end
    local function sitesList()
        local list = {}
        for _, s_ in ipairs(FindAllOf("BP_UFOLandingSite_C") or {}) do if valid(s_) then list[#list + 1] = s_ end end
        return list
    end
    local function siteLabel(i, site)
        local tags = {}
        pcall(function() if site.m_bIsSpawn then tags[#tags + 1] = "start" end end)
        pcall(function() if site.m_bIsDefaultSite then tags[#tags + 1] = "default" end end)
        pcall(function() if not site.m_bUnlocked then tags[#tags + 1] = "locked" end end)
        local n = shortName(site):gsub("^BP_UFOLandingSite", "Pad ")
        return string.format("%d. %s%s", i, n, #tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or "")
    end

    local function saveSky(sd)
        if saved then return end
        saved = {}
        local sun = subObj(sd, "DirectionalLight")
        if sun then
            pcall(function() saved.sunRot = sun:K2_GetComponentRotation() end)
            pcall(function() saved.sunIntensity = sun.Intensity end)
            pcall(function() saved.sunColor = sun.LightColor end)
        end
        local sky = subObj(sd, "SkyLight")
        if sky then pcall(function() saved.skyIntensity = sky.Intensity end) end
        local fog = subObj(sd, "ExponentialHeightFog")
        if fog then pcall(function() saved.fogDensity = fog.FogDensity end) end
        log("Trainer: saved the map's sky (sun pitch %s, sun %s, sky light %s, fog %s)",
            saved.sunRot and string.format("%.1f", saved.sunRot.Pitch) or "?", tostring(saved.sunIntensity),
            tostring(saved.skyIntensity), tostring(saved.fogDensity))
    end

    -- name = { sun pitch (negative = above the horizon), sun brightness x, sky light x, sun colour }
    local TIMES = {
        { "Game default" },
        { "Dawn", -4, 0.5, 0.45, { R = 1.0, G = 0.55, B = 0.35 } },
        { "Morning", -25, 0.9, 0.85, { R = 1.0, G = 0.9, B = 0.8 } },
        { "Noon", -80, 1.0, 1.0, { R = 1.0, G = 1.0, B = 1.0 } },
        { "Afternoon", -45, 1.0, 1.0, { R = 1.0, G = 0.95, B = 0.85 } },
        { "Sunset", -6, 0.6, 0.5, { R = 1.0, G = 0.45, B = 0.2 } },
        { "Dusk", -1, 0.25, 0.3, { R = 0.8, G = 0.4, B = 0.45 } },
        { "Night (moonlight)", -50, 0.08, 0.12, { R = 0.45, G = 0.55, B = 1.0 } },
        { "Midnight (very dark)", -70, 0.02, 0.04, { R = 0.35, G = 0.45, B = 1.0 } },
    }
    local function applyTime(label)
        local sd = skydome()
        if not valid(sd) then log("Trainer: this map has no sky actor (BP_Tool_Skydome)."); return end
        saveSky(sd)
        local sun, sky = subObj(sd, "DirectionalLight"), subObj(sd, "SkyLight")
        local t = nil
        for _, e in ipairs(TIMES) do if e[1] == label then t = e end end
        if not t then return end
        if sun then pcall(function() sun:SetMobility(2) end) end
        if sky then pcall(function() sky:SetMobility(2) end) end
        if not t[2] then
            if sun and saved.sunRot then pcall(function() sun:K2_SetWorldRotation(saved.sunRot, false, {}, true) end) end
            if sun and saved.sunIntensity then pcall(function() sun:SetIntensity(saved.sunIntensity) end) end
            if sun and saved.sunColor then pcall(function() sun:SetLightColor(saved.sunColor, true) end) end
            if sky and saved.skyIntensity then pcall(function() sky:SetIntensity(saved.skyIntensity) end) end
        else
            local yaw = saved.sunRot and saved.sunRot.Yaw or 0
            local okR = pcall(function() sun:K2_SetWorldRotation({ Pitch = t[2], Yaw = yaw, Roll = 0 }, false, {}, true) end)
            local okI = pcall(function() sun:SetIntensity((saved.sunIntensity or 3.0) * t[3]) end)
            local c = t[5]
            pcall(function() sun:SetLightColor({ R = c.R, G = c.G, B = c.B, A = 1 }, true) end)
            pcall(function() sky:SetIntensity((saved.skyIntensity or 1.0) * t[4]) end)
            pcall(function() sky:RecaptureSky() end)
            log("Trainer: time of day %s (sun turned: %s, brightness: %s)", label, tostring(okR), tostring(okI))
        end
    end

    local FOGS = { { "Game default", nil }, { "Off", 0 }, { "Light", 0.5 }, { "Heavy", 4 }, { "Very heavy", 12 }, { "Pea soup", 40 } }
    local function applyFog(label)
        local sd = skydome()
        local fog = valid(sd) and subObj(sd, "ExponentialHeightFog") or nil
        if not fog then fog = FindFirstOf("ExponentialHeightFogComponent") end
        if not fog then log("Trainer: no height fog in this map."); return end
        if valid(sd) then saveSky(sd) end
        local base = (saved and saved.fogDensity) or 0.02
        for _, e in ipairs(FOGS) do
            if e[1] == label then
                local d = e[2] and (e[2] == 0 and 0 or base * e[2]) or base
                local ok = pcall(function() fog:SetFogDensity(d) end)
                log("Trainer: fog %s (density %.4f): %s", label, d, tostring(ok))
            end
        end
    end

    local SPEEDS = { { "Normal", 1.0 }, { "Slow motion 25%", 0.25 }, { "Half speed", 0.5 }, { "Fast 150%", 1.5 }, { "Double speed", 2.0 } }
    local function applySpeed(label)
        for _, e in ipairs(SPEEDS) do
            if e[1] == label then
                local ok = pcall(function() getStatics():SetGlobalTimeDilation(getWorld(), e[2]) end)
                log("Trainer: game speed %s: %s", label, tostring(ok))
            end
        end
    end

    local GRAVITY = { { "Normal", nil }, { "Moon (1/6)", -163 }, { "Low (half)", -490 }, { "Heavy (double)", -1960 } }
    local function applyGravity(label)
        local ws = nil
        pcall(function() ws = getWorld():K2_GetWorldSettings() end)
        if not valid(ws) then ws = FindFirstOf("WorldSettings") end
        if not valid(ws) then log("Trainer: no world settings."); return end
        for _, e in ipairs(GRAVITY) do
            if e[1] == label then
                pcall(function() ws.bGlobalGravitySet = e[2] ~= nil end)
                pcall(function() ws.GlobalGravityZ = e[2] or -980 end)
                log("Trainer: gravity %s", label)
            end
        end
    end

    local function teleportToSite(label)
        local i = tonumber(label:match("^(%d+)%."))
        local site = i and sitesList()[i]
        if not valid(site) then return end
        local okL, loc = pcall(function() return site:K2_GetActorLocation() end)
        if not okL then return end
        local p1pawn = getPawn(player1Controller())
        local dest = { X = loc.X, Y = loc.Y, Z = loc.Z + 150 }
        if valid(p1pawn) then teleportPawn(p1pawn, dest, { Pitch = 0, Yaw = 0, Roll = 0 }) end
        if valid(state.p2) and valid(getPawn(state.p2)) then
            teleportPawn(getPawn(state.p2), { X = dest.X + 200, Y = dest.Y, Z = dest.Z }, { Pitch = 0, Yaw = 0, Roll = 0 })
        end
        log("Trainer: teleported to %s", label)
    end
    local function setStartSite(label)
        local i = tonumber(label:match("^(%d+)%."))
        local list = sitesList()
        if not (i and list[i]) then return end
        for j, site in ipairs(list) do
            pcall(function() site.m_bIsSpawn = (j == i) end)
            pcall(function() site.m_bIsDefaultSite = (j == i) end)
            if j == i then pcall(function() site:SetUnlocked(true) end) end
        end
        log("Trainer: start pad set to %s (takes effect when the map loads again; experimental)", label)
    end

    -- Maps with real day/night sets (Rockwell: TimeOfDay/Rockwell_day01 and _night01, plus
    -- day/night crowds) switch them as streaming sub-levels.
    local function streamingLevels()
        local list = {}
        pcall(function()
            for _, l in ipairs(arrayToList(getWorld().StreamingLevels)) do
                local pkg = ""
                pcall(function() pkg = l.PackageNameToLoad:ToString() end)
                if pkg == "" then pcall(function() pkg = l:GetWorldAssetPackageName():ToString() end) end
                list[#list + 1] = { lvl = l, pkg = pkg }
            end
        end)
        return list
    end
    local function lightingSets()
        local r = {}
        for _, e in ipairs(streamingLevels()) do
            if e.pkg:find("/TimeOfDay/", 1, true) then r[#r + 1] = e end
        end
        return r
    end
    local function applyLightingSet(label)
        local sets = lightingSets()
        local pick = nil
        for _, e in ipairs(sets) do if (e.pkg:match("[^/]+$") or e.pkg) == label then pick = e end end
        if not pick then return end
        local lower = label:lower()
        local tod = (lower:find("night") and "night") or (lower:find("evening") and "evening")
            or (lower:find("morning") and "morning") or "day"
        for _, e in ipairs(sets) do
            local on = e == pick
            pcall(function() e.lvl:SetShouldBeLoaded(on) end)
            pcall(function() e.lvl:SetShouldBeVisible(on) end)
        end
        -- crowds made for a time of day (LD_CrowdLife_daytime / _Night / _DayAndEvening ...)
        local switched = {}
        for _, e in ipairs(streamingLevels()) do
            local n = (e.pkg:match("[^/]+$") or ""):lower()
            if e.pkg:find("/Crowd/", 1, true) and (n:find("day") or n:find("night") or n:find("evening") or n:find("morning")) then
                local on = n:find(tod, 1, true) ~= nil or (tod == "morning" and n:find("day", 1, true) ~= nil)
                pcall(function() e.lvl:SetShouldBeLoaded(on) end)
                pcall(function() e.lvl:SetShouldBeVisible(on) end)
                if on then switched[#switched + 1] = n end
            end
        end
        saved = nil -- the sky actor changes with the set
        log("Trainer: lighting set %s loaded (crowds: %s)", label, #switched > 0 and table.concat(switched, ", ") or "unchanged")
    end
    -- Another map's lighting set loaded into this map (experimental, can look strange).
    -- Every map's lighting sets the mod has seen (the list in overkill_coop_skies.txt grows as you
    -- visit maps), plus the ones the world scans found.
    local FOREIGN = {
        "/Game/Maps/Worlds/Rockwell/TimeOfDay/Rockwell_day01",
        "/Game/Maps/Worlds/Rockwell/TimeOfDay/Rockwell_night01",
        "/Game/Maps/Worlds/SantaModesta/TimeOfDay/SantaModesta_day01",
        "/Game/Maps/Worlds/SantaModesta/TimeOfDay/SantaModesta_Evening01",
        "/Game/Maps/Worlds/SantaModesta/TimeOfDay/SantaModesta_Night01",
        "/Game/Maps/Worlds/Area42/TimeOfDay/Area42_day01",
        "/Game/Maps/Worlds/Area42/TimeOfDay/Area42_evening01",
        "/Game/Maps/Worlds/Area42/TimeOfDay/Area42_morning01",
    }
    local function rememberSkies()
        local known = {}
        for _, f in ipairs(FOREIGN) do known[f] = true end
        pcall(function()
            local fh = io.open("overkill_coop_skies.txt", "r")
            if fh then
                for line in fh:lines() do
                    if line:find("/TimeOfDay/", 1, true) and not known[line] then known[line] = true; FOREIGN[#FOREIGN + 1] = line end
                end
                fh:close()
            end
        end)
        local added = false
        for _, e in ipairs(lightingSets()) do
            if not known[e.pkg] and e.pkg:find("^/Game/") then known[e.pkg] = true; FOREIGN[#FOREIGN + 1] = e.pkg; added = true end
        end
        if added then
            pcall(function()
                local fh = io.open("overkill_coop_skies.txt", "w")
                if fh then for _, f in ipairs(FOREIGN) do fh:write(f, "\n") end fh:close() end
            end)
        end
    end
    local foreignLoaded = nil
    onWorldChange(function() foreignLoaded = nil end)
    local function applyForeignSky(label)
        if label == "None" then
            if foreignLoaded then
                pcall(function() foreignLoaded:SetShouldBeVisible(false) end)
                pcall(function() foreignLoaded:SetShouldBeLoaded(false) end)
                foreignLoaded = nil
                for _, sd in ipairs(FindAllOf("BP_Tool_Skydome_C") or {}) do pcall(function() sd:SetActorHiddenInGame(false) end) end
                log("Trainer: other map's sky removed")
            end
            return
        end
        local path = nil
        for _, f in ipairs(FOREIGN) do if (f:match("[^/]+$")) == label then path = f end end
        if not path then return end
        if foreignLoaded then applyForeignSky("None") end
        local cls_ = StaticFindObject("/Script/Engine.Default__LevelStreamingDynamic")
        local okL, lvl = pcall(function()
            local outOk = {}
            return cls_:LoadLevelInstance(getWorld(), path, { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }, outOk)
        end)
        if okL and valid(lvl) then
            foreignLoaded = lvl
            saved = nil
            log("Trainer: loaded %s into this map (its sky and lights appear once it streams in)", label)
        else
            log("Trainer: could not load %s here: %s", label, tostring(lvl))
        end
    end

    -- NPC spawner: any person/animal type loaded on this map, spawned in front of Player 1.
    local spawned = {}
    onWorldChange(function() spawned = {} end)
    local function npcClasses()
        local list, seen = {}, {}
        -- the kinds of people/animals in this map right now (taken from the actors themselves)
        local classes = {}
        pcall(function()
            local out = {}
            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
            local got = {}
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                local okC, c = pcall(function() return v:GetClass() end)
                if okC and valid(c) then
                    local k = keyOf(c)
                    if k and not got[k] then got[k] = true; classes[#classes + 1] = c end
                end
            end
        end)
        for _, c in ipairs(classes) do
            local n = nameOf(c)
            if n:find("BP_", 1, true) and not n:find("Player", 1, true) and not n:find("SKEL_", 1, true)
                and not n:find("REINST", 1, true) then
                local short = n:match("([%w_]+)_C$") or n:match("[^%.]+$")
                if short and not seen[short] then seen[short] = c; list[#list + 1] = short end
            end
        end
        table.sort(list)
        return list, seen
    end
    do
        local lastMap = nil
        addTickJob("skyRemember", 5.0, function()
            local w = getWorld()
            local n = w and nameOf(w) or nil
            if n and n ~= lastMap then lastMap = n; pcall(rememberSkies) end
        end)
    end
    local function spawnNpc(label)
        local _, byName = npcClasses()
        local c = byName[label]
        if not valid(c) then log("Trainer: %s isn't loaded on this map", label); return end
        local pawn = getPawn(player1Controller())
        if not valid(pawn) then return end
        local okL, loc = pcall(function() return pawn:K2_GetActorLocation() end)
        local okF, fwd = pcall(function() return pawn:GetActorForwardVector() end)
        if not (okL and okF) then return end
        local n = tonumber(state.trSpawnCount or "3") or 3
        local statics, world = getStatics(), getWorld()
        local made = 0
        for i = 1, n do
            local side = (i - (n + 1) / 2) * 150
            local pos = { X = loc.X + fwd.X * 600 - fwd.Y * side, Y = loc.Y + fwd.Y * 600 + fwd.X * side, Z = loc.Z + 100 }
            local yaw = math.deg(math.atan(-fwd.Y, -fwd.X))
            local q = { X = 0, Y = 0, Z = math.sin(math.rad(yaw) / 2), W = math.cos(math.rad(yaw) / 2) }
            local xf = { Rotation = q, Translation = pos, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local ok, a = pcall(function()
                local d = statics:BeginDeferredActorSpawnFromClass(world, c, xf, 2, nil)
                return statics:FinishSpawningActor(d, xf)
            end)
            if ok and valid(a) then
                pcall(function() a:SpawnDefaultController() end)
                spawned[#spawned + 1] = a
                made = made + 1
            elseif i == 1 then
                log("Trainer: spawning %s failed: %s", label, tostring(a))
            end
        end
        log("Trainer: spawned %d x %s", made, label)
    end
    -- for other parts of the mod (raining people): spawn one of this map's NPC types at a spot
    state.npcTypes = function() return npcClasses() end
    state.spawnNpcAt = function(label, pos, yaw)
        local _, byName = npcClasses()
        local c = byName[label]
        if not valid(c) then return nil end
        local statics, world = getStatics(), getWorld()
        yaw = yaw or 0
        local q = { X = 0, Y = 0, Z = math.sin(math.rad(yaw) / 2), W = math.cos(math.rad(yaw) / 2) }
        local xf = { Rotation = q, Translation = pos, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local ok, a = pcall(function()
            local d = statics:BeginDeferredActorSpawnFromClass(world, c, xf, 2, nil)
            return statics:FinishSpawningActor(d, xf)
        end)
        if ok and valid(a) then
            pcall(function() a:SpawnDefaultController() end)
            spawned[#spawned + 1] = a
            return a
        end
        return nil
    end
    local function despawnAll(label)
        if label ~= "Remove the ones I spawned" then return end
        local n = 0
        for _, a in ipairs(spawned) do
            if valid(a) then pcall(function() a:K2_DestroyActor() end); n = n + 1 end
        end
        spawned = {}
        log("Trainer: removed %d spawned NPC(s)", n)
    end

    -- NPCs ignore both players: the game's own "invisible" state on each player, kept on.
    local function setInvisible(pawn, on)
        local inv = stat(pawn, "m_pIsInvisibleStat")
        if inv then
            pcall(function() inv:SetValue(on, true, true, false) end)
            pcall(function() inv:SetValue(on) end)
            pcall(function() inv.m_bValue = on end)
        end
        local ai = subObj(pawn, "m_pAITargetComponent")
        if ai then
            if on then pcall(function() ai:Deactivate() end) else pcall(function() ai:Activate(true) end) end
        end
    end
    local function applyIgnore(label)
        state.trIgnore = label
        local on = label == "On"
        for _, pc in ipairs({ player1Controller(), state.p2 }) do
            local pw = valid(pc) and getPawn(pc) or nil
            if valid(pw) then setInvisible(pw, on) end
        end
        log("Trainer: NPCs ignore both players: %s", on and "on" or "off")
    end
    -- checked often (a new body - map load, Player 2 joining - is hidden at once), fully
    -- re-applied every 2 s
    local ignoreDone, ignoreAll = {}, 0
    addTickJob("trainerIgnore", 0.1, function()
        if state.trIgnore ~= "On" then ignoreDone = {} return end
        local full = os.clock() - ignoreAll > 2.0
        if full then ignoreAll = os.clock() end
        local pcs = { player1Controller(), state.p2 }
        for slot = 3, 4 do local xp = state.extraPlayers and state.extraPlayers[slot]; if valid(xp) then pcs[#pcs + 1] = xp end end
        for _, pc in ipairs(pcs) do
            local pw = valid(pc) and getPawn(pc) or nil
            if valid(pw) and (full or not ignoreDone[keyOf(pw)]) then
                setInvisible(pw, true)
                ignoreDone[keyOf(pw)] = true
            end
        end
    end)
    -- No "turn around" / out-of-bounds death: the map's OOB trigger zones stop working.
    -- Optional: the invisible map-edge walls too (you can fall off the world).
    local function setOOB(off)
        -- these zones are shapes the game checks the player against (not walls), so they are
        -- removed for this visit of the map (they come back when the map loads again)
        if not off then return 0 end
        local n = 0
        for _, cn in ipairs({ "BP_MissionTriggerZone_CustomShape_OOB_C", "BFGMissionBoundaries" }) do
            for _, z in ipairs(FindAllOf(cn) or {}) do
                if valid(z) then
                    pcall(function() z.m_bIsOOBTrigger = false end)
                    pcall(function() z:SetActorTickEnabled(false) end)
                    pcall(function() z:K2_DestroyActor() end)
                    n = n + 1
                end
            end
        end
        -- the saucer's own "out of bounds" notifier
        for _, ufo in ipairs(FindAllOf("BP_PlayerUFO_C") or {}) do
            local c = subObj(ufo, "BP_SceneComponent_OOBNotifier")
            if c then pcall(function() c:SetComponentTickEnabled(false) end); pcall(function() c:Deactivate() end) end
        end
        pcall(function()
            local ws = getWorld():K2_GetWorldSettings()
            ws.bEnableWorldBoundsChecks = false
        end)
        return n
    end
    local function setEdgeWalls(off)
        local n = 0
        for _, v in ipairs(FindAllOf("BlockingVolume") or {}) do
            if valid(v) then pcall(function() v:SetActorEnableCollision(not off) end); n = n + 1 end
        end
        return n
    end
    local function applyBounds(label)
        state.trBounds = label
        local zones = setOOB(label ~= "Normal")
        local walls = setEdgeWalls(label == "No limits, no edge walls (can fall off the map)")
        log("Trainer: map limits %s (%d out-of-bounds zones, %d edge walls)", label, zones, walls)
    end
    addTickJob("trainerBounds", 3.0, function()
        if state.trBounds and state.trBounds ~= "Normal" then
            setOOB(true)
            if state.trBounds:find("edge walls") then setEdgeWalls(true) end
        end
    end)

    -- Holobob never runs out: its concentration drain is set to zero (both players).
    local holoSaved = {}
    onWorldChange(function() holoSaved = {} end)
    local HOLO_PROPS = { "m_fConcentrationDrainPerSecond", "m_fConcentrationDrainPerSecond_Disrupted",
        "m_fConcentrationDrainPerSecond_SuppressionAura", "m_fConcentrationPctOffsetSpeedWhileDisrupted" }
    local function setHolobob(on)
        local n = 0
        local list, seenH = {}, {}
        for _, cn in ipairs({ "BFGMentalAbility_Holobob", "BP_MentalAbility_Holobob_C" }) do
            for _, a in ipairs(FindAllOf(cn) or {}) do
                local k = keyOf(a)
                if k and not seenH[k] then seenH[k] = true; list[#list + 1] = a end
            end
        end
        for _, a in ipairs(list) do
            if valid(a) then
                local k = keyOf(a) or "?"
                if on and not holoSaved[k] then
                    holoSaved[k] = {}
                    for _, pn in ipairs(HOLO_PROPS) do pcall(function() holoSaved[k][pn] = a[pn] end) end
                end
                for _, pn in ipairs(HOLO_PROPS) do
                    if on then pcall(function() a[pn] = 0.0 end)
                    elseif holoSaved[k] and holoSaved[k][pn] then pcall(function() a[pn] = holoSaved[k][pn] end) end
                end
                n = n + 1
            end
        end
        if not on then holoSaved = {} end
        return n
    end
    local function applyHolobob(label)
        state.trHolo = label
        local n = setHolobob(label == "On")
        log("Trainer: Holobob never runs out: %s (%d disguise abilities)", label, n)
    end
    addTickJob("trainerHolobob", 2.0, function() if state.trHolo == "On" then setHolobob(true) end end)
    -- ...and never compromised: the disguise's "corrupted" / "disturbed" flags are kept clear.
    addTickJob("trainerHoloClean", 0.1, function()
        if state.trHolo ~= "On" then return end
        for _, cn in ipairs({ "BP_MentalAbility_Holobob_C" }) do
            for _, a in ipairs(FindAllOf(cn) or {}) do
                if valid(a) then
                    pcall(function() if a.m_bIsCorrupted then a.m_bIsCorrupted = false end end)
                    pcall(function() if a.bIsAbilityDisturbed then a.bIsAbilityDisturbed = false end end)
                    pcall(function() if a.bStartDisruptingAbility then a.bStartDisruptingAbility = false end end)
                    pcall(function() a.m_fCorruptionResetDelay = 0.0 end)
                end
            end
        end
    end)

    -- Research for infinite ammo: where the game keeps each weapon's ammo (dump_ammo.txt).
    local ammoDumped = false
    local function dumpAmmo()
        if ammoDumped then return end
        ammoDumped = true
        local lines = {}
        local eq = subObj(getPawn(player1Controller()), "m_pEquipmentManagerComponent")
        if eq then
            pcall(function()
                eq:ForEachProperty(function() end)
            end)
            local okC, c = pcall(function() return eq:GetClass() end)
            if okC then
                pcall(function()
                    c:ForEachProperty(function(p)
                        local pn = p:GetFName():ToString()
                        if pn == "m_aWeaponInfo" then
                            local okI, inner = pcall(function() return p:GetInner():GetStruct() end)
                            if okI and inner then appendStructFields(lines, "m_aWeaponInfo element", inner) end
                        end
                    end)
                end)
            end
            local okW, ws = pcall(function() return eq:GetCurrentWeapons() end)
            for i, w in ipairs(okW and arrayToList(ws) or {}) do
                if i <= 2 then
                    appendClassDump(lines, "weapon " .. shortName(w), w)
                    local okA, am = pcall(function() return eq:GetCurrentWeaponAmmo() end)
                    lines[#lines + 1] = "  GetCurrentWeaponAmmo = " .. (okA and tostring(am) or "?")
                end
            end
        end
        writeDumpFile("ammo", lines)
    end

    -- Infinite ammo: ray weapons stop draining, projectile weapons stop using ammo (both players).
    local WHO = { "Off", "Both players", "Player 1 only", "Player 2 only" }
    local function whoList(choice)
        local r = {}
        if choice == "Both players" or choice == "Player 1 only" or choice == "On" then r[#r + 1] = player1Controller() end
        if (choice == "Both players" or choice == "Player 2 only" or choice == "On") and valid(state.p2) then r[#r + 1] = state.p2 end
        if choice == "Both players" or choice == "On" then   -- "Both players" = everyone, Players 3 and 4 too
            for slot = 3, 4 do
                local xp = state.extraPlayers and state.extraPlayers[slot]
                if valid(xp) then r[#r + 1] = xp end
            end
        end
        return r
    end
    local ammoSaved = {}
    onWorldChange(function() ammoSaved = {} end)
    local AMMO_PROPS = { "m_fDischargeRate", "m_fAmmoConsumedPerShot" }
    local function playerWeapons(pcs)
        local list = {}
        for _, pc in ipairs(pcs or { player1Controller(), state.p2 }) do
            local eq = valid(pc) and subObj(getPawn(pc), "m_pEquipmentManagerComponent") or nil
            if eq then
                pcall(function()
                    eq.m_aWeaponInfo:ForEach(function(_, e)
                        local info = e:get()
                        local w = info.m_pWeaponInstance
                        if valid(w) then list[#list + 1] = w end
                    end)
                end)
                local okW, ws = pcall(function() return eq:GetCurrentWeapons() end)
                for _, w in ipairs(okW and arrayToList(ws) or {}) do if valid(w) then list[#list + 1] = w end end
            end
        end
        return list
    end
    local function setInfiniteAmmo(on, pcs)
        local n = 0
        for _, w in ipairs(on and playerWeapons(pcs) or {}) do
            local k = keyOf(w) or "?"
            if on and not ammoSaved[k] then
                ammoSaved[k] = { w = w }
                for _, pn in ipairs(AMMO_PROPS) do pcall(function() ammoSaved[k][pn] = w[pn] end) end
            end
            for _, pn in ipairs(AMMO_PROPS) do
                if on then pcall(function() if type(w[pn]) == "number" then w[pn] = 0.0 end end) end
            end
            n = n + 1
        end
        if not on then
            for _, e in pairs(ammoSaved) do
                for _, pn in ipairs(AMMO_PROPS) do
                    if e[pn] ~= nil and valid(e.w) then pcall(function() e.w[pn] = e[pn] end) end
                end
            end
            ammoSaved = {}
        end
        return n
    end
    local function applyAmmo(label)
        state.trAmmo = label
        setInfiniteAmmo(false)
        local n = label ~= "Off" and setInfiniteAmmo(true, whoList(label)) or 0
        log("Trainer: infinite ammo %s (%d weapons)", label, n)
    end
    addTickJob("trainerAmmo", 2.0, function()
        if state.trAmmo and state.trAmmo ~= "Off" then setInfiniteAmmo(true, whoList(state.trAmmo)) end
    end)

    -- Giant / tiny Crypto.
    local SIZES = { { "Normal", 1.0 }, { "Smallest (bug-sized)", 0.1 }, { "Tiny", 0.35 }, { "Small", 0.65 }, { "Big", 1.5 },
                    { "Giant (smashes buildings)", 4.0 }, { "Colossal (largest, smashes buildings)", 10.0 } }
    local function isGiant(l) return l and (l:find("^Giant") or l:find("^Colossal")) ~= nil end
    local function sizeOf(l) for _, e in ipairs(SIZES) do if e[1] == l then return e[2] end end return 1.0 end
    SIZE_NAMES = {}
    for _, e in ipairs(SIZES) do SIZE_NAMES[#SIZE_NAMES + 1] = e[1] end
    onWorldChange(function() state.sizeSpeed = {} end)
    function applySize(who, label)
        local pc = who == 1 and player1Controller() or state.p2
        local pw = valid(pc) and getPawn(pc) or nil
        if not valid(pw) then return end
        local f = 1.0
        for _, e in ipairs(SIZES) do if e[1] == label then f = e[2] end end
        if who == 1 then state.trSize1 = label else state.trSize2 = label end
        -- growing: lift first by the extra height, so a giant doesn't end up in the ground
        pcall(function()
            local old = pw:GetActorScale3D().Z or 1
            if f > old then
                local l = pw:K2_GetActorLocation()
                pw:K2_SetActorLocation({ X = l.X, Y = l.Y, Z = l.Z + 95 * (f - old) + 30 }, false, {}, true)
            end
        end)
        local ok = pcall(function() pw:SetActorScale3D({ X = f, Y = f, Z = f }) end)
        -- the game's own camera rig (a camera handle, not a spring arm): its offset goes with the
        -- size (giants: camera up and back out with them), and when tiny the camera isn't pulled
        -- into Crypto by walls and bumps
        pcall(function()
            local ch = subObj(pw, "m_pCameraHandle")
            if not ch then return end
            state.camBase = state.camBase or {}
            local ck = keyOf(ch)
            if not state.camBase[ck] then
                local so = ch.m_vSocketOffset
                state.camBase[ck] = { probe = ch.m_fProbeSize, test = ch.m_bDoCollisionTest,
                                      so = { X = so.X, Y = so.Y, Z = so.Z }, lock = ch.m_fLockOnArmLengthOverride }
            end
            local b0 = state.camBase[ck]
            local m = math.min(f, CFG.SIZE_CAMERA_MAX or 8)
            ch.m_fProbeSize = (b0.probe or 12) * math.min(1, math.max(0.1, f))
            ch.m_bDoCollisionTest = (f >= 0.5) and (b0.test ~= false) or false
            if f > 1 then
                -- further back: the socket offset pulls the camera out behind and above the giant
                ch.m_vSocketOffset = { X = (b0.so.X or 0) * m - 250 * (m - 1), Y = (b0.so.Y or 0) * m, Z = (b0.so.Z or 0) * m + 60 * (m - 1) }
            elseif f < 1 then
                ch.m_vSocketOffset = { X = b0.so.X or 0, Y = (b0.so.Y or 0) * math.max(0.3, f), Z = b0.so.Z or 0 }
            else
                ch.m_vSocketOffset = b0.so
            end
        end)
        -- tiny: the camera's collision probe shrinks too (it pulled the camera into Crypto's head)
        pcall(function()
            for _, arm in ipairs(arrayToList(pw:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SpringArmComponent")))) do
                state.armProbe = state.armProbe or {}
                local ak = keyOf(arm)
                if ak and not state.armProbe[ak] then
                    state.armProbe[ak] = { probe = arm.ProbeSize, len = arm.TargetArmLength, test = arm.bDoCollisionTest }
                end
                local b0 = state.armProbe[ak] or { probe = 12, len = 300, test = true }
                arm.ProbeSize = (b0.probe or 12) * math.min(1, math.max(0.1, f))
                -- the camera distance goes with size: far back for the giants, and the tiny sizes
                -- don't let walls and bumps pull the camera into Crypto (that looked first person)
                if f > 1 then arm.TargetArmLength = (b0.len or 300) * math.min(f, CFG.SIZE_CAMERA_MAX or 8)
                else arm.TargetArmLength = b0.len or 300 end
                arm.bDoCollisionTest = (f >= 0.5) and (b0.test ~= false) or false
            end
        end)
        -- giants move faster and see more (wider camera); everyone else normal
        local giant = isGiant(label)
        -- speed goes with size: giants fast (more so the bigger), small ones slower
        local speedMul = giant and CFG.GIANT_SPEED * math.sqrt(f / 4.0) or (f < 1 and math.max(0.3, math.sqrt(f)) or 1.0)
        local move = subObj(pw, "CharacterMovement")
        local pk = keyOf(pw) or "?"
        state.sizeSpeed = state.sizeSpeed or {}
        if move then
            if not state.sizeSpeed[pk] then
                state.sizeSpeed[pk] = {}
                for _, f in ipairs({ "MaxWalkSpeed", "MaxCustomMovementSpeed", "MaxFlySpeed", "MaxAcceleration",
                                     "JumpZVelocity", "MaxStepHeight", "BrakingDecelerationFlying", "BrakingDecelerationFalling",
                                     "MaxSwimSpeed", "MaxWalkSpeedCrouched" }) do
                    pcall(function() state.sizeSpeed[pk][f] = move[f] end)
                end
            end
            local scaleBy = {
                JumpZVelocity = math.sqrt(f),            -- jump height goes with size
                MaxStepHeight = f,                       -- giants step over cars and walls, tiny over pebbles
                BrakingDecelerationFlying = speedMul, BrakingDecelerationFalling = speedMul,
            }
            for fname, base in pairs(state.sizeSpeed[pk]) do
                if type(base) == "number" then pcall(function() move[fname] = base * (scaleBy[fname] or speedMul) end) end
            end
        end
        -- a giant walks through the saucer instead of getting stuck on it
        for _, ufo in ipairs(FindAllOf("BP_PlayerUFO_C") or {}) do
            if valid(ufo) then
                if giant then pcall(function() pw:MoveIgnoreActorAdd(ufo) end)
                else pcall(function() pw:MoveIgnoreActorRemove(ufo) end) end
            end
        end
        local mesh = subObj(pw, "Mesh")
        if mesh then pcall(function() mesh.GlobalAnimRateScale = giant and (1.0 / speedMul) or 1.0 end) end
        local cam = subObj(pc, "PlayerCameraManager")
        if cam then
            if giant then pcall(function() cam:SetFOV(CFG.GIANT_FOV) end) else pcall(function() cam:UnlockFOV() end) end
        end
        log("Trainer: Player %d size %s (x%.2f): %s", who, label, f, tostring(ok))
    end

    -- A giant Crypto walking into a building wrecks it (the game's own damage path).
    local buildings, buildingsAt, smashed, smashLogged = {}, -100, {}, 0
    onWorldChange(function() buildings, buildingsAt, smashed = {}, -100, {} end)
    local function buildingList()
        if os.clock() - buildingsAt < 10 then return buildings end
        buildingsAt = os.clock()
        buildings = {}
        pcall(function()
            local out = {}
            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/BFGCore.BFGActorBuilding"), out)
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) then buildings[#buildings + 1] = v end
            end
        end)
        return buildings
    end
    -- Damage something the way the game does (its own damage component), falling back to
    -- Unreal's damage. Returns how it was done.
    local function gameDamage(victim, amount, pw)
        local dt = StaticFindObject("/Script/Engine.DamageType")
        local exPart = subObj(victim, "m_pExplosiveComponent")
        if exPart then pcall(function() local d = exPart.m_pDamageType; if valid(d) then dt = d end end) end
        local dcs = {}
        local own = subObj(victim, "m_pDamageComponent")
        if own then dcs[#dcs + 1] = own end
        pcall(function()
            victim:GetClass():ForEachProperty(function(pp)
                local n = pp:GetFName():ToString()
                if n:lower():find("damage") and n ~= "m_pDamageComponent" then
                    local okV, v = pcall(function() return victim[n] end)
                    if okV and valid(v) and nameOf(v):find("Damage", 1, true) then dcs[#dcs + 1] = v end
                end
            end)
        end)
        local mine = subObj(pw, "m_pDamageComponent")
        if mine then dcs[#dcs + 1] = mine end
        local how = nil
        if amount >= 10000 then
            -- big hit: leave a sliver of health so the killing blow below goes through the game's
            -- own "died" path (death, explosion, wreck)
            local sc0 = subObj(victim, "m_pStatsComponent")
            local st0 = sc0 and subObj(sc0, "m_pHealthStat")
            if st0 then pcall(function() st0:SetValue(0.01, true, true, false) end) end
        end
        for _, dc in ipairs(dcs) do
            if pcall(function() dc:ApplyAndReportDamage(victim, amount, pw, pw, dt, true) end) then how = "game damage"; break end
        end
        if amount >= 10000 then
            -- wreck it for sure: health to zero through the game's own stat (so it dies / explodes)
            local sc = subObj(victim, "m_pStatsComponent")
            local st = sc and subObj(sc, "m_pHealthStat")
            if not st and sc then pcall(function() st = sc:GetHealthStat() end) end
            if st and pcall(function() st:SetValue(0.0, true, true, false) end) then how = (how or "") .. " + health 0" end
            local ex = subObj(victim, "m_pExplosiveComponent")
            if ex then
                -- the game's explosive part (cars, barrels, gas tanks): set it off now
                if pcall(function() ex:OnEventExplosion(false) end) then how = (how or "") .. " + exploded" end
            end
        end
        if how then return how end
        pcall(function() getStatics():ApplyDamage(victim, amount, pw:GetController(), pw, dt) end)
        return "unreal damage"
    end
    state.gameDamage = gameDamage
    local destrLogged = false
    local function paramsOf(path)
        local f = StaticFindObject(path)
        if not valid(f) then return "not found" end
        local parts = {}
        pcall(function() f:ForEachProperty(function(pp) parts[#parts + 1] = pp:GetClass():GetFName():ToString() .. " " .. pp:GetFName():ToString() end) end)
        return table.concat(parts, ", ")
    end
    local function smash(pw, b)
        local before = "?"
        pcall(function() before = tostring(b:GetDestructionState()) end)
        -- the building's own "destroy" (what cutscenes use: explosion, rubble, effects)
        local how = "none"
        if pcall(function() b:Cutscene_DestroyBuilding() end) then how = "building destroy" end
        local mid = "?"
        pcall(function() mid = tostring(b:GetDestructionState()) end)
        if mid == before then
            pcall(function() b:DestructionPhase_Explosion() end)
            how = how .. " + explosion phase"
            how = how .. ", " .. gameDamage(b, 100000.0, pw)
        end
        local after = "?"
        pcall(function() after = tostring(b:GetDestructionState()) end)
        if after == before then
            -- damage didn't do it: set the building's destruction state directly
            if not destrLogged then
                destrLogged = true
                log("Trainer: SetDestructionState(%s)  GetDestructionState(%s)",
                    paramsOf("/Script/BFGCore.BFGActorBuilding:SetDestructionState"), paramsOf("/Script/BFGCore.BFGActorBuilding:GetDestructionState"))
                local lines = {}
                appendClassDump(lines, "building " .. shortName(b), b)
                writeDumpFile("building", lines)
            end
            for _, v in ipairs({ 3, 2, 4, 1 }) do
                if pcall(function() b:SetDestructionState(v) end) then
                    pcall(function() after = tostring(b:GetDestructionState()) end)
                    if after ~= before then how = how .. ", destruction state " .. v; break end
                end
            end
        end
        state.bldLogged = (state.bldLogged or 0) + 1
        if state.bldLogged <= 8 then
            log("Trainer: giant hit %s: %s (state %s -> %s)", shortName(b), how, before, after)
        end
    end
    -- people and cars the giant walks into
    local function smashProps(pw, loc, r)
        pcall(function()
            local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            local out = {}
            local okO, err = pcall(function() ksl:SphereOverlapActors(getWorld(), loc, r, { 0, 1, 2, 3, 4, 5 }, nil, { pw }, out) end)
            state.propsLogN = (state.propsLogN or 0) + 1
            if state.propsLogN == 1 or state.propsLogN == 40 then
                local names = {}
                for i, a in ipairs(out) do if i <= 12 then local v = a; pcall(function() if not valid(v) then v = a:get() end end); names[#names + 1] = shortName(v) end end
                log("Trainer: giant prop check: %s, %d things nearby (%s)", okO and "ok" or tostring(err), #out, table.concat(names, ", "))
            end
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) then
                    local okC, cpath = pcall(function() return nameOf(v:GetClass()) end)
                    local k = keyOf(v) or "?"
                    if okC and not cpath:find("CharacterPlayer", 1, true) and not cpath:find("UFO", 1, true)
                        and not cpath:find("Building", 1, true) and not cpath:find("/Engine.", 1, true)
                        and not cpath:find("Landscape", 1, true) and not cpath:find("Road", 1, true) and not cpath:find("Terrain", 1, true)
                        and os.clock() - (smashed[k] or -100) > 2 then
                        smashed[k] = os.clock()
                        gameDamage(v, 100000.0, pw)
                        local root = v.RootComponent
                        pcall(function()
                            if root:IsSimulatingPhysics(FName("None")) then
                                local vl = v:K2_GetActorLocation()
                                root:AddImpulse({ X = (vl.X - loc.X) * 20, Y = (vl.Y - loc.Y) * 20, Z = 3000 }, FName("None"), true)
                            end
                        end)
                    end
                end
            end
        end)
    end
    local function smashAround(pw, loc, scale)
        local reach = 65 * scale
        -- boosting / skating fast as a giant: a sonic boom around you
        local okV, vel = pcall(function() return pw:GetVelocity() end)
        if okV and vel and (vel.X * vel.X + vel.Y * vel.Y) > 1400 * 1400 then reach = reach + 250 end
        pcall(function()
            local out = {}
            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Pawn"), out)
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) and keyOf(v) ~= keyOf(pw) then
                    local okC, cpath = pcall(function() return nameOf(v:GetClass()) end)
                    if okC and not cpath:find("CharacterPlayer", 1, true) and not cpath:find("UFO", 1, true) then
                        local okV, vl = pcall(function() return v:K2_GetActorLocation() end)
                        if okV then
                            local dx, dy, dz = vl.X - loc.X, vl.Y - loc.Y, vl.Z - loc.Z
                            local isCar = cpath:find("Vehicle", 1, true) ~= nil
                            local r = isCar and reach + 120 or reach
                            local k = keyOf(v) or "?"
                            if dx * dx + dy * dy < r * r and math.abs(dz) < 150 * scale and os.clock() - (smashed[k] or -100) > 2 then
                                smashed[k] = os.clock()
                                local how = gameDamage(v, isCar and 100000.0 or 1000.0, pw)
                                if not isCar then pcall(function() v:LaunchCharacter({ X = dx * 4, Y = dy * 4, Z = 600 }, true, true) end) end
                                if isCar then
                                    -- kick the car away like a toy, and learn how cars blow up (dump_vehicle.txt)
                                    pcall(function()
                                        local root = v.RootComponent
                                        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
                                        root:AddImpulse({ X = dx / len * 2500, Y = dy / len * 2500, Z = 1800 }, FName("None"), true)
                                    end)
                                    if state.vehDumpedV ~= 2 then
                                        state.vehDumpedV = 2
                                        state.vehDumped = true
                                        local lines = {}
                                        appendClassDump(lines, "vehicle " .. shortName(v), v)
                                        appendClassDump(lines, "its explosive part", subObj(v, "m_pExplosiveComponent"))
                                        appendClassDump(lines, "its damage part", subObj(v, "m_pDamageComponent"))
                                        writeDumpFile("vehicle", lines)
                                    end
                                end
                                if isCar then
                                    state.carLogN = (state.carLogN or 0) + 1
                                    if state.carLogN <= 6 then
                                        local hp = "?"
                                        pcall(function() hp = tostring(v.m_pStatsComponent.m_pHealthStat:GetValue()) end)
                                        log("Trainer: giant hit car %s: %s (health now %s, explodes on death %s)", shortName(v), how, hp,
                                            tostring(v.m_bExplodesOnDeath))
                                    end
                                elseif smashLogged < 12 then
                                    smashLogged = smashLogged + 1
                                    log("Trainer: giant squashed %s: %s", shortName(v), how)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
    addTickJob("trainerGiantSmash", 0.25, function()
        local who = {}
        if isGiant(state.trSize1) then who[#who + 1] = player1Controller() end
        if isGiant(state.trSize2) and valid(state.p2) then who[#who + 1] = state.p2 end
        if #who == 0 then return end
        local now = os.clock()
        for _, pc in ipairs(who) do
            local pw = getPawn(pc)
            local okL, loc = pcall(function() return pw:K2_GetActorLocation() end)
            if okL then
                local sz = sizeOf(pc == player1Controller() and state.trSize1 or state.trSize2)
                smashAround(pw, loc, sz)
                smashProps(pw, loc, 350 * sz / 4.0)
                for _, b in ipairs(buildingList()) do
                    if valid(b) then
                        local k = keyOf(b) or "?"
                        if now - (smashed[k] or -100) > 3 then
                            local okB, o, e = pcall(function()
                                local o_, e_ = {}, {}
                                b:GetActorBounds(true, o_, e_)
                                return o_, e_
                            end)
                            if okB and o and o.X and e and e.X then
                                local dx = math.max(0, math.abs(loc.X - o.X) - e.X)
                                local dy = math.max(0, math.abs(loc.Y - o.Y) - e.Y)
                                local dz = math.max(0, math.abs(loc.Z - o.Z) - e.Z)
                                local reach = 150 * math.max(1, sz / 4.0)
                                if dx < reach and dy < reach and dz < 200 * math.max(1, sz / 4.0) then
                                    smashed[k] = now
                                    smash(pw, b)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Weapons wreck buildings on foot (like the saucer's do): every shot that ends next to a
    -- building adds damage by what it was (a Quantum Deconstructor blast far more than a
    -- Disintegrator bolt); a building collapses once it has taken enough for its size.
    do
        -- by the projectile itself (whatever gun fired it: a Disintegrator firing Quantum
        -- Deconstructor shots wrecks like the saucer)
        local POWER = { { "QuantumDecon", 120 }, { "SonicBoom", 70 }, { "DeathRay", 60 }, { "BossAOE", 60 }, { "Tank", 50 },
                        { "Ion", 40 }, { "SAM", 40 }, { "Rocket", 40 }, { "Missile", 40 }, { "PowerSuit", 30 },
                        { "TeslaCoil", 30 }, { "Grenade", 25 }, { "Mortar", 35 }, { "MindLinkPulse", 15 },
                        { "MajesticAlienTech", 12 }, { "Disintegrat", 8 }, { "GunTurret", 6 }, { "Shotgun", 5 },
                        { "Rifle", 4 }, { "Pistol", 3 }, { "Probe", 3 }, { "Transmogrif", 10 } }
        local function powerOf(n)
            for _, e in ipairs(POWER) do if n:find(e[1]) then return e[2] end end
            return 10
        end
        local live, hits = {}, {}
        onWorldChange(function() live, hits = {}, {} end)
        state.trainerExtras = state.trainerExtras or {}
        state.trainerExtras[#state.trainerExtras + 1] = { key = "x_wreck", page = 4,
            label = "Weapons wreck buildings on foot (by how strong the shot is)",
            options = { "Off", "Players' shots", "Everyone's shots" },
            get = function() return state.trWreck or "Off" end,
            set = function(v) state.trWreck = v; log("Trainer: buildings wreckable on foot: %s", v) end }
        state.trainerExtras[#state.trainerExtras + 1] = { key = "x_ff", page = 4,
            label = "TEST  Enemies' friendly fire (their shots hurt each other)",
            options = { "Off", "On" },
            get = function() return state.trFF or "Off" end,
            set = function(v) state.trFF = v; log("Trainer: enemy friendly fire %s", v) end }
        addTickJob("footWreck", 0.1, function()
            local wreckOn = state.trWreck and state.trWreck ~= "Off"
            if not wreckOn and state.trFF ~= "On" then return end
            local p1, p2 = getPawn(player1Controller()), valid(state.p2) and getPawn(state.p2) or nil
            local seenNow = {}
            pcall(function()
                local arr = {}
                getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/BFGCore.BFGProjectile"), arr)
                for _, a in ipairs(arr) do
                    local v = a
                    if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                    if valid(v) and not nameOf(v):find("Beam") then
                        local k = keyOf(v)
                        local okL, l = pcall(function() return v:K2_GetActorLocation() end)
                        -- (the game keeps used shots in a pool: a shot "ends" when it is hidden again)
                        local okH, hid = pcall(function() return v.bHidden end)
                        hid = okH and hid == true
                        if k and okL and l and not hid then
                            seenNow[k] = true
                            local e = live[k]
                            if not e then
                                local okI, inst = pcall(function() return v:GetInstigator() end)
                                local mine = okI and valid(inst) and ((valid(p1) and keyOf(inst) == keyOf(p1)) or (p2 and keyOf(inst) == keyOf(p2)))
                                e = { n = shortName(v), mine = mine, by = mine and inst or p1, shooter = okI and inst or nil }
                                live[k] = e
                            end
                            -- a jump of more than 30 m in a tenth of a second: put back in the pool
                            if e.at and math.abs(l.X - e.at.X) + math.abs(l.Y - e.at.Y) + math.abs(l.Z - e.at.Z) > 3000 then
                                seenNow[k] = nil
                            else
                                e.prev = e.at
                                e.at = { X = l.X, Y = l.Y, Z = l.Z }
                            end
                        end
                    end
                end
            end)
            if not state.wreckDiag then
                state.wreckDiag = true
                local nb = #buildingList()
                local np = 0
                for _ in pairs(live) do np = np + 1 end
                log("Wreck: watching %d flying shots now, %d buildings on this map", np, nb)
            end
            -- shots that just ended: did they end at a building?
            for k, e in pairs(live) do
                if not seenNow[k] then
                    live[k] = nil
                    if (state.wreckEnds or 0) < 6 and e.at then
                        state.wreckEnds = (state.wreckEnds or 0) + 1
                        local best = nil
                        for _, b in ipairs(buildingList()) do
                            pcall(function()
                                local o_, e_ = {}, {}
                                b:GetActorBounds(false, o_, e_)
                                local d = math.max(0, math.abs(e.at.X - o_.X) - e_.X) + math.max(0, math.abs(e.at.Y - o_.Y) - e_.Y)
                                if not best or d < best then best = d end
                            end)
                        end
                        log("Wreck: shot %s ended (%s), nearest building %s cm away", e.n, e.mine and "a player's" or "an NPC's", best and string.format("%.0f", best) or "?")
                    end
                    -- where it most likely ended: one more step along its last movement
                    if e.at and e.prev then
                        e.at = { X = e.at.X + (e.at.X - e.prev.X), Y = e.at.Y + (e.at.Y - e.prev.Y), Z = e.at.Z + (e.at.Z - e.prev.Z) }
                    end
                    -- friendly fire: an NPC's shot that ended at another NPC hurts them
                    if state.trFF == "On" and e.at and not e.mine then
                        pcall(function()
                            local arr = {}
                            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), arr)
                            for _, a in ipairs(arr) do
                                local c = a
                                if type(a) == "userdata" and not valid(a) then pcall(function() c = a:get() end) end
                                if valid(c) and not state.notTargetable(c) and not (valid(e.shooter) and keyOf(c) == keyOf(e.shooter)) then
                                    local okC, cl = pcall(function() return c:K2_GetActorLocation() end)
                                    if okC and cl and math.abs(cl.X - e.at.X) + math.abs(cl.Y - e.at.Y) + math.abs(cl.Z - e.at.Z) < 260 then
                                        pcall(gameDamage, c, 2.0 * powerOf(e.n), valid(e.shooter) and e.shooter or c)
                                        if (state.ffLogs or 0) < 6 then
                                            state.ffLogs = (state.ffLogs or 0) + 1
                                            log("Friendly fire: %s hit %s", e.n, shortName(c))
                                        end
                                    end
                                end
                            end
                        end)
                    end
                    if wreckOn and e.at and (e.mine or state.trWreck == "Everyone's shots") then
                        for _, b in ipairs(buildingList()) do
                            if valid(b) then
                                local okB, o, ex = pcall(function()
                                    local o_, e_ = {}, {}
                                    b:GetActorBounds(false, o_, e_)
                                    return o_, e_
                                end)
                                if okB and o and o.X and ex and ex.X then
                                    local dx = math.max(0, math.abs(e.at.X - o.X) - ex.X)
                                    local dy = math.max(0, math.abs(e.at.Y - o.Y) - ex.Y)
                                    local dz = math.max(0, math.abs(e.at.Z - o.Z) - ex.Z)
                                    if dx < 250 and dy < 250 and dz < 250 then
                                        local bk = keyOf(b) or "?"
                                        local size = math.max(ex.X, ex.Y, ex.Z)
                                        local need = math.max(60, math.min(400, size / 10))
                                        hits[bk] = (hits[bk] or 0) + powerOf(e.n)
                                        if (state.wreckLogs or 0) < 10 then
                                            state.wreckLogs = (state.wreckLogs or 0) + 1
                                            log("Wreck: %s hit %s (%.0f / %.0f)", e.n, shortName(b), hits[bk], need)
                                        end
                                        if hits[bk] >= need then
                                            hits[bk] = 0
                                            pcall(smash, valid(e.by) and e.by or p1, b)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    -- Riot mode (experimental): every NPC is put on a different side (the game's m_faction),
    -- in turn, so the sides fight each other. Off puts everyone back.
    local riotSaved, riotFactions = {}, nil
    onWorldChange(function() riotSaved = {}; riotFactions = nil end)
    local function factionValues()
        if riotFactions then return riotFactions end
        riotFactions = {}
        local names = {}
        pcall(function()
            local prop = StaticFindObject("/Script/BFGCore.BFGNPCCharacter:m_faction")
            local en = prop:GetEnum()
            en:ForEachName(function(name, value)
                local n = name:ToString()
                names[#names + 1] = n .. "=" .. tostring(value)
                if not n:find("MAX") and not n:find("Max") and not n:find("None") then riotFactions[#riotFactions + 1] = value end
            end)
        end)
        if #riotFactions == 0 then
            -- no names readable: use only the sides NPCs on this map really have (made-up
            -- values crashed the game)
            local seen = {}
            pcall(function()
                local out = {}
                getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
                for _, a in ipairs(out) do
                    local v = a
                    if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                    local okF, f = pcall(function() return v.m_faction end)
                    if okF and type(f) == "number" and not seen[f] then seen[f] = true; riotFactions[#riotFactions + 1] = f end
                end
            end)
            table.sort(riotFactions)
        end
        log("Trainer: NPC sides: %s; using %s", #names > 0 and table.concat(names, ", ") or "names not readable",
            table.concat(riotFactions, ","))
        return riotFactions
    end
    local function riotTick(on)
        local vals = factionValues()
        local n = 0
        if on and #vals < 2 then log("Trainer: only one side on this map; riot needs at least two"); return 0 end
        pcall(function()
            local out = {}
            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) then
                    local okF, f = pcall(function() return v.m_faction end)
                    if okF and f ~= nil then
                        local k = keyOf(v) or "?"
                        if on then
                            if riotSaved[k] == nil then
                                riotSaved[k] = { a = v, f = f }
                                n = n + 1
                                local pick = vals[(n % #vals) + 1]
                                pcall(function() v.m_faction = pick end)
                            end
                        elseif riotSaved[k] then
                            pcall(function() v.m_faction = riotSaved[k].f end)
                        end
                    end
                end
            end
        end)
        if not on then riotSaved = {} end
        return n
    end
    state.factionValues = factionValues
    local function applyRiot(label)
        state.trRiot = label
        log("Trainer: riot mode %s (%d NPCs changed side)", label, riotTick(label == "On (experimental)"))
    end
    addTickJob("trainerRiot", 2.0, function() if state.trRiot == "On (experimental)" then riotTick(true) end end)

    -- God mode: both players' shield and health kept full.
    -- (also the engine's own "can't be damaged" switch: refilling alone missed one-hit deaths,
    -- e.g. a fall right after a size change)
    local godOn = {}
    addTickJob("trainerGod", 0.1, function()
        if not state.trGod or state.trGod == "Off" then
            for k, pw in pairs(godOn) do if valid(pw) then pcall(function() pw.bCanBeDamaged = true end) end godOn[k] = nil end
            return
        end
        local now = {}
        for _, pc in ipairs(whoList(state.trGod)) do
            local pw = valid(pc) and getPawn(pc) or nil
            if valid(pw) then
                now[keyOf(pw)] = true
                if not godOn[keyOf(pw)] then godOn[keyOf(pw)] = pw end
                pcall(function() pw.bCanBeDamaged = false end)
                local sh, hp = stat(pw, "m_pShieldStat"), stat(pw, "m_pHealthStat")
                if sh and (ratioOf(sh) or 1) < 0.999 then fillStat(sh, 1.0) end
                if hp and (ratioOf(hp) or 1) < 0.999 then fillStat(hp, 1.0) end
            end
        end
        for k, pw in pairs(godOn) do
            if not now[k] then if valid(pw) then pcall(function() pw.bCanBeDamaged = true end) end godOn[k] = nil end
        end
    end)
    local function applyGod(label) state.trGod = label; log("Trainer: god mode %s", label) end

    -- Jetpack never runs dry (boost-flying like DAH2's cheat): any fuel/energy stat on the
    -- player is kept full, and the jetpack's fuel use is set to zero.
    local fuelLogged = false
    local function fuelStats(pw)
        local list = {}
        local sc = subObj(pw, "m_pStatsComponent")
        -- every stat the component holds (they're named after what they are, e.g. "...Fuel")
        if sc then
            pcall(function()
                for _, st in ipairs(arrayToList(sc.m_aStatsCache)) do
                    if valid(st) then
                        local nm = (nameOf(st):match("[^%.]+$") or ""):lower()
                        if nm:find("fuel") or nm:find("jetpack") or nm:find("boost") or nm:find("thrust") then list[#list + 1] = { nm, st } end
                    end
                end
            end)
        end
        for _, holder in ipairs({ sc, pw }) do
            if holder then
                pcall(function()
                    holder:GetClass():ForEachProperty(function(pp) end)
                end)
                local okC, c = pcall(function() return holder:GetClass() end)
                local depth = 0
                while okC and valid(c) and depth < 6 do
                    pcall(function()
                        c:ForEachProperty(function(pp)
                            local n = pp:GetFName():ToString()
                            local ln = n:lower()
                            if ln:find("fuel") or ln:find("jetpack") or ln:find("boost") or ln:find("energy") then
                                local okV, v = pcall(function() return holder[n] end)
                                if okV and valid(v) and nameOf(v):find("Stat", 1, true) then list[#list + 1] = { n, v } end
                            end
                        end)
                    end)
                    local okS, sup = pcall(function() return c:GetSuperStruct() end)
                    if not okS then break end
                    c = sup; depth = depth + 1
                end
            end
        end
        return list
    end
    addTickJob("trainerFuel", 0.2, function()
        if state.trFuel ~= "On" then return end
        for _, pc in ipairs({ player1Controller(), state.p2 }) do
            local pw = valid(pc) and getPawn(pc) or nil
            if valid(pw) then
                local stats = fuelStats(pw)
                for _, e in ipairs(stats) do if (ratioOf(e[2]) or 1) < 0.999 then fillStat(e[2], 1.0) end end
                local jp = subObj(pw, "m_pJetpackPilotComponent")
                local params = jp and subObj(jp, "m_pJetpackParams") or nil
                for _, h in ipairs({ jp, params }) do
                    if h then
                        pcall(function()
                            h:GetClass():ForEachProperty(function(pp)
                                local n = pp:GetFName():ToString()
                                if n:lower():find("consumption") then pcall(function() if type(h[n]) == "number" then h[n] = 0.0 end end) end
                            end)
                        end)
                    end
                end
                if not fuelLogged then
                    fuelLogged = true
                    local all = {}
                    pcall(function()
                        for _, st in ipairs(arrayToList(subObj(pw, "m_pStatsComponent").m_aStatsCache)) do
                            all[#all + 1] = nameOf(st):match("[^%.]+$") or "?"
                        end
                    end)
                    log("Trainer: player stats: %s", table.concat(all, " | "))
                    local names = {}
                    for _, e in ipairs(stats) do names[#names + 1] = e[1] end
                    log("Trainer: jetpack fuel stats kept full: %s; params %s", #names > 0 and table.concat(names, ", ") or "none found",
                        params and shortName(params) or "none")
                end
            end
        end
    end)
    local function applyFuel(label) state.trFuel = label; log("Trainer: endless jetpack %s", label) end

    -- Bodyguards: people you hypnotize stay on your side for good (they can still die).
    local hypSaved = {}
    onWorldChange(function() hypSaved = {} end)
    local function setHypnosis(on)
        local n = 0
        for _, cn in ipairs({ "BFGMentalAbility_Hypnotize", "BP_MentalAbility_Hypnotize_C" }) do
            for _, a in ipairs(FindAllOf(cn) or {}) do
                if valid(a) then
                    local k = keyOf(a) or "?"
                    if on and not hypSaved[k] then
                        hypSaved[k] = { a = a }
                        pcall(function() hypSaved[k].d = a.m_fHypnotizeDuration end)
                        pcall(function() hypSaved[k].b = a.m_bDeactivateOnDamage end)
                        pcall(function() hypSaved[k].m = a.m_iMaxTargetCount end)
                    end
                    if on then
                        pcall(function() a.m_fHypnotizeDuration = 1000000.0 end)
                        pcall(function() a.m_bDeactivateOnDamage = false end)
                        pcall(function() if (a.m_iMaxTargetCount or 0) < 6 then a.m_iMaxTargetCount = 6 end end)
                    end
                    n = n + 1
                end
            end
        end
        if not on then
            for _, e in pairs(hypSaved) do
                if valid(e.a) then
                    if e.d then pcall(function() e.a.m_fHypnotizeDuration = e.d end) end
                    if e.b ~= nil then pcall(function() e.a.m_bDeactivateOnDamage = e.b end) end
                    if e.m then pcall(function() e.a.m_iMaxTargetCount = e.m end) end
                end
            end
            hypSaved = {}
        end
        return n
    end
    local function applyHyp(label)
        state.trHyp = label
        log("Trainer: permanent bodyguards %s (%d hypnosis abilities)", label, setHypnosis(label == "On"))
    end
    addTickJob("trainerHyp", 2.0, function() if state.trHyp == "On" then setHypnosis(true) end end)

    -- Research: write the Holobob and Hypnotize abilities' layouts once (dump_abilities.txt),
    -- for "Holobob never compromised".
    local abilDumped = false
    onWorldChange(function() abilDumped = false end)
    local function dumpAbilities()
        if abilDumped then return end
        abilDumped = true
        local lines = {}
        for _, cn in ipairs({ "BP_MentalAbility_Holobob_C", "BP_MentalAbility_Hypnotize_C" }) do
            local a = FindFirstOf(cn)
            appendClassDump(lines, cn, a)
            if valid(a) then
                pcall(function()
                    local c = a:GetClass()
                    local depth = 0
                    while valid(c) and depth < 5 do
                        c:ForEachProperty(function(pp)
                            local n = pp:GetFName():ToString()
                            local t = pp:GetClass():GetFName():ToString()
                            if t == "FloatProperty" or t == "BoolProperty" or t == "IntProperty" or t == "ByteProperty" then
                                local okV, v = pcall(function() return a[n] end)
                                if okV then lines[#lines + 1] = "    = " .. n .. " " .. tostring(v) end
                            end
                        end)
                        c = c:GetSuperStruct(); depth = depth + 1
                    end
                end)
            end
        end
        writeDumpFile("abilities", lines)
        -- research for riot mode: how NPCs pick sides (a few NPCs, their controllers, AI parts)
        local npcLines, done = {}, {}
        pcall(function()
            local out = {}
            getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
            for _, a in ipairs(out) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                local cn = valid(v) and shortName(v):gsub("_%d+$", "") or ""
                local okP, path = pcall(function() return nameOf(v:GetClass()) end)
                local isPerson = okP and path:find("/Character/", 1, true) and not path:find("Animal", 1, true)
                if isPerson and cn ~= "" and not cn:find("Player") and not done[cn] and #npcLines < 20000 then
                    local n = 0
                    for _ in pairs(done) do n = n + 1 end
                    if n < 3 then
                        done[cn] = true
                        appendClassDump(npcLines, "NPC " .. cn, v)
                        local okC, ctrl = pcall(function() return v.Controller end)
                        appendClassDump(npcLines, "its controller", okC and ctrl or nil)
                    end
                end
            end
        end)
        writeDumpFile("npc", npcLines)
        -- research for the bottom "!!" alert card: both players' alert widgets
        local al = {}
        for i, pc in ipairs({ player1Controller(), state.p2 }) do
            if valid(pc) then
                for _, hud in ipairs(hudWidgetsOf(pc)) do
                    local a = subObj(hud, "BPW_UI_HUD_AlertLevel")
                    if a then
                        appendClassDump(al, "P" .. i .. " alert widget", a)
                        pcall(function()
                            local c = a:GetClass()
                            local depth = 0
                            while valid(c) and depth < 4 do
                                c:ForEachProperty(function(pp)
                                    local n = pp:GetFName():ToString()
                                    local pt = pp:GetClass():GetFName():ToString()
                                    local simple = pt == "FloatProperty" or pt == "IntProperty" or pt == "BoolProperty"
                                        or pt == "ByteProperty" or pt == "ObjectProperty"
                                    local okV, v = false, nil
                                    if simple then okV, v = pcall(function() return a[n] end) end
                                    if okV then
                                        if type(v) ~= "userdata" then al[#al + 1] = "    = " .. n .. " " .. tostring(v)
                                        elseif valid(v) then al[#al + 1] = "    = " .. n .. " -> " .. shortName(v) end
                                    end
                                end)
                                c = c:GetSuperStruct(); depth = depth + 1
                            end
                        end)
                    end
                end
            end
        end
        writeDumpFile("alertwidget", al)
    end

    -- Saucer weapons on foot (experimental): each of Crypto's guns is swapped for a saucer
    -- weapon in the same slot. Zap-O-Matic -> Sonic Boom, Disintegrator -> Death Ray,
    -- Ion Detonator -> Quantum Deconstructor (the probe keeps its gun: no saucer version exists).
    local UFO_FOR = {
        { "Zap-O-Matic", "BP_Weapon_UFO_SonicBoom_C" },
        { "DisintegratorRay", "BP_Weapon_UFO_DeathRay_C" },
        { "IonDetonator", "BP_Weapon_UFO_QuantumDecontructor_C" },
    }
    local ufoSwaps = {}
    onWorldChange(function() ufoSwaps = {} end)
    local paramsLogged = false
    local function fnParams(path)
        local f = StaticFindObject(path)
        if not valid(f) then return "not found" end
        local parts = {}
        pcall(function() f:ForEachProperty(function(pp) parts[#parts + 1] = pp:GetClass():GetFName():ToString() .. " " .. pp:GetFName():ToString() end) end)
        return table.concat(parts, ", ")
    end
    local function tryCalls(label, shapes)
        for _, fn in ipairs(shapes) do
            local ok, err = pcall(fn)
            if ok then return true end
        end
        return false
    end
    -- How it works now: the game keeps equipping Crypto's own guns as usual (switching works
    -- normally); whatever gun is in hand is swapped, in the "equipped" list only, for its saucer
    -- version (the probe gun gets the last saucer weapon used). Nothing else is changed, so
    -- turning it off just puts the real gun back in hand.
    local ufoMade = {}      -- pawn key -> { [ufoName] = actor }
    local ufoLast = {}      -- pawn key -> ufoName last used
    local ufoOrig = {}      -- pawn key -> original gun now hidden
    onWorldChange(function() ufoMade, ufoLast, ufoOrig = {}, {}, {} end)
    local function ufoClassFor(ufoName)
        local short = ufoName:gsub("_C$", "")
        local path = "/Game/Blueprints/Weapon/UFO/" .. short .. "." .. ufoName
        local c = StaticFindObject(path)
        if not valid(c) and type(LoadAsset) == "function" then
            pcall(function() LoadAsset("/Game/Blueprints/Weapon/UFO/" .. short) end)
            c = StaticFindObject(path)
        end
        if not valid(c) then
            local inst = FindFirstOf(ufoName)
            if valid(inst) then c = inst:GetClass() end
        end
        return valid(c) and c or nil
    end
    local function makeUfo(pawn, eq, ufoName, near)
        local pk = keyOf(pawn) or "?"
        ufoMade[pk] = ufoMade[pk] or {}
        local have = ufoMade[pk][ufoName]
        if valid(have) then return have end
        local c = ufoClassFor(ufoName)
        if not c then log("Trainer: %s isn't loaded", ufoName); return nil end
        local okL, loc = pcall(function() return near:K2_GetActorLocation() end)
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = okL and loc or { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local statics, world = getStatics(), getWorld()
        local ok, w = pcall(function()
            local d = statics:BeginDeferredActorSpawnFromClass(world, c, xf, 1, pawn)
            return statics:FinishSpawningActor(d, xf)
        end)
        if not (ok and valid(w)) then log("Trainer: couldn't make %s: %s", ufoName, tostring(w)); return nil end
        pcall(function() w:SetHolder(pawn) end)
        pcall(function() w:SetEquipmentManager(eq) end)
        ufoMade[pk][ufoName] = w
        log("Trainer: made %s for %s", ufoName, shortName(pawn))
        return w
    end
    local function attachLike(w, original)
        local okP, parent = pcall(function() return original.RootComponent:GetAttachParent() end)
        local okN, sock = pcall(function() return original.RootComponent:GetAttachSocketName() end)
        if okP and valid(parent) then
            pcall(function() w:K2_AttachToComponent(parent, okN and sock or FName("None"), 2, 2, 2, true) end)
        end
        -- the Death Ray is built to fire straight down from a saucer: turn it to fire forward
        if nameOf(w):find("DeathRay", 1, true) then
            pcall(function() w:K2_SetActorRelativeRotation({ Pitch = CFG.DEATHRAY_TILT, Yaw = 0, Roll = 0 }, false, {}, true) end)
        end
    end
    local function isOurUfo(pk, w)
        for _, u in pairs(ufoMade[pk] or {}) do if valid(u) and keyOf(u) == keyOf(w) then return true end end
        return false
    end
    local function ufoTick(mode)
        for _, pc in ipairs({ player1Controller(), state.p2 }) do
            local pawn = valid(pc) and getPawn(pc) or nil
            local eq = pawn and subObj(pawn, "m_pEquipmentManagerComponent") or nil
            if eq then
                local pk = keyOf(pawn) or "?"
                pcall(function()
                    eq.m_apCurrentlyEquipWeapons:ForEach(function(_, e)
                        local cur = e:get()
                        if not valid(cur) then return end
                        local only = UFO_ONLY_NAME and UFO_ONLY_NAME[mode] or nil
                        if mode and mode:find("^On: R3") then only = UFO_CYCLE[ufoSel[pk] or 1] end
                        if isOurUfo(pk, cur) then
                            if only and not nameOf(cur):find(only, 1, true) then
                                -- the chosen weapon changed: swap to it
                                local want = makeUfo(pawn, eq, only, cur)
                                if want then
                                    attachLike(want, ufoOrig[pk] or cur)
                                    pcall(function() cur:SetActorHiddenInGame(true) end)
                                    pcall(function() want:SetActorHiddenInGame(false) end)
                                    e:set(want)
                                    ufoLast[pk] = only
                                end
                            end
                            return
                        end
                        -- one of Crypto's own guns is in hand: put its saucer version in its place
                        local cn = nameOf(cur)
                        local ufoName = only
                        if not ufoName then
                            for _, m in ipairs(UFO_FOR) do if cn:find(m[1], 1, true) then ufoName = m[2] end end
                            if not ufoName then ufoName = ufoLast[pk] or "BP_Weapon_UFO_SonicBoom_C" end -- the probe gun
                        end
                        local w = makeUfo(pawn, eq, ufoName, cur)
                        if not w then return end
                        if ufoOrig[pk] and valid(ufoOrig[pk]) and keyOf(ufoOrig[pk]) ~= keyOf(cur) then
                            pcall(function() ufoOrig[pk]:SetActorHiddenInGame(true) end)
                        end
                        for _, u in pairs(ufoMade[pk]) do if valid(u) then pcall(function() u:SetActorHiddenInGame(true) end) end end
                        attachLike(w, cur)
                        pcall(function() cur:SetActorHiddenInGame(true) end)
                        pcall(function() w:SetActorHiddenInGame(false) end)
                        e:set(w)
                        ufoOrig[pk] = cur
                        ufoLast[pk] = ufoName
                    end)
                end)
            end
        end
    end
    local function setSaucerWeapons(on)
        if on then ufoTick(state.trUfoWeap); return 1 end
        local n = 0
        for _, pc in ipairs({ player1Controller(), state.p2 }) do
            local pawn = valid(pc) and getPawn(pc) or nil
            local eq = pawn and subObj(pawn, "m_pEquipmentManagerComponent") or nil
            local pk = pawn and keyOf(pawn) or "?"
            if eq and ufoOrig[pk] and valid(ufoOrig[pk]) then
                pcall(function()
                    eq.m_apCurrentlyEquipWeapons:ForEach(function(_, e)
                        local cur = e:get()
                        if valid(cur) and isOurUfo(pk, cur) then e:set(ufoOrig[pk]) end
                    end)
                end)
                pcall(function() ufoOrig[pk]:SetActorHiddenInGame(false) end)
            end
            for _, u in pairs(ufoMade[pk] or {}) do
                if valid(u) then pcall(function() u:K2_DestroyActor() end); n = n + 1 end
            end
        end
        ufoMade, ufoLast, ufoOrig = {}, {}, {}
        return n
    end
    local UFO_MODES = { "Off", "On: R3 cycles Death Ray / Sonic Boom / Quantum", "Death Ray only", "Sonic Boom only", "Quantum Deconstructor only" }
    UFO_ONLY_NAME = { ["Death Ray only"] = "BP_Weapon_UFO_DeathRay_C", ["Sonic Boom only"] = "BP_Weapon_UFO_SonicBoom_C",
        ["Quantum Deconstructor only"] = "BP_Weapon_UFO_QuantumDecontructor_C" }
    local function applyUfoWeapons(label)
        local was = state.trUfoWeap
        state.trUfoWeap = label
        if label == "Off" then
            log("Trainer: saucer weapons on foot off (%d removed)", setSaucerWeapons(false))
        else
            if was and was ~= "Off" then setSaucerWeapons(false) end
            setSaucerWeapons(true)
            log("Trainer: saucer weapons on foot: %s", label)
        end
    end
    addTickJob("trainerUfoEquip", 0.0, function()
        local mode = state.trUfoWeap
        if not mode or mode == "Off" then return end
        if mode:find("^On: R3") then
            for _, pc in ipairs({ player1Controller(), state.p2 }) do
                local pw = valid(pc) and getPawn(pc) or nil
                if pw then
                    local pk = keyOf(pw) or "?"
                    local d = kbDown(pc, "Gamepad_RightThumbstick")
                    if d and not r3Held[pk] then
                        ufoSel[pk] = ((ufoSel[pk] or 1) % #UFO_CYCLE) + 1
                        log("Trainer: %s saucer weapon -> %s", shortName(pc), UFO_CYCLE[ufoSel[pk]])
                    end
                    r3Held[pk] = d
                end
            end
        end
        ufoTick(mode)
    end)

    -- Player 2 gets a saucer of their own (experimental): a second copy of the map's saucer,
    -- taken over by Player 2; "On foot" puts Player 2 back on the ground below it.
    local p2ufo, p2walker = nil, nil
    local applyP2Saucer
    state.p2SaucerOff = function() if applyP2Saucer then applyP2Saucer("On foot") end end
    function applyP2Saucer(label)
        if not valid(state.p2) then log("Trainer: no Player 2."); return end
        local statics, world = getStatics(), getWorld()
        if label == "Fly a saucer" then
            if valid(p2ufo) then return end
            local template = FindFirstOf("BP_PlayerUFO_C")
            if not valid(template) then log("Trainer: no saucer on this map to copy."); return end
            local walker = getPawn(state.p2)
            local okL, loc = pcall(function() return walker:K2_GetActorLocation() end)
            if not okL then return end
            local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = loc.X, Y = loc.Y, Z = loc.Z + 900 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local ok, ufo = pcall(function()
                local d = statics:BeginDeferredActorSpawnFromClass(world, template:GetClass(), xf, 2, nil)
                return statics:FinishSpawningActor(d, xf)
            end)
            if not (ok and valid(ufo)) then log("Trainer: couldn't make a saucer: %s", tostring(ufo)); return end
            p2ufo, p2walker = ufo, walker
            pcall(function() walker:SetActorHiddenInGame(true) end)
            pcall(function() walker:SetActorEnableCollision(false) end)
            local okP, err = pcall(function() state.p2:Possess(ufo) end)
            log("Trainer: Player 2 saucer: %s", okP and "flying" or tostring(err))
        else
            if not valid(p2ufo) then return end
            local okL, loc = pcall(function() return p2ufo:K2_GetActorLocation() end)
            if valid(p2walker) then
                pcall(function() state.p2:Possess(p2walker) end)
                pcall(function() p2walker:SetActorHiddenInGame(false) end)
                pcall(function() p2walker:SetActorEnableCollision(true) end)
                if okL then teleportPawn(p2walker, { X = loc.X, Y = loc.Y, Z = loc.Z - 600 }, { Pitch = 0, Yaw = 0, Roll = 0 }) end
            end
            pcall(function() p2ufo:K2_DestroyActor() end)
            p2ufo, p2walker = nil, nil
            log("Trainer: Player 2 back on foot")
        end
    end

    -- Player 1 saucer (same idea as Player 2's, for a quick saucer anywhere).
    local p1ufo, p1walker = nil, nil
    onWorldChange(function() p1ufo, p1walker = nil, nil end)
    local function applyP1Saucer(label)
        local pc = player1Controller()
        if not valid(pc) then return end
        local statics, world = getStatics(), getWorld()
        if label == "Fly a saucer" then
            if valid(p1ufo) then return end
            local template = FindFirstOf("BP_PlayerUFO_C")
            if not valid(template) then log("Trainer: no saucer on this map to copy."); return end
            local walker = getPawn(pc)
            local okL, loc = pcall(function() return walker:K2_GetActorLocation() end)
            if not okL then return end
            local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = loc.X, Y = loc.Y, Z = loc.Z + 900 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local ok, ufo = pcall(function()
                local d = statics:BeginDeferredActorSpawnFromClass(world, template:GetClass(), xf, 2, nil)
                return statics:FinishSpawningActor(d, xf)
            end)
            if not (ok and valid(ufo)) then log("Trainer: couldn't make a saucer: %s", tostring(ufo)); return end
            p1ufo, p1walker = ufo, walker
            pcall(function() walker:SetActorHiddenInGame(true) end)
            pcall(function() walker:SetActorEnableCollision(false) end)
            local okP, err = pcall(function() pc:Possess(ufo) end)
            log("Trainer: Player 1 saucer: %s", okP and "flying" or tostring(err))
        else
            if not valid(p1ufo) then return end
            local okL, loc = pcall(function() return p1ufo:K2_GetActorLocation() end)
            if valid(p1walker) then
                pcall(function() pc:Possess(p1walker) end)
                pcall(function() p1walker:SetActorHiddenInGame(false) end)
                pcall(function() p1walker:SetActorEnableCollision(true) end)
                if okL then teleportPawn(p1walker, { X = loc.X, Y = loc.Y, Z = loc.Z - 600 }, { Pitch = 0, Yaw = 0, Roll = 0 }) end
            end
            pcall(function() p1ufo:K2_DestroyActor() end)
            p1ufo, p1walker = nil, nil
            log("Trainer: Player 1 back on foot")
        end
    end

    -- Wanted level (the game's alert system: response levels 0..max).
    local function alertMgr()
        local gs = FindFirstOf("GameStateBase")
        local ok, mgr = pcall(function() return gs:GetAlertSystemManager() end)
        return ok and valid(mgr) and mgr or nil
    end
    local function wantedOptions()
        local mgr = alertMgr()
        local mx = 4
        if mgr then pcall(function() mx = mgr:GetMaxResponseLevelIndex() end) end
        local list = { "Game decides", "Never wanted (locked)" }
        local top = math.max(4, tonumber(mx) or 4)   -- the four alert levels, whatever the map reports
        for i = 1, top do list[#list + 1] = "Wanted " .. i .. " (locked)" end
        for i = 1, top do list[#list + 1] = "Wanted " .. i .. " (set, then the game decides)" end
        return list
    end
    local function holdWanted()
        local mgr = alertMgr()
        if not mgr then return end
        local want = state.trWanted
        if not want or want == "Game decides" or want:find("set, then") then return end
        local level = want:find("^Never") and 0 or tonumber(want:match("(%d+)")) or 0
        local okC, cur = pcall(function() return mgr:GetCurrentResponseLevelIndex() end)
        if not okC or cur ~= level then
            pcall(function() mgr:SetResponseLevelLockedMode(false) end)
            if level == 0 and not state.trWantedReset then
                state.trWantedReset = true -- only once: resetting again and again cut NPC voice lines short
                pcall(function() mgr:Reset() end)
                pcall(function() mgr:SetUndetected() end)
            end
            pcall(function() mgr:SetResponseLevelIndex(level, false) end)
        end
        pcall(function() mgr:SetResponseLevelLockedMode(true) end)
    end
    local function applyWanted(label)
        state.trWanted = label
        state.trWantedReset = nil
        local mgr = alertMgr()
        if not mgr then log("Trainer: no wanted system on this map."); return end
        if label == "Game decides" then
            pcall(function() mgr:SetResponseLevelLockedMode(false) end)
        elseif label:find("set, then") then
            -- straight to that level once, then the game carries on from there
            local level = tonumber(label:match("(%d+)")) or 1
            pcall(function() mgr:SetResponseLevelLockedMode(false) end)
            pcall(function() mgr:SetResponseLevelIndex(level, true) end)
        else
            holdWanted()
        end
        local okC, cur = pcall(function() return mgr:GetCurrentResponseLevelIndex() end)
        log("Trainer: wanted level %s (now %s)", label, okC and tostring(cur) or "?")
    end
    addTickJob("trainerWanted", 1.0, function()
        if state.trWanted and state.trWanted ~= "Game decides" and not state.trWanted:find("set, then") then holdWanted() end
    end)

    -- The wanted / alert system: write its layout once per map so the wanted slider can use it.
    local alertDumped = nil
    local function dumpAlertSystem()
        local w = getWorld()
        local key = w and nameOf(w) or ""
        if alertDumped == key then return end
        alertDumped = key
        local gs = FindFirstOf("GameStateBase")
        local ok, mgr = pcall(function() return gs:GetAlertSystemManager() end)
        local lines = {}
        appendClassDump(lines, "AlertSystemManager", ok and mgr or nil)
        for _, pc in ipairs({ player1Controller() }) do
            local st = subObj(getPawn(pc), "m_pStatsComponent")
            appendClassDump(lines, "P1 alert state stat", st and subObj(st, "m_pCurrentAIAlertStateStat") or nil)
        end
        writeDumpFile("alert", lines)
    end

    local function closeMenu()
        if not menu then return end
        state.trainerOpen = false
        local pc = player1Controller()
        pcall(function() menu.widget:RemoveFromParent() end)
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        pcall(function() wbl:SetInputMode_GameOnly(pc) end)
        pcall(function() pc.bShowMouseCursor = false end)
        if menu.pad then local pw = getPawn(pc); if valid(pw) then pcall(function() pw:EnableInput(pc) end) end end
        menu = nil
        log("Trainer menu closed")
    end

    local function highlight()
        if not menu then return end
        state.trCursorOf = state.trCursorOf or {}
        state.trCursorOf[menu.page] = menu.cursor
        for i, key in ipairs(menu.order) do
            local t = menu.labels[key]
            local on = menu.pad and i == menu.cursor
            local kept = state.trIsSaved and state.trIsSaved(key)
            pcall(function() t:SetText(FText(menu.titles[key] .. (kept and "   (saved)" or ""))) end)
            local tc = on and { R = 1, G = 1, B = 1, A = 1 } or (kept and { R = 0.45, G = 1, B = 0.45, A = 1 } or { R = 0.36, G = 0.92, B = 1, A = 1 })
            pcall(function() t:SetColorAndOpacity({ SpecifiedColor = tc, ColorUseRule = 0 }) end)
            local bar = menu.bars and menu.bars[key]
            local bc
            if kept then bc = on and { R = 0.15, G = 0.65, B = 0.2, A = 0.65 } or { R = 0.08, G = 0.4, B = 0.1, A = 0.45 }
            else bc = on and { R = 0.1, G = 0.5, B = 0.58, A = 0.55 } or { R = 0, G = 0, B = 0, A = 0 } end
            if bar then pcall(function() bar:SetBrushColor(bc) end) end
            local vt = menu.values and menu.values[key]
            local c = menu.combos[key]
            if vt and c then
                local okS, cur = pcall(function() return c:GetSelectedOption():ToString() end)
                pcall(function() vt:SetText(FText(okS and cur and ((on and "<  " or "") .. cur .. (on and "  >" or "")) or "")) end)
            end
        end
        -- keep the picked row on screen
        local ck = menu.pad and menu.order[menu.cursor]
        local cb = ck and menu.bars and menu.bars[ck]
        if cb and menu.scroll and valid(menu.scroll) then
            if not pcall(function() menu.scroll:ScrollWidgetIntoView(cb, false, 0, 40) end) then
                pcall(function() menu.scroll:ScrollWidgetIntoView(cb, false, 0) end)
            end
        end
    end

    local PAGES = { "Welcome", "Controls", "Players", "World", "Spawn & travel", "Active", "Known issues", "Projectiles", "Upgrades" }
    -- the order the tabs are shown and stepped through (page numbers stay as they are)
    local TAB_ORDER = { 1, 6, 2, 3, 4, 5, 8, 9, 7 }
    local function tabStep(page, dir)
        local at = 1
        for k, pg in ipairs(TAB_ORDER) do if pg == page then at = k end end
        return TAB_ORDER[(at - 1 + dir) % #TAB_ORDER + 1]
    end
    local PAGE_OF = { time = 4, set = 4, foreign = 4, fog = 4, speed = 4, gravity = 4, bounds = 4,
        ignore = 3, riot = 3, wanted = 3, holo = 3, ammo = 3, ufoweap = 3, p2ufo = 3, p1ufo = 3, god = 3, fuel = 3, hyp = 3, size1 = 3, size2 = 3,
        spawncount = 5, spawn = 5, despawn = 5, tp = 5, start = 5, save = 1 }
    local WELCOME = {
        { "THIRD EYE DECALCIFIED CO-OP  (early access beta)", true },
        { "Split-screen co-op, an overhauled PK, a mind & weapons wheel with new mind powers, and a trainer." },
        { "Created by Keaton and Claude" },
        { "GETTING STARTED", true },
        { "Press Start on a second controller to bring in Player 2. Hold Start on that pad (2 s) to drop out." },
        { "Hold LB for the mind & weapons wheel: A / B / X / Y pick a weapon, the D-pad picks a power, LT uses it." },
        { "LB / RB flip through these pages. Trainer choices saved with X come back every time and never touch your save." },
        { "EARLY ACCESS", true },
        { "Everything here is a work in progress and may change between versions." },
        { "Made for two players. Players 3 and 4 are an early test and not ready yet: four players will come in time." },
        { "MOD FEATURES", true },
        { "Every part of the mod that works outside the menus can be switched off below, for a near-vanilla game. Rows marked CO-OP are needed for split screen to work properly. Save a row with X to keep it." },
    }
    local ISSUES = {
        { "KNOWN ISSUES  (early access: all work in progress, subject to change)", true },
        { "Players 3 and 4 (Players page) are not ready: radars, some trainer options, saucers and HUD are unfinished. Play with two." },
        { "Some mind powers are still being tuned: effects, damage and costs can change (Shockwave, Hysteria, Free Fear, Deflector, Sentry)." },
        { "Player 2's yellow PK arcs may not show and P2's weapon lock-on can sit slightly off (being worked on); P2's PK glow can look flat." },
        { "The '!!' seen card can drop while both players are being chased." },
        { "Saucers in split screen are experimental: land both saucers before changing map." },
        { "After a game over with two players, give the game a few seconds before dropping Player 2 out." },
        { "Options marked TEST haven't been fully tried yet." },
        { "Skins: Player 1 changes skin at the Mothership as normal. The mod's skin keys are for Player 2 only, because changing Player 1's skin through the mod caused save-game problems in testing." },
        { "All mind powers are on. Psi-Barrage, Mutant Shockwave, Free Fear and Body Snatch are newly back and still being tuned." },
        { "Free Love works in co-op too; its dance party and hearts only show in single player." },
        { "After a game over the game goes back to one player at the saucer; Player 2 presses Start to rejoin." },
        { "Bug reports: send overkill_coop_log.txt and overkill_pk_log.txt (next to the game exe) and ue4ss/UE4SS.log." },
    }
    local HELP = {
        { "SPLIT SCREEN", true },
        { "Start on pad 2: Player 2 joins     Hold Start on pad 2 (2 s): Player 2 leaves     Ctrl+Y / Ctrl+I: keyboard" },
        { "Ctrl+T: Player 2 to Player 1            Ctrl+Shift+T: Player 1 to Player 2" },
        { "Pad 2 Select + D-pad left/right: Player 2 skin       Keyboard skins: Delete = P2, End = P3, Insert = P4" },
        { "Partner down: stand next to them for 3 s to revive (they get up on their own after 45 s)" },
        { "TRAINER MENU", true },
        { "Pad 1 Select + R3 (or Ctrl+Shift+M): open / close" },
        { "D-pad up/down: pick   left/right: change   A: apply   Y: back to default   X: save / forget   B: close   LB/RB: page" },
        { "Saved rows are green and come back every time you play (per map for time, lighting, fog and pad)" },
        { "PK", true },
        { "RB tap: PK on (blue)   RB hold: RELEASE TO THROW (red; LB = blue RELEASE, sets it down)" },
        { "While holding RB, LB: RELEASE (blue) - let go of RB to drop it instead of throwing" },
        { "L3 pull in   R3 push out (or shrink / grow in blue, Players page)   (mouse wheel on keyboard)" },
        { "F6: PK changes on / off" },
        { "MIND & WEAPONS WHEEL", true },
        { "Hold LB: A / B / X / Y pick a weapon, D-pad picks a mind power (LT uses it), let go of LB to switch" },
        { "SAUCER WEAPONS ON FOOT (Players page)", true },
        { "R3 cycles Death Ray / Sonic Boom / Quantum Deconstructor; the trigger fires" },
    }
    local openMenu
    local function switchPage(padMode, page)
        state.trPage = page
        runGame("trainerPage", function()
            if menu then closeMenu() end
            openMenu(padMode, page)
        end)
    end

    function openMenu(padMode, page, collect)
        page = page or state.trPage or 1
        local pc = player1Controller()
        local world = getWorld()
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local template = nil
        for _, w in ipairs(hudWidgetsOf(pc)) do
            local note = subObj(w, "BPW_HUD_TextNotification")
            if note then template = note break end
        end
        if not (world and valid(wbl) and template) then log("Trainer: no HUD to build the menu from yet."); return end
        local w = wbl:Create(world, template:GetClass(), pc)
        local tree = subObj(w, "WidgetTree")
        if not tree then return end
        -- looks like the game's pause / mothership menus: deep teal glass, thin cyan edges,
        -- a yellow title with a yellow rule under it, cyan list, a button bar at the bottom
        local CY, CYD = { R = 0.36, G = 0.92, B = 1, A = 1 }, { R = 0.25, G = 0.6, B = 0.68, A = 1 }
        local YE, YEP = { R = 1, G = 0.8, B = 0.2, A = 1 }, { R = 1, G = 0.9, B = 0.55, A = 1 }
        local border = U("Border", tree, "DAH2P_TrainerEdge")      -- the cyan edge (top and right)
        local inner = U("Border", tree, "DAH2P_TrainerBg")
        local box = U("VerticalBox", tree, "DAH2P_TrainerBox")
        -- the rows go in a scrolling list of limited height (in split screen they ran off the
        -- bottom); the cursor scrolls it
        local listBox, listIsScroll = nil, false
        local function addToList(w)
            if not listBox then
                local sb = U("SizeBox", tree, "DAH2P_TrainerListSize")
                local sc = U("ScrollBox", tree, "DAH2P_TrainerList")
                if valid(sb) and valid(sc) then
                    -- 1-2 players: the long list; 3-4 players (smaller screens): the short one
                    local party = state.extraPlayers and (valid(state.extraPlayers[3]) or valid(state.extraPlayers[4]))
                    local h = party and (CFG.TRAINER_LIST_HEIGHT_SPLIT or 430) or (CFG.TRAINER_LIST_HEIGHT or 640)
                    -- fill the menu: as tall as the screen allows (minus the title, tabs and hint)
                    pcall(function()
                        local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
                        local sz, sc = lib:GetViewportSize(world), lib:GetViewportScale(world)
                        local vh = (sz.Y or 0) / ((type(sc) == "number" and sc > 0) and sc or 1)
                        if party then vh = vh / 2 end
                        local fit = vh - (CFG.TRAINER_CHROME or 300) - (page == 1 and 280 or 0)
                        if fit > 250 then h = fit end
                    end)
                    pcall(function() sb:SetMaxDesiredHeight(h) end)
                    pcall(function() sb:SetContent(sc) end)
                    pcall(function() box:AddChildToVerticalBox(sb) end)
                    listBox, listIsScroll = sc, true
                    menu.scroll = sc
                else
                    listBox = box
                end
            end
            if listIsScroll then
                local ok, sl = pcall(function() return listBox:AddChild(w) end)
                return ok and sl or nil
            end
            local ok, sl = pcall(function() return listBox:AddChildToVerticalBox(w) end)
            return ok and sl or nil
        end
        pcall(function() border:SetBrushColor({ R = 0.36, G = 0.92, B = 1, A = 0.85 }) end)
        pcall(function() border:SetPadding({ Left = 0, Top = 2, Right = 2, Bottom = 0 }) end)
        pcall(function() inner:SetBrushColor({ R = 0.0, G = 0.075, B = 0.095, A = 0.93 }) end)
        pcall(function() inner:SetPadding({ Left = 30, Top = 22, Right = 30, Bottom = 18 }) end)
        pcall(function() border:SetContent(inner) end)
        pcall(function() inner:SetContent(box) end)
        local function line(name, col, h)
            local l = U("Border", tree, name)
            pcall(function() l:SetBrushColor(col) end)
            pcall(function() l:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
            local sb = U("SizeBox", tree, name .. "S")
            pcall(function() sb:SetHeightOverride(h or 2) end)
            pcall(function() sb:SetContent(l) end)
            return sb
        end
        local function text(name, str, size, col)
            local t = U("TextBlock", tree, name)
            pcall(function() t:SetText(FText(str)) end)
            if not state.applyGameFont(t, size) then
                pcall(function() local f = t.Font; f.Size = size; t:SetFont(f) end)
            end
            pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col or { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }) end)
            return t
        end
        local hint = padMode and "D-pad: pick / change     A: apply     Y: default     X: save (green) / forget     LB / RB: page     B: back"
            or "Click a list to change it.     Ctrl+Shift+M: close"
        do
            -- the mod's logo on the Welcome page (Mods/OverkillCoop/logo.png)
            if page == 1 and CFG.TRAINER_LOGO ~= false then
                pcall(function()
                    if not valid(state.logoTex) then
                        local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
                        for _, path in ipairs({ "ue4ss/Mods/OverkillCoop/logo.png", "Mods/OverkillCoop/logo.png" }) do
                            local okI, t = pcall(function() return krl:ImportFileAsTexture2D(world, path) end)
                            if okI and valid(t) then state.logoTex = t break end
                        end
                    end
                    if not valid(state.logoTex) then return end
                    local img = U("Image", tree, "OK_TrainerLogo")
                    img:SetBrushFromTexture(state.logoTex, false)
                    img:SetBrushSize({ X = 480, Y = 270 })
                    local sl = box:AddChildToVerticalBox(img)
                    sl:SetHorizontalAlignment(2)
                end)
            end
            local head = U("HorizontalBox", tree, "OK_TrainerHead")
            local t1 = text("OK_TrainerTitle", "THIRD EYE", 30, YE)
            local t2 = text("OK_TrainerSub", "   DECALCIFIED CO-OP  >  " .. PAGES[page], 19, YEP)
            pcall(function() head:AddChildToHorizontalBox(t1) end)
            pcall(function() local sl = head:AddChildToHorizontalBox(t2); sl:SetVerticalAlignment(2) end)
            pcall(function() box:AddChildToVerticalBox(head) end)
            pcall(function()
                local sl = box:AddChildToVerticalBox(line("OK_TrainerRule", { R = 1, G = 0.78, B = 0.2, A = 0.85 }, 2))
                sl:SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 8 })
            end)
            -- page tabs, like the mothership's  Q  MISSION SELECTION  POX'S LAB  ARCHIVES  E
            local tabs = U("HorizontalBox", tree, "OK_TrainerTabs")
            local function chip(name, str)
                local b = U("Border", tree, name)
                pcall(function() b:SetBrushColor(CY) end)
                pcall(function() b:SetPadding({ Left = 6, Top = 1, Right = 6, Bottom = 1 }) end)
                pcall(function() b:SetContent(text(name .. "T", str, 13, { R = 0.0, G = 0.1, B = 0.12, A = 1 })) end)
                return b
            end
            if padMode then pcall(function() local sl = tabs:AddChildToHorizontalBox(chip("OK_TabLB", "LB")); sl:SetVerticalAlignment(2) end) end
            for _, pi in ipairs(TAB_ORDER) do
                local TAB_SHORT = { ["Spawn & travel"] = "Travel", ["Known issues"] = "Issues", ["Projectiles"] = "Shots" }
                local pn = TAB_SHORT[PAGES[pi]] or PAGES[pi]
                local t
                if pi == page then
                    -- the page you're on: dark letters on a yellow tab
                    t = U("Border", tree, "OK_TabOn" .. pi)
                    pcall(function() t:SetBrushColor({ R = 1, G = 0.8, B = 0.15, A = 1 }) end)
                    pcall(function() t:SetPadding({ Left = 0, Top = 1, Right = 0, Bottom = 1 }) end)
                    pcall(function() t:SetContent(text("OK_Tab" .. pi, "  " .. string.upper(pn) .. "  ", 14, { R = 0.05, G = 0.05, B = 0.02, A = 1 })) end)
                else
                    t = text("OK_Tab" .. pi, "  " .. string.upper(pn) .. "  ", 13, CYD)
                end
                pcall(function() local sl = tabs:AddChildToHorizontalBox(t); sl:SetVerticalAlignment(2) end)
            end
            if padMode then pcall(function() local sl = tabs:AddChildToHorizontalBox(chip("OK_TabRB", "RB")); sl:SetVerticalAlignment(2) end) end
            pcall(function()
                local sl = box:AddChildToVerticalBox(tabs)
                sl:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 12 })
            end)
        end
        menu = { widget = w, combos = {}, last = {}, actions = {}, order = {}, labels = {}, titles = {}, opts = {}, cursor = 1, pad = padMode, page = page }
        local function row(key, label, options, current, action)
            state.trApply = state.trApply or {}
            state.trOpts = state.trOpts or {}
            state.trApply[key], state.trOpts[key] = action, options
            if key:sub(1, 4) ~= "act_" then
                state.trNow = state.trNow or {}
                state.trLabel = state.trLabel or {}
                state.trNow[key], state.trLabel[key] = current or options[1], label
            end
            if collect then return end
            if key ~= "page" and PAGE_OF[key] and PAGE_OF[key] ~= page then return end
            local bar = U("Border", tree, "DAH2P_TrainerBar_" .. key)
            pcall(function() bar:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
            pcall(function() bar:SetPadding({ Left = 10, Top = 4, Right = 10, Bottom = 4 }) end)
            local hb = U("HorizontalBox", tree, "DAH2P_TrainerRow_" .. key)
            local lt = text("DAH2P_TrainerL_" .. key, label, 14, CY)
            pcall(function() lt:SetJustification(0) end)
            local vt = text("DAH2P_TrainerV_" .. key, "", 14, YE)
            pcall(function() local sl = hb:AddChildToHorizontalBox(lt); sl:SetSize({ SizeRule = 1, Value = 1 }); sl:SetVerticalAlignment(2) end)
            if padMode then pcall(function() local sl = hb:AddChildToHorizontalBox(vt); sl:SetVerticalAlignment(2) end) end
            pcall(function() bar:SetContent(hb) end)
            pcall(function() local sl = addToList(bar); sl:SetPadding({ Left = 0, Top = 1, Right = 0, Bottom = 1 }) end)
            menu.order[#menu.order + 1] = key
            menu.labels[key], menu.titles[key], menu.opts[key] = lt, label, options
            menu.bars = menu.bars or {}
            menu.values = menu.values or {}
            menu.bars[key], menu.values[key] = bar, vt
            local c = U("ComboBoxString", tree, "DAH2P_TrainerC_" .. key)
            if not valid(c) then return end
            for _, o in ipairs(options) do pcall(function() c:AddOption(o) end) end
            pcall(function() c:SetSelectedOption(current or options[1]) end)
            local slot = addToList(c)
            if slot then pcall(function() slot:SetPadding({ Left = 10, Top = 1, Right = 0, Bottom = 5 }) end) end
            -- on the controller the value is shown on the row itself (the list stays, hidden)
            if padMode then pcall(function() c:SetVisibility(1) end) end
            menu.combos[key] = c
            menu.last[key] = current or options[1]
            menu.actions[key] = action
        end
        local function names(list) local r = {} for _, e in ipairs(list) do r[#r + 1] = e[1] end return r end
        local LINES = (PAGES[page] == "Controls" and HELP) or (PAGES[page] == "Welcome" and WELCOME)
            or (PAGES[page] == "Known issues" and ISSUES) or nil
        if LINES then
            -- long lines are broken up here (by words) so they stay inside the menu
            local function wrapText(str, max)
                local out, cur = {}, ""
                for word in str:gmatch("%S+") do
                    if cur == "" then cur = word
                    elseif #cur + 1 + #word <= max then cur = cur .. " " .. word
                    else out[#out + 1] = cur; cur = "    " .. word end
                end
                if cur ~= "" then out[#out + 1] = cur end
                return out
            end
            local n = 0
            for _, h in ipairs(LINES) do
                local col = h[2] and YE or { R = 0.8, G = 0.95, B = 1, A = 1 }
                local parts = h[2] and { h[1] } or wrapText(h[1], CFG.TRAINER_WRAP_CHARS or 92)
                for pi2, part in ipairs(parts) do
                    n = n + 1
                    local t = text("DAH2P_TrainerHelp" .. n, part, h[2] and 16 or 13, col)
                    pcall(function() t:SetJustification(0) end)
                    local okS, slot = pcall(function() return box:AddChildToVerticalBox(t) end)
                    if okS and slot and h[2] then pcall(function() slot:SetPadding({ Left = 0, Top = 10, Right = 0, Bottom = 2 }) end) end
                end
            end
        end
        if not padMode then
            row("page", "Page", PAGES, PAGES[page], function(v)
                for i, n in ipairs(PAGES) do if n == v then switchPage(false, i) end end
            end)
        end
        row("save", "Remember trainer settings (own file, never your game save)", { "On", "Off" },
            state.trSaveOn == false and "Off" or "On", function() end)
        row("time", "Time of day", names(TIMES), state.trTime, applyTime)
        local setNames = { "Game default" }
        for _, e in ipairs(lightingSets()) do setNames[#setNames + 1] = e.pkg:match("[^/]+$") or e.pkg end
        if #setNames > 1 then
            local cur = nil
            for _, e in ipairs(lightingSets()) do
                local okV, vis = pcall(function() return e.lvl:IsLevelVisible() end)
                if okV and vis then cur = e.pkg:match("[^/]+$") end
            end
            -- the map's own lighting is the first one seen on this map (before any change)
            local wn = nameOf(getWorld())
            state.trSetDefault = state.trSetDefault or {}
            if cur and not state.trSetDefault[wn] then state.trSetDefault[wn] = cur end
            if cur == state.trSetDefault[wn] then cur = "Game default" end
            row("set", "This map's day / night lighting", setNames, cur, function(v)
                if v == "Game default" then v = state.trSetDefault and state.trSetDefault[nameOf(getWorld())] end
                if v then applyLightingSet(v) end
            end)
        end
        rememberSkies()
        local foreign = { "None" }
        for _, f in ipairs(FOREIGN) do foreign[#foreign + 1] = f:match("[^/]+$") end
        row("foreign", "Load another map's sky here (experimental)", foreign, foreignLoaded and nil or "None", applyForeignSky)
        row("fog", "Fog / weather", names(FOGS), state.trFog, applyFog)
        row("speed", "Game speed", names(SPEEDS), state.trSpeed, applySpeed)
        row("gravity", "Gravity", names(GRAVITY), state.trGravity, applyGravity)
        local types = npcClasses()
        if #types > 0 then
            local list = { "(pick who to spawn)" }
            for _, t in ipairs(types) do list[#list + 1] = t end
            row("spawncount", "How many to spawn", { "1", "3", "5", "10" }, state.trSpawnCount or "3", function(v) state.trSpawnCount = v end)
            row("spawn", "Spawn in front of Player 1 (types on this map)", list, list[1], spawnNpc)
            row("despawn", "Spawned NPCs", { "(keep them)", "Remove the ones I spawned" }, "(keep them)", despawnAll)
        end
        row("ignore", "NPCs ignore both players (invisible)", { "Off", "On" }, state.trIgnore or "Off", applyIgnore)
        row("riot", "Riot mode: everyone fights everyone", { "Off", "On (experimental)" }, state.trRiot or "Off", applyRiot)
        row("wanted", "Wanted level", wantedOptions(), state.trWanted or "Game decides", applyWanted)
        row("bounds", "Map limits / Pox's 'turn around' (until the map reloads)", { "Normal", "No out-of-bounds death",
            "No limits, no edge walls (can fall off the map)" }, state.trBounds or "Normal", applyBounds)
        row("holo", "Holobob never runs out or gets compromised", { "Off", "On" }, state.trHolo or "Off", applyHolobob)
        local who = valid(state.p2) and WHO or { "Off", "On" }
        row("ammo", "Infinite ammo", who, state.trAmmo or "Off", applyAmmo)
        row("god", "God mode (shield and health stay full)", who, state.trGod or "Off", applyGod)
        row("size1", "Player 1 size", SIZE_NAMES, state.trSize1 or "Normal", function(v) applySize(1, v) end)
        if valid(state.p2) then row("size2", "Player 2 size", SIZE_NAMES, state.trSize2 or "Normal", function(v) applySize(2, v) end) end
        row("fuel", "Endless jetpack boost (fly)", { "Off", "On" }, state.trFuel or "Off", applyFuel)
        row("hyp", "Permanent bodyguards (hypnotized people stay on your side)", { "Off", "On" }, state.trHyp or "Off", applyHyp)
        pcall(dumpAbilities)
        row("ufoweap", "Saucer weapons on foot (both players)", UFO_MODES, state.trUfoWeap or "Off", applyUfoWeapons)
        row("p1ufo", "Player 1 saucer (experimental: set back On foot before changing map)", { "On foot", "Fly a saucer" },
            valid(p1ufo) and "Fly a saucer" or "On foot", applyP1Saucer)
        if valid(state.p2) then
            row("p2ufo", "Player 2 saucer (experimental: P1 boards their saucer first; set P2 back On foot before ending split screen)", { "On foot", "Fly a saucer" }, valid(p2ufo) and "Fly a saucer" or "On foot", applyP2Saucer)
        end
        pcall(dumpAmmo)
        pcall(dumpAlertSystem)
        -- rows added by other parts of the mod (state.trainerExtras: key, page, label, options, get, set)
        for _, e in ipairs(state.trainerExtras or {}) do
            PAGE_OF[e.key] = e.page
            if (not e.p2only or valid(state.p2)) and (not e.show or e.show()) then
                local okG, cur = pcall(e.get)
                row(e.key, e.label, e.options, okG and cur or e.options[1], function(v)
                    local ok, err = pcall(e.set, v)
                    if not ok then log("Trainer: %s failed: %s", e.key, tostring(err)) end
                end)
            end
        end
        local pads = { "(pick a landing pad)" }
        for i, site in ipairs(sitesList()) do pads[#pads + 1] = siteLabel(i, site) end
        row("tp", "Teleport both players to a saucer landing pad", pads, pads[1], teleportToSite)
        local starts = { "(pick a landing pad)" }
        for i = 2, #pads do starts[#starts + 1] = pads[i] end
        row("start", "Start at this landing pad next time the map loads (experimental)", starts, starts[1], setStartSite)
        pcall(function()
            local sl = box:AddChildToVerticalBox(line("OK_TrainerFoot", { R = 0.36, G = 0.92, B = 1, A = 0.6 }, 1))
            sl:SetPadding({ Left = 0, Top = 14, Right = 0, Bottom = 6 })
        end)
        pcall(function()
            local ht = text("DAH2P_TrainerHint", hint, 13, CY)
            local sl = box:AddChildToVerticalBox(ht)
            sl:SetHorizontalAlignment(3)
        end)
        -- Active page: everything that's switched on, each with a quick way back to normal
        if PAGES[page] == "Active" and not collect then
            local SKIP = { page = true, spawn = true, despawn = true, tp = true, save = true, spawncount = true, x_p2skin = true }
            local keys = {}
            for k, v in pairs(state.trNow or {}) do
                local opts = state.trOpts and state.trOpts[k]
                if not SKIP[k] and opts and v ~= opts[1] and not tostring(v):find("^%(") then keys[#keys + 1] = k end
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local opts, cur = state.trOpts[k], state.trNow[k]
                local ak = "act_" .. k
                PAGE_OF[ak] = page
                row(ak, state.trLabel[k] or k, { cur, opts[1] }, cur, function(v)
                    if v == nil or v == "" then return end
                local ok, err = pcall(state.trApply[k], v)
                    if ok then
                        state.trNow[k] = v
                        if state.trainerApplied then pcall(state.trainerApplied, k, v) end
                    else log("Trainer: %s failed: %s", k, tostring(err)) end
                end)
            end
            if #keys == 0 then
                PAGE_OF.act_none = page
                row("act_none", "Nothing is switched on. Changes from the other pages show up here.", { "-" }, "-", function() end)
            end
        end
        if collect then menu = nil; return end   -- only wanted the list of options (to load saved settings)
        pcall(function() tree.RootWidget = border end)
        pcall(function() border:SetVisibility(0) end)
        pcall(function() w:SetVisibility(0) end)          -- the borrowed widget hides itself by default
        pcall(function() w:SetRenderOpacity(1.0) end)
        local okA = pcall(function() w:AddToViewport(200) end)
        pcall(function() w:SetDesiredSizeInViewport({ X = 880, Y = 1040 }) end)
        pcall(function() w:SetAlignmentInViewport({ X = 0, Y = 0 }) end)
        pcall(function() w:SetPositionInViewport({ X = 40, Y = 20 }, true) end)
        local okIn, inVp = pcall(function() return w:IsInViewport() end)
        log("Trainer menu: added %s, in viewport %s", tostring(okA), okIn and tostring(inVp) or "?")
        if padMode then
            local pw = getPawn(pc)
            if valid(pw) then pcall(function() pw:DisableInput(pc) end) end   -- Player 1 stands still while choosing
        else
            pcall(function() wbl:SetInputMode_UIOnlyEx(pc, w, 0) end)
            pcall(function() pc.bShowMouseCursor = true end)
        end
        -- back on the row you were on last time on this page
        local sc0 = state.trCursorOf and state.trCursorOf[page]
        if type(sc0) == "number" and sc0 >= 1 and sc0 <= #menu.order then menu.cursor = sc0 end
        highlight()
        state.trainerOpen = true
        state.trainerWidget = w
        log("Trainer menu open (%s, %d landing pads)", padMode and "controller" or "mouse", #pads - 1)
    end

    addTickJob("trainerMenu", 0.1, function()
        if not menu then return end
        if not valid(menu.widget) then menu = nil return end
        local pc = player1Controller()
        if not menu.pad then
            -- the game switches back to game-only input every so often: take the mouse back
            local okC, shown = pcall(function() return pc.bShowMouseCursor end)
            if okC and not shown then
                local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
                pcall(function() wbl:SetInputMode_UIOnlyEx(pc, menu.widget, 0) end)
                pcall(function() pc.bShowMouseCursor = true end)
            end
        end
        pcall(function() if not menu.widget:IsVisible() then menu.widget:SetVisibility(0); menu.widget:SetRenderOpacity(1.0) end end)
        for key, c in pairs(menu.combos) do
            local okS, sel = pcall(function() return c:GetSelectedOption():ToString() end)
            if not okS then okS, sel = pcall(function() return tostring(c:GetSelectedOption()) end) end
            if okS and sel and sel ~= menu.last[key] then
                menu.last[key] = sel
                if not sel:find("^%(") then
                    if key == "time" then state.trTime = sel elseif key == "fog" then state.trFog = sel
                    elseif key == "speed" then state.trSpeed = sel elseif key == "gravity" then state.trGravity = sel end
                    local ok, err = pcall(menu.actions[key], sel)
                    if not ok then log("Trainer: %s failed: %s", key, tostring(err)) end
                    if ok and state.trainerApplied then pcall(state.trainerApplied, key, sel) end
                end
            end
        end
    end)

    state.trainerOnDown = function()
        if menu then pcall(closeMenu) end
        pcall(function() if state.p2SaucerOff then state.p2SaucerOff() end end)
        pcall(function() applyP1Saucer("On foot") end)
        if state.trUfoWeap and state.trUfoWeap ~= "Off" then pcall(function() setSaucerWeapons(false) end); state.trUfoWeap = nil end
    end
    -- re-apply sizes to a new body after a respawn (the game swaps the character)
    addTickJob("trainerSizeKeep", 1.0, function()
        for who = 1, 2 do
            local label = who == 1 and state.trSize1 or state.trSize2
            local pc = who == 1 and player1Controller() or state.p2
            local pw = valid(pc) and getPawn(pc) or nil
            if label and label ~= "Normal" and valid(pw) then
                local k = keyOf(pw)
                state.sizeOn = state.sizeOn or {}
                if state.sizeOn[who] ~= k then state.sizeOn[who] = k; applySize(who, label) end
            end
        end
    end)
    -- Everything back to normal (before any map change: mothership, new region, mission).
    state.trainerResetAll = function()
        local function try(label, fn) local ok, err = pcall(fn); if not ok then log("  reset %s: %s", label, tostring(err)) end end
        if menu then try("menu", closeMenu) end
        try("p2 saucer", function() if state.p2SaucerOff then state.p2SaucerOff() end end)
        try("p1 saucer", function() applyP1Saucer("On foot") end)
        try("saucer weapons", function() setSaucerWeapons(false) end)
        try("ammo", function() setInfiniteAmmo(false) end)
        try("holobob", function() setHolobob(false) end)
        try("hypnosis", function() setHypnosis(false) end)
        try("ignore", function() if state.trIgnore == "On" then applyIgnore("Off") end end)
        try("riot", function() if state.trRiot and state.trRiot ~= "Off" then applyRiot("Off") end end)
        try("wanted", function() if state.trWanted and state.trWanted ~= "Game decides" then applyWanted("Game decides") end end)
        try("size", function()
            if state.trSize1 and state.trSize1 ~= "Normal" then applySize(1, "Normal") end
            if state.trSize2 and state.trSize2 ~= "Normal" then applySize(2, "Normal") end
        end)
        state.trAmmo, state.trGod, state.trFuel, state.trHolo, state.trHyp, state.trUfoWeap = nil, nil, nil, nil, nil, nil
        state.trBounds, state.trIgnore, state.trWanted, state.trSize1, state.trSize2, state.trRiot = nil, nil, nil, nil, nil, nil
        state.trTime, state.trFog, state.trSpeed, state.trGravity = nil, nil, nil, nil
        for _, e in ipairs(state.trainerExtras or {}) do
            if e.reset then try(e.key, e.reset) end
        end
        saved = nil
        log("Trainer: everything switched back to normal")
    end

    -- Saved trainer settings: overkill_coop_settings.txt next to the game exe (never the game's
    -- save). Lighting, fog, time of day and the start pad are remembered per map. Loaded a few
    -- seconds after each map starts, while "Remember trainer settings" is On.
    do
        local FILE = "overkill_coop_settings.txt"
        local PER_MAP = { time = true, set = true, fog = true, start = true }
        local NOT_SAVED = { page = true, spawn = true, despawn = true, tp = true, foreign = true, save = true, p1ufo = true, p2ufo = true,
            j_play = true, j_station = true, j_track = true, j_gamesong = true }   -- songs are never remembered
        local settings = {}
        local function load()
            settings = {}
            local f = io.open(FILE, "r")
            if not f then return end
            for line in f:lines() do
                local k, v = line:match("^([^=#]+)=(.*)$")
                if k then settings[k] = v end
            end
            f:close()
        end
        local function save()
            local keys = {}
            for k in pairs(settings) do keys[#keys + 1] = k end
            table.sort(keys)
            local f = io.open(FILE, "w")
            if not f then return end
            f:write("# Third Eye Decalcified Co-op trainer settings (delete this file to start fresh)\n")
            for _, k in ipairs(keys) do f:write(k, "=", settings[k], "\n") end
            f:close()
        end
        load()
        -- the mod music never starts by itself from a saved setting
        if settings.j_play or settings.j_station or settings.j_track or settings.j_gamesong then
            settings.j_play, settings.j_station, settings.j_track, settings.j_gamesong = nil, nil, nil, nil   -- songs never start by themselves
            save()
        end
        local function mapName()
            local wn = ""
            pcall(function() wn = nameOf(getWorld()) end)
            return wn:match("([%w_]+)$") or "map"
        end
        local function slot(key) return PER_MAP[key] and ("map." .. mapName() .. "." .. key) or key end
        state.trSaveOn = settings.save ~= "Off"
        state.trainerApplied = function(key, value)
            if key:sub(1, 4) == "act_" then return end
            if value == nil or value == "" then return end   -- an empty choice is never a setting
            if state.trNow then state.trNow[key] = value end
            if key == "save" then
                state.trSaveOn = value == "On"
                settings.save = value
                save()
                return
            end
            -- a saved row follows what you change it to; others are only saved with X
            if settings[slot(key)] ~= nil and not NOT_SAVED[key] then
                settings[slot(key)] = value
                save()
            end
        end
        state.trIsSaved = function(key) return not NOT_SAVED[key] and settings[slot(key)] ~= nil end
        state.trCanSave = function(key) return not NOT_SAVED[key] and key:sub(1, 4) ~= "act_" end
        -- X on a row: remember its value (or forget it if it's already remembered)
        state.trainerSaveKey = function(key, value)
            if not state.trCanSave(key) then return nil end
            if settings[slot(key)] ~= nil then
                settings[slot(key)] = nil
                save()
                log("Trainer: %s forgotten", key)
                return false
            end
            settings[slot(key)] = value
            save()
            log("Trainer: %s = %s saved%s", key, value, PER_MAP[key] and (" for " .. mapName()) or "")
            return true
        end
        local function restore()
            if not state.trSaveOn then return end
            local wn = ""
            pcall(function() wn = nameOf(getWorld()) end)
            if wn == "" or wn:find("/Menus/", 1, true) or menu then return end
            if state.trRestoredFor == wn and os.clock() - (state.trRestoredAt or -100) < 30 then return end
            state.trRestoredFor, state.trRestoredAt = wn, os.clock()
            pcall(openMenu, true, 1, true)              -- fills state.trApply without showing anything
            local n = 0
            for key, action in pairs(state.trApply or {}) do
                local v = settings[slot(key)]
                if v == "" then settings[slot(key)] = nil; v = nil end   -- a bad empty save from before
                if v and not NOT_SAVED[key] then
                    if key == "time" then state.trTime = v elseif key == "fog" then state.trFog = v
                    elseif key == "speed" then state.trSpeed = v elseif key == "gravity" then state.trGravity = v end
                    local ok, err = pcall(action, v)
                    if ok then n = n + 1 else log("Saved settings: %s = %s failed: %s", key, v, tostring(err)) end
                end
            end
            -- favourite landing pad: also go there now (the game only uses it on the next load)
            local fav = settings[slot("start")]
            if fav and state.trApply and state.trApply.tp then
                local ok, err = pcall(state.trApply.tp, fav)
                log("Saved settings: favourite pad %s %s", fav, ok and "" or tostring(err))
            end
            if n > 0 then log("Saved settings: %d loaded for %s", n, mapName()) end
        end
        onWorldChange(function()
            -- "NPCs ignore you" can't wait for the rest: on straight away
            if state.trSaveOn and settings[slot("ignore")] == "On" then state.trIgnore = "On" end
            later(CFG.TRAINER_RESTORE_DELAY or 8, "savedSettings", restore)
        end)
    end

    RegisterKeyBind(Key.M, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        runGame("trainerMenu", function() if menu then closeMenu() else openMenu(false) end end)
    end)

    -- Player 1's controller: Select + R3 together opens/closes; D-pad + A drives it.
    local held = {}
    -- rows where "default" makes no sense (actions, not settings)
    local NO_DEFAULT = { page = true, spawn = true, despawn = true, tp = true, spawncount = true, save = true }
    -- a short green flash on the row that was just switched on / changed
    local function flashRow(key)
        local bar = menu and menu.bars and menu.bars[key]
        if not bar then return end
        pcall(function() bar:SetBrushColor({ R = 0.15, G = 0.85, B = 0.3, A = 0.8 }) end)
        later(0.35, "trainerFlash", function() if menu then highlight() end end)
    end
    local function edge(pc, k)
        local d = kbDown(pc, k)
        local was = held[k]
        held[k] = d
        return d and not was
    end
    addTickJob("trainerPad", 0.0, function()
        if not CFG.TRAINER_PAD then return end
        local pc = player1Controller()
        if not valid(pc) then return end
        local combo = CFG.TRAINER_PAD_COMBO
        local both = kbDown(pc, combo[1]) and kbDown(pc, combo[2])
        if both and not held.combo then
            held.combo = true
            if menu then closeMenu() else openMenu(true) end
            return
        end
        if not both then held.combo = false end
        if not (menu and menu.pad) then
            for _, k in ipairs({ "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
                                 "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
                                 "Gamepad_LeftShoulder", "Gamepad_RightShoulder" }) do held[k] = kbDown(pc, k) end
            return
        end
        if edge(pc, "Gamepad_RightShoulder") then switchPage(true, tabStep(menu.page, 1)) return end
        if edge(pc, "Gamepad_LeftShoulder") then switchPage(true, tabStep(menu.page, -1)) return end
        local n = #menu.order
        if n == 0 then
            if edge(pc, "Gamepad_FaceButton_Right") then closeMenu() end
            return
        end
        -- D-pad: a press moves at once; holding it repeats
        local now = os.clock()
        local function pressRepeat(k)
            local d = kbDown(pc, k)
            local rk = "rep_" .. k
            if d and not held[k] then held[k] = true; held[rk] = now + 0.25; return true end
            if not d then held[k] = false; return false end
            if now >= (held[rk] or 0) then held[rk] = now + 0.045; return true end   -- held: runs down the list fast
            return false
        end
        local goDown = pressRepeat("Gamepad_DPad_Down")
        local goUp = pressRepeat("Gamepad_DPad_Up")
        local goRight = pressRepeat("Gamepad_DPad_Right")
        local goLeft = pressRepeat("Gamepad_DPad_Left")
        if goDown then menu.cursor = menu.cursor % n + 1; highlight() end
        if goUp then menu.cursor = (menu.cursor - 2) % n + 1; highlight() end
        local key = menu.order[menu.cursor]
        local opts = menu.opts[key]
        local c = menu.combos[key]
        local step = 0
        if goRight then step = 1 end
        if goLeft then step = -1 end
        if step ~= 0 and opts and c then
            local okS, cur = pcall(function() return c:GetSelectedOption():ToString() end)
            local idx = 1
            for i, o in ipairs(opts) do if okS and o == cur then idx = i end end
            idx = (idx - 1 + step) % #opts + 1
            pcall(function() c:SetSelectedOption(opts[idx]) end)
            menu.last[key] = opts[idx]          -- shown only; A applies it
            highlight()
        end
        if edge(pc, "Gamepad_FaceButton_Bottom") and c then
            local okS, cur = pcall(function() return c:GetSelectedOption():ToString() end)
            if okS and cur and cur ~= "" and not cur:find("^%(") then
                if key == "time" then state.trTime = cur elseif key == "fog" then state.trFog = cur
                elseif key == "speed" then state.trSpeed = cur elseif key == "gravity" then state.trGravity = cur end
                local ok, err = pcall(menu.actions[key], cur)
                log("Trainer (pad): %s = %s %s", key, cur, ok and "" or tostring(err))
                if ok and state.trainerApplied then pcall(state.trainerApplied, key, cur) end
                if ok then flashRow(key) end
            end
        end
        -- Y: this row back to its default (the first choice in its list)
        if edge(pc, "Gamepad_FaceButton_Top") and c and opts and opts[1] and not NO_DEFAULT[key] and menu.actions[key] then
            local def = opts[1]
            if key:sub(1, 4) == "act_" then def = opts[2] or opts[1] end   -- Active page: { now, default }
            if not def:find("^%(") then
                pcall(function() c:SetSelectedOption(def) end)
                menu.last[key] = def
                if key == "time" then state.trTime = def elseif key == "fog" then state.trFog = def
                elseif key == "speed" then state.trSpeed = def elseif key == "gravity" then state.trGravity = def end
                local ok, err = pcall(menu.actions[key], def)
                log("Trainer (pad): %s back to default (%s) %s", key, def, ok and "" or tostring(err))
                if ok and state.trainerApplied then pcall(state.trainerApplied, key, def) end
                highlight()
                if ok then flashRow(key) end
            end
        end
        if edge(pc, "Gamepad_FaceButton_Left") and c and state.trainerSaveKey then
            local okS, cur = pcall(function() return c:GetSelectedOption():ToString() end)
            if okS and cur and cur ~= "" and not cur:find("^%(") then
                local wasSaved = state.trIsSaved(key)
                -- saving a value also puts it on, so what's saved is what you see
                if not wasSaved and menu.last[key] ~= nil and menu.actions[key] then
                    if key == "time" then state.trTime = cur elseif key == "fog" then state.trFog = cur
                    elseif key == "speed" then state.trSpeed = cur elseif key == "gravity" then state.trGravity = cur end
                    pcall(menu.actions[key], cur)
                end
                pcall(state.trainerSaveKey, key, cur)
                highlight()
            end
        end
        if edge(pc, "Gamepad_FaceButton_Right") then closeMenu() end
    end)
end)()

log("Keys: skins Delete = P2, End = P3, Insert = P4 | Ctrl+E aim report | Ctrl+Shift+W world scan | Ctrl+Shift+M trainer menu")

-- Shared with the other parts of the mod (the mind & weapons wheel)
OverkillCoop = {
    state = state, CFG = CFG, log = log, valid = valid, nameOf = nameOf, shortName = shortName,
    subObj = subObj, getPawn = getPawn, kbDown = kbDown, player1Controller = player1Controller,
    hudWidgetsOf = hudWidgetsOf, addTickJob = addTickJob, onWorldChange = onWorldChange,
    getWorld = getWorld, getStatics = getStatics, arrayToList = arrayToList, keyOf = keyOf,
    runGame = runGame, later = later, stat = stat, setRatio = setRatio, healthRatio = healthRatio,
}

-- Test recorder tick and the Guide-button snapshot request (see state.snapshot)
;(function()
    local last, reqAt = nil, 0
    local function nm(x) return (x and valid(x)) and shortName(x):gsub("^BP_Character_", ""):gsub("_Base_C_", "_") or "-" end
    local function pkOf(pc)
        local mental = subObj(getPawn(pc), "m_pMentalAbilityComponent")
        if not mental then return nil, nil end
        for _, ab in ipairs(state.p2Abilities(mental)) do
            if valid(ab) and nameOf(ab):find("kinesis") then
                local okA, a = pcall(function() return ab.m_pCurrentAimTarget end)
                local okH, h = pcall(function() return ab:GetCurrentHoveredActor() end)
                local okT, held = pcall(function() return ab.m_pActiveTarget end)
                return (okA and a or nil), (okH and h or nil), (okT and valid(held))
            end
        end
    end
    addTickJob("testRecorder", 0.25, function()
        if not CFG.TEST_RECORDER then return end
        local parts = {}
        for i, pc in ipairs({ player1Controller(), state.p2 }) do
            if valid(pc) then
                local a, h, holding = pkOf(pc)
                local f = subObj(getPawn(pc), "m_pFocusComponent")
                local okF, ft = pcall(function() return f and f.m_pCurrentAutoLockTarget end)
                local mc = subObj(getPawn(pc), "m_pMentalAbilityComponent")
                local okM, ma = pcall(function() return mc and mc.m_pCurrentAimTarget end)
                parts[#parts + 1] = string.format("P%d PKaim=%s hover=%s%s shared=%s", i, nm(a), nm(h), holding and " HOLDING" or "", nm(okM and ma or nil))
            end
        end
        pcall(function()
            local gs = FindFirstOf("GameStateBase")
            local pp = gs.m_pLastKnownPrimaryPlayerPawn
            parts[#parts + 1] = "| primary=" .. ((valid(pp) and keyOf(pp) == keyOf(getPawn(player1Controller()))) and "P1" or (valid(pp) and "P2" or "-"))
        end)
        if valid(state.p2) then
            parts[#parts + 1] = string.format("| P2 arcs=%s bracket=%s (game %s x%d, mod %s)", nm(state.p2PKLock), nm(state.p2BracketOn), nm(state.p2GameGun), state.p2GameGunN or 0, nm(state.p2ModLock))
        end
        local line = table.concat(parts, "  ")
        local now = os.clock()
        if line ~= last then
            last = line
            local b = state.recBuf
            b[#b + 1] = { t = now, s = line }
        end
        while #state.recBuf > 0 and now - state.recBuf[1].t > 12 do table.remove(state.recBuf, 1) end
        -- Guide button (the DLL writes this file)
        if now >= reqAt then
            reqAt = now + 0.25
            for _, path in ipairs({ "padrouter_snapshot_request.txt", "ue4ss/padrouter_snapshot_request.txt" }) do
                local f = io.open(path, "r")
                if f then
                    local txt = f:read("*a") or ""
                    f:close()
                    os.remove(path)
                    local pad = txt:match("snapshot(%d)")
                    if pad then state.snapshot("Guide button, pad " .. pad) end
                end
            end
        end
    end)
end)()

-- Player 2's PK reach to the sides, and the health bar of Player 2's gun target
;(function()
    local widened = {}
    onWorldChange(function() widened = {} end)
    addTickJob("p2PKWiden", 2.0, function()
        if not valid(state.p2) then return end
        local mental = subObj(getPawn(state.p2), "m_pMentalAbilityComponent")
        local k = mental and keyOf(mental)
        if not k or widened[k] then return end
        local ok, v = pcall(function() return mental.m_fMaxRangeAutoTargetPercent2D end)
        if ok and type(v) == "number" and v > 0 then
            widened[k] = true
            local nv = v * CFG.P2_PK_AIM_WIDEN
            pcall(function() mental.m_fMaxRangeAutoTargetPercent2D = nv end)
            log("P2 PK reach to the sides: %.3f -> %.3f", v, nv)
        end
    end)

    -- Each person's health bar is a screen widget on that person, drawn for one player only
    -- (Player 1 by default), so Player 2 never saw one. While Player 2's gun is locked on to
    -- someone Player 1 isn't, their bar is handed to Player 2's screen, and back afterwards.
    local cur, curComp, wcClass = nil, nil, nil
    local function healthComp(actor)
        local hb = subObj(actor, "m_pHealthBarComponent")
        if hb then return hb end
        wcClass = wcClass or StaticFindObject("/Script/UMG.WidgetComponent")
        if not wcClass then return nil end
        local found = nil
        pcall(function()
            local list = actor:K2_GetComponentsByClass(wcClass)
            for _, c in ipairs(arrayToList(list)) do
                local okW, w = pcall(function() return c:GetUserWidgetObject() end)
                if okW and valid(w) and nameOf(w):find("HealthIndicator") then found = c break end
            end
        end)
        return found
    end
    local function giveBack()
        if curComp and valid(curComp) then
            pcall(function() curComp:DisableWidget() end)
            pcall(function() curComp:SetOwnerPlayer(player1Controller().Player) end)
        end
        cur, curComp = nil, nil
    end
    onWorldChange(function() cur, curComp = nil, nil end); state.onP2Leave(giveBack)
    addTickJob("p2TargetHealth", 0.1, function()
        if not (CFG.P2_TARGET_HEALTH and valid(state.p2)) then if cur then giveBack() end return end
        local t = state.p2BracketOn
        if not (valid(t) and not state.deadChar(t)) then if cur then giveBack() end return end
        -- Player 1 is looking at the same one: leave it on Player 1's screen
        local p1Same = false
        pcall(function()
            local eq = subObj(getPawn(player1Controller()), "m_pEquipmentManagerComponent")
            for _, x in ipairs(arrayToList(eq:GetCurrentWeapon().m_apCurrentLockedTargets)) do
                if valid(x) and keyOf(x) == keyOf(t) then p1Same = true end
            end
        end)
        if p1Same then if cur then giveBack() end return end
        if cur ~= keyOf(t) then
            giveBack()
            local c = healthComp(t)
            if not c then
                cur = keyOf(t)
                if (state.p2HealthLogs or 0) < 3 then state.p2HealthLogs = (state.p2HealthLogs or 0) + 1; log("P2 target health bar: %s has none", shortName(t)) end
                return
            end
            cur, curComp = keyOf(t), c
            pcall(function() c:DisableWidget() end)
            local okO = pcall(function() c:SetOwnerPlayer(state.p2.Player) end)
            pcall(function() c:EnsureWidgetInitialized() end)
            pcall(function() c:EnableWidget() end)
            local okW, w = pcall(function() return c:GetUserWidgetObject() end)
            if okW and valid(w) then pcall(function() w:ShowWidget() end) end
            if (state.p2HealthLogs or 0) < 3 then
                state.p2HealthLogs = (state.p2HealthLogs or 0) + 1
                log("P2 target health bar: %s (%s) owner %s, widget %s", shortName(t), shortName(c), okO and "set" or "failed",
                    (okW and valid(w)) and shortName(w) or "none")
            end
        elseif curComp and valid(curComp) then
            pcall(function() curComp:SetVisibility(true, false) end)
        end
    end)
end)()

-- Two players: a detail profile for the smaller half-screen views (on join, off on leave)
;(function()
    local on = false
    local function set(want)
        if want == on then return end
        on = want
        for _, c in ipairs(want and CFG.SPLIT_LOD_COMMANDS or CFG.SPLIT_LOD_RESET) do runConsole(c) end
        log("Split-screen detail profile: %s", want and "on" or "off")
    end
    state.onP2Leave(function() set(false) end)
    addTickJob("splitLod", 2.0, function()
        if state.lodForced then return end   -- Ctrl+F3's forced LOD wins
        set(CFG.SPLIT_LOD_PROFILE and valid(state.p2) or false)
    end)
end)()

-- Two players: cars swap to empty low-detail shells (no driver) by distance from Player 1
-- only; push those distances out so Player 2's area keeps real traffic
;(function()
    local done = {}
    onWorldChange(function() done = {} end)
    local function scale(v, m)
        local okC, cfgS = pcall(function() return v.Config end)
        if not (okC and cfgS) then return false end
        local ok = true
        for _, f in ipairs({ "m_fLODStart", "m_fLODEnd" }) do
            local okR, x = pcall(function() return cfgS[f] end)
            if okR and type(x) == "number" then
                local okW = pcall(function() cfgS[f] = x * m end)
                ok = ok and okW
            else
                ok = false
            end
        end
        return ok
    end
    state.onP2Leave(function()
        for _, e in pairs(done) do if valid(e.v) then scale(e.v, 1 / e.m) end end
        done = {}
    end)
    addTickJob("splitVehicleLod", 3.0, function()
        local m = CFG.SPLIT_VEHICLE_LOD_MULT or 1
        if not (valid(state.p2) and m > 1) then return end
        local list = {}
        for _, cn in ipairs({ "BP_BasicVehicle_C", "BP_BasicVehicle_Police_C", "BFGBasicVehicle" }) do
            for _, v in ipairs(FindAllOf(cn) or {}) do list[#list + 1] = v end
        end
        local n = 0
        for _, v in ipairs(list) do
            if valid(v) then
                local k = keyOf(v)
                if k and not done[k] then
                    if scale(v, m) then done[k] = { v = v, m = m }; n = n + 1 end
                end
            end
        end
        if n > 0 and not state.vehLodLogged then
            state.vehLodLogged = true
            local v1 = nil
            for _, e in pairs(done) do v1 = e.v break end
            local okA, a = pcall(function() return v1.Config.m_fLODStart end)
            local okB, b = pcall(function() return v1.Config.m_fLODEnd end)
            log("Split-screen cars: %d cars keep detail further out (first: LOD %s .. %s)", n, okA and tostring(a) or "?", okB and tostring(b) or "?")
        end
    end)
end)()

-- Tests from the other games' data
;(function()
    local function pkAbility(pawn)
        local mental = subObj(pawn, "m_pMentalAbilityComponent")
        if not mental then return nil end
        for _, ab in ipairs(state.p2Abilities(mental)) do
            if valid(ab) and nameOf(ab):find("kinesis") then return ab end
        end
    end
    local function holding(ab)
        local ok, t = pcall(function() return ab and ab.m_pActiveTarget end)
        return ok and valid(t)
    end
    -- Clone Carnage's traffic/crowd system keeps every player's PK; this game's keeps one (Player
    -- 1's), so a person or car lifted by Player 2 is still treated as walking/driving its path
    -- (it fights the lift: the "pushed away, on and off" pickups). Point it at whoever is holding.
    local cachedFor = nil
    addTickJob("pkCrowdPerPlayer", 0.05, function()
        if not (CFG.PK_CROWD_PER_PLAYER and valid(state.p2)) then return end
        local gs = FindFirstOf("GameStateBase")
        local okT, tm = pcall(function() return gs:GetTrafficCrowdManager() end)
        if not (okT and valid(tm)) then return end
        local a1, a2 = pkAbility(getPawn(player1Controller())), pkAbility(getPawn(state.p2))
        local want = (holding(a2) and not holding(a1)) and a2 or a1
        if want and keyOf(want) ~= cachedFor then
            local ok = pcall(function() tm.m_pCachedPKComponent = want end)
            cachedFor = keyOf(want)
            if (state.pkCrowdLogs or 0) < 6 then
                state.pkCrowdLogs = (state.pkCrowdLogs or 0) + 1
                log("Crowd system PK -> %s (%s)", want == a2 and "Player 2" or "Player 1", ok and "ok" or "failed")
            end
        end
    end)
    state.onP2Leave(function()
        pcall(function()
            local tm = FindFirstOf("GameStateBase"):GetTrafficCrowdManager()
            local a1 = pkAbility(getPawn(player1Controller()))
            if a1 then tm.m_pCachedPKComponent = a1 end
        end)
        cachedFor = nil
    end)

    -- Player 2's gun and mind powers share one aim target; when that is a prop (what PK is
    -- aimed at), the Zap-O-Matic went for it. Clear it for the zap while it's not a person.
    local charCls = nil
    addTickJob("p2ZapNoProps", 0.0, function()
        if not (CFG.P2_ZAP_NO_PROPS and valid(state.p2)) then return end
        local pawn = getPawn(state.p2)
        local eq = subObj(pawn, "m_pEquipmentManagerComponent")
        local okW, w = pcall(function() return eq:GetCurrentWeapon() end)
        if not (okW and valid(w)) then
            pcall(function() w = arrayToList(eq:GetCurrentWeapons())[1] end)
        end
        if not (valid(w) and nameOf(w):find("Zap")) then
            if not state.zapNoPropWhy and valid(w) then state.zapNoPropWhy = true; log("P2 zap side limit: weapon in hand is %s", shortName(w)) end
            return
        end
        local mental = subObj(pawn, "m_pMentalAbilityComponent")
        local okA, t = pcall(function() return mental and mental.m_pCurrentAimTarget end)
        if not (okA and valid(t)) then return end
        charCls = charCls or StaticFindObject("/Script/Engine.Character")
        local okC, isChar = pcall(function() return t:IsA(charCls) end)
        -- (PK reaches further to the sides for Player 2; the zap shouldn't follow it out there)
        local tooWide = false
        pcall(function()
            local loc = state.targetPoint(t)
            local cm = state.p2.PlayerCameraManager
            local c, r = cm:GetCameraLocation(), cm:GetCameraRotation()
            local yaw, pitch = math.rad(r.Yaw), math.rad(r.Pitch)
            local far = { X = c.X + math.cos(pitch) * math.cos(yaw) * 5000, Y = c.Y + math.cos(pitch) * math.sin(yaw) * 5000, Z = c.Z + math.sin(pitch) * 5000 }
            local mid, tp = {}, {}
            if state.p2:ProjectWorldLocationToScreen(far, mid, true) and state.p2:ProjectWorldLocationToScreen(loc, tp, true) and mid.X > 0 then
                local cx, cy = mid.X, mid.Y * (1 + CFG.P2_CROSSHAIR_RAISE)
                local dx, dy = (tp.X - cx) / (2 * mid.X), (tp.Y - cy) / (2 * mid.X)
                tooWide = math.sqrt(dx * dx + dy * dy) > CFG.P2_ZAP_SIDE_LIMIT
            end
        end)
        if (okC and not isChar) or tooWide then
            pcall(function() mental.m_pCurrentAimTarget = nil end)
            state.zapIgnored = (state.zapIgnored or 0) + 1
            if state.zapIgnored <= 5 then log("P2 zap: ignored %s as the zap's target (%s)", shortName(t), tooWide and "too far to the side" or "a prop") end
        end
    end)
end)()

-- Snapshot extras: who and what is around each player (for the LOD / spawning tests), and
-- what each player's radar is tied to
state.populationReport = function()
    if not valid(state.p2) then return end
    local pcs = { player1Controller(), state.p2 }
    local pawns, locs = {}, {}
    for i, pc in ipairs(pcs) do
        pawns[i] = getPawn(pc)
        local ok, l = pcall(function() return pawns[i]:K2_GetActorLocation() end)
        locs[i] = ok and l or nil
    end
    if not (locs[1] and locs[2]) then return end
    local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    -- how the players stand to each other
    local apart = dist(locs[1], locs[2]) / 100
    local function facing(i, j)
        local ok, r = pcall(function() return pcs[i].PlayerCameraManager:GetCameraRotation() end)
        if not ok then return "?" end
        local yaw = math.rad(r.Yaw)
        local dx, dy = locs[j].X - locs[i].X, locs[j].Y - locs[i].Y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local cosA = (math.cos(yaw) * dx + math.sin(yaw) * dy) / len
        return string.format("%.0f deg", math.deg(math.acos(math.max(-1, math.min(1, cosA)))))
    end
    local okS, seen = pcall(function() return pcs[1]:LineOfSightTo(pawns[2], { X = 0, Y = 0, Z = 0 }, false) end)
    log("  players: %.0f m apart | P1 looks %s away from P2, P2 looks %s away from P1 | clear line between them: %s",
        apart, facing(1, 2), facing(2, 1), okS and tostring(seen) or "?")
    -- people and cars around each player
    local chars, cars = {}, {}
    pcall(function()
        local out = {}
        getStatics():GetAllActorsOfClass(getWorld(), StaticFindObject("/Script/Engine.Character"), out)
        for _, a in ipairs(out) do
            local v = a
            if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
            if valid(v) and not state.notTargetable(v) then chars[#chars + 1] = v end
        end
    end)
    for _, cn in ipairs({ "BP_BasicVehicle_C", "BP_BasicVehicle_Police_C" }) do
        for _, v in ipairs(FindAllOf(cn) or {}) do if valid(v) then cars[#cars + 1] = v end end
    end
    local rings = { 30, 60, 120 }
    for i = 1, 2 do
        local cP, cH, vP, vE = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }
        for _, c in ipairs(chars) do
            local okL, l = pcall(function() return c:K2_GetActorLocation() end)
            if okL and l and not state.deadChar(c) then
                local d = dist(l, locs[i]) / 100
                local okH, hid = pcall(function() return c.bHidden end)
                for r, m in ipairs(rings) do
                    if d <= m then
                        cP[r] = cP[r] + 1
                        if okH and hid then cH[r] = cH[r] + 1 end
                    end
                end
            end
        end
        for _, v in ipairs(cars) do
            local okL, l = pcall(function() return v:K2_GetActorLocation() end)
            if okL and l then
                local d = dist(l, locs[i]) / 100
                local riders = 0
                pcall(function()
                    local out = {}
                    v:GetAttachedActors(out)
                    for _, x in ipairs(out) do
                        local okC, isC = pcall(function() return x:IsA(StaticFindObject("/Script/Engine.Character")) end)
                        if okC and isC then riders = riders + 1 end
                    end
                end)
                for r, m in ipairs(rings) do
                    if d <= m then
                        vP[r] = vP[r] + 1
                        if riders == 0 then vE[r] = vE[r] + 1 end
                    end
                end
            end
        end
        log("  around P%d (30 / 60 / 120 m): people %d/%d/%d (hidden %d/%d/%d) | cars %d/%d/%d (no one inside %d/%d/%d)",
            i, cP[1], cP[2], cP[3], cH[1], cH[2], cH[3], vP[1], vP[2], vP[3], vE[1], vE[2], vE[3])
    end
end

state.radarReport = function()
    pcall(function()
        local gs = FindFirstOf("GameStateBase")
        log("  game's primary player: %s", shortName(gs.m_pLastKnownPrimaryPlayerPawn))
    end)
    for i, pc in ipairs({ player1Controller(), state.p2 }) do
        if valid(pc) then
            for _, hud in ipairs(hudWidgetsOf(pc)) do
                local mm = subObj(hud, "BPW_UI_Minimap")
                local radar = mm and subObj(mm, "BPW_UI_HUDRadar")
                if radar then
                    local bits = {}
                    forEachObjectProperty(radar, function(name)
                        local okV, v = pcall(function() return radar[name] end)
                        if okV and valid(v) then
                            local n = shortName(v)
                            if n:find("Player") or n:find("Controller") or n:find("Camera") or n:find("Pawn") or n:find("Radar") or n:find("Hud") or n:find("HUD") then
                                bits[#bits + 1] = name .. "=" .. n
                            end
                        end
                    end)
                    local okO, own = pcall(function() return radar:GetOwningPlayer() end)
                    log("  radar on P%d's HUD (%s): owner %s | %s", i, shortName(hud), (okO and valid(own)) and shortName(own) or "-", table.concat(bits, ", "))
                end
            end
        end
    end
end

-- Test tool for the DLL work: find the game code that reads Player 1's camera (the crowd /
-- traffic detail decides from it). The pad router DLL watches Player 1's camera position for
-- a few seconds and logs which code read it. Runs once 40 s after Player 2 joins; Ctrl+F7 again.
;(function()
    local function start(secs)
        local pcm = subObj(player1Controller(), "PlayerCameraManager")
        if not pcm then log("Camera watch: no camera") return end
        local off = nil
        pcall(function()
            local cls = pcm:GetClass()
            local depth = 0
            while valid(cls) and depth < 8 and not off do
                cls:ForEachProperty(function(prop)
                    local okN, n = pcall(function() return prop:GetFName():ToString() end)
                    if okN and n == "CameraCachePrivate" then off = prop:GetOffset_Internal() end
                end)
                cls = cls:GetSuperStruct()
                depth = depth + 1
            end
        end)
        local okA, addr = pcall(function() return pcm:GetAddress() end)
        local okL, loc = pcall(function() return pcm:GetCameraLocation() end)
        if not (off and okA and okL and loc) then log("Camera watch: couldn't find the camera data (offset %s)", tostring(off)) return end
        local f = io.open("padrouter_watch_request.txt", "w")
        if not f then log("Camera watch: couldn't write the request") return end
        f:write(string.format("watch %x %d %.3f\n", addr + off, secs, loc.X))
        f:close()
        log("Camera watch: asked the DLL to watch Player 1's camera for %d s (data at +0x%x)", secs, off)
    end
    state.startCamWatch = start
    local armedAt = nil
    state.onP2Leave(function() armedAt = nil end)
    addTickJob("camWatchAuto", 2.0, function()
        if not (CFG.CAM_WATCH_AUTO and valid(state.p2)) or state.camWatchDone then return end
        armedAt = armedAt or os.clock()
        if os.clock() - armedAt > 40 then state.camWatchDone = true; start(6) end
    end)
    if Key.F7 ~= nil then RegisterKeyBind(Key.F7, { ModifierKey.CONTROL }, function() start(6) end) end
end)()

-- The game's "primary player" must stay Player 1 (radars, and other game systems, are worked
-- out around it). The game itself sometimes hands it to Player 2 (seen after Player 1 used the
-- jetpack); put it back, except while Player 1 is down (then Player 2 stands in on purpose).
;(function()
    local fixes = 0
    addTickJob("keepPrimaryP1", 0.25, function()
        if not (CFG.KEEP_PRIMARY_P1 and valid(state.p2)) or state.p1Down then return end
        local gs = FindFirstOf("GameStateBase")
        local p1 = getPawn(player1Controller())
        if not (valid(gs) and valid(p1)) then return end
        local okC, cur = pcall(function() return gs.m_pLastKnownPrimaryPlayerPawn end)
        if okC and valid(cur) and keyOf(cur) ~= keyOf(p1) then
            pcall(function() gs.m_pLastKnownPrimaryPlayerPawn = p1 end)
            fixes = fixes + 1
            if fixes <= 5 then log("Primary player was %s: set back to Player 1", shortName(cur)) end
        end
    end)
end)()

------------------------------------------------------------------------------------------
-- Trainer: Projectiles page (each gun, the players' and the NPCs', can shoot any projectile
-- the game has loaded), Upgrades page (turn upgrades on/off for this session only), DNA,
-- and Player 1's look without touching the save.
------------------------------------------------------------------------------------------
;(function()
    local PAGE_PROJ, PAGE_UPG, PAGE_PLAYERS = 8, 9, 3
    state.trainerExtras = state.trainerExtras or {}
    local add = function(e) state.trainerExtras[#state.trainerExtras + 1] = e end
    local function short(n) return (n or ""):match("([%w_%-]+)$") or n end
    -- (IsChildOf on a class crashed the game from Lua: walk the parent classes by name instead)
    local function inherits(c, baseShort)
        local cur, depth = c, 0
        while cur and depth < 12 do
            if not valid(cur) then return false end
            if short(nameOf(cur)) == baseShort then return true end
            local okS, sup = pcall(function() return cur:GetSuperStruct() end)
            if not okS then return false end
            cur = sup
            depth = depth + 1
        end
        return false
    end
    local function inGame()
        local wn = ""
        pcall(function() wn = nameOf(getWorld()) end)
        return wn ~= "" and not wn:find("/Menus/", 1, true)
    end

    -- ---------- projectiles ----------
    local projList, projByName = { "Game default" }, {}
    local original = {}     -- weapon key -> { a, b, c } original cached classes
    -- every projectile / beam ever scanned is kept in projectiles.txt (shipped with the mod),
    -- by its path, so they're all on the list from the start; each is only loaded when picked
    local KNOWN_FILE = "ue4ss/Mods/OverkillCoop/projectiles.txt"
    local knownPath = {}   -- short name -> full path ("/Game/.../X.X_C")
    local knownKind = {}   -- short name -> "proj" / "beam"
    local function pathOf(c)
        local full = nameOf(c) or ""
        return full:match("%s(/%S+)$") or full:match("^(/%S+)$")
    end
    local function readKnown()
        local f = io.open(KNOWN_FILE, "r")
        if not f then return end
        for line in f:lines() do
            local gk = line:match("^gun%s+(%S+)")
            if gk then state.knownGuns = state.knownGuns or {}; state.knownGuns[gk] = true end
            local kind, path = line:match("^(%a+)%s+(/%S+)")
            if kind and path then
                local n = path:match("%.([%w_%-]+)$") or path
                knownPath[n], knownKind[n] = path, kind
            end
        end
        f:close()
    end
    local function writeKnown()
        local f = io.open(KNOWN_FILE, "w")
        if not f then return end
        f:write("# Third Eye Decalcified Co-op: projectiles and beams seen in the game (the trainer's Shots page)\n")
        local names = {}
        for n in pairs(knownPath) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do f:write(string.format("%s %s\n", knownKind[n] or "proj", knownPath[n])) end
        local guns = {}
        for g in pairs(state.knownGuns or {}) do guns[#guns + 1] = g end
        table.sort(guns)
        for _, g in ipairs(guns) do f:write("gun " .. g .. "\n") end
        f:close()
    end
    readKnown()
    -- beams the Zap-O-Matic can use even if the game hasn't loaded them yet
    for _, p in ipairs({ "/Game/Blueprints/Weapon/UFO/BP_DeathRayBeam.BP_DeathRayBeam_C",
                         "/Game/Blueprints/Weapon/Crypto/BP_Zap-O-MaticBeam.BP_Zap-O-MaticBeam_C" }) do
        local n = p:match("%.([%w_%-]+)$")
        if not knownPath[n] then knownPath[n], knownKind[n] = p, "beam" end
    end
    -- the class for a name: loaded already, or loaded now from its path
    local function classFor(n, map)
        local c = map[n]
        if valid(c) then return c end
        local p = knownPath[n]
        if not p then return nil end
        c = StaticFindObject(p)
        if not valid(c) and state.loadClass then c = state.loadClass(p) end
        if valid(c) then map[n] = c end
        return valid(c) and c or nil
    end
    state.projClassFor = classFor
    local function refreshProjectiles()
        local seen = {}
        for n, k in pairs(knownKind) do if k == "proj" then seen[n] = true end end
        for _, c in ipairs(FindAllOf("BlueprintGeneratedClass") or {}) do
            if valid(c) then
                local n = short(nameOf(c))
                if n:find("Projectile") and not n:find("^Default__") and not n:find("^SKEL_") and not n:find("^REINST_") and not seen[n] then
                    -- (by name: the parent check found nothing in game)
                    if not n:find("Beam") then seen[n] = true; projByName[n] = c end
                end
            end
        end
        -- and from every gun in the level (what each one fires) and projectiles flying right now
        local function addCls(c)
            if valid(c) then
                local n = short(nameOf(c))
                if n ~= "" and n ~= "None" and not n:find("^Default__") and not seen[n] then seen[n] = true; projByName[n] = c end
            end
        end
        local changed = false
        pcall(function()
            local base = StaticFindObject("/Script/BFGCore.BFGWeapon_BaseProjectile")
            if not (inGame() and base and valid(base)) then return end
            local arr = {}
            getStatics():GetAllActorsOfClass(getWorld(), base, arr)
            for _, a in ipairs(arr) do
                local w = a
                if type(a) == "userdata" and not valid(a) then pcall(function() w = a:get() end) end
                if valid(w) then
                    for _, f in ipairs({ "m_pCachedProjectileClass", "m_pCachedAlternateProjectileClass", "m_pCachedSecondAlternateProjectileClass" }) do
                        local okF, c = pcall(function() return w[f] end)
                        -- (skip what the mod itself put there)
                        if okF and not (original[keyOf(w)]) then addCls(c) end
                    end
                end
            end
        end)
        pcall(function()
            local base = StaticFindObject("/Script/BFGCore.BFGProjectile")
            if not (inGame() and base and valid(base)) then return end
            local arr = {}
            getStatics():GetAllActorsOfClass(getWorld(), base, arr)
            for _, a in ipairs(arr) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) then pcall(function() addCls(v:GetClass()) end) end
            end
        end)
        for n, c in pairs(projByName) do
            if valid(c) and not knownPath[n] then
                local p = pathOf(c)
                if p then knownPath[n], knownKind[n] = p, "proj"; changed = true end
            end
        end
        if changed then writeKnown() end
        local names = {}
        for n in pairs(seen) do names[#names + 1] = n end
        table.sort(names)
        log("Projectiles: %d projectile types on the list (%s new)", #names, changed and "some" or "none")
        for i = #projList, 2, -1 do projList[i] = nil end
        for _, n in ipairs(names) do projList[#projList + 1] = n end
    end
    -- weapon kinds: one bar per kind of gun (class name without the _C_123 instance part)
    local function kindOf(w)
        local okC, c = pcall(function() return w:GetClass() end)
        return okC and valid(c) and short(nameOf(c)) or nil
    end
    local PLAYER_GUNS = { "DisintegratorRay", "IonDetonator", "AnalProbe" }
    local function isPlayerGun(k)
        if k:find("UFO_") then return true end   -- the saucer's own weapons (on foot too)
        for _, g in ipairs(PLAYER_GUNS) do if k:find(g) then return true end end
        return false
    end
    local choice = {}       -- kind -> projectile name
    local npcKinds = {}     -- list of NPC weapon kinds seen
    local function projWeapons()
        local out = {}
        local base = StaticFindObject("/Script/BFGCore.BFGWeapon_BaseProjectile")
        if not (inGame() and base and valid(base)) then return out end
        pcall(function()
            local arr = {}
            getStatics():GetAllActorsOfClass(getWorld(), base, arr)
            for _, a in ipairs(arr) do
                local v = a
                if type(a) == "userdata" and not valid(a) then pcall(function() v = a:get() end) end
                if valid(v) then out[#out + 1] = v end
            end
        end)
        return out
    end
    local function applyTo(w)
        local k = kindOf(w)
        if not k then return end
        local want = choice[k]
        local wk = keyOf(w)
        if want and want ~= "Game default" then
            local cls = classFor(want, projByName)
            if not valid(cls) then return end
            if not original[wk] then
                local o = {}
                pcall(function() o[1] = w.m_pCachedProjectileClass end)
                pcall(function() o[2] = w.m_pCachedAlternateProjectileClass end)
                pcall(function() o[3] = w.m_pCachedSecondAlternateProjectileClass end)
                pcall(function() o.tri = w.m_pTrifusionChambers_ExtraBulletClass end)
                o.soft = {}
                for _, f in ipairs({ "m_ProjectileClass", "m_AlternateProjectileClass", "m_SecondAlternateProjectileClass" }) do
                    pcall(function() o.soft[f] = w[f].AssetPathName:ToString() end)
                end
                original[wk] = o
            end
            pcall(function() w.m_pCachedProjectileClass = cls end)
            pcall(function() w.m_pCachedAlternateProjectileClass = cls end)
            pcall(function() w.m_pCachedSecondAlternateProjectileClass = cls end)
            pcall(function() w.m_pTrifusionChambers_ExtraBulletClass = cls end)   -- the Disintegrator's 2 extra shots
            -- the upgraded extra shots are made from the gun's class paths: point those at it too
            -- (the gun's own class paths are left alone: changing them stopped it being equipped)
        elseif original[wk] then
            local o = original[wk]
            for f, v in pairs(o.soft or {}) do pcall(function() w[f].AssetPathName = FName(v) end) end
            if o[1] then pcall(function() w.m_pCachedProjectileClass = o[1] end) end
            if o.tri then pcall(function() w.m_pTrifusionChambers_ExtraBulletClass = o.tri end) end
            if o[2] then pcall(function() w.m_pCachedAlternateProjectileClass = o[2] end) end
            if o[3] then pcall(function() w.m_pCachedSecondAlternateProjectileClass = o[3] end) end
            original[wk] = nil
        end
    end
    local function anyChoice() for _, v in pairs(choice) do if v ~= "Game default" then return true end end return false end
    addTickJob("projectileSwap", 1.0, function()
        if not anyChoice() and not next(original) then return end
        for _, w in ipairs(projWeapons()) do pcall(applyTo, w) end
    end)
    onWorldChange(function() original = {} end)
    local function projRow(kind, label)
        add({ key = "proj_" .. kind, page = PAGE_PROJ, label = label, options = projList,
              show = function() return true end,
              get = function() return choice[kind] or "Game default" end,
              set = function(v)
                  choice[kind] = v
                  -- the Disintegrator's burning comes from its fire upgrades, not the projectile:
                  -- with another projectile in it, those are off for the session (back on with default)
                  if false and kind:find("Disintegrator") and state.upgSet then
                      for _, t in ipairs({ "Weapon.DisintegratorRay.CascadeIncinerator", "Weapon.DisintegratorRay.CascadeImmolator" }) do
                          state.upgSet(t, v == "Game default" and "game" or "off")
                      end
                  end
                  for _, w in ipairs(projWeapons()) do if kindOf(w) == kind then pcall(applyTo, w) end end
                  log("Projectiles: %s now shoots %s", kind, v)
              end })
    end
    -- the players' guns (fixed rows), plus one row per NPC gun kind ever found (saved list)
    projRow("DisintegratorRayBP_C", "Disintegrator Ray shoots")
    do
        local guns = {}
        for g in pairs(state.knownGuns or {}) do guns[#guns + 1] = g end
        table.sort(guns)
        for _, g in ipairs(guns) do
            if not isPlayerGun(g) and not npcKinds[g] then
                npcKinds[g] = true
                projRow(g, "NPC gun " .. g:gsub("^BP_Weapon_", ""):gsub("_C$", "") .. " shoots")
            end
        end
    end
    add({ key = "act_projscan", page = PAGE_PROJ, label = "Look again for projectiles and NPC guns (after loading a new area)",
          options = { "Scan now" }, show = function() return true end, get = function() return "Scan now" end,
          set = function(v)
              if v ~= "Scan now" then return end
              refreshProjectiles()
              if state.refreshBeams then state.refreshBeams() end
              local found = 0
              for _, w in ipairs(projWeapons()) do
                  local k = kindOf(w)
                  if k and not isPlayerGun(k) and not npcKinds[k] then
                      npcKinds[k] = true
                      state.knownGuns = state.knownGuns or {}; if not state.knownGuns[k] then state.knownGuns[k] = true; writeKnown() end
                state.knownGuns = state.knownGuns or {}; if not state.knownGuns[k] then state.knownGuns[k] = true; writeKnown() end
                      found = found + 1
                      projRow(k, "NPC gun " .. k:gsub("^BP_Weapon_", ""):gsub("_C$", "") .. " shoots")
                  end
              end
              log("Projectiles: %d projectile types, %d new NPC gun kinds (close and reopen the trainer to see new rows)", #projList - 1, found)
          end })
    -- first scan once the world is up
    local scanned = false
    onWorldChange(function() scanned = false end)
    addTickJob("projectileFirstScan", 5.0, function()
        if scanned or not inGame() then return end
        scanned = true
        refreshProjectiles()
        for _, w in ipairs(projWeapons()) do
            local k = kindOf(w)
            if k and not isPlayerGun(k) and not npcKinds[k] then
                npcKinds[k] = true
                state.knownGuns = state.knownGuns or {}; if not state.knownGuns[k] then state.knownGuns[k] = true; writeKnown() end
                projRow(k, "NPC gun " .. k:gsub("^BP_Weapon_", ""):gsub("_C$", "") .. " shoots")
            end
        end
    end)

    -- ---------- Zap-O-Matic: any of the game's beams (TEST) ----------
    local beamList, beamByName = { "Game default" }, {}
    local function refreshBeams()
        local seen = {}
        for _, c in ipairs(FindAllOf("BlueprintGeneratedClass") or {}) do
            if valid(c) then
                local n = short(nameOf(c))
                if not n:find("^Default__") and not n:find("^SKEL_") and not n:find("^REINST_") and not seen[n] then
                    if n:find("Beam") and (n:find("Projectile") or n:find("Zap") or n:find("Ray") or inherits(c, "BFGProjectile_Beam")) and not n:find("Effect") then seen[n] = true; beamByName[n] = c end
                end
            end
        end
        local changed = false
        for n, c in pairs(beamByName) do
            if valid(c) and not knownPath[n] then local p = pathOf(c); if p then knownPath[n], knownKind[n] = p, "beam"; changed = true end end
        end
        for n, k in pairs(knownKind) do if k == "beam" then seen[n] = true end end
        -- the Death Ray only aims and hurts when the saucer's own weapon drives it: not on the list
        for n in pairs(seen) do if n:find("DeathRay") then seen[n] = nil end end
        if changed then writeKnown() end
        local names = {}
        for n in pairs(seen) do names[#names + 1] = n end
        table.sort(names)
        for i = #beamList, 2, -1 do beamList[i] = nil end
        for _, n in ipairs(names) do beamList[#beamList + 1] = n end
    end
    state.refreshBeams = refreshBeams
    local beamChoice, beamOrig, beamMade = "Game default", {}, {}
    local function zaps()
        local out = {}
        for _, pc in ipairs({ player1Controller(), state.p2 }) do
            if valid(pc) then
                local eq = subObj(getPawn(pc), "m_pEquipmentManagerComponent")
                pcall(function()
                    for _, w in ipairs(arrayToList(eq.m_aWeaponList)) do
                        if valid(w) and nameOf(w):find("Zap%-O%-Matic") then out[#out + 1] = w end
                    end
                end)
            end
        end
        return out
    end
    local function applyBeam(w)
        local wk = keyOf(w)
        if beamChoice == "Game default" then
            if beamOrig[wk] and valid(beamOrig[wk]) then
                pcall(function() w.m_pBeam = beamOrig[wk] end)
                if beamMade[wk] and valid(beamMade[wk]) then pcall(function() beamMade[wk]:K2_DestroyActor() end) end
            end
            beamOrig[wk], beamMade[wk] = nil, nil
            return
        end
        local cls = classFor(beamChoice, beamByName)
        if not valid(cls) then log("Zap beam: couldn't load %s", beamChoice) return end
        if beamMade[wk] and valid(beamMade[wk]) and beamMade[wk]:GetClass() == cls then return end
        if not beamOrig[wk] then pcall(function() beamOrig[wk] = w.m_pBeam end) end
        if beamMade[wk] and valid(beamMade[wk]) then pcall(function() beamMade[wk]:K2_DestroyActor() end) end
        local okL, loc = pcall(function() return w:K2_GetActorLocation() end)
        local okS, b = pcall(function() return getWorld():SpawnActor(cls, okL and loc or { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
        if not (okS and valid(b)) then log("Zap beam: couldn't make %s", beamChoice) return end
        pcall(function() b:SetOwner(w) end)
        pcall(function() b.Instigator = w.m_pHolder end)
        pcall(function() b:K2_AttachToActor(w, FName("None"), 1, 1, 1, false) end)
        -- the Death Ray's charge-up never finishes on the Zap-O-Matic (red glow, no beam): no charge
        pcall(function() b.m_fStartupDelay = 0 end)
        pcall(function() w.m_pBeam = b end)
        beamMade[wk] = b
        log("Zap beam: %s now uses %s", shortName(w), beamChoice)
    end
    onWorldChange(function() beamOrig, beamMade = {}, {} end)
    if false then add({ key = "zapbeam", page = PAGE_PROJ, label = "TEST  Zap-O-Matic beam (both players)", options = beamList,
          show = function() if #beamList == 1 then refreshBeams() end return true end,
          get = function() return beamChoice end,
          set = function(v) beamChoice = v; for _, w in ipairs(zaps()) do pcall(applyBeam, w) end end }) end
    addTickJob("zapBeamKeep", 2.0, function()
        if beamChoice == "Game default" then return end
        for _, w in ipairs(zaps()) do pcall(applyBeam, w) end
    end)

    -- ---------- Zap-O-Matic fires projectiles instead of its beam (TEST) ----------
    local zapShot, zapNext, zapBeamSaved, zapFxHidden = "Game default", {}, {}, {}
    add({ key = "zapshot", page = PAGE_PROJ, label = "TEST  Zap-O-Matic fires", options = projList,
          show = function() return true end, get = function() return zapShot end,
          set = function(v) zapShot = v; log("Zap-O-Matic: now fires %s", v) end })
    addTickJob("zapShots", 0.0, function()
        if zapShot == "Game default" or not state.fireProjectile then return end
        local cls = classFor(zapShot, projByName)
        if not valid(cls) then return end
        local now = os.clock()
        for i, pc in ipairs({ player1Controller(), state.p2 }) do
            if valid(pc) then
                local pawn = getPawn(pc)
                local eq = subObj(pawn, "m_pEquipmentManagerComponent")
                local okW, w = pcall(function() return eq:GetCurrentWeapon() end)
                if not (okW and valid(w)) then pcall(function() w = arrayToList(eq:GetCurrentWeapons())[1] end) end
                if valid(w) and nameOf(w):find("Zap%-O%-Matic") then
                    local okS, firing = pcall(function() return w:IsShooting() end)
                    -- the beam stays, but unseen and harmless, while the gun fires the projectile
                    pcall(function()
                        local b = w.m_pBeam
                        if valid(b) then
                            local bk = keyOf(b)
                            zapBeamSaved[bk] = zapBeamSaved[bk] or { b = b, dmg = b.m_fDamagePerTick }
                            zapBeamSaved[bk].len = zapBeamSaved[bk].len or b.m_fBeamLength
                            zapBeamSaved[bk].jumps = zapBeamSaved[bk].jumps or { b.m_iIRIDIUM_NumberPossibleJumps, b.m_iIridiumSpreaderNumberOfJumps }
                            b.m_fDamagePerTick = 0
                            b.m_fBeamLength = 1
                            pcall(function() b.m_iIRIDIUM_NumberPossibleJumps = 0 end)
                            pcall(function() b.m_iIridiumSpreaderNumberOfJumps = 0 end)
                            b:SetActorHiddenInGame(true)
                            pcall(function() if valid(b.BeamEffect) then b.BeamEffect:SetActorHiddenInGame(true); zapBeamSaved[bk].fx = b.BeamEffect end end)
                        end
                    end)
                    -- the beam's arcs are separate effect actors: hidden while firing projectiles
                    if okS and firing then
                        for _, fx in ipairs(FindAllOf("BP_Zapomatic_BeamEffectActor_C") or {}) do
                            if valid(fx) then pcall(function() fx:SetActorHiddenInGame(true) end); zapFxHidden[keyOf(fx)] = fx end
                        end
                    end
                    state.zapShotActive = true
                    if okS and firing and now >= (zapNext[i] or 0) then
                        zapNext[i] = now + (CFG.ZAP_SHOT_EVERY or 0.2)
                        pcall(function()
                            local from = w:K2_GetActorLocation()
                            local to, homing = nil, nil
                            pcall(function()
                                for _, t in ipairs(arrayToList(w.m_apCurrentLockedTargets)) do
                                    if valid(t) then to = state.targetPoint(t); homing = t:K2_GetRootComponent() break end
                                end
                            end)
                            if not to then
                                local cm = pc.PlayerCameraManager
                                local c, r = cm:GetCameraLocation(), cm:GetCameraRotation()
                                local raise = (i == 2 and state.p2CrosshairPitch) and (state.p2CrosshairPitch() or 0) or 0
                                local yaw, pitch = math.rad(r.Yaw), math.rad(r.Pitch + raise)
                                to = { X = c.X + math.cos(pitch) * math.cos(yaw) * 6000, Y = c.Y + math.cos(pitch) * math.sin(yaw) * 6000,
                                       Z = c.Z + math.sin(pitch) * 6000 }
                            end
                            local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
                            local d = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
                            local dir = { X = dx / d, Y = dy / d, Z = dz / d }
                            local rot = { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
                            local start = { X = from.X + dir.X * 60, Y = from.Y + dir.Y * 60, Z = from.Z + dir.Z * 60 + 10 }
                            local okP, pr = pcall(function() return getWorld():SpawnActor(cls, start, rot) end)
                            if not (okP and valid(pr)) then return end
                            pcall(function() pr:SetOwner(pawn) end)
                            pcall(function() pr.Instigator = pawn end)
                            -- the game's own launch (as its guns do): flight, damage and effects from the projectile
                            pcall(function() pr:SetWeapon(w) end)
                            local okF = pcall(function() pr:FireProjectile(8000, homing, dir) end)
                            -- (the game's launch aims from the gun's own target data: point it at our aim)
                            pcall(function() pr:K2_SetActorRotation(rot, false) end)
                            pcall(function()
                                local pm = pr.m_pMovementComponent
                                local spd = CFG.ZAP_SHOT_SPEED or 5000
                                pcall(function() local m = pm.MaxSpeed; if type(m) == "number" and m > 100 then spd = math.min(m, spd) end end)
                                pm.Velocity = { X = dir.X * spd, Y = dir.Y * spd, Z = dir.Z * spd }
                            end)
                            if not okF then
                                pcall(function()
                                    local pm = pr.m_pMovementComponent
                                    pm:SetUpdatedComponent(pr:K2_GetRootComponent())
                                    pm.Velocity = { X = dir.X * 5000, Y = dir.Y * 5000, Z = dir.Z * 5000 }
                                    pm:Activate(true)
                                end)
                            end
                            if not state.zapShotLogged then state.zapShotLogged = true; log("Zap-O-Matic shot: %s, game launch %s", shortName(pr), okF and "ok" or "failed (pushed instead)") end
                        end)
                    end
                end
            end
        end
    end)
    -- back to the beam: put it back as it was
    addTickJob("zapShotsRestore", 0.5, function()
        if zapShot ~= "Game default" then return end
        state.zapShotActive = false
        for k, fx in pairs(zapFxHidden) do if valid(fx) then pcall(function() fx:SetActorHiddenInGame(false) end) end zapFxHidden[k] = nil end
        for k, e in pairs(zapBeamSaved) do
            if valid(e.b) then
                pcall(function() e.b.m_fDamagePerTick = e.dmg end)
                if e.len then pcall(function() e.b.m_fBeamLength = e.len end) end
                if e.jumps then
                    pcall(function() e.b.m_iIRIDIUM_NumberPossibleJumps = e.jumps[1] end)
                    pcall(function() e.b.m_iIridiumSpreaderNumberOfJumps = e.jumps[2] end)
                end
                pcall(function() e.b:SetActorHiddenInGame(false) end)
                if e.fx and valid(e.fx) then pcall(function() e.fx:SetActorHiddenInGame(false) end) end
            end
            zapBeamSaved[k] = nil
        end
    end)

    -- ---------- upgrades (this session only), shown as chains like the Pox lab ----------
    -- Each weapon / ability's upgrades are a chain (cheapest first = level 1). One row per
    -- chain: pick the level; the boxes show it (filled = on). "Game (save)" is what you bought.
    -- Levels can only add to what you bought (taking a bought one away locked the whole weapon).
    local chains, chainOf, upgState = {}, {}, {}
    local UPG_LOGGED = false
    local function unlocks()
        local ps = subObj(player1Controller(), "PlayerState")
        return ps and subObj(ps, "m_pUnlocks")
    end
    local function setUpgrade(tagName, mode)
        local u = unlocks()
        if not u then return end
        local tag = { TagName = FName(tagName) }
        if mode == "off" then
            -- (only what this session added can be taken away: locking a bought upgrade locked its
            -- whole weapon - the Disintegrator couldn't be held - so that's never done)
            pcall(function() u:RemoveLockedTag(tag) end)
            pcall(function() u:LockRemoveTag(tag, false) end)
        elseif mode == "on" then
            pcall(function() u:RemoveLockedTag(tag) end)
            pcall(function() u:UnlockTag(tag, false) end)
        else
            pcall(function() u:RemoveLockedTag(tag) end)
            pcall(function() u:LockRemoveTag(tag, false) end)
        end
        upgState[tagName] = mode
    end
    state.upgSet = setUpgrade
    local function owned(tagName)
        local u = unlocks()
        local ok, v = pcall(function() return u:IsUnlockedTag({ TagName = FName(tagName) }) end)
        return ok and v == true
    end
    local function boxes(n, total)
        local b = ""
        for i = 1, total do b = b .. (i <= n and "[#]" or "[ ]") end
        return b
    end
    local function pretty(seg)
        return (seg or ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    end
    local function chainOptions(ch)
        local o = { "Game (save)" }
        for lvl = 0, #ch.items do
            local what = lvl == 0 and "none" or ch.items[lvl].label
            o[#o + 1] = string.format("Level %d  %s  %s", lvl, boxes(lvl, #ch.items), what)
        end
        return o
    end
    local function applyChain(ch, v)
        if v:find("^Game %(save%)") then
            for _, it in ipairs(ch.items) do setUpgrade(it.tag, "game") end
            ch.level = nil
            return
        end
        local lvl = tonumber(v:match("^Level (%d+)")) or 0
        for i, it in ipairs(ch.items) do setUpgrade(it.tag, i <= lvl and "on" or "off") end
        ch.level = lvl
    end
    local function addChainRow(ch)
        ch.options = chainOptions(ch)
        add({ key = "upg_" .. ch.key:gsub("[^%w]", "_"), page = PAGE_UPG, label = ch.label, options = ch.options,
              show = function()
                  -- what you own (asked only when the trainer opens, and only while the game decides)
                  if not ch.level then
                      local have = 0
                      for _, it in ipairs(ch.items) do if owned(it.tag) then have = have + 1 end end
                      ch.have = have
                      ch.options[1] = string.format("Game (save)  %s  you have %d of %d", boxes(have, #ch.items), have, #ch.items)
                  end
                  return true
              end,
              get = function()
                  if ch.level then return ch.options[ch.level + 2] end
                  return ch.options[1]
              end,
              set = function(v) applyChain(ch, v); log("Upgrades: %s -> %s", ch.label, v) end })
    end
    local function scanUpgrades()
        local found = {}
        for _, a in ipairs(FindAllOf("BFGDataAssetPoxLabUpgrade") or {}) do
            if valid(a) then
                local okT, t = pcall(function() return a.m_oUpgradeTag.TagName:ToString() end)
                if okT and t and t ~= "None" and not chainOf[t] then
                    local okU, un = pcall(function() return a.m_strUpgradeName:ToString() end)
                    local okW, wn = pcall(function() return a.m_strWeaponName:ToString() end)
                    local okC, cost = pcall(function() return a.m_iUpgradeCost end)
                    found[#found + 1] = { tag = t, label = (okU and un ~= "") and un or short(t),
                        weapon = (okW and wn ~= "") and wn or nil, cost = (okC and tonumber(cost)) or 0 }
                end
            end
        end
        if #found == 0 then return 0 end
        if not UPG_LOGGED then
            UPG_LOGGED = true
            for _, f in ipairs(found) do log("Upgrade found: %s | %s | weapon %s | cost %d", f.tag, f.label, tostring(f.weapon), f.cost) end
        end
        -- group: the weapon name when the game has one, else the tag without its last part
        local groups, order = {}, {}
        for _, f in ipairs(found) do
            local gk = f.weapon or f.tag:match("^(.*)%.[^%.]+$") or f.tag
            if not groups[gk] then groups[gk] = {}; order[#order + 1] = gk end
            table.insert(groups[gk], f)
        end
        table.sort(order)
        local n = 0
        for _, gk in ipairs(order) do
            local items = groups[gk]
            table.sort(items, function(x, y) if x.cost ~= y.cost then return x.cost < y.cost end return x.tag < y.tag end)
            local label = pretty(gk:match("([^%.]+)$") or gk)
            local ch = { key = gk, label = label, items = items }
            chains[#chains + 1] = ch
            for _, it in ipairs(items) do chainOf[it.tag] = ch end
            addChainRow(ch)
            n = n + #items
        end
        return n
    end
    add({ key = "upg_all", page = PAGE_UPG, label = "ALL UPGRADES (this session only, your save keeps what you bought)",
          options = { "Game (save)", "Fully upgraded (all on)" }, show = function() return true end,
          get = function() return state.upgAll or "Game (save)" end,
          set = function(v)
              state.upgAll = v
              for _, ch in ipairs(chains) do
                  if v == "Game (save)" then applyChain(ch, "Game (save)")
                  elseif v == "Base Crypto (all off)" then applyChain(ch, "Level 0")
                  else applyChain(ch, "Level " .. #ch.items) end
              end
              log("Upgrades: all -> %s (%d chains)", v, #chains)
          end })
    add({ key = "act_upgscan", page = PAGE_UPG, label = "Look again for upgrades (they list once the game has loaded them)",
          options = { "Scan now" }, show = function() return true end, get = function() return "Scan now" end,
          set = function(v) if v == "Scan now" then log("Upgrades: %d new (reopen the trainer)", scanUpgrades()) end end })
    local upgScanned = false
    onWorldChange(function() upgScanned = false end)
    addTickJob("upgradeFirstScan", 5.0, function()
        if upgScanned or not inGame() then return end
        upgScanned = true
        local n = scanUpgrades()
        if n > 0 then log("Upgrades: %d listed in %d chains", n, #chains) end
        -- undo the temporary locks an earlier version put on upgrades (they locked whole weapons)
        local u = unlocks()
        if u then
            for _, ch in ipairs(chains) do
                for _, it in ipairs(ch.items) do pcall(function() u:RemoveLockedTag({ TagName = FName(it.tag) }) end) end
            end
        end
        for _, ch in ipairs(chains) do if ch.level then applyChain(ch, "Level " .. ch.level) end end
    end)

    -- ---------- DNA (this one does go into the save) ----------
    add({ key = "act_dna", page = PAGE_PLAYERS, label = "Give DNA (this DOES go into your save)",
          options = { "(pick an amount)", "+1,000", "+5,000", "+10,000", "+50,000", "+100,000" },
          show = function() return true end, get = function() return "(pick an amount)" end,
          set = function(v)
              local n = tonumber((v:gsub("[^%d]", "")))
              if not n or n <= 0 then return end
              local pc = player1Controller()
              local okC = pcall(function() pc.CheatManager:AddDNA(n) end)
              if not okC then
                  local ps = subObj(pc, "PlayerState")
                  pcall(function() ps.m_iDNA = (ps.m_iDNA or 0) + n end)
              end
              local ps = subObj(pc, "PlayerState")
              local okD, now = pcall(function() return ps.m_iDNA end)
              log("DNA: +%d (%s) -> %s", n, okC and "cheat manager" or "direct", okD and tostring(now) or "?")
          end })

    -- ---------- Player 1's look, without the save ----------
    add({ key = "act_p1look", page = PAGE_PLAYERS, label = "Player 1 look (this session only, not saved)",
          options = { "(choose)", "Next look", "Previous look" }, show = function() return true end,
          get = function() return "(choose)" end,
          set = function(v)
              if v == "Next look" then cycleSkin(player1Controller(), 1, "P1V")
              elseif v == "Previous look" then cycleSkin(player1Controller(), -1, "P1V") end
          end })
end)()
