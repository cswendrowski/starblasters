extends Control

# BattleshipLab (Roman 2026-07-02) — live-tune + trigger the Zealot Battleship's maneuvers. Spawns the
# REAL boss + a real backdrop + a "bullet_world" sink + an invulnerable, arrow-key-flyable dummy player
# in a native-480 SubViewport, so the ponderous maneuver feel can be judged in context. Trigger any
# single maneuver / hazard on demand, or "Run gated combat" for the full director-driven wave→maneuver
# flow. Knob sliders live-apply to the boss's @export movement/timing vars; Copy GDScript emits the
# paste-ready block. House tuner contract (scripts/dev/ui_designer.gd): JSON save/load, Reset,
# Esc-to-close, mandatory Copy GDScript.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const DirectorScript = preload("res://scripts/levels/director.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const BOSS_SCENE := "res://scenes/enemies/factions/zealot/boss_z_battleship.tscn"
const CONFIG_PATH := "user://tuners/battleship.json"

# key (= the boss @export var), label, min, max, step
const KNOBS := [
	["HIGH_HOLD_Y", "High hold Y (px)", 20.0, 150.0, 2.0],
	["HOOK_RISE_SPEED", "Hook rise speed", 20.0, 220.0, 5.0],
	["HOOK_DIVE_SPEED", "Hook dive speed", 20.0, 260.0, 5.0],
	["SLIDE_ENTER_SPEED", "Slide enter speed", 20.0, 220.0, 5.0],
	["SLIDE_CROSS_SPEED", "Slide cross speed", 20.0, 220.0, 5.0],
	["SLIDE_EXIT_SPEED", "Slide exit speed", 20.0, 260.0, 5.0],
	["FLEE_SPEED", "Flee speed", 60.0, 400.0, 10.0],
	["ROTATE_SLIDE_DUR", "Rotate-slide dur (s)", 0.5, 4.0, 0.1],
	["ROTATE_TO_DOWN_DUR", "Pivot-down dur (s)", 0.3, 3.0, 0.1],
	["BEAM_HOLD", "Beam hold (s)", 0.5, 8.0, 0.25],
	["BLOCKADE_HOLD", "Blockade hold (s)", 0.5, 8.0, 0.25],
	["HAZARD_MIN_GAP", "Hazard gap MIN (s)", 2.0, 20.0, 0.5],
	["HAZARD_MAX_GAP", "Hazard gap MAX (s)", 2.0, 30.0, 0.5],
	["HAZARD_SWEEP_SPEED", "Hazard sweep speed", 10.0, 120.0, 5.0],
]

# Trigger buttons: label, maneuver-name (boss.MANEUVER_NAMES)
const TRIGGERS := [
	["Hook: Firecores", "hook_firecores"],
	["Hook: Laser", "hook_laser"],
	["Hook: Blockade", "hook_blockade"],
	["Slide: Firecores", "firecore_slide"],
	["Slide: Laser", "laser_slide"],
	["Hazard: Lane Laser", "hazard_lane_laser"],
	["Hazard: Sweep", "hazard_sweep"],
]

var _values: Dictionary = {}
var _spins: Dictionary = {}
var _status_label: Label = null
var _world: SubViewport = null
var _boss = null
var _player = null
var _director = null
var _hd_scope: HdViewportScope = null


class DummyPlayer extends Area2D:
	# Invulnerable, arrow-key-flyable target so turrets aim + beams have someone to (harmlessly) hit.
	var hull: int = 999999
	const SPEED := 150.0
	func _ready() -> void:
		add_to_group("player")
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(10, 10)
		cs.shape = shape
		add_child(cs)
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(0, -7), Vector2(6, 7), Vector2(-6, 7)])
		poly.color = Color(0.4, 0.9, 1.0)
		poly.z_index = 10
		add_child(poly)
	func take_damage(_d: int = 0) -> void: pass   # never dies (lab target)
	func take_hit(_d: int = 1) -> bool: return false
	func _process(dt: float) -> void:
		var v := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		position = Playfield.clamp_pos(position + v * SPEED * dt)


func _ready() -> void:
	_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_preview()
	_seed_values()
	_load_from_disk()   # override seed with any saved tuning
	_apply_all_to_boss()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


# --- UI -------------------------------------------------------------------

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(390, 0)
	rail.add_theme_constant_override("separation", 5)
	root.add_child(rail)

	var title := Label.new()
	title.text = "BATTLESHIP LAB"
	title.add_theme_font_size_override("font_size", 22)
	rail.add_child(title)
	var hint := Label.new()
	hint.text = "Arrow keys fly the (invulnerable) player."
	hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	rail.add_child(hint)

	rail.add_child(_section("Trigger maneuver"))
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.add_theme_constant_override("h_separation", 6)
	tgrid.add_theme_constant_override("v_separation", 4)
	rail.add_child(tgrid)
	for t in TRIGGERS:
		var nm: String = String(t[1])
		_add_button(tgrid, String(t[0]), func(): _trigger(nm))
	var trow := HBoxContainer.new()
	rail.add_child(trow)
	_add_button(trow, "Random", func(): _trigger(""))
	_add_button(trow, "Respawn boss", _respawn_boss)
	_add_button(trow, "Destroy parts", _destroy_parts)

	rail.add_child(_section("Full combat (director-gated waves)"))
	var crow := HBoxContainer.new()
	rail.add_child(crow)
	_add_button(crow, "Run gated combat", _run_combat)
	_add_button(crow, "Stop", _stop_combat)

	rail.add_child(_section("Movement / timing"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	rail.add_child(scroll)
	var kbox := VBoxContainer.new()
	kbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(kbox)
	for spec in KNOBS:
		kbox.add_child(_make_knob_row(spec))

	var brow := HBoxContainer.new()
	rail.add_child(brow)
	_add_button(brow, "Save", _on_save)
	_add_button(brow, "Load", _on_load)
	_add_button(brow, "Reset", _on_reset)
	var brow2 := HBoxContainer.new()
	rail.add_child(brow2)
	_add_button(brow2, "Copy GDScript", _on_copy)
	_add_button(brow2, "Back (Esc)", _on_back)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_status_label.text = "Editing battleship.json"
	rail.add_child(_status_label)

	# Preview: native-480 SubViewport, crisp 3× upscale.
	var svc := SubViewportContainer.new()
	svc.position = Vector2(420, 40)
	svc.stretch = true
	svc.stretch_shrink = 3
	svc.custom_minimum_size = Vector2(1440, 810)
	svc.size = Vector2(1440, 810)
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = SubViewport.new()
	_world.size = Vector2i(480, 270)
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_world)
	add_child(svc)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	l.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0))
	return l


func _make_knob_row(spec: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = String(spec[1])
	lbl.custom_minimum_size = Vector2(170, 0)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = float(spec[2])
	spin.max_value = float(spec[3])
	spin.step = float(spec[4])
	spin.custom_minimum_size = Vector2(110, 0)
	var key: String = String(spec[0])
	spin.value_changed.connect(func(v): _on_knob(key, v))
	row.add_child(spin)
	_spins[key] = spin
	return row


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_knob(key: String, v: float) -> void:
	_values[key] = v
	if _boss != null and is_instance_valid(_boss):
		_boss.set(key, v)


func _apply_all_to_boss() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	for key in _values.keys():
		_boss.set(key, _values[key])


# Seed the knob values from the live boss's export defaults.
func _seed_values() -> void:
	for spec in KNOBS:
		var key: String = String(spec[0])
		var dv: float = float(_boss.get(key)) if (_boss != null and key in _boss) else float(spec[2])
		_values[key] = dv
		if _spins.has(key):
			(_spins[key] as SpinBox).set_value_no_signal(dv)


# --- Preview --------------------------------------------------------------

func _build_preview() -> void:
	if _world == null:
		return
	var bw := Node2D.new()          # projectile / firecore sink INSIDE the SubViewport (BulletWorld group)
	bw.add_to_group("bullet_world")
	_world.add_child(bw)
	_spawn_backdrop()
	_spawn_boss()
	_player = DummyPlayer.new()
	_player.position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 30.0)
	_world.add_child(_player)


func _spawn_backdrop() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null and "current_stellar" in run:
		run.current_stellar = {
			"planet_idx": 2, "planet_seed": 71, "star_color": Color(0.9, 0.8, 1.0),
			"has_asteroids": false, "asteroid_density": 0.0,
			"nebula_band": "", "nebula_tint": Color.WHITE, "moons": [], "system": [],
		}
	var bd = BackdropCoordinatorScene.instantiate()
	_world.add_child(bd)


func _spawn_boss() -> void:
	var scn := load(BOSS_SCENE) as PackedScene
	if scn == null:
		return
	_boss = scn.instantiate()
	_world.add_child(_boss)
	if _boss.has_method("start"):
		_boss.start(Vector2(Playfield.CENTER.x, 330.0))   # off-screen below (idle)
	_apply_all_to_boss()


func _respawn_boss() -> void:
	_stop_combat()
	if _boss != null and is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	await get_tree().process_frame
	_spawn_boss()
	_set_status("Boss respawned")


func _destroy_parts() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	for p in _boss.live_parts().duplicate():
		if is_instance_valid(p) and p.has_method("destroy"):
			p.destroy()
	_set_status("Destroyed all parts → death sequence")


func _trigger(nm: String) -> void:
	if _boss == null or not is_instance_valid(_boss):
		_set_status("No boss — respawn first")
		return
	if nm == "":
		_boss.play_wave_maneuver(0)
		_set_status("Random maneuver")
	else:
		_boss.play_named_maneuver(nm)
		_set_status("Playing: %s" % nm)


# --- Full gated combat ----------------------------------------------------

func _run_combat() -> void:
	_stop_combat()
	if _boss == null or not is_instance_valid(_boss):
		_spawn_boss()
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.forced_boss_scene = BOSS_SCENE
	var score = WaveGen.build_score(1, 0, true)
	_director = DirectorScript.new()
	_director.max_concurrent = 16
	_director.start_grace = 0.4
	_world.add_child(_director)   # enemies spawn as its children → into the SubViewport
	_director.boss_gate = _boss
	_director.start_score(score)
	_set_status("Gated combat running (drain → maneuver → next wave)")


func _stop_combat() -> void:
	if _director != null and is_instance_valid(_director):
		_director.queue_free()
	_director = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e == _boss or (_boss != null and is_instance_valid(_boss) and _boss.is_ancestor_of(e)):
			continue   # leave the boss + its parts
		e.queue_free()
	_set_status("Combat stopped")


# --- Persistence + snippet ------------------------------------------------

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		_set_status("Save FAILED")
		return
	f.store_string(JSON.stringify(_values, "\t"))
	f.close()
	_set_status("Saved → %s" % CONFIG_PATH)


func _on_load() -> void:
	if _load_from_disk():
		_apply_all_to_boss()
		_set_status("Loaded from disk")
	else:
		_set_status("No saved file")


func _load_from_disk() -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		return false
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return false
	for spec in KNOBS:
		var key: String = String(spec[0])
		if data.has(key):
			_values[key] = float(data[key])
			if _spins.has(key):
				(_spins[key] as SpinBox).set_value_no_signal(_values[key])
	return true


func _on_reset() -> void:
	# Reset to the boss SCRIPT defaults (a fresh instance's export values).
	var scn := load(BOSS_SCENE) as PackedScene
	var tmp = scn.instantiate() if scn != null else null
	for spec in KNOBS:
		var key: String = String(spec[0])
		var dv: float = float(tmp.get(key)) if (tmp != null and key in tmp) else float(spec[2])
		_values[key] = dv
		if _spins.has(key):
			(_spins[key] as SpinBox).set_value_no_signal(dv)
	if tmp != null:
		tmp.free()
	_apply_all_to_boss()
	_set_status("Reset to script defaults")


func _on_copy() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied (%d chars)" % s.length())


func _build_snippet() -> String:
	var lines := PackedStringArray()
	lines.append("# Paste into scripts/enemies/bosses/boss_z_battleship.gd (the movement/timing knobs):")
	for spec in KNOBS:
		var key: String = String(spec[0])
		lines.append("@export var %s: float = %s" % [key, _fmt(float(_values[key]))])
	return "\n".join(lines)


func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return "%.1f" % v
	return "%.2f" % v


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
