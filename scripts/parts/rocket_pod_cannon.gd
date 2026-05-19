extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Rocket Pod. Dumb-fire ordnance — fast, straight-line, contact-detonate.
# Slow cadence to balance the high per-shot damage; doesn't home, so the
# player has to lead targets.

@export var bullet_scene: PackedScene
@export var base_damage: int = 2
@export var dmg_per_mark: int = 2
@export var base_cooldown: float = 0.55

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: String = ""

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Rocket Pod"
	description = "Dumb-fire rockets. Heavy hit on impact, lead your shots."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = "energy"
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = "rocket"
	ship.cooldown = base_cooldown
	ship.bullet_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


func unapply(ship) -> void:
	ship.bullet_scene = _prev_bullet_scene
	ship.cooldown = _prev_cooldown
	ship.bullet_damage = _prev_damage
	if "weapon_style" in ship:
		ship.weapon_style = _prev_style
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown
