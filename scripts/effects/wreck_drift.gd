extends Node

# WreckDrift (Roman 2026-06-10) — drives a reparented enemy hull sprite as a DISABLED wreck. The
# transition from active enemy to dead hull reads naturally:
#   - PRESERVES the enemy's velocity at the moment of death, then gravity curves it into a fall (an
#     upward mover decelerates and drops; a descender keeps falling) while lateral motion damps to a
#     slight drift — easing from active flight into a disabled tumble.
#   - A slow randomized TUMBLE eases in (starts at the enemy's facing, not an instant spin).
#   - MID-DEPTH recession (core function of entering the wreck layer): smoothly scales DOWN to ~half
#     the recycle shrink and darkens, so the hull recedes into the backdrop depth. (Colour grade rides
#     on the wreck layer's modulate; the damage-overlay shader stays on the sprite for the battered
#     look — the two can't share the one material slot, so depth here is scale + grade.)
#   - At the EXIT ZONE (bottom of the play band) it's DECIDED: 70% explode in place, 30% keep falling
#     off-screen and free. (Roman 2026-06-10 — disabled hulls don't just fade; they resolve at the
#     bottom.)
# The fire + smoke tells are attached by enemy_base._die_as_wreck (the player's damage effects).
#
# Attached as a CHILD of the wreck Sprite2D; its _process moves the parent.

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")

# Tunables (Roman: retune once you eyeball the fall).
const FALL_GRAVITY := 110.0        # px/s^2 downward accel that curves the preserved velocity into a fall
const FALL_SPEED_MAX := 190.0      # px/s terminal fall
const LATERAL_DAMP := 1.6          # per-sec rate the sideways velocity decays toward the slight drift
const SPIN_MIN := 0.30             # rad/s — "slight" tumble
const SPIN_MAX := 1.25
const SPIN_EASE := 2.6             # per-sec rate the tumble eases in from 0 (preserve facing first)
const WRECK_SCALE := 0.72          # ~half the recycle shrink (recycle goes to 0.45); "reduce slightly"
const SCALE_TIME := 1.0            # doubled from 0.5 (Roman 2026-06-10 — the shrink wasn't reading)
const RECEDE_DARKEN := 0.9         # subtle per-sprite push into depth (compounds with the layer grade)
const EXIT_ZONE_Y := 195.0         # Zones.DEPARTURE_START — the "exit zone" where the fate is decided
const EXPLODE_CHANCE := 0.70       # at the exit zone: explode vs fall off-screen
const DESPAWN_Y := 320.0           # the fall-off case frees here, below the 270 playfield
const SAFETY_LIFETIME := 10.0      # backstop free if it somehow never reaches the exit zone

var _vel: Vector2 = Vector2.ZERO
var _drift_x: float = 0.0
var _spin_target: float = 0.0
var _spin_cur: float = 0.0
var _t: float = 0.0
var _decided: bool = false
var _done: bool = false


# Attach a fresh drift controller to a wreck sprite. `init_vel` (px/s, world) is the enemy's velocity
# at death — preserved as the starting motion. `seed_i` (a counter, not Math.random) varies the spin
# + drift direction per wreck.
static func attach(sprite: Node2D, init_vel: Vector2, seed_i: int) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var ctrl := Node.new()
	ctrl.set_script(load("res://scripts/effects/wreck_drift.gd"))
	ctrl.name = "WreckDrift"
	sprite.add_child(ctrl)
	(ctrl as Node)._init_drift(init_vel, seed_i)


func _init_drift(init_vel: Vector2, seed_i: int) -> void:
	var sprite := get_parent()
	if not (sprite is Node2D):
		return
	var s: Node2D = sprite
	var dir: float = 1.0 if (seed_i % 2 == 0) else -1.0
	_spin_target = dir * (SPIN_MIN + randf() * (SPIN_MAX - SPIN_MIN))
	_drift_x = dir * randf_range(3.0, 11.0)
	_vel = init_vel   # preserve the enemy's motion at the moment of death
	# Mid-depth recession: smooth scale-down + a subtle darken (the colour grade itself rides on the
	# wreck layer's modulate). Core part of "moving anything into the wreck layer".
	var tw := s.create_tween()
	tw.tween_property(s, "scale", s.scale * WRECK_SCALE, SCALE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	s.modulate = Color(s.modulate.r * RECEDE_DARKEN, s.modulate.g * RECEDE_DARKEN, s.modulate.b * RECEDE_DARKEN, s.modulate.a)


func _process(delta: float) -> void:
	var sprite := get_parent()
	if _done or not (sprite is Node2D) or not is_instance_valid(sprite):
		return
	var s: Node2D = sprite
	_t += delta
	# Curve the preserved velocity into a fall: gravity pulls Y down (decelerating an upward mover,
	# then dropping it), lateral velocity damps toward the slight drift.
	_vel.y = minf(_vel.y + FALL_GRAVITY * delta, FALL_SPEED_MAX)
	_vel.x = lerpf(_vel.x, _drift_x, clampf(LATERAL_DAMP * delta, 0.0, 1.0))
	s.position += _vel * delta
	# Tumble eases in from 0 so the hull keeps its facing for a beat before slowly turning.
	_spin_cur = lerpf(_spin_cur, _spin_target, clampf(SPIN_EASE * delta, 0.0, 1.0))
	s.rotation += _spin_cur * delta
	# Decide the wreck's fate when it reaches the exit zone (bottom of the play band).
	if not _decided and s.global_position.y >= EXIT_ZONE_Y:
		_decided = true
		if randf() < EXPLODE_CHANCE:
			_explode_and_free(s)
			return
	# Fall-off case (or pre-decision safety): free once well below the screen or after the backstop.
	if s.global_position.y > DESPAWN_Y or _t >= SAFETY_LIFETIME:
		_done = true
		s.queue_free()


func _explode_and_free(s: Node2D) -> void:
	_done = true
	ExplosionFx.play(s.global_position, 1.0)   # distance-based sound rides along
	s.queue_free()
