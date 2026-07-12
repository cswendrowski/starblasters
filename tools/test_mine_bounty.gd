extends SceneTree

# Mine-scene bounty assertion (island-cleanup 2026-07-11). Instantiates every field-mine scene headless
# and verifies the shared mine_base bounty pipeline: each mine's base bounty_value is preserved, and the
# Ordnance-Disposal Condition (grant.mine_bounty) + event field (mine_bonus_bounty) bonus is applied on
# top exactly once — for the four enemy_core mines (via mine_base.super._ready()) AND the tether mine
# (via the shared MineBase.apply_mine_bounty_bonus static helper).
# Run: godot --headless --script res://tools/test_mine_bounty.gd

func _initialize() -> void:
	_run.call_deferred()

# scene path -> base bounty_value (author intent, before any Condition/event bonus)
const MINES := {
	"res://scenes/enemies/enemy_mine.tscn": 1,
	"res://scenes/enemies/enemy_mine_armored.tscn": 1,
	"res://scenes/enemies/enemy_mine_shield.tscn": 0,
	"res://scenes/enemies/enemy_mine_smart.tscn": 2,
	"res://scenes/enemies/enemy_mine_gravity.tscn": 0,
	"res://scenes/enemies/enemy_mine_tether.tscn": 0,
}

func _instantiate_bounty(path: String) -> int:
	var ps: PackedScene = load(path)
	var m: Node = ps.instantiate()
	root.add_child(m)          # _ready() runs synchronously → bounty bonus applied by now
	var bv: int = int(m.bounty_value)
	root.remove_child(m)
	m.free()                   # immediate free; cancels the _ready deferreds cleanly
	return bv

func _run() -> void:
	var lines: Array = []
	var fails := 0
	var run = root.get_node("/root/Run")

	# Phase A — NO conditions / no event bonus: bounty_value must equal the author base exactly.
	run.new_run()
	run.mine_bonus_bounty = 0
	run.active_conditions = []
	for path in MINES:
		var base: int = int(MINES[path])
		var got: int = _instantiate_bounty(path)
		lines.append("no-bonus %s => %d (expect %d)" % [String(path).get_file(), got, base])
		if got != base:
			lines.append("FAIL base bounty drift"); fails += 1

	# Phase B — Ordnance Disposal (grant.mine_bounty) + a +3 event mine_bonus_bounty. Expected bonus is
	# read from Run so the assertion tracks the catalog, not a hardcoded number.
	run.new_run()
	run.mine_bonus_bounty = 3
	run.active_conditions = ["ordnance_disposal"]
	var bonus: int = int(run.mine_bonus_bounty) + int(run.cond_sum("grant.mine_bounty"))
	lines.append("bonus components: mine_bonus_bounty=%d + grant.mine_bounty=%d = %d"
		% [int(run.mine_bonus_bounty), int(run.cond_sum("grant.mine_bounty")), bonus])
	if bonus <= 0:
		lines.append("FAIL expected a positive bonus for Phase B"); fails += 1
	for path in MINES:
		var expected: int = int(MINES[path]) + bonus
		var got: int = _instantiate_bounty(path)
		lines.append("bonus %s => %d (expect %d)" % [String(path).get_file(), got, expected])
		if got != expected:
			lines.append("FAIL bounty bonus not applied exactly once"); fails += 1

	# Phase C — shared hazard flags. The four enemy_core mines (via mine_base) get recycle_passes=0;
	# tether keeps its own offscreen_mode=NONE (recycle_passes stays the enemy_base default -1). All
	# five share is_hazard=true, has_ship_vfx=false, auto_rotate=false, display_scale=1.0.
	run.new_run()
	run.mine_bonus_bounty = 0
	run.active_conditions = []
	var core_mines := [
		"res://scenes/enemies/enemy_mine.tscn",
		"res://scenes/enemies/enemy_mine_shield.tscn",
		"res://scenes/enemies/enemy_mine_smart.tscn",
		"res://scenes/enemies/enemy_mine_gravity.tscn",
	]
	for path in core_mines:
		var ps: PackedScene = load(path)
		var m: Node = ps.instantiate()
		root.add_child(m)
		var ok: bool = m.is_hazard == true and m.has_ship_vfx == false and m.auto_rotate == false \
			and is_equal_approx(m.display_scale, 1.0) and int(m.recycle_passes) == 0
		lines.append("flags %s => hazard=%s vfx=%s rot=%s scale=%s recycle=%s"
			% [String(path).get_file(), m.is_hazard, m.has_ship_vfx, m.auto_rotate,
				str(m.display_scale), str(m.recycle_passes)])
		if not ok:
			lines.append("FAIL core-mine shared flags"); fails += 1
		root.remove_child(m)
		m.free()
	# Tether keeps its bespoke flags (offscreen_mode=NONE, recycle_passes default -1) + shared hazard tells.
	var tps: PackedScene = load("res://scenes/enemies/enemy_mine_tether.tscn")
	var tm: Node = tps.instantiate()
	root.add_child(tm)
	var tok: bool = tm.is_hazard == true and tm.has_ship_vfx == false and tm.auto_rotate == false \
		and is_equal_approx(tm.display_scale, 1.0) and int(tm.offscreen_mode) == tm.OffscreenMode.NONE
	lines.append("flags tether => hazard=%s vfx=%s rot=%s scale=%s offscreen=%s recycle=%s"
		% [tm.is_hazard, tm.has_ship_vfx, tm.auto_rotate, str(tm.display_scale),
			str(tm.offscreen_mode), str(tm.recycle_passes)])
	if not tok:
		lines.append("FAIL tether shared flags"); fails += 1
	root.remove_child(tm)
	tm.free()

	run.new_run()  # leave Run clean
	lines.append("MINE_BOUNTY: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
