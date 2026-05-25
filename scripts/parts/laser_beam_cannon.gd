extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

# Auto Laser (formerly Laser Beam). Alternating left/right tandem energy
# bolts at moderate cadence. Spawn offset ±8px from the player's pixel
# center; player.fire_primary handles the toggle via fire_tandem_alternating.
# Uses the rotary laser muzzle flash for the "energy weapon" tell.
#
# Roman, 2026-05-24: placeholder fire SFX — fire_sfx_kind = "" routes
# through the legacy $ShootSound on the player scene. Swap to a dedicated
# kind in scripts/effects/weapon_sfx.gd once final SFX land.

@export var bullet_scene: PackedScene
@export var base_damage: int = 3
@export var dmg_per_mark: int = 3
@export var base_cooldown: float = 0.18

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: int = WS.WeaponStyle.ENERGY
var _prev_sfx_kind: String = ""
var _prev_tandem: bool = false
var _prev_tandem_side: int = 0
var _prev_use_rotary_muzzle: bool = false

func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Auto Laser"
	description = "Alternating left/right tandem bolts. Moderate rate of fire."

func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = WS.WeaponStyle.ENERGY
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	# Placeholder fire SFX — empty kind falls through to $ShootSound.
	if "fire_sfx_kind" in ship:
		_prev_sfx_kind = ship.fire_sfx_kind
		ship.fire_sfx_kind = ""
	# Tandem alternating fire (player.fire_primary reads these).
	if "fire_tandem_alternating" in ship:
		_prev_tandem = ship.fire_tandem_alternating
		ship.fire_tandem_alternating = true
	if "_tandem_side" in ship:
		_prev_tandem_side = ship._tandem_side
		ship._tandem_side = 0
	# Borrow the rotary laser muzzle flash (designer 2026-05-24).
	if "use_rotary_laser_muzzle" in ship:
		_prev_use_rotary_muzzle = ship.use_rotary_laser_muzzle
		ship.use_rotary_laser_muzzle = true
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
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = _prev_sfx_kind
	if "fire_tandem_alternating" in ship:
		ship.fire_tandem_alternating = _prev_tandem
	if "_tandem_side" in ship:
		ship._tandem_side = _prev_tandem_side
	if "use_rotary_laser_muzzle" in ship:
		ship.use_rotary_laser_muzzle = _prev_use_rotary_muzzle
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown
