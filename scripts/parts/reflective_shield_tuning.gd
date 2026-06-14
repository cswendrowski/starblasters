extends "res://scripts/parts/module_part.gd"

# Reflective Shield Tuning — offensive-defensive Module (2026-06-14). Like ablative
# plating's rhythm, but for the shield: every Nth bullet your shield absorbs is bounced
# back into the playfield as a player bolt aimed at the nearest enemy. The counter lives
# on player.gd (`_reflect_hit_count`, reset in start()); the reflected bolt reuses your
# primary's bullet scene + damage. Mk lowers N (more reflects): every 6th at Mk.1 down to
# every 2nd at Mk.9.
# Default-safe: module_reflect_n stays 0 (off) unless equipped.

@export var base_n: int = 6     # Mk.1 = reflect every 6th absorbed bullet
@export var min_n: int = 2      # floor at high Mk

var _applied_n: int = 0


func _init() -> void:
	super._init()
	module_id = "reflective_shield"
	display_name = "Reflective Shield Tuning"
	description = "Every Nth bullet your shield absorbs is reflected back into the playfield at the nearest enemy. Mk reflects more often — every 6th hit down to every 2nd."


func apply(ship) -> void:
	_applied_n = _n_for(int(mark))
	# Best-wins: a lower N reflects more often. Treat ship's 0 as "off" so we don't
	# min() down to the no-op sentinel.
	if ship.module_reflect_n <= 0:
		ship.module_reflect_n = _applied_n
	else:
		ship.module_reflect_n = mini(ship.module_reflect_n, _applied_n)


func unapply(ship) -> void:
	ship.module_reflect_n = 0
	_applied_n = 0


func _n_for(at_mark: int) -> int:
	return maxi(min_n, base_n - (at_mark - 1) / 2)


# Editor readout — the N (reflect every Nth) at this Mk.
func effective_damage(at_mark: int) -> int:
	return _n_for(at_mark)
