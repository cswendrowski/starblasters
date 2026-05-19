extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# +5% lateral speed per mark.
@export var speed_pct_per_mark: float = 0.05
# Hull rework 2026-05-17 — hull comes from upgrades now.
@export var hull_bonus: int = 0

var _speed_applied: float = 0.0
var _hull_applied: int = 0

func _init() -> void:
	display_name = "Reactive Wing"
	description = "Lighter alloy; faster turns."

func apply(ship) -> void:
	var pct: float = speed_pct_per_mark * mark_multiplier()
	_speed_applied = ship.speed * pct
	ship.speed += _speed_applied
	_hull_applied = int(hull_bonus * mark_multiplier())
	ship.max_hull += _hull_applied
	ship.hull = ship.max_hull

func unapply(ship) -> void:
	ship.speed -= _speed_applied
	ship.max_hull -= _hull_applied
	ship.hull = clampi(ship.hull, 0, ship.max_hull)
	_speed_applied = 0.0
	_hull_applied = 0
