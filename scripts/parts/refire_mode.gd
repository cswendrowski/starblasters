extends "res://scripts/parts/mode_part.gd"

# Refire — Shift mode. Tap Shift for a burst of higher rate-of-fire. Unlike Hyper you STILL
# pay ammo costs — it's a pure cadence boost, not a free-fire window. Charges refill over time.
# Effect lives in player.gd (gated on _refire_on(), feeds the _arm_cooldown fire-rate bonus).
# Numbers first-pass (tuner job).

@export var duration: float = 4.0
@export var charges: int = 2
@export var regen_secs: float = 5.0
@export var base_fire_bonus: float = 0.30      # +30% fire rate at Mk1
@export var fire_bonus_per_mark: float = 0.05  # +5% per further Mk


func _init() -> void:
	super._init()
	mode_id = Mode.REFIRE
	display_name = "Refire"
	description = "Tap Shift to overclock your trigger — a burst of faster fire. You still spend ammo. Charges refill over time."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs


# +fire-rate fraction while active. Mk1 = base; each further Mk adds fire_bonus_per_mark.
func fire_bonus_at_mark(at_mark: int) -> float:
	return base_fire_bonus + float(clampi(at_mark, 1, 9) - 1) * fire_bonus_per_mark
