extends "res://scripts/enemies/mine_base.gd"

# Shielded Mine (on-lane migration 2026-06-08; 4-frame activation 2026-06-09). Identical to a basic
# mine once the shield breaks; the shield is a per-hit ShieldComponent absorber. Extends enemy_core
# + the shared StraightDown pattern. recycle_passes = 0 frees it off the bottom.
#
# Sprite strip (16×16 ea, 4 frames): F0 dormant, F1/F2 transition, F3 active. The mine spawns
# DORMANT + UNSHIELDED, plays the F0→F3 transition over `activate_time`, then the shield ACTIVATES
# at F3 — a brief window to kill it before it shields (Roman 2026-06-09).

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const MineBlinker = preload("res://scripts/effects/mine_blinker.gd")

@export var drift_speed: float = 120.0
@export var damage_on_collide: int = 2
@export var shield_health: int = 2
@export var activate_time: float = 0.5   # F0→F3 transition before the shield raises


func _ready() -> void:
	max_health = 5
	bounty_value = 0
	# Shared hazard flags + Ordnance-Disposal bounty bonus land in mine_base.super._ready() (below).
	# Start DORMANT on F0 (unshielded). Set BEFORE super._ready() so the drop-shadow mirrors it.
	if has_node("Sprite2D"):
		$Sprite2D.hframes = 4
		$Sprite2D.frame = 0
	# No-regen CHARGE ShieldComponent (its own 24px ring), DOWN at spawn — raise_shield() at F3.
	var sh := ShieldComponent.new()
	sh.capacity = shield_health
	sh.regen_interval = 0.0
	sh.ring_size = 24.0
	sh.start_inactive = true
	components = components + [sh]
	# Descent = chassis move_speed (StraightDown reads it). Seed from the authored drift_speed when
	# unset so it descends at the written rate instead of the pattern's 180 fallback; a handed
	# move_speed wins. (speed-source pass, option B.)
	if move_speed <= 0.0:
		move_speed = drift_speed
	if movement == null:
		var m := StraightDown.new()
		movement = m
	super._ready()
	add_child(MineBlinker.new())   # 2px flashing red centre dot + glow
	_begin_activation()


# Animate F0→F1→F2→F3 over activate_time, then raise the shield at F3.
func _begin_activation() -> void:
	var step: float = maxf(activate_time, 0.0001) / 3.0
	var tw := create_tween()
	tw.tween_interval(step)
	tw.tween_callback(func(): _set_mine_frame(1))
	tw.tween_interval(step)
	tw.tween_callback(func(): _set_mine_frame(2))
	tw.tween_interval(step)
	tw.tween_callback(_activate_shield)


func _set_mine_frame(f: int) -> void:
	if not _dying and has_node("Sprite2D"):
		$Sprite2D.frame = f


func _activate_shield() -> void:
	if _dying:
		return
	_set_mine_frame(3)
	for c in _components:
		if c is ShieldComponent:
			c.raise_shield()
			break


func explode() -> void:
	# Free the shield ring instantly so it doesn't linger over the explosion. The post-dying
	# callback lets us fire the component death hook after _dying is set (intentional for shield cleanup).
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	await _mine_explode_sequence(
		func(): ExplosionFx.play(global_position, 1.0),
		Callable(),   # no pre-dying callback
		func(): _components_death()   # post-dying: free the shield ring
	)


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
