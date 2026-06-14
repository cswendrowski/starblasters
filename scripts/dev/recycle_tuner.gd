extends Control

# RecycleTuner — Pillar 2, step 1 (the spec's mandated FIRST deliverable:
# docs/recycling_system_pillar2_2026-06-04.md). Live-tunes the enemy fly-back
# recycle: pre-cycle hold, re-entry inset, ghost scale/tint, fly-back duration +
# target. Persists to user://tuners/recycle.json via RecycleController (same source
# the runtime reads), so tuned values take effect in-game on next combat.
#
# Follows the house tuner contract (scripts/dev/ui_designer.gd): JSON save/load,
# Reset, Esc-to-close, and a mandatory Copy-GDScript button that emits a paste-ready
# RecycleController.DEFAULTS literal.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const RecycleController = preload("res://scripts/effects/recycle_controller.gd")

# Knob spec: key, label, min, max, step.
const KNOBS := [
	["hold_min", "Pre-cycle hold MIN (s)", 0.0, 3.0, 0.05],
	["hold_max", "Pre-cycle hold MAX (s)", 0.0, 3.0, 0.05],
	["entry_inset", "Re-entry inset (px)", 0.0, 60.0, 1.0],
	["fly_scale", "Ghost scale", 0.1, 1.0, 0.01],
	["fly_time", "Fly-back time (s)", 0.3, 5.0, 0.05],
	["fly_target_y", "Fly-back target Y (px)", -60.0, 40.0, 1.0],
	["tint_r", "Tint R", 0.0, 1.0, 0.01],
	["tint_g", "Tint G", 0.0, 1.0, 0.01],
	["tint_b", "Tint B", 0.0, 1.0, 0.01],
	["tint_a", "Tint A", 0.0, 1.0, 0.01],
]

var _values: Dictionary = {}
var _spins: Dictionary = {}        # key -> SpinBox
var _status_label: Label = null

# --- Preview state machine (mimics enemy_core._start_cycle timing) ---
var _ghost: Node2D = null
var _ghost_base: Polygon2D = null
var _preview_rect: Rect2 = Rect2()
var _phase: String = "hold"        # hold -> fly -> done(loop)
var _phase_t: float = 0.0
var _hold_dur: float = 0.7
var _from_y: float = 0.0
var _to_y: float = 0.0
var _entry_x: float = 0.0


var _hd_scope: HdViewportScope = null

func _ready() -> void:
	# Render at HD (1920×1080) instead of the cramped 480×270 native viewport, so the
	# knob rail + preview are actually usable (Roman 2026-06-11). Freed with the scene.
	_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_from_config()
	_build_ui()
	_build_preview()
	set_process(true)


func _seed_from_config() -> void:
	var cfg := RecycleController.config()
	for spec in KNOBS:
		_values[spec[0]] = float(cfg.get(spec[0], RecycleController.DEFAULTS[spec[0]]))


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# Left rail: title + knobs + buttons.
	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(360, 0)
	rail.add_theme_constant_override("separation", 6)
	root.add_child(rail)

	var title := Label.new()
	title.text = "RECYCLE TUNER"
	title.add_theme_font_size_override("font_size", 22)
	rail.add_child(title)

	for spec in KNOBS:
		rail.add_child(_make_knob_row(spec))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	rail.add_child(btn_row)
	_add_button(btn_row, "Save", _on_save)
	_add_button(btn_row, "Load", _on_load)
	_add_button(btn_row, "Reset", _on_reset)
	var btn_row2 := HBoxContainer.new()
	btn_row2.add_theme_constant_override("separation", 8)
	rail.add_child(btn_row2)
	_add_button(btn_row2, "Copy GDScript", _on_copy_snippet)
	_add_button(btn_row2, "Back (Esc)", _on_back)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_status_label.text = "Editing recycle.json"
	rail.add_child(_status_label)

	# Right: preview panel (a SubViewport-free in-place draw region).
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var preview_host := Control.new()
	preview_host.name = "PreviewHost"
	preview_host.clip_contents = true
	panel.add_child(preview_host)


func _make_knob_row(spec: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = String(spec[1])
	lbl.custom_minimum_size = Vector2(210, 0)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = float(spec[2])
	spin.max_value = float(spec[3])
	spin.step = float(spec[4])
	spin.value = float(_values[spec[0]])
	spin.custom_minimum_size = Vector2(110, 0)
	var key: String = String(spec[0])
	spin.value_changed.connect(func(v): _on_knob(key, v))
	row.add_child(spin)
	_spins[key] = spin
	return row


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_knob(key: String, v: float) -> void:
	_values[key] = v


# --- Live preview ---------------------------------------------------------

func _build_preview() -> void:
	var host := get_node_or_null("HBoxContainer/PanelContainer/PreviewHost") as Control
	if host == null:
		# Find it regardless of container nesting.
		host = find_child("PreviewHost", true, false) as Control
	if host == null:
		return
	_ghost = Node2D.new()
	host.add_child(_ghost)
	# Upward-pointing triangle stands in for a recycling enemy.
	_ghost_base = Polygon2D.new()
	_ghost_base.polygon = PackedVector2Array([Vector2(0, -10), Vector2(7, 8), Vector2(-7, 8)])
	_ghost_base.color = Color(0.9, 0.9, 0.95)
	_ghost.add_child(_ghost_base)
	host.resized.connect(_recompute_preview_rect)
	call_deferred("_recompute_preview_rect")


func _recompute_preview_rect() -> void:
	var host := find_child("PreviewHost", true, false) as Control
	if host == null:
		return
	_preview_rect = Rect2(Vector2.ZERO, host.size)
	_restart_preview()


func _restart_preview() -> void:
	_phase = "hold"
	_phase_t = 0.0
	_hold_dur = randf_range(float(_values.hold_min), float(_values.hold_max))
	var w: float = max(40.0, _preview_rect.size.x)
	var h: float = max(40.0, _preview_rect.size.y)
	# Map the playfield band re-entry to the preview width using the inset ratio.
	var inset_ratio: float = clampf(float(_values.entry_inset) / 108.0, 0.0, 0.45)
	_entry_x = randf_range(w * inset_ratio, w * (1.0 - inset_ratio))
	_from_y = h - 14.0
	# fly_target_y is screen-space (-20 ≈ just off the top); map to preview top.
	_to_y = lerp(0.0, -20.0, 1.0) + 12.0  # a touch below the panel top so it stays visible
	if _ghost:
		_ghost.position = Vector2(_entry_x, _from_y)
		_ghost.visible = false


func _process(delta: float) -> void:
	if _ghost == null:
		return
	_phase_t += delta
	match _phase:
		"hold":
			_ghost.visible = false
			if _phase_t >= _hold_dur:
				_phase = "fly"
				_phase_t = 0.0
				_ghost.visible = true
		"fly":
			var t: float = clampf(_phase_t / max(0.05, float(_values.fly_time)), 0.0, 1.0)
			var s: float = float(_values.fly_scale)
			_ghost.scale = Vector2(s, s)
			_ghost_base.color = RecycleController.tint(_values)
			_ghost.position = Vector2(_entry_x, lerp(_from_y, _to_y, t))
			if t >= 1.0:
				_phase = "done"
				_phase_t = 0.0
		"done":
			_ghost.visible = false
			if _phase_t >= 0.5:
				_restart_preview()


# --- Persistence + snippet ------------------------------------------------

func _on_save() -> void:
	if RecycleController.save(_values):
		_set_status("Saved → %s" % RecycleController.CONFIG_PATH)
	else:
		_set_status("Save FAILED")


func _on_load() -> void:
	RecycleController.invalidate()
	_seed_from_config()
	for key in _spins.keys():
		(_spins[key] as SpinBox).value = float(_values[key])
	_set_status("Loaded from disk")


func _on_reset() -> void:
	for spec in KNOBS:
		_values[spec[0]] = float(RecycleController.DEFAULTS[spec[0]])
		(_spins[spec[0]] as SpinBox).value = float(_values[spec[0]])
	_set_status("Reset to defaults")


func _on_copy_snippet() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied (%d chars)" % s.length())


# Emit a paste-ready RecycleController.DEFAULTS literal so tuned values can be
# baked into the controller's defaults.
func _build_snippet() -> String:
	var lines := PackedStringArray()
	lines.append("# Paste into scripts/effects/recycle_controller.gd (DEFAULTS):")
	lines.append("const DEFAULTS := {")
	lines.append("\t\"hold_min\": %.2f, \"hold_max\": %.2f," % [_values.hold_min, _values.hold_max])
	lines.append("\t\"entry_inset\": %.1f," % _values.entry_inset)
	lines.append("\t\"fly_scale\": %.2f, \"fly_time\": %.2f, \"fly_target_y\": %.1f," % [_values.fly_scale, _values.fly_time, _values.fly_target_y])
	lines.append("\t\"tint_r\": %.2f, \"tint_g\": %.2f, \"tint_b\": %.2f, \"tint_a\": %.2f," % [_values.tint_r, _values.tint_g, _values.tint_b, _values.tint_a])
	lines.append("}")
	return "\n".join(lines)


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
