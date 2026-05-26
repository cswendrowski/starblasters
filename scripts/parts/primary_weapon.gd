extends "res://scripts/parts/weapon_part.gd"

# PrimaryWeapon — base for CANNON-slot Parts. Owns the cannon-triple
# (bullet_scene, cooldown, bullet_damage) plus weapon_style + fire_sfx_kind
# routing. Subclasses typically only override _init() defaults +
# _mk_knobs() for their damage curve.

const WS = preload("res://scripts/weapons/WeaponStyle.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Weapon-style routing. Subclasses override the virtual methods below —
# do NOT use @exports for these, because .tres-loaded weapons don't run
# _init() (Godot loads field values from the resource, not the script).
# Virtual methods work for both .new() and .tres-loaded instances.


# Weapons Phase 1 (2026-05-26): every non-blaster primary carries its own
# ammo on the Part instance, so cannon_pool[i] survives swaps. The blaster
# (Energy Blaster) overrides ammo_at_mark() to return -1 (infinite).
# Default current_ammo = -1 so cannons that haven't been mark-bumped yet
# still read as infinite — Run.equip_part seeds these on append.
@export var current_ammo: int = -1
@export var ammo_max: int = -1

# Prevents outpost from showing an ammo-refill row for this cannon.
# Used by lasers which regen naturally and shouldn't be sold refills.
@export var no_outpost_refill: bool = false

# If >= 0, outpost uses this cost instead of PRIMARY_REFILL_COST.
@export var refill_cost_override: int = -1


func _init() -> void:
	slot_type = Slots.SlotType.CANNON


# Returns the starting ammo for this cannon at the given mark. Designer
# formula (Roman 2026-05-26): 1000 / max(1, effective damage at mark) for
# replacement primaries. The blaster + metered_primary subclasses override
# (blaster returns -1 = infinite; metered keeps its explicit base_ammo).
func ammo_at_mark(mk: int) -> int:
	var dmg: int = _effective_damage_at_mark(mk)
	return int(1000.0 / float(max(1, dmg)))


# Resolve bullet_damage from the per-mark curve in _mk_knobs() without
# touching a live ship. Mirrors WeaponPart._compute_knob_value for the
# bullet_damage array case (the only one we need for the ammo formula).
func _effective_damage_at_mark(mk: int) -> int:
	var spec = _mk_knobs().get("bullet_damage", null)
	if spec == null:
		return max(1, int(base_damage))
	if spec is Array and spec.size() == 2:
		var t: float = (clampf(float(mk), 1.0, 9.0) - 1.0) / 8.0
		return int(round(lerpf(float(spec[0]), float(spec[1]), t)))
	if spec is Callable:
		return int(spec.call(int(mk)))
	return max(1, int(base_damage))


# Subclasses override these — return the WS enum value for the cannon's
# routing. Defaults are safe placeholders that route through $ShootSound
# / default ENERGY style if a subclass forgets.
func _weapon_style() -> int:
	return WS.WeaponStyle.ENERGY


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.NONE


# Snapshot the cannon-triple plus style/sfx so re-equip always restores.
# Subclasses can extend this list (e.g. Auto Laser's tandem fields) by
# overriding and concatenating.
func _snapshot_keys() -> Array:
	return [
		"bullet_scene",
		"cooldown",
		"bullet_damage",
		"weapon_style",
		"fire_sfx_kind",
	]


# Default Mk-knob curve: bullet_damage scales linearly base → +dmg_per_mark*8.
# Subclasses that want non-linear scaling override and return their own
# table (e.g. Wave Gun, Spread Cannon).
func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [base_damage, base_damage + dmg_per_mark * 8],
		"cooldown": [base_cooldown, base_cooldown],
	}


# Write the non-knob fields. bullet_scene comes from the @export (.tres or
# script default); the snapshot covers reversal on unapply.
func _apply_visuals(ship) -> void:
	if bullet_scene != null:
		ship.bullet_scene = bullet_scene
	ship.weapon_style = _weapon_style()
	ship.fire_sfx_kind = _fire_sfx_kind()
	# Weapons Phase 1: stamp the Part's ammo onto the ship so fire_primary's
	# decrement guard (`ammo > 0`) trips correctly for every non-blaster
	# primary — not just the metered_primary subclasses. Blaster passes
	# current_ammo == -1 (infinite); the >= 0 guard is the discriminator.
	if "ammo_max" in ship:
		ship.ammo_max = ammo_max
	if ship.has_method("set_ammo"):
		ship.set_ammo(current_ammo)
