extends SceneTree

# Sector Conditions — Wildcard front-end pipe test (WP5). Covers the single
# Run.apply_conditions() entry: start-gate re-seed (No Starting Super/Mode),
# Starting Funds grant folded through award_bounty, active_conditions install,
# determinism through the pipe, baseline intactness, and mutex through the pipe.
# Run: godot --headless --script res://tools/test_conditions_wildcard.gd

const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0
	var run = root.get_node("/root/Run")

	# 1. No Starting Super + No Starting Mode + Starting Funds through the pipe.
	run.new_run()
	run.apply_conditions(["no_starting_super", "no_starting_mode", "starting_funds"])
	var has_super: bool = run.loadout_snapshot.has(SlotTypes.SlotType.DEVICE_BAY_1)
	var has_mode: bool = run.loadout_snapshot.has(SlotTypes.SlotType.SHIFT_MODE)
	lines.append("post-apply: has_super=%s has_mode=%s active=%d bounty=%d" % [
		str(has_super), str(has_mode), run.active_conditions.size(), int(run.bounty)])
	if has_super:
		lines.append("FAIL No Starting Super left a DEVICE_BAY_1 entry"); fails += 1
	if has_mode:
		lines.append("FAIL No Starting Mode left a SHIFT_MODE entry"); fails += 1
	if run.active_conditions.size() != 3:
		lines.append("FAIL expected 3 active conditions, got %d" % run.active_conditions.size()); fails += 1
	# Starting Funds = 500. Reward coupling CUT 2026-07-09 (bounty_mult identity 1.0), so the
	# grant lands EXACTLY 500 with no net-Threat scaling.
	var expected_bounty: int = 500
	lines.append("expected bounty (flat Starting Funds, coupling cut) = %d" % expected_bounty)
	if int(run.bounty) != expected_bounty:
		lines.append("FAIL bounty expected %d got %d" % [expected_bounty, int(run.bounty)]); fails += 1

	# 2. Determinism through the pipe — same roll args across two new_runs land
	#    identical active_conditions.
	run.new_run()
	run.apply_conditions(Conditions.roll(5, 4242))
	var picks_a: Array = run.active_conditions.duplicate()
	run.new_run()
	run.apply_conditions(Conditions.roll(5, 4242))
	var picks_b: Array = run.active_conditions.duplicate()
	lines.append("determinism a=%s b=%s" % [str(picks_a), str(picks_b)])
	if picks_a != picks_b:
		lines.append("FAIL pipe not deterministic across new_runs"); fails += 1

	# 3. Baseline intact — new_run alone keeps super + mode, bounty 0.
	run.new_run()
	var base_super: bool = run.loadout_snapshot.has(SlotTypes.SlotType.DEVICE_BAY_1)
	var base_mode: bool = run.loadout_snapshot.has(SlotTypes.SlotType.SHIFT_MODE)
	lines.append("baseline: has_super=%s has_mode=%s bounty=%d" % [
		str(base_super), str(base_mode), int(run.bounty)])
	if not base_super:
		lines.append("FAIL baseline lost DEVICE_BAY_1"); fails += 1
	if not base_mode:
		lines.append("FAIL baseline lost SHIFT_MODE"); fails += 1
	if int(run.bounty) != 0:
		lines.append("FAIL baseline bounty expected 0 got %d" % int(run.bounty)); fails += 1

	# 4. Mutex respected THROUGH the pipe across 30 seeds — installed
	#    active_conditions never carry two ids sharing a nonempty mutex group.
	var mutex_ok := true
	for s in range(30):
		run.new_run()
		run.apply_conditions(Conditions.roll(5, 9000 + s * 17))
		var groups_seen: Dictionary = {}
		for id in run.active_conditions:
			var grp: String = String(Conditions.CATALOG[id].get("group", ""))
			if grp != "":
				if groups_seen.has(grp):
					mutex_ok = false
				groups_seen[grp] = true
	lines.append("pipe mutex_ok over 30 seeds = %s" % str(mutex_ok))
	if not mutex_ok:
		lines.append("FAIL pipe installed two ids in same mutex group"); fails += 1

	lines.append("CONDITIONS_WILDCARD: " + ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
