extends SceneTree

# Click-routing test for HD UI. Reproduces the shop's setup — content_scale
# swapped to 1920×1080 via HdViewportScope — then fires a synthetic left-click
# at each test button's VISUAL centre and checks whether the button actually
# receives `pressed`. If a click misses, scans vertically to measure the
# offset (the reported "click lands below the button" bug). Tests a plain
# button AND one inside a ScrollContainer (the shop's structure) to isolate
# whether the container is the culprit.
#
# Run NON-headless (real window → faithful input transform); result is written
# to captures/hd_click_result.txt. Via tools/test_hd_click.ps1.

const OUT := "res://captures/hd_click_result.txt"
var _lines: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _log(s: String) -> void:
	_lines.append(s)


func _run() -> void:
	var scope := HdViewportScope.attach(root, Vector2i(1920, 1080))
	await process_frame
	await process_frame

	var vp := root.get_viewport()
	_log("window.size = %s" % str(get_root().size))
	_log("content_scale_size = %s" % str(get_root().content_scale_size))
	_log("viewport visible_rect = %s" % str(vp.get_visible_rect().size))

	# --- Test 1: plain button on a CanvasLayer ---
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var plain := Button.new()
	plain.text = "PLAIN"
	plain.position = Vector2(820, 440)
	plain.custom_minimum_size = Vector2(280, 90)
	cl.add_child(plain)

	# --- Test 2: button inside a ScrollContainer (shop card structure) ---
	var cl2 := CanvasLayer.new()
	root.add_child(cl2)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(200, 200)
	scroll.custom_minimum_size = Vector2(400, 500)
	scroll.size = Vector2(400, 500)
	cl2.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	# Pad with spacer rows so the target sits partway down the scroll content.
	for i in range(3):
		var pad := Button.new()
		pad.text = "pad %d" % i
		pad.custom_minimum_size = Vector2(0, 90)
		vbox.add_child(pad)
	var scrolled := Button.new()
	scrolled.text = "SCROLLED"
	scrolled.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(scrolled)

	await process_frame
	# --- Test 3: button in the ROOT CANVAS (no CanvasLayer) — this is how
	# main_menu/run_summary/signal_event host their UI. Suspected to be offset
	# under the runtime content_scale swap, unlike CanvasLayer-hosted UI.
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_ctrl)
	var rootcanvas := Button.new()
	rootcanvas.text = "ROOTCANVAS"
	rootcanvas.position = Vector2(820, 700)
	rootcanvas.custom_minimum_size = Vector2(280, 90)
	rootcanvas.size = Vector2(280, 90)
	root_ctrl.add_child(rootcanvas)

	await process_frame
	await process_frame
	await process_frame

	_probe("plain (canvaslayer)", plain)
	_probe("scrolled (canvaslayer)", scrolled)
	_probe("rootcanvas", rootcanvas)

	# Write results.
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
		f.close()
	for l in _lines:
		print("[hdclick] " + l)
	if scope:
		scope.free()
	quit()


# Fire a click at the button's visual centre; if it misses, scan ±vertical to
# find the real hit band and report the offset.
func _probe(label: String, btn: Button) -> void:
	var rect := btn.get_global_rect()
	var center := rect.get_center()
	_log("--- %s ---" % label)
	_log("  global_rect = %s  center = %s" % [str(rect), str(center)])

	var hit_center := _click_at(btn, center)
	_log("  click at visual center -> %s" % ("HIT" if hit_center else "MISS"))

	if not hit_center:
		# Scan vertically (±200px) to find where a click actually lands on it.
		var found := []
		for dy in range(-200, 201, 5):
			if _click_at(btn, center + Vector2(0, dy)):
				found.append(dy)
		if found.size() > 0:
			_log("  real hit y-offsets from center: %d..%d (mid %d)" % [found[0], found[-1], (found[0] + found[-1]) / 2])
		else:
			_log("  no vertical offset hit it within ±200px")


func _click_at(btn: Button, pos: Vector2) -> bool:
	var got := {"v": false}
	var cb := func(): got["v"] = true
	btn.pressed.connect(cb)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	root.push_input(down, false)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	root.push_input(up, false)
	btn.pressed.disconnect(cb)
	return got["v"]
