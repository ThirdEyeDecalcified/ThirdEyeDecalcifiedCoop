--[[
    Third Eye Decalcified Co-op - the jukebox (loaded by main.lua)
    Two radio stations in the trainer (World page): the game's own music, or the mod's music
    (the songs listed in Mods\OverkillCoop\Music\playlist.txt). Off by default.
    The controller DLL (xinput1_3.dll) does the playing; this file tells it what to do through
    overkill_music.txt next to the game exe. Like the game's own music, the mod's music stops
    while the game is paused, in cutscenes and menus, while loading, and when the game isn't
    the window in front.
]]

local OK = OverkillCoop
if not OK then return end
local state, CFG, log, valid = OK.state, OK.CFG, OK.log, OK.valid
local function jlog(fmt, ...) log("Jukebox: " .. fmt, ...) end

local CMD_FILE = "overkill_music.txt"
local STATUS_FILE = "overkill_music_status.txt"

local juke = { station = "Game music", playing = false, volume = 75, track = 1, gen = 0, written = nil }
state.jukebox = juke

------------------------------------------------------------------------------------------
-- The songs: Music\playlist.txt, one file name per line (mp3 or wav), next to this mod
------------------------------------------------------------------------------------------
local musicDir = nil
local function findMusicDir()
    if musicDir then return musicDir end
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("/", "\\")
    local base = src:match("^(.*\\)Scripts\\[^\\]+$")
    local tries = {}
    if base then tries[#tries + 1] = base; tries[#tries + 1] = "ue4ss\\" .. base end
    tries[#tries + 1] = "ue4ss\\Mods\\OverkillCoop\\"
    tries[#tries + 1] = "Mods\\OverkillCoop\\"
    for _, t in ipairs(tries) do
        local f = io.open(t .. "Music\\playlist.txt", "r")
        if f then f:close(); musicDir = t .. "Music\\"; return musicDir end
    end
    return nil
end
local tracks = {}   -- { name, path }
local function loadPlaylist()
    tracks = {}
    local dir = findMusicDir()
    if not dir then jlog("no Music\\playlist.txt found"); return end
    local f = io.open(dir .. "playlist.txt", "r")
    if not f then return end
    for line in f:lines() do
        local file = line:gsub("^%s+", ""):gsub("%s+$", "")
        if file ~= "" and not file:find("^#") then
            local probe = io.open(dir .. file, "rb")
            if probe then
                probe:close()
                local name = file:gsub("%.[^.]+$", ""):gsub("_", " ")
                tracks[#tracks + 1] = { name = name, path = dir .. file }
            else
                jlog("playlist: %s isn't in the Music folder", file)
            end
        end
    end
    f:close()
    jlog("%d song(s) in the playlist", #tracks)
end
loadPlaylist()

------------------------------------------------------------------------------------------
-- The game's own music: muted while the mod station is on (its sound class volume)
------------------------------------------------------------------------------------------
local musicClasses = nil   -- { {obj, volume} }
local function findMusicClasses()
    if musicClasses then return musicClasses end
    musicClasses = {}
    local names = {}
    pcall(function()
        for _, sc in ipairs(FindAllOf("SoundClass") or {}) do
            if valid(sc) then
                local n = OK.nameOf(sc)
                names[#names + 1] = OK.shortName and OK.shortName(sc) or n
                if n:lower():find("music") then
                    local okV, v = pcall(function() return sc.Properties.Volume end)
                    musicClasses[#musicClasses + 1] = { obj = sc, volume = okV and v or 1.0 }
                end
            end
        end
    end)
    jlog("sound classes: %s; muting %d for the mod station", table.concat(names, ", "), #musicClasses)
    return musicClasses
end
local gameMuted = false
local function muteGameMusic(on)
    if on == gameMuted then return end
    for _, e in ipairs(findMusicClasses()) do
        if valid(e.obj) then pcall(function() e.obj.Properties.Volume = on and 0.0 or e.volume end) end
    end
    gameMuted = on
end
OK.onWorldChange(function() musicClasses = nil; gameMuted = false end)

------------------------------------------------------------------------------------------
-- When music may play (the same moments the game's own music stops)
------------------------------------------------------------------------------------------
local function musicAllowed()
    local world = OK.getWorld()
    if not world then return false, "no map" end
    local wn = OK.nameOf(world)
    if wn:find("MainMenu") or wn:find("/Menus/") or wn:find("Loading") then return false, "menu" end
    local okP, paused = pcall(function() return OK.getStatics():IsGamePaused(world) end)
    if okP and paused then return false, "paused" end
    -- a cutscene = one of the game's cutscene sequences actually playing (the controller's
    -- "cinematic mode" flag stayed on in normal play, so the music never started)
    local playing = false
    for _, sp in ipairs(FindAllOf("LevelSequencePlayer") or {}) do
        local okP, on = pcall(function() return sp:IsPlaying() end)
        if okP and on then playing = OK.shortName(sp) break end
    end
    if playing then return false, "cutscene: " .. tostring(playing) end
    if state.trainerOpen then return true, nil end
    return true, nil
end

------------------------------------------------------------------------------------------
-- Telling the DLL
------------------------------------------------------------------------------------------
local function writeCommand(want)
    local t = tracks[juke.track]
    local lines = {
        "gen=" .. juke.gen,
        "state=" .. want,
        "volume=" .. juke.volume,
        "index=" .. (juke.track - 1),
    }
    for _, tr in ipairs(tracks) do lines[#lines + 1] = "track=" .. tr.path end
    local text = table.concat(lines, "\n") .. "\n"
    if text == juke.written then return end
    local f = io.open(CMD_FILE, "w")
    if not f then return end
    f:write(text)
    f:close()
    juke.written = text
    if t then jlog("%s: %s (volume %d%%)", want, t.name, juke.volume) end
end
local function bump() juke.gen = juke.gen + 1 end
-- the DLL moves on to the next song by itself and says which one it's on
local function readStatus()
    local f = io.open(STATUS_FILE, "r")
    if not f then return end
    local text = f:read("*a") or ""
    f:close()
    local idx = tonumber(text:match("index=(%d+)"))
    if idx and tracks[idx + 1] then juke.track = idx + 1 end
end
local lastWhy = nil
OK.addTickJob("jukebox", 0.5, function()
    local modStation = juke.station == "Mod music"
    if not modStation and juke.written == nil then return end   -- never used: nothing to do
    if #tracks == 0 then return end
    readStatus()
    local allowed, why = musicAllowed()
    muteGameMusic(modStation)
    local want = "stop"
    if modStation then want = (juke.playing and allowed) and "play" or "pause" end
    if why ~= lastWhy then lastWhy = why; if why and modStation and juke.playing then jlog("waiting (%s)", why) end end
    writeCommand(want)
end)
-- a clean start: nothing playing left over from last time
pcall(function() local f = io.open(CMD_FILE, "w"); if f then f:write("gen=0\nstate=stop\n"); f:close() end end)

------------------------------------------------------------------------------------------
-- Trainer rows (World page)
------------------------------------------------------------------------------------------
state.trainerExtras = state.trainerExtras or {}
local function add(e) state.trainerExtras[#state.trainerExtras + 1] = e end
local trackNames = {}
for _, t in ipairs(tracks) do trackNames[#trackNames + 1] = t.name end
if #trackNames == 0 then trackNames = { "(no songs)" } end
-- Mod songs: A plays the song shown; A on the song that's playing stops it
add({ key = "j_track", page = 4, label = "Mod song (A: play / stop)", options = trackNames, nosave = true,
    get = function() return tracks[juke.track] and tracks[juke.track].name or trackNames[1] end,
    set = function(v)
        -- only a press in the open trainer plays a song (never a remembered setting at start-up)
        if not state.trainerOpen then
            for i, t in ipairs(tracks) do if t.name == v then juke.track = i end end
            return
        end
        local was = juke.track
        for i, t in ipairs(tracks) do if t.name == v then juke.track = i end end
        if juke.playing and was == juke.track then
            juke.playing = false
            jlog("mod song stopped")
        else
            if state.stopGameSong then pcall(state.stopGameSong) end   -- one song at a time
            juke.station, juke.playing = "Mod music", true
            jlog("mod song: %s", v)
        end
        bump()
    end,
    reset = function() end })
add({ key = "j_volume", page = 4, label = "Mod music volume", options = { "25%", "50%", "75%", "100%" },
    get = function() return juke.volume .. "%" end,
    set = function(v) juke.volume = tonumber(v:match("%d+")) or 75; bump() end,
    reset = function() end })

-- The game's own songs (Content/Audio/Waves/Music, found by Keaton): picked here, played by
-- the game itself over its usual music
local GAME_SONGS = {
    "m_mainmenu", "m_maintheme_excerpt_0_35", "m_maintheme_excerpt_1_05", "music_outerspace_master", "Credits_song_vs4",
    "m_santamodesta_default_master2_part1", "m_santamodesta_combat_master2_part1", "m_santamodesta_stealth_master2_part1", "santamodesta_music_undisguised_edit",
    "m_rockwell_default_master2_part1", "m_rockwell_combat_master2_part1", "m_rockwell_stealth_master2_part1",
    "m_area42_default_master2_part1", "m_area42_combat_master2_part1", "m_area42_stealth_master2_part1",
    "m_uniontown_default_master2_part1", "m_uniontown_combat_master2_part1", "m_uniontown_stealth_master2_part1",
    "m_capitolcity_default_master2_part1", "m_capitolcity_combat_master2_part1", "m_capitolcity_stealth_master2_part1",
    "m_mm04_poolparty_loop", "m_mm04_poolparty_start", "m_silhouettemarch", "m_celloriff", "m_triplebrass", "m_sadbrass",
    "m_jingle_victory_01", "m_jingle_defeat",
}
local gameSongNames = { "Off" }
for _, n in ipairs(GAME_SONGS) do gameSongNames[#gameSongNames + 1] = n end
local gameSong = { name = "Off", comp = nil, all = {} }
local function stopGameSong()
    -- every one started, not just the last (they used to pile up)
    for _, c in ipairs(gameSong.all) do
        pcall(function() c:Stop() end)
        pcall(function() c:SetPaused(true) end)
        pcall(function() c:K2_DestroyComponent(c) end)
    end
    gameSong.all, gameSong.comp = {}, nil
end
state.stopGameSong = function() stopGameSong(); gameSong.name = "Off" end
OK.onWorldChange(function() gameSong.comp = nil end)
add({ key = "j_gamesong", page = 4, label = "Game song (A: play / stop)", options = gameSongNames, nosave = true,
    get = function() return gameSong.name end,
    set = function(v)
        if not state.trainerOpen then return end   -- never from a remembered setting
        local again = (v == gameSong.name) and #gameSong.all > 0
        stopGameSong()
        if again then gameSong.name = "Off"; jlog("game song stopped") return end
        gameSong.name = v
        if v == "Off" then jlog("game song off") return end
        local path = "/Game/Audio/Waves/Music/" .. v .. "." .. v
        local snd = StaticFindObject(path)
        if not valid(snd) then pcall(function() LoadAsset(path) end); snd = StaticFindObject(path) end
        if not valid(snd) then jlog("game song %s: not found", v) return end
        -- mod music pauses while a game song plays
        if juke.playing then juke.playing = false; juke.station = "Game music"; bump() end
        local gs = OK.getStatics()
        local ok, c = pcall(function() return gs:SpawnSound2D(OK.getWorld(), snd, (juke.volume or 75) / 100, 1, 0, nil, true, true) end)
        if not (ok and valid(c)) then ok, c = pcall(function() return gs:SpawnSound2D(OK.getWorld(), snd, (juke.volume or 75) / 100) end) end
        gameSong.comp = (ok and c) or nil
        if gameSong.comp then gameSong.all[#gameSong.all + 1] = gameSong.comp end
        jlog("game song %s: %s", v, gameSong.comp and "playing" or ("couldn't play: " .. tostring(c)))
    end,
    reset = function() stopGameSong(); gameSong.name = "Off" end })

jlog("loaded (trainer > World > Radio station)")
