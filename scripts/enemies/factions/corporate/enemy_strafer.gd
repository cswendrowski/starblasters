extends "res://scripts/enemy_core.gd"

# Strafer (on-lane migration 2026-06-08). Was bespoke capped-turn steering + hand-rolled nose-ray
# firing; now on the lane system. The StrafeRun movement pattern flies a capped-turn pass beside
# the player; auto_rotate keeps the nose on the flight heading; the host's "nose" weapon
# (Aim.FORWARD) fires along that nose, gated by fire_only_on_target so it only shoots when lined
# up on the player — reproducing the old nose-ray strafe. recycle_passes runs a few passes.
#
# The matrix assigns the "strafe_run" movement; the roster assigns the "nose" weapon.

func _ready() -> void:
	if max_health <= 1:
		max_health = 2
	if bounty_value <= 0:
		bounty_value = 8
	auto_rotate = true          # nose tracks heading; the nose weapon fires along it
	fire_only_on_target = true  # release only when the nose is on the player (the ray gate)
	fire_aim_tol_deg = 12.0
	fire_interval_min = 0.13    # rapid taps across the pass (was a 6-round burst)
	fire_interval_max = 0.16
	recycle_passes = 2          # up to ~3 strafing passes, then leave
	super._ready()
