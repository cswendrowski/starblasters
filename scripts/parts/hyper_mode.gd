extends "res://scripts/parts/mode_part.gd"

# Hyper — Shift mode (reworked 2026-06-25). Tap Shift to go full-auto: for the duration ALL
# your weapons fire automatically with NO ammo cost — the blaster AND your equipped cannon
# AND your secondary, all at once, hands-off. The "ultimate" burst. The EFFECT lives in
# player.gd (autofire dispatch + blaster-direct + secondary ammo-skip, gated on _hyper_on()).
# (The old +fire-rate/+damage buff moved to Refire; fire_bonus_at_mark/damage_mult_at_mark
# remain for save-compat but nothing reads them.) Mk scaling (2026-07-11, the Phase
# alternation): even Mk (2,4,6,8) each add duration_per_even_mark seconds of uptime; odd
# Mk >1 (3,5,7,9) each add +1 charge → Mk.9 = 6s / 6 charges. First-pass (tuner job).

@export var base_fire_bonus: float = 0.10        # legacy (unread) — kept for save-compat
@export var fire_bonus_per_odd_mark: float = 0.05  # legacy (unread) — kept for save-compat
@export var dmg_bonus_per_even_mark: float = 0.10  # legacy (unread) — kept for save-compat
@export var bar_seconds: float = 4.0             # active uptime per activation (duration bar)
@export var duration_per_even_mark: float = 0.5  # +0.5s per even Mk (2,4,6,8)
@export var recharge_per_sec: float = 0.8        # legacy refill rate → derives regen cadence
@export var charges: int = 2                     # discrete charges (HUD pips) at Mk.1


func _init() -> void:
	super._init()
	mode_id = Mode.HYPER
	display_name = "Hyper Mode"
	description = "Tap Shift to go full-auto — every weapon you have fires automatically with no ammo cost for a few seconds. Spends a charge; charges refill over time while idle."


# Mk1 = base; each further ODD Mk (3,5,7,9) adds fire_bonus_per_odd_mark.
# Count of {3,5,7,9} <= M = floor((M-1)/2).
func fire_bonus_at_mark(at_mark: int) -> float:
	return base_fire_bonus + float(int((at_mark - 1) / 2)) * fire_bonus_per_odd_mark


# Multiplier on primary damage while active. Each EVEN Mk (2,4,6,8) stacks
# dmg_bonus_per_even_mark. Count of {2,4,6,8} <= M = floor(M/2). 1.0 = no bonus.
func damage_mult_at_mark(at_mark: int) -> float:
	return 1.0 + float(int(at_mark / 2)) * dmg_bonus_per_even_mark


# --- Unified Shift-mode interface ---
# Regen derives from the legacy recharge_per_sec (0.8/s on a 4s bar = one charge per 5s).
# Even Mk (2,4,6,8) each add duration_per_even_mark: adds at Mk M = floor(M/2).
func mode_duration(at_mark: int) -> float:
	return bar_seconds + float(int(at_mark / 2)) * duration_per_even_mark

# Odd Mk >1 (3,5,7,9) each add +1 charge: adds at Mk M = floor((M-1)/2).
func mode_charges(at_mark: int) -> int:
	return charges + int((at_mark - 1) / 2)

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return bar_seconds / maxf(recharge_per_sec, 0.01)
