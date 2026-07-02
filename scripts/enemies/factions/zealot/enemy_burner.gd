extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyBurner

# Burner — medium-tough beam enemy that ALWAYS arrives in pairs. The two members find
# each other on spawn, settle near the top, then string a damaging beam BETWEEN them
# and descend together with the beam held taut. Passing through it damages the player.
# Killing EITHER member stops the beam and blows up BOTH.
#
# M6a.2 step 4b: the bespoke 4-layer Line2D + segment-distance damage (~140 lines) are
# gone — the owner now drives a MANUAL, SEGMENT-mode BeamEmitter (set_segment each
# frame between the two inner-emit points; show_telegraph during TELEGRAPH, show_fire
# during FIRING). The pairing/ownership/phase/death machine stays here (it owns the
# timing); the emitter owns the shared visuals + damage.

const BeamEmitter = preload("res://scripts/enemies/beam_emitter.gd")

# --- movement tuning ----------------------------------------------------
const SETTLE_Y      := 56.0
const ENTER_SPEED   := 150.0
const DESCENT_SPEED := 26.0
const X_CLAMP_INSET := 8.0

# --- beam tuning --------------------------------------------------------
const TELEGRAPH_DURATION := 0.7
const BEAM_DPS    := 3.0
const HIT_RADIUS  := 6.0

enum Phase { ENTER, TELEGRAPH, FIRING, LEAVING }

var _partner: EnemyBurner = null
var _is_beam_owner: bool = false
var _adopt_tried: bool = false
var _phase: int = Phase.ENTER
var _phase_t: float = 0.0
var _settled: bool = false
var _beam: Node = null   # owner-only MANUAL SEGMENT BeamEmitter


func _ready() -> void:
	# HP/bounty come from the roster (hp_override 12 / bounty_override 30), set by the director before
	# _ready. The guard is only a dev/emitter-spawn fallback (default max_health is 1) so it doesn't
	# clobber the roster value in production — the roster is the single source (2026-07-02 consolidation).
	if max_health <= 1:
		max_health = 12
	display_scale = 1.0
	super._ready()


func _process(delta: float) -> void:
	if _dying:
		return
	if not _adopt_tried:
		_try_adopt_partner()
	_tick(delta)
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
		if not is_instance_valid(other) or other._dying:
			continue
		if other._partner != null and is_instance_valid(other._partner):
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = other
	if nearest != null:
		_partner = nearest
		nearest._partner = self
		var mine: int = get_instance_id()
		var theirs: int = nearest.get_instance_id()
		_is_beam_owner = mine < theirs
		nearest._is_beam_owner = theirs < mine
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
			_drive_beam(true)
			if _phase_t >= TELEGRAPH_DURATION:
				_enter_firing()
		Phase.FIRING:
			_joint_descent(delta)
			_drive_beam(false)
		Phase.LEAVING:
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
	if _is_beam_owner and _settled:
		if _has_live_partner() and _partner._settled:
			_enter_telegraph()
	elif _settled and not _has_live_partner():
		if _phase_t > 1.0:
			_phase = Phase.LEAVING
			_phase_t = 0.0


func _joint_descent(delta: float) -> void:
	# Y is OWNER-AUTHORITATIVE so the beam is dead-level; each keeps its own X.
	if _is_beam_owner:
		global_position.y += DESCENT_SPEED * delta
		global_position = Playfield.clamp_pos(global_position, X_CLAMP_INSET)
		if _has_live_partner():
			var p: Vector2 = _partner.global_position
			p.y = global_position.y
			_partner.global_position = Playfield.clamp_pos(p, X_CLAMP_INSET)
	else:
		global_position = Playfield.clamp_pos(global_position, X_CLAMP_INSET)


func _enter_telegraph() -> void:
	if _phase != Phase.ENTER:
		return
	_phase = Phase.TELEGRAPH
	_phase_t = 0.0
	if _has_live_partner() and _partner._phase == Phase.ENTER:
		_partner._phase = Phase.TELEGRAPH
		_partner._phase_t = 0.0
		var p: Vector2 = _partner.global_position
		p.y = global_position.y
		_partner.global_position = Playfield.clamp_pos(p, X_CLAMP_INSET)


func _enter_firing() -> void:
	_phase = Phase.FIRING
	_phase_t = 0.0
	if _has_live_partner() and _partner._phase == Phase.TELEGRAPH:
		_partner._phase = Phase.FIRING
		_partner._phase_t = 0.0


# --- beam (owner only, delegated to a MANUAL SEGMENT BeamEmitter) --------

func _ensure_beam() -> void:
	if _beam != null and is_instance_valid(_beam):
		return
	_beam = BeamEmitter.new()
	_beam.configure({
		"endpoint": BeamEmitter.Endpoint.SEGMENT, "cycle": BeamEmitter.Cycle.MANUAL,
		"autostart": true, "dps": BEAM_DPS, "hit_radius": HIT_RADIUS, "target_group": "player",
		# enemy_beam_shooter style thinned ~20%: outer 12.8 / mid 6.4 / core 2.4, telegraph 0.8.
		"layers": [
			{"width": 12.8, "color": Color(0.65, 0.15, 1.0, 0.55)},
			{"width": 6.4, "color": Color(1.0, 0.5, 0.1, 0.85)},
			{"width": 2.4, "color": Color(1.0, 0.95, 0.35, 1.0)},
		],
		"telegraph_width": 0.8,
	})
	add_child(_beam)


# Drive the owner's beam: set the world segment between the two inner-emit points,
# then telegraph (warning) or fire (lethal). Owner only; no-op without a live partner.
func _drive_beam(telegraph: bool) -> void:
	if not _is_beam_owner:
		return
	if not _has_live_partner():
		_free_beam()
		return
	_ensure_beam()
	var own_pt: Vector2 = _beam_point(_partner.global_position)
	var partner_pt: Vector2 = _partner._beam_point(global_position)
	_beam.set_segment(own_pt, partner_pt)
	if telegraph:
		_beam.show_telegraph()
	else:
		_beam.show_fire()


func _free_beam() -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.queue_free()
	_beam = null


# Beam endpoint in WORLD space, from the marker facing the partner (inner edge).
# Selected by world distance to the partner (rotation-invariant — the hull
# auto-rotates ~180° on descent, so name/local-x selection would pick the outer edge).
func _beam_point(toward: Vector2) -> Vector2:
	var mr: Node2D = get_node_or_null("BeamR") as Node2D
	var ml: Node2D = get_node_or_null("BeamL") as Node2D
	if mr != null and ml != null:
		var dr: float = mr.global_position.distance_squared_to(toward)
		var dl: float = ml.global_position.distance_squared_to(toward)
		return mr.global_position if dr <= dl else ml.global_position
	if mr != null:
		return mr.global_position
	if ml != null:
		return ml.global_position
	return global_position


# --- death --------------------------------------------------------------

func explode() -> void:
	if _dying:
		return
	_free_beam()
	super.explode()
	if _partner != null and is_instance_valid(_partner):
		_partner.explode()
