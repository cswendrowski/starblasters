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


# Protected helper for metered subclasses that override _apply_visuals. Seeds
# current_ammo from the mark (so super._apply_visuals reads the correct per-mark
# value instead of stale -1), and returns the value for post-super ammo_max setting.
# Usage: var mag = _seed_metered_ammo_for_mark(int(mark)); super._apply_visuals(ship);
# then set ship.ammo_max = mag if needed.
func _seed_metered_ammo_for_mark(mark: int) -> int:
	var mag: int = ammo_at_mark(int(mark))
	current_ammo = mag
	return mag


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
		# Prefer the Part's OWN ammo_max: run_state stamps it from ammo_at_mark(mark) at equip/reseed
		# (run_state.cond_ammo_cap) so it's ALREADY Condition-scaled AND tracks the mark curve. For a
		# compound-magazine weapon (Minigun/Machinegun: Mk1=1000 … Mk9≈4300) the flat `base_ammo` export
		# only equals the Mk1 magazine, so using it capped the CAP below the mark-scaled current_ammo —
		# a persistent current>max mismatch. Use ammo_max verbatim; do NOT rescale it (it's pre-scaled —
		# a second cond_scalar would double-count More Ammo). Fall back to the scaled base_ammo curve only
		# when ammo_max is uninitialized (-1) — a dev/headless equip before run_state seeded the Part.
		if ammo_max > 0:
			ship.ammo_max = ammo_max
		else:
			var cap: int = base_ammo
			if base_ammo > 0 and ship.has_node("/root/Run"):
				cap = ship.get_node("/root/Run").cond_ammo_cap(base_ammo)
			ship.ammo_max = cap
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
