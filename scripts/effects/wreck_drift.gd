extends Node

# WreckDrift (Roman 2026-06-10) — drives a reparented enemy hull sprite as an inert wreck: it
# "falls" toward the bottom of the screen with a gravity-style downward accel, tumbles slowly with
# a slight randomized spin, and trails world-space smoke. After its lifetime it fades and frees the
# sprite. Pure decoration: the sprite is a bare Sprite2D in the wreck layer (no Area2D), so it's
# never targetable, collidable, or counted for level-clear.
#
# Attached as a CHILD of the wreck Sprite2D; its _process moves the parent. The smoke is a
# MissileSmokeTrail (the world-space "copy of the player damage-smoke effect") so it respects the
# wreck's motion — already-emitted puffs stay put while the hull falls past them.

const MissileSmokeTrailCls = preload("res://scripts/effects/missile_smoke_trail.gd")

# Tunables (Roman: easy to retune once you eyeball the fall feel).
const FALL_SPEED_START := 24.0     # px/s initial downward velocity
const FALL_GRAVITY := 120.0        # px/s^2 downward accel
const FALL_SPEED_MAX := 200.0      # px/s terminal fall
const SPIN_MIN := 0.25             # rad/s — "slight" tumble
const SPIN_MAX := 1.4
const LIFETIME := 3.2              # seconds before fade
const FADE_TIME := 0.6
const DESPAWN_Y := 320.0           # safety: free once well below the 270 playfield

var _vel_y: float = FALL_SPEED_START
var _spin: float = 0.0
var _drift_x: float = 0.0
var _t: float = 0.0
var _fading: bool = false
var _smoke: Node2D = null


# Attach a fresh drift controller to a wreck sprite. `seed_i` varies spin/drift direction per wreck
# without Math.random (unavailable in some headless contexts; the caller passes an index).
static func attach(sprite: Node2D, seed_i: int) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var ctrl := Node.new()
	ctrl.set_script(load("res://scripts/effects/wreck_drift.gd"))
	ctrl.name = "WreckDrift"
	sprite.add_child(ctrl)
	(ctrl as Node)._init_drift(seed_i)


func _init_drift(seed_i: int) -> void:
	# Deterministic-ish spread from the seed + a little randf jitter.
	var dir: float = 1.0 if (seed_i % 2 == 0) else -1.0
	_spin = dir * (SPIN_MIN + randf() * (SPIN_MAX - SPIN_MIN))
	_drift_x = dir * randf_range(2.0, 10.0)
	_vel_y = FALL_SPEED_START + randf_range(-6.0, 10.0)
	# World-space smoke trailing the falling hull (flip_drift: a down-mover trails its smoke up/behind).
	var sprite := get_parent()
	if sprite is Node2D:
		_smoke = MissileSmokeTrailCls.new()
		if "flip_drift" in _smoke:
			_smoke.flip_drift = true
		# The trail is a self-managing Node2D that parents its Line2D at the scene root; add it to
		# the tree so its _ready runs, then point it at the sprite.
		sprite.add_child(_smoke)
		if _smoke.has_method("attach_to"):
			_smoke.attach_to(sprite)


func _process(delta: float) -> void:
	var sprite := get_parent()
	if not (sprite is Node2D) or not is_instance_valid(sprite):
		return
	var s: Node2D = sprite
	_t += delta
	if not _fading:
		_vel_y = minf(_vel_y + FALL_GRAVITY * delta, FALL_SPEED_MAX)
		s.position += Vector2(_drift_x * delta, _vel_y * delta)
		s.rotation += _spin * delta
		if _t >= LIFETIME or s.global_position.y > DESPAWN_Y:
			_begin_fade(s)


func _begin_fade(s: Node2D) -> void:
	_fading = true
	# Detach the smoke so it dissipates on its own instead of being yanked with the hull.
	if _smoke != null and is_instance_valid(_smoke) and _smoke.has_method("attach_to"):
		_smoke.attach_to(null)
	_smoke = null
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)
