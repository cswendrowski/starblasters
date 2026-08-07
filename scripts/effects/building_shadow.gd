class_name BuildingShadow
extends RefCounted

# Reusable rig for the top-down oblique building shadow (Roman 2026-07-13, `graphics/building_shadow.gdshader`).
# Given a building LAYER (a Sprite2D — Base / Building overlay / turret), builds a ColorRect "carrier" behind
# it that ray-marches the layer's own ALPHA silhouette into an oblique drop shadow. Handles the fiddly bits so
# the Shader Lab tuner AND production share ONE correct path: derives the drawn frame's UV region from the
# sprite's hframes/frame, sizes the carrier carrier_scale× the frame, centres it on the layer, and applies the
# tuned params. Add the returned ColorRect UNDER the building root at a z below the layers so every layer's
# shadow lands on the ground beneath the whole building.
#
# Usage:
#   var shadow := BuildingShadow.attach(base_layer, {"shadow_strength": 0.7, "sun_dir": Vector2(0.4, 0.9)})
#   building_root.add_child(shadow)                 # z_index default -2 → under the layers
#   BuildingShadow.apply_params(shadow, base_layer, new_params)   # live re-tune (lab)

const SHADER = preload("res://graphics/building_shadow.gdshader")

# Shipped GLOBAL look — Roman's Shader Lab "Building Shadow" tune (2026-07-13). `height_scale` is the
# per-layer default; the real per-building/layer heights live in HEIGHTS below.
#
# `sun_dir` is NOT here: the direction comes from SceneLight (one source of truth for the whole
# scene, docs/scene_light_direction_2026-07-28.md) and a `const` can't hold a function call. It is
# injected in _merged() below, where explicit params still override it. Note the shader's `sun_dir`
# is the SHADOW direction despite its name — hence shadow_dir(), not light_dir().
const DEFAULTS := {
	"carrier_scale": 1.5,
	"height_scale": 1.0,
	"sun_elevation": 1.0,
	"step_px": 0.25,
	"steps": 50,
	"shadow_ray_offset_px": 0.0,
	"shadow_softness": 0.001,
	"shadow_aa_enabled": true,
	"shadow_aa_radius_px": 0.0,            # 0 ⇒ AA branch skipped
	"shadow_strength": 0.5,
	"shadow_tint": Color(0, 0, 0, 0.8),    # #000000cc
	"shadow_on_footprint": false,
	"z_index": -2,
}

# Per-building, per-layer silhouette HEIGHT (Roman's tune, 2026-07-13) — bigger ⇒ longer shadow. Keyed by
# the building's scene path → { layer_name: height_scale }. Layers absent here fall back to DEFAULTS.height_scale.
# Flat footprints ≈ 0.2 (a hugging ground shadow); raised overlays cast longer. Edit via the Shader Lab tuner.
const HEIGHTS := {
	"res://scenes/enemies/ground/b_b_glass.tscn": {"Base": 0.2},
	"res://scenes/enemies/ground/b_f_bunker.tscn": {"Base": 0.2},
	"res://scenes/enemies/ground/b_s_glass.tscn": {"Base": 0.2, "Building": 1.0},
	"res://scenes/enemies/ground/b_p_small.tscn": {"Base": 0.2},
	"res://scenes/enemies/ground/b_f_farm.tscn": {"Base": 0.2, "Building": 0.8},
	"res://scenes/enemies/ground/b_t_scatter.tscn": {"Base": 0.2, "Building": 0.2, "GlowMuzzle": 0.2},
	"res://scenes/enemies/ground/b_t_rocket.tscn": {"Base": 0.2, "Building": 1.0},
	"res://scenes/enemies/ground/b_t_ball.tscn": {"Base": 0.2, "Building": 0.75},
}


# DEFAULTS + the scene-wide light direction + the caller's overrides (caller wins — the Shader Lab
# passes its own `sun_dir` from the tuner slider).
static func _merged(params: Dictionary) -> Dictionary:
	var p: Dictionary = DEFAULTS.duplicate()
	p["sun_dir"] = SceneLight.shadow_dir()
	for k in params:
		p[k] = params[k]
	return p


# Build the shadow carrier for `layer`. Returns a ColorRect (NOT yet in the tree — caller adds it under the
# building root). Returns null if the layer has no texture.
static func attach(layer: Sprite2D, params: Dictionary = {}) -> ColorRect:
	if layer == null or layer.texture == null:
		return null
	var p: Dictionary = _merged(params)
	var rect := ColorRect.new()
	rect.name = "Shadow_" + layer.name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = ShaderMaterial.new()
	(rect.material as ShaderMaterial).shader = SHADER
	apply_params(rect, layer, p)
	return rect


# (Re)apply size + params to an existing shadow carrier — used for live tuning + carrier_scale changes (which
# resize/recentre the rect). `layer` is needed to re-derive the frame region + geometry.
static func apply_params(rect: ColorRect, layer: Sprite2D, params: Dictionary) -> void:
	if rect == null or layer == null or layer.texture == null:
		return
	var p: Dictionary = _merged(params)
	var mat := rect.material as ShaderMaterial
	if mat == null:
		return
	var full: Vector2 = layer.texture.get_size()
	var hf: int = max(layer.hframes, 1)
	var vf: int = max(layer.vframes, 1)
	var fw: float = full.x / float(hf)
	var fh: float = full.y / float(vf)
	var frame_px: float = maxf(fw, fh)
	var cs: float = float(p["carrier_scale"])
	var carrier_px: float = frame_px * cs
	# Drawn frame's UV sub-rect within the sheet.
	var col: int = layer.frame % hf
	var row: int = int(layer.frame / hf)
	var region := Vector4(
		(float(col) * fw) / full.x,
		(float(row) * fh) / full.y,
		fw / full.x,
		fh / full.y)
	# Geometry: a square carrier centred on the layer's origin (layers are `centered`), behind the building.
	rect.size = Vector2(carrier_px, carrier_px)
	rect.position = layer.position - Vector2(carrier_px, carrier_px) * 0.5
	rect.z_index = int(p["z_index"])
	rect.z_as_relative = true
	# Source + geometry uniforms.
	mat.set_shader_parameter("src_tex", layer.texture)
	mat.set_shader_parameter("frame_region", region)
	mat.set_shader_parameter("carrier_scale", cs)
	mat.set_shader_parameter("carrier_size_px", carrier_px)
	# Tunable look uniforms.
	mat.set_shader_parameter("height_scale", float(p["height_scale"]))
	mat.set_shader_parameter("sun_dir", p["sun_dir"])
	mat.set_shader_parameter("sun_elevation", float(p["sun_elevation"]))
	mat.set_shader_parameter("step_px", float(p["step_px"]))
	mat.set_shader_parameter("steps", int(p["steps"]))
	mat.set_shader_parameter("shadow_ray_offset_px", float(p["shadow_ray_offset_px"]))
	mat.set_shader_parameter("shadow_softness", float(p["shadow_softness"]))
	mat.set_shader_parameter("shadow_aa_enabled", bool(p["shadow_aa_enabled"]))
	mat.set_shader_parameter("shadow_aa_radius_px", float(p["shadow_aa_radius_px"]))
	mat.set_shader_parameter("shadow_strength", float(p["shadow_strength"]))
	mat.set_shader_parameter("shadow_tint", p["shadow_tint"])
	mat.set_shader_parameter("shadow_on_footprint", bool(p["shadow_on_footprint"]))


# PRODUCTION entry point — attach a shadow to every casting layer of a live building, using the tuned
# per-building HEIGHTS (falls back to DEFAULTS.height_scale for untabled layers). Adds each ColorRect UNDER
# `building_root` (z below the layers). Call from the building's `_ready()` (after super._ready). `scene_path`
# defaults to the root's scene_file_path. Returns the shadow ColorRects (all named "Shadow_<layer>").
static func attach_to_building(building_root: Node2D, scene_path: String = "") -> Array:
	if scene_path == "":
		scene_path = building_root.scene_file_path
	var heights: Dictionary = HEIGHTS.get(scene_path, {})
	var rects: Array = []
	for layer in casting_layers(building_root):
		var params: Dictionary = {}
		if heights.has(layer.name):
			params["height_scale"] = float(heights[layer.name])
		var rect := attach(layer, params)
		if rect != null:
			# Parent the shadow UNDER its layer (not the root) so it inherits the layer's VISIBILITY: when a
			# layer hides on death (explode() hides Building/GlowMuzzle), its shadow vanishes with it, while the
			# surviving Base husk keeps its shadow — no explode() bookkeeping needed. attach() positioned the
			# rect as a root-sibling (layer.position − carrier/2); reparented to the layer it's layer-local, so
			# drop layer.position. z stays relative (−2) → renders below every layer (base_z−2 / overlay_z−2).
			layer.add_child(rect)
			rect.position -= layer.position
			rects.append(rect)
	return rects


# The Sprite2D layers of a building that should CAST a shadow — its visible, non-"Destroyed" sprite layers.
# (Base footprint + any raised Building overlay; skips the hidden death frame + non-sprite children.)
static func casting_layers(building_root: Node) -> Array:
	var out: Array = []
	for c in building_root.get_children():
		if c is Sprite2D and c.visible and String(c.name) != "Destroyed":
			out.append(c)
	return out
