extends RefCounted
class_name EnemyEngineFx

# Reusable engine flame for enemy ships. Attaches a small additive
# flame sprite at the rear of an Area2D enemy. Pulses + flickers in
# brightness so it reads as a live engine without per-frame logic on the
# enemy. Roman, 2026-05-16: "Look in the sprites for an engine flame or
# flare effect, and build a reusable enemy engine effect".
#
# Usage from any enemy:
#   const EngineFx = preload("res://scripts/effects/enemy_engine_fx.gd")
#   EngineFx.attach(self)
#
# Auto-rotation on EnemyBase puts the sprite's "down" along the velocity
# direction, so the flame at +Y in local space ends up trailing behind
# regardless of which way the enemy is traveling.

const FLAME_OFFSET := Vector2(0, 11)  # below the body in local space
const FLAME_SIZE := Vector2(0.55, 0.85)
const FLAME_TINT := Color(1.0, 0.65, 0.25, 0.95)

static var _flame_tex: Texture2D = null


static func attach(enemy: Node2D, tint: Color = FLAME_TINT, scale_mult: float = 1.0) -> Node2D:
	# Don't double-attach if the helper was already called.
	if enemy.has_node("EngineFlame"):
		return enemy.get_node("EngineFlame") as Node2D
	var holder := Node2D.new()
	holder.name = "EngineFlame"
	# Draw behind the body so it reads as "exhaust from behind" rather
	# than overlapping the silhouette.
	holder.z_index = -1
	holder.z_as_relative = true
	enemy.add_child(holder)
	var base_scale: Vector2 = FLAME_SIZE * scale_mult
	var spr := Sprite2D.new()
	spr.texture = _flame_texture()
	spr.position = FLAME_OFFSET
	spr.scale = base_scale
	spr.modulate = tint
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	holder.add_child(spr)
	# Brightness-flicker tint (slight desaturation pulse) keyed off the
	# caller-supplied tint so a yellow trail flickers yellow, not orange.
	var flicker_tint := Color(
		clamp(tint.r * 1.0, 0.0, 1.0),
		clamp(tint.g * 0.85, 0.0, 1.0),
		clamp(tint.b * 0.6, 0.0, 1.0),
		tint.a,
	)
	var tw: Tween = holder.create_tween().set_loops()
	tw.tween_property(spr, "scale", base_scale * Vector2(1.15, 1.25), 0.08).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(spr, "modulate", flicker_tint, 0.08)
	tw.tween_property(spr, "scale", base_scale, 0.10).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(spr, "modulate", tint, 0.10)
	return holder


# Soft teardrop flame texture — radial gradient pinched to a vertical
# ellipse via FILL_RADIAL with offset fill_to. White at the source, fades
# to clear at the edge; the host's modulate drives the hue.
static func _flame_texture() -> Texture2D:
	if _flame_tex != null:
		return _flame_tex
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 48
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.3)
	t.fill_to = Vector2(1.0, 0.7)
	_flame_tex = t
	return t
