extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

# Energy Blaster. Default ship-issued primary cannon. Blue energy bolts,
# infinite ammo, modest damage.
# Roman, 2026-05-18 balance: blaster reference weapon.
# Mk.1=2, +2/Mk → Mk.9=18.
@export var bullet_scene: PackedScene
@export var base_damage: int = 2
@export var dmg_per_mark: int = 2
# Energy blaster cadence — slower than the machinegun so each shot reads.
@export var base_cooldown: float = 0.22

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: int = WS.WeaponStyle.ENERGY

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Energy Blaster"
	description = "Standard issue energy cannon. Unlimited ammo."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = WS.WeaponStyle.ENERGY
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = WS.FireSfxKind.BLASTER_SMALL
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
	if "weapon_style" in ship:
		ship.weapon_style = _prev_style
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown
