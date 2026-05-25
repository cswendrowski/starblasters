extends "res://scripts/parts/secondary_weapon.gd"

# BulletSecondary — secondary weapons that fire bullets/missiles/rockets.
# Subclasses override the virtual methods below (not @exports — .tres
# loading skips _init, so script-default @exports would silently override
# subclass values).

const WS = preload("res://scripts/weapons/WeaponStyle.gd")


# Subclass overrides — Resource-load safe (no _init dependency).
func _homing() -> bool:
	return false


func _pod_count() -> int:
	return 1


# Positive = metered (seed from Run); -1 = unmetered.
func _base_ammo() -> int:
	return -1


func _secondary_mode() -> int:
	return WS.SecondaryMode.BULLET


func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	if "secondary_homing" in ship:
		ship.secondary_homing = _homing()
	if "secondary_pod_count" in ship:
		ship.secondary_pod_count = _pod_count()
	# Ammo handling — metered weapons seed from Run snapshot; unmetered
	# clears ammo state so the HUD/fire gate don't think we're capped.
	if ship.has_method("set_secondary_ammo"):
		var ammo: int = _base_ammo()
		if ammo < 0:
			ship.set_secondary_ammo(-1, -1)
		else:
			var seeded: int = ammo
			if ship.has_node("/root/Run"):
				var run = ship.get_node("/root/Run")
				if "secondary_ammo" in run and int(run.secondary_ammo) >= 0:
					seeded = int(run.secondary_ammo)
			ship.set_secondary_ammo(seeded, ammo)


func _on_unapply(ship) -> void:
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)
