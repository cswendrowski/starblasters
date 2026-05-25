extends "res://scripts/parts/primary_weapon.gd"

# Spread Cannon. Fans bullets across an arc instead of stacking them
# straight up — classic shmup 3-way / spread weapon. Trades single-target
# DPS for crowd coverage; aim-forgiving against wave formations.
#
# Mk scaling adds bullet count (3 → 5 → 7 → … capped at 9) rather than
# damage per shot, so upgrades feel like "wider net" not "stronger gun".

@export var base_bullet_count: int = 3
@export var bullets_per_mark: int = 2
@export var max_bullets: int = 9
@export var spread_degrees: float = 30.0


func _init() -> void:
	super._init()
	display_name = "Spread Cannon"
	description = "Fans bullets in a forward arc. Higher Mk widens the spread."
	base_damage = 1
	dmg_per_mark = 1
	base_cooldown = 0.30


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.BLASTER_SMALL


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("bullet_spread_count")
	keys.append("bullet_spread_degrees")
	return keys


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [base_damage, base_damage + dmg_per_mark * 8],
		"cooldown": [base_cooldown, base_cooldown],
		"bullet_spread_count": Callable(self, "_count_for_mark"),
		"bullet_spread_degrees": [spread_degrees, spread_degrees],
	}


func _count_for_mark(at_mark: int) -> int:
	return mini(base_bullet_count + (at_mark - 1) * bullets_per_mark, max_bullets)


# Editor DPS readout — accounts for bullet count.
func effective_damage(at_mark: int) -> int:
	var per_bullet: int = base_damage + (at_mark - 1) * dmg_per_mark
	return per_bullet * _count_for_mark(at_mark)
