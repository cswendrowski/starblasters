extends Control

# Movement Lab — preview the three new movement patterns
# (omnidirectional / inertial / jet) all at once. A pointer ship the user
# drags around with the mouse plays "player", and each test enemy is
# locked to one pattern so Roman can watch behavior in isolation.
#
# Build pattern:
#   - Three labeled enemy stubs, each running one of the three patterns.
#   - One Node2D in group "player" that follows the mouse — the patterns
#     read this via `get_tree().get_nodes_in_group("player")`.
#   - A reset button to re-randomize spawn positions, plus speed knobs
#     so the patterns can be tuned without rebuilding.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const OmniThrust = preload("res://scripts/enemies/patterns/omni_thrust.gd")
const InertialThrust = preload("res://scripts/enemies/patterns/inertial_thrust.gd")
const JetMovement = preload("res://scripts/enemies/patterns/jet.gd")
const JetCharger = preload("res://scripts/enemies/patterns/jet_charger.gd")
const JetVector = preload("res://scripts/enemies/patterns/jet_vector.gd")

const FIELD_RECT := Rect2(8, 24, 200, 352)
const ENEMY_SIZE := Vector2(14, 14)
const POINTER_SIZE := Vector2(10, 10)

# An enemy stub — minimal Node2D that exposes the few fields the
# MovementPatterns read (auto_rotate). Each enemy holds its own pattern
# instance and ticks it every frame.
#
# Adds a "test fire" pulse — when the body's nose points at the player
# (within a tolerance), it emits a tracer Line2D the user can see.
class TestEnemy extends Node2D:
	var pattern = null
	var label_text: String = "?"
	var color: Color = Color(1, 1, 1)
	var auto_rotate: bool = false
	var _body: Polygon2D = null
	var _label: Label = null
	var _fire_t: float = 0.0
	const FIRE_COOLDOWN: float = 0.6
	const FIRE_TOL_DEG: float = 12.0

	func _ready() -> void:
		_body = Polygon2D.new()
		_body.polygon = PackedVector2Array([
			Vector2(0, -8),
			Vector2(-6, 6),
			Vector2(0, 3),
			Vector2(6, 6),
		])
		_body.color = color
		add_child(_body)
		_label = Label.new()
		_label.text = label_text
		_label.add_theme_font_size_override("font_size", 7)
		_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		_label.position = Vector2(-30, -22)
		_label.size = Vector2(60, 10)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_label)
		if pattern and pattern.has_method("on_start"):
			pattern.on_start(self)

	func _process(delta: float) -> void:
		if pattern == null:
			return
		var step: Vector2 = pattern.compute_step(self, delta)
		position += step
		# Hard playfield clamp so a pattern that wants to flee doesn't
		# vanish off-canvas. Mirrors what boss.gd does in combat.
		position.x = clamp(position.x, 8.0, 192.0)
		position.y = clamp(position.y, 8.0, 344.0)
		# Test-fire check — emit a tracer when nose is on player, capped
		# by FIRE_COOLDOWN so we don't spam (Roman, 2026-05-17 Movement
		# Lab: "have each of these enemies fire a shot at the player when
		# their nose is pointed at them").
		_fire_t -= delta
		if _fire_t <= 0.0:
			var player := _find_player()
			if player:
				var to_p: Vector2 = player.global_position - global_position
				var rot: float = rotation - PI * 0.5
				var fwd: Vector2 = Vector2(cos(rot), sin(rot))
				if to_p.length_squared() > 1.0 and fwd.dot(to_p.normalized()) > cos(deg_to_rad(FIRE_TOL_DEG)):
					_emit_tracer(player.global_position)
					_fire_t = FIRE_COOLDOWN

	func _find_player() -> Node:
		for n in get_tree().get_nodes_in_group("player"):
			return n
		return null

	func _emit_tracer(target_pos: Vector2) -> void:
		var line := Line2D.new()
		line.add_point(global_position)
		line.add_point(target_pos)
		line.width = 1.5
		line.default_color = Color(color.r, color.g, color.b, 0.9)
		get_parent().add_child(line)
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.18)
		tw.tween_callback(line.queue_free)


var _field: Control = null
var _player_marker: Node2D = null
var _enemies: Array = []


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_build_ui()
	_build_field()
	_spawn_player_marker()
	_spawn_enemies()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header := Label.new()
	header.text = "MOVEMENT LAB"
	header.position = Vector2(8, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	add_child(header)

	var hint := Label.new()
	hint.text = "Move mouse — enemies chase pointer"
	hint.position = Vector2(8, 380)
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	add_child(hint)

	var back := Button.new()
	back.text = "Back to Dev Menu"
	back.position = Vector2(214, 376)
	back.size = Vector2(100, 18)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	add_child(back)

	# Reset button — re-randomize spawn positions.
	var reset := Button.new()
	reset.text = "Reset Positions"
	reset.position = Vector2(214, 26)
	reset.size = Vector2(100, 18)
	UiTheme.style_button(reset, true)
	reset.pressed.connect(_on_reset)
	add_child(reset)

	# Legend.
	_add_legend("OMNI",     Color(1.0, 0.45, 0.45), Vector2(214, 60))
	_add_legend("INERTIAL", Color(0.55, 1.0, 0.55), Vector2(214, 74))
	_add_legend("JET",      Color(0.55, 0.85, 1.0), Vector2(214, 88))
	_add_legend("VECTOR",   Color(0.85, 0.65, 1.0), Vector2(214, 102))
	_add_legend("CHARGER",  Color(1.0, 0.85, 0.4), Vector2(214, 116))

	# Tunables hint.
	var note := Label.new()
	note.text = "Tune in patterns/*.gd:\nomni_thrust  inertial_thrust  jet"
	note.position = Vector2(214, 116)
	note.size = Vector2(100, 60)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 7)
	note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	add_child(note)


func _add_legend(text: String, color: Color, pos: Vector2) -> void:
	var dot := ColorRect.new()
	dot.color = color
	dot.position = pos
	dot.size = Vector2(8, 8)
	add_child(dot)
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos + Vector2(12, -3)
	lbl.size = Vector2(98, 12)
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	add_child(lbl)


func _build_field() -> void:
	_field = Control.new()
	_field.position = FIELD_RECT.position
	_field.size = FIELD_RECT.size
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_field)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.16, 1.0)
	bg.size = FIELD_RECT.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(bg)
	# Faint grid.
	var grid := Node2D.new()
	grid.draw.connect(_draw_grid.bind(grid))
	_field.add_child(grid)


func _draw_grid(canvas: Node2D) -> void:
	var c := Color(1, 1, 1, 0.05)
	for x in range(0, int(FIELD_RECT.size.x), 16):
		canvas.draw_line(Vector2(x, 0), Vector2(x, FIELD_RECT.size.y), c, 1.0)
	for y in range(0, int(FIELD_RECT.size.y), 16):
		canvas.draw_line(Vector2(0, y), Vector2(FIELD_RECT.size.x, y), c, 1.0)


func _spawn_player_marker() -> void:
	# A pointer Node2D in group "player" so the enemy patterns find it via
	# their existing `get_nodes_in_group("player")` lookup.
	_player_marker = Node2D.new()
	_player_marker.name = "PlayerPointer"
	_player_marker.add_to_group("player")
	_player_marker.position = FIELD_RECT.size * 0.5
	_field.add_child(_player_marker)
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	var sides: int = 12
	for i in sides:
		var a: float = float(i) / float(sides) * TAU
		pts.append(Vector2(cos(a), sin(a)) * 6.0)
	ring.polygon = pts
	ring.color = Color(1.0, 0.95, 0.55, 0.85)
	_player_marker.add_child(ring)


func _spawn_enemies() -> void:
	_clear_enemies()
	_enemies.append(_make_enemy("OMNI", Color(1.0, 0.45, 0.45), OmniThrust.new(), Vector2(30, 60)))
	_enemies.append(_make_enemy("INERTIAL", Color(0.55, 1.0, 0.55), InertialThrust.new(), Vector2(80, 60)))
	_enemies.append(_make_enemy("JET", Color(0.55, 0.85, 1.0), JetMovement.new(), Vector2(130, 60)))
	_enemies.append(_make_enemy("VECTOR", Color(0.85, 0.65, 1.0), JetVector.new(), Vector2(30, 200)))
	_enemies.append(_make_enemy("CHARGER", Color(1.0, 0.85, 0.4), JetCharger.new(), Vector2(130, 200)))


func _make_enemy(label: String, color: Color, pattern, spawn_pos: Vector2):
	var e = TestEnemy.new()
	e.label_text = label
	e.color = color
	e.pattern = pattern
	e.position = spawn_pos
	_field.add_child(e)
	return e


func _clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies = []


func _process(_delta: float) -> void:
	# Mouse moves the player pointer (clamped to the field).
	if _player_marker == null or _field == null:
		return
	var local: Vector2 = _field.get_local_mouse_position()
	local.x = clamp(local.x, 4.0, FIELD_RECT.size.x - 4.0)
	local.y = clamp(local.y, 4.0, FIELD_RECT.size.y - 4.0)
	_player_marker.position = local


func _on_reset() -> void:
	_spawn_enemies()


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
