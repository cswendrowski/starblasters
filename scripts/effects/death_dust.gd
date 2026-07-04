extends Node
class_name DeathDust

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

# Death dust supplement (Roman 2026-05-24).
#
# Spawned alongside the existing debris strip on enemy/boss death. The
# debris pieces are sprite shards; this layer is many tiny 1×1 gray
# particles with a short lifetime, scattering radially with a soft
# downward gravity so they read as settling dust.
#
# Usage:
#   DeathDust.play(global_position, scale_factor)    # auto count
#   DeathDust.play_with_count(world_pos, 32)         # explicit count
#
# Count is driven by enemy display_scale, mapped to the same size buckets
# the rest of the explosion system uses:
#   small (<=1.0)  → 8
#   medium (~1.5)  → 16
#   large (~2.5)   → 32
#   huge/giant (>=3.5) → 64
#
# Per CLAUDE.md the particles are LITERALLY 1px — Sprite2D with a 1×1
# ImageTexture, scale fixed at 1.0.

const LIFETIME_MIN: float = 0.4
const LIFETIME_MAX: float = 0.7
const SPEED_MIN: float = 30.0
const SPEED_MAX: float = 90.0
const GRAVITY: Vector2 = Vector2(0.0, 40.0)

# Cached 1×1 white texture. Tinted per-particle via modulate.
static var _dot_tex: Texture2D = null


static func _white_dot() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1, 1, 1, 1))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


# Map enemy display_scale → particle count using the standard size buckets.
static func count_for_scale(scale_factor: float) -> int:
	if scale_factor >= 3.5:
		return 64
	if scale_factor >= 2.5:
		return 32
	if scale_factor >= 1.5:
		return 16
	return 8


# `parent` lets a caller place the dust in a specific container (e.g. the hangar
# SubViewport world) so it shares the coordinate space of the thing that died;
# defaults to the current scene / window root (combat behavior).
static func play(world_pos: Vector2, scale_factor: float = 1.0, parent: Node = null) -> void:
	play_with_count(world_pos, count_for_scale(scale_factor), parent)


static func play_with_count(world_pos: Vector2, count: int, parent: Node = null) -> void:
	if count <= 0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if parent == null or not is_instance_valid(parent):
		# Prefer a SubViewport dev bench's registered gameplay layer over current_scene/root so
		# an unparented dust puff doesn't land in the window's top-left corner (no-op in production).
		parent = BulletWorld.spawn_root(tree, tree.current_scene if tree.current_scene != null else tree.root)
	var tex := _white_dot()
	for i in count:
		_spawn_one(parent, world_pos, tex)


static func _spawn_one(parent: Node, world_pos: Vector2, tex: Texture2D) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE  # 1px, fixed
	s.global_position = world_pos
	s.z_index = 5  # under debris (z=6), above most parallax
	s.z_as_relative = false
	# Per-particle gray tint, varied for texture.
	var g: float = randf_range(0.6, 0.8)
	s.modulate = Color(g, g, g, 1.0)
	parent.add_child(s)

	var life: float = randf_range(LIFETIME_MIN, LIFETIME_MAX)
	var angle: float = randf_range(0.0, TAU)
	var speed: float = randf_range(SPEED_MIN, SPEED_MAX)
	var v0: Vector2 = Vector2(cos(angle), sin(angle)) * speed
	# Closed-form integral of v0 + GRAVITY*t over [0, life]:
	#   pos(life) = world_pos + v0*life + 0.5*GRAVITY*life*life
	var end_pos: Vector2 = world_pos + v0 * life + 0.5 * GRAVITY * life * life

	var tw := s.create_tween()
	tw.set_parallel(true)
	# X eases out (radial burst plateaus).
	tw.tween_property(s, "global_position:x", end_pos.x, life)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Y eases in (gravity accelerates downward).
	tw.tween_property(s, "global_position:y", end_pos.y, life)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Fade out in the last 40% of life.
	tw.tween_property(s, "modulate:a", 0.0, life * 0.4).set_delay(life * 0.6)
	tw.set_parallel(false)
	tw.tween_callback(s.queue_free)
