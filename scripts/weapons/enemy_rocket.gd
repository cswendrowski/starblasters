extends "res://scripts/projectiles/base_missile.gd"
class_name EnemyRocket

# Enemy rocket — a DUMB-FIRE (no homing) configuration of the shared BaseMissile
# (Roman 2026-06-08 unify). All the engine-flare / smoke-trail / shoot-down /
# velocity-rotation / explosive-impact wiring now comes from BaseMissile; this is
# only the rocket-specific config. Fires straight immediately (no drop-and-coast),
# deals 2 on contact, can be shot down (1 HP).
#
# Per-rocket speed lives in the SCENE: a dumb rocket flies at a constant speed, so
# the scenes set drift_speed == homing_max_speed (180 standard / 60 large). Callers
# set `initial_dir` (the launch heading) BEFORE add_child, then call start(pos).


func _ready() -> void:
	target_group = "player"   # damages the player side on contact
	dumb_fire = true          # straight-line thrust along initial_dir, never homes
	flame_trail = true        # rear smoke trail (built by BaseMissile)
	drift_time = 0.0          # ignite on frame 0 — no backward drop
	damage_on_contact = 2
	is_hazard = true          # don't gate wave-clear (director skips hazards)
	has_ship_vfx = false      # a projectile, not a ship: no hull outline / damage overlay / shadow
	super._ready()
	bounty_value = 0          # shooting one down awards nothing (BaseMissile defaults to 5)
