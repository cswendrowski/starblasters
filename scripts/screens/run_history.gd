extends Control

# Run History — a dated list of past runs (Run.load_run_history()), reached from
# the main menu. HD 1920×1080 layout. Click a run to drill into its per-run stats.
# Recorded stats are shown live; stats not yet instrumented (Phase-2 of the
# run-summary scope) are shown as "—" placeholders so the detail page is
# complete and fills in as the hooks land.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

# Stats recorded in the history JSON as plain ints: {label, key}. (Run time,
# Accuracy, and Damage are formatted/derived — added as computed rows in _show_detail.)
const RECORDED_STATS := [
	{"label": "Sectors cleared", "key": "sectors"},
	{"label": "Enemies destroyed", "key": "kills"},
	{"label": "Boss kills", "key": "boss_kills"},
	{"label": "Max bounty", "key": "bounty"},
	{"label": "Bounty earned", "key": "bounty_gained"},
	{"label": "Bounty spent", "key": "bounty_spent"},
	{"label": "Shots fired", "key": "shots_fired"},
	{"label": "Shots hit", "key": "shots_hit"},
	{"label": "Unique weapons", "key": "weapons_used"},
	{"label": "Locations visited", "key": "locations_visited"},
	{"label": "Outposts visited", "key": "stations_visited"},
	{"label": "Signals visited", "key": "signals_visited"},
	{"label": "Asteroids destroyed", "key": "asteroids"},
	{"label": "Mines cleared", "key": "mines_cleared"},
	{"label": "Distance", "key": "distance"},
	{"label": "Run seed", "key": "seed"},
]
# Phase 2 fully instrumented — no remaining placeholders. (Older runs predating a
# given stat simply read 0 for it.)
const PENDING_STATS := []

var _hd_scope: HdViewportScope = null
var _content: VBoxContainer = null   # swapped between the list and a run detail
var _view: String = "list"


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_build_ui()
	_show_list()


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

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "RunHistoryUI"
	add_child(ui_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	ui_layer.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 20)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "RUN HISTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	outer.add_child(title)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)
	# Content host — rebuilt for the list vs a run's detail.
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_content)

	var back := Button.new()
	back.text = "Back to Menu"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(back)
	back.pressed.connect(_to_menu)
	outer.add_child(back)

	UiTheme.assert_inside_viewport.call_deferred(self)


# ---- List view -----------------------------------------------------------

func _show_list() -> void:
	_view = "list"
	_clear_content()
	var hist: Array = []
	if has_node("/root/Run"):
		hist = get_node("/root/Run").load_run_history()
	if hist.is_empty():
		var empty := _label("No runs recorded yet. Fly a patrol!", UiTheme.LabelKind.BODY)
		_content.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	# Most recent first; each row is a button into the run's detail.
	for i in range(hist.size() - 1, -1, -1):
		var rec = hist[i]
		if not (rec is Dictionary):
			continue
		var row := Button.new()
		row.text = _format_row(rec)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(row)
		row.pressed.connect(_show_detail.bind(rec))
		vb.add_child(row)


# ---- Detail view ---------------------------------------------------------

func _show_detail(rec: Dictionary) -> void:
	_view = "detail"
	_clear_content()
	# Back-to-list.
	var back := Button.new()
	back.text = "<  Back to list"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_button(back)
	back.pressed.connect(_show_list)
	_content.add_child(back)
	# Header: date + outcome (color-coded).
	var date := String(rec.get("date", "?"))
	var head := _label(date, UiTheme.LabelKind.HEADER)
	_content.add_child(head)
	var outcome := String(rec.get("outcome", "?")).capitalize()
	var oc := _label("Outcome:  %s" % outcome, UiTheme.LabelKind.BODY)
	oc.add_theme_color_override("font_color", UiTheme.COLOR_DANGER if String(rec.get("outcome", "")) == "died" else UiTheme.COLOR_ACCENT)
	_content.add_child(oc)
	# Scrollable stat block.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stats)
	# Computed / formatted headline rows.
	_stat_row(stats, "Run time", _fmt_time_h(int(rec.get("time", 0))), false)
	var sf := int(rec.get("shots_fired", 0))
	var sh := int(rec.get("shots_hit", 0))
	_stat_row(stats, "Accuracy", ("%d%%" % int(round(100.0 * float(sh) / float(sf)))) if sf > 0 else "—", false)
	_stat_row(stats, "Damage taken", "%d shield · %d hull" % [int(rec.get("damage_shield", 0)), int(rec.get("damage_hull", 0))], false)
	for s in RECORDED_STATS:
		_stat_row(stats, String(s["label"]), str(int(rec.get(s["key"], 0))), false)
	if not PENDING_STATS.is_empty():
		var pend_head := _label("NOT YET TRACKED", UiTheme.LabelKind.CAPTION)
		pend_head.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)
		stats.add_child(pend_head)
		for label in PENDING_STATS:
			_stat_row(stats, label, "—", true)


func _stat_row(parent: VBoxContainer, label_text: String, value_text: String, pending: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := _label(label_text, UiTheme.LabelKind.BODY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if pending:
		name_lbl.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)
	row.add_child(name_lbl)
	var val_lbl := _label(value_text, UiTheme.LabelKind.STATUS_VALUE if not pending else UiTheme.LabelKind.BODY)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if pending:
		val_lbl.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)
	row.add_child(val_lbl)
	parent.add_child(row)


# ---- Helpers -------------------------------------------------------------

func _clear_content() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()


func _format_row(rec: Dictionary) -> String:
	var date := String(rec.get("date", "?"))
	var outcome := String(rec.get("outcome", "?")).capitalize()
	var sectors := int(rec.get("sectors", 0))
	var kills := int(rec.get("kills", 0))
	var bounty := int(rec.get("bounty", 0))
	return "%s   %s   ·   Sector %d   ·   %d kills   ·   %d bounty" % [date, outcome, sectors, kills, bounty]


func _label(text: String, kind: int) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, kind)
	return l


func _fmt_time_h(secs: int) -> String:
	return "%d:%02d" % [secs / 60, secs % 60]


func _to_menu() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _view == "detail":
			_show_list()
		else:
			_to_menu()
		get_viewport().set_input_as_handled()
