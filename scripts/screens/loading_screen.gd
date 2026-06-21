class_name LoadingScreen
extends Control

# Inter-node loading screen (Roman 2026-06-19). Shown while the next combat level
# loads: the chosen ship "flies at speed" up the screen toward a destination, over a
# black void of swift star-parallax + warp streaks. When loading finishes, fly_off()
# launches the ship off the top — the same accelerate-and-vanish beat as the real
# level-exit (`main.gd::_run_outro`) — then emits `flight_complete` for the caller to
# swap scenes.
#
# RENDER MODEL (mirrors the HD dev-tool pattern, scripts/dev/player_fx_lab.gd):
#   HD (1920×1080) Control root → a native 480×270 SubViewport holds the WORLD
#   (black + the two star CanvasLayers + warp streaks + the ship), upscaled 4× by the
#   SubViewportContainer. The "Flying to …" title is HD Control text composited on top
#   (crisp). The ship, its engine plume, and the fly-off tween all live in native 480
#   space, so the exit reads identically to combat.
#
# Identity (ship variant + livery + hull DAMAGE + destination) defaults from the Run autoload — the
# ship shown is the player's ACTUAL ship in its ACTUAL damage state, so a battered ship arrives at
# the next fight looking battered. A caller (or the dev lab) can override the public fields before
# add_child, or live via the set_*/rebuild_*/apply_hull methods. Set `manage_hd_scope = false` when
# embedding under a host that already owns an HD scope (the dev lab) to avoid a double scale swap.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

const STARS_SCENE := "res://scenes/parallax/layers/layer_stars.tscn"

# Player scenes per variant (index = Run.ship_variant). We render the REAL combat player (idle: no
# input / collision / weapons, never dies) rather than a sprite mock, so the livery shader, engine
# glow AND the live damage tells (engine_torch / damage_smoke_trail / spark_trail) match combat.
const PLAYER_SCENES := [
	"res://scenes/player/player.tscn",
	"res://scenes/player/player_b.tscn",
	"res://scenes/player/player_c.tscn",
]

const NATIVE_W := 480.0
const SHIP_X := NATIVE_W / 2.0   # 240 — native viewport centre (matches _run_outro)
const FLYOFF_TARGET_Y := -120.0  # off the top edge, same as _run_outro

signal flight_complete

# ---- Identity (set before add_child, or via configure(); -1/false = read from Run) ----
@export var poi_name: String = ""
@export var ship_variant: int = -1
@export var ship_hull: int = -1       # current hull; -1 = read Run.current_hull (carried damage)
@export var ship_max_hull: int = -1   # max hull;     -1 = read Run.max_hull
@export var manage_hd_scope: bool = true

# ---- Visual tuning knobs (the dev lab drives these; defaults are the shipped look) ----
@export var star_drift: float = 18000.0       # star scroll rate — "swiftness" of the rush
@export var star_alpha: float = 0.5           # fade the star layers (1 = full bright)
@export var streak_count: int = 4
@export var streak_speed: float = 1600.0
@export var streak_width_min: float = 1.0     # px — streaks render 1..2px wide (texture is 1px wide)
@export var streak_width_max: float = 1.5
@export var streak_length: float = 80.0       # px — base streak length (texture height)
@export var ship_rest_y: float = 150.0        # native-Y the ship hovers around
@export var ship_drift_ax: float = 5.0        # gentle centre-drift amplitude (px)
@export var ship_drift_ay: float = 1.5
@export var ship_drift_period_x: float = 2.4  # seconds per drift cycle
@export var ship_drift_period_y: float = 1.9
@export var flyoff_time: float = 1.0

var _hd: HdViewportScope = null
var _world: SubViewport = null
var _stars: CanvasLayer = null
var _streaks: GPUParticles2D = null
var _ship: Node2D = null
var _name_label: Label = null
var _enroute_label: Label = null
var _t: float = 0.0
var _flying: bool = true
var _built: bool = false


func _ready() -> void:
	if manage_hd_scope:
		_hd = HdScreen.enter(self)
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resolve_identity()
	_build_world_viewport()
	rebuild_streaks()
	_build_stars()
	rebuild_ship()
	_build_title()
	_built = true


# Robust HD play-area. HdScreen.make_play_subviewport (a SubViewportContainer with stretch) rendered
# BLURRY + SMALL in the live window: the container recomputes the viewport size from its own size on
# every layout pass, which is timing-fragile across a scene transition (it reads correct in headless
# but not in the real window). Instead use a FIXED 480×270 SubViewport shown by a full-rect,
# nearest-filtered STRETCH_SCALE TextureRect — the exact crisp 1:1 upscale live backdrops use
# (HdScreen.add_upscaled_backdrop). The world always renders at native 480 and scales up cleanly.
func _build_world_viewport() -> void:
	_world = SubViewport.new()
	_world.name = "WorldViewport"
	_world.size = Vector2i(480, 270)
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world.transparent_bg = false
	_world.gui_disable_input = true
	_world.handle_input_locally = false
	# Match the project's 2D-HDR mode so additive blends (engine glow / muzzle) composite correctly.
	_world.use_hdr_2d = bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))
	add_child(_world)
	var view := TextureRect.new()
	view.name = "WorldView"
	view.texture = _world.get_texture()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)


# Override identity in one call (caller-facing). Pass -1 for any of variant/hull/max_hull to defer
# that field to the Run value. Livery is always taken from Run (the real player reads it).
func configure(p_poi: String, p_variant: int = -1, p_hull: int = -1, p_max_hull: int = -1) -> void:
	poi_name = p_poi
	ship_variant = p_variant
	ship_hull = p_hull
	ship_max_hull = p_max_hull
	if _built:
		_resolve_identity()
		rebuild_ship()
		set_poi_name(poi_name)


func _resolve_identity() -> void:
	var run := get_node_or_null("/root/Run")
	if ship_variant < 0:
		ship_variant = int(run.ship_variant) if run != null and "ship_variant" in run else 0
	ship_variant = clampi(ship_variant, 0, PLAYER_SCENES.size() - 1)
	# Carried damage state (current/max). Stay -1 when Run has none (fresh Run / dev lab) → the ship
	# keeps the player scene's own default hull (undamaged).
	if ship_max_hull < 0 and run != null and "max_hull" in run:
		ship_max_hull = int(run.max_hull)
	if ship_hull < 0 and run != null and "current_hull" in run:
		ship_hull = int(run.current_hull)
	if poi_name.is_empty():
		poi_name = _default_poi_name(run)


# Deterministic-per-node destination name (same node → same name across map re-entries),
# falling back to a fresh random name outside a run. Mirrors run_state's per-POI seeding.
func _default_poi_name(run: Node) -> String:
	var seed_value: int = 0
	if run != null and "run_seed" in run:
		seed_value = int(run.run_seed) ^ abs(hash(String(run.current_node_id)))
	else:
		seed_value = randi()
	return SectorNameGenerator.generate(seed_value)


# ---- World build ----------------------------------------------------------

func _build_stars() -> void:
	if _stars != null and is_instance_valid(_stars):
		_stars.queue_free()
	_stars = load(STARS_SCENE).instantiate()
	_world.add_child(_stars)
	if _stars.has_method("reseed"):
		_stars.reseed(randi())
	apply_star_alpha()


# Fade the star fields (not the black backdrop) to taste. The DeepSpace ColorRect is a
# sibling of the two Parallax2D star containers, so modulating those leaves the void black.
func apply_star_alpha() -> void:
	if _stars == null or not is_instance_valid(_stars):
		return
	for nm in ["FarStars", "NearStars"]:
		var n = _stars.get_node_or_null(nm)
		if n != null:
			n.modulate.a = clampf(star_alpha, 0.0, 1.0)


# Dedicated warp streaks. A 1px-WIDE, tall texture means uniform particle scale sets the
# on-screen WIDTH (1..2px) while the texture HEIGHT carries the length — long but thin, which
# the shared combat streak layer (a 2px texture scaled uniformly) cannot do. Behind the ship.
func rebuild_streaks() -> void:
	if _streaks != null and is_instance_valid(_streaks):
		_streaks.queue_free()
		_streaks = null
	var p := GPUParticles2D.new()
	p.name = "WarpStreaks"
	p.amount = maxi(1, streak_count)
	p.lifetime = (320.0 + streak_length) / maxf(streak_speed, 1.0)
	p.preprocess = p.lifetime   # populate the field on spawn rather than empty
	p.local_coords = false
	p.position = Vector2(SHIP_X, -10.0)
	p.z_index = -2              # behind the ship (z 0) and its exhaust trail (z -1)
	p.z_as_relative = false
	p.texture = _build_streak_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(240.0, 6.0, 0.0)
	m.direction = Vector3(0, 1, 0)   # downward = ship flying up
	m.spread = 0.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = streak_speed * 0.8
	m.initial_velocity_max = streak_speed * 1.2
	m.scale_min = streak_width_min   # 1px-wide texture → scale == on-screen width (px)
	m.scale_max = streak_width_max
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(0.55, 0.7, 1.0, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	m.color_ramp = ramp
	p.process_material = m
	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive glow
	p.material = cmat
	_streaks = p
	_world.add_child(p)


# 1px-wide vertical gradient (faint tips, bright middle); height = streak length.
func _build_streak_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 1
	t.height = int(maxf(streak_length, 2.0))
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t


# Spawn the real combat player as an idle presentation copy: no input, no collision, no weapons,
# never dies. Its _ready wires the livery shader, engine glow + the live damage tells; setting hull
# from Run then lights up the tells the ship would show in combat at the same damage.
func rebuild_ship() -> void:
	if _ship != null and is_instance_valid(_ship):
		_ship.queue_free()
	var idx: int = clampi(ship_variant, 0, PLAYER_SCENES.size() - 1)
	var p: Node2D = load(PLAYER_SCENES[idx]).instantiate()
	if "controls_enabled" in p:
		p.controls_enabled = false   # skips input/fire; pins the level-flight frame
	if "invincible" in p:
		p.invincible = true
	if "is_alive" in p:
		p.is_alive = true
	_world.add_child(p)
	if "monitoring" in p:
		p.monitoring = false
	if "monitorable" in p:
		p.monitorable = false
	p.position = Vector2(SHIP_X, ship_rest_y)
	_ship = p
	# Drop the shield FX (the Ship/Shield bubble + the code-built ShieldRing) — a calm loading
	# screen shouldn't carry the combat shield graphic. Hides any shield CanvasItem on the ship.
	for n in p.find_children("*Shield*", "", true, false):
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	# The player's _ready attaches its engine trail + damage tells (some add deferred). Let them
	# settle a frame, then drive the hull so the tells reflect the carried damage.
	await get_tree().process_frame
	if is_instance_valid(_ship):
		apply_hull()


# Drive the ship's hull → emits hull_changed → engine_torch / damage_smoke_trail / spark_trail
# update to the carried damage severity (1 - hull/max). No-op when there's no valid hull state
# (fresh Run / dev lab default) — the ship then reads as undamaged.
func apply_hull() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	if ship_max_hull <= 0:
		return
	var mh: int = maxi(1, ship_max_hull)
	var h: int = clampi(ship_hull, 0, mh)
	if "max_hull" in _ship:
		_ship.max_hull = mh
	if "hull" in _ship:
		_ship.hull = h
	if _ship.has_signal("hull_changed"):
		_ship.hull_changed.emit(mh, h)


func _build_title() -> void:
	# HD title block, top-centre. Composited over the upscaled world (crisp at 1:1).
	var box := VBoxContainer.new()
	box.name = "TitleBox"
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 88.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var eyebrow := _label("FLYING TO", UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_FAINT)
	box.add_child(eyebrow)

	_name_label = _label(poi_name.to_upper(), UiTheme.FONT_SIZE_TITLE + 12, UiTheme.COLOR_ACCENT)
	box.add_child(_name_label)

	_enroute_label = _label("• EN ROUTE •", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	box.add_child(_enroute_label)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---- Live setters (dev lab) -----------------------------------------------

func set_poi_name(p: String) -> void:
	poi_name = p
	if _name_label != null and is_instance_valid(_name_label):
		_name_label.text = p.to_upper()


# ---- Runtime --------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _stars != null and is_instance_valid(_stars) and _stars.has_method("scroll_stars"):
		_stars.scroll_stars(star_drift * delta)
	if _enroute_label != null and is_instance_valid(_enroute_label):
		_enroute_label.modulate.a = 0.45 + 0.35 * (0.5 + 0.5 * sin(_t * TAU * 0.6))
	if _flying and _ship != null and is_instance_valid(_ship):
		var dx: float = sin(_t * TAU / maxf(ship_drift_period_x, 0.1)) * ship_drift_ax
		var dy: float = sin(_t * TAU / maxf(ship_drift_period_y, 0.1) + 1.3) * ship_drift_ay
		_ship.position = Vector2(SHIP_X + dx, ship_rest_y + dy)


# Loading finished → launch the ship off the top, then signal. Idempotent.
func fly_off() -> void:
	if not _flying:
		return
	_flying = false
	if _ship == null or not is_instance_valid(_ship):
		emit_signal("flight_complete")
		return
	var tw := create_tween()
	tw.tween_property(_ship, "position", Vector2(SHIP_X, FLYOFF_TARGET_Y), flyoff_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void: emit_signal("flight_complete"))


# Release the HD content-scale scope. The launcher calls this under the black cover of the
# exit swap (combat is native 480 — leaving HD up would render it blown-up). No-op when this
# screen never owned a scope (embedded in the dev lab with manage_hd_scope=false).
func drop_hd_scope() -> void:
	HdScreen.drop(_hd)
	_hd = null


# Reset to the hovering "flying" state (dev lab re-test).
func replay() -> void:
	_flying = true
	_t = 0.0
	if _ship != null and is_instance_valid(_ship):
		_ship.position = Vector2(SHIP_X, ship_rest_y)
