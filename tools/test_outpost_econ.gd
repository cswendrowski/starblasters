extends SceneTree

# OutpostEcon — pure headless math test (no scene). Exercises the single static
# cost engine (scripts/systems/outpost_econ.gd) under representative Sector-
# Condition sets: baseline, the repair pairs, restock pairs, buy-price pairs,
# stock pairs, Mk-bias clamps, the upgrade flag/mult matrix, and null-safety.
# Run: godot --headless --script res://tools/test_outpost_econ.gd

var _fails: int = 0
var _lines: Array = []


func _initialize() -> void:
	var run = _get_run()

	# --- null-safety: null run → baseline everywhere ---
	_eq_d(OutpostEcon.repair_costs(null, 250), {"bounty": 250, "mats": 1}, "null repair = 250/1")
	_eq(OutpostEcon.restock_cost(null, 100), 100, "null restock = base")
	_eqf(OutpostEcon.restock_per_round(null, 1.0), 1.0, "null per_round = base")
	_eq_d(OutpostEcon.upgrade_costs(null, 3, 175), {"mats": 3, "bounty": 175}, "null upgrade = mk/base")
	_eq(OutpostEcon.offer_price(null, 116), 116, "null price = base")
	_eq(OutpostEcon.stock_count(null, 5), 5, "null stock = base")
	_eq(OutpostEcon.bias_mark(null, 4, 9), 4, "null bias = mk")

	# --- baseline (no conditions) ---
	_apply(run, [])
	_eq_d(OutpostEcon.repair_costs(run, 250), {"bounty": 250, "mats": 1}, "baseline repair 250/1")
	_eq(OutpostEcon.restock_cost(run, 100), 100, "baseline restock primary 100")
	_eq(OutpostEcon.restock_cost(run, 60), 60, "baseline restock secondary 60")
	_eq(OutpostEcon.restock_cost(run, 120), 120, "baseline restock super 120")
	_eqf(OutpostEcon.restock_per_round(run, 1.0), 1.0, "baseline per_round 1.0")
	_eq_d(OutpostEcon.upgrade_costs(run, 3, 175), {"mats": 3, "bounty": 175}, "baseline upgrade mk3 3/175")
	_eq(OutpostEcon.offer_price(run, 116), 116, "baseline price passthrough")
	_eq(OutpostEcon.stock_count(run, 5), 5, "baseline stock 5")
	_eq(OutpostEcon.bias_mark(run, 4, 9), 4, "baseline mk passthrough")

	# --- repair pairs (all one mutex group, so tested singly) ---
	_apply(run, ["costly_repairs"])   # bounty ×1.5, 1 mat
	_eq_d(OutpostEcon.repair_costs(run, 250), {"bounty": 375, "mats": 1}, "costly_repairs 375/1")
	_apply(run, ["cheap_repairs"])    # no bounty, +1 mat → 2 mats
	_eq_d(OutpostEcon.repair_costs(run, 250), {"bounty": 0, "mats": 2}, "cheap_repairs 0/2")
	_apply(run, ["easy_repairs"])     # bounty only, no mats
	_eq_d(OutpostEcon.repair_costs(run, 250), {"bounty": 250, "mats": 0}, "easy_repairs 250/0")
	_apply(run, ["complex_repairs"])  # bounty + 2 mats
	_eq_d(OutpostEcon.repair_costs(run, 250), {"bounty": 250, "mats": 2}, "complex_repairs 250/2")

	# --- restock pairs ---
	_apply(run, ["costly_restock"])   # ×1.5
	_eq(OutpostEcon.restock_cost(run, 100), 150, "costly_restock 150")
	_eqf(OutpostEcon.restock_per_round(run, 1.0), 1.5, "costly per_round 1.5")
	_apply(run, ["cheap_restock"])    # ×0.7
	_eq(OutpostEcon.restock_cost(run, 100), 70, "cheap_restock 70")
	_eq(OutpostEcon.restock_cost(run, 1), 1, "cheap_restock floors at 1")
	_eqf(OutpostEcon.restock_per_round(run, 1.0), 0.7, "cheap per_round 0.7")

	# --- buy-price pairs ---
	_apply(run, ["galactic_tariffs"])  # ×1.2
	_eq(OutpostEcon.offer_price(run, 100), 120, "tariffs 120")
	_apply(run, ["buyers_market"])     # ×0.8
	_eq(OutpostEcon.offer_price(run, 100), 80, "buyers_market 80")

	# --- stock pairs ---
	_apply(run, ["market_scarcity"])   # -1
	_eq(OutpostEcon.stock_count(run, 5), 4, "scarcity 4")
	_eq(OutpostEcon.stock_count(run, 1), 1, "scarcity floors at 1")
	_apply(run, ["market_surplus"])    # +1
	_eq(OutpostEcon.stock_count(run, 5), 6, "surplus 6")

	# --- Mk-bias clamps ---
	_apply(run, ["shoddy_imports"])    # -1
	_eq(OutpostEcon.bias_mark(run, 4, 9), 3, "shoddy 4→3")
	_eq(OutpostEcon.bias_mark(run, 1, 9), 1, "shoddy floors at 1")
	_apply(run, ["quality_goods"])     # +1
	_eq(OutpostEcon.bias_mark(run, 4, 9), 5, "quality 4→5")
	_eq(OutpostEcon.bias_mark(run, 9, 9), 9, "quality clamps to cap")

	# --- upgrade flag/mult matrix ---
	_apply(run, ["complex_upgrades"])  # mat_mult 1.5
	_eq_d(OutpostEcon.upgrade_costs(run, 4, 200), {"mats": 6, "bounty": 200}, "complex_upgrades 6/200")
	_apply(run, ["cheap_upgrades"])    # no bounty
	_eq_d(OutpostEcon.upgrade_costs(run, 4, 200), {"mats": 4, "bounty": 0}, "cheap_upgrades 4/0")
	_apply(run, ["costly_upgrades"])   # bounty_mult 1.5
	_eq_d(OutpostEcon.upgrade_costs(run, 4, 200), {"mats": 4, "bounty": 300}, "costly_upgrades 4/300")
	_apply(run, ["easy_upgrades"])     # no mats
	_eq_d(OutpostEcon.upgrade_costs(run, 4, 200), {"mats": 0, "bounty": 200}, "easy_upgrades 0/200")

	for l in _lines:
		print("[test] " + l)
	print("OUTPOST_ECON: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _get_run():
	var run = root.get_node_or_null("/root/Run")
	if run == null:
		run = load("res://scripts/autoload/run_state.gd").new()
		run.name = "Run"
		root.add_child(run)
	if run.has_method("new_run"):
		run.new_run()
	return run


func _apply(run, ids: Array) -> void:
	run.active_conditions = ids


func _eq(got: int, want: int, msg: String) -> void:
	if got == want:
		_lines.append("ok: %s (=%d)" % [msg, got])
	else:
		_fails += 1
		_lines.append("FAIL: %s — got %d want %d" % [msg, got, want])


func _eqf(got: float, want: float, msg: String) -> void:
	if is_equal_approx(got, want):
		_lines.append("ok: %s (=%s)" % [msg, str(got)])
	else:
		_fails += 1
		_lines.append("FAIL: %s — got %s want %s" % [msg, str(got), str(want)])


func _eq_d(got: Dictionary, want: Dictionary, msg: String) -> void:
	var ok := true
	for k in want:
		if int(got.get(k, -99999)) != int(want[k]):
			ok = false
	if ok:
		_lines.append("ok: %s (%s)" % [msg, str(got)])
	else:
		_fails += 1
		_lines.append("FAIL: %s — got %s want %s" % [msg, str(got), str(want)])
