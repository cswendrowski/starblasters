extends "res://scripts/enemy_core.gd"

# Omni Gunship (privateer). Roman 2026-06-07 divergence rework.
#
# A vector-thrust harasser: it roams the playfield holding a stand-off range
# from the player (movement = "omni", omni_thrust pattern from the roster slot)
# while working two weapons:
#   - TRACERS: fast bullets from the two hull muzzles (MuzzleL/MuzzleR),
#     alternating L/R, aimed at the player, fired in short bursts.
#   - CANNON: slow heavy slugs from the WINGTIP mounts (CannonL/CannonR at
#     x = -8 / +8), fired straight down as area denial.
#
# Was a bespoke EnemyBase sweep-platform that rained ROCKET salvos + gun bursts
# in fixed formations. The rockets + the slow drift/weave/shift/advance role now
# live on the new Rocket variant (enemy_rocket.gd, sharing this scene's launch-
# point rack). This script keeps ONLY the bespoke dual-weapon firing; locomotion
# is the omni movement pattern (mirrors interceptor: enemy_core + custom _process).
#
# Two-frame sprite: frame 0 hull + frame 1 emissive glow (GlowMask). EnemyBase
# installs the damage shader on "Sprite2D" only, so the glow stays bright.

const BULLET_SCENE = preload("res://scenes/projectiles/enemy_bullet.tscn")
const CANNON_SLUG = preload("res://data/bullets/heavy_slug.tres")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

# --- Tracer burst (hull muzzles) ----------------------------------------
const BURST_SIZE     := 5      # tracers per burst
const BURST_DELAY    := 0.1    # seconds between tracers in a burst
const BURST_COOLDOWN := 2.0    # seconds between bursts
const TRACER_SPEED   := 300.0  # px/s

# --- Wingtip cannon -----------------------------------------------------
const CANNON_INTERVAL := 2.4   # seconds between wingtip salvos (both fire together)

var _in_burst: bool = false
var _burst_left: int = 0
var _burst_t: float = 0.0
var _cooldown_t: float = 0.0
var _next_left: bool = true
var _cannon_t: float = 0.0


func _ready() -> void:
	max_health = 12
	bounty_value = 30
	super._ready()
	_cooldown_t = randf_range(0.2, BURST_COOLDOWN)   # desync bursts across a wave
	_cannon_t = randf_range(0.6, CANNON_INTERVAL)


func _process(delta: float) -> void:
	super._process(delta)   # omni movement + offscreen + parallax cycle
	if _dying or _cycling:
		return
	if not _on_playfield():
		return
	_tick_tracers(delta)
	_tick_cannon(delta)


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


# Both wingtip cannons fire a slow heavy slug straight down (area denial).
func _tick_cannon(delta: float) -> void:
	_cannon_t -= delta
	if _cannon_t > 0.0:
		return
	_cannon_t = CANNON_INTERVAL
	for nm in ["CannonL", "CannonR"]:
		var mz := get_node_or_null(nm) as Marker2D
		if mz == null:
			continue
		var b = BULLET_SCENE.instantiate()
		b.variant = CANNON_SLUG
		get_tree().root.add_child(b)
		if b.has_method("start"):
			b.start(mz.global_position, Vector2(0, 1))
		MuzzleFx.play_enemy(mz.global_position, Vector2(0, 1), get_tree().root)
