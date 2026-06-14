extends "res://scripts/parts/part.gd"

# ModulePart — base for the passive Module Bay (2026-06-13). A module is an
# AUTOMATIC (no-input) Part that ADDS a mechanic (vs an Upgrade, which refines a
# number). Modules live in the `Run.modules` LIST (up to Run.MODULE_BAY_SIZE),
# applied by the player's module apply loop at combat start — NOT the one-part-per-
# slot pegboard. The MODULE slot_type is just a TAG so the catalog/shop recognize them.
#
# Contract: subclasses set identity + module_id in _init() and override apply(ship)/
# unapply(ship) to mutate the ship. DEFAULT-SAFE — the player's module_* fields default
# to no-op, so a ship with no module (or no bay at all) behaves exactly as today. Mk.1–9
# scaling via `mark`, like every Part. See docs/passive_module_bay_2026-06-13.md.

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Stable identity used for "is module X equipped?" checks (e.g. the shield gates on a
# Shield Core). Subclasses set it in _init().
@export var module_id: String = ""


func _init() -> void:
	slot_type = Slots.SlotType.MODULE
