extends SceneTree

# Outpost dup-equipped safeguard test (Roman 2026-06-10): verifies _ensure_no_duplicate_equipped
# MOVES (not copies) duplicate cannons — keeps the higher-mark copy in the pool, removes the dup,
# pushes it to the hold, never displaces the Blaster at [0], and remaps active_cannon_idx. Run:
# godot --headless --script res://tools/test_outpost_safeguard.gd

const RESULT := "res://tools/_outpost_safeguard_result.txt"
const Outpost = preload("res://scripts/outpost.gd")

# Minimal mock part with the fields the safeguard reads.
class MockPart extends RefCounted:
	var display_name: String
	var mark: int
	func _init(n: String, m: int) -> void:
		display_name = n
		mark = m

# Minimal mock Run (the safeguard only reads loadout_snapshot / cannon_pool / weapon_storage /
# active_cannon_idx via `in` + property access).
class MockRun extends RefCounted:
	var loadout_snapshot: Dictionary = {}
	var cannon_pool: Array = []
	var weapon_storage: Array = []
	var active_cannon_idx: int = 0

func _init() -> void:
	var lines: Array = []
	var fails := 0

	var run := MockRun.new()
	var blaster := MockPart.new("Energy Blaster", 1)
	var rotary_lo := MockPart.new("Rotary Laser", 1)
	var rotary_hi := MockPart.new("Rotary Laser", 3)   # higher mark — should be KEPT
	var auto := MockPart.new("Auto Laser", 2)
	# Pool: [blaster, rotary_lo, auto, rotary_hi] — rotary duplicated at idx 1 + 3.
	run.cannon_pool = [blaster, rotary_lo, auto, rotary_hi]
	run.active_cannon_idx = 1   # pointing at the LOW rotary (will be removed)

	Outpost._ensure_no_duplicate_equipped(run)

	# Pool should now be [blaster, auto, rotary_hi] (low rotary removed); order of kept entries
	# preserved by index. rotary_lo moved to hold.
	var names := run.cannon_pool.map(func(c): return c.display_name)
	lines.append("pool after: %s" % str(names))
	var rotary_count := 0
	for c in run.cannon_pool:
		if c.display_name == "Rotary Laser":
			rotary_count += 1
	if rotary_count != 1:
		lines.append("FAIL pool still has %d Rotary Lasers (expect 1)" % rotary_count); fails += 1
	# The kept rotary must be the Mk.3.
	for c in run.cannon_pool:
		if c.display_name == "Rotary Laser" and c.mark != 3:
			lines.append("FAIL kept the wrong (lower-mark) Rotary"); fails += 1
	# Blaster still at [0].
	if run.cannon_pool.is_empty() or run.cannon_pool[0].display_name != "Energy Blaster":
		lines.append("FAIL blaster no longer at [0]"); fails += 1
	# The removed low rotary is in the hold (moved, not duplicated).
	var hold_has_lo := false
	for s in run.weapon_storage:
		if s.display_name == "Rotary Laser" and s.mark == 1:
			hold_has_lo = true
	if not hold_has_lo:
		lines.append("FAIL removed dup not in hold"); fails += 1
	lines.append("hold: %s" % str(run.weapon_storage.map(func(c): return "%s Mk%d" % [c.display_name, c.mark])))
	# active_cannon_idx must be valid + not point past the new pool.
	if run.active_cannon_idx < 0 or run.active_cannon_idx >= run.cannon_pool.size():
		lines.append("FAIL active_cannon_idx %d out of range" % run.active_cannon_idx); fails += 1
	lines.append("active_cannon_idx remapped: %d (pool size %d)" % [run.active_cannon_idx, run.cannon_pool.size()])

	lines.append("OUTPOST SAFEGUARD: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
