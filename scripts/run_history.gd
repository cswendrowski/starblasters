extends Control

# Run History — a dated list of past runs (Run.load_run_history()), reached from
# the main menu. Native 480 layout mirroring the enemy codex (no live preview):
# a scrollable list of past-run rows, most recent first, + a Back button.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var _list_vbox: VBoxContainer = null


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
	# Title.
	var title := Label.new()
	title.text = "RUN HISTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 24)
	title.position = Vector2(0, 8)
	UiTheme.style_label(title, UiTheme.LabelKind.HEADER)
	# Native 480 render (mirrors codex) — pin font size after style_label so the
	# HD theme doesn't blow it up.
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	# Scrollable list panel.
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	panel.size = Vector2(vp.x - 16.0, vp.y - 78.0)
	panel.position = Vector2(8, 36)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.size = panel.size - Vector2(12, 12)
	scroll.position = Vector2(6, 6)
	panel.add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 3)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)
	_populate()
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
		empty.add_theme_font_size_override("font_size", 12)
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
		row.add_theme_font_size_override("font_size", 11)
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
