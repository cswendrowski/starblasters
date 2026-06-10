#!/usr/bin/env -S godot --script
# Test harness for weapon SFX pools.
# Usage: godot --script tools/test_weapon_sfx.gd

extends SceneTree

const WeaponSfx = preload("res://scripts/effects/weapon_sfx.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")

func _init() -> void:
	print("=== WEAPON SFX TEST ===")

	# Check that the SFX pools are accessible (not null).
	print("Checking SFX pools...")
	assert(WeaponSfx.AUTOCANNON_CLIPS.size() > 0, "AUTOCANNON_CLIPS should have clips")
	print("  AUTOCANNON_CLIPS: %d clips" % WeaponSfx.AUTOCANNON_CLIPS.size())
	assert(WeaponSfx.AUTOCANNON_CLIPS.size() == 9, "AUTOCANNON_CLIPS should have 9 clips")

	assert(WeaponSfx.MINIGUN_CLIPS.size() > 0, "MINIGUN_CLIPS should have clips")
	print("  MINIGUN_CLIPS: %d clips" % WeaponSfx.MINIGUN_CLIPS.size())
	assert(WeaponSfx.MINIGUN_CLIPS.size() == 12, "MINIGUN_CLIPS should have 12 clips")

	# Check sfx_kind_string mappings.
	print("Checking sfx_kind_string mappings...")
	var ac_str = WS.sfx_kind_string(WS.FireSfxKind.AUTOCANNON)
	print("  AUTOCANNON -> '%s'" % ac_str)
	assert(ac_str == "autocannon", "AUTOCANNON should map to 'autocannon'")

	var mg_str = WS.sfx_kind_string(WS.FireSfxKind.MINIGUN)
	print("  MINIGUN -> '%s'" % mg_str)
	assert(mg_str == "minigun", "MINIGUN should map to 'minigun'")

	# Verify all clips preload correctly (no null entries).
	print("Verifying clip loads...")
	for i in range(WeaponSfx.AUTOCANNON_CLIPS.size()):
		assert(WeaponSfx.AUTOCANNON_CLIPS[i] != null, "AUTOCANNON clip %d is null" % i)
	print("  ✓ All AUTOCANNON clips loaded")

	for i in range(WeaponSfx.MINIGUN_CLIPS.size()):
		assert(WeaponSfx.MINIGUN_CLIPS[i] != null, "MINIGUN clip %d is null" % i)
	print("  ✓ All MINIGUN clips loaded")

	print("✓ All weapon SFX tests passed!")
	quit(0)
