extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var bullet_scene: PackedScene
@export var base_damage: int = 4
@export var dmg_per_mark: int = 3
@export var base_cooldown: float = 0.28

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_sfx_kind: String = ""

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Heavy Blaster"
	description = "Slow firing, hits hard per shot."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "fire_sfx_kind" in ship:
		_prev_sfx_kind = ship.fire_sfx_kind
		ship.fire_sfx_kind = "blaster_large"
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	ship.cooldown = base_cooldown
	ship.bullet_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown

func unapply(ship) -> void:
	ship.bullet_scene = _prev_bullet_scene
	ship.cooldown = _prev_cooldown
	ship.bullet_damage = _prev_damage
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = _prev_sfx_kind
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown
