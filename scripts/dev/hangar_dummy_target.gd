extends Area2D

# Hangar dummy target. Listens for bullet hits and plays a hit-flash so
# the player can verify cannon damage visually. Never dies; pretends to
# have infinite HP so the test session keeps running.

const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	# Bullets call take_hit on us through the BaseBullet pipeline; we
	# don't need to handle the impact here. The flash is for non-take_hit
	# code paths (impact sprites still spawn via the bullet itself).
	pass


# Bullet pipeline routes here for damage. We swallow it but play the flash
# so the player sees the bullet land. take_hit returns false (not fatal).
func take_hit(damage: int = 1) -> bool:
	if has_node("Sprite2D"):
		HitFlashFx.flash($Sprite2D, HitFlashFx.FLASH_WHITE)
	return false


# Bulwark-shield path checks this. We're not shielded.
func has_meta_bulwark_shielded() -> bool:
	return false
