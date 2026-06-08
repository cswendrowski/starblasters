extends Node

# Reusable SHADER-based additive glow (Roman, 2026-05-30). Replaces the two
# old glow paths — the scene "Glow" GradientTexture2D children and the radial
# glow_fx.attach_glow() halos on projectiles. ONE code path any bright thing
# (projectiles now; engines / explosions / muzzle flashes later) can opt into.
#
#   GlowShaderFx.apply(sprite)            → derive color, attach halo behind sprite
#   GlowShaderFx.apply(sprite, override)  → force a specific glow color
#
# HOW IT WORKS
#   A fragment shader on the sprite quad can only draw INSIDE the texture, so
#   a 2-3px OUTER halo needs a separate, slightly larger quad behind the host.
#   apply() spawns that quad: a Sprite2D (or AnimatedSprite2D, to track an
#   animated host) carrying the host's texture + the glow_halo.gdshader, at
#   z_index -1, scaled up by HALO_PX pixels PER AXIS (uniform scale under-glows
#   elongated bolts). The shader's linear sampler softens the upscaled
#   silhouette into a halo without any multi-tap blur loop.
#
# COLOR DERIVATION
#   The glow color is the brightest, most-saturated NON-WHITE pixel of the
#   host texture (see _derive_color). Computed ONCE per texture on the CPU and
#   cached; the ShaderMaterial is cached per glow color (the shader reads the
#   node's builtin TEXTURE, so texture isn't part of the material) so every
#   instance with the same color shares one material. Textures with no derivable
#   color (pure white / greyscale / unreadable image) get NO glow — acceptable
#   per the design.

const GLOW_SHADER: Shader = preload("res://scripts/effects/glow_halo.gdshader")

# --- Tuning knobs (designer-facing) -----------------------------------------
# Outer halo MARGIN in *texture* pixels, added on every edge. This is the
# transparent room the bloom fades into; it MUST exceed BLUR_PX so the haze
# reaches zero before the quad edge (otherwise it gets cut off as a hard rect).
const HALO_PX: float = 7.0
# Bloom reach in native texture pixels (how far the alpha is spread/blurred).
# Kept under HALO_PX so the soft tail fully fades inside the quad.
const BLUR_PX: float = 4.0
# Falloff exponent: >1 keeps a brighter core with a faster-fading tail (bloom).
const FALLOFF: float = 1.6
# Overall additive brightness of the halo. Subtle but present.
const INTENSITY: float = 0.55
# Saturation/value gates for "is this pixel a usable, non-white color".
const MIN_SAT: float = 0.18      # below this = too grey/white to tint with
const MAX_WHITE_VALUE: float = 0.92  # near-white high-value low-sat = skip
const MIN_ALPHA: float = 0.5     # ignore mostly-transparent pixels when scanning

# Cache: texture instance id → derived Color (or a sentinel for "no color").
static var _color_cache: Dictionary = {}
# Cache: "<texid>:<color hex>" → ShaderMaterial shared across instances.
static var _mat_cache: Dictionary = {}

const _NO_COLOR := Color(0, 0, 0, -1.0)  # sentinel: scanned, nothing usable


# Attach a shader glow behind `host`. `host` is a Sprite2D or
# AnimatedSprite2D. If `color_override.a > 0` that color is used directly;
# otherwise the color is auto-derived from the host's texture. Returns the
# glow node, or null if no glow could be made (no derivable color / no texture).
static func apply(host: CanvasItem, color_override: Color = Color(0, 0, 0, 0), intensity_mult: float = 1.0, halo_mult: float = 1.0) -> CanvasItem:
	if host == null:
		return null

	var tex: Texture2D = _host_texture(host)
	if tex == null:
		return null

	# --- color ---
	var color: Color
	if color_override.a > 0.0:
		color = color_override
	else:
		color = _derive_color(tex)
		if color.a < 0.0:
			# Sentinel: nothing usable in this texture → no glow.
			return null

	# --- size: per-axis scale so the halo is HALO_PX wide on BOTH axes ---
	# Use the DISPLAYED frame size, not the whole sheet: a Sprite2D with
	# hframes shows tex_w/hframes per frame, so scaling off the full sheet
	# width would under-glow the X axis.
	var tex_w: float = float(tex.get_width())
	var tex_h: float = float(tex.get_height())
	var s2d_for_size: Sprite2D = host as Sprite2D
	if s2d_for_size != null:
		if s2d_for_size.hframes > 1:
			tex_w = tex_w / float(s2d_for_size.hframes)
		if s2d_for_size.vframes > 1:
			tex_h = tex_h / float(s2d_for_size.vframes)
	if tex_w <= 0.0 or tex_h <= 0.0:
		return null
	var halo_px: float = HALO_PX * halo_mult
	var sx: float = (tex_w + 2.0 * halo_px) / tex_w
	var sy: float = (tex_h + 2.0 * halo_px) / tex_h

	# --- glow node ---
	# The glow node is ALWAYS a plain Sprite2D carrying a SINGLE-FRAME texture
	# (the host's currently-displayed frame, cropped to a standalone
	# ImageTexture). The shader insets UV around the FULL-texture center and
	# clamps its bloom taps to [0,1] of the WHOLE texture — so if we fed it a
	# multi-frame sheet (AtlasTexture sub-region or hframes Sprite2D) the bloom
	# would read ACROSS frame boundaries and ghost neighboring frames into the
	# halo. A one-frame texture makes UV genuinely span 0..1 of one frame, so the
	# existing shader math is correct with no shader change.
	#
	# TRADEOFF: the halo is STATIC (one frame's silhouette) and won't pulse with
	# the bullet's animation. For a soft additive bloom behind a 16px bullet this
	# is imperceptible and strictly better than ghosting.
	#
	# Note `tex` (the size/color source above) is intentionally LEFT UNTOUCHED:
	# the per-axis size block already divides the full sheet by hframes/vframes,
	# and _derive_color caches by the shared source-texture id. We only swap what
	# the glow NODE samples, via a separate single-frame `frame_tex`.
	var frame_tex: Texture2D = _single_frame_texture(host, tex)
	if frame_tex == null:
		return null
	var g := Sprite2D.new()
	g.texture = frame_tex
	g.scale = Vector2(sx, sy)
	var glow: CanvasItem = g

	glow.name = "ShaderGlow"
	glow.z_index = -1
	# Linear filter softens the upscaled silhouette into a halo (project
	# default is nearest). The shader samples the builtin TEXTURE so this
	# node-level filter applies to it.
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# quad_scale tells the shader how to map this enlarged quad's UV back onto
	# the native sprite rect (so the bloom fades into the transparent margin).
	# It varies per aspect ratio, so it MUST be part of the material cache key —
	# sharing one material across different-aspect bullets would mis-size the
	# bloom (a thin bolt's scale leaking onto a round orb, etc.).
	glow.material = _get_material(color, Vector2(sx, sy), intensity_mult)

	# Parent behind the host's own sprite. The host is the Sprite2D /
	# AnimatedSprite2D; add the glow as its sibling under the host's parent so
	# transforms (rotation from base_bullet.start) carry through, then push it
	# to draw first.
	var parent: Node = host.get_parent()
	if parent == null:
		# Host not yet in tree (rare) — child it directly so it still renders.
		host.add_child(glow)
		host.move_child(glow, 0)
		return glow
	parent.add_child(glow)
	parent.move_child(glow, host.get_index())
	# Match the host's local transform so the glow sits exactly behind it.
	var host2d: Node2D = host as Node2D
	if host2d != null and glow is Node2D:
		(glow as Node2D).position = host2d.position
		(glow as Node2D).rotation = host2d.rotation
	return glow


# Convenience: apply to whichever of a node's children is the visible sprite.
# Looks for a child Sprite2D/AnimatedSprite2D not named "ShaderGlow". Used by
# projectile scripts that pass `self` (the Area2D root).
static func apply_to_host(root: Node, color_override: Color = Color(0, 0, 0, 0)) -> CanvasItem:
	if root == null:
		return null
	var sprite: CanvasItem = _find_sprite(root)
	if sprite == null:
		return null
	return apply(sprite, color_override)


static func _find_sprite(root: Node) -> CanvasItem:
	for child in root.get_children():
		if child.name == "ShaderGlow":
			continue
		if child is AnimatedSprite2D and (child as AnimatedSprite2D).sprite_frames != null:
			return child as CanvasItem
		if child is Sprite2D and (child as Sprite2D).texture != null:
			return child as CanvasItem
	return null


static func _host_texture(host: CanvasItem) -> Texture2D:
	var asp: AnimatedSprite2D = host as AnimatedSprite2D
	if asp != null and asp.sprite_frames != null:
		var anim: String = asp.animation
		if asp.sprite_frames.get_frame_count(anim) > 0:
			return asp.sprite_frames.get_frame_texture(anim, 0)
		return null
	var s2d: Sprite2D = host as Sprite2D
	if s2d != null:
		return s2d.texture
	return null


# Shared material per (glow color, quad scale). The shader reads the builtin
# TEXTURE off the glow node, so the texture is NOT part of the material — but
# quad_scale (the per-axis upscale of this quad) IS a shader uniform and varies
# by sprite aspect ratio, so it belongs in the key: bullets that share both a
# color AND an aspect-derived scale share one material.
static func _get_material(color: Color, quad_scale: Vector2, intensity_mult: float = 1.0) -> ShaderMaterial:
	var key: String = "%s|%.3f|%.3f|%.2f" % [color.to_html(true), quad_scale.x, quad_scale.y, intensity_mult]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("glow_color", color)
	mat.set_shader_parameter("intensity", INTENSITY * intensity_mult)
	mat.set_shader_parameter("blur_px", BLUR_PX)
	mat.set_shader_parameter("falloff", FALLOFF)
	mat.set_shader_parameter("quad_scale", quad_scale)
	_mat_cache[key] = mat
	return mat


# Pick the brightest, most-saturated, non-white opaque pixel of the sprite —
# this IS the sprite's identity color. Returns a Color with a >= 0, or
# _NO_COLOR (a < 0) when nothing usable was found.
#
# A frequency-weighted dominant-hue variant was tried and reverted: the enemy
# sprites here are genuinely warm-amber art (an "orange diamond with a pink
# rim", etc.), so a hue histogram only added a body-vs-rim artifact without
# changing the faithful result. The simple max(value × saturation) reflects
# the sprite art directly, which is the spec.
static func _derive_color(tex: Texture2D) -> Color:
	var tid: int = tex.get_instance_id()
	if _color_cache.has(tid):
		return _color_cache[tid]

	var img: Image = _texture_image(tex)
	if img == null:
		_color_cache[tid] = _NO_COLOR
		return _NO_COLOR

	var w: int = img.get_width()
	var h: int = img.get_height()
	var best_score: float = -1.0
	var best: Color = _NO_COLOR
	# Step a few pixels on large sheets to stay cheap; bullet textures are tiny
	# so this is usually a full scan.
	var step: int = 1
	if w * h > 4096:
		step = 2
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < w:
			# image.get_pixel returns a typed Color — safe to read directly.
			var px: Color = img.get_pixel(x, y)
			if px.a >= MIN_ALPHA:
				var mx: float = maxf(px.r, maxf(px.g, px.b))
				var mn: float = minf(px.r, minf(px.g, px.b))
				var sat: float = 0.0
				if mx > 0.0:
					sat = (mx - mn) / mx
				var is_near_white: bool = sat < MIN_SAT and mx > MAX_WHITE_VALUE
				if sat >= MIN_SAT and not is_near_white:
					# Pick the BRIGHTEST non-white pixel (Roman 2026-05-30): value*saturation
						# grabbed the saturated rim/edge instead of the bright body.
						# sat>=MIN_SAT still skips greys; brightest colored pixel wins.
					var score: float = mx
					if score > best_score:
						best_score = score
						best = Color(px.r, px.g, px.b, 1.0)
			x += step
		y += step

	_color_cache[tid] = best
	return best


# Cache: "<source texture instance id>:<frame index>" → single-frame Texture2D.
# Bullet frames are tiny (16px), so cropping once per bullet-type-frame is cheap.
static var _frame_tex_cache: Dictionary = {}


# Return a standalone SINGLE-FRAME Texture2D for `host`'s currently-displayed
# frame, so the glow node samples one frame's UV span 0..1 (no cross-frame
# bleed). `sheet_tex` is the texture already resolved by _host_texture (reused
# for the single-frame Sprite2D / atlas-frame-0 cases). Returns null if no
# image can be read. CACHED by (source texture id + frame index).
static func _single_frame_texture(host: CanvasItem, sheet_tex: Texture2D) -> Texture2D:
	var asp: AnimatedSprite2D = host as AnimatedSprite2D
	if asp != null and asp.sprite_frames != null:
		# Animated host: crop the CURRENT frame's AtlasTexture region out of the
		# atlas image. apply() runs in _ready before the animation advances, so
		# frame is effectively 0 here — but reading asp.frame keeps it correct if
		# applied later. The cropped silhouette is static regardless (see note in
		# apply): the bloom does not pulse with the animation.
		var anim: String = asp.animation
		var frame_idx: int = asp.frame
		var fcount: int = asp.sprite_frames.get_frame_count(anim)
		if fcount <= 0:
			return null
		if frame_idx < 0 or frame_idx >= fcount:
			frame_idx = 0
		var ftex: Texture2D = asp.sprite_frames.get_frame_texture(anim, frame_idx)
		return _crop_atlas_frame(ftex)
	var s2d: Sprite2D = host as Sprite2D
	if s2d != null:
		if s2d.hframes > 1 or s2d.vframes > 1:
			return _crop_grid_frame(s2d)
		# Single-frame Sprite2D (possibly region-enabled): use as-is.
		return sheet_tex
	return sheet_tex


# Crop an AtlasTexture's region out of its atlas image into a standalone
# ImageTexture. If `tex` is not an atlas (single-frame), return it unchanged.
static func _crop_atlas_frame(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var atlas: AtlasTexture = tex as AtlasTexture
	if atlas == null or atlas.atlas == null:
		return tex
	var src_id: int = atlas.atlas.get_instance_id()
	var rr: Rect2 = atlas.region
	var key: String = "%d:r%d_%d_%d_%d" % [src_id, int(rr.position.x), int(rr.position.y), int(rr.size.x), int(rr.size.y)]
	if _frame_tex_cache.has(key):
		return _frame_tex_cache[key]
	var full: Image = atlas.atlas.get_image()
	if full == null:
		_frame_tex_cache[key] = null
		return null
	var region_i: Rect2i = Rect2i(int(rr.position.x), int(rr.position.y), int(rr.size.x), int(rr.size.y))
	# Clamp to the atlas bounds so get_region never reads out of range.
	region_i = region_i.intersection(Rect2i(0, 0, full.get_width(), full.get_height()))
	if region_i.size.x <= 0 or region_i.size.y <= 0:
		_frame_tex_cache[key] = null
		return null
	var sub: Image = full.get_region(region_i)
	var itex: ImageTexture = ImageTexture.create_from_image(sub)
	_frame_tex_cache[key] = itex
	return itex


# Crop the displayed cell of an hframes/vframes Sprite2D into a standalone
# ImageTexture. Returns null if the texture image can't be read.
static func _crop_grid_frame(s2d: Sprite2D) -> Texture2D:
	if s2d.texture == null:
		return null
	var src_id: int = s2d.texture.get_instance_id()
	var hf: int = maxi(s2d.hframes, 1)
	var vf: int = maxi(s2d.vframes, 1)
	var frame_idx: int = s2d.frame
	var key: String = "%d:g%d_%d_%d" % [src_id, hf, vf, frame_idx]
	if _frame_tex_cache.has(key):
		return _frame_tex_cache[key]
	var img: Image = _texture_image(s2d.texture)
	if img == null:
		_frame_tex_cache[key] = null
		return null
	var cell_w: int = img.get_width() / hf
	var cell_h: int = img.get_height() / vf
	if cell_w <= 0 or cell_h <= 0:
		_frame_tex_cache[key] = null
		return null
	var col: int = frame_idx % hf
	var row: int = frame_idx / hf
	var region_i: Rect2i = Rect2i(col * cell_w, row * cell_h, cell_w, cell_h)
	region_i = region_i.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if region_i.size.x <= 0 or region_i.size.y <= 0:
		_frame_tex_cache[key] = null
		return null
	var sub: Image = img.get_region(region_i)
	var itex: ImageTexture = ImageTexture.create_from_image(sub)
	_frame_tex_cache[key] = itex
	return itex


# Get a CPU-readable Image from any Texture2D flavor (AtlasTexture, plain
# Texture2D, etc.). Returns null if the image can't be read (compressed /
# non-CPU-readable).
static func _texture_image(tex: Texture2D) -> Image:
	var atlas: AtlasTexture = tex as AtlasTexture
	if atlas != null and atlas.atlas != null:
		# Scan the whole atlas sheet — fine for picking a representative color.
		var full: Image = atlas.atlas.get_image()
		return full
	return tex.get_image()
