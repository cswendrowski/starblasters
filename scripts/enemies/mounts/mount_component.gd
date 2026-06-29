extends EnemyComponent

# Realizes a GUN or LAUNCHER MountSpec (Roman 2026-06-16). Fires the spec's payload from the spec's
# marker(s) on its OWN cadence, so two guns fire independently (the gunship MG+cannon pattern,
# generalized). Rides the component lifecycle: on_start/on_process are fanned out by enemy_base and
# ticked by enemy_core, so no new plumbing. GUN reuses the Weapon spawn helper (free homing/wobble +
# BulletWorld parenting + faction/sector mult-scaling + muzzle flash); LAUNCHER instantiates a
# projectile scene. Holds fire while the enemy is cycling / off-playfield, matching enemy_core's
# generic shoot-timer guards (_dying is already guarded upstream by _tick_components).
#
# Preload-const, NOT class_name (a self-referencing `MountComponent.new()` fails the headless compile
# pass; MountBuilder constructs it via its preload const, and the bench detects it by script-identity).

const WeaponC = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const MountSpecC = preload("res://scripts/enemies/mounts/mount_spec.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")

var spec: Resource = null
var _weapon = null            # internal Weapon, borrowed for _spawn_bullet + aim helpers (GUN)
var _markers: Array = []
var _cycle: int = 0
var _t: float = 0.0
var _next: float = 2.0
var _phase_idx: int = 0          # path-phase firing: next band-progress line to cross
var _beat_fire_at: float = -1.0  # path-phase beat-sync: scheduled global beat for a deferred shot


func on_start(enemy) -> void:
	_resolve_markers(enemy)
	if int(spec.kind) == MountSpecC.Kind.GUN:
		_weapon = WeaponC.new()
		_weapon.bullet_scene = EnemyBullet
		_weapon.payload = spec.payload
		_weapon.aim = int(spec.aim)
		_weapon.lead_factor = spec.lead_factor
		_weapon.bullet_speed = spec.bullet_speed
		_weapon.homing_rate = spec.homing_rate
		_weapon.wobble_amplitude = spec.wobble_amplitude
		_weapon.wobble_frequency = spec.wobble_frequency
	_t = randf_range(0.2, maxf(0.2, spec.fire_interval_max))   # desync, matches the bespoke _ready
	_next = _roll_interval()


func on_process(enemy, delta: float) -> void:
	if _held(enemy):
		return
	# MODE: path-phase firing (fixed band-progress lines) replaces the cadence timer — fires once as
	# the host descends past each fraction, beat-synced into a cross-formation volley.
	if not spec.fire_path_phases.is_empty():
		_tick_path_phases(enemy)
		return
	# MODE: phase-event firing — fires from on_phase() on a named movement phase, not the cadence.
	if String(spec.fire_on_phase) != "":
		return
	_t += delta
	if _t < _next:
		return
	# Conditional gates (zone / nose): hold fire + fast re-poll, mirroring enemy_core's hull shoot.
	if not _gates_pass(enemy):
		_t = 0.0
		_next = 0.15
		return
	_t = 0.0
	_next = _roll_interval()
	_fire(enemy)


# Phase-event firing (spec.fire_on_phase): the host movement entered a named phase; fire if it
# matches, subject to the same zone/nose gates. Fanned in by enemy_core._on_movement_phase_entered.
func on_phase(enemy, phase_name: String) -> void:
	if String(spec.fire_on_phase) == "" or phase_name != String(spec.fire_on_phase):
		return
	if _held(enemy) or not _gates_pass(enemy):
		return
	_fire(enemy)


func _roll_interval() -> float:
	return randf_range(spec.fire_interval_min, maxf(spec.fire_interval_min, spec.fire_interval_max))


# Hold fire while recycling or off the playfield — mirrors enemy_core._on_shoot_timer_timeout.
# enemy_core provides _on_playfield; pure enemy_base enemies (bombers, bulwark) don't, so we fall back
# to an inline off-screen check there too — EVERY mount holds fire until the enemy is on the visible
# playfield (Roman 2026-06-29: enemies shouldn't shoot while well off-screen). Recycling is enemy_core-only.
func _held(enemy) -> bool:
	if "_cycling" in enemy and enemy._cycling:
		return true
	if enemy.has_method("_on_playfield"):
		return not enemy._on_playfield()
	return _off_screen(enemy)


# Inline "off the visible playfield" check for enemies without _on_playfield. Mirrors enemy_core's
# 8px-margin box (X uses the full viewport so the gutters never gate; only the Y edges suppress fire).
func _off_screen(enemy) -> bool:
	if not (enemy is Node2D):
		return false
	const M := 8.0
	var sz: Vector2 = enemy.get_viewport_rect().size
	var p: Vector2 = enemy.position
	return p.x < M or p.x > sz.x - M or p.y < M or p.y > sz.y - M


# Conditional fire gates shared by cadence + path-phase, mirroring enemy_core's hull shoot: hold
# fire outside the engagement band (fire_zone_gated) or until the nose lines up (fire_only_on_target).
func _gates_pass(enemy) -> bool:
	if spec.fire_zone_gated and not Zones.in_engagement(enemy.position.y):
		return false
	if spec.fire_only_on_target and not _nose_on_player(enemy):
		return false
	return true


# Host forward vector within fire_aim_tol_deg of the player direction (sprite faces +Y at rot 0).
func _nose_on_player(enemy) -> bool:
	var player = enemy.find_player() if enemy.has_method("find_player") else null
	if player == null:
		return false
	var to_p: Vector2 = player.global_position - enemy.global_position
	if to_p.length_squared() < 1.0:
		return false
	var rot: float = enemy.rotation - PI * 0.5
	var fwd: Vector2 = Vector2(cos(rot), sin(rot))
	return fwd.dot(to_p.normalized()) >= cos(deg_to_rad(spec.fire_aim_tol_deg))


# Path-phase firing: one shot each time the host descends past the next band-progress fraction,
# optionally quantized to the shared tempo so a descending formation volleys on the same line.
# Mirrors enemy_core._check_path_phase_fire / _do_path_shot.
func _tick_path_phases(enemy) -> void:
	if _beat_fire_at >= 0.0 and Beat.now() >= _beat_fire_at:
		_beat_fire_at = -1.0
		_do_path_shot(enemy)
	if _phase_idx >= spec.fire_path_phases.size():
		return
	if Zones.band_progress(enemy.position.y) < spec.fire_path_phases[_phase_idx]:
		return
	_phase_idx += 1
	if spec.fire_beat_synced:
		var beat_at: float = Beat.next_beat_time(Beat.now())
		var vel_y: float = enemy._last_move_vel.y if "_last_move_vel" in enemy else 0.0
		var predicted_y: float = enemy.position.y + vel_y * maxf(0.0, beat_at - Beat.now())
		if predicted_y >= Zones.DEPARTURE_START:
			_do_path_shot(enemy)
		else:
			_beat_fire_at = beat_at
	else:
		_do_path_shot(enemy)


func _do_path_shot(enemy) -> void:
	if _held(enemy):
		return
	if spec.fire_only_on_target and not _nose_on_player(enemy):
		return
	_fire(enemy)


func _resolve_markers(enemy) -> void:
	_markers = []
	if String(spec.marker) == "":
		return
	for m in enemy.find_children(spec.marker, "Marker2D", true, false):
		_markers.append(m)


# Spawn positions for this volley: matched markers (ALL, or one cycled) or the hull centre.
func _spawn_positions(enemy) -> Array:
	if _markers.is_empty():
		return [enemy.global_position]
	if int(spec.marker_mode) == MountSpecC.MarkerMode.CYCLE:
		var m = _markers[_cycle % _markers.size()]
		_cycle += 1
		return [m.global_position]
	var out: Array = []
	for m in _markers:
		out.append(m.global_position)
	return out


func _fire(enemy) -> void:
	if int(spec.kind) == MountSpecC.Kind.LAUNCHER:
		_fire_launcher(enemy)
	else:
		_fire_gun(enemy)


func _fire_gun(enemy) -> void:
	if _weapon == null:
		return
	var n: int = maxi(1, spec.count)
	var cycling: bool = int(spec.marker_mode) == MountSpecC.MarkerMode.CYCLE and not _markers.is_empty()
	for i in n:
		if spec.burst_interval > 0.0 and i > 0:
			# Wait ONE interval between consecutive shots. The await is serial (it blocks the loop), so
			# each step already lands burst_interval after the previous shot — multiplying by i here
			# (the old bug) double-counted the elapsed time, stretching the gaps to 0.1/0.2/0.3 instead
			# of a steady 0.1 (Roman 2026-06-29: "2 fast, 1 late, 1 later").
			await enemy.get_tree().create_timer(spec.burst_interval).timeout
			if not is_instance_valid(enemy):
				return
		# Re-aim per shot (the player moves between burst shots), then fan if spread is set.
		var dir: Vector2 = _fan(_weapon._aim_dir(enemy), i, n)
		if cycling:
			var m = _markers[_cycle % _markers.size()]   # one cycled marker per shot (alternating MG muzzles)
			_cycle += 1
			_weapon._spawn_bullet(enemy, dir, spec.payload, m.global_position)
		else:
			for pos in _all_positions(enemy):            # every marker fires this shot (both cannons)
				_weapon._spawn_bullet(enemy, dir, spec.payload, pos)
	_play_sfx(enemy)


# All matched marker globals, or the hull centre when there's no marker.
func _all_positions(enemy) -> Array:
	if _markers.is_empty():
		return [enemy.global_position]
	var out: Array = []
	for m in _markers:
		out.append(m.global_position)
	return out


func _fire_launcher(enemy) -> void:
	if spec.payload_scene == null:
		return
	var world: Node = BulletWorld.resolve(enemy, enemy.get_tree().root)
	var n: int = maxi(1, spec.count)
	for pos in _spawn_positions(enemy):
		for i in n:
			var dir: Vector2 = _fan(Vector2(0, 1), i, n)
			var proj = spec.payload_scene.instantiate()
			if "initial_dir" in proj:
				proj.initial_dir = dir
			world.add_child(proj)
			if proj.has_method("start"):
				proj.start(pos)
			elif proj is Node2D:
				proj.global_position = pos
	_play_sfx(enemy)


# i-th direction in a `n`-wide fan around `base` (no fan when spread_deg==0 or n==1).
func _fan(base: Vector2, i: int, n: int) -> Vector2:
	if spec.spread_deg <= 0.0 or n <= 1:
		return base
	var total: float = deg_to_rad(spec.spread_deg)
	return base.rotated(-total * 0.5 + total / float(n - 1) * float(i))


func _play_sfx(enemy) -> void:
	var kind: String = "enemy_blaster"
	if spec.payload != null and "enemy_sfx_kind" in spec.payload and String(spec.payload.enemy_sfx_kind) != "":
		kind = String(spec.payload.enemy_sfx_kind)
	var pos = enemy.global_position if enemy is Node2D else null
	EnemySfxC.play(enemy.get_tree().root, pos, kind)
