extends "res://scripts/parts/metered_primary.gd"

# Auto Laser (formerly Laser Beam). Alternating left/right tandem energy
# bolts at moderate cadence. Metered ammo (120 + 30/Mk); recharges at
# 3 shots/sec when not firing. No outpost refill — the natural recharge
# makes sold refills redundant.
#
# Roman, 2026-05-24: placeholder fire SFX — NONE routes through the
# legacy $ShootSound on the player scene.


func _init() -> void:
	super._init()
	display_name = "Auto Laser"
	description = "Alternating left/right tandem bolts. Mk.1: 120 ammo, recharges 3/sec. Each Mk adds 30 ammo and slightly tightens cadence."
	base_damage = 3
	dmg_per_mark = 0  # damage is fixed; cooldown scales via callable
	base_cooldown = 0.18
	base_ammo = 120
	ammo_recharge_rate = 3.0
	no_outpost_refill = true


func ammo_at_mark(mk: int) -> int:
	return 120 + 30 * (mk - 1)


func _cooldown_for_mark(at_mark: int) -> float:
	# Compound tightening: 0.18 / 1.1^(mk-1). Mk.1=0.18s, Mk.9≈0.085s.
	return 0.18 / pow(1.1, clampf(float(at_mark - 1), 0.0, 8.0))


# Default _fire_sfx_kind() returns NONE; default _weapon_style() returns ENERGY.
# Both correct for Auto Laser — no overrides needed.


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("fire_tandem_alternating")
	keys.append("_tandem_side")
	keys.append("use_rotary_laser_muzzle")
	return keys


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [3, 3],  # fixed
		"cooldown": Callable(self, "_cooldown_for_mark"),
	}


func _apply_visuals(ship) -> void:
	# Seed the per-mark ammo BEFORE super so metered_primary._apply_visuals
	# reads the correct current_ammo value (not the stale -1 default).
	current_ammo = ammo_at_mark(int(mark))
	super._apply_visuals(ship)
	# Overwrite ammo_max after super (super writes base_ammo = 120 flat).
	if "ammo_max" in ship:
		ship.ammo_max = ammo_at_mark(int(mark))
	if "fire_tandem_alternating" in ship:
		ship.fire_tandem_alternating = true
	if "_tandem_side" in ship:
		ship._tandem_side = 0
	if "use_rotary_laser_muzzle" in ship:
		ship.use_rotary_laser_muzzle = true
