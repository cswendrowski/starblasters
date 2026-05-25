extends "res://scripts/parts/super_part.gd"

# Hyper Mode — DoDonPachi / Cave-lineage super. On activation:
#   - Player goes invulnerable for the duration.
#   - Primary fire ignores GunCooldown for the duration (auto-fires
#     every frame at max cadence).
#   - Bullet damage is multiplied (constant in player.gd::HYPER_DAMAGE_MULT).

@export var base_duration: float = 3.0
@export var duration_per_mark: float = 0.25


func _init() -> void:
	super._init()
	display_name = "Hyper Mode"
	description = "Brief invulnerability + supercharged primary. Offensive super."
	base_charges = 2
	charges_per_mark = 1


func activate(ship) -> void:
	var dur: float = base_duration + (float(mark) - 1.0) * duration_per_mark
	# _hyper_t > 0 → bypass GunCooldown + 2× damage in player._process.
	# _invuln_t > 0 → take_damage bails immediately.
	if "_hyper_t" in ship:
		ship._hyper_t = dur
	if "_invuln_t" in ship:
		ship._invuln_t = max(ship._invuln_t, dur)
	# VFX — tight central flash for "one big punch from the ship outward."
	_flash_at(ship, 1.8)
	_burst_at(ship, 3, 8.0, 0.04)
	_camera_trauma(ship, 0.4)


func effective_damage(at_mark: int) -> int:
	return int(round((base_duration + (float(at_mark) - 1.0) * duration_per_mark) * 10.0))
