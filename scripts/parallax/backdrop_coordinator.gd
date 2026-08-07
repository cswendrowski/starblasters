extends Node2D

@export var drift_speed: float = 22.0
@export var planet_size: float = 240.0
@export var planet_size_variance: float = 0.35
@export var tint_alpha: float = 0.09
@export var use_warp_streaks: bool = true
@export var warp_streak_count: int = 14
@export var warp_streak_speed: float = 750.0
@export var forced_planet_idx: int = -1
@export var pixel_density: float = 1.0
@export var asteroid_presence: float = 0.65
@export_range(1.0, 2.0) var asteroid_density_scale: float = 1.0
# Force decorative asteroids ON regardless of the node's has_asteroids flag (Roman 2026-06-15).
# OFF by default (the flag normally gates asteroids to asteroid-field nodes). The SIGNAL EVENT
# backdrop sets this so events get the same drifting rocks combat has. Count still follows
# asteroid_density + the per-layer floor.
@export var force_asteroids: bool = false
# Nebula filament churn — TIME-driven swirl applied to any per-POI nebula the stellar config carries
# (current_stellar.nebula_band/nebula_tint). 0 = static (legacy). Backdrop tune (Roman 2026-06-12).
@export_range(0.0, 1.0) var nebula_swirl: float = 0.25
# Hazard-node decoration (background mines). OFF by default so the SHARED coordinator
# (also used by the main menu + signal events) never paints mines from a stale
# current_hazard_subtype. ONLY the combat backdrop (main.tscn) turns this on, so mines
# decorate minefield COMBAT and nowhere else (Roman 2026-06-11).
@export var enable_hazard_decor: bool = false
# ── Parallax V4 showcase knobs (all inert by default) ──────────────────────
# Horizontal parallax: px of NEAR-layer shift at full strafe. 0 = no lateral
# response (today). Each layer's shift is auto depth-scaled by its scroll_rate.
@export var lateral_strength: float = 0.0
# Grade the scene + layer tints from the live planet's sampled dominant color
# (layer_planet.get_dominant_color) instead of the per-type PLANET_TINT table.
# false = today's type-keyed grade.
@export var use_dominant_grade: bool = false
# ── Parallax V4 Phase 2 (WP3): composer fallback + palette authority (inert) ──
# When ON and current_stellar is empty, _populate builds the stellar dict via
# StellarComposer.compose() (full-variety fallback: systems/nebulas/asteroid belts)
# instead of the bare single-planet inline fallback. OFF = today's sparse fallback
# (menus/dev). forced_planet_idx still wins the planet pick.
@export var use_composer_fallback: bool = false
# Force a composition kind ("system"/"planet"/"asteroid"/"nebula"); "" = weighted
# random. Passed to the composer as opts.kind (showcase kind picker).
@export var forced_kind: String = ""
# Palette authority: when ON, the grade/starfield/asteroid/streak color authorities
# all sample the per-node `palette` struct (implies use_dominant_grade for the grade).
# OFF = today's independent color sources. Nothing consumes the palette while OFF.
@export var use_palette: bool = false
# Per-depth asteroid count gradient (Parallax V4 showcase, item 4). x=far, y=mid, z=near —
# multiplies each stellar band's density-scaled asteroid AND mini count on top of density_mult
# (through the _base_counts cache, so it never compounds across regenerate). Vector3.ONE = today
# exactly. PROPOSED (2.0, 1.0, 0.7) makes far the busiest band, near the sparsest.
@export var asteroid_layer_mult: Vector3 = Vector3.ONE
# Asteroid drop shadows (ports the Flyover cloud-shadow rig): player + enemy
# silhouettes darken the decorative rocks, band-scaled exactly like the flyover
# cloud layers. OFF by default — only the combat backdrop (main.tscn) turns it
# on, so menu/signal-event coordinators never pay for the 3 mask viewports.
@export var asteroid_shadows: bool = false

# Planet Flyover eligibility. OFF by default — only combat's main.tscn Backdrop instance turns
# it on. Menu / signal-event / lab / capture coordinators always keep the space parallax stack
# regardless of whatever mid-run node state Run is carrying (Roman 2026-07-18).
@export var allow_flyover: bool = false

# Planet-to-tint mapping from V1 PLANET_TINT. Read galaxy_backdrop.gd for the exact colors.
const PLANET_TINT := {
	0: Color(1.0, 0.45, 0.20),  # LavaWorld
	1: Color(0.60, 0.85, 1.0),  # IceWorld
	2: Color(0.85, 0.65, 0.40), # DryTerran
	3: Color(0.65, 0.80, 0.55), # GasPlanet
	4: Color(0.70, 0.70, 0.75), # NoAtmosphere
	5: Color(0.45, 0.75, 0.55), # LandMasses
	6: Color(0.10, 0.10, 0.15), # BlackHole — skip tint
	7: Color(0.55, 0.45, 0.80), # Galaxy
	8: Color(1.00, 0.95, 0.75), # Star — skip tint
}
const SKIP_TINT := [6, 8]

# Full-variety fallback + palette authoring (WP3). Preload const, NOT class_name.
const StellarComposer = preload("res://scripts/parallax/stellar_composer.gd")
# Asteroid drop-shadow rig (mask viewports + caster tracking). Preload const, NOT class_name.
const AsteroidShadowRig = preload("res://scripts/parallax/asteroid_shadow_rig.gd")
# Planet Flyover combat backdrop (Phase B1). Both preload consts, NOT class_name (the planner
# has no class_name by design; keep the pair symmetric).
const FlyoverPlanner = preload("res://scripts/parallax/flyover_planner.gd")
const FlyoverBackdrop = preload("res://scripts/parallax/flyover_backdrop.gd")
# base_z for the flyover stack. The space parallax layers live on deeply-negative CanvasLayers
# (LayerStars -10 … LayerComposite -1), so they always sit behind the default layer-0 gameplay.
# The FlyoverBackdrop, by contrast, is a child of THIS Node2D (default CanvasLayer 0), so it must
# use z_index to stay behind gameplay. The component's topmost layer is Near = base_z + 24; the
# design pins that at ≤ -8 (below ships 0, rocks -1, ground plane -5..-4). -32 puts Near at -8
# and the ground floor at -32, preserving the fixed ground<atmo<cloud interleave.
const FLYOVER_BASE_Z := -32

# ── Row-system staging position knobs (Roman to tune) ──────────────────────
# When current_stellar carries a `system` array (star + nearest planets), the
# bodies are spread across the upper backdrop by their `frac` (0=left/near star,
# 1=right/far). Bodies are decorative + behind gameplay, so the full 480 width
# (incl. side gutters) is fair game for spreading them out without overlap.
const SYS_X_MIN        := 40.0    # KNOB: screen-x for frac 0.0 (star, left)
const SYS_X_MAX        := 440.0   # KNOB: screen-x for frac 1.0 (far-right body)
const SYS_Y_BASE       := -40.0   # KNOB: baseline top-y of a body's top-left
const SYS_Y_JITTER     := 70.0    # KNOB: per-seed vertical spread band (px)
const SYS_Y_LOWER_BIG  := 26.0    # KNOB: nearer/larger bodies sit this much lower
# Size ceiling for the NEAREST body (scale 1.0). Roman v2: the body at the
# current node should FILL the screen — the playfield is 480×270, so a ceiling
# of 330px makes the nearest body ~330px tall (taller than the 270 viewport;
# partially off-frame is intended). `scale` (0..1) from _stage_scale multiplies
# this. Distant bodies fall off fast via the exponential curve in sector_map_v3.
const SYS_SIZE_CEILING := 330.0   # KNOB: px size of a body at scale 1.0 (fills screen)
# Below this RAW px size (before any floor) a body is too far to read as a
# sphere — render it as a ~2px glowing dot in its main color instead.
const SYS_DOT_THRESHOLD_PX := 6.0 # KNOB: raw px under which a body becomes a 2px dot
const SYS_DOT_PX           := 2.0 # KNOB: the glowing dot's core size (px)
const SYS_MIN_BODY_PX  := 18.0    # KNOB: clamp so NON-dot bodies don't degenerate

var _layer_stars: Node = null
var _layer_planet: Node = null
var _layer_stellar_far: Node = null
var _layer_stellar_mid: Node = null
var _layer_stellar_near: Node = null
var _layer_streaks: Node = null
var _layer_composite: Node = null
var _scroll_layers: Array = []

# Lateral parallax state (Parallax V4 showcase). _lateral_target is set by
# set_lateral_input (−1..1 × strength-derived range); _lateral_pos smooths toward
# it. Both stay 0 while lateral_strength is 0, so the _process loop is skipped.
var _lateral_target: float = 0.0
var _lateral_pos: float = 0.0
# Seed override for regenerate() — >= 0 wins over the run-derived seed. -1 = use
# the run/time seed (default production path).
var _seed_override: int = -1
# Authored (scene-default) per-layer asteroid/mini counts, captured on the FIRST
# _populate. _populate overwrites the layers' *_count in place with the
# density-scaled value; without this cache a regenerate() would re-scale the
# already-scaled count and shrink the rocks each call. Keyed by layer instance id.
var _base_counts: Dictionary = {}

# Completed per-node palette {key, accent, dust, deep} (WP3). key/dust/deep are
# authored from the composition; accent is the live planet's sampled dominant hue,
# filled after planet spawn. Stored for the showcase lab + future consumers (recycle
# ghost). Empty until the first _populate. Consumed only while use_palette is ON.
var palette: Dictionary = {}
# The stellar dict _populate last consumed (composed or sector-map) — exposes the
# rolled `kind` / `nebula_band` / `has_asteroids` for the showcase status line.
var last_stellar: Dictionary = {}
# The asteroid drop-shadow rig (created in _populate only while asteroid_shadows
# is on AND rocks will actually spawn — 3 always-updating mask viewports aren't free).
var _shadow_rig: Node = null
# The Planet Flyover backdrop (Phase B1) — built by _populate's early branch when a real-run
# planet POI rolls a flyover; when present the entire space stack is skipped. Freed on teardown.
var _flyover: Node = null
# Direct stellar-dict injection (WP11): when non-empty, _populate consumes THIS ahead of
# Run.current_stellar and reads `asteroid_base_color` from it (key optional) instead of Run meta.
# Empty = production behavior unchanged. Lets the showcase lab drive gameplay-authored (sector-map
# shaped) backdrops without writing into Run (the P1 lesson). regenerate(seed) stays deterministic —
# the override IS the stellar dict; the seed drives the rest (rocks / star layout / etc.).
var stellar_override: Dictionary = {}


func _ready() -> void:
	# PAUSABLE so the drift in _process() FREEZES with the game when the pause
	# menu sets get_tree().paused (was ALWAYS, which left the backdrop visibly
	# scrolling behind the near-opaque pause dim — "still animating", 2026-07-04).
	# The backdrop only ever renders during combat (the sole place the tree is
	# paused) or on non-pausing menu screens, so pausable is a no-op elsewhere.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_layer_stars         = get_node_or_null("LayerStars")
	_layer_planet        = get_node_or_null("LayerPlanet")
	_layer_stellar_far   = get_node_or_null("LayerStellarFar")
	_layer_stellar_mid   = get_node_or_null("LayerStellarMid")
	_layer_stellar_near  = get_node_or_null("LayerStellarNear")
	_layer_streaks       = get_node_or_null("LayerStreaks")
	_layer_composite     = get_node_or_null("LayerComposite")
	_scroll_layers = [_layer_planet, _layer_stellar_far, _layer_stellar_mid, _layer_stellar_near]
	_populate()


func _populate() -> void:
	var run_node := get_node_or_null("/root/Run")

	# Scene light (docs/scene_light_direction_2026-07-28.md §4): resolve THIS level's sun FIRST.
	# Everything built below samples SceneLight during construction — the flyover ground's sun_dir,
	# every PlanetKit body's light_origin, the asteroid shadow rig — so publishing here, before the
	# flyover branch returns, is what makes the whole scene agree. _populate is the single funnel
	# every backdrop host uses (combat, signal events, labs, capture tools), so labs that inject a
	# stellar_override get a consistent sun for free. Constant for the level by contract: nothing
	# re-publishes until the next _populate.
	var light_stellar: Dictionary = {}
	if not stellar_override.is_empty():
		light_stellar = stellar_override
	elif run_node != null and "current_stellar" in run_node and run_node.current_stellar is Dictionary:
		light_stellar = run_node.current_stellar
	SceneLight.set_level_azimuth_deg(SceneLight.azimuth_for_stellar(light_stellar))

	# Planet Flyover branch (Phase B1): in a REAL run on a planet POI, a deterministic per-node
	# roll can replace the whole space parallax stack with the close-to-planet flyover backdrop.
	# OPT-IN via allow_flyover — only combat's main.tscn Backdrop instance enables it. Every other
	# coordinator host (main menu via menu_backdrop, signal_event, dev labs, capture tools) keeps
	# the space parallax unconditionally, even when Run still carries mid-run node state (Roman
	# 2026-07-18: main screen stays space). Labs that inject stellar_override never roll flyover;
	# dev testing of flyover in combat goes through the forced_flyover Run meta (handled inside
	# FlyoverPlanner.plan). Non-planet POIs (obj_kind != 0) never plan, so stronghold/asteroid-
	# pepper nodes fall through to the standard stack for free.
	if allow_flyover and stellar_override.is_empty() and run_node != null \
			and String(run_node.get("current_node_id") if "current_node_id" in run_node else "") != "":
		var fstellar: Dictionary = run_node.current_stellar if "current_stellar" in run_node else {}
		var frun_seed: int = int(run_node.run_seed) if "run_seed" in run_node else 0
		var plan: Dictionary = FlyoverPlanner.plan(fstellar, frun_seed, String(run_node.current_node_id))
		if not plan.is_empty():
			_build_flyover(plan)
			return

	var stellar: Dictionary = {}
	# stellar_override (WP11) wins over Run.current_stellar when set — the lab injects a
	# gameplay-authored dict here without touching Run.
	if not stellar_override.is_empty():
		stellar = stellar_override
	elif run_node and "current_stellar" in run_node:
		stellar = run_node.current_stellar

	var rng := RandomNumberGenerator.new()
	# Deterministic per-run seed in gameplay (from Run); a fresh time-based
	# seed everywhere else (tuner "Generate New", capture tool) so each
	# regeneration actually varies instead of repeating one fixed backdrop.
	var seed_val := int(Time.get_ticks_usec())
	if run_node:
		var rs := 12345 if not "run_seed" in run_node else int(run_node.run_seed)
		var sc := 0 if not "sectors_cleared" in run_node else int(run_node.sectors_cleared)
		var node_id: String = run_node.get("current_node_id") if "current_node_id" in run_node else ""
		var node_hash := hash(node_id) if node_id != "" else 0
		seed_val = rs + sc * 9973 + node_hash
	# Explicit override (regenerate / dev labs) wins — lets "Generate New" actually
	# vary the composition without writing into Run (the P1 seed bug).
	if _seed_override >= 0:
		seed_val = _seed_override
	rng.seed = abs(seed_val)

	# Full-variety fallback (WP3): compose a rich stellar dict for empty-context
	# backdrops (menus/dev) instead of the bare single-planet fallback below.
	# Consumes `rng` FIRST (before the planet/size rolls) so regenerate(seed) stays
	# deterministic. Inert unless the flag is on — no rng is consumed here when off,
	# so the bare-fallback rng stream (and today's visuals) is byte-identical.
	if stellar.is_empty() and use_composer_fallback:
		var opts := {}
		if forced_kind != "":
			opts["kind"] = forced_kind
		stellar = StellarComposer.compose(rng, opts)
	last_stellar = stellar

	# Base palette (key/dust/deep): carried on the composed dict, else authored from
	# the sector-map dict (so combat gains a palette too). accent is filled after the
	# planet spawns. Duplicated so we never mutate Run.current_stellar in place.
	var pal: Dictionary = (stellar.get("palette", {}) as Dictionary).duplicate()
	if pal.is_empty():
		pal = StellarComposer.author_palette(stellar)

	# Reseed the starfield so the star layout varies per level/regen (it was a
	# byte-identical constant seed before). Derived from seed_val by a fixed salt
	# — NOT from `rng`, so this does not consume the main stream (which would shift
	# the planet pick / size roll and change today's visuals). Runs before either
	# branch so both the current_stellar and fallback paths reseed. key_tint MUST be
	# set before reseed() — reseed respawns the stars, which read key_tint at spawn.
	if _layer_stars != null:
		if "key_tint" in _layer_stars:
			_layer_stars.set("key_tint", pal.get("key", Color.WHITE) if use_palette else Color.WHITE)
		if _layer_stars.has_method("reseed"):
			_layer_stars.reseed(abs(seed_val ^ 0x51A2F17D))

	# Planet
	var planet_idx := forced_planet_idx
	if planet_idx < 0:
		# 0..10 — includes the ringed GasPlanetLayers(9) + Rivers(10); the old % 9 capped at 0..8
		# and silently excluded both from every random backdrop. LayerPlanet.PLANETS has all 11.
		planet_idx = stellar.get("planet_idx", rng.randi() % 11)
	var size_mult := rng.randf_range(1.0 - planet_size_variance, 1.0 + planet_size_variance)
	var actual_size := planet_size * size_mult
	# Composer size widening (item 5): a composed single-planet dict may carry a wider
	# per-scene `size_scale` than planet_size_variance allows. Absent on sector-map dicts
	# (that path untouched) and on the bare fallback, so production is byte-identical.
	if stellar.has("size_scale"):
		actual_size *= float(stellar["size_scale"])

	# Row-system staging: if current_stellar carries a non-empty `system` array,
	# render every body (star + nearest planets) staged by frac/scale instead of
	# a single planet. Bodies are decorative + behind gameplay. Moons are SKIPPED
	# in system mode (KNOB) — the bodies themselves are the decoration, and there
	# is no single "the planet" for moons to orbit.
	var system: Array = stellar.get("system", [])
	if _layer_planet != null:
		_layer_planet.set("pixel_density", pixel_density)
		# Star-mode drives per-body parallax depth weighting (item 6) — near_star bodies
		# read as CLOSE (move fast), distant_star bodies barely drift. "" = single-planet /
		# sector-map default (moderate). Set before spawn so bodies register with the right mult.
		if "star_mode" in _layer_planet:
			_layer_planet.set("star_mode", String(stellar.get("star_mode", "")))
		if not system.is_empty() and _layer_planet.has_method("spawn_system_body"):
			_spawn_system(system)
		elif _layer_planet.has_method("spawn_planet"):
			var planet_seed: int = int(stellar.get("planet_seed", -1))
			var star_color: Color = stellar.get("star_color", Color.WHITE)
			_layer_planet.spawn_planet(planet_idx, actual_size, rng, "", planet_seed, star_color)
			# Attach POI moons if present (single-planet path only).
			if _layer_planet.has_method("attach_moons"):
				var moons: Array = stellar.get("moons", [])
				if not moons.is_empty():
					_layer_planet.attach_moons(moons)

	# Complete + store the palette. accent = the live planet's sampled dominant hue
	# (SDR-normalized in layer_planet). System mode has no single "the planet" to
	# sample (sampler returns WHITE) — fall back to `key`: the star IS the scene's
	# light source there, and a WHITE accent would un-grade the whole scene under
	# use_palette. Stored on the coordinator for the lab + downstream consumers.
	if _layer_planet != null and _layer_planet.has_method("get_dominant_color"):
		pal["accent"] = _layer_planet.get_dominant_color()
	else:
		pal["accent"] = Color.WHITE
	if pal["accent"].is_equal_approx(Color.WHITE):
		pal["accent"] = pal.get("key", Color.WHITE)
	palette = pal

	# Stellar layers.
	# Decorative parallax asteroids appear ONLY when the current node is an
	# asteroid-field hazard (Roman 2026-05-30). The sector map sets
	# current_stellar.has_asteroids = true only for those nodes
	# (see sector_map_v3._compute_poi_stellar). When false we drive the per-layer
	# asteroid + mini-asteroid counts to ZERO so nothing spawns — note we must
	# bypass the maxi(1, ...) floor below, which previously forced >=1 asteroid
	# per layer regardless of density. Planets / nebula / stars are unaffected.
	var has_asteroids: bool = bool(stellar.get("has_asteroids", false)) or force_asteroids
	var asteroid_density: float = float(stellar.get("asteroid_density", 0.0))
	# Asteroid drop shadows: (re)create or drop the rig BEFORE the layer loop —
	# layer_stellar binds mask textures at rock spawn via the rig's group. When
	# dropping, leave the group first so this populate's rocks can't bind a
	# dying rig's viewport texture.
	if asteroid_shadows and has_asteroids:
		if _shadow_rig == null or not is_instance_valid(_shadow_rig):
			_shadow_rig = AsteroidShadowRig.new()
			add_child(_shadow_rig)
	elif _shadow_rig != null:
		if is_instance_valid(_shadow_rig):
			_shadow_rig.remove_from_group("asteroid_shadow_rig")
			_shadow_rig.queue_free()
		_shadow_rig = null
	var density_mult: float = (0.5 + asteroid_density) * asteroid_density_scale
	var ast_color: Color = Color(0.9, 0.88, 0.85, 1.0)
	# Authored asteroid colour source: the stellar_override dict (lab / WP11) carries it directly (key
	# optional); production reads it from Run meta. When an override is active we NEVER consult Run meta
	# (the lab must not depend on Run state). Either authored source wins over the palette-dust fallback.
	var override_active: bool = not stellar_override.is_empty()
	if override_active and stellar_override.has("asteroid_base_color"):
		ast_color = stellar_override["asteroid_base_color"]
	elif not override_active and run_node != null and run_node.has_meta("asteroid_base_color"):
		ast_color = run_node.get_meta("asteroid_base_color")
	elif use_palette:
		# No authored sector-map asteroid colour → ramp rocks from the palette dust hue.
		ast_color = pal.get("dust", ast_color)
	# Per-POI nebula (Roman 2026-06-12): the sector map authors a nebula_band/nebula_tint on some
	# nodes; when present, enable + tint + swirl the stellar layers' procedural nebula. Empty band =
	# no nebula (most nodes), so it stays an occasional atmospheric beat, not a constant wash.
	var nebula_band: String = String(stellar.get("nebula_band", ""))
	var nebula_tint: Color = stellar.get("nebula_tint", Color.WHITE)
	for layer in _scroll_layers:
		if layer != null and layer.has_method("populate"):
			if "nebula_enabled" in layer:
				layer.set("nebula_enabled", nebula_band != "")
				if nebula_band != "":
					# The nebula tint IS palette.dust by author_palette's derivation
					# (dust = band_tint when a band is present), so no palette branch here.
					layer.set("nebula_tint", nebula_tint)
					layer.set("nebula_swirl", nebula_swirl)
			# Capture the authored counts ONCE so regenerate() re-scales from the
			# original base, not the already-scaled value (which would compound).
			var lid: int = layer.get_instance_id()
			if not _base_counts.has(lid):
				_base_counts[lid] = {
					"ast": int(layer.get("asteroid_count")) if "asteroid_count" in layer else 0,
					"mini": int(layer.get("mini_asteroid_count")) if "mini_asteroid_count" in layer else 0,
				}
			var base_dict: Dictionary = _base_counts[lid]
			# Per-depth count multiplier (item 4): far/mid/near band picked by identity.
			# 1.0 for the planet layer (no asteroid_count) + any unmatched layer, so
			# Vector3.ONE stays byte-identical to today.
			var layer_mult: float = 1.0
			if layer == _layer_stellar_far:
				layer_mult = asteroid_layer_mult.x
			elif layer == _layer_stellar_mid:
				layer_mult = asteroid_layer_mult.y
			elif layer == _layer_stellar_near:
				layer_mult = asteroid_layer_mult.z
			if "asteroid_count" in layer:
				if has_asteroids:
					layer.set("asteroid_count", maxi(1, int(round(int(base_dict["ast"]) * density_mult * layer_mult))))
				else:
					layer.set("asteroid_count", 0)
			if "mini_asteroid_count" in layer:
				if has_asteroids:
					var base_mini: int = int(base_dict["mini"])
					layer.set("mini_asteroid_count", maxi(1, int(round(base_mini * density_mult * layer_mult))))
				else:
					layer.set("mini_asteroid_count", 0)
			if "asteroid_tint" in layer:
				layer.set("asteroid_tint", ast_color)
			layer.populate(rng)

	# Warp streaks
	if _layer_streaks != null:
		_layer_streaks.set("streak_count", warp_streak_count)
		_layer_streaks.set("streak_speed", warp_streak_speed)
		_layer_streaks.set("enabled", use_warp_streaks)
		# Tie streaks into the palette (the lab may override after this call).
		if use_palette and "streak_tint" in _layer_streaks:
			_layer_streaks.set("streak_tint", pal.get("accent", Color.WHITE))
		# The particle gradient/material are built at spawn — and on regenerate the
		# layer respawned during _clear_spawned, BEFORE the writes above. rebuild()
		# respawns only if the config actually changed (no-op on the default path).
		if _layer_streaks.has_method("rebuild"):
			_layer_streaks.rebuild()

	# Tints
	_apply_tints(planet_idx)
	_setup_composite(planet_idx)

	# Decorative background mines on minefield levels (Roman 2026-06-11): mine sprites
	# in 3 depth bands, each carrying a DIMMED pulse light, so the minefield reads as
	# a layered hazard. Pure decoration — no collision. Combat backdrop only (the flag),
	# so a stale "minefield" subtype can't leak mines into the menu / signal events.
	if enable_hazard_decor and run_node and "current_hazard_subtype" in run_node \
			and String(run_node.current_hazard_subtype) == "minefield":
		_spawn_background_mines(rng)


# Build the Planet Flyover backdrop child from a planner settings dict and slot it behind
# gameplay via FLYOVER_BASE_Z. apply_settings applies night too (the dict carries night keys),
# so night is NOT wired separately. track_combat_casters = true polls player/enemies for cloud
# shadows. base_z MUST be set before add_child — the component reads it while building rects.
func _build_flyover(plan: Dictionary) -> void:
	if _flyover != null and is_instance_valid(_flyover):
		_flyover.queue_free()
	var fb := FlyoverBackdrop.new()
	fb.name = "FlyoverBackdrop"
	fb.base_z = FLYOVER_BASE_Z
	fb.track_combat_casters = true
	add_child(fb)
	fb.apply_settings(plan)
	_flyover = fb


const BgMineScript = preload("res://scripts/parallax/bg_mine.gd")
# Live-mine art (the SAME sprites the gameplay mines use) so the background reads as
# dimmed, distant versions of the real thing — NOT the retired mine_basic.png (Roman 2026-06-11).
const MINE_BG_TEX := preload("res://graphics/mines/enemy_mine.png")
const BOMBLET_BG_TEX := preload("res://graphics/mines/enemy_mine_bomblet.png")

func _spawn_background_mines(rng: RandomNumberGenerator) -> void:
	var layers := [
		{"count": 6, "scale": 0.35, "speed": 14.0, "z": -2, "dim": 0.16},
		{"count": 10, "scale": 0.45, "speed": 24.0, "z": -1, "dim": 0.26},
		{"count": 12, "scale": 0.55, "speed": 34.0, "z": -1, "dim": 0.34},
	]
	for layer in layers:
		for i in int(layer["count"]):
			var spr := Sprite2D.new()
			spr.set_script(BgMineScript)
			# 35% bomblets for variety (mirrors the live minefield mix).
			spr.texture = BOMBLET_BG_TEX if (rng.randf() < 0.35) else MINE_BG_TEX
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2.ONE * float(layer["scale"])
			# Plain MIX blend, dimmed + semi-transparent so they read as distant background.
			# (The old BLEND_MODE_MUL multiplied the sprite's transparent border to BLACK,
			# painting a black box around every mine — Roman 2026-06-11.)
			spr.modulate = Color(0.6, 0.6, 0.66, 0.7)
			spr.position = Vector2(rng.randf_range(-16.0, 496.0), rng.randf_range(-270.0, 270.0))
			spr.z_index = int(layer["z"])
			spr.fall_speed = float(layer["speed"])
			add_child(spr)
			# Dimmed pulse light (the live-mine warning pixel, dimmed for background).
			var pulse := ColorRect.new()
			pulse.size = Vector2(1.5, 1.5)
			pulse.position = Vector2(-0.75, -0.75)
			pulse.color = Color(1.0, 0.35, 0.25, 1.0)
			pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pmat := CanvasItemMaterial.new()
			pmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			pulse.material = pmat
			spr.add_child(pulse)
			var dim: float = float(layer["dim"])
			var ptw := pulse.create_tween().set_loops()
			ptw.tween_property(pulse, "modulate:a", dim, rng.randf_range(0.7, 1.2)).set_trans(Tween.TRANS_SINE)
			ptw.tween_property(pulse, "modulate:a", dim * 0.15, rng.randf_range(0.7, 1.2)).set_trans(Tween.TRANS_SINE)


# Render a staged star-system: clear LayerPlanet ONCE, then spawn each body at a
# frac-derived screen position + scale-derived size. `system` entries are dicts:
#   {kind, planet_idx, planet_seed, frac, scale, star_color}
func _spawn_system(system: Array) -> void:
	if _layer_planet.has_method("clear_planet"):
		_layer_planet.clear_planet()
	for body in system:
		var b: Dictionary = body
		var p_idx: int = int(b.get("planet_idx", 8))
		var p_seed: int = int(b.get("planet_seed", 0))
		var scale_f: float = float(b.get("scale", 1.0))
		var frac: float = clampf(float(b.get("frac", 0.0)), 0.0, 1.0)
		var star_color: Color = b.get("star_color", Color.WHITE)
		# RAW (unfloored) px from the size ceiling — this is what decides whether
		# the body is close enough to render as a sphere or far enough to collapse
		# to a glowing dot. Do NOT floor before this branch (see dot-threshold).
		var raw_px: float = SYS_SIZE_CEILING * scale_f
		# Position: x by frac across the comfortable spread; y is a per-seed
		# jitter within the band, with larger (nearer) bodies nudged lower so
		# they read as more central/present.
		var jrng := RandomNumberGenerator.new()
		jrng.seed = abs(p_seed) ^ 0x5A17C0DE
		var center_x: float = lerpf(SYS_X_MIN, SYS_X_MAX, frac)
		if raw_px < SYS_DOT_THRESHOLD_PX:
			# Extreme distance: render a tiny additive glowing dot in the body's
			# MAIN color instead of a degenerate sphere. The dot sits centered in
			# the upper band (no big-body lower-nudge, it has no size to nudge).
			var dot_color: Color = _body_main_color(p_idx, star_color)
			var dot_y: float = SYS_Y_BASE + jrng.randf_range(0.0, SYS_Y_JITTER)
			var dot_center: Vector2 = Vector2(center_x, dot_y)
			if _layer_planet.has_method("spawn_system_dot"):
				_layer_planet.spawn_system_dot(dot_center, SYS_DOT_PX, dot_color)
			continue
		# Close enough to read as a body — floor so it doesn't degenerate.
		var size_px: float = maxf(SYS_MIN_BODY_PX, raw_px)
		var y_top: float = SYS_Y_BASE + jrng.randf_range(0.0, SYS_Y_JITTER) + scale_f * SYS_Y_LOWER_BIG
		var top_left: Vector2 = Vector2(center_x - size_px * 0.5, y_top)
		# glow_boost (item 5): a tiny distant_star still reads "very bright" — the composer
		# stamps >1 on the star entry so spawn_system_body over-boosts its HDR palette + adds a
		# bloom halo. 1.0 (planets / near_star) = today's glow. Default 1.0 keeps other callers inert.
		var glow_boost: float = float(b.get("glow_boost", 1.0))
		_layer_planet.spawn_system_body(p_idx, size_px, top_left, p_seed, star_color, glow_boost)


# Representative MAIN color for a far body's glowing dot. The star (planet_idx
# 8) uses its actual star_color; planets use the per-type PLANET_TINT palette
# (PixelPlanets are shader-driven ColorRects with no CPU-readable texture, so
# _derive_color can't be used here — Roman 2026-05-30).
func _body_main_color(planet_idx: int, star_color: Color) -> Color:
	if planet_idx == 8:
		return Color(star_color.r, star_color.g, star_color.b, 1.0)
	var c: Color = PLANET_TINT.get(planet_idx, Color(0.8, 0.85, 1.0))
	return Color(c.r, c.g, c.b, 1.0)


# The grade source color: the live planet's sampled dominant hue when
# use_dominant_grade is on, else the per-type PLANET_TINT (today's behavior).
func _grade_tint(planet_idx: int) -> Color:
	# use_palette subsumes use_dominant_grade: grade from the palette accent (the live
	# planet's sampled hue) so every authority shares one colour. use_dominant_grade
	# keeps working independently when use_palette is off.
	if use_palette and palette.has("accent"):
		return palette["accent"]
	if use_dominant_grade and _layer_planet != null and _layer_planet.has_method("get_dominant_color"):
		return _layer_planet.get_dominant_color()
	return PLANET_TINT.get(planet_idx, Color.WHITE)


func _apply_tints(planet_idx: int) -> void:
	var base_tint: Color = _grade_tint(planet_idx)
	var skip := planet_idx in SKIP_TINT

	_set_modulate(_layer_stellar_far,  base_tint.lerp(Color.WHITE, 0.75) if not skip else Color.WHITE)
	_set_modulate(_layer_stellar_mid,  base_tint.lerp(Color.WHITE, 0.60) if not skip else Color.WHITE)
	_set_modulate(_layer_stellar_near, base_tint.lerp(Color.WHITE, 0.45) if not skip else Color.WHITE)


func _set_modulate(layer: Node, color: Color) -> void:
	if layer == null:
		return
	if "modulate_color" in layer:
		layer.modulate_color = color
	else:
		var cm := layer.get_node_or_null("CanvasModulate") as CanvasModulate
		if cm:
			cm.color = color


func _setup_composite(planet_idx: int) -> void:
	if _layer_composite == null:
		return
	var base_tint: Color = _grade_tint(planet_idx)
	var skip := planet_idx in SKIP_TINT
	var grade_color := Color.WHITE.lerp(base_tint, tint_alpha) if not skip else Color.WHITE

	var cm := _layer_composite.get_node_or_null("CanvasModulate") as CanvasModulate
	if cm:
		cm.color = grade_color

	var grade := _layer_composite.get_node_or_null("GradeRect") as ColorRect
	if grade and grade.material == null:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		grade.material = mat

	var vignette := _layer_composite.get_node_or_null("Vignette") as Sprite2D
	if vignette and vignette.texture == null:
		var mat2 := CanvasItemMaterial.new()
		mat2.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		vignette.material = mat2
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1,1,1,1), Color(0.74, 0.74, 0.74, 1)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to   = Vector2(1.0, 0.5)
		vignette.texture = tex


func _process(delta: float) -> void:
	var drift_delta := drift_speed * delta
	for layer in _scroll_layers:
		if layer != null and layer.has_method("scroll"):
			layer.scroll(drift_delta * float(layer.get("scroll_rate") if "scroll_rate" in layer else 1.0))
	if _layer_stars != null and _layer_stars.has_method("scroll_stars"):
		_layer_stars.scroll_stars(drift_delta)
	# Horizontal parallax — skip the whole loop while inert (keeps the hot path
	# clean; offsets stay untouched, so no visual change at the default 0).
	if lateral_strength != 0.0:
		_lateral_pos = lerpf(_lateral_pos, _lateral_target, 0.1)
		var shift := -_lateral_pos * lateral_strength
		if _layer_stars != null and _layer_stars.has_method("apply_lateral"):
			_layer_stars.apply_lateral(shift)
		for layer in _scroll_layers:
			if layer != null and layer.has_method("apply_lateral"):
				layer.apply_lateral(shift)


# Feed the coordinator the playfield-normalized strafe (−1..1 from center). The
# coordinator smooths this in _process. No-op on visuals until lateral_strength
# is set (the _process loop is skipped while it's 0).
func set_lateral_input(norm_x: float) -> void:
	_lateral_target = clampf(norm_x, -1.0, 1.0)


# Tear down everything _populate spawned and re-run it. `seed_override` >= 0
# forces a specific composition (deterministic — same seed = identical layout);
# -1 keeps the run/time-derived seed. This is how "Generate New" varies the
# backdrop without writing into Run (the P1 seed bug).
func regenerate(seed_override: int = -1) -> void:
	_seed_override = seed_override
	_clear_spawned()
	_populate()


# Free/reset every container _populate touches so a re-populate leaks nothing and
# leaves no stale _animated/_objects entries. Layers own their own content reset
# (reset() → _on_reset() clears planets/rocks/nebula/stars); the coordinator only
# owns the bg-mine sprites it add_child'd directly.
func _clear_spawned() -> void:
	for child in get_children():
		if child.get_script() == BgMineScript:
			child.queue_free()
	for layer in _scroll_layers:
		if layer != null and layer.has_method("reset"):
			layer.reset()
	if _layer_stars != null and _layer_stars.has_method("reset"):
		_layer_stars.reset()
	if _layer_streaks != null and _layer_streaks.has_method("reset"):
		_layer_streaks.reset()
	# Planet Flyover backdrop (Phase B1): free it so a repopulate rebuilds cleanly (or falls
	# back to the space stack if the new context isn't a flyover).
	if _flyover != null and is_instance_valid(_flyover):
		_flyover.queue_free()
	_flyover = null
	# Lateral state resets so a regen doesn't carry a stale offset.
	_lateral_pos = 0.0
	_lateral_target = 0.0
