extends Control

# Ship Sizer — dev tuner that lets Roman iterate the on-screen size of every
# ship (player + every enemy / boss scene) against a real combat backdrop +
# the 216×270 playfield band.
#
# Layout mirrors scripts/dev/ui_designer.gd: galaxy_backdrop behind, glass
# gutters + vertical-only outline panel, knob rail on its own CanvasLayer
# at layer=20 so it always reads above the playfield outline.
#
# Sizing contract (per scripts/levels/director.gd lines 106-114):
#   - Each enemy scene exports `display_scale: float`. The WaveDirector reads
#     it on spawn and sets `enemy.scale = Vector2(s, s)` when > 0.
#   - Player ship doesn't have `display_scale`; we drive `player.scale`
#     directly.
# This tuner stores one size per scene_path in a flat dict, applies it live
# to the preview instance, and Roman copies a paste-ready snippet back into
# the .gd files himself (no auto-rewrite of source).

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const BACKDROP_SCRIPT = preload("res://scripts/galaxy_backdrop.gd")
# Playfield class_name resolves at parse time inside .tscn-loaded scripts
# but Godot 4.4.1's GDScript::reload path can't see the global class cache
# (capture scripts hit this — "Identifier Playfield not declared"). Make it
# a local const so the file is self-contained regardless of load path.
const Playfield = preload("res://scripts/playfield.gd")

const CONFIG_PATH := "user://tuners/ship_sizer.json"

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"

# Ordered list of ships available in the picker. First entry is the player;
# the rest are the explicit roster from the task brief. Label is what the
# OptionButton shows.
const SHIPS := [
	{"path": PLAYER_SCENE_PATH,                              "label": "Player"},
	{"path": "res://scenes/enemies/enemy_firecore.tscn",     "label": "Firecore"},
	{"path": "res://scenes/enemies/enemy_drifter.tscn",      "label": "Drifter"},
	{"path": "res://scenes/enemies/enemy_crystal.tscn",      "label": "Crystal"},
	{"path": "res://scenes/enemies/enemy_dart.tscn",         "label": "Dart"},
	{"path": "res://scenes/enemies/enemy_weaver.tscn",       "label": "Weaver"},
	{"path": "res://scenes/enemies/enemy_hover.tscn",        "label": "Hover"},
	{"path": "res://scenes/enemies/enemy_mine.tscn",         "label": "Mine"},
	{"path": "res://scenes/enemies/enemy_mine_shield.tscn",  "label": "Mine Shield"},
	{"path": "res://scenes/enemies/enemy_mine_cluster.tscn", "label": "Mine Cluster"},
	{"path": "res://scenes/enemies/enemy_mine_cluster_smart.tscn", "label": "Mine Cluster Smart"},
	{"path": "res://scenes/enemies/enemy_mine_smart.tscn",   "label": "Mine Smart"},
	{"path": "res://scenes/enemies/enemy_bomblet.tscn",      "label": "Bomblet"},
	{"path": "res://scenes/enemies/enemy_smart_bomblet.tscn","label": "Smart Bomblet"},
	{"path": "res://scenes/enemies/enemy_asteroid.tscn",     "label": "Asteroid"},
	{"path": "res://scenes/enemies/enemy_bomber.tscn",       "label": "Bomber"},
	{"path": "res://scenes/enemies/enemy_bulwark.tscn",      "label": "Bulwark"},
	{"path": "res://scenes/enemies/enemy_frigate.tscn",      "label": "Frigate"},
	{"path": "res://scenes/enemies/enemy_cutter.tscn",       "label": "Cutter"},
	{"path": "res://scenes/enemies/enemy_skirmisher.tscn",   "label": "Skirmisher"},
	{"path": "res://scenes/enemies/enemy_interceptor.tscn",  "label": "Interceptor"},
	{"path": "res://scenes/enemies/enemy_minelayer.tscn",    "label": "Minelayer"},
	{"path": "res://scenes/enemies/enemy_hunter_drone.tscn", "label": "Hunter Drone"},
	{"path": "res://scenes/enemies/boss.tscn",               "label": "Boss (Commander)"},
	{"path": "res://scenes/enemies/boss_reaver.tscn",        "label": "Boss (Lash)"},
	{"path": "res://scenes/enemies/boss_sentinel.tscn",      "label": "Boss (Aegis)"},
	{"path": "res://scenes/enemies/boss_howler.tscn",        "label": "Boss (Howler)"},
	{"path": "res://scenes/enemies/boss_voidmaw.tscn",       "label": "Boss (Voidmaw)"},
	{"path": "res://scenes/enemies/boss_spinwright.tscn",    "label": "Boss (Spinwright)"},
	{"path": "res://scenes/enemies/boss_conductor.tscn",     "label": "Boss (Conductor)"},
]

const SIZE_MIN := 0.25
const SIZE_MAX := 4.0
const SIZE_STEP := 0.05
const DEFAULT_SIZE := 1.0

const GLASS_LAYER_Z := 1
const OUTLINE_LAYER_Z := 10
const PREVIEW_LAYER_Z := 5  # ships render between glass + outline

# --- State ----------------------------------------------------------------

var _backdrop: Node2D = null
var _glass_layer: CanvasLayer = null
var _frame_layer: CanvasLayer = null
var _preview_layer: CanvasLayer = null

var _sizes: Dictionary = {}        # scene_path -> float
var _flips: Dictionary = {}        # scene_path -> bool (extra 180° flip)
var _current_index: int = 0
var _show_all: bool = false

var _picker: OptionButton = null
var _size_slider: HSlider = null
var _size_spin: SpinBox = null
var _show_all_check: CheckButton = null
var _flip_check: CheckButton = null
var _status_label: Label = null
var _grabber_tex: ImageTexture = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_defaults()
	_load_from_disk()
	_install_backdrop_and_frame()
	_preview_layer = CanvasLayer.new()
	_preview_layer.name = "ShipPreview"
	_preview_layer.layer = PREVIEW_LAYER_Z
	add_child(_preview_layer)
	_build_ui()
	_rebuild_preview()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _seed_defaults() -> void:
	for ship in SHIPS:
		_sizes[String(ship["path"])] = DEFAULT_SIZE
		_flips[String(ship["path"])] = false


func _make_grabber_texture() -> ImageTexture:
	if _grabber_tex != null:
		return _grabber_tex
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in 4:
		for x in 4:
			var dx := float(x) - 1.5
			var dy := float(y) - 1.5
			if dx * dx + dy * dy <= 4.0:
				img.set_pixel(x, y, Color(0.85, 0.92, 1.0, 1.0))
	_grabber_tex = ImageTexture.create_from_image(img)
	return _grabber_tex


# --- Backdrop + playfield frame ------------------------------------------

func _install_backdrop_and_frame() -> void:
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_script(BACKDROP_SCRIPT)
	_backdrop.set("drift_speed", 10.0)
	_backdrop.set("starfield_density", 30.0)
	_backdrop.set("starfield_scroll", 5.0)
	_backdrop.set("warp_streak_count", 6)
	_backdrop.set("warp_streak_speed", 280.0)
	add_child(_backdrop)
	move_child(_backdrop, 0)

	_glass_layer = CanvasLayer.new()
	_glass_layer.name = "PlayfieldGlass"
	_glass_layer.layer = GLASS_LAYER_Z
	add_child(_glass_layer)

	_frame_layer = CanvasLayer.new()
	_frame_layer.name = "PlayfieldFrame"
	_frame_layer.layer = OUTLINE_LAYER_Z
	add_child(_frame_layer)

	var glass_bg := Color(0.04, 0.06, 0.10, 0.55)
	var glass_edge := Color(0.32, 0.50, 0.72, 1.0)

	for spec in [
		{"name": "GutterLeft",  "x": 0.0,             "w": Playfield.X_MIN,         "edge": "right"},
		{"name": "GutterRight", "x": Playfield.X_MAX, "w": 480.0 - Playfield.X_MAX, "edge": "left"},
	]:
		var panel := Panel.new()
		panel.name = String(spec["name"])
		panel.position = Vector2(float(spec["x"]), 0.0)
		panel.size = Vector2(float(spec["w"]), 270.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = glass_bg
		gsb.border_color = glass_edge
		if String(spec["edge"]) == "right":
			gsb.border_width_right = 1
		else:
			gsb.border_width_left = 1
		panel.add_theme_stylebox_override("panel", gsb)
		_glass_layer.add_child(panel)

	var frame := Panel.new()
	frame.name = "Frame"
	frame.position = Vector2(Playfield.X_MIN, Playfield.Y_MIN)
	frame.size = Vector2(Playfield.W, Playfield.H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = glass_edge
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	frame.add_theme_stylebox_override("panel", sb)
	_frame_layer.add_child(frame)


# --- UI rail --------------------------------------------------------------

func _build_ui() -> void:
	var rail_layer := CanvasLayer.new()
	rail_layer.name = "TunerRail"
	rail_layer.layer = 20
	add_child(rail_layer)

	var header := Label.new()
	header.text = "SHIP SIZER — Esc to close"
	header.position = Vector2(6, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	header.add_theme_font_size_override("font_size", 9)
	rail_layer.add_child(header)

	var rail_bg := PanelContainer.new()
	rail_bg.position = Vector2(6, 38)
	rail_bg.size = Vector2(158, 224)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.86)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	rail_bg.add_theme_stylebox_override("panel", sb)
	rail_layer.add_child(rail_bg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_bg.add_child(scroll)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 1)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rail)

	# Ship picker row.
	var pick_lbl := Label.new()
	pick_lbl.text = "Ship"
	UiTheme.style_label(pick_lbl, UiTheme.LabelKind.CAPTION)
	pick_lbl.add_theme_font_size_override("font_size", 8)
	rail.add_child(pick_lbl)

	_picker = OptionButton.new()
	_picker.custom_minimum_size = Vector2(0, 12)
	_picker.add_theme_font_size_override("font_size", 8)
	for ship in SHIPS:
		_picker.add_item(String(ship["label"]))
	_picker.select(0)
	_picker.item_selected.connect(_on_picker_changed)
	rail.add_child(_picker)

	# Prev / Next row.
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 2)
	rail.add_child(nav_row)
	var prev_btn := Button.new()
	prev_btn.text = "Prev"
	prev_btn.custom_minimum_size = Vector2(0, 12)
	prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_btn.add_theme_font_size_override("font_size", 8)
	UiTheme.style_button(prev_btn, true)
	prev_btn.pressed.connect(_on_prev)
	nav_row.add_child(prev_btn)
	var next_btn := Button.new()
	next_btn.text = "Next"
	next_btn.custom_minimum_size = Vector2(0, 12)
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.add_theme_font_size_override("font_size", 8)
	UiTheme.style_button(next_btn, true)
	next_btn.pressed.connect(_on_next)
	nav_row.add_child(next_btn)

	rail.add_child(HSeparator.new())

	# Drawn size — slider + spinbox in one row, matching ui_designer.gd.
	var size_lbl := Label.new()
	size_lbl.text = "Drawn size"
	UiTheme.style_label(size_lbl, UiTheme.LabelKind.CAPTION)
	size_lbl.add_theme_font_size_override("font_size", 8)
	rail.add_child(size_lbl)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 2)
	rail.add_child(size_row)

	_size_slider = HSlider.new()
	_size_slider.min_value = SIZE_MIN
	_size_slider.max_value = SIZE_MAX
	_size_slider.step = SIZE_STEP
	_size_slider.value = DEFAULT_SIZE
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_slider.custom_minimum_size = Vector2(0, 8)
	var grab_tex := _make_grabber_texture()
	if grab_tex:
		_size_slider.add_theme_icon_override("grabber", grab_tex)
		_size_slider.add_theme_icon_override("grabber_highlight", grab_tex)
		_size_slider.add_theme_icon_override("grabber_disabled", grab_tex)
	size_row.add_child(_size_slider)

	_size_spin = SpinBox.new()
	_size_spin.min_value = SIZE_MIN
	_size_spin.max_value = SIZE_MAX
	_size_spin.step = SIZE_STEP
	_size_spin.value = DEFAULT_SIZE
	_size_spin.custom_minimum_size = Vector2(38, 10)
	_size_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_row.add_child(_size_spin)
	var le := _size_spin.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", 7)

	_size_slider.value_changed.connect(_on_size_changed)
	_size_spin.value_changed.connect(_on_size_changed)

	# Flip toggle — adds 180° to the current ship's rotation, in case the
	# default face-down orientation is backwards for some sprite.
	_flip_check = CheckButton.new()
	_flip_check.text = "Flip 180°"
	_flip_check.custom_minimum_size = Vector2(0, 12)
	_flip_check.add_theme_font_size_override("font_size", 8)
	_flip_check.toggled.connect(_on_flip_toggled)
	rail.add_child(_flip_check)

	rail.add_child(HSeparator.new())

	# Show All toggle.
	_show_all_check = CheckButton.new()
	_show_all_check.text = "Show all"
	_show_all_check.custom_minimum_size = Vector2(0, 12)
	_show_all_check.add_theme_font_size_override("font_size", 8)
	_show_all_check.button_pressed = false
	_show_all_check.toggled.connect(_on_show_all_toggled)
	rail.add_child(_show_all_check)

	rail.add_child(HSeparator.new())

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(130, 0)
	UiTheme.style_label(_status_label, UiTheme.LabelKind.CAPTION)
	_status_label.add_theme_font_size_override("font_size", 8)
	rail.add_child(_status_label)

	_add_button(rail, "Save",             _on_save)
	_add_button(rail, "Load",             _on_load)
	_add_button(rail, "Reset Defaults",   _on_reset)
	_add_button(rail, "Copy GDScript",    _on_copy_snippet)
	rail.add_child(HSeparator.new())
	_add_button(rail, "Back to Dev Menu", _on_back)

	_sync_size_editors()


func _add_button(parent: Node, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 12)
	btn.add_theme_font_size_override("font_size", 8)
	UiTheme.style_button(btn, true)
	btn.pressed.connect(cb)
	parent.add_child(btn)


# --- Preview --------------------------------------------------------------

func _clear_preview() -> void:
	if _preview_layer == null or not is_instance_valid(_preview_layer):
		return
	for c in _preview_layer.get_children():
		c.queue_free()


func _rebuild_preview() -> void:
	_clear_preview()
	if _show_all:
		_build_grid_preview()
	else:
		_build_single_preview()


func _build_single_preview() -> void:
	# Always mount the player at the bottom of the band so Roman has a
	# size reference — even when an enemy is selected.
	var player_size: float = float(_sizes.get(PLAYER_SCENE_PATH, DEFAULT_SIZE))
	var player_inst = _instance_ship(PLAYER_SCENE_PATH, player_size)
	if player_inst is Node2D:
		(player_inst as Node2D).position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 30.0)
	if player_inst != null:
		_preview_layer.add_child(player_inst)

	# If the picker is on the player, we're done — don't double-mount.
	var ship: Dictionary = SHIPS[_current_index]
	var path: String = String(ship["path"])
	if path == PLAYER_SCENE_PATH:
		return
	var size: float = float(_sizes.get(path, DEFAULT_SIZE))
	var inst = _instance_ship(path, size)
	if inst == null:
		_set_status("Failed to instantiate %s" % path)
		return
	if inst is Node2D:
		(inst as Node2D).position = Playfield.CENTER
	_preview_layer.add_child(inst)


func _build_grid_preview() -> void:
	# Lay every ship out in a grid inside the playfield band. 4 columns × N
	# rows; cell pitch is tuned so a 1× thumbnail (~16 px ship) reads at
	# native scale with a label below.
	var cols: int = 4
	var rows: int = int(ceil(float(SHIPS.size()) / float(cols)))
	var inner_w: float = Playfield.W - 16.0  # 8 px inset each side
	var inner_h: float = Playfield.H - 16.0
	var cell_w: float = inner_w / float(cols)
	var cell_h: float = inner_h / float(rows)
	var origin: Vector2 = Vector2(Playfield.X_MIN + 8.0, Playfield.Y_MIN + 8.0)
	for i in SHIPS.size():
		var ship: Dictionary = SHIPS[i]
		var path: String = String(ship["path"])
		var lbl: String = String(ship["label"])
		var size: float = float(_sizes.get(path, DEFAULT_SIZE))
		var col: int = i % cols
		var row: int = i / cols
		var cx: float = origin.x + cell_w * (float(col) + 0.5)
		var cy: float = origin.y + cell_h * (float(row) + 0.5)
		var inst = _instance_ship(path, size)
		if inst == null:
			continue
		if inst is Node2D:
			(inst as Node2D).position = Vector2(cx, cy - 4.0)
		_preview_layer.add_child(inst)
		# Label under the ship. Render as a Control on the preview layer
		# (CanvasLayer accepts Control children).
		var name_lbl := Label.new()
		name_lbl.text = lbl
		name_lbl.position = Vector2(cx - cell_w * 0.5, cy + cell_h * 0.5 - 8.0)
		name_lbl.size = Vector2(cell_w, 8.0)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 6)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_layer.add_child(name_lbl)


func _instance_ship(path: String, size: float) -> Node:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if inst == null:
		return null
	# Disable motion/AI/shoot logic so the preview ship sits still.
	# Bomber/bulwark/mine_smart subclass _process heavily —
	# PROCESS_MODE_DISABLED is the safest catch-all.
	if path == PLAYER_SCENE_PATH:
		if "controls_enabled" in inst:
			inst.set("controls_enabled", false)
	else:
		inst.process_mode = Node.PROCESS_MODE_DISABLED
	# Drive scale.
	if "display_scale" in inst:
		inst.set("display_scale", size)
	if inst is Node2D:
		(inst as Node2D).scale = Vector2(size, size)
	# Facing. Enemy sprites are authored facing UP; in combat their
	# movement_pattern rotates them to face their travel direction
	# (typically PI = down). Since process_mode is DISABLED, that never
	# runs in the preview. Set rotation = PI by hand so enemies render
	# the way they actually spawn. Player ship stays at rotation 0
	# (faces up — its in-game orientation). Flip toggle adds another PI.
	if inst is Node2D and path != PLAYER_SCENE_PATH:
		var base_rot: float = PI
		if bool(_flips.get(path, false)):
			base_rot += PI
		(inst as Node2D).rotation = base_rot
		# auto_rotate would still try to overwrite this on the first
		# physics tick if the parent re-enables processing, so clear it.
		if "auto_rotate" in inst:
			inst.set("auto_rotate", false)
	# Strip the orange engine flame + parallax shadow VFX that enemy_core
	# / enemy_base attach in _ready. They render as a glow / dark blob
	# behind the sprite and clutter the preview.
	_strip_preview_vfx(inst)
	return inst


func _strip_preview_vfx(root: Node) -> void:
	# Hide any child node that's a particle system or whose name matches
	# a known VFX helper. Walks the tree once so deeply-nested attachments
	# (e.g. effects attached via static .attach() helpers) are caught.
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
			if c is CPUParticles2D or c is GPUParticles2D:
				c.visible = false
				continue
			var nm: String = String(c.name).to_lower()
			if nm.find("engineflame") >= 0 or nm.find("torch") >= 0 \
				or nm.find("smoke") >= 0 or nm.find("trail") >= 0 \
				or nm.find("shadow") >= 0 or nm.find("burn") >= 0 \
				or nm.find("warp") >= 0 or nm.find("muzzle") >= 0:
				c.visible = false


# --- Knob handlers --------------------------------------------------------

func _on_picker_changed(idx: int) -> void:
	_current_index = idx
	_sync_size_editors()
	_rebuild_preview()


func _on_prev() -> void:
	_current_index = (_current_index - 1 + SHIPS.size()) % SHIPS.size()
	_picker.select(_current_index)
	_sync_size_editors()
	_rebuild_preview()


func _on_next() -> void:
	_current_index = (_current_index + 1) % SHIPS.size()
	_picker.select(_current_index)
	_sync_size_editors()
	_rebuild_preview()


func _on_size_changed(v: float) -> void:
	var path: String = String(SHIPS[_current_index]["path"])
	var rounded: float = snapped(v, SIZE_STEP)
	if abs(float(_sizes.get(path, DEFAULT_SIZE)) - rounded) < 0.0001:
		# Keep sibling editors in sync anyway (they may be on a fractional
		# step the other rounded differently).
		_sync_size_editors()
		return
	_sizes[path] = rounded
	_sync_size_editors()
	_rebuild_preview()


func _on_show_all_toggled(pressed: bool) -> void:
	_show_all = pressed
	_rebuild_preview()


func _on_flip_toggled(pressed: bool) -> void:
	var path: String = String(SHIPS[_current_index]["path"])
	_flips[path] = pressed
	_rebuild_preview()


func _sync_size_editors() -> void:
	var path: String = String(SHIPS[_current_index]["path"])
	var v: float = float(_sizes.get(path, DEFAULT_SIZE))
	if _size_slider:
		_size_slider.set_value_no_signal(v)
	if _size_spin:
		_size_spin.set_value_no_signal(v)
	if _flip_check:
		_flip_check.set_pressed_no_signal(bool(_flips.get(path, false)))


# --- Persistence ---------------------------------------------------------

func _save_to_disk() -> bool:
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("tuners"):
			dir.make_dir("tuners")
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var out := {"sizes": _sizes, "flips": _flips}
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	return true


func _load_from_disk() -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		return false
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return false
	# v2 schema: {"sizes": {...}, "flips": {...}}. Fall back to v1 (flat
	# dict of sizes) if "sizes" key is missing.
	var sizes_in: Dictionary = parsed.get("sizes", parsed) as Dictionary
	var flips_in: Dictionary = parsed.get("flips", {}) as Dictionary
	for ship in SHIPS:
		var p: String = String(ship["path"])
		if sizes_in.has(p):
			_sizes[p] = float(sizes_in[p])
		if flips_in.has(p):
			_flips[p] = bool(flips_in[p])
	return true


# --- Snippet output ------------------------------------------------------

func _build_snippet() -> String:
	var lines: PackedStringArray = []
	lines.append("# Ship Sizer export.")
	lines.append("# Paste these into the @export var display_scale lines of each")
	lines.append("# enemy's .gd (or update the .tscn override). Player ship uses")
	lines.append("# scenes/player/player.tscn root.scale directly — no display_scale.")
	lines.append("")
	for ship in SHIPS:
		var path: String = String(ship["path"])
		var lbl: String = String(ship["label"])
		var v: float = float(_sizes.get(path, DEFAULT_SIZE))
		var flipped: bool = bool(_flips.get(path, false))
		var flip_tag: String = "  [FLIP 180°]" if flipped else ""
		lines.append("# %s -> %.2f%s  (%s)" % [path, v, flip_tag, lbl])
	return "\n".join(lines)


# --- Buttons -------------------------------------------------------------

func _on_save() -> void:
	if _save_to_disk():
		_set_status("Saved to %s" % CONFIG_PATH)
	else:
		_set_status("Save FAILED")


func _on_load() -> void:
	if _load_from_disk():
		_sync_size_editors()
		_rebuild_preview()
		_set_status("Loaded from %s" % CONFIG_PATH)
	else:
		_set_status("No saved config (or load failed)")


func _on_reset() -> void:
	_seed_defaults()
	_sync_size_editors()
	_rebuild_preview()
	_set_status("Reset to defaults")


func _on_copy_snippet() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied (%d chars)" % s.length())


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
