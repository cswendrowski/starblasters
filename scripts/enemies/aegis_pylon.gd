extends Area2D

# Aegis pylon — destructible turret-node hanging off the Aegis boss. Has
# its own HP, takes hits, emits a signal on destruction, free itself.
# Not a real EnemyBase to avoid the engine flame / parallax shadow / etc
# pipeline — pylons are stationary props attached to the boss.

signal pylon_killed(side: String)

var hp: int = 80
var max_hp: int = 80
var side: String = ""

# True so the wave director doesn't gate clear on these — the boss core
# is the only thing that matters for sector completion.
var is_hazard: bool = true


func take_hit(damage: int = 1) -> bool:
	if hp <= 0:
		return false
	hp -= damage
	if has_node("Sprite2D"):
		var spr := $Sprite2D as Sprite2D
		var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
		HitFlashFx.flash(spr, HitFlashFx.FLASH_WHITE)
	if hp <= 0:
		var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
		ExplosionFx.burst(global_position, 3, 14.0, 0.06)
		pylon_killed.emit(side)
		queue_free()
		return true
	return false
