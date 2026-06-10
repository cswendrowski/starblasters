extends Node

# WreckDrift (Roman 2026-06-10) — drives a reparented enemy hull sprite as an inert wreck. The
# transition from active enemy to dead hull is meant to read naturally:
#   - PRESERVES the enemy's velocity at the moment of death, then gravity curves it into a fall
#     (an upward-moving enemy decelerates and drops; a descender keeps falling) while lateral motion
#     damps to a slight drift — so it eases from active flight into a disabled tumble.
#   - A slow randomized TUMBLE eases in (starts at the enemy's facing, not an instant spin).
#   - MID-DEPTH recession (a core function of entering the wreck layer): smoothly scales DOWN to
#     ~half the recycle shrink and darkens a touch, so the hull recedes into the backdrop depth. (The
#     near-band colour grade comes from the wreck layer's modulate; the damage-overlay shader stays
#     on the sprite so the wreck reads as battle-damaged — the two can't share the one material slot,
#     so depth here is scale + grade, not the depth_tint shader.)
#   - World-space smoke (MissileSmokeTrail) trails behind the falling hull.
# After its lifetime it fades and frees the sprite. Pure decoration: a bare Sprite2D, no Area2D.
#
# Attached as a CHILD of the wreck Sprite2D; its _process moves the parent.

const MissileSmokeTrailCls = preload("res://scripts/effects/missile_smoke_trail.gd")

# Tunables (Roman: retune once you eyeball the fall).
const FALL_GRAVITY := 110.0        # px/s^2 downward accel that curves the preserved velocity into a fall
const FALL_SPEED_MAX := 190.0      # px/s terminal fall
const LATERAL_DAMP := 1.6          # per-sec rate the sideways velocity decays toward the slight drift
const SPIN_MIN := 0.30             # rad/s — "slight" tumble
const SPIN_MAX := 1.25
const SPIN_EASE := 2.6             # per-sec rate the tumble eases in from 0 (preserve facing first)
const WRECK_SCALE := 0.72          # ~half the recycle shrink (recycle goes to 0.45); "reduce slightly"
const SCALE_TIME := 0.5
const RECEDE_DARKEN := 0.9         # subtle per-sprite push into depth (compounds with the layer grade)
const LIFETIME := 3.2              # seconds before fade
const FADE_TIME := 0.6
const DESPAWN_Y := 320.0           # safety: free once well below the 270 playfield

var _vel: Vector2 = Vector2.ZERO
var _drift_x: float = 0.0
var _spin_target: float = 0.0
var _spin_cur: float = 0.0
var _t: float = 0.0
var _fading: bool = false
var _smoke: Node2D = null


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
	# World-space smoke trailing the falling hull (flip_drift: a down-mover trails its smoke up/behind).
	_smoke = MissileSmokeTrailCls.new()
	if "flip_drift" in _smoke:
		_smoke.flip_drift = true
	s.add_child(_smoke)
	if _smoke.has_method("attach_to"):
		_smoke.attach_to(s)


func _process(delta: float) -> void:
	var sprite := get_parent()
	if not (sprite is Node2D) or not is_instance_valid(sprite):
		return
	var s: Node2D = sprite
	_t += delta
	if _fading:
		return
	# Curve the preserved velocity into a fall: gravity pulls Y down (decelerating an upward mover,
	# then dropping it), lateral velocity damps toward the slight drift.
	_vel.y = minf(_vel.y + FALL_GRAVITY * delta, FALL_SPEED_MAX)
	_vel.x = lerpf(_vel.x, _drift_x, clampf(LATERAL_DAMP * delta, 0.0, 1.0))
	s.position += _vel * delta
	# Tumble eases in from 0 so the hull keeps its facing for a beat before slowly turning.
	_spin_cur = lerpf(_spin_cur, _spin_target, clampf(SPIN_EASE * delta, 0.0, 1.0))
	s.rotation += _spin_cur * delta
	if _t >= LIFETIME or s.global_position.y > DESPAWN_Y:
		_begin_fade(s)


func _begin_fade(s: Node2D) -> void:
	_fading = true
	if _smoke != null and is_instance_valid(_smoke) and _smoke.has_method("attach_to"):
		_smoke.attach_to(null)   # let the trail dissipate on its own
	_smoke = null
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)
