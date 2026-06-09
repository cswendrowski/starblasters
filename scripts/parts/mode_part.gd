extends "res://scripts/parts/part.gd"

# ModePart — base for the SHIFT_MODE slot (Focus / Phase / Hyper). The Shift-Mode
# slot holds exactly one of these; it's the stance the `focus` action (Shift)
# activates. Design: docs/shift_mode_system_2026-06-08.md.
#
# Unlike SuperPart (one button, charges, fire-once on X), a ModePart just declares
# WHICH stance is active — the per-mode runtime (resource models, intangibility,
# fire/ammo/damage) lives in player.gd, dispatched on `ship.active_mode`. Each mode
# part exposes Mk-scaled getters the runtime reads (duration_at_mark / charges_at_mark
# / fire_bonus_at_mark / ...).
#
# Default stance is FOCUS — a fresh ship has a Focus mode part, and `ship.active_mode`
# defaults to FOCUS, so an empty/absent mode slot still behaves as Focus.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

enum Mode { FOCUS, PHASE, HYPER }

@export var mode_id: int = Mode.FOCUS

# Snapshot so unequip restores the prior mode (back to Focus by default).
var _prev_mode_part = null
var _prev_active_mode: int = Mode.FOCUS
var _had_prev: bool = false


func _init() -> void:
	slot_type = Slots.SlotType.SHIFT_MODE


func apply(ship) -> void:
	if not ("active_mode" in ship):
		return
	_prev_mode_part = ship.mode_part if "mode_part" in ship else null
	_prev_active_mode = int(ship.active_mode)
	_had_prev = true
	if "mode_part" in ship:
		ship.mode_part = self
	ship.active_mode = mode_id
	if ship.has_method("_on_mode_changed"):
		ship._on_mode_changed()


func unapply(ship) -> void:
	if not ("active_mode" in ship):
		return
	# Only relinquish the slot if we're still the active mode part.
	if "mode_part" in ship and ship.mode_part != self:
		return
	if "mode_part" in ship:
		ship.mode_part = _prev_mode_part
	# Revert to the prior stance — or FOCUS (the base) if there was none.
	ship.active_mode = _prev_active_mode if _had_prev else Mode.FOCUS
	if ship.has_method("_on_mode_changed"):
		ship._on_mode_changed()
	_had_prev = false
