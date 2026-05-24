extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Particle Beam — secondary continuous beam. Hold shoot2 (C) to fire.
# Pierces through any enemy NOT flagged tough or boss; stops at the
# first tough/boss enemy in its column.
#
# Mk scaling (Cody 2026-05-20):
#   - Width: 6 px @ Mk.1 → +1 px per Mk → 14 px @ Mk.9.
#   - Damage: flat 30 DPS, no Mk scaling. Mk is purely the reach knob.

@export var base_dps: float = 30.0
@export var base_width: float = 6.0
@export var width_per_mark: float = 1.0


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
	# Beam is unmetered — clear any leftover Rocket/Missile ammo state.
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)


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


# Editor readout — flat DPS, no Mk scaling on damage.
func effective_damage(_at_mark: int) -> int:
	return int(round(base_dps))
