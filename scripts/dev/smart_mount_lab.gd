extends Control

# Smart Mount Lab — HD dev tuner (2026-06-14). A controlled arena for the auto-turret
# modules (Blaster + Primary Smart Mount): a live player ship in a native 480×270
# SubViewport with randomized drifting targets + optional auto player-movement, and live
# knobs for the turret feel (traverse, dispersion, arc, range, fire tolerance). Copy
# GDScript emits paste-ready values for smart_mount.gd + the player MOUNT_* defaults.
# Persists to user://tuners/smart_mount_lab.json.
#
# Playspace mirrors hangar.gd's proven SubViewportContainer skeleton (stretch_shrink=4,
# HDR-2D parity, z=-1 backdrop layer, bullet_parent=_world). The turret runs in the
# player's own _process (controls_enabled=true gates it); auto-move just overrides
# player.position (the ship doesn't self-move without input).

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const TargetScript = preload("res://scripts/dev/mount_lab_target.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")

const SAVE_PATH := "user://tuners/smart_mount_lab.json"
const FS_HEADER := 22
const FS_CAPTION := 14

var _hd_scope: HdViewportScope = null
var _preview_vp: SubViewport = null
var _world: Node2D = null
var _player: Node = null
var _targets: Array = []

# Knob controls.
var _blaster_cb: CheckBox
var _primary_cb: CheckBox
var _btrav: SpinBox
var _bdisp: SpinBox
var _ptrav: SpinBox
var _pdisp: SpinBox
var _arc: SpinBox
var _range: SpinBox
var _tol: SpinBox
var _count: SpinBox
var _tspeed: SpinBox
var _automove_cb: CheckBox
var _amspeed: SpinBox
var _primary_dd: OptionButton
var _status: Label

var _primary_factories: Array = []
var _automove_phase: float = 0.0


func _ready() -> void:
	# HD attach — gate on being the window's scene root (see hangar.gd for the rationale).
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_primary_factories = _factories_for(SlotTypes.SlotType.CANNON)
	_setup_run()
	_build_playspace()
	_build_overlay()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_preview_vp, "SmartMountLab")
	_load()
	_apply_knobs()


# Fresh run + a non-blaster primary so the Primary Mount has a cannon_pool[1] to drive.
func _setup_run() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	run.new_run()
	run.test_mode_active = true
	_equip_primary(run, _default_primary_factory())


func _default_primary_factory() -> String:
	# Prefer a clear, metered/visible primary so cannon_pool[1] is populated.
	for pref in ["_make_heavy_blaster", "_make_rotary_laser", "_make_autocannon"]:
		for e in _primary_factories:
			if e["factory"] == pref:
				return pref
	return _primary_factories[0]["factory"] if not _primary_factories.is_empty() else "_make_heavy_blaster"


func _equip_primary(run, factory: String) -> void:
	var prim = PartCatalog._make_by_name(factory, SlotTypes.SlotType.CANNON)
	if prim != null:
		if "mark" in prim:
			prim.mark = 5
		run.equip_part(prim)


func _factories_for(slot: int) -> Array:
	var out: Array = []
	var seen := {}
	for entry in PartCatalog._all_pool():
		if int(entry["slot"]) != slot:
			continue
		var f := String(entry["factory"])
		if seen.has(f):
			continue
		seen[f] = true
		var part = PartCatalog._make_by_name(f, slot)
		out.append({"factory": f, "name": String(part.display_name) if part != null else f})
	return out


# ---- Playspace (mirrors hangar.gd) --------------------------------------

func _build_playspace() -> void:
	var sub := SubViewportContainer.new()
	sub.stretch = true
	sub.stretch_shrink = 4   # 1920/4 = 480 native, upscaled 4× (see hangar.gd)
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	HdScreen.apply_native_parity(_preview_vp)
	HdScreen.verify_native_subviewport.call_deferred(_preview_vp, "smart_mount_lab")
	sub.add_child(_preview_vp)

	# Opaque backdrop on a z=-1 layer so player bullets (z=-1) render in front of it.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	_preview_vp.add_child(bg_layer)
	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	bg_layer.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	bg_layer.add_child(band)

	_world = Node2D.new()
	_world.name = "World"
	# Advertise this native-coord world as the "bullet_world" sink so any parent-less gameplay fx
	# (explosions, dust, EM burst) resolve HERE instead of the 1920×1080 window's top-left corner.
	_world.add_to_group("bullet_world")
	_preview_vp.add_child(_world)

	_preview_vp.audio_listener_enable_2d = true
	var listener := AudioListener2D.new()
	listener.position = Vector2(Playfield.CENTER.x, Playfield.CENTER.y)
	_world.add_child(listener)
	listener.make_current()

	_spawn_player()


func _spawn_player() -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.bullet_parent = _world
	if "controls_enabled" in _player:
		_player.controls_enabled = true   # turret runs in _process only when this is true
	if "invincible" in _player:
		_player.invincible = true          # targets shouldn't kill the test ship
	_player.position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 30.0)


func _rebuild_targets(n: int) -> void:
	for t in _targets:
		if is_instance_valid(t):
			t.queue_free()
	_targets.clear()
	for i in n:
		var t := Area2D.new()
		t.set_script(TargetScript)
		_world.add_child(t)
		_targets.append(t)


# ---- Overlay (floats over playspace) ------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var title := _mk_label("SMART MOUNT LAB", FS_HEADER, UiTheme.COLOR_ACCENT)
	title.position = Vector2(28, 18)
	layer.add_child(title)
	var hint := _mk_label("WASD to fly · turrets auto-fire · Esc to exit", FS_CAPTION, UiTheme.COLOR_FAINT)
	hint.position = Vector2(28, 54)
	layer.add_child(hint)

	var panel := PanelContainer.new()
	panel.position = Vector2(1488, 18)
	panel.custom_minimum_size = Vector2(412, 1044)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	sb.border_color = Color(0.35, 0.55, 0.75, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(372, 0)
	scroll.add_child(v)

	v.add_child(_mk_label("MOUNTS", FS_HEADER, UiTheme.COLOR_ACCENT))
	_blaster_cb = _check(v, "Blaster Smart Mount", true)
	_primary_cb = _check(v, "Primary Smart Mount", true)
	_primary_dd = _drop(v, "Primary weapon", _primary_factories.map(func(e): return e["name"]))
	_primary_dd.item_selected.connect(func(_i): _on_primary_changed())

	v.add_child(_mk_label("TURRET FEEL", FS_HEADER, UiTheme.COLOR_ACCENT))
	_btrav = _spin(v, "Blaster traverse (deg/s)", 30, 720, 5, 143)
	_bdisp = _spin(v, "Blaster dispersion (deg)", 0, 30, 0.5, 10)
	_ptrav = _spin(v, "Primary traverse (deg/s)", 30, 720, 5, 143)
	_pdisp = _spin(v, "Primary dispersion (deg)", 0, 30, 0.5, 10)
	_arc = _spin(v, "Arc half-angle (deg)", 10, 90, 1, 60)
	_range = _spin(v, "Acquisition range (px)", 60, 480, 5, 240)
	_tol = _spin(v, "Fire tolerance (deg)", 1, 30, 0.5, 8)

	v.add_child(_mk_label("ARENA", FS_HEADER, UiTheme.COLOR_ACCENT))
	_count = _spin(v, "Targets", 1, 10, 1, 4)
	_count.value_changed.connect(func(_x): _rebuild_targets(int(_count.value)))
	_tspeed = _spin(v, "Target speed ×", 0.2, 4.0, 0.1, 1.0)
	_automove_cb = _check(v, "Auto-move ship", false)
	_amspeed = _spin(v, "Auto-move speed ×", 0.2, 3.0, 0.1, 1.0)

	v.add_child(HSeparator.new())
	_status = _mk_label("Ready.", FS_CAPTION, UiTheme.COLOR_FAINT)
	v.add_child(_status)
	var copy_btn := _btn(v, "Copy GDScript")
	copy_btn.pressed.connect(_on_copy)
	var save_btn := _btn(v, "Save")
	save_btn.pressed.connect(func(): _save(); _set_status("Saved."))
	var back_btn := _btn(v, "Back (Esc)")
	back_btn.pressed.connect(_on_back)


# ---- Knob → player ------------------------------------------------------

func _apply_knobs() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.module_blaster_mount = _blaster_cb.button_pressed
	_player.module_blaster_traverse = deg_to_rad(_btrav.value)
	_player.module_blaster_dispersion = deg_to_rad(_bdisp.value)
	_player.module_primary_mount = _primary_cb.button_pressed
	_player.module_primary_traverse = deg_to_rad(_ptrav.value)
	_player.module_primary_dispersion = deg_to_rad(_pdisp.value)
	_player.mount_arc = deg_to_rad(_arc.value)
	_player.mount_range = float(_range.value)
	_player.mount_fire_tolerance = deg_to_rad(_tol.value)
	_player._setup_smart_mounts()
	for t in _targets:
		if is_instance_valid(t):
			t.speed_scale = float(_tspeed.value)
	if int(_count.value) != _targets.size():
		_rebuild_targets(int(_count.value))


func _on_primary_changed() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	run.new_run()
	run.test_mode_active = true
	_equip_primary(run, _primary_factories[_primary_dd.selected]["factory"])
	_spawn_player()
	await get_tree().process_frame
	_apply_knobs()
	_set_status("Primary: %s" % _primary_factories[_primary_dd.selected]["name"])


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# Push live tunables every frame (cheap) so the arc/range/dispersion respond
	# instantly while the panel is open. Skip the _setup re-call here (only on
	# discrete changes) to avoid resetting the turret aim each frame.
	for t in _targets:
		if is_instance_valid(t):
			t.speed_scale = float(_tspeed.value)
	_player.module_blaster_traverse = deg_to_rad(_btrav.value)
	_player.module_blaster_dispersion = deg_to_rad(_bdisp.value)
	_player.module_primary_traverse = deg_to_rad(_ptrav.value)
	_player.module_primary_dispersion = deg_to_rad(_pdisp.value)
	_player.mount_arc = deg_to_rad(_arc.value)
	_player.mount_range = float(_range.value)
	_player.mount_fire_tolerance = deg_to_rad(_tol.value)
	_player.module_blaster_mount = _blaster_cb.button_pressed
	_player.module_primary_mount = _primary_cb.button_pressed
	# Auto-move: sweep the ship across the band (ship doesn't self-move without input).
	if _automove_cb.button_pressed:
		_automove_phase += delta * float(_amspeed.value)
		var x: float = Playfield.CENTER.x + sin(_automove_phase) * (Playfield.W * 0.5 - 16.0)
		var y: float = (Playfield.Y_MAX - 30.0) + sin(_automove_phase * 0.6) * 30.0
		_player.position = Vector2(x, y)


# ---- Copy GDScript ------------------------------------------------------

func _on_copy() -> void:
	var bt: float = deg_to_rad(_btrav.value)
	var bd: float = deg_to_rad(_bdisp.value)
	var pt: float = deg_to_rad(_ptrav.value)
	var pd: float = deg_to_rad(_pdisp.value)
	var s := "# Smart Mount Lab tuning (2026-06-14)\n"
	s += "# scripts/parts/smart_mount.gd — these are ABSOLUTE values; pick a Mk-curve from them:\n"
	s += "base_traverse = %.3f      # %.0f deg/s (blaster: %.0f, primary: %.0f)\n" % [pt, _ptrav.value, _btrav.value, _ptrav.value]
	s += "base_dispersion = %.4f    # %.1f deg (blaster: %.1f, primary: %.1f)\n" % [pd, _pdisp.value, _bdisp.value, _pdisp.value]
	s += "# scripts/player.gd — MOUNT geometry defaults:\n"
	s += "mount_arc = %.4f          # half-angle %.0f deg (= %.0f deg total arc)\n" % [deg_to_rad(_arc.value), _arc.value, _arc.value * 2.0]
	s += "mount_range = %.1f\n" % float(_range.value)
	s += "mount_fire_tolerance = %.4f  # %.1f deg\n" % [deg_to_rad(_tol.value), _tol.value]
	DisplayServer.clipboard_set(s)
	_set_status("Copied GDScript to clipboard.")


# ---- Persistence --------------------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"blaster": _blaster_cb.button_pressed, "primary": _primary_cb.button_pressed,
		"btrav": _btrav.value, "bdisp": _bdisp.value, "ptrav": _ptrav.value, "pdisp": _pdisp.value,
		"arc": _arc.value, "range": _range.value, "tol": _tol.value,
		"count": _count.value, "tspeed": _tspeed.value,
		"automove": _automove_cb.button_pressed, "amspeed": _amspeed.value,
		"primary_idx": _primary_dd.selected,
	}, "\t"))
	f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_rebuild_targets(int(_count.value))
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_blaster_cb.button_pressed = bool(d.get("blaster", true))
		_primary_cb.button_pressed = bool(d.get("primary", true))
		_btrav.value = float(d.get("btrav", 143))
		_bdisp.value = float(d.get("bdisp", 10))
		_ptrav.value = float(d.get("ptrav", 143))
		_pdisp.value = float(d.get("pdisp", 10))
		_arc.value = float(d.get("arc", 60))
		_range.value = float(d.get("range", 240))
		_tol.value = float(d.get("tol", 8))
		_count.value = float(d.get("count", 4))
		_tspeed.value = float(d.get("tspeed", 1.0))
		_automove_cb.button_pressed = bool(d.get("automove", false))
		_amspeed.value = float(d.get("amspeed", 1.0))
	_rebuild_targets(int(_count.value))


# ---- UI factories -------------------------------------------------------

func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _check(parent: VBoxContainer, text: String, on: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = on
	cb.add_theme_font_override("font", UiTheme.menu_font())
	cb.add_theme_font_size_override("font_size", FS_CAPTION + 2)
	parent.add_child(cb)
	return cb

func _drop(parent: VBoxContainer, caption: String, items) -> OptionButton:
	parent.add_child(_mk_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.menu_font())
	dd.add_theme_font_size_override("font_size", FS_CAPTION + 2)
	for it in items:
		dd.add_item(String(it))
	parent.add_child(dd)
	return dd

func _spin(parent: VBoxContainer, caption: String, lo: float, hi: float, step: float, val: float) -> SpinBox:
	parent.add_child(_mk_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var sb := SpinBox.new()
	sb.add_theme_font_override("font", UiTheme.menu_font())
	sb.add_theme_font_size_override("font_size", FS_CAPTION + 2)
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = val
	parent.add_child(sb)
	return sb

func _btn(parent: VBoxContainer, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	UiTheme.style_button(b, true)
	parent.add_child(b)
	return b


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg


# ---- Nav ----------------------------------------------------------------

func _on_back() -> void:
	_save()
	var scope := _hd_scope
	_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn", func(): HdScreen.drop(scope))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
