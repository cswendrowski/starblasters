extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Rotary Laser Cannon. Minigun-style energy weapon — blistering rate of fire
# (20 shots/sec), limited ammo (300 base), recharges at 10 shots/sec when not
# firing. Pairs with the "rotary_laser" weapon_style branch in player.gd.
@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var dmg_per_mark: int = 1
@export var base_cooldown: float = 0.05
@export var base_ammo: int = 300
@export var ammo_recharge_rate: float = 10.0

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: String = ""
var _prev_ammo_recharge_rate: float = 0.0
var _prev_ammo_max: int = 0

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Rotary Laser"
	description = "Rapid-fire energy cannon. 300 ammo base; recharges when not firing."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	ship.cooldown = base_cooldown
	ship.bullet_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = "rotary_laser"
	# Record and set ammo recharge rate.
	if "ammo_recharge_rate" in ship:
		_prev_ammo_recharge_rate = ship.ammo_recharge_rate
		ship.ammo_recharge_rate = ammo_recharge_rate
	if "ammo_max" in ship:
		_prev_ammo_max = ship.ammo_max
		ship.ammo_max = base_ammo
	# Seed ammo from Run snapshot so ammo persists across scenes.
	if ship.has_method("set_ammo"):
		var seeded: int = base_ammo
		if ship.has_node("/root/Run"):
			var run = ship.get_node("/root/Run")
			if "ammo" in run and int(run.ammo) > 0:
				seeded = int(run.ammo)
		ship.set_ammo(seeded)
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


func unapply(ship) -> void:
	ship.bullet_scene = _prev_bullet_scene
	ship.cooldown = _prev_cooldown
	ship.bullet_damage = _prev_damage
	if "weapon_style" in ship:
		ship.weapon_style = _prev_style
	if "ammo_recharge_rate" in ship:
		ship.ammo_recharge_rate = _prev_ammo_recharge_rate
	if "ammo_max" in ship:
		ship.ammo_max = _prev_ammo_max
	if ship.has_method("set_ammo"):
		ship.set_ammo(0)
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown
