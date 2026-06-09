extends "res://scripts/parts/mode_part.gd"

# Phase — Shift mode. A short intangibility BURST: identical dodge effect to Focus
# (passes through bullets + enemies, takes no hits) but with NO dot/trail and NO
# speed cut. Purely defensive — while phased the player cannot hit bullets OR
# enemies, and there is NO bullet-clear (that's the Smart Bomb's job; Phase is a
# reposition, not a panic clear). Charges refill by KILLING ENEMIES, not by time.
#
# Mk scaling alternates +1s duration / +1 charge:
#   even Mk (2,4,6,8) -> +1.0s duration; odd Mk >1 (3,5,7,9) -> +1 max charge.
# Design: docs/shift_mode_system_2026-06-08.md §3.2. Numbers first-pass (tuner job).

@export var base_duration: float = 1.5     # seconds of intangibility per activation
@export var base_charges: int = 2
@export var duration_per_step: float = 1.0  # +1s per even Mk
@export var kills_per_charge: int = 4       # enemy kills to earn one charge back


func _init() -> void:
	super._init()
	mode_id = Mode.PHASE
	display_name = "Phase"
	description = "Tap Shift to phase out — brief intangibility, no offense, no bullet-clear. Charges refill by killing enemies."


# Even Mk (2,4,6,8) each add +1s. Cumulative adds at Mk M = floor(M/2).
func duration_at_mark(at_mark: int) -> float:
	return base_duration + float(int(at_mark / 2)) * duration_per_step


# Odd Mk >1 (3,5,7,9) each add +1 charge. Cumulative adds at Mk M = floor((M-1)/2).
func charges_at_mark(at_mark: int) -> int:
	return base_charges + int((at_mark - 1) / 2)
