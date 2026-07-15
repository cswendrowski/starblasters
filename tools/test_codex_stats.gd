extends SceneTree

# The Codex item detail now embeds the shared PartStatsView (full stats + a tappable Mk ladder),
# replacing the one-line blurb-only view — so the Codex and the outpost dock show the same numbers.

const CodexScene = preload("res://scenes/enemy_codex.tscn")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var codex = CodexScene.instantiate()
	root.add_child(codex)
	await process_frame
	await process_frame

	# Open the Primary (CANNON) armory category, then the basic blaster's detail.
	var prim_idx := -1
	for i in codex._cats.size():
		var c = codex._cats[i]
		if String(c.get("kind", "")) == "armory" and int(c.get("slot", -1)) == SlotTypes.SlotType.CANNON:
			prim_idx = i
			break
	_assert(prim_idx >= 0, "found the Primary armory category")
	codex._show_category(prim_idx)
	await process_frame
	codex._show_item("_make_basic_blaster")
	await process_frame
	_assert(codex._view == "detail", "item detail view active")

	# The detail pane now embeds a Mk ladder: an HBox of 9 chip buttons labelled 1..9.
	var ladder := _find_mark_ladder(codex._right_root)
	_assert(ladder != null, "detail embeds a 9-chip Mark ladder (PartStatsView)")
	# ...and a stats header for the previewed Mk (reference view: no "(current)" flag).
	_assert(_has_text(codex._right_root, "Mk.1 stats"), "detail shows the Mk stats header")
	_assert(not _has_text(codex._right_root, "(current)"), "reference view drops the (current) flag")
	# Tapping a higher Mk re-renders the stats box without error.
	var chip: Button = ladder.get_child(4)   # Mk.5
	chip.pressed.emit()
	await process_frame
	_assert(_has_text(codex._right_root, "Mk.5 stats"), "tapping Mk.5 previews that level")

	print("[test] ALL PASS")
	quit()


func _find_mark_ladder(node: Node) -> HBoxContainer:
	if node is HBoxContainer and node.get_child_count() == 9:
		var labels := ""
		var all_buttons := true
		for c in node.get_children():
			if not (c is Button):
				all_buttons = false
				break
			labels += String(c.text)
		if all_buttons and labels == "123456789":
			return node
	for c in node.get_children():
		var r := _find_mark_ladder(c)
		if r != null:
			return r
	return null


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String(node.text).contains(needle):
		return true
	for c in node.get_children():
		if _has_text(c, needle):
			return true
	return false


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg)
		quit(1)
