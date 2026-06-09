extends "res://scripts/enemies/movement_pattern.gd"

# Pendulum (Roman 2026-06-08, ported from the bespoke enemy_crystal SM): a vertical ping-pong
# diver. Dive to a low band → fishtail-rotate to aim at the player → fire → rise to a high band →
# aim → fire → 50/50 dive again or exit down. The aim dwell rotates the HULL (the weapon fires
# along it — pair with a FORWARD-aim weapon, or any weapon: rotation is the telegraph). Emits
# phase_entered("fire") at each band so enemy_core fires once per stop (set fire_on_phase="fire").
#
# Movement-only by design: it owns rotation (set auto_rotate=false on the host). The weapon +
# fire timing live on the weapon axis. Faithful to the crystal's original constants.

const Playfield = preload("res://scripts/playfield.gd")

signal phase_entered(phase_name: String)

@export var target_y_low: float = 200.0
@export var target_y_high: float = 30.0
@export var dive_speed: float = 220.0
@export var slow_band: float = 30.0        # ease the last px of each dive/rise
@export var slow_min_speed: float = 35.0
@export var fishtail_time: float = 0.4     # seconds spent rotating to aim before firing
@export var rot_lerp_rate: float = 8.0
@export var fire_pause: float = 0.18       # hold after firing
@export var exit_speed: float = 240.0

enum Ph { DIVE, AIM, FIRE, RISE, AIM_HIGH, FIRE_HIGH, EXIT }
var _ph: int = Ph.DIVE
var _t: float = 0.0


func on_start(_enemy) -> void:
	_ph = Ph.DIVE
	_t = 0.0


func compute_step(enemy, delta: float) -> Vector2:
	match _ph:
		Ph.DIVE:
			return _travel_to(enemy, target_y_low, delta, Ph.AIM)
		Ph.AIM:
			return _aim_then(enemy, delta, Ph.FIRE, "fire")
		Ph.FIRE:
			return _hold_then(delta, Ph.RISE)
		Ph.RISE:
			return _travel_to(enemy, target_y_high, delta, Ph.AIM_HIGH)
		Ph.AIM_HIGH:
			return _aim_then(enemy, delta, Ph.FIRE_HIGH, "fire")
		Ph.FIRE_HIGH:
			# After the top stop: 50/50 dive again or commit to leaving.
			if _t == 0.0:
				pass
			_t += delta
			if _t >= fire_pause:
				_t = 0.0
				if randf() < 0.5:
					_ph = Ph.DIVE
				else:
					_ph = Ph.EXIT
			return Vector2.ZERO
		_:  # EXIT — face down, plunge out the bottom
			enemy.rotation = lerp_angle(enemy.rotation, PI, rot_lerp_rate * delta)
			return Vector2(0.0, exit_speed * delta)


# Eased vertical travel to target_y; faces travel direction; advances to next phase on arrival.
func _travel_to(enemy, target_y: float, delta: float, next: int) -> Vector2:
	var dy: float = target_y - enemy.position.y
	var dist: float = absf(dy)
	if dist <= 1.5:
		_ph = next
		_t = 0.0
		return Vector2(0.0, dy)
	var speed_now: float = dive_speed
	if dist < slow_band:
		speed_now = lerpf(slow_min_speed, dive_speed, dist / slow_band)
	var dir: float = signf(dy)
	enemy.rotation = lerp_angle(enemy.rotation, (PI if dir > 0.0 else 0.0), rot_lerp_rate * delta)
	return Vector2(0.0, dir * speed_now * delta)


# Rotate to face the player for fishtail_time, then emit the fire beat + advance. No translation.
func _aim_then(enemy, delta: float, next: int, beat: String) -> Vector2:
	var p = enemy.find_player() if enemy.has_method("find_player") else null
	if p != null and is_instance_valid(p):
		var to_p: Vector2 = p.global_position - enemy.global_position
		if to_p.length_squared() > 1.0:
			enemy.rotation = lerp_angle(enemy.rotation, to_p.angle() + PI * 0.5, rot_lerp_rate * delta)
	_t += delta
	if _t >= fishtail_time:
		_t = 0.0
		_ph = next
		phase_entered.emit(beat)
	return Vector2.ZERO


func _hold_then(delta: float, next: int) -> Vector2:
	_t += delta
	if _t >= fire_pause:
		_t = 0.0
		_ph = next
	return Vector2.ZERO
