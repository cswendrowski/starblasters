extends Control

# Credits screen — reached from the main menu Credits button.
# HD 1920×1080 layout: centered card on sector_bg backdrop.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

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
	ui_layer.name = "CreditsUI"
	add_child(ui_layer)

	# CenterContainer fills the full HD canvas.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(center)

	# Card panel.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# "STARBLASTER" caption.
	var game_title := Label.new()
	game_title.text = "STARBLASTER"
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(game_title, UiTheme.LabelKind.CAPTION)
	vbox.add_child(game_title)

	# "CREDITS" title.
	var heading := Label.new()
	heading.text = "CREDITS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(heading, UiTheme.LabelKind.TITLE)
	vbox.add_child(heading)

	# Section: DESIGN
	_add_section_header(vbox, "DESIGN")
	_add_names(vbox, "Roman & Cody")

	# Spacer between sections.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Section: TESTERS
	_add_section_header(vbox, "TESTERS")
	_add_names(vbox, "Stacey, Cody, Nath, Pao, Kyle, Doug, Ellen")

	# Spacer before button.
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	# Back button.
	var back := Button.new()
	back.text = "Back to Menu"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(back)
	back.pressed.connect(func():
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	vbox.add_child(back)

	UiTheme.assert_inside_viewport.call_deferred(self)


func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(lbl, UiTheme.LabelKind.HEADER)
	parent.add_child(lbl)


func _add_names(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	parent.add_child(lbl)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
		get_viewport().set_input_as_handled()
