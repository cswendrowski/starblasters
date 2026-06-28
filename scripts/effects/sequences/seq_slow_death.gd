extends "res://scripts/effects/sequences/sequence_player.gd"

# Large-ship slow death (Roman 2026-06-12) — the dramatic death for a big hull: its movement SLOWS,
# it LISTS (tilts) to one side, the LIGHTS GO OUT (darken), and SECONDARY EXPLOSIONS pop across
# random weighted markers (engines favoured). At `handoff_at` it HANDS OFF to the wreck layer —
# the listed, darkened hull becomes a drifting wreck that recedes + exits (seq_wreck).

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const SeqWreck = preload("res://scripts/effects/sequences/seq_wreck.gd")

var _markers: Array = []        # [{node: Marker2D|null, weight: float}] — node null = hull centre
var _blast_times: Array = []
var _list_dir: float = 1.0
var _handed_off: bool = false


static func knob_schema() -> Array:
	return [
		{"key": "enter_speed", "label": "Entry speed (px/s)", "min": 0.0, "max": 200.0, "step": 5.0, "def": 60.0},
		{"key": "slow_to", "label": "Slow to (× speed)", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.25},
		{"key": "slow_dur", "label": "Slow time (s)", "min": 0.5, "max": 5.0, "step": 0.1, "def": 2.2},
		{"key": "list_angle", "label": "List angle (deg)", "min": 0.0, "max": 45.0, "step": 1.0, "def": 14.0},
		{"key": "list_dur", "label": "List time (s)", "min": 0.5, "max": 5.0, "step": 0.1, "def": 2.4},
		{"key": "darken_to", "label": "Lights-out to", "min": 0.1, "max": 1.0, "step": 0.02, "def": 0.45},
		{"key": "darken_dur", "label": "Lights-out time (s)", "min": 0.3, "max": 5.0, "step": 0.1, "def": 2.0},
		{"key": "blast_count", "label": "Secondary blasts", "min": 0.0, "max": 12.0, "step": 1.0, "def": 6.0},
		{"key": "blast_window", "label": "Blast window (s)", "min": 0.5, "max": 5.0, "step": 0.1, "def": 2.6},
		{"key": "handoff_at", "label": "Wreck handoff @ (s)", "min": 1.0, "max": 6.0, "step": 0.1, "def": 2.8},
	]


func _begin() -> void:
	if target == null:
		_finish()
		return
	_list_dir = 1.0 if randf() < 0.5 else -1.0
	# Weighted markers (engines 3×, muzzles/cannons/turrets 1×, hull centre always).
	_markers.clear()
	for m in target.find_children("Engine*", "Marker2D", true, false):
		if m is Node2D:
			_markers.append({"node": m, "weight": 3.0})
	for pat in ["Muzzle*", "Cannon*", "Turret*"]:
		for m in target.find_children(pat, "Marker2D", true, false):
			if m is Node2D:
				_markers.append({"node": m, "weight": 1.0})
	_markers.append({"node": null, "weight": 1.0})   # centre fallback
	# Random blast schedule across the window.
	_blast_times.clear()
	var n: int = maxi(0, int(k("blast_count", 6.0)))
	var win: float = k("blast_window", 2.6)
	for i in n:
		_blast_times.append(randf() * win)
	_blast_times.sort()


func _on_tick(t: float, delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_finish()
		return
	if _handed_off:
		return   # the wreck is playing; we finish when it does (signal-connected)
	# 1) Slow the downward movement from enter_speed toward enter_speed × slow_to.
	var slow_f: float = clampf(t / maxf(0.01, k("slow_dur", 2.2)), 0.0, 1.0)
	var enter: float = k("enter_speed", 60.0)
	var spd: float = lerpf(enter, enter * k("slow_to", 0.25), slow_f)
	target.position += Vector2(0.0, spd) * delta
	# 2) List (tilt) to one side, ease-out.
	var list_f: float = clampf(t / maxf(0.01, k("list_dur", 2.4)), 0.0, 1.0)
	target.rotation = deg_to_rad(k("list_angle", 14.0)) * _list_dir * (1.0 - pow(1.0 - list_f, 2.0))
	# 3) Lights out — darken the whole hull.
	var dk: float = clampf(t / maxf(0.01, k("darken_dur", 2.0)), 0.0, 1.0)
	var b: float = lerpf(1.0, k("darken_to", 0.45), dk)
	target.modulate = Color(b, b, b, target.modulate.a)
	# 4) Secondary explosions at weighted markers.
	for i in _blast_times.size():
		var bt: float = float(_blast_times[i])
		if bt >= 0.0 and t >= bt:
			_blast_times[i] = -1.0
			_blast_at_marker()
	# 5) Hand off to the wreck layer.
	if t >= k("handoff_at", 2.8):
		_hand_off(spd)


func _blast_at_marker() -> void:
	if _markers.is_empty():
		return
	var total: float = 0.0
	for md in _markers:
		total += float(md["weight"])
	var r: float = randf() * total
	var chosen: Dictionary = _markers[_markers.size() - 1]
	for md in _markers:
		r -= float(md["weight"])
		if r <= 0.0:
			chosen = md
			break
	var node = chosen.get("node")
	var pos: Vector2 = target.global_position
	if node != null and is_instance_valid(node):
		pos = (node as Node2D).global_position
	ExplosionFx.play(pos, 1.0, true, _fx_parent())


# Hand the listed, darkened hull to the wreck sequence with its residual downward speed.
func _hand_off(residual_speed: float) -> void:
	if _handed_off:
		return
	_handed_off = true
	if sprite == null or not is_instance_valid(sprite):
		_finish()
		return
	var w = SeqWreck.new()
	var wknobs: Dictionary = {}
	for s in SeqWreck.knob_schema():
		wknobs[String(s["key"])] = float(s["def"])
	wknobs["init_speed"] = maxf(residual_speed, 40.0)
	var host: Node = get_parent() if get_parent() != null else target
	host.add_child(w)
	w.finished.connect(_finish)
	w.play(target, sprite, wknobs)


func _fx_parent() -> Node:
	return get_parent() if get_parent() != null else target
