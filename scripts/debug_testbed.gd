extends Control

# Visual rendering test bed. Hosts the cosmos backdrop in isolation so we
# can cycle through planet variants + nebula styles independently and
# inspect the rendering. Accessible from main menu.

const Backdrop = preload("res://scripts/galaxy_backdrop.gd")

const PLANET_NAMES = [
	"LavaWorld", "IceWorld", "DryTerran", "GasPlanet", "NoAtmosphere",
	"LandMasses", "BlackHole", "Galaxy", "Star",
]

# Nebula style presets — each independently cycleable.
const NEBULA_PRESETS = [
	{"name": "Default",  "nebula_scale": 2.5, "nebula_octaves": 5.0, "nebula_drift": 0.004, "nebula_alpha": 0.35, "nebula_density": 0.9,  "nebula_edge": 0.4, "nebula_pixels": 200.0, "starfield_density": 40.0},
	{"name": "Wisps",    "nebula_scale": 1.5, "nebula_octaves": 3.0, "nebula_drift": 0.008, "nebula_alpha": 0.25, "nebula_density": 0.6,  "nebula_edge": 0.2, "nebula_pixels": 0.0,   "starfield_density": 30.0},
	{"name": "Stormy",   "nebula_scale": 4.5, "nebula_octaves": 7.0, "nebula_drift": 0.015, "nebula_alpha": 0.45, "nebula_density": 1.4,  "nebula_edge": 0.7, "nebula_pixels": 0.0,   "starfield_density": 50.0},
	{"name": "Vibrant",  "nebula_scale": 3.0, "nebula_octaves": 6.0, "nebula_drift": 0.003, "nebula_alpha": 0.55, "nebula_density": 1.2,  "nebula_edge": 0.3, "nebula_pixels": 0.0,   "starfield_density": 60.0},
	{"name": "Sparse",   "nebula_scale": 1.2, "nebula_octaves": 2.0, "nebula_drift": 0.002, "nebula_alpha": 0.2,  "nebula_density": 0.4,  "nebula_edge": 0.1, "nebula_pixels": 0.0,   "starfield_density": 20.0},
	{"name": "Retro",    "nebula_scale": 2.5, "nebula_octaves": 5.0, "nebula_drift": 0.004, "nebula_alpha": 0.4,  "nebula_density": 0.9,  "nebula_edge": 0.6, "nebula_pixels": 120.0, "starfield_density": 40.0},
	{"name": "None",     "nebula_scale": 2.5, "nebula_octaves": 5.0, "nebula_drift": 0.0,   "nebula_alpha": 0.0,  "nebula_density": 0.0,  "nebula_edge": 0.0, "nebula_pixels": 0.0,   "starfield_density": 60.0},
]

# Live props apply without respawn. Nebula uniforms are all live since they're
# just shader parameters on the existing Nebula ColorRect.
const LIVE_PROPS = [
	"planet_pixels", "asteroid_pixels", "surface_time_scale", "drift_speed",
	"nebula_drift", "nebula_alpha", "nebula_density", "nebula_edge",
	"nebula_scale", "nebula_octaves", "nebula_pixels",
]

@onready var stage: Node2D = $Stage
@onready var info_label: Label = $TopBar/InfoLabel
@onready var back_btn: Button = $TopBar/BackBtn
@onready var randomize_btn: Button = $TopBar/RandomizeBtn
@onready var showcase: Node2D = $Showcase if has_node("Showcase") else null

# Tabs
@onready var tabs: TabContainer = $Tabs
@onready var planet_name_label: Label = $Tabs/Planet/PlanetName
@onready var planet_stats_label: Label = $Tabs/Planet/PlanetStats
@onready var prev_btn: Button = $Tabs/Planet/PlanetBtns/PrevBtn
@onready var next_btn: Button = $Tabs/Planet/PlanetBtns/NextBtn
@onready var random_btn: Button = $Tabs/Planet/PlanetBtns/RandomBtn

@onready var nebula_name_label: Label = $Tabs/Nebula/NebulaName
@onready var nebula_stats_label: Label = $Tabs/Nebula/NebulaStats
@onready var neb_prev_btn: Button = $Tabs/Nebula/NebulaBtns/NebPrevBtn
@onready var neb_next_btn: Button = $Tabs/Nebula/NebulaBtns/NebNextBtn
@onready var neb_rand_btn: Button = $Tabs/Nebula/NebulaBtns/NebRandBtn

const SHOWCASE_LIST = [
	# Row 1 (y=720) — Player + small enemies
	["res://scenes/player/player.tscn",          "Player",   Vector2( 80, 720), 3.0],
	["res://scenes/enemies/enemy_firecore.tscn", "Firecore", Vector2(180, 720), 3.0],
	["res://scenes/enemies/enemy_diver.tscn",    "Diver",    Vector2(280, 720), 2.5],
	# Row 2 (y=815) — medium enemies
	["res://scenes/enemies/enemy_crystal.tscn",  "Crystal",  Vector2( 80, 815), 1.6],
	["res://scenes/enemies/enemy_dart.tscn",     "Dart",     Vector2(180, 815), 1.5],
	["res://scenes/enemies/enemy_hopper.tscn",   "Hopper",   Vector2(280, 815), 2.0],
	# Row 3 (y=920) — boss alone at full in-game scale
	["res://scenes/enemies/boss.tscn",           "Boss",     Vector2(230, 920), 3.0],
]

var _current_bd = null
var _current_planet_idx: int = 0
var _planet_forced: bool = true
var _current_nebula_idx: int = 0
var _nebula_forced: bool = true
var _tweak_overrides: Dictionary = {}

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	randomize_btn.pressed.connect(_on_randomize)
	prev_btn.pressed.connect(_on_planet_prev)
	next_btn.pressed.connect(_on_planet_next)
	random_btn.pressed.connect(_on_planet_random)
	neb_prev_btn.pressed.connect(_on_nebula_prev)
	neb_next_btn.pressed.connect(_on_nebula_next)
	neb_rand_btn.pressed.connect(_on_nebula_random)
	# Pull defaults from main.tscn's Backdrop so the testbed starts where
	# the actual game starts, not from script defaults.
	_sync_defaults_from_main()
	_apply_nebula_preset(0)
	_wire_sliders()
	_wire_ships_tab()
	_spawn_showcase()
	_spawn_backdrop()

# Read planet/nebula settings from main.tscn's Backdrop node and stash them
# as the initial _tweak_overrides so the testbed mirrors the real game.
func _sync_defaults_from_main() -> void:
	var ps = load("res://scenes/main.tscn")
	if ps == null:
		return
	var inst = ps.instantiate()
	var bd = inst.get_node_or_null("Backdrop")
	if bd:
		var keys = [
			"planet_size", "planet_size_variance", "planet_pixels", "asteroid_pixels",
			"asteroid_count", "drift_speed", "surface_time_scale",
			"nebula_pixels", "nebula_octaves", "nebula_drift", "nebula_alpha",
			"nebula_density", "nebula_edge", "nebula_scale", "starfield_density",
		]
		for k in keys:
			if k in bd:
				_tweak_overrides[k] = bd.get(k)
	inst.queue_free()

# --- Spawning ---

func _spawn_backdrop() -> void:
	if _current_bd != null and is_instance_valid(_current_bd):
		_current_bd.queue_free()
	var bd = Backdrop.new()
	bd.name = "Backdrop"
	bd.forced_planet_idx = _current_planet_idx if _planet_forced else -1
	# Apply all overrides BEFORE add_child so _ready uses them
	for prop in _tweak_overrides.keys():
		if prop in bd:
			bd.set(prop, _tweak_overrides[prop])
	stage.add_child(bd)
	_current_bd = bd
	await get_tree().process_frame
	_update_info()

# Wire the Ships tab sliders so each one rescales its showcase ship live.
func _wire_ships_tab() -> void:
	if tabs == null or not tabs.has_node("Ships"):
		return
	var ships_tab = tabs.get_node("Ships")
	for row in ships_tab.get_children():
		if not (row is VBoxContainer):
			continue
		var sld = row.get_node_or_null("Slider")
		if sld == null:
			continue
		sld.value_changed.connect(_on_ship_scale_changed.bind(row))
	var save_btn = ships_tab.get_node_or_null("SaveScalesBtn")
	if save_btn:
		save_btn.pressed.connect(_on_save_ship_scales)

func _on_ship_scale_changed(value, row) -> void:
	var sld = row.get_node("Slider")
	var lbl = row.get_node("Label")
	var ship_name: String = sld.get_meta("ship_name")
	lbl.text = "%s: %.2f" % [ship_name, value]
	# Find and rescale the matching showcase ship
	if showcase == null:
		return
	for c in showcase.get_children():
		if c.has_meta("ship_name") and c.get_meta("ship_name") == ship_name:
			c.scale = Vector2(value, value)
			return

func _on_save_ship_scales() -> void:
	# Print current values so user can copy them; in-place save would mutate
	# .tscn files which is risky from a running scene.
	if tabs == null or not tabs.has_node("Ships"):
		return
	var lines: Array = ["Current ship scales (copy into each scene's display_scale):"]
	for row in tabs.get_node("Ships").get_children():
		if not (row is VBoxContainer):
			continue
		var sld = row.get_node_or_null("Slider")
		if sld == null:
			continue
		var ship_name: String = sld.get_meta("ship_name")
		var scene_path: String = sld.get_meta("scene_path")
		lines.append("  %-9s %s -> display_scale=%.2f" % [ship_name + ":", scene_path.get_file(), sld.value])
	print("\n".join(lines))
	# Also flash the info label so the user sees something happened
	info_label.text = "Ship scales printed to console"

func _spawn_showcase() -> void:
	if showcase == null:
		return
	for child in showcase.get_children():
		child.queue_free()
	for entry in SHOWCASE_LIST:
		var path: String = entry[0]
		var lbl_text: String = entry[1]
		var pos: Vector2 = entry[2]
		var sc: float = entry[3]
		var ps = load(path)
		if ps == null:
			continue
		var inst = ps.instantiate()
		inst.scale = Vector2(sc, sc)
		# Tag with ship name so the Ships tab slider can find it
		inst.set_meta("ship_name", lbl_text)
		showcase.add_child(inst)
		inst.position = pos
		inst.process_mode = Node.PROCESS_MODE_DISABLED
		var lbl = Label.new()
		lbl.text = lbl_text
		# Caption offset scales with the ship's display scale so big sprites
		# don't sit on top of their own labels.
		var cap_y: float = max(32.0, sc * 18.0 + 10.0)
		lbl.position = pos + Vector2(-40, cap_y)
		lbl.custom_minimum_size = Vector2(80, 16)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1, 0.95))
		showcase.add_child(lbl)

# --- Info / labels ---

func _update_info() -> void:
	if _current_bd == null or not is_instance_valid(_current_bd):
		return
	var bd = _current_bd
	info_label.text = "%d children" % bd.get_child_count()
	# Planet labels
	var name_str: String = "?"
	if _current_planet_idx >= 0 and _current_planet_idx < PLANET_NAMES.size():
		name_str = PLANET_NAMES[_current_planet_idx]
	var mode = "FORCED" if _planet_forced else "RANDOM"
	planet_name_label.text = "[ %d/%d ] %s — %s" % [_current_planet_idx + 1, PLANET_NAMES.size(), name_str, mode]
	planet_stats_label.text = _build_planet_stats()
	# Nebula labels
	var n_name: String = "Random"
	if _nebula_forced and _current_nebula_idx >= 0 and _current_nebula_idx < NEBULA_PRESETS.size():
		n_name = NEBULA_PRESETS[_current_nebula_idx].name
	nebula_name_label.text = "[ %d/%d ] %s" % [_current_nebula_idx + 1, NEBULA_PRESETS.size(), n_name]
	nebula_stats_label.text = _build_nebula_stats()

func _build_planet_stats() -> String:
	var bd = _current_bd
	var planet = null
	for c in bd.get_children():
		if c.has_meta("planet_actual_size"):
			planet = c
			break
	var lines: Array = []
	lines.append("size:     %d" % int(bd.planet_size))
	lines.append("variance: %.2f" % bd.planet_size_variance)
	lines.append("drift:    %.1f" % bd.drift_speed)
	lines.append("pixels:   %d" % int(bd.planet_pixels))
	if planet:
		var act: float = float(planet.get_meta("planet_actual_size"))
		lines.append("actual:   %d" % int(act))
		lines.append("scale:    %.2fx" % (act / 100.0))
		var voff: float = -planet.position.y / max(act, 1.0)
		lines.append("y_offset: %.2f" % voff)
	return "\n".join(lines)

func _build_nebula_stats() -> String:
	var bd = _current_bd
	var lines: Array = []
	lines.append("neb_pixels:  %d" % int(bd.nebula_pixels))
	lines.append("neb_octaves: %d" % int(bd.nebula_octaves))
	lines.append("neb_drift:   %.3f" % bd.nebula_drift)
	lines.append("starfield:   %d" % int(bd.starfield_density))
	return "\n".join(lines)

# --- Slider wiring ---

func _wire_sliders() -> void:
	if tabs == null:
		return
	var defaults_src = Backdrop.new()
	# Walk both tabs
	for tab in [tabs.get_node("Planet"), tabs.get_node("Nebula")]:
		for row in tab.get_children():
			if not (row is VBoxContainer):
				continue
			if not row.name.begins_with("Row_"):
				continue
			var sld = row.get_node_or_null("Slider")
			if sld == null:
				continue
			var prop: String = sld.get_meta("prop")
			# Initialize from script default OR existing override
			var v: float = float(defaults_src.get(prop)) if (prop in defaults_src) else sld.value
			if _tweak_overrides.has(prop):
				v = _tweak_overrides[prop]
			sld.value = v
			_tweak_overrides[prop] = v
			_update_slider_label(row)
			sld.value_changed.connect(_on_slider_changed.bind(row))
			sld.drag_ended.connect(_on_slider_drag_ended.bind(row))
	defaults_src.queue_free()

func _update_slider_label(row: VBoxContainer) -> void:
	var sld = row.get_node("Slider")
	var lbl = row.get_node("Label")
	var pfx: String = sld.get_meta("label_pfx")
	var suffix: String = sld.get_meta("suffix")
	var fmt: String = "%.3f" if sld.step < 0.1 else ("%.2f" if sld.step < 1.0 else "%d")
	var val_str: String = fmt % (int(sld.value) if sld.step >= 1.0 else sld.value)
	lbl.text = "%s: %s%s" % [pfx, val_str, suffix]

func _on_slider_changed(value, row) -> void:
	var sld = row.get_node("Slider")
	var prop: String = sld.get_meta("prop")
	_tweak_overrides[prop] = value
	_update_slider_label(row)
	if prop in LIVE_PROPS and _current_bd != null and is_instance_valid(_current_bd):
		_current_bd.set(prop, value)
		if prop == "planet_pixels" or prop == "asteroid_pixels":
			for c in _current_bd.get_children():
				_current_bd._apply_pixels_only(c, value)
		else:
			# Nebula shader-uniform map: prop name -> uniform name
			var neb_uniforms = {
				"nebula_drift": "drift_speed",
				"nebula_alpha": "max_alpha",
				"nebula_density": "density",
				"nebula_edge": "edge_sharpness",
				"nebula_scale": "scale",
				"nebula_octaves": "octaves",
				"nebula_pixels": "pixels",
			}
			if prop in neb_uniforms:
				for c in _current_bd.get_children():
					if c.name == "Nebula" and c.material is ShaderMaterial:
						var uname: String = neb_uniforms[prop]
						# octaves is int
						if uname == "octaves":
							c.material.set_shader_parameter(uname, int(value))
						else:
							c.material.set_shader_parameter(uname, value)

func _on_slider_drag_ended(value_changed: bool, row) -> void:
	if not value_changed:
		return
	var sld = row.get_node("Slider")
	var prop: String = sld.get_meta("prop")
	if prop in LIVE_PROPS:
		return
	_spawn_backdrop()

# --- Planet controls ---

func _on_planet_prev() -> void:
	_planet_forced = true
	_current_planet_idx = (_current_planet_idx - 1 + PLANET_NAMES.size()) % PLANET_NAMES.size()
	_spawn_backdrop()

func _on_planet_next() -> void:
	_planet_forced = true
	_current_planet_idx = (_current_planet_idx + 1) % PLANET_NAMES.size()
	_spawn_backdrop()

func _on_planet_random() -> void:
	_planet_forced = false
	if has_node("/root/Run"):
		get_node("/root/Run").run_seed = randi()
	_spawn_backdrop()

# --- Nebula controls ---

func _on_nebula_prev() -> void:
	_nebula_forced = true
	_current_nebula_idx = (_current_nebula_idx - 1 + NEBULA_PRESETS.size()) % NEBULA_PRESETS.size()
	_apply_nebula_preset(_current_nebula_idx)
	_sync_sliders_from_overrides()
	_spawn_backdrop()

func _on_nebula_next() -> void:
	_nebula_forced = true
	_current_nebula_idx = (_current_nebula_idx + 1) % NEBULA_PRESETS.size()
	_apply_nebula_preset(_current_nebula_idx)
	_sync_sliders_from_overrides()
	_spawn_backdrop()

func _on_nebula_random() -> void:
	# Randomize nebula seed (not preset) — keeps preset but new pattern
	_nebula_forced = false
	if has_node("/root/Run"):
		get_node("/root/Run").run_seed = randi()
	_spawn_backdrop()

func _apply_nebula_preset(idx: int) -> void:
	if idx < 0 or idx >= NEBULA_PRESETS.size():
		return
	var p = NEBULA_PRESETS[idx]
	for k in p.keys():
		if k == "name":
			continue
		_tweak_overrides[k] = p[k]

func _sync_sliders_from_overrides() -> void:
	if tabs == null:
		return
	for tab in [tabs.get_node("Planet"), tabs.get_node("Nebula")]:
		for row in tab.get_children():
			if not (row is VBoxContainer):
				continue
			var sld = row.get_node_or_null("Slider")
			if sld == null:
				continue
			var prop: String = sld.get_meta("prop")
			if _tweak_overrides.has(prop):
				sld.value = float(_tweak_overrides[prop])
				_update_slider_label(row)

# --- Misc ---

func _on_back() -> void:
	var SceneTransition = load("res://scripts/scene_transition.gd")
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")

func _on_randomize() -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").run_seed = randi()
	_spawn_backdrop()
