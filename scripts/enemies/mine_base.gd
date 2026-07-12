extends "res://scripts/enemies/enemy_core.gd"

# Shared base for the enemy_core-driven field mines (basic / shielded / smart / gravity). Owns the
# boilerplate every field mine used to re-implement independently: the hazard flags (is_hazard, no
# ship VFX, no auto-rotate, unit display scale, recycle_passes = 0 so it frees off the bottom instead
# of parallax-cycling) + the Ordnance-Disposal bounty bonus. Extends enemy_core (path-based, matching
# the mines' own `extends`), so the mines keep their movement / component / shoot slots unchanged.
#
# ORDERING (mirrors the boss-base "set stats then super" pattern in CLAUDE.md): each mine sets its OWN
# bounty_value / max_health / movement / components in its _ready(), THEN calls super._ready() — which
# lands here. This applies the shared flags + adds the bounty bonus ON TOP of the child's bounty_value,
# then chains up to enemy_core._ready(). The bonus therefore always runs AFTER the child set its base
# bounty_value, and BEFORE enemy_base._ready() reads the flags (has_ship_vfx / auto_rotate / is_hazard).
#
# The tether mine can NOT share this base: it extends enemy_base directly for its bespoke pull/beam and
# must NOT gain enemy_core's oblique drop-shadow. It reuses just the bounty math via the static helper.

func _ready() -> void:
	is_hazard = true
	display_scale = 1.0
	auto_rotate = false       # mines don't have a "forward"
	has_ship_vfx = false      # no engine flame / damage-overlay — mines explode, not fray
	recycle_passes = 0        # off the bottom = free, never parallax-cycle
	# Ordnance Disposal Condition (grant.mine_bounty) + events (mine_bonus_bounty) both raise per-mine
	# bounty; additive so they STACK (design §4f). Applied on TOP of the child's already-set bounty_value.
	apply_mine_bounty_bonus(self)
	super._ready()


# Shared Ordnance-Disposal / event bounty bonus, applied on top of the mine's own bounty_value. Static
# so the tether mine (enemy_base-based, can't extend this class) reuses the IDENTICAL math. Guarded on
# /root/Run so headless / no-Run boots are a clean no-op. Mirror of the asteroid_bonus_bounty path in
# asteroid.gd.
static func apply_mine_bounty_bonus(mine: Node) -> void:
	if mine.has_node("/root/Run"):
		var _run = mine.get_node("/root/Run")
		mine.bounty_value += int(_run.mine_bonus_bounty) + int(_run.cond_sum("grant.mine_bounty"))
