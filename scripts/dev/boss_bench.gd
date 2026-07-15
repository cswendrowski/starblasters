extends Control

# BossBench (Roman 2026-07-12) — live-tune + trigger the game's physics-driven "flying-fortress" bosses in
# ONE bench. Merges the retired battleship_lab + director_lab (they were near-identical twins) behind a boss
# selector. Both the Zealot Battleship and the Corporate Director extend physics_boss.gd and share the same
# maneuver API (play_named_maneuver / play_wave_maneuver / live_parts / start + the physics @export knobs),
# so a single data-driven bench covers them: pick a boss, trigger any maneuver / interlude, live-tune its
# knobs, or "Run gated combat" for the full director-driven wave→maneuver flow. Copy GDScript emits the
# paste-ready block. House tuner contract (scripts/dev/ui_designer.gd): JSON save/load, Reset, Esc-to-close,
# mandatory Copy GDScript.
#
# Adding a boss: give it physics_boss + the maneuver API, then append a BOSSES entry (scene / config path /
# snippet file / faction / own_knobs / int_keys / triggers / actions). No other change needed.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const DirectorScript = preload("res://scripts/levels/director.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")

# Shared thrust knobs (inherited from physics_boss.gd). Tuning here overrides THIS boss instance; Copy emits
# them as _ready() overrides (NOT @export) so a boss can feel different from its siblings WITHOUT redeclaring
# — and shadowing — the base-class exports.
const PHYS_KNOBS := [
	["MAIN_ACCEL", "Main thrust accel", 60.0, 700.0, 10.0],
	["STRAFE_ACCEL", "Strafe accel", 40.0, 700.0, 10.0],
	["MAX_SPEED", "Max speed (px/s)", 40.0, 460.0, 10.0],
	["LIN_DAMP", "Linear drag (1/s)", 0.4, 8.0, 0.1],
	["RCS_ANG_ACCEL", "RCS yaw accel", 0.5, 12.0, 0.2],
	["MAX_ANG_SPEED", "Max yaw rate", 0.4, 5.0, 0.1],
	["ANG_DAMP", "Yaw drag (1/s)", 0.5, 8.0, 0.1],
	["ARRIVE_RADIUS", "Arrive radius (px)", 15.0, 120.0, 2.0],
	["FACE_GAIN", "Yaw P gain", 1.0, 16.0, 0.5],
	["FACE_DAMP", "Yaw D gain", 0.2, 6.0, 0.1],
	["DEPTH_ACCEL", "Depth dive accel", 1.0, 14.0, 0.5],
	["DEPTH_SPRING", "Depth restore spring", 1.0, 14.0, 0.5],
	["DEPTH_DAMP", "Depth drag", 1.0, 12.0, 0.5],
]

# --- Per-boss config. Each: name, scene, config (user:// JSON), snippet_file (where Copy pastes back),
# faction (Factions.Id for the gated run-up waves; -1 = generic), own_knobs (boss-specific @export knobs,
# [key,label,min,max,step]), int_keys (own_knobs emitted as int in the snippet), triggers ([label, maneuver
# name]), actions ([label, action id → _do_action]).
const BOSSES := [
	{
		"name": "Zealot Battleship",
		"scene": "res://scenes/enemies/factions/zealot/boss_z_battleship.tscn",
		"config": "user://tuners/battleship.json",
		"snippet_file": "scripts/enemies/bosses/boss_z_battleship.gd",
		"faction": 3,   # Factions.Id.ZEALOT
		"own_knobs": [
			["HIGH_HOLD_Y", "High hold Y (px)", -120.0, 140.0, 2.0],
			["BLOCKADE_Y", "Blockade hold Y (px)", -60.0, 140.0, 2.0],
			["BEAM_HOLD", "Beam hold (s)", 0.5, 8.0, 0.25],
			["BLOCKADE_HOLD", "Blockade hold (s)", 0.5, 8.0, 0.25],
			["HAZARD_MIN_GAP", "Hazard gap MIN (s)", 2.0, 20.0, 0.5],
			["HAZARD_MAX_GAP", "Hazard gap MAX (s)", 2.0, 30.0, 0.5],
			["HAZARD_SWEEP_SPEED", "Hazard sweep speed", 10.0, 120.0, 5.0],
		],
		"int_keys": [],
		"triggers": [
			["Hook: Firecores", "hook_firecores"],
			["Hook: Laser", "hook_laser"],
			["Hook: Blockade", "hook_blockade"],
			["Slide: Firecores", "firecore_slide"],
			["Slide: Laser", "laser_slide"],
			["Lane Laser", "lane_laser"],
			["Hazard: Lane Laser", "hazard_lane_laser"],
			["Hazard: Sweep", "hazard_sweep"],
		],
		"actions": [
			["Destroy parts", "destroy_parts"],
		],
	},
	{
		"name": "Corporate Director",
		"scene": "res://scenes/enemies/factions/corporate/boss_c_director.tscn",
		"config": "user://tuners/director.json",
		"snippet_file": "scripts/enemies/bosses/boss_c_director.gd",
		"faction": 2,   # Factions.Id.CORPORATE — the Director only appears with corpo enemies
		"own_knobs": [
			["ARRIVE_Y", "Combat hold Y (px)", -40.0, 180.0, 2.0],
			["PARK_Y", "BG park Y (px)", -40.0, 180.0, 2.0],
			["SECTION_HP", "Section HP (per stage)", 10.0, 200.0, 5.0],
			["SECTION_DEBRIS", "Section debris pieces", 0.0, 16.0, 1.0],
			["WING_HP", "Wing cannon HP", 20.0, 300.0, 10.0],
			["GUN_VOLLEYS", "Gun volleys", 1.0, 8.0, 1.0],
			["GUN_BEAT", "Gun beat (s)", 0.1, 2.0, 0.05],
			["WING_BEAM_HOLD", "Wing beam hold (s)", 0.5, 6.0, 0.25],
			["RUSH_DUR", "Rush / exit dur (s)", 1.0, 5.0, 0.2],
			["KNOCK_UP", "Knock-away up", 0.0, 220.0, 4.0],
			["KNOCK_SIDE", "Knock-away side", 0.0, 120.0, 4.0],
			["MISSILE_SALVO", "Missiles / salvo", 1.0, 8.0, 1.0],
			["MISSILE_SHOT_DELAY", "Missile shot delay", 0.0, 1.0, 0.05],
			["BARRAGE_SALVO_GAP", "Barrage salvo gap", 0.5, 5.0, 0.25],
			["LANE_STRIKE_SPOTS", "Lane-strike spots", 2.0, 10.0, 1.0],
			["SKIRMISH_STOPS", "Skirmish stops", 2.0, 10.0, 1.0],
			["SKIRMISH_SLIDE_X", "Skirmish slide (px)", 20.0, 100.0, 4.0],
			["SKIRMISH_BURST_SHOTS", "Skirmish burst shots", 1.0, 6.0, 1.0],
			["SKIRMISH_BURST_GAP", "Skirmish burst gap", 0.05, 0.6, 0.02],
			["SKIRMISH_MISSILES", "Skirmish missiles", 1.0, 6.0, 1.0],
			["HAZARD_MIN_GAP", "Interlude gap MIN", 3.0, 20.0, 0.5],
			["HAZARD_MAX_GAP", "Interlude gap MAX", 3.0, 30.0, 0.5],
		],
		"int_keys": ["SECTION_HP", "SECTION_DEBRIS", "WING_HP", "GUN_VOLLEYS", "MISSILE_SALVO", "LANE_STRIKE_SPOTS", "SKIRMISH_STOPS", "SKIRMISH_BURST_SHOTS", "SKIRMISH_MISSILES"],
		"triggers": [
			["Gun Charge", "gun_charge"],
			["Laser Lane", "laser_lane"],
			["Missile Weave", "missile_weave"],
			["Cannon Skirmish", "cannon_skirmish"],
			["Missile Barrage", "missile_barrage"],
			["Missile Lane-Strike", "missile_lane_strike"],
		],
		"actions": [
			["Destroy wings", "destroy_wings"],
			["Kill (all sections)", "kill_body"],
		],
	},
]

var _boss_idx: int = 0
var _cfg: Dictionary = {}
var _values: Dictionary = {}
var _spins: Dictionary = {}
var _status_label: Label = null
var _world: SubViewport = null
var _boss = null
var _player = null
var _director = null
var _hd_scope: HdViewportScope = null

# Dynamic UI sections rebuilt on each boss switch.
var _trigger_grid: GridContainer = null
var _action_row: HBoxContainer = null
var _knob_box: VBoxContainer = null


class DummyPlayer extends Area2D:
	# Invulnerable, arrow-key-flyable target so guns/beams/missiles have someone to (harmlessly) hit.
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
	func take_damage(_d: int = 0) -> void: pass   # never dies (bench target)
	func take_hit(_d: int = 1) -> bool: return false
	func _process(dt: float) -> void:
		var v := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		position = Playfield.clamp_pos(position + v * SPEED * dt)


func _ready() -> void:
	_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_preview()
	await _select_boss(_boss_idx)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


func _all_knobs() -> Array:
	return PHYS_KNOBS + (_cfg.get("own_knobs", []) as Array)


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
	title.text = "BOSS BENCH"
	title.add_theme_font_size_override("font_size", 22)
	rail.add_child(title)
	var hint := Label.new()
	hint.text = "Arrow keys fly the (invulnerable) player."
	hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	rail.add_child(hint)

	rail.add_child(_section("Boss"))
	var picker := OptionButton.new()
	for b in BOSSES:
		picker.add_item(String(b["name"]))
	picker.selected = _boss_idx
	picker.item_selected.connect(_on_boss_selected)
	rail.add_child(picker)

	rail.add_child(_section("Trigger maneuver / interlude"))
	_trigger_grid = GridContainer.new()
	_trigger_grid.columns = 2
	_trigger_grid.add_theme_constant_override("h_separation", 6)
	_trigger_grid.add_theme_constant_override("v_separation", 4)
	rail.add_child(_trigger_grid)
	_action_row = HBoxContainer.new()
	rail.add_child(_action_row)

	rail.add_child(_section("Full combat (director-gated waves)"))
	var crow := HBoxContainer.new()
	rail.add_child(crow)
	_add_button(crow, "Run gated combat", _run_combat)
	_add_button(crow, "Stop", _stop_combat)

	rail.add_child(_section("Movement / timing"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	rail.add_child(scroll)
	_knob_box = VBoxContainer.new()
	_knob_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_knob_box)

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


# Repopulate the per-boss sections (triggers, actions, knob rows) for _cfg.
func _rebuild_dynamic() -> void:
	_spins.clear()
	_clear(_trigger_grid)
	_clear(_action_row)
	_clear(_knob_box)
	for t in (_cfg.get("triggers", []) as Array):
		var nm: String = String(t[1])
		_add_button(_trigger_grid, String(t[0]), func(): _trigger(nm))
	_add_button(_action_row, "Random", func(): _trigger(""))
	_add_button(_action_row, "Respawn", _respawn_boss)
	for a in (_cfg.get("actions", []) as Array):
		var id: String = String(a[1])
		_add_button(_action_row, String(a[0]), func(): _do_action(id))
	for spec in _all_knobs():
		_knob_box.add_child(_make_knob_row(spec))


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


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
	for spec in _all_knobs():
		var key: String = String(spec[0])
		var dv: float = float(_boss.get(key)) if (_boss != null and key in _boss) else float(spec[2])
		_values[key] = dv
		if _spins.has(key):
			(_spins[key] as SpinBox).set_value_no_signal(dv)


# --- Boss selection -------------------------------------------------------

func _on_boss_selected(idx: int) -> void:
	await _select_boss(idx)


func _select_boss(idx: int) -> void:
	_stop_combat()
	if _boss != null and is_instance_valid(_boss):
		_boss.queue_free()
		_boss = null
		await get_tree().process_frame
	_boss_idx = idx
	_cfg = BOSSES[idx]
	_values.clear()
	_rebuild_dynamic()
	_spawn_boss()
	_seed_values()
	_load_from_disk()   # override seed with any saved tuning for THIS boss
	_apply_all_to_boss()
	_set_status("Editing %s" % _cfg_file())


# --- Preview --------------------------------------------------------------

func _build_preview() -> void:
	if _world == null:
		return
	var bw := Node2D.new()          # projectile / firecore sink INSIDE the SubViewport (BulletWorld group)
	bw.add_to_group("bullet_world")
	_world.add_child(bw)
	_spawn_backdrop()
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
	var scn := load(String(_cfg["scene"])) as PackedScene
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


# --- Per-boss special actions (dispatched from the config's `actions`) -----

func _do_action(id: String) -> void:
	match id:
		"destroy_parts": _destroy_parts()
		"destroy_wings": _destroy_wings()
		"kill_body": _kill_body()


func _destroy_parts() -> void:
	if _boss == null or not is_instance_valid(_boss) or not _boss.has_method("live_parts"):
		return
	for p in _boss.live_parts().duplicate():
		if is_instance_valid(p) and p.has_method("destroy"):
			p.destroy()
	_set_status("Destroyed all parts → death sequence")


func _destroy_wings() -> void:
	if _boss == null or not is_instance_valid(_boss) or not ("_wings" in _boss):
		return
	for w in _boss._wings.duplicate():
		if is_instance_valid(w) and w.has_method("destroy"):
			w.destroy()
	_set_status("Destroyed the wing cannons (Laser Lane now falls back)")


# Kill every section + wing (the fight IS the sections → kill-all = death). Hits each a few times so the
# 2-stage hood/missile fully clears.
func _kill_body() -> void:
	if _boss == null or not is_instance_valid(_boss) or not _boss.has_method("live_parts"):
		return
	for p in _boss.live_parts().duplicate():
		for _n in 3:
			if not is_instance_valid(p) or (p.has_method("is_destroyed") and p.is_destroyed()):
				break
			p.take_hit(999999)
	_set_status("All sections destroyed → death sequence")


# --- Full gated combat ----------------------------------------------------

func _run_combat() -> void:
	_stop_combat()
	if _boss == null or not is_instance_valid(_boss):
		_spawn_boss()
	var fac: int = int(_cfg.get("faction", -1))
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.forced_boss_scene = String(_cfg["scene"])
		if fac >= 0:
			run.set_meta("active_faction", fac)   # the boss's faction gates its run-up waves
	var score = WaveGen.build_score(1, 0, true, fac)
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

func _cfg_file() -> String:
	return String(_cfg.get("config", "user://tuners/boss.json")).get_file()


func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(String(_cfg["config"]), FileAccess.WRITE)
	if f == null:
		_set_status("Save FAILED")
		return
	f.store_string(JSON.stringify(_values, "\t"))
	f.close()
	_set_status("Saved → %s" % _cfg_file())


func _on_load() -> void:
	if _load_from_disk():
		_apply_all_to_boss()
		_set_status("Loaded from disk")
	else:
		_set_status("No saved file")


func _load_from_disk() -> bool:
	var path := String(_cfg["config"])
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return false
	for spec in _all_knobs():
		var key: String = String(spec[0])
		if data.has(key):
			_values[key] = float(data[key])
			if _spins.has(key):
				(_spins[key] as SpinBox).set_value_no_signal(_values[key])
	return true


func _on_reset() -> void:
	# Reset to the boss SCRIPT defaults (a fresh instance's export values).
	var scn := load(String(_cfg["scene"])) as PackedScene
	var tmp = scn.instantiate() if scn != null else null
	for spec in _all_knobs():
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
	lines.append("# %s tuning (Boss Bench). Boss-specific @exports → %s defaults:" % [String(_cfg["name"]), String(_cfg["snippet_file"])])
	for spec in (_cfg.get("own_knobs", []) as Array):
		var key: String = String(spec[0])
		lines.append("@export var %s%s = %s" % [key, _type_of(key), _val_str(key)])
	lines.append("")
	lines.append("# Shared thrust knobs are inherited from physics_boss.gd — to give this boss its OWN feel")
	lines.append("# without shadowing the base, set these in _ready() AFTER super._ready():")
	for spec in PHYS_KNOBS:
		var key: String = String(spec[0])
		lines.append("\t%s = %s" % [key, _val_str(key)])
	return "\n".join(lines)


func _type_of(key: String) -> String:
	return ": int" if key in (_cfg.get("int_keys", []) as Array) else ": float"


func _val_str(key: String) -> String:
	var v: float = float(_values.get(key, 0.0))
	if key in (_cfg.get("int_keys", []) as Array):
		return str(int(round(v)))
	return _fmt(v)


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
