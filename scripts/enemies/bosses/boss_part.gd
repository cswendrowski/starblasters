extends Area2D

# Reusable DESTRUCTIBLE BOSS PART (turret / pod / arm / weak-point), the
# standardized generalization of conductor_satellite.gd. Owns its own HP, takes
# hits from player fire, and on death plays an explosion, optionally leaves a
# burning trail at its mount, emits part_destroyed, and frees itself.
#
# Path-based (no class_name), mirroring boss_base — bosses reference it via
# preload. A part is a child of the boss (often parented to a Marker2D mount) so
# it rides the hull. It joins "enemies" so player bullets collide, but is flagged
# is_hazard so it does NOT gate wave-clear on its own (the boss is the combatant);
# the boss frees surviving parts on death via BossBase.free_parts().
#
# A part is purely the destructible shell + VFX. Any behaviour (a turret's barrel
# aim/fire) is layered on top by the boss / a coordinator — see boss_shepherd.gd.

signal part_destroyed(part)

var hp: int = 30
var max_hp: int = 30
var boss_ref: Node2D = null
var is_hazard: bool = true          # don't gate wave-clear (boss is the combatant)
# Leave a persistent burning/smoke trail at the mount on death. `trail_fall` adds
# downward drift so it reads as motion while the boss holds + jiggles (per spec).
var leave_trail: bool = true
var trail_fall: float = 40.0

var _destroyed: bool = false


func _ready() -> void:
	add_to_group("enemies")


# Configure on spawn. `host` is the boss (for find_player fallbacks + cleanup).
func setup(host: Node2D, part_hp: int) -> void:
	boss_ref = host
	hp = part_hp
	max_hp = part_hp


# Player-fire entry point (matches the EnemyBase contract bullets call).
func take_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	_flash()
	if hp <= 0:
		destroy()
		return true
	return false


# Blow the part: explosion at its position, optional burning trail at the mount,
# notify the boss, free. Idempotent.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	var tree := get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx != null:
		# "Small circle explode" (Shepherd brief). scene defaults to current_scene.
		ExplosionFx.play(global_position, 0.8, false, scene, ExplosionFx.scene_for("small_circle"))
	if leave_trail:
		_spawn_burn_trail()
	part_destroyed.emit(self)
	queue_free()


# White hit flash on the part's first child Sprite2D, if any.
func _flash() -> void:
	for c in get_children():
		if c is Sprite2D:
			var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
			HitFlashFx.flash(c, HitFlashFx.FLASH_WHITE)
			return


# Persistent burning trail at the mount (the parent Marker2D rides the boss, so
# the trail follows the hull). Downward gravity sells "the wrecked mount streams
# smoke as the ship drifts." Auto-frees after a few seconds.
func _spawn_burn_trail() -> void:
	var mount: Node = get_parent()
	if mount == null or not (mount is Node2D):
		return
	var p := CPUParticles2D.new()
	p.amount = 18
	p.lifetime = 0.8
	p.one_shot = false
	p.explosiveness = 0.0
	p.spread = 25.0
	p.direction = Vector2(0, 1)
	p.gravity = Vector2(0, trail_fall)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(1.0, 0.55, 0.2, 0.9)
	(mount as Node2D).add_child(p)
	# Fade the emission out and free so the wreck-smoke doesn't last forever.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.emitting = false
				var t2 := p.get_tree()
				if t2 != null:
					t2.create_timer(1.0).timeout.connect(func() -> void:
						if is_instance_valid(p):
							p.queue_free()))
