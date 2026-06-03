extends "res://scripts/projectiles/base_bullet.gd"

# Multi-hit wave projectile. Drills through several enemies in one pass
# instead of detonating on first contact. Inherits the unified hit
# pipeline from BaseBullet; the only override is _finish_hit, which
# tracks "which enemies have already been hit" and only kills the bullet
# once the per-bullet budget is spent.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")

# Roman, 2026-05-18 weapon balance: 5 -> 3 so wave can't drill through
# a whole boss formation in a single shot.
@export var max_hits: int = 3

var _hit: Dictionary = {}
var _hits_left: int = 0


func _init() -> void:
	target_group = "enemies"
	velocity_dir = Vector2(0, -1)
	speed = 120.0


func _ready() -> void:
	super._ready()
	_hits_left = max_hits


func _apply_visuals() -> void:
	# Subtle shader halo, color auto-derived from the wave sprite. Replaces
	# both the old scene "Glow" children and the procedural GlowFX halo.
	GlowShaderFx.apply_to_host(self)


# Override the per-hit consumption: skip enemies we've already tagged,
# decrement the hit budget instead of dying on first contact. Bulwark
# shielded enemies are handled by BaseBullet — the wave fizzles too.
func _on_area_entered(area: Area2D) -> void:
	if _killed or area == null:
		return
	if not area.is_in_group(target_group):
		return
	if area.has_meta("bulwark_shielded"):
		# Shielded enemies don't consume the wave's hit budget — wave
		# slides off and keeps going to find a non-shielded target.
		return
	var id := area.get_instance_id()
	if _hit.has(id):
		return
	_hit[id] = true
	_apply_enemy_hit(area)


# Inside BaseBullet._apply_enemy_hit the default _finish_hit runs after
# damage is applied. Override it to NOT kill the bullet — just decrement
# the budget and only die once we've spent it.
func _finish_hit(_target: Node) -> void:
	_hits_left -= 1
	if _hits_left <= 0:
		_kill()
