extends "res://scripts/enemies/enemy_base.gd"

# Smart Mine (Roman, 2026-05-18 mine pass): "uses mine_smart and appears
# as frame 1 when dormant. When shot, plays F2 then F3, upon F3 it
# begins aggressively flying toward the player. It also activates if
# the player comes within 16 pixels of it. Slow, but relentless."
#
# Sprite is a 3-frame strip (16×16 each, 48×16 total):
#   F0 = dormant
#   F1 = transition (shown briefly when activating)
#   F2 = active / chasing
#
# Activation triggers:
#   - Bullet hit while dormant (any non-lethal hit)
#   - Player within `proximity_trigger` pixels

@export var drift_speed: float = 60.0  # +20% per Roman 2026-05-18
@export var chase_accel: float = 360.0
@export var chase_max_speed: float = 180.0
@export var damage_on_collide: int = 2
@export var proximity_trigger: float = 16.0
# Frame-by-frame transition timing once activation fires.
@export var transition_time: float = 0.18

enum Phase { DORMANT, TRANSITIONING, CHASING }

var _phase: int = Phase.DORMANT
var _phase_t: float = 0.0
var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	max_health = 3
	is_hazard = true
	bounty_value = 2
	display_scale = 1.0
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	if has_node("Sprite2D"):
		$Sprite2D.frame = 0
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


func start(pos: Vector2) -> void:
	position = pos
	_velocity = Vector2(0.0, drift_speed)


func _process(delta: float) -> void:
	if _dying:
		return
	match _phase:
		Phase.DORMANT:
			# Proximity trigger.
			var p := find_player()
			if p and is_instance_valid(p):
				if global_position.distance_to(p.global_position) <= proximity_trigger:
					_begin_activation()
		Phase.TRANSITIONING:
			_phase_t += delta
			# Show F1 for transition_time, then snap to F2 and chase.
			if has_node("Sprite2D"):
				$Sprite2D.frame = 1
			if _phase_t >= transition_time:
				_phase = Phase.CHASING
				if has_node("Sprite2D"):
					$Sprite2D.frame = 2
		Phase.CHASING:
			var p_c := find_player()
			if p_c and is_instance_valid(p_c):
				var dir: Vector2 = (p_c.global_position - global_position).normalized()
				_velocity = _velocity.move_toward(dir * chase_max_speed, chase_accel * delta)
	position += _velocity * delta
	# Don't sail off the playfield band while chasing.
	if position.x < Playfield.X_MIN + 4.0 and _velocity.x < 0.0:
		position.x = Playfield.X_MIN + 4.0
		_velocity.x = -_velocity.x * 0.5
	elif position.x > Playfield.X_MAX - 4.0 and _velocity.x > 0.0:
		position.x = Playfield.X_MAX - 4.0
		_velocity.x = -_velocity.x * 0.5
	# Despawn off the bottom only when dormant — once chasing, stick
	# around until destroyed or contact.
	if _phase == Phase.DORMANT and position.y > screensize.y + 32.0:
		queue_free()


func hit() -> void:
	# Any bullet hit while dormant arms the mine.
	if _phase == Phase.DORMANT:
		_begin_activation()
	if has_node("ParticleHit"):
		$ParticleHit.restart()


func _begin_activation() -> void:
	if _phase != Phase.DORMANT:
		return
	_phase = Phase.TRANSITIONING
	_phase_t = 0.0
	_velocity = Vector2.ZERO  # halt drift while spinning up


func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# Chasing smart mines pop with a 2nd jitter blast; otherwise single 1×.
	if _phase == Phase.CHASING:
		ExplosionFx.burst(global_position, 2, 6.0, 0.05)
	else:
		ExplosionFx.play(global_position, 1.0)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
