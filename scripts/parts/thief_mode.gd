extends "res://scripts/parts/mode_part.gd"

# Thief — Shift mode. Tap Shift to project a purple catch-bubble around your ship for the
# duration; enemy bullets that enter the sphere are STOLEN (deleted) and converted into
# shield regen, a few points per catch. Effect lives in player.gd (_set_mode_field +
# _on_mode_field_hit, gated on _thief_on()). Charges refill over time. Mk scaling
# (2026-07-11, the Phase alternation): even Mk +0.5s duration; odd Mk >1 = +1 charge
# → Mk.9 = 6s / 6 charges. First-pass nums.

@export var duration: float = 4.0        # bubble seconds at Mk.1
@export var charges: int = 2             # charges at Mk.1
@export var regen_secs: float = 5.0
@export var duration_per_even_mark: float = 0.5  # +0.5s per even Mk (2,4,6,8)
@export var regen_per_hit: int = 1       # shield restored per caught bullet
@export var catch_radius: float = 14.0   # bubble radius (px) — just over the ship's shield ring


func _init() -> void:
	super._init()
	mode_id = Mode.THIEF
	display_name = "Thief"
	description = "Tap Shift to deploy a catch-field — enemy bullets entering the sphere are stolen and converted to shield. Charges refill over time."


# Even Mk (2,4,6,8) each add +0.5s; odd Mk >1 (3,5,7,9) each add +1 charge.
func mode_duration(at_mark: int) -> float:
	return duration + float(int(at_mark / 2)) * duration_per_even_mark

func mode_charges(at_mark: int) -> int:
	return charges + int((at_mark - 1) / 2)

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs
