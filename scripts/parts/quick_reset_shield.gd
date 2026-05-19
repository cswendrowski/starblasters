extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Shield variants are dormant after the 2026-05-17 charge-pool rework.
# Shield charges + recharge now live on the player base + outpost
# upgrades. Kept as a stub so the part catalog still rolls something
# clearly-typed in the SHIELD slot.
@export var shield_bonus: int = 0
@export var regen_bonus: int = 0


func _init() -> void:
	slot_type = Slots.SlotType.SHIELD
	display_name = "Quick-Reset Shield"
	description = "Cosmetic stub — shield is driven by upgrades now."


func apply(_ship) -> void:
	pass


func unapply(_ship) -> void:
	pass
