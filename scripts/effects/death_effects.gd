extends Node2D

# DeathEffects (Roman 2026-06-29) — graphical enemy-death STYLES. One controller per dying ship: it
# takes over the host hull, plays the chosen style (composing the existing VFX primitives — fire /
# smoke / spark trails, the centralized ExplosionFx blast, ShipDebrisEmber burning chunks, the
# pixelated-burn disintegrate, and the mid-depth recede tint) then frees BOTH the host and itself.
#
# Built for the Shader Lab "Death" tab (the tuner); designed to drop onto enemy_base.explode() later.
#
#   var fx := DeathEffects.new()
#   vfx_parent.add_child(fx)            # a node that OUTLIVES the enemy (combat scene root / lab stage)
#   fx.play(enemy, "spinout", cfg, Vector2.DOWN * speed,
#       {"vfx_parent": vfx_parent, "wreck_parent": wreck_layer, "bounds": play_rect})
#
# Each style declares its OWN knob schema in STYLE_KNOBS (the source of truth — the lab builds sliders
# from it + seeds defaults). A knob marked `"range": true` has a [lo, hi] value that DeathEffects
# RANDOMIZES per play (each death varies). play()'s cfg overrides the schema.
#
# The styles:
#   random    — half spinout(→resolution), half a size-gated resolution straight away.
#   spinout   — ball-blast over an engine, ignite a size-based trail, keep the heading it died with +
#               veer toward the nearer edge while tumbling, then RESOLVE into instakill / flashout /
#               wreck / blow_out (lab Resolution dropdown; random in production).
#   flashout  — circle blasts + a spark cone in the travel direction + a brief disintegrate (small/tiny).
#   instakill — explode; debris matches the enemy's velocity going into the kill (any size).
#   blow_out  — slump + DARKEN + SHRINK while ball-pops ripple across weighted hull markers (medium+).
#   wreck     — the damaged hull keeps its momentum + drifts off-screen while shrinking; fire trail
#               tapers → smoke + sparks (spark density tapers with the shrink). Randomly a shallow shrink
#               or a deep, slow shrink that recedes away. (Also spinout's "wreck" resolution.)

signal finished

const STYLES := ["random", "spinout", "flashout", "instakill", "blow_out", "wreck"]
# Spinout resolutions (how the spin-out ends). "random" picks uniformly among the concrete four.
const RESOLUTIONS := ["random", "instakill", "flashout", "wreck", "blow_out"]

# Overkill-biased death pick (Roman 2026-07-08). When the killing blow massively overkills a hull —
# overkill_ratio = fatal hull damage / max_health, supplied by the caller (enemy_base.take_hit → styled)
# — the "random" auto-pick leans toward the punchy INSTANT styles (instakill / flashout) and away from
# the slow spin-out, so a big weapon one-shotting small chaff reads snappy instead of a lazy tumble.
# This is the small-chaff-hit-hard case (a boss taking 2× overkill is rare/irrelevant, and composes with
# the size-gating below). The bias is a WEIGHTING, not a hard override, so variety is preserved. Absent
# or modest overkill (0.0 = no info, e.g. bosses / mass-wipe / ram deaths, or ratio ≤ threshold) leaves
# the pick EXACTLY as before.
const OVERKILL_RATIO_THRESHOLD := 2.0   # ratio above which the bias engages (Roman: "> 2× max health")
const OVERKILL_SPINOUT_CHANCE := 0.2    # spin-out probability in _run_random when overkilled (baseline 0.5)
const OVERKILL_INSTANT_WEIGHT := 3.0    # weight multiplier on instakill/flashout in the gated pick when overkilled

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const EmberFx = preload("res://scripts/effects/ember_fx.gd")
const BurnFx = preload("res://scripts/effects/burn_fx.gd")
const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const DamageSmokeTrail = preload("res://scripts/effects/damage_smoke_trail.gd")
# Small fireball trail for general use (Roman 2026-07-16). The bigger explosion-strip trail is kept on
# hand at burning_trail.tscn / burning_trail_old.tscn for a future use.
const BURNING_TRAIL := preload("res://scenes/effects/burning_trail_small.tscn")
const TORCH_SHADER := preload("res://graphics/torch_fire.gdshader")

# Ships at/above this size_scale get the FULL fire trail; smaller ones get the smoulder trail
# (black smoke + sparks + a small torch, the debris-ember look).
const LARGE_SIZE := 2.5
const SPINOUT_LEAD := 0.6        # seconds of pure spin-out before it resolves
const DRIFT_SAFETY := 8.0        # wreck finish backstop if it never leaves the frame
const DRIFT_DECEL := 18.0        # wreck momentum decay (px/s²) toward the drift floor
const WRECK_SHRINK_TIME_MAX := 6.0  # deepest-shrink variant duration (smaller shrink = slower)

# The hull-ripple explosion (Roman's lab tune) — small fast ball-pops, no glow/shockwave/sparks/debris.
# Used per blast in the blow-out cascade; the cascade (blast_count over blast_window) ripples them
# across the hull markers.
const HULL_RIPPLE_CFG := {
	"type": "ball", "size": 1.0, "area": 5.0, "duration": 0.025, "density": 1, "stagger": 0.2,
	"secondaries": 1.0, "glow": 0.0, "shockwave": 0.0, "sparks": 0.0, "debris": 0.0,
}

# Blow-out blast origins: the damage-tell hardpoint marker set, engines/thrusters weighted higher.
const BLAST_MARKER_GROUPS := [
	{"globs": ["Engine*", "Thruster*"], "w": 2.0},
	{"globs": ["*Muzzle*", "Cannon*", "cannon_*", "Gun*", "weapon_*", "Launcher*", "Missile*", "LaunchPoint*", "launch_point*", "missile_port*", "Turret*", "turret_*"], "w": 1.0},
]

# Per-style tunable knob schema {key, label, min, max, step, def}. `range` knobs carry a [lo, hi] def
# and RANDOMIZE per play; the lab shows Lo/Hi sliders for them.
const STYLE_KNOBS := {
	# Spin-out params randomize per death (each spin-out looks different). spinout_amp is fixed.
	"spinout": [
		{"key": "spinout_speed", "label": "Spinout speed", "range": true, "min": 0.0, "max": 320.0, "step": 5.0, "def": [40.0, 60.0]},
		{"key": "spinout_veer", "label": "Edge veer", "range": true, "min": 0.0, "max": 1.0, "step": 0.05, "def": [0.0, 0.3]},
		{"key": "spinout_spin", "label": "Spinout spin", "range": true, "min": 0.0, "max": 20.0, "step": 0.5, "def": [0.0, 1.0]},
		{"key": "spinout_swirl", "label": "Spinout swirl", "range": true, "min": 0.0, "max": 20.0, "step": 0.5, "def": [0.0, 0.0]},
		{"key": "spinout_amp", "label": "Spinout amplitude", "min": 0.0, "max": 120.0, "step": 5.0, "def": 35.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "range": true, "min": 0.0, "max": 1.0, "step": 0.05, "def": [0.1, 0.3]},
	],
	# explosion_density / sparks / debris are MULTIPLIERS on a size-derived base (bigger hull = MORE
	# booms). The boom SPRITES are always 1× (the never-stretch convention).
	# A "random" meta-style: either spinout(→resolution) or a size-gated resolution straight away.
	"random": [],
	# flashout = small/tiny only. Sparks thrown in a cone aimed the way the enemy was moving.
	"flashout": [
		{"key": "explosion_density", "label": "Explosion density ×", "min": 0.5, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "burn_time", "label": "Disintegrate time (s)", "min": 0.2, "max": 2.0, "step": 0.05, "def": 0.45},
		{"key": "spark_amount", "label": "Spark count", "min": 0.0, "max": 96.0, "step": 2.0, "def": 10.0},
		{"key": "spark_spread", "label": "Spark cone (deg)", "min": 5.0, "max": 120.0, "step": 5.0, "def": 85.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	# instakill = all enemies. No spark/ember sliders (those effects aren't in this one); the DEBRIS is
	# the star — it inherits the enemy's velocity going into the kill (see _run_instakill).
	"instakill": [
		{"key": "explosion_density", "label": "Explosion density ×", "min": 0.5, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "explosion_shockwave", "label": "Shockwave × (off=0)", "min": 0.0, "max": 3.0, "step": 0.1, "def": 0.0},
	],
	# Blow-out (slump + erupting marker blasts + spark trails). Defaults baked from Roman's lab tuning.
	"blow_out": [
		{"key": "enter_speed", "label": "Entry speed (px/s)", "min": 20.0, "max": 300.0, "step": 5.0, "def": 40.0},
		{"key": "decel", "label": "Deceleration", "min": 0.0, "max": 60.0, "step": 1.0, "def": 14.0},
		{"key": "min_drift", "label": "Min drift speed", "min": 20.0, "max": 200.0, "step": 5.0, "def": 70.0},
		{"key": "darken_to", "label": "Darken to", "min": 0.1, "max": 1.0, "step": 0.02, "def": 0.5},
		{"key": "darken_dur", "label": "Darken time (s)", "min": 0.3, "max": 4.0, "step": 0.1, "def": 1.8},
		{"key": "shrink_to", "label": "Shrink to (×)", "min": 0.4, "max": 1.0, "step": 0.02, "def": 0.7},
		{"key": "shrink_dur", "label": "Shrink time (s)", "min": 0.5, "max": 6.0, "step": 0.1, "def": 3.5},
		{"key": "blast_count", "label": "Blast count", "min": 1.0, "max": 16.0, "step": 1.0, "def": 10.0},
		{"key": "blast_window", "label": "Blast window (s)", "min": 0.3, "max": 4.0, "step": 0.1, "def": 2.5},
		{"key": "max_dur", "label": "Max duration (s)", "min": 1.0, "max": 8.0, "step": 0.5, "def": 6.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	# Wreck RETAINS the entry momentum (decays to a drift). Per play it randomly does either the shallow
	# shrink (shrink_to / shrink_time) or a DEEP shrink (down to 0.1) whose duration scales up as the
	# shrink deepens (to WRECK_SHRINK_TIME_MAX at the smallest). veer/spin/swirl/amp reuse the spinout_*
	# keys (the cork tick reads them), relabeled.
	"wreck": [
		{"key": "spinout_veer", "label": "Edge veer", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.2},
		{"key": "spinout_spin", "label": "Tumble (rad/s)", "min": 0.0, "max": 10.0, "step": 0.25, "def": 0.5},
		{"key": "spinout_swirl", "label": "Swirl freq", "min": 0.0, "max": 20.0, "step": 0.5, "def": 1.0},
		{"key": "spinout_amp", "label": "Wobble amp", "min": 0.0, "max": 120.0, "step": 5.0, "def": 10.0},
		{"key": "shrink_to", "label": "Shrink to (×, shallow)", "min": 0.2, "max": 1.0, "step": 0.02, "def": 0.6},
		{"key": "shrink_time", "label": "Shrink time (s, shallow)", "min": 0.5, "max": 6.0, "step": 0.1, "def": 5.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
}


# The default cfg for a style — built from its knob schema (keeps range defs as [lo, hi] arrays;
# play() resolves them to a random value per death).
static func default_cfg(style: String) -> Dictionary:
	var d := {}
	for def in STYLE_KNOBS.get(style, []):
		d[String(def["key"])] = def["def"]
	return d


# Seed the cfg for the style play() was handed. For the concrete styles this is just its own knob
# defaults. For the META styles ("random" / "spinout"), which delegate to another style's run/tick
# functions at runtime, we DON'T pre-flatten every delegate here (spinout & wreck share keys with
# CONFLICTING defs) — instead each delegation point calls _apply_style_defaults() to lay in the delegate
# style's baked defaults just-in-time (Roman 2026-07-07: production plays "random"/{} — without this the
# spin-out corkscrew fell back to the hardcoded swirl=6.0 instead of the baked 0.0, so in-game spinouts
# over-swirled vs the Death tab, which plays each style directly with its own seeded cfg).
static func _seed_cfg(style: String) -> Dictionary:
	return default_cfg(style)


var _host: Node2D = null
var _body: Sprite2D = null
var _size_scale: float = 1.0
var _cfg: Dictionary = {}
var _explicit_keys: Array = []   # cfg keys the caller passed explicitly (never overridden by delegate defaults)
# Death VFX renders UNDER gameplay actors (player / live enemies / bullets sit at z_index 0) so a
# death never occludes a live target — playspace clarity under all circumstances (Roman 2026-07-07).
# Every blast / ember / spark / smoke this controller spawns goes through _death_sink(), a relative-z
# container at this depth (explosion instances are z_as_relative=true so they inherit it).
const DEATH_VFX_Z: int = -3
var _vfx_parent: Node = null
var _sink: Node2D = null
var _wreck_parent: Node = null
var _bounds: Rect2 = Rect2(0, 0, 480, 270)
var _travel: Vector2 = Vector2.ZERO
var _phase: String = "idle"       # "idle" | "glide" | "cork" | "blowout" | "done"
var _cork_travel: Vector2 = Vector2.DOWN   # the heading the ship died with (spin-out keeps it)
var _cork_lateral: Vector2 = Vector2.ZERO  # unit perpendicular toward the nearer screen edge
var _cork_t: float = 0.0
var _spin: float = 0.0
var _cork_speed: float = 40.0              # current cork/drift speed (fixed for spinout, momentum for wreck)
var _keep_momentum: bool = false           # wreck: decay the entry speed toward a floor, don't reset it
var _drift_floor: float = 15.0             # momentum decay floor (retain forward motion)
var _resolution: String = "instakill"      # spin-out ending
var _overkill_ratio: float = 0.0           # killing-blow overkill (fatal dmg / max_health); 0 = no bias. Set from opts.
var _drift_off: bool = false               # wreck: keep drifting until off-screen
var _shrinking: bool = false               # shrink the hull each tick (wreck)
var _shrink0: Vector2 = Vector2.ONE
var _shrink_t: float = 0.0
var _shrink_target: float = 0.6            # wreck shrink end scale (this play's variant)
var _shrink_dur: float = 3.0               # wreck shrink duration (this play's variant)
var _shrink_finishes: bool = false         # deep-shrink variant ends the death when fully shrunk
var _spark_emitters: Array = []            # spark GPUParticles2D to taper (amount_ratio) as it shrinks
var _drift_t: float = 0.0
var _trails: Array = []           # every trail node (fire / smoke / spark / torch), lingered on finish
var _fire_parts: Array = []       # the FIRE bits (BURNING_TRAIL emitter / torch) to taper on fire→smoke
var _trail_markers: Array = []    # local marker positions the trail sits at
var _has_smoke: bool = false      # whether the trail already carries a smoke stream
var _start_scale: Vector2 = Vector2.ONE
var _blast_times: Array = []      # blow-out blast schedule
var _blast_markers_cache: Array = []
var _blast_sparked: Dictionary = {}
var _style_t: float = 0.0
var _done: bool = false


# Begin a death. `host` = the dying hull; `travel` = the glide / inherited velocity. opts: vfx_parent
# (blast container that outlives the host), wreck_parent (where the spin-out sinks the hull), bounds
# (play rect for the edge veer + exit). cfg may include "resolution" for spinout.
func play(host: Node2D, style: String, cfg: Dictionary = {}, travel: Vector2 = Vector2.ZERO, opts: Dictionary = {}) -> void:
	_host = host
	if _host == null or not is_instance_valid(_host):
		_finish()
		return
	_body = _find_body(_host)
	_size_scale = _measure_scale(_host, _body)
	_cfg = _seed_cfg(style)
	_cfg.merge(cfg, true)
	_explicit_keys = cfg.keys()   # caller overrides win over any just-in-time delegate defaults
	_resolve_ranges()
	_travel = travel
	_vfx_parent = opts.get("vfx_parent", null)
	if _vfx_parent == null or not is_instance_valid(_vfx_parent):
		_vfx_parent = _host.get_parent()
	_wreck_parent = opts.get("wreck_parent", _vfx_parent)
	if _wreck_parent == null or not is_instance_valid(_wreck_parent):
		_wreck_parent = _vfx_parent
	_bounds = opts.get("bounds", _bounds)
	_overkill_ratio = float(opts.get("overkill_ratio", 0.0))   # biases the "random" auto-pick when the kill overkilled
	match style:
		"random":
			_run_random()
		"spinout":
			_run_spinout()
		"flashout":
			_run_flashout()
		"instakill":
			_run_instakill()
		"blow_out":
			_run_blowout()
		"wreck":
			_run_wreck()
		_:
			_run_flashout()


# Replace any [lo, hi] range values with a single randf_range pick — each death varies.
func _resolve_ranges() -> void:
	for k in _cfg.keys():
		var v = _cfg[k]
		if v is Array and v.size() == 2:
			var lo := float(v[0])
			var hi := float(v[1])
			_cfg[k] = randf_range(minf(lo, hi), maxf(lo, hi))


# Lay a delegate STYLE's baked knob defaults into _cfg just before its run/tick functions execute — but
# only for keys the caller didn't explicitly override, and only where _cfg doesn't already carry the key
# (so a meta-style's OWN seeded value wins over a later delegate's). Range defs are resolved to a single
# pick immediately (play()'s _resolve_ranges already ran). This is what makes production's "random"/{}
# death read the LAB-TUNED spin/swirl/etc. defs instead of the hardcoded `_c(..., fallback)` values.
func _apply_style_defaults(style: String) -> void:
	for def in STYLE_KNOBS.get(style, []):
		var k := String(def["key"])
		if _explicit_keys.has(k) or _cfg.has(k):
			continue
		var dv = def["def"]
		if dv is Array and dv.size() == 2:
			_cfg[k] = randf_range(minf(float(dv[0]), float(dv[1])), maxf(float(dv[0]), float(dv[1])))
		else:
			_cfg[k] = dv


func _process(delta: float) -> void:
	if _done:
		return
	match _phase:
		"glide":
			if not _host_ok():
				_finish()
				return
			_host.global_position += _travel * delta
		"cork":
			if not _host_ok():
				_finish()
				return
			_tick_cork(delta)
		"blowout":
			if not _host_ok():
				_finish()
				return
			_tick_blowout(delta)
		_:
			pass


# ── Styles ───────────────────────────────────────────────────────────────────────────────────────

# Random meta-style: half the time a full spin-out (which resolves randomly), half the time jump
# straight to a size-gated resolution — the production-representative "surprise me" death.
func _run_random() -> void:
	# Overkill bias: a massively-overkilled hull spins out far less often — the slow tumble reads wrong on
	# a one-shot chaff kill, so most go straight to a punchy gated resolution (itself overkill-biased).
	var spin_chance: float = OVERKILL_SPINOUT_CHANCE if _overkill_ratio > OVERKILL_RATIO_THRESHOLD else 0.5
	if randf() < spin_chance:
		_run_spinout()
		return
	match _pick_gated_resolution():
		"instakill":
			_run_instakill()
		"flashout":
			_run_flashout()
		"wreck":
			_run_wreck()
		"blow_out":
			_run_blowout()
		_:
			_run_instakill()


func _run_spinout() -> void:
	_apply_style_defaults("spinout")
	_resolution = _resolve_resolution()
	# The resolution's knobs (burn_time / explosion_density / blow_out params) feed the inline resolution
	# handlers below — seed them from the resolution style's baked defaults too (spinout's shared spin/
	# swirl/veer/amp keys are already set above, so they win over wreck's conflicting defs).
	_apply_style_defaults(_resolution)
	_phase = "glide"
	var engines: Array = _engine_local()
	var first: Vector2 = (engines[0] if not engines.is_empty() else Vector2.ZERO)
	_ball_explode(_host.to_global(first))
	await _wait(0.1)
	if not _valid():
		return
	_ignite_trail()          # size-based (smoulder for small/med, full fire for large)
	_to_wreck_layer()
	_cull_host_overlays()     # flicker the glow out + fade the livery as it spins out
	_start_corkscrew()
	await _wait(SPINOUT_LEAD)
	if not _valid():
		return
	match _resolution:
		"instakill":
			_phase = "idle"
			_explode_velocity(_cork_travel * _cork_speed)   # debris matches the spin-out velocity
			_finish()
		"flashout":
			_travel = _cork_travel * _cork_speed * 0.6   # keep a bit of the spin-out motion
			_phase = "glide"
			_explode(false)
			_disintegrate()
			await _wait(_c("burn_time", 0.45) + 0.2)
			_finish()
		"wreck":
			_fire_to_smoke()
			_begin_shrink_drift()   # keep the cork motion; add shrink + off-screen finish
		"blow_out":
			_run_blowout()
		_:
			_phase = "idle"
			_explode(false)
			_finish()


# flashout keeps a bit of the ship's incoming motion rather than a hard stop, then blasts + disintegrates.
func _run_flashout() -> void:
	_apply_style_defaults("flashout")
	var dir: Vector2 = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_travel *= 0.45   # keep a bit of the incoming motion rather than a hard stop
	_phase = "glide"
	_explode(false)
	_spark_cone(dir)   # sparks thrown in a cone aimed the way the enemy was moving
	_disintegrate()
	await _wait(_c("burn_time", 0.45) + 0.2)
	_finish()


func _run_instakill() -> void:
	_apply_style_defaults("instakill")
	_phase = "idle"
	_explode_velocity(_travel)   # debris matches the enemy's incoming velocity + extra
	_finish()


# A cone of ember-sparks thrown from the hull, aimed along `dir` (the travel direction).
func _spark_cone(dir: Vector2) -> void:
	if not _host_ok():
		return
	EmberFx.spray(_death_sink(), _host.global_position, dir, {
		"amount": int(_c("spark_amount", 24.0)),
		"spread_deg": _c("spark_spread", 40.0),
		"variant": "normal",
	})


# Standalone wreck: the damaged hull KEEPS GLIDING as it sinks (no stop-then-go hitch), a brief fire
# trail tapers into smoke + sparks, then it retains its momentum and drifts off-screen while shrinking.
func _run_wreck() -> void:
	_apply_style_defaults("wreck")
	_cork_travel = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_phase = "glide"          # keep moving through the fire→smoke beat, so the drift transition is smooth
	_to_wreck_layer()
	_ignite_trail()
	_cull_host_overlays()
	await _wait(0.15)
	if not _valid():
		return
	_fire_to_smoke()
	_begin_drift()


# Standalone wreck: RETAIN the entry momentum (like blow-out) — decay it to a drift — plus a
# veer/wobble/tumble, and shrink while drifting off-screen (variant picked in _pick_shrink_variant).
func _begin_drift() -> void:
	if not _host_ok():
		_finish()
		return
	_cork_travel = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_spin = _c("spinout_spin", 0.5) * (1.0 if randf() < 0.5 else -1.0)
	_pick_edge_lateral()
	_cork_speed = maxf(_travel.length(), 20.0)     # keep the incoming speed
	_keep_momentum = true
	_drift_floor = maxf(15.0, _cork_speed * 0.4)   # decays to a drift, never fully stops
	_pick_shrink_variant()
	_drift_off = true
	_cork_t = 0.0
	_drift_t = 0.0
	_phase = "cork"


# Spinout's wreck resolution: the cork is already running (fixed spin-out speed) — just add the shrink
# variant + off-screen finish, keeping its motion.
func _begin_shrink_drift() -> void:
	if not _host_ok():
		return
	_pick_shrink_variant()
	_drift_off = true


# Wreck randomly does one of two shrinks per play: a SHALLOW shrink (shrink_to/shrink_time, drifts off),
# or a DEEP shrink (down to ~0.1) whose duration scales UP as it deepens (to WRECK_SHRINK_TIME_MAX at
# the smallest) and which ENDS the death when fully shrunk (receded into the distance).
func _pick_shrink_variant() -> void:
	_shrinking = true
	_shrink0 = _host.scale
	_shrink_t = 0.0
	if randf() < 0.5:
		_shrink_target = _c("shrink_to", 0.6)
		_shrink_dur = _c("shrink_time", 3.0)
		_shrink_finishes = false
	else:
		_shrink_target = randf_range(0.1, 0.5)
		_shrink_dur = remap(_shrink_target, 0.1, 0.5, WRECK_SHRINK_TIME_MAX, _c("shrink_time", 3.0))
		_shrink_finishes = true


# Blow-out: keep downward momentum, decelerate to a drift, DARKEN + SHRINK, and erupt a cascade of
# blasts from WEIGHTED hull markers (engines favoured) — each leaving a spark trail — then slip off.
func _run_blowout() -> void:
	_apply_style_defaults("blow_out")
	_cull_host_overlays()
	_start_scale = _host.scale
	_travel = Vector2(0.0, _c("enter_speed", 40.0) * 1.6)
	_blast_times.clear()
	var n: int = maxi(1, int(_c("blast_count", 10.0)))
	var win: float = _c("blast_window", 0.9)
	for i in n:
		_blast_times.append((float(i) / float(n)) * win)
	_blast_markers_cache = _blast_markers()
	_style_t = 0.0
	_phase = "blowout"


# ── Per-frame ticks ────────────────────────────────────────────────────────────────────────────

func _tick_cork(delta: float) -> void:
	_cork_t += delta
	if _keep_momentum:
		_cork_speed = maxf(_cork_speed - DRIFT_DECEL * delta, _drift_floor)   # retain forward motion
	# Move along the heading + a steady veer toward the nearer edge + a sine wobble, and tumble.
	var perp := Vector2(-_cork_travel.y, _cork_travel.x)
	var wob: Vector2 = perp * sin(_cork_t * _c("spinout_swirl", 6.0)) * _c("spinout_amp", 35.0)
	var veer: Vector2 = _cork_lateral * (_cork_speed * _c("spinout_veer", 0.4))
	_host.global_position += (_cork_travel * _cork_speed + veer + wob) * delta
	_host.rotation += _spin * delta
	# Shrink toward this play's target (shallow or deep variant), ease-out (blow-out model).
	if _shrinking:
		_shrink_t += delta
		var f: float = clampf(_shrink_t / maxf(0.01, _shrink_dur), 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - f, 2.0)
		_host.scale = _shrink0.lerp(_shrink0 * _shrink_target, e)
		# Taper the spark density with the shrink — fewer sparks as it recedes into the distance.
		var frac: float = clampf(_host.scale.x / maxf(0.001, _shrink0.x), 0.0, 1.0)
		for em in _spark_emitters:
			if em != null and is_instance_valid(em):
				em.amount_ratio = frac
		if _shrink_finishes and f >= 1.0:   # deep shrink complete — receded away, done
			_finish()
			return
	if not _drift_off:
		return
	_drift_t += delta
	if _drift_t >= DRIFT_SAFETY or _off_screen(_host.global_position):
		_finish()


func _tick_blowout(delta: float) -> void:
	_style_t += delta
	_travel.y = maxf(_c("min_drift", 70.0), _travel.y - _c("decel", 14.0) * delta)
	_travel.x *= 0.96
	_host.global_position += _travel * delta
	var dk: float = clampf(_style_t / maxf(0.01, _c("darken_dur", 1.8)), 0.0, 1.0)
	var b: float = lerpf(1.0, _c("darken_to", 0.5), dk)
	_host.modulate = Color(b, b, b, _host.modulate.a)
	var sh: float = clampf(_style_t / maxf(0.01, _c("shrink_dur", 3.5)), 0.0, 1.0)
	var sh_e: float = 1.0 - pow(1.0 - sh, 2.0)
	_host.scale = _start_scale.lerp(_start_scale * _c("shrink_to", 0.7), sh_e)
	# Blast cascade ERUPTING from weighted hull markers (1× sprites); each point starts a spark trail.
	for i in _blast_times.size():
		var bt: float = float(_blast_times[i])
		if bt >= 0.0 and _style_t >= bt:
			_blast_times[i] = -1.0
			var mk: Vector2 = _pick_blast_marker(_blast_markers_cache)
			ExplosionFx.play_config(_host.to_global(mk), HULL_RIPPLE_CFG, _death_sink())
			_spark_at_marker(mk)
	if _style_t >= _c("max_dur", 6.0) or _host.global_position.y > _bounds.position.y + _bounds.size.y + 60.0:
		_finish()


# ── Trails ─────────────────────────────────────────────────────────────────────────────────────

# Size-based trail: large hulls get the full BURNING_TRAIL fire streak; small/medium get the debris-
# ember SMOULDER (black smoke + sparks + a small torch). Both ride the host + linger on finish.
func _ignite_trail() -> void:
	if not _host_ok():
		return
	var spots: Array = _engine_local()
	if spots.is_empty():
		spots = [Vector2.ZERO]
	_trail_markers = spots
	var large: bool = _size_scale >= LARGE_SIZE
	for p in spots:
		if large:
			var bt: Node2D = BURNING_TRAIL.instantiate()
			bt.position = p
			_host.add_child(bt)
			var parts: GPUParticles2D = SparkTrailFx.particles(bt)
			if parts != null:
				parts.local_coords = false
				parts.emitting = true
				_fire_parts.append(parts)
			_trails.append(bt)
		else:
			_attach_smoke(p)
			var sp: Node2D = SparkTrailFx.spawn(_host, p)
			if sp != null:
				var spp: GPUParticles2D = SparkTrailFx.particles(sp)
				if spp != null:
					spp.local_coords = false
					spp.emitting = true
					_spark_emitters.append(spp)   # tapered by amount_ratio as the wreck shrinks
				_trails.append(sp)
			var torch: ColorRect = _make_smoulder_torch(p)
			_host.add_child(torch)
			_trails.append(torch)
			_fire_parts.append(torch)
	_has_smoke = not large


# Wreck transition: taper off the fire (BURNING_TRAIL emitter stops / torch fades) and make
# sure a smoke stream is running, so the fire hands off to smoke + sparks that linger behind.
func _fire_to_smoke() -> void:
	for fp in _fire_parts:
		if fp == null or not is_instance_valid(fp):
			continue
		if fp is GPUParticles2D:
			(fp as GPUParticles2D).emitting = false
		elif fp is CanvasItem:
			var tw: Tween = (fp as CanvasItem).create_tween()
			tw.tween_property(fp, "modulate:a", 0.0, 0.4)
	_fire_parts.clear()
	if not _has_smoke and _host_ok():
		for p in _trail_markers:
			_attach_smoke(p)
		_has_smoke = true


func _attach_smoke(local_pos: Vector2) -> void:
	if not _host_ok() or _vfx_parent == null or not is_instance_valid(_vfx_parent):
		return
	# The Line2D billow-smoke — the SAME damage-smoke the debris-ember + wreck use, driven at full
	# severity. Added to the vfx parent so it survives the hull and fades on its own when the host frees;
	# it samples the host marker (emit_local) each frame.
	var smoke := DamageSmokeTrail.new()
	smoke.activate_below = 0.0
	smoke.emit_local = local_pos
	smoke.drift_sign = -1.0            # enemy smoke trails up/behind the falling ship
	_death_sink().add_child(smoke)
	# Sink the smoke's Line2D under the gameplay-actor band (it's absolute-z, so the sink's relative z
	# doesn't reach it) — same playspace-clarity rule as the rest of the death VFX (Roman 2026-07-07).
	if smoke.get("_line") != null and is_instance_valid(smoke._line):
		smoke._line.z_index = DEATH_VFX_Z - 1
	smoke.set_player(_host)
	smoke._damage_level = 1.0
	smoke._severity = 1.0
	smoke._sample_interval = 0.06


# A small torch flame at a hull marker (the debris-ember look), pointing back along the ship (which
# faces down, so the child rotates PI to trail up/behind). Its orientation is a first-pass — tune it.
func _make_smoulder_torch(local_pos: Vector2) -> ColorRect:
	var sz := Vector2(10.0, 16.0)
	var rect := ColorRect.new()
	rect.size = sz
	rect.pivot_offset = sz * 0.5
	rect.position = local_pos - sz * 0.5
	rect.rotation = PI
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Relative to the wreck host (z -1 in the wreck layer) but nudged DOWN so the flame never climbs
	# into the gameplay-actor band (z 0) (Roman 2026-07-07).
	rect.z_index = -1
	rect.z_as_relative = false
	var mat := ShaderMaterial.new()
	mat.shader = TORCH_SHADER
	mat.set_shader_parameter("pixelSize", 0.06)
	mat.set_shader_parameter("toColor", Color.html("894400"))
	mat.set_shader_parameter("fromColor", Color.html("f06007"))
	mat.set_shader_parameter("sparkColor", Color.html("ffa435"))
	mat.set_shader_parameter("smokeColor", Color.html("050505"))
	mat.set_shader_parameter("speed", 5.0)
	mat.set_shader_parameter("sparkSpeed", 0.4)
	mat.set_shader_parameter("aspectRatio", sz.x / sz.y)
	mat.set_shader_parameter("size", Vector2(0.06, 0.8))
	mat.set_shader_parameter("alpha", 0.9)
	mat.set_shader_parameter("timeOffset", randf_range(0.0, 1000.0))
	mat.set_shader_parameter("seedOffset", randf_range(0.0, 100.0))
	rect.material = mat
	return rect


# ── Composed primitives ────────────────────────────────────────────────────────────────────────

func _disintegrate() -> void:
	_cull_host_overlays()
	if _body != null and is_instance_valid(_body):
		BurnFx.apply_burn(_body, _c("burn_time", 0.55), Color(0, 0, 0, 0), _burn_origin_uv())


# Cull the host's presentation the SAME FRAME the ship dies — nothing lingers a few frames past the
# hull. Hard-clears the engine exhaust (its world-space streak, else it ages out ~0.28s later) and
# hard-hides every non-body, non-glow layer (livery / outline / firecore). The glow flickers out on
# its own (glow_flicker_time). No-op for a host without those (e.g. the headless test).
func _cull_host_overlays() -> void:
	if not _host_ok():
		return
	if _host.has_method("cull_engine_trail"):
		_host.cull_engine_trail()
	elif _host.has_method("set_engine_trail_emitting"):
		_host.set_engine_trail_emitting(false)
	for child in _host.get_children():
		if not (child is CanvasItem) or _is_glow(child):
			continue
		var nm := String(child.name)
		if nm == "Livery":
			(child as CanvasItem).visible = false
			var m: Material = (child as CanvasItem).material
			if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("fade") != null:
				(m as ShaderMaterial).set_shader_parameter("fade", 0.0)
		elif nm == "Outline" or nm.begins_with("Firecore"):
			(child as CanvasItem).visible = false
	_flicker_glow_out(_c("glow_flicker_time", 0.3))


# Flicker every glow overlay on the host out: quick dim/bright stutters across `time`, then a fade.
func _flicker_glow_out(time: float) -> void:
	if not _host_ok():
		return
	var flick: float = maxf(0.0, time)
	var cycles: int = maxi(1, int(round(flick / 0.1)))
	var step: float = flick / float(maxi(1, cycles * 2))
	for n in _host.find_children("*", "Sprite2D", true, false):
		if not _is_glow(n):
			continue
		var gl: CanvasItem = n
		var tw: Tween = gl.create_tween()
		for _i in cycles:
			tw.tween_property(gl, "modulate:a", 0.15, step)
			tw.tween_property(gl, "modulate:a", 0.9, step)
		tw.tween_property(gl, "modulate:a", 0.0, 0.25)


func _is_glow(n: Node) -> bool:
	if not (n is Sprite2D):
		return false
	var nm := String(n.name)
	return nm.to_lower().contains("glow") or nm == "EngineLayer"


# A full blast at the host position, into the vfx container. With embers, scatter burning chunks too.
func _explode(with_embers: bool) -> void:
	if not _host_ok():
		return
	var world: Vector2 = _host.global_position
	# Boom SPRITES are always 1× (never-stretch); a bigger hull throws MORE booms, not bigger ones.
	ExplosionFx.play_config(world, {
		"type": String(_cfg.get("explosion_type", "basic")),
		"size": 1.0,
		"density": maxi(1, int(round((1.0 + _size_scale * 0.6) * _c("explosion_density", 1.0)))),
		"area": 6.0 + _size_scale * 5.0,
		"sparks": _c("sparks", 1.0),
		"glow": 1.2,
		"shockwave": _c("explosion_shockwave", 0.0) * clampf(_size_scale, 0.6, 2.5),
	}, _death_sink())
	if with_embers:
		_spawn_embers(world, Vector2.ZERO)


# Instakill: a clean boom + debris that MATCHES the enemy's velocity going into the kill (`inherit`)
# plus a little extra outward energy.
func _explode_velocity(inherit: Vector2) -> void:
	if not _host_ok():
		return
	var world: Vector2 = _host.global_position
	ExplosionFx.play_config(world, {
		"type": "basic", "size": 1.0,
		"density": maxi(1, int(round((1.0 + _size_scale * 0.6) * _c("explosion_density", 1.0)))),
		"area": 6.0 + _size_scale * 5.0, "sparks": 1.0, "glow": 1.2,
		"shockwave": _c("explosion_shockwave", 0.0) * clampf(_size_scale, 0.6, 2.5),
	}, _death_sink())
	_spawn_embers(world, inherit)


# Scatter ShipDebrisEmber chunks (size-derived count). Every chunk inherits `base_vel` (the enemy's
# velocity going into the kill) plus a little extra outward energy. Per-chunk recipe = Roman's Shader
# Lab Explosions-tab ember-debris tune (2026-07-07): lower-hemisphere spread, light gravity/drag, a
# short randomized burn that fades its fire out at the end (see ship_debris_ember _stop_trails/fade).
func _spawn_embers(world: Vector2, base_vel: Vector2) -> void:
	var n: int = clampi(int(round((2.0 + _size_scale * 4.0) * _c("debris", 1.0))), 0, 24)
	for i in n:
		var ang: float = randf_range(0.15, PI - 0.15)
		var spd: float = randf_range(60.0, 105.0)   # extra energy on top of the matched enemy velocity
		ShipDebrisEmber.spawn(_death_sink(), world, {
			"velocity": base_vel + Vector2(cos(ang), sin(ang)) * spd,
			"spin": randf_range(-6.0, 6.0),
			"piece_scale": randf_range(0.50, 1.00),
			"gravity": 10.0, "drag": 0.25,
			"burn_time": randf_range(0.50, 1.00),
			"flame_size": Vector2(0.10, 1.00), "flame_speed": 3.0,
		})


# A single "ball" boom over a world point (spinout's engine pop).
func _ball_explode(world: Vector2) -> void:
	ExplosionFx.play_config(world, {
		"type": "ball", "size": 1.0,
		"density": 1, "area": 0.0, "glow": 1.0, "shockwave": 0.0, "sparks": 1.0,
	}, _death_sink())


# Sink the hull into the wreck layer (reparent, world transform preserved) + dim it.
func _to_wreck_layer() -> void:
	if not _host_ok():
		return
	if _wreck_parent == null or not is_instance_valid(_wreck_parent):
		return
	var gpos: Vector2 = _host.global_position
	var grot: float = _host.global_rotation
	var gscl: Vector2 = _host.global_scale
	var cur: Node = _host.get_parent()
	if cur != _wreck_parent:
		if cur != null:
			cur.remove_child(_host)
		_wreck_parent.add_child(_host)
		_host.global_position = gpos
		_host.global_rotation = grot
		_host.global_scale = gscl
	_host.z_index = -1
	if _body != null and is_instance_valid(_body):
		_body.modulate = _body.modulate.darkened(0.35)


# Spin-out launch: keep the heading the ship died with (never reverse), and veer toward whichever
# PERPENDICULAR screen edge is nearer.
func _start_corkscrew() -> void:
	if not _host_ok():
		return
	_spin = _c("spinout_spin", 0.5) * (1.0 if randf() < 0.5 else -1.0)
	_cork_travel = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_cork_speed = _c("spinout_speed", 40.0)   # fixed tumble speed (spinout); wreck uses momentum
	_keep_momentum = false
	_shrinking = false
	_drift_off = false
	_pick_edge_lateral()
	_cork_t = 0.0
	_drift_t = 0.0
	_phase = "cork"


# Pick the perpendicular side whose screen edge is nearer, to veer toward as it drifts.
func _pick_edge_lateral() -> void:
	var perp := Vector2(-_cork_travel.y, _cork_travel.x)
	var d_plus: float = _dist_to_bounds(_host.global_position, perp)
	var d_minus: float = _dist_to_bounds(_host.global_position, -perp)
	if absf(d_plus - d_minus) < 1.0:
		_cork_lateral = perp * (signf(_spin) if _spin != 0.0 else 1.0)
	else:
		_cork_lateral = perp if d_plus < d_minus else -perp


# ── Blow-out marker helpers ──────────────────────────────────────────────────────────────────────

func _blast_markers() -> Array:
	var out: Array = []
	var seen := {}
	if _host_ok():
		for grp in BLAST_MARKER_GROUPS:
			for glob in grp["globs"]:
				for m in _host.find_children(glob, "Marker2D", true, false):
					if m is Node2D and not seen.has(m):
						seen[m] = true
						out.append({"pos": _host.to_local((m as Node2D).global_position), "weight": float(grp["w"])})
	out.append({"pos": Vector2.ZERO, "weight": 1.0})
	return out


func _pick_blast_marker(markers: Array) -> Vector2:
	if markers.is_empty():
		return Vector2.ZERO
	var total := 0.0
	for m in markers:
		total += float(m["weight"])
	var r := randf() * maxf(total, 0.0001)
	for m in markers:
		r -= float(m["weight"])
		if r <= 0.0:
			return m["pos"]
	return markers[markers.size() - 1]["pos"]


func _spark_at_marker(local_pos: Vector2) -> void:
	if not _host_ok():
		return
	var key := Vector2(roundf(local_pos.x), roundf(local_pos.y))
	if _blast_sparked.has(key):
		return
	_blast_sparked[key] = true
	var trail: Node2D = SparkTrailFx.spawn(_host, local_pos)
	if trail == null:
		return
	var parts: GPUParticles2D = SparkTrailFx.particles(trail)
	if parts != null:
		parts.local_coords = false
		parts.emitting = true
	_trails.append(trail)


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

# Read a float cfg knob with a fallback (all ranges resolved to floats in play()).
func _c(key: String, fallback: float) -> float:
	return float(_cfg.get(key, fallback))


# A relative-z container under the vfx parent that holds every death VFX so it all renders BELOW the
# gameplay-actor band (z 0). Explosion instances are z_as_relative=true → they inherit this depth;
# ember chunks / spark trails / smoke set their own absolute negative z (still under actors). Lazily
# created; survives the host (parented to _vfx_parent, not the dying hull).
func _death_sink() -> Node:
	if _sink != null and is_instance_valid(_sink):
		return _sink
	if _vfx_parent == null or not is_instance_valid(_vfx_parent):
		return _vfx_parent
	_sink = Node2D.new()
	_sink.name = "DeathVfxSink"
	_sink.z_index = DEATH_VFX_Z
	_sink.z_as_relative = false
	_vfx_parent.add_child(_sink)
	return _sink


func _host_ok() -> bool:
	return _host != null and is_instance_valid(_host)


func _resolve_resolution() -> String:
	var r := String(_cfg.get("resolution", "random"))
	if r == "random" or not RESOLUTIONS.has(r):
		return _pick_gated_resolution()
	return r


# A random resolution valid for this hull's SIZE: instakill/wreck for anyone, flashout only for
# small/tiny (< 1.5), blow_out only for medium+ (>= 1.5).
func _pick_gated_resolution() -> String:
	var opts := ["instakill", "wreck"]
	if _size_scale < 1.5:
		opts.append("flashout")
	else:
		opts.append("blow_out")
	# No overkill info (bosses / mass-wipe / ram) or a modest hit → the original uniform pick, unchanged.
	if _overkill_ratio <= OVERKILL_RATIO_THRESHOLD:
		return opts[randi() % opts.size()]
	# Overkill: weight the punchy instant styles heavier so a one-shot chaff kill reads snappy. For small
	# chaff (the target case) that's instakill + flashout; on medium+ hulls only instakill is in the gate.
	var weighted := {}
	for o in opts:
		weighted[o] = OVERKILL_INSTANT_WEIGHT if (o == "instakill" or o == "flashout") else 1.0
	return _weighted_pick(weighted)


# Pick a key from a {name: weight} dictionary proportional to its weight (insertion-ordered, deterministic).
func _weighted_pick(weighted: Dictionary) -> String:
	var total := 0.0
	for k in weighted:
		total += float(weighted[k])
	if total <= 0.0:
		return "instakill"
	var r := randf() * total
	for k in weighted:
		r -= float(weighted[k])
		if r <= 0.0:
			return String(k)
	return String(weighted.keys()[weighted.size() - 1])


func _off_screen(pos: Vector2) -> bool:
	var m := 40.0
	return pos.x < _bounds.position.x - m or pos.x > _bounds.position.x + _bounds.size.x + m \
		or pos.y < _bounds.position.y - m or pos.y > _bounds.position.y + _bounds.size.y + m


func _engine_local() -> Array:
	var out: Array = []
	if not _host_ok():
		return out
	for m in _host.find_children("Engine*", "Marker2D", true, false):
		if m is Node2D:
			out.append(_host.to_local((m as Node2D).global_position))
	return out


func _engine_world() -> Array:
	var out: Array = []
	if not _host_ok():
		return out
	for m in _host.find_children("Engine*", "Marker2D", true, false):
		if m is Node2D:
			out.append((m as Node2D).global_position)
	return out


func _burn_origin_uv() -> Vector2:
	if _body == null or not is_instance_valid(_body) or _body.texture == null:
		return Vector2(0.5, 0.5)
	var worlds: Array = _engine_world()
	if worlds.is_empty():
		return Vector2(0.5, 0.5)
	var lp: Vector2 = _body.to_local(worlds[randi() % worlds.size()])
	var uv: Vector2 = Vector2(0.5, 0.5) + lp / _body.texture.get_size()
	return uv.clamp(Vector2(0.05, 0.05), Vector2(0.95, 0.95))


# Distance from `pos` to the bounds boundary travelling along unit direction `d` (slab method).
func _dist_to_bounds(pos: Vector2, d: Vector2) -> float:
	var best := INF
	if absf(d.x) > 0.0001:
		var bx: float = (_bounds.position.x + _bounds.size.x) if d.x > 0.0 else _bounds.position.x
		best = minf(best, (bx - pos.x) / d.x)
	if absf(d.y) > 0.0001:
		var by: float = (_bounds.position.y + _bounds.size.y) if d.y > 0.0 else _bounds.position.y
		best = minf(best, (by - pos.y) / d.y)
	return maxf(0.0, best)


func _find_body(ship: Node) -> Sprite2D:
	var s := ship.get_node_or_null("Sprite2D")
	if s is Sprite2D:
		return s
	for c in ship.find_children("*", "Sprite2D", true, false):
		var nm := String(c.name).to_lower()
		if nm.contains("glow") or nm.contains("mask") or nm.contains("shadow"):
			continue
		if c is Sprite2D:
			return c as Sprite2D
	return null


# Ship size_scale = body sprite pixel size / 16 (mirrors enemy_base / the Shader Lab).
func _measure_scale(ship: Node, body: Sprite2D) -> float:
	if body != null and is_instance_valid(body) and body.texture != null:
		var fsz: Vector2 = body.texture.get_size()
		if body.hframes > 1:
			fsz.x /= float(body.hframes)
		if body.vframes > 1:
			fsz.y /= float(body.vframes)
		var gs: Vector2 = body.global_scale
		return clampf(maxf(fsz.x, fsz.y) * maxf(absf(gs.x), absf(gs.y)) / 16.0, 0.6, 3.5)
	if "display_scale" in ship:
		return clampf(float(ship.display_scale), 0.6, 3.5)
	return 1.0


func _wait(t: float) -> void:
	if t <= 0.0 or get_tree() == null:
		return
	await get_tree().create_timer(t).timeout


func _valid() -> bool:
	return not _done and _host != null and is_instance_valid(_host) and is_inside_tree()


# Detach any live trails so their streak lingers + fades instead of snapping off with the hull.
func _release_trails() -> void:
	for bt in _trails:
		if bt == null or not is_instance_valid(bt):
			continue
		var parts: GPUParticles2D = SparkTrailFx.particles(bt)
		if parts == null and bt is GPUParticles2D:
			parts = bt
		if parts != null:
			parts.emitting = false
		# Only reparent WORLD-space (Node2D) trails to linger — a Control (the smoulder torch) frees
		# with the host instead of surviving. Reparent into the death SINK (negative z) so the lingering
		# streak stays UNDER the gameplay-actor band, not the raw vfx parent (z 0) (Roman 2026-07-07).
		var sink: Node = _death_sink()
		if sink != null and is_instance_valid(sink) and bt is Node2D:
			var n2d: Node2D = bt
			var gp: Vector2 = n2d.global_position
			var cur: Node = bt.get_parent()
			if cur != null and cur != sink:
				cur.remove_child(bt)
				sink.add_child(bt)
				n2d.global_position = gp
			if get_tree() != null:
				get_tree().create_timer(0.9).timeout.connect(bt.queue_free)
	_trails.clear()


func _finish() -> void:
	if _done:
		return
	_done = true
	_phase = "done"
	_release_trails()
	# The sink holds lingering trails/embers that outlive this controller — free it once they've
	# faded so it doesn't leak (well past the 0.9s trail linger + ember burn) (Roman 2026-07-07).
	if _sink != null and is_instance_valid(_sink) and get_tree() != null:
		get_tree().create_timer(4.0).timeout.connect(_sink.queue_free)
	_sink = null
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null
	finished.emit()
	queue_free()
