extends Control

# Run History — a dated list of past runs (Run.load_run_history()), reached from
# the main menu. HD 1920×1080 layout: sector_bg backdrop, full-page scrollable
# list, Back button.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var _list_vbox: VBoxContainer = null
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_build_ui()


func _build_ui() -> void:
	# Sector backdrop (mirrors run_summary.gd).
	var bg := TextureRect.new()
	bg.texture = load("res://graphics/ui/sector_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	# All UI on layer 5 (mirrors manage_ship.gd).
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "RunHistoryUI"
	add_child(ui_layer)

	# Outer margin + vertical layout.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	ui_layer.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 20)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer_vbox)

	# Title.
	var title := Label.new()
	title.text = "RUN HISTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	outer_vbox.add_child(title)

	# Scrollable list panel fills the remaining vertical space.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(panel_vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_vbox.add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 8)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)

	_populate()

	# Back button.
	var back := Button.new()
	back.text = "Back to Menu"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(back)
	back.pressed.connect(func():
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	outer_vbox.add_child(back)

	UiTheme.assert_inside_viewport.call_deferred(self)


func _populate() -> void:
	if _list_vbox == null:
		return
	var hist: Array = []
	if has_node("/root/Run"):
		hist = get_node("/root/Run").load_run_history()
	if hist.is_empty():
		var empty := Label.new()
		empty.text = "No runs recorded yet. Fly a patrol!"
		UiTheme.style_label(empty, UiTheme.LabelKind.BODY)
		_list_vbox.add_child(empty)
		return
	# Most recent first.
	for i in range(hist.size() - 1, -1, -1):
		var rec = hist[i]
		if not (rec is Dictionary):
			continue
		var row := Label.new()
		row.text = _format_row(rec)
		UiTheme.style_label(row, UiTheme.LabelKind.BODY)
		_list_vbox.add_child(row)


func _format_row(rec: Dictionary) -> String:
	var date := String(rec.get("date", "?"))
	var outcome := String(rec.get("outcome", "?")).capitalize()
	var sectors := int(rec.get("sectors", 0))
	var kills := int(rec.get("kills", 0))
	var bosses := int(rec.get("boss_kills", 0))
	var bounty := int(rec.get("bounty", 0))
	return "%s   %s   ·   Sector %d   ·   %d kills   ·   %d bosses   ·   %d bounty" % [
		date, outcome, sectors, kills, bosses, bounty
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
		get_viewport().set_input_as_handled()
