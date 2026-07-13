#!/usr/bin/env -S godot --script
# Test harness for Minigun weapon.
# Usage: godot --script tools/test_minigun.gd

extends SceneTree

const MinigunCannon = preload("res://scripts/parts/minigun_cannon.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

func _init() -> void:
	var mg = MinigunCannon.new()
	print("=== MINIGUN TEST ===")
	print("Display Name: %s" % mg.display_name)
	assert(mg.display_name == "Minigun", "Display name mismatch")

	print("Description: %s" % mg.description)
	assert(mg.description.contains("stream") or mg.description.contains("rapid"), "Description should describe the weapon type")

	# Note: base_damage, base_cooldown, base_ammo live in the .tres file (stats live in resources, not scripts).
	# A .new() instance won't have these populated until loaded from disk.
	print("Base Damage: %d (from .tres in production)" % mg.base_damage)
	print("Base Cooldown: %.4f (from .tres in production)" % mg.base_cooldown)
	print("Base Ammo: %d (from .tres in production)" % mg.base_ammo)

	var style = mg._weapon_style()
	print("Weapon Style: %d (MINIGUN=%d)" % [style, WS.WeaponStyle.MINIGUN])
	assert(style == WS.WeaponStyle.MINIGUN, "Weapon style should be MINIGUN")

	var sfx_kind = mg._fire_sfx_kind()
	print("Fire SFX Kind: %d (MINIGUN=%d)" % [sfx_kind, WS.FireSfxKind.MINIGUN])
	assert(sfx_kind == WS.FireSfxKind.MINIGUN, "SFX kind should be MINIGUN")

	# Test ammo scaling (same as machinegun: compound +20%/Mk).
	var ammo_mk1 = mg.ammo_at_mark(1)
	var ammo_mk5 = mg.ammo_at_mark(5)
	var ammo_mk9 = mg.ammo_at_mark(9)
	print("Ammo: Mk.1=%d, Mk.5=%d, Mk.9=%d" % [ammo_mk1, ammo_mk5, ammo_mk9])
	assert(ammo_mk1 == 1000, "Mk.1 ammo should be 1000")
	assert(ammo_mk9 > ammo_mk5, "Mk.9 ammo should be > Mk.5")
	assert(ammo_mk5 > ammo_mk1, "Mk.5 ammo should be > Mk.1")

	# Test knobs.
	var knobs = mg._mk_knobs()
	print("Knobs: %s" % knobs)
	assert("bullet_damage" in knobs, "Should have bullet_damage knob")
	assert("cooldown" in knobs, "Should have cooldown knob")

	print("✓ All Minigun tests passed!")

func _process(_d: float) -> bool:
	quit(0)
	return true
