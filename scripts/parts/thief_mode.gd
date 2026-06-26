extends "res://scripts/parts/mode_part.gd"

# Thief — Shift mode. Tap Shift to project a purple catch-bubble around your ship for the
# duration; enemy bullets that enter the sphere are STOLEN (deleted) and converted into
# shield regen, a few points per catch. Effect lives in player.gd (_set_mode_field +
# _on_mode_field_hit, gated on _thief_on()). Charges refill over time. First-pass nums.

@export var duration: float = 4.0
@export var charges: int = 2
@export var regen_secs: float = 5.0
@export var regen_per_hit: int = 1       # shield restored per caught bullet
@export var catch_radius: float = 14.0   # bubble radius (px) — just over the ship's shield ring


func _init() -> void:
	super._init()
	mode_id = Mode.THIEF
	display_name = "Thief"
	description = "Tap Shift to deploy a catch-field — enemy bullets entering the sphere are stolen and converted to shield. Charges refill over time."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs
