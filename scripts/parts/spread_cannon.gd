extends "res://scripts/parts/primary_weapon.gd"

# Spread Cannon. Fans bullets across an arc instead of stacking them
# straight up — classic shmup 3-way / spread weapon. Trades single-target
# DPS for crowd coverage; aim-forgiving against wave formations.
#
# Mk scaling: bullet count grows every 2 Mk (coverage), damage is fixed at 2.
#   Mk: 1  2  3  4  5  6  7  8  9
#   N : 3  4  4  5  5  6  6  7  7
#   D : 2  2  2  2  2  2  2  2  2
# Formula: count = 3 + (mk / 2), damage = base_damage (constant).

@export var base_bullet_count: int = 3
@export var spread_degrees: float = 30.0


func _init() -> void:
	super._init()
	display_name = "Spread Cannon"
	description = "Fans bullets in a forward arc. Each pair of Mks adds another bullet."
	# Stats live in resources/weapons/spread_cannon.tres (single source of truth).


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.SPREAD


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


func _damage_for_mark(_at_mark: int) -> int:
	# Fixed damage at all marks — spread's scaling identity is bullet count.
	return base_damage


# Editor DPS readout — accounts for bullet count.
func effective_damage(at_mark: int) -> int:
	return _damage_for_mark(at_mark) * _count_for_mark(at_mark)
