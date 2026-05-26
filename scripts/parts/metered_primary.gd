extends "res://scripts/parts/primary_weapon.gd"

# MeteredPrimary — base for CANNON Parts with limited ammo (Machinegun,
# Rotary Laser). Adds the Run-snapshot ammo seed pattern + optional
# recharge rate. Subclasses set base_ammo + ammo_recharge_rate via @export
# (or .tres) and override _apply_visuals to set weapon_style/sfx.

@export var base_ammo: int = 0
@export var ammo_recharge_rate: float = 0.0


# MeteredPrimary subclasses (Machinegun, Rotary Laser) keep their explicit
# `base_ammo` instead of the 1000/damage curve — they're designed as
# high-rate-of-fire weapons whose magazine size is part of their identity.
# TODO Phase 2: revisit whether MG/RL should fall into the same formula.
func ammo_at_mark(_mk: int) -> int:
	return int(base_ammo)


func _snapshot_keys() -> Array:
	# ammo_max + ammo_recharge_rate live on ship; both must round-trip.
	# The actual `ammo` field is driven via set_ammo(); we restore by
	# calling set_ammo(0) in _on_unapply since the prior weapon's apply
	# will seed its own ammo.
	var keys: Array = super._snapshot_keys()
	keys.append("ammo_max")
	keys.append("ammo_recharge_rate")
	return keys


func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	if "ammo_recharge_rate" in ship:
		ship.ammo_recharge_rate = ammo_recharge_rate
	if "ammo_max" in ship:
		ship.ammo_max = base_ammo
	# Seed ammo from the Part's own current_ammo (Weapons Phase 1: each
	# non-blaster primary owns its magazine on the cannon_pool entry). Fall
	# back to Run.ammo for pre-Phase-1 saves or first-equip cases where
	# current_ammo hasn't been seeded yet.
	if ship.has_method("set_ammo"):
		var seeded: int = base_ammo
		if current_ammo > 0:
			seeded = current_ammo
		elif ship.has_node("/root/Run"):
			var run = ship.get_node("/root/Run")
			if "ammo" in run and int(run.ammo) > 0:
				seeded = int(run.ammo)
		ship.set_ammo(seeded)


func _on_unapply(ship) -> void:
	# Zero the primary ammo gate so the next weapon (which may be unmetered)
	# doesn't inherit a stale ammo count. Recharge rate / max are restored
	# from snapshot already.
	if ship.has_method("set_ammo"):
		ship.set_ammo(0)
