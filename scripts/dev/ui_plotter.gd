extends Control

# UI Plotter — dev tool for laying out any in-game screen against the
# annotated 16px grid we use for the V3 sector map. Pick a screen from
# the modal; the plotter loads it underneath, draws the grid overlay on
# top, and shows a live mouse-cell readout. Replaces the obsolete dev
# sector_map_v3 scene whose grid was the original inspiration.
#
# Mouse clicks fall through to the loaded screen (overlay is no-input),
# so interactive widgets in the underlying screen still respond — you can
# poke at a button while reading its grid cell off the HUD.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const GridOverlay = preload("res://scripts/dev/grid_overlay.gd")

# Hardcoded list of user-reachable screens. Skipping dev-only scenes since
# the plotter is meant for player-facing layout work. Add entries here as
# new player surfaces ship.
const SCREENS := [
	{ "label": "Main Menu",       "path": "res://scenes/main_menu.tscn" },
	{ "label": "Sector Map",      "path": "res://scenes/sector_map_v3.tscn" },
	{ "label": "Outpost",         "path": "res://scenes/outpost.tscn" },
	{ "label": "Signal Event",    "path": "res://scenes/signal_event.tscn" },
	{ "label": "Onboarding",      "path": "res://scenes/onboarding.tscn" },
	{ "label": "Hangar",          "path": "res://scenes/hangar.tscn" },
	{ "label": "Run Summary",     "path": "res://scenes/run_summary.tscn" },
	{ "label": "Cleared Summary", "path": "res://scenes/cleared_summary.tscn" },
	{ "label": "Enemy Codex",     "path": "res://scenes/enemy_codex.tscn" },
	{ "label": "Combat",          "path": "res://scenes/main.tscn" },
]

var _loaded_host: Control = null
var _overlay: Node2D = null
var _hud_readout: Label = null
var _hud_status: Label = null
var _pick_modal: CanvasLayer = null
var _current_screen_label: String = ""
var _overflow_layer: CanvasLayer = null
var _overflow_visible: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Loaded screen sits below the overlay. Plain Control container so any
	# Control or Node2D scene drops in without surprise transforms.
	_loaded_host = Control.new()
	_loaded_host.name = "LoadedHost"
	_loaded_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loaded_host.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_loaded_host)
	_build_overlay()
	_build_hud()
	# Default screen = Main Menu so the plotter has something to draw on
	# from the jump (otherwise the user opens it and sees only the grid).
	_load_screen(SCREENS[0])


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1000
	add_child(layer)
	_overlay = GridOverlay.new()
	_overlay.name = "GridOverlay"
	layer.add_child(_overlay)


func _build_hud() -> void:
	# HUD lives one layer above the grid so the readout text stays legible
	# over the brightest grid lines.
	var layer := CanvasLayer.new()
	layer.layer = 1001
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Top bar: title + current screen + pick button + back button.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.position = Vector2(4, 2)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(top)

	_hud_status = Label.new()
	_hud_status.text = "UI Plotter"
	UiTheme.style_label(_hud_status, UiTheme.LabelKind.CAPTION)
	_hud_status.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9, 1.0))
	_hud_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hud_status.add_theme_constant_override("outline_size", 3)
	top.add_child(_hud_status)

	var pick_btn := Button.new()
	pick_btn.text = "Pick Screen"
	pick_btn.custom_minimum_size = Vector2(80, 14)
	UiTheme.style_button(pick_btn, true)
	pick_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pick_btn.pressed.connect(_show_pick_modal)
	top.add_child(pick_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(48, 14)
	UiTheme.style_button(back_btn, true)
	back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	back_btn.pressed.connect(_back_to_dev_menu)
	top.add_child(back_btn)

	# Bottom readout: live mouse cell + hotkey legend. Anchored bottom-left
	# so it stays out of the way of common HUD elements (which cluster top).
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 1)
	bottom.position = Vector2(4, 250)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_hud_readout = Label.new()
	UiTheme.style_label(_hud_readout, UiTheme.LabelKind.CAPTION)
	_hud_readout.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9, 1.0))
	_hud_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hud_readout.add_theme_constant_override("outline_size", 3)
	bottom.add_child(_hud_readout)
	var hint := Label.new()
	hint.text = "[G] grid  [L] labels  [O] overflow  [Esc] back"
	UiTheme.style_label(hint, UiTheme.LabelKind.CAPTION)
	hint.add_theme_color_override("font_color", Color(0.7, 0.85, 0.9, 0.9))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 3)
	bottom.add_child(hint)


func _process(_delta: float) -> void:
	if _hud_readout == null or _overlay == null:
		return
	var mp: Vector2 = get_global_mouse_position()
	var cs: int = _overlay.cell_size
	var col: int = int(floor(mp.x / float(cs)))
	var row: int = int(floor(mp.y / float(cs)))
	_hud_readout.text = "cell (%d, %d)  px (%d, %d)  size %d" % [
		col, row, int(mp.x), int(mp.y), cs,
	]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _pick_modal != null and is_instance_valid(_pick_modal):
				_close_pick_modal()
				get_viewport().set_input_as_handled()
				return
			_back_to_dev_menu()
			get_viewport().set_input_as_handled()
		KEY_G:
			_overlay.cycle_cell_size()
			get_viewport().set_input_as_handled()
		KEY_L:
			_overlay.show_labels = not _overlay.show_labels
			get_viewport().set_input_as_handled()
		KEY_O:
			_overflow_visible = not _overflow_visible
			_refresh_overflow_outlines()
			get_viewport().set_input_as_handled()


func _back_to_dev_menu() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _load_screen(entry: Dictionary) -> void:
	for c in _loaded_host.get_children():
		c.queue_free()
	var path: String = String(entry.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		_hud_status.text = "UI Plotter — missing: %s" % path
		return
	var packed: PackedScene = load(path)
	if packed == null:
		_hud_status.text = "UI Plotter — failed to load: %s" % path
		return
	var inst = packed.instantiate()
	# Control-typed screens need a full-rect anchor so they fill the host;
	# Node2D scenes draw at their own coords already.
	if inst is Control:
		inst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loaded_host.add_child(inst)
	_current_screen_label = String(entry.get("label", path))
	_hud_status.text = "UI Plotter — %s" % _current_screen_label
	# Walk the freshly-loaded screen once it's settled; defers a frame so
	# anchors-and-offsets-preset calls in the loaded scene's _ready land
	# before we measure.
	call_deferred("_audit_loaded_screen")


func _audit_loaded_screen() -> void:
	if _loaded_host == null or _loaded_host.get_child_count() == 0:
		return
	UiTheme.assert_inside_viewport(_loaded_host)
	_refresh_overflow_outlines()


# Walks the loaded screen's Control descendants and draws a red outline
# rect around any whose global rect exceeds the viewport. Toggled by [O].
# Outlines clear on every screen swap or every keypress refresh — cheap
# to redraw, so we don't try to cache.
func _refresh_overflow_outlines() -> void:
	if _overflow_layer != null and is_instance_valid(_overflow_layer):
		_overflow_layer.queue_free()
	_overflow_layer = null
	if not _overflow_visible:
		return
	_overflow_layer = CanvasLayer.new()
	_overflow_layer.layer = 1050  # above grid, below pick-modal
	add_child(_overflow_layer)
	if _loaded_host == null:
		return
	var vp_rect: Rect2 = get_viewport().get_visible_rect().grow(1)
	_collect_and_draw_overflow(_loaded_host, vp_rect)


func _collect_and_draw_overflow(n: Node, vp_rect: Rect2) -> void:
	if n is Control:
		var c: Control = n
		if c.visible and c.size.x > 0.0 and c.size.y > 0.0:
			var r: Rect2 = c.get_global_rect()
			if not vp_rect.encloses(r):
				var box := ColorRect.new()
				box.color = Color(0, 0, 0, 0)
				box.position = r.position
				box.size = r.size
				box.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_overflow_layer.add_child(box)
				# Draw the outline via a child Line2D — ColorRect can't outline.
				var line := Line2D.new()
				line.width = 1.0
				line.default_color = Color(1.0, 0.25, 0.25, 0.95)
				line.points = PackedVector2Array([
					r.position,
					Vector2(r.end.x, r.position.y),
					r.end,
					Vector2(r.position.x, r.end.y),
					r.position,
				])
				_overflow_layer.add_child(line)
	for child in n.get_children():
		_collect_and_draw_overflow(child, vp_rect)


# ---------------------------------------------------------------------------
# Pick Screen modal — vertical list of buttons, one per SCREENS entry.
# ---------------------------------------------------------------------------

func _show_pick_modal() -> void:
	if _pick_modal != null and is_instance_valid(_pick_modal):
		return
	# First consumer of UiTheme.make_modal — shared factory replaces the
	# 30-line CanvasLayer + dim + panel + vbox boilerplate that every
	# modal in the codebase used to hand-roll.
	var m := UiTheme.make_modal(1100, Vector2(160, 0))
	var v: VBoxContainer = m.vbox
	v.add_theme_constant_override("separation", 3)
	var head := Label.new()
	head.text = "Pick Screen"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(head, UiTheme.LabelKind.HEADER)
	v.add_child(head)
	for entry in SCREENS:
		var btn := Button.new()
		btn.text = String(entry.label)
		btn.custom_minimum_size = Vector2(140, 16)
		UiTheme.style_button(btn, true)
		btn.pressed.connect(_on_pick.bind(entry))
		v.add_child(btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(140, 16)
	UiTheme.style_button(cancel, true)
	cancel.pressed.connect(_close_pick_modal)
	v.add_child(cancel)
	add_child(m.layer)
	_pick_modal = m.layer


func _close_pick_modal() -> void:
	if _pick_modal != null and is_instance_valid(_pick_modal):
		_pick_modal.queue_free()
	_pick_modal = null


func _on_pick(entry: Dictionary) -> void:
	_close_pick_modal()
	_load_screen(entry)
