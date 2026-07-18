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
var settle_y: float = -1.0       # >=0: a beam MOUNT begins only once the host descends past this Y
var _settle_gated: bool = false  # internal: true once the settle-gate has fired begin()
# Stagger (Roman 2026-07-06): delay the first begin() by this many seconds. For ALTERNATING muzzles the
# builder gives each beam a different begin_delay (period/n × index) so they fire out of phase; BOTH-muzzle
# beams share begin_delay 0 (fire in sync). Only applies to autostart beams.
var begin_delay: float = 0.0
var _begin_delay_t: float = 0.0
var _begin_gate_done: bool = false

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
# Friendly fire (Roman 2026-07-01): when on, the beam ALSO damages the "enemies" group (in addition
# to target_group) — a lane hazard that blows up the player AND enemies alike. EXCEPT any node that
# is `ignore_owner` or its descendant, so a boss's own lane laser never kills its own turrets/lasers.
var friendly_fire: bool = false
var ignore_owner: Node = null

# Width ENVELOPE (Roman 2026-07-02): the lethal beam comes in as a thin (white-cored) line that rapidly
# grows to full width, holds, then shrinks back down + flickers out over the tail of FIRING. This is the
# canonical laser animation cycle (Roman 2026-07-07: "all lasers use the zealot-battleship baseline") —
# ON by default so warning-line → grow-to-size → flicker-out is uniform across every beam in the game.
var envelope: bool = true
var envelope_grow: float = 0.15    # rapid grow-in at fire onset
var envelope_shrink: float = 0.45  # shrink + flicker over the tail of firing
var _base_widths: Array = []       # authored layer widths (envelope scales these)
var _fading: bool = false          # graceful shrink+flicker OUT (fade_out) mid-firing instead of a hard cut
var _fade_t: float = 0.0

# --- visuals: layer table [{width, color}], widest first; empty = default stack ---
var layers: Array = []
var telegraph_color: Color = Color(1.0, 0.95, 0.35, 0.5)
var telegraph_width: float = 1.5
# Faction tint (Roman 2026-07-06): the beam takes the host faction's MUZZLE color (Supremacy/Zealot gold,
# Privateer/Corporate lime); the innermost (core) layer stays white-hot. Core faction / no faction (-1) =
# white throughout. AUTO (-2, default) = detect from the host's `faction_skin` meta (walking up the tree);
# -1..3 = explicit; FACTION_OFF (-3) = keep authored layer colors (a boss beam with a fixed bespoke look).
const FACTION_OFF := -3
var faction: int = -2

# --- audio (Roman 2026-07-15) ---
# Sound family for this beam: "enemy" (default — small start/stop blasts, power_up
# charge warning, field loops 1-3), "boss" (large blasts, power up/down flutters,
# field loops 4-5), "sapper" (force loop), "silent" (no beam audio).
# The charge warning plays at WINDUP start, so the sound ALWAYS precedes firing
# (the visual tell may run longer). The firing loop fades out with the envelope
# shrink as the beam finishes.
var sfx_profile: String = "enemy"

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
# Audio state: the firing loop node (child, reused across shots), its fade tween,
# and the hit-effect tint (faction laser-inner, or the authored mid-layer color for
# FACTION_OFF boss beams) captured in _ensure_visuals.
var _loop_player: AudioStreamPlayer2D = null
var _loop_tween: Tween = null
var _loop_fading: bool = false
var _audio_fire_on: bool = false
var _fx_color: Color = Color.WHITE

signal phase_changed(phase: int)


func _ready() -> void:
	position = emitter_offset
	if autostart and begin_delay <= 0.0:
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


# Graceful stop: if currently FIRING with an envelope, play the shrink+flicker OUT (like the natural end
# of firing) before hiding — so an early cut looks the same as a full cycle. Else stop immediately.
func fade_out() -> void:
	if _phase == Phase.FIRING and envelope and not _fading:
		_fading = true
		_fade_t = 0.0
		_begin_loop_fade()   # loop fades with the shrink; the stop blast lands at stop()
	else:
		stop()


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
	var prev: int = _phase
	_phase = p
	_t = 0.0
	_fading = false
	_fade_t = 0.0
	# Audio on the transitions (covers BOTH the FSM and the MANUAL show_*/cease drive):
	# WINDUP entry = charge warning; FIRING entry = start blast + loop; FIRING exit =
	# stop blast (+ boss spin-down). fade_out() keeps the phase FIRING while it shrinks,
	# so its final stop() lands here as the FIRING exit — the blast plays as the beam
	# visually disappears, same as a natural cycle end.
	if sfx_profile != "silent" and is_inside_tree():
		if p == Phase.WINDUP and prev != Phase.WINDUP:
			LaserSfxC.play_charge(get_tree().root, global_position, sfx_profile == "boss")
		if p == Phase.FIRING and prev != Phase.FIRING:
			_audio_start_fire(true)
		elif prev == Phase.FIRING and p != Phase.FIRING:
			_audio_end_fire(true)
	phase_changed.emit(p)


func _process(delta: float) -> void:
	# Settle-gate (beam mounts): hold fire until the host descends into the band, then allow begin.
	# Replaces the Beamer's bespoke begin-on-settle; pair with autostart:false + settle_y in the cfg.
	if settle_y >= 0.0 and not _settle_gated:
		var sh := get_parent()
		if sh != null and sh is Node2D and (sh as Node2D).global_position.y >= settle_y:
			_settle_gated = true
			if begin_delay <= 0.0:
				begin()
		else:
			return
	# Begin-delay stagger (alternating muzzles): once cleared to begin (autostart or settled), hold the
	# first begin() for begin_delay seconds so staggered beams fire out of phase.
	if begin_delay > 0.0 and not _begin_gate_done and _phase == Phase.OFF and (autostart or _settle_gated):
		_begin_delay_t += delta
		if _begin_delay_t >= begin_delay:
			_begin_gate_done = true
			begin()
		return
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
		# Cut the firing loop silently (no stop blast — the host's death/recycle audio
		# covers it). If the host resumes FIRING after a recycle, _show_lethal restarts
		# the loop without a fresh start blast.
		if _audio_fire_on:
			_audio_end_fire(false)
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
			if _fading:
				_fade_t += delta
				if _fade_t >= envelope_shrink:
					stop()
					return
			_show_lethal()
			if not _fading:
				_apply_damage(delta)   # a fading beam stops dealing damage as it shrinks out
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
	var first_hit := Vector2.INF
	for t in _damage_candidates():
		if not is_instance_valid(t) or not (t is Node2D) or _is_ignored(t):
			continue
		if _dist_point_to_segment((t as Node2D).global_position, a, b) <= hit_radius:
			_damage_target(t, dmg)
			# Hit effect at the strike point (the beam-line point nearest the target),
			# tinted with the beam's laser-inner color — same family as bullet impacts.
			var hp := _spawn_hit_fx(t as Node2D, a, b)
			if first_hit == Vector2.INF:
				first_hit = hp
			if not pierce:
				break
	# One hit SOUND per damage tick (a friendly-fire lane beam can strike many targets
	# at once — per-target audio would stack into a wall).
	if first_hit != Vector2.INF and sfx_profile != "silent" and is_inside_tree():
		LaserSfxC.play_hit(get_tree().root, first_hit)


func _damage_target(t: Object, dmg: int) -> void:
	if t.has_method("take_damage"):
		t.take_damage(dmg)
	elif t.has_method("take_hit"):
		t.take_hit(dmg)


# The nodes the beam can hit this frame: target_group, plus the "enemies" group when friendly_fire
# is on (the boss's lane laser is indifferent — it torches the player AND enemies).
func _damage_candidates() -> Array:
	var tree := get_tree()
	if tree == null:
		return []
	var out: Array = tree.get_nodes_in_group(target_group)
	if friendly_fire and target_group != "enemies":
		out = out + tree.get_nodes_in_group("enemies")
	return out


# Skip the beam's own owner + everything under it (a boss never kills its own turrets/lasers).
func _is_ignored(t: Object) -> bool:
	if ignore_owner == null or not (t is Node):
		return false
	var n: Node = t as Node
	return n == ignore_owner or ignore_owner.is_ancestor_of(n)


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
	for t in _damage_candidates():
		if not is_instance_valid(t) or not (t is Node2D) or _is_ignored(t):
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


const FactionsC = preload("res://scripts/levels/factions.gd")


# The host faction that colors the beam: explicit `faction` (>= -1) wins; -2 auto-detects from the host's
# `faction_skin` meta (walking up the tree); -1 = no faction (white).
func _resolve_faction() -> int:
	if faction >= -1:
		return faction
	var n: Node = get_parent()
	while n != null:
		if n.has_meta("faction_skin"):
			return int(n.get_meta("faction_skin"))
		n = n.get_parent()
	return -1


func _ensure_visuals() -> void:
	if not _lines.is_empty():
		return
	var tbl: Array = layers if not layers.is_empty() else _default_layers()
	# Faction muzzle color for the beam (white for no faction / Core), unless tinting is OFF.
	var tint_on: bool = faction != FACTION_OFF
	var mc: Color = FactionsC.muzzle_glow_color(_resolve_faction()) if tint_on else Color.WHITE
	# Hit-effect tint: the faction laser-inner when tinted; a FACTION_OFF (authored
	# palette) beam falls back to its mid layer so boss beams keep their bespoke hue.
	if tint_on:
		_fx_color = mc
	elif tbl.size() >= 2:
		_fx_color = (tbl[tbl.size() - 2] as Dictionary).get("color", Color.WHITE)
	elif not tbl.is_empty():
		_fx_color = (tbl[0] as Dictionary).get("color", Color.WHITE)
	_base_widths.clear()
	for i in tbl.size():
		var spec = tbl[i]
		var w: float = spec.get("width", 4.0)
		_base_widths.append(w)
		var col: Color = spec.get("color", Color.WHITE)
		if tint_on:
			# Outer/mid layers take the muzzle hue; the innermost (core) layer stays white-hot. Keep the
			# authored per-layer alpha so the outer glow stays soft and the core reads bright.
			var is_core: bool = (i == tbl.size() - 1)
			var base: Color = Color.WHITE if is_core else mc
			base.a = col.a
			col = base
		_lines.append(_make_line(col, w))
	if tint_on:
		# Telegraph warning takes the faction hue too. Mutate telegraph_color (not just the line) since
		# _show_telegraph_only re-derives the pulsing color from it every frame.
		telegraph_color = Color(mc.r, mc.g, mc.b, telegraph_color.a)
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
	# Loop upkeep: restart silently if it was cut mid-FIRING (host recycle pause).
	if not _audio_fire_on and not _fading and sfx_profile != "silent":
		_audio_start_fire(false)
	var pts := _line_points()
	var wscale := 1.0
	var alpha := 1.0
	if envelope:
		var ft: float = maxf(0.05, firing_time)
		if _fading:
			wscale = clampf(1.0 - _fade_t / maxf(0.01, envelope_shrink), 0.0, 1.0)   # early-cut shrink
			alpha = 1.0 if fmod(_fade_t * 34.0, 1.0) < 0.5 else 0.2                   # flicker out
		elif _t < envelope_grow:
			wscale = clampf(_t / maxf(0.01, envelope_grow), 0.05, 1.0)   # rapid grow-in (thin white → full)
		elif _t > ft - envelope_shrink:
			wscale = clampf((ft - _t) / maxf(0.01, envelope_shrink), 0.0, 1.0)   # natural shrink at the end
			alpha = 1.0 if fmod(_t * 34.0, 1.0) < 0.5 else 0.2                    # flicker out
			if cycle != Cycle.HOLD and cycle != Cycle.MANUAL:
				_begin_loop_fade()   # loop fades WITH the natural end-of-firing shrink
	for i in _lines.size():
		var l: Line2D = _lines[i]
		l.visible = true
		l.points = pts
		if envelope:
			l.width = maxf(0.1, float(_base_widths[i]) * wscale) if i < _base_widths.size() else l.width
			var m: Color = l.modulate
			m.a = alpha
			l.modulate = m
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


# ---------------------------------------------------------------- audio

const LaserSfxC = preload("res://scripts/effects/laser_sfx.gd")
const ImpactCircleFxC = preload("res://scripts/effects/impact_circle_fx.gd")


# Fire onset: start blast (small/large per profile) + the sustained loop. with_blast
# false = silent loop restart after a recycle pause.
func _audio_start_fire(with_blast: bool) -> void:
	if sfx_profile == "silent" or not is_inside_tree():
		return
	if with_blast:
		LaserSfxC.play_blast(get_tree().root, global_position, sfx_profile == "boss")
	if _loop_player == null or not is_instance_valid(_loop_player):
		_loop_player = LaserSfxC.make_loop_player(sfx_profile)
		add_child(_loop_player)
	if _loop_tween != null and _loop_tween.is_valid():
		_loop_tween.kill()
	_loop_player.volume_db = LaserSfxC.LOOP_VOLUME_DB
	_loop_player.play()
	_loop_fading = false
	_audio_fire_on = true


# Fire end: stop blast (+ boss spin-down flutter) and make sure the loop is fading.
# with_blast false = silent cut (host died / recycle pause).
func _audio_end_fire(with_blast: bool) -> void:
	if not _audio_fire_on:
		return
	_audio_fire_on = false
	if with_blast and sfx_profile != "silent" and is_inside_tree():
		LaserSfxC.play_blast(get_tree().root, global_position, sfx_profile == "boss")
		if sfx_profile == "boss":
			LaserSfxC.play_spin_down(get_tree().root, global_position)
	_begin_loop_fade()


# Fade the firing loop out over the envelope-shrink window ("fades out as the laser
# finishes firing"). Idempotent per shot.
func _begin_loop_fade() -> void:
	if _loop_fading or _loop_player == null or not is_instance_valid(_loop_player) or not _loop_player.playing:
		return
	_loop_fading = true
	if _loop_tween != null and _loop_tween.is_valid():
		_loop_tween.kill()
	_loop_tween = create_tween()
	_loop_tween.tween_property(_loop_player, "volume_db", LaserSfxC.SILENT_DB, maxf(envelope_shrink, 0.2))
	_loop_tween.tween_callback(_loop_player.stop)


# Impact-circle burst where the beam strikes a target — the same effect family bullets
# use, tinted with the beam's laser-inner color. Returns the strike point.
func _spawn_hit_fx(t: Node2D, a: Vector2, b: Vector2) -> Vector2:
	var p: Vector2 = t.global_position
	var ab: Vector2 = b - a
	var lsq: float = ab.length_squared()
	if lsq > 0.0001:
		p = a + ab * clampf((p - a).dot(ab) / lsq, 0.0, 1.0)
	if is_inside_tree():
		var dir: Vector2 = (ab / sqrt(lsq)) if lsq > 0.0001 else Vector2.DOWN
		ImpactCircleFxC.spawn(get_tree().root, p, dir, _fx_color)
	return p
