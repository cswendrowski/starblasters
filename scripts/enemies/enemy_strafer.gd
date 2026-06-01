extends "res://scripts/enemies/enemy_base.gd"

# Strafer (Roman, 2026-05-31). Chaff fighter that does a head-on pass:
#   1. APPROACH  — enters from the top and homes on the player (intercept
#                  vector), a touch faster than most chaff but slower than
#                  the Dart. auto_rotate banks the sprite along travel.
#   2. FIRE      — once inside fire range (or after an approach timeout so a
#                  juking player can't stall it forever), fires a 6-shot
#                  tracer burst at the MG cannon's base ROF (0.1333s/shot),
#                  alternating between the MuzzleL / MuzzleR markers. Shots
#                  aim along the facing locked at burst start (a committed
#                  head-on pass, not per-shot re-aim).
#   3. VEER+BEELINE — the moment the 6th shot leaves, it banks hard to one
#                  side then bee-lines straight for the bottom of the screen
#                  and exits, like a fighter breaking off the pass.
#
# Bespoke (extends enemy_base directly, bomber-style) because the firing is
# tightly coupled to the locomotion phase (committed head-on pass, locked
# fire direction, veer-on-last-shot) — that timing can't be expressed by the
# stock shoot_pattern helpers. Marker spawning + alternation + the muzzle
# flash DO use the shared enemy_base helpers (next_muzzle_pos / has_muzzles /
# MuzzleFx.play_enemy); only the phase coupling stays bespoke. See CLAUDE.md:
# bespoke is reserved for exactly this kind of multi-phase locomotion.
#
# Markers: MuzzleL / MuzzleR are real Marker2D children — the burst reads
# their LIVE global_position every shot, so Roman can reposition them in the
# scene after push and the shots follow with no code change.

const BulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

enum Phase { APPROACH, FIRE, VEER }

# --- Tunables (first-pass; tune in playtest) ---------------------------
# Approach/beeline speed. Faster than most chaff, slower than the Dart
# (Dart top_dive = 260). 210 per the brief.
@export var travel_speed: float = 210.0
# How sharply the homing heading can turn toward the player during APPROACH
# (deg/sec). Lower = lazier intercept that reads as a committed dive.
@export var approach_turn_rate_deg: float = 140.0
# Begin the burst when this close to the player...
@export var fire_range: float = 150.0
# ...or, failing that, after this many seconds of approach (anti-stall).
@export var approach_timeout: float = 1.6
# 6-shot MG-cannon burst at base ROF.
@export var burst_count: int = 6
@export var burst_interval: float = 0.1333
@export var bullet_speed: float = 300.0   # tracer-style: fast + flat
# Veer: how hard it banks off-axis before committing to the beeline.
@export var veer_speed: float = 240.0
@export var veer_time: float = 0.35

var _phase: int = Phase.APPROACH
var _vel: Vector2 = Vector2(0, 1)
var _approach_t: float = 0.0
var _shots_fired: int = 0
var _shot_timer: float = 0.0
var _fire_dir: Vector2 = Vector2(0, 1)
var _veer_t: float = 0.0
var _veer_dir: Vector2 = Vector2(1, 0)


func _ready() -> void:
	# Stats set directly BEFORE super._ready() (never the `<=0 ? default`
	# idiom — that caused the historical 1-HP bug). Chaff: dies in 1-2 hits,
	# modest bounty, mirrors the Dart/Skirmisher band.
	max_health = 2
	bounty_value = 8
	# One-pass leaver: exit any edge frees it. The veer can carry it out a
	# side, and the beeline carries it out the bottom — both should clean up.
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	auto_rotate = true
	super._ready()
	# Start heading straight down until the first homing step retargets.
	_vel = Vector2(0, 1) * travel_speed


# Wave system calls start(pos) on spawn (mirrors enemy_core's contract).
func start(pos: Vector2) -> void:
	position = pos
	_phase = Phase.APPROACH
	_approach_t = 0.0
	_shots_fired = 0
	_vel = Vector2(0, 1) * travel_speed


func _process(delta: float) -> void:
	if _dying:
		return
	# Cap delta so a hitch can't teleport the strafer a screenful in one step
	# (same guard enemy_core uses).
	var dt: float = min(delta, 1.0 / 30.0)
	match _phase:
		Phase.APPROACH:
			_process_approach(dt)
		Phase.FIRE:
			_process_fire(dt)
		Phase.VEER:
			_process_veer(dt)
	# Base handles offscreen cleanup + sprite auto-rotation (banks the ship
	# along _vel since we move via position += _vel * dt).
	_offscreen_cleanup_check()
	_apply_auto_rotation()


func _process_approach(dt: float) -> void:
	_approach_t += dt
	var player := find_player() as Node2D
	var desired: Vector2 = Vector2(0, 1)
	if player != null:
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length_squared() > 1.0:
			desired = to_p.normalized()
	# Steer the current heading toward the player at a capped turn rate so the
	# intercept reads as a banking dive, not an instant lock.
	var cur: Vector2 = _vel.normalized()
	var max_turn: float = deg_to_rad(approach_turn_rate_deg) * dt
	var turn: float = clampf(cur.angle_to(desired), -max_turn, max_turn)
	cur = cur.rotated(turn)
	_vel = cur * travel_speed
	position += _vel * dt
	# Transition to FIRE on range OR timeout.
	var in_range: bool = player != null \
		and global_position.distance_to(player.global_position) <= fire_range
	if in_range or _approach_t >= approach_timeout:
		_enter_fire()


func _enter_fire() -> void:
	_phase = Phase.FIRE
	_shots_fired = 0
	_shot_timer = 0.0
	# Lock the firing direction now — a committed head-on pass. Aim at the
	# player if present, else straight along current heading.
	var player := find_player() as Node2D
	if player != null:
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length_squared() > 1.0:
			_fire_dir = to_p.normalized()
		else:
			_fire_dir = _vel.normalized()
	else:
		_fire_dir = _vel.normalized()
	# Fire the first shot immediately so the burst starts on phase entry.
	_fire_one()


func _process_fire(dt: float) -> void:
	# Keep drifting forward along the locked fire direction during the burst
	# so the pass keeps moving (a strafing fighter doesn't hover to shoot).
	_vel = _fire_dir * travel_speed
	position += _vel * dt
	if _shots_fired >= burst_count:
		_enter_veer()
		return
	_shot_timer -= dt
	if _shot_timer <= 0.0:
		_fire_one()


func _fire_one() -> void:
	# Alternate MuzzleL/MuzzleR via the shared enemy_base helper, which reads
	# the LIVE marker global_position (repositioning the Marker2D in the scene
	# moves the muzzle with no code change) and cycles its per-instance index
	# so consecutive shots alternate L/R/L/R. Markers are name-sorted, so the
	# first shot fires from MuzzleL — identical to the previous behavior.
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
	# Pink muzzle flash at the firing marker, pointed along the locked dir.
	if has_muzzles():
		MuzzleFx.play_enemy(spawn_pos, _fire_dir, get_tree().root)
	if has_node("EnemyShoot"):
		$EnemyShoot.play()
	_shots_fired += 1
	_shot_timer = burst_interval


func _enter_veer() -> void:
	_phase = Phase.VEER
	_veer_t = 0.0
	# Break off toward whichever side the strafer is already leaning, so the
	# veer continues its momentum rather than snapping back across the player.
	var side: float = 1.0 if _fire_dir.x >= 0.0 else -1.0
	# Veer = mostly sideways, biased downward (it's breaking off toward the
	# bottom exit).
	_veer_dir = Vector2(side, 0.45).normalized()


func _process_veer(dt: float) -> void:
	_veer_t += dt
	if _veer_t < veer_time:
		# Hard bank off-axis.
		_vel = _veer_dir * veer_speed
	else:
		# Committed beeline straight for the bottom of the screen.
		_vel = Vector2(0, 1) * travel_speed
	position += _vel * dt
