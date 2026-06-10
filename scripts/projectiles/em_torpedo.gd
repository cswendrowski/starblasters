extends "res://scripts/projectiles/base_missile.gd"

# EM Torpedo projectile (Roman 2026-06-10) — a large dumb-fire rocket that flies forward and erupts
# into an electrical burst among the enemy formation. It does NOT detonate on contact (fly-through);
# it bursts when its nose reaches the top of the play area (so the discharge lands among the
# front-line enemies) OR at the fuse, whichever comes first. The burst (em_burst_fx) strips/ignores
# shields, chain-detonates enemy ordnance, and routes kills to the wreck-drift death.
#
# Built on base_missile (dumb_fire flight is free); only the detonation is bespoke. The fly-through +
# top-of-field burst is a deliberate tuning for the 270px playfield — a literal 2s forward flight
# would carry the rocket off the top before the fuse. detonate_y / fuse are both exported so the
# burst point is tunable; set detonate_y very negative to rely purely on the fuse.

const EmBurstFx = preload("res://scripts/effects/em_burst_fx.gd")

@export var burst_radius: float = 72.0
@export var burst_max_targets: int = 8
@export var burst_damage: int = 6        # fallback; `damage` (Mk-scaled, set by fire_secondary) wins if > 0
# Burst once the nose climbs to the top of the FIRE ZONE (Zones.ENTRY_END = 40) — i.e. it detonates
# among the front-line enemies if it didn't hit one on the way up. Tunable; set very negative to
# rely purely on contact + fuse.
@export var detonate_y: float = 40.0

# fire_secondary writes secondary_damage here (`if "damage" in b`). Mk-scaled via the Part's knobs;
# overrides burst_damage when positive so the torpedo scales with mark.
var damage: int = 0


func _process(delta: float) -> void:
	# Detonate at the top of the fire zone (among the front line) if it didn't already hit an enemy.
	# Only after ignition so it doesn't pop the instant it spawns.
	if not _dying and _ignited and global_position.y <= detonate_y:
		explode()
		return
	super._process(delta)


# Detonate on contact with an enemy (Roman 2026-06-10) OR at the top of the fire zone (the _process
# check above), whichever comes first. Enemy ordnance is in the "enemies" group too, which is fine —
# the burst chain-detonates it anyway.
func _on_area_entered(area: Area2D) -> void:
	if _dying or area == self:
		return
	if area.is_in_group("enemies"):
		explode()


# Ignore stray bullet hits — it's a heavy payload, not popped early into a normal missile poof.
func hit() -> void:
	pass


func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	# Let the smoke trail dissipate on its own rather than being yanked with the warhead.
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.call("attach_to", null)
		_smoke_trail = null
	var dmg: int = damage if damage > 0 else burst_damage
	EmBurstFx.detonate(get_tree(), global_position, burst_radius, dmg, burst_max_targets, _fx_parent())
	queue_free()
