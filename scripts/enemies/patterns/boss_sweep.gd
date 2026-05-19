extends "res://scripts/enemies/movement_pattern.gd"

# Enter from top, settle at hover_y, then sweep left-right with a slow sine
# wave plus a tiny vertical wobble. Boss-friendly — never leaves the top
# quarter.

# 480×270 viewport, 216-wide centred playfield. Amplitude pulled back to
# 90 px (~83 % of the 108-px half-width) so the boss stays inside the
# shootable band — Roman, vertical-aspect lock pass.
@export var hover_y: float = 60.0
@export var enter_speed: float = 70.0
@export var sweep_amplitude: float = 90.0
@export var sweep_frequency: float = 0.35

enum Phase { ENTERING, SWEEPING }
var _phase: int = Phase.ENTERING
var _t: float = 0.0
var _center_x: float = 400.0


func on_start(enemy) -> void:
	_phase = Phase.ENTERING
	_t = 0.0
	_center_x = enemy.position.x


func compute_step(enemy, delta: float) -> Vector2:
	match _phase:
		Phase.ENTERING:
			var step_y: float = enter_speed * delta
			if enemy.position.y + step_y >= hover_y:
				step_y = hover_y - enemy.position.y
				_phase = Phase.SWEEPING
				_t = 0.0
			return Vector2(0, step_y)
		Phase.SWEEPING:
			_t += delta
			# Sin^3 easing on the X sweep (Roman 2026-05-19) — peaks linger
			# briefly rather than snapping direction, so the side-to-side
			# motion is less stark. Same amplitude, slightly slower feel.
			var raw_x: float = sin(_t * sweep_frequency * TAU)
			var eased_x: float = raw_x * raw_x * raw_x
			var target_x: float = _center_x + eased_x * sweep_amplitude
			var target_y: float = hover_y + sin(_t * 0.6) * 3.0
			return Vector2(target_x - enemy.position.x, target_y - enemy.position.y)
	return Vector2.ZERO
