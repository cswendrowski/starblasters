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


func _init() -> void:
	slot_type = Slots.SlotType.CANNON


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
