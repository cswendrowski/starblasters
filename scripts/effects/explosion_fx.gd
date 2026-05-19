extends Node

# Static helper to play an explosion at a position. Spawns the explosion
# scene as a child of `get_tree().root` so it survives whatever node was
# blown up. Usage:
#   ExplosionFx.play(global_position, 1.0)
#   ExplosionFx.play(boss.global_position, 3.0, false)  # no extra light

const EXPLOSION_SCENE = preload("res://scenes/effects/explosion.tscn")

static func play(world_pos: Vector2, scale: float = 1.0, with_light: bool = true) -> Node2D:
	var inst: Node2D = EXPLOSION_SCENE.instantiate()
	inst.global_position = world_pos
	if "base_scale" in inst:
		inst.base_scale = scale
	if "emit_light" in inst:
		inst.emit_light = with_light
	Engine.get_main_loop().root.add_child(inst)
	return inst


# Spawn `count` explosions at `world_pos` with small spatial jitter and
# staggered timing so larger enemies read as "many simultaneous blasts"
# rather than one oversized one (Roman 2026-05-18). All blasts are at
# native 1× scale.
static func burst(world_pos: Vector2, count: int = 1, jitter_radius: float = 10.0, stagger: float = 0.06) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for i in count:
		var delay: float = float(i) * stagger
		if delay <= 0.001:
			_spawn_one(world_pos, jitter_radius)
		else:
			tree.create_timer(delay).timeout.connect(_spawn_one.bind(world_pos, jitter_radius))


static func _spawn_one(world_pos: Vector2, jitter_radius: float) -> void:
	var off := Vector2(randf_range(-jitter_radius, jitter_radius), randf_range(-jitter_radius, jitter_radius))
	play(world_pos + off, 1.0, true)
