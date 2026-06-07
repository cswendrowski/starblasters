extends "res://scripts/enemies/enemy_base.gd"

# Bomblet — small munition released by Cluster / Smart Cluster mines.
# Behavior:
#   - Drifts in a randomized direction (cluster) or homes toward the player
#     when within homing_range (smart).
#   - Damages the player on contact like an enemy bullet, then self-destructs.
#   - Has 1 HP — can be shot down in a single hit.
#   - Off-screen despawn at the bottom of the playfield.
#
# Inherits the standard hit / find_player / died-signal pipeline from
# EnemyBase. Overrides `explode()` so the bomblet detonation uses its
# softer-than-mine VFX + audio.

@export var damage_on_collide: int = 1
# 320×400 res rework — speeds + radii halved.
@export var descent_speed: float = 180.0
@export var lateral_jitter_speed: float = 120.0
@export var jitter_cadence: float = 0.18
@export var lifetime: float = 8.0
const BOMBLET_AVOID_RADIUS := 14.0
const BOMBLET_AVOID_STRENGTH := 140.0
const BOMBLET_NEIGHBOUR_CAP := 4
const BOMBLET_GROUP := "bomblets"
@export var smart: bool = false
@export var homing_accel: float = 360.0
@export var homing_max_speed: float = 180.0
# Smart bomblets only pursue when the player crosses inside this range
# (Roman, 2026-05-18 mine pass: smart bomblet "holds its position in
# space but pursues the player if they come within 16 pixels").
@export var smart_engage_range: float = 100.0
var _smart_engaged: bool = false

var _velocity: Vector2 = Vector2.ZERO
var _lateral_target: float = 0.0
var _jitter_timer: float = 0.0
var _age: float = 0.0
var _pulse_phase: float = 0.0


func _ready() -> void:
	max_health = 1
	is_hazard = true
	bounty_value = 0
	# Roman, 2026-05-17: bomblet size is now a single source of truth.
	# Previously mine_cluster.gd overwrote scale to (3,3) AFTER spawn while
	# the minelayer relied on bomblet's own default — leaving cluster
	# bomblets at 3.0× and minelayer bomblets at a different size. Lock
	# it here at 3.0× and require callers NOT to override.
	display_scale = 1.0
	scale = Vector2(display_scale, display_scale)
	# Bomblets don't have a "forward" — they tumble. Skip auto-rotation
	# and the engine flame; they're not ships.
	auto_rotate = false
	has_ship_vfx = false  # no ground shadow / damage-overlay — bomblets explode, not fray
	wants_outline = false  # mine munitions are projectile-class, excepted
	# Bomblets don't parallax-cycle; they cap at the bottom edge and
	# despawn cleanly. NONE keeps EnemyBase's per-frame check out of the
	# way — this script does its own edge handling for bounce + despawn.
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	_pulse_phase = randf() * TAU
	_velocity = Vector2(randf_range(-32.0, 32.0), descent_speed)
	_lateral_target = randf_range(-lateral_jitter_speed, lateral_jitter_speed)
	add_to_group(BOMBLET_GROUP)


func start(pos: Vector2) -> void:
	position = pos


# Used by the parent mine to seed initial position with a directional kick.
func launch(pos: Vector2, dir: Vector2, speed: float) -> void:
	position = pos
	var nudge: Vector2 = dir.normalized() * speed * 0.35
	_velocity = Vector2(nudge.x, descent_speed + nudge.y * 0.5)
	_lateral_target = nudge.x


func _process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	if _age >= lifetime:
		explode()
		return
	if smart:
		# Smart bomblets hold position until the player crosses the engage
		# range; once engaged they pursue indefinitely (relentless).
		var p := find_player()
		if p and is_instance_valid(p):
			var to_p: Vector2 = p.global_position - global_position
			var d: float = to_p.length()
			if not _smart_engaged and d <= smart_engage_range:
				_smart_engaged = true
			if _smart_engaged and d > 0.1:
				var dir: Vector2 = to_p.normalized()
				_velocity = _velocity.move_toward(dir * homing_max_speed, homing_accel * delta)
			elif not _smart_engaged:
				# Decay velocity so the bomblet holds station.
				_velocity = _velocity.move_toward(Vector2.ZERO, homing_accel * delta * 0.4)
	else:
		_jitter_timer -= delta
		if _jitter_timer <= 0.0:
			_jitter_timer = jitter_cadence * randf_range(0.6, 1.6)
			_lateral_target = randf_range(-lateral_jitter_speed, lateral_jitter_speed)
		_velocity.x = lerp(_velocity.x, _lateral_target, clamp(delta * 5.0, 0.0, 1.0))
		_velocity.y = lerp(_velocity.y, descent_speed, clamp(delta * 2.5, 0.0, 1.0))
	_apply_neighbour_repulsion(delta)
	# Pulse red so it reads as "live munition".
	if has_node("Sprite2D"):
		var t: float = Time.get_ticks_msec() / 1000.0
		var pulse: float = 0.5 + 0.5 * sin(t * 6.0 + _pulse_phase)
		var k: float = 1.0 + 0.9 * pulse
		$Sprite2D.modulate = Color(k, 0.6, 0.55, 1.0)
	position += _velocity * delta
	# Bounce off the playfield band edges (not the 480-px viewport).
	var margin: float = 4.0
	if position.x < Playfield.X_MIN + margin and _velocity.x < 0.0:
		position.x = Playfield.X_MIN + margin
		_velocity.x = -_velocity.x * 0.85
	elif position.x > Playfield.X_MAX - margin and _velocity.x > 0.0:
		position.x = Playfield.X_MAX - margin
		_velocity.x = -_velocity.x * 0.85
	# Despawn off top/bottom — silent leaver.
	if position.y > screensize.y + 24.0 or position.y < -24.0:
		queue_free()


# Bomblets explode silently softer than the parent mine — quieter audio,
# smaller burn — so a salvo of 6 doesn't drown the soundscape.
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# Explosive impact flash (Roman, 2026-05-17 sprite pass) layered on
	# top of the existing fiery explosion for the warhead detonation read.
	var ImpactFxCls = load("res://scripts/effects/impact_fx.gd")
	if ImpactFxCls:
		ImpactFxCls.spawn(get_tree().root, global_position, Color(1.0, 0.55, 0.2, 1.0), 1)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, 1.0)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position, -6.0)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.25)
	await get_tree().create_timer(0.25).timeout
	queue_free()


# One-shot kill — bullet contact is fatal regardless of "non-fatal" path.
func hit() -> void:
	explode()


func _apply_neighbour_repulsion(delta: float) -> void:
	if _dying:
		return
	var checked: int = 0
	var push: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group(BOMBLET_GROUP):
		if other == self or not is_instance_valid(other):
			continue
		var to_self: Vector2 = global_position - other.global_position
		var d: float = to_self.length()
		if d > 0.001 and d < BOMBLET_AVOID_RADIUS:
			var falloff: float = 1.0 - (d / BOMBLET_AVOID_RADIUS)
			push += to_self.normalized() * (BOMBLET_AVOID_STRENGTH * falloff)
		checked += 1
		if checked >= BOMBLET_NEIGHBOUR_CAP:
			break
	if push != Vector2.ZERO:
		_velocity += push * delta


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
