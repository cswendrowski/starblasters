extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Hyper Mode — DoDonPachi / Cave-lineage super. On activation:
#   - Player goes invulnerable for the duration.
#   - Primary fire ignores GunCooldown for the duration (auto-fires
#     every frame at max cadence).
#   - Bullet damage is multiplied (constant in player.gd::HYPER_DAMAGE_MULT).
#
# Trade vs Smart Bomb: Smart Bomb is defensive panic (clear screen,
# big alpha). Hyper is offensive panic (you keep dodging, but you
# DELETE whatever you're aiming at for 3 seconds).

@export var base_duration: float = 3.0
@export var duration_per_mark: float = 0.25
@export var base_charges: int = 2
@export var charges_per_mark: int = 1


func _init() -> void:
	slot_type = Slots.SlotType.DEVICE_BAY_1
	display_name = "Hyper Mode"
	description = "Brief invulnerability + supercharged primary. Offensive super."


func apply(ship) -> void:
	if not ("super_part" in ship):
		return
	ship.super_part = self
	ship.max_super_charges = base_charges + (int(mark) - 1) * charges_per_mark
	ship.super_charges = ship.max_super_charges
	if ship.has_signal("super_charges_changed"):
		ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)


func unapply(ship) -> void:
	if not ("super_part" in ship):
		return
	if ship.super_part == self:
		ship.super_part = null
		ship.super_charges = 0
		if ship.has_signal("super_charges_changed"):
			ship.super_charges_changed.emit(0, 0)


func activate(ship) -> void:
	var dur: float = base_duration + (float(mark) - 1.0) * duration_per_mark
	# Both timers drive separate effects in player._process:
	#   _hyper_t > 0 → bypass GunCooldown + 2× damage
	#   _invuln_t > 0 → take_damage bails immediately
	if "_hyper_t" in ship:
		ship._hyper_t = dur
	if "_invuln_t" in ship:
		ship._invuln_t = max(ship._invuln_t, dur)
	# VFX: golden ring around player, plus camera nudge to sell the snap.
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx:
		ExplosionFx.play(ship.global_position, 1.5, true)
	var tree := ship.get_tree() if ship.has_method("get_tree") else null
	if tree:
		var main := tree.get_current_scene()
		if main and main.has_node("Camera2D"):
			var cam = main.get_node("Camera2D")
			if cam.has_method("add_trauma"):
				cam.add_trauma(0.4)


# Editor readout — duration-based super, no per-hit damage. Report
# duration*10 as a placeholder "intensity" number so the DPS box isn't
# blank in the editor.
func effective_damage(at_mark: int) -> int:
	return int(round((base_duration + (float(at_mark) - 1.0) * duration_per_mark) * 10.0))
