extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Particle Beam — secondary continuous beam. Hold shoot2 (C) to fire.
# Pierces through any enemy NOT flagged tough or boss; stops at the
# first tough/boss enemy in its column. Damage is DPS-based: dmg_per_sec
# distributed across every frame the beam is active and every enemy in
# the beam's path.
#
# Cody 2026-05-19: distinct from the (deferred) primary continuous-beam
# laser refactor — this lives in the HARDPOINT_WING secondary slot so
# it can supplement any primary cannon.

@export var base_dps: float = 30.0
@export var dps_per_mark: float = 5.0


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Particle Beam"
	description = "Continuous secondary beam. Pierces chaff, stops on tough/boss enemies."


func apply(ship) -> void:
	if not ("secondary_mode" in ship):
		return
	ship.secondary_mode = "beam"
	if "secondary_beam_dps" in ship:
		ship.secondary_beam_dps = base_dps + (float(mark) - 1.0) * dps_per_mark


func unapply(ship) -> void:
	if not ("secondary_mode" in ship):
		return
	if ship.secondary_mode == "beam":
		ship.secondary_mode = ""
		# Tear down the beam visual if it's currently on.
		if "_beam_line" in ship and ship._beam_line and ship._beam_line.visible:
			ship._beam_line.visible = false
		ship._beam_active = false


# Editor / DPS readout — DPS at this Mk, formatted as damage-per-second.
func effective_damage(at_mark: int) -> int:
	return int(round(base_dps + (float(at_mark) - 1.0) * dps_per_mark))
