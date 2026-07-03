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
const FiringSchedulerC = preload("res://scripts/enemies/firing_scheduler.gd")

var spec: Resource = null
var _weapon = null            # internal Weapon, borrowed for _spawn_bullet + aim helpers (GUN)
var _markers: Array = []
var _cycle: int = 0
var _t: float = 0.0
var _next: float = 2.0
# Trigger-resolution engine shared with enemy_core's hull (roadmap P3.9). Owns the path-phase
# line-crossing + beat-sync state. Note the mount deliberately does NOT auto-populate
# DEFAULT_PATH_PHASES (unlike the hull) — a mount path-fires ONLY when its spec sets fire_path_phases
# explicitly; auto-populating would change every mount's firing behavior. This difference is the
# reason the mount keeps its own `if not spec.fire_path_phases.is_empty()` guard rather than sharing
# an auto-populate config flag.
var _scheduler = FiringSchedulerC.new()


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


# Deterministic fire cadence (firing-consistency pass 2026-07-02, parity with enemy_core._fire_interval).
# Replaces the old per-shot randf_range(min, max): re-rolling every shot made the mount's rhythm wander
# unpredictably. We fire at a FIXED interval — the midpoint of the roster's min/max — for a steady,
# readable cadence. The random spawn-time desync (on_start _t seed) keeps identical mounts from firing in
# perfect lockstep, so the fixed rate doesn't read as robotic. Floor at 0.1s so a degenerate 0/0 can't
# busy-loop the timer.
func _roll_interval() -> float:
	return maxf(0.1, (spec.fire_interval_min + spec.fire_interval_max) * 0.5)


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


# Conditional fire gates shared by cadence + path-phase — the zone/nose gate now lives in the shared
# FiringScheduler (P3.9). _held stays local (it also folds in recycling + the pure-enemy_base
# off-screen fallback, which is mount-host-specific), so the cadence path checks _held THEN gates.
func _gates_pass(enemy) -> bool:
	return _scheduler.gates_pass(enemy, spec.fire_zone_gated, spec.fire_only_on_target, spec.fire_aim_tol_deg)


# Path-phase firing: delegated to the shared FiringScheduler (line-crossing + beat-sync quantize +
# fast-mover departure escape) — the same engine the hull uses. The mount only reaches here when its
# spec set fire_path_phases explicitly (no auto-populate; see _scheduler declaration).
func _tick_path_phases(enemy) -> void:
	_scheduler.tick_path_phases(enemy, spec.fire_path_phases, spec.fire_beat_synced, _do_path_shot.bind(enemy))


# Fire one path-phase shot, re-checking the live guards (the beat-synced path defers the shot, so the
# host may have started dying / left the band by the time it fires). _held covers recycling +
# off-playfield (with the pure-enemy_base fallback); the dying re-check is the P3.9 SAFE unification —
# a pure enemy_base host isn't dying-gated on the deferred beat otherwise.
func _do_path_shot(enemy) -> void:
	if "_dying" in enemy and enemy._dying:
		return
	if _held(enemy):
		return
	if spec.fire_only_on_target and not FiringSchedulerC.nose_on_player(enemy, spec.fire_aim_tol_deg):
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
	var is_burst: bool = spec.burst_interval > 0.0
	for i in n:
		if is_burst and i > 0:
			# Wait ONE interval between consecutive shots. The await is serial (it blocks the loop), so
			# each step already lands burst_interval after the previous shot — multiplying by i here
			# (the old bug) double-counted the elapsed time, stretching the gaps to 0.1/0.2/0.3 instead
			# of a steady 0.1 (Roman 2026-06-29: "2 fast, 1 late, 1 later").
			await enemy.get_tree().create_timer(spec.burst_interval).timeout
			# Bail if the host went away OR is now held (recycling / off the playfield) — a burst that
			# started on-screen must not keep firing into a recycle (Roman 2026-07-01).
			if not is_instance_valid(enemy) or _held(enemy):
				return
		# Re-aim per shot (the player moves between burst shots), then fan if spread is set.
		var dir: Vector2 = _fan(_weapon._aim_dir(enemy), i, n)
		if cycling:
			var m = _markers[_cycle % _markers.size()]   # one cycled marker per shot (alternating MG muzzles)
			_cycle += 1
			_drop_strip(enemy, _weapon._spawn_bullet(enemy, dir, spec.payload, m.global_position), dir)
		else:
			for pos in _all_positions(enemy):            # every marker fires this shot (both cannons)
				_drop_strip(enemy, _weapon._spawn_bullet(enemy, dir, spec.payload, pos), dir)
		# A burst is several distinct shots over time, so each one gets its own fire sound (Roman
		# 2026-06-29). A simultaneous volley (no burst gap) stays a single sound — played once below.
		if is_burst:
			_play_sfx(enemy)
	if not is_burst:
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
	var is_burst: bool = spec.burst_interval > 0.0
	# Mirror _fire_gun: the `count` rockets/missiles are spaced by burst_interval (was a single-frame
	# clump that ignored burst, Roman 2026-06-29). Resolve spawn positions per shot so they follow the
	# moving launcher and CYCLE alternates muzzles per shot.
	for i in n:
		if is_burst and i > 0:
			await enemy.get_tree().create_timer(spec.burst_interval).timeout
			# Bail if the host went away OR is now held (recycling / off the playfield) — a burst that
			# started on-screen must not keep firing into a recycle (Roman 2026-07-01).
			if not is_instance_valid(enemy) or _held(enemy):
				return
		var dir: Vector2 = _fan(Vector2(0, 1), i, n)
		for pos in _spawn_positions(enemy):
			var proj = spec.payload_scene.instantiate()
			if "initial_dir" in proj:
				proj.initial_dir = dir
			world.add_child(proj)
			if proj.has_method("start"):
				proj.start(pos)
			elif proj is Node2D:
				proj.global_position = pos
		if is_burst:
			_play_sfx(enemy)
	if not is_burst:
		_play_sfx(enemy)


# i-th direction in a `n`-wide fan around `base` (no fan when spread_deg==0 or n==1).
func _fan(base: Vector2, i: int, n: int) -> Vector2:
	if spec.spread_deg <= 0.0 or n <= 1:
		return base
	var total: float = deg_to_rad(spec.spread_deg)
	return base.rotated(-total * 0.5 + total / float(n - 1) * float(i))


# Drop gun (spec.no_inertia): undo the velocity-inheritance the firing layer added, so the shot leaves
# at its OWN intended speed regardless of the gun's travel. Mirrors the "Doppler" add in
# shoot_pattern._spawn_bullet (same forward term) — kept in lockstep with it. Duck-typed on
# _last_move_vel: if the firing layer never added inertia, there's nothing to strip.
func _drop_strip(enemy, b, dir: Vector2) -> void:
	if not spec.no_inertia or b == null:
		return
	if "speed" in b and "_last_move_vel" in enemy:
		var fwd: float = maxf(0.0, enemy._last_move_vel.dot(dir))
		if fwd > 0.0:
			b.speed = maxf(b.speed - fwd, 1.0)


func _play_sfx(enemy) -> void:
	var kind: String = "enemy_blaster"
	if spec.payload != null and "enemy_sfx_kind" in spec.payload and String(spec.payload.enemy_sfx_kind) != "":
		kind = String(spec.payload.enemy_sfx_kind)
	var pos = enemy.global_position if enemy is Node2D else null
	EnemySfxC.play(enemy.get_tree().root, pos, kind)
