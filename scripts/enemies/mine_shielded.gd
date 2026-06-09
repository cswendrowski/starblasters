extends "res://scripts/enemy_core.gd"

# Shielded Mine (on-lane migration 2026-06-08). Identical to a basic mine once the shield breaks;
# the shield is a per-hit ShieldComponent absorber. Now extends enemy_core + the shared
# StraightDown pattern (conductor-handled, minefield-upgrade prep). The minefield producer doesn't
# inject a movement_override, so the pattern is defaulted here; recycle_passes = 0 frees it off the
# bottom. Explode-on-contact + the shield are unchanged.

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")

@export var drift_speed: float = 120.0
@export var damage_on_collide: int = 2
@export var shield_health: int = 2


func _ready() -> void:
	max_health = 5
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false
	has_ship_vfx = false
	recycle_passes = 0
	# Sit on the shielded frame (skip the F0/F1 activation pageant). Set BEFORE super._ready()
	# so the drop-shadow enemy_core attaches mirrors the shielded frame.
	if has_node("Sprite2D"):
		$Sprite2D.hframes = 3
		$Sprite2D.frame = 2
	# No-regen CHARGE ShieldComponent (its own 24px ring), up from spawn. Appended BEFORE
	# super._ready() so _init_components dups it. Reassign (not append) — shared @export default.
	var sh := ShieldComponent.new()
	sh.capacity = shield_health
	sh.regen_interval = 0.0
	sh.ring_size = 24.0
	components = components + [sh]
	if movement == null:
		var m := StraightDown.new()
		m.speed = drift_speed
		movement = m
	super._ready()


func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	# Free the shield ring instantly so it doesn't linger over the explosion (this explode()
	# doesn't call super.explode(), so fire the component death hook by hand).
	_components_death()
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, 1.0)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
