extends EnemyBase

# Sapper — rare small enemy that drains player shield charges via a teal beam.
# Does NOT deal damage directly; instead transfers shield charges from the player
# to itself and blocks shield regeneration while draining.

enum SapState { SEEKING, DRAINING }

const DRAIN_RANGE   := 160.0   # beam max reach
const DRAIN_DPS     := 0.4     # shield drain rate — 1 charge per 2.5s
const BEAM_COLOR    := Color(0.2, 0.9, 0.85, 0.9)  # teal

var _sap_state: int = SapState.SEEKING
var _drain_accum: float = 0.0
var _pattern: Resource = null

# Beam visuals — created lazily on first DRAINING entry.
var _beam_outer: Line2D = null
var _beam_core: Line2D = null


func _ready() -> void:
	max_health = 2
	bounty_value = 20
	auto_rotate = true
	display_scale = 1.0
	super._ready()
	_pattern = preload("res://scripts/enemies/patterns/omni_thrust.gd").new()
	_pattern.on_start(self)


func _process(delta: float) -> void:
	if _dying:
		_hide_beam()
		return
	var player = find_player()
	# Movement — omni thrust, clamped to top half.
	var step: Vector2 = _pattern.compute_step(self, delta)
	global_position += step
	global_position.y = clamp(global_position.y, 10.0, 120.0)
	# Beam state machine.
	match _sap_state:
		SapState.SEEKING:
			_hide_beam()
			if player and global_position.distance_to(player.global_position) <= DRAIN_RANGE:
				_sap_state = SapState.DRAINING
				_drain_accum = 0.0
		SapState.DRAINING:
			if player == null or global_position.distance_to(player.global_position) > DRAIN_RANGE * 1.2:
				_sap_state = SapState.SEEKING
				_restore_shield_regen(player)
			else:
				_tick_drain(player, delta)
				_show_beam(player)
	super._process(delta)


func _tick_drain(player: Node, delta: float) -> void:
	# Block shield regen each frame we are draining.
	var regen_timer = player.get_node_or_null("ShieldRegenTimer")
	if regen_timer and not regen_timer.is_stopped():
		regen_timer.stop()
	# Accumulate drain and consume full charges.
	_drain_accum += DRAIN_DPS * delta
	while _drain_accum >= 1.0:
		_drain_accum -= 1.0
		if "shield" in player and player.shield > 0:
			# Assigning through the setter fires shield_changed + SFX automatically.
			player.shield -= 1
			# Steal the charge into Sapper's own pool (internal tracking, no visual ring).
			shield = min(shield + 1, 3)


func _restore_shield_regen(player: Node) -> void:
	if player == null:
		return
	var regen_timer = player.get_node_or_null("ShieldRegenTimer")
	if regen_timer and regen_timer.is_stopped():
		if "shield" in player and "max_shield" in player and player.shield < player.max_shield:
			regen_timer.start()


# ---- Beam visuals -----------------------------------------------------------

func _ensure_beam_visuals() -> void:
	if _beam_outer and is_instance_valid(_beam_outer):
		return
	_beam_outer = Line2D.new()
	_beam_outer.default_color = Color(0.2, 0.9, 0.85, 0.6)
	_beam_outer.width = 3.0
	_beam_outer.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_outer.end_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_outer.z_index = 4
	_beam_outer.visible = false

	_beam_core = Line2D.new()
	_beam_core.default_color = Color(1.0, 1.0, 1.0, 0.9)
	_beam_core.width = 1.0
	_beam_core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_core.end_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_core.z_index = 5
	_beam_core.visible = false

	add_child.call_deferred(_beam_outer)
	add_child.call_deferred(_beam_core)


func _show_beam(player: Node) -> void:
	_ensure_beam_visuals()
	if _beam_outer == null or not is_instance_valid(_beam_outer):
		return
	var target_local: Vector2 = to_local(player.global_position)
	var pts := PackedVector2Array([Vector2.ZERO, target_local])
	_beam_outer.points = pts
	_beam_outer.visible = true
	_beam_core.points = pts
	_beam_core.visible = true


func _hide_beam() -> void:
	if _beam_outer and is_instance_valid(_beam_outer):
		_beam_outer.visible = false
	if _beam_core and is_instance_valid(_beam_core):
		_beam_core.visible = false
