extends "res://scripts/parts/metered_primary.gd"

# Quad Lasers (Roman 2026-06-11) — metered energy cannon firing FOUR parallel bolts
# at once from ≈-5,-3,+3,+5 (±1px around each wing muzzle), a 4-lane spread for wide
# coverage / screen-clearing. Uses the rotary-laser bolt + the rotary blue muzzle
# flash; an energy-laser pew per volley. Regenerating ammo like the other lasers (no
# outpost refill). Light per-bolt damage + moderate cadence: trades single-target
# focus for width, and is ammo-gated. weapon_style is ENERGY (not ROTARY_LASER) so it
# skips the rotary charge-up — the rotary LOOK comes from use_rotary_laser_muzzle.

const BulletRotaryLaser = preload("res://scenes/projectiles/bullet_rotary_laser.tscn")
# ±1px around each wing muzzle (≈±4) → 4 parallel lanes. (Not const: a packed
# array literal isn't a constant expression in GDScript.)
static var QUAD_OFFSETS := PackedFloat32Array([-5.0, -3.0, 3.0, 5.0])


func _init() -> void:
	super._init()
	display_name = "Quad Lasers"
	description = "Fires four parallel laser bolts at once for wide coverage. Mk.1: 90 ammo, regen 2.5/sec; +20 ammo per Mk."
	base_damage = 1
	dmg_per_mark = 0
	base_cooldown = 0.12
	base_ammo = 90
	ammo_recharge_rate = 2.5
	no_outpost_refill = true
	if bullet_scene == null:
		bullet_scene = BulletRotaryLaser


func _weapon_style() -> int:
	return WS.WeaponStyle.ENERGY


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.AUTOLASER


func ammo_at_mark(mk: int) -> int:
	return 90 + 20 * (mk - 1)


func _damage_for_mark(at_mark: int) -> int:
	# Per bolt: Mk.1=1 → Mk.9=3 (×4 bolts on screen).
	return int(round(1.0 + 2.0 * (clampf(float(at_mark), 1.0, 9.0) - 1.0) / 8.0))


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": Callable(self, "_damage_for_mark"),
		"cooldown": [base_cooldown, base_cooldown],
	}


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("use_rotary_laser_muzzle")
	keys.append("primary_parallel_offsets")
	return keys


func _apply_visuals(ship) -> void:
	# Seed per-mark ammo BEFORE super so metered_primary reads the right current_ammo.
	current_ammo = ammo_at_mark(int(mark))
	super._apply_visuals(ship)
	if "ammo_max" in ship:
		ship.ammo_max = ammo_at_mark(int(mark))
	# Rotary look (flash) + 4 parallel bolts + the rotary bolt sprite.
	if "use_rotary_laser_muzzle" in ship:
		ship.use_rotary_laser_muzzle = true
	if "primary_parallel_offsets" in ship:
		ship.primary_parallel_offsets = QUAD_OFFSETS
	if "bullet_scene" in ship:
		ship.bullet_scene = BulletRotaryLaser
