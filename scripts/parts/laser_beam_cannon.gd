extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Laser Beam. Fast charged bolts — sees great damage on hit but a slower
# cadence than the blaster. Single-target.

@export var bullet_scene: PackedScene
@export var base_damage: int = 3
@export var dmg_per_mark: int = 3
@export var base_cooldown: float = 0.40

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: String = ""

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Laser Beam"
	description = "Charged single-target bolts. Slow but heavy hitting."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = "energy"
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	# Roman, 2026-05-18: laser sounds not yet supplied — clear the SFX
	# kind so player.fire_primary falls through to the legacy ShootSound
	# instead of inheriting whichever cannon was equipped last.
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = ""
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
