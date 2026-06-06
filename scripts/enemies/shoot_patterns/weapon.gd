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
const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")

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

# Movement axis (homing/wobble) is inherited from shoot_pattern and applied inside
# _spawn_bullet — the weapon-driven homing/wobble that restores boss/enemy
# signatures and that faction/sector multipliers scale.

# Beam config (fire_pattern == BEAM). A beam is CONTINUOUS, not a per-shot fire() —
# enemy_core attaches a BeamEmitter from make_beam_config() instead of arming the
# shoot timer. The shared BeamEmitter owns the visuals/FSM/damage; these are its knobs.
@export_group("Beam")
@export var beam_idle: float = 0.9
@export var beam_windup: float = 1.3
@export var beam_firing: float = 1.1
@export var beam_cooldown: float = 1.5
@export var beam_reach: float = 320.0
@export var beam_dps: float = 3.0
@export var beam_hit_radius: float = 8.0
@export var beam_aim_mode: int = BeamEmitterC.AimMode.LOCAL_FORWARD
@export var beam_cycle: int = BeamEmitterC.Cycle.LOOP_IDLE
@export var beam_emitter_offset: Vector2 = Vector2(0, -8)
@export var beam_forward_local: Vector2 = Vector2(0, -1)
@export var beam_tracking_rate: float = 1.8
@export var beam_sweep_rate: float = 0.0


func is_beam() -> bool:
	return fire_pattern == FirePattern.BEAM


# The BeamEmitter.configure() dict for this weapon's beam. enemy_core uses it to
# attach a per-enemy beam emitter (continuous, so no shoot-timer arming).
func make_beam_config() -> Dictionary:
	return {
		"idle_time": beam_idle, "windup_time": beam_windup, "firing_time": beam_firing,
		"cooldown_time": beam_cooldown, "cycle": beam_cycle, "autostart": true,
		"endpoint": BeamEmitterC.Endpoint.RAY, "aim_mode": beam_aim_mode,
		"forward_local": beam_forward_local, "tracking_rate": beam_tracking_rate,
		"sweep_rate": beam_sweep_rate, "reach": beam_reach, "dps": beam_dps,
		"hit_radius": beam_hit_radius, "emitter_offset": beam_emitter_offset,
		"target_group": "player",
	}


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
	# _spawn_bullet applies the inherited movement axis to the bullet.
	_spawn_bullet(enemy, dir, payload)


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
