extends RefCounted
class_name ShipVisualsCatalog

# Static registry of the modular ship art under res://graphics/main-ship/.
# Maps enum-style keys to Texture2D resources and the hframes for animated
# strips. Consumed by ShipVisuals (in-game) and the Hangar (test scene).
#
# All sprites come from the same pixel-art set so their internal origins line
# up — a ShipVisuals layout offset that works for the base body works for
# every other body variant too.

# ---- Hull body --------------------------------------------------------------
# Damage tiers map directly to hull % thresholds:
#   FULL          ≥ 0.75
#   SLIGHT_DMG    ≥ 0.50
#   DAMAGED       ≥ 0.25
#   VERY_DAMAGED  > 0.0
enum HullState { FULL, SLIGHT, DAMAGED, VERY_DAMAGED }

const HULL_TEXTURES := {
	HullState.FULL: preload("res://graphics/main-ship/Main Ship - Base - Full health.png"),
	HullState.SLIGHT: preload("res://graphics/main-ship/Main Ship - Base - Slight damage.png"),
	HullState.DAMAGED: preload("res://graphics/main-ship/Main Ship - Base - Damaged.png"),
	HullState.VERY_DAMAGED: preload("res://graphics/main-ship/Main Ship - Base - Very damaged.png"),
}

static func hull_state_for_pct(pct: float) -> int:
	if pct >= 0.75:
		return HullState.FULL
	if pct >= 0.50:
		return HullState.SLIGHT
	if pct >= 0.25:
		return HullState.DAMAGED
	return HullState.VERY_DAMAGED


# ---- Engines ----------------------------------------------------------------
# Each engine has Idle and Powering animation strips. The base + powering
# sheets are loose horizontal strips of the same height.
enum EngineModel { BASE, BIG_PULSE, BURST, SUPERCHARGED }

# `idle` and `powering` are textures; `idle_frames` / `powering_frames` say how
# many horizontal frames each strip has. ShipVisuals cycles them at FPS.
# Frame counts measured directly from the source PNGs (Image.Width / 48).
# Body and all part strips share a 48-pixel frame width; the per-frame art
# already contains the part's offset from the body anchor, so all overlay
# sprites mount at the same (0,0) origin as the hull.
const ENGINES := {
	EngineModel.BASE: {
		"label": "Base Engine",
		"idle": preload("res://graphics/main-ship/Main Ship - Engines - Base Engine - Idle.png"),
		"idle_frames": 3,
		"powering": preload("res://graphics/main-ship/Main Ship - Engines - Base Engine - Powering.png"),
		"powering_frames": 4,
		"mount": preload("res://graphics/main-ship/Main Ship - Engines - Base Engine.png"),
	},
	EngineModel.BIG_PULSE: {
		"label": "Big Pulse Engine",
		"idle": preload("res://graphics/main-ship/Main Ship - Engines - Big Pulse Engine - Idle.png"),
		"idle_frames": 4,
		"powering": preload("res://graphics/main-ship/Main Ship - Engines - Big Pulse Engine - Powering.png"),
		"powering_frames": 4,
		"mount": preload("res://graphics/main-ship/Main Ship - Engines - Big Pulse Engine.png"),
	},
	EngineModel.BURST: {
		"label": "Burst Engine",
		"idle": preload("res://graphics/main-ship/Main Ship - Engines - Burst Engine - Idle.png"),
		"idle_frames": 7,
		"powering": preload("res://graphics/main-ship/Main Ship - Engines - Burst Engine - Powering.png"),
		"powering_frames": 6,
		"mount": preload("res://graphics/main-ship/Main Ship - Engines - Burst Engine.png"),
	},
	EngineModel.SUPERCHARGED: {
		"label": "Supercharged Engine",
		"idle": preload("res://graphics/main-ship/Main Ship - Engines - Supercharged Engine - Idle.png"),
		"idle_frames": 4,
		"powering": preload("res://graphics/main-ship/Main Ship - Engines - Supercharged Engine - Powering.png"),
		"powering_frames": 4,
		"mount": preload("res://graphics/main-ship/Main Ship - Engines - Supercharged Engine.png"),
	},
}


# ---- Shields ----------------------------------------------------------------
# Shield strips are animated overlays. hframes is the count of frames in the
# horizontal strip; ShipVisuals cycles them while the shield is up.
enum ShieldModel { FRONT, FRONT_SIDE, ROUND, INVINCIBILITY }

const SHIELDS := {
	ShieldModel.FRONT: {
		"label": "Front Shield",
		"texture": preload("res://graphics/main-ship/Main Ship - Shields - Front Shield.png"),
		"hframes": 10,
	},
	ShieldModel.FRONT_SIDE: {
		"label": "Front+Side Shield",
		"texture": preload("res://graphics/main-ship/Main Ship - Shields - Front and Side Shield.png"),
		"hframes": 6,
	},
	ShieldModel.ROUND: {
		"label": "Round Shield",
		"texture": preload("res://graphics/main-ship/Main Ship - Shields - Round Shield.png"),
		"hframes": 12,
	},
	ShieldModel.INVINCIBILITY: {
		"label": "Invincibility",
		"texture": preload("res://graphics/main-ship/Main Ship - Shields - Invincibility Shield.png"),
		"hframes": 10,
	},
}


# ---- Weapons ----------------------------------------------------------------
# Each weapon strip is a row of mark tiers. Mk.1 == frame 0; the strip's
# last frame is the top-tier visual. ShipVisuals picks the frame based on
# the part's mark.
enum WeaponModel { AUTO_CANNON, BIG_SPACE_GUN, ROCKETS, ZAPPER }

# `muzzles` is a list of local-space offsets (inside the 48-px body frame,
# (0,0) = body center) where each shot of a volley spawns. Auto Cannon and
# Zapper fire one projectile from each muzzle per trigger pull.
# Rockets are different: `volley_order` indexes into `muzzles` to fire one
# rocket per pull, inside-out (inner-left first per Roman, 2026-05-16). The
# strip frame steps through `depletion_frames` to show fewer rockets remaining.
const WEAPONS := {
	WeaponModel.AUTO_CANNON: {
		"label": "Auto Cannon",
		"texture": preload("res://graphics/main-ship/Main Ship - Weapons - Auto Cannon.png"),
		"hframes": 7,
		"projectile": preload("res://graphics/main-ship/Main ship weapon - Projectile - Auto cannon bullet.png"),
		"projectile_hframes": 4,
		"muzzles": [Vector2(-7, -8), Vector2(7, -8)],
	},
	WeaponModel.BIG_SPACE_GUN: {
		"label": "Big Space Gun",
		"texture": preload("res://graphics/main-ship/Main Ship - Weapons - Big Space Gun.png"),
		"hframes": 12,
		"projectile": preload("res://graphics/main-ship/Main ship weapon - Projectile - Big Space Gun.png"),
		"projectile_hframes": 10,
		"muzzles": [Vector2(0, -12)],
	},
	WeaponModel.ROCKETS: {
		"label": "Rockets",
		"texture": preload("res://graphics/main-ship/Main Ship - Weapons - Rockets.png"),
		"hframes": 17,
		"projectile": preload("res://graphics/main-ship/Main ship weapon - Projectile - Rocket.png"),
		"projectile_hframes": 3,
		# 6 rocket tubes, 3 per side. Order = inner→outer, alternating sides
		# starting with inner-left.
		"muzzles": [
			Vector2(-3, -4),   # inner-left   (fire 1)
			Vector2( 3, -4),   # inner-right  (fire 2)
			Vector2(-7, -4),   # mid-left     (fire 3)
			Vector2( 7, -4),   # mid-right    (fire 4)
			Vector2(-11, -4),  # outer-left   (fire 5)
			Vector2( 11, -4),  # outer-right  (fire 6)
		],
		# Strip frame to show after N rockets have been fired (index N).
		# Evenly spread across the 17-frame strip; tune later if specific
		# frames map to specific tube states.
		"depletion_frames": [0, 3, 6, 8, 11, 13, 16],
	},
	WeaponModel.ZAPPER: {
		"label": "Zapper",
		"texture": preload("res://graphics/main-ship/Main Ship - Weapons - Zapper.png"),
		"hframes": 14,
		"projectile": preload("res://graphics/main-ship/Main ship weapon - Projectile - Zapper.png"),
		"projectile_hframes": 8,
		"muzzles": [Vector2(-7, -8), Vector2(7, -8)],
	},
}


# Convenience: return all entries of a category as ordered (key, label) pairs.
static func engine_options() -> Array:
	return [
		[EngineModel.BASE, "Base"],
		[EngineModel.BIG_PULSE, "Big Pulse"],
		[EngineModel.BURST, "Burst"],
		[EngineModel.SUPERCHARGED, "Supercharged"],
	]

static func shield_options() -> Array:
	return [
		[ShieldModel.FRONT, "Front"],
		[ShieldModel.FRONT_SIDE, "Front+Side"],
		[ShieldModel.ROUND, "Round"],
		[ShieldModel.INVINCIBILITY, "Invincibility"],
	]

static func weapon_options() -> Array:
	return [
		[WeaponModel.AUTO_CANNON, "Auto Cannon"],
		[WeaponModel.BIG_SPACE_GUN, "Big Space Gun"],
		[WeaponModel.ROCKETS, "Rockets"],
		[WeaponModel.ZAPPER, "Zapper"],
	]

static func hull_options() -> Array:
	return [
		[HullState.FULL, "Full"],
		[HullState.SLIGHT, "Slight"],
		[HullState.DAMAGED, "Damaged"],
		[HullState.VERY_DAMAGED, "Very Damaged"],
	]
