extends "res://scripts/parts/mode_part.gd"

# Focus — the default Shift mode. Tap Shift for a burst of bonus CRIT chance: while active
# your primary fire gains crit_chance, which STACKS additively with the Targeting Computer
# module's crit. Charges refill over time. The EFFECT lives in player.gd (the fire_primary
# crit roll, gated on _focus_on()). Focus is the default, so its duration/charges are flat.
# (Reworked 2026-06-25 — the old precision-slow stance is retired.)
# Design: docs/shift_mode_system_2026-06-08.md.

@export var duration: float = 3.0       # seconds of crit window per activation
@export var charges: int = 3            # discrete charges (HUD pips)
@export var regen_secs: float = 3.0     # seconds to refill one charge (while idle)
@export var base_crit_chance: float = 0.15      # +15% crit at Mk1
@export var crit_chance_per_mark: float = 0.03  # +3% per further Mk


func _init() -> void:
	super._init()
	mode_id = Mode.FOCUS
	display_name = "Focus"
	description = "Tap Shift to sharpen your aim — bonus critical-hit chance on your primary fire for a few seconds (stacks with Targeting Computer). The default mode."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs


# +crit chance while active. Mk1 = base; each further Mk adds crit_chance_per_mark.
func crit_chance_at_mark(at_mark: int) -> float:
	return clampf(base_crit_chance + float(clampi(at_mark, 1, 9) - 1) * crit_chance_per_mark, 0.0, 1.0)
