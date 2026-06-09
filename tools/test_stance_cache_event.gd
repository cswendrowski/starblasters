extends SceneTree

# Stance Module Cache signal event: it's registered, and salvaging it stows a
# Shift-mode module (Phase/Hyper) into the player's inventory via the standard
# grant path.

const SignalEventScene = preload("res://scenes/signal_event.tscn")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ev = SignalEventScene.instantiate()
	root.add_child(ev)
	await process_frame
	await process_frame

	# Registered in the catalog with id "stance_cache".
	var ids := []
	for e in ev._events():
		ids.append(String(e.get("id", "")))
	_assert("stance_cache" in ids, "stance_cache event is registered (ids: %s)" % str(ids))

	# Salvaging stows a SHIFT_MODE module into inventory.
	var run = root.get_node("/root/Run")
	run.inventory.clear()
	ev._do_stance_cache()
	await process_frame
	_assert(run.inventory.size() >= 1, "a part was stowed (%d in inventory)" % run.inventory.size())
	var stowed = run.inventory[run.inventory.size() - 1]
	_assert(int(stowed.slot_type) == int(SlotTypes.SlotType.SHIFT_MODE), "stowed part is a SHIFT_MODE module")
	var dn := String(stowed.display_name)
	_assert(dn == "Phase" or dn == "Hyper Mode", "stowed a real mode (Phase/Hyper), got '%s'" % dn)
	print("[test] stance cache granted: %s" % dn)

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
