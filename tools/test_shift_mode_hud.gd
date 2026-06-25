extends SceneTree

# Shift-Mode HUD wiring (unified system): the mode meter swaps with the active mode.
# Instantiates the combat UI + a player, binds them, swaps modes, and checks the label
# text + bar colour + charge PIPS follow. (Headless — verifies signal wiring, not pixels;
# the visual read is Roman's once combat boots.)

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
	_assert(ui._focus_bar_fill != null, "mode duration bar exists")
	_assert(ui._mode_pip_container != null, "mode pip container exists")
	# Default Focus.
	_assert(ui._mode_label.text == "FOCUS", "label FOCUS by default (got '%s')" % ui._mode_label.text)

	var loadout = player.get_node("Loadout")

	# Hyper -> label HYPER, bar orange.
	_equip("_make_hyper_mode", 1, loadout, player)
	await process_frame
	_assert(ui._mode_label.text.begins_with("HYPER"), "label HYPER (got '%s')" % ui._mode_label.text)
	_assert(_close(ui._focus_bar_fill.color, ui._MODE_COL_HYPER) or _close(ui._focus_bar_fill.color, ui._MODE_COL_HYPER_ON), "bar is Hyper colour")

	# Phase -> label PHASE, bar purple, charges shown as pips.
	_equip("_make_phase_shift", 1, loadout, player)
	await process_frame
	_assert(ui._mode_label.text == "PHASE", "label 'PHASE' (got '%s')" % ui._mode_label.text)
	_assert(_close(ui._focus_bar_fill.color, ui._MODE_COL_PHASE), "bar is Phase colour")
	_assert(ui._mode_pips.size() == 2, "Phase shows 2 charge pips (got %d)" % ui._mode_pips.size())
	_assert(_lit(ui) == 2, "both pips lit at full charges (got %d)" % _lit(ui))
	# Spend a charge -> one pip dims.
	player.mode_charges = 1
	player.mode_charges_changed.emit(1, 2)
	await process_frame
	_assert(_lit(ui) == 1, "one pip lit after spending a charge (got %d)" % _lit(ui))

	# Back to Focus -> label FOCUS, bar cyan, 3 pips.
	_equip("_make_focus_mode", 1, loadout, player)
	await process_frame
	_assert(ui._mode_label.text == "FOCUS", "label back to FOCUS (got '%s')" % ui._mode_label.text)
	_assert(_close(ui._focus_bar_fill.color, ui._MODE_COL_FOCUS), "bar is Focus colour")
	_assert(ui._mode_pips.size() == 3, "Focus shows 3 charge pips (got %d)" % ui._mode_pips.size())

	print("[test] ALL PASS")
	quit()


func _equip(factory: String, mk: int, loadout, player) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.SHIFT_MODE)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.SHIFT_MODE, part)


# Count lit charge pips (frame 1 = on).
func _lit(ui) -> int:
	var n := 0
	for p in ui._mode_pips:
		if p != null and is_instance_valid(p) and int(p.frame) == 1:
			n += 1
	return n


func _close(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.01 and abs(a.g - b.g) < 0.01 and abs(a.b - b.b) < 0.01


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
