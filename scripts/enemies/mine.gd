extends "res://scripts/enemies/enemy_core.gd"

# Basic mine (Roman 2026-05-18; on-lane migration 2026-06-08). Drifts straight down, explodes on
# player contact. Now extends enemy_core and moves via the shared StraightDown pattern so the
# conductor handles it like any other formation (minefield-upgrade prep). The minefield producer
# does NOT inject a movement_override, so the pattern is defaulted here. recycle_passes = 0 makes
# it FREE off the bottom (no parallax fly-back). Explode-on-contact is unchanged.

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const MineBlinker = preload("res://scripts/effects/mine_blinker.gd")
const LateralDrift = preload("res://scripts/enemies/patterns/lateral_drift.gd")

@export var drift_speed: float = 120.0
@export var damage_on_collide: int = 2
# Lateral drift mode (Roman 2026-06-23). Default "straight" keeps the StraightDown descent (the
# minefield is unchanged). The conductor can set "drift_lane"/"drift_adjacent"/"drift_all" to swap
# in the shared LateralDrift through the movement slot — mines reusing the asteroid drift modes.
@export var drift_mode: String = "straight"
# Hull HP, overridable per scene so variants reuse this script: basic = 2, the
# Armored mine (enemy_mine_armored.tscn) sets 4. Set BEFORE super._ready().
@export var hull_hp: int = 2


func _ready() -> void:
	max_health = hull_hp
	is_hazard = true
	bounty_value = 1
	display_scale = 1.0
	auto_rotate = false       # mines don't have a "forward"
	has_ship_vfx = false      # no engine flame / damage-overlay — mines explode, not fray
	recycle_passes = 0        # off the bottom = free, never parallax-cycle
	if movement == null:
		var m := StraightDown.new()
		movement = m
	# A drift_mode (set by the conductor before add_child) swaps the descent for a confined wander.
	# "straight"/"" leaves the StraightDown above untouched.
	if drift_mode == "drift_lane" or drift_mode == "drift_adjacent" or drift_mode == "drift_all":
		var ld := LateralDrift.new()
		ld.mode = LateralDrift.mode_from_key(drift_mode)
		movement = ld
	super._ready()
	add_child(MineBlinker.new())   # 2px flashing red centre dot + glow


func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()


# Mine-specific death VFX — larger explosion + sfx + burn — overrides EnemyBase.explode.
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	_fade_death_overlays()   # drop glow-mask / outline / centre-blink instantly so only the body burns
	# Single circle explosion (Roman 2026-06-11) — not the fiery default blast.
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, 1.0, true, null, ExplosionFx.scene_for("small_circle"))
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
