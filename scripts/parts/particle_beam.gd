extends "res://scripts/parts/beam_secondary.gd"

# Particle Beam — secondary continuous beam. Hold shoot2 (C) to fire.
# Pierces through any enemy NOT flagged tough or boss; stops at the
# first tough/boss enemy in its column.
#
# Mk scaling: width 6 → 14 px linearly; damage flat 30 DPS (no Mk scaling).

@export var base_dps: float = 30.0
@export var base_width: float = 6.0
@export var width_per_mark: float = 1.0


func _init() -> void:
	super._init()
	display_name = "Particle Beam"
	description = "Continuous secondary beam. Pierces chaff, stops on tough/boss enemies. Mk widens the beam."


func _mk_knobs() -> Dictionary:
	return {
		"secondary_beam_dps": [base_dps, base_dps],
		"secondary_beam_width": [base_width, base_width + width_per_mark * 8.0],
	}


# Editor readout — flat DPS, no Mk scaling on damage.
func effective_damage(_at_mark: int) -> int:
	return int(round(base_dps))
