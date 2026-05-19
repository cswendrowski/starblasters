extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Shield rework 2026-05-17 — capacity comes from upgrades now.
@export var shield_bonus: int = 0

var _applied: int = 0

func _init() -> void:
	slot_type = Slots.SlotType.SHIELD
	display_name = "Reinforced Shield"
	description = "+40% capacity over stock. Slow to recharge."

func apply(ship) -> void:
	_applied = int(shield_bonus * mark_multiplier())
	ship.max_shield += _applied
	ship.shield = ship.max_shield

func unapply(ship) -> void:
	ship.max_shield -= _applied
	ship.shield = clampi(ship.shield, 0, ship.max_shield)
