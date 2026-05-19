extends Sprite2D

# Single tumbling shell casing. Spawned by MuzzleFx.play(); takes a launch
# velocity from the caller, applies gravity each frame, spins until it falls
# past the bottom of the screen and is freed.

var _velocity: Vector2 = Vector2.ZERO
var _angular_velocity: float = 0.0
var _spawn_y: float = 0.0
# Shells start large (2x) at the ship's muzzle and shrink to 1x with 50%
# opacity as they reach the bottom of the playfield — sells the depth of the
# falling motion (Roman, 2026-05-16). Zero-g coast, no gravity/drag.
const SCALE_MAX := 2.0
const SCALE_MIN := 1.0
const ALPHA_MAX := 1.0
const ALPHA_MIN := 0.5
@onready var _screensize: Vector2 = get_viewport_rect().size

func _ready() -> void:
	_spawn_y = position.y
	scale = Vector2(SCALE_MAX, SCALE_MAX)

func launch(velocity: Vector2, spin: float = 0.0) -> void:
	_velocity = velocity
	_angular_velocity = spin if spin != 0.0 else randf_range(-12.0, 12.0)

func _process(delta: float) -> void:
	position += _velocity * delta
	rotation += _angular_velocity * delta
	# Progress: 0 at spawn → 1 at screen bottom. Drives scale + alpha falloff.
	var span: float = max(_screensize.y - _spawn_y, 1.0)
	var t: float = clamp((position.y - _spawn_y) / span, 0.0, 1.0)
	var s: float = lerp(SCALE_MAX, SCALE_MIN, t)
	scale = Vector2(s, s)
	modulate.a = lerp(ALPHA_MAX, ALPHA_MIN, t)
	# Off-screen cleanup: any direction. A casing that falls off the bottom
	# vanishes; one that flies sideways past the edge does too.
	if position.y > _screensize.y + 24.0:
		queue_free()
		return
	if position.x < -24.0 or position.x > _screensize.x + 24.0:
		queue_free()
