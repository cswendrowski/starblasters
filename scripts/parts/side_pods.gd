extends "res://scripts/parts/part.gd"

# Ammo Pods — passive HARDPOINT_WING part. No firing behavior.
# Adds 15% max ammo per mark to all equipped metered weapons
# (primary MG / Rotary Laser, and secondary Rocket Pod / Seeking Missile).
# Unmetered weapons (ammo == -1) are untouched.
#
# apply() snapshots the base values BEFORE the bonus and records exact integer
# deltas; unapply() subtracts them exactly.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

const AMMO_BONUS_PER_MARK: float = 0.15

var _applied_ammo: int = 0
var _applied_ammo_max: int = 0
var _applied_sec_ammo: int = 0
var _applied_sec_ammo_max: int = 0


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Ammo Pods"
	description = "Increases ammo for primary and secondary weapons by +15% per mark."


func apply(ship) -> void:
	_applied_ammo = 0
	_applied_ammo_max = 0
	_applied_sec_ammo = 0
	_applied_sec_ammo_max = 0

	var pct: float = AMMO_BONUS_PER_MARK * mark

	# Primary — Rotary Laser: ammo_max > 0 drives the charge cap.
	if "ammo_max" in ship and int(ship.ammo_max) > 0:
		var bonus: int = int(floor(int(ship.ammo_max) * pct))
		ship.ammo_max += bonus
		ship.ammo += bonus
		_applied_ammo_max = bonus

	# Primary — Machinegun: ammo >= 0, ammo_max == 0.
	elif "ammo" in ship and int(ship.ammo) >= 0:
		var bonus: int = int(floor(int(ship.ammo) * pct))
		ship.ammo += bonus
		_applied_ammo = bonus
		if ship.has_node("/root/Run"):
			ship.get_node("/root/Run").ammo = int(ship.ammo)

	# Secondary — metered (secondary_ammo_max >= 0 means capped pool).
	if "secondary_ammo_max" in ship and int(ship.secondary_ammo_max) >= 0:
		var bonus: int = int(floor(int(ship.secondary_ammo_max) * pct))
		ship.secondary_ammo_max += bonus
		if "secondary_ammo" in ship and int(ship.secondary_ammo) >= 0:
			ship.secondary_ammo += bonus
		_applied_sec_ammo_max = bonus

	# Secondary — countdown pool with no explicit max.
	elif "secondary_ammo" in ship and int(ship.secondary_ammo) >= 0:
		var bonus: int = int(floor(int(ship.secondary_ammo) * pct))
		ship.secondary_ammo += bonus
		_applied_sec_ammo = bonus


func unapply(ship) -> void:
	if "ammo" in ship and _applied_ammo > 0:
		ship.ammo = maxi(0, int(ship.ammo) - _applied_ammo)
		if ship.has_node("/root/Run"):
			ship.get_node("/root/Run").ammo = int(ship.ammo)
	if "ammo_max" in ship and _applied_ammo_max > 0:
		ship.ammo_max = maxi(0, int(ship.ammo_max) - _applied_ammo_max)
		ship.ammo = mini(int(ship.ammo), int(ship.ammo_max))
	if "secondary_ammo" in ship and _applied_sec_ammo > 0:
		ship.secondary_ammo = maxi(0, int(ship.secondary_ammo) - _applied_sec_ammo)
	if "secondary_ammo_max" in ship and _applied_sec_ammo_max > 0:
		ship.secondary_ammo_max = maxi(0, int(ship.secondary_ammo_max) - _applied_sec_ammo_max)
		if "secondary_ammo" in ship and int(ship.secondary_ammo) >= 0:
			ship.secondary_ammo = mini(int(ship.secondary_ammo), int(ship.secondary_ammo_max))
	_applied_ammo = 0
	_applied_ammo_max = 0
	_applied_sec_ammo = 0
	_applied_sec_ammo_max = 0
