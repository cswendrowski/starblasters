extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Rocket Pod. Secondary weapon (HARDPOINT_WING). Dumb-fire ordnance —
# fast, straight-line, contact-detonate. Slow cadence balances the high
# per-shot damage; doesn't home, so the player has to lead targets.
#
# Was a CANNON primary; moved to HARDPOINT_WING (Cody 2026-05-19) so it
# supplements a primary blaster instead of replacing one.

@export var bullet_scene: PackedScene
@export var base_damage: int = 2
@export var dmg_per_mark: int = 2
@export var base_cooldown: float = 0.55

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_homing: bool = false


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Rocket Pod"
	description = "Dumb-fire rockets. Heavy hit, lead your shots. Secondary."


func apply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	_prev_bullet_scene = ship.secondary_bullet_scene
	_prev_cooldown = ship.secondary_cooldown
	_prev_damage = ship.secondary_damage
	_prev_homing = ship.secondary_homing
	if bullet_scene != null:
		ship.secondary_bullet_scene = bullet_scene
	ship.secondary_cooldown = base_cooldown
	ship.secondary_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	ship.secondary_homing = false


func unapply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	ship.secondary_bullet_scene = _prev_bullet_scene
	ship.secondary_cooldown = _prev_cooldown
	ship.secondary_damage = _prev_damage
	ship.secondary_homing = _prev_homing
