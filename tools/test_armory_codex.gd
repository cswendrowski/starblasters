extends SceneTree

# Armory codex tab: categories registered, factories enumerated per slot, blurbs
# resolve, and the list/detail render without crashing.

const ArmoryStrings = preload("res://scripts/armory_strings.gd")
const CodexScene = preload("res://scenes/enemy_codex.tscn")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Blurbs resolve for a sampling of items (incl. the new Swarm Launcher).
	_assert(ArmoryStrings.codex_for("_make_basic_blaster") != "", "blaster has a blurb")
	_assert(ArmoryStrings.codex_for("_make_swarm_launcher").contains("homing"), "swarm launcher blurb")
	_assert(ArmoryStrings.codex_for("_make_focus_mode").contains("FOCUS"), "focus blurb")
	_assert(ArmoryStrings.codex_for("_make_smart_bomb").contains("panic"), "smart bomb blurb")
	_assert(ArmoryStrings.codex_for("_nonexistent") == "", "missing factory -> empty (safe)")

	var codex = CodexScene.instantiate()
	root.add_child(codex)
	await process_frame
	await process_frame

	# Armory categories present (Primary/Secondary/Super/Modes).
	var armory_cats := []
	for c in codex._cats:
		if String(c.get("kind", "")) == "armory":
			armory_cats.append(String(c.get("label", "")))
	_assert(armory_cats.size() == 4, "4 armory categories (got %s)" % str(armory_cats))

	# Factories per slot.
	var prim: Array = codex._armory_factories({"slot": SlotTypes.SlotType.CANNON})
	_assert(prim.has("_make_basic_blaster") and not prim.has("_make_swarm_launcher"), "primary list has cannons, not secondaries")
	var sec: Array = codex._armory_factories({"slot": SlotTypes.SlotType.HARDPOINT_WING})
	_assert(sec.has("_make_swarm_launcher"), "secondary list has Swarm Launcher")
	var modes: Array = codex._armory_factories({"slot": SlotTypes.SlotType.SHIFT_MODE})
	_assert(modes.has("_make_focus_mode") and modes.has("_make_phase_shift") and modes.has("_make_hyper_mode"), "modes list has Focus/Phase/Hyper")

	# Navigate to the Secondary armory category + open the Swarm Launcher detail.
	var sec_idx := -1
	for i in codex._cats.size():
		if String(codex._cats[i].get("label", "")) == "Secondaries":
			sec_idx = i
	_assert(sec_idx >= 0, "found Secondaries category")
	codex._show_category(sec_idx)
	await process_frame
	_assert(codex._right_root.get_child_count() > 0, "armory list rendered rows")
	codex._show_item("_make_swarm_launcher")
	await process_frame
	_assert(codex._view == "detail", "item detail view active")
	# The detail pane should contain a label with the item's display name + blurb.
	_assert(_has_text(codex._right_root, "Swarm Launcher"), "detail shows the item name")
	_assert(_has_text(codex._right_root, "homing micro-missiles"), "detail shows the codex blurb")

	print("[test] ALL PASS")
	quit()


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	for c in node.get_children():
		if _has_text(c, needle):
			return true
	return false


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
