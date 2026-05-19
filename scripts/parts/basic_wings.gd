extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Base structural wing. Hull bonus moved to the outpost "Hull" upgrade
# (Roman, 2026-05-17 design pass) — the player now starts with a flat
# max_hull base and grows it through upgrades, not through wing parts.
# Kept on the part for future tuning hooks; default = 0 = no effect.
@export var hull_bonus: int = 0

var _applied: int = 0

func _init() -> void:
	display_name = "Standard Wing"
	description = "Stock airframe panel. Adds hull."

func apply(ship) -> void:
	var bonus := int(hull_bonus * mark_multiplier())
	ship.max_hull += bonus
	ship.hull = ship.max_hull
	_applied = bonus

func unapply(ship) -> void:
	ship.max_hull -= _applied
	ship.hull = clampi(ship.hull, 0, ship.max_hull)
	_applied = 0
