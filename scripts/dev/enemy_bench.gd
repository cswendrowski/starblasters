extends Control

# Enemy Bench (Roman 2026-06-09) — replaces the Shipyard. A variant of the Hangar test bench
# (scripts/hangar.gd) flipped to ENEMIES: spawn a selected enemy in the native 480×270
# SubViewport, watch it cycle through its ELIGIBLE movement patterns (the pattern_eligibility
# matrix), and let it fire at a DUMMY PLAYER you drive with WASD/arrows. The right panel
# sets + SAVES per-enemy weapon settings: firing pattern, aim rule, payload, and death
# explosion. Persists to user://tuners/enemy_bench.json + a Copy-GDScript snippet (tuner
# contract). Esc / Back returns to the dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const EnemyStrings = preload("res://scripts/enemy_strings.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const HangarDummy = preload("res://scripts/dev/hangar_dummy_target.gd")
const Playfield = preload("res://scripts/playfield.gd")
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const PLAYER_SPRITE = preload("res://Mini Pixel Pack 3/Player ship/Player_ship (16 x 16).png")

const SAVE_PATH := "user://tuners/enemy_bench.json"

# Editor option pools.
const FIRE_PATTERNS := ["SINGLE", "AIMED", "SPREAD", "BURST", "BEAM", "LOB", "BROADSIDE"]
const AIMS := ["STRAIGHT_DOWN", "TOWARD_CENTER", "AT_PLAYER", "FORWARD"]
const PAYLOADS := {
	"Basic": EnemyRoster.BV_Basic, "Spread Pellet": EnemyRoster.BV_SpreadPellet,
	"Aimed Sniper": EnemyRoster.BV_AimedSniper, "Burst Round": EnemyRoster.BV_BurstRound,
	"Plasma Orb": EnemyRoster.BV_PlasmaOrb, "Heavy Slug": EnemyRoster.BV_HeavySlug,
	"Drop Pellet": EnemyRoster.BV_DropPellet,
}

const FS_TITLE := 40
const FS_HEADER := 24
const FS_BODY := 18
const FS_CAPTION := 15
const RAIL_W := 300
const INFO_W := 430
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)
const DUMMY_SPEED := 150.0
const RESPAWN_DELAY := 1.2

var _hd_scope: HdViewportScope = null

# Playspace.
var _preview_vp: SubViewport = null
var _enemy_layer: Node2D = null
var _dummy: Area2D = null
var _current_enemy: Node = null
var _respawn_timer: Timer = null

# Enemy list.
var _list: ItemList = null
var _paths: Array = []
var _selected_path: String = ""

# Pattern cycling.
var _eligible: Array = []      # eligible movement keys for the selected enemy
var _pattern_idx: int = 0
var _pattern_lbl: Label = null

# Editors.
var _name_lbl: Label = null
var _stats_lbl: Label = null
var _fire_dd: OptionButton = null
var _aim_dd: OptionButton = null
var _payload_dd: OptionButton = null
var _explosion_dd: OptionButton = null
var _recycle_chk: CheckButton = null
var _recycle_passes_spin: SpinBox = null
var _recycle_chance_spin: SpinBox = null

# Persisted per-scene settings.
var _saved: Dictionary = {}


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_saved()
	_build_playspace()
	_build_overlay()
	_load_list()
	if _list.item_count > 0:
		_list.select(0)
		_on_list_select(0)
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_preview_vp, "Enemy Bench")   # guard: catch the corner regression


# ---- Playspace -----------------------------------------------------------

func _build_playspace() -> void:
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	# CRITICAL (the recurring "play area in the corner" regression, Roman 2026-06-11): stretch=true
	# overwrites the child SubViewport.size to container_size / stretch_shrink each layout pass. Under
	# HdViewportScope the full-rect container is 1920x1080, so the DEFAULT stretch_shrink=1 forces the
	# viewport to 1920x1080 and the 480-native content renders in a corner. stretch_shrink=4 keeps it
	# native 480x270, upscaled 4x. Reference: parallax_tuner.gd + docs/godot-patterns.md.
	sub_container.stretch_shrink = 4
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)   # initial; stretch_shrink=4 keeps it here each layout pass
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	sub_container.add_child(_preview_vp)

	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	_preview_vp.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	_preview_vp.add_child(band)

	# Controllable dummy PLAYER — moved by input in _process (see _drive_dummy).
	_dummy = Area2D.new()
	_dummy.set_script(HangarDummy)
	_dummy.name = "DummyPlayer"
	_dummy.add_to_group("player")
	_dummy.position = Vector2(Playfield.CENTER.x, 230)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = PLAYER_SPRITE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dummy.add_child(sprite)
	var hit := CollisionShape2D.new()
	var cs := RectangleShape2D.new()
	cs.size = Vector2(12, 12)
	hit.shape = cs
	_dummy.add_child(hit)
	_preview_vp.add_child(_dummy)

	_enemy_layer = Node2D.new()
	_enemy_layer.name = "EnemyLayer"
	_preview_vp.add_child(_enemy_layer)

	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	_respawn_timer.wait_time = RESPAWN_DELAY
	_respawn_timer.timeout.connect(_cycle_and_spawn)
	add_child(_respawn_timer)


# ---- Overlay UI ----------------------------------------------------------

func _build_overlay() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)

	var header := _label("ENEMY BENCH", FS_TITLE, UiTheme.COLOR_ACCENT)
	header.position = Vector2(MARGIN, 12)
	header.add_theme_constant_override("outline_size", 6)
	ui.add_child(header)

	var hint := _label("WASD / arrows: drive the dummy player", FS_CAPTION, UiTheme.COLOR_FAINT)
	hint.position = Vector2(MARGIN, 60)
	ui.add_child(hint)

	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(1920 - MARGIN - 120, 16)
	back.size = Vector2(120, 40)
	UiTheme.style_button(back, true)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.pressed.connect(_on_back)
	ui.add_child(back)

	_build_left_rail(ui)
	_build_right_panel(ui)


func _build_left_rail(ui: CanvasLayer) -> void:
	var x := MARGIN
	var y := HEADER_H + MARGIN + 24
	var h := int((1080 - y - MARGIN) * 0.82)
	ui.add_child(_panel(Vector2(x, y), Vector2(RAIL_W, h)))

	var lbl := _label("Enemy", FS_CAPTION, UiTheme.COLOR_FAINT)
	lbl.position = Vector2(x + 14, y + 10)
	ui.add_child(lbl)

	_list = ItemList.new()
	_list.position = Vector2(x + 14, y + 36)
	_list.size = Vector2(RAIL_W - 28, h - 50)
	_list.add_theme_font_override("font", UiTheme.active_font())
	_list.add_theme_font_size_override("font_size", FS_BODY)
	_list.fixed_icon_size = Vector2i(28, 28)
	_list.item_selected.connect(_on_list_select)
	ui.add_child(_list)


func _build_right_panel(ui: CanvasLayer) -> void:
	var x := 1920 - MARGIN - INFO_W
	var y := HEADER_H + MARGIN + 24
	var h := int((1080 - y - MARGIN) * 0.82)
	ui.add_child(_panel(Vector2(x, y), Vector2(INFO_W, h)))

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(x + 16, y + 14)
	vbox.size = Vector2(INFO_W - 32, h - 28)
	vbox.add_theme_constant_override("separation", 8)
	ui.add_child(vbox)

	_name_lbl = _label("—", FS_HEADER, UiTheme.COLOR_ACCENT)
	vbox.add_child(_name_lbl)
	_stats_lbl = _label("", FS_CAPTION, UiTheme.COLOR_TEXT)
	vbox.add_child(_stats_lbl)
	_pattern_lbl = _label("Pattern: —", FS_BODY, UiTheme.COLOR_BOUNTY)
	vbox.add_child(_pattern_lbl)

	var next_btn := Button.new()
	next_btn.text = "Next Pattern"
	UiTheme.style_button(next_btn, true)
	next_btn.add_theme_font_size_override("font_size", FS_BODY)
	next_btn.custom_minimum_size = Vector2(0, 36)
	next_btn.pressed.connect(_cycle_and_spawn)
	vbox.add_child(next_btn)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Weapon", FS_BODY, UiTheme.COLOR_ACCENT))

	# Weapon changes respawn (re-runs start() so BEAM/aim init correctly).
	_fire_dd = _dropdown(vbox, "Firing pattern", FIRE_PATTERNS)
	_fire_dd.item_selected.connect(func(_i): _spawn_current())
	_aim_dd = _dropdown(vbox, "Aim rule", AIMS)
	_aim_dd.item_selected.connect(func(_i): _spawn_current())
	_payload_dd = _dropdown(vbox, "Payload", PAYLOADS.keys())
	_payload_dd.item_selected.connect(func(_i): _spawn_current())

	vbox.add_child(HSeparator.new())
	# Death explosion only matters on death, so apply it live (no respawn).
	_explosion_dd = _dropdown(vbox, "Death explosion", ExplosionFx.variant_names())
	_explosion_dd.item_selected.connect(func(_i): _apply_explosion_live())

	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Recycle Behavior", FS_BODY, UiTheme.COLOR_ACCENT))

	# Can recycle checkbox
	vbox.add_child(_label("Can recycle", FS_CAPTION, UiTheme.COLOR_FAINT))
	_recycle_chk = CheckButton.new()
	_recycle_chk.button_pressed = true
	_recycle_chk.add_theme_font_override("font", UiTheme.active_font())
	_recycle_chk.add_theme_font_size_override("font_size", FS_BODY)
	_recycle_chk.toggled.connect(func(_v): _apply_recycle_live())
	vbox.add_child(_recycle_chk)

	# Recycle passes spinbox
	_recycle_passes_spin = _spinbox(vbox, "Recycle passes", 1, 10, 1)
	_recycle_passes_spin.value_changed.connect(func(_v): _apply_recycle_live())

	# Chance to recycle vs flee slider
	_recycle_chance_spin = _spinbox(vbox, "Recycle chance (0=flee, 1=recycle)", 0, 1, 0.1)
	_recycle_chance_spin.value_changed.connect(func(_v): _apply_recycle_live())

	vbox.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vbox.add_child(row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	UiTheme.style_button(save_btn, true)
	save_btn.add_theme_font_size_override("font_size", FS_BODY)
	save_btn.custom_minimum_size = Vector2(120, 36)
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy GDScript"
	UiTheme.style_button(copy_btn, false)
	copy_btn.add_theme_font_size_override("font_size", FS_BODY)
	copy_btn.custom_minimum_size = Vector2(180, 36)
	copy_btn.pressed.connect(_on_copy)
	row.add_child(copy_btn)


func _dropdown(vbox: VBoxContainer, caption: String, items) -> OptionButton:
	vbox.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for it in items:
		dd.add_item(String(it))
	vbox.add_child(dd)
	return dd


func _spinbox(vbox: VBoxContainer, caption: String, min_v: float, max_v: float, step: float) -> SpinBox:
	vbox.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var sb := SpinBox.new()
	sb.add_theme_font_override("font", UiTheme.active_font())
	sb.add_theme_font_size_override("font_size", FS_BODY)
	sb.custom_minimum_size = Vector2(0, 34)
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = min_v
	vbox.add_child(sb)
	return sb


# ---- List / selection ----------------------------------------------------

func _load_list() -> void:
	_paths.clear()
	for p in EnemyManifest.paths():
		_paths.append(String(p))
	_paths.sort()
	for p in _paths:
		_list.add_item(EnemyStrings.display_name(p), _icon_for(p))


func _icon_for(path: String) -> Texture2D:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var state := ps.get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != &"Sprite2D":
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"texture":
				var tex := state.get_node_property_value(i, j) as Texture2D
				if tex != null:
					return tex
	return null


func _on_list_select(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	_selected_path = _paths[idx]
	# Eligible patterns from the matrix (identity-only if unmapped/bespoke).
	_eligible = PatternEligibility.eligible_for(_selected_path)
	if _eligible.is_empty():
		var idk := PatternEligibility.identity_for(_selected_path)
		_eligible = [idk] if idk != "" else ["straight_medium"]
	_pattern_idx = 0
	_load_settings_into_editors()
	_spawn_current()


# ---- Spawn + pattern cycling ---------------------------------------------

func _cycle_and_spawn() -> void:
	if not _eligible.is_empty():
		_pattern_idx = (_pattern_idx + 1) % _eligible.size()
	_spawn_current()


func _spawn_current() -> void:
	_respawn_timer.stop()
	_clear_enemy()
	if _selected_path == "":
		return
	var ps := load(_selected_path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	var spawn_pos := Vector2(Playfield.CENTER.x, -20)
	# Configure BEFORE add_child + start() so enemy_core._start_with_pattern
	# duplicates the chosen movement and the weapon/explosion are live from frame 0.
	var key := ""
	if not _eligible.is_empty() and "movement" in inst:
		key = String(_eligible[_pattern_idx])
		inst.movement = EnemyRoster.make_movement({"movement": key})
	if "shoot_pattern" in inst:
		inst.shoot_pattern = _build_weapon()
		if "fire_on_phase" in inst:
			inst.fire_on_phase = ""    # use the generic ShootTimer cadence
	if "explosion_variant" in inst:
		inst.explosion_variant = ExplosionFx.variant_names()[_explosion_dd.selected]
	if inst is Node2D:
		(inst as Node2D).position = spawn_pos
	_enemy_layer.add_child(inst)
	_current_enemy = inst
	# start() is what inits the movement pattern (anchor + on_start) — the director's
	# contract. enemy_core._ready does NOT auto-start.
	if inst.has_method("start"):
		inst.start(spawn_pos)
	if _pattern_lbl:
		var n: int = max(1, _eligible.size())
		_pattern_lbl.text = "Pattern: %s  (%d/%d)" % [(key if key != "" else "—"), _pattern_idx + 1, n]
	_refresh_info()


func _build_weapon() -> Weapon:
	var w := Weapon.new()
	w.fire_pattern = _fire_dd.selected
	w.aim = _aim_dd.selected
	var pkeys: Array = PAYLOADS.keys()
	var pname: String = String(pkeys[clampi(_payload_dd.selected, 0, pkeys.size() - 1)])
	w.payload = PAYLOADS[pname]
	return w


func _apply_explosion_live() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy) and "explosion_variant" in _current_enemy:
		_current_enemy.explosion_variant = ExplosionFx.variant_names()[_explosion_dd.selected]


func _apply_recycle_live() -> void:
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if not "recycle_passes" in _current_enemy:
		return
	if not _recycle_chk.button_pressed:
		# Can't recycle = flee behavior
		_current_enemy.recycle_passes = 0
	else:
		# Can recycle: use the spinbox value, unless chance says flee
		var chance: float = float(_recycle_chance_spin.value)
		if randf() < chance:
			_current_enemy.recycle_passes = int(_recycle_passes_spin.value)
		else:
			_current_enemy.recycle_passes = 0  # flee


func _clear_enemy() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy):
		_current_enemy.queue_free()
	_current_enemy = null


# ---- Per-frame: drive dummy + respawn check ------------------------------

func _process(delta: float) -> void:
	_drive_dummy(delta)
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if not (_current_enemy is Node2D):
		return
	var p: Vector2 = (_current_enemy as Node2D).position
	if p.y > 320 or p.x < -40 or p.x > 520:
		_clear_enemy()
		if _respawn_timer.is_stopped():
			_respawn_timer.start()


func _drive_dummy(delta: float) -> void:
	if _dummy == null or not is_instance_valid(_dummy):
		return
	var v := Vector2.ZERO
	if Input.is_action_pressed("left"): v.x -= 1.0
	if Input.is_action_pressed("right"): v.x += 1.0
	if Input.is_action_pressed("up"): v.y -= 1.0
	if Input.is_action_pressed("down"): v.y += 1.0
	if v != Vector2.ZERO:
		var np: Vector2 = _dummy.position + v.normalized() * DUMMY_SPEED * delta
		np.x = clampf(np.x, Playfield.X_MIN + 8.0, Playfield.X_MAX - 8.0)
		np.y = clampf(np.y, 20.0, 262.0)
		_dummy.position = np


# ---- Info + settings persistence -----------------------------------------

func _refresh_info() -> void:
	_name_lbl.text = EnemyStrings.display_name(_selected_path)
	var hp: int = int(_current_enemy.max_health) if (_current_enemy and "max_health" in _current_enemy) else 0
	var bounty: int = int(_current_enemy.bounty_value) if (_current_enemy and "bounty_value" in _current_enemy) else 0
	_stats_lbl.text = "HP %d   Bounty %d   Eligible: %s" % [hp, bounty, ", ".join(_eligible)]


func _load_settings_into_editors() -> void:
	var s: Dictionary = _saved.get(_selected_path, {})
	_select_text(_fire_dd, String(s.get("fire_pattern", "SINGLE")), FIRE_PATTERNS)
	_select_text(_aim_dd, String(s.get("aim", "STRAIGHT_DOWN")), AIMS)
	_select_text(_payload_dd, String(s.get("payload", "Basic")), PAYLOADS.keys())
	_select_text(_explosion_dd, String(s.get("explosion", "default")), ExplosionFx.variant_names())
	if _recycle_chk:
		_recycle_chk.button_pressed = bool(s.get("can_recycle", true))
	if _recycle_passes_spin:
		_recycle_passes_spin.value = int(s.get("recycle_passes", 1))
	if _recycle_chance_spin:
		_recycle_chance_spin.value = float(s.get("recycle_chance", 1.0))


func _select_text(dd: OptionButton, text: String, pool) -> void:
	var i: int = Array(pool).find(text)
	dd.select(i if i >= 0 else 0)


func _current_settings() -> Dictionary:
	return {
		"fire_pattern": FIRE_PATTERNS[_fire_dd.selected],
		"aim": AIMS[_aim_dd.selected],
		"payload": String(PAYLOADS.keys()[_payload_dd.selected]),
		"explosion": ExplosionFx.variant_names()[_explosion_dd.selected],
		"can_recycle": _recycle_chk.button_pressed,
		"recycle_passes": int(_recycle_passes_spin.value),
		"recycle_chance": float(_recycle_chance_spin.value),
	}


func _on_save() -> void:
	if _selected_path == "":
		return
	_saved[_selected_path] = _current_settings()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_saved, "\t"))
		f.close()
	if _pattern_lbl:
		_pattern_lbl.text = "Saved %s" % EnemyStrings.display_name(_selected_path)


func _load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_saved = data


func _on_copy() -> void:
	var s := _current_settings()
	var payload_const: String = "BV_" + String(s["payload"]).replace(" ", "")
	var txt := "# Enemy Bench — %s\n" % EnemyStrings.display_name(_selected_path)
	txt += "var w := Weapon.new()\n"
	txt += "w.fire_pattern = Weapon.FirePattern.%s\n" % s["fire_pattern"]
	txt += "w.aim = Weapon.Aim.%s\n" % s["aim"]
	txt += "w.payload = %s\n" % payload_const
	txt += "enemy.shoot_pattern = w\n"
	txt += "enemy.explosion_variant = \"%s\"\n" % s["explosion"]
	txt += "# Recycle behavior:\n"
	if s["can_recycle"]:
		txt += "enemy.recycle_passes = %d  # %.1f chance to recycle\n" % [s["recycle_passes"], s["recycle_chance"]]
	else:
		txt += "enemy.recycle_passes = 0  # flee (no recycle)\n"
	DisplayServer.clipboard_set(txt)
	if _pattern_lbl:
		_pattern_lbl.text = "Copied GDScript to clipboard"


# ---- Helpers + back ------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_top = 10
	sb.content_margin_right = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.size = sz
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _on_back() -> void:
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
