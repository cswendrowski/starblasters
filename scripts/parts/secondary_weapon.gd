extends "res://scripts/parts/weapon_part.gd"

# SecondaryWeapon — base for HARDPOINT_WING-slot Parts. Mirrors the cannon
# triple on secondary_* ship fields. Subclasses pick BULLET vs BEAM mode
# via secondary_mode and supply scene/damage/cooldown via the standard
# WeaponPart @exports (base_damage / dmg_per_mark / base_cooldown / bullet_scene).

const WS = preload("res://scripts/weapons/WeaponStyle.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")

func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING


# Virtual — subclasses override. Avoids the .tres-doesn't-run-_init trap
# where an @export default would silently win over the intended value.
func _secondary_mode() -> int:
	return WS.SecondaryMode.BULLET


func _snapshot_keys() -> Array:
	return [
		"secondary_bullet_scene",
		"secondary_cooldown",
		"secondary_damage",
		"secondary_homing",
		"secondary_mode",
		"secondary_pod_count",
	]


# Default Mk-knob curve mirrors PrimaryWeapon: secondary_damage scales
# linearly. Subclasses override for non-linear (Side Pods scales count,
# Particle Beam scales width).
func _mk_knobs() -> Dictionary:
	return {
		"secondary_damage": [base_damage, base_damage + dmg_per_mark * 8],
		"secondary_cooldown": [base_cooldown, base_cooldown],
	}


func _apply_visuals(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	if bullet_scene != null:
		ship.secondary_bullet_scene = bullet_scene
	if "secondary_mode" in ship:
		ship.secondary_mode = _secondary_mode()


# Override: if the ship doesn't expose the secondary triple, bail before
# touching anything. Preserves the original guard from rocket_pod.gd etc.
func apply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	super.apply(ship)


func unapply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	super.unapply(ship)


# Secondary weapons don't drive GunCooldown — that's the primary timer.
# Override to no-op so the base's _resync_gun_cooldown doesn't wrongly
# rewrite the primary timer with secondary_cooldown when a secondary
# equips. (cooldown field is the primary's; we never touch it here.)
func _resync_gun_cooldown(_ship) -> void:
	pass
