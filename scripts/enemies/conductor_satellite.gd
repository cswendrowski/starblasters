extends Area2D

# Conductor satellite drone — orbits the boss core with its own HP. Mirrors
# player X on top of the orbit motion. Fires a telegraphed 3-shot aimed
# burst on cadence. Notifies the boss on death so the boss can phase-gate.

signal satellite_killed

var hp: int = 100
var max_hp: int = 100
var is_hazard: bool = true  # don't gate wave-clear on me

# Configured by the boss on spawn.
var boss_ref: Node2D = null
var orbit_radius: float = 24.0
var orbit_speed: float = 1.8  # rad/s
var orbit_phase: float = 0.0
var mirror_strength: float = 0.6

var _t: float = 0.0
var _fire_t: float = 0.0
var _fire_cadence: float = 1.4
var _next_telegraph: float = 0.7  # next fire happens after telegraph window


func _ready() -> void:
	# Stagger first fire so satellites don't shoot simultaneously.
	_fire_t = orbit_phase * 0.3


func _process(delta: float) -> void:
	if not is_instance_valid(boss_ref):
		return
	_t += delta
	var angle: float = orbit_phase + _t * orbit_speed
	var orbit_pos: Vector2 = Vector2.from_angle(angle) * orbit_radius
	# Mirror player X — slide left/right with the player on top of orbit.
	var player_offset_x: float = 0.0
	var p: Node = null
	for n in get_tree().get_nodes_in_group("player"):
		p = n
		break
	if p != null and p is Node2D:
		player_offset_x = ((p as Node2D).global_position.x - boss_ref.global_position.x) * mirror_strength
	global_position = boss_ref.global_position + orbit_pos + Vector2(player_offset_x, 0)

	# Fire cadence.
	_fire_t += delta
	if _fire_t >= _fire_cadence - _next_telegraph and _fire_t < _fire_cadence:
		# Telegraph window — show red dot on the projected aim point once.
		if not has_meta("telegraphed_this_cycle"):
			set_meta("telegraphed_this_cycle", true)
			_show_aim_telegraph()
	if _fire_t >= _fire_cadence:
		_fire_t = 0.0
		set_meta("telegraphed_this_cycle", false)
		_fire_burst()


func _show_aim_telegraph() -> void:
	var p: Node = null
	for n in get_tree().get_nodes_in_group("player"):
		p = n
		break
	if p == null or not (p is Node2D):
		return
	var dot := ColorRect.new()
	dot.color = Color(1.0, 0.4, 0.4, 0.0)
	dot.size = Vector2(6, 6)
	dot.position = -dot.size * 0.5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(p as Node2D).add_child(dot)
	var tw := dot.create_tween()
	tw.tween_property(dot, "color:a", 0.85, _next_telegraph * 0.5)
	tw.tween_property(dot, "color:a", 0.0, _next_telegraph * 0.5)
	tw.tween_callback(dot.queue_free)


func _fire_burst() -> void:
	var p: Node = null
	for n in get_tree().get_nodes_in_group("player"):
		p = n
		break
	if p == null or not (p is Node2D):
		return
	var aim: Vector2 = ((p as Node2D).global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(0, 1)
	var bs: PackedScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
	var spread_rad: float = deg_to_rad(8.0)
	for i in 3:
		var t: float = (float(i) - 1.0)  # -1, 0, 1
		var dir: Vector2 = aim.rotated(t * spread_rad * 0.5)
		var b = bs.instantiate()
		get_tree().root.add_child(b)
		if b.has_method("start"):
			b.start(global_position, dir)
		else:
			b.global_position = global_position


func take_hit(damage: int = 1) -> bool:
	if hp <= 0:
		return false
	hp -= damage
	if has_node("Sprite2D"):
		var spr := $Sprite2D as Sprite2D
		var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
		HitFlashFx.flash(spr, HitFlashFx.FLASH_WHITE)
	if hp <= 0:
		var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
		ExplosionFx.burst(global_position, 3, 14.0, 0.06)
		satellite_killed.emit()
		queue_free()
		return true
	return false
