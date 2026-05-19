extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Shield bonus moved to outpost "Shield Capacity" upgrade (Roman,
# 2026-05-17). Shield is now a charge pool with starting max=3 and grows
# via upgrades, not parts. Default 0 = no effect; kept for tuning hooks.
@export var shield_bonus: int = 0

var _applied: int = 0

func _init() -> void:
	slot_type = Slots.SlotType.SHIELD
	display_name = "Standard Shield"
	description = "Stock deflector array."

func apply(ship) -> void:
	var bonus := int(shield_bonus * mark_multiplier())
	ship.max_shield += bonus
	ship.shield = ship.max_shield
	_applied = bonus

func unapply(ship) -> void:
	ship.max_shield -= _applied
	ship.shield = clampi(ship.shield, 0, ship.max_shield)
	_applied = 0
