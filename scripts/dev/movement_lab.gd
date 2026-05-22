extends Control

# Movement Lab — preview the five movement patterns (omni / inertial / jet /
# vector / charger) all at once. A pointer ship the user drags around with
# the mouse plays "player", and each test enemy is locked to one pattern so
# Roman can watch behavior in isolation.
#
# Layout: 480×270 viewport with the live playfield band (X 132–348, Y 0–270).
# Left gutter (x 0–132): controls panel. Right gutter (x 348–480): info panel.
# Field area (x 132–348): no background fill, faint 16×16 grid overlay only.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const Playfield = preload("res://scripts/playfield.gd")
const OmniThrust = preload("res://scripts/enemies/patterns/omni_thrust.gd")
const InertialThrust = preload("res://scripts/enemies/patterns/inertial_thrust.gd")
const JetMovement = preload("res://scripts/enemies/patterns/jet.gd")
const JetCharger = preload("res://scripts/enemies/patterns/jet_charger.gd")
const JetVector = preload("res://scripts/enemies/patterns/jet_vector.gd")

# Field covers the full playfield band in viewport coordinates.
const FIELD_RECT := Rect2(132, 0, 216, 270)
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
	# Playfield bounds in field-local coords (field origin = 132, 0).
	# Values: X_MIN - field_x = 132 - 132 = 0; X_MAX - field_x = 348 - 132 = 216;
	# Y_MIN = 0; Y_MAX = 270. (from Playfield constants)
	const CLAMP_X_MIN: float = 0.0
	const CLAMP_X_MAX: float = 216.0
	const CLAMP_Y_MIN: float = 0.0
	const CLAMP_Y_MAX: float = 270.0

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
		# vanish off-canvas. Field origin is at (132, 0) in viewport space,
		# so field-local coords map directly to Playfield width/height.
		position.x = clamp(position.x, CLAMP_X_MIN, CLAMP_X_MAX)
		position.y = clamp(position.y, CLAMP_Y_MIN, CLAMP_Y_MAX)
		# Test-fire check — emit a tracer when nose is on player, capped
		# by FIRE_COOLDOWN so we don't spam.
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
	# Dark full-viewport background.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Left gutter panel: x 0–132, full height 270.
	var left_panel := _make_panel(Vector2(0, 0), Vector2(132, 270))
	add_child(left_panel)
	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 4)
	left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_vb)

	# Header.
	var header := Label.new()
	header.text = "MOVEMENT LAB"
	header.add_theme_font_size_override("font_size", 7)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	# Override font size back to 7 after style_label sets it larger.
	header.add_theme_font_size_override("font_size", 7)
	left_vb.add_child(header)

	# Color legend.
	_add_legend_row(left_vb, "OMNI",     Color(1.0, 0.45, 0.45))
	_add_legend_row(left_vb, "INERTIAL", Color(0.55, 1.0, 0.55))
	_add_legend_row(left_vb, "JET",      Color(0.55, 0.85, 1.0))
	_add_legend_row(left_vb, "VECTOR",   Color(0.85, 0.65, 1.0))
	_add_legend_row(left_vb, "CHARGER",  Color(1.0, 0.85, 0.4))

	# Spacer.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	left_vb.add_child(gap)

	# Buttons.
	_add_button(left_vb, "Reset", _on_reset)
	_add_button(left_vb, "Back",  _on_back)

	# Right gutter panel: x 348–480, full height 270.
	var right_panel := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right_panel)
	var right_vb := VBoxContainer.new()
	right_vb.add_theme_constant_override("separation", 4)
	right_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_vb)

	var right_caption := Label.new()
	right_caption.text = "PATTERNS"
	right_caption.add_theme_font_size_override("font_size", 6)
	UiTheme.style_label(right_caption, UiTheme.LabelKind.CAPTION)
	right_vb.add_child(right_caption)

	var right_note := Label.new()
	right_note.text = "Tune in patterns/*.gd"
	right_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_note.add_theme_font_size_override("font_size", 6)
	right_note.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	right_vb.add_child(right_note)


func _make_panel(pos: Vector2, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.85)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p


func _add_legend_row(parent: Node, text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	row.add_child(lbl)


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.add_theme_font_size_override("font_size", 7)
	UiTheme.style_button(b, true)
	b.pressed.connect(cb)
	parent.add_child(b)


func _build_field() -> void:
	_field = Control.new()
	_field.position = FIELD_RECT.position
	_field.size = FIELD_RECT.size
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_field)
	# No background fill — playfield band shows through the dark viewport bg.
	# Faint 16×16 grid drawn over it.
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
	# Start at centre of the field in field-local coords:
	# (Playfield.X_MAX - Playfield.X_MIN) * 0.5 = 108, (Playfield.Y_MAX - Playfield.Y_MIN) * 0.5 = 135
	_player_marker.position = Vector2(108.0, 135.0)
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
	# Positions are field-local (origin at field x=132, y=0).
	# Spread across the 216×270 field: three top, two mid.
	_enemies.append(_make_enemy("OMNI",     Color(1.0, 0.45, 0.45), OmniThrust.new(),    Vector2(50,  60)))
	_enemies.append(_make_enemy("INERTIAL", Color(0.55, 1.0, 0.55), InertialThrust.new(), Vector2(108, 60)))
	_enemies.append(_make_enemy("JET",      Color(0.55, 0.85, 1.0), JetMovement.new(),   Vector2(166, 60)))
	_enemies.append(_make_enemy("VECTOR",   Color(0.85, 0.65, 1.0), JetVector.new(),     Vector2(50,  160)))
	_enemies.append(_make_enemy("CHARGER",  Color(1.0, 0.85, 0.4),  JetCharger.new(),    Vector2(166, 160)))


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
