extends Node

# WreckDrift (Roman 2026-06-10) — drives a reparented enemy hull sprite as a DISABLED wreck, and owns
# its damage tells (fire + smoke). The transition from active enemy to dead hull reads naturally:
#   - PRESERVES the enemy's velocity at death, then gravity curves it into a fall (an upward mover
#     decelerates and drops; a descender keeps falling) while lateral motion damps to a slight drift.
#   - A slow randomized TUMBLE eases in (starts at the enemy's facing, not an instant spin).
#   - MID-DEPTH recession: smoothly scales DOWN to ~half the recycle shrink + darkens, so the hull
#     recedes into the backdrop depth (the colour grade rides on the wreck layer's modulate).
#   - DAMAGE TELLS: the player's engine-torch FIRE + dark DamageSmokeTrail SMOKE, emitted from a
#     RANDOM engine marker (or the hull centre). The FLAME orients to burn OPPOSITE the wreck's
#     velocity (trails behind its motion, independent of the tumble). The SMOKE is parented to the
#     wreck layer (not the hull) so it FADES OUT after the hull is gone instead of popping.
#   - At the EXIT ZONE (bottom of the play band) the fate is decided by `exit_explode_chance`: that
#     fraction explode in place, the rest drop off-screen. (EM-torp disable passes 0.0 = always fall
#     off; the general disable mode passes 0.70.)
#
# Attached as a CHILD of the wreck Sprite2D; its _process moves the parent + drives the flame.

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const EngineTorchScript = preload("res://scripts/effects/engine_torch.gd")
const DamageSmokeScript = preload("res://scripts/effects/damage_smoke_trail.gd")

# Tunables (Roman: retune once you eyeball the fall).
const FALL_GRAVITY := 110.0        # px/s^2 downward accel that curves the preserved velocity into a fall
const FALL_SPEED_MAX := 190.0      # px/s terminal fall
const LATERAL_DAMP := 1.6          # per-sec rate the sideways velocity decays toward the slight drift
const SPIN_MIN := 0.30             # rad/s — "slight" tumble
const SPIN_MAX := 1.25
const SPIN_EASE := 2.6             # per-sec rate the tumble eases in from 0 (preserve facing first)
const WRECK_SCALE := 0.72          # ~half the recycle shrink (recycle goes to 0.45); "reduce slightly"
const SCALE_TIME := 1.0
const RECEDE_DARKEN := 0.9         # subtle per-sprite push into depth (compounds with the layer grade)
const EXIT_ZONE_Y := 195.0         # Zones.DEPARTURE_START — the "exit zone" where the fate is decided
const DESPAWN_Y := 320.0           # the fall-off case frees here, below the 270 playfield
const SAFETY_LIFETIME := 12.0      # backstop free if it somehow never reaches the exit zone
const VEL_EPS := 4.0               # below this speed the flame keeps its last heading (no jitter)

var _vel: Vector2 = Vector2.ZERO
var _drift_x: float = 0.0
var _spin_target: float = 0.0
var _spin_cur: float = 0.0
var _t: float = 0.0
var _exit_explode_chance: float = 0.0
var _decided: bool = false
var _done: bool = false
var _torch: Node = null            # EngineTorch (child of the hull) — oriented each frame


# Attach a fresh drift controller to a wreck sprite. `init_vel` (px/s, world) preserves the enemy's
# velocity at death. `seed_i` (a counter) varies spin/drift direction. `exit_explode_chance` decides
# the exit-zone fate. `emit_points` are hull-LOCAL emit positions (engine markers + centre) to pick
# the fire/smoke origin from.
static func attach(sprite: Node2D, init_vel: Vector2, seed_i: int, exit_explode_chance: float, emit_points: Array) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var ctrl := Node.new()
	ctrl.set_script(load("res://scripts/effects/wreck_drift.gd"))
	ctrl.name = "WreckDrift"
	sprite.add_child(ctrl)
	(ctrl as Node)._init_drift(init_vel, seed_i, exit_explode_chance, emit_points)


func _init_drift(init_vel: Vector2, seed_i: int, exit_explode_chance: float, emit_points: Array) -> void:
	var sprite := get_parent()
	if not (sprite is Node2D):
		return
	var s: Node2D = sprite
	var dir: float = 1.0 if (seed_i % 2 == 0) else -1.0
	_spin_target = dir * (SPIN_MIN + randf() * (SPIN_MAX - SPIN_MIN))
	_drift_x = dir * randf_range(3.0, 11.0)
	_vel = init_vel
	_exit_explode_chance = exit_explode_chance
	# Mid-depth recession: smooth scale-down + a subtle darken.
	var tw := s.create_tween()
	tw.tween_property(s, "scale", s.scale * WRECK_SCALE, SCALE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	s.modulate = Color(s.modulate.r * RECEDE_DARKEN, s.modulate.g * RECEDE_DARKEN, s.modulate.b * RECEDE_DARKEN, s.modulate.a)
	# Pick a random emit point (engine marker or hull centre) for the fire + smoke combo.
	var emit: Vector2 = Vector2.ZERO
	if not emit_points.is_empty():
		emit = emit_points[seed_i % emit_points.size()]
	_spawn_tells(s, emit)


# Fire (engine torch, child of the hull, oriented each frame to oppose motion) + dark smoke (parented
# to the wreck LAYER so it can fade after the hull frees), both emitted from `emit_local`.
func _spawn_tells(s: Node2D, emit_local: Vector2) -> void:
	# Fire.
	_torch = EngineTorchScript.attach_to_player(s, emit_local, 0.0)
	if _torch != null and is_instance_valid(_torch):
		_torch.visible = true
		if "_mat" in _torch and _torch._mat != null:
			_torch._mat.set_shader_parameter("size", Vector2(0.4, 1.0))   # full flame
	# Smoke — independent of the hull so it survives + fades after the hull is freed.
	var layer: Node = s.get_parent()
	if layer == null:
		layer = get_tree().current_scene
	var smoke = DamageSmokeScript.new()
	if "activate_below" in smoke:
		smoke.activate_below = 0.0
	if "emit_local" in smoke:
		smoke.emit_local = emit_local
	if "drift_sign" in smoke:
		smoke.drift_sign = -1.0   # trails up/behind a falling hull
	layer.add_child(smoke)
	if smoke.has_method("set_player"):
		smoke.set_player(s)
	smoke._damage_level = 1.0
	smoke._severity = 1.0
	smoke._sample_interval = 0.06


func _process(delta: float) -> void:
	var sprite := get_parent()
	if _done or not (sprite is Node2D) or not is_instance_valid(sprite):
		return
	var s: Node2D = sprite
	_t += delta
	# Curve the preserved velocity into a fall.
	_vel.y = minf(_vel.y + FALL_GRAVITY * delta, FALL_SPEED_MAX)
	_vel.x = lerpf(_vel.x, _drift_x, clampf(LATERAL_DAMP * delta, 0.0, 1.0))
	s.position += _vel * delta
	# Tumble eases in from 0 so the hull keeps its facing for a beat before slowly turning.
	_spin_cur = lerpf(_spin_cur, _spin_target, clampf(SPIN_EASE * delta, 0.0, 1.0))
	s.rotation += _spin_cur * delta
	# Flame burns OPPOSITE the velocity (world-space), independent of the hull's tumble. The torch's
	# flame points world +Y at torch.global_rotation == PI, so to point it along D = (-vel) we need
	# torch.global_rotation = PI/2 + D.angle(); subtract the hull rotation for the child-local value.
	if _torch != null and is_instance_valid(_torch) and _vel.length() >= VEL_EPS:
		var d: Vector2 = (-_vel).normalized()
		_torch.rotation = d.angle() + PI * 0.5 - s.global_rotation
	# Decide the wreck's fate at the exit zone.
	if not _decided and s.global_position.y >= EXIT_ZONE_Y:
		_decided = true
		if randf() < _exit_explode_chance:
			_explode_and_free(s)
			return
	if s.global_position.y > DESPAWN_Y or _t >= SAFETY_LIFETIME:
		_done = true
		s.queue_free()


func _explode_and_free(s: Node2D) -> void:
	_done = true
	ExplosionFx.play(s.global_position, 1.0)   # distance-based sound rides along
	s.queue_free()
