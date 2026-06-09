extends Control

# Pattern Eligibility Editor (Phase 2, docs/pattern_eligibility_2026-06-08.md). Per-enemy
# authoring for the movement-pattern matrix: pick a faction → pick an enemy → set its identity
# movement + check the behaviors it's eligible for, with a LIVE PREVIEW of the enemy's sprite
# running the highlighted behavior. Iterates against user://tuners/pattern_eligibility.json;
# Export emits a paste-ready DATA const (clipboard + file) to drop into
# scripts/levels/pattern_eligibility.gd (the committed source of truth — production never reads
# user://). Standalone tool (not a lane-visualizer tab) to stay clear of other UI work.
#
# Native 480×270 (like lane_visualizer): gutters host controls, the band shows the preview.
# Esc returns to the dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const Factions = preload("res://scripts/levels/factions.gd")

const SAVE_PATH := "user://tuners/pattern_eligibility.json"
const EXPORT_PATH := "user://tuners/pattern_eligibility_export.txt"

# The offerable movement keys (the 2026-06-08 make_movement pattern set).
const MOVEMENT_KEYS := [
	"straight_crawl", "straight_slow", "straight_medium", "straight_fast", "straight_reflex", "straight_charge",
	"skirmish_loop", "skirmish_figure8",
	"drift_low", "drift_mid", "drift_high",
	"loiter_low", "loiter_mid", "loiter_high",
	"lane_weave", "lane_drift", "lane_shift", "lane_hook", "lane_cut",
	"side_turn", "side_dive", "side_traverse",
	"top_dive", "hunt_beeline", "hunt_omni",
]

const FACTION_FILTERS := ["All", "Sup", "Priv", "Corp", "Zealot"]
const FACTION_HOME := {"Sup": 0, "Priv": 1, "Corp": 2, "Zealot": 3}  # Factions.Id order

const SZ := 7   # native font size (matches lane_visualizer)

var _data: Dictionary = {}          # working copy: scene -> {identity, eligible[]}
var _scenes: Array = []             # all matrix scene paths (sorted)
var _filtered: Array = []           # scenes matching the current faction filter
var _filter: String = "All"
var _idx: int = 0                   # index into _filtered
var _tex_cache: Dictionary = {}

var _world: Node2D = null
var _preview: Node2D = null
var _enemy_lbl: Label = null
var _identity_lbl: Label = null
var _status_lbl: Label = null
var _check_box: VBoxContainer = null
var _checks: Dictionary = {}        # key -> Button(toggle)
var _preview_key: String = ""       # behavior currently previewed


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_data()
	_build_bg()
	_world = Node2D.new()
	_world.name = "PreviewWorld"
	add_child(_world)
	_build_ui()
	_apply_filter()


# ---------------------------------------------------------------- data

func _load_data() -> void:
	# Start from the committed matrix, then overlay any saved iteration JSON.
	for scene in PatternEligibility.DATA.keys():
		var rec: Dictionary = PatternEligibility.DATA[scene]
		_data[scene] = {
			"identity": str(rec.get("identity", "")),
			"eligible": (rec.get("eligible", []) as Array).duplicate(),
		}
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				for scene in parsed.keys():
					if _data.has(scene) and parsed[scene] is Dictionary:
						var p: Dictionary = parsed[scene]
						_data[scene]["identity"] = str(p.get("identity", _data[scene]["identity"]))
						if p.get("eligible", null) is Array:
							_data[scene]["eligible"] = (p["eligible"] as Array).duplicate()
	_scenes = _data.keys()
	_scenes.sort()


func _home_of(scene: String) -> int:
	var t: Variant = Factions.ENEMY_TAGS.get(scene, null)
	if t == null:
		return -1
	return int(t.get("home", -1))


func _apply_filter() -> void:
	_filtered = []
	for scene in _scenes:
		if _filter == "All":
			_filtered.append(scene)
		elif int(_home_of(scene)) == int(FACTION_HOME.get(_filter, -99)):
			_filtered.append(scene)
	if _filtered.is_empty():
		_filtered = _scenes.duplicate()
	_idx = clampi(_idx, 0, _filtered.size() - 1)
	_refresh_enemy()


func _current_scene() -> String:
	if _filtered.is_empty():
		return ""
	return str(_filtered[_idx])


# ---------------------------------------------------------------- preview

func _refresh_enemy() -> void:
	var scene: String = _current_scene()
	if scene == "":
		return
	if _enemy_lbl:
		_enemy_lbl.text = "%d/%d  %s" % [_idx + 1, _filtered.size(), scene.get_file().replace(".tscn", "")]
	var rec: Dictionary = _data.get(scene, {})
	if _identity_lbl:
		_identity_lbl.text = "id: " + str(rec.get("identity", ""))
	# Sync checkboxes to this enemy's eligible set.
	var elig: Array = rec.get("eligible", [])
	for key in _checks.keys():
		(_checks[key] as Button).set_pressed_no_signal(key in elig)
	# Preview the identity behavior by default.
	_set_preview(str(rec.get("identity", "")))


func _set_preview(key: String) -> void:
	_preview_key = key
	if _preview and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	var scene: String = _current_scene()
	if scene == "" or key == "":
		return
	var pat: Resource = EnemyRoster.make_movement({"movement": key, "scene": scene})
	if pat == null:
		return
	var tex_info: Dictionary = _enemy_texture(scene)
	var d := PreviewDummy.new()
	d.pattern = pat
	d.tex = tex_info.get("texture", null)
	d.hframes = int(tex_info.get("hframes", 1))
	d.position = Vector2(Lanes.lane_center(3), 16.0)
	_world.add_child(d)
	_preview = d   # track it so the NEXT _set_preview frees this one (else dummies pile up)
	if _status_lbl:
		_status_lbl.text = "preview: " + key


# Grab the enemy's hull sprite (frame 0) WITHOUT running its _ready (instantiate doesn't enter
# the tree). Cached per scene.
func _enemy_texture(scene: String) -> Dictionary:
	if _tex_cache.has(scene):
		return _tex_cache[scene]
	var out := {"texture": null, "hframes": 1}
	if ResourceLoader.exists(scene):
		var ps: PackedScene = load(scene)
		if ps != null:
			var inst: Node = ps.instantiate()
			var spr: Node = inst.get_node_or_null("Sprite2D")
			if spr != null and spr is Sprite2D:
				out["texture"] = (spr as Sprite2D).texture
				out["hframes"] = (spr as Sprite2D).hframes
			inst.free()
	_tex_cache[scene] = out
	return out


# ---------------------------------------------------------------- edits

func _toggle_eligible(key: String, on: bool) -> void:
	var scene: String = _current_scene()
	if scene == "":
		return
	var elig: Array = _data[scene]["eligible"]
	if on and not (key in elig):
		elig.append(key)
	elif not on and (key in elig):
		elig.erase(key)
	# Identity must always be eligible — re-check it if it got removed.
	var ident: String = str(_data[scene]["identity"])
	if not (ident in elig):
		elig.append(ident)
		if _checks.has(ident):
			(_checks[ident] as Button).set_pressed_no_signal(true)
	_data[scene]["eligible"] = elig


func _cycle_identity(dir: int) -> void:
	var scene: String = _current_scene()
	if scene == "":
		return
	# Identity cycles through the enemy's ELIGIBLE set (it must be one it can do).
	var elig: Array = _data[scene]["eligible"]
	if elig.is_empty():
		return
	elig.sort()
	var cur: int = elig.find(str(_data[scene]["identity"]))
	if cur < 0:
		cur = 0
	var nxt: int = (cur + dir + elig.size()) % elig.size()
	_data[scene]["identity"] = str(elig[nxt])
	_refresh_enemy()


func _cycle_enemy(dir: int) -> void:
	if _filtered.is_empty():
		return
	_idx = (_idx + dir + _filtered.size()) % _filtered.size()
	_refresh_enemy()


# ---------------------------------------------------------------- save / export

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data, "\t"))
		f.close()
	if _status_lbl:
		_status_lbl.text = "saved json"


func _export() -> void:
	var text: String = _build_data_const()
	DisplayServer.clipboard_set(text)
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	if _status_lbl:
		_status_lbl.text = "exported → clipboard"


# Paste-ready DATA const for scripts/levels/pattern_eligibility.gd (tuner contract).
func _build_data_const() -> String:
	var out: String = "const DATA := {\n"
	for scene in _scenes:
		var rec: Dictionary = _data[scene]
		var elig: Array = (rec.get("eligible", []) as Array).duplicate()
		elig.sort()
		var parts: Array = []
		for k in elig:
			parts.append("\"" + str(k) + "\"")
		out += "\t\"" + scene + "\": {\"identity\": \"" + str(rec.get("identity", "")) + \
			"\", \"eligible\": [" + ", ".join(PackedStringArray(parts)) + "]},\n"
	out += "}\n"
	return out


# ---------------------------------------------------------------- UI

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_ui() -> void:
	# Left gutter — faction filter + enemy nav + identity.
	var left := _panel(Vector2(0, 0), Vector2(128, 270))
	add_child(left)
	var lv := _vbox(left)
	lv.add_child(_label("PATTERN ELIGIBILITY", UiTheme.COLOR_ACCENT))
	_add_caption(lv, "FACTION")
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 1)
	lv.add_child(fr)
	for fname in FACTION_FILTERS:
		_btn(fr, fname, func(): _filter = fname; _idx = 0; _apply_filter())
	lv.add_child(HSeparator.new())
	_add_caption(lv, "ENEMY")
	_enemy_lbl = _label("-", UiTheme.COLOR_TEXT)
	_enemy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_enemy_lbl)
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 2)
	lv.add_child(er)
	_btn(er, "< Prev", func(): _cycle_enemy(-1))
	_btn(er, "Next >", func(): _cycle_enemy(1))
	lv.add_child(HSeparator.new())
	_add_caption(lv, "IDENTITY (default)")
	_identity_lbl = _label("id: -", UiTheme.COLOR_TEXT)
	lv.add_child(_identity_lbl)
	var ir := HBoxContainer.new()
	ir.add_theme_constant_override("separation", 2)
	lv.add_child(ir)
	_btn(ir, "< id", func(): _cycle_identity(-1))
	_btn(ir, "id >", func(): _cycle_identity(1))
	lv.add_child(HSeparator.new())
	_btn(lv, "Save JSON", _save)
	_btn(lv, "Export const", _export)
	_status_lbl = _label("", UiTheme.COLOR_FAINT)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_status_lbl)
	_btn(lv, "Back", _on_back)

	# Right gutter — eligible checklist (scroll).
	var right := _panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := _vbox(right)
	rv.add_child(_label("ELIGIBLE", UiTheme.COLOR_ACCENT))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	_check_box = VBoxContainer.new()
	_check_box.add_theme_constant_override("separation", 1)
	_check_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_check_box)
	for key in MOVEMENT_KEYS:
		var b := Button.new()
		b.text = key
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 11)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b)
		# Toggle eligible on press; click preview-text uses the same key. (A long-press preview
		# isn't available, so checking a box also previews it.)
		b.toggled.connect(func(p: bool):
			_toggle_eligible(key, p)
			_set_preview(key))
		_check_box.add_child(b)
		_checks[key] = b


func _process(_delta: float) -> void:
	pass


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


# ---- UI helpers (mirror lane_visualizer's native-480 styling) ----

func _panel(pos: Vector2, sz: Vector2) -> Panel:
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


func _vbox(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 3
	v.offset_top = 3
	v.offset_right = -3
	v.offset_bottom = -3
	parent.add_child(v)
	return v


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", SZ)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 1)
	return l


func _add_caption(parent: Node, text: String) -> void:
	parent.add_child(_label(text, UiTheme.COLOR_FAINT))


func _button_sb(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
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
	b.add_theme_stylebox_override("normal", _button_sb(Color(0.08, 0.11, 0.16, 0.9)))
	b.add_theme_stylebox_override("hover", _button_sb(Color(0.12, 0.17, 0.24, 0.95)))
	var on_sb := _button_sb(Color(0.20, 0.34, 0.50, 0.95))
	on_sb.border_color = UiTheme.COLOR_ACCENT
	b.add_theme_stylebox_override("pressed", on_sb)


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- preview dummy

# Shows an enemy's sprite running ONE movement pattern in absolute coords, looping when it
# leaves the band. Exposes only the fields patterns read.
class PreviewDummy extends Node2D:
	var pattern = null
	var tex: Texture2D = null
	var hframes: int = 1
	var auto_rotate: bool = true
	var allow_side_exit: bool = false
	var offscreen_mode: int = 0   # dive_return sets FREE_ANY_EDGE (=1); harmless here
	var _spawn: Vector2 = Vector2.ZERO
	var _trail: Line2D = null
	const MAX_TRAIL := 200

	func _ready() -> void:
		_spawn = position
		add_to_group("enemies")  # lane-aware patterns query occupancy
		if tex != null:
			var s := Sprite2D.new()
			s.texture = tex
			s.hframes = maxi(hframes, 1)
			s.frame = 0
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(s)
		else:
			var body := Polygon2D.new()
			body.polygon = PackedVector2Array([Vector2(0, -6), Vector2(-5, 5), Vector2(0, 2), Vector2(5, 5)])
			body.color = Color(0.6, 0.95, 1.0)
			add_child(body)
		_trail = Line2D.new()
		_trail.width = 1.0
		_trail.default_color = Color(0.6, 0.95, 1.0, 0.45)
		get_parent().add_child(_trail)
		if pattern and pattern.has_method("on_start"):
			pattern.on_start(self)

	func _process(delta: float) -> void:
		if pattern == null:
			return
		var safe: float = min(delta, 1.0 / 30.0)
		position += pattern.compute_step(self, safe)
		if _trail and is_instance_valid(_trail):
			_trail.add_point(global_position)
			if _trail.get_point_count() > MAX_TRAIL:
				_trail.remove_point(0)
		if position.y > Playfield.Y_MAX + 18.0 or position.y < -28.0 \
				or position.x < Playfield.X_MIN - 30.0 or position.x > Playfield.X_MAX + 30.0:
			_reset()

	func _reset() -> void:
		position = _spawn
		offscreen_mode = 0
		if _trail and is_instance_valid(_trail):
			_trail.clear_points()
		if pattern and pattern.has_method("on_start"):
			pattern.on_start(self)

	func _exit_tree() -> void:
		if _trail and is_instance_valid(_trail):
			_trail.queue_free()
