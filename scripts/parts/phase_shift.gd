extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Phase Shift — pure defensive super. On activation:
#   - Player goes invulnerable for the duration.
#   - Every enemy bullet on screen is cancelled.
#   - No damage burst, no fire boost — just "make me safe NOW."
#
# Pairs well with builds that want the offensive output of their primary
# but need a panic-cancel option. Trade vs Smart Bomb: same screen-clear
# but no enemy damage. Trade vs Hyper: same survival edge but no offence.

@export var base_duration: float = 2.0
@export var duration_per_mark: float = 0.2
@export var base_charges: int = 3
@export var charges_per_mark: int = 1


func _init() -> void:
	slot_type = Slots.SlotType.DEVICE_BAY_1
	display_name = "Phase Shift"
	description = "Brief invulnerability + bullet cancel. Defensive super."


func apply(ship) -> void:
	if not ("super_part" in ship):
		return
	ship.super_part = self
	ship.max_super_charges = base_charges + (int(mark) - 1) * charges_per_mark
	ship.super_charges = ship.max_super_charges
	if ship.has_signal("super_charges_changed"):
		ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)


func unapply(ship) -> void:
	if not ("super_part" in ship):
		return
	if ship.super_part == self:
		ship.super_part = null
		ship.super_charges = 0
		if ship.has_signal("super_charges_changed"):
			ship.super_charges_changed.emit(0, 0)


func activate(ship) -> void:
	var dur: float = base_duration + (float(mark) - 1.0) * duration_per_mark
	if "_invuln_t" in ship:
		ship._invuln_t = max(ship._invuln_t, dur)
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	# Cancel every bullet on screen (same path as Smart Bomb, minus the
	# enemy-damage step).
	for b in tree.get_nodes_in_group("bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	# Distinct activation VFX — radial ring of small bursts so the
	# bullet-cancel reads as "wall of force around the ship," visibly
	# different from Smart Bomb's tight panic-burst and Hyper's single
	# flash. (No tinting available; we differentiate by SHAPE.)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx:
		ExplosionFx.play(ship.global_position, 1.2, true)
		ExplosionFx.burst(ship.global_position, 6, 36.0, 0.0)
	# Camera nudge — every other super has one; without it Phase Shift's
	# activation has no tactile feedback when no bullets are onscreen.
	var main: Node = tree.get_current_scene()
	if main and main.has_node("Camera2D"):
		var cam = main.get_node("Camera2D")
		if cam.has_method("add_trauma"):
			cam.add_trauma(0.35)


# Editor readout — duration-based, no damage. Report duration*5 as a
# placeholder so the DPS box isn't blank.
func effective_damage(at_mark: int) -> int:
	return int(round((base_duration + (float(at_mark) - 1.0) * duration_per_mark) * 5.0))
