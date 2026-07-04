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
#   spinout   — ball-blast over an engine, ignite a size-based trail, keep the heading it died with +
#               veer toward the nearer edge while tumbling, then RESOLVE into instakill / flashout /
#               wreck / descent (lab Resolution dropdown; random in production).
#   flashout  — the default look: circle blasts + a brief disintegrate.
#   instakill — just explode with debris/sparks/embers, gone immediately.
#   blow_out  — slump + DARKEN + SHRINK while a cascade of blasts ERUPTS from weighted hull markers
#               (engines favoured), each leaving a spark trail, then slips off.
#   wreck     — the damaged hull drifts in its heading until off-screen; fire trail tapers → smoke +
#               sparks linger. (Also spinout's "wreck" resolution.)
#   descent   — like wreck but keeps shrinking + receding into the backdrop tint until ~1px / off.
#               (Also spinout's "descent" resolution.)

signal finished

const STYLES := ["random", "spinout", "flashout", "instakill", "blow_out", "wreck", "descent"]
# Spinout resolutions (how the spin-out ends). "random" picks uniformly among the concrete four.
const RESOLUTIONS := ["random", "instakill", "flashout", "wreck", "descent", "blow_out"]

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const EmberFx = preload("res://scripts/effects/ember_fx.gd")
const BurnFx = preload("res://scripts/effects/burn_fx.gd")
const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const DamageSmokeTrail = preload("res://scripts/effects/damage_smoke_trail.gd")
const MidDepth = preload("res://scripts/effects/mid_depth_presentation.gd")
const BURNING_TRAIL := preload("res://scenes/effects/burning_trail.tscn")
const TORCH_SHADER := preload("res://graphics/torch_fire.gdshader")

# Ships at/above this size_scale get the FULL fire trail; smaller ones get the smoulder trail
# (black smoke + sparks + a small torch, the debris-ember look).
const LARGE_SIZE := 2.5
const SPINOUT_LEAD := 0.6        # seconds of pure spin-out before it resolves
const DESCENT_SHRINK_TIME := 2.5 # descent shrink-to-1px duration (ease-out, like blow_out)
const DESCENT_MIN_SCALE := 0.04  # ~1px for a 16px sprite
const DRIFT_SAFETY := 8.0        # wreck/descent finish backstop if it never leaves the frame
const DRIFT_DECEL := 18.0        # wreck/descent momentum decay (px/s²) toward the drift floor

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
		{"key": "spinout_speed", "label": "Spinout speed", "range": true, "min": 0.0, "max": 320.0, "step": 5.0, "def": [0.0, 40.0]},
		{"key": "spinout_veer", "label": "Edge veer", "range": true, "min": 0.0, "max": 1.0, "step": 0.05, "def": [0.0, 0.3]},
		{"key": "spinout_spin", "label": "Spinout spin", "range": true, "min": 0.0, "max": 20.0, "step": 0.5, "def": [0.0, 1.0]},
		{"key": "spinout_swirl", "label": "Spinout swirl", "range": true, "min": 0.0, "max": 20.0, "step": 0.5, "def": [0.0, 1.0]},
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
		{"key": "spark_amount", "label": "Spark count", "min": 0.0, "max": 96.0, "step": 2.0, "def": 24.0},
		{"key": "spark_spread", "label": "Spark cone (deg)", "min": 5.0, "max": 120.0, "step": 5.0, "def": 40.0},
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
		{"key": "blast_window", "label": "Blast window (s)", "min": 0.3, "max": 4.0, "step": 0.1, "def": 0.9},
		{"key": "max_dur", "label": "Max duration (s)", "min": 1.0, "max": 8.0, "step": 0.5, "def": 6.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	# Wreck / descent RETAIN the entry momentum (they don't reset to a fixed drift speed — see
	# _begin_drift). veer/spin/swirl/amp reuse the spinout_* keys (the cork tick reads them), relabeled.
	"wreck": [
		{"key": "spinout_veer", "label": "Edge veer", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.2},
		{"key": "spinout_spin", "label": "Tumble (rad/s)", "min": 0.0, "max": 10.0, "step": 0.25, "def": 0.5},
		{"key": "spinout_swirl", "label": "Swirl freq", "min": 0.0, "max": 20.0, "step": 0.5, "def": 1.0},
		{"key": "spinout_amp", "label": "Wobble amp", "min": 0.0, "max": 120.0, "step": 5.0, "def": 10.0},
		{"key": "shrink_to", "label": "Shrink to (×)", "min": 0.2, "max": 1.0, "step": 0.02, "def": 0.6},
		{"key": "shrink_time", "label": "Shrink time (s)", "min": 0.5, "max": 6.0, "step": 0.1, "def": 3.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	"descent": [
		{"key": "spinout_veer", "label": "Edge veer", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.15},
		{"key": "spinout_spin", "label": "Tumble (rad/s)", "min": 0.0, "max": 10.0, "step": 0.25, "def": 0.5},
		{"key": "spinout_swirl", "label": "Swirl freq", "min": 0.0, "max": 20.0, "step": 0.5, "def": 1.0},
		{"key": "spinout_amp", "label": "Wobble amp", "min": 0.0, "max": 120.0, "step": 5.0, "def": 8.0},
		{"key": "shrink_time", "label": "Shrink to 1px (s)", "min": 0.5, "max": 6.0, "step": 0.1, "def": 2.5},
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


var _host: Node2D = null
var _body: Sprite2D = null
var _size_scale: float = 1.0
var _cfg: Dictionary = {}
var _vfx_parent: Node = null
var _wreck_parent: Node = null
var _bounds: Rect2 = Rect2(0, 0, 480, 270)
var _travel: Vector2 = Vector2.ZERO
var _phase: String = "idle"       # "idle" | "glide" | "cork" | "blowout" | "done"
var _cork_travel: Vector2 = Vector2.DOWN   # the heading the ship died with (spin-out keeps it)
var _cork_lateral: Vector2 = Vector2.ZERO  # unit perpendicular toward the nearer screen edge
var _cork_t: float = 0.0
var _spin: float = 0.0
var _cork_speed: float = 40.0              # current cork/drift speed (fixed for spinout, momentum for wreck)
var _keep_momentum: bool = false           # wreck/descent: decay the entry speed toward a floor, don't reset it
var _drift_floor: float = 15.0             # momentum decay floor (retain forward motion)
var _resolution: String = "instakill"      # spin-out ending
var _drift_off: bool = false               # wreck/descent: keep drifting until off-screen
var _descent: bool = false                 # descent: shrink all the way to ~1px + recede (vs wreck's partial shrink)
var _shrinking: bool = false               # shrink the hull each tick (wreck + descent)
var _shrink0: Vector2 = Vector2.ONE
var _shrink_t: float = 0.0
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
	_cfg = default_cfg(style)
	_cfg.merge(cfg, true)
	_resolve_ranges()
	_travel = travel
	_vfx_parent = opts.get("vfx_parent", null)
	if _vfx_parent == null or not is_instance_valid(_vfx_parent):
		_vfx_parent = _host.get_parent()
	_wreck_parent = opts.get("wreck_parent", _vfx_parent)
	if _wreck_parent == null or not is_instance_valid(_wreck_parent):
		_wreck_parent = _vfx_parent
	_bounds = opts.get("bounds", _bounds)
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
		"descent":
			_run_descent()
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
	if randf() < 0.5:
		_run_spinout()
		return
	match _pick_gated_resolution():
		"instakill":
			_run_instakill()
		"flashout":
			_run_flashout()
		"wreck":
			_run_wreck()
		"descent":
			_run_descent()
		"blow_out":
			_run_blowout()
		_:
			_run_instakill()


func _run_spinout() -> void:
	_resolution = _resolve_resolution()
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
			_begin_shrink_drift(false)   # keep the cork motion; add shrink + off-screen finish
		"descent":
			_fire_to_smoke()
			_apply_recede_tint()
			_begin_shrink_drift(true)
		"blow_out":
			_run_blowout()
		_:
			_phase = "idle"
			_explode(false)
			_finish()


# flashout keeps a bit of the ship's incoming motion rather than a hard stop, then blasts + disintegrates.
func _run_flashout() -> void:
	var dir: Vector2 = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_travel *= 0.45   # keep a bit of the incoming motion rather than a hard stop
	_phase = "glide"
	_explode(false)
	_spark_cone(dir)   # sparks thrown in a cone aimed the way the enemy was moving
	_disintegrate()
	await _wait(_c("burn_time", 0.45) + 0.2)
	_finish()


func _run_instakill() -> void:
	_phase = "idle"
	_explode_velocity(_travel)   # debris matches the enemy's incoming velocity + extra
	_finish()


# A cone of ember-sparks thrown from the hull, aimed along `dir` (the travel direction).
func _spark_cone(dir: Vector2) -> void:
	if not _host_ok():
		return
	EmberFx.spray(_vfx_parent, _host.global_position, dir, {
		"amount": int(_c("spark_amount", 24.0)),
		"spread_deg": _c("spark_spread", 40.0),
		"variant": "normal",
	})


# Standalone wreck: the damaged hull sinks + drifts in its heading until off-screen; a brief fire
# trail tapers into smoke + sparks. (Spinout's "wreck" resolution reuses the same drift + fire→smoke.)
func _run_wreck() -> void:
	_to_wreck_layer()
	_ignite_trail()
	_cull_host_overlays()
	await _wait(0.15)
	if not _valid():
		return
	_fire_to_smoke()
	_begin_drift(false)


# Standalone descent: like wreck, but keeps shrinking toward ~1px + recedes into the backdrop tint.
func _run_descent() -> void:
	_to_wreck_layer()
	_ignite_trail()
	_cull_host_overlays()
	await _wait(0.15)
	if not _valid():
		return
	_fire_to_smoke()
	_apply_recede_tint()
	_begin_drift(true)


# Standalone wreck/descent: RETAIN the entry momentum (like blow-out) — decay it toward a floor, not
# reset to a fixed speed — plus a veer/wobble/tumble, and shrink while drifting off-screen.
func _begin_drift(is_descent: bool) -> void:
	if not _host_ok():
		_finish()
		return
	_cork_travel = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_spin = _c("spinout_spin", 0.5) * (1.0 if randf() < 0.5 else -1.0)
	_pick_edge_lateral()
	_cork_speed = maxf(_travel.length(), 20.0)     # keep the incoming speed
	_keep_momentum = true
	_drift_floor = maxf(15.0, _cork_speed * 0.4)   # never fully stop — retain forward motion
	_shrinking = true
	_shrink0 = _host.scale
	_shrink_t = 0.0
	_descent = is_descent
	_drift_off = true
	_cork_t = 0.0
	_drift_t = 0.0
	_phase = "cork"


# Spinout's wreck/descent resolution: the cork is already running (fixed spin-out speed) — just add the
# shrink + off-screen finish, keeping its motion.
func _begin_shrink_drift(is_descent: bool) -> void:
	if not _host_ok():
		return
	_shrinking = true
	_shrink0 = _host.scale
	_shrink_t = 0.0
	_descent = is_descent
	_drift_off = true


# Blow-out: keep downward momentum, decelerate to a drift, DARKEN + SHRINK, and erupt a cascade of
# blasts from WEIGHTED hull markers (engines favoured) — each leaving a spark trail — then slip off.
func _run_blowout() -> void:
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
	# Shrink (wreck = partial toward shrink_to; descent = all the way to ~1px), ease-out (blow-out model).
	if _shrinking:
		_shrink_t += delta
		var f: float = clampf(_shrink_t / _c("shrink_time", DESCENT_SHRINK_TIME), 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - f, 2.0)
		var target: float = DESCENT_MIN_SCALE if _descent else _c("shrink_to", 0.6)
		_host.scale = _shrink0.lerp(_shrink0 * target, e)
		if _descent and f >= 1.0:   # descent reached ~1px
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
			ExplosionFx.play_config(_host.to_global(mk), HULL_RIPPLE_CFG, _vfx_parent)
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
				_trails.append(sp)
			var torch: ColorRect = _make_smoulder_torch(p)
			_host.add_child(torch)
			_trails.append(torch)
			_fire_parts.append(torch)
	_has_smoke = not large


# Wreck / descent transition: taper off the fire (BURNING_TRAIL emitter stops / torch fades) and make
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
	_vfx_parent.add_child(smoke)
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
	rect.z_index = 1
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
	}, _vfx_parent)
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
	}, _vfx_parent)
	_spawn_embers(world, inherit)


# Scatter ShipDebrisEmber chunks (size-derived count). Every chunk inherits `base_vel` (the enemy's
# velocity going into the kill) plus a little extra outward energy.
func _spawn_embers(world: Vector2, base_vel: Vector2) -> void:
	var n: int = clampi(int(round((2.0 + _size_scale * 4.0) * _c("debris", 1.0))), 0, 24)
	for i in n:
		var ang: float = randf_range(0.0, TAU)
		var spd: float = randf_range(30.0, 90.0)   # extra energy on top of the matched enemy velocity
		ShipDebrisEmber.spawn(_vfx_parent, world, {
			"velocity": base_vel + Vector2(cos(ang), sin(ang)) * spd,
			"spin": randf_range(-6.0, 6.0),
			"piece_scale": randf_range(0.8, 1.4),
		})


# A single "ball" boom over a world point (spinout's engine pop).
func _ball_explode(world: Vector2) -> void:
	ExplosionFx.play_config(world, {
		"type": "ball", "size": 1.0,
		"density": 1, "area": 0.0, "glow": 1.0, "shockwave": 0.0, "sparks": 1.0,
	}, _vfx_parent)


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


# Descent resolution: haze the body toward the level's mid-parallax grade (recede into the backdrop),
# using the shared MidDepthPresentation depth-tint. Grade-matches the live backdrop if one is present.
func _apply_recede_tint() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	MidDepth.recede_body(_body, _find_backdrop(), MidDepth.WRECK_TINT, MidDepth.WRECK_AMOUNT)


# The combat scene's BackdropCoordinator ("Backdrop") to grade-match against, or null (lab / bare).
func _find_backdrop() -> Node:
	var cs: Node = get_tree().current_scene if get_tree() != null else null
	if cs != null:
		return cs.get_node_or_null("Backdrop")
	return null


# Spin-out launch: keep the heading the ship died with (never reverse), and veer toward whichever
# PERPENDICULAR screen edge is nearer.
func _start_corkscrew() -> void:
	if not _host_ok():
		return
	_spin = _c("spinout_spin", 0.5) * (1.0 if randf() < 0.5 else -1.0)
	_cork_travel = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	_cork_speed = _c("spinout_speed", 40.0)   # fixed tumble speed (spinout); wreck/descent use momentum
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


func _host_ok() -> bool:
	return _host != null and is_instance_valid(_host)


func _resolve_resolution() -> String:
	var r := String(_cfg.get("resolution", "random"))
	if r == "random" or not RESOLUTIONS.has(r):
		return _pick_gated_resolution()
	return r


# A random resolution valid for this hull's SIZE: instakill/wreck/descent for anyone, flashout only for
# small/tiny (< 1.5), blow_out only for medium+ (>= 1.5).
func _pick_gated_resolution() -> String:
	var opts := ["instakill", "wreck", "descent"]
	if _size_scale < 1.5:
		opts.append("flashout")
	else:
		opts.append("blow_out")
	return opts[randi() % opts.size()]


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
		# with the host instead of surviving.
		if _vfx_parent != null and is_instance_valid(_vfx_parent) and bt is Node2D:
			var n2d: Node2D = bt
			var gp: Vector2 = n2d.global_position
			var cur: Node = bt.get_parent()
			if cur != null and cur != _vfx_parent:
				cur.remove_child(bt)
				_vfx_parent.add_child(bt)
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
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null
	finished.emit()
	queue_free()
