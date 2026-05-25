extends "res://scripts/parts/super_part.gd"

# Phase Shift — pure defensive super. On activation:
#   - Player goes invulnerable for the duration.
#   - Every enemy bullet on screen is cancelled.
#   - No damage burst, no fire boost — just "make me safe NOW."

@export var base_duration: float = 2.0
@export var duration_per_mark: float = 0.2


func _init() -> void:
	super._init()
	display_name = "Phase Shift"
	description = "Brief invulnerability + bullet cancel. Defensive super."
	base_charges = 3
	charges_per_mark = 1


func activate(ship) -> void:
	var dur: float = base_duration + (float(mark) - 1.0) * duration_per_mark
	if "_invuln_t" in ship:
		ship._invuln_t = max(ship._invuln_t, dur)
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	# Cancel every bullet on screen (same path as Smart Bomb, minus damage).
	for b in tree.get_nodes_in_group("bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	# Wide ring of bursts — distinct from Smart Bomb's tight panic-burst
	# and Hyper's single flash. Differentiate by SHAPE since we can't tint.
	_flash_at(ship, 1.2)
	_burst_at(ship, 6, 36.0, 0.0)
	_camera_trauma(ship, 0.35)


func effective_damage(at_mark: int) -> int:
	return int(round((base_duration + (float(at_mark) - 1.0) * duration_per_mark) * 5.0))
