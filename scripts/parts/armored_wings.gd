extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Trades speed for hull. Per mark: -3% speed, +10% hull.
@export var speed_pct_penalty: float = 0.03
# Hull rework 2026-05-17 — hull comes from upgrades now.
@export var hull_bonus: int = 0

var _speed_applied: float = 0.0
var _hull_applied: int = 0

func _init() -> void:
	display_name = "Armored Wing"
	description = "Heavy plating. Slower, but tougher."

func apply(ship) -> void:
	var pct: float = speed_pct_penalty * mark_multiplier()
	_speed_applied = ship.speed * pct
	ship.speed -= _speed_applied
	_hull_applied = int(hull_bonus * mark_multiplier())
	ship.max_hull += _hull_applied
	ship.hull = ship.max_hull

func unapply(ship) -> void:
	ship.speed += _speed_applied
	ship.max_hull -= _hull_applied
	ship.hull = clampi(ship.hull, 0, ship.max_hull)
