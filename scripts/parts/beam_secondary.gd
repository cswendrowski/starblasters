extends "res://scripts/parts/secondary_weapon.gd"

# BeamSecondary — secondary weapons that fire a continuous hit-scan beam
# (Particle Beam). Sets secondary_mode=BEAM; subclasses provide dps/width
# scaling via _mk_knobs over secondary_beam_dps/secondary_beam_width.

const WS = preload("res://scripts/weapons/WeaponStyle.gd")


func _secondary_mode() -> int:
	return WS.SecondaryMode.BEAM


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("secondary_beam_dps")
	keys.append("secondary_beam_width")
	return keys


# Default — no damage scaling on the secondary triple; beam DPS lives in
# its own field. Subclasses override _mk_knobs() with the beam-specific
# scaling (see particle_beam.gd).
func _mk_knobs() -> Dictionary:
	return {}


func _on_unapply(ship) -> void:
	# Tear down the beam visual if it's currently rendering.
	if "_beam_line" in ship and ship._beam_line and ship._beam_line.visible:
		ship._beam_line.visible = false
	if "_beam_halo" in ship and ship._beam_halo and ship._beam_halo.visible:
		ship._beam_halo.visible = false
	if "_beam_core" in ship and ship._beam_core and ship._beam_core.visible:
		ship._beam_core.visible = false
	if "_beam_active" in ship:
		ship._beam_active = false
	# Unmetered — clear ammo gate same as unmetered bullet secondaries.
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)
