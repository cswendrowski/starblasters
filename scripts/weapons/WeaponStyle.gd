extends RefCounted

# Primary CANNON weapon style. Drives player.fire_primary's branching:
# muzzle FX, audio loop (MG / Rotary), ammo gating, and HUD ammo
# visibility. Each CANNON Part MUST snapshot the prior style in apply()
# and write its own value — never leave it inherited from a previously
# equipped weapon (silent fallback violation per CLAUDE.md).
#
# Migrated from stringly-typed "energy"/"machinegun"/"rotary_laser" on
# 2026-05-24. Heavy Blaster previously forgot to set the style at all
# and inherited whichever cannon was equipped before it — most painfully
# the Machinegun, which routed Heavy Blaster fire through the MG audio
# loop.

enum WeaponStyle {
	ENERGY,        # base blaster, heavy blaster, laser beam, spread, wave
	MACHINEGUN,    # MG ammo + brrrt audio loop path
	ROTARY_LASER,  # charge-up + ammo path
	BEAM,          # reserved for hit-scan primaries (currently secondary)
}

static func style_name(s: int) -> String:
	match s:
		WeaponStyle.ENERGY: return "Energy"
		WeaponStyle.MACHINEGUN: return "Machinegun"
		WeaponStyle.ROTARY_LASER: return "Rotary Laser"
		WeaponStyle.BEAM: return "Beam"
		_: return "Unknown"


# Secondary fire pipeline mode. Drives player.fire_secondary's branching:
# BULLET routes through the projectile spawner (rockets, missiles, pods);
# BEAM runs the held-tick hit-scan path (Particle Beam). Each secondary
# Part MUST explicitly set this in apply() — no silent fallback through
# a default empty value. Migrated from stringly-typed "bullet"/"beam"/""
# on 2026-05-24.

enum SecondaryMode {
	BULLET,    # standard projectile (rocket, missile, pods)
	BEAM,      # hit-scan beam (particle beam)
	BURST,     # burst-fire ordnance (Rocket Pod): N rockets at a fixed RPM,
	           # alternating wing ports, then a fixed cooldown before the
	           # next cycle. State machine lives in player._tick_burst.
	DEPLOY,    # timed deployable (Combat Drones): one press spawns a wave of
	           # companion drones for a duration, consuming one deploy charge.
	           # Re-deploy is blocked while a wave is live. Duration countdown
	           # + active gate + ammo decrement live in player._tick_deploy;
	           # the Part's deploy() spawns + returns the drone nodes.
}


# Per-shot fire SFX routing for CANNON Parts. Lives alongside WeaponStyle
# because the two travel together — every cannon Part sets both in apply().
# Migrated from stringly-typed "blaster_small" / "" on 2026-05-24 to kill
# the silent fallback where an empty string implicitly routed through
# $ShootSound. NONE is now an explicit enum value — the player's
# fire_primary still falls back to $ShootSound for NONE, but the intent
# reads at the call site instead of being hidden in an empty literal.
enum FireSfxKind {
	NONE,           # Explicit fallback to player's $ShootSound (e.g. Auto Laser placeholder)
	BLASTER_SMALL,  # base + spread blaster (SMALL_CLIPS pool)
	BLASTER_LARGE,  # heavy blaster (LARGE_CLIPS pool)
	PULSE,          # generic pulse (PULSE_CLIPS pool)
	WAVE,           # wave gun Mk.1-4, small projectile (WAVE_CLIPS pool)
	WAVE_BIG,       # wave gun Mk.5+, large projectile (WAVE_BIG_CLIPS pool)
	MACHINEGUN,     # reserved — MG currently routes via weapon_style audio loop
	ROTARY_LASER,   # reserved — rotary currently routes via weapon_style audio loop
	BEAM,           # reserved — placeholder for future beam SFX
}


# Bridge from the enum back to the legacy string pool keys consumed by
# WeaponSfx.play(kind: String). Keeps the SFX pool dictionary untouched
# while the call sites move to the enum. NONE returns "" — WeaponSfx.play
# will early-out on the unknown kind, and player.fire_primary branches on
# FireSfxKind.NONE explicitly to play $ShootSound.
static func sfx_kind_string(k: int) -> String:
	match k:
		FireSfxKind.NONE: return ""
		FireSfxKind.BLASTER_SMALL: return "blaster_small"
		FireSfxKind.BLASTER_LARGE: return "blaster_large"
		FireSfxKind.PULSE: return "pulse"
		FireSfxKind.WAVE: return "wave"
		FireSfxKind.WAVE_BIG: return "wave_big"
		FireSfxKind.MACHINEGUN: return "machinegun"
		FireSfxKind.ROTARY_LASER: return "rotary_laser"
		FireSfxKind.BEAM: return "beam"
		_: return ""
