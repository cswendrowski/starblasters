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
