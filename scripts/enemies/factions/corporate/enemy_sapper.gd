extends "res://scripts/enemies/enemy_core.gd"

# Sapper — rare small enemy that drains player shield charges via a teal beam.
# Does NOT deal damage directly; instead transfers shield charges from the player
# to itself and blocks shield regeneration while draining.

enum SapState { SEEKING, DRAINING }

const DRAIN_RANGE   := 140.0   # beam max reach — matches omni_thrust target_range (130) + tolerance
const DRAIN_DPS     := 0.4     # shield drain rate — 1 charge per 2.5s

# Shield blue — matches Ui.COLOR_SHIELD (the HUD shield pip color) so the beam
# visually reads as "this thing is eating your shield".
const BEAM_COLOR    := Color(0.35, 0.65, 1.0)

const OmniThrust  = preload("res://scripts/enemies/patterns/omni_thrust.gd")

var _sap_state: int = SapState.SEEKING
var _drain_accum: float = 0.0

# Beam visual — a shared BeamEmitter (visual-only: dps 0, the sapper does its own
# shield drain in _tick_drain). MANUAL cycle + SEGMENT endpoint so the sapper drives
# on/off and sets the sapper→player endpoints each frame. Created lazily on first DRAIN.
const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
var _beam: Node = null


func _ready() -> void:
	max_health = 2
	# Unified shield (shield_unification_2026-06-08.md): the sapper is the one POOL-mode
	# shield — a banked DAMAGE pool that grows past its initial capacity as it steals the
	# player's charges (bank()), and the only shield that can tank a whole damage amount
	# (so a well-fed sapper survives a smart bomb). Appended BEFORE super._ready() so
	# _init_components dups it.
	var sh := ShieldComponent.new()
	sh.mode = ShieldComponent.Mode.POOL
	sh.capacity = 2   # initial pool (was the double-shielded max_shield)
	sh.ring_size = 22.0
	# Reassign (not append) — @export Array defaults are shared across instances.
	components = components + [sh]
	bounty_value = 20
	auto_rotate = true
	display_scale = 1.0
	# Guard the omni install (2026-07-18) like cruiser/bomber: the director sets the roster-assigned
	# movement BEFORE add_child (so it's already live in _ready). Only self-install omni when nothing
	# assigned one — a bench/dev spawn with no director — so an assigned NON-omni movement (e.g. a
	# vary/wildcard "proximity_chase") is respected instead of being stomped back into omni-hunt.
	if movement == null:
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
			# Bank the stolen charge into the POOL shield — it accumulates PAST the
			# initial capacity, so a sapper that's been feeding can out-tank a bomb.
			var pool = _pool_shield()
			if pool != null:
				pool.bank(1.0)


# The live POOL-mode ShieldComponent (dup'd into _components at spawn), or null.
func _pool_shield():
	for c in _components:
		if c != null and c.has_method("is_pool") and c.is_pool():
			return c
	return null


func _restore_shield_regen(player: Node) -> void:
	if player == null:
		return
	var regen_timer = player.get_node_or_null("ShieldRegenTimer")
	if regen_timer and regen_timer.is_stopped():
		if "shield" in player and "max_shield" in player and player.shield < player.max_shield:
			regen_timer.start()


func _ensure_beam() -> void:
	if _beam and is_instance_valid(_beam):
		return
	# Visual-only beam: dps 0 (the sapper transfers shield charges in _tick_drain, not via
	# beam damage) and a teal shield-blue 2-layer stack (wide soft glow under a crisp core)
	# matching the HUD shield color. MANUAL cycle = the sapper drives show_fire()/cease();
	# SEGMENT endpoint = the sapper sets the sapper→player endpoints each frame.
	var b := BeamEmitterC.new()
	b.configure({
		"sfx_profile": "sapper",   # energy-force loop while draining (Roman 2026-07-15)
		"cycle": BeamEmitterC.Cycle.MANUAL,
		"endpoint": BeamEmitterC.Endpoint.SEGMENT,
		"autostart": true,
		"dps": 0.0,
		"hit_radius": 0.0,
		"target_group": "player",
		"emitter_offset": Vector2.ZERO,
		"layers": [
			{"width": 6.0, "color": Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.35)},
			{"width": 2.0, "color": BEAM_COLOR},
		],
	})
	_beam = b
	add_child(b)


func _show_beam(player: Node) -> void:
	_ensure_beam()
	if _beam == null or not is_instance_valid(_beam):
		return
	# Sapper origin → player, in world space (SEGMENT draws via to_local each frame).
	_beam.set_segment(global_position, player.global_position)
	_beam.show_fire()


func _hide_beam() -> void:
	if _beam and is_instance_valid(_beam):
		_beam.cease()
