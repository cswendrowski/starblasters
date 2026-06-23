extends Node2D

# BeamEmitter (M6a.2 step 4) — the ONE reusable beam: FSM + layered Line2D visuals +
# width-aware DPS damage + aim modes. Consolidates the ~250-300 lines of beam logic
# copy-pasted across enemy_beam_shooter / enemy_burner / enemy_beam_turret (the
# 4-layer stack, _dist_point_to_segment, the DPS drip, the windup->fire FSM, the
# telegraph pulse). Those three become thin CONFIGS of this node.
#
# Add as a child of any host; configure(); begin(). It self-ticks (own _process), so
# no weapon-tick hook is needed in enemy_core — per-enemy state lives on this node
# (the resource convention forbids per-instance state on a shared Resource).
#
# Referenced via preload, not a class_name (a new class_name isn't registered in
# headless --script until the cache regenerates; preload is the codebase convention).
#
# Identity is by GROUP (the project keys hits off "player"/"enemies" groups, not
# physics layers), so damage is a centralized width-aware geometric query against
# target_group — the canonical form of the shapecast given group-based identity.
# Fairness contract (genre): windup (thin warning) -> fire (thick lethal), reserved
# danger color, no damage until FIRING.

enum Phase { OFF, IDLE, WINDUP, FIRING, COOLDOWN }
# How the FSM repeats. MANUAL = no auto-advance; the host drives the phase via
# show_telegraph()/show_fire()/cease() (for hosts with their own state machine, e.g.
# the Burner's pairing/settle logic). The emitter still owns visuals + damage.
enum Cycle { LOOP_IDLE, LOOP_WINDUP, ONCE, HOLD, MANUAL }
enum Endpoint { RAY, SEGMENT }                       # beam geometry
# LOCAL_FORWARD = fire along the host's forward (host rotation aims it).
# LOCKED        = snapshot a world dir at windup, hold it (no re-aim).
# TRACKING      = continuously re-aim toward the target group ("track player") at tracking_rate.
# TRACK_LOCK    = track between shots, but FREEZE the aim while committed (windup+firing) — an
#                 evade window for the player (the old Beamer "LOCK" hull behavior, generalized).
# SWEEP         = rake the beam at a constant sweep_rate (host stays put).
enum AimMode { LOCAL_FORWARD, LOCKED, TRACKING, SWEEP, TRACK_LOCK }

# --- lifecycle ---
var idle_time: float = 0.9
var windup_time: float = 1.3
var firing_time: float = 1.1
var cooldown_time: float = 1.5
var cycle: int = Cycle.LOOP_IDLE
var autostart: bool = true

# --- geometry ---
var endpoint: int = Endpoint.RAY
var reach: float = 320.0
var emitter_offset: Vector2 = Vector2(0, -8)   # local origin for RAY

# --- aim (RAY) ---
var aim_mode: int = AimMode.LOCAL_FORWARD
var forward_local: Vector2 = Vector2(0, -1)    # local fire dir for LOCAL_FORWARD
var tracking_rate: float = 1.8                 # rad/s (TRACKING)
var sweep_rate: float = 0.0                    # rad/s (SWEEP)

# --- damage ---
var dps: float = 3.0
var hit_radius: float = 8.0                    # damage band half-width (gameplay)
var target_group: String = "player"
var pierce: bool = true                        # false = stop visual+damage at first hit

# --- visuals: layer table [{width, color}], widest first; empty = default stack ---
var layers: Array = []
var telegraph_color: Color = Color(1.0, 0.95, 0.35, 0.5)
var telegraph_width: float = 1.5

# --- state ---
var _phase: int = Phase.OFF
var _t: float = 0.0
var _beam_t: float = 0.0
var _dmg_accum: float = 0.0
var _aim_dir: Vector2 = Vector2(0, 1)          # world fire dir (RAY)
var _seg_a: Vector2 = Vector2.ZERO             # SEGMENT world endpoints
var _seg_b: Vector2 = Vector2.ZERO
var _lines: Array = []                         # lethal Line2D layers
var _telegraph: Line2D = null

signal phase_changed(phase: int)


func _ready() -> void:
	position = emitter_offset
	if autostart:
		begin()


func configure(cfg: Dictionary) -> void:
	for k in cfg.keys():
		if k in self:
			set(k, cfg[k])
	position = emitter_offset


func begin() -> void:
	match cycle:
		Cycle.HOLD:
			_set_phase(Phase.WINDUP)
		Cycle.MANUAL:
			_set_phase(Phase.IDLE)   # hidden until the host drives it
		_:
			_set_phase(Phase.IDLE)


func stop() -> void:
	_hide_all()
	_set_phase(Phase.OFF)


func is_firing() -> bool:
	return _phase == Phase.FIRING


# Charge fraction for an external charge-layer animation (e.g. the Spear's ChargeMask): 0.0 =
# uncharged (start of WINDUP / end of COOLDOWN), 1.0 = fully charged (FIRING). WINDUP ramps 0->1,
# FIRING holds 1, COOLDOWN ramps 1->0. Returns -1.0 when idle/off so the caller hides the layer.
func charge_fraction() -> float:
	match _phase:
		Phase.WINDUP:
			return clampf(_t / maxf(0.0001, windup_time), 0.0, 1.0)
		Phase.FIRING:
			return 1.0
		Phase.COOLDOWN:
			return clampf(1.0 - _t / maxf(0.0001, cooldown_time), 0.0, 1.0)
		_:
			return -1.0


# True while the beam is committed to its shot (telegraph + lethal). Hull-aimed beams
# (the Beamer LOCK behavior) hold their rotation during this window, then re-aim.
func is_committed() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.FIRING


# --- MANUAL drive (host owns timing) ---
func show_telegraph() -> void:
	if _phase != Phase.WINDUP:
		_set_phase(Phase.WINDUP)

func show_fire() -> void:
	if _phase != Phase.FIRING:
		_set_phase(Phase.FIRING)

func cease() -> void:
	_hide_all()
	if _phase != Phase.IDLE:
		_set_phase(Phase.IDLE)


# SEGMENT mode: the host sets the two world endpoints each frame (e.g. the Burner's
# ship-to-ship link). RAY mode ignores this.
func set_segment(a_world: Vector2, b_world: Vector2) -> void:
	_seg_a = a_world
	_seg_b = b_world


# LOCKED aim: snapshot a world fire direction (e.g. the Turret locking at windup).
func set_locked_aim(world_dir: Vector2) -> void:
	if world_dir.length_squared() > 0.0001:
		_aim_dir = world_dir.normalized()


func _set_phase(p: int) -> void:
	_phase = p
	_t = 0.0
	phase_changed.emit(p)


func _process(delta: float) -> void:
	if _phase == Phase.OFF:
		return
	# Host-state guard (review P0): suppress the beam entirely while the host enemy is
	# dying (explode() runs a ~0.5s death anim during which a still-firing beam would
	# land lethal hits) or parallax-cycling (the host is hidden but the geometry-based
	# damage would otherwise deal INVISIBLE damage). The emitter is a child of the host,
	# so get_parent() is it. Freezes the FSM (no _t advance) → clean pause + auto-resume
	# when cycling ends. Covers Beamer/Burner + enemy_core beam-weapon hosts uniformly.
	var host := get_parent()
	if host != null and (("_dying" in host and host._dying) or ("_cycling" in host and host._cycling)):
		_hide_all()
		return
	_t += delta
	_beam_t += delta
	_update_aim(delta)
	# MANUAL: render + damage for the host-set phase, but never auto-advance.
	if cycle == Cycle.MANUAL:
		match _phase:
			Phase.WINDUP:
				_show_telegraph_only()
			Phase.FIRING:
				_show_lethal()
				_apply_damage(delta)
			_:
				_hide_all()
		return
	match _phase:
		Phase.IDLE:
			_hide_all()
			if _t >= idle_time:
				_enter_windup()
		Phase.WINDUP:
			_show_telegraph_only()
			if _t >= windup_time:
				_set_phase(Phase.FIRING)
		Phase.FIRING:
			_show_lethal()
			_apply_damage(delta)
			if cycle != Cycle.HOLD and _t >= firing_time:
				_enter_after_firing()
		Phase.COOLDOWN:
			_hide_all()
			if _t >= cooldown_time:
				match cycle:
					Cycle.ONCE:
						stop()
					Cycle.LOOP_WINDUP:
						_enter_windup()   # re-arm without the idle pause
					_:
						_set_phase(Phase.IDLE)   # LOOP_IDLE


func _enter_windup() -> void:
	# Snapshot/seed the aim for LOCKED + TRACKING at the start of the warning.
	if aim_mode == AimMode.LOCKED or aim_mode == AimMode.TRACKING:
		var to_t := _aim_target_dir()
		if to_t != Vector2.ZERO:
			_aim_dir = to_t
	_set_phase(Phase.WINDUP)


func _enter_after_firing() -> void:
	# Cooldown ALWAYS follows firing; the cycle decides what comes after cooldown
	# (loop to idle, loop straight to windup, or stop). See the COOLDOWN case.
	_dmg_accum = 0.0
	_set_phase(Phase.COOLDOWN)


# ---------------------------------------------------------------- aim

func _update_aim(delta: float) -> void:
	if endpoint == Endpoint.SEGMENT:
		return
	match aim_mode:
		AimMode.LOCAL_FORWARD:
			_aim_dir = forward_local.rotated(global_rotation)
		AimMode.TRACKING:
			var want := _aim_target_dir()
			if want != Vector2.ZERO:
				var diff: float = _aim_dir.angle_to(want)
				_aim_dir = _aim_dir.rotated(clampf(diff, -tracking_rate * delta, tracking_rate * delta))
		AimMode.SWEEP:
			_aim_dir = _aim_dir.rotated(sweep_rate * delta)
		AimMode.TRACK_LOCK:
			# Track the target between shots; hold the aim once committed (the evade window).
			if not is_committed():
				var w2 := _aim_target_dir()
				if w2 != Vector2.ZERO:
					var d2: float = _aim_dir.angle_to(w2)
					_aim_dir = _aim_dir.rotated(clampf(d2, -tracking_rate * delta, tracking_rate * delta))
		AimMode.LOCKED:
			pass   # held from windup / set_locked_aim
	if _aim_dir.length_squared() < 0.0001:
		_aim_dir = Vector2(0, 1)


func _aim_target_dir() -> Vector2:
	var tree := get_tree()
	if tree == null:
		return Vector2.ZERO
	var t := tree.get_first_node_in_group(target_group)
	if t == null or not (t is Node2D):
		return Vector2.ZERO
	var d: Vector2 = (t as Node2D).global_position - global_position
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.ZERO


# World [start, end] of the beam this frame, end truncated to the nearest hit when
# pierce is off.
func _world_segment() -> Array:
	if endpoint == Endpoint.SEGMENT:
		return [_seg_a, _seg_b]
	var a: Vector2 = global_position
	var b: Vector2 = a + _aim_dir * reach
	if not pierce:
		var trunc := _nearest_hit_distance(a, b)
		if trunc >= 0.0:
			b = a + _aim_dir * trunc
	return [a, b]


# ---------------------------------------------------------------- damage

func _apply_damage(delta: float) -> void:
	_dmg_accum += dps * delta
	if _dmg_accum < 1.0:
		return
	var dmg: int = int(_dmg_accum)
	_dmg_accum -= float(dmg)
	var seg: Array = _world_segment()
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var tree := get_tree()
	if tree == null:
		return
	for t in tree.get_nodes_in_group(target_group):
		if not is_instance_valid(t) or not (t is Node2D):
			continue
		if _dist_point_to_segment((t as Node2D).global_position, a, b) <= hit_radius:
			_damage_target(t, dmg)
			if not pierce:
				break


func _damage_target(t: Object, dmg: int) -> void:
	if t.has_method("take_damage"):
		t.take_damage(dmg)
	elif t.has_method("take_hit"):
		t.take_hit(dmg)


# Distance along the beam to the nearest target_group member within hit_radius, or
# -1 if none (used to truncate when pierce is off).
func _nearest_hit_distance(a: Vector2, b: Vector2) -> float:
	var tree := get_tree()
	if tree == null:
		return -1.0
	var ab: Vector2 = b - a
	var len_ab: float = ab.length()
	if len_ab < 0.001:
		return -1.0
	var dir: Vector2 = ab / len_ab
	var best: float = -1.0
	for t in tree.get_nodes_in_group(target_group):
		if not is_instance_valid(t) or not (t is Node2D):
			continue
		var p: Vector2 = (t as Node2D).global_position
		if _dist_point_to_segment(p, a, b) <= hit_radius:
			var along: float = clampf((p - a).dot(dir), 0.0, len_ab)
			if best < 0.0 or along < best:
				best = along
	return best


static func _dist_point_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return pt.distance_to(a)
	var t: float = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


# ---------------------------------------------------------------- visuals

func _default_layers() -> Array:
	return [
		{"width": 10.0, "color": Color(0.65, 0.15, 1.0, 0.55)},   # outer glow (danger purple)
		{"width": 6.0, "color": Color(1.0, 0.5, 0.1, 0.85)},      # mid (orange)
		{"width": 3.5, "color": Color(1.0, 0.95, 0.35, 1.0)},     # core (yellow)
	]


func _ensure_visuals() -> void:
	if not _lines.is_empty():
		return
	var tbl: Array = layers if not layers.is_empty() else _default_layers()
	for spec in tbl:
		_lines.append(_make_line(spec.get("color", Color.WHITE), spec.get("width", 4.0)))
	_telegraph = _make_line(telegraph_color, telegraph_width)
	for l in _lines:
		add_child(l)
	add_child(_telegraph)


const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")

func _make_line(color: Color, w: float) -> Line2D:
	var l := Line2D.new()
	l.default_color = color
	l.modulate = VfxGlow.prod_hdr("lasers")   # HDR-bright so the WorldEnvironment blooms the beam
	l.width = w
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.z_index = 4
	l.visible = false
	return l


# Convert the world beam segment into this node's LOCAL space for the Line2D points,
# so all aim modes (and SEGMENT) draw uniformly regardless of host rotation.
func _line_points() -> PackedVector2Array:
	var seg: Array = _world_segment()
	return PackedVector2Array([to_local(seg[0]), to_local(seg[1])])


func _show_lethal() -> void:
	_ensure_visuals()
	var pts := _line_points()
	for l in _lines:
		l.visible = true
		l.points = pts
	if _telegraph:
		_telegraph.visible = false


func _show_telegraph_only() -> void:
	_ensure_visuals()
	for l in _lines:
		l.visible = false
	if _telegraph:
		_telegraph.visible = true
		_telegraph.points = _line_points()
		var c: Color = telegraph_color
		c.a = sin(_beam_t * TAU * 2.0) * 0.2 + 0.5   # pulse (genre warning tell)
		_telegraph.default_color = c


func _hide_all() -> void:
	for l in _lines:
		if is_instance_valid(l):
			l.visible = false
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.visible = false
