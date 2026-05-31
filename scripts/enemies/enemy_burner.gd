extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyBurner

# Burner — medium-tough beam enemy that ALWAYS arrives in pairs (Roman spec,
# 2026-05-31). The two members find each other on spawn, descend to a settle
# band near the top, then establish a damaging beam strung BETWEEN them and
# descend the rest of the screen together with the beam held taut. Passing
# through the beam damages the player. Killing EITHER member stops the beam
# and blows up BOTH.
#
# Bespoke self-driving enemy (extends enemy_base directly, like
# enemy_beam_shooter / enemy_firecore_cruiser). No movement/shoot Resource
# slots — roster entry sets movement:null, shoot:null.
#
# Pairing model:
#   - On first _process, an unlinked Burner scans the "enemies" group for the
#     nearest other unlinked Burner and adopts it (sets _partner both ways).
#   - The member with the LOWER instance id becomes the beam owner
#     (_is_beam_owner). Both sides compute the same answer deterministically,
#     so exactly one owner draws + applies the beam; the other is a passive
#     anchor. This avoids double damage.
#   - A lone Burner (odd-count wave, or the standalone scene) never finds a
#     partner: it simply descends and leaves, no beam, no crash.
#
# Death model:
#   - explode() frees the beam, runs super.explode() (which sets _dying
#     synchronously BEFORE its await), THEN calls partner.explode(). The
#     partner's reciprocal call back into us hits `if _dying: return` and
#     no-ops, so no infinite recursion.

# --- movement tuning ----------------------------------------------------
const SETTLE_Y      := 56.0    # y the pair descends to before establishing beam
const ENTER_SPEED   := 150.0   # px/s while diving to the settle band
const DESCENT_SPEED := 26.0    # px/s slow joint descent once the beam is live
const X_CLAMP_INSET := 8.0     # keep members inside the playfield band

# --- beam tuning --------------------------------------------------------
const TELEGRAPH_DURATION := 0.7   # pulsing, no-damage warning before the beam bites
const BEAM_DPS    := 3.0
const HIT_RADIUS  := 6.0   # matches the thinned beam's visible outer half-width (Roman 2026-05-31)

enum Phase { ENTER, TELEGRAPH, FIRING, LEAVING }

var _partner: EnemyBurner = null
var _is_beam_owner: bool = false
var _adopt_tried: bool = false
var _phase: int = Phase.ENTER
var _phase_t: float = 0.0
var _beam_t: float = 0.0
var _settled: bool = false
var _dmg_accum: float = 0.0

# Beam Line2D stack — only the owner ever builds these.
var _beam_outer:     Line2D = null
var _beam_mid:       Line2D = null
var _beam_core:      Line2D = null
var _beam_telegraph: Line2D = null


func _ready() -> void:
	# Medium-tough. Set BEFORE super._ready() so health = max_health lands at 12
	# (the .tscn / wave overrides may still raise it, but never via compose_stats
	# for this non-chaff enemy). Roman: ~12 HP, ~30 bounty.
	max_health   = 12
	bounty_value = 30
	auto_rotate  = false   # beam pair holds a fixed horizontal stance; no banking
	display_scale = 1.0
	super._ready()


func _process(delta: float) -> void:
	if _dying:
		return
	if not _adopt_tried:
		_try_adopt_partner()
	_tick(delta)
	# Base handles offscreen cleanup (CYCLE_BOTTOM by default — but burners
	# should leave at the bottom, so force FREE_ANY_EDGE-style leave below).
	super._process(delta)


# --- pairing ------------------------------------------------------------

func _try_adopt_partner() -> void:
	_adopt_tried = true
	if _partner != null and is_instance_valid(_partner):
		return
	var nearest: EnemyBurner = null
	var nearest_d: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		if not (node is EnemyBurner):
			continue
		var other: EnemyBurner = node as EnemyBurner
		if not is_instance_valid(other):
			continue
		if other._dying:
			continue
		# Only adopt a partner that is itself still unlinked.
		if other._partner != null and is_instance_valid(other._partner):
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = other
	if nearest != null:
		_partner = nearest
		nearest._partner = self
		# Deterministic owner: lower instance id draws + damages. Both members
		# compute the same boolean from the same id pair, so exactly one owns.
		var mine: int = get_instance_id()
		var theirs: int = nearest.get_instance_id()
		_is_beam_owner = mine < theirs
		nearest._is_beam_owner = theirs < mine
		# Mark the partner as having resolved adoption too, so it doesn't
		# re-scan and (harmlessly) re-confirm us next frame.
		nearest._adopt_tried = true


func _has_live_partner() -> bool:
	return _partner != null and is_instance_valid(_partner) and not _partner._dying


# --- movement + phase ---------------------------------------------------

func _tick(delta: float) -> void:
	_phase_t += delta
	match _phase:
		Phase.ENTER:
			_descend_to_settle(delta)
		Phase.TELEGRAPH:
			_joint_descent(delta)
			_tick_beam_telegraph(delta)
			if _phase_t >= TELEGRAPH_DURATION:
				_enter_firing()
		Phase.FIRING:
			_joint_descent(delta)
			_tick_beam_firing(delta)
		Phase.LEAVING:
			# Drop the beam and just fall off the bottom; base offscreen check
			# frees us once we clear the edge.
			_free_beam()
			global_position.y += DESCENT_SPEED * delta


func _descend_to_settle(delta: float) -> void:
	if global_position.y < SETTLE_Y:
		global_position.y += ENTER_SPEED * delta
		if global_position.y >= SETTLE_Y:
			global_position.y = SETTLE_Y
	else:
		global_position.y = SETTLE_Y
	global_position = Playfield.clamp_pos(global_position, X_CLAMP_INSET)
	_settled = global_position.y >= SETTLE_Y - 0.5
	# Only the owner advances the shared phase, and only once BOTH are settled
	# and linked. A lone burner never links → falls through to LEAVING.
	if _is_beam_owner and _settled:
		if _has_live_partner() and _partner._settled:
			_enter_telegraph()
	elif _settled and not _has_live_partner():
		# Lone burner (no partner adopted): give up on the beam and leave.
		# Give adoption a brief grace window before bailing, in case the
		# partner spawns a frame later.
		if _phase_t > 1.0:
			_phase = Phase.LEAVING
			_phase_t = 0.0


func _joint_descent(delta: float) -> void:
	# Both members keep their own X (tandem spread preserved for free), but Y is
	# OWNER-AUTHORITATIVE so the beam is dead-level (Roman, 2026-05-31). The owner
	# advances its Y by DESCENT_SPEED then stamps that exact Y onto the partner,
	# so even if they entered TELEGRAPH a frame apart or drifted, they re-converge
	# to a common Y every frame the beam is live. The anchor only clamps its X and
	# leaves Y alone (the owner sets it), so the two stay perfectly parallel.
	if _is_beam_owner:
		global_position.y += DESCENT_SPEED * delta
		global_position = Playfield.clamp_pos(global_position, X_CLAMP_INSET)
		if _has_live_partner():
			var p: Vector2 = _partner.global_position
			p.y = global_position.y
			_partner.global_position = Playfield.clamp_pos(p, X_CLAMP_INSET)
	else:
		# Anchor: keep X in-band; Y is driven by the owner's stamp above.
		global_position = Playfield.clamp_pos(global_position, X_CLAMP_INSET)


func _enter_telegraph() -> void:
	# Owner-only state transition; mirror onto the anchor so the anchor stops
	# its ENTER bookkeeping and just joint-descends.
	if _phase != Phase.ENTER:
		return
	_phase = Phase.TELEGRAPH
	_phase_t = 0.0
	_beam_t = 0.0
	if _has_live_partner() and _partner._phase == Phase.ENTER:
		_partner._phase = Phase.TELEGRAPH
		_partner._phase_t = 0.0
		# Snap the partner to the owner's exact Y the instant the beam is
		# established so the TELEGRAPH (and the FIRING beam after it) is dead
		# horizontal from frame 0 — _joint_descent keeps it level thereafter.
		var p: Vector2 = _partner.global_position
		p.y = global_position.y
		_partner.global_position = Playfield.clamp_pos(p, X_CLAMP_INSET)


func _enter_firing() -> void:
	_phase = Phase.FIRING
	_phase_t = 0.0
	if _has_live_partner() and _partner._phase == Phase.TELEGRAPH:
		_partner._phase = Phase.FIRING
		_partner._phase_t = 0.0


# --- beam (owner only) --------------------------------------------------

func _tick_beam_telegraph(delta: float) -> void:
	if not _is_beam_owner:
		return
	if not _has_live_partner():
		_free_beam()
		return
	_beam_t += delta
	_ensure_beam_visuals()
	_set_beam_layers_visible(false, false, false, true)
	var alpha: float = sin(_beam_t * TAU * 2.0) * 0.2 + 0.5
	if _beam_telegraph and is_instance_valid(_beam_telegraph):
		var c: Color = _beam_telegraph.default_color
		c.a = alpha
		_beam_telegraph.default_color = c
		_update_beam_points(_beam_telegraph)


func _tick_beam_firing(delta: float) -> void:
	if not _is_beam_owner:
		return
	if not _has_live_partner():
		_free_beam()
		return
	_ensure_beam_visuals()
	_set_beam_layers_visible(true, true, true, false)
	_update_beam_points(_beam_outer)
	_update_beam_points(_beam_mid)
	_update_beam_points(_beam_core)
	_apply_beam_damage(delta)


func _ensure_beam_visuals() -> void:
	if _beam_outer and is_instance_valid(_beam_outer):
		return
	# enemy_beam_shooter visual style thinned ~20% (Roman, 2026-05-31):
	# outer 16→12.8, mid 8→6.4, core 3→2.4, telegraph 1→0.8. Colors/style kept.
	_beam_outer     = _make_line(Color(0.65, 0.15, 1.0, 0.55), 12.8)
	_beam_mid       = _make_line(Color(1.0, 0.5, 0.1, 0.85),   6.4)
	_beam_core      = _make_line(Color(1.0, 0.95, 0.35, 1.0),  2.4)
	_beam_telegraph = _make_line(Color(1.0, 0.95, 0.35, 0.5),  0.8)
	add_child.call_deferred(_beam_outer)
	add_child.call_deferred(_beam_mid)
	add_child.call_deferred(_beam_core)
	add_child.call_deferred(_beam_telegraph)


func _make_line(color: Color, width: float) -> Line2D:
	var l := Line2D.new()
	l.default_color = color
	l.width = width
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode   = Line2D.LINE_CAP_ROUND
	l.z_index = 4
	l.visible = false
	return l


func _update_beam_points(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	if not _has_live_partner():
		return
	# Line is a child of the owner; draw from owner origin to the partner's
	# position in owner-local space (arbitrary-endpoint geometry, beam-turret
	# style). seg_start = own global, seg_end = partner global.
	line.points = PackedVector2Array([Vector2.ZERO, to_local(_partner.global_position)])


func _set_beam_layers_visible(outer: bool, mid: bool, core: bool, telegraph: bool) -> void:
	if _beam_outer     and is_instance_valid(_beam_outer):     _beam_outer.visible     = outer
	if _beam_mid       and is_instance_valid(_beam_mid):       _beam_mid.visible       = mid
	if _beam_core      and is_instance_valid(_beam_core):      _beam_core.visible      = core
	if _beam_telegraph and is_instance_valid(_beam_telegraph): _beam_telegraph.visible = telegraph


func _free_beam() -> void:
	for l in [_beam_outer, _beam_mid, _beam_core, _beam_telegraph]:
		if l != null and is_instance_valid(l):
			l.queue_free()
	_beam_outer = null
	_beam_mid = null
	_beam_core = null
	_beam_telegraph = null


func _apply_beam_damage(delta: float) -> void:
	var player: Node = find_player()
	if player == null:
		return
	if not _has_live_partner():
		return
	var seg_start: Vector2 = global_position
	var seg_end: Vector2 = _partner.global_position
	if _dist_point_to_segment(player.global_position, seg_start, seg_end) <= HIT_RADIUS:
		_dmg_accum += BEAM_DPS * delta
		while _dmg_accum >= 1.0:
			player.take_damage(1)
			_dmg_accum -= 1.0


static func _dist_point_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return pt.distance_to(a)
	var t: float = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


# --- death --------------------------------------------------------------

# Killing either member blows up both. Ordering is load-bearing:
#   1. _free_beam() — beam vanishes instantly.
#   2. super.explode() — sets _dying = true SYNCHRONOUSLY (before its await),
#      runs death VFX + bounty + queue_free schedule.
#   3. partner.explode() — partner runs its own explode; its reciprocal call
#      back into THIS node hits `if _dying: return` (now true) and no-ops.
# Setting _dying manually first would make super.explode() skip all VFX, so we
# must NOT pre-guard; the inherited guard at the top of super.explode() is what
# protects against the reciprocal call.
func explode() -> void:
	if _dying:
		return
	_free_beam()
	super.explode()
	if _partner != null and is_instance_valid(_partner):
		_partner.explode()
