extends "res://scripts/parts/metered_primary.gd"

# Auto Laser (formerly Laser Beam). Alternating left/right tandem energy
# bolts at moderate cadence. Metered ammo (200 + 30/Mk); recharges at
# 3 shots/sec when not firing. No outpost refill — the natural recharge
# makes sold refills redundant.
#
# Roman, 2026-05-24: placeholder fire SFX — NONE routes through the
# legacy $ShootSound on the player scene.


func _init() -> void:
	super._init()
	display_name = "Auto Laser"
	description = "Alternating left/right tandem bolts. Mk.1: 200 ammo, recharges 3/sec. Each Mk adds 30 ammo and slightly tightens cadence."
	# Stats live in resources/weapons/laser_beam.tres (single source of truth).
	# NOTE: cadence + ammo curves are hardcoded in _cooldown_for_mark / ammo_at_mark
	# below (curve SHAPE = behavior); the .tres base_cooldown/base_ammo mirror Mk.1.


func ammo_at_mark(mk: int) -> int:
	return 200 + 30 * (mk - 1)


func _cooldown_for_mark(at_mark: int) -> float:
	# Compound tightening: 0.162 / 1.1^(mk-1). Mk.1=0.162s, Mk.9≈0.077s.
	return 0.162 / pow(1.1, clampf(float(at_mark - 1), 0.0, 8.0))


# Default _weapon_style() returns ENERGY (correct for Auto Laser). Fire SFX = the new autolaser set.
func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.AUTOLASER


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
	# The helper returns the mag for post-super ammo_max override.
	var mag: int = _seed_metered_ammo_for_mark(int(mark))
	super._apply_visuals(ship)
	# Overwrite ammo_max after super (super writes base_ammo = 200 flat).
	if "ammo_max" in ship:
		ship.ammo_max = mag
	if "fire_tandem_alternating" in ship:
		ship.fire_tandem_alternating = true
	if "_tandem_side" in ship:
		ship._tandem_side = 0
	if "use_rotary_laser_muzzle" in ship:
		ship.use_rotary_laser_muzzle = true
