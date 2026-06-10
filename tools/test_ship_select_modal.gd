extends SceneTree

# Ship-select modal smoke test (Roman 2026-06-09): open the overlay, confirm it builds its UI without
# error, drive a variant + color selection, and verify the confirm callback fires with the chosen
# (variant, color). No autoloads needed (the overlay only depends on UiTheme). Run:
# godot --headless --script res://tools/test_ship_select_modal.gd

const RESULT := "res://tools/_ship_select_result.txt"
const ShipSelect = preload("res://scripts/ui/ship_select_overlay.gd")
var _t := 0
var _overlay: CanvasLayer = null
var _got_variant := -1
var _got_color: Color = Color(0, 0, 0, 0)
var _fired := false

func _process(_dt: float) -> bool:
	_t += 1
	if _t == 1:
		_overlay = ShipSelect.open(root, 0, Color(0.9, 0.16, 0.16), func(v, c):
			_fired = true
			_got_variant = v
			_got_color = c)
		return false
	if _t < 4:
		return false
	var lines: Array = []
	var fails := 0
	if _overlay == null or not is_instance_valid(_overlay):
		lines.append("FAIL overlay not created"); fails += 1
		_finish(lines, fails); return true
	# UI built? Expect a dim ColorRect + a CenterContainer with the panel.
	var built := _overlay.get_child_count() >= 2
	lines.append("overlay children: %d (built=%s)" % [_overlay.get_child_count(), built])
	if not built:
		lines.append("FAIL overlay UI not built"); fails += 1
	# Drive a selection: ship C (idx 2) + a teal color, then confirm.
	_overlay._on_select_variant(2)
	_overlay._set_color(Color(0.2, 0.8, 0.65))
	_overlay._on_begin()
	if not _fired:
		lines.append("FAIL confirm callback did not fire"); fails += 1
	lines.append("callback: variant=%d color=%s" % [_got_variant, str(_got_color)])
	if _got_variant != 2:
		lines.append("FAIL expected variant 2, got %d" % _got_variant); fails += 1
	if _got_color.g < 0.7 or _got_color.b < 0.5:
		lines.append("FAIL expected teal color"); fails += 1
	lines.append("SHIP SELECT MODAL: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines, fails)
	return true

func _finish(lines: Array, _fails: int) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
