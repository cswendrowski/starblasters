extends "res://scripts/enemies/enemy_base.gd"

# Shield Pylon — a stationary boss-structure piece. A boss will (in a later
# follow-up) spawn a ring of these and gate its own damage behind them, so the
# player has to clear the pylons first. This script only defines the standalone
# combatant; the summon/gate wiring is intentionally NOT here.
#
# Why bespoke instead of enemy_core: the pylon never moves and never shoots, so
# the movement/shoot Resource slots would just sit empty. More importantly we
# want the progressive damage-overlay shader on the BODY without auto_rotate —
# auto_rotate is the base's gate for both the shader AND the parallax shadow,
# and a stationary structure that silently rotates to "face velocity" would
# look wrong (and has no velocity to face). So we keep auto_rotate off and
# install the damage material by hand after super._ready().


func _ready() -> void:
	# Stats BEFORE super._ready() — the base copies max_health into the live
	# `health` field inside its _ready(), so setting it afterward would leave
	# the pylon at 1 HP (the documented regression). No `<= 0 ? default`
	# fallback — set the real values here.
	# GUESS (designer to confirm): the designer did not specify HP/bounty.
	# 20 HP reads as a chunky boss-structure piece; 0 bounty because pylons are
	# expected to be a gate the player must clear, not a payout source.
	max_health = 20
	bounty_value = 0
	# Stationary structure: no banking, no parallax shadow, no flip_v handling.
	auto_rotate = false
	super._ready()
	# Re-add the damage overlay shader to the BODY only. The base skips this
	# when auto_rotate is false, but _update_damage_visual() (driven by
	# take_hit) only needs _damage_material != null — it does NOT depend on
	# auto_rotate. So this one call gives the body its darken/fray-on-damage
	# look while leaving the Orb (a separate Sprite2D) untouched and bright.
	if has_node("Sprite2D"):
		_install_damage_material($Sprite2D)
