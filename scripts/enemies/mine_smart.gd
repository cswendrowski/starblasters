extends "res://scripts/enemies/enemy_core.gd"

# Smart Mine (Roman 2026-05-18; on-lane migration 2026-06-08). Drifts straight down (a plain
# medium descent) until the player comes within range, then transitions and flies relentlessly at
# them. Also arms if shot while dormant.
#
# MOVEMENT now on the lane system: the ProximityChase pattern owns drift→proximity→chase and
# emits phase_entered("transition"/"armed") so this script swaps the 3-frame sprite. The contact
# explode + the bullet-hit arm are unchanged. recycle_passes = 0 frees a dormant mine off the
# bottom (a chasing mine homes to the player, so it stays on-screen).
#
# Sprite strip (16×16 ea, 4 frames): F0 dormant, F1/F2 transition (play before it can move/chase),
# F3 active (Roman 2026-06-09).

const ProximityChase = preload("res://scripts/enemies/patterns/proximity_chase.gd")
const MineBlinker = preload("res://scripts/effects/mine_blinker.gd")

@export var drift_speed: float = 180.0     # dormant descent (straight_medium)
@export var chase_accel: float = 360.0
@export var chase_max_speed: float = 180.0
@export var damage_on_collide: int = 2
@export var proximity_trigger: float = 80.0
@export var transition_time: float = 0.18

var _armed: bool = false


func _ready() -> void:
	max_health = 3
	is_hazard = true
	bounty_value = 2
	display_scale = 1.0
	auto_rotate = false
	has_ship_vfx = false
	recycle_passes = 0
	if has_node("Sprite2D"):
		$Sprite2D.hframes = 4
		$Sprite2D.frame = 0
	# Descent = chassis move_speed (ProximityChase drift + chase both read it). Seed from the authored
	# drift_speed when unset; a handed move_speed wins. chase_accel/chase_max_speed are vestigial —
	# ProximityChase derives the chase from move_speed × its own accel ratio. (speed-source pass.)
	if move_speed <= 0.0:
		move_speed = drift_speed
	if movement == null:
		var m := ProximityChase.new()
		m.proximity = proximity_trigger
		m.transition_time = transition_time
		movement = m
	super._ready()
	add_child(MineBlinker.new())   # 2px flashing red centre dot + glow


# The ProximityChase pattern emits these as it activates — swap the sprite frame.
# 4-frame strip: transition plays F1 then F2 across the transition window, armed = F3.
func _on_movement_phase_entered(phase_name: String) -> void:
	if not has_node("Sprite2D"):
		return
	if phase_name == "transition":
		$Sprite2D.frame = 1
		# Advance to the 2nd transition frame partway through the transition window.
		var tw := create_tween()
		tw.tween_interval(maxf(transition_time, 0.0001) * 0.5)
		tw.tween_callback(func(): if is_instance_valid(self) and not _armed and not _dying and has_node("Sprite2D"): $Sprite2D.frame = 2)
	elif phase_name == "armed":
		$Sprite2D.frame = 3
		_armed = true


func hit() -> void:
	# Any bullet hit while dormant arms the mine.
	if _pattern != null and _pattern.has_method("force_activate"):
		_pattern.force_activate()
	if has_node("ParticleHit"):
		$ParticleHit.restart()


func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	_fade_death_overlays()   # drop outline / centre-blink instantly so only the body burns
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# Armed/chasing mines pop with a 2nd jitter blast; dormant a single 1×.
	if _armed:
		ExplosionFx.burst(global_position, 2, 6.0, 0.05)
	else:
		ExplosionFx.play(global_position, 1.0)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/effects/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
