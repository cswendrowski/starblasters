extends "res://scripts/parts/mode_part.gd"

# Echo — Shift mode. Tap Shift to spawn a translucent ghost that trails your movement on a
# short delay and fires alongside you (baseline bolts at your fire cadence — it does NOT
# clone special cannon styles; see player._echo_fire_ghost_bolt). Fades out when the window
# ends. Effect lives in player.gd (the Echo position/fire ring-buffer + the EchoGhost node,
# gated on _echo_on()). Charges refill over time. Mk scaling (2026-07-11, the Phase
# alternation): even Mk +1s duration; odd Mk >1 = +1 charge → Mk.9 = 9s / 6 charges.

@export var duration: float = 5.0        # window seconds at Mk.1
@export var charges: int = 2             # charges at Mk.1
@export var regen_secs: float = 6.0
@export var delay: float = 0.35          # seconds the ghost trails behind you
@export var duration_per_even_mark: float = 1.0  # +1s per even Mk (2,4,6,8)


func _init() -> void:
	super._init()
	mode_id = Mode.ECHO
	display_name = "Echo"
	description = "Tap Shift to split off a ghost that mirrors your moves a beat behind and fires alongside you. Fades when the window ends. Charges refill over time."


# Even Mk (2,4,6,8) each add +1s window; odd Mk >1 (3,5,7,9) each add +1 charge.
func mode_duration(at_mark: int) -> float:
	return duration + float(int(at_mark / 2)) * duration_per_even_mark

func mode_charges(at_mark: int) -> int:
	return charges + int((at_mark - 1) / 2)

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs
