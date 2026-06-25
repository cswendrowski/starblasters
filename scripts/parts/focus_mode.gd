extends "res://scripts/parts/mode_part.gd"

# Focus — the default Shift mode. Precision stance: 0.55x move speed, tight hitbox
# dot + cyan glow/trail, intangible-feel dodging. Plugs into the unified Shift-mode
# system (mode_part.gd): tap Shift to activate for `duration` seconds at the cost of one
# charge; charges refill over time. The EFFECT lives in player.gd (gated on
# active_mode == FOCUS). Focus is the default, so its data is flat (no Mk scaling).
# Design: docs/shift_mode_system_2026-06-08.md §3.1.

@export var duration: float = 3.0       # seconds of precision per activation
@export var charges: int = 3            # discrete charges (HUD pips)
@export var regen_secs: float = 3.0     # seconds to refill one charge (while idle)


func _init() -> void:
	super._init()
	mode_id = Mode.FOCUS
	display_name = "Focus"
	description = "Precision stance: tap Shift for a few seconds of slow, tight-hitbox dodging. Charges refill over time. The default mode."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs
