extends SceneTree

# Custom run-seed override test (2026-07-14). Covers:
#   (a) new_run(seed) reproduces run_seed AND the derived outpost 2d6 charge rolls,
#       and flags seed_was_custom true;
#   (b) new_run() with no arg → random seed, seed_was_custom false;
#   (c) PatrolStart.parse_seed rules (empty/int/negative/text-hash/"0" edge);
#   (d) the full pipe — a custom seed reproduces the blind-condition split.
# Run: godot --headless --script res://tools/test_run_seed.gd

const PatrolStart = preload("res://scripts/screens/patrol_start.gd")
const COND_SEED_SALT := 0x51EC7C0D   # matches patrol_start.COND_SEED_SALT (blind-roll decorrelation)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0
	var run = root.get_node("/root/Run")

	# (a) Custom seed reproduces run_seed + the charge rolls derived from it.
	run.new_run(12345)
	var seed_a: int = int(run.run_seed)
	var repair_a: int = int(run.repair_charges)
	var ammo_a: int = int(run.ammo_restock_charges)
	var custom_a: bool = bool(run.seed_was_custom)
	run.new_run(12345)
	var seed_b: int = int(run.run_seed)
	var repair_b: int = int(run.repair_charges)
	var ammo_b: int = int(run.ammo_restock_charges)
	lines.append("(a) seed=%d/%d repair=%d/%d ammo=%d/%d custom=%s" % [
		seed_a, seed_b, repair_a, repair_b, ammo_a, ammo_b, str(custom_a)])
	if seed_a != 12345 or seed_b != 12345:
		lines.append("FAIL custom seed not applied (want 12345)"); fails += 1
	if repair_a != repair_b or ammo_a != ammo_b:
		lines.append("FAIL charge rolls not reproduced from custom seed"); fails += 1
	if not custom_a:
		lines.append("FAIL seed_was_custom expected true on override"); fails += 1

	# (b) No override → random seed, seed_was_custom false.
	run.new_run()
	lines.append("(b) random new_run: custom=%s" % str(run.seed_was_custom))
	if run.seed_was_custom:
		lines.append("FAIL seed_was_custom expected false on random run"); fails += 1

	# (c) parse_seed rules (pure static).
	var p_empty := PatrolStart.parse_seed("")
	var p_int := PatrolStart.parse_seed("42")
	var p_neg := PatrolStart.parse_seed("-7")
	var p_ws := PatrolStart.parse_seed("   ")
	var p_zero := PatrolStart.parse_seed("0")
	var p_banana1 := PatrolStart.parse_seed("BANANA")
	var p_banana2 := PatrolStart.parse_seed("BANANA")
	lines.append("(c) ''=%d '42'=%d '-7'=%d '   '=%d '0'=%d 'BANANA'=%d/%d" % [
		p_empty, p_int, p_neg, p_ws, p_zero, p_banana1, p_banana2])
	if p_empty != 0: lines.append("FAIL '' should map to 0"); fails += 1
	if p_int != 42: lines.append("FAIL '42' should map to 42"); fails += 1
	if p_neg != -7: lines.append("FAIL '-7' should map to -7"); fails += 1
	if p_ws != 0: lines.append("FAIL whitespace should trim to 0"); fails += 1
	if p_zero != 0: lines.append("FAIL '0' should map to 0 (documented random edge)"); fails += 1
	if p_banana1 == 0: lines.append("FAIL 'BANANA' should hash to nonzero"); fails += 1
	if p_banana1 != p_banana2: lines.append("FAIL 'BANANA' hash not stable"); fails += 1

	# (d) Full pipe — a custom seed reproduces the blind-condition split.
	run.new_run(777)
	run.apply_conditions(Conditions.roll_split(2, 1, int(run.run_seed) ^ COND_SEED_SALT))
	var picks_a: Array = run.active_conditions.duplicate()
	run.new_run(777)
	run.apply_conditions(Conditions.roll_split(2, 1, int(run.run_seed) ^ COND_SEED_SALT))
	var picks_b: Array = run.active_conditions.duplicate()
	lines.append("(d) picks a=%s b=%s" % [str(picks_a), str(picks_b)])
	if picks_a != picks_b:
		lines.append("FAIL custom seed did not reproduce blind-condition split"); fails += 1

	# Leave Run clean for any downstream shared-state readers.
	run.new_run()

	lines.append("RUN_SEED: " + ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
