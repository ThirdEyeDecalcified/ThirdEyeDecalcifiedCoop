-- Overkill Coop - PK settings
-- Every name marked "DISCOVER" is a guess. Press F9 in game while holding
-- something with PK and the mod prints the real class/property names to the
-- UE4SS console. Copy the right ones in here.

local Config = {}

------------------------------------------------------------------------
-- Controller binds (Unreal FKey names)
------------------------------------------------------------------------
Config.Keys = {
    PKHold = "Gamepad_RightShoulder",   -- RB
    PullIn = "Gamepad_LeftThumbstick",  -- L3
    PushOut = "Gamepad_RightThumbstick", -- R3
    -- Keyboard / mouse equivalents (optional, set to nil to disable)
    PullInKB = "MouseScrollDown",
    PushOutKB = "MouseScrollUp",
}

------------------------------------------------------------------------
-- Finding the PK component and the thing it is holding   (DISCOVER)
------------------------------------------------------------------------
-- Exact property names on Crypto (BP_CharacterPlayer_C), tried first.
-- From the F9 dump: PK, Hypnosis, Holobob are "mental abilities" in this game.
Config.PKComponentProps = { "m_pMentalAbilityComponent" }

-- Fallback: substrings (case-insensitive) matched against component class and
-- property names. SpringArmComponent is skipped (that's the PK camera boom).
Config.PKComponentClassHints = { "mentalabilit", "psycho", "kinesis", "telekin" }

-- F9 dumps these components in depth (property names on Crypto)
Config.DeepDumpComponents = {
    "m_pMentalAbilityComponent",   -- PK logic (most likely)
    "m_pLockOnComponent",          -- R3 candidate
    "m_pFocusComponent",           -- R3 candidate
    "m_pInputActionsComponent",    -- the game's own input layer (R3/L3/RB live here)
    "m_pTargetComponent",
    "m_pCharacterPhysicsComponent",
    "m_pDamageComponent",          -- how the game applies damage
}

-- When dumping, follow sub-objects / structs whose name or class contains one of these
Config.DeepDumpHints = {
    "ability", "pk", "psycho", "kinesis", "telek", "grab", "held", "hold", "target",
    "lock", "focus", "input", "action", "binding", "mapping", "physic", "damage", "config", "settings",
}

-- Keywords for the F9 dump's filtered lists (pawn / controller / held actor)
Config.DumpKeywords = {
    "psy", "pk", "kinesis", "telek", "grab", "held", "hold", "lift", "throw",
    "target", "distance", "dist", "health", "hp", "damage", "ragdoll",
}

-- Property names tried, in order, on the PK component to get the held actor.
-- Each name is also tried with the m_p prefix BFG uses (HeldActor -> m_pHeldActor).
-- From the F9 dump: PK is the BP_MentalAbility_Psycokinesis ability; m_pActiveTarget is what it holds.
Config.PKAbilityHints = { "psycokinesis", "psychokinesis" }
-- Hold distance: the character's PK spring arm (TargetArmLength). Set to nil to use the nudge fallback.
Config.HoldArm = { Component = "m_pPKSpringArmComponent", Length = "TargetArmLength" }
Config.HeldActorProps = { "ActiveTarget", "PK_Object", "ThrownActor", "HeldActor", "GrabbedActor", "TargetActor", "PKTarget", "PKObject", "CurrentTarget", "Target" }

-- Property names tried, in order, for the hold distance (float, in cm).
-- If one is found, push/pull edits it directly (cleanest result).
-- Each name is also tried with the m_f prefix (HoldDistance -> m_fHoldDistance).
Config.HoldDistanceProps = { "HoldDistance", "GrabDistance", "TargetDistance", "CurrentDistance", "PKDistance", "Distance" }

------------------------------------------------------------------------
-- Push / pull
------------------------------------------------------------------------
Config.Push = {
    Speed = 900.0,         -- cm per second while L3/R3 is held
    TapStep = 300.0,       -- extra cm applied on the press itself, so taps feel responsive
    MinDistance = 250.0,
    SizedMinDistance = true,  -- things can come in as close as their own size allows (never into Crypto)
    MinDistanceFloor = 70.0,  -- ...but never closer than this
    MinDistanceGap = 45.0,    -- ...and this much air between the thing's edge and Crypto's middle
    MinDistancePeople = 90.0, -- people can be pulled right up to Crypto (about three feet)   -- closest the object can come to Crypto
    MaxDistance = 3500.0,  -- furthest it can be pushed
    -- Fallback when no hold-distance property exists: nudge the object's
    -- physics velocity along the camera ray. Experimental: it fights the
    -- game's own PK spring, so keep the strength modest.
    FallbackNudgeEnabled = true,
    AlsoNudge = true,
    WallCheckDistance = 160.0, -- cm: stop pushing out when a wall is this close in front of the held thing      -- push/pull the object physically as well as changing the hold distance (stronger, more drastic)
    FallbackNudgeStrength = 2500.0, -- cm/s added along camera forward
}

------------------------------------------------------------------------
-- HUD (world-space label that floats above the held object)
------------------------------------------------------------------------
Config.Hud = {
    Enabled = true,
    HeightOffset = -30.0,    -- cm below the held thing's lowest point (80 cm more if its size can't be read)
    TextSize = 42.0,
    ShowDistanceWhenIdle = true,
    TextIn = "IN!",
    TextOut = "OUT!",
    TextThrow = "RELEASE TO THROW",      -- holding RB (red); LB switches to...
    TextRelease = "RELEASE",          -- ...blue: let go of RB to drop it instead of throwing
    TextShrink = "SHRINK!",
    TextGrow = "GROW!",
}
-- Blue PK (tapped RB, or LB while holding): L3 / R3 shrink and grow the held thing
-- instead of pulling it in / pushing it out. The trainer can switch this.
Config.BlueResize = false

------------------------------------------------------------------------
-- Collision damage
------------------------------------------------------------------------
Config.Damage = {
    Enabled = true,

    -- Held thing slams into a wall/ground (sudden stop while moving fast)
    WallImpact = {
        Enabled = true,
        MinSpeed = 600.0,          -- cm/s before an impact counts (~22 km/h)
        DecelFraction = 0.45,      -- speed must drop by at least this fraction in one tick
        BaseDamage = 30.0,
        DamagePerSpeed = 0.05,     -- extra damage per cm/s above MinSpeed
        MaxDamage = 120.0,
        UseLineTraceConfirm = true, -- require a trace hit along the old velocity (cuts false hits when you just stop the stick)
    },

    -- Held thing (object or NPC) swept into an NPC
    BodyImpact = {
        Enabled = true,
        MinSpeed = 300.0,
        HitRadius = 160.0,         -- grows to the held thing's size (cars)         -- cm from held actor centre to NPC centre
        BaseDamage = 10.0,
        DamagePerSpeed = 0.03,
        ReferenceMass = 200.0,     -- kg; heavier than this hits harder
        MassFactorMin = 0.5,
        MassFactorMax = 3.0,
        MaxDamage = 200.0,
        Knockback = 0.35,          -- people hit by a held person/object get knocked over (capped)
        VehicleRadius = 250.0,     -- cm: most a held car reaches out from its centre (its own size, flat)
        VehicleKnockback = 0.5,    -- a held car sends people flying (capped)           -- fraction of held object's velocity transferred to the victim (0 = off)
    },

    PerTargetCooldown = 0.35,
    AfterReleaseSeconds = 3.0,
    ThrowSpeed = 1400.0,           -- cm/s at release: faster than this counts as a throw (full damage)
    RagdollImpactSpeed = 900.0,
    RagdollWhileHeld = true,       -- a person slammed into a wall while held goes limp in PK's grip   -- a person slammed harder than this goes limp (ragdoll)
    Modes = {
        held = { Scale = 0.35, KeepHealth = 0.15 },   -- scraped/slammed while held: hurts, never kills
        dropped = { Scale = 0.5, KeepHealth = 0.0 },  -- let go gently: half damage
        thrown = { Scale = 1.0, KeepHealth = 0.0 },   -- thrown into something: full damage
    },     -- keep counting hits this long after PK lets go (drops and throws)      -- seconds before the same actor can be damaged again

    -- Classes counted as NPCs for BodyImpact (short class names). DISCOVER:
    -- F9 prints the held actor's class; hold a human and add it here.
    NPCClassNames = { "Character" },

    -- How damage is applied:
    --   "ApplyDamage" -> UGameplayStatics::ApplyDamage (works if the game uses UE damage)
    --   "HealthProp"  -> subtract from a float property directly (set HealthProps below)
    Method = "Stat",                -- the game's own health stat (falls back to ApplyDamage)
    StatsComponentProps = { "m_pStatsComponent", "m_pPawnStatsComponent", "m_pStats" },
    StatDamageScale = 1.0,          -- 100 damage points = the NPC's whole health bar
    HealthProps = { "Health", "CurrentHealth", "HP" }, -- DISCOVER if using HealthProp
}

------------------------------------------------------------------------
-- Input gate: block the game's own R3/L3 actions while PK is active,
-- so those clicks only do push/pull. Normal behaviour everywhere else.
------------------------------------------------------------------------
-- NOTE: the F5 dump showed R3/L3/RB aren't in Unreal's ActionMappings in this
-- game (it uses its own BFG input layer), so this gate currently does nothing.
-- Kept for now; the next version will block R3 through the game's own system.
Config.InputGate = {
    Enabled = false,
    -- Keys whose game actions get unbound while gated. Remove L3 if you
    -- want sprint/skates to keep working while holding something.
    Keys = { "Gamepad_RightThumbstick", "Gamepad_LeftThumbstick" },
    -- "Holding" = only while RB is down AND PK has a target
    -- "RBDown"  = whenever RB is down, even before something is grabbed
    When = "Holding",
}

------------------------------------------------------------------------
-- Impact sounds (the first loaded sound whose name contains one of these words; the log lists candidates)
Config.Sounds = {
    Enabled = true,
    -- the game's own PK impact sounds (s_pk_impact_<material>_cue)
    Wall = { "s_pk_impact_earth_cue", "s_pk_impact_conc_cue", "s_pk_impact_stone_cue" },
    Body = { "s_pk_impact_skin_cue", "s_pk_impact_leath_cue", "s_pk_impact_cloth_cue" },
    Car = { "s_pk_impact_met_cue", "s_weap_impact_met", "s_pk_impact_glass_cue" },
}
Config.BlockCameraR3 = true -- R3 doesn't turn the camera while PK holds something
Config.TickMs = 16     -- ~60 Hz polling
Config.FxReport = false   -- (temporary) log what the PK glow is made of on each grab
Config.RideReport = false -- (temporary) log riding a held car ("magic carpet")
Config.Debug = false    -- true = log every impact and distance change

return Config
