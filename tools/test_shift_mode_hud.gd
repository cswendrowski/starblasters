extends SceneTree

# Shift-Mode HUD wiring (unified system): the mode meter swaps with the active mode.
# Retargeted 2026-07-15 at the decomposed ModeStatus widget (scenes/hud/
# hud_mode_status.tscn) after the HUD split — ui.gd no longer owns the meter.
# Instantiates the widget + a player, binds them, swaps modes, and checks the
# label text + charge PIPS follow, and that the pips hold the fixed purple
# meter colour (Roman 2026-07-12 — per-mode pip colours retired). (Headless —
# verifies signal wiring, not pixels; the visual read is Roman's in combat.)

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const ModeStatusScene = preload("res://scenes/hud/hud_mode_status.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hud = ModeStatusScene.instantiate()
	root.add_child(hud)
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	hud.bind_player(player)
	await process_frame

	var label: Label = hud.get_node("ModeLabel")
	_assert(label != null, "mode label exists")
	_assert(hud.get_node("TimerBar") != null, "mode duration bar exists")
	_assert(hud._lights.size() > 0, "charge pips exist")
	# Default Focus.
	_assert(label.text == "FOCUS", "label FOCUS by default (got '%s')" % label.text)

	var loadout = player.get_node("Loadout")

	# Hyper -> label HYPER; pips keep the fixed purple meter colour.
	_equip("_make_hyper_mode", 1, loadout, player)
	await process_frame
	_assert(label.text.begins_with("HYPER"), "label HYPER (got '%s')" % label.text)
	_assert(_close(hud._lights[0].modulate, hud._pip_lit), "pips stay fixed purple on Hyper")

	# Phase -> label PHASE, charges shown as pips.
	_equip("_make_phase_shift", 1, loadout, player)
	await process_frame
	_assert(label.text == "PHASE", "label 'PHASE' (got '%s')" % label.text)
	_assert(_close(hud._lights[0].modulate, hud._pip_lit), "pips stay fixed purple on Phase")
	_assert(_shown(hud) == 2, "Phase shows 2 charge pips (got %d)" % _shown(hud))
	_assert(_lit(hud) == 2, "both pips lit at full charges (got %d)" % _lit(hud))
	# Spend a charge -> one pip dims.
	player.mode_charges = 1
	player.mode_charges_changed.emit(1, 2)
	await process_frame
	_assert(_lit(hud) == 1, "one pip lit after spending a charge (got %d)" % _lit(hud))

	# Back to Focus -> label FOCUS, 3 pips.
	_equip("_make_focus_mode", 1, loadout, player)
	await process_frame
	_assert(label.text == "FOCUS", "label back to FOCUS (got '%s')" % label.text)
	_assert(_shown(hud) == 3, "Focus shows 3 charge pips (got %d)" % _shown(hud))

	print("[test] ALL PASS")
	quit()


func _equip(factory: String, mk: int, loadout, player) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.SHIFT_MODE)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.SHIFT_MODE, part)


# Count visible charge pips (hidden = beyond this mode's max charges).
func _shown(hud) -> int:
	var n := 0
	for p in hud._lights:
		if p != null and is_instance_valid(p) and p.visible:
			n += 1
	return n


# Count lit charge pips (frame 1 = on) among the visible ones.
func _lit(hud) -> int:
	var n := 0
	for p in hud._lights:
		if p != null and is_instance_valid(p) and p.visible and int(p.frame) == 1:
			n += 1
	return n


func _close(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.01 and abs(a.g - b.g) < 0.01 and abs(a.b - b.b) < 0.01


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
