extends Control

# Patrol Start (2026-06-27) — the new-patrol hangar ship-select sequence. PRODUCTION: the main
# menu's "Start New Patrol" opens this scene; "Begin Patrol" resets the run, writes the chosen
# hull/livery/settings, flies the ship out, and hands off to onboarding (or the sector map when
# Skip Tutorial is set). Also reachable from the dev menu. Esc/Back → main menu.
#
# LIVE vs DEV launch: the main menu sets Run meta `patrol_live_launch` (+ a `patrol_menu_snapshot`
# frame grab) and DIRECT-swaps here with NO fade-to-black. Live mode builds NO dummy menu and NO dev
# chrome; instead it covers the first frame with the captured main-menu image and CROSSFADES it out as
# the hangar rises — so the player's menu dissolves smoothly straight into the patrol start, no black
# flash and no second menu. The dev-menu launch leaves both metas unset and keeps the full tuner: the
# dummy main-menu bridge (so the sequence can be replayed from a menu) + Tune ⚙ + rail.
#
# Flow (dev launch shows step 1's dummy menu; live launch crossfades the real menu frame in its place):
#   1. A dummy main menu (the shared random parallax backdrop + title + buttons) shows first.
#   2. "Start New Patrol" fades the menu out (music walks Intensity_1 → Intensity_2), waits a
#      tunable beat, then the hangar rises into view (TRANS_CUBIC/EASE_IN_OUT — slow start,
#      accelerate, settle) while the backdrop PANS DOWN at a speed matched to the hangar's
#      approach (driven off the hangar's own velocity). Warp streaks run during the rise only —
#      once the bay is in place everything is stationary, so the streaks switch off.
#   3. The fleet parks in two columns flanking the pad, each on a drop shadow. A hover LIFTER
#      sits idle on the floor; ammo-crate clusters + a couple of parked tractor+trailer rigs
#      (lights on/off) dress the outer edges. The hangar is dim (outpost parity).
#   4. Clicking a ship spotlights it + prints its codex/loadout into the LEFT panel.
#   5. "Ready Ship": the LIFTER settles over the ship's centre, lowers until the centres align,
#      fires its grav-glow lights + layer, lifts + carries it to the pad, sets it down, powers
#      the grav off and flies back to idle. Music progresses into Main — rising energy. Readying
#      a different ship returns the previous one to its slot first.
#   6. "Begin Patrol" spools the readied ship's engines, the shadow spreads (outpost depart), and
#      it flies out the top, trail fading (streaks return) — then the run starts (onboarding / map).
#
# TUNING: the "Tune ⚙" button (top-left) or Tab toggles a slider rail with Replay + Copy GDScript.
# RENDER MODEL mirrors outpost_arrival.gd (HD root + native 480×270 TRANSPARENT SubViewport so the
# backdrop shows behind). Altitude is faked with the drop shadow only (no sprite scaling).

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
const EngineTrailFx = preload("res://scripts/effects/engine_trail_fx.gd")
const PF = preload("res://scripts/systems/playfield.gd")
const MenuBackdrop = preload("res://scripts/ui/menu_backdrop.gd")
const ShipVisual = preload("res://scripts/ui/ship_visual.gd")
const HANGAR_STAGE := "res://scenes/hangar_stage.tscn"   # shared authorable plate + runway + lights + slot markers
const HangarClutter = preload("res://scripts/screens/hangar_clutter.gd")
const PointLightFx = preload("res://scripts/effects/point_light_fx.gd")
const DockShadowRig = preload("res://scripts/effects/dock_shadow_rig.gd")
const DockConst = preload("res://scripts/effects/dock_const.gd")
const FIRECORE_SCENE := "res://scenes/enemies/factions/zealot/firecore_core.tscn"
const LIFTER_SCENE := "res://scenes/outpost/outpost_lifter.tscn"
const TRACTOR_SCENE := "res://scenes/outpost/outpost_tractor.tscn"
const TRAILER_SCENE := "res://scenes/outpost/outpost_tractor_trailer.tscn"
const TRACTOR_TEX := "res://graphics/backgrounds/outpost_tractor.png"
const TRAILER_TEX := "res://graphics/backgrounds/outpost_tractor_trailer.png"
const LIFTER_TEX := "res://graphics/backgrounds/outpost_lifter.png"
const CRATE_TEX := "res://graphics/backgrounds/outpost_ammo_crates.png"

const NATIVE_W := DockConst.NATIVE_W
const NATIVE_H := DockConst.NATIVE_H
const HD_SCALE := DockConst.HD_SCALE
const HD_W := DockConst.HD_W
const HD_H := DockConst.HD_H
const SHIP_X := DockConst.SHIP_X
const FLYOFF_TARGET_Y := DockConst.FLYOFF_TARGET_Y
const GUTTER_HD := DockConst.GUTTER_HD   # 528
const RIGHT_HD := DockConst.RIGHT_HD     # 1392

const ENGINE_GLOW_COLOR := DockConst.ENGINE_GLOW_COLOR
const ENGINE_LIGHT_COLOR := DockConst.ENGINE_LIGHT_COLOR
const ENGINE_LIGHT_ENERGY := DockConst.ENGINE_LIGHT_ENERGY   # bright — the engines are the dock's main light
const ENGINE_LIGHT_SCALE := 0.3           # FOCUSED nozzle glow (128px tex → ~38px); scale wasn't the issue
                                          # (Roman 2026-06-26)
const ENGINE_FLARE_PEAK := DockConst.ENGINE_FLARE_PEAK   # energy × at the moment of launch
const ENGINE_FLARE_SCALE := DockConst.ENGINE_FLARE_SCALE   # light-size × at launch (bright spot blooms)
const FIRECORE_LIGHT_COLOR := Color(1.0, 0.62, 0.16)
const SELECT_LIGHT_COLOR := Color(0.62, 0.82, 1.0)
const LIFTER_Z := 12                                # flies above the hulls
const CARRY_Z := 8                                  # carried hull lifts above the parked ones
# Shadow prototype: LEGACY = baked drop shadows; KEY = central key light; FILL = the 2×3 fill lights.
enum ShadowMode { LEGACY, KEY, FILL }

# The plate, runway lights, fill lights, and the pad/lifter/park/crate slot markers now live in the
# shared authorable hangar stage (scenes/hangar_stage.tscn). patrol reads the slot markers from it
# (see _build_backdrop) so ship-park positions etc. are tuned in the editor, not hardcoded here.
# Parked tractor+trailer rigs as dressing: {pos, lights_on}.
const DRESSING_RIGS := [
	{"pos": Vector2(158.0, 206.0), "on": true},
	{"pos": Vector2(330.0, 206.0), "on": false},
]

const SWATCHES := [
	Color(0.90, 0.16, 0.16), Color(0.96, 0.55, 0.13), Color(0.98, 0.85, 0.25),
	Color(0.45, 0.85, 0.30), Color(0.20, 0.80, 0.65), Color(0.25, 0.62, 0.97),
	Color(0.70, 0.38, 0.95), Color(0.96, 0.40, 0.78), Color(0.92, 0.92, 0.95),
]

# ---- Tunables (Tune rail + inspector; read live) -------------------------
@export_group("Sequence")
@export var menu_fade_time: float = 0.5
@export var rise_delay: float = 0.6             # beat between menu fade-out and the hangar rising
@export var slide_time: float = 1.8
@export var bars_fade_time: float = 0.7
@export var bg_pan_ratio: float = 0.6           # celestial pan-up px per px of hangar rise
@export var bg_celestial_drop: float = 110.0    # start the celestial bodies this far down (toward
                                                # centre, matching the main menu); they pan up on the rise
@export_group("Takeoff")
@export var engine_spool: float = 0.8
@export var rise_time: float = 0.5
@export var flyoff_time: float = 0.9
@export_group("Drop shadow / altitude")
@export var shadow_land_offset: Vector2 = Vector2(2.0, 3.0)
@export var shadow_land_alpha: float = 0.5
@export var shadow_fly_offset: Vector2 = Vector2(5.0, 9.0)
@export var shadow_fly_scale: float = 0.85
@export var shadow_fly_alpha: float = 0.2
@export_group("Lifter")
@export var lift_set_time: float = 0.6          # lower / raise duration
@export var lift_fly_time: float = 1.1          # cross at altitude
@export var carry_distance: float = 0.0         # hull offset below the lifter centre while carried
@export var grav_light_energy: float = 1.6      # purple grav lights while carrying
@export_group("Lighting")
# scene_dim dims the WHOLE rendered bay (the hangar SubViewport's OUTPUT) — applied after the
# livery shader has already screen-sampled the full-bright hulls inside the viewport, so the bay
# reads dim/moody WITHOUT the livery going matte (which is what dimming the hulls themselves does,
# since the shader screen-MULTIPLIES the body behind it). 1.0 = no dim. Lights pop relative to it.
@export var scene_dim: float = 0.6     # adopted from the hangar stage on build; applied to the bay output
@export var runway_speed: float = 0.9  # passed to the hangar stage (fill-light energy is authored in the stage)
# Light-derived shadow prototype (Roman 2026-06-26) — see ShadowMode. Default LEGACY = unchanged.
@export var shadow_mode: int = ShadowMode.LEGACY
@export var shadow_dynamic: bool = false   # also cast from tractor head/tail + lifter grav/hover lights
@export var shadow_length: float = 4.0
@export var shadow_alpha: float = 0.5
@export var shadow_falloff: float = 110.0
@export var shadow_softness: float = 0.0
@export var shadow_max: int = 6

var _hd: HdViewportScope = null
var _world: SubViewport = null
var _hangar: Node2D = null
var _hangar_stage: Node2D = null   # shared hangar stage (plate + runway + fill + slot markers), rides in _hangar
var _hangar_off := Vector2.ZERO    # where the stage sits within _hangar (slot markers are relative to it)
var _pad := Vector2(SHIP_X, 132.0)        # readied-ship pad (overwritten from the stage's Pad marker)
var _lifter_idle := Vector2(SHIP_X, 226.0)  # lifter rest (overwritten from the LifterIdle marker)
var _select_light: PointLight2D = null
var _light_tex: Texture2D = null
var _shadow_rig = null               # DockShadowRig (owns the LightShadowFx; light-derived prototype)
var _legacy_shadows: Array = []      # baked drop shadows to hide in the light-derived modes
var _extra_casters: Array = []       # [{src, parent, z}] ship/tractor/lifter bodies
var _dynamic_lights: Array = []      # tractor head/brake/hover + lifter grav/hover PointLights
var _backdrop: Node = null
var _bg_stars: Node = null
var _streaks_node: Node = null
var _celestial_layers: Array = []   # planet + stellar layers — dropped at start, pan up on the rise
var _celestial_start: Array = []    # their start positions (for Replay reset)
var _prev_hangar_y: float = NATIVE_H

# (runway / plate / fill-light state now lives in the shared hangar stage)

# Lifter.
var _lifter: Node2D = null
var _lifter_shadow: Sprite2D = null
var _grav_lights: Array = []
var _grav_glow: Sprite2D = null
var _lifter_engines: Sprite2D = null   # engine glow sprite (4-frame anim) — off when idle
var _hover_lights: Array = []
var _lifter_active: bool = false       # engines lit + animating
var _engine_anim_t: float = 0.0
var _altitude: float = 0.0
var _grab: Dictionary = {}

# Per-ship state.
var _ships: Array = []
var _selected_idx: int = -1
var _readied_idx: int = -1
var _busy: bool = false
var _started: bool = false

var _skip_tutorial: bool = false
var _endless: bool = false
var _live_launch: bool = false   # main-menu launch: seamless auto-run, no dev chrome (see header)
var _menu_snapshot: Texture2D = null   # captured main-menu frame, crossfaded out on a live launch
var _crossfade_layer: CanvasLayer = null

# ---- Customize Patrol (the Conditions overlay; persisted to user://conditions_setup.json) ----
# State = { picked, bad, good, blind }. An empty pick list is a STRICT no-op (no
# apply_conditions). Blind rolls the bane/good split SECRETLY at Begin off a
# decorrelated seed (run_seed ^ salt) — deterministic per run, hidden until in-run.
const COND_SETUP_PATH := "user://conditions_setup.json"
const COND_SEED_SALT := 0x51EC7C0D   # decorrelates the Blind roll from sector-gen (matches the legacy salt)
# First-pass dials for the 0/0 "surprise me" spread — when both steppers sit at 0/0,
# Random / Blind roll a random count from these (inclusive) ranges instead of a strict
# no-op. Bad-biased (bad floor ≥ 1) so a surprise roll always has spice.
const RAND_BAD_RANGE := Vector2i(1, 4)
const RAND_GOOD_RANGE := Vector2i(0, 3)
# Boon blue — the game's blue (#4d9fff family; corporate livery). UiTheme.COLOR_ACCENT
# reads pale/cyan, so a saturated blue keeps a boon NAME legible against the panel.
const COLOR_BOON := Color(0.30, 0.62, 1.0, 1.0)
var _cond_picked: Array = []       # hand-picked (or Random-filled) ids
var _cond_bad: int = 0             # bane count (Random fill / Blind roll)
var _cond_good: int = 0            # boon count (Random fill / Blind roll)
var _cond_blind: bool = false      # roll secretly at Begin, ignore the visible picks
# UI refs — settings panel + the Customize overlay.
var _cond_setup_summary_lbl: Label = null   # summary echoed beside Customize on the settings panel
var _cust_layer: CanvasLayer = null
var _cust_dim: ColorRect = null
var _cust_panel: PanelContainer = null
var _cust_open: bool = false
var _cust_busy: bool = false                # guards the open/close animation
var _cond_checks: Dictionary = {}           # id -> CheckBox (overlay pick rows)
var _cust_columns_box: Control = null       # BANES/BOONS grid — dimmed/disabled when Blind
var _cust_random_btn: Button = null         # disabled + dimmed under Blind (a blind roll ignores it)
var _bad_stepper_set: Callable = Callable()  # setter to reflect a rolled Bad count in the stepper UI
var _good_stepper_set: Callable = Callable() # setter to reflect a rolled Good count in the stepper UI
var _cust_blind_caption: Label = null
var _cust_summary_lbl: Label = null         # overlay summary line
var _cust_detail_name: Label = null         # hovered-condition detail panel
var _cust_detail_value: Label = null
var _cust_detail_blurb: Label = null

# UI refs.
var _menu_ui: Control = null
var _left_body: VBoxContainer = null
var _ready_btn: Button = null
var _begin_btn: Button = null
var _seed_edit: LineEdit = null       # optional custom run-seed box (blank = random); not persisted
var _seed_caption: Label = null       # live "→ <resolved seed>" echo under the box
var _left_sidebar: ColorRect = null
var _right_sidebar: ColorRect = null
var _left_panel: Control = null
var _right_panel: Control = null
var _status: Label = null
var _click_layer: Control = null
var _rail: PanelContainer = null
var _rail_vals: Dictionary = {}


func _ready() -> void:
	# Consume the one-shot live-launch flag + crossfade frame the main menu set (dev launch sets neither).
	var run := get_node_or_null("/root/Run")
	if run != null and run.has_meta("patrol_live_launch"):
		_live_launch = bool(run.get_meta("patrol_live_launch"))
		run.remove_meta("patrol_live_launch")
	if run != null and run.has_meta("patrol_menu_snapshot"):
		_menu_snapshot = run.get_meta("patrol_menu_snapshot") as Texture2D
		run.remove_meta("patrol_menu_snapshot")
	_hd = HdScreen.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_menu_backdrop()
	_world = HdScreen.make_play_subviewport(self)
	_world.transparent_bg = true
	# The bay dim lives in the hangar stage's own CanvasModulate (authored + tuned there).
	_light_tex = _make_light_texture()
	_hangar = Node2D.new()
	_hangar.name = "Hangar"
	_hangar.position = Vector2(0, NATIVE_H)
	_world.add_child(_hangar)
	_prev_hangar_y = NATIVE_H
	_build_backdrop()
	_build_crates()
	_build_dressing()
	_build_ships()
	_build_lifter()
	_build_shadow_mgr()
	_load_cond_setup()
	_build_ui()
	if _live_launch:
		_preready_default_ship()   # default hull already on the pad + codex up — player can Begin at once
		_build_live_crossfade()    # cover the first frame with the captured menu so the direct swap is invisible
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	if _live_launch:
		_begin_live_launch()


func _process(delta: float) -> void:
	_lift_update()
	_animate_lifter_engines(delta)
	_update_bg_pan()


func _install_menu_backdrop() -> void:
	# LIVE launch: the main menu hands over its ALREADY-RENDERED backdrop (accumulated parallax drift +
	# per-layer star scatter intact) via the `patrol_backdrop_live` meta. ADOPT it so the crossfade
	# dissolves the menu into the SAME sky instead of a freshly-reset coordinator. Consume the meta
	# unconditionally — never leave a stashed node dangling. Dev launch (no meta) builds fresh as before.
	var adopted := _adopt_live_backdrop()
	if adopted:
		return
	var bd := MenuBackdrop.make()
	bd.name = "MenuBackdrop"
	HdScreen.add_upscaled_backdrop(self, bd)
	_backdrop = bd
	_bg_stars = bd.get_node_or_null("LayerStars")
	_streaks_node = bd.get_node_or_null("LayerStreaks")
	# Celestial bodies start dropped toward centre (matching the main menu) and pan up on the rise.
	MenuBackdrop.drop_celestials(bd)
	_celestial_layers = []
	_celestial_start = []
	for cl in MenuBackdrop.celestial_layers(bd):
		_celestial_layers.append(cl)
		_celestial_start.append((cl as CanvasLayer).offset)


# Adopt the live main-menu backdrop stashed in the `patrol_backdrop_live` Run meta (if valid). Returns
# true when adopted; false → the caller builds a fresh backdrop. Consumes the meta either way, freeing
# an unusable stashed node so it never dangles.
func _adopt_live_backdrop() -> bool:
	var run := get_node_or_null("/root/Run")
	if run == null or not run.has_meta("patrol_backdrop_live"):
		return false
	var sub = run.get_meta("patrol_backdrop_live")
	run.remove_meta("patrol_backdrop_live")   # consume unconditionally
	if not (sub is SubViewport) or not is_instance_valid(sub):
		return false
	var bd := (sub as SubViewport).get_node_or_null("Backdrop")
	if bd == null:
		# Stashed viewport has no backdrop child — unusable; free it so it doesn't dangle.
		(sub as SubViewport).queue_free()
		return false
	if HdScreen.adopt_upscaled_backdrop(self, sub) == null:
		(sub as SubViewport).queue_free()
		return false
	_backdrop = bd
	_bg_stars = bd.get_node_or_null("LayerStars")
	_streaks_node = bd.get_node_or_null("LayerStreaks")
	# The menu already dropped the celestials by bg_celestial_drop — do NOT re-apply it. Record their
	# CURRENT offsets as the pan/replay baseline so _update_bg_pan + _replay still work.
	_celestial_layers = []
	_celestial_start = []
	for cl in MenuBackdrop.celestial_layers(bd):
		_celestial_layers.append(cl)
		_celestial_start.append((cl as CanvasLayer).offset)
	return true


# Pan the celestial bodies UP in proportion to the hangar's upward travel — the camera craning down
# onto the rising bay, so space pans across. Speed matches the outpost approach exactly (slow start,
# accelerate, settle) and naturally stops when the hangar does.
func _update_bg_pan() -> void:
	if _hangar == null:
		return
	var dy: float = _hangar.position.y - _prev_hangar_y
	_prev_hangar_y = _hangar.position.y
	if absf(dy) < 0.001:
		return
	for L in _celestial_layers:
		if is_instance_valid(L):
			(L as CanvasLayer).offset.y += dy * bg_pan_ratio   # hangar up (dy<0) → celestials pan up


func _set_streaks(on: bool) -> void:
	if _streaks_node != null and is_instance_valid(_streaks_node):
		_streaks_node.set("enabled", on)


# Bay dim → the hangar stage's in-scene CanvasModulate (single source; tuned via the rail).
func _set_scene_dim(x: float) -> void:
	scene_dim = x
	if _hangar_stage != null and is_instance_valid(_hangar_stage):
		_hangar_stage.set_scene_dim(x)


func _set_runway_speed(x: float) -> void:
	runway_speed = x
	if _hangar_stage != null and is_instance_valid(_hangar_stage):
		_hangar_stage.set_runway_speed(x)


# ---- World ---------------------------------------------------------------

func _build_backdrop() -> void:
	# Shared authorable hangar stage (plate + runway lights + ambient fill + slot markers). Rides inside
	# _hangar at the band centre; scene_dim dims the whole bay output, so the plate stays full-bright.
	_hangar_stage = load(HANGAR_STAGE).instantiate()
	_hangar_stage.runway_speed = runway_speed
	_hangar_stage.position = Vector2(SHIP_X, NATIVE_H / 2.0)
	_hangar.add_child(_hangar_stage)
	# Read the slot markers (stage-local) into the positions the rest of the scene uses (in _hangar
	# coords). Authored in scenes/hangar_stage.tscn → tune ship slots in the editor, not in code.
	_hangar_off = _hangar_stage.position
	_pad = _hangar_off + _hangar_stage.slot("Pad")
	_lifter_idle = _hangar_off + _hangar_stage.slot("LifterIdle")
	scene_dim = _hangar_stage.scene_dim   # adopt the stage's authored CanvasModulate dim (for the rail default)
	# The selection spotlight stays dynamic (moves to the clicked ship), so it lives in patrol.
	_select_light = _make_point_light(Vector2.ZERO, SELECT_LIGHT_COLOR, 0.5, _light_tex)
	_hangar.add_child(_select_light)


# Randomized crate clutter at the hangar stage's authored ClutterZones (out of the way of the ships
# /lifter/rigs by where those zones are placed). Re-rolls per patrol start (seed = the run seed).
func _build_crates() -> void:
	var baked := shadow_mode == ShadowMode.LEGACY   # light-derived modes project crate shadows instead
	_hangar_stage.scatter_clutter(_clutter_seed(), -1, baked)


# Per-patrol clutter seed: the run seed if a run is live, else random (a fresh launch = fresh clutter).
func _clutter_seed() -> int:
	var run := get_node_or_null("/root/Run")
	if run != null and "run_seed" in run and int(run.run_seed) != 0:
		return int(run.run_seed)
	return randi()


# ---- Light-derived shadow prototype (Roman 2026-06-26; shared light_shadow_fx) --------------------
# Mirrors the outpost lab: LEGACY = baked drop shadows; KEY = a central key light; FILL = the bay's 2×3
# fill lights (multi-shadow). Dynamic adds the bright bay lights (tractor head/tail + lifter grav/hover)
# as extra casters. Default LEGACY = unchanged.

func _build_shadow_mgr() -> void:
	_shadow_rig = DockShadowRig.new()
	_shadow_rig.setup(_world, _hangar_stage)
	# Per-screen registration: the ship/tractor/lifter bodies (from _extra_casters) + the dynamic bay
	# lights (tractor head/tail + lifter grav/hover, from _dynamic_lights). Clutter casters + key/fill
	# lights are handled by the rig.
	_shadow_rig.set_casters_callback(func(rig) -> void:
		for c in _extra_casters:
			if is_instance_valid(c["src"]):
				rig.add_caster(c["src"], c["parent"], int(c["z"])))
	_shadow_rig.set_dynamic_lights_callback(func(rig) -> void:
		for l in _dynamic_lights:
			if is_instance_valid(l):
				rig.add_dynamic_light(l, 1.0, 1.5))
	_apply_shadow_mode()


func set_shadow_mode(m: int) -> void:
	shadow_mode = m
	_build_crates()   # re-scatter crates with/without baked shadows (same seed → same layout)
	_apply_shadow_mode()


func set_shadow_dynamic(on: bool) -> void:
	shadow_dynamic = on
	if _shadow_rig != null:
		_shadow_rig.rebuild_lights()


func set_shadow_max(x: float) -> void:
	shadow_max = int(round(x))
	_sync_shadow_knobs()


func _set_shadow_knob(prop: String, x: float) -> void:
	set(prop, x)
	_sync_shadow_knobs()


func _apply_shadow_mode() -> void:
	if _shadow_rig == null:
		return
	var proto: bool = shadow_mode != ShadowMode.LEGACY
	for s in _legacy_shadows:
		if is_instance_valid(s):
			(s as Node2D).visible = not proto
	_sync_shadow_knobs()
	_shadow_rig.apply(shadow_mode, shadow_dynamic)


func _sync_shadow_knobs() -> void:
	if _shadow_rig != null:
		_shadow_rig.sync_knobs(shadow_length, shadow_alpha, shadow_falloff, shadow_softness, shadow_max)


# Parked tractor+trailer rigs (4-wheel ground vehicles) as dressing: tractor (front, facing up) +
# trailer behind, hitched rear-to-front with a 1px gray pivot between the hitch markers, in on/off
# light states. Pure scenery.
func _build_dressing() -> void:
	for rig in DRESSING_RIGS:
		_make_rig(rig["pos"], bool(rig["on"]))


func _make_rig(pos: Vector2, lights_on: bool) -> void:
	# Short shadows (silhouettes) under both vehicles.
	var t_sh := _make_frame_sprite(load(TRACTOR_TEX), 4, 0)
	t_sh.modulate = Color(0, 0, 0, 0.4)
	t_sh.position = pos + Vector2(1.0, 1.5)
	t_sh.z_index = -6
	_hangar.add_child(t_sh)
	var trailer_pos := pos + Vector2(0, 12)
	var r_sh := _make_frame_sprite(load(TRAILER_TEX), 1, 0)
	r_sh.modulate = Color(0, 0, 0, 0.4)
	r_sh.position = trailer_pos + Vector2(1.0, 1.5)
	r_sh.z_index = -6
	_hangar.add_child(r_sh)
	# Tractor + trailer.
	var tractor = load(TRACTOR_SCENE).instantiate()
	tractor.position = pos
	tractor.z_index = -4
	_nearest_all(tractor)
	_hangar.add_child(tractor)
	var trailer = load(TRAILER_SCENE).instantiate()
	trailer.position = trailer_pos
	trailer.z_index = -4
	_nearest_all(trailer)
	_hangar.add_child(trailer)
	# Load a couple of small crates into the trailer's carrying space (TrailerArea), z above its body.
	HangarClutter.fill_trailer(trailer, _clutter_seed() ^ int(pos.x) ^ (int(pos.y) << 8))
	# Gray 1px pivot between the tractor's rear Hitch (pos + 0,5) and the trailer's front HitchF.
	var pivot := Polygon2D.new()
	pivot.polygon = PackedVector2Array([Vector2(-0.5, 5.0), Vector2(0.5, 5.0), Vector2(0.5, 6.0), Vector2(-0.5, 6.0)])
	pivot.color = Color(0.5, 0.5, 0.5)
	pivot.position = pos
	pivot.z_index = -3
	_hangar.add_child(pivot)
	# Lights track the glowmasks: an ON rig shows its head/brake/engine glow AND casts its point lights;
	# an OFF rig has both dark. Set both ways explicitly so it never rides on the scene's default state.
	# Only enable the TRACTOR's headlights (not the trailer's) to keep a rig pair at 2 enabled lights max,
	# respecting the plate's 16-light budget (see LIGHT BUDGET in hangar_stage.gd).
	_rig_lights(tractor, lights_on, true)
	_rig_lights(trailer, lights_on, false)
	# Shadow prototype: each vehicle body casts; its drop shadow becomes legacy; an ON rig's point
	# lights join the dynamic shadow sources (an OFF rig's are hidden → they contribute nothing).
	for sh2 in [t_sh, r_sh]:
		_legacy_shadows.append(sh2)
	for veh in [tractor, trailer]:
		var vb = veh.get_node_or_null("Body")
		if vb is Sprite2D:
			_extra_casters.append({"src": vb, "parent": _hangar, "z": -3})
		for l in veh.find_children("*", "PointLight2D", true, false):
			_dynamic_lights.append(l)


# Toggle a rig vehicle's lights (the PointLights + the head/brake/engine light sprite layers).
func _rig_lights(vehicle: Node, on: bool, is_tractor: bool = true) -> void:
	# Light budget: when a rig is ON, only enable the TRACTOR's HEADLIGHTS (2 PointLight2Ds) to cap the
	# rig pair at 2 enabled lights total; the trailer's PointLights all stay disabled even when ON.
	# The visual glow sprite layers (Headlights/Brakelights/Engines) remain fully visible on both
	# tractor + trailer, so the display isn't compromised. This keeps an ON rig within the plate's 16-light
	# budget (see LIGHT BUDGET in hangar_stage.gd). Roman 2026-07-02.
	for l in vehicle.find_children("*", "PointLight2D", true, false):
		var light_node = l as Node2D
		var light_name = String(light_node.name)
		if on and is_tractor:
			# Only TRACTOR headlights are enabled (most visible/important for lighting the bay).
			light_node.visible = light_name.begins_with("HeadLight")
		else:
			# Trailer lights always off; tractor lights off when the rig is OFF.
			light_node.visible = false
	for nm in ["Headlights", "Brakelights", "Engines"]:
		var n = vehicle.get_node_or_null(nm)
		if n != null:
			n.visible = on


func _make_frame_sprite(tex: Texture2D, hframes: int, frame: int) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.hframes = hframes
	spr.frame = frame
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return spr


func _nearest_all(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for spr in node.find_children("*", "Sprite2D", true, false):
		(spr as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _build_ships() -> void:
	_ships.clear()
	for i in ShipCatalog.count():
		var ship: Dictionary = ShipCatalog.get_ship(i)
		var col: Color = ship.get("livery_color", Color(0.90, 0.16, 0.16))
		# Shared dock ship stack (body + livery UNDER body + additive glow + engine markers). Patrol
		# parents the livery under the body, sets the body z to -2, and starts the glow unlit (alpha 0 —
		# parked). Bodies are full-bright (live-ship look); scene_dim dims the whole bay output.
		var built := ShipVisual.build_dock_ship(ship, col, true, -2, 0.0)
		var host: Node2D = built["host"]
		host.name = "Ship_%s" % String(ship["id"])
		var body: Sprite2D = built["body"]
		var glow: Sprite2D = built["glow"]
		var livery_mat := (built["livery"] as Sprite2D).material as ShaderMaterial
		var markers: Array = built["markers"]
		# Drop shadow — added under the body layers (built earlier so it sorts behind). Absolute z so it
		# stays on the FLOOR (under everything) even while the hull is raised to CARRY_Z during a lift —
		# it tracks the hull across the bay as a ground shadow.
		var shadow := _make_sprite(String(ship["body"]))
		shadow.modulate = Color(0, 0, 0, shadow_land_alpha)
		shadow.position = shadow_land_offset
		shadow.z_as_relative = false
		shadow.z_index = -3
		host.add_child(shadow)
		if String(ship["id"]) == "pilgrim":
			_attach_firecore(host)
		var park: Vector2 = _park_pos(i)
		host.position = park
		_hangar.add_child(host)
		_ships.append({
			"idx": i, "host": host, "body": body, "glow": glow, "shadow": shadow,
			"markers": markers, "park_pos": park, "btn": null,
			"livery_mat": livery_mat, "livery_color": col, "trail": null, "engine_lights": [],
		})
		# Shadow prototype: the hull body casts; its baked drop shadow becomes legacy.
		_extra_casters.append({"src": body, "parent": _hangar, "z": -3})
		_legacy_shadows.append(shadow)


func _park_pos(idx: int) -> Vector2:
	# Ship-park slots are authored Marker2D ("Park0".."ParkN") in the hangar stage; read by index.
	return _hangar_off + _hangar_stage.slot("Park%d" % idx)


func _make_sprite(path: String) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.hframes = 3
	spr.frame = 1
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return spr


func _attach_firecore(host: Node2D) -> void:
	var core = load(FIRECORE_SCENE).instantiate()
	core.z_index = 3
	core.position = Vector2(0, 0)
	host.add_child(core)
	var light := _make_point_light(Vector2(0, 0), FIRECORE_LIGHT_COLOR, 0.35, _light_tex)
	light.energy = 0.9
	light.enabled = true   # pulses forever (never parked off) — always on (see LIGHT BUDGET, hangar_stage)
	host.add_child(light)
	var pulse := create_tween().set_loops()
	pulse.tween_property(light, "energy", 1.1, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(light, "energy", 0.65, 0.7).set_trans(Tween.TRANS_SINE)


func _make_light_texture() -> Texture2D:
	return PointLightFx.make_texture(128)


func _make_point_light(pos: Vector2, col: Color, scale: float, tex: Texture2D) -> PointLight2D:
	return PointLightFx.make(pos, col, scale, tex)


# ---- Lifter (grav crane: centres over a ship, lowers, grav-grabs, carries) ----

func _build_lifter() -> void:
	_lifter = load(LIFTER_SCENE).instantiate()
	_lifter.z_index = LIFTER_Z
	_lifter.position = _lifter_idle
	_nearest_all(_lifter)
	# Grav glow layer + grav light start OFF (the lifter is idle, grav cold). Roman 2026-07-02: lifter
	# refactored to 1 GravLight PointLight2D at root (was Body/GravLight + Body/GravLight2).
	_grav_glow = _lifter.get_node_or_null("GravGlow")
	if _grav_glow != null:
		_grav_glow.modulate.a = 0.0
	_grav_lights = []
	var grav_light = _lifter.get_node_or_null("GravLight")
	if grav_light != null:
		(grav_light as PointLight2D).energy = 0.0
		(grav_light as PointLight2D).enabled = false   # idle = off; frees a plate light slot (LIGHT BUDGET)
		_grav_lights.append(grav_light)
	# Engines + hover light start OFF (idle = powered down); they fade in + animate on activation.
	# Roman 2026-07-02: lifter refactored to 1 HoverLight PointLight2D at root (was 4x Body/HoverLight*).
	_lifter_engines = _lifter.get_node_or_null("Engines")
	if _lifter_engines != null:
		_lifter_engines.modulate.a = 0.0
	_hover_lights = []
	var hover_light = _lifter.get_node_or_null("HoverLight")
	if hover_light != null:
		(hover_light as PointLight2D).energy = 0.0
		(hover_light as PointLight2D).enabled = false   # idle = off; frees a plate light slot (LIGHT BUDGET)
		_hover_lights.append(hover_light)
	_hangar.add_child(_lifter)
	# The lifter's own drop shadow (frame-0 silhouette; spreads with altitude on lift-off).
	var sh := _make_frame_sprite(load(LIFTER_TEX), 3, 0)
	sh.modulate = Color(0, 0, 0, shadow_land_alpha)
	sh.position = _lifter_idle + shadow_land_offset
	sh.z_index = -3
	_hangar.add_child(sh)
	_lifter_shadow = sh
	# Shadow prototype: the lifter body casts; its grav/hover lights join the dynamic shadow sources.
	_legacy_shadows.append(sh)
	var lbody = _lifter.get_node_or_null("Body")
	if lbody is Sprite2D:
		_extra_casters.append({"src": lbody, "parent": _hangar, "z": -3})
	for gl in _grav_lights:
		_dynamic_lights.append(gl)
	for hl in _hover_lights:
		_dynamic_lights.append(hl)


# Per-frame: altitude → lifter + carried-hull shadows; keep a carried hull under the lifter.
func _lift_update() -> void:
	if _lifter == null or not is_instance_valid(_lifter):
		return
	var pose := DockShadowRig.shadow_pose(_altitude, shadow_land_offset, shadow_fly_offset, shadow_land_alpha, shadow_fly_alpha, shadow_fly_scale)
	var off: Vector2 = pose["offset"]
	var scl: float = pose["scale"]
	var alp: float = pose["alpha"]
	if _lifter_shadow != null and is_instance_valid(_lifter_shadow):
		_lifter_shadow.position = _lifter.position + off
		_lifter_shadow.scale = Vector2(scl, scl)
		_lifter_shadow.modulate.a = alp
	if not _grab.is_empty():
		var host: Node2D = _grab["host"]
		host.position = _lifter.position + Vector2(0, carry_distance)
		var hsh: Sprite2D = _grab["shadow"]
		hsh.position = off
		hsh.scale = Vector2(scl, scl)
		hsh.modulate.a = alp


func _tween_altitude(target: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_altitude", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _tween_lifter_to(target: Vector2, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_lifter, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _set_grav(on: bool) -> void:
	if on:
		for l in _grav_lights:
			(l as PointLight2D).enabled = true   # enable before fading in (see LIGHT BUDGET, hangar_stage)
	var tw := create_tween().set_parallel(true)
	for l in _grav_lights:
		tw.tween_property(l, "energy", grav_light_energy if on else 0.0, 0.3)
	if _grav_glow != null:
		tw.tween_property(_grav_glow, "modulate:a", 1.0 if on else 0.0, 0.3)
	if not on:
		# After the fade-out, disable the parked 0-energy grav lights so they free their plate slots.
		var lights := _grav_lights
		tw.chain().tween_callback(func() -> void:
			for l in lights:
				if is_instance_valid(l):
					(l as PointLight2D).enabled = false)


# Power the lifter's engines up (fade the engine glow in + light the hover lights) or down. The
# engine sprite frames cycle while active (see _animate_lifter_engines).
func _set_lifter_engines(on: bool) -> void:
	_lifter_active = on
	if on:
		for h in _hover_lights:
			(h as PointLight2D).enabled = true   # enable before fading in (see LIGHT BUDGET, hangar_stage)
	var tw := create_tween().set_parallel(true)
	if _lifter_engines != null:
		tw.tween_property(_lifter_engines, "modulate:a", 1.0 if on else 0.0, 0.4)
	for h in _hover_lights:
		tw.tween_property(h, "energy", 1.0 if on else 0.0, 0.4)
	if not on:
		# After fade-out, disable the parked hover lights so they free their plate slots.
		var lights := _hover_lights
		tw.chain().tween_callback(func() -> void:
			for h in lights:
				if is_instance_valid(h):
					(h as PointLight2D).enabled = false)


func _animate_lifter_engines(delta: float) -> void:
	if not _lifter_active or _lifter_engines == null or not is_instance_valid(_lifter_engines):
		return
	_engine_anim_t += delta
	_lifter_engines.frame = int(_engine_anim_t * 14.0) % 4   # cycle the 4 engine frames


# Settle over the ship's centre, lower until the centres align, fire the grav, lift + carry to
# `dest`, set down, power the grav off.
func _lift_pick(ship: Dictionary, dest: Vector2) -> void:
	var host: Node2D = ship["host"]
	await _tween_altitude(1.0, lift_set_time)
	await _tween_lifter_to(host.position, lift_fly_time)
	await _tween_altitude(0.0, lift_set_time)
	# Grav-grab.
	_grab = ship
	host.z_index = CARRY_Z
	_set_grav(true)
	await get_tree().create_timer(0.25).timeout
	await _tween_altitude(1.0, lift_set_time)
	await _tween_lifter_to(dest, lift_fly_time)
	await _tween_altitude(0.0, lift_set_time)
	# Power down + release.
	_set_grav(false)
	host.z_index = 0
	host.position = dest
	_grab = {}
	_position_ship_button(ship)


func _lift_return() -> void:
	await _tween_altitude(1.0, lift_set_time)
	await _tween_lifter_to(_lifter_idle, lift_fly_time)
	await _tween_altitude(0.0, lift_set_time)


# ---- HD UI ---------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "PatrolUI"
	add_child(layer)

	_left_sidebar = _make_sidebar(0.0, GUTTER_HD)
	layer.add_child(_left_sidebar)
	_right_sidebar = _make_sidebar(RIGHT_HD, HD_W)
	layer.add_child(_right_sidebar)

	_click_layer = Control.new()
	_click_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_click_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_layer.visible = false
	layer.add_child(_click_layer)
	for s in _ships:
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(80, 80)
		btn.size = Vector2(80, 80)
		var clear := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, clear)
		btn.pressed.connect(_on_ship_clicked.bind(int(s["idx"])))
		_click_layer.add_child(btn)
		s["btn"] = btn
		_position_ship_button(s)

	_build_left_panel(layer)
	_build_right_panel(layer)
	# DEV launch keeps the dummy main-menu bridge + tuner chrome (rail + Tune ⚙ + Tab) so the sequence
	# can be replayed from a menu state. A LIVE launch from the real main menu builds NEITHER — the real
	# menu already played that role, so there's no redundant second menu and we drop straight into the
	# hangar rise (see _begin_live_launch / _on_start_patrol).
	if not _live_launch:
		_build_menu_overlay(layer)
		_build_rail(layer)
		var tune := UiTheme.make_button("Tune ⚙", true)
		tune.position = Vector2(16, 10)
		tune.size = Vector2(132, 40)
		tune.pressed.connect(_toggle_rail)
		layer.add_child(tune)


func _make_sidebar(x0: float, x1: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.03, 0.05, 1.0)
	r.position = Vector2(x0, 0)
	r.size = Vector2(x1 - x0, HD_H)
	r.modulate.a = 0.0
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


func _position_ship_button(s: Dictionary) -> void:
	var btn: Button = s["btn"]
	if btn == null:
		return
	var host: Node2D = s["host"]
	var hd: Vector2 = host.position * HD_SCALE
	btn.position = hd - btn.size * 0.5


func _build_menu_overlay(layer: CanvasLayer) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_menu_ui = root
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var title := _label("STARBLASTER", UiTheme.LabelKind.TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.custom_minimum_size = Vector2(460, 0)
	v.add_child(btns)
	var start_btn := UiTheme.make_button("Start New Patrol")
	start_btn.custom_minimum_size = Vector2(460, 64)
	start_btn.pressed.connect(_on_start_patrol)
	btns.add_child(start_btn)
	for label in ["Continue Patrol", "Options", "Quit"]:
		var b := UiTheme.make_button(label)
		b.custom_minimum_size = Vector2(460, 64)
		b.disabled = true
		btns.add_child(b)


func _build_left_panel(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.position = Vector2(16, 16)
	panel.size = Vector2(GUTTER_HD - 32, HD_H - 32)
	panel.modulate.a = 0.0
	layer.add_child(panel)
	_left_panel = panel
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	_left_body = v
	_refresh_left_panel()


func _refresh_left_panel() -> void:
	if _left_body == null:
		return
	for c in _left_body.get_children():
		c.queue_free()
	if _selected_idx < 0:
		_left_body.add_child(_label("SELECT A SHIP", UiTheme.LabelKind.HEADER))
		var sub := _label("Click a parked hull to inspect it.", UiTheme.LabelKind.CAPTION)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left_body.add_child(sub)
		return
	var ship: Dictionary = ShipCatalog.get_ship(_selected_idx)
	_left_body.add_child(_label(String(ship["name"]), UiTheme.LabelKind.HEADER))
	_left_body.add_child(_label(String(ship["tag"]), UiTheme.LabelKind.CAPTION))
	_left_body.add_child(_label("ARMAMENT", UiTheme.LabelKind.CAPTION))
	var arm := _label(String(ship["armament"]), UiTheme.LabelKind.BODY)
	arm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_body.add_child(arm)
	_left_body.add_child(_label("MODULES", UiTheme.LabelKind.CAPTION))
	var mod := _label(String(ship["modules"]), UiTheme.LabelKind.BODY)
	mod.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_body.add_child(mod)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_body.add_child(scroll)
	var blurb := _label(String(ship["codex"]), UiTheme.LabelKind.BODY)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(blurb)
	_left_body.add_child(HSeparator.new())
	_left_body.add_child(_label("LIVERY", UiTheme.LabelKind.CAPTION))
	var swatch_grid := GridContainer.new()
	swatch_grid.columns = 5
	swatch_grid.add_theme_constant_override("h_separation", 8)
	swatch_grid.add_theme_constant_override("v_separation", 8)
	_left_body.add_child(swatch_grid)
	for c in SWATCHES:
		swatch_grid.add_child(_make_swatch(c))
	var ready_row := CenterContainer.new()
	_left_body.add_child(ready_row)
	_ready_btn = UiTheme.make_button("Ready Ship")
	_ready_btn.pressed.connect(_on_ready_pressed)
	if _selected_idx == _readied_idx:
		_ready_btn.text = "Readied ✓"
		_ready_btn.disabled = true
	ready_row.add_child(_ready_btn)


func _make_swatch(c: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 40)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.6)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(_on_livery_picked.bind(c))
	return b


func _build_right_panel(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.position = Vector2(RIGHT_HD + 16, 16)
	panel.size = Vector2(HD_W - RIGHT_HD - 32, HD_H - 32)
	panel.modulate.a = 0.0
	layer.add_child(panel)
	_right_panel = panel
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	v.add_child(_label("PATROL SETUP", UiTheme.LabelKind.HEADER))
	v.add_child(HSeparator.new())
	# Plain run-settings list (the LOADOUT|CONDITIONS tabs were cut 2026-07-09).
	v.add_child(_make_toggle("Skip Tutorial", _skip_tutorial, func(on): _skip_tutorial = on))
	v.add_child(_make_toggle("Endless Mode", _endless, func(on): _endless = on))
	# Customize Patrol — opens the full-screen Conditions overlay (banes/boons picker).
	var cust_btn := UiTheme.make_button("Customize Patrol")
	cust_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cust_btn.pressed.connect(_open_customize)
	v.add_child(cust_btn)
	_cond_setup_summary_lbl = _label(_cond_summary_text(), UiTheme.LabelKind.CAPTION)
	_cond_setup_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_cond_setup_summary_lbl)
	var setup_spacer := Control.new()
	setup_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(setup_spacer)
	v.add_child(HSeparator.new())
	_status = _label("Ready a ship, then begin the patrol.", UiTheme.LabelKind.CAPTION)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var begin_row := CenterContainer.new()
	v.add_child(begin_row)
	_begin_btn = UiTheme.make_button("Begin Patrol")
	_begin_btn.disabled = true
	_begin_btn.pressed.connect(_on_begin_pressed)
	begin_row.add_child(_begin_btn)
	# Custom run seed (2026-07-14): an optional box overriding the randomly-rolled run seed so a
	# player can replay a specific patrol. Placed right under Begin; blank = random. Deliberately NOT
	# persisted to conditions_setup.json — a sticky seed silently reused every run is a trap, so it
	# clears each time the panel opens. The resolved seed is echoed live in a caption below.
	v.add_child(HSeparator.new())
	v.add_child(_label("SEED", UiTheme.LabelKind.CAPTION))
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed (blank = random)"
	_seed_edit.max_length = 24
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.add_theme_font_override("font", UiTheme.menu_font())
	_seed_edit.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_seed_edit.text_changed.connect(func(_t: String) -> void: _update_seed_caption())
	v.add_child(_seed_edit)
	_seed_caption = _label("→ random", UiTheme.LabelKind.CAPTION)
	_seed_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_seed_caption)
	var back := UiTheme.make_button("Back", true)
	back.pressed.connect(_back)
	v.add_child(back)


func _make_toggle(text: String, initial: bool, on_change: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = initial
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_override("font", UiTheme.menu_font())
	cb.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	cb.toggled.connect(func(on: bool) -> void: on_change.call(on))
	return cb


# ---- Customize Patrol overlay (full-screen Conditions picker) -------------
# Clicking "Customize Patrol" on the settings panel fades the background to black
# and slide-expands a full-screen overlay out of the right-hand panel. The overlay
# holds a hovered-condition DETAIL panel (left) + three category groups (ENEMY | PLAYER
# | ECONOMY), each its own paired BANES/BOONS pick columns (six columns, no vertical
# scroll), a controls row (Reset / Random / Bad-Good steppers / Blind), and a Confirm
# button that shrinks it back. Esc == Confirm. Begin Patrol (the normal button) is unchanged.

func _open_customize() -> void:
	if _cust_busy or _cust_open:
		return
	_cust_busy = true
	_cust_open = true
	_build_customize_overlay()
	# The overlay starts exactly over the right panel + grows left, so hide the
	# behind-panels the same frame — the grow reads as the right menu expanding.
	if _right_panel != null:
		_right_panel.visible = false
	if _left_panel != null:
		_left_panel.visible = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_cust_dim, "modulate:a", 0.92, 0.3)
	tw.tween_property(_cust_panel, "position", Vector2(16, 16), 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cust_panel, "size", Vector2(HD_W - 32, HD_H - 32), 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_cust_busy = false


func _close_customize() -> void:
	if _cust_busy or not _cust_open:
		return
	_cust_busy = true
	_save_cond_setup()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_cust_dim, "modulate:a", 0.0, 0.28)
	tw.tween_property(_cust_panel, "position", Vector2(RIGHT_HD + 16, 16), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cust_panel, "size", Vector2(HD_W - RIGHT_HD - 32, HD_H - 32), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(_cust_layer):
		_cust_layer.queue_free()
	_cust_layer = null
	_cust_dim = null
	_cust_panel = null
	_cond_checks = {}
	_cust_columns_box = null
	_cust_random_btn = null
	_bad_stepper_set = Callable()
	_good_stepper_set = Callable()
	_cust_blind_caption = null
	_cust_summary_lbl = null
	_cust_detail_name = null
	_cust_detail_value = null
	_cust_detail_blurb = null
	if _right_panel != null:
		_right_panel.visible = true
	if _left_panel != null:
		_left_panel.visible = true
	_cust_open = false
	_cust_busy = false
	_refresh_setup_summary()   # echo the new setup beside the Customize button


func _build_customize_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6   # above PatrolUI (5)
	layer.name = "CustomizeOverlay"
	add_child(layer)
	_cust_layer = layer
	# Dim — fades the whole hangar/backdrop to black behind the overlay.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.modulate.a = 0.0
	layer.add_child(dim)
	_cust_dim = dim
	# Panel — starts at the right-panel rect, grows to full-screen on open.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.position = Vector2(RIGHT_HD + 16, 16)
	panel.size = Vector2(HD_W - RIGHT_HD - 32, HD_H - 32)
	layer.add_child(panel)
	_cust_panel = panel
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	_build_customize_content(root)


func _build_customize_content(root: VBoxContainer) -> void:
	# Header — title + live summary.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(_label("CUSTOMIZE PATROL", UiTheme.LabelKind.HEADER))
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_spacer)
	_cust_summary_lbl = _label(_cond_summary_text(), UiTheme.LabelKind.STATUS_VALUE)
	head.add_child(_cust_summary_lbl)
	root.add_child(head)

	# Controls row — Reset · Random · Bad/Good steppers · Blind.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 16)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	var reset_btn := UiTheme.make_button("Reset", true)
	reset_btn.pressed.connect(_on_cond_reset)
	controls.add_child(reset_btn)
	var random_btn := UiTheme.make_button("Random", true)
	random_btn.pressed.connect(_on_cond_random)
	controls.add_child(random_btn)
	_cust_random_btn = random_btn
	controls.add_child(_make_stepper("Bad", _cond_bad, 0, 10, func(v):
		_cond_bad = v
		_save_cond_setup()
		_apply_blind_state()
		_update_customize_summary(),
		func(setter): _bad_stepper_set = setter))
	controls.add_child(_make_stepper("Good", _cond_good, 0, 10, func(v):
		_cond_good = v
		_save_cond_setup()
		_apply_blind_state()
		_update_customize_summary(),
		func(setter): _good_stepper_set = setter))
	controls.add_child(_make_toggle("Blind", _cond_blind, _on_blind_toggled))
	root.add_child(controls)

	# Blind caption — hidden unless Blind is on.
	_cust_blind_caption = _label("", UiTheme.LabelKind.CAPTION)
	_cust_blind_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_cust_blind_caption)
	root.add_child(HSeparator.new())

	# Body — detail panel (left) + three category groups (ENEMY | PLAYER | ECONOMY), each its own
	# bane|boon column pair (six columns total). The horizontal spread lets every condition sit
	# visible at once — no vertical scroll (the tallest column is ~13 rows, which fits the full-screen
	# HD overlay). No ScrollContainer: the design goal is everything on screen (see design doc).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_detail_panel())
	body.add_child(VSeparator.new())
	# The three category groups share the remaining width equally. Dimming this HBox (Blind) dims all
	# three at once, so it's the single node _apply_blind_state fades.
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 20)
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(groups)
	_cust_columns_box = groups
	groups.add_child(_build_category_group("ENEMY", "enemy"))
	groups.add_child(_build_category_group("PLAYER", "player"))
	groups.add_child(_build_category_group("ECONOMY", "economy"))

	root.add_child(HSeparator.new())
	# Confirm — saves + shrinks the overlay back.
	var confirm_row := CenterContainer.new()
	var confirm := UiTheme.make_button("Confirm Modifiers")
	confirm.pressed.connect(_close_customize)
	confirm_row.add_child(confirm)
	root.add_child(confirm_row)

	_apply_blind_state()
	_update_customize_summary()
	_set_detail_prompt()


# Detail panel — shows the currently hovered (or last toggled) condition.
func _build_detail_panel() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(440, 0)
	_cust_detail_name = _label("", UiTheme.LabelKind.HEADER)
	_cust_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_cust_detail_name)
	_cust_detail_value = _label("", UiTheme.LabelKind.STATUS_VALUE)
	v.add_child(_cust_detail_value)
	_cust_detail_blurb = _label("", UiTheme.LabelKind.BODY)
	_cust_detail_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_cust_detail_blurb)
	return v


# Neutral prompt when nothing is hovered.
func _set_detail_prompt() -> void:
	if _cust_detail_name == null:
		return
	_cust_detail_name.text = "Hover a condition"
	_cust_detail_name.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	_cust_detail_value.text = ""
	_cust_detail_blurb.text = "Banes raise the patrol's Difficulty; boons lower it. Pick any mix — or roll a random split with the Random button."


# Show a condition's name (colored by sign), signed Difficulty value, + blurb.
func _show_detail(id: String) -> void:
	if _cust_detail_name == null:
		return
	var t := Conditions.threat_of(id)
	var col := UiTheme.COLOR_DANGER if t > 0 else COLOR_BOON
	_cust_detail_name.text = Conditions.label(id)
	_cust_detail_name.add_theme_color_override("font_color", col)
	_cust_detail_value.text = "Difficulty %+d" % t
	_cust_detail_value.add_theme_color_override("font_color", col)
	_cust_detail_blurb.text = Conditions.blurb(id)


# One category group: a header pill + its own 2-column bane|boon grid. Three of these
# sit side by side (ENEMY | PLAYER | ECONOMY) so the whole vocabulary is visible without
# vertical scroll. Each group filters the CATALOG to its `category` (Conditions.category_of).
func _build_category_group(header_text: String, category: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_FILL
	var hdr := _label(header_text, UiTheme.LabelKind.SLOT_PILL)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hdr)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	_build_condition_grid(grid, category)
	return v


# Build one category's paired BANES | BOONS grid. Pairing is programmatic via group_of/
# threat_of, over just the ids in `category` (Conditions.category_of) — a mutex group with
# one bane + one boon becomes one aligned grid row; a group with two same-sign members stacks
# (one per row, opposite cell empty); ungrouped singles fill below in catalog order on their
# sign's side. (Cross-category mutex pairs — e.g. Fast Enemies here vs a same-group boon in
# another column — stay mutex-enforced live in _on_overlay_toggled, which reads group_of
# globally; within a column they simply render as singles.)
func _build_condition_grid(grid: GridContainer, category: String) -> void:
	grid.add_child(_column_header("BANES", UiTheme.COLOR_DANGER))
	grid.add_child(_column_header("BOONS", COLOR_BOON))
	var rows: Array = []            # each = {"bane": id|"", "boon": id|""}
	var seen: Dictionary = {}
	# First: grouped members, in first-encounter (catalog) order.
	for id in Conditions.CATALOG.keys():
		var sid := String(id)
		if Conditions.category_of(sid) != category:
			continue
		var grp := Conditions.group_of(sid)
		if grp == "" or seen.has(sid):
			continue
		var banes: Array = []
		var boons: Array = []
		for other in Conditions.CATALOG.keys():
			var soid := String(other)
			if Conditions.category_of(soid) != category:
				continue
			if Conditions.group_of(soid) == grp:
				seen[soid] = true
				if Conditions.threat_of(soid) > 0:
					banes.append(soid)
				else:
					boons.append(soid)
		var n: int = maxi(banes.size(), boons.size())
		for i in n:
			rows.append({
				"bane": banes[i] if i < banes.size() else "",
				"boon": boons[i] if i < boons.size() else "",
			})
	# Then: ungrouped singles, catalog order, on their sign's side.
	for id in Conditions.CATALOG.keys():
		var sid := String(id)
		if Conditions.category_of(sid) != category:
			continue
		if Conditions.group_of(sid) != "":
			continue
		if Conditions.threat_of(sid) > 0:
			rows.append({"bane": sid, "boon": ""})
		else:
			rows.append({"bane": "", "boon": sid})
	for r in rows:
		grid.add_child(_make_cond_cell(String(r["bane"])))
		grid.add_child(_make_cond_cell(String(r["boon"])))


func _column_header(text: String, col: Color) -> Label:
	var lbl := _label(text, UiTheme.LabelKind.SLOT_PILL)
	lbl.add_theme_color_override("font_color", col)
	return lbl


# One pick cell: compact checkbox + sign-colored name. An empty id → a spacer that
# keeps the paired column aligned. Hover (or toggle) updates the detail panel.
func _make_cond_cell(id: String) -> Control:
	if id == "":
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 30)
		return spacer
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = Conditions.blurb(id)
	var cb := CheckBox.new()
	cb.button_pressed = _cond_picked.has(id)
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_constant_override("h_separation", 0)   # trim the box footprint (no text)
	cb.custom_minimum_size = Vector2(30, 0)
	cb.toggled.connect(_on_overlay_toggled.bind(id))
	# The CheckBox swallows mouse_entered on itself, so hover it directly too (the label passes
	# through to the row via MOUSE_FILTER_IGNORE) — the WHOLE row drives the detail panel.
	cb.mouse_entered.connect(_show_detail.bind(id))
	row.add_child(cb)
	_cond_checks[id] = cb
	var name_lbl := _label(Conditions.label(id), UiTheme.LabelKind.BODY)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UiTheme.COLOR_DANGER if Conditions.threat_of(id) > 0 else COLOR_BOON
	name_lbl.add_theme_color_override("font_color", col)
	row.add_child(name_lbl)
	row.mouse_entered.connect(_show_detail.bind(id))
	return row


func _on_overlay_toggled(on: bool, id: String) -> void:
	if on:
		if not _cond_picked.has(id):
			_cond_picked.append(id)
		# Live mutex: drop any already-picked same-group id (uncheck it too).
		var grp := Conditions.group_of(id)
		if grp != "":
			for other in _cond_picked.duplicate():
				if other != id and Conditions.group_of(other) == grp:
					_cond_picked.erase(other)
					if _cond_checks.has(other):
						(_cond_checks[other] as CheckBox).set_pressed_no_signal(false)
	else:
		_cond_picked.erase(id)
	_save_cond_setup()
	_update_customize_summary()
	_show_detail(id)   # keyboard-less clarity: reflect the toggle in the detail panel


func _on_cond_reset() -> void:
	_cond_picked = []
	for id in _cond_checks:
		(_cond_checks[id] as CheckBox).set_pressed_no_signal(false)
	_save_cond_setup()
	_update_customize_summary()
	_set_detail_prompt()


func _on_cond_random() -> void:
	# Fresh randomize() seed — a pre-run UI action, NOT the deterministic Begin roll.
	# Clears previous picks first; re-click = re-roll.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# 0/0 = "surprise me": roll a random bad/good spread from this same rng, then reflect the
	# rolled counts in the steppers (visible feedback) before rolling the picks as usual.
	if _cond_bad <= 0 and _cond_good <= 0:
		var counts := _roll_surprise_counts(rng)
		_cond_bad = counts.x
		_cond_good = counts.y
		if _bad_stepper_set.is_valid():
			_bad_stepper_set.call(_cond_bad)
		if _good_stepper_set.is_valid():
			_good_stepper_set.call(_cond_good)
	_cond_picked = _mutex_filter(Conditions.roll_split(_cond_bad, _cond_good, rng.randi()))
	for id in _cond_checks:
		(_cond_checks[id] as CheckBox).set_pressed_no_signal(_cond_picked.has(String(id)))
	_save_cond_setup()
	_update_customize_summary()


# Draw a "surprise me" bad/good count from `rng` for the 0/0 case. Pure over the rng
# state, so a SEEDED rng (the Blind path) makes this deterministic per run_seed. Bad is
# drawn before good so both the Random (randomize) and Blind (seeded) paths agree.
static func _roll_surprise_counts(rng: RandomNumberGenerator) -> Vector2i:
	var bad := rng.randi_range(RAND_BAD_RANGE.x, RAND_BAD_RANGE.y)
	var good := rng.randi_range(RAND_GOOD_RANGE.x, RAND_GOOD_RANGE.y)
	return Vector2i(bad, good)


# Resolve a Blind roll into its final Condition list from a decorrelated seed. 0/0 = the
# "surprise me" case: draw a random bad/good spread from a rng seeded with `seed_value`,
# then roll the picks with the SAME stream's next draw (rng.randi()) — fully deterministic
# per run_seed. Any other count pair rolls straight. Pure + static → headless-testable.
static func _resolve_blind_conditions(bad: int, good: int, seed_value: int) -> Array:
	if bad <= 0 and good <= 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var counts := _roll_surprise_counts(rng)
		return Conditions.roll_split(counts.x, counts.y, rng.randi())
	return Conditions.roll_split(bad, good, seed_value)


func _on_blind_toggled(on: bool) -> void:
	_cond_blind = on
	_save_cond_setup()
	_apply_blind_state()
	_update_customize_summary()


# Blind ON → dim + disable the pick columns and show the "rolled secretly" caption.
func _apply_blind_state() -> void:
	if _cust_columns_box != null:
		_cust_columns_box.modulate.a = 0.35 if _cond_blind else 1.0
		for id in _cond_checks:
			(_cond_checks[id] as CheckBox).disabled = _cond_blind
	# Random rolls into the visible picks — meaningless (and misleading) under Blind, which
	# ignores them and rolls secretly at Begin. Disable + dim it to match the checkboxes.
	# (Reset stays active: clearing hidden picks is harmless and reads as "clear picks," not
	# "affect the blind roll," which is count-driven.)
	if _cust_random_btn != null:
		_cust_random_btn.disabled = _cond_blind
		_cust_random_btn.modulate.a = 0.35 if _cond_blind else 1.0
	if _cust_blind_caption != null:
		_cust_blind_caption.visible = _cond_blind
		if _cond_bad <= 0 and _cond_good <= 0:
			_cust_blind_caption.text = "Rolled secretly at launch — random spread"
		else:
			_cust_blind_caption.text = "Rolled secretly at launch — Bad %d · Good %d" % [_cond_bad, _cond_good]


func _update_customize_summary() -> void:
	var txt := _cond_summary_text()
	if _cust_summary_lbl != null:
		_cust_summary_lbl.text = txt
	_refresh_setup_summary()


# Echo the setup summary on the settings panel (visible when the overlay is closed).
func _refresh_setup_summary() -> void:
	if _cond_setup_summary_lbl != null:
		_cond_setup_summary_lbl.text = _cond_summary_text()


# Generic −/value/+ integer stepper (reuses the retired rocker's shape).
# `register_setter` (optional) is handed a `func(int)` that sets the stepper's value +
# label programmatically — used to reflect a rolled 0/0 "surprise me" count in the UI.
func _make_stepper(caption: String, initial: int, lo: int, hi: int, on_change: Callable, register_setter: Callable = Callable()) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label(caption, UiTheme.LabelKind.CAPTION))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var val_lbl := _label(str(initial), UiTheme.LabelKind.HEADER)
	val_lbl.custom_minimum_size = Vector2(48, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cur := {"v": initial}
	if register_setter.is_valid():
		register_setter.call(func(nv: int) -> void:
			cur["v"] = clampi(nv, lo, hi)
			val_lbl.text = str(cur["v"]))
	var minus := UiTheme.make_button("−", true)
	minus.custom_minimum_size = Vector2(48, 0)
	minus.pressed.connect(func() -> void:
		cur["v"] = clampi(int(cur["v"]) - 1, lo, hi)
		val_lbl.text = str(cur["v"])
		on_change.call(int(cur["v"])))
	row.add_child(minus)
	row.add_child(val_lbl)
	var plus := UiTheme.make_button("+", true)
	plus.custom_minimum_size = Vector2(48, 0)
	plus.pressed.connect(func() -> void:
		cur["v"] = clampi(int(cur["v"]) + 1, lo, hi)
		val_lbl.text = str(cur["v"])
		on_change.call(int(cur["v"])))
	row.add_child(plus)
	box.add_child(row)
	return box


# The live setup summary line: "N picked · Difficulty %+d" (or Blind counts).
# No payout percentages (reward coupling cut 2026-07-09).
func _cond_summary_text() -> String:
	if _cond_blind:
		if _cond_bad <= 0 and _cond_good <= 0:
			return "Blind · random spread"
		return "Blind · Bad %d · Good %d" % [_cond_bad, _cond_good]
	var eff := _mutex_filter(_cond_picked)
	return "%d picked · Difficulty %+d" % [eff.size(), Conditions.net_threat(eff)]


# ---- Custom run seed ------------------------------------------------------
# Resolve the seed box text into the int handed to Run.new_run(). Pure + static so
# tools/test_run_seed.gd can exercise it via load() without instancing the scene.
# Rules:
#   • trimmed-empty  → 0  (sentinel = "random roll" — new_run() falls back to randi())
#   • valid integer  → that int, via int() (GDScript ints are 64-bit; run_seed only ever
#                      feeds RNG seeding + a decorrelated XOR, never a %d-into-fixed-width
#                      format, so seeds beyond randi()'s 32-bit range are harmless)
#   • anything else  → String.hash() (a deterministic 32-bit hash, stable ACROSS sessions
#                      and platforms — same string always yields the same run), remapped to a
#                      nonzero constant if it happens to hash to 0 (0 would silently mean random)
# Reserved-0 edge: a player typing literal "0" parses to 0 → a RANDOM run (documented; 0 is the
# no-override sentinel). Accepted per spec.
const _SEED_HASH_ZERO_FALLBACK := 0x5EED  # nonzero stand-in when a text seed hashes to 0
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return 0
	if t.is_valid_int():
		return int(t)
	var h := int(t.hash())
	return h if h != 0 else _SEED_HASH_ZERO_FALLBACK


# Echo the resolved seed under the box so the player sees exactly what they'll get.
func _update_seed_caption() -> void:
	if _seed_caption == null:
		return
	var resolved := parse_seed(_seed_edit.text if _seed_edit != null else "")
	_seed_caption.text = "→ random" if resolved == 0 else "→ %d" % resolved


# ---- Conditions persistence ----------------------------------------------

func _load_cond_setup() -> void:
	if not FileAccess.file_exists(COND_SETUP_PATH):
		return
	var f := FileAccess.open(COND_SETUP_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if not (data is Dictionary):
		return
	# Migration: the old file carried a `mode` enum (Off/Picked/Random/Blind) — ignored
	# now; `blind` + `picked` fully describe the state. Legacy files gracefully load their
	# bad/good/picked and default blind=false.
	_cond_bad = clampi(int(data.get("bad", 0)), 0, 10)
	_cond_good = clampi(int(data.get("good", 0)), 0, 10)
	_cond_blind = bool(data.get("blind", false))
	_cond_picked = []
	for id in data.get("picked", []):
		var sid := String(id)
		if Conditions.CATALOG.has(sid):   # drop unknowns
			_cond_picked.append(sid)
	_cond_picked = _mutex_filter(_cond_picked)   # heal a stale/edited save


func _save_cond_setup() -> void:
	var data := {
		"picked": _cond_picked,
		"bad": _cond_bad,
		"good": _cond_good,
		"blind": _cond_blind,
	}
	var f := FileAccess.open(COND_SETUP_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


# Drop unknown ids + later members of any already-claimed mutex group (belt &
# braces against a hand-edited or stale save file).
func _mutex_filter(ids: Array) -> Array:
	var out: Array = []
	var groups: Dictionary = {}
	for id in ids:
		var sid := String(id)
		if not Conditions.CATALOG.has(sid):
			continue
		var grp := Conditions.group_of(sid)
		if grp != "" and groups.has(grp):
			continue
		out.append(sid)
		if grp != "":
			groups[grp] = true
	return out


# ---- Tuning rail ---------------------------------------------------------

func _toggle_rail() -> void:
	if _rail != null:
		_rail.visible = not _rail.visible


func _build_rail(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.92)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(HD_W - 470, 12)
	panel.size = Vector2(458, HD_H - 24)
	panel.visible = false
	layer.add_child(panel)
	_rail = panel
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(420, 0)
	scroll.add_child(v)
	v.add_child(_label("PATROL START TUNER", UiTheme.LabelKind.HEADER))
	v.add_child(_label("Tune ⚙ / Tab: hide · Esc: back", UiTheme.LabelKind.CAPTION))

	v.add_child(_label("Sequence", UiTheme.LabelKind.CAPTION))
	_slider(v, "menu_fade_time", "Menu fade (s)", 0.1, 1.5, 0.05)
	_slider(v, "rise_delay", "Delay before rise (s)", 0.0, 2.0, 0.05)
	_slider(v, "slide_time", "Hangar rise (s)", 0.6, 4.0, 0.05)
	_slider(v, "bars_fade_time", "Bars/panels fade (s)", 0.2, 1.5, 0.05)
	_slider(v, "bg_pan_ratio", "Background pan ratio", 0.0, 2.0, 0.05)

	v.add_child(_label("Takeoff", UiTheme.LabelKind.CAPTION))
	_slider(v, "engine_spool", "Engine spool (s)", 0.1, 2.0, 0.05)
	_slider(v, "rise_time", "Rise (s)", 0.2, 1.5, 0.05)
	_slider(v, "flyoff_time", "Fly-off (s)", 0.4, 2.5, 0.05)

	v.add_child(_label("Drop shadow / altitude", UiTheme.LabelKind.CAPTION))
	_slider_v2x(v, "shadow_land_offset", "Land offset X", 0.0, 8.0, 0.5)
	_slider_v2y(v, "shadow_land_offset", "Land offset Y", 0.0, 10.0, 0.5)
	_slider(v, "shadow_land_alpha", "Land alpha", 0.0, 1.0, 0.05)
	_slider_v2x(v, "shadow_fly_offset", "Fly offset X", 0.0, 16.0, 0.5)
	_slider_v2y(v, "shadow_fly_offset", "Fly offset Y", 0.0, 20.0, 0.5)
	_slider(v, "shadow_fly_scale", "Fly scale", 0.5, 1.5, 0.02)
	_slider(v, "shadow_fly_alpha", "Fly alpha", 0.0, 1.0, 0.05)

	v.add_child(_label("Lifter", UiTheme.LabelKind.CAPTION))
	_slider(v, "lift_set_time", "Lower / raise (s)", 0.2, 1.5, 0.05)
	_slider(v, "lift_fly_time", "Cross at altitude (s)", 0.4, 2.5, 0.05)
	_slider(v, "carry_distance", "Carry offset (px below centre)", 0.0, 24.0, 0.5)
	_slider(v, "grav_light_energy", "Grav light energy", 0.0, 3.0, 0.05)

	v.add_child(_label("Lighting", UiTheme.LabelKind.CAPTION))
	_slider_generic(v, "Scene dim (whole bay)", 0.2, 1.0, 0.02, scene_dim, _set_scene_dim)
	_slider_generic(v, "Runway pulse (rad/s)", 0.2, 4.0, 0.1, runway_speed, _set_runway_speed)

	v.add_child(_label("Shadows (prototype)", UiTheme.LabelKind.CAPTION))
	var sm := OptionButton.new()
	sm.add_item("Legacy (drop)", ShadowMode.LEGACY)
	sm.add_item("Key light", ShadowMode.KEY)
	sm.add_item("Fill lights (2x3)", ShadowMode.FILL)
	sm.selected = shadow_mode
	sm.item_selected.connect(func(i: int) -> void: set_shadow_mode(i))
	v.add_child(sm)
	var dyn := CheckBox.new()
	dyn.text = "Dynamic (tractor/lifter) casters"
	dyn.button_pressed = shadow_dynamic
	dyn.toggled.connect(func(on: bool) -> void: set_shadow_dynamic(on))
	v.add_child(dyn)
	_slider_generic(v, "Shadow length (px)", 0.0, 16.0, 0.5, shadow_length, func(x): _set_shadow_knob("shadow_length", x))
	_slider_generic(v, "Shadow alpha (per light)", 0.0, 1.0, 0.02, shadow_alpha, func(x): _set_shadow_knob("shadow_alpha", x))
	_slider_generic(v, "Shadow falloff (px)", 20.0, 300.0, 5.0, shadow_falloff, func(x): _set_shadow_knob("shadow_falloff", x))
	_slider_generic(v, "Shadow softness (scale+)", 0.0, 1.0, 0.05, shadow_softness, func(x): _set_shadow_knob("shadow_softness", x))
	_slider_generic(v, "Max shadows / object", 1.0, 8.0, 1.0, float(shadow_max), set_shadow_max)

	v.add_child(HSeparator.new())
	var replay := UiTheme.make_button("Replay Sequence")
	replay.pressed.connect(_replay)
	v.add_child(replay)
	var copy := UiTheme.make_button("Copy GDScript")
	copy.pressed.connect(_copy_gdscript)
	v.add_child(copy)


func _slider(parent: Node, prop: String, label: String, mn: float, mx: float, step: float) -> void:
	_slider_generic(parent, label, mn, mx, step, float(get(prop)), func(x: float) -> void: set(prop, x))


func _slider_v2x(parent: Node, prop: String, label: String, mn: float, mx: float, step: float) -> void:
	var v: Vector2 = get(prop)
	_slider_generic(parent, label, mn, mx, step, v.x, func(x: float) -> void: _set_v2(prop, x, true))


func _slider_v2y(parent: Node, prop: String, label: String, mn: float, mx: float, step: float) -> void:
	var v: Vector2 = get(prop)
	_slider_generic(parent, label, mn, mx, step, v.y, func(x: float) -> void: _set_v2(prop, x, false))


func _set_v2(prop: String, val: float, is_x: bool) -> void:
	var v: Vector2 = get(prop)
	if is_x:
		v.x = val
	else:
		v.y = val
	set(prop, v)


func _slider_generic(parent: Node, label: String, mn: float, mx: float, step: float, val: float, on_change: Callable) -> void:
	var head := HBoxContainer.new()
	var name_lbl := _label(label, UiTheme.LabelKind.CAPTION)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	var key := str(_rail_vals.size())
	var val_lbl := _label(_fmt(val, step), UiTheme.LabelKind.CAPTION)
	_rail_vals[key] = val_lbl
	head.add_child(val_lbl)
	parent.add_child(head)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void:
		on_change.call(x)
		val_lbl.text = _fmt(x, step))
	parent.add_child(s)


func _fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1.0 else "%.2f" % v


func _copy_gdscript() -> void:
	var lines := [
		"# Patrol Start tuned defaults:",
		"menu_fade_time = %s" % _f(menu_fade_time),
		"rise_delay = %s" % _f(rise_delay),
		"slide_time = %s" % _f(slide_time),
		"bars_fade_time = %s" % _f(bars_fade_time),
		"bg_pan_ratio = %s" % _f(bg_pan_ratio),
		"engine_spool = %s" % _f(engine_spool),
		"rise_time = %s" % _f(rise_time),
		"flyoff_time = %s" % _f(flyoff_time),
		"shadow_land_offset = Vector2(%s, %s)" % [_f(shadow_land_offset.x), _f(shadow_land_offset.y)],
		"shadow_land_alpha = %s" % _f(shadow_land_alpha),
		"shadow_fly_offset = Vector2(%s, %s)" % [_f(shadow_fly_offset.x), _f(shadow_fly_offset.y)],
		"shadow_fly_scale = %s" % _f(shadow_fly_scale),
		"shadow_fly_alpha = %s" % _f(shadow_fly_alpha),
		"lift_set_time = %s" % _f(lift_set_time),
		"lift_fly_time = %s" % _f(lift_fly_time),
		"carry_distance = %s" % _f(carry_distance),
		"grav_light_energy = %s" % _f(grav_light_energy),
		"scene_dim = %s" % _f(scene_dim),
		"runway_speed = %s" % _f(runway_speed),
		"shadow_mode = %d" % shadow_mode,
		"shadow_dynamic = %s" % str(shadow_dynamic),
		"shadow_length = %s" % _f(shadow_length),
		"shadow_alpha = %s" % _f(shadow_alpha),
		"shadow_falloff = %s" % _f(shadow_falloff),
		"shadow_softness = %s" % _f(shadow_softness),
		"shadow_max = %d" % shadow_max,
	]
	DisplayServer.clipboard_set("\n".join(lines))
	if _status != null:
		_status.text = "Copied tuned defaults to clipboard."


func _f(v: float) -> String:
	return "%.2f" % v


# ---- Sequence (menu → delay → rise + pan → hangar) -----------------------

# Default hull for a fresh patrol — catalog index 0 (the Reaver / "default Starblaster").
func _default_ship_idx() -> int:
	return 0


# LIVE start: drop the default hull straight onto the pad, readied, with its codex up — so the player
# can Begin the patrol at once (or ready a different ship). Skips the mandatory click-ready-wait-click
# loop the "start menu is slow" complaint was about. Its column slot is simply left empty.
func _preready_default_ship() -> void:
	var idx := _default_ship_idx()
	if idx < 0 or idx >= _ships.size():
		return
	var ship: Dictionary = _ships[idx]
	var host: Node2D = ship["host"]
	host.position = _pad
	_position_ship_button(ship)
	_readied_idx = idx
	_selected_idx = idx
	_move_select_light(idx)
	if _begin_btn != null:
		_begin_btn.disabled = false
	if _status != null:
		_status.text = "%s standing by on the pad. Begin the patrol, or ready another ship." % ShipCatalog.display_name(idx)
	_refresh_left_panel()   # codex + loadout up for the readied hull


# Cover the first post-swap frame with the captured main-menu image so the direct (no-black) scene
# swap is invisible — the player keeps seeing their menu until the crossfade dissolves it.
func _build_live_crossfade() -> void:
	if _menu_snapshot == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "MenuCrossfade"
	layer.layer = 80   # above PatrolUI (5), below a SceneTransition black cover (128)
	add_child(layer)
	var tr := TextureRect.new()
	tr.name = "MenuFrame"
	tr.texture = _menu_snapshot
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	_crossfade_layer = layer
	_menu_snapshot = null


# Player-facing "skip the patrol cinematics" preference (Settings.skip_patrol_anim). Only honored on a
# LIVE launch — the dev-tool launch always animates so the tuner stays useful. When true, the hangar
# drops straight into place (no rise/pan) and readying a different ship is instant (no lifter carry).
func _skip_anim() -> bool:
	if not _live_launch:
		return false
	var s := get_node_or_null("/root/Settings")
	return s != null and bool(s.skip_patrol_anim)


# LIVE launch (from the real main menu): no dummy menu, no second click, no dev chrome. Crossfade the
# captured menu frame out (no black) so the menu dissolves into the patrol backdrop, then run the
# hangar-rise sequence directly. With no snapshot (e.g. headless) just run the rise.
func _begin_live_launch() -> void:
	if _crossfade_layer != null and is_instance_valid(_crossfade_layer):
		# Skip mode: drop the captured menu frame immediately (no crossfade) — straight into the bay.
		if not _skip_anim():
			var tr := _crossfade_layer.get_node_or_null("MenuFrame")
			if tr != null:
				var tw := create_tween()
				tw.tween_property(tr, "modulate:a", 0.0, menu_fade_time)
				await tw.finished
		if is_instance_valid(_crossfade_layer):
			_crossfade_layer.queue_free()
		_crossfade_layer = null
	if is_instance_valid(self):
		_on_start_patrol()


func _on_start_patrol() -> void:
	if _started:
		return
	_started = true
	_music_intensity(1)   # Intensity_1 → Intensity_2
	# Skip mode (live launch only): no rise/pan — drop the assembled bay straight into place.
	if _skip_anim():
		_snap_hangar_in_place()
		return
	# 1. Fade the dummy menu out — DEV launch only. A live launch never built one (the real main menu
	#    already played that role), so this step is skipped and we go straight to the rise.
	if _menu_ui != null:
		var fade := create_tween()
		fade.tween_property(_menu_ui, "modulate:a", 0.0, menu_fade_time)
		await fade.finished
		_menu_ui.visible = false
	# 2. Beat before the bay rises.
	if rise_delay > 0.0:
		await get_tree().create_timer(rise_delay).timeout
	# 3. Streaks on (motion), rise + backdrop pan (driven off the hangar velocity) + bars/panels.
	_set_streaks(true)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_hangar, "position:y", 0.0, slide_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_left_sidebar, "modulate:a", 1.0, bars_fade_time).set_delay(maxf(slide_time - bars_fade_time, 0.0))
	tw.tween_property(_right_sidebar, "modulate:a", 1.0, bars_fade_time).set_delay(maxf(slide_time - bars_fade_time, 0.0))
	tw.tween_property(_left_panel, "modulate:a", 1.0, bars_fade_time).set_delay(maxf(slide_time - bars_fade_time + 0.3, 0.0))
	tw.tween_property(_right_panel, "modulate:a", 1.0, bars_fade_time).set_delay(maxf(slide_time - bars_fade_time + 0.3, 0.0))
	await tw.finished
	# 4. In place — everything's stationary, so the streaks switch off.
	_set_streaks(false)
	for s in _ships:
		_position_ship_button(s)
	_click_layer.visible = true


# Skip-mode counterpart to the rise: place the bay + panels at their post-rise end-state in one step,
# no tweens. Pans the celestials to where the rise would have left them (so the sky matches), then
# syncs _prev_hangar_y so _update_bg_pan is a no-op afterward.
func _snap_hangar_in_place() -> void:
	if _menu_ui != null:
		_menu_ui.visible = false
	_set_streaks(false)
	var dy: float = 0.0 - _prev_hangar_y
	for L in _celestial_layers:
		if is_instance_valid(L):
			(L as CanvasLayer).offset.y += dy * bg_pan_ratio
	_hangar.position.y = 0.0
	_prev_hangar_y = 0.0
	_left_sidebar.modulate.a = 1.0
	_right_sidebar.modulate.a = 1.0
	_left_panel.modulate.a = 1.0
	_right_panel.modulate.a = 1.0
	for s in _ships:
		_position_ship_button(s)
	_click_layer.visible = true


# ---- Interaction ----------------------------------------------------------

func _on_ship_clicked(idx: int) -> void:
	if _busy:
		return
	_selected_idx = idx
	_move_select_light(idx)
	_refresh_left_panel()


func _move_select_light(idx: int) -> void:
	var s: Dictionary = _ships[idx]
	var host: Node2D = s["host"]
	_select_light.position = host.position
	_select_light.enabled = true   # coming on — take a plate light slot (see LIGHT BUDGET, hangar_stage)
	if _select_light.energy <= 0.0:
		var tw := create_tween()
		tw.tween_property(_select_light, "energy", 1.1, 0.25)
	else:
		_select_light.energy = 1.1


func _on_livery_picked(c: Color) -> void:
	if _selected_idx < 0:
		return
	var s: Dictionary = _ships[_selected_idx]
	s["livery_color"] = c
	(s["livery_mat"] as ShaderMaterial).set_shader_parameter("tint_color", c)


func _on_ready_pressed() -> void:
	if _busy or _selected_idx < 0 or _selected_idx == _readied_idx:
		return
	# Skip mode (live launch only): no lifter carry — swap the hull onto the pad instantly.
	if _skip_anim():
		_ready_ship_instant(_selected_idx)
		return
	_busy = true
	# Gray Begin Patrol out for the whole carry — the pad is in flux until the lifter sets the
	# incoming hull down (clicks were already _busy-guarded; this makes the state visible).
	if _begin_btn != null:
		_begin_btn.disabled = true
	var incoming := _selected_idx
	if _status != null:
		_status.text = "Lifter moving %s to the pad…" % ShipCatalog.display_name(incoming)
	_set_lifter_engines(true)   # power up (engine glow fades in + animates) before it moves
	await get_tree().create_timer(0.4).timeout
	# Return the currently-readied ship to its slot first, then lift the new one onto the pad.
	if _readied_idx >= 0:
		await _lift_pick(_ships[_readied_idx], _ships[_readied_idx]["park_pos"])
	await _lift_pick(_ships[incoming], _pad)
	await _lift_return()
	_set_lifter_engines(false)  # back on the floor — power down
	_readied_idx = incoming
	_move_select_light(incoming)
	_music_intensity(2)   # progress into Main — rising energy
	_busy = false
	if _begin_btn != null:
		_begin_btn.disabled = false
	if _status != null:
		_status.text = "%s readied on the pad. Begin the patrol when ready." % ShipCatalog.display_name(incoming)
	_refresh_left_panel()


# Skip-mode counterpart to the lifter carry: return the currently-readied hull to its slot and drop
# the incoming hull straight onto the pad — no lifter, no tweens.
func _ready_ship_instant(incoming: int) -> void:
	if _readied_idx >= 0 and _readied_idx != incoming:
		var prev: Dictionary = _ships[_readied_idx]
		(prev["host"] as Node2D).position = prev["park_pos"]
		_position_ship_button(prev)
	var ship: Dictionary = _ships[incoming]
	(ship["host"] as Node2D).position = _pad
	_position_ship_button(ship)
	_readied_idx = incoming
	_move_select_light(incoming)
	_music_intensity(2)   # progress into Main — rising energy
	if _begin_btn != null:
		_begin_btn.disabled = false
	if _status != null:
		_status.text = "%s readied on the pad. Begin the patrol when ready." % ShipCatalog.display_name(incoming)
	_refresh_left_panel()


func _on_begin_pressed() -> void:
	if _busy or _readied_idx < 0:
		return
	_busy = true
	_begin_btn.disabled = true
	if _status != null:
		_status.text = "Launching…"
	_set_streaks(true)   # the ship's away — motion returns
	# Reset the run, then write the chosen hull + livery + run settings (new_run() clears them, so
	# it must come FIRST — mirrors main_menu._on_new_game's order).
	var run := get_node_or_null("/root/Run")
	if run != null:
		# Custom seed override (blank box → 0 → random). Passed INTO new_run() so the outpost
		# charge rolls + blind-condition split + sector gen all reproduce from the player's seed.
		run.new_run(parse_seed(_seed_edit.text if _seed_edit != null else ""))
		run.ship_variant = _readied_idx
		run.livery_color = _ships[_readied_idx]["livery_color"]
		run.livery_chosen = true
		run.set_meta("patrol_skip_tutorial", _skip_tutorial)
		run.set_meta("patrol_endless", _endless)
		_apply_conditions_for_run(run)
	await _launch(_ships[_readied_idx])
	# Hand off to the run: the tutorial onboarding (which funnels to the sector map), or straight to
	# the map when the player asked to skip it. The fly-out covers the swap.
	var dest: String = SectorMapRoute.SECTOR_MAP_SCENE if _skip_tutorial else "res://scenes/onboarding.tscn"
	SceneTransition.change_scene(get_tree(), dest)


# Resolve the Conditions setup into the final active list + install it through the
# single Run pipe. MUST be called AFTER new_run() (which zeroes bounty + re-seeds
# the loadout snapshot) and the run-settings writes. apply_conditions is NOT
# idempotent (it grants Starting Funds bounty), so call it EXACTLY ONCE and only
# for a non-empty list.
func _apply_conditions_for_run(run) -> void:
	var final_list: Array = []
	var blind := _cond_blind
	if blind:
		# Deterministic per-run roll off a DECORRELATED seed (run_seed ^ salt — the
		# same trick as outpost_name; never consumes the global/sector-gen RNG, so
		# layouts don't shift). Rolled here, hidden from the player until in-run. 0/0 =
		# the "surprise me" case: a random bad/good spread rolled from the SAME seeded
		# stream (still deterministic per run_seed). The result is empty → strict no-op
		# below ONLY if the rolled counts land at 0 (bad floor ≥ 1 makes that impossible
		# for the 0/0 case; a strict no-op still happens for an all-zero picked list).
		final_list = _resolve_blind_conditions(_cond_bad, _cond_good, int(run.run_seed) ^ COND_SEED_SALT)
	else:
		final_list = _mutex_filter(_cond_picked)   # defensive: heal a stale save
	if final_list.is_empty():
		return   # strict no-op — no apply_conditions, no summary meta
	run.apply_conditions(final_list)
	# Reveal hook (v1): a one-line summary meta. Visible picks list the labels + signed
	# Difficulty; Blind hides them (the outpost Status readout reveals them in-run).
	# No payout percentages (reward coupling cut 2026-07-09).
	if blind:
		run.set_meta("conditions_summary", "CONDITIONS: ??? (blind patrol)")
	else:
		var labels: Array = []
		for id in final_list:
			labels.append(Conditions.label(id))
		run.set_meta("conditions_summary", "CONDITIONS: %s (Difficulty %+d)" % [
			"  ·  ".join(labels), run.condition_net_threat()])


# Spool engines, then the ship flies up while the whole BAY slides down off the bottom — the
# outpost departing beneath you (mirrors outpost_arrival.depart: ship up, plate down). The ship is
# reparented into world space so it flies independently of the sinking hangar.
func _launch(s: Dictionary) -> void:
	var host: Node2D = s["host"]
	var glow: Sprite2D = s["glow"]
	var shadow: Sprite2D = s["shadow"]
	# Move the ship out of the hangar into world space (keeps its on-pad position) so the bay can
	# sink without dragging it; the trail's world-space lines then parent to the viewport correctly.
	if host.get_parent() != _world:
		host.reparent(_world)
	if s["trail"] == null:
		var trail := EngineTrailFx.new()
		host.add_child(trail)
		trail.setup(host, s["markers"], ENGINE_GLOW_COLOR, 0.0)
		s["trail"] = trail
	var lights: Array = []
	for mk in s["markers"]:
		var el := _make_point_light((mk as Marker2D).position, ENGINE_LIGHT_COLOR, ENGINE_LIGHT_SCALE, _light_tex)
		el.enabled = true   # about to spool up — enable before the tween (see LIGHT BUDGET, hangar_stage)
		host.add_child(el)
		lights.append(el)
	s["engine_lights"] = lights
	var spool := create_tween()
	spool.set_parallel(true)
	spool.tween_property(glow, "modulate:a", 1.0, engine_spool)
	for el in lights:
		# Lights LEAD the glow in (EASE_OUT front-loads the fade) so they read sooner. Roman 2026-06-26.
		spool.tween_property(el, "energy", ENGINE_LIGHT_ENERGY, engine_spool) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await spool.finished
	# Bay slides down (SINE/EASE_IN, like the outpost plate) as the ship lifts off + flies out.
	var bay := create_tween()
	bay.tween_property(_hangar, "position:y", NATIVE_H, rise_time + flyoff_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Engine lights flare to their brightest/biggest bloom right as the ship accelerates off the top
	# (EASE_IN peaks at the launch instant). Roman 2026-06-26.
	var flare := create_tween()
	flare.set_parallel(true)
	for el in lights:
		if is_instance_valid(el):
			flare.tween_property(el, "energy", ENGINE_LIGHT_ENERGY * ENGINE_FLARE_PEAK, rise_time + flyoff_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			flare.tween_property(el, "texture_scale", ENGINE_LIGHT_SCALE * ENGINE_FLARE_SCALE, rise_time + flyoff_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var fly := create_tween()
	if shadow != null:
		fly.parallel().tween_property(shadow, "position", shadow_fly_offset, rise_time)
		fly.parallel().tween_property(shadow, "scale", Vector2(shadow_fly_scale, shadow_fly_scale), rise_time)
		fly.parallel().tween_property(shadow, "modulate:a", shadow_fly_alpha, rise_time)
	fly.parallel().tween_property(host, "position:y", _pad.y - 10.0, rise_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fly.chain().tween_property(host, "position:y", FLYOFF_TARGET_Y, flyoff_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fly.finished
	var trail = s["trail"]
	if trail != null and is_instance_valid(trail):
		trail.set_emitting(false)
	if _select_light != null:
		_select_light.energy = 0.0
		_select_light.enabled = false


func _music_intensity(idx: int) -> void:
	var m := get_node_or_null("/root/Music")
	if m != null and m.has_method("set_intensity"):
		m.set_intensity(idx)


# ---- Replay (rail) -------------------------------------------------------

func _replay() -> void:
	_busy = false
	_started = false
	_selected_idx = -1
	_readied_idx = -1
	_grab = {}
	_altitude = 0.0
	_set_grav(false)
	_set_lifter_engines(false)
	if _lifter != null:
		_lifter.position = _lifter_idle
	for s in _ships:
		var host: Node2D = s["host"]
		# A launched ship was reparented into world space — put it back in the hangar.
		if host.get_parent() != _hangar:
			host.get_parent().remove_child(host)
			_hangar.add_child(host)
		host.position = s["park_pos"]
		host.z_index = 0
		(s["glow"] as Sprite2D).modulate.a = 0.0
		var sh: Sprite2D = s["shadow"]
		sh.position = shadow_land_offset
		sh.scale = Vector2.ONE
		sh.modulate = Color(0, 0, 0, shadow_land_alpha)
		if s["trail"] != null and is_instance_valid(s["trail"]):
			s["trail"].queue_free()
		s["trail"] = null
		for el in s["engine_lights"]:
			if is_instance_valid(el):
				el.queue_free()
		s["engine_lights"] = []
		_position_ship_button(s)
	if _select_light != null:
		_select_light.energy = 0.0
		_select_light.enabled = false
	_hangar.position = Vector2(0, NATIVE_H)
	_prev_hangar_y = NATIVE_H
	for i in _celestial_layers.size():
		if is_instance_valid(_celestial_layers[i]):
			(_celestial_layers[i] as CanvasLayer).offset = _celestial_start[i]
	_left_sidebar.modulate.a = 0.0
	_right_sidebar.modulate.a = 0.0
	_left_panel.modulate.a = 0.0
	_right_panel.modulate.a = 0.0
	_click_layer.visible = false
	if _begin_btn != null:
		_begin_btn.disabled = true
	if _menu_ui != null:
		_menu_ui.visible = true
		_menu_ui.modulate.a = 1.0
	_refresh_left_panel()
	if _status != null:
		_status.text = "Ready a ship, then begin the patrol."
	_on_start_patrol()


# ---- Misc ----------------------------------------------------------------

func _panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.92)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


func _label(text: String, kind: int) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, kind)
	return l


func _back() -> void:
	if _busy:
		return
	# LIVE launch backs out by REVERSING the intro (Roman 2026-07-11): panels fade out, the bay sinks
	# away (celestials pan back down automatically via _update_bg_pan), then the main menu re-adopts
	# the live backdrop and fades its logo/buttons in — no fade-to-black, no regenerated sky.
	# Dev launch, skip-anim mode, or mid-intro (rise still running) keep the plain covered transition.
	if not _live_launch or _skip_anim() or _click_layer == null or not _click_layer.visible:
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
		return
	_busy = true
	_click_layer.visible = false
	_music_intensity(0)   # back to the menu's calm base layer
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_left_sidebar, "modulate:a", 0.0, bars_fade_time)
	fade.tween_property(_right_sidebar, "modulate:a", 0.0, bars_fade_time)
	fade.tween_property(_left_panel, "modulate:a", 0.0, bars_fade_time)
	fade.tween_property(_right_panel, "modulate:a", 0.0, bars_fade_time)
	await fade.finished
	# Streaks on for the descent (motion), bay sinks back out of view — the exact reverse of the rise.
	_set_streaks(true)
	var tw := create_tween()
	tw.tween_property(_hangar, "position:y", float(NATIVE_H), slide_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_set_streaks(false)
	# Hand the LIVE backdrop back to the menu (mirror of the forward handoff in main_menu._on_new_game):
	# detach the upscaled-backdrop SubViewport so change_scene's free of this scene leaves it alive;
	# main_menu re-adopts + consumes it (freeing it if adoption is impossible).
	var run := get_node_or_null("/root/Run")
	if run != null and _backdrop != null and is_instance_valid(_backdrop):
		var sub := _backdrop.get_parent() as SubViewport
		if sub != null:
			if sub.get_parent() != null:
				sub.get_parent().remove_child(sub)
			run.set_meta("menu_backdrop_live", sub)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Esc closes the Customize overlay (== Confirm); otherwise it backs out.
			if _cust_open:
				_close_customize()
			else:
				_back()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			_toggle_rail()
			get_viewport().set_input_as_handled()
