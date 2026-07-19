extends SceneTree

# Sector Conditions — HULL/SHIELD META-SEED owner test (audit #2 fix, 2026-07-19).
# Guards the split-owner bug where run_state._seed_meta_stats_from_modules computed
# max_hull = 3 + pips (never adding Better Hull) while combat used 2 + pips + Better Hull.
# Now BOTH route through run.effective_max_hull() (base 2). Also guards the shield-count
# meta parity (Weak/Better Shields must scale the dock count like combat does).
# Run: godot --headless --script res://tools/test_conditions_hull.gd

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")

# Minimal ship stand-in exposing just module_hull_bonus — the field the Reinforced Hull
# part's apply() writes. Used to prove run.module_hull_pips() == a real part's contribution.
class StubHullShip:
	var module_hull_bonus: int = 0


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0
	var run = root.get_node("/root/Run")

	# ── (a) Better Hull, no modules: 2 + 0 + 3 = 5, max == current ────────────
	run.new_run()
	run.apply_conditions(["better_hull"])
	lines.append("(a) better_hull: max_hull=%d current_hull=%d (expect 5/5)" % [run.max_hull, run.current_hull])
	if run.max_hull != 5:
		lines.append("FAIL better_hull max_hull != 5 (Better Hull not folded into the meta seed)"); fails += 1
	if run.current_hull != run.max_hull:
		lines.append("FAIL current_hull != max_hull on fresh seed"); fails += 1
	if run.effective_max_hull() != 5:
		lines.append("FAIL effective_max_hull() != 5 under better_hull"); fails += 1

	# ── (b) conditionless fresh run: base 2 (the split-owner fix; dock was 3) ──
	run.new_run()
	run.apply_conditions([])
	lines.append("(b) conditionless: max_hull=%d current_hull=%d (expect 2/2 — dock now shows 2, not 3)"
		% [run.max_hull, run.current_hull])
	if run.max_hull != 2:
		lines.append("FAIL conditionless base hull != 2 (the latent 3-vs-2 bug)"); fails += 1
	if run.current_hull != 2:
		lines.append("FAIL conditionless current_hull != 2"); fails += 1
	if run.module_hull_pips() != 0:
		lines.append("FAIL module_hull_pips != 0 with no Reinforced Hull in the bay"); fails += 1

	# ── (c) Reinforced Hull Mk3 in the bay: pips=3 → 2+3=5; +Better Hull → 8 ──
	run.new_run()
	run.active_conditions = []
	var rh = PartCatalog.make_part("_make_reinforced_hull", 3)
	if rh == null:
		lines.append("FAIL could not build Reinforced Hull via PartCatalog"); fails += 1
	else:
		run.modules = [rh]
		var pips: int = run.module_hull_pips()
		lines.append("(c) reinforced_hull Mk3: module_hull_pips=%d (expect 3)" % pips)
		if pips != 3:
			lines.append("FAIL module_hull_pips != mini(mark,8)"); fails += 1
		run._seed_meta_stats_from_modules()
		lines.append("(c) reinforced_hull Mk3 seeded: max_hull=%d (expect 5 = 2+3)" % run.max_hull)
		if run.max_hull != 5:
			lines.append("FAIL reinforced-hull-only max_hull != 5"); fails += 1
		# Now stack Better Hull on the same bay: 2 + 3 + 3 = 8.
		run.active_conditions = ["better_hull"]
		run._seed_meta_stats_from_modules()
		lines.append("(c) reinforced_hull Mk3 + better_hull: max_hull=%d (expect 8 = 2+3+3)" % run.max_hull)
		if run.max_hull != 8:
			lines.append("FAIL reinforced+better_hull did not stack to 8"); fails += 1

	# ── (d) Weak Shields halves the dock's shield count vs baseline ────────────
	# Fresh run defaults to a Shield Core (base 10). Baseline seed → 10; weak → 5.
	run.new_run()
	run.apply_conditions([])
	var base_shield: int = run.max_shield
	lines.append("(d) baseline shield count = %d (expect 10 from the default Shield Core)" % base_shield)
	run.new_run()
	run.apply_conditions(["weak_shields"])
	var weak_shield: int = run.max_shield
	lines.append("(d) weak_shields count = %d (expect %d = half of baseline)" % [weak_shield, maxi(1, roundi(base_shield * 0.5))])
	if base_shield <= 0:
		lines.append("FAIL baseline shield count non-positive — cannot assess halving"); fails += 1
	elif weak_shield != maxi(1, roundi(base_shield * 0.5)):
		lines.append("FAIL Weak Shields did not scale the meta shield count"); fails += 1
	if run.current_shield != run.max_shield:
		lines.append("FAIL current_shield != max_shield after weak-shields seed"); fails += 1

	# ── (e) parity: player-side module_hull_bonus == run.module_hull_pips() ────
	# apply the SAME Reinforced Hull part(s) to a stub ship (mirrors the part's apply on the
	# live player) and confirm module_hull_bonus == module_hull_pips() across marks + the
	# mini(,8) cap, so player.apply_run_upgrades' max_hull = run.effective_max_hull() and the
	# dock seed can never diverge. (The full apply_run_upgrades needs a live Player scene; the
	# formula itself is one shared call — verified by code-reading, the module term by this.)
	run.new_run()
	run.active_conditions = []
	var parity_ok := true
	for mk in [1, 5, 8, 9]:  # 9 exercises the mini(mark,8) cap (pips stay 8)
		var part = PartCatalog.make_part("_make_reinforced_hull", mk)
		var stub := StubHullShip.new()
		part.apply(stub)
		run.modules = [part]
		var side_player: int = stub.module_hull_bonus
		var side_run: int = run.module_hull_pips()
		if side_player != side_run:
			parity_ok = false
			lines.append("FAIL parity Mk%d: player module_hull_bonus=%d != run module_hull_pips=%d" % [mk, side_player, side_run])
		# And the full formula equals what player.gd would set.
		var expect_max: int = 2 + side_run + int(run.cond_sum("player.hull_bonus"))
		if run.effective_max_hull() != expect_max:
			parity_ok = false
			lines.append("FAIL effective_max_hull Mk%d != 2+pips+cond" % mk)
	if parity_ok:
		lines.append("(e) parity OK: module_hull_bonus == module_hull_pips() across Mk 1/5/8/9 (incl. mini(,8) cap)")

	run.new_run()  # leave Run clean
	lines.append("CONDITIONS_HULL: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
