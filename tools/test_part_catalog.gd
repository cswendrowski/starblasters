#!/usr/bin/env -S godot --script
# Test harness for part catalog weapons.
# Usage: godot --script tools/test_part_catalog.gd

extends SceneTree

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

func _init() -> void:
	print("=== PART CATALOG TEST ===")

	# Test that autocannon and minigun are in the pool.
	var pool = PartCatalog._all_pool()
	var has_autocannon = false
	var has_minigun = false
	var has_machinegun = false

	for entry in pool:
		if entry["factory"] == "_make_autocannon":
			has_autocannon = true
			print("✓ Found _make_autocannon in pool")
		elif entry["factory"] == "_make_minigun":
			has_minigun = true
			print("✓ Found _make_minigun in pool")
		elif entry["factory"] == "_make_machinegun":
			has_machinegun = true
			print("✗ ERROR: _make_machinegun found in pool (should be removed)")

	assert(has_autocannon, "Autocannon not found in pool")
	assert(has_minigun, "Minigun not found in pool")
	assert(not has_machinegun, "Machinegun should NOT be in pool")

	# Test that we can create autocannon via factory.
	var ac = PartCatalog._make_by_name("_make_autocannon", Slots.SlotType.CANNON)
	assert(ac != null, "Failed to create autocannon")
	assert(ac.display_name == "Autocannon", "Autocannon display name mismatch")
	assert(ac._weapon_style() == WS.WeaponStyle.AUTOCANNON, "Autocannon weapon style mismatch")
	print("✓ Autocannon factory works correctly")

	# Test that we can create minigun via factory.
	var mg = PartCatalog._make_by_name("_make_minigun", Slots.SlotType.CANNON)
	assert(mg != null, "Failed to create minigun")
	assert(mg.display_name == "Minigun", "Minigun display name mismatch")
	assert(mg._weapon_style() == WS.WeaponStyle.MINIGUN, "Minigun weapon style mismatch")
	print("✓ Minigun factory works correctly")

	print("✓ All part catalog tests passed!")
	quit(0)
