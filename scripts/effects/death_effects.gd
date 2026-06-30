extends Node2D

# DeathEffects (Roman 2026-06-29) — graphical enemy-death STYLES. One controller per dying ship: it
# takes over the host hull, plays the chosen style (composing the existing VFX primitives — the
# damage-tell BURNING_TRAIL fire streak, the centralized ExplosionFx blast, ShipDebrisEmber burning
# chunks, the pixelated-burn disintegrate, and a spin-out) and then frees BOTH the host and itself
# when the sequence finishes.
#
# Built for the Shader Lab "Death" tab (the tuner); designed to drop onto enemy_base.explode() later
# so production deaths can pick a style. Usage:
#
#   var fx := DeathEffects.new()
#   vfx_parent.add_child(fx)            # a node that OUTLIVES the enemy (combat scene root / lab stage)
#   fx.play(enemy, "burn_out", cfg, Vector2.DOWN * speed,
#       {"vfx_parent": vfx_parent, "wreck_parent": wreck_layer, "bounds": play_rect})
#
# Each style declares its OWN tunable knob schema in STYLE_KNOBS (the single source of truth — the lab
# builds per-style sliders from it AND seeds the defaults from it). play()'s cfg overrides those.
#
# The six styles:
#   burn_out  — keep gliding straight, a couple frames' delay, ignite the fire trail, then disintegrate
#               while trailing fire (the ship burns up).
#   firework  — glide + delay as burn_out, but EXPLODE with debris/embers/sparks instead of dissolving.
#   spinout   — ball-blast over an engine, ignite the trail, then SPIN OUT: keep the heading it died with
#               and veer toward the nearer screen edge while tumbling off (never reverses).
#   flashout  — the default look: circle blasts + a brief disintegrate.
#   instakill — just explode with debris/sparks/embers, gone immediately.
#   blow_out  — keep downward momentum, slump + DARKEN + SHRINK while a cascade of blasts ERUPTS from
#               weighted hull markers (engines favoured), each leaving a spark trail, then slips off.

signal finished

const STYLES := ["burn_out", "firework", "spinout", "flashout", "instakill", "blow_out"]

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const BurnFx = preload("res://scripts/effects/burn_fx.gd")
const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const BURNING_TRAIL := preload("res://scenes/effects/burning_trail.tscn")

# Blow-out blast origins: the damage-tell hardpoint marker set, engines/thrusters weighted higher
# (the typical damage-tell failure points). Centre is always added as a fallback.
const BLAST_MARKER_GROUPS := [
	{"globs": ["Engine*", "Thruster*"], "w": 2.0},
	{"globs": ["*Muzzle*", "Cannon*", "cannon_*", "Gun*", "weapon_*", "Launcher*", "Missile*", "LaunchPoint*", "launch_point*", "missile_port*", "Turret*", "turret_*"], "w": 1.0},
]

# Per-style tunable knob schema {key, label, min, max, step, def}. Source of truth for both the
# module defaults (default_cfg) and the Shader Lab "Death" sliders.
const STYLE_KNOBS := {
	"burn_out": [
		{"key": "travel_speed", "label": "Glide speed (px/s)", "min": 0.0, "max": 200.0, "step": 5.0, "def": 70.0},
		{"key": "disintegrate_delay", "label": "Disintegrate delay (s)", "min": 0.0, "max": 0.5, "step": 0.01, "def": 0.06},
		{"key": "burn_time", "label": "Disintegrate time (s)", "min": 0.2, "max": 2.0, "step": 0.05, "def": 0.55},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	# explosion_density / sparks / debris are MULTIPLIERS on a size-derived base (a bigger hull auto-gets
	# a denser death via MORE booms). The booms themselves are ALWAYS 1× scale (the never-stretch
	# convention) — bigger hull = more blasts, not bigger sprites.
	"firework": [
		{"key": "travel_speed", "label": "Glide speed (px/s)", "min": 0.0, "max": 200.0, "step": 5.0, "def": 70.0},
		{"key": "disintegrate_delay", "label": "Blast delay (s)", "min": 0.0, "max": 0.5, "step": 0.01, "def": 0.06},
		{"key": "explosion_density", "label": "Explosion density ×", "min": 0.5, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "explosion_shockwave", "label": "Shockwave × (off=0)", "min": 0.0, "max": 3.0, "step": 0.1, "def": 0.0},
		{"key": "sparks", "label": "Spark density ×", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "debris", "label": "Ember density ×", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
	],
	# Spin-out continues the heading it died with + drifts toward the nearer perpendicular edge
	# (spinout_veer = that drift as a fraction of speed; 0 = straight, 1 = ~45° veer).
	"spinout": [
		{"key": "spinout_speed", "label": "Spinout speed (px/s)", "min": 40.0, "max": 320.0, "step": 5.0, "def": 40.0},
		{"key": "spinout_veer", "label": "Edge veer (0-1)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.4},
		{"key": "spinout_spin", "label": "Spinout spin (rad/s)", "min": 0.0, "max": 20.0, "step": 0.5, "def": 0.5},
		{"key": "spinout_swirl", "label": "Spinout swirl freq", "min": 0.0, "max": 20.0, "step": 0.5, "def": 6.0},
		{"key": "spinout_amp", "label": "Spinout amplitude (px/s)", "min": 0.0, "max": 120.0, "step": 5.0, "def": 5.0},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	"flashout": [
		{"key": "explosion_density", "label": "Explosion density ×", "min": 0.5, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "burn_time", "label": "Disintegrate time (s)", "min": 0.2, "max": 2.0, "step": 0.05, "def": 0.45},
		{"key": "glow_flicker_time", "label": "Glow flicker (s)", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.3},
	],
	"instakill": [
		{"key": "explosion_density", "label": "Explosion density ×", "min": 0.5, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "explosion_shockwave", "label": "Shockwave × (off=0)", "min": 0.0, "max": 3.0, "step": 0.1, "def": 0.0},
		{"key": "sparks", "label": "Spark density ×", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "debris", "label": "Ember density ×", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
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
}


# The default cfg for a style — built from its knob schema (the single source of truth).
static func default_cfg(style: String) -> Dictionary:
	var d := {}
	for def in STYLE_KNOBS.get(style, []):
		d[String(def["key"])] = float(def["def"])
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
var _trails: Array = []           # active fire / spark trails (detached + lingered on finish)
var _start_scale: Vector2 = Vector2.ONE
var _blast_times: Array = []      # blow-out blast schedule
var _blast_markers_cache: Array = []   # weighted hull markers for the blow-out cascade
var _blast_sparked: Dictionary = {}    # marker positions already wearing a spark trail (dedup)
var _style_t: float = 0.0         # elapsed time for the per-frame styles (blow_out)
var _done: bool = false


# Begin a death. `host` = the dying hull (a body Sprite2D + optional Engine* markers); `travel` = the
# glide / inherited velocity (direction × speed). opts: vfx_parent (blast container that outlives the
# host), wreck_parent (where the spin-out sinks the hull), bounds (play rect for the edge veer + exit).
func play(host: Node2D, style: String, cfg: Dictionary = {}, travel: Vector2 = Vector2.ZERO, opts: Dictionary = {}) -> void:
	_host = host
	if _host == null or not is_instance_valid(_host):
		_finish()
		return
	_body = _find_body(_host)
	_size_scale = _measure_scale(_host, _body)
	_cfg = default_cfg(style)
	_cfg.merge(cfg, true)
	_travel = travel
	_vfx_parent = opts.get("vfx_parent", null)
	if _vfx_parent == null or not is_instance_valid(_vfx_parent):
		_vfx_parent = _host.get_parent()
	_wreck_parent = opts.get("wreck_parent", _vfx_parent)
	if _wreck_parent == null or not is_instance_valid(_wreck_parent):
		_wreck_parent = _vfx_parent
	_bounds = opts.get("bounds", _bounds)
	match style:
		"burn_out":
			_run_burn_out()
		"firework":
			_run_firework()
		"spinout":
			_run_spinout()
		"flashout":
			_run_flashout()
		"instakill":
			_run_instakill()
		"blow_out":
			_run_blowout()
		_:
			_run_flashout()


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
			_cork_t += delta
			# Keep the heading + a steady veer toward the nearer edge + a sine wobble — the spin-out.
			var perp := Vector2(-_cork_travel.y, _cork_travel.x)
			var spd: float = _c("spinout_speed", 40.0)
			var wob: Vector2 = perp * sin(_cork_t * _c("spinout_swirl", 6.0)) * _c("spinout_amp", 5.0)
			var veer: Vector2 = _cork_lateral * (spd * _c("spinout_veer", 0.4))
			_host.global_position += (_cork_travel * spd + veer + wob) * delta
			_host.rotation += _spin * delta
		"blowout":
			if not _host_ok():
				_finish()
				return
			_tick_blowout(delta)
		_:
			pass


# ── Styles ───────────────────────────────────────────────────────────────────────────────────────

func _run_burn_out() -> void:
	_phase = "glide"
	_ignite_fire_trail()
	await _wait(_c("disintegrate_delay", 0.06))
	if not _valid():
		return
	_disintegrate()
	await _wait(_c("burn_time", 0.55) + 0.3)   # let the burn finish, the trail linger
	_finish()


func _run_firework() -> void:
	_phase = "glide"
	_ignite_fire_trail()
	await _wait(_c("disintegrate_delay", 0.06))
	if not _valid():
		return
	_explode(true)
	_finish()


func _run_spinout() -> void:
	_phase = "glide"
	var engines: Array = _engine_local()
	var first: Vector2 = (engines[0] if not engines.is_empty() else Vector2.ZERO)
	_ball_explode(_host.to_global(first))
	await _wait(0.1)
	if not _valid():
		return
	_ignite_fire_trail()
	_to_wreck_layer()
	_fade_host_overlays()   # flicker the glow out + fade the livery as it spins out
	_start_corkscrew()
	await _wait(2.4)
	_finish()


func _run_flashout() -> void:
	_phase = "idle"
	_explode(false)
	_disintegrate()
	await _wait(_c("burn_time", 0.45) + 0.2)
	_finish()


func _run_instakill() -> void:
	_phase = "idle"
	_explode(true)
	_finish()


# Blow-out: keep downward momentum, decelerate to a drift, DARKEN + SHRINK, and erupt a cascade of
# blasts from WEIGHTED hull markers (engines favoured) — each leaving a spark trail — then slip off.
func _run_blowout() -> void:
	_fade_host_overlays()   # glow flickers out + livery fades + engines cut as it slumps
	_start_scale = _host.scale
	_travel = Vector2(0.0, _c("enter_speed", 40.0) * 1.6)   # keep 1.6× downward momentum
	_blast_times.clear()
	var n: int = maxi(1, int(_c("blast_count", 10.0)))
	var win: float = _c("blast_window", 0.9)
	for i in n:
		_blast_times.append((float(i) / float(n)) * win)
	_blast_markers_cache = _blast_markers()
	_style_t = 0.0
	_phase = "blowout"


func _tick_blowout(delta: float) -> void:
	_style_t += delta
	# Momentum slump.
	_travel.y = maxf(_c("min_drift", 70.0), _travel.y - _c("decel", 14.0) * delta)
	_travel.x *= 0.96
	_host.global_position += _travel * delta
	# Darken the whole hull.
	var dk: float = clampf(_style_t / maxf(0.01, _c("darken_dur", 1.8)), 0.0, 1.0)
	var b: float = lerpf(1.0, _c("darken_to", 0.5), dk)
	_host.modulate = Color(b, b, b, _host.modulate.a)
	# Shrink (ease-out).
	var sh: float = clampf(_style_t / maxf(0.01, _c("shrink_dur", 3.5)), 0.0, 1.0)
	var sh_e: float = 1.0 - pow(1.0 - sh, 2.0)
	_host.scale = _start_scale.lerp(_start_scale * _c("shrink_to", 0.7), sh_e)
	# Blast cascade ERUPTING from weighted hull markers (1× sprites); each point starts a spark trail.
	for i in _blast_times.size():
		var bt: float = float(_blast_times[i])
		if bt >= 0.0 and _style_t >= bt:
			_blast_times[i] = -1.0
			var mk: Vector2 = _pick_blast_marker(_blast_markers_cache)
			ExplosionFx.play(_host.to_global(mk), 1.0, true, _vfx_parent)
			_spark_at_marker(mk)
	# Exit off the bottom or past the max duration.
	if _style_t >= _c("max_dur", 6.0) or _host.global_position.y > _bounds.position.y + _bounds.size.y + 60.0:
		_finish()


# ── Composed primitives ────────────────────────────────────────────────────────────────────────

# Ignite the damage-tell BURNING_TRAIL at every engine marker (hull centre if none), parented to the
# host so they ride along; local_coords=false makes the sparks stream off into world space as the
# hull moves — the burning-up streak.
func _ignite_fire_trail() -> void:
	if not _host_ok():
		return
	var spots: Array = _engine_local()
	if spots.is_empty():
		spots = [Vector2.ZERO]
	for p in spots:
		var bt: Node2D = BURNING_TRAIL.instantiate()
		bt.position = p
		_host.add_child(bt)
		var parts: GPUParticles2D = SparkTrailFx.particles(bt)
		if parts != null:
			parts.local_coords = false
			parts.emitting = true
		_trails.append(bt)


func _disintegrate() -> void:
	# Fade the livery / glow / outline OVERLAY layers (and stop the engine trail) so the WHOLE ship
	# dissolves with the body — not just the hull sprite under an intact livery decal.
	_fade_host_overlays()
	if _body != null and is_instance_valid(_body):
		BurnFx.apply_burn(_body, _c("burn_time", 0.55), Color(0, 0, 0, 0), _burn_origin_uv())


# Tear down the host's presentation as it dies: stop the engine trail, fade the livery/outline via
# enemy_base's proven fade (skip_glow=true — we own the glow), and FLICKER the glow layers out over
# the tunable glow_flicker_time. No-op for a host without those (e.g. the headless test).
func _fade_host_overlays() -> void:
	if not _host_ok():
		return
	if _host.has_method("set_engine_trail_emitting"):
		_host.set_engine_trail_emitting(false)
	if _host.has_method("_fade_death_overlays"):
		_host._fade_death_overlays(true)   # skip glow — flickered out below
	_flicker_glow_out(_c("glow_flicker_time", 0.3))


# Flicker every glow overlay on the host out: a few quick dim/bright stutters across `time`, then a
# short fade to nothing — a dying-ship power-flicker (mirrors enemy_base's wreck-disable glow flicker).
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


# A glow overlay sprite (name reads "glow" anywhere, or the Shepherd's "EngineLayer") — mirrors
# enemy_base._is_glow_overlay so the same layers flicker that the engine HDR-blooms.
func _is_glow(n: Node) -> bool:
	if not (n is Sprite2D):
		return false
	var nm := String(n.name)
	return nm.to_lower().contains("glow") or nm == "EngineLayer"


# A full blast at the host position, into the vfx container (so it outlives the freed hull). With
# embers, scatter ShipDebrisEmber burning chunks too.
func _explode(with_embers: bool) -> void:
	if not _host_ok():
		return
	var world: Vector2 = _host.global_position
	# Boom SPRITES are always 1× (the never-stretch convention); a bigger hull throws MORE booms +
	# more embers (size-derived density/area), not bigger sprites.
	ExplosionFx.play_config(world, {
		"type": String(_cfg.get("explosion_type", "basic")),
		"size": 1.0,   # 1× scale — size variety comes from density, not stretched sprites
		"density": maxi(1, int(round((1.0 + _size_scale * 0.6) * _c("explosion_density", 1.0)))),
		"area": 6.0 + _size_scale * 5.0,
		"sparks": _c("sparks", 1.0),
		"glow": 1.2,
		"shockwave": _c("explosion_shockwave", 0.0) * clampf(_size_scale, 0.6, 2.5),
	}, _vfx_parent)
	if with_embers:
		_spawn_embers(world)


func _spawn_embers(world: Vector2) -> void:
	# Size-derived chunk count × the ember multiplier (chaff ~6, a big hull ~16, like enemy_base).
	var n: int = clampi(int(round((2.0 + _size_scale * 4.0) * _c("debris", 1.0))), 0, 24)
	for i in n:
		var ang: float = randf_range(0.15, PI - 0.15)
		var spd: float = randf_range(50.0, 130.0)
		ShipDebrisEmber.spawn(_vfx_parent, world, {
			"velocity": Vector2(cos(ang), sin(ang)) * spd,
			"spin": randf_range(-6.0, 6.0),
			"piece_scale": randf_range(0.8, 1.4),
		})


# A single "ball" boom over a world point (spinout's engine pop).
func _ball_explode(world: Vector2) -> void:
	ExplosionFx.play_config(world, {
		"type": "ball", "size": 1.0,   # 1× scale (never-stretch convention)
		"density": 1, "area": 0.0, "glow": 1.0, "shockwave": 0.0, "sparks": 1.0,
	}, _vfx_parent)


# Sink the hull into the wreck layer (reparent, world transform preserved) and dim it so it reads as
# falling into the background. No-op reparent if it's already in the wreck container (the lab passes
# its own stage as both).
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
# PERPENDICULAR screen edge is nearer (so it tumbles out toward that side as it continues forward).
func _start_corkscrew() -> void:
	if not _host_ok():
		return
	_spin = _c("spinout_spin", 0.5) * (1.0 if randf() < 0.5 else -1.0)
	_cork_travel = _travel.normalized() if _travel.length() > 0.1 else Vector2.DOWN
	var perp := Vector2(-_cork_travel.y, _cork_travel.x)
	var d_plus: float = _dist_to_bounds(_host.global_position, perp)
	var d_minus: float = _dist_to_bounds(_host.global_position, -perp)
	if absf(d_plus - d_minus) < 1.0:
		_cork_lateral = perp * (signf(_spin) if _spin != 0.0 else 1.0)   # tie → veer with the spin
	else:
		_cork_lateral = perp if d_plus < d_minus else -perp
	_cork_t = 0.0
	_phase = "cork"


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

# Read a float cfg knob with a fallback (so a style is robust if a key is omitted).
func _c(key: String, fallback: float) -> float:
	return float(_cfg.get(key, fallback))


func _host_ok() -> bool:
	return _host != null and is_instance_valid(_host)


# Engine-marker positions in HOST-local space (for trail placement).
func _engine_local() -> Array:
	var out: Array = []
	if not _host_ok():
		return out
	for m in _host.find_children("Engine*", "Marker2D", true, false):
		if m is Node2D:
			out.append(_host.to_local((m as Node2D).global_position))
	return out


# Engine-marker positions in WORLD space.
func _engine_world() -> Array:
	var out: Array = []
	if not _host_ok():
		return out
	for m in _host.find_children("Engine*", "Marker2D", true, false):
		if m is Node2D:
			out.append((m as Node2D).global_position)
	return out


# The blow-out's weighted hull markers (engines/thrusters favoured) in HOST-local space, + centre.
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
	out.append({"pos": Vector2.ZERO, "weight": 1.0})   # hull centre — always available
	return out


# Weighted-random pick of a blast marker (engines favoured).
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


# Leave a lingering spark trail at a blow-out blast point (host-local), so the damaged spot smokes +
# trails as the ship slumps. Deduped per point so repeat blasts on one marker don't stack emitters.
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


# Pick an engine marker and return its UV on the body sprite so the burn dissolves from a thruster
# (falls back to centre when the ship has no engine markers).
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


# Ship size_scale = body sprite pixel size / 16 (mirrors enemy_base / the Shader Lab). Drives blast
# density + debris counts.
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


# Detach any live fire / spark trails so their streak lingers + fades instead of snapping off with the
# hull.
func _release_trails() -> void:
	for bt in _trails:
		if bt == null or not is_instance_valid(bt):
			continue
		var parts: GPUParticles2D = SparkTrailFx.particles(bt)
		if parts != null:
			parts.emitting = false
		if _vfx_parent != null and is_instance_valid(_vfx_parent):
			var gp: Vector2 = (bt as Node2D).global_position
			var cur: Node = bt.get_parent()
			if cur != null and cur != _vfx_parent:
				cur.remove_child(bt)
				_vfx_parent.add_child(bt)
				(bt as Node2D).global_position = gp
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
