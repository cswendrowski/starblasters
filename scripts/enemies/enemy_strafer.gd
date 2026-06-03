extends "res://scripts/enemies/enemy_base.gd"

# Strafer (Roman, 2026-05-31; locomotion rebuilt 2026-06-01). A fighter that
# rushes the player, fires a tracer burst AT them, then breaks off and flies to
# safety WITHOUT colliding — recycling up to `max_passes` strafing runs before
# leaving the battle for good. The whole point is the SMOOTH fan of crossing
# arcs in Roman's path diagram, so every heading change is a capped-turn steer
# (rotate the current heading toward a desired heading by at most
# `turn_rate_deg * dt` per frame) — never a hard snap.
#
# Non-collision guarantee (the explicit goal):
#   APPROACH/FIRE steer toward a STRAFE POINT offset laterally beside the
#   player (`strafe_offset` px to a per-instance side), NOT the player itself.
#   The curve therefore carries the strafer PAST the player and out the
#   opposite side — it never aims at the body, so even flying straight it
#   misses. The FIRE transition triggers on range to the PLAYER (well before
#   the strafer reaches the offset point), and during FIRE the AIM is locked at
#   the player while the VELOCITY keeps following the strafe point. So: aim = at
#   player (locked), motion = past player.
#
# Crossing geometry: strafe-side and exit-bias are tied to ENTRY-X (left entry
# → strafe on the player's right + exit right; right entry → mirror), so a
# strafer entering top-left sweeps PAST the player and exits lower-right,
# crossing a right-entry strafer doing the opposite — reproducing the diagram.
#
# Per-instance variety: entry X, strafe-side, offset magnitude, turn rate and
# exit bias are jittered with randf()/randi() so the three diagram paths fan
# out instead of tracing one identical arc. We do NOT call randomize() — the
# global RNG is already auto-seeded at startup, and re-seeding from the clock
# would give same-frame spawns identical params (a conga line).
#
# Bespoke (extends enemy_base directly, bomber-style) because firing is tightly
# coupled to the multi-phase steering. Marker spawning + alternation + the
# muzzle flash use the shared enemy_base helpers (next_muzzle_pos /
# has_muzzles / MuzzleFx.play_enemy). Markers MuzzleL / MuzzleR are real
# Marker2D children read LIVE every shot, so repositioning them in the scene
# moves the muzzles with no code change.

const Playfield = preload("res://scripts/playfield.gd")
const BulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

enum Phase { APPROACH, FIRE, BREAKOFF }

# --- Tunables (first-pass; Roman will tune) ----------------------------
# Travel speed. Faster than chaff, slower than the Dart (top_dive = 260).
@export var travel_speed: float = 240.0
# How sharply the heading can turn toward the desired direction (deg/sec).
# This is what makes the arcs smooth — lower = lazier, wider banks.
@export var turn_rate_deg: float = 160.0
# Begin the burst when this close to the PLAYER (not the strafe point).
@export var fire_range: float = 150.0
# ...or, failing that, after this long in APPROACH (anti-stall vs a juker).
@export var approach_timeout: float = 1.6
# Lateral miss distance: the strafe point sits this far to the side of the
# player. Big enough to clear the player hitbox + sprite so we never ram.
@export var strafe_offset: float = 50.0
# 6-shot MG-cannon burst at base ROF.
@export var burst_count: int = 6
@export var burst_interval: float = 0.1333
@export var bullet_speed: float = 300.0   # tracer-style: fast + flat
# Total attack runs before the strafer leaves the battle entirely. Roman's
# "recycle up to 3 times" is ambiguous (3-total vs 1+3); defaulting to 3
# TOTAL passes — exported so Roman can bump to 4 if he meant 1+3.
@export var max_passes: int = 3

var _phase: int = Phase.APPROACH
var _vel: Vector2 = Vector2(0, 1)
var _approach_t: float = 0.0
var _shots_fired: int = 0
var _shot_timer: float = 0.0
var _fire_dir: Vector2 = Vector2(0, 1)      # locked aim at the player
var _pass_index: int = 0                    # how many runs started so far

# --- Per-instance variety (seeded per pass in _begin_pass) -------------
var _strafe_side: float = 1.0               # +1 = strafe point on player's right
var _inst_offset: float = 50.0              # jittered strafe_offset for this pass
var _inst_turn_rate: float = 160.0          # jittered turn_rate_deg for this pass
var _exit_x: float = 240.0                  # clamped exit waypoint X for BREAKOFF
var _entry_x: float = 240.0                 # this pass's top entry X


func _ready() -> void:
	# Stats set directly BEFORE super._ready() (never the `<=0 ? default`
	# idiom — that caused the historical 1-HP bug). Chaff: dies in 1-2 hits.
	max_health = 2
	bounty_value = 8
	# We manage off-field detection + recycle/free ourselves so the base's
	# cleanup can't free the strafer mid-recycle. NONE makes
	# _offscreen_cleanup_check() a no-op (see enemy_base).
	offscreen_mode = OffscreenMode.NONE
	auto_rotate = true
	super._ready()
	_vel = Vector2(0, 1) * travel_speed


# Wave system calls start(pos) on spawn (mirrors enemy_core's contract). The
# given pos is the first top entry point; subsequent recycles pick a new X.
func start(pos: Vector2) -> void:
	position = pos
	_pass_index = 0
	_entry_x = pos.x
	_begin_pass(true)


func _process(delta: float) -> void:
	if _dying:
		return
	# Cap delta so a hitch can't teleport a screenful in one step.
	var dt: float = min(delta, 1.0 / 30.0)
	match _phase:
		Phase.APPROACH:
			_process_approach(dt)
		Phase.FIRE:
			_process_fire(dt)
		Phase.BREAKOFF:
			_process_breakoff(dt)
	_apply_auto_rotation()
	_check_off_field()


# ---- Pass lifecycle ----------------------------------------------------

# Begin (or restart) a strafing run. `use_current_x` keeps the entry X the wave
# system gave us on the very first pass; recycles pick a fresh spread-out X.
func _begin_pass(use_current_x: bool) -> void:
	_pass_index += 1
	_phase = Phase.APPROACH
	_approach_t = 0.0
	_shots_fired = 0
	_shot_timer = 0.0

	if not use_current_x:
		# Reposition to a NEW top entry, spread across the playfield top, just
		# above the top edge. Off-screen transit = the fighter circling back.
		var span: float = Playfield.X_MAX - Playfield.X_MIN
		_entry_x = Playfield.X_MIN + 20.0 + randf() * (span - 40.0)
		position = Vector2(_entry_x, -14.0 - randf() * 10.0)
		# Re-init auto-rotation so the bottom→top teleport delta doesn't cause
		# one frame of the sprite snapping to a wrong heading (it derives
		# rotation from position delta, not _vel).
		_rot_init = false
		_last_position = position

	# Crossing geometry: strafe-side keyed to entry X. Entering on the LEFT
	# half → strafe point on the player's RIGHT (+1) so the arc sweeps across
	# to exit right; entering RIGHT → mirror. A small random flip keeps it from
	# being perfectly deterministic without breaking the cross most of the time.
	var left_half: bool = _entry_x < Playfield.CENTER.x
	_strafe_side = 1.0 if left_half else -1.0
	if randf() < 0.2:
		_strafe_side = -_strafe_side
	# Per-pass jitter so paths fan out.
	_inst_offset = strafe_offset + randf_range(-12.0, 16.0)
	_inst_turn_rate = turn_rate_deg + randf_range(-30.0, 30.0)

	# Heading starts straight down; the first steer step bends it toward the
	# strafe point.
	_vel = Vector2(0, 1) * travel_speed


# The strafe point: beside the player on this pass's side. Falls back to a
# point below us when there's no player (standalone scene boot), so APPROACH
# still flies down the screen and the phases still advance.
func _strafe_point() -> Vector2:
	var player := find_player() as Node2D
	if player == null:
		return global_position + Vector2(0, 200)
	return player.global_position + Vector2(_strafe_side * _inst_offset, 0.0)


# Capped-turn steer: rotate current heading toward `desired` by at most
# turn_rate*dt, return the new velocity at travel_speed.
func _steer(desired: Vector2, dt: float) -> Vector2:
	var cur: Vector2 = _vel.normalized()
	if cur.length_squared() < 0.001:
		cur = Vector2(0, 1)
	var want: Vector2 = desired
	if want.length_squared() < 0.001:
		want = cur
	else:
		want = want.normalized()
	var max_turn: float = deg_to_rad(_inst_turn_rate) * dt
	var turn: float = clampf(cur.angle_to(want), -max_turn, max_turn)
	return cur.rotated(turn) * travel_speed


func _process_approach(dt: float) -> void:
	_approach_t += dt
	var target: Vector2 = _strafe_point()
	_vel = _steer(target - global_position, dt)
	position += _vel * dt
	# Transition to FIRE on range to the PLAYER (or timeout). Range is checked
	# against the player, while steering targets the offset strafe point — so
	# we trip fire_range well before reaching the strafe point and never close
	# to collision distance.
	var player := find_player() as Node2D
	var in_range: bool = player != null \
		and global_position.distance_to(player.global_position) <= fire_range
	if in_range or _approach_t >= approach_timeout:
		_enter_fire()


func _enter_fire() -> void:
	_phase = Phase.FIRE
	_shots_fired = 0
	_shot_timer = 0.0
	# Lock the AIM direction at the player now (so shots don't spin wildly as
	# we keep moving). Motion stays on the strafe point — decoupled.
	var player := find_player() as Node2D
	if player != null:
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length_squared() > 1.0:
			_fire_dir = to_p.normalized()
		else:
			_fire_dir = _vel.normalized()
	else:
		_fire_dir = _vel.normalized()
	# First shot on phase entry.
	_fire_one()


func _process_fire(dt: float) -> void:
	# Keep steering toward the SAME strafe point so the flight continues PAST
	# the player while the burst plays — aim is locked (_fire_dir), motion is
	# not.
	var target: Vector2 = _strafe_point()
	_vel = _steer(target - global_position, dt)
	position += _vel * dt
	if _shots_fired >= burst_count:
		_enter_breakoff()
		return
	_shot_timer -= dt
	if _shot_timer <= 0.0:
		_fire_one()


func _fire_one() -> void:
	# Alternate MuzzleL/MuzzleR via the shared enemy_base helper (reads LIVE
	# marker global_position, cycles per-instance index → L/R/L/R). Shots fly
	# along the locked aim dir, NOT the current motion dir.
	var spawn_pos: Vector2 = next_muzzle_pos() if has_muzzles() else global_position
	var b = BulletScene.instantiate()
	if "speed" in b:
		b.speed = bullet_speed
	# Spawn under root so the bullet survives the strafer's queue_free.
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(spawn_pos, _fire_dir)
	else:
		b.global_position = spawn_pos
	# Pink muzzle flash at the firing marker, pointed along the locked aim.
	if has_muzzles():
		MuzzleFx.play_enemy(spawn_pos, _fire_dir, get_tree().root)
	if has_node("EnemyShoot"):
		$EnemyShoot.play()
	_shots_fired += 1
	_shot_timer = burst_interval


func _enter_breakoff() -> void:
	_phase = Phase.BREAKOFF
	# Exit waypoint: down + low, biased toward the side we're already heading
	# (continuing the strafe-side momentum), clamped INSIDE the playfield so the
	# seek target is never past a wall. The capped-turn seek toward this
	# clamped point produces the diagram's "bend before the wall" naturally.
	var exit_side: float = _strafe_side
	var raw_x: float = Playfield.CENTER.x + exit_side * (Playfield.W * 0.5 + 60.0)
	# Clamp with a margin so the strafer banks away before the actual wall.
	_exit_x = clampf(raw_x, Playfield.X_MIN + 18.0, Playfield.X_MAX - 18.0)
	# Small per-pass jitter on the exit X for variety.
	_exit_x = clampf(_exit_x + randf_range(-20.0, 20.0), Playfield.X_MIN + 14.0, Playfield.X_MAX - 14.0)


func _process_breakoff(dt: float) -> void:
	# Seek the exit waypoint below the bottom edge.
	var target: Vector2 = Vector2(_exit_x, Playfield.Y_MAX + 80.0)
	var desired: Vector2 = target - global_position
	_vel = _steer(desired, dt)
	# Gentle wall-repulsion nudge ONLY when very close to a side wall, so a
	# strafer that drifted toward the edge eases back. Kept small (a velocity
	# bias, re-normalized to travel_speed) so it never fights the seek hard
	# enough to jitter and break smoothness.
	var wall_zone: float = 26.0
	if global_position.x < Playfield.X_MIN + wall_zone:
		var push_l: float = (Playfield.X_MIN + wall_zone - global_position.x) / wall_zone
		_vel = (_vel + Vector2(push_l * 110.0, 0.0)).normalized() * travel_speed
	elif global_position.x > Playfield.X_MAX - wall_zone:
		var push_r: float = (global_position.x - (Playfield.X_MAX - wall_zone)) / wall_zone
		_vel = (_vel - Vector2(push_r * 110.0, 0.0)).normalized() * travel_speed
	position += _vel * dt


# Pass-1 APPROACH/FIRE still gates (first engagement matters). Once it
# breaks off pass 1 (BREAKOFF) or starts any recycle pass (_pass_index>=2),
# it's disengaging/looping and must not stall the next wave.
func is_recycling() -> bool:
	return _phase == Phase.BREAKOFF or _pass_index >= 2


# ---- Off-field detection + recycle/free --------------------------------

# We own this (offscreen_mode == NONE). Generous margin so on-screen wobble
# never trips it. Off the bottom OR fully past a side ends a pass.
func _check_off_field() -> void:
	if _dying:
		return
	var sz: Vector2 = get_viewport_rect().size
	var margin: float = 40.0
	var off: bool = global_position.y > sz.y + margin \
		or global_position.x < -margin \
		or global_position.x > sz.x + margin
	# Don't end a pass while still entering from the top.
	if global_position.y < -margin and _phase == Phase.APPROACH:
		return
	if not off:
		return
	if _pass_index < max_passes:
		# RECYCLE: re-enter from the top for another run.
		_begin_pass(false)
	else:
		# Final pass done — leave the battle (queue_free, no false `died`).
		_leave()
