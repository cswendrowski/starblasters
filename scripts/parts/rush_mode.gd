extends "res://scripts/parts/mode_part.gd"

# Rush — Shift mode. Tap Shift for a short burst of extra move speed during which impacts
# do NO damage to you (a brief invulnerable dash) — but unlike Phase your offense stays ON,
# so it's an aggressive reposition, not a defensive blink. Charges refill over time.
# Effect lives in player.gd (gated on _rush_on()). Numbers first-pass (tuner job).

@export var duration: float = 2.5       # seconds of the dash
@export var charges: int = 3
@export var regen_secs: float = 4.0     # seconds to refill one charge (while idle)
@export var speed_bonus: float = 0.25   # +move-speed fraction while active


func _init() -> void:
	super._init()
	mode_id = Mode.RUSH
	display_name = "Rush"
	description = "Tap Shift to surge — faster movement and impacts do no damage for a few seconds, but you keep firing. Charges refill over time."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs
