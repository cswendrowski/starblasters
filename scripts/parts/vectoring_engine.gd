extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var speed_bonus: float = 300.0

var _applied: float = 0.0

func _init() -> void:
	slot_type = Slots.SlotType.ENGINE
	display_name = "Vectoring Engine"
	description = "All-direction thrust. Higher speed than stock."

func apply(ship) -> void:
	_applied = speed_bonus * mark_multiplier()
	ship.speed += _applied

func unapply(ship) -> void:
	ship.speed -= _applied
