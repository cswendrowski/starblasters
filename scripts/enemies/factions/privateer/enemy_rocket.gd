extends "res://scripts/enemy_core.gd"

# Rocket Gunship (privateer). Roman 2026-06-07 — the divergent dupe of the Gunship.
#
# Where the Gunship roams with omni thrust, this hull is a SLOW, deliberate
# presence: its movement comes from the roster slot (drift / weave / shift /
# advance — any of the lane patterns) and it works two weapons off the shared
# gunship marker rack:
#   - ROCKETS: salvos from the launch-point rack (launch_point1..6, cycled),
#     fired downward with a little spread.
#   - TRACERS: fast bullets from the two hull muzzles (MuzzleL/MuzzleR),
#     alternating L/R, aimed at the player, in short bursts.
#
# Only the dual-weapon firing is bespoke; locomotion is the movement pattern
# (mirrors interceptor: enemy_core + custom _process). Two-frame sprite:
# frame 0 hull + frame 1 emissive glow (GlowMask).

const ROCKET_SCENE = preload("res://scenes/projectiles/enemy_rocket.tscn")
const BULLET_SCENE = preload("res://scenes/projectiles/enemy_bullet.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

# --- Rocket salvo -------------------------------------------------------
const SALVO_SIZE     := 3      # rockets per salvo
const SALVO_INTERVAL := 1.8    # seconds between salvos
const ROCKET_SPEED   := 280.0  # px/s (fallback if the rocket has no start())
const ROCKET_SPREAD_DEG := 12.0
const ROCKET_RACK    := 6      # launch_point1..6

# --- Tracer burst (hull muzzles) ----------------------------------------
const BURST_SIZE     := 4
const BURST_DELAY    := 0.12
const BURST_COOLDOWN := 2.4
const TRACER_SPEED   := 300.0

var _salvo_t: float = 0.0
var _next_rocket: int = 0
var _in_burst: bool = false
var _burst_left: int = 0
var _burst_t: float = 0.0
var _cooldown_t: float = 0.0
var _next_left: bool = true


func _ready() -> void:
	max_health = 14
	bounty_value = 35
	super._ready()
	_salvo_t = randf_range(0.5, SALVO_INTERVAL)
	_cooldown_t = randf_range(0.3, BURST_COOLDOWN)


func _process(delta: float) -> void:
	super._process(delta)   # movement pattern + offscreen + parallax cycle
	if _dying or _cycling:
		return
	if not _on_playfield():
		return
	_tick_rockets(delta)
	_tick_tracers(delta)


func _tick_rockets(delta: float) -> void:
	_salvo_t -= delta
	if _salvo_t > 0.0:
		return
	_salvo_t = SALVO_INTERVAL
	for _i in SALVO_SIZE:
		_fire_rocket()


func _fire_rocket() -> void:
	var mz := get_node_or_null("launch_point%d" % (_next_rocket + 1)) as Marker2D
	_next_rocket = (_next_rocket + 1) % ROCKET_RACK
	var pos: Vector2 = mz.global_position if mz else global_position
	var spread: float = deg_to_rad(randf_range(-ROCKET_SPREAD_DEG, ROCKET_SPREAD_DEG))
	var dir: Vector2 = Vector2(0, 1).rotated(spread)
	var r = ROCKET_SCENE.instantiate()
	get_tree().root.add_child(r)
	if r.has_method("start"):
		r.start(pos, dir)
	elif "velocity" in r:
		r.position = pos
		r.velocity = dir * ROCKET_SPEED
	else:
		r.position = pos


# Tracer burst from alternating hull muzzles, aimed at the player.
func _tick_tracers(delta: float) -> void:
	if _in_burst:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_tracer()
			_burst_left -= 1
			if _burst_left <= 0:
				_in_burst = false
				_cooldown_t = BURST_COOLDOWN
			else:
				_burst_t = BURST_DELAY
	else:
		_cooldown_t -= delta
		if _cooldown_t <= 0.0:
			_in_burst = true
			_burst_left = BURST_SIZE
			_burst_t = 0.0


func _fire_tracer() -> void:
	var mz := get_node_or_null("MuzzleL" if _next_left else "MuzzleR") as Marker2D
	_next_left = not _next_left
	var pos: Vector2 = mz.global_position if mz else global_position
	var player := find_player()
	var dir: Vector2 = (player.global_position - pos).normalized() if player else Vector2(0, 1)
	var b = BULLET_SCENE.instantiate()
	b.speed = TRACER_SPEED
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(pos, dir)
	MuzzleFx.play_enemy(pos, dir, get_tree().root)
	if has_node("EnemyShoot"):
		$EnemyShoot.play()
