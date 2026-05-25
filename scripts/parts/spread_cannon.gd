extends "res://scripts/parts/primary_weapon.gd"

# Spread Cannon. Fans bullets across an arc instead of stacking them
# straight up — classic shmup 3-way / spread weapon. Trades single-target
# DPS for crowd coverage; aim-forgiving against wave formations.
#
# Mk scaling alternates between +1 bullet and +1 damage per Mk so every
# upgrade meaningfully shifts either coverage or per-shot bite:
#   Mk: 1  2  3  4  5  6  7  8  9
#   N : 3  4  4  5  5  6  6  7  7
#   D : 1  1  2  2  3  3  4  4  5
# Formula: count = 3 + (mk / 2), damage = base + (mk - 1) / 2 (int div).

@export var base_bullet_count: int = 3
@export var spread_degrees: float = 30.0


func _init() -> void:
	super._init()
	display_name = "Spread Cannon"
	description = "Fans bullets in a forward arc. Even Mk adds a bullet, odd Mk adds damage."
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
		"bullet_damage": Callable(self, "_damage_for_mark"),
		"cooldown": [base_cooldown, base_cooldown],
		"bullet_spread_count": Callable(self, "_count_for_mark"),
		"bullet_spread_degrees": [spread_degrees, spread_degrees],
	}


func _count_for_mark(at_mark: int) -> int:
	# Mk 1 → 3, Mk 2 → 4, Mk 3 → 4, Mk 4 → 5, ... Mk 9 → 7.
	return base_bullet_count + int(at_mark / 2)


func _damage_for_mark(at_mark: int) -> int:
	# Mk 1 → +0, Mk 2 → +0, Mk 3 → +1, Mk 4 → +1, ... Mk 9 → +4.
	return base_damage + int((at_mark - 1) / 2)


# Editor DPS readout — accounts for bullet count.
func effective_damage(at_mark: int) -> int:
	return _damage_for_mark(at_mark) * _count_for_mark(at_mark)
