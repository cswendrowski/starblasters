class_name FlyoverBackdrop
extends Control

# Planet Flyover backdrop — the UI-free world builder extracted from
# scripts/dev/planet_flyover_lab.gd (Roman 2026-07-18). Approximates flying straight down
# over a planet's surface: a flat, vertically-scrolling, seamlessly-looping ground texture
# (graphics/planet_ground.gdshader — the kit's tileable fbm with spherify() dropped + the
# noise scrolled along +Y), three atmosphere haze slices, and three gray/white cloud layers
# (graphics/nebula2.gdshader OR graphics/cloud_layer.gdshader) at Far/Mid/Near depths, each
# scrolling FASTER than the ground for parallax.
#
# Host-agnostic: the ground/atmo/cloud rects are built as this Control's own children (so they
# render into whatever canvas this node is parented to — a play SubViewport in the lab, a
# CanvasLayer in the loading screen, the combat world in production). It NEVER creates a
# SubViewport for the world itself; the only SubViewports it owns are the three shadow masks.
# Draw order is controlled by `base_z` + fixed interleave offsets so the host owns layering.
#
# Casters: ship/enemy silhouettes are drawn into a per-layer shadow-mask SubViewport (offset +
# scale baked into the mask sprites); the cloud shaders sample the mask and darken rgb only,
# density-gated. Register casters explicitly via register_caster(node, tex), or set
# track_combat_casters = true to auto-poll the "player"/"enemies" groups (mirrors
# scripts/parallax/asteroid_shadow_rig.gd).

const GROUND_SHADER := preload("res://graphics/planet_ground.gdshader")
const CLOUD_SHADER := preload("res://graphics/nebula2.gdshader")
const CLOUD_GEN_SHADER := preload("res://graphics/cloud_layer.gdshader")

const NATIVE := Vector2(480.0, 270.0)
const CLOUD_LAYERS := ["Far", "Mid", "Near"]
const LAYER_STYLE_NAMES := ["Nebula", "Clouds"]

# Ship drop shadows: deeper layers get a bigger offset, SMALLER shadow (half per layer — the
# depth read), slightly weaker. Verbatim from the lab (asteroid_shadow_rig ports these too).
const SHADOW_DIR := Vector2(0.35, 0.9)   # normalized in _update_masks; down + slightly right
const SHADOW_DIST := {"Far": 26.0, "Mid": 16.0, "Near": 8.0}
const SHADOW_SCALE := {"Far": 0.25, "Mid": 0.5, "Near": 1.0}
const SHADOW_MULT := {"Far": 0.8, "Mid": 0.9, "Near": 1.0}

# Planet-surface presets. Each maps to a `surface_type` (a distinct generator in
# planet_ground.gdshader) + an 8-colour palette (indices interpreted per generator) + a couple
# of per-type knobs. `atmo` = whether this world has an atmosphere (gates the tint overlay + is
# the natural home for cloud layers); `atmo_color` = the default haze tint.
#   type 0 TERRAN  biome ladder: [deep sea, sea, shallows, sand, grass, forest, mountain, snow]
#   type 1 DESERT  colours: [0..4] dark->light dunes, [5] canyon rock, [6] mesa, [7] caprock
#   type 2 ICE     colours: [0] crack, [1..3] ice dark->bright, [4] lake shelf, [5] lake deep
#   type 3 LAVA    colours: [0..2] rock dark->light, [3] lava edge, [4] lava mid, [5] lava core
#   type 4 MOON    colours: [0] shadow, [1] mid regolith, [2] maria/bowl, [3] sunlit
const PRESETS := {
	"Terran": {"type": 0, "river": 0.50, "emissive": 0.0, "atmo": true, "atmo_color": Color(0.45, 0.65, 0.95), "colors": [
		Color(0.05, 0.12, 0.30), Color(0.08, 0.22, 0.44), Color(0.16, 0.42, 0.58),
		Color(0.80, 0.72, 0.46), Color(0.32, 0.53, 0.26), Color(0.17, 0.38, 0.20),
		Color(0.48, 0.44, 0.42), Color(0.93, 0.95, 0.96)]},
	"Desert": {"type": 1, "river": 0.50, "emissive": 0.0, "atmo": true, "atmo_color": Color(0.86, 0.60, 0.34), "colors": [
		Color(0.30, 0.16, 0.12), Color(0.52, 0.30, 0.16), Color(0.72, 0.48, 0.24),
		Color(0.88, 0.68, 0.38), Color(0.98, 0.86, 0.62), Color(0.22, 0.12, 0.10),
		Color(0.55, 0.33, 0.22), Color(0.84, 0.66, 0.46)]},
	# Lake tones from the kit's IceWorld; land bands regrayed (Roman: the blue speckle
	# read as noise — gray/white ice sells the surface better).
	"Ice": {"type": 2, "river": 0.50, "emissive": 0.0, "atmo": true, "atmo_color": Color(0.75, 0.85, 0.95), "colors": [
		Color(0.36, 0.50, 0.66), Color(0.68, 0.72, 0.78), Color(0.85, 0.87, 0.90),
		Color(0.97, 0.98, 1.00), Color(0.31, 0.64, 0.72), Color(0.23, 0.25, 0.37),
		Color(0.97, 0.98, 1.00), Color(0.97, 0.98, 1.00)]},
	# Rock + lava tones are the kit's exact LavaWorld palette.
	"Lava": {"type": 3, "river": 0.46, "emissive": 2.4, "atmo": true, "atmo_color": Color(0.50, 0.28, 0.22), "colors": [
		Color(0.24, 0.16, 0.21), Color(0.32, 0.20, 0.25), Color(0.56, 0.30, 0.34),
		Color(0.68, 0.18, 0.27), Color(0.90, 0.27, 0.22), Color(1.00, 0.54, 0.20),
		Color(1.00, 0.54, 0.20), Color(1.00, 0.54, 0.20)]},
	# Straight asteroid-shader port: kit 3-tone roles — [0] dark, [1] mid, [2] light.
	# Relief slider = the kit's sun-offset; Water slider = crater size/coverage.
	"Moon": {"type": 4, "river": 0.50, "emissive": 0.0, "atmo": false, "atmo_color": Color.WHITE, "colors": [
		Color(0.30, 0.30, 0.34), Color(0.51, 0.50, 0.49), Color(0.72, 0.71, 0.67),
		Color(0.72, 0.71, 0.67), Color(0.72, 0.71, 0.67), Color(0.72, 0.71, 0.67),
		Color(0.72, 0.71, 0.67), Color(0.72, 0.71, 0.67)]},
	# Alt-desert (Roman): the LAVA generator re-skinned — its basin-pooling "molten rivers"
	# become bright sand corridors flowing between dark rock tiers, the bank glow becomes a
	# sandy transition rim, ember veins become wadi streaks. emissive 0 = no glow.
	"Desert 2": {"type": 3, "river": 0.50, "emissive": 0.0, "atmo": true, "atmo_color": Color(0.86, 0.60, 0.34), "colors": [
		Color(0.22, 0.12, 0.10), Color(0.38, 0.22, 0.15), Color(0.55, 0.33, 0.22),
		Color(0.78, 0.52, 0.26), Color(0.90, 0.64, 0.32), Color(0.98, 0.82, 0.55),
		Color(0.98, 0.82, 0.55), Color(0.98, 0.82, 0.55)]},
	# Kit asteroid EXACTLY (single crater lattice, no big-crater addition) — Roman wants
	# to see how the raw asteroid generation reads as a moon surface.
	"Moonsteroid": {"type": 5, "river": 0.50, "emissive": 0.0, "atmo": false, "atmo_color": Color.WHITE, "colors": [
		Color(0.30, 0.30, 0.34), Color(0.51, 0.50, 0.49), Color(0.72, 0.71, 0.67),
		Color(0.72, 0.71, 0.67), Color(0.72, 0.71, 0.67), Color(0.72, 0.71, 0.67),
		Color(0.72, 0.71, 0.67), Color(0.72, 0.71, 0.67)]},
}
const PRESET_NAMES := ["Terran", "Desert", "Ice", "Lava", "Moon", "Desert 2", "Moonsteroid"]

# Per-cloud-layer base config. `parallax` is relative to the ground (1.0 = ground speed);
# ALL clouds are > 1.0 because they float ABOVE the surface — higher (Near) = faster.
# `fs` = feature_scale for the generated-cloud style (Far = smaller distant puffs).
const CLOUD_CFG := {
	"Far":  {"scale": 3.4, "octaves": 6, "density": 0.85, "edge": 0.45, "warp": 1.0, "max_alpha": 0.34, "parallax": 1.15, "fs": 7.0},
	"Mid":  {"scale": 2.5, "octaves": 6, "density": 0.95, "edge": 0.40, "warp": 1.3, "max_alpha": 0.44, "parallax": 1.55, "fs": 5.0},
	"Near": {"scale": 1.7, "octaves": 5, "density": 1.05, "edge": 0.34, "warp": 1.6, "max_alpha": 0.60, "parallax": 2.30, "fs": 3.5},
}

# Fixed interleave offsets from base_z: ground < atmo0 < Far < atmo1 < Mid < atmo2 < Near.
# The host picks base_z to slot the whole stack into its canvas ordering.
const Z_GROUND := 0
const Z_ATMO := [4, 12, 20]                     # atmo slice 0/1/2
const Z_CLOUD := {"Far": 8, "Mid": 16, "Near": 24}
const ATMO_SLICE_W := [0.45, 0.33, 0.22]        # opacity share per slice (ground gets all three)

# How often the auto-tracker rescans the caster groups (seconds).
const CASTER_POLL_INTERVAL := 0.5

@export var base_z: int = 0
@export var track_combat_casters: bool = false
# Caster global_position → mask-viewport (480×270) coords. 1.0 when casters share the native
# 480 canvas (lab, combat); 0.25 when the host's world is HD ×4 (loading screen).
@export var caster_coord_scale: float = 1.0

# ---- Settings state (mirrors the FlyoverBackdrop settings dict) -----------
var _flight: float = 0.35
var _feature_scale: float = 8.0
var _loop_size: int = 32
var _octaves: int = 5
var _relief: float = 0.35
var _pixels: float = 160.0
var _river_cutoff: float = 0.5
var _surface_type: int = 0
var _colors: Array = []          # 8 palette colours (post hue-roll)
var _emissive: float = 0.0
var _seed: float = 1.0           # ground-shader noise seed
var _atmo_on: bool = true
var _atmo_color: Color = Color(0.45, 0.65, 0.95)
var _atmo_opacity: float = 0.18
var _cloud_opacity: float = 0.6
var _cloud_coverage: float = 0.55
var _cloud_on := {"Far": true, "Mid": true, "Near": true}
var _layer_style := {"Far": 0, "Mid": 0, "Near": 0}
var _layer_opacity := {"Far": 1.0, "Mid": 1.0, "Near": 1.0}
var _layer_color := {"Far": Color(0.75, 0.78, 0.83), "Mid": Color(0.82, 0.84, 0.88), "Near": Color(0.90, 0.91, 0.94)}
var _ship_shadow: float = 0.35

# Night: a CanvasModulate owned by this node darkens the whole canvas it lives in (HUD/Glass
# are separate CanvasLayers and stay lit in combat).
var _night_on: bool = false
var _night_darkness: float = 0.45
var _night_color: Color = Color(0.25, 0.31, 0.53)
var _canvas_mod: CanvasModulate = null

# ---- Runtime nodes --------------------------------------------------------
var _ground: ColorRect = null
var _atmo_rects: Array = []      # the three depth slices
var _clouds := {}                # layer -> ColorRect
var _mask_vps := {}              # layer -> SubViewport (shadow silhouettes)
var _casters := {}               # instance_id -> {node, tex, masks: {layer: Sprite2D}}
var _ground_scroll: float = 0.0  # accumulator, cells
var _cloud_off := {"Far": 0.0, "Mid": 0.0, "Near": 0.0}       # nebula style, screens
var _cloud_scroll := {"Far": 0.0, "Mid": 0.0, "Near": 0.0}    # clouds style, noise cells
var _poll_accum: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _colors.is_empty():
		_colors = (PRESETS[PRESET_NAMES[0]]["colors"] as Array).duplicate()
	_build()
	_apply_all()
	_apply_night()


func _process(delta: float) -> void:
	_scroll(delta)
	if track_combat_casters:
		_poll_accum += delta
		if _poll_accum >= CASTER_POLL_INTERVAL:
			_poll_accum = 0.0
			for c in get_tree().get_nodes_in_group("player"):
				_auto_register(c)
			for c in get_tree().get_nodes_in_group("enemies"):
				_auto_register(c)
	_update_masks()


# ---- Public API -----------------------------------------------------------

# Apply a full settings dict (planner output / lab knobs). Fields fall back to the current
# value so partial dicts are safe. Rebuilds materials + night when the node is ready.
func apply_settings(d: Dictionary) -> void:
	_flight = float(d.get("flight", _flight))
	_feature_scale = float(d.get("feature_scale", _feature_scale))
	_loop_size = int(d.get("loop_size", _loop_size))
	_octaves = int(d.get("octaves", _octaves))
	_relief = float(d.get("relief", _relief))
	_pixels = float(d.get("pixels", _pixels))
	_river_cutoff = float(d.get("river_cutoff", _river_cutoff))
	_surface_type = int(d.get("surface_type", _surface_type))
	_emissive = float(d.get("emissive", _emissive))
	_seed = float(d.get("seed", _seed))
	if d.has("colors") and d["colors"] is Array and (d["colors"] as Array).size() >= 1:
		_colors = (d["colors"] as Array).duplicate()
	_atmo_on = bool(d.get("atmo", _atmo_on))
	_atmo_color = d.get("atmo_color", _atmo_color)
	_atmo_opacity = float(d.get("atmo_opacity", _atmo_opacity))
	_cloud_opacity = float(d.get("cloud_opacity", _cloud_opacity))
	_cloud_coverage = float(d.get("cloud_coverage", _cloud_coverage))
	_ship_shadow = float(d.get("ship_shadow", _ship_shadow))
	for layer in CLOUD_LAYERS:
		if d.has("cloud_on") and d["cloud_on"].has(layer):
			_cloud_on[layer] = bool(d["cloud_on"][layer])
		if d.has("layer_style") and d["layer_style"].has(layer):
			_layer_style[layer] = int(d["layer_style"][layer])
		if d.has("layer_opacity") and d["layer_opacity"].has(layer):
			_layer_opacity[layer] = float(d["layer_opacity"][layer])
		if d.has("layer_color") and d["layer_color"].has(layer):
			_layer_color[layer] = d["layer_color"][layer]
	if d.has("night") or d.has("night_darkness") or d.has("night_color"):
		_night_on = bool(d.get("night", _night_on))
		_night_darkness = float(d.get("night_darkness", _night_darkness))
		_night_color = d.get("night_color", _night_color)
	if is_node_ready():
		_apply_all()
		_apply_night()


# Register a shadow caster: one silhouette sprite per cloud layer, living in that layer's mask
# viewport, pre-scaled to the layer's shadow size. The mask follows the node's global transform
# each frame. Idempotent per node instance.
func register_caster(node: Node2D, tex: Texture2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _casters.has(id):
		return
	var masks := {}
	for layer in CLOUD_LAYERS:
		var ms := Sprite2D.new()
		ms.texture = tex
		ms.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ms.rotation = node.global_rotation
		ms.scale = Vector2.ONE * float(SHADOW_SCALE[layer])
		_mask_vps[layer].add_child(ms)
		masks[layer] = ms
	_casters[id] = {"node": node, "tex": tex, "masks": masks}


func unregister_caster(node: Node2D) -> void:
	if node == null:
		return
	var id := node.get_instance_id()
	if not _casters.has(id):
		return
	var rec: Dictionary = _casters[id]
	for layer in rec["masks"]:
		var ms: Sprite2D = rec["masks"][layer]
		if is_instance_valid(ms):
			ms.queue_free()
	_casters.erase(id)


# Toggle the night CanvasModulate. Effect = Color.WHITE.lerp(color, darkness) over the whole
# canvas this node lives in.
func set_night(on: bool, darkness: float, color: Color) -> void:
	_night_on = on
	_night_darkness = darkness
	_night_color = color
	_apply_night()


# Deterministic hue-roll of one palette colour — shared by the lab's Randomize Look and the
# planner's per-planet colour identity. Low-saturation entries (snow, gray rock) barely move
# under hue rotation, which is exactly right. `dh` = shared hue turn; `rng` supplies per-slot
# sat/val jitter (pass the SAME dh for every slot in a palette to keep the ramp coherent).
static func shift_color(c: Color, dh: float, rng: RandomNumberGenerator) -> Color:
	return Color.from_hsv(
		fposmod(c.h + dh, 1.0),
		clampf(c.s + rng.randf_range(-0.08, 0.08), 0.0, 1.0),
		clampf(c.v + rng.randf_range(-0.06, 0.06), 0.0, 1.0),
		c.a)


# ---- Build ----------------------------------------------------------------

func _build() -> void:
	# Ground fills the whole native area, behind everything.
	_ground = ColorRect.new()
	_ground.name = "Ground"
	_ground.size = NATIVE
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.z_index = base_z + Z_GROUND
	var gmat := ShaderMaterial.new()
	gmat.shader = GROUND_SHADER
	_ground.material = gmat
	add_child(_ground)
	# Atmosphere haze: three slices interleaved with the cloud layers, gated by `atmo`.
	_atmo_rects.clear()
	for i in Z_ATMO.size():
		var slice := ColorRect.new()
		slice.name = "Atmosphere%d" % i
		slice.size = NATIVE
		slice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slice.z_index = base_z + int(Z_ATMO[i])
		add_child(slice)
		_atmo_rects.append(slice)
	# Cloud layers, back (Far) to front (Near). Materials are assigned in _apply_clouds — the
	# shader depends on the layer's chosen style.
	for layer in CLOUD_LAYERS:
		var rect := ColorRect.new()
		rect.name = "Cloud_" + layer
		rect.size = NATIVE
		rect.color = Color(0, 0, 0, 0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.z_index = base_z + int(Z_CLOUD[layer])
		add_child(rect)
		_clouds[layer] = rect
	# Per-layer shadow-mask viewports: casters' silhouettes drawn at that layer's offset + scale;
	# the cloud shaders sample the mask. These are the ONLY SubViewports the component owns.
	for layer in CLOUD_LAYERS:
		var vp := SubViewport.new()
		vp.size = Vector2i(480, 270)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.gui_disable_input = true
		vp.handle_input_locally = false
		add_child(vp)
		_mask_vps[layer] = vp


# ---- Apply ----------------------------------------------------------------

func _apply_all() -> void:
	_apply_ground()
	_apply_atmo()
	_apply_clouds()


func _apply_ground() -> void:
	if _ground == null or not is_instance_valid(_ground):
		return
	var mat: ShaderMaterial = _ground.material
	mat.set_shader_parameter("rect_size", NATIVE)
	mat.set_shader_parameter("pixels", _pixels)
	mat.set_shader_parameter("feature_scale", _feature_scale)
	mat.set_shader_parameter("size", float(_loop_size))
	mat.set_shader_parameter("OCTAVES", _octaves)
	mat.set_shader_parameter("relief", _relief)
	mat.set_shader_parameter("seed", _seed)
	mat.set_shader_parameter("sun_dir", Vector2(0.40, 0.35))
	mat.set_shader_parameter("surface_type", _surface_type)
	mat.set_shader_parameter("river_cutoff", _river_cutoff)
	mat.set_shader_parameter("emissive", _emissive)
	mat.set_shader_parameter("should_dither", true)
	mat.set_shader_parameter("colors", PackedColorArray(_colors))


func _apply_atmo() -> void:
	for i in _atmo_rects.size():
		var slice = _atmo_rects[i]
		if slice == null or not is_instance_valid(slice):
			continue
		slice.visible = _atmo_on
		slice.color = Color(_atmo_color.r, _atmo_color.g, _atmo_color.b, _atmo_opacity * float(ATMO_SLICE_W[i]))


func _apply_clouds() -> void:
	for layer in CLOUD_LAYERS:
		var rect = _clouds.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		rect.visible = bool(_cloud_on[layer])
		var cfg: Dictionary = CLOUD_CFG[layer]
		var style: int = int(_layer_style[layer])
		var want_shader: Shader = CLOUD_GEN_SHADER if style == 1 else CLOUD_SHADER
		var mat: ShaderMaterial = rect.material
		if mat == null or mat.shader != want_shader:
			mat = ShaderMaterial.new()
			mat.shader = want_shader
			rect.material = mat
		var lcol: Color = _layer_color[layer]
		var lop: float = _cloud_opacity * float(_layer_opacity[layer])
		# Ship drop shadows: the layer's mask viewport holds every caster's silhouette.
		mat.set_shader_parameter("shadow_mask", (_mask_vps[layer] as SubViewport).get_texture())
		mat.set_shader_parameter("shadow_strength", _ship_shadow * float(SHADOW_MULT[layer]))
		if style == 1:
			# Generated clouds (cloud_layer.gdshader — the repurposed land-mass field).
			mat.set_shader_parameter("rect_size", NATIVE)
			mat.set_shader_parameter("pixels", _pixels)
			mat.set_shader_parameter("feature_scale", float(cfg["fs"]))
			mat.set_shader_parameter("size", float(_loop_size))
			mat.set_shader_parameter("OCTAVES", _octaves)
			mat.set_shader_parameter("seed", 1.0 + float(abs(hash(layer)) % 700) / 100.0)
			mat.set_shader_parameter("wind_dir", Vector2(0.35, 0.35))
			mat.set_shader_parameter("cloud_color", lcol)
			mat.set_shader_parameter("coverage", _cloud_coverage)
			mat.set_shader_parameter("opacity", lop)
		else:
			# Nebula style (nebula2.gdshader).
			mat.set_shader_parameter("rect_size", NATIVE)
			mat.set_shader_parameter("pixels", _pixels)
			mat.set_shader_parameter("scale", cfg["scale"])
			mat.set_shader_parameter("octaves", int(cfg["octaves"]))
			mat.set_shader_parameter("density", cfg["density"])
			mat.set_shader_parameter("edge_sharpness", cfg["edge"])
			mat.set_shader_parameter("warp_strength", cfg["warp"])
			mat.set_shader_parameter("warp_scale", 1.2)
			mat.set_shader_parameter("swirl_speed", 0.05)
			mat.set_shader_parameter("wisp_strength", 0.25)
			mat.set_shader_parameter("drift_speed", 0.0)   # motion comes from scroll_offset
			mat.set_shader_parameter("max_alpha", float(cfg["max_alpha"]))
			mat.set_shader_parameter("opacity", lop)
			mat.set_shader_parameter("uv_correct", Vector2(1, 1))
			mat.set_shader_parameter("seed", 1.0 + float(abs(hash(layer)) % 700) / 100.0)
			mat.set_shader_parameter("colorscheme", _cloud_gradient(lcol))


# Cloud palette ramp tinted toward the layer colour: dark edges -> bright cores.
func _cloud_gradient(c: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(c.r * 0.55, c.g * 0.57, c.b * 0.60, 1.0),
		Color(c.r * 0.78, c.g * 0.80, c.b * 0.83, 1.0),
		Color(minf(c.r * 1.0, 1.0), minf(c.g * 1.01, 1.0), minf(c.b * 1.02, 1.0), 1.0),
		Color(minf(c.r * 1.12, 1.0), minf(c.g * 1.12, 1.0), minf(c.b * 1.12, 1.0), 1.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 4
	return t


func _apply_night() -> void:
	if _night_on:
		if _canvas_mod == null or not is_instance_valid(_canvas_mod):
			_canvas_mod = CanvasModulate.new()
			_canvas_mod.name = "FlyoverNight"
			add_child(_canvas_mod)
		_canvas_mod.color = Color.WHITE.lerp(_night_color, _night_darkness)
		_canvas_mod.visible = true
	elif _canvas_mod != null and is_instance_valid(_canvas_mod):
		_canvas_mod.visible = false


# ---- Scroll + shadows -----------------------------------------------------

func _scroll(delta: float) -> void:
	# Ground: one screen-height = `_feature_scale` cells, so flight (screens/sec) advances
	# flight × feature_scale cells/sec. Wrap at 8× the tiling period — a whole period for every
	# layer whose Y coeff is a multiple of 0.125 (the moon's supermassive lattice).
	if _ground != null and is_instance_valid(_ground):
		_ground_scroll += _flight * _feature_scale * delta
		var mat: ShaderMaterial = _ground.material
		if mat != null:
			mat.set_shader_parameter("scroll", fposmod(_ground_scroll, 8.0 * float(_loop_size)))
	# Cloud layers: each rides its own parallax > ground. Nebula2 takes a UV scroll_offset
	# (procedural, no seam); generated clouds take a noise-cell `scroll` wrapped at 2× the period.
	for layer in CLOUD_LAYERS:
		var rect = _clouds.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		var m: ShaderMaterial = rect.material
		if m == null:
			continue
		var par: float = float(CLOUD_CFG[layer]["parallax"])
		if int(_layer_style[layer]) == 1:
			_cloud_scroll[layer] = fposmod(_cloud_scroll[layer] + _flight * par * float(CLOUD_CFG[layer]["fs"]) * delta, 2.0 * float(_loop_size))
			m.set_shader_parameter("scroll", _cloud_scroll[layer])
		else:
			_cloud_off[layer] += _flight * par * delta
			m.set_shader_parameter("scroll_offset", Vector2(0.0, fposmod(_cloud_off[layer], 1024.0)))


func _update_masks() -> void:
	var dir := SHADOW_DIR.normalized()
	for id in _casters.keys():
		var rec: Dictionary = _casters[id]
		# Untyped on purpose: a caster may have been freed since last frame (enemies die + free
		# constantly in combat). Assigning a freed instance to a TYPED var throws; holding it
		# untyped lets the is_instance_valid guard below clean it up quietly.
		var node = rec["node"]
		if not is_instance_valid(node):
			for layer in rec["masks"]:
				var dead: Sprite2D = rec["masks"][layer]
				if is_instance_valid(dead):
					dead.queue_free()
			_casters.erase(id)
			continue
		var pos: Vector2 = node.global_position * caster_coord_scale
		var rot: float = node.global_rotation
		var vis: bool = node.is_visible_in_tree()
		for layer in CLOUD_LAYERS:
			var ms: Sprite2D = rec["masks"][layer]
			if ms == null or not is_instance_valid(ms):
				continue
			ms.visible = vis
			ms.position = pos + dir * float(SHADOW_DIST[layer])
			ms.rotation = rot


# Auto-track: register a group member using its visible sprite's texture (mirrors
# asteroid_shadow_rig). The mask follows the registered node's transform each frame.
func _auto_register(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not (node is Node2D):
		return
	if _casters.has(node.get_instance_id()):
		return
	var src := _find_source_sprite(node)
	if src == null:
		return
	register_caster(node as Node2D, src.texture)


# The caster's body sprite: the node itself (demo sprites), else the conventional layer names —
# enemies carry "Sprite2D", the player carries "Ship" (enemy-marker-layer naming). Fallback:
# first Sprite2D child.
func _find_source_sprite(caster: Node) -> Sprite2D:
	if caster is Sprite2D:
		return caster as Sprite2D
	var s: Node = caster.get_node_or_null("Sprite2D")
	if s is Sprite2D:
		return s as Sprite2D
	s = caster.get_node_or_null("Ship")
	if s is Sprite2D:
		return s as Sprite2D
	for child in caster.get_children():
		if child is Sprite2D:
			return child as Sprite2D
	return null
