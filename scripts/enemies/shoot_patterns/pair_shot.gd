extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Twin-muzzle pair (spec "pair_shot = single ×2, twin muzzle", Roman 2026-06-08).
# Fires one bullet STRAIGHT DOWN from each muzzle marker — a parallel side-by-side
# pair, NOT a fan (that's spread_shot). Generalizes to >2 muzzles (one per muzzle).
#
# Fallback when the enemy has fewer than two muzzles: fire a tight parallel pair
# around the single muzzle (or the enemy centre) so the "pair" read is preserved.
# This replaces the old pair_shot.tres, which faked a pair as a 2-bullet 12° spread.

@export var bullet_variant: BulletVariant = null
@export var fallback_offset: float = 3.0   # px half-gap when fewer than 2 muzzles


func fire(enemy) -> void:
	var dir := Vector2(0, 1)
	var muzzles: Array = []
	if enemy.has_method("all_muzzle_pos"):
		muzzles = enemy.all_muzzle_pos()
	if muzzles.size() >= 2:
		for pos in muzzles:
			_spawn_bullet(enemy, dir, bullet_variant, pos)
	else:
		var c: Vector2 = muzzles[0] if muzzles.size() == 1 else enemy.global_position
		_spawn_bullet(enemy, dir, bullet_variant, c + Vector2(-fallback_offset, 0.0))
		_spawn_bullet(enemy, dir, bullet_variant, c + Vector2(fallback_offset, 0.0))
