extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

# Seeking Missile launcher. Secondary weapon (HARDPOINT_WING) — fires
# alongside the primary cannon on its own cooldown. Slow cadence, slow
# projectile, but the missile homes onto the nearest non-shielded enemy.
# Highest per-shot damage in the supplement slot; great against tanky
# elites and bosses.
#
# Was a CANNON primary; moved to HARDPOINT_WING (Cody 2026-05-19) so it
# supplements a primary blaster instead of replacing one.

@export var bullet_scene: PackedScene
@export var base_damage: int = 3
@export var dmg_per_mark: int = 3
@export var base_cooldown: float = 0.75
# Limited magazine — designer call (Roman, 2026-05-23): missiles are
# premium ordnance, refilled at outposts (shop rework pending). Flat 60
# regardless of mark; mark scales damage only.
@export var base_ammo: int = 60

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_homing: bool = false
var _prev_secondary_mode: int = WS.SecondaryMode.BULLET


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Seeking Missile"
	description = "Tracks the nearest enemy. Slow cadence, heavy damage. Secondary."


func apply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	_prev_bullet_scene = ship.secondary_bullet_scene
	_prev_cooldown = ship.secondary_cooldown
	_prev_damage = ship.secondary_damage
	_prev_homing = ship.secondary_homing
	if "secondary_mode" in ship:
		_prev_secondary_mode = int(ship.secondary_mode)
		ship.secondary_mode = WS.SecondaryMode.BULLET
	if bullet_scene != null:
		ship.secondary_bullet_scene = bullet_scene
	ship.secondary_cooldown = base_cooldown
	ship.secondary_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	ship.secondary_homing = true
	# Single-bullet — reset any pod_count left over from a previous
	# Side Pods equip.
	if "secondary_pod_count" in ship:
		ship.secondary_pod_count = 1
	# Seed ammo from the Run snapshot if the player already has a partial
	# magazine; otherwise hand them a fresh `base_ammo`.
	if ship.has_method("set_secondary_ammo"):
		var seeded: int = base_ammo
		if ship.has_node("/root/Run"):
			var run = ship.get_node("/root/Run")
			if "secondary_ammo" in run and int(run.secondary_ammo) >= 0:
				seeded = int(run.secondary_ammo)
		ship.set_secondary_ammo(seeded, base_ammo)


func unapply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	ship.secondary_bullet_scene = _prev_bullet_scene
	ship.secondary_cooldown = _prev_cooldown
	ship.secondary_damage = _prev_damage
	ship.secondary_homing = _prev_homing
	if "secondary_mode" in ship:
		ship.secondary_mode = _prev_secondary_mode
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)
