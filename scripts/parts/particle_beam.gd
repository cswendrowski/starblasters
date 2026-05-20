extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Particle Beam — secondary continuous beam. Hold shoot2 (C) to fire.
# Pierces through any enemy NOT flagged tough or boss; stops at the
# first tough/boss enemy in its column.
#
# Mk scaling: damage stays constant; the BEAM WIDTH grows by
# width_per_mark pixels per Mk (Cody 2026-05-20). Wider beam = bigger
# hit column = easier to land hits + visibly more impressive at high
# Mk. Mk.1 = 3 px → Mk.9 = 19 px.

@export var base_dps: float = 30.0
@export var base_width: float = 3.0
@export var width_per_mark: float = 2.0


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Particle Beam"
	description = "Continuous secondary beam. Pierces chaff, stops on tough/boss enemies. Mk widens the beam."


func apply(ship) -> void:
	if not ("secondary_mode" in ship):
		return
	ship.secondary_mode = "beam"
	if "secondary_beam_dps" in ship:
		ship.secondary_beam_dps = base_dps
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
		ship._beam_active = false


# Editor readout — flat DPS now (no Mk scaling). Width is what the Mk
# slider grows, but DPS reporting needs a number — return base_dps so
# the readout matches actual damage.
func effective_damage(at_mark: int) -> int:
	return int(round(base_dps))
