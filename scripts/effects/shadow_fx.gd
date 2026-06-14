extends Node

# Oblique drop-shadow helper. Static helpers attach a child Sprite2D mirror of
# a host Sprite2D (or AnimatedSprite2D) with the oblique_shadow shader, sat
# behind the host (z_index = -1) and offset down-right to fake a high sun.
#
# Designed to be called from _ready() of any Area2D/Node2D actor — no .tscn
# edits required. Modeled on burn_fx.gd / trail_fx.gd for resource caching.

# Drop shadows disabled 2026-05-30 (Roman) — revisit in a dedicated shadow
# pass. Flip to true to re-enable everywhere it's attached.
const SHADOWS_ENABLED := false

const SHADOW_SHADER = preload("res://graphics/oblique_shadow.gdshader")

# Defaults tuned for our 16x16 pixel-art ships rendered at 3x world scale.
# offset is expressed in *world pixels* — the shader receives this divided by
# the host's accumulated scale so the shadow lands at a consistent screen
# offset regardless of how the host is scaled.
const DEFAULT_OFFSET_WORLD := Vector2(8, 8)
const DEFAULT_OPACITY := 0.4
const DEFAULT_SOFTNESS_PX := 1.5
const DEFAULT_ALPHA_CUTOFF := 0.25

# Attaches a shadow to `host_sprite` (a Sprite2D or AnimatedSprite2D). The
# shadow becomes a child of the host so it follows transform / frame changes.
# Optional overrides let the boss request a bigger, denser shadow.
static func attach_shadow(
		host_sprite: Node,
		offset_world: Vector2 = DEFAULT_OFFSET_WORLD,
		opacity: float = DEFAULT_OPACITY,
		softness_px: float = DEFAULT_SOFTNESS_PX
) -> Node:
	if not SHADOWS_ENABLED:
		return null
	if host_sprite == null or not is_instance_valid(host_sprite):
		return null
	if not (host_sprite is Sprite2D or host_sprite is AnimatedSprite2D):
		return null
	# Don't double-attach if a previous call already wired one up.
	if host_sprite.has_node("ObliqueShadow"):
		return host_sprite.get_node("ObliqueShadow")

	var tex: Texture2D = _resolve_texture(host_sprite)
	if tex == null:
		return null

	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("shadow_opacity", opacity)
	mat.set_shader_parameter("softness_px", softness_px)
	mat.set_shader_parameter("alpha_cutoff", DEFAULT_ALPHA_CUTOFF)
	# Convert the world-pixel offset into source-texture pixels. The host
	# sprite is rendered at host.global_scale, so 1 source-pixel covers
	# global_scale world-pixels. shadow_offset_px in the shader is in source
	# pixels, so divide world offset by accumulated scale.
	var s := _effective_scale(host_sprite)
	var shader_offset := Vector2(
		offset_world.x / max(s.x, 0.0001),
		offset_world.y / max(s.y, 0.0001)
	)
	mat.set_shader_parameter("shadow_offset_px", shader_offset)
	mat.set_shader_parameter("shadow_tint", Color(0, 0, 0, 1))

	var shadow := Sprite2D.new()
	shadow.name = "ObliqueShadow"
	shadow.texture = tex
	# If the host is animated (sheet) mirror hframes/vframes/frame so the
	# silhouette matches the current animation cell.
	if host_sprite is Sprite2D:
		var src := host_sprite as Sprite2D
		shadow.hframes = src.hframes
		shadow.vframes = src.vframes
		shadow.frame = src.frame
		shadow.centered = src.centered
		shadow.offset = src.offset
		# Keep frame in sync with host frame changes.
		var sync := func():
			if is_instance_valid(shadow) and is_instance_valid(src):
				shadow.frame = src.frame
		src.frame_changed.connect(sync)
	shadow.material = mat
	shadow.z_index = -1
	shadow.z_as_relative = true
	# Same local transform as host so the silhouette aligns; the shader does
	# the visual offset via UV. This keeps shadow scale identical to host.
	host_sprite.add_child(shadow)
	return shadow

# Resolve the current texture for either sprite type.
static func _resolve_texture(host_sprite: Node) -> Texture2D:
	if host_sprite is Sprite2D:
		return (host_sprite as Sprite2D).texture
	if host_sprite is AnimatedSprite2D:
		var anim := host_sprite as AnimatedSprite2D
		if anim.sprite_frames != null and anim.sprite_frames.has_animation(anim.animation):
			return anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)
	return null

# Walk up parents accumulating scale so the shader offset compensates for
# nested scaling (Player root is scaled 3x, then Ship sprite is unit-scaled).
static func _effective_scale(node: Node) -> Vector2:
	var s := Vector2.ONE
	var cur := node
	while cur != null and cur is Node2D:
		s *= (cur as Node2D).scale
		cur = cur.get_parent()
	return s
