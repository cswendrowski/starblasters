extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Tail formerly drove `shield_regen` (charges-per-tick). Shield is now a
# charge pool with timed recharge driven by the outpost "Shield Recharge"
# upgrade (Roman, 2026-05-17). Default tail is a no-op for now.
@export var shield_regen_bonus: int = 0

var _applied: int = 0

func _init() -> void:
	slot_type = Slots.SlotType.TAIL
	display_name = "Stabilizer Tail"
	description = "Houses shield capacitors; cosmetic until upgrades land."

func apply(_ship) -> void:
	_applied = 0

func unapply(_ship) -> void:
	_applied = 0
