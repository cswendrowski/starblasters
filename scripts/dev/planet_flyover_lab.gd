extends Control

# Planet Flyover Lab (Roman 2026-07-11) — approximates flying straight down over the
# surface of a planet. The BACKGROUND is a flat, vertically-scrolling, seamlessly-looping
# ground texture built from the PixelPlanets land-mass noise (graphics/planet_ground.gdshader
# — the kit's tileable fbm with spherify() dropped + the noise scrolled along +Y). Over it,
# three gray/white nebula layers (graphics/nebula2.gdshader) sit at Far/Mid/Near depths as
# drifting clouds, each scrolling FASTER than the ground (they're above it) for parallax.
#
# Everything renders into a native 480×270 SubViewport (4× nearest upscale) so it matches
# combat's pixel-art look exactly. Knobs persist to user://tuners/planet_flyover.json;
# Copy GDScript emits a paste-ready block (tuner contract).

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const HdScreen = preload("res://scripts/ui/hd_screen.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const GROUND_SHADER := preload("res://graphics/planet_ground.gdshader")
const CLOUD_SHADER := preload("res://graphics/nebula2.gdshader")
const CLOUD_GEN_SHADER := preload("res://graphics/cloud_layer.gdshader")
const SHIP_TEX := preload("res://graphics/player/player_ship_a_body.png")

# Ship drop shadows: every caster's silhouette is drawn into a per-layer shadow-mask
# SubViewport (offset + scale baked into the mask sprites); the cloud shaders sample the
# mask and darken rgb only, density-gated. Deeper layers: bigger offset, SMALLER shadow
# (half per layer — the depth read), slightly weaker.
const SHADOW_DIR := Vector2(0.35, 0.9)   # normalized in _process; down + slightly right
const SHADOW_DIST := {"Far": 26.0, "Mid": 16.0, "Near": 8.0}
const SHADOW_SCALE := {"Far": 0.25, "Mid": 0.5, "Near": 1.0}
const SHADOW_MULT := {"Far": 0.8, "Mid": 0.9, "Near": 1.0}
# Demo enemy ships (single-frame sprites) that travel DOWN-screen under the Near layer.
const ENEMY_TEXES: Array = [
	preload("res://graphics/enemies/enemy_core_s_jet.png"),
	preload("res://graphics/enemies/enemy_c_s_skirmisher.png"),
	preload("res://graphics/enemies/enemy_core_s_flechette.png"),
]

const CONFIG_PATH := "user://tuners/planet_flyover.json"
const NATIVE := Vector2(480.0, 270.0)
const CLOUD_LAYERS := ["Far", "Mid", "Near"]

# Planet-surface presets. Each maps to a `surface_type` (a distinct generator in
# planet_ground.gdshader) + an 8-colour palette (indices are interpreted per generator —
# see the shader) + a couple of per-type knobs. This is what makes the surfaces genuinely
# different rather than one noise field recoloured.
#   type 0 TERRAN  biome ladder: [deep sea, sea, shallows, sand, grass, forest, mountain, snow]
#   type 1 DESERT  colours: [0..4] dark->light dunes, [5] canyon rock, [6] mesa, [7] caprock
#   type 2 ICE     colours: [0] crack, [1..3] ice dark->bright, [4] lake shelf, [5] lake deep
#   type 3 LAVA    colours: [0..2] rock dark->light, [3] lava edge, [4] lava mid, [5] lava core
#   type 4 MOON    colours: [0] shadow, [1] mid regolith, [2] maria/bowl, [3] sunlit
# `atmo` = whether this world has an atmosphere (gates the tint overlay + is the natural
# home for cloud layers); `atmo_color` = the default haze tint (user-tunable after).
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
	"Far":  {"scale": 3.4, "octaves": 6, "density": 0.85, "edge": 0.45, "warp": 1.0, "max_alpha": 0.34, "parallax": 1.15, "z": 10, "fs": 7.0},
	"Mid":  {"scale": 2.5, "octaves": 6, "density": 0.95, "edge": 0.40, "warp": 1.3, "max_alpha": 0.44, "parallax": 1.55, "z": 20, "fs": 5.0},
	"Near": {"scale": 1.7, "octaves": 5, "density": 1.05, "edge": 0.34, "warp": 1.6, "max_alpha": 0.60, "parallax": 2.30, "z": 30, "fs": 3.5},
}
const LAYER_STYLE_NAMES := ["Nebula", "Clouds"]

# ---- Tunable state (persisted) -------------------------------------------
var _flight: float = 0.35        # ground scroll speed, screen-heights / second
var _feature_scale: float = 8.0  # noise cells across the screen (feature size)
var _loop_size: int = 32         # tiling period (integer) — bigger = longer loop
var _octaves: int = 5
var _relief: float = 0.35
var _pixels: float = 160.0
var _river_cutoff: float = 0.5   # water/lava/rock coverage threshold (per preset, tunable)
var _cloud_opacity: float = 0.6  # master multiplier over each layer's opacity
var _cloud_coverage: float = 0.55  # generated-cloud style: how much sky is covered
var _preset: int = 0
# Atmosphere overlay: gated by the preset's `atmo` flag; colour defaults from the preset
# on switch, then both are free user knobs. Rendered as THREE slices interleaved with the
# cloud layers, so depth grades naturally: the ground sits under all three slices, Far
# under two, Mid under one, Near under none (most haze near the ground, least at the ship).
var _atmo_color: Color = Color(0.45, 0.65, 0.95)
var _atmo_opacity: float = 0.18
const ATMO_SLICE_Z := [5, 15, 25]          # ground<5<Far(10)<15<Mid(20)<25<Near(30)
const ATMO_SLICE_W := [0.45, 0.33, 0.22]   # opacity share per slice
# Demo ship + its cloud shadow.
var _ship_on: bool = true
var _ship_shadow: float = 0.35
# Per-decorative-layer knobs: style (Nebula=nebula2 / Clouds=cloud_layer), opacity, colour.
var _layer_style := {"Far": 0, "Mid": 0, "Near": 0}
var _layer_opacity := {"Far": 1.0, "Mid": 1.0, "Near": 1.0}
var _layer_color := {"Far": Color(0.75, 0.78, 0.83), "Mid": Color(0.82, 0.84, 0.88), "Near": Color(0.90, 0.91, 0.94)}
# Randomize Look state: shader noise seed (new terrain layout) + per-preset hue-rolled
# palettes (kit-style randomize_colors — one hue rotation shared by all slots keeps the
# ramp structure coherent while the hue family goes anywhere, like the kit's schemes).
var _rand_seed: float = 1.0
var _rand_palettes := {}         # preset name -> Array[Color] override (not persisted)
var _cloud_on := {"Far": true, "Mid": true, "Near": true}

# ---- Runtime -------------------------------------------------------------
var _sub: SubViewport = null
var _ground: ColorRect = null
var _atmo_rects: Array = []      # the three depth slices
var _ship: Sprite2D = null
var _ship_time: float = 0.0
var _mask_vps := {}              # layer -> SubViewport (shadow silhouettes)
var _casters: Array = []         # [{node, speed, masks: {layer: Sprite2D}}]
var _clouds := {}                # layer -> ColorRect
var _ground_scroll: float = 0.0  # accumulator, cells
var _cloud_off := {"Far": 0.0, "Mid": 0.0, "Near": 0.0}       # nebula style, screens
var _cloud_scroll := {"Far": 0.0, "Mid": 0.0, "Near": 0.0}    # clouds style, noise cells
var _status: Label = null
var _knob_box: VBoxContainer = null
var _atmo_picker: ColorPickerButton = null


func _ready() -> void:
	HdScreen.enter(self)
	_load()
	_build_scene()
	_build_ui()
	_apply_all()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _process(delta: float) -> void:
	# Ground: one screen-height = `_feature_scale` cells, so flight (screens/sec) advances
	# flight × feature_scale cells/sec. Wrap at 8× the tiling period — a whole period for
	# every layer whose Y coeff is a multiple of 0.125 (the moon's supermassive lattice).
	if _ground != null and is_instance_valid(_ground):
		_ground_scroll += _flight * _feature_scale * delta
		var mat: ShaderMaterial = _ground.material
		mat.set_shader_parameter("scroll", fposmod(_ground_scroll, 8.0 * float(_loop_size)))
	# Demo ships: player hover-bobs, enemies travel down-screen and respawn above. Every
	# caster's silhouette sprites follow it into the per-layer shadow masks.
	_ship_time += delta
	if _ship != null and is_instance_valid(_ship):
		_ship.position = Vector2(240.0 + sin(_ship_time * 0.7) * 4.0, 195.0 + sin(_ship_time * 1.3) * 2.0)
	var sh_dir := SHADOW_DIR.normalized()
	for c in _casters:
		var n: Sprite2D = c["node"]
		if n == null or not is_instance_valid(n):
			continue
		if float(c["speed"]) > 0.0:
			n.position.y += float(c["speed"]) * delta
			# Bottom zone → RECYCLE: drop under the Near cloud layer with the depth-tint
			# ghost, so the exit reads as sinking away through the cloud deck.
			if not bool(c["recycled"]) and n.position.y > 235.0:
				c["recycled"] = true
				n.z_index = 24
				n.modulate = Color(0.62, 0.66, 0.76, 0.95)
			if n.position.y > 310.0:
				c["recycled"] = false
				n.z_index = 35
				n.modulate = Color.WHITE
				n.position = Vector2(randf_range(60.0, 420.0), -40.0)
				c["speed"] = randf_range(30.0, 70.0)
		n.visible = _ship_on
		for layer in c["masks"]:
			var ms: Sprite2D = c["masks"][layer]
			if ms != null and is_instance_valid(ms):
				# A recycled ship is BELOW the Near layer — it can't shadow it.
				ms.visible = _ship_on and not (String(layer) == "Near" and bool(c["recycled"]))
				ms.position = n.position + sh_dir * float(SHADOW_DIST[layer])
	# Cloud layers: each rides its own parallax > ground. The two styles scroll through
	# different uniforms — nebula2 takes a UV scroll_offset (procedural, no seam), the
	# generated clouds take a noise-cell `scroll` wrapped at 2× the tiling period.
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


# ---- Scene ---------------------------------------------------------------

func _build_scene() -> void:
	_sub = HdScreen.make_play_subviewport(self)
	# Ground fills the whole native viewport, behind everything.
	_ground = ColorRect.new()
	_ground.name = "Ground"
	_ground.size = NATIVE
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.z_index = 0
	var gmat := ShaderMaterial.new()
	gmat.shader = GROUND_SHADER
	_ground.material = gmat
	_sub.add_child(_ground)
	# Atmosphere haze: three slices interleaved with the cloud layers (see ATMO_SLICE_Z),
	# gated by the preset's `atmo` flag.
	_atmo_rects.clear()
	for i in ATMO_SLICE_Z.size():
		var slice := ColorRect.new()
		slice.name = "Atmosphere%d" % i
		slice.size = NATIVE
		slice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slice.z_index = int(ATMO_SLICE_Z[i])
		_sub.add_child(slice)
		_atmo_rects.append(slice)
	# Cloud layers on top, back (Far) to front (Near). Materials are assigned in
	# _apply_clouds — the shader depends on the layer's chosen style.
	for layer in CLOUD_LAYERS:
		var rect := ColorRect.new()
		rect.name = "Cloud_" + layer
		rect.size = NATIVE
		rect.color = Color(0, 0, 0, 0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.z_index = int(CLOUD_CFG[layer]["z"])
		_sub.add_child(rect)
		_clouds[layer] = rect
	# Per-layer shadow-mask viewports: casters' silhouettes drawn at that layer's offset
	# and scale; the cloud shaders sample the mask. Children of the Control, not _sub.
	for layer in CLOUD_LAYERS:
		var vp := SubViewport.new()
		vp.size = Vector2i(480, 270)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.gui_disable_input = true
		vp.handle_input_locally = false
		add_child(vp)
		_mask_vps[layer] = vp
	# Demo player ship above everything — a COMPOSED single frame (the sheet is a 3-hframe
	# banking strip; frame 1 = level flight), casts on all three layers.
	_ship = Sprite2D.new()
	_ship.name = "Ship"
	_ship.texture = _single_frame(SHIP_TEX, 1)
	_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship.position = Vector2(240.0, 195.0)
	_ship.z_index = 40
	_sub.add_child(_ship)
	_casters.append(_register_caster(_ship, CLOUD_LAYERS, 0.0))
	# Demo enemy ships: LIVE they travel down-screen ABOVE the Near layer (z 35) casting on
	# all three masks. Reaching the bottom zone they RECYCLE — drop to z 24 (UNDER the Near
	# clouds: the production contract for the recycle/wreck layers), take the depth-tint
	# ghost, stop casting on Near — and sink off through the cloud deck, then respawn.
	for i in 3:
		var e := Sprite2D.new()
		e.name = "Enemy%d" % i
		# Enemy sheets are 3-hframe strips too (body/glow/livery); frame 0 = the body.
		e.texture = _single_frame(ENEMY_TEXES[i % ENEMY_TEXES.size()], 0)
		e.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		e.rotation = PI   # art faces up; these fly down
		e.z_index = 35
		e.position = Vector2(randf_range(60.0, 420.0), randf_range(-260.0, -20.0))
		_sub.add_child(e)
		_casters.append(_register_caster(e, CLOUD_LAYERS, randf_range(30.0, 70.0)))


# One frame of a 3-hframe sprite strip as a standalone texture.
func _single_frame(tex: Texture2D, frame: int) -> AtlasTexture:
	var fw: float = tex.get_width() / 3.0
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(fw * float(frame), 0.0, fw, tex.get_height())
	return at


# Build a caster record: one silhouette sprite per cloud layer it shadows, living in that
# layer's mask viewport, pre-scaled to the layer's shadow size.
func _register_caster(node: Sprite2D, layers: Array, speed: float) -> Dictionary:
	var masks := {}
	for layer in layers:
		var ms := Sprite2D.new()
		ms.texture = node.texture
		ms.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ms.rotation = node.rotation
		ms.scale = Vector2.ONE * float(SHADOW_SCALE[layer])
		_mask_vps[layer].add_child(ms)
		masks[layer] = ms
	return {"node": node, "speed": speed, "masks": masks, "recycled": false}


func _apply_all() -> void:
	_apply_ground()
	_apply_atmo()
	_apply_clouds()


func _apply_atmo() -> void:
	var has_atmo: bool = bool(PRESETS[PRESET_NAMES[_preset]]["atmo"])
	for i in _atmo_rects.size():
		var slice = _atmo_rects[i]
		if slice == null or not is_instance_valid(slice):
			continue
		slice.visible = has_atmo
		slice.color = Color(_atmo_color.r, _atmo_color.g, _atmo_color.b, _atmo_opacity * float(ATMO_SLICE_W[i]))


func _apply_ground() -> void:
	if _ground == null or not is_instance_valid(_ground):
		return
	var pname: String = PRESET_NAMES[_preset]
	var preset: Dictionary = PRESETS[pname]
	var mat: ShaderMaterial = _ground.material
	mat.set_shader_parameter("rect_size", NATIVE)
	mat.set_shader_parameter("pixels", _pixels)
	mat.set_shader_parameter("feature_scale", _feature_scale)
	mat.set_shader_parameter("size", float(_loop_size))
	mat.set_shader_parameter("OCTAVES", _octaves)
	mat.set_shader_parameter("relief", _relief)
	mat.set_shader_parameter("seed", _rand_seed)
	mat.set_shader_parameter("sun_dir", Vector2(0.40, 0.35))
	mat.set_shader_parameter("surface_type", int(preset["type"]))
	mat.set_shader_parameter("river_cutoff", _river_cutoff)
	mat.set_shader_parameter("emissive", float(preset["emissive"]))
	mat.set_shader_parameter("should_dither", true)
	mat.set_shader_parameter("colors", PackedColorArray(_rand_palettes.get(pname, preset["colors"])))


func _apply_clouds() -> void:
	for layer in CLOUD_LAYERS:
		var rect = _clouds.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		rect.visible = _cloud_on[layer]
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
		mat.set_shader_parameter("shadow_strength", (_ship_shadow * float(SHADOW_MULT[layer])) if _ship_on else 0.0)
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


# ---- UI ------------------------------------------------------------------

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -430
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.92)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(398, 0)
	scroll.add_child(v)

	v.add_child(_label("PLANET FLYOVER LAB", UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))
	v.add_child(_label("Scrolling ground from the PixelPlanets land-mass noise + gray/white cloud layers.\nSeamless vertical loop.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))

	# Planet surface preset.
	v.add_child(_label("SURFACE", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var dd := OptionButton.new()
	for n in PRESET_NAMES:
		dd.add_item(n)
	dd.select(_preset)
	dd.item_selected.connect(_on_preset_changed)
	v.add_child(dd)

	# Randomize Look: new noise seed + kit-style hue-rolled palette for this preset.
	var rrow := HBoxContainer.new()
	var rand_b := UiTheme.make_button("Randomize Look", true)
	rand_b.pressed.connect(_on_randomize_look)
	rrow.add_child(rand_b)
	var auth_b := UiTheme.make_button("Authored Look", true)
	auth_b.pressed.connect(_on_authored_look)
	rrow.add_child(auth_b)
	v.add_child(rrow)

	# Atmosphere: gated by the preset's atmo flag; colour + opacity free knobs.
	v.add_child(_label("ATMOSPHERE", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var arow := HBoxContainer.new()
	_atmo_picker = ColorPickerButton.new()
	_atmo_picker.color = _atmo_color
	_atmo_picker.custom_minimum_size = Vector2(56, 26)
	_atmo_picker.color_changed.connect(func(c): _atmo_color = c; _apply_atmo())
	arow.add_child(_atmo_picker)
	var aslider := _slider("Opacity", _atmo_opacity, 0.0, 0.6, 0.01, func(x): _atmo_opacity = x; _apply_atmo())
	aslider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(aslider)
	v.add_child(arow)

	# Cloud layer toggles.
	v.add_child(_label("CLOUD LAYERS (depth)", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var lrow := HBoxContainer.new()
	for layer in CLOUD_LAYERS:
		var cb := CheckButton.new()
		cb.text = layer
		cb.button_pressed = _cloud_on[layer]
		cb.toggled.connect(_on_cloud_toggled.bind(layer))
		lrow.add_child(cb)
	v.add_child(lrow)

	# Per-layer style / colour / opacity — max parallax cloud/dust tunability.
	for layer in CLOUD_LAYERS:
		var row := HBoxContainer.new()
		var name_l := _label(layer, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
		name_l.custom_minimum_size = Vector2(38, 0)
		row.add_child(name_l)
		var style_dd := OptionButton.new()
		for s in LAYER_STYLE_NAMES:
			style_dd.add_item(s)
		style_dd.select(int(_layer_style[layer]))
		style_dd.item_selected.connect(func(idx): _layer_style[layer] = idx; _apply_clouds())
		row.add_child(style_dd)
		var pick := ColorPickerButton.new()
		pick.color = _layer_color[layer]
		pick.custom_minimum_size = Vector2(44, 26)
		pick.color_changed.connect(func(c): _layer_color[layer] = c; _apply_clouds())
		row.add_child(pick)
		var op := HSlider.new()
		op.min_value = 0.0
		op.max_value = 1.0
		op.step = 0.02
		op.value = float(_layer_opacity[layer])
		op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		op.custom_minimum_size = Vector2(0, 16)
		op.value_changed.connect(func(x): _layer_opacity[layer] = x; _apply_clouds())
		row.add_child(op)
		v.add_child(row)

	v.add_child(HSeparator.new())
	v.add_child(_label("GROUND", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	v.add_child(_slider("Flight speed", _flight, 0.0, 2.0, 0.01, func(x): _flight = x))
	v.add_child(_slider("Feature scale", _feature_scale, 3.0, 24.0, 0.5, func(x): _feature_scale = x; _apply_ground()))
	v.add_child(_slider("Loop size (period)", float(_loop_size), 12.0, 96.0, 1.0, func(x): _loop_size = int(x); _apply_ground()))
	v.add_child(_slider("Octaves", float(_octaves), 1.0, 8.0, 1.0, func(x): _octaves = int(x); _apply_ground()))
	v.add_child(_slider("Relief (sun)", _relief, 0.0, 1.0, 0.02, func(x): _relief = x; _apply_ground()))
	v.add_child(_slider("Water / lava level", _river_cutoff, 0.2, 0.8, 0.01, func(x): _river_cutoff = x; _apply_ground()))
	v.add_child(_slider("Pixelation", _pixels, 40.0, 480.0, 5.0, func(x): _pixels = x; _apply_ground(); _apply_clouds()))

	v.add_child(HSeparator.new())
	v.add_child(_label("CLOUDS", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	v.add_child(_slider("Cloud opacity", _cloud_opacity, 0.0, 1.0, 0.02, func(x): _cloud_opacity = x; _apply_clouds()))
	v.add_child(_slider("Cloud coverage", _cloud_coverage, 0.0, 1.0, 0.02, func(x): _cloud_coverage = x; _apply_clouds()))
	var srow := HBoxContainer.new()
	var ship_cb := CheckButton.new()
	ship_cb.text = "Ships"
	ship_cb.button_pressed = _ship_on
	ship_cb.toggled.connect(func(p): _ship_on = p; _apply_clouds())
	srow.add_child(ship_cb)
	var sshadow := _slider("Cloud shadow", _ship_shadow, 0.0, 1.0, 0.02, func(x): _ship_shadow = x; _apply_clouds())
	sshadow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sshadow)
	v.add_child(srow)

	v.add_child(HSeparator.new())
	var frow := HBoxContainer.new()
	var save_b := UiTheme.make_button("Save", true)
	save_b.pressed.connect(_save)
	frow.add_child(save_b)
	var copy_b := UiTheme.make_button("Copy GDScript", true)
	copy_b.pressed.connect(_copy_snippet)
	frow.add_child(copy_b)
	var close_b := UiTheme.make_button("Close", true)
	close_b.pressed.connect(_on_close)
	frow.add_child(close_b)
	v.add_child(frow)

	_status = _label("", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	v.add_child(_status)


func _on_preset_changed(idx: int) -> void:
	_preset = idx
	# Atmosphere colour defaults from the preset on switch (then stays user-tunable).
	_atmo_color = PRESETS[PRESET_NAMES[idx]]["atmo_color"]
	if _atmo_picker != null and is_instance_valid(_atmo_picker):
		_atmo_picker.color = _atmo_color
	_apply_ground()
	_apply_atmo()
	_set_status("Surface: %s" % PRESET_NAMES[idx])


# New shader seed (fresh terrain layout) + a hue-rolled palette for the current preset —
# one random hue rotation shared across all slots (ramps stay coherent, hue family goes
# anywhere, like the kit's randomize_colors schemes) with slight per-slot sat/val jitter.
func _on_randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_rand_seed = rng.randf_range(1.0, 10.0)
	var pname: String = PRESET_NAMES[_preset]
	var dh := rng.randf()
	var out: Array = []
	for c in PRESETS[pname]["colors"]:
		out.append(_shift_color(c, dh, rng))
	_rand_palettes[pname] = out
	_apply_ground()
	_set_status("Randomized %s look (seed %.2f)." % [pname, _rand_seed])


func _on_authored_look() -> void:
	_rand_palettes.erase(PRESET_NAMES[_preset])
	_rand_seed = 1.0
	_apply_ground()
	_set_status("Authored look restored.")


# Hue-rotate + jitter one palette colour. Low-saturation entries (snow, gray rock) barely
# move under hue rotation, which is exactly right — snow stays snow on any hue roll.
func _shift_color(c: Color, dh: float, rng: RandomNumberGenerator) -> Color:
	return Color.from_hsv(
		fposmod(c.h + dh, 1.0),
		clampf(c.s + rng.randf_range(-0.08, 0.08), 0.0, 1.0),
		clampf(c.v + rng.randf_range(-0.06, 0.06), 0.0, 1.0),
		c.a)


func _on_cloud_toggled(pressed: bool, layer: String) -> void:
	_cloud_on[layer] = pressed
	_apply_clouds()


# ---- Persistence ---------------------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var lc := {}
	for layer in CLOUD_LAYERS:
		lc[layer] = (_layer_color[layer] as Color).to_html(false)
	var data := {
		"flight": _flight, "feature_scale": _feature_scale, "loop_size": _loop_size,
		"octaves": _octaves, "relief": _relief, "pixels": _pixels, "river_cutoff": _river_cutoff,
		"cloud_opacity": _cloud_opacity, "cloud_coverage": _cloud_coverage,
		"preset": _preset, "cloud_on": _cloud_on,
		"atmo_color": _atmo_color.to_html(false), "atmo_opacity": _atmo_opacity,
		"layer_style": _layer_style, "layer_opacity": _layer_opacity, "layer_color": lc,
		"ship_on": _ship_on, "ship_shadow": _ship_shadow,
	}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		_set_status("Saved to %s" % CONFIG_PATH)


func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_flight = float(d.get("flight", _flight))
		_feature_scale = float(d.get("feature_scale", _feature_scale))
		_loop_size = int(d.get("loop_size", _loop_size))
		_octaves = int(d.get("octaves", _octaves))
		_relief = float(d.get("relief", _relief))
		_pixels = float(d.get("pixels", _pixels))
		_river_cutoff = float(d.get("river_cutoff", _river_cutoff))
		_cloud_opacity = float(d.get("cloud_opacity", _cloud_opacity))
		_cloud_coverage = float(d.get("cloud_coverage", _cloud_coverage))
		_atmo_opacity = float(d.get("atmo_opacity", _atmo_opacity))
		_ship_on = bool(d.get("ship_on", _ship_on))
		_ship_shadow = float(d.get("ship_shadow", _ship_shadow))
		if d.has("atmo_color"):
			_atmo_color = Color.from_string(String(d["atmo_color"]), _atmo_color)
		# Clamp: a saved index can outlive a removed preset (Moon 2 was scrubbed).
		_preset = clampi(int(d.get("preset", _preset)), 0, PRESET_NAMES.size() - 1)
		if d.has("cloud_on"):
			for layer in CLOUD_LAYERS:
				_cloud_on[layer] = bool(d["cloud_on"].get(layer, true))
		if d.has("layer_style"):
			for layer in CLOUD_LAYERS:
				_layer_style[layer] = int(d["layer_style"].get(layer, 0))
		if d.has("layer_opacity"):
			for layer in CLOUD_LAYERS:
				_layer_opacity[layer] = float(d["layer_opacity"].get(layer, 1.0))
		if d.has("layer_color"):
			for layer in CLOUD_LAYERS:
				if d["layer_color"].has(layer):
					_layer_color[layer] = Color.from_string(String(d["layer_color"][layer]), _layer_color[layer])


func _copy_snippet() -> void:
	var t := "# Planet Flyover — tuned ground config.\n"
	t += "const GROUND_PRESET := \"%s\"  # surface_type %d\n" % [PRESET_NAMES[_preset], int(PRESETS[PRESET_NAMES[_preset]]["type"])]
	t += "const GROUND_FLIGHT := %s        # screen-heights / second\n" % _fmt(_flight)
	t += "const GROUND_FEATURE_SCALE := %s # noise cells across the screen\n" % _fmt(_feature_scale)
	t += "const GROUND_LOOP_SIZE := %d      # tiling period (integer, seamless)\n" % _loop_size
	t += "const GROUND_OCTAVES := %d\n" % _octaves
	t += "const GROUND_RELIEF := %s\n" % _fmt(_relief)
	t += "const GROUND_RIVER_CUTOFF := %s  # water/lava/rock coverage\n" % _fmt(_river_cutoff)
	t += "const GROUND_SEED := %s\n" % _fmt(_rand_seed)
	t += "const GROUND_PIXELS := %s\n" % _fmt(_pixels)
	var pname: String = PRESET_NAMES[_preset]
	t += "const ATMOSPHERE := %s  # colour #%s, opacity %s\n" % [str(PRESETS[pname]["atmo"]), _atmo_color.to_html(false), _fmt(_atmo_opacity)]
	t += "const CLOUD_OPACITY := %s\n" % _fmt(_cloud_opacity)
	t += "const CLOUD_COVERAGE := %s\n" % _fmt(_cloud_coverage)
	t += "const SHIP_CLOUD_SHADOW := %s\n" % _fmt(_ship_shadow)
	for layer in CLOUD_LAYERS:
		t += "# %s: style=%s colour=#%s opacity=%s\n" % [layer, LAYER_STYLE_NAMES[int(_layer_style[layer])], (_layer_color[layer] as Color).to_html(false), _fmt(_layer_opacity[layer])]
	DisplayServer.clipboard_set(t)
	_set_status("Copied GDScript to clipboard.")


func _fmt(x) -> String:
	return "%.3f" % float(x)


func _on_close() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---- Small helpers -------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _slider(title: String, value: float, lo: float, hi: float, step: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var name_l := _label(title, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
	name_l.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 16)
	var val_l := _label("%.2f" % value, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_ACCENT)
	val_l.custom_minimum_size = Vector2(52, 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x):
		val_l.text = "%.2f" % x
		on_change.call(x))
	row.add_child(s)
	row.add_child(val_l)
	return row


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg
