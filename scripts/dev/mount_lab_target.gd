extends Area2D

# Smart Mount Lab target — a lightweight drifting dummy the auto-turrets lock onto + kill.
# Sweeps laterally (sine) and drifts slowly down; respawns at the top with a fresh lane +
# velocity when killed or when it exits the playfield. Lives in the "enemies" group so
# player.gd `_mount_target()` acquires it and player bullets collide with it.

const Playfield = preload("res://scripts/playfield.gd")

var hp: int = 6
var speed_scale: float = 1.0   # lab knob — scales drift speed

var _vy: float = 30.0
var _phase: float = 0.0
var _amp: float = 0.0
var _base_x: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	var spr := Sprite2D.new()
	var tex: Texture2D = load("res://graphics/extra-ships/ship_2.png")
	if tex == null:
		tex = load("res://graphics/extra-ships/ship_1.png")
	if tex:
		spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 14)
	shape.shape = rect
	add_child(shape)
	_respawn()


# Player bullets call take_hit(dmg) on "enemies"-group Area2Ds.
func take_hit(dmg: int) -> void:
	hp -= dmg
	if hp <= 0:
		_respawn()
		return
	modulate = Color(2.2, 2.2, 2.2)   # brief HDR flash
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.12)


func _process(delta: float) -> void:
	_phase += delta * 2.0
	position.x = clampf(_base_x + sin(_phase) * _amp, Playfield.X_MIN + 8.0, Playfield.X_MAX - 8.0)
	position.y += _vy * speed_scale * delta
	if position.y > Playfield.Y_MAX + 20.0:
		_respawn()


func _respawn() -> void:
	hp = 6
	modulate = Color(1, 1, 1)
	_base_x = randf_range(Playfield.X_MIN + 16.0, Playfield.X_MAX - 16.0)
	_amp = randf_range(0.0, (Playfield.W * 0.5) - 16.0)
	_phase = randf_range(0.0, TAU)
	_vy = randf_range(15.0, 45.0)
	position = Vector2(_base_x, Playfield.Y_MIN - randf_range(0.0, 60.0))
