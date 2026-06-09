extends SceneTree

# Shift-Mode Phase 3 HUD wiring: the mode meter (reused focus-bar slot) swaps with
# the active mode. Instantiates the combat UI + a player, binds them, swaps modes,
# checks the label text + bar colour follow. (Headless — verifies signal wiring,
# not pixels; the visual read is Roman's once combat boots.)

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const UiScene = preload("res://scenes/ui.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ui = UiScene.instantiate()
	root.add_child(ui)
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	ui.bind_player(player)
	await process_frame

	_assert(ui._mode_label != null, "mode label exists")
	_assert(ui._focus_bar_fill != null, "mode bar exists")
	# Default Focus.
	_assert(ui._mode_label.text == "FOCUS", "label FOCUS by default (got '%s')" % ui._mode_label.text)

	var loadout = player.get_node("Loadout")

	# Hyper -> label HYPER, bar orange.
	_equip("_make_hyper_mode", 1, loadout, player)
	await process_frame
	_assert(ui._mode_label.text.begins_with("HYPER"), "label HYPER (got '%s')" % ui._mode_label.text)
	_assert(_close(ui._focus_bar_fill.color, ui._MODE_COL_HYPER) or _close(ui._focus_bar_fill.color, ui._MODE_COL_HYPER_ON), "bar is Hyper colour")

	# Phase -> label shows charge count, bar purple.
	_equip("_make_phase_shift", 1, loadout, player)
	await process_frame
	_assert(ui._mode_label.text == "PHASE 2/2", "label 'PHASE 2/2' (got '%s')" % ui._mode_label.text)
	_assert(_close(ui._focus_bar_fill.color, ui._MODE_COL_PHASE), "bar is Phase colour")
	# Spend a charge -> label updates.
	player.phase_charges = 1
	player.phase_charges_changed.emit(1, 2)
	await process_frame
	_assert(ui._mode_label.text == "PHASE 1/2", "label updates to 'PHASE 1/2' (got '%s')" % ui._mode_label.text)

	# Back to Focus -> label FOCUS, bar cyan.
	_equip("_make_focus_mode", 1, loadout, player)
	await process_frame
	_assert(ui._mode_label.text == "FOCUS", "label back to FOCUS (got '%s')" % ui._mode_label.text)
	_assert(_close(ui._focus_bar_fill.color, ui._MODE_COL_FOCUS), "bar is Focus colour")

	print("[test] ALL PASS")
	quit()


func _equip(factory: String, mk: int, loadout, player) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.SHIFT_MODE)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.SHIFT_MODE, part)


func _close(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.01 and abs(a.g - b.g) < 0.01 and abs(a.b - b.b) < 0.01


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
