extends "res://scripts/parts/primary_weapon.gd"

# Auto Laser (formerly Laser Beam). Alternating left/right tandem energy
# bolts at moderate cadence. Player.fire_primary handles the toggle via
# fire_tandem_alternating.
#
# Roman, 2026-05-24: placeholder fire SFX — NONE routes through the
# legacy $ShootSound on the player scene.


func _init() -> void:
	super._init()
	display_name = "Auto Laser"
	description = "Alternating left/right tandem bolts. Moderate rate of fire."
	base_damage = 3
	dmg_per_mark = 3
	base_cooldown = 0.18


# Default _fire_sfx_kind() returns NONE; default _weapon_style() returns ENERGY.
# Both correct for Auto Laser — no overrides needed.


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("fire_tandem_alternating")
	keys.append("_tandem_side")
	keys.append("use_rotary_laser_muzzle")
	return keys


func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	if "fire_tandem_alternating" in ship:
		ship.fire_tandem_alternating = true
	if "_tandem_side" in ship:
		ship._tandem_side = 0
	if "use_rotary_laser_muzzle" in ship:
		ship.use_rotary_laser_muzzle = true
