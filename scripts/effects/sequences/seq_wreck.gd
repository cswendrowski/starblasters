extends "res://scripts/effects/sequences/sequence_player.gd"

# Wreck sequence — drives the existing wreck-drift hull behavior (descent → tumble → recede/darken
# → engine-fire + smoke → exit-zone explode-or-drop). Reusable standalone (lab "Wreck" mode) AND as
# the slow-death finale handoff (begin_wreck() with a residual velocity). Reparents the body sprite
# into a wreck container and hands it to wreck_drift, tuned by the knobs.

const WreckDrift = preload("res://scripts/effects/wreck_drift.gd")
const FALLBACK_GRADE := Color(0.55, 0.58, 0.66, 1.0)   # the dim recede grade for a bare dev stage

var _container: Node2D = null
var _safety: float = 0.0


static func knob_schema() -> Array:
	return [
		{"key": "init_speed", "label": "Entry speed (px/s)", "min": 0.0, "max": 300.0, "step": 5.0, "def": 120.0},
		{"key": "descent_time", "label": "Descent time (s)", "min": 0.2, "max": 4.0, "step": 0.1, "def": 1.4},
		{"key": "fall_gravity", "label": "Fall gravity", "min": 0.0, "max": 400.0, "step": 5.0, "def": 110.0},
		{"key": "fall_speed_max", "label": "Fall speed max", "min": 50.0, "max": 400.0, "step": 5.0, "def": 190.0},
		{"key": "speed_loss_end", "label": "Speed kept @end", "min": 0.3, "max": 1.0, "step": 0.02, "def": 0.8},
		{"key": "spin_min", "label": "Spin min (rad/s)", "min": 0.0, "max": 3.0, "step": 0.05, "def": 0.3},
		{"key": "spin_max", "label": "Spin max (rad/s)", "min": 0.0, "max": 4.0, "step": 0.05, "def": 1.25},
		{"key": "spin_ease", "label": "Spin ease-in", "min": 0.5, "max": 6.0, "step": 0.1, "def": 2.6},
		{"key": "wreck_scale", "label": "Recede scale", "min": 0.3, "max": 1.0, "step": 0.02, "def": 0.72},
		{"key": "scale_time", "label": "Recede time (s)", "min": 0.3, "max": 4.0, "step": 0.1, "def": 1.4},
		{"key": "recede_darken", "label": "Recede darken", "min": 0.4, "max": 1.0, "step": 0.02, "def": 0.9},
		{"key": "exit_explode_chance", "label": "Exit explode %", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.7},
	]


func _begin() -> void:
	if sprite == null or not is_instance_valid(sprite):
		_finish()
		return
	begin_wreck(Vector2(0.0, k("init_speed", 120.0)))


# Public so the slow-death finale can hand off with its own residual velocity. Reparents the hull
# into a fresh container and attaches wreck_drift (tuned by the knobs).
func begin_wreck(init_vel: Vector2) -> void:
	if sprite == null or not is_instance_valid(sprite):
		_finish()
		return
	var host: Node = (target.get_parent() if target != null and is_instance_valid(target) else get_parent())
	if host == null:
		host = get_parent()
	_container = Node2D.new()
	_container.name = "WreckContainer"
	_container.modulate = FALLBACK_GRADE   # recede grade (matches wreck_layer's bare-scene fallback)
	host.add_child(_container)
	# Capture world transform + emit points (engine markers + hull centre) BEFORE reparenting.
	var gpos: Vector2 = sprite.global_position
	var grot: float = sprite.global_rotation
	var gscl: Vector2 = sprite.global_scale
	var emit_worlds: Array = [sprite.global_position]
	if target != null and is_instance_valid(target):
		for mk in target.find_children("Engine*", "Marker2D", true, false):
			if mk is Node2D:
				emit_worlds.append((mk as Node2D).global_position)
	# Battered-hull look (matches enemy_base._die_as_wreck).
	if sprite.material is ShaderMaterial:
		var m: ShaderMaterial = sprite.material
		m.set_shader_parameter("flash_strength", 0.0)
		m.set_shader_parameter("sensitivity", 0.75)
	# Reparent the hull into the container (world transform preserved).
	var sp_parent: Node = sprite.get_parent()
	if sp_parent != null:
		sp_parent.remove_child(sprite)
	_container.add_child(sprite)
	sprite.global_position = gpos
	sprite.rotation = grot
	sprite.global_scale = gscl
	sprite.z_index = 0
	var emit_local: Array = []
	for w in emit_worlds:
		emit_local.append(sprite.to_local(w))
	WreckDrift.attach(sprite, init_vel, randi(), k("exit_explode_chance", 0.7), emit_local, _wreck_cfg())
	_safety = 0.0


func _wreck_cfg() -> Dictionary:
	return {
		"descent_time": k("descent_time", 1.4),
		"fall_gravity": k("fall_gravity", 110.0),
		"fall_speed_max": k("fall_speed_max", 190.0),
		"speed_loss_end": k("speed_loss_end", 0.8),
		"spin_min": k("spin_min", 0.3),
		"spin_max": k("spin_max", 1.25),
		"spin_ease": k("spin_ease", 2.6),
		"wreck_scale": k("wreck_scale", 0.72),
		"scale_time": k("scale_time", 1.4),
		"recede_darken": k("recede_darken", 0.9),
	}


func _on_tick(_elapsed: float, delta: float) -> void:
	# wreck_drift owns the motion + frees the hull at the exit zone; we finish when it's gone (or a
	# safety timeout in case it never reaches the exit).
	_safety += delta
	if sprite == null or not is_instance_valid(sprite) or _safety > 14.0:
		_finish()


func _finish() -> void:
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
	super._finish()
