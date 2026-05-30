extends "res://scripts/parts/bullet_secondary.gd"

# Rocket Pod. Secondary weapon (HARDPOINT_WING). Dumb-fire ordnance —
# fast, straight-line, contact-detonate burst from twin wing ports.
#
# Roman 2026-05-30 rework: burst-fire. A trigger looses `shots` rockets in
# sequence at 500 RPM (0.12s apart), alternating the -port / +port on X
# (±6px from ship center), then locks out for a 1.0s cooldown before the
# next cycle. The cycle/cooldown/port-toggle state machine LIVES IN THE
# PLAYER (player._tick_burst) — a Part is a Resource and can't tick. The
# cannon is the source of truth for the numbers: it sets secondary_mode =
# BURST plus the Mk-scaled shot count + per-rocket damage and the fixed
# burst constants. See player.gd secondary_burst_* fields.
#
# Mk scaling (alternating +2 shots, then +10% damage):
#   Mk1: 2 shots, 100%   Mk2: 4 shots, 100%   Mk3: 4 shots, 110%
#   Mk4: 6 shots, 110%   Mk5: 6 shots, 120%   Mk6: 8 shots, 120%
#   Mk7: 8 shots, 130%   Mk8: 10 shots, 130%  Mk9: 10 shots, 140%
# `shots` is always even, split evenly between the two ports.

const WSb = preload("res://scripts/weapons/WeaponStyle.gd")

# Fixed burst geometry / cadence (NOT Mk-scaled).
const BURST_RPM: float = 500.0
const BURST_INTERVAL: float = 60.0 / BURST_RPM   # 0.12s between rockets
const BURST_COOLDOWN: float = 1.0                # lockout after a full cycle
const PORT_OFFSET: float = 6.0                   # ±px from ship center


func _init() -> void:
	super._init()
	display_name = "Rocket Pod"
	description = "Burst-fire rockets from twin wing ports. Heavy hit, lead your shots. Secondary."
	# base_damage is the Mk1 per-rocket damage. 8 × 2 rockets = 16 = the HP
	# of a tough common enemy (cruiser / drone carrier / bomber), so the
	# base 2-rocket cycle reliably kills one. .tres overrides this; the
	# damage Callable reads self.base_damage so the .tres value wins.
	base_damage = 8
	dmg_per_mark = 0   # damage scales via the Mk Callable, not linear per-mark
	base_cooldown = 0.55


func _base_ammo() -> int:
	return 60


func _homing() -> bool:
	return false


func _secondary_mode() -> int:
	return WSb.SecondaryMode.BURST


# Total rockets per burst cycle. 2,4,4,6,6,8,8,10,10 across Mk1-9.
func _shots_for_mark(m: int) -> int:
	return 2 * int((m + 2) / 2)


# Per-rocket damage. Multiplier steps +10% every other Mk:
# 1.0,1.0,1.1,1.1,1.2,1.2,1.3,1.3,1.4. Rounded to int per rocket.
func _damage_for_mark(m: int) -> int:
	var mult: float = 1.0 + 0.1 * float(int((m - 1) / 2))
	return int(round(float(base_damage) * mult))


func _mk_knobs() -> Dictionary:
	return {
		"secondary_damage": Callable(self, "_damage_for_mark"),
		"secondary_burst_shots": Callable(self, "_shots_for_mark"),
		"secondary_burst_interval": BURST_INTERVAL,
		"secondary_burst_cooldown": BURST_COOLDOWN,
		"secondary_burst_port_offset": PORT_OFFSET,
	}


func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	# Reset the live burst state machine so a re-equip never resumes a
	# half-fired cycle or a stale cooldown from a previous loadout.
	if "_burst_phase" in ship:
		ship._burst_phase = 0
		ship._burst_shots_left = 0
		ship._burst_shot_t = 0.0
		ship._burst_cool_t = 0.0
		ship._burst_port_right = false
