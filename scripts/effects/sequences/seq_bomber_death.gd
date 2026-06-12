extends "res://scripts/effects/sequences/sequence_player.gd"

# Bomber death — lifted from the legacy enemy_bomber_wing._run_bomber_death (Roman 2026-05-18) and
# parameterized: the bomber keeps its downward momentum and slumps off the bottom while it DARKENS,
# SHRINKS, and fires a cascade of jittered explosions. Drives the whole TARGET (modulate/scale/pos).

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")

var _start_scale: Vector2 = Vector2.ONE
var _v: Vector2 = Vector2.ZERO
var _blast_times: Array = []


static func knob_schema() -> Array:
	return [
		{"key": "enter_speed", "label": "Entry speed (px/s)", "min": 20.0, "max": 300.0, "step": 5.0, "def": 96.0},
		{"key": "decel", "label": "Deceleration", "min": 0.0, "max": 60.0, "step": 1.0, "def": 14.0},
		{"key": "min_drift", "label": "Min drift speed", "min": 20.0, "max": 200.0, "step": 5.0, "def": 70.0},
		{"key": "darken_to", "label": "Darken to", "min": 0.1, "max": 1.0, "step": 0.02, "def": 0.4},
		{"key": "darken_dur", "label": "Darken time (s)", "min": 0.3, "max": 4.0, "step": 0.1, "def": 1.8},
		{"key": "shrink_to", "label": "Shrink to (×)", "min": 0.4, "max": 1.0, "step": 0.02, "def": 0.7},
		{"key": "shrink_dur", "label": "Shrink time (s)", "min": 0.5, "max": 6.0, "step": 0.1, "def": 3.5},
		{"key": "blast_count", "label": "Blast count", "min": 1.0, "max": 10.0, "step": 1.0, "def": 4.0},
		{"key": "blast_window", "label": "Blast window (s)", "min": 0.3, "max": 4.0, "step": 0.1, "def": 1.8},
		{"key": "max_dur", "label": "Max duration (s)", "min": 1.0, "max": 8.0, "step": 0.5, "def": 6.0},
	]


func _begin() -> void:
	if target == null:
		_finish()
		return
	_start_scale = target.scale
	_v = Vector2(0.0, k("enter_speed", 96.0) * 1.6)   # keep 1.6× downward momentum (original)
	# Evenly-spaced blast schedule across the window.
	_blast_times.clear()
	var n: int = maxi(1, int(k("blast_count", 4.0)))
	var win: float = k("blast_window", 1.8)
	for i in n:
		_blast_times.append((float(i) / float(n)) * win)


func _on_tick(t: float, delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_finish()
		return
	# Momentum slump.
	_v.y = maxf(k("min_drift", 70.0), _v.y - k("decel", 14.0) * delta)
	_v.x *= 0.96
	target.position += _v * delta
	# Darken.
	var dk: float = clampf(t / maxf(0.01, k("darken_dur", 1.8)), 0.0, 1.0)
	var b: float = lerpf(1.0, k("darken_to", 0.4), dk)
	target.modulate = Color(b, b, b, target.modulate.a)
	# Shrink (ease-out).
	var sh: float = clampf(t / maxf(0.01, k("shrink_dur", 3.5)), 0.0, 1.0)
	var sh_e: float = 1.0 - pow(1.0 - sh, 2.0)
	target.scale = _start_scale.lerp(_start_scale * k("shrink_to", 0.7), sh_e)
	# Blast cascade (jittered, 1× explosions).
	for i in _blast_times.size():
		var bt: float = float(_blast_times[i])
		if bt >= 0.0 and t >= bt:
			_blast_times[i] = -1.0
			var jit := Vector2(randf_range(-16.0, 16.0), randf_range(-12.0, 12.0))
			ExplosionFx.play(target.global_position + jit, 1.0, true, _fx_parent())
	# Exit when off the bottom or past max duration.
	if t >= k("max_dur", 6.0) or target.global_position.y > 270.0 + 60.0:
		_finish()


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else target
