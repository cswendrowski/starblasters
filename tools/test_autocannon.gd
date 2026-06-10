#!/usr/bin/env -S godot --script
# Test harness for Autocannon weapon.
# Usage: godot --script tools/test_autocannon.gd

extends SceneTree

const AutocannonCannon = preload("res://scripts/parts/autocannon_cannon.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

func _init() -> void:
	var ac = AutocannonCannon.new()
	print("=== AUTOCANNON TEST ===")
	print("Display Name: %s" % ac.display_name)
	assert(ac.display_name == "Autocannon", "Display name mismatch")

	print("Description: %s" % ac.description)
	assert(ac.description.contains("spin-up"), "Description should mention spin-up")

	print("Base Damage: %d" % ac.base_damage)
	assert(ac.base_damage == 5, "Base damage should be 5")

	print("Base Cooldown: %.4f" % ac.base_cooldown)
	assert(ac.base_cooldown == 0.1333, "Base cooldown should be 0.1333")

	print("Base Ammo: %d" % ac.base_ammo)
	assert(ac.base_ammo == 1000, "Base ammo should be 1000")

	var style = ac._weapon_style()
	print("Weapon Style: %d (AUTOCANNON=%d)" % [style, WS.WeaponStyle.AUTOCANNON])
	assert(style == WS.WeaponStyle.AUTOCANNON, "Weapon style should be AUTOCANNON")

	var sfx_kind = ac._fire_sfx_kind()
	print("Fire SFX Kind: %d (AUTOCANNON=%d)" % [sfx_kind, WS.FireSfxKind.AUTOCANNON])
	assert(sfx_kind == WS.FireSfxKind.AUTOCANNON, "SFX kind should be AUTOCANNON")

	# Test ammo scaling.
	var ammo_mk1 = ac.ammo_at_mark(1)
	var ammo_mk5 = ac.ammo_at_mark(5)
	var ammo_mk9 = ac.ammo_at_mark(9)
	print("Ammo: Mk.1=%d, Mk.5=%d, Mk.9=%d" % [ammo_mk1, ammo_mk5, ammo_mk9])
	assert(ammo_mk1 == 1000, "Mk.1 ammo should be 1000")
	assert(ammo_mk9 > ammo_mk5, "Mk.9 ammo should be > Mk.5")
	assert(ammo_mk5 > ammo_mk1, "Mk.5 ammo should be > Mk.1")

	print("✓ All Autocannon tests passed!")
	quit(0)
