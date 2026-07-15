extends Control

# Parallax V4 Showcase (Roman 2026-07-06) — A/B the backdrop review's proposed fixes LIVE against
# the current look, over the REAL backdrop_coordinator at the combat-live drift (50). A thin driver
# over WP1's inert-by-default knobs: nothing here reimplements parallax — it flips coordinator +
# per-layer exports and calls regenerate(stored_seed) for the size/streak knobs that need a respawn.
#
# CURRENT vs PROPOSED presets set every knob to the plan doc's table. Each feature section has a
# master CheckButton: ON = apply that section's sliders; OFF = hold that feature at CURRENT values
# (so Roman can mix, e.g. proposed ratios + current brightness). Everything recomputes on any change.
#
# Knobs persist to user://tuners/parallax_showcase.json; Copy GDScript emits a paste-ready block
# grouped by REAL destination (coordinator exports / per-layer .tscn overrides / layer_* exports).

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const MenuBackdrop = preload("res://scripts/ui/menu_backdrop.gd")
const HdScreen = preload("res://scripts/ui/hd_screen.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
# WP11: gameplay-true backdrop authoring (the same module the sector map uses). GAMEPLAY source rolls
# a simulated node through this and feeds the result to coordinator.stellar_override.
const StellarGameplay = preload("res://scripts/parallax/stellar_gameplay.gd")

const CONFIG_PATH := "user://tuners/parallax_showcase.json"
const SHIP_TEX := preload("res://graphics/player/player_ship_a_body.png")

# Planet-type OptionButton (index 0 = Random; 1.. map to layer_planet PLANETS idx via i-1).
const PLANET_TYPE_NAMES := ["Random", "LavaWorld", "IceWorld", "DryTerran", "GasPlanet", "NoAtmosphere", "LandMasses", "BlackHole", "Galaxy", "Star", "GasPlanetLayers", "Rivers"]

const BAND_HALF := 108.0   # (X_MAX - X_MIN) / 2 = 216/2
const PANEL_W := 460.0      # control-panel column width (fixed so long CheckButton labels can't balloon it)

# ── The two presets (plan doc table). Keys map 1:1 to _vals entries. ─────────
const CURRENT := {
	"stars_far": 0.005, "stars_near": 0.02, "planet_rate": 0.03,
	"far_rate": 0.2, "mid_rate": 0.5, "near_rate": 1.2, "drift_speed": 50.0,
	"bright_far": 0.2, "bright_mid": 0.4, "bright_near": 0.6,
	"contrast_far": 0.0, "contrast_mid": 0.7,
	"rock_near_min": 72.0, "rock_near_max": 308.0, "rock_size_pow": 3.0,
	# WP10: alphas re-anchored to Roman's ported Nebula Lab tune (the OLD 0.1/0.2/0.15 presets
	# were authored against the retired nebula recipe and would crush the new one).
	"neb_far": 1.0, "neb_mid": 0.5, "neb_near": 1.0,
	"streak_speed": 750.0, "streak_alpha": 0.6, "streak_var_min": 0.8, "streak_count": 14.0,
	"use_dominant_grade": false, "streak_tint_palette": false,
	"lateral_strength": 0.0, "drift_variance": 0.0, "lateral_wander": 0.0,
	"use_palette": false, "forced_kind": "",
	# WP7 — WP5 engine knobs surfaced.
	"pixel_snap": true,                                      # viewport snap ON (today's steppy motion)
	"ast_mult_far": 1.0, "ast_mult_mid": 1.0, "ast_mult_near": 1.0,   # asteroid_layer_mult = ONE
	"body_parallax": 0.0,                                    # layer scrolls as one rigid plate
	# WP9 — star FX tiers (LayerPlanet exports, respawn-class).
	"star_fx": false, "star_sparkle_max": 32.0, "star_clamp_max": 120.0, "halo_scale_mult": 1.0,
	"halo_mid_alpha": 0.75, "halo_core_intensity": 1.5,
	"sparkle_decay": 0.3, "sparkle_scale_mult": 1.0, "dot_size_frac": 0.45, "dot_hdr": 2.5,
}
const PROPOSED := {
	"stars_far": 0.01, "stars_near": 0.03, "planet_rate": 0.07,
	"far_rate": 0.18, "mid_rate": 0.45, "near_rate": 1.8, "drift_speed": 50.0,
	"bright_far": 0.2, "bright_mid": 0.5, "bright_near": 0.95,
	"contrast_far": 0.5, "contrast_mid": 0.7,
	"rock_near_min": 110.0, "rock_near_max": 308.0, "rock_size_pow": 1.6,
	"neb_far": 1.0, "neb_mid": 0.5, "neb_near": 1.0,   # WP10: the ported lab tune (both presets)
	"streak_speed": 480.0, "streak_alpha": 0.35, "streak_var_min": 0.5, "streak_count": 14.0,
	"use_dominant_grade": true, "streak_tint_palette": true,
	"lateral_strength": 28.0, "drift_variance": 2.0, "lateral_wander": 0.3,
	"use_palette": true, "forced_kind": "",
	# WP7 — WP5 engine knobs surfaced.
	"pixel_snap": false,                                     # smooth planet motion (needs HD raster to SEE it)
	"ast_mult_far": 2.0, "ast_mult_mid": 1.0, "ast_mult_near": 0.7,   # far busiest, near sparsest
	"body_parallax": 1.0,                                    # full per-body depth spread
	# WP9 — star FX tiers ON; thresholds start at the plan-doc anchors (sparkle<32, cap 120, halo ×1.0).
	"star_fx": true, "star_sparkle_max": 32.0, "star_clamp_max": 120.0, "halo_scale_mult": 1.0,
	"halo_mid_alpha": 0.75, "halo_core_intensity": 1.5,
	"sparkle_decay": 0.3, "sparkle_scale_mult": 1.0, "dot_size_frac": 0.45, "dot_hdr": 2.5,
}

# Composition-kind picker (WP4): OptionButton index → coordinator.forced_kind ("" = Auto/weighted).
const KIND_NAMES := ["Auto", "System", "Planet", "Asteroid", "Nebula"]
const KIND_VALUES := ["", "system", "planet", "asteroid", "nebula"]

# ── Composition source (WP11) ────────────────────────────────────────────────
# Composer = the StellarComposer full-variety fallback (WP3/4). Gameplay = the sector-map authoring
# (StellarGameplay) piped through coordinator.stellar_override — rolls THE SORTS OF BACKGROUNDS PLAY
# PRODUCES. The kind picker only applies to Composer mode.
const SOURCE_NAMES := ["Composer", "Gameplay"]
const SOURCE_VALUES := ["composer", "gameplay"]

# Simulated node-type weights for GAMEPLAY mode. Approximates a real sector row's backdrop mix:
# run_state rolls per-POI combat 5/9, hazard 2/9 (→ minefield/asteroid_field 50/50), signal 2/9
# (signal reads visually like combat for the backdrop, folded into "combat"). belt_adjacent (a
# combat node NEXT TO a belt) + boss (the row's star-only endpoint) are added for backdrop variety —
# they aren't POI-type rolls in the map, but they ARE distinct backdrops the player sees. Weights sum 1.
const GP_TYPE_WEIGHTS := {
	"combat": 0.46,          # planet backdrop (combat + signal), the common case
	"asteroid_field": 0.16,  # belt: has_asteroids, no planet
	"minefield": 0.14,       # planet backdrop (mine decor is off in the lab)
	"belt_adjacent": 0.16,   # planet + BELT_DENSITY_ADJACENT drifting rocks
	"boss": 0.08,            # star-only endpoint (compute_boss_stellar)
}
const GP_ROW_END_X := 448.0  # boss column — the frac span denominator (matches run_state)

# Slider specs per section: [key, label, min, max, step]. Section master keys listed in SECTIONS.
const SEC_SCROLL := "scroll"
const SEC_BRIGHT := "bright"
const SEC_ROCK := "rock"
const SEC_GRADE := "grade"
const SEC_LATERAL := "lateral"
const SEC_DRIFT := "drift"
const SEC_STREAK := "streak"
const SEC_NEBULA := "nebula"
const SEC_DENSITY := "density"   # WP7: asteroid count gradient (asteroid_layer_mult)

# Which knobs need a coordinator.regenerate(stored_seed) rather than a live apply.
# WP7 respawn-class additions: asteroid_layer_mult (count scaling happens in _populate) and
# body_parallax (bodies register their depth_mult at spawn only). pixel_snap is NOT here — it's
# a live viewport flag.
const RESPAWN_KEYS := ["rock_near_min", "rock_near_max", "rock_size_pow", "streak_speed", "streak_count", "streak_var_min", "streak_alpha", "drift_variance", "ast_mult_far", "ast_mult_mid", "ast_mult_near", "body_parallax", "star_fx", "star_sparkle_max", "star_clamp_max", "halo_scale_mult", "halo_mid_alpha", "halo_core_intensity", "sparkle_decay", "sparkle_scale_mult", "dot_size_frac", "dot_hdr"]

var _backdrop_sub: SubViewport = null
var _backdrop: Node = null
var _seed: int = 12345               # stored seed so respawn-knobs change ONLY that property

# WorldEnvironment (Item 1): combat's HDR glow so planet-palette HDR boosts + star halos actually
# bloom. The node lives ALWAYS as a child of the backdrop SubViewport (frees with the scene — no
# orphan leak, unlike parallax_tuner's toggle-off path). The Bloom CheckButton flips glow_enabled +
# use_hdr_2d together so OFF = plain LDR (old look), ON = combat HDR+glow.
var _we_node: WorldEnvironment = null
var _env: Environment = null
var _bloom_on: bool = true

# HD raster (WP7 critical finding). The lab's backdrop SubViewport renders 480×270 nearest-upscaled
# ×4 by default (today's lab view) — at that raster the pixel_snap toggle is a visual NO-OP (the
# 480 grid quantizes regardless). Combat renders 480-logical content at 1920×1080 (project stretch
# mode canvas_items). HD raster ON mirrors that with SubViewport.size_2d_override: content stays in
# 480-logical space (layers/nebula/ship all hardcode 480 coords, verified) while the viewport
# rasterizes at 1920×1080 — so pixel_snap=false actually smooths planet motion combat-accurately.
# Default ON (combat-accurate is what Roman judges). Lab-only — never emitted in Copy GDScript.
var _hd_raster: bool = true

# Live tunable values (seeded from CURRENT, overwritten by preset/load/sliders).
var _vals: Dictionary = CURRENT.duplicate(true)
# Per-section master toggles: true = apply this section's sliders; false = hold at CURRENT.
var _sec_on := {
	SEC_SCROLL: true, SEC_BRIGHT: true, SEC_ROCK: true, SEC_GRADE: true,
	SEC_LATERAL: true, SEC_DRIFT: true, SEC_STREAK: true, SEC_NEBULA: true,
	SEC_DENSITY: true,
}
var _planet_type: int = 0            # 0 = random

# Lateral strafe input.
var _ship: Sprite2D = null
var _ship_x: float = 240.0
var _auto_sweep: bool = false
var _time: float = 0.0

# UI refs for live readouts.
var _status: Label = null
var _swatch: ColorRect = null
var _clamp_lbl: Label = null
var _slider_val_labels := {}         # key -> Label (to refresh on preset)
var _slider_nodes := {}              # key -> HSlider
var _bool_cbs := {}                  # _vals bool-key -> CheckButton (refresh on preset)

# WP11 composition source (Composer / Gameplay).
var _source: String = "composer"     # persisted; default Composer (WP4 behavior unchanged)
var _gp_depth: int = 0               # sector depth → sectors_cleared (exotic-star odds); row = depth % 3
var _gp_type: String = "combat"      # rolled node type (only changes on Generate New)
var _source_dd: OptionButton = null
var _gp_depth_lbl: Label = null

# WP4 composition + palette UI refs.
var _kind_dd: OptionButton = null
var _status_line: Label = null       # rolled composition readout (kind/nebula/asteroids/bodies)
var _palette_master_cb: CheckButton = null
var _pal_swatches := {}              # "key"/"accent"/"dust"/"deep" -> ColorRect

# Test hook: force every section master ON + defaults (used by the headless lab test so a
# persisted JSON with a section toggled off can't skew preset assertions).
func force_all_sections_on() -> void:
	for k in _sec_on.keys():
		_sec_on[k] = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HdViewportScope.attach(self)
	_load()
	_build_backdrop()
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	MenuBackdrop.drop_celestials(_backdrop)
	_apply_all(true)   # initial: forced regenerate so rock/planet knobs land
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _process(delta: float) -> void:
	_time += delta
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	# Strafe input → ship sprite → coordinator.set_lateral_input.
	if _auto_sweep:
		_ship_x = Playfield.CENTER.x + sin(_time * TAU / 4.0) * BAND_HALF
	else:
		var dir := Input.get_axis("left", "right")
		if dir != 0.0:
			_ship_x = clampf(_ship_x + dir * 140.0 * delta, Playfield.X_MIN, Playfield.X_MAX)
	if _ship != null and is_instance_valid(_ship):
		_ship.position.x = _ship_x
	var norm_x: float = (_ship_x - Playfield.CENTER.x) / BAND_HALF
	if _backdrop.has_method("set_lateral_input"):
		_backdrop.set_lateral_input(norm_x)
	# Live dominant-color swatch.
	if _swatch != null and is_instance_valid(_swatch):
		var lp := _backdrop.get_node_or_null("LayerPlanet")
		if lp != null and lp.has_method("get_dominant_color"):
			_swatch.color = lp.get_dominant_color()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


# ── Backdrop ────────────────────────────────────────────────────────────────

func _build_backdrop() -> void:
	_backdrop = MenuBackdrop.make()
	_backdrop.set("drift_speed", 50.0)             # combat-live — DELIBERATE (tuning at 22 was a trap)
	_backdrop.set("use_composer_fallback", true)   # WP4: full-variety fallback drives what spawns
	# NOTE: force_asteroids is deliberately NOT set — the composer now decides has_asteroids, so rocks
	# follow the rolled kind. The ROCK SIZES section is demonstrated by picking kind=Asteroid.
	if _planet_type > 0:
		_backdrop.set("forced_planet_idx", _planet_type - 1)
	_backdrop_sub = HdScreen.add_upscaled_backdrop(self, _backdrop)
	# HD raster (WP7): reconfigure the just-built 480×270 SubViewport to combat's render path when ON.
	# add_upscaled_backdrop's TextureRect uses STRETCH_SCALE + NEAREST, which correctly shows a 1920
	# texture 1:1 (HD ON) OR a 480 texture ×4 (HD OFF) with no lab-side display change needed.
	_apply_hd_raster(_hd_raster)
	# HDR + combat-matched WorldEnvironment (Item 1). add_upscaled_backdrop builds an LDR SubViewport;
	# combat's glow relies on the ROOT viewport being hdr_2d=true + a WorldEnvironment. Mirror that on
	# THIS SubViewport only (project setting is per-window; a hand-built SubViewport defaults LDR).
	_backdrop_sub.use_hdr_2d = _bloom_on
	_we_node = WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CANVAS      # = main.tscn background_mode 3
	_env.glow_enabled = _bloom_on
	_env.glow_intensity = 0.8
	_env.glow_strength = 0.75
	_env.glow_blend_mode = 1
	_env.glow_hdr_threshold = 1.5
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = 1.0
	_env.adjustment_saturation = 1.0
	_we_node.environment = _env
	_backdrop_sub.add_child(_we_node)              # parented → frees with the scene (no orphan leak)
	# Ship sprite riding the bottom of the playfield band. player_ship_a_body.png is a 3-frame
	# horizontal bank strip — render the neutral (center) frame, not the whole strip (Item 7).
	_ship = Sprite2D.new()
	_ship.texture = SHIP_TEX
	_ship.hframes = 3
	_ship.frame = 1
	_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship.position = Vector2(_ship_x, 240.0)
	_backdrop_sub.add_child(_ship)


func _set_bloom(on: bool) -> void:
	_bloom_on = on
	if _env != null:
		_env.glow_enabled = on
	if _backdrop_sub != null and is_instance_valid(_backdrop_sub):
		_backdrop_sub.use_hdr_2d = on   # OFF = plain LDR (old look); ON = combat HDR+glow


# HD raster (WP7). ON = combat-accurate: the SubViewport rasterizes at 1920×1080 while its 2D content
# stays authored in 480-logical space via size_2d_override_stretch (exactly how the game's canvas_items
# stretch renders 480 content at the 1080p window). This is the engine's built-in "logical res ≠ render
# res" lever — no Node2D scaling, so the CanvasLayer children never need a hand-rolled transform (a
# CanvasLayer does NOT inherit a parent Node2D scale, which is why manual ×4 scaling was rejected). The
# layers/nebula/ship all place content with hardcoded 480/270 constants, so nothing depends on the
# viewport reporting 480 — content is byte-identical in both modes; only the raster resolution changes.
# OFF = today's lab view: native 480×270, nearest-upscaled ×4 by the TextureRect.
func _apply_hd_raster(on: bool) -> void:
	_hd_raster = on
	if _backdrop_sub == null or not is_instance_valid(_backdrop_sub):
		return
	if on:
		_backdrop_sub.size = Vector2i(1920, 1080)
		_backdrop_sub.size_2d_override = Vector2i(480, 270)
		_backdrop_sub.size_2d_override_stretch = true
	else:
		_backdrop_sub.size_2d_override_stretch = false
		_backdrop_sub.size_2d_override = Vector2i(0, 0)   # (0,0) = disabled → use size
		_backdrop_sub.size = Vector2i(480, 270)
	# Re-assert the viewport snap for the current pixel_snap value (a size/override change leaves it,
	# but keep the two in lockstep so a toggle is never in a half-configured state).
	_apply_viewport_snap()


# Drive the backdrop viewport's snap_2d_transforms_to_pixel from the pixel_snap value. layer_base's
# pixel_snap setter only ever forces it FALSE (its inert-default contract), so the lab owns restoring
# the TRUE direction. Snap ON + HD raster = combat today (steppy slow planet); snap OFF + HD raster =
# the smooth proposed motion at combat-accurate raster.
func _apply_viewport_snap() -> void:
	if _backdrop_sub != null and is_instance_valid(_backdrop_sub):
		_backdrop_sub.snap_2d_transforms_to_pixel = bool(_v(SEC_SCROLL, "pixel_snap"))


func _regenerate() -> void:
	if _backdrop != null and is_instance_valid(_backdrop) and _backdrop.has_method("regenerate"):
		_backdrop.regenerate(_seed)


func _layer(name: String) -> Node:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return null
	return _backdrop.get_node_or_null(name)


# Value for `key`, honoring the section master toggle: OFF → CURRENT column.
func _v(section: String, key: String):
	if _sec_on.get(section, true):
		return _vals[key]
	return CURRENT[key]


# ── Apply ─────────────────────────────────────────────────────────────────────

func _apply_all(force_respawn: bool = false) -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	# Composition source (WP11): Composer fallback (WP4) vs Gameplay (sector-map authoring via
	# stellar_override). Both are respawn-class — consumers apply during _populate, so any change here
	# arrives via a regenerate below.
	if _source == "gameplay":
		# Author a gameplay-true dict from the module + pipe it in — NEVER writes Run (the P1 lesson).
		_backdrop.set("use_composer_fallback", false)
		_backdrop.set("forced_kind", "")   # composer-only; ignored while an override drives the scene
		_backdrop.set("stellar_override", _author_gameplay_dict())
	else:
		_backdrop.set("stellar_override", {})   # clear so Composer sees an empty stellar + composes
		_backdrop.set("use_composer_fallback", true)
		_backdrop.set("forced_kind", String(_vals.get("forced_kind", "")))
	_backdrop.set("use_palette", bool(_vals.get("use_palette", false)))
	# Scroll ratios (live).
	var stars := _layer("LayerStars")
	# NOTE: layer_stars FAR_RATE/NEAR_RATE are consts — can't set live; shipped via Copy block only.
	var lp := _layer("LayerPlanet")
	if lp != null: lp.set("scroll_rate", float(_v(SEC_SCROLL, "planet_rate")))
	var lf := _layer("LayerStellarFar")
	var lm := _layer("LayerStellarMid")
	var ln := _layer("LayerStellarNear")
	if lf != null: lf.set("scroll_rate", float(_v(SEC_SCROLL, "far_rate")))
	if lm != null: lm.set("scroll_rate", float(_v(SEC_SCROLL, "mid_rate")))
	if ln != null: ln.set("scroll_rate", float(_v(SEC_SCROLL, "near_rate")))
	_backdrop.set("drift_speed", float(_v(SEC_SCROLL, "drift_speed")))
	# Pixel snap (WP7 item 2) — a viewport-wide flag. Set it on the planet layer (real property that
	# ships) AND drive the viewport directly (layer_base only forces the FALSE direction). Live.
	if lp != null and "pixel_snap" in lp:
		lp.set("pixel_snap", bool(_v(SEC_SCROLL, "pixel_snap")))
	_apply_viewport_snap()

	# Asteroid count gradient (WP7 item 4) — respawn-class: set on the coordinator BEFORE the
	# regenerate below so _populate scales the per-band counts. Vector3(far, mid, near).
	_backdrop.set("asteroid_layer_mult", Vector3(
		float(_v(SEC_DENSITY, "ast_mult_far")),
		float(_v(SEC_DENSITY, "ast_mult_mid")),
		float(_v(SEC_DENSITY, "ast_mult_near"))))

	# Brightness ramp (live).
	if lf != null:
		lf.set("brightness", float(_v(SEC_BRIGHT, "bright_far")))
		lf.set("contrast", float(_v(SEC_BRIGHT, "contrast_far")))
	if lm != null:
		lm.set("brightness", float(_v(SEC_BRIGHT, "bright_mid")))
		lm.set("contrast", float(_v(SEC_BRIGHT, "contrast_mid")))
	if ln != null:
		ln.set("brightness", float(_v(SEC_BRIGHT, "bright_near")))

	# Rock sizes (respawn) — near layer only, per the plan.
	if ln != null:
		ln.set("asteroid_min_size", float(_v(SEC_ROCK, "rock_near_min")))
		ln.set("asteroid_max_size", float(_v(SEC_ROCK, "rock_near_max")))
		ln.set("asteroid_size_pow", float(_v(SEC_ROCK, "rock_size_pow")))

	# Palette grade (live).
	_backdrop.set("use_dominant_grade", bool(_v(SEC_GRADE, "use_dominant_grade")))

	# Lateral parallax (live).
	_backdrop.set("lateral_strength", float(_v(SEC_LATERAL, "lateral_strength")))

	# Rock drift + planet wander (drift_variance = respawn; wander = live).
	for l in [lf, lm, ln]:
		if l != null:
			l.set("drift_variance", float(_v(SEC_DRIFT, "drift_variance")))
	if lp != null:
		lp.set("lateral_wander", float(_v(SEC_DRIFT, "lateral_wander")))
		# Per-body parallax (WP7 item 6) — respawn-class: bodies register their depth_mult at spawn,
		# so it takes effect on the regenerate below.
		if "body_parallax" in lp:
			lp.set("body_parallax", float(_v(SEC_DRIFT, "body_parallax")))

	# Star FX tiers (WP9) — respawn-class: layer_planet builds sparkle/halo children + clamps star
	# size at spawn, so these land on the regenerate below. Read straight from _vals (the star_fx
	# CheckButton is the section master, like use_palette — no _sec_on gating).
	if lp != null:
		lp.set("star_fx", bool(_vals.get("star_fx", false)))
		lp.set("star_sparkle_max", float(_vals.get("star_sparkle_max", 32.0)))
		lp.set("star_clamp_max", float(_vals.get("star_clamp_max", 120.0)))
		lp.set("halo_scale_mult", float(_vals.get("halo_scale_mult", 1.0)))
		lp.set("halo_mid_alpha", float(_vals.get("halo_mid_alpha", 0.75)))
		lp.set("halo_core_intensity", float(_vals.get("halo_core_intensity", 1.5)))
		lp.set("sparkle_decay", float(_vals.get("sparkle_decay", 0.3)))
		lp.set("sparkle_scale_mult", float(_vals.get("sparkle_scale_mult", 1.0)))
		lp.set("dot_size_frac", float(_vals.get("dot_size_frac", 0.45)))
		lp.set("dot_hdr", float(_vals.get("dot_hdr", 2.5)))

	# Streaks (speed/count/var-min = respawn; alpha/tint = respawn too since the emitter
	# builds its gradient at spawn — layer_streaks.reset() rebuilds it).
	var ls := _layer("LayerStreaks")
	if ls != null:
		ls.set("streak_speed", float(_v(SEC_STREAK, "streak_speed")))
		ls.set("streak_count", int(_v(SEC_STREAK, "streak_count")))
		ls.set("streak_alpha", float(_v(SEC_STREAK, "streak_alpha")))
		ls.set("streak_speed_variance_min", float(_v(SEC_STREAK, "streak_var_min")))
		var tint: Color = Color.WHITE
		if bool(_v(SEC_STREAK, "streak_tint_palette")) and lp != null and lp.has_method("get_dominant_color"):
			tint = lp.get_dominant_color()
		ls.set("streak_tint", tint)
		# Coordinator overwrites streak_count/speed from its OWN exports on regenerate — mirror them
		# so a respawn keeps the section's values instead of reverting to warp_streak_*.
		_backdrop.set("warp_streak_count", int(_v(SEC_STREAK, "streak_count")))
		_backdrop.set("warp_streak_speed", float(_v(SEC_STREAK, "streak_speed")))

	# Nebula alphas (respawn — nebula rebuilds on populate; but usually no nebula in dev fallback).
	for pair in [[lf, "neb_far"], [lm, "neb_mid"], [ln, "neb_near"]]:
		if pair[0] != null:
			pair[0].set("nebula_alpha", float(_v(SEC_NEBULA, pair[1])))

	# Planet type.
	if _planet_type > 0:
		_backdrop.set("forced_planet_idx", _planet_type - 1)
	else:
		_backdrop.set("forced_planet_idx", -1)

	if force_respawn:
		_regenerate()
		# _populate re-sets streak_tint from palette.accent when use_palette — re-assert the lab's
		# STREAKS "Tint = dominant color" toggle so it stays the authoritative per-consumer override.
		_reassert_post_regen()
	_refresh_palette_swatches()
	_refresh_status_line()
	_refresh_clamp()


func _reassert_post_regen() -> void:
	var ls := _layer("LayerStreaks")
	var lp := _layer("LayerPlanet")
	if ls != null:
		var tint: Color = Color.WHITE
		if bool(_v(SEC_STREAK, "streak_tint_palette")) and lp != null and lp.has_method("get_dominant_color"):
			tint = lp.get_dominant_color()
		ls.set("streak_tint", tint)
		# Gradient is built at spawn — rebuild (change-aware no-op) so the override
		# actually lands this generation, not the next.
		if ls.has_method("rebuild"):
			ls.rebuild()


# ── Gameplay-source authoring (WP11) ──────────────────────────────────────────
# Author a sector-map-shaped stellar dict via StellarGameplay for the current rolled node. Deterministic
# from _seed (used AS run_seed) + _gp_depth + _gp_type, so slider changes re-author without a fresh roll.
# Carries `asteroid_base_color` (production reads it from Run meta; the lab MUST NOT touch Run).
func _author_gameplay_dict() -> Dictionary:
	var run_seed: int = _seed
	var sectors_cleared: int = _gp_depth
	var row: int = _gp_depth % 3
	var stellar: Dictionary
	if _gp_type == "boss":
		stellar = StellarGameplay.compute_boss_stellar({
			"row": row, "run_seed": run_seed, "sectors_cleared": sectors_cleared})
	else:
		var row_pois: Array = _synth_row_pois(run_seed, row)
		var cur: Dictionary = _pick_current_node(row_pois, run_seed, row)
		var hazard: String = ""
		var belt: bool = false
		match _gp_type:
			"asteroid_field": hazard = "asteroid_field"
			"minefield": hazard = "minefield"
			"belt_adjacent": belt = true
		stellar = StellarGameplay.compute_poi_stellar({
			"id": String(cur["id"]),
			"row": row,
			"pos_x": float(cur["pos_x"]),
			"row_end_x": GP_ROW_END_X,
			"hazard_subtype": hazard,
			"belt_adjacent": belt,
			"sectors_cleared": sectors_cleared,
			"run_seed": run_seed,
			"row_pois": row_pois,
		})
	stellar["asteroid_base_color"] = StellarGameplay.asteroid_color_for_row(row, run_seed)
	return stellar


# Synthesize a plausible row of POIs, mirroring run_state._gen_row_pois's position geometry (3-5 nodes,
# evenly spaced 128..432 with jitter, cell-snapped to 16px) so the row-system staging reads like a real
# star system. Deterministic from run_seed + row. The lab rolls belt-adjacency as a direct flag rather
# than deriving it from neighbors (simpler; the map computes it from the grid).
func _synth_row_pois(run_seed: int, row: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("gp_row:%d:%d" % [row, run_seed]))
	var count: int = rng.randi_range(3, 5)
	var pois: Array = []
	var step: float = (432.0 - 128.0) / float(count)
	for i in range(count):
		var base_x: float = 128.0 + step * (0.5 + float(i))
		var jitter: float = rng.randf_range(-step * 0.25, step * 0.25)
		var x: float = base_x + jitter
		x = float(int(x / 16.0)) * 16.0
		pois.append({"id": "s0_r%d_p%d" % [row, i], "pos_x": x})
	return pois


func _pick_current_node(row_pois: Array, run_seed: int, row: int) -> Dictionary:
	if row_pois.is_empty():
		return {"id": "s0_r%d_p0" % row, "pos_x": 240.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("gp_cur:%d:%d" % [row, run_seed]))
	return row_pois[rng.randi() % row_pois.size()]


func _roll_gameplay_type() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(_seed) ^ 0x60D1
	var r: float = rng.randf()
	var acc: float = 0.0
	for k in GP_TYPE_WEIGHTS:
		acc += float(GP_TYPE_WEIGHTS[k])
		if r <= acc:
			_gp_type = String(k)
			return
	_gp_type = "combat"


func _refresh_palette_swatches() -> void:
	if _pal_swatches.is_empty() or _backdrop == null or not is_instance_valid(_backdrop):
		return
	var pal: Dictionary = _backdrop.get("palette")
	for k in _pal_swatches.keys():
		var rect: ColorRect = _pal_swatches[k]
		if is_instance_valid(rect):
			rect.color = pal.get(k, Color.BLACK)


func _refresh_status_line() -> void:
	if _status_line == null or _backdrop == null or not is_instance_valid(_backdrop):
		return
	var st: Dictionary = _backdrop.get("last_stellar")
	var kind: String = String(st.get("kind", ""))
	if kind == "":
		kind = "-"
	var neb: String = String(st.get("nebula_band", ""))
	if neb == "":
		neb = "-"
	var ast: String = "-"
	if bool(st.get("has_asteroids", false)):
		ast = "%.1fx" % float(st.get("asteroid_density", 0.0))
	var sysarr: Array = st.get("system", [])
	var bodies: int = sysarr.size() if not sysarr.is_empty() else 1
	var star_mode: String = String(st.get("star_mode", ""))
	if star_mode == "":
		star_mode = "-"
	# WP11: prepend the composition source. GAMEPLAY dicts carry no `kind` (sector-map shape), so show
	# the rolled node type + row/depth instead.
	var prefix: String = "src=composer   "
	if _source == "gameplay":
		prefix = "src=gameplay row=%d depth=%d type=%s   " % [_gp_depth % 3, _gp_depth, _gp_type]
	_status_line.text = prefix + "kind=%s   nebula=%s   asteroids=%s   bodies=%d   star=%s   starfx=%s" % [kind, neb, ast, bodies, star_mode, _hero_star_tier()]


# Hero star's rendered tier from the LayerPlanet StarFx container metas (WP9 status readout).
# "<tier>@<px>px" (e.g. "sparkle@24px") when a StarFx child exists, "-" otherwise (star_fx off,
# or the composed scene has no star body).
func _hero_star_tier() -> String:
	var lp := _layer("LayerPlanet")
	if lp == null:
		return "-"
	for c in lp.get_children():
		if c.name == "StarFx" and c.has_meta("star_tier"):
			return "%s@%dpx" % [String(c.get_meta("star_tier")), int(round(float(c.get_meta("star_px", 0.0))))]
	return "-"


func _refresh_clamp() -> void:
	if _clamp_lbl == null:
		return
	var sp: float = float(_v(SEC_STREAK, "streak_speed"))
	if sp > 480.0:
		_clamp_lbl.text = "⚠ %.0f > 480 (clarity ceiling)" % sp
		_clamp_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	else:
		_clamp_lbl.text = "✓ %.0f ≤ 480" % sp
		_clamp_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))


# ── Presets ───────────────────────────────────────────────────────────────────

func _apply_preset(preset: Dictionary) -> void:
	_vals = preset.duplicate(true)
	# Refresh every slider + toggle UI to the new values.
	for key in _slider_nodes.keys():
		var s: HSlider = _slider_nodes[key]
		if is_instance_valid(s):
			s.set_value_no_signal(float(_vals[key]))
			if _slider_val_labels.has(key):
				_slider_val_labels[key].text = _fmt_val(float(_vals[key]))
	# Refresh the WP4 composition + palette controls (not sliders).
	if _palette_master_cb != null and is_instance_valid(_palette_master_cb):
		_palette_master_cb.set_pressed_no_signal(bool(_vals.get("use_palette", false)))
	if _kind_dd != null and is_instance_valid(_kind_dd):
		_kind_dd.select(_kind_index())
	# Refresh WP7 (+ any) bool checkbuttons bound to _vals keys (e.g. pixel_snap).
	for k in _bool_cbs.keys():
		var cb: CheckButton = _bool_cbs[k]
		if is_instance_valid(cb):
			cb.set_pressed_no_signal(bool(_vals.get(k, false)))
	_apply_all(true)
	_set_status("Applied preset.")


func _kind_index() -> int:
	var i: int = KIND_VALUES.find(String(_vals.get("forced_kind", "")))
	return i if i >= 0 else 0


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Item 3 — panel layout. CULPRIT: the section-header CheckButtons carry long single-line text
	# ("ROCK SIZES (near, respawn — pick kind=Asteroid…)" etc.). Buttons don't autowrap by default, so
	# each reports a minimum width = its full text width. That propagates up (VBox → ScrollContainer,
	# which has horizontal scroll DISABLED so it can't clip in the min-size direction → PanelContainer),
	# ballooning the right-anchored panel LEFTWARD over the backdrop and clipping the rightmost slider
	# value labels. Fix: give the VBox a fixed content width + make every Button/CheckButton autowrap so
	# no child forces the column wider than PANEL_W. (Sliders already carry a bounded min, not expand-greed.)
	var panel := PanelContainer.new()
	panel.name = "ControlPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_W
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.92)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	# Content width = panel − content margins (14 each) − vertical scrollbar allowance. Fixed so the
	# column never grows past PANEL_W; children fill/wrap to this instead of dictating it.
	v.custom_minimum_size = Vector2(PANEL_W - 40, 0)
	v.size_flags_horizontal = Control.SIZE_FILL
	scroll.add_child(v)

	v.add_child(_label("PARALLAX SHOWCASE", UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))
	v.add_child(_label("A/B the review's proposed backdrop fixes. Combat drift 50 (live).\nStar far/near rates are consts — ship them via the Copy block.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))

	# Bloom toggle (Item 1) — A/B combat's HDR glow itself. Default ON.
	var bloom_cb := CheckButton.new()
	bloom_cb.text = "Bloom (HDR glow)"
	bloom_cb.button_pressed = _bloom_on
	bloom_cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bloom_cb.toggled.connect(_set_bloom)
	v.add_child(bloom_cb)

	# HD raster toggle (WP7) — combat-accurate 1920×1080 render of the 480-logical backdrop. Default
	# ON. Only at this raster does the pixel_snap toggle visibly smooth planet motion; OFF is the old
	# 480 lab view. Lab-only (never shipped) — not in the Copy block.
	var hd_cb := CheckButton.new()
	hd_cb.text = "HD raster (combat-accurate)"
	hd_cb.button_pressed = _hd_raster
	hd_cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hd_cb.toggled.connect(_apply_hd_raster)
	v.add_child(hd_cb)

	# Composition section (WP4) — above presets: picks what the composer rolls.
	_build_composition(v)

	# Preset row.
	var prow := HBoxContainer.new()
	var cur_b := UiTheme.make_button("CURRENT", true)
	cur_b.pressed.connect(func(): _apply_preset(CURRENT))
	prow.add_child(cur_b)
	var prop_b := UiTheme.make_button("PROPOSED", true)
	prop_b.pressed.connect(func(): _apply_preset(PROPOSED))
	prow.add_child(prop_b)
	var gen_b := UiTheme.make_button("⟲ New", true)
	gen_b.pressed.connect(_on_generate_new)
	prow.add_child(gen_b)
	v.add_child(prow)

	var pt_row := HBoxContainer.new()
	pt_row.add_child(_label("Planet", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT))
	var pt_dd := OptionButton.new()
	for pn in PLANET_TYPE_NAMES:
		pt_dd.add_item(pn)
	pt_dd.select(_planet_type)
	pt_dd.item_selected.connect(_on_planet_type)
	pt_row.add_child(pt_dd)
	v.add_child(pt_row)

	# Palette section (WP4).
	_build_palette(v)

	# Star FX section (WP9) — placed after PALETTE, before the slider sections.
	_build_star_fx(v)

	# Feature sections.
	_section(v, SEC_SCROLL, "SCROLL RATIOS", [
		["stars_far", "Stars far (const)", 0.0, 0.1, 0.001],
		["stars_near", "Stars near (const)", 0.0, 0.1, 0.001],
		["planet_rate", "Planet", 0.0, 0.2, 0.005],
		["far_rate", "Far", 0.0, 2.0, 0.01],
		["mid_rate", "Mid", 0.0, 2.5, 0.01],
		["near_rate", "Near", 0.0, 3.0, 0.05],
		["drift_speed", "Drift speed", 0.0, 80.0, 1.0],
	])
	# Planet pixel snap (WP7 item 2) — viewport-wide flag; only visibly differs under HD raster.
	v.add_child(_bool_cb("Planet pixel snap (viewport-wide)", "pixel_snap", false))
	_section(v, SEC_BRIGHT, "BRIGHTNESS RAMP", [
		["bright_far", "Bright far", 0.0, 1.5, 0.05],
		["bright_mid", "Bright mid", 0.0, 1.5, 0.05],
		["bright_near", "Bright near", 0.0, 1.5, 0.05],
		["contrast_far", "Contrast far", 0.0, 2.0, 0.05],
		["contrast_mid", "Contrast mid", 0.0, 2.0, 0.05],
	])
	_section(v, SEC_ROCK, "ROCK SIZES (near, respawn — pick kind=Asteroid to see rocks)", [
		["rock_near_min", "Near min", 16.0, 320.0, 1.0],
		["rock_near_max", "Near max", 16.0, 320.0, 1.0],
		["rock_size_pow", "Size pow", 0.5, 4.0, 0.05],
	])
	_section(v, SEC_GRADE, "PALETTE GRADE", [], true)   # bool + swatch handled below
	_section(v, SEC_LATERAL, "LATERAL PARALLAX (←/→)", [
		["lateral_strength", "Strength (px)", 0.0, 80.0, 1.0],
	], false, true)   # add auto-sweep row
	_section(v, SEC_DRIFT, "ROCK DRIFT", [
		["drift_variance", "Rock drift (respawn)", 0.0, 8.0, 0.1],
		["lateral_wander", "Planet wander", 0.0, 4.0, 0.05],
		["body_parallax", "Body parallax (respawn)", 0.0, 1.5, 0.05],
	])
	_section(v, SEC_DENSITY, "ASTEROID DENSITY (per-depth count, respawn — needs kind=Asteroid)", [
		["ast_mult_far", "Far mult", 0.0, 3.0, 0.1],
		["ast_mult_mid", "Mid mult", 0.0, 3.0, 0.1],
		["ast_mult_near", "Near mult", 0.0, 3.0, 0.1],
	])
	_section(v, SEC_STREAK, "STREAKS", [
		["streak_speed", "Speed (respawn)", 100.0, 900.0, 10.0],
		["streak_alpha", "Alpha (respawn)", 0.0, 1.0, 0.02],
		["streak_count", "Count", 0.0, 40.0, 1.0],
		["streak_var_min", "Var min", 0.0, 1.2, 0.02],
	], false, false, true)   # streak-tint bool + clamp indicator
	_section(v, SEC_NEBULA, "NEBULA ALPHAS", [
		["neb_far", "Far", 0.0, 1.0, 0.01],
		["neb_mid", "Mid", 0.0, 1.0, 0.01],
		["neb_near", "Near", 0.0, 1.0, 0.01],
	])

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


func _build_composition(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(_label("COMPOSITION", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_ACCENT))
	# Source picker (WP11): Composer fallback vs Gameplay (sector-map authoring).
	var srow := HBoxContainer.new()
	srow.add_child(_label("Source", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT))
	_source_dd = OptionButton.new()
	for sn in SOURCE_NAMES:
		_source_dd.add_item(sn)
	_source_dd.select(maxi(0, SOURCE_VALUES.find(_source)))
	_source_dd.item_selected.connect(_on_source_selected)
	srow.add_child(_source_dd)
	parent.add_child(srow)
	# Sector depth (GAMEPLAY only): drives sectors_cleared (exotic-star odds) + row = depth % 3.
	var drow := HBoxContainer.new()
	_gp_depth_lbl = _label("Sector depth: %d (row %d)" % [_gp_depth, _gp_depth % 3], UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
	_gp_depth_lbl.custom_minimum_size = Vector2(180, 0)
	drow.add_child(_gp_depth_lbl)
	var ds := HSlider.new()
	ds.min_value = 0
	ds.max_value = 16
	ds.step = 1
	ds.value = _gp_depth
	ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.custom_minimum_size = Vector2(0, 16)
	ds.value_changed.connect(_on_gp_depth_changed)
	drow.add_child(ds)
	parent.add_child(drow)
	# Kind picker (COMPOSER only — ignored in Gameplay).
	var krow := HBoxContainer.new()
	krow.add_child(_label("Kind (composer only)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT))
	_kind_dd = OptionButton.new()
	for kn in KIND_NAMES:
		_kind_dd.add_item(kn)
	_kind_dd.select(_kind_index())
	_kind_dd.item_selected.connect(_on_kind_selected)
	krow.add_child(_kind_dd)
	parent.add_child(krow)
	_status_line = _label("src=-   kind=-", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_GREEN)
	parent.add_child(_status_line)
	parent.add_child(_label("Composer = full-variety fallback (kind picker applies). Gameplay = the sector\nmap's per-node authoring; ⟲ New rolls a node, depth sets exotic-star odds.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))


func _build_palette(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	_palette_master_cb = CheckButton.new()
	_palette_master_cb.text = "PALETTE (use_palette)"
	_palette_master_cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_palette_master_cb.button_pressed = bool(_vals.get("use_palette", false))
	_palette_master_cb.toggled.connect(func(on): _vals["use_palette"] = on; _apply_all(true))
	parent.add_child(_palette_master_cb)
	parent.add_child(_label("consumers: grade + stars + asteroids (driven by master). Streaks has its own\ntoggle in STREAKS (that override wins over the master).", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	for k in ["key", "accent", "dust", "deep"]:
		var col := VBoxContainer.new()
		col.add_child(_label(k, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT))
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(44, 20)
		rect.color = Color.BLACK
		_pal_swatches[k] = rect
		col.add_child(rect)
		srow.add_child(col)
	parent.add_child(srow)


# Star FX section (WP9). The master is the `star_fx` bool CheckButton itself (respawn-class, wired
# through _bool_cbs so presets refresh it — like PALETTE's use_palette master). Three respawn-class
# threshold sliders land on the LayerPlanet exports in _apply_all. Consts/exports only — no new
# section-toggle in _sec_on (values read straight from _vals).
func _build_star_fx(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(_label("STAR FX (tiered star rendering, respawn)", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_ACCENT))
	parent.add_child(_bool_cb("star_fx (sparkle / halo / clamp tiers)", "star_fx", true))
	parent.add_child(_slider("star_sparkle_max", "Sparkle below (px)", float(_vals["star_sparkle_max"]), 8.0, 48.0, 1.0))
	parent.add_child(_slider("star_clamp_max", "Star size cap (px)", float(_vals["star_clamp_max"]), 60.0, 200.0, 5.0))
	# 1.0 = the lab-proven star×2 halo; 1.5 reproduces Roman's first-pass ×3 spec (120px → 360).
	parent.add_child(_slider("halo_scale_mult", "Halo scale", float(_vals["halo_scale_mult"]), 0.5, 2.0, 0.05))
	# The two brightness levers that stack with the HDR kit + bloom (Roman 2026-07-08).
	parent.add_child(_slider("halo_mid_alpha", "Halo mid alpha", float(_vals["halo_mid_alpha"]), 0.0, 1.0, 0.05))
	parent.add_child(_slider("halo_core_intensity", "Halo core intensity", float(_vals["halo_core_intensity"]), -1.0, 3.0, 0.05))
	# Sparkle-tier levers (round 2 of the "giant central dot"): decay tightens the shader's own
	# gaussian core (0.12 = the fat lab reference, 0.3 ≈ 17% of star), scale mult tightens
	# core+spikes together, dot frac/hdr shape the white HDR point.
	parent.add_child(_slider("sparkle_decay", "Sparkle decay (core)", float(_vals["sparkle_decay"]), 0.05, 1.0, 0.01))
	parent.add_child(_slider("sparkle_scale_mult", "Sparkle scale ×", float(_vals["sparkle_scale_mult"]), 0.5, 3.0, 0.05))
	parent.add_child(_slider("dot_size_frac", "Glint energy", float(_vals["dot_size_frac"]), 0.1, 1.5, 0.05))
	parent.add_child(_slider("dot_hdr", "Glint HDR", float(_vals["dot_hdr"]), 1.0, 4.0, 0.1))
	parent.add_child(_label("tiers: sparkle < N px < kit+halo <= cap; force kind=System to demo.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))


func _on_kind_selected(idx: int) -> void:
	_vals["forced_kind"] = KIND_VALUES[idx]
	if _source != "gameplay":   # kind picker is composer-only
		_seed = abs(int(randi()))   # fresh example of the picked kind
	_apply_all(true)
	_set_status("Kind = %s (seed %d)." % [KIND_NAMES[idx], _seed])


func _on_source_selected(idx: int) -> void:
	_source = SOURCE_VALUES[idx]
	if _source == "gameplay":
		_roll_gameplay_type()   # roll an initial node so the scene isn't empty
	_apply_all(true)
	_set_status("Source = %s." % SOURCE_NAMES[idx])


func _on_gp_depth_changed(v: float) -> void:
	_gp_depth = int(v)
	if _gp_depth_lbl != null and is_instance_valid(_gp_depth_lbl):
		_gp_depth_lbl.text = "Sector depth: %d (row %d)" % [_gp_depth, _gp_depth % 3]
	if _source == "gameplay":
		_apply_all(true)   # re-author + respawn


func _section(parent: VBoxContainer, section: String, title: String, sliders: Array, is_grade: bool = false, add_sweep: bool = false, is_streak: bool = false) -> void:
	parent.add_child(HSeparator.new())
	var head := CheckButton.new()
	head.text = title
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long section titles wrap, don't balloon the column
	head.button_pressed = _sec_on.get(section, true)
	head.toggled.connect(func(on): _sec_on[section] = on; _apply_all(true))
	parent.add_child(head)
	for spec in sliders:
		var key: String = spec[0]
		parent.add_child(_slider(key, spec[1], float(_vals[key]), spec[2], spec[3], spec[4]))
	if is_grade:
		var gcb := CheckButton.new()
		gcb.text = "use_dominant_grade"
		gcb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gcb.button_pressed = bool(_vals["use_dominant_grade"])
		gcb.toggled.connect(func(on): _vals["use_dominant_grade"] = on; _apply_all(false))
		parent.add_child(gcb)
		var srow := HBoxContainer.new()
		srow.add_child(_label("dominant color", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT))
		_swatch = ColorRect.new()
		_swatch.custom_minimum_size = Vector2(48, 16)
		_swatch.color = Color.WHITE
		srow.add_child(_swatch)
		parent.add_child(srow)
	if add_sweep:
		var scb := CheckButton.new()
		scb.text = "Auto-sweep (sine ~4s)"
		scb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scb.button_pressed = _auto_sweep
		scb.toggled.connect(func(on): _auto_sweep = on)
		parent.add_child(scb)
	if is_streak:
		var tcb := CheckButton.new()
		tcb.text = "Tint = dominant color"
		tcb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tcb.button_pressed = bool(_vals["streak_tint_palette"])
		tcb.toggled.connect(func(on): _vals["streak_tint_palette"] = on; _apply_all(true))
		parent.add_child(tcb)
		_clamp_lbl = _label("", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
		parent.add_child(_clamp_lbl)


func _slider(key: String, title: String, value: float, lo: float, hi: float, step: float) -> Control:
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
	var val_l := _label(_fmt_val(value), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_ACCENT)
	val_l.custom_minimum_size = Vector2(56, 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(vv):
		val_l.text = _fmt_val(vv)
		_vals[key] = vv
		_apply_all(key in RESPAWN_KEYS))
	row.add_child(s)
	row.add_child(val_l)
	_slider_nodes[key] = s
	_slider_val_labels[key] = val_l
	return row


# A CheckButton bound to a _vals bool key. Registered in _bool_cbs so preset apply refreshes it.
# `respawn` = whether flipping it needs a coordinator regenerate (else a live apply).
func _bool_cb(text: String, key: String, respawn: bool) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cb.button_pressed = bool(_vals.get(key, false))
	cb.toggled.connect(func(on):
		_vals[key] = on
		_apply_all(respawn or (key in RESPAWN_KEYS)))
	_bool_cbs[key] = cb
	return cb


func _on_planet_type(idx: int) -> void:
	_planet_type = idx
	_apply_all(true)


func _on_generate_new() -> void:
	_seed = abs(int(randi()))
	if _source == "gameplay":
		# Fresh node type from the new seed, then author + respawn through _apply_all (which sets the
		# stellar_override BEFORE the regenerate). Never touches Run.
		_roll_gameplay_type()
		_apply_all(true)
		_set_status("Rolled gameplay node (seed %d, %s)." % [_seed, _gp_type])
	else:
		_apply_all(true)   # composer path: _apply_all clears the override + composes, then regenerates
		_set_status("Generated new backdrop (seed %d)." % _seed)


# ── Persistence ───────────────────────────────────────────────────────────────

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var data := {"vals": _vals, "sections": _sec_on, "planet_type": _planet_type, "seed": _seed, "auto_sweep": _auto_sweep, "hd_raster": _hd_raster, "source": _source, "gp_depth": _gp_depth, "gp_type": _gp_type}
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
		if d.has("vals") and d["vals"] is Dictionary:
			for key in CURRENT.keys():
				if d["vals"].has(key):
					var cv = CURRENT[key]
					var rv = d["vals"][key]
					if cv is bool:
						_vals[key] = bool(rv)
					elif cv is String:
						_vals[key] = String(rv)
					else:
						_vals[key] = float(rv)
		if d.has("sections") and d["sections"] is Dictionary:
			for key in _sec_on.keys():
				if d["sections"].has(key):
					_sec_on[key] = bool(d["sections"][key])
		_planet_type = int(d.get("planet_type", _planet_type))
		_seed = int(d.get("seed", _seed))
		_auto_sweep = bool(d.get("auto_sweep", _auto_sweep))
		_hd_raster = bool(d.get("hd_raster", _hd_raster))   # WP7 lab-only render mode
		# WP11 composition source.
		var src := String(d.get("source", _source))
		_source = src if SOURCE_VALUES.has(src) else _source
		_gp_depth = int(d.get("gp_depth", _gp_depth))
		_gp_type = String(d.get("gp_type", _gp_type))


# ── Copy GDScript ─────────────────────────────────────────────────────────────

func _copy_snippet() -> String:
	var t := "# Parallax V4 Showcase — export (paste into the REAL destinations).\n\n"
	t += "# backdrop_coordinator.gd exports:\n"
	t += "#   drift_speed = %s  (combat scene sets this in main.tscn)\n" % _fmt(_v(SEC_SCROLL, "drift_speed"))
	t += "#   lateral_strength = %s\n" % _fmt(_v(SEC_LATERAL, "lateral_strength"))
	t += "#   use_dominant_grade = %s\n" % str(bool(_v(SEC_GRADE, "use_dominant_grade")))
	t += "#   warp_streak_count = %d\n" % int(_v(SEC_STREAK, "streak_count"))
	t += "#   warp_streak_speed = %s\n" % _fmt(_v(SEC_STREAK, "streak_speed"))
	t += "#   use_composer_fallback = true  (dev/menu full-variety fallback flag; ship OFF in prod until the menu_backdrop flip)\n"
	if String(_vals.get("forced_kind", "")) != "":
		t += "#   forced_kind = \"%s\"  (dev picker only — leave \"\" in prod for weighted-random)\n" % String(_vals["forced_kind"])
	t += "#   use_palette = %s\n" % str(bool(_vals.get("use_palette", false)))
	t += "#   asteroid_layer_mult = Vector3(%s, %s, %s)  (x=far, y=mid, z=near asteroid count)\n" % [
		_fmt(_v(SEC_DENSITY, "ast_mult_far")), _fmt(_v(SEC_DENSITY, "ast_mult_mid")), _fmt(_v(SEC_DENSITY, "ast_mult_near"))]
	t += "\n# layer_stars.gd consts (edit FAR_RATE / NEAR_RATE):\n"
	t += "#   FAR_RATE  = %s\n" % _fmt(_v(SEC_SCROLL, "stars_far"))
	t += "#   NEAR_RATE = %s\n" % _fmt(_v(SEC_SCROLL, "stars_near"))
	t += "#   key_tint  = set from palette.key at runtime by the coordinator when use_palette (export default Color.WHITE)\n"
	t += "\n# layer_planet.tscn override + layer_planet.gd export:\n"
	t += "#   LayerPlanet: scroll_rate = %s\n" % _fmt(_v(SEC_SCROLL, "planet_rate"))
	t += "#   LayerPlanet: lateral_wander = %s\n" % _fmt(_v(SEC_DRIFT, "lateral_wander"))
	t += "#   LayerPlanet: body_parallax = %s\n" % _fmt(_v(SEC_DRIFT, "body_parallax"))
	t += "#   LayerPlanet: pixel_snap = %s  (viewport-wide: OFF unsnaps snap_2d_transforms_to_pixel for the\n" % str(bool(_v(SEC_SCROLL, "pixel_snap")))
	t += "#     whole backdrop viewport — production combat renders 1080p canvas_items + snaps, so it honors this)\n"
	t += "#   LayerPlanet: star_fx = %s  (tiered star rendering: sparkle / halo / clamp)\n" % str(bool(_vals.get("star_fx", false)))
	t += "#   LayerPlanet: star_sparkle_max = %s  (below this px → sparkle tier, no kit)\n" % _fmt(_vals.get("star_sparkle_max", 32.0))
	t += "#   LayerPlanet: star_clamp_max = %s  (star display size capped here at spawn)\n" % _fmt(_vals.get("star_clamp_max", 120.0))
	t += "#   LayerPlanet: halo_scale_mult = %s  (multiplier on the lerped 90→336 halo size)\n" % _fmt(_vals.get("halo_scale_mult", 1.0))
	t += "#   LayerPlanet: halo_mid_alpha = %s  (halo gradient mid-stop alpha)\n" % _fmt(_vals.get("halo_mid_alpha", 0.75))
	t += "#   LayerPlanet: halo_core_intensity = %s  (1.5 = at the bloom threshold)\n" % _fmt(_vals.get("halo_core_intensity", 1.5))
	t += "#   LayerPlanet: sparkle_decay = %s  (sparkle shader core tightness)\n" % _fmt(_vals.get("sparkle_decay", 0.3))
	t += "#   LayerPlanet: sparkle_scale_mult = %s\n" % _fmt(_vals.get("sparkle_scale_mult", 1.0))
	t += "#   LayerPlanet: dot_size_frac = %s  (glint energy: core heat + ray length)\n" % _fmt(_vals.get("dot_size_frac", 0.45))
	t += "#   LayerPlanet: dot_hdr = %s  (glint HDR boost)\n" % _fmt(_vals.get("dot_hdr", 2.5))
	t += "\n# backdrop_coordinator.tscn per-layer overrides (layer_base / layer_stellar exports):\n"
	t += "#   LayerStellarFar:  scroll_rate=%s brightness=%s contrast=%s nebula_alpha=%s drift_variance=%s\n" % [
		_fmt(_v(SEC_SCROLL, "far_rate")), _fmt(_v(SEC_BRIGHT, "bright_far")), _fmt(_v(SEC_BRIGHT, "contrast_far")),
		_fmt(_v(SEC_NEBULA, "neb_far")), _fmt(_v(SEC_DRIFT, "drift_variance"))]
	t += "#   LayerStellarMid:  scroll_rate=%s brightness=%s contrast=%s nebula_alpha=%s drift_variance=%s\n" % [
		_fmt(_v(SEC_SCROLL, "mid_rate")), _fmt(_v(SEC_BRIGHT, "bright_mid")), _fmt(_v(SEC_BRIGHT, "contrast_mid")),
		_fmt(_v(SEC_NEBULA, "neb_mid")), _fmt(_v(SEC_DRIFT, "drift_variance"))]
	t += "#   LayerStellarNear: scroll_rate=%s brightness=%s nebula_alpha=%s drift_variance=%s\n" % [
		_fmt(_v(SEC_SCROLL, "near_rate")), _fmt(_v(SEC_BRIGHT, "bright_near")),
		_fmt(_v(SEC_NEBULA, "neb_near")), _fmt(_v(SEC_DRIFT, "drift_variance"))]
	t += "#   LayerStellarNear: asteroid_min_size=%s asteroid_max_size=%s asteroid_size_pow=%s\n" % [
		_fmt(_v(SEC_ROCK, "rock_near_min")), _fmt(_v(SEC_ROCK, "rock_near_max")), _fmt(_v(SEC_ROCK, "rock_size_pow"))]
	t += "\n# layer_streaks.gd exports (LayerStreaks override):\n"
	t += "#   streak_speed=%s streak_alpha=%s streak_count=%d streak_speed_variance_min=%s\n" % [
		_fmt(_v(SEC_STREAK, "streak_speed")), _fmt(_v(SEC_STREAK, "streak_alpha")),
		int(_v(SEC_STREAK, "streak_count")), _fmt(_v(SEC_STREAK, "streak_var_min"))]
	t += "#   streak_tint = %s (dominant-color at runtime)\n" % ("palette" if bool(_v(SEC_STREAK, "streak_tint_palette")) else "Color.WHITE")
	DisplayServer.clipboard_set(t)
	print(t)
	_set_status("Copied GDScript to clipboard.")
	return t


func _fmt(v) -> String:
	return "%.3f" % float(v)


func _fmt_val(v: float) -> String:
	if absf(v) < 1.0:
		return "%.3f" % v
	return "%.2f" % v


# ── Small helpers ─────────────────────────────────────────────────────────────

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg


func _on_close() -> void:
	_save()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
