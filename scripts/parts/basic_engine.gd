extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var speed_bonus: float = 200.0

var _applied: float = 0.0

func _init() -> void:
	slot_type = Slots.SlotType.ENGINE
	display_name = "Main Engine"
	description = "Stock thrusters. Base maneuvering."

func apply(ship) -> void:
	var bonus := speed_bonus * mark_multiplier()
	ship.speed += bonus
	_applied = bonus

func unapply(ship) -> void:
	ship.speed -= _applied
	_applied = 0.0
