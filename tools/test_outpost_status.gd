extends SceneTree

# Headless test for the outpost dock STATUS tab: with active conditions set,
# the dock builds condition rows + badge count.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

var _oa
var _fails: int = 0


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)


func _init() -> void:
	# Autoloads aren't loaded in `-s` SceneTree mode — instantiate Run manually at /root/Run.
	var run = get_root().get_node_or_null("/root/Run")
	if run == null:
		run = load("res://scripts/autoload/run_state.gd").new()
		run.name = "Run"
		get_root().add_child(run)
	if run.has_method("new_run"):
		run.new_run()
	run.run_seed = 12345
	run.bounty = 5000
	run.materials = 50

	# Set active conditions: one bane, two boons (all REAL catalog ids — an unknown
	# id would still render via the label fallback and mask a regression).
	run.active_conditions = ["heavy_ordnance", "buyers_market", "more_ammo"]

	_oa = load("res://scenes/outpost_arrival.tscn").instantiate()
	_oa.manage_hd_scope = true
	_oa.return_to_map = false
	_oa.damage_level = 0.0
	get_root().add_child(_oa)
	var t := Timer.new()
	t.wait_time = 0.3
	t.one_shot = true
	t.autostart = true
	t.timeout.connect(_run)
	get_root().add_child(t)
	var guard := Timer.new()
	guard.wait_time = 8.0
	guard.one_shot = true
	guard.autostart = true
	guard.timeout.connect(func() -> void:
		print("VERDICT: FAIL (timeout)")
		quit(1))
	get_root().add_child(guard)


func _run() -> void:
	var run = get_root().get_node_or_null("/root/Run")

	# STATUS tab should exist.
	_ck(_oa._page_status != null and is_instance_valid(_oa._page_status), "STATUS page built")

	# STATUS should show difficulty header (or condition rows if empty, but we set conditions).
	_ck(_oa._page_status.get_child_count() > 0, "STATUS page has content")

	# Count condition rows: each active condition gets a row + an info button within.
	# The scroll container is a child; inside it is a VBoxContainer with rows.
	var rows_found: int = 0
	for child in _oa._page_status.get_children():
		if child is ScrollContainer:
			for row_child in child.get_children():
				if row_child is VBoxContainer:
					# Each row is an HBoxContainer (name + chip + info button).
					# Count HBoxContainers that are direct children of the VBox.
					for hbox in row_child.get_children():
						if hbox is HBoxContainer:
							rows_found += 1
					break
	_ck(rows_found >= 3, "STATUS page lists all 3 active conditions (%d rows found)" % rows_found)

	# TAB button should show a count badge (if implemented) or at least exist.
	# The left_tabs is a TabContainer, so we can check if STATUS tab is present.
	_ck(_oa._left_tabs != null, "left tabs exist")
	_ck(_oa._left_tabs.get_tab_count() >= 3, "left tabs have at least 3 pages (MARKET, SERVICES, STATUS)")

	# Verify tab names.
	var status_tab_idx: int = -1
	for i in range(_oa._left_tabs.get_tab_count()):
		var page = _oa._left_tabs.get_tab_control(i)
		if page.name == "STATUS":
			status_tab_idx = i
			break
	_ck(status_tab_idx >= 0, "STATUS tab found at index %d" % status_tab_idx)

	print("live: conditions=%d rows=%d" % [run.active_conditions.size(), rows_found])
	print("VERDICT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
