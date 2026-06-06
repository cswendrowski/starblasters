extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Unified Weapon resource (M6a.2) — the single, swappable firing identity any enemy
# can carry. Evolves shoot_pattern into one resource owning the volley SHAPE
# (fire_pattern), the PAYLOAD (a BulletVariant), the RATE (the inherited
# fire_interval_min/max — the single source), and the AIM. The movement axis
# (homing/wobble) is driven here onto each spawned bullet, so it's weapon-tunable
# (and faction/sector can multiply it) rather than baked per-variant.
#
# Referenced via preload (NOT a global class_name): a new class_name isn't registered
# in headless --script runs until the class cache regenerates. Preload is the
# codebase convention for pattern dependencies (see enemy_roster).
#
# The behavior (movement pattern) still owns fire TIMING (path-phase / on-hold /
# timer in enemy_core); the weapon owns fire CONTENT. Any behavior × any weapon.

const Playfield = preload("res://scripts/playfield.gd")

enum FirePattern { SINGLE, AIMED, SPREAD, BURST, BEAM, LOB }
enum Aim { STRAIGHT_DOWN, TOWARD_CENTER, AT_PLAYER }

@export var fire_pattern: FirePattern = FirePattern.SINGLE
@export var payload: BulletVariant = null
@export var aim: Aim = Aim.STRAIGHT_DOWN
@export var lead_factor: float = 0.0          # AT_PLAYER velocity lead
@export var aim_angle_deg: float = 30.0       # TOWARD_CENTER diagonal angle

@export_group("Spread")
@export var spread_count: int = 3
@export var spread_degrees: float = 30.0

@export_group("Burst")
@export var burst_count: int = 3
@export var burst_interval: float = 0.12

# Projectile-movement axis (M6a.2). >0 overrides the payload variant's movement on
# every spawned bullet — the weapon-driven homing/wobble that restores boss/enemy
# signatures and that faction/sector multipliers scale.
@export_group("Movement axis")
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0


func fire(enemy) -> void:
	match fire_pattern:
		FirePattern.SINGLE:
			_fire_bullet(enemy, _aim_dir(enemy))
		FirePattern.AIMED:
			_fire_bullet(enemy, _aim_at_player(enemy, lead_factor))
		FirePattern.SPREAD:
			_fire_spread(enemy)
		FirePattern.BURST:
			_fire_burst(enemy)
		FirePattern.BEAM:
			pass  # continuous — driven by tick() (beam fold, later sub-step)
		FirePattern.LOB:
			pass  # deferred payload
		_:
			_fire_bullet(enemy, _aim_dir(enemy))


# Base fire direction for the non-AT_PLAYER shapes.
func _aim_dir(enemy) -> Vector2:
	match aim:
		Aim.AT_PLAYER:
			return _aim_at_player(enemy, lead_factor)
		Aim.TOWARD_CENTER:
			var sign_x: float = -1.0 if enemy.global_position.x > Playfield.CENTER.x else 1.0
			return Vector2(0, 1).rotated(deg_to_rad(aim_angle_deg) * sign_x)
		_:
			return Vector2(0, 1)


func _fire_bullet(enemy, dir: Vector2) -> void:
	var b = _spawn_bullet(enemy, dir, payload)
	_apply_axis(b)


func _fire_spread(enemy) -> void:
	var base_dir: Vector2 = _aim_dir(enemy)
	var n: int = maxi(1, spread_count)
	if n == 1:
		_fire_bullet(enemy, base_dir)
		return
	var total: float = deg_to_rad(spread_degrees)
	var step: float = total / float(n - 1)
	var start: float = -total * 0.5
	for i in n:
		_fire_bullet(enemy, base_dir.rotated(start + step * float(i)))


func _fire_burst(enemy) -> void:
	var dir: Vector2 = _aim_dir(enemy)
	_fire_bullet(enemy, dir)
	for i in range(1, maxi(1, burst_count)):
		await enemy.get_tree().create_timer(burst_interval).timeout
		if not is_instance_valid(enemy):
			return
		_fire_bullet(enemy, dir)


# Drive the projectile-movement axis onto a freshly spawned bullet. Only overrides
# when the weapon specifies a value (>0), so a payload variant's own movement is
# preserved when the weapon leaves the axis at 0.
func _apply_axis(b) -> void:
	if b == null:
		return
	if homing_rate > 0.0 and "homing_rate" in b:
		b.homing_rate = homing_rate
	if wobble_amplitude > 0.0 and "wobble_amplitude" in b:
		b.wobble_amplitude = wobble_amplitude
		b.wobble_frequency = wobble_frequency
