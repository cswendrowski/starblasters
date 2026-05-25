extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

# Machinegun Cannon. Alt CANNON weapon. Trades the Energy Blaster's
# infinite ammo for raw damage + cadence: limited ammo (1000 rounds at
# Mk.1, scales with mark), tighter cooldown, brrrt audio loop. Purchasable
# cheap at Friendly Outposts (Roman, 2026-05-16); ammo refills are
# available there and at Junk Trader signal events.
@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var dmg_per_mark: int = 1
@export var base_cooldown: float = 0.10   # MG-loop cadence
@export var base_ammo: int = 1000

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: int = WS.WeaponStyle.ENERGY

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Machinegun Cannon"
	description = "High rate of fire, high damage. Limited ammo (1000 rounds). Refill at outposts."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	ship.cooldown = base_cooldown
	ship.bullet_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	# Plumb the style + ammo into the player so fire_primary can route to
	# the MG audio loop + decrement ammo. The Run autoload persists ammo
	# across scenes.
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = WS.WeaponStyle.MACHINEGUN
	# Seed ammo from the Run snapshot if it exists (so a player who bought
	# the MG at outpost A keeps their remaining ammo into outpost B). The
	# outpost top-up flow writes back to Run.ammo when refilling.
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
	if ship.has_method("set_ammo"):
		ship.set_ammo(0)
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown
