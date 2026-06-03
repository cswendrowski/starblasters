extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var speed_bonus: float = 60.0  # +1 px/frame per Mk (60 px/s)

var _applied: float = 0.0

func _init() -> void:
	slot_type = Slots.SlotType.ENGINE
	max_mark = 6  # +1 px/f per Mk caps at Mk.6 = 8 px/f (readability ceiling)
	display_name = "Vectoring Engine"
	description = "All-direction thrust. Higher speed than stock."

func apply(ship) -> void:
	_applied = speed_bonus * mark_multiplier()
	ship.speed += _applied

func unapply(ship) -> void:
	ship.speed -= _applied
