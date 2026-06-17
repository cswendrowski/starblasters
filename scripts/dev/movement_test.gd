extends Control

# Movement Test — drop a single enemy on an empty playfield, trace its
# global position frame-by-frame with a Line2D, and re-run multiple times
# with the traces overlaid in different hues. Enemies whose runs don't
# overlap cleanly are the inconsistent ones; the shape of the curve also
# tells us whether the bug is in the pattern resource, auto-rotation,
# or the offscreen-cycle/leave logic.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const BossSweep = preload("res://scripts/enemies/patterns/boss_sweep.gd")

# Playfield rect on screen. The full game uses 800×1000; we shrink the
# trace area horizontally so a control rail can sit on the right.
const FIELD_RECT := Rect2(8, 24, 180, 350)  # 320×400 res rework
# Hide non-standalone scenes (placeholder enemy.tscn, the bomblet hazard
# spawned by mines, etc.). Bosses are included on purpose — their flight
# is part of the bug surface.
const HIDE_LIST: Array = ["enemy", "enemy-mine", "enemy_bomblet"]
const TRAIL_PALETTE: Array = [
	Color(0.55, 0.95, 1.00, 0.85),
	Color(1.00, 0.80, 0.45, 0.85),
	Color(0.95, 0.55, 0.95, 0.85),
	Color(0.65, 1.00, 0.55, 0.85),
	Color(1.00, 0.50, 0.50, 0.85),
]
# How long a single run is given before we forcibly end it (e.g. for an
# enemy that loiters indefinitely or sits at an anchor).
const RUN_TIMEOUT := 5.0

var _enemy_paths: Array[String] = []
var _field: Control = null
var _field_world: Node2D = null   # spawn parent (Node2D so children carry world coords)
var _trail_layer: Node2D = null   # Line2D parent
var _enemy_select: OptionButton = null
var _status: Label = null
var _run_count_spinner: SpinBox = null
var _active_runs: int = 0
# Current trail being grown; rotates as we cycle through runs.
var _current_trail: Line2D = null
var _current_enemy: Node = null
var _run_t: float = 0.0
var _runs_remaining: int = 0
var _palette_idx: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_scan_enemies()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.11, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header := Label.new()
	header.text = "MOVEMENT TEST"
	header.position = Vector2(8, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	add_child(header)

	var back_btn := Button.new()
	back_btn.text = "Back to Dev Menu"
	back_btn.position = Vector2(8, 380)
	back_btn.size = Vector2(80, 14)
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)

	_status = Label.new()
	_status.position = Vector2(96, 382)
	_status.size = Vector2(220, 12)
	_status.text = "Pick an enemy, click Run."
	UiTheme.style_label(_status, UiTheme.LabelKind.CAPTION)
	add_child(_status)

	# Playfield mockup
	_field = Control.new()
	_field.position = FIELD_RECT.position
	_field.size = FIELD_RECT.size
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_field)

	var field_bg := ColorRect.new()
	field_bg.color = Color(0.10, 0.13, 0.18, 1.0)
	field_bg.size = FIELD_RECT.size
	_field.add_child(field_bg)

	var grid := Node2D.new()
	grid.draw.connect(_draw_grid.bind(grid))
	_field.add_child(grid)
	grid.queue_redraw()

	# World-space layer where enemies live. Positions are field-local px.
	_field_world = Node2D.new()
	_field_world.name = "World"
	_field.add_child(_field_world)
	# Trail layer sits above the world so traces are visible even after
	# the enemy walks past.
	_trail_layer = Node2D.new()
	_trail_layer.name = "Trails"
	_field.add_child(_trail_layer)

	# Right rail wrapped in a ScrollContainer so controls don't get
	# clipped off-screen when the legend wraps (Roman, 2026-05-17).
	var rail_scroll := ScrollContainer.new()
	rail_scroll.position = Vector2(192, 24)
	rail_scroll.size = Vector2(124, 350)
	add_child(rail_scroll)
	var rail := VBoxContainer.new()
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 8)
	rail_scroll.add_child(rail)

	var pick_lbl := Label.new()
	pick_lbl.text = "Enemy"
	UiTheme.style_label(pick_lbl, UiTheme.LabelKind.CAPTION)
	rail.add_child(pick_lbl)

	_enemy_select = OptionButton.new()
	_enemy_select.custom_minimum_size = Vector2(0, 14)
	# Long enemy names like "enemy_mine_cluster_smart" otherwise force the
	# OptionButton's preferred width past the rail, dragging every sibling
	# off-screen. Clip + don't grow.
	_enemy_select.fit_to_longest_item = false
	_enemy_select.clip_text = true
	_enemy_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(_enemy_select)

	var runs_lbl := Label.new()
	runs_lbl.text = "Runs (overlay)"
	UiTheme.style_label(runs_lbl, UiTheme.LabelKind.CAPTION)
	rail.add_child(runs_lbl)

	_run_count_spinner = SpinBox.new()
	_run_count_spinner.min_value = 1
	_run_count_spinner.max_value = 8
	_run_count_spinner.value = 3
	_run_count_spinner.step = 1
	_run_count_spinner.custom_minimum_size = Vector2(0, 14)
	_run_count_spinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(_run_count_spinner)

	var run_btn := Button.new()
	run_btn.text = "Run"
	run_btn.custom_minimum_size = Vector2(0, 14)
	UiTheme.style_button(run_btn, true)
	run_btn.pressed.connect(_on_run)
	rail.add_child(run_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Trails"
	clear_btn.custom_minimum_size = Vector2(0, 14)
	UiTheme.style_button(clear_btn, true)
	clear_btn.pressed.connect(_on_clear)
	rail.add_child(clear_btn)

	rail.add_child(HSeparator.new())

	var legend := Label.new()
	legend.text = "Each run gets a unique hue. Tight overlap = consistent. Fanning lines = bug."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(0, 0)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(legend, UiTheme.LabelKind.CAPTION)
	rail.add_child(legend)


func _scan_enemies() -> void:
	# Hardcoded manifest — DirAccess.list_dir on res:// returns nothing in
	# exported web builds, which is what was making the dropdown look empty.
	_enemy_select.clear()
	_enemy_paths.clear()
	# Full dev roster (incl. faction units like the zealots), bosses kept — the movement test covers
	# them too. HIDE_LIST below still trims anything not worth testing (Roman 2026-06-17).
	var paths: Array = EnemyManifest.all_enemies(true)
	paths.sort()
	for p in paths:
		var nm: String = (p as String).get_file().get_basename()
		if nm in HIDE_LIST:
			continue
		_enemy_paths.append(p)
		_enemy_select.add_item(nm)


func _draw_grid(canvas: Node2D) -> void:
	var c := Color(1, 1, 1, 0.05)
	for x in range(0, int(FIELD_RECT.size.x), 16):
		canvas.draw_line(Vector2(x, 0), Vector2(x, FIELD_RECT.size.y), c, 1.0)
	for y in range(0, int(FIELD_RECT.size.y), 16):
		canvas.draw_line(Vector2(0, y), Vector2(FIELD_RECT.size.x, y), c, 1.0)
	# Top + bottom edge markers — same convention as Maneuver Sim.
	canvas.draw_line(Vector2(0, 0), Vector2(FIELD_RECT.size.x, 0), Color(0.6, 0.82, 1.0, 0.55), 2.0)
	canvas.draw_line(Vector2(0, FIELD_RECT.size.y), Vector2(FIELD_RECT.size.x, FIELD_RECT.size.y), Color(1.0, 0.6, 0.5, 0.55), 2.0)


# ---- Run loop --------------------------------------------------------------

func _on_run() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy):
		_status.text = "Run in progress."
		return
	if _enemy_paths.is_empty():
		_status.text = "No enemies found."
		return
	_runs_remaining = int(_run_count_spinner.value)
	_start_next_run()


func _on_clear() -> void:
	for c in _trail_layer.get_children():
		c.queue_free()
	for c in _field_world.get_children():
		c.queue_free()
	_current_enemy = null
	_status.text = "Cleared."


func _start_next_run() -> void:
	if _runs_remaining <= 0:
		_status.text = "Done — review trails."
		return
	var path: String = _enemy_paths[_enemy_select.selected]
	var ps: PackedScene = load(path)
	if ps == null:
		_status.text = "Failed to load %s" % path
		return
	# Build a fresh enemy instance. Match the in-game spawn path: in combat,
	# WaveDirector pulls a movement Resource from EnemyRoster.make_movement
	# for non-boss enemies and applies it to the instance. Mirror that here
	# so the test shows the *real* pattern, not a generic straight_down
	# fallback (Roman, 2026-05-17: "double check the movement test is
	# actually loading the ship's movement behavior").
	var inst: Node = ps.instantiate()
	if "movement" in inst:
		var assigned: Resource = _resolve_movement_for(path)
		if assigned != null:
			inst.movement = assigned
	if "shoot_pattern" in inst:
		inst.shoot_pattern = null  # don't try to fire bullets in a blank scene
	# Match WaveDirector's default scale. At 320×400 internal that's 1×
	# native (no scaling).
	if inst is Node2D:
		(inst as Node2D).scale = Vector2(1, 1)
	_field_world.add_child(inst)
	# Spawn at top-center of the field. enemy.start(pos) is the standard
	# entry point used by WaveDirector; fall back to plain position assign.
	var spawn := Vector2(FIELD_RECT.size.x * 0.5, 24.0)
	if inst.has_method("start"):
		inst.start(spawn)
	else:
		if inst is Node2D:
			(inst as Node2D).position = spawn
	_current_enemy = inst
	_run_t = 0.0
	# Start a new trail Line2D.
	_current_trail = Line2D.new()
	_current_trail.width = 2.0
	_current_trail.default_color = TRAIL_PALETTE[_palette_idx % TRAIL_PALETTE.size()]
	_palette_idx += 1
	_trail_layer.add_child(_current_trail)
	_status.text = "Run %d of %d (%s)" % [
		int(_run_count_spinner.value) - _runs_remaining + 1,
		int(_run_count_spinner.value),
		_enemy_select.get_item_text(_enemy_select.selected),
	]


func _process(delta: float) -> void:
	if _current_enemy == null:
		return
	_run_t += delta
	if not is_instance_valid(_current_enemy):
		_finish_run()
		return
	# Trace the position (field-local).
	if _current_enemy is Node2D and _current_trail != null:
		var pos: Vector2 = (_current_enemy as Node2D).global_position - _field.global_position
		_current_trail.add_point(pos)
	# Time out if the enemy is loitering forever.
	if _run_t >= RUN_TIMEOUT:
		_finish_run()


func _finish_run() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy):
		_current_enemy.queue_free()
	_current_enemy = null
	_current_trail = null
	_runs_remaining -= 1
	# Small inter-run pause so the next instance gets a clean tick.
	get_tree().create_timer(0.15).timeout.connect(_start_next_run)


# Return the movement Resource WaveDirector would assign to this scene
# in actual combat. Pulls from EnemyRoster.ENTRIES by scene path; bosses
# fall through to a stock BossSweep (matching wave_generator._build_boss_waves).
func _resolve_movement_for(scene_path: String) -> Resource:
	for entry in EnemyRoster.ENTRIES:
		if String(entry.get("scene", "")) == scene_path:
			return EnemyRoster.make_movement(entry)
	# Bosses + anything outside the roster get the boss sweep so they
	# don't read as broken in the test.
	var nm: String = scene_path.get_file().get_basename()
	if nm.begins_with("boss"):
		var bm = BossSweep.new()
		bm.hover_y = 200.0
		bm.enter_speed = 140.0
		bm.sweep_amplitude = 240.0
		bm.sweep_frequency = 0.3
		return bm
	# Last resort — straight-down so the test doesn't silently freeze.
	var Straight = load("res://scripts/enemies/patterns/straight_down.gd")
	var fallback = Straight.new()
	fallback.speed = 220.0
	return fallback


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
