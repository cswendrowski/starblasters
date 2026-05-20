extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Particle Beam — secondary continuous beam. Hold shoot2 (C) to fire.
# Pierces through any enemy NOT flagged tough or boss; stops at the
# first tough/boss enemy in its column.
#
# Mk scaling (Cody 2026-05-20 spec):
#   - Width: 6 px @ Mk.1 → +1 px per Mk → 14 px @ Mk.9.
#   - Damage: 1 dmg per tick @ Mk.1 → +1 per Mk → 9 dmg per tick @ Mk.9.
# "Per tick" = per frame the beam is active, applied to every enemy in
# the column.

@export var base_damage_per_tick: int = 1
@export var damage_per_mark: int = 1
@export var base_width: float = 6.0
@export var width_per_mark: float = 1.0


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Particle Beam"
	description = "Continuous secondary beam. Pierces chaff, stops on tough/boss enemies. Mk widens the beam + bumps damage."


func apply(ship) -> void:
	if not ("secondary_mode" in ship):
		return
	ship.secondary_mode = "beam"
	if "secondary_beam_damage" in ship:
		ship.secondary_beam_damage = base_damage_per_tick + (int(mark) - 1) * damage_per_mark
	if "secondary_beam_width" in ship:
		ship.secondary_beam_width = base_width + (float(mark) - 1.0) * width_per_mark


func unapply(ship) -> void:
	if not ("secondary_mode" in ship):
		return
	if ship.secondary_mode == "beam":
		ship.secondary_mode = ""
		# Tear down the beam visual if it's currently on.
		if "_beam_line" in ship and ship._beam_line and ship._beam_line.visible:
			ship._beam_line.visible = false
		if "_beam_halo" in ship and ship._beam_halo and ship._beam_halo.visible:
			ship._beam_halo.visible = false
		if "_beam_core" in ship and ship._beam_core and ship._beam_core.visible:
			ship._beam_core.visible = false
		ship._beam_active = false


# Editor readout — per-tick damage at this Mk.
func effective_damage(at_mark: int) -> int:
	return base_damage_per_tick + (at_mark - 1) * damage_per_mark
