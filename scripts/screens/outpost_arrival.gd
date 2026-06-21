class_name OutpostArrival
extends Control

# Outpost arrival sequence + dock screen (Roman 2026-06-19). A cinematic-led menu:
# the composed player ship flies in slowly from the bottom of the screen, decelerates
# to a stop over a landing pad and cuts its engines; a close drop shadow snaps tighter
# as it sets down (the "landing" cue). Black bars on the gutters then fade away to
# reveal the dock menus (left market/services, right ship-status/hold). Departing
# reverses it: UI fades back to the narrow play band, engines relight, the ship rises
# (shadow spreads) then launches off the top.
#
# RENDER MODEL (mirrors the loading-screen / HD dev-tool pattern, scripts/screens/
# loading_screen.gd): an HD (1920×1080) Control root composites a native 480×270
# SubViewport (the dark bay + landing pad + the ship + its shadow + engine plume,
# upscaled 4×) UNDER the HD menu Controls. The center 216-band (Playfield.X_MIN..X_MAX
# → HD 528..1392) is the visible landing strip; the two 132-px gutters host the side
# panels, masked by black ColorRects that fade on landing.
#
# DAMAGE VISUALS (Roman 2026-06-19): the composited ship wears the SAME damage-overlay
# shader the combat player uses (graphics/damage_noise.gdshader), plus damage tells —
# smoke (damage_smoke_trail) that emits only while the engine runs (so it STOPS once
# the ship sets down) and sparks (spark_trail_fx, replacing the engine-torch flames)
# that persist while damaged. The engine streak + tells respect EACH body's real engine
# markers (A: 1, B/C: 2). Drive the damage with `damage_level` (0 = pristine, 1 = wreck).
#
# SCOPE: the cinematic + the dock LAYOUT are real. The inventory is a self-contained
# MOCK (local item model — buy/pull/slot/swap/scrap/lock all work on it) so the screen
# can be evaluated; wiring it to Run's real loadout/storage is the follow-on.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const EngineTrailFx = preload("res://scripts/effects/engine_trail_fx.gd")
const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const DamageSmokeTrail = preload("res://scripts/effects/damage_smoke_trail.gd")
const PF = preload("res://scripts/systems/playfield.gd")

const DamageOverlayShader = preload("res://graphics/damage_noise.gdshader")
const _DamageNoiseTex = preload("res://resources/noise_damage.tres")
const _DamageEdgeTex = preload("res://resources/edge_distance_flat.tres")

const ENGINE_GLOW_COLOR := Color(0.0, 0.827, 1.0)   # #00d3ff — in-game engine glowmask
const TELL_ACTIVATE := 0.5   # missing-hull fraction at which smoke/sparks light (player default)
const SPARK_GRAVITY := 120.0  # gentle downward drift on the sparks (lower = "less velocity")
# Landed sparks crackle intermittently (not a constant fountain); frequency + density scale
# with damage. While moving they emit continuously (the motion trails them). Roman 2026-06-19.
const SPARK_BURST_DUR := 0.2          # emit window per landed puff (s)
const SPARK_SPRAY_DUR := 0.5          # damaged spool-up spray duration (s) — "engine starting up"
const SPARK_INTERVAL_LIGHT := 3.6     # seconds between puffs at threshold damage
const SPARK_INTERVAL_HEAVY := 1.4     # ... at full damage (more frequent)
const SPARK_AMOUNT_LIGHT := 8         # particles per puff at threshold damage
const SPARK_AMOUNT_HEAVY := 55        # ... at full damage (denser)
const SPARK_SPRAY_AMOUNT := 60        # emphatic spool-up spray on a damaged launch
const SPARK_LIFETIME := 0.5           # short-lived parked sparks
const SPARK_TRAIL_LIFETIME := 0.35    # short spark ribbons
const SPARK_RADIAL_VEL := 16.0        # low spark velocity (scene default ~50)
# Point lights: blue on each engine (follows the glow on/off), orange on each spark marker
# (flashes when the ship sparks). Roman 2026-06-20.
const ENGINE_LIGHT_COLOR := Color(0.10, 0.60, 1.0)
const ENGINE_LIGHT_ENERGY := 0.9
const ENGINE_LIGHT_SCALE := 0.30
const SPARK_LIGHT_COLOR := Color(1.0, 0.55, 0.12)
const SPARK_LIGHT_ENERGY := 1.0
const SPARK_LIGHT_SCALE := 0.22
const SPARK_LIGHT_RATE := 8.0         # light energy attack/decay per second (flash speed)

# Per-variant art layers + engine marker positions (index = Run.ship_variant). The engine
# positions mirror scenes/player/player{,_b,_c}.tscn so the streak + tells sit on each
# body's real nozzles (A has one, B/C have two). Roman 2026-06-19.
const VARIANTS := [
	{"body": "res://graphics/player/player_ship_a_body.png", "livery": "res://graphics/player/player_ship_a_livery.png", "engine": "res://graphics/player/player_ship_a_engines.png", "engines": [Vector2(0, 6)]},
	{"body": "res://graphics/player/player_ship_b_body.png", "livery": "res://graphics/player/player_ship_b_livery.png", "engine": "res://graphics/player/player_ship_b_engines.png", "engines": [Vector2(-4, 5), Vector2(4, 5)]},
	{"body": "res://graphics/player/player_ship_c_body.png", "livery": "res://graphics/player/player_ship_c_livery.png", "engine": "res://graphics/player/player_ship_c_engines.png", "engines": [Vector2(-2, 7), Vector2(2, 7)]},
]

const NATIVE_W := 480.0
const NATIVE_H := 270.0
const SHIP_X := NATIVE_W / 2.0      # 240 — native viewport centre
const HD_SCALE := 4.0
const HD_W := 1920.0
const HD_H := 1080.0
const GUTTER_HD := PF.X_MIN * HD_SCALE   # 528 — left panel / mask right edge
const RIGHT_HD := PF.X_MAX * HD_SCALE     # 1392 — right panel / mask left edge
const BAR_H := 150.0                # HD height of the top money bar / bottom action bar
const FLYOFF_TARGET_Y := -120.0    # off the top edge, same as _run_outro

const ARM_SLOTS := ["PRIMARY", "SECONDARY", "SUPER"]
const SYS_SLOTS := ["MODULE_1", "MODULE_2", "MODULE_3"]

signal landed
signal departed
signal depart_requested   # bottom-bar Depart pressed (caller may intercept; default → depart())

enum State { ARRIVING, LANDED, DEPARTING, GONE }
enum ShopMode { NONE, SCRAP, SELL }

# ---- Identity (set before add_child; -1/false = read from Run) ----
@export var ship_variant: int = -1
@export var livery_color: Color = Color(0.90, 0.16, 0.16)
@export var livery_set: bool = false
@export var outpost_name: String = ""
@export var manage_hd_scope: bool = true
@export var damage_level: float = 0.0   # 0 = pristine, 1 = near-wreck; drives shader + tells

# ---- Tuning knobs (the dev lab drives these; defaults are the shipped feel) ----
@export var arrival_time: float = 3.0       # slow decelerating fly-in (s)
@export var start_y: float = 330.0          # native-Y below the screen the ship starts at
@export var land_y: float = 151.0           # native-Y the ship sets down at
@export var idle_bob: float = 0.0           # hover bob amplitude once landed (px; 0 = dead-static)
@export var idle_bob_period: float = 2.6
# Engine exhaust drifts ZERO here: unlike combat (world scrolls past a hovering ship), the
# dock ship ACTUALLY moves — the trail streaks off real motion, idles to nothing when static.
@export var engine_drift: float = 0.0
@export var engine_spool: float = 1.5       # engine glow power-down (landing) / spool-up (liftoff) fade (s)
# Drop shadow — offset/scale while descending ("high") vs landed ("tight").
@export var shadow_fly_offset: Vector2 = Vector2(4.0, 8.0)
@export var shadow_land_offset: Vector2 = Vector2(1.0, 2.5)
@export var shadow_fly_scale: float = 0.9
@export var shadow_land_scale: float = 1.0
@export var shadow_fly_alpha: float = 0.4
@export var shadow_land_alpha: float = 0.9
@export var shadow_settle_time: float = 1.0
# Reveal / exit timing.
@export var bars_fade_time: float = 0.3
@export var rise_time: float = 1.0
@export var flyoff_time: float = 1.0

var _hd: HdViewportScope = null
var _world: SubViewport = null
var _ship: Node2D = null
var _body: Sprite2D = null
var _shadow: Sprite2D = null
var _engine_glow: Sprite2D = null
var _trail: EngineTrailFx = null
var _smoke = null              # DamageSmokeTrail
var _sparks: Array = []        # spark trail instances (one per engine marker)
var _damage_mat: ShaderMaterial = null
var _engine_on: bool = false
var _pad: Node2D = null
var _sparks_on: bool = false
var _spark_t: float = 0.0          # countdown to the next landed puff
var _spark_burst_t: float = 0.0    # remaining emit time of the active puff
var _spray_t: float = 0.0          # remaining time of a damaged spool-up spray
var _engine_lights: Array = []     # blue PointLight2D per engine marker
var _spark_lights: Array = []      # orange PointLight2D per engine marker
var _light_tex: Texture2D = null

var _state: int = State.ARRIVING
var _t: float = 0.0
var _shadow_offset: Vector2 = Vector2.ZERO   # tweened; applied to the shadow each frame
var _shadow_scale: float = 1.0               # tweened
var _phase_tween: Tween = null
var _glow_tween: Tween = null
var _ui_tween: Tween = null

# Inventory mock (local model — see file header).
var _slots: Dictionary = {}
var _hold: Array = []
var _shift_mode: String = "Focus"
var _money: int = 0
var _materials: int = 0
var _shop_mode: int = ShopMode.NONE
var _market: Array = []            # market entries (item dicts; sold ones carry ["buyback"]=true)
var _left_tabs: TabContainer = null

# UI refs.
var _left_panel: Control = null
var _right_panel: Control = null
var _top_bar: Control = null
var _bottom_bar: Control = null
var _left_mask: ColorRect = null
var _right_mask: ColorRect = null
var _money_lbl: Label = null
var _parts_lbl: Label = null
var _toast_lbl: Label = null
var _toast_tween: Tween = null
var _info_popup: Control = null
var _page_market: VBoxContainer = null
var _page_services: VBoxContainer = null
var _page_armaments: VBoxContainer = null
var _page_systems: VBoxContainer = null
var _page_hold: VBoxContainer = null
var _built: bool = false


func _ready() -> void:
	if manage_hd_scope:
		_hd = HdScreen.enter(self)
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resolve_identity()
	_init_inventory()
	_world = HdScreen.make_play_subviewport(self)
	_build_world_background()
	_build_landing_pad()
	_build_ship()
	# Menu Controls (under the masks) then the masks on top.
	_build_left_panel()
	_build_right_panel()
	_build_top_bar()
	_build_bottom_bar()
	_build_masks()
	_build_toast()
	_built = true
	begin_arrival()
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_world, "Outpost Arrival")


func _resolve_identity() -> void:
	var run := get_node_or_null("/root/Run")
	if ship_variant < 0:
		ship_variant = int(run.ship_variant) if run != null and "ship_variant" in run else 0
	ship_variant = clampi(ship_variant, 0, VARIANTS.size() - 1)
	if not livery_set and run != null and "livery_chosen" in run and bool(run.livery_chosen):
		livery_color = run.livery_color
	if outpost_name.is_empty():
		outpost_name = _default_outpost_name(run)


func _default_outpost_name(run: Node) -> String:
	var seed_value: int = 0
	if run != null and "run_seed" in run:
		seed_value = int(run.run_seed) ^ abs(hash(String(run.current_node_id)))
	else:
		seed_value = randi()
	return SectorNameGenerator.generate(seed_value)


func _init_inventory() -> void:
	_money = _run_int("bounty", 1250)
	_materials = _run_int("materials", 8)
	_slots = {
		"PRIMARY": _mk_item("Twin Cannon", "PRIMARY", 3, 40, "Rapid dual-bolt cannon. Mk scales fire-rate + damage."),
		"SECONDARY": _mk_item("Seeker Missiles", "SECONDARY", 2, 30, "Homing missile pod. Mk adds salvo size + tracking."),
		"SUPER": _mk_item("Smart Bomb", "SUPER", 1, 60, "Screen-clearing blast. Mk adds charges + radius."),
		"MODULE_1": _mk_item("Shield Core", "MODULE", 2, 50, "Adds shield charges. Mk raises the charge pool."),
		"MODULE_2": _mk_item("Thrusters", "MODULE", 1, 35, "Raises move speed. Mk sharpens handling."),
		"MODULE_3": null,
	}
	_hold = [
		_mk_item("Reinforced Hull", "MODULE", 4, 55, "Adds hull pips. Mk raises max hull."),
		_mk_item("Spread Cannon", "PRIMARY", 2, 40, "Wide pellet spread. Mk widens the cone + damage."),
		_mk_item("Repair Drone", "MODULE", 1, 25, "Slow passive hull repair between waves."),
	]
	_market = _base_offers()


func _mk_item(nm: String, kind: String, mark: int, scrap: int, desc: String) -> Dictionary:
	return {"name": nm, "kind": kind, "mark": mark, "max_mark": 9, "scrap": scrap, "locked": false, "desc": desc}


# ---- World build (native 480 SubViewport) ---------------------------------

func _build_world_background() -> void:
	var bg := Polygon2D.new()
	bg.name = "BayFloor"
	bg.polygon = PackedVector2Array([Vector2(0, 0), Vector2(NATIVE_W, 0), Vector2(NATIVE_W, NATIVE_H), Vector2(0, NATIVE_H)])
	bg.color = Color(0.035, 0.045, 0.07, 1.0)
	bg.z_index = -10
	_world.add_child(bg)


func _build_landing_pad() -> void:
	var pad := Node2D.new()
	pad.name = "LandingPad"
	pad.z_index = -3
	var hw := 30.0
	var hh := 20.0
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	fill.color = Color(0.10, 0.12, 0.17, 1.0)
	pad.add_child(fill)
	var grid_col := Color(UiTheme.COLOR_ACCENT_DIM.r, UiTheme.COLOR_ACCENT_DIM.g, UiTheme.COLOR_ACCENT_DIM.b, 0.35)
	for gx in [-hw / 3.0, hw / 3.0]:
		pad.add_child(_pad_line(Vector2(gx, -hh), Vector2(gx, hh), grid_col, 1.0))
	for gy in [-hh / 3.0, hh / 3.0]:
		pad.add_child(_pad_line(Vector2(-hw, gy), Vector2(hw, gy), grid_col, 1.0))
	var border := Line2D.new()
	border.points = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh)])
	border.width = 1.0
	border.default_color = Color(UiTheme.COLOR_ACCENT.r, UiTheme.COLOR_ACCENT.g, UiTheme.COLOR_ACCENT.b, 0.6)
	pad.add_child(border)
	_world.add_child(pad)
	_pad = pad
	_position_pad()


func _pad_line(a: Vector2, b: Vector2, col: Color, w: float) -> Line2D:
	var l := Line2D.new()
	l.points = PackedVector2Array([a, b])
	l.width = w
	l.default_color = col
	return l


func _position_pad() -> void:
	if _pad != null and is_instance_valid(_pad):
		_pad.position = Vector2(SHIP_X, land_y + 14.0)


func _build_ship() -> void:
	var host := Node2D.new()
	host.name = "DockShip"
	var data: Dictionary = VARIANTS[clampi(ship_variant, 0, VARIANTS.size() - 1)]
	_body = _make_layer(String(data["body"]), Color.WHITE, false)
	host.add_child(_body)
	host.add_child(_make_layer(String(data["livery"]), livery_color, false))
	_engine_glow = _make_layer(String(data["engine"]), ENGINE_GLOW_COLOR, true)
	host.add_child(_engine_glow)
	# Engine markers — one per real nozzle of THIS body (A: 1, B/C: 2). Roman 2026-06-19.
	var markers: Array = []
	for i in (data["engines"] as Array).size():
		var mk := Marker2D.new()
		mk.name = "Engine%d" % i
		mk.position = data["engines"][i]
		host.add_child(mk)
		markers.append(mk)
	_world.add_child(host)
	host.position = Vector2(SHIP_X, start_y)
	_ship = host

	# Damage-overlay shader on the body (mirrors player._install_damage_material).
	_install_damage_material()

	# Drop shadow: a black silhouette of the body cell, behind the ship, animated to fake height.
	var shadow := Sprite2D.new()
	shadow.name = "DropShadow"
	shadow.texture = load(String(data["body"]))
	shadow.hframes = 3
	shadow.frame = 1
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.modulate = Color(0.0, 0.0, 0.0, shadow_fly_alpha)
	shadow.z_index = -2
	_world.add_child(shadow)
	_shadow = shadow

	# Engine streak — one Line2D trail per marker (engine_trail_fx handles plural markers).
	var trail := EngineTrailFx.new()
	host.add_child(trail)
	trail.setup(host, markers, ENGINE_GLOW_COLOR, engine_drift)
	_trail = trail

	# Damage tells: sparks at every nozzle (replacing the engine-torch flames), one smoke
	# column from the primary nozzle. Both driven by damage_level + engine state.
	_sparks.clear()
	for mk in markers:
		_attach_spark(mk.position)
	_attach_smoke(markers[0].position)
	# Point lights: blue engine light + orange spark light at each nozzle.
	_build_engine_lights(markers)
	_apply_damage()


func _make_layer(path: String, tint: Color, additive: bool) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.hframes = 3
	spr.frame = 1
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.modulate = tint
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		spr.material = m
	return spr


# Mirrors scripts/game/player.gd::_install_damage_material — the health-driven fray overlay.
func _install_damage_material() -> void:
	if _body == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = DamageOverlayShader
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", _DamageNoiseTex)
	mat.set_shader_parameter("edge_distance_map", _DamageEdgeTex)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	mat.set_shader_parameter("max_strength", 0.9)
	mat.set_shader_parameter("edge_bias_strength", 0.3)
	mat.set_shader_parameter("details_opacity", 0.1)
	mat.set_shader_parameter("edge_color", Color("494e55"))
	mat.set_shader_parameter("details_color", Color("cacaca"))
	_body.material = mat
	_damage_mat = mat


func _attach_spark(pos: Vector2) -> void:
	var inst = SparkTrailFx.spawn(_ship, pos)
	if inst == null:
		return
	var p = SparkTrailFx.particles(inst)
	if p != null:
		# Dupe the process material so the downward drift only touches THIS spark (the scene
		# resource is shared). Mirrors spark_trail_fx.attach_to_player.
		if p.process_material != null:
			p.process_material = p.process_material.duplicate()
			var pm := p.process_material as ParticleProcessMaterial
			if pm != null:
				pm.gravity = Vector3(0.0, SPARK_GRAVITY, 0.0)
				pm.radial_velocity_min = 0.0
				pm.radial_velocity_max = SPARK_RADIAL_VEL   # slower sparks
		p.lifetime = SPARK_LIFETIME                         # shorter-lived
		p.trail_lifetime = SPARK_TRAIL_LIFETIME             # shorter ribbons
		p.amount = mini(p.amount, 60)
		p.emitting = false
	_sparks.append(inst)


# Soft radial light texture (white centre → transparent), shared by all the point lights.
func _make_light_texture() -> Texture2D:
	if _light_tex != null:
		return _light_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_light_tex = t
	return t


func _build_engine_lights(markers: Array) -> void:
	_engine_lights.clear()
	_spark_lights.clear()
	var tex := _make_light_texture()
	for mk in markers:
		var el := _make_point_light(mk.position, ENGINE_LIGHT_COLOR, ENGINE_LIGHT_SCALE, tex)
		_ship.add_child(el)
		_engine_lights.append(el)
		var sl := _make_point_light(mk.position, SPARK_LIGHT_COLOR, SPARK_LIGHT_SCALE, tex)
		_ship.add_child(sl)
		_spark_lights.append(sl)


func _make_point_light(pos: Vector2, col: Color, scale: float, tex: Texture2D) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.color = col
	l.energy = 0.0
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.shadow_enabled = false
	l.position = pos
	return l


func _attach_smoke(pos: Vector2) -> void:
	var s = DamageSmokeTrail.new()
	s.emit_local = pos
	s.activate_below = TELL_ACTIVATE
	_ship.add_child(s)
	# set_player keeps its host reference valid (so its world-space line is positioned and not
	# faded out). The host has no hull_changed signal — we drive its level via _drive_smoke().
	s.set_player(_ship)
	_smoke = s


func _teardown_ship_fx() -> void:
	if _smoke != null and is_instance_valid(_smoke):
		_smoke.queue_free()
	_smoke = null
	for inst in _sparks:
		if is_instance_valid(inst):
			inst.queue_free()
	_sparks.clear()
	_engine_lights.clear()   # the PointLight2Ds are ship children, freed with it
	_spark_lights.clear()
	# The smoke's world-space Line2D lives under _world independently of its node — sweep it.
	if _world != null and is_instance_valid(_world):
		for c in _world.get_children():
			if c is Line2D and String(c.name).begins_with("DamageTrailLine"):
				c.queue_free()


# ---- Damage driving -------------------------------------------------------

# Re-evaluate shader + smoke for the current damage_level. Sparks are timed in _update_sparks
# (they read damage_level live each frame), so they self-heal when the level drops on repair.
func _apply_damage() -> void:
	if _damage_mat != null:
		_damage_mat.set_shader_parameter("sensitivity", clampf(0.6 * damage_level, 0.0, 0.6))
	_drive_smoke()


# Smoke emits only while the engine runs AND the ship is damaged — so it STOPS on landing.
func _drive_smoke() -> void:
	if _smoke == null or not is_instance_valid(_smoke):
		return
	var emit: bool = _engine_on and damage_level >= TELL_ACTIVATE
	var eff: float = damage_level if emit else 0.0
	_smoke._on_hull_changed(100, int(round(100.0 * (1.0 - eff))))


# Sparks (the flame replacement). While the ship MOVES they trail continuously; once LANDED
# they crackle in intermittent puffs whose density + frequency scale with damage. Driven per
# frame from _process so a repair (damage_level → 0) tapers them out live. Roman 2026-06-19.
func _update_sparks(delta: float) -> void:
	if _sparks.is_empty():
		return
	# A timed spool-up spray (damaged launch) takes priority — a short startup burst, then off.
	if _spray_t > 0.0:
		_spray_t -= delta
		if _spray_t <= 0.0:
			_set_sparks_emitting(false)
		return
	# Ambient sparks only while ARRIVING or LANDED + damaged (no trail during departure).
	if (_state != State.ARRIVING and _state != State.LANDED) or damage_level < TELL_ACTIVATE:
		if _sparks_on:
			_set_sparks_emitting(false)
		return
	if _state == State.LANDED:
		# Intermittent puffs — interval + density scale with damage. Roman 2026-06-20.
		if _sparks_on:
			_spark_burst_t -= delta
			if _spark_burst_t <= 0.0:
				_set_sparks_emitting(false)
		else:
			_spark_t -= delta
			if _spark_t <= 0.0:
				_begin_spark_burst()
	elif not _sparks_on:
		# Arriving: a continuous trail off the engines (the motion streaks it).
		_set_spark_amount(_spark_amount_for_damage())
		_set_sparks_emitting(true)


# Drive the point lights: blue engine lights track the engine glow brightness (so they fade
# out on landing + stutter on a damaged spool-up); orange spark lights flash on each puff.
func _update_lights(delta: float) -> void:
	var glow_ratio: float = 0.0
	if _engine_glow != null and is_instance_valid(_engine_glow):
		glow_ratio = clampf(_engine_glow.modulate.b / maxf(ENGINE_GLOW_COLOR.b, 0.001), 0.0, 1.0)
	for l in _engine_lights:
		if is_instance_valid(l):
			l.energy = glow_ratio * ENGINE_LIGHT_ENERGY
	var spark_target: float = SPARK_LIGHT_ENERGY if _sparks_on else 0.0
	for l in _spark_lights:
		if is_instance_valid(l):
			l.energy = move_toward(l.energy, spark_target, SPARK_LIGHT_RATE * delta)


func _begin_spark_burst() -> void:
	_set_spark_amount(_spark_amount_for_damage())
	_set_sparks_emitting(true)
	_spark_burst_t = SPARK_BURST_DUR
	_spark_t = _spark_interval()


# Emphatic spark spray off the engine(s) when a damaged ship fights to spool up — a ~0.5s
# startup burst (gated by _spray_t in _update_sparks), not a trail through the whole launch.
func _spool_spray() -> void:
	_set_spark_amount(SPARK_SPRAY_AMOUNT)
	_set_sparks_emitting(true)
	_spray_t = SPARK_SPRAY_DUR


func _set_sparks_emitting(on: bool) -> void:
	_sparks_on = on
	for inst in _sparks:
		var p = SparkTrailFx.particles(inst)
		if p != null:
			p.emitting = on


func _set_spark_amount(amt: int) -> void:
	for inst in _sparks:
		var p = SparkTrailFx.particles(inst)
		if p != null:
			p.amount = maxi(1, amt)


func _damage_norm() -> float:
	return clampf((damage_level - TELL_ACTIVATE) / (1.0 - TELL_ACTIVATE), 0.0, 1.0)


func _spark_amount_for_damage() -> int:
	return int(round(lerpf(float(SPARK_AMOUNT_LIGHT), float(SPARK_AMOUNT_HEAVY), _damage_norm())))


func _spark_interval() -> float:
	return lerpf(SPARK_INTERVAL_LIGHT, SPARK_INTERVAL_HEAVY, _damage_norm())


# Stutter the engine glow up (a damaged ship catching) over `dur`, ending at full brightness.
func _start_glow_stutter(dur: float) -> Tween:
	var steps := 6
	var sd: float = maxf(dur, 0.05) / float(steps)
	var tw := create_tween()
	for i in range(steps):
		if i == steps - 1:
			tw.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR, sd)   # settle to full
		elif i % 2 == 0:
			var frac: float = float(i + 1) / float(steps)
			tw.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR * lerpf(0.4, 0.9, frac), sd)
		else:
			tw.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR * 0.12, sd)   # flicker-dim
	return tw


# Toggle the engine: the blue streak + smoke follow it; the glow is tweened separately.
func _set_engine_active(on: bool) -> void:
	_engine_on = on
	if _trail != null and is_instance_valid(_trail):
		_trail.set_emitting(on)
	_drive_smoke()


# ---- HD menu build --------------------------------------------------------

# All anchors 0 → offsets are absolute HD coords (the root is exactly 1920×1080).
func _set_rect(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _panel(l: float, t: float, r: float, b: float, tint: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	_set_rect(p, l, t, r, b)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _tab_container() -> TabContainer:
	var tc := TabContainer.new()
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tc.add_theme_font_override("font", UiTheme.menu_font())
	tc.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	return tc


# A scrollable tab page; the ScrollContainer's name becomes the tab title.
func _add_page(tc: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	tc.add_child(scroll)
	return v


func _build_left_panel() -> void:
	var p := _panel(0.0, 0.0, GUTTER_HD, HD_H, Color(0.07, 0.05, 0.06, 0.92))
	_left_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_header("TRADE POST"))
	var tc := _tab_container()
	_left_tabs = tc
	_page_market = _add_page(tc, "MARKET")
	_page_services = _add_page(tc, "SERVICES")
	v.add_child(tc)
	# Swapping back to the part market ends scrap/sell mode.
	tc.tab_changed.connect(func(idx: int) -> void:
		if idx == 0:
			_set_shop_mode(ShopMode.NONE))
	_rebuild_market()
	_rebuild_services()


func _build_right_panel() -> void:
	var p := _panel(RIGHT_HD, 0.0, HD_W, HD_H, Color(0.05, 0.06, 0.09, 0.92))
	_right_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_header("SHIP STATUS"))
	var tc := _tab_container()
	_page_armaments = _add_page(tc, "ARMAMENTS")
	_page_systems = _add_page(tc, "SYSTEMS")
	_page_hold = _add_page(tc, "HOLD")
	v.add_child(tc)
	_rebuild_inventory()


func _build_top_bar() -> void:
	var p := _panel(GUTTER_HD, 0.0, RIGHT_HD, BAR_H, Color(0.06, 0.05, 0.10, 0.88))
	_top_bar = p
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var name_lbl := _label(outpost_name.to_upper(), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	v.add_child(row)
	_money_lbl = _label("₵ %d" % _money, UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_BOUNTY)
	row.add_child(_money_lbl)
	_parts_lbl = _label("◆ %d" % _materials, UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_GREEN)
	row.add_child(_parts_lbl)


func _build_bottom_bar() -> void:
	var p := _panel(GUTTER_HD, HD_H - BAR_H, RIGHT_HD, HD_H, Color(0.05, 0.07, 0.06, 0.88))
	_bottom_bar = p
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(row)
	var depart := UiTheme.make_button("DEPART")
	depart.custom_minimum_size = Vector2(220, 60)
	depart.pressed.connect(_on_depart_pressed)
	row.add_child(depart)
	var options := UiTheme.make_button("OPTIONS", true)
	options.custom_minimum_size = Vector2(180, 60)
	options.pressed.connect(func() -> void: toast("Options (stub)"))
	row.add_child(options)
	var code := UiTheme.make_button("CODE", true)
	code.custom_minimum_size = Vector2(160, 60)
	code.pressed.connect(func() -> void: toast("Enter Code (stub)"))
	row.add_child(code)


func _build_masks() -> void:
	_left_mask = _mask(0.0, 0.0, GUTTER_HD, HD_H)
	_right_mask = _mask(RIGHT_HD, 0.0, HD_W, HD_H)


func _mask(l: float, t: float, r: float, b: float) -> ColorRect:
	var m := ColorRect.new()
	m.color = Color(0, 0, 0, 1)
	_set_rect(m, l, t, r, b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block the panel beneath when faded
	add_child(m)
	return m


func _build_toast() -> void:
	_toast_lbl = _label("", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_ACCENT)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(_toast_lbl, GUTTER_HD, HD_H - BAR_H - 64.0, RIGHT_HD, HD_H - BAR_H - 24.0)
	_toast_lbl.modulate.a = 0.0
	_toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_lbl)


# ---- Left panel: market + services ----------------------------------------

func _rebuild_market() -> void:
	if _page_market == null:
		return
	_clear(_page_market)
	_page_market.add_child(_caption("Buy parts → hold (sold parts list here for buyback)"))
	if _market.is_empty():
		_page_market.add_child(_label("(stock cleared)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_DISABLED))
	for entry in _market:
		_page_market.add_child(_market_card(entry))
	_page_market.add_child(_spacer())


func _base_offers() -> Array:
	return [
		_mk_item("Heavy Cannon", "PRIMARY", 3, 50, "High-damage slow cannon. Mk adds pierce."),
		_mk_item("Flak Pod", "SECONDARY", 2, 35, "Short-range flak burst. Mk widens the burst."),
		_mk_item("Overcharge", "SUPER", 1, 70, "Brief fire-rate surge. Mk extends duration."),
		_mk_item("Plating", "MODULE", 2, 45, "Flat damage reduction. Mk raises the cut."),
	]


# A market entry. Normal stock → BUY at full price; a sold part (buyback flag) → BUYBACK at
# the 20% it sold for, until the player departs (then it rises to full price).
func _market_card(entry: Dictionary) -> PanelContainer:
	var card := _card_frame()
	var v: VBoxContainer = card.get_child(0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var nm := _label("%s · Mk.%d" % [entry["name"], int(entry["mark"])], UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var is_bb: bool = bool(entry.get("buyback", false))
	var price: int = _sell_price(entry) if is_bb else _item_value(entry)
	row.add_child(_label("₵%d" % price, UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_BOUNTY))
	var btn := UiTheme.make_button("BUYBACK" if is_bb else "BUY", true)
	btn.pressed.connect(func() -> void: _buy_market(entry))
	row.add_child(btn)
	v.add_child(row)
	if is_bb:
		v.add_child(_label("· sold — buyback until you depart", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	return card


func _buy_market(entry: Dictionary) -> void:
	var is_bb: bool = bool(entry.get("buyback", false))
	var price: int = _sell_price(entry) if is_bb else _item_value(entry)
	if _money < price:
		toast("Not enough ₵")
		return
	_money -= price
	_market.erase(entry)
	var item := entry.duplicate()
	item.erase("buyback")
	_hold.append(item)
	toast("%s %s → hold" % ["Bought back" if is_bb else "Bought", entry["name"]])
	_update_money_parts()
	_rebuild_market()
	_rebuild_hold()


func _item_value(item: Dictionary) -> int:
	return 80 + int(item["mark"]) * 80


func _sell_price(item: Dictionary) -> int:
	return int(round(0.2 * float(_item_value(item))))


func _rebuild_services() -> void:
	if _page_services == null:
		return
	_clear(_page_services)
	_page_services.add_child(_caption("Repair, rearm and upgrade"))
	# Repair clears battle damage — the shader fray + sparks heal LIVE (driven, never baked).
	_page_services.add_child(_service_row("Repair Hull", 250, _do_repair))
	_page_services.add_child(_service_row("Refill MG Ammo", 120, func() -> void: toast("Refilled MG ammo (stub)")))
	_page_services.add_child(_service_row("Refill Super", 120, func() -> void: toast("Refilled super (stub)")))
	_page_services.add_child(HSeparator.new())
	_page_services.add_child(_label("PART HANDLING", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	# Scrap / Sell put the shop in a mode that retargets the owned-part action buttons.
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	var scrap_btn := UiTheme.make_button("Scrap Parts", true)
	if _shop_mode == ShopMode.SCRAP:
		scrap_btn.add_theme_color_override("font_color", UiTheme.COLOR_DANGER)
	scrap_btn.pressed.connect(func() -> void: _toggle_shop_mode(ShopMode.SCRAP))
	modes.add_child(scrap_btn)
	var sell_btn := UiTheme.make_button("Sell Parts", true)
	if _shop_mode == ShopMode.SELL:
		sell_btn.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	sell_btn.pressed.connect(func() -> void: _toggle_shop_mode(ShopMode.SELL))
	modes.add_child(sell_btn)
	_page_services.add_child(modes)
	if _shop_mode == ShopMode.SCRAP:
		_page_services.add_child(_label("SCRAP MODE — tap an owned part to break it for ◆ materials.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_DANGER))
	elif _shop_mode == ShopMode.SELL:
		_page_services.add_child(_label("SELL MODE — tap an owned part to sell for 20% ₵ (buyable back until you depart).", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_BOUNTY))
	_page_services.add_child(_spacer())


func _toggle_shop_mode(mode: int) -> void:
	_set_shop_mode(ShopMode.NONE if _shop_mode == mode else mode)


func _set_shop_mode(mode: int) -> void:
	if _shop_mode == mode:
		return
	_shop_mode = mode
	_rebuild_services()
	_rebuild_inventory()


# Departing for a node ends buyback: any sold parts still listed rise back to full price.
func _complete_node_shop() -> void:
	for e in _market:
		if bool(e.get("buyback", false)):
			e.erase("buyback")
	_rebuild_market()


func _service_row(title: String, cost: int, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var nm := _label(title, UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var b := UiTheme.make_button("₵%d" % cost, true)
	b.pressed.connect(cb)
	row.add_child(b)
	return row


# Demonstrates live damage removal: pay, then heal damage_level → 0. Because the overlay is
# driven (not baked) the fray recedes + the sparks/smoke taper out as the level falls.
func _do_repair() -> void:
	if damage_level <= 0.01:
		toast("Hull already pristine")
		return
	if _money < 250:
		toast("Not enough ₵")
		return
	_money -= 250
	_update_money_parts()
	repair()
	toast("Hull repaired — damage clearing")


# ---- Right panel: armaments / systems / hold ------------------------------

func _rebuild_inventory() -> void:
	_rebuild_armaments()
	_rebuild_systems()
	_rebuild_hold()


func _rebuild_armaments() -> void:
	if _page_armaments == null:
		return
	_clear(_page_armaments)
	_page_armaments.add_child(_caption("Installed weapons + super"))
	for sid in ARM_SLOTS:
		_page_armaments.add_child(_slot_card(sid))
	_page_armaments.add_child(_spacer())


func _rebuild_systems() -> void:
	if _page_systems == null:
		return
	_clear(_page_systems)
	_page_systems.add_child(_caption("Installed modules + shift mode"))
	for sid in SYS_SLOTS:
		_page_systems.add_child(_slot_card(sid))
	_page_systems.add_child(_shift_mode_row())
	_page_systems.add_child(_spacer())


func _rebuild_hold() -> void:
	if _page_hold == null:
		return
	_clear(_page_hold)
	_page_hold.add_child(_caption("Carried, unslotted — %d items" % _hold.size()))
	if _hold.is_empty():
		_page_hold.add_child(_label("(hold empty)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_DISABLED))
	for i in _hold.size():
		_page_hold.add_child(_hold_card(i))
	_page_hold.add_child(_spacer())


# Installed-slot card: Info + Pull (or just the slot name if empty).
func _slot_card(sid: String) -> PanelContainer:
	var item = _slots.get(sid)
	var card := _card_frame()
	var v: VBoxContainer = card.get_child(0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_label(_slot_label(sid), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var nm := _label(String(item["name"]) if item != null else "(empty)", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT if item != null else UiTheme.COLOR_DISABLED)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if item != null:
		top.add_child(_label("Mk.%d" % int(item["mark"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_ACCENT))
	v.add_child(top)
	if item != null:
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		btns.add_child(_mini_btn("Info", func() -> void: _show_info(item)))
		# The mode retargets the action: Pull (default) / Scrap / Sell. Installed parts are unlocked.
		match _shop_mode:
			ShopMode.SCRAP:
				btns.add_child(_mini_btn("Scrap (+%d)" % int(item["scrap"]), func() -> void: _scrap_slot(sid)))
			ShopMode.SELL:
				btns.add_child(_mini_btn("Sell (+%d)" % _sell_price(item), func() -> void: _sell_slot(sid)))
			_:
				btns.add_child(_mini_btn("Pull", func() -> void: _pull(sid)))
		v.add_child(btns)
	return card


# Hold card: Info + variable Slot/Swap + Scrap(+N) + Lock toggle.
func _hold_card(idx: int) -> PanelContainer:
	var item = _hold[idx]
	var card := _card_frame()
	var v: VBoxContainer = card.get_child(0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var nm := _label(String(item["name"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(_label("%s · Mk.%d" % [item["kind"], int(item["mark"])], UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	v.add_child(top)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.add_child(_mini_btn("Info", func() -> void: _show_info(item)))
	var locked: bool = bool(item["locked"])
	# Scrap/Sell modes retarget the action (only for unlocked parts); default = Slot/Swap.
	match _shop_mode:
		ShopMode.SCRAP:
			if not locked:
				btns.add_child(_mini_btn("Scrap (+%d)" % int(item["scrap"]), func() -> void: _scrap_hold(idx)))
		ShopMode.SELL:
			if not locked:
				btns.add_child(_mini_btn("Sell (+%d)" % _sell_price(item), func() -> void: _sell_hold(idx)))
		_:
			var empty := _empty_target(String(item["kind"]))
			if empty != "":
				btns.add_child(_mini_btn("Slot", func() -> void: _slot_from_hold(idx, empty)))
			else:
				btns.add_child(_mini_btn("Swap", func() -> void: _swap_from_hold(idx)))
	var lock_btn := _mini_btn("Locked" if locked else "Lock", func() -> void: _toggle_lock(idx))
	if locked:
		lock_btn.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	btns.add_child(lock_btn)
	v.add_child(btns)
	return card


func _shift_mode_row() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label("SHIFT MODE", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	for m in ["Focus", "Phase", "Hyper"]:
		var b := UiTheme.make_button(m, true)
		if m == _shift_mode:
			b.add_theme_color_override("font_color", UiTheme.COLOR_GREEN)
		b.pressed.connect(func() -> void:
			_shift_mode = m
			_rebuild_systems()
			toast("Shift → %s" % m))
		modes.add_child(b)
	box.add_child(modes)
	return box


# ---- Inventory actions ----------------------------------------------------

func _pull(sid: String) -> void:
	var item = _slots.get(sid)
	if item == null:
		return
	_hold.append(item)
	_slots[sid] = null
	toast("Pulled %s to hold" % item["name"])
	_rebuild_inventory()


func _slot_from_hold(idx: int, sid: String) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var nm = _hold[idx]["name"]
	_slots[sid] = _hold[idx]
	_hold.remove_at(idx)
	toast("Slotted %s → %s" % [nm, _slot_label(sid)])
	_rebuild_inventory()


func _swap_from_hold(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var item = _hold[idx]
	var sid: String = _target_slots(String(item["kind"]))[0]
	var old = _slots.get(sid)
	_slots[sid] = item
	_hold[idx] = old   # the displaced part drops into the same hold slot
	toast("Swapped into %s" % _slot_label(sid))
	_rebuild_inventory()


func _scrap_hold(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var item = _hold[idx]
	if bool(item["locked"]):
		toast("%s is locked" % item["name"])
		return
	_materials += int(item["scrap"])
	_hold.remove_at(idx)
	toast("Scrapped %s  (+%d ◆)" % [item["name"], int(item["scrap"])])
	_update_money_parts()
	_rebuild_hold()


func _scrap_slot(sid: String) -> void:
	var item = _slots.get(sid)
	if item == null:
		return
	_materials += int(item["scrap"])
	_slots[sid] = null
	toast("Scrapped %s  (+%d ◆)" % [item["name"], int(item["scrap"])])
	_update_money_parts()
	_rebuild_inventory()


func _sell_hold(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var item = _hold[idx]
	if bool(item["locked"]):
		toast("%s is locked" % item["name"])
		return
	_hold.remove_at(idx)
	_complete_sale(item)
	_rebuild_hold()


func _sell_slot(sid: String) -> void:
	var item = _slots.get(sid)
	if item == null:
		return
	_slots[sid] = null
	_complete_sale(item)
	_rebuild_inventory()


# Sell at 20% of value → money; the part lists in the market for buyback (until departure).
func _complete_sale(item: Dictionary) -> void:
	var gain: int = _sell_price(item)
	_money += gain
	var listed := item.duplicate()
	listed["locked"] = false
	listed["buyback"] = true
	_market.append(listed)
	toast("Sold %s  (+%d ₵)" % [item["name"], gain])
	_update_money_parts()
	_rebuild_market()


func _toggle_lock(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	_hold[idx]["locked"] = not bool(_hold[idx]["locked"])
	_rebuild_hold()


func _target_slots(kind: String) -> Array:
	if kind == "MODULE":
		return SYS_SLOTS
	return [kind]   # PRIMARY / SECONDARY / SUPER map to the same-named slot


func _empty_target(kind: String) -> String:
	for sid in _target_slots(kind):
		if _slots.get(sid) == null:
			return sid
	return ""


func _slot_label(sid: String) -> String:
	match sid:
		"PRIMARY": return "PRIMARY"
		"SECONDARY": return "SECONDARY"
		"SUPER": return "SUPER"
		"MODULE_1": return "MODULE 1"
		"MODULE_2": return "MODULE 2"
		"MODULE_3": return "MODULE 3"
	return sid


func _update_money_parts() -> void:
	if _money_lbl != null and is_instance_valid(_money_lbl):
		_money_lbl.text = "₵ %d" % _money
	if _parts_lbl != null and is_instance_valid(_parts_lbl):
		_parts_lbl.text = "◆ %d" % _materials


# ---- Info popup (codex entry) ---------------------------------------------

func _show_info(item: Dictionary) -> void:
	_close_info()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_info())
	add_child(dim)
	_info_popup = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.98)
	sb.border_color = UiTheme.COLOR_ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(760, 0)
	panel.add_child(v)
	v.add_child(_label(String(item["name"]), UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))
	v.add_child(_label("%s   ·   Mk.%d / %d" % [item["kind"], int(item["mark"]), int(item["max_mark"])], UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var desc := _label(String(item["desc"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_FAINT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(760, 0)
	v.add_child(desc)
	v.add_child(_label("MARK LEVELS  (current highlighted)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	v.add_child(_mark_ladder(int(item["mark"]), int(item["max_mark"])))
	v.add_child(_label("Scrap value:   ◆ %d" % int(item["scrap"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_GREEN))
	v.add_child(_label("Sell value:    ₵ %d   (20%% of ₵%d)" % [_sell_price(item), _item_value(item)], UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_BOUNTY))
	var close := UiTheme.make_button("Close")
	close.pressed.connect(_close_info)
	v.add_child(close)


func _mark_ladder(cur: int, mx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in range(1, mx + 1):
		var chip := Label.new()
		chip.text = str(i)
		chip.custom_minimum_size = Vector2(40, 40)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_font_override("font", UiTheme.menu_font())
		chip.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_CAPTION)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		if i == cur:
			sb.bg_color = UiTheme.COLOR_BOUNTY
			chip.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		elif i < cur:
			sb.bg_color = Color(UiTheme.COLOR_ACCENT_DIM.r, UiTheme.COLOR_ACCENT_DIM.g, UiTheme.COLOR_ACCENT_DIM.b, 0.55)
			chip.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
		else:
			sb.bg_color = Color(0, 0, 0, 0.35)
			chip.add_theme_color_override("font_color", UiTheme.COLOR_DISABLED)
		chip.add_theme_stylebox_override("normal", sb)
		row.add_child(chip)
	return row


func _close_info() -> void:
	if _info_popup != null and is_instance_valid(_info_popup):
		_info_popup.queue_free()
	_info_popup = null


# ---- Small UI helpers -----------------------------------------------------

func _card_frame() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.30)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	return card


func _mini_btn(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text, true)
	b.pressed.connect(cb)
	return b


func _header(text: String) -> Label:
	return _label(text, UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_ACCENT)


func _caption(text: String) -> Label:
	return _label(text, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _run_int(field: String, fallback: int) -> int:
	var run := get_node_or_null("/root/Run")
	if run != null and field in run:
		return int(run.get(field))
	return fallback


# ---- Sequence -------------------------------------------------------------

func _kill_phase_tween() -> void:
	for tw in [_phase_tween, _glow_tween, _ui_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_phase_tween = null
	_glow_tween = null
	_ui_tween = null


# ARRIVING: ship below the screen, engines lit, masks closed, menus hidden →
# decelerating fly-in to the pad. Idempotent reset (the lab's Replay).
func begin_arrival() -> void:
	if not _built:
		return
	_kill_phase_tween()
	_state = State.ARRIVING
	_t = 0.0
	_position_pad()
	_shadow_offset = shadow_fly_offset
	_shadow_scale = shadow_fly_scale
	if _shadow != null:
		_shadow.modulate.a = shadow_fly_alpha
	if _ship != null:
		_ship.position = Vector2(SHIP_X, start_y)
	if _engine_glow != null:
		_engine_glow.modulate = ENGINE_GLOW_COLOR
	_set_engine_active(true)
	# Reset spark scheduling (the continuous fly-in trail relights via _update_sparks).
	_set_sparks_emitting(false)
	_spark_t = 0.0
	_spark_burst_t = 0.0
	_spray_t = 0.0
	_apply_damage()
	# Masks closed, menus hidden.
	_set_alpha(_left_mask, 1.0)
	_set_alpha(_right_mask, 1.0)
	_set_alpha(_left_panel, 0.0)
	_set_alpha(_right_panel, 0.0)
	_set_alpha(_top_bar, 0.0)
	_set_alpha(_bottom_bar, 0.0)

	_phase_tween = create_tween()
	_phase_tween.tween_property(_ship, "position:y", land_y, arrival_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_callback(_on_landed)


# LANDED: settle the shadow tight, fade the gutter masks off the menus, THEN cut engines.
func _on_landed() -> void:
	_state = State.LANDED
	_t = 0.0
	# Engines stay LIT through the settle — they only cut once the ship has fully set down
	# (after the shadow converges), not the instant the descent ends. Roman 2026-06-19.
	_kill_phase_tween()
	_phase_tween = create_tween()
	_phase_tween.set_parallel(true)
	_phase_tween.tween_property(self, "_shadow_offset", shadow_land_offset, shadow_settle_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(self, "_shadow_scale", shadow_land_scale, shadow_settle_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(_shadow, "modulate:a", shadow_land_alpha, shadow_settle_time)
	_phase_tween.tween_property(_left_mask, "modulate:a", 0.0, bars_fade_time)
	_phase_tween.tween_property(_right_mask, "modulate:a", 0.0, bars_fade_time)
	_phase_tween.tween_property(_left_panel, "modulate:a", 1.0, bars_fade_time)
	_phase_tween.tween_property(_right_panel, "modulate:a", 1.0, bars_fade_time)
	_phase_tween.tween_property(_top_bar, "modulate:a", 1.0, bars_fade_time)
	_phase_tween.tween_property(_bottom_bar, "modulate:a", 1.0, bars_fade_time)
	# Fully set down → cut engines (streak + smoke stop) and power the glow down, THEN announce.
	_phase_tween.chain().tween_callback(_cut_engines)
	_phase_tween.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR * 0.18, engine_spool)
	_phase_tween.chain().tween_callback(func() -> void: emit_signal("landed"))


func _cut_engines() -> void:
	_set_engine_active(false)   # blue streak + smoke stop; sparks persist while damaged


func _on_depart_pressed() -> void:
	emit_signal("depart_requested")
	depart()


# DEPARTING: fade the menus, close the masks, relight engines, the ship rises (shadow
# spreads), then launches off the top. No-op unless landed.
func depart() -> void:
	if _state != State.LANDED:
		return
	_state = State.DEPARTING
	_kill_phase_tween()
	_close_info()
	_set_shop_mode(ShopMode.NONE)
	_complete_node_shop()   # heading to a node ends buyback (sold parts rise to full price)
	_set_engine_active(true)
	var damaged: bool = damage_level >= TELL_ACTIVATE

	# Menus retract (independent of the motion sequence).
	_ui_tween = create_tween()
	_ui_tween.set_parallel(true)
	_ui_tween.tween_property(_left_panel, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_right_panel, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_top_bar, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_bottom_bar, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_left_mask, "modulate:a", 1.0, bars_fade_time)
	_ui_tween.tween_property(_right_mask, "modulate:a", 1.0, bars_fade_time)

	# Engine spool (ship still static): a DAMAGED ship STUTTERS to life + sprays sparks off the
	# engine(s) before catching; a clean ship just fades the glow up smoothly. Roman 2026-06-19.
	if damaged:
		_spool_spray()
		_glow_tween = _start_glow_stutter(engine_spool)
	else:
		_glow_tween = create_tween()
		_glow_tween.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR, engine_spool)

	# Motion: hold through the spool, THEN rise (shadow spreads), then launch off the top.
	var hover_y: float = land_y - 10.0
	_phase_tween = create_tween()
	_phase_tween.tween_interval(engine_spool)
	_phase_tween.tween_property(self, "_shadow_offset", shadow_fly_offset, rise_time)
	_phase_tween.parallel().tween_property(self, "_shadow_scale", shadow_fly_scale, rise_time)
	_phase_tween.parallel().tween_property(_shadow, "modulate:a", shadow_fly_alpha, rise_time)
	_phase_tween.parallel().tween_property(_ship, "position:y", hover_y, rise_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(_ship, "position:y", FLYOFF_TARGET_Y, flyoff_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_phase_tween.tween_callback(_on_departed)


func _on_departed() -> void:
	_state = State.GONE
	emit_signal("departed")


# ---- Runtime --------------------------------------------------------------

func _process(delta: float) -> void:
	if _state == State.LANDED and _ship != null and is_instance_valid(_ship):
		_t += delta
		_ship.position = Vector2(SHIP_X, land_y + sin(_t * TAU / maxf(idle_bob_period, 0.1)) * idle_bob)
	if _shadow != null and is_instance_valid(_shadow) and _ship != null and is_instance_valid(_ship):
		_shadow.position = _ship.position + _shadow_offset
		_shadow.scale = Vector2(_shadow_scale, _shadow_scale)
	_update_sparks(delta)
	_update_lights(delta)


func toast(msg: String) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = msg
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_lbl.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(_toast_lbl, "modulate:a", 0.0, 0.5)


# Release the HD content-scale scope (no-op when embedded in the dev lab).
func drop_hd_scope() -> void:
	HdScreen.drop(_hd)
	_hd = null


# ---- Live setters (dev lab) -----------------------------------------------

func get_state() -> int:
	return _state


func set_damage(level: float) -> void:
	damage_level = clampf(level, 0.0, 1.0)
	_apply_damage()


# Heal damage to `target` over `dur`, re-driving the shader + tells each step (the overlay is
# live, so reducing the level removes the fray + stops the sparks). Services "Repair Hull"
# calls this; production would tie it to the player actually buying a hull repair.
func repair(target: float = 0.0, dur: float = 0.6) -> void:
	target = clampf(target, 0.0, 1.0)
	if not _built or dur <= 0.0:
		set_damage(target)
		return
	var tw := create_tween()
	tw.tween_method(set_damage, damage_level, target, dur)


func set_ship(variant: int, livery: Color, set_livery: bool) -> void:
	ship_variant = clampi(variant, 0, VARIANTS.size() - 1)
	livery_color = livery
	livery_set = set_livery
	if not _built:
		return
	_teardown_ship_fx()
	if _trail != null and is_instance_valid(_trail):
		_trail.queue_free()
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	if _ship != null and is_instance_valid(_ship):
		_ship.queue_free()
	_build_ship()
	begin_arrival()


func _set_alpha(c: Control, a: float) -> void:
	if c != null and is_instance_valid(c):
		c.modulate.a = a
