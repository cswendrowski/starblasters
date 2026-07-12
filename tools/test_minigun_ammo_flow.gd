extends SceneTree

# Island 2 verification (2026-07-11): metered_primary._apply_visuals must stamp the ship's magazine CAP
# (ammo_max) from the Part's run-stamped ammo_max — which run_state seeds from ammo_at_mark(mark) and is
# already Condition-scaled — instead of the flat base_ammo export. For a compound-magazine weapon
# (Minigun: Mk1=1000 … Mk9≈4300) base_ammo only equals the Mk1 size, so the old path capped ammo_max
# below the mark-scaled current_ammo. This asserts cap == current after apply. Also asserts the Rotary
# Laser (the other metered primary — it overwrites ammo_max AFTER super) is unaffected.
# Run: godot --headless --script res://tools/test_minigun_ammo_flow.gd

const MinigunCannon = preload("res://scripts/parts/minigun_cannon.gd")
const RotaryLaser = preload("res://scripts/parts/rotary_laser_cannon.gd")

class MockShip extends Node:
	var ammo_max: int = -1
	var ammo: int = -1
	var ammo_recharge_rate: float = 0.0
	var bullet_scene = null
	var weapon_style: int = 0
	var fire_sfx_kind: int = 0
	func set_ammo(v: int) -> void:
		ammo = v

func _init() -> void:
	var fails := 0

	# --- Minigun at Mk5: simulate run_state stamping the scaled compound magazine onto the Part. ---
	# .new() leaves base_ammo at the script default 0 (the 1000 lives in minigun.tres) — deliberately,
	# to prove the fix no longer depends on base_ammo: with the OLD code ship.ammo_max would land at 0.
	var mg = MinigunCannon.new()
	mg.mark = 5
	var mag: int = mg.ammo_at_mark(5)      # run_state seeds current_ammo + ammo_max to this (scaled) value
	mg.current_ammo = mag
	mg.ammo_max = mag
	var ship := MockShip.new()
	root.add_child(ship)
	mg._apply_visuals(ship)
	print("[test] MINIGUN Mk5: mag=%d base_ammo=%d ship.ammo_max=%d ship.ammo=%d"
		% [mag, mg.base_ammo, ship.ammo_max, ship.ammo])
	if ship.ammo_max != mag:
		print("[test] FAIL minigun cap not stamped from Part.ammo_max (%d != %d)" % [ship.ammo_max, mag]); fails += 1
	if ship.ammo != mag:
		print("[test] FAIL minigun current not seeded to mag"); fails += 1
	if ship.ammo_max != ship.ammo:
		print("[test] FAIL minigun cap/current MISMATCH (the bug)"); fails += 1
	ship.free()

	# --- Minigun fallback: no run stamp (ammo_max = -1) → scaled base_ammo curve (dev/headless equip). ---
	var mg2 = MinigunCannon.new()
	mg2.base_ammo = 1000       # emulate the .tres seed present on a disk-loaded Part
	mg2.mark = 1
	mg2.current_ammo = -1
	mg2.ammo_max = -1
	var ship2 := MockShip.new()
	root.add_child(ship2)
	mg2._apply_visuals(ship2)
	print("[test] MINIGUN uninit fallback: ship.ammo_max=%d (expect base_ammo 1000)" % ship2.ammo_max)
	if ship2.ammo_max != 1000:
		print("[test] FAIL uninit fallback should use base_ammo curve"); fails += 1
	ship2.free()

	# --- Rotary Laser (other metered primary): overwrites ammo_max AFTER super → unaffected by the fix. ---
	var rl = RotaryLaser.new()
	rl.mark = 5
	var rl_mag: int = rl.ammo_at_mark(5)
	rl.current_ammo = rl_mag
	rl.ammo_max = rl_mag
	var ship3 := MockShip.new()
	root.add_child(ship3)
	rl._apply_visuals(ship3)
	print("[test] ROTARY Mk5: ammo_at_mark=%d ship.ammo_max=%d (rotary sets it post-super)"
		% [rl_mag, ship3.ammo_max])
	if ship3.ammo_max != rl.ammo_at_mark(5):
		print("[test] FAIL rotary ammo_max should equal its own post-super ammo_at_mark(mark)"); fails += 1
	ship3.free()

	print("[test] MINIGUN_AMMO_FLOW: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit()
