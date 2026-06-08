extends Control

# Credits screen — reached from the main menu Credits button. Native 480×270
# layout (mirrors run_history.gd): dark backdrop, centered title, sectioned
# name list, Back button returns to main_menu.tscn.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_build_ui()


func _build_ui() -> void:
	var vp: Vector2 = get_viewport_rect().size
	size = vp

	# Backdrop.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.10, 1.0)
	bg.size = vp
	add_child(bg)

	# Game title — small accent line at the top.
	var game_title := Label.new()
	game_title.text = "STARBLASTER"
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.size = Vector2(vp.x, 18)
	game_title.position = Vector2(0, 6)
	UiTheme.style_label(game_title, UiTheme.LabelKind.BODY)
	game_title.add_theme_font_size_override("font_size", 10)
	game_title.add_theme_color_override("font_color", Color(0.45, 0.75, 0.95, 0.8))
	add_child(game_title)

	# "CREDITS" heading.
	var heading := Label.new()
	heading.text = "CREDITS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size = Vector2(vp.x, 22)
	heading.position = Vector2(0, 22)
	UiTheme.style_label(heading, UiTheme.LabelKind.HEADER)
	heading.add_theme_font_size_override("font_size", 16)
	add_child(heading)

	# Centered content panel.
	var panel_w: float = 280.0
	var panel_h: float = 154.0
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	panel.size = Vector2(panel_w, panel_h)
	panel.position = Vector2((vp.x - panel_w) * 0.5, 48)
	add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.size = Vector2(panel_w - 20, panel_h - 16)
	inner.position = Vector2(10, 8)
	panel.add_child(inner)

	# Section: DESIGN
	_add_section_header(inner, "DESIGN")
	_add_names(inner, "Roman & Cody")

	# Spacer between sections.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	inner.add_child(spacer)

	# Section: TESTERS
	_add_section_header(inner, "TESTERS")
	_add_names(inner, "Stacey, Cody, Nath, Pao, Kyle, Doug, Ellen")

	# Back button.
	var back := Button.new()
	back.text = "Back to Menu"
	UiTheme.style_button(back, true, 4)
	back.add_theme_font_size_override("font_size", 12)
	back.position = Vector2(8, vp.y - 30.0)
	back.size = Vector2(120, 22)
	back.pressed.connect(func():
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	add_child(back)


func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(lbl, UiTheme.LabelKind.HEADER)
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)


func _add_names(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)
