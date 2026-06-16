extends Control

# Wave Pattern Editor (2026-06-16) — hand-author single-formation wave patterns on a lane grid that
# the conductor auto-mixes into generated levels (see docs/wave_pattern_editor_design_2026-06-15.md +
# scripts/levels/authored_patterns.gd). Native 480×270 dev tool (mirrors lane_visualizer /
# pattern_eligibility_editor): controls in the side gutters, the 7-lane × stagger-row grid in the band.
#
# A pattern = a FORMATION burst. Each filled cell is a slot at (lane, row=entry-stagger beat). A slot's
# ENEMY and MOVEMENT are each SPECIFIC or WILDCARD ("" = conductor-assigned), which yields the three
# authoring modes: enemies-only, patterns-only, both. The active "brush" (enemy + movement + size) is
# stamped on click; clicking a filled cell clears it. Preview runs the REAL conductor; Save writes JSON
# to user://tuners; Copy GDScript emits a paste-ready const DATA for authored_patterns.gd; Send→Cond
# pushes the live pattern to the next launched standard combat (Run.forced_pattern_dict).

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const DirectorScript = preload("res://scripts/levels/director.gd")
const AuthoredPatterns = preload("res://scripts/levels/authored_patterns.gd")
const EnemyRosterC = preload("res://scripts/levels/enemy_roster.gd")
const MovementKeys = preload("res://scripts/dev/pattern_eligibility_editor.gd")

const SAVE_PATH := "user://tuners/wave_patterns.json"
const EXPORT_PATH := "user://tuners/wave_patterns_export.txt"
const ROWS := 6
const SZ := 7

const FACTIONS := ["any", "supremacy", "privateer", "corporate", "zealot"]
const SIZES := ["", "small", "medium", "large", "huge", "giant"]
const STAGGERS := [0.08, 0.12, 0.18, 0.25, 0.35]

# Library of pattern dicts (same shape as AuthoredPatterns.DATA).
var _library: Array = []
var _pat_idx: int = 0
var _cells: Dictionary = {}        # Vector2i(lane,row) -> {enemy, movement, size}

# Active brush.
var _brush_enemy: String = ""      # "" = wildcard, else a scene path
var _brush_move: String = ""       # "" = wildcard/default, else a movement key
var _brush_size: String = ""       # "" = any, else small/medium/...

var _move_keys: Array = []         # ["" (Any)] + MOVEMENT_KEYS
var _move_idx: int = 0
var _size_idx: int = 0
var _enemy_choices: Array = []     # [{label, scene}]
var _enemy_buttons: Array = []

var _world: Node2D = null
var _overlay: Node2D = null
var _director: Node = null
var _font: Font = null
var _preview_seed: int = 1

var _name_lbl: Label = null
var _brush_lbl: Label = null
var _move_lbl: Label = null
var _size_lbl: Label = null
var _fac_lbl: Label = null
var _sector_lbl: Label = null
var _stagger_lbl: Label = null
var _status_lbl: Label = null


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	var run := get_node_or_null("/root/Run")
	if run and run.has_method("new_run"):
		run.new_run()
	_font = UiTheme.active_font()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_move_keys = [""]
	for k in MovementKeys.MOVEMENT_KEYS:
		_move_keys.append(str(k))
	_build_enemy_choices()
	_load_library()
	_build_bg()
	_build_world()
	_build_ui()
	_select_pattern(0)


func _build_enemy_choices() -> void:
	_enemy_choices = [{"label": "Any (wild)", "scene": ""}]
	for e in EnemyRosterC.ENTRIES:
		var path: String = String(e.get("scene", ""))
		if path == "":
			continue
		_enemy_choices.append({"label": _enemy_short(path), "scene": path})


func _enemy_short(path: String) -> String:
	return path.get_file().get_basename().trim_prefix("enemy_")


# ---------------------------------------------------------------- library / pattern

func _blank_pattern() -> Dictionary:
	return {"name": "new_pattern", "faction": "any", "min_sector": 0, "stagger": 0.18, "placements": []}


func _load_library() -> void:
	_library = []
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				_library = parsed
	if _library.is_empty():
		for p in AuthoredPatterns.DATA:
			_library.append((p as Dictionary).duplicate(true))
	if _library.is_empty():
		_library.append(_blank_pattern())


func _cur() -> Dictionary:
	return _library[_pat_idx]


func _select_pattern(i: int) -> void:
	_pat_idx = (i + _library.size()) % _library.size()
	_cells.clear()
	for pl in _cur().get("placements", []):
		var k := Vector2i(int(pl.get("lane", 0)), int(pl.get("row", 0)))
		_cells[k] = {"enemy": String(pl.get("enemy", "")), "movement": String(pl.get("movement", "")), "size": String(pl.get("size", ""))}
	_refresh_prop_labels()
	if _overlay:
		_overlay.queue_redraw()
	_update_status()


func _sync_placements() -> void:
	var placements: Array = []
	for k in _cells:
		var c: Dictionary = _cells[k]
		placements.append({"lane": int(k.x), "row": int(k.y),
			"enemy": String(c["enemy"]), "movement": String(c["movement"]), "size": String(c["size"])})
	_cur()["placements"] = placements


func _new_pattern() -> void:
	_sync_placements()
	var p := _blank_pattern()
	p["name"] = "pattern_%d" % _library.size()
	_library.append(p)
	_select_pattern(_library.size() - 1)


func _del_pattern() -> void:
	if _library.size() <= 1:
		_cur()["placements"] = []
		_select_pattern(_pat_idx)
		return
	_library.remove_at(_pat_idx)
	_select_pattern(_pat_idx)


# ---------------------------------------------------------------- world + grid draw

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_draw_overlay)
	_world.add_child(_overlay)


func _row_h() -> float:
	return Playfield.H / float(ROWS)


func _row_center(r: int) -> float:
	return Playfield.Y_MIN + (float(r) + 0.5) * _row_h()


func _draw_overlay() -> void:
	var top: float = Playfield.Y_MIN
	var bot: float = Playfield.Y_MAX
	_overlay.draw_rect(Rect2(Playfield.X_MIN, top, Playfield.W, Playfield.H), Color(0.4, 0.6, 0.9, 0.5), false, 1.0)
	# Lane columns + centers.
	for i in Lanes.COUNT:
		_overlay.draw_rect(Rect2(Lanes.lane_left(i), top, Lanes.WIDTH, Playfield.H), Color(0.5, 0.7, 1.0, 0.05), true)
		var cx: float = Lanes.lane_center(i)
		_overlay.draw_line(Vector2(cx, top), Vector2(cx, bot), Color(0.5, 0.7, 1.0, 0.10), 1.0)
		_overlay.draw_string(_font, Vector2(cx - 3.0, top + 7.0), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.5, 0.7, 1.0, 0.6))
	# Row dividers + labels.
	var rh: float = _row_h()
	for r in range(1, ROWS):
		var y: float = top + float(r) * rh
		_overlay.draw_line(Vector2(Playfield.X_MIN, y), Vector2(Playfield.X_MAX, y), Color(1, 1, 1, 0.06), 1.0)
	for r in ROWS:
		_overlay.draw_string(_font, Vector2(Playfield.X_MIN + 1.0, _row_center(r) + 2.0), "r%d" % r, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.18))
	# Filled cells.
	for k in _cells:
		var c: Dictionary = _cells[k]
		var ccx: float = Lanes.lane_center(int(k.x))
		var ccy: float = _row_center(int(k.y))
		var wild_enemy: bool = String(c["enemy"]) == ""
		var col: Color = Color(0.34, 0.39, 0.48, 0.9) if wild_enemy else Color(0.20, 0.45, 0.55, 0.92)
		_overlay.draw_rect(Rect2(ccx - 10.0, ccy - 9.0, 20.0, 18.0), col, true)
		_overlay.draw_rect(Rect2(ccx - 10.0, ccy - 9.0, 20.0, 18.0), Color(1, 1, 1, 0.5), false, 1.0)
		var etxt: String = "?" if wild_enemy else _enemy_short(String(c["enemy"]))
		_overlay.draw_string(_font, Vector2(ccx - 9.0, ccy - 1.0), etxt.substr(0, 5), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.95))
		var mtxt: String = "·" if String(c["movement"]) == "" else String(c["movement"]).substr(0, 4)
		_overlay.draw_string(_font, Vector2(ccx - 9.0, ccy + 7.0), mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.8, 0.9, 1.0, 0.85))


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	# Left gutter.
	var left := _make_panel(Vector2(0, 0), Vector2(128, 270))
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	left.add_child(lv)
	_fill_panel(lv)

	lv.add_child(_new_label("WAVE PATTERN ED", UiTheme.COLOR_ACCENT, SZ))

	# Pattern nav.
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	lv.add_child(pr)
	_add_fixed_button(pr, "<", func(): _select_pattern(_pat_idx - 1), 14)
	_name_lbl = _new_label("-", UiTheme.COLOR_TEXT, SZ)
	_name_lbl.clip_text = true
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.add_child(_name_lbl)
	_add_fixed_button(pr, ">", func(): _select_pattern(_pat_idx + 1), 14)
	var pr2 := HBoxContainer.new()
	pr2.add_theme_constant_override("separation", 2)
	lv.add_child(pr2)
	_add_button(pr2, "New", _new_pattern)
	_add_button(pr2, "Rename", _rename_pattern)
	_add_button(pr2, "Del", _del_pattern)

	lv.add_child(_sep())
	_add_caption(lv, "BRUSH")
	_brush_lbl = _new_label("enemy: Any", UiTheme.COLOR_TEXT, SZ)
	_brush_lbl.clip_text = true
	lv.add_child(_brush_lbl)
	var mv := HBoxContainer.new()
	mv.add_theme_constant_override("separation", 2)
	lv.add_child(mv)
	_add_fixed_button(mv, "<", func(): _cycle_move(-1), 14)
	_move_lbl = _new_label("mv: Any", UiTheme.COLOR_TEXT, SZ)
	_move_lbl.clip_text = true
	_move_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_move_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_move_lbl)
	_add_fixed_button(mv, ">", func(): _cycle_move(1), 14)
	var szr := HBoxContainer.new()
	szr.add_theme_constant_override("separation", 2)
	lv.add_child(szr)
	_add_fixed_button(szr, "<", func(): _cycle_size(-1), 14)
	_size_lbl = _new_label("sz: any", UiTheme.COLOR_TEXT, SZ)
	_size_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	szr.add_child(_size_lbl)
	_add_fixed_button(szr, ">", func(): _cycle_size(1), 14)
	# Mode presets.
	var modr := HBoxContainer.new()
	modr.add_theme_constant_override("separation", 2)
	lv.add_child(modr)
	_add_button(modr, "Enem", func(): _preset("enemies"))
	_add_button(modr, "Patt", func(): _preset("patterns"))
	_add_button(modr, "Both", func(): _preset("both"))

	lv.add_child(_sep())
	_add_caption(lv, "PROPS")
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 2)
	lv.add_child(fr)
	_add_fixed_button(fr, "<", func(): _cycle_faction(-1), 14)
	_fac_lbl = _new_label("fac: any", UiTheme.COLOR_TEXT, SZ)
	_fac_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fac_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fr.add_child(_fac_lbl)
	_add_fixed_button(fr, ">", func(): _cycle_faction(1), 14)
	var scr := HBoxContainer.new()
	scr.add_theme_constant_override("separation", 2)
	lv.add_child(scr)
	_add_fixed_button(scr, "<", func(): _cycle_sector(-1), 14)
	_sector_lbl = _new_label("minS: 0", UiTheme.COLOR_TEXT, SZ)
	_sector_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sector_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scr.add_child(_sector_lbl)
	_add_fixed_button(scr, ">", func(): _cycle_sector(1), 14)
	var str_row := HBoxContainer.new()
	str_row.add_theme_constant_override("separation", 2)
	lv.add_child(str_row)
	_add_fixed_button(str_row, "<", func(): _cycle_stagger(-1), 14)
	_stagger_lbl = _new_label("stg: 0.18", UiTheme.COLOR_TEXT, SZ)
	_stagger_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stagger_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	str_row.add_child(_stagger_lbl)
	_add_fixed_button(str_row, ">", func(): _cycle_stagger(1), 14)

	lv.add_child(_sep())
	var a1 := HBoxContainer.new()
	a1.add_theme_constant_override("separation", 2)
	lv.add_child(a1)
	_add_button(a1, "Preview", _preview)
	_add_button(a1, "Send>C", _send_to_conductor)
	var a2 := HBoxContainer.new()
	a2.add_theme_constant_override("separation", 2)
	lv.add_child(a2)
	_add_button(a2, "Save", _save_json)
	_add_button(a2, "Export", _export)
	var a3 := HBoxContainer.new()
	a3.add_theme_constant_override("separation", 2)
	lv.add_child(a3)
	_add_button(a3, "ClearGrid", _clear_grid)
	_add_button(a3, "Back", _on_back)
	_status_lbl = _new_label("", UiTheme.COLOR_FAINT, SZ)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.custom_minimum_size = Vector2(120, 0)
	lv.add_child(_status_lbl)

	# Right gutter — enemy palette.
	var right := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	right.add_child(rv)
	_fill_panel(rv)
	_add_caption(rv, "ENEMY BRUSH")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	var listbox := VBoxContainer.new()
	listbox.add_theme_constant_override("separation", 1)
	listbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(listbox)
	_enemy_buttons = []
	for i in _enemy_choices.size():
		var b := Button.new()
		b.text = String(_enemy_choices[i]["label"])
		b.toggle_mode = true
		b.button_pressed = (i == 0)
		b.custom_minimum_size = Vector2(0, 11)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b)
		var idx: int = i
		b.pressed.connect(func(): _select_enemy(idx))
		listbox.add_child(b)
		_enemy_buttons.append(b)


# ---------------------------------------------------------------- brush + props

func _select_enemy(i: int) -> void:
	_brush_enemy = String(_enemy_choices[i]["scene"])
	for j in _enemy_buttons.size():
		if is_instance_valid(_enemy_buttons[j]):
			_enemy_buttons[j].set_pressed_no_signal(j == i)
	_refresh_brush_label()
	_update_status()


func _cycle_move(d: int) -> void:
	_move_idx = (_move_idx + d + _move_keys.size()) % _move_keys.size()
	_brush_move = String(_move_keys[_move_idx])
	_move_lbl.text = "mv: %s" % ("Any" if _brush_move == "" else _brush_move)
	_update_status()


func _cycle_size(d: int) -> void:
	_size_idx = (_size_idx + d + SIZES.size()) % SIZES.size()
	_brush_size = String(SIZES[_size_idx])
	_size_lbl.text = "sz: %s" % ("any" if _brush_size == "" else _brush_size)
	_update_status()


func _preset(mode: String) -> void:
	# Quick-set what the brush leaves wildcard. Keeps the current palette/cycler picks.
	if mode == "enemies":
		_brush_move = ""
		_move_idx = 0
		_move_lbl.text = "mv: Any"
	elif mode == "patterns":
		_brush_enemy = ""
		_select_enemy(0)
	# "both" leaves whatever's selected.
	_refresh_brush_label()
	_update_status()


func _refresh_brush_label() -> void:
	_brush_lbl.text = "enemy: %s" % ("Any" if _brush_enemy == "" else _enemy_short(_brush_enemy))


func _cycle_faction(d: int) -> void:
	var cur: String = String(_cur().get("faction", "any"))
	var idx: int = FACTIONS.find(cur)
	idx = (idx + d + FACTIONS.size()) % FACTIONS.size()
	_cur()["faction"] = FACTIONS[idx]
	_fac_lbl.text = "fac: %s" % FACTIONS[idx]


func _cycle_sector(d: int) -> void:
	var s: int = clampi(int(_cur().get("min_sector", 0)) + d, 0, 9)
	_cur()["min_sector"] = s
	_sector_lbl.text = "minS: %d" % s


func _cycle_stagger(d: int) -> void:
	var cur: float = float(_cur().get("stagger", 0.18))
	var idx: int = 2
	for i in STAGGERS.size():
		if abs(float(STAGGERS[i]) - cur) < 0.001:
			idx = i
	idx = (idx + d + STAGGERS.size()) % STAGGERS.size()
	_cur()["stagger"] = STAGGERS[idx]
	_stagger_lbl.text = "stg: %s" % str(STAGGERS[idx])


func _refresh_prop_labels() -> void:
	if _name_lbl:
		_name_lbl.text = String(_cur().get("name", "-"))
	if _fac_lbl:
		_fac_lbl.text = "fac: %s" % String(_cur().get("faction", "any"))
	if _sector_lbl:
		_sector_lbl.text = "minS: %d" % int(_cur().get("min_sector", 0))
	if _stagger_lbl:
		_stagger_lbl.text = "stg: %s" % str(_cur().get("stagger", 0.18))


func _rename_pattern() -> void:
	# No text-input chrome at native size — cycle a numbered name so each pattern is addressable.
	_cur()["name"] = "pattern_%d_%d" % [_pat_idx, Time.get_ticks_msec() % 1000]
	_refresh_prop_labels()
	_update_status()


func _clear_grid() -> void:
	_cells.clear()
	_sync_placements()
	_overlay.queue_redraw()
	_update_status()


# ---------------------------------------------------------------- preview / conductor

func _build_pattern_for_run() -> Dictionary:
	_sync_placements()
	return _cur()


func _preview() -> void:
	var pat: Dictionary = _build_pattern_for_run()
	if (pat.get("placements", []) as Array).is_empty():
		_set_status("nothing to preview")
		return
	var ff: int = AuthoredPatterns.faction_id(String(pat.get("faction", "any")))
	if ff < 0:
		ff = 1   # privateer as the default preview fill for "any" patterns
	var sector: int = maxi(1, int(pat.get("min_sector", 0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = _preview_seed
	_preview_seed += 1
	var ph = AuthoredPatterns.build_phrase(pat, ff, sector, rng)
	if ph == null:
		_set_status("preview: pattern didn't resolve")
		return
	var sw := ScoreWave.new()
	sw.phrases = [ph]
	var score := CombatScore.new()
	score.waves = [sw]
	_run_score(score)
	_set_status("preview running (%d slots)" % ph.specs.size())


func _send_to_conductor() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		_set_status("no Run")
		return
	run.set_meta("forced_pattern_dict", _build_pattern_for_run().duplicate(true))
	_set_status("queued for next standard combat")


func _run_score(score) -> void:
	_clear_world()
	if score == null:
		return
	_director = DirectorScript.new()
	_director.name = "WaveDirector"
	if "start_grace" in _director:
		_director.start_grace = 0.0
	if "max_concurrent" in _director:
		_director.max_concurrent = 20
	_world.add_child(_director)
	_director.start_score(score)


func _clear_world() -> void:
	if _director and is_instance_valid(_director):
		if _director.has_method("stop"):
			_director.stop()
		_director.queue_free()
	_director = null
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n):
				n.queue_free()


# ---------------------------------------------------------------- save / export

func _save_json() -> void:
	_sync_placements()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_library, "\t"))
		f.close()
		_set_status("saved json (%d patterns)" % _library.size())
	else:
		_set_status("save failed")


func _export() -> void:
	_sync_placements()
	# JSON dict/array literals are valid GDScript literals, so this pastes straight into
	# scripts/levels/authored_patterns.gd's `const DATA`.
	var text: String = "const DATA: Array = " + JSON.stringify(_library, "\t") + "\n"
	DisplayServer.clipboard_set(text)
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	_set_status("exported const DATA → clipboard")


# ---------------------------------------------------------------- input / status

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_at(get_global_mouse_position())


func _place_at(pos: Vector2) -> void:
	if pos.x < Playfield.X_MIN or pos.x > Playfield.X_MAX or pos.y < Playfield.Y_MIN or pos.y > Playfield.Y_MAX:
		return
	var lane: int = Lanes.nearest_lane(pos.x)
	var row: int = clampi(int((pos.y - Playfield.Y_MIN) / _row_h()), 0, ROWS - 1)
	var k := Vector2i(lane, row)
	if _cells.has(k):
		_cells.erase(k)
	else:
		_cells[k] = {"enemy": _brush_enemy, "movement": _brush_move, "size": _brush_size}
	_sync_placements()
	_overlay.queue_redraw()
	_update_status()


func _set_status(s: String) -> void:
	if _status_lbl:
		_status_lbl.text = s


func _update_status() -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = "slots: %d   brush: %s / %s" % [
		_cells.size(), ("Any" if _brush_enemy == "" else _enemy_short(_brush_enemy)),
		("Any" if _brush_move == "" else _brush_move)]


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---------------------------------------------------------------- UI helpers (lane_visualizer convention)

func _style_label(l: Label, color: Color, size: int) -> void:
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 1)


func _new_label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	_style_label(l, color, size)
	return l


func _make_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _fill_panel(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 3
	c.offset_top = 3
	c.offset_right = -3
	c.offset_bottom = -3


func _sep() -> HSeparator:
	return HSeparator.new()


func _add_caption(parent: Node, text: String) -> void:
	parent.add_child(_new_label(text, UiTheme.COLOR_FAINT, SZ))


func _native_button_stylebox(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _style_button(b: Button) -> void:
	b.clip_text = true
	b.add_theme_font_override("font", UiTheme.active_font())
	b.add_theme_font_size_override("font_size", SZ)
	b.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	b.add_theme_color_override("font_hover_color", UiTheme.COLOR_TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.COLOR_TEXT)
	b.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_stylebox_override("normal", _native_button_stylebox(Color(0.08, 0.11, 0.16, 0.9)))
	b.add_theme_stylebox_override("hover", _native_button_stylebox(Color(0.12, 0.17, 0.24, 0.95)))
	b.add_theme_stylebox_override("pressed", _native_button_stylebox(Color(0.06, 0.09, 0.13, 1.0)))


func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _add_fixed_button(parent: Node, text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 12)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
