extends Node

# Static helper to play an explosion at a position. Spawns the explosion
# scene as a child of `get_tree().root` so it survives whatever node was
# blown up. Usage:
#   ExplosionFx.play(global_position, 1.0)
#   ExplosionFx.play(boss.global_position, 3.0, false)  # no extra light

const EXPLOSION_SCENE = preload("res://scenes/effects/explosion.tscn")
const ExplosionSfx = preload("res://scripts/effects/explosion_sfx.gd")

# Named death-explosion variants. The enemy dev tool / enemy_base.explosion_variant
# select by name; scene_for() resolves it (unknown name -> default). Add new
# variant scenes here.
const VARIANTS := {
	"default": EXPLOSION_SCENE,
	"small_circle": preload("res://scenes/effects/explosion_small_circle.tscn"),
	"ball": preload("res://scenes/effects/explosion_small_circle.tscn"),  # zealot enemies
}

static func variant_names() -> Array:
	return VARIANTS.keys()

static func scene_for(variant: String) -> PackedScene:
	return VARIANTS.get(variant, EXPLOSION_SCENE)

# `parent` lets a caller spawn the blast into a specific container (e.g. the
# hangar's SubViewport world) instead of the window root — needed so effects
# land in the same coordinate space as the thing that blew up. Defaults to the
# window root (combat), preserving prior behavior.
static func play(world_pos: Vector2, scale: float = 1.0, with_light: bool = true, parent: Node = null, scene: PackedScene = null, with_sound: bool = true) -> Node2D:
	var src: PackedScene = scene if scene != null else EXPLOSION_SCENE
	var inst: Node2D = src.instantiate()
	inst.global_position = world_pos
	if "base_scale" in inst:
		inst.base_scale = scale
	if "emit_light" in inst:
		inst.emit_light = with_light
	# Fall back to the window root if no parent given OR it was freed (a staggered
	# burst can outlive a transient container like the hangar world).
	var p: Node = parent if (parent != null and is_instance_valid(parent)) else Engine.get_main_loop().root
	p.add_child(inst)
	# Distance-based explosion SFX (close/medium/distant). Silenced on burst sub-blasts so a
	# multi-blast death sounds once, not N times.
	if with_sound:
		ExplosionSfx.play(world_pos, scale, p)
	return inst


# Spawn `count` explosions at `world_pos` with small spatial jitter and
# staggered timing so larger enemies read as "many simultaneous blasts"
# rather than one oversized one (Roman 2026-05-18). All blasts are at
# native 1× scale.
static func burst(world_pos: Vector2, count: int = 1, jitter_radius: float = 10.0, stagger: float = 0.06, parent: Node = null, scene: PackedScene = null) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# One explosion SFX for the whole death, scaled up by blast count (bigger enemy = bigger boom).
	var snd_parent: Node = parent if (parent != null and is_instance_valid(parent)) else tree.root
	ExplosionSfx.play(world_pos, clampf(1.0 + float(count - 1) * 0.25, 1.0, 2.5), snd_parent)
	for i in count:
		var delay: float = float(i) * stagger
		if delay <= 0.001:
			_spawn_one(world_pos, jitter_radius, parent, scene)
		else:
			tree.create_timer(delay).timeout.connect(_spawn_one.bind(world_pos, jitter_radius, parent, scene))


static func _spawn_one(world_pos: Vector2, jitter_radius: float, parent: Node = null, scene: PackedScene = null) -> void:
	var off := Vector2(randf_range(-jitter_radius, jitter_radius), randf_range(-jitter_radius, jitter_radius))
	# with_sound=false — burst() already played one SFX for the whole death.
	play(world_pos + off, 1.0, true, parent, scene, false)
