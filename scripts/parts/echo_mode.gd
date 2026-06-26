extends "res://scripts/parts/mode_part.gd"

# Echo — Shift mode. Tap Shift to spawn a translucent ghost that trails your movement on a
# short delay and re-fires your PRIMARY weapon exactly as you did, doubling your forward fire
# for the duration. Fades out when the window ends. Effect lives in player.gd (the Echo
# position/fire ring-buffer + the EchoGhost node, gated on _echo_on()). Charges refill over
# time. Numbers first-pass (tuner job).

@export var duration: float = 5.0
@export var charges: int = 2
@export var regen_secs: float = 6.0
@export var delay: float = 0.35          # seconds the ghost trails behind you


func _init() -> void:
	super._init()
	mode_id = Mode.ECHO
	display_name = "Echo"
	description = "Tap Shift to split off a ghost that mirrors your moves a beat behind and fires your weapon with you. Fades when the window ends. Charges refill over time."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs
