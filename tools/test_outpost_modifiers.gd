extends SceneTree

# #6: the outpost shows the active sector modifiers. Verify the formatter maps the
# raw keys to player-facing labels (and reads the sector-wide pool).

const OutpostScene = preload("res://scenes/outpost.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node("/root/Run")
	run.new_run()
	run.sector_map_cache = {"sector_modifiers": ["wanted", "dangerous"]}
	var op = OutpostScene.instantiate()
	root.add_child(op)
	await process_frame
	await process_frame
	var txt: String = String(op._modifiers_lbl.text)
	print("[test] modifiers line: '%s'" % txt)
	_assert(txt.contains("Wanted"), "shows Wanted")
	_assert(txt.contains("Dangerous"), "shows Dangerous")
	_assert(txt.begins_with("SECTOR:"), "labeled SECTOR:")

	# Empty pool -> standard conditions.
	run.sector_map_cache = {"sector_modifiers": []}
	op._refresh_status_panel()
	await process_frame
	_assert(String(op._modifiers_lbl.text).contains("standard"), "empty -> standard conditions")

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
