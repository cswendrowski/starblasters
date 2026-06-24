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
const EnemyManifestC = preload("res://scripts/dev/enemy_manifest.gd")
const MovementKeys = preload("res://scripts/dev/pattern_eligibility_editor.gd")

const SAVE_PATH := "user://tuners/wave_patterns.json"
const EXPORT_PATH := "user://tuners/wave_patterns_export.txt"
const ROWS := 6
const SZ := 7
const SUB := 3   # NxN sub-grid per lane square — pack multiple (tiny) enemies into one cell

const FACTIONS := ["any", "supremacy", "privateer", "corporate", "zealot"]
const SIZES := ["", "tiny", "small", "medium", "large", "huge", "giant"]
const DIRS := ["", "left", "right", "random"]   # "" = any (leave authored)
const DEPTHS := ["", "high", "mid", "low"]      # "" = enemy default; else hold/cross band (locomotion refactor)
const STAGGERS := [0.08, 0.12, 0.18, 0.25, 0.35]

# Library of pattern dicts (same shape as AuthoredPatterns.DATA).
var _library: Array = []
var _pat_idx: int = 0
var _cells: Dictionary = {}        # Vector2i(lane,row) -> { Vector2i(sub_x,sub_y) -> {enemy,movement,size} }

# Active brush.
var _brush_enemy: String = ""      # "" = wildcard, else a scene path
var _brush_move: String = ""       # "" = wildcard/default, else a movement key
var _brush_size: String = ""       # "" = any, else small/medium/...
var _brush_dir: String = ""        # "" = any (authored), else left/right/random — side-aware movements only
var _brush_depth: String = ""      # "" = enemy default, else high/mid/low — hold/cross depth (locomotion refactor)

var _move_keys: Array = []         # ["" (Any)] + MOVEMENT_KEYS
var _move_idx: int = 0
var _size_idx: int = 0
var _dir_idx: int = 0
var _depth_idx: int = 0
var _enemy_choices: Array = []     # [{label, scene, faction, size}]
var _enemy_buttons: Array = []
var _palette_listbox: VBoxContainer = null   # holds the enemy-brush buttons (re-sortable)
var _icon_cache: Dictionary = {}   # scene path -> frame-0 Texture2D (palette + cell previews)

var _world: Node2D = null
var _overlay: Node2D = null
var _director: Node = null
var _font: Font = null
var _preview_seed: int = 1

# Preview controls (Roman 2026-06-17).
var _shoot_enabled: bool = true    # toggle: spawned preview enemies fire or stay silent
var _shoot_btn: Button = null
var _pulse_t: float = 0.0          # animates the placed-enemy direction pulse
const MountComponentScript = preload("res://scripts/enemies/mounts/mount_component.gd")
const EnemyTurretScript = preload("res://scripts/enemies/enemy_turret.gd")

var _name_lbl: LineEdit = null
var _brush_lbl: Label = null
var _move_lbl: Label = null
var _size_lbl: Label = null
var _dir_lbl: Label = null
var _depth_lbl: Label = null
var _fac_lbl: Label = null
var _sector_lbl: Label = null
var _stagger_lbl: Label = null
var _mode_btn: Button = null       # Formation/Free speed-mode toggle (per-pattern)
var _status_lbl: Label = null
var _note_edit: TextEdit = null    # free-text note saved on the pattern (for review/evaluation)


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")
	var run := get_node_or_null("/root/Run")
	if run and run.has_method("new_run"):
		run.new_run()
	_font = UiTheme.active_font()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The root Control defaults to MOUSE_FILTER_STOP, which CONSUMES grid clicks before
	# _unhandled_input fires (so placement silently did nothing). IGNORE lets empty-area clicks
	# fall through to _unhandled_input; the side panels/buttons keep their own STOP filter.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# Pull from the SHARED full dev roster (manifest ∪ faction tags) so every placeable enemy shows —
	# including faction units like the zealots that aren't in the production wave roll (Roman
	# 2026-06-17). Bosses + mines are skipped (not formation units); size comes from the roster entry
	# when one exists, else a fallback from the scene name.
	_enemy_choices = [{"label": "Any (wild)", "scene": "", "faction": "", "size": ""}]
	for path in EnemyManifestC.all_enemies(false):
		var low: String = path.to_lower()
		if low.contains("mine") and not low.contains("minelayer"):
			continue
		var entry: Dictionary = EnemyRosterC.entry_for_scene(path)
		var sz: String = String(entry.get("size", "")) if not entry.is_empty() else ""
		if sz == "":
			sz = _size_from_path(path)
		_enemy_choices.append({"label": _enemy_short(path), "scene": path,
			"faction": _faction_of(path), "size": sz})


# Size fallback for enemies without a roster entry (e.g. zealots) — the scene name encodes it
# (enemy_z_s_/_z_m_/_z_l_); default small.
func _size_from_path(path: String) -> String:
	var p: String = path.to_lower()
	if "_z_m_" in p or "_m_helix" in p:
		return "medium"
	if "_z_l_" in p:
		return "large"
	return "small"


# Faction bucket from the scene path (mirrors the Enemy Bench's grouping).
func _faction_of(path: String) -> String:
	var p := path.to_lower()
	for fac in ["supremacy", "privateer", "corporate", "zealot"]:
		if p.contains("/factions/%s/" % fac):
			return fac
	if p.contains("/core/"):
		return "core"
	return "other"


# Approx on-screen px for an enemy's size class — placed cells draw at this so tiny reads small.
func _size_px(size: String) -> float:
	match size:
		"tiny": return 7.0
		"small": return 11.0
		"medium": return 15.0
		"large": return 19.0
		"huge", "giant": return 22.0
		_: return 13.0


# Resolve a placement's effective size: explicit → roster entry → "small".
func _placement_size(c: Dictionary) -> String:
	var s := String(c.get("size", ""))
	if s != "":
		return s
	var en := String(c.get("enemy", ""))
	if en != "":
		s = String(EnemyRosterC.entry_for_scene(en).get("size", ""))
	return s if s != "" else "small"


# Frame-0 texture for a scene's hull sprite (codex-style single frame), cached. Mirrors the
# Enemy Bench's list-icon extraction so the palette + placed cells read the same as the codex.
func _frame0_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	var ps := load(path) as PackedScene
	if ps != null:
		var st := ps.get_state()
		for i in st.get_node_count():
			if st.get_node_type(i) != &"Sprite2D":
				continue
			var t: Texture2D = null
			var hf := 1
			var vf := 1
			for j in st.get_node_property_count(i):
				var pn := st.get_node_property_name(i, j)
				if pn == &"texture": t = st.get_node_property_value(i, j) as Texture2D
				elif pn == &"hframes": hf = int(st.get_node_property_value(i, j))
				elif pn == &"vframes": vf = int(st.get_node_property_value(i, j))
			if t != null:
				if hf <= 1 and vf <= 1:
					tex = t
				else:
					var at := AtlasTexture.new()
					at.atlas = t
					at.region = Rect2(0, 0, float(t.get_width()) / float(maxi(1, hf)), float(t.get_height()) / float(maxi(1, vf)))
					tex = at
				break
	_icon_cache[path] = tex
	return tex


func _enemy_short(path: String) -> String:
	return path.get_file().get_basename().trim_prefix("enemy_")


# ---------------------------------------------------------------- library / pattern

func _blank_pattern() -> Dictionary:
	# lockstep=false → FREE speed mode (each unit at its own speed); true → FORMATION (whole burst
	# moves at the slowest member's speed). build_phrase reads it; AuthoredPatterns._lock_to_slowest.
	return {"name": "new_pattern", "faction": "any", "min_sector": 0, "stagger": 0.18, "lockstep": false, "note": "", "placements": []}


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
		# Legacy placements (no sub_x/sub_y) land at the sub-grid centre (1,1).
		var sub := Vector2i(clampi(int(pl.get("sub_x", 1)), 0, SUB - 1), clampi(int(pl.get("sub_y", 1)), 0, SUB - 1))
		if not _cells.has(k):
			_cells[k] = {}
		_cells[k][sub] = {"enemy": String(pl.get("enemy", "")), "movement": String(pl.get("movement", "")), "size": String(pl.get("size", "")), "dir": String(pl.get("dir", "")), "depth": String(pl.get("depth", ""))}
	_refresh_prop_labels()
	if _note_edit:
		_note_edit.text = String(_cur().get("note", ""))
	if _overlay:
		_overlay.queue_redraw()
	_update_status()


func _sync_placements() -> void:
	var placements: Array = []
	for k in _cells:
		for sub in _cells[k]:
			var c: Dictionary = _cells[k][sub]
			placements.append({"lane": int(k.x), "row": int(k.y), "sub_x": int(sub.x), "sub_y": int(sub.y),
				"enemy": String(c["enemy"]), "movement": String(c["movement"]), "size": String(c["size"]),
				"dir": String(c.get("dir", "")), "depth": String(c.get("depth", ""))})
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
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel-art cell previews
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
	# Filled cells — each lane square holds a 3×3 sub-grid; draw each placed sub-cell.
	var sw: float = Lanes.WIDTH / float(SUB)
	var sh: float = _row_h() / float(SUB)
	for k in _cells:
		var lx: float = Lanes.lane_left(int(k.x))
		var rtop: float = Playfield.Y_MIN + float(k.y) * _row_h()
		for sub in _cells[k]:
			var c: Dictionary = _cells[k][sub]
			var ccx: float = lx + (float(sub.x) + 0.5) * sw
			var ccy: float = rtop + (float(sub.y) + 0.5) * sh
			var wild_enemy: bool = String(c["enemy"]) == ""
			var col: Color = Color(0.34, 0.39, 0.48, 0.9) if wild_enemy else Color(0.20, 0.45, 0.55, 0.92)
			# Footprint: tiny fills its sub-cell; everything else (placed at the centre) fills the cell.
			var is_tiny: bool = _placement_size(c) == "tiny"
			var fw: float = sw if is_tiny else Lanes.WIDTH
			var fh: float = sh if is_tiny else _row_h()
			_overlay.draw_rect(Rect2(ccx - fw * 0.5 + 0.5, ccy - fh * 0.5 + 0.5, fw - 1.0, fh - 1.0), col, true)
			# Sprite drawn at the enemy's size-class px (tiny reads small, large reads big), capped to the lane.
			var tex: Texture2D = null if wild_enemy else _frame0_tex(String(c["enemy"]))
			if tex != null:
				var tsz: Vector2 = tex.get_size()
				var target: float = minf(_size_px(_placement_size(c)), Lanes.WIDTH - 1.0)
				var sc: float = minf(target / maxf(1.0, tsz.x), target / maxf(1.0, tsz.y))
				_overlay.draw_texture_rect(tex, Rect2(ccx - tsz.x * sc * 0.5, ccy - tsz.y * sc * 0.5, tsz.x * sc, tsz.y * sc), false)
			else:
				_overlay.draw_string(_font, Vector2(ccx - 2.0, ccy + 2.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7))
			# Pulsing direction indicator (compact, scaled to the sub-cell).
			var dir: Vector2 = _move_dir(String(c["movement"]), int(k.x)).normalized()
			var reach: float = minf(sw, sh) * 0.85
			var frac: float = fmod(_pulse_t * 0.9, 1.0)
			_overlay.draw_circle(Vector2(ccx, ccy) + dir * (1.0 + reach * frac), 1.0, Color(0.75, 0.92, 1.0, (1.0 - frac) * 0.75))


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	# Left gutter.
	var left := _make_panel(Vector2(0, 0), Vector2(128, 270))
	add_child(left)
	# The control stack outgrew 270px (depth/speed brushes etc.) and the panel clips, so the
	# NOTE field + action buttons (Preview/Save/…) were being cut off the bottom. Scroll it so
	# every control stays reachable no matter how many accumulate (Roman 2026-06-23).
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	left.add_child(outer)
	_fill_panel(outer)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(lsc)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(lv)

	lv.add_child(_new_label("FORMATION BUILDER", UiTheme.COLOR_ACCENT, SZ))

	# Pattern nav.
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	lv.add_child(pr)
	_add_fixed_button(pr, "<", func(): _select_pattern(_pat_idx - 1), 14)
	# Editable pattern name (Roman 2026-06-23): type + Enter (or click away) renames the pattern.
	_name_lbl = LineEdit.new()
	_name_lbl.add_theme_font_size_override("font_size", SZ)
	_name_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_lbl.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.text_submitted.connect(_commit_name)
	_name_lbl.focus_exited.connect(func(): _commit_name(_name_lbl.text))
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
	# Direction brush — forces which way a side-aware movement (hook/shift/drift/cut/…) runs.
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 2)
	lv.add_child(dr)
	_add_fixed_button(dr, "<", func(): _cycle_dir(-1), 14)
	_dir_lbl = _new_label("dir: any", UiTheme.COLOR_TEXT, SZ)
	_dir_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dir_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dr.add_child(_dir_lbl)
	_add_fixed_button(dr, ">", func(): _cycle_dir(1), 14)
	# Depth brush — hold/cross band (loiter/drift hold, hook/cut turn-off, crosser cross).
	# "" = the enemy's own default depth (locomotion refactor 2026-06-19).
	var dpr := HBoxContainer.new()
	dpr.add_theme_constant_override("separation", 2)
	lv.add_child(dpr)
	_add_fixed_button(dpr, "<", func(): _cycle_depth(-1), 14)
	_depth_lbl = _new_label("depth: def", UiTheme.COLOR_TEXT, SZ)
	_depth_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depth_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dpr.add_child(_depth_lbl)
	_add_fixed_button(dpr, ">", func(): _cycle_depth(1), 14)
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
	# Speed mode (Roman 2026-06-22): Formation = the whole burst moves at the SLOWEST member's speed
	# so it holds its shape; Free = each unit moves at its own chassis speed. Per-pattern toggle.
	_mode_btn = _add_button(lv, "spd: free", _toggle_speed_mode)

	_add_caption(lv, "NOTE")
	_note_edit = TextEdit.new()
	_note_edit.custom_minimum_size = Vector2(0, 42)
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_edit.add_theme_font_size_override("font_size", SZ)
	_note_edit.text_changed.connect(func(): if not _library.is_empty(): _cur()["note"] = _note_edit.text)
	lv.add_child(_note_edit)

	# --- Pinned action bar (outside the scroll, always visible at the panel bottom) ---
	outer.add_child(_sep())
	var a1 := HBoxContainer.new()
	a1.add_theme_constant_override("separation", 2)
	outer.add_child(a1)
	_add_button(a1, "Preview", _preview)
	_shoot_btn = _add_button(a1, "Shoot:On", _toggle_shoot)
	_add_button(a1, "Send>C", _send_to_conductor)
	var a2 := HBoxContainer.new()
	a2.add_theme_constant_override("separation", 2)
	outer.add_child(a2)
	_add_button(a2, "Save", _save_json)
	_add_button(a2, "Export", _export)
	var a3 := HBoxContainer.new()
	a3.add_theme_constant_override("separation", 2)
	outer.add_child(a3)
	_add_button(a3, "ClearGrid", _clear_grid)
	_add_button(a3, "Back", _on_back)
	_status_lbl = _new_label("", UiTheme.COLOR_FAINT, SZ)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.custom_minimum_size = Vector2(120, 0)
	outer.add_child(_status_lbl)

	# Right gutter — enemy palette.
	var right := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	right.add_child(rv)
	_fill_panel(rv)
	_add_caption(rv, "ENEMY BRUSH")
	# Sort rockers — reorder the palette by faction or size (Any stays pinned on top).
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 2)
	rv.add_child(sort_row)
	_add_button(sort_row, "Fac", func(): _sort_palette("faction"))
	_add_button(sort_row, "Size", func(): _sort_palette("size"))
	_add_button(sort_row, "A-Z", func(): _sort_palette("default"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	_palette_listbox = VBoxContainer.new()
	_palette_listbox.add_theme_constant_override("separation", 1)
	_palette_listbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_palette_listbox)
	_rebuild_enemy_buttons()


func _rebuild_enemy_buttons() -> void:
	if _palette_listbox == null:
		return
	for ch in _palette_listbox.get_children():
		_palette_listbox.remove_child(ch)
		ch.queue_free()
	_enemy_buttons = []
	for i in _enemy_choices.size():
		var b := Button.new()
		b.text = String(_enemy_choices[i]["label"])
		b.toggle_mode = true
		b.button_pressed = (String(_enemy_choices[i]["scene"]) == _brush_enemy)
		b.custom_minimum_size = Vector2(0, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon = _frame0_tex(String(_enemy_choices[i]["scene"]))   # codex-style frame-0 preview
		b.expand_icon = true
		_style_button(b)
		var idx: int = i
		b.pressed.connect(func(): _select_enemy(idx))
		_palette_listbox.add_child(b)
		_enemy_buttons.append(b)


# Reorder the enemy palette ("Any (wild)" stays first); rebuild the buttons.
func _sort_palette(key: String) -> void:
	var head: Dictionary = _enemy_choices[0]
	var rest: Array = _enemy_choices.slice(1)
	if key == "faction":
		rest.sort_custom(func(a, b):
			if String(a["faction"]) != String(b["faction"]):
				return String(a["faction"]) < String(b["faction"])
			return String(a["label"]) < String(b["label"]))
	elif key == "size":
		var ord := {"tiny": 0, "small": 1, "medium": 2, "large": 3, "huge": 4, "giant": 5}
		rest.sort_custom(func(a, b):
			var az: int = int(ord.get(String(a["size"]), 1))
			var bz: int = int(ord.get(String(b["size"]), 1))
			if az != bz:
				return az < bz
			return String(a["label"]) < String(b["label"]))
	else:
		rest.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
	_enemy_choices = [head] + rest
	_rebuild_enemy_buttons()


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


func _cycle_dir(d: int) -> void:
	_dir_idx = (_dir_idx + d + DIRS.size()) % DIRS.size()
	_brush_dir = String(DIRS[_dir_idx])
	_dir_lbl.text = "dir: %s" % ("any" if _brush_dir == "" else _brush_dir)
	_update_status()


func _cycle_depth(d: int) -> void:
	_depth_idx = (_depth_idx + d + DEPTHS.size()) % DEPTHS.size()
	_brush_depth = String(DEPTHS[_depth_idx])
	_depth_lbl.text = "depth: %s" % ("def" if _brush_depth == "" else _brush_depth)
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
	if _name_lbl and not _name_lbl.has_focus():
		_name_lbl.text = String(_cur().get("name", "-"))
	if _fac_lbl:
		_fac_lbl.text = "fac: %s" % String(_cur().get("faction", "any"))
	if _sector_lbl:
		_sector_lbl.text = "minS: %d" % int(_cur().get("min_sector", 0))
	if _stagger_lbl:
		_stagger_lbl.text = "stg: %s" % str(_cur().get("stagger", 0.18))
	if _mode_btn:
		_mode_btn.text = "spd: formation" if bool(_cur().get("lockstep", false)) else "spd: free"


# Toggle the current pattern's speed mode: Formation (lockstep to the slowest unit) vs Free.
func _toggle_speed_mode() -> void:
	var on: bool = not bool(_cur().get("lockstep", false))
	_cur()["lockstep"] = on
	if _mode_btn:
		_mode_btn.text = "spd: formation" if on else "spd: free"
	_set_status("speed mode: %s" % ("FORMATION (slowest-wins)" if on else "free"))


func _rename_pattern() -> void:
	# Focus the name field so you can type a new name (Enter or click-away commits it).
	if _name_lbl:
		_name_lbl.grab_focus()
		_name_lbl.select_all()


# Commit an edited pattern name (from the name LineEdit's text_submitted/focus_exited). Blank ignored.
func _commit_name(t: String) -> void:
	if _library.is_empty():
		return
	var nm: String = t.strip_edges()
	if nm == "":
		return
	_cur()["name"] = nm
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


func _process(delta: float) -> void:
	_pulse_t += delta
	if _overlay:
		_overlay.queue_redraw()   # animate the placed-enemy direction pulse
	_tame_preview_enemies()


# Preview hygiene: spawned enemies default to UNLIMITED recycle (recycle_passes = -1), so a single
# formation loops forever. Pin each to 0 (one pass) so the preview plays out and clears, and apply
# the Shoot toggle. Tagged via meta so each enemy is handled exactly once.
func _tame_preview_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.has_meta("_fb_tamed"):
			continue
		e.set_meta("_fb_tamed", true)
		if "recycle_passes" in e:
			e.recycle_passes = 0
		if not _shoot_enabled:
			_disable_firing(e)


func _toggle_shoot() -> void:
	_shoot_enabled = not _shoot_enabled
	if _shoot_btn:
		_shoot_btn.text = "Shoot:On" if _shoot_enabled else "Shoot:Off"
	if not _shoot_enabled:
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e):
				_disable_firing(e)
		for grp in ["enemy_bullets", "bullets"]:
			for n in get_tree().get_nodes_in_group(grp):
				if is_instance_valid(n):
					n.queue_free()
	# Re-enabling only affects the next Preview (already-spawned enemies stay silent).


# Stop every firing path on a preview enemy: hull weapon, mounted turrets, and gun/launcher mounts.
func _disable_firing(e: Node) -> void:
	if "shoot_pattern" in e:
		e.shoot_pattern = null
	for t in e.find_children("*", "", true, false):
		if t.get_script() == EnemyTurretScript and "enabled" in t:
			t.enabled = false
	if "_components" in e and e._components is Array:
		var kept: Array = []
		for c in e._components:
			if c.get_script() != MountComponentScript:
				kept.append(c)
		e._components = kept


# Coarse "where it's headed" direction for the placed-enemy pulse. Crossers go sideways (toward the
# far edge from their spawn lane); lane-movers descend with a lateral lean; the rest descend.
func _move_dir(key: String, lane: int) -> Vector2:
	var k := key.to_lower()
	var side: float = 1.0 if lane < int(Lanes.COUNT / 2) else -1.0
	if k.begins_with("side"):
		return Vector2(side, 0.3)
	if k.begins_with("lane"):
		return Vector2(side * 0.4, 1.0)
	if k.begins_with("skirmish"):
		return Vector2(0.2, 0.9)   # vertical in-lane loops (incl. skirmish_pendulum)
	if k.begins_with("loiter") or k.begins_with("drift"):
		return Vector2(0.15, 0.85)
	return Vector2(0, 1)   # straight_*, hunt_*, proximity_*, wildcard → descend


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
	# Only TINY enemies pack into the 3×3 sub-grid; everything else occupies the cell centre (1,1).
	# Effective size = explicit brush size → the brush enemy's roster size → "small" ("any" assumes small).
	var sx: int = 1
	var sy: int = 1
	if _effective_brush_size() == "tiny":
		sx = clampi(int((pos.x - Lanes.lane_left(lane)) / (Lanes.WIDTH / float(SUB))), 0, SUB - 1)
		sy = clampi(int((pos.y - (Playfield.Y_MIN + float(row) * _row_h())) / (_row_h() / float(SUB))), 0, SUB - 1)
	var k := Vector2i(lane, row)
	var sub := Vector2i(sx, sy)
	if _cells.has(k) and _cells[k].has(sub):
		_cells[k].erase(sub)
		if _cells[k].is_empty():
			_cells.erase(k)
	else:
		if not _cells.has(k):
			_cells[k] = {}
		_cells[k][sub] = {"enemy": _brush_enemy, "movement": _brush_move, "size": _brush_size, "dir": _brush_dir, "depth": _brush_depth}
	_sync_placements()
	_overlay.queue_redraw()
	_update_status()


func _effective_brush_size() -> String:
	if _brush_size != "":
		return _brush_size
	if _brush_enemy != "":
		var s := String(EnemyRosterC.entry_for_scene(_brush_enemy).get("size", ""))
		if s != "":
			return s
	return "small"


func _set_status(s: String) -> void:
	if _status_lbl:
		_status_lbl.text = s


func _update_status() -> void:
	if _status_lbl == null:
		return
	var total := 0
	for k in _cells:
		total += _cells[k].size()
	_status_lbl.text = "slots: %d   brush: %s / %s" % [
		total, ("Any" if _brush_enemy == "" else _enemy_short(_brush_enemy)),
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
