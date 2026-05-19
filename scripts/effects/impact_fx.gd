extends Node
class_name ImpactFx

# Bullet-hit visual pipeline (Roman, 2026-05-17 sprite pass).
#
# Two modes:
#   ImpactKind.SMOKE       — for small projectiles. Strip is 7×16 frames:
#                            frames 0-1 are bullet-color flash, frames 2-6
#                            transition to gray and fade.
#   ImpactKind.EXPLOSIVE   — for warhead projectiles (missiles, rockets,
#                            cannon rounds, bomblets). Strip is 5×16 frames
#                            of impact flash, layered over the existing
#                            fiery explosion scene.
#
# Static `spawn(parent, position, color, kind)` is the only entry point.

enum ImpactKind { SMOKE, EXPLOSIVE }

const SMOKE_STRIP := preload("res://graphics/effects/impact_smoke.png")
const FLASH_STRIP := preload("res://graphics/effects/impact_flash.png")
const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")

# Strip layouts — measured from the source PNGs.
const SMOKE_FRAMES: int = 7        # 112×16 → 7 frames @ 16 wide
const FLASH_FRAMES: int = 5        # 80×16  → 5 frames @ 16 wide
const FRAME_W: int = 16
const FRAME_H: int = 16

# How long each frame holds on screen.
const FRAME_TIME: float = 0.045

# Frames where the bullet-color flash applies (rest fade to gray).
const SMOKE_COLOR_FRAMES: int = 2
const FLASH_COLOR_FRAMES: int = 2


static func spawn(parent: Node, world_pos: Vector2, color: Color, kind: int = ImpactKind.SMOKE) -> void:
	if parent == null:
		return
	match kind:
		ImpactKind.EXPLOSIVE:
			_spawn_explosive(parent, world_pos, color)
		_:
			_spawn_smoke(parent, world_pos, color)


static func _spawn_smoke(parent: Node, world_pos: Vector2, color: Color) -> void:
	var s := _make_animated_sprite(SMOKE_STRIP, SMOKE_FRAMES)
	s.global_position = world_pos
	s.z_index = 5
	# Additive blend so the first frames read as a hot flash.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	parent.add_child(s)
	_animate_strip(s, color, SMOKE_FRAMES, SMOKE_COLOR_FRAMES)


static func _spawn_explosive(parent: Node, world_pos: Vector2, color: Color) -> void:
	# Impact flash strip plays the flash frames.
	var s := _make_animated_sprite(FLASH_STRIP, FLASH_FRAMES)
	s.global_position = world_pos
	s.z_index = 6
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	parent.add_child(s)
	_animate_strip(s, color, FLASH_FRAMES, FLASH_COLOR_FRAMES)
	# Layer the existing fiery explosion underneath.
	var exp = EXPLOSION_SCENE.instantiate()
	if exp is Node2D:
		exp.global_position = world_pos
	parent.add_child(exp)


# Build a Sprite2D with the strip's first frame visible. Subsequent frames
# are advanced by tweens in _animate_strip.
static func _make_animated_sprite(tex: Texture2D, frames: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = frames
	s.vframes = 1
	s.frame = 0
	return s


# Step through the frames at FRAME_TIME. First `color_frames` use the
# bullet's color via modulate; remaining frames desaturate to gray and
# fade out. Calls queue_free at the end.
static func _animate_strip(s: Sprite2D, color: Color, frames: int, color_frames: int) -> void:
	var tw := s.create_tween()
	for i in frames:
		# Set frame + modulate at the beginning of this beat.
		var f := i
		var is_color: bool = i < color_frames
		var mod: Color
		if is_color:
			mod = Color(color.r, color.g, color.b, 1.0)
		else:
			# Linearly fade toward transparent gray over the remaining frames.
			var t: float = float(i - color_frames + 1) / float(max(1, frames - color_frames))
			var gray: float = 0.6
			var a: float = 1.0 - t
			mod = Color(gray, gray, gray, max(0.0, a))
		tw.tween_callback(_apply_frame.bind(s, f, mod))
		tw.tween_interval(FRAME_TIME)
	tw.tween_callback(s.queue_free)


static func _apply_frame(s: Sprite2D, frame_idx: int, mod: Color) -> void:
	if not is_instance_valid(s):
		return
	s.frame = frame_idx
	s.modulate = mod
