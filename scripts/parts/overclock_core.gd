extends "res://scripts/parts/module_part.gd"

# Overclock Core — offensive Module (2026-06-13). Sustained fire RAMPS your rate of fire
# up to a cap (≈20 shots to full); stop firing for a beat and it resets. Rewards holding
# the trigger on a target. Default-safe: ship.module_overclock_max (0) is off until applied.
# The ramp + decay live on the player (OVERCLOCK_RAMP_PER_SHOT / OVERCLOCK_RESET_DELAY).
#   Mk.1 = +15% at full ramp  →  Mk.9 = +45%.
# Balance (2026-06-25): ceiling pulled down from +25%/+65% — this is the LOW-RISK,
# unconditional fire-rate module, so it must not out-ceiling the gated ones (De-Limiter
# needs near-death, Hyper needs the bar). Ramp also slowed on the player so the cap only
# pays off under genuinely sustained fire, not short bursts.


func _init() -> void:
	super._init()
	module_id = "overclock_core"
	display_name = "Overclock Core"
	description = "Hold fire and your rate-of-fire ramps up; release and it resets. Caps higher each Mk (Mk.1: +15% → Mk.9: +45%)."


func _max_bonus() -> float:
	return 0.15 + 0.0375 * float(clampi(int(mark), 1, 9) - 1)


func apply(ship) -> void:
	if "module_overclock_max" in ship:
		ship.module_overclock_max = maxf(float(ship.module_overclock_max), _max_bonus())


func unapply(ship) -> void:
	if "module_overclock_max" in ship:
		ship.module_overclock_max = 0.0


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var bonus: float = 0.15 + 0.0375 * float(m - 1)
	var pct: int = int(round(bonus * 100.0))
	return "+%d%% rate-of-fire when holding trigger" % pct
