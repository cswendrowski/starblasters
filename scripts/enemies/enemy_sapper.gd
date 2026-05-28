extends "res://scripts/enemy_core.gd"

# Sapper — rare small enemy that drains player shield charges via a teal beam.
# Does NOT deal damage directly; instead transfers shield charges from the player
# to itself and blocks shield regeneration while draining.

enum SapState { SEEKING, DRAINING }

const DRAIN_RANGE   := 140.0   # beam max reach — matches omni_thrust target_range (130) + tolerance
const DRAIN_DPS     := 0.4     # shield drain rate — 1 charge per 2.5s
const BEAM_COLOR    := Color(0.2, 0.9, 0.85, 0.9)  # teal

# Beam shader — scrolling UV drives the player→sapper energy-flow animation.
const BEAM_SHADER = preload("res://graphics/sapper_beam.gdshader")
const OmniThrust  = preload("res://scripts/enemies/patterns/omni_thrust.gd")

var _sap_state: int = SapState.SEEKING
var _drain_accum: float = 0.0

# Beam visuals — created lazily on first DRAINING entry.
var _beam_outer: Line2D = null
var _beam_core: Line2D = null
var _beam_mat: ShaderMaterial = null


func _ready() -> void:
	# Set stats BEFORE super._ready() so the base class sees max_shield = 3
	# and calls _setup_shield_ring() automatically (same pattern as bosses).
	max_health = 2
	max_shield = 3
	shield_ring_size = 22.0
	bounty_value = 20
	auto_rotate = true
	display_scale = 1.0
	movement = OmniThrust.new()
	super._ready()
	start(global_position)


func _process(delta: float) -> void:
	if _dying:
		_hide_beam()
		return
	super._process(delta)
	# Clamp to top half — sapper hovers near the player in the upper band.
	global_position.y = clamp(global_position.y, 10.0, 120.0)
	var player = find_player()
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


func take_hit(damage: int = 1) -> bool:
	if _dying:
		return false
	if _sap_state == SapState.DRAINING:
		var player = find_player()
		if player != null and "shield" in player and player.shield > 0:
			player.shield = max(0, player.shield - damage)
			var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
			if player.has_node("Ship"):
				HitFlashFx.flash(player.get_node("Ship"), HitFlashFx.FLASH_SHIELD)
			return false
	return super.take_hit(damage)


func _tick_drain(player: Node, delta: float) -> void:
	var regen_timer = player.get_node_or_null("ShieldRegenTimer")
	if regen_timer and not regen_timer.is_stopped():
		regen_timer.stop()
	_drain_accum += DRAIN_DPS * delta
	while _drain_accum >= 1.0:
		_drain_accum -= 1.0
		if "shield" in player and player.shield > 0:
			player.shield -= 1
			shield = min(shield + 1, max_shield)


func _restore_shield_regen(player: Node) -> void:
	if player == null:
		return
	var regen_timer = player.get_node_or_null("ShieldRegenTimer")
	if regen_timer and regen_timer.is_stopped():
		if "shield" in player and "max_shield" in player and player.shield < player.max_shield:
			regen_timer.start()


func _ensure_beam_visuals() -> void:
	if _beam_outer and is_instance_valid(_beam_outer):
		return
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("beam_color", Color(0.2, 0.9, 0.85, 0.85))
	_beam_mat.set_shader_parameter("scroll_speed", 1.4)
	_beam_mat.set_shader_parameter("band_freq", 4.0)
	_beam_mat.set_shader_parameter("pulse_contrast", 0.55)
	_beam_mat.set_shader_parameter("edge_fade", 0.06)

	_beam_outer = Line2D.new()
	_beam_outer.default_color = Color(1.0, 1.0, 1.0, 1.0)
	_beam_outer.width = 5.0
	_beam_outer.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_outer.end_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_outer.material = _beam_mat
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
