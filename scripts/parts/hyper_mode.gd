extends "res://scripts/parts/mode_part.gd"

# Hyper — Shift mode. While active: primary fire is +10% faster AND has unlimited
# ammo (metered weapons don't deplete). NO invulnerability, NO damage mult at base —
# a sustain/uptime buff, not a nuke. Runs off a Focus-style charge bar that recharges
# only while NOT in use and CANNOT be re-engaged until fully recharged (no tapping:
# commit the whole bar, then wait for a full refill).
#
# Mk scaling:
#   odd Mk (1,3,5,7,9) -> increase the fire-rate boost (base 10% +5% per further odd Mk)
#   even Mk (2,4,6,8)  -> add a stacking +10% damage boost
# Design: docs/shift_mode_system_2026-06-08.md §3.3. Numbers first-pass (tuner job).

@export var base_fire_bonus: float = 0.10        # +10% fire rate at Mk1
@export var fire_bonus_per_odd_mark: float = 0.05  # each further odd Mk (3,5,7,9)
@export var dmg_bonus_per_even_mark: float = 0.10  # each even Mk (2,4,6,8) stacks
@export var bar_seconds: float = 4.0             # active uptime per activation (duration bar)
@export var recharge_per_sec: float = 0.8        # legacy refill rate → derives regen cadence
@export var charges: int = 2                     # discrete charges (HUD pips)


func _init() -> void:
	super._init()
	mode_id = Mode.HYPER
	display_name = "Hyper Mode"
	description = "Tap Shift to overdrive for a few seconds — +10% fire rate and unlimited ammo. Spends a charge; charges refill over time while idle."


# Mk1 = base; each further ODD Mk (3,5,7,9) adds fire_bonus_per_odd_mark.
# Count of {3,5,7,9} <= M = floor((M-1)/2).
func fire_bonus_at_mark(at_mark: int) -> float:
	return base_fire_bonus + float(int((at_mark - 1) / 2)) * fire_bonus_per_odd_mark


# Multiplier on primary damage while active. Each EVEN Mk (2,4,6,8) stacks
# dmg_bonus_per_even_mark. Count of {2,4,6,8} <= M = floor(M/2). 1.0 = no bonus.
func damage_mult_at_mark(at_mark: int) -> float:
	return 1.0 + float(int(at_mark / 2)) * dmg_bonus_per_even_mark


# --- Unified Shift-mode interface (Mk getters above drive the fire/dmg effect) ---
# Duration = bar_seconds; regen derives from the legacy recharge_per_sec (0.8/s on a 4s
# bar = one charge per 5s). Charges are flat (Mk unchanged).
func mode_duration(_at_mark: int) -> float:
	return bar_seconds

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return bar_seconds / maxf(recharge_per_sec, 0.01)
