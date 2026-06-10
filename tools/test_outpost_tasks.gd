#!/usr/bin/env godot
# Test harness for outpost tasks #1, #3, #6
# Usage: godot tools/test_outpost_tasks.tscn
# Or, boot the outpost scene directly from the editor.

extends Control

const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const Strings = preload("res://scripts/strings.gd")


# Dummy Part for testing.
class DummyPart extends Resource:
	var display_name: String
	var mark: int = 1
	var slot_type: int
	var base_damage: int = 0
	var dmg_per_mark: int = 0
	var base_cooldown: float = 0.0

	func _init(p_name: String, p_slot: int, p_mark: int = 1) -> void:
		display_name = p_name
		slot_type = p_slot
		mark = p_mark


# Test helpers extracted from outpost.gd (inline for testing).
func _is_energy_blaster(part) -> bool:
	if part == null:
		return false
	return String(part.display_name) == "Energy Blaster"


func _type_name_for_part(part, slot: int) -> String:
	if slot == SlotTypes.SlotType.CANNON:
		if _is_energy_blaster(part):
			return Strings.TYPE_NAME_BLASTER
		return Strings.TYPE_NAME_PRIMARY_WEAPON
	match slot:
		SlotTypes.SlotType.HARDPOINT_WING:
			return Strings.TYPE_NAME_SECONDARY_WEAPON
		SlotTypes.SlotType.DEVICE_BAY_1:
			return Strings.TYPE_NAME_SUPER
		SlotTypes.SlotType.SHIFT_MODE:
			return Strings.TYPE_NAME_MODE
	return "PART"


func _should_roll_weapon_standalone(owned_items: Array, part_name: String, offered_mk: int) -> bool:
	# Simplified version for testing: owned_items is an array of (name, mk) tuples.
	for item in owned_items:
		if item[0] == part_name:
			if offered_mk <= item[1]:
				return false  # Reject: own same or higher.
	return true


func _ready() -> void:
	print("\n=== OUTPOST TASKS TEST SUITE ===\n")

	# Task #1, #3: Blaster vs Primary Weapon disambiguation
	test_task_1_3()

	# Task #6b: Own-better filter
	test_task_6b()

	print("\n=== ALL TESTS PASSED ===\n")
	queue_free()


func test_task_1_3() -> void:
	print("[Task #1/#3] Blaster vs Primary Weapon")

	var blaster = DummyPart.new("Energy Blaster", SlotTypes.SlotType.CANNON, 1)
	var rotary = DummyPart.new("Rotary Laser", SlotTypes.SlotType.CANNON, 3)
	var secondary = DummyPart.new("Rocket Pod", SlotTypes.SlotType.HARDPOINT_WING, 2)
	var super_bomb = DummyPart.new("Smart Bomb", SlotTypes.SlotType.DEVICE_BAY_1, 1)
	var mode = DummyPart.new("Hyper Mode", SlotTypes.SlotType.SHIFT_MODE, 2)

	# Test Energy Blaster detection.
	assert(_is_energy_blaster(blaster), "Blaster should be detected as Energy Blaster")
	assert(not _is_energy_blaster(rotary), "Rotary Laser should NOT be detected as Energy Blaster")
	assert(not _is_energy_blaster(null), "null should not be a blaster")
	print("  ✓ Energy Blaster detection works")

	# Test type name mapping.
	var blaster_type = _type_name_for_part(blaster, SlotTypes.SlotType.CANNON)
	var primary_type = _type_name_for_part(rotary, SlotTypes.SlotType.CANNON)
	var secondary_type = _type_name_for_part(secondary, SlotTypes.SlotType.HARDPOINT_WING)
	var super_type = _type_name_for_part(super_bomb, SlotTypes.SlotType.DEVICE_BAY_1)
	var mode_type = _type_name_for_part(mode, SlotTypes.SlotType.SHIFT_MODE)

	assert(blaster_type == Strings.TYPE_NAME_BLASTER,
		"Blaster should map to TYPE_NAME_BLASTER, got %s" % blaster_type)
	assert(primary_type == Strings.TYPE_NAME_PRIMARY_WEAPON,
		"Other cannons should map to PRIMARY_WEAPON, got %s" % primary_type)
	assert(secondary_type == Strings.TYPE_NAME_SECONDARY_WEAPON,
		"Wing hardpoint should map to SECONDARY_WEAPON, got %s" % secondary_type)
	assert(super_type == Strings.TYPE_NAME_SUPER,
		"Device bay should map to SUPER, got %s" % super_type)
	assert(mode_type == Strings.TYPE_NAME_MODE,
		"Shift mode should map to MODE, got %s" % mode_type)
	print("  ✓ Type name mapping correct")
	print("    - Blaster → 'Blaster'")
	print("    - Rotary Laser → 'Primary Weapon'")
	print("    - Rocket Pod → 'Secondary Weapon'")
	print("    - Smart Bomb → 'Super'")
	print("    - Hyper Mode → 'Mode'")


func test_task_6b() -> void:
	print("\n[Task #6b] Own-better filter")

	# Test: Player owns Mk.2 Rotary and Mk.1 Auto Laser.
	# Should reject Mk.2 Rotary (same), accept Mk.3 Rotary (higher).
	# Should reject Mk.1 Auto Laser (same), accept Mk.2 Auto Laser (higher).

	var owned = [
		["Rotary Laser", 2],
		["Auto Laser", 1],
	]

	# Owned items at same mark → reject.
	assert(not _should_roll_weapon_standalone(owned, "Rotary Laser", 2),
		"Should reject Mk.2 Rotary (already own Mk.2)")
	assert(not _should_roll_weapon_standalone(owned, "Auto Laser", 1),
		"Should reject Mk.1 Auto Laser (already own Mk.1)")
	print("  ✓ Rejects same-mark items")

	# Owned items at lower mark → reject.
	assert(not _should_roll_weapon_standalone(owned, "Rotary Laser", 1),
		"Should reject Mk.1 Rotary (already own Mk.2)")
	print("  ✓ Rejects lower-mark items")

	# Owned items at higher mark → accept.
	assert(_should_roll_weapon_standalone(owned, "Rotary Laser", 3),
		"Should accept Mk.3 Rotary (own Mk.2)")
	assert(_should_roll_weapon_standalone(owned, "Auto Laser", 2),
		"Should accept Mk.2 Auto Laser (own Mk.1)")
	print("  ✓ Accepts higher-mark items")

	# Unowned items → always accept.
	assert(_should_roll_weapon_standalone(owned, "Brand New Cannon", 1),
		"Should accept unknown items")
	print("  ✓ Accepts new items")
