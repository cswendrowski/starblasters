extends "res://scripts/parts/part.gd"

# Ammo Pods — passive HARDPOINT_WING part. No firing behavior.
# Adds +150 ammo per mark to the equipped primary weapon's ammo pool.
# Only has effect when the primary is a metered weapon (MG or Rotary Laser);
# unmetered primaries are untouched and this part still occupies the slot.
#
# Mk scaling: linear 150 * mk — Mk.1=150, Mk.9=1350.
# apply() records the exact integer deltas; unapply() subtracts them exactly.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

const AMMO_PER_MARK: int = 150

var _applied_ammo: int = 0
var _applied_ammo_max: int = 0


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Ammo Pods"
	description = "Increases ammo for metered primary weapons by +150 per mark."


func apply(ship) -> void:
	var bonus: int = AMMO_PER_MARK * mark
	_applied_ammo = 0
	_applied_ammo_max = 0
	# ammo_max > 0 means a charge-based metered weapon (Rotary Laser) is
	# equipped. Raise both cap and current so the boost feels immediate.
	# Check this branch first — rotary also has ammo >= 0, so we need the
	# two cases to be mutually exclusive.
	if "ammo_max" in ship and int(ship.ammo_max) > 0:
		ship.ammo_max += bonus
		ship.ammo += bonus
		_applied_ammo_max = bonus
	# ammo >= 0 and ammo_max == 0 means a countdown weapon (MG) is equipped;
	# ammo == -1 = unmetered/none — skip.
	elif "ammo" in ship and int(ship.ammo) >= 0:
		ship.ammo += bonus
		_applied_ammo = bonus
		# Sync MG pool to Run so the bonus survives scene transitions.
		if ship.has_node("/root/Run"):
			ship.get_node("/root/Run").ammo = int(ship.ammo)


func unapply(ship) -> void:
	if "ammo" in ship and _applied_ammo > 0:
		ship.ammo = maxi(0, int(ship.ammo) - _applied_ammo)
		if ship.has_node("/root/Run"):
			ship.get_node("/root/Run").ammo = int(ship.ammo)
	if "ammo_max" in ship and _applied_ammo_max > 0:
		ship.ammo_max = maxi(0, int(ship.ammo_max) - _applied_ammo_max)
		ship.ammo = mini(int(ship.ammo), int(ship.ammo_max))
	_applied_ammo = 0
	_applied_ammo_max = 0
