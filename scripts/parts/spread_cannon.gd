extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Spread Cannon. Fans bullets across an arc instead of stacking them
# straight up — classic shmup 3-way / spread weapon. Trades single-target
# DPS for crowd coverage; aim-forgiving against wave formations.
#
# Mk scaling adds bullet count (3 → 5 → 7 → … capped at 9) rather than
# damage per shot, so upgrades feel like "wider net" not "stronger gun".
# Damage stays modest so it doesn't out-DPS the heavy single-target guns
# at point-blank.

@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var dmg_per_mark: int = 1
@export var base_cooldown: float = 0.30
@export var base_bullet_count: int = 3
# Each Mark above 1 adds two bullets, capped at MAX_BULLETS. So Mk.1=3,
# Mk.2=5, Mk.3=7, Mk.4+=9.
@export var bullets_per_mark: int = 2
@export var max_bullets: int = 9
@export var spread_degrees: float = 30.0

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_style: String = ""
var _prev_spread_count: int = 1
var _prev_spread_degrees: float = 0.0


func _init() -> void:
	slot_type = Slots.SlotType.CANNON
	display_name = "Spread Cannon"
	description = "Fans bullets in a forward arc. Higher Mk widens the spread."


func apply(ship) -> void:
	_prev_bullet_scene = ship.bullet_scene
	_prev_cooldown = ship.cooldown
	_prev_damage = ship.bullet_damage
	if "weapon_style" in ship:
		_prev_style = ship.weapon_style
		ship.weapon_style = "energy"
	if "fire_sfx_kind" in ship:
		ship.fire_sfx_kind = "blaster_small"
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	ship.cooldown = base_cooldown
	ship.bullet_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	# Spread knobs — read by player.gd::fire_primary.
	if "bullet_spread_count" in ship:
		_prev_spread_count = ship.bullet_spread_count
		ship.bullet_spread_count = mini(
			base_bullet_count + (int(mark) - 1) * bullets_per_mark,
			max_bullets,
		)
	if "bullet_spread_degrees" in ship:
		_prev_spread_degrees = ship.bullet_spread_degrees
		ship.bullet_spread_degrees = spread_degrees
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


func unapply(ship) -> void:
	ship.bullet_scene = _prev_bullet_scene
	ship.cooldown = _prev_cooldown
	ship.bullet_damage = _prev_damage
	if "weapon_style" in ship:
		ship.weapon_style = _prev_style
	if "bullet_spread_count" in ship:
		ship.bullet_spread_count = _prev_spread_count
	if "bullet_spread_degrees" in ship:
		ship.bullet_spread_degrees = _prev_spread_degrees
	if ship.has_node("GunCooldown"):
		ship.get_node("GunCooldown").wait_time = ship.cooldown


# Override the standard formula so the weapon editor's DPS readout
# accounts for bullet count, not just per-bullet damage.
func effective_damage(at_mark: int) -> int:
	var per_bullet: int = base_damage + (at_mark - 1) * dmg_per_mark
	var n_bullets: int = mini(
		base_bullet_count + (at_mark - 1) * bullets_per_mark,
		max_bullets,
	)
	return per_bullet * n_bullets
