extends RefCounted
class_name HudLight

enum Pattern { STEADY, BLINK, PULSE, FLICKER }


static func apply(node: CanvasItem, pattern: Pattern) -> void:
	stop(node)
	if not is_instance_valid(node):
		return
	match pattern:
		Pattern.STEADY:
			node.modulate.a = 1.0
		Pattern.BLINK:
			var t := node.create_tween().set_loops()
			t.tween_property(node, "modulate:a", 1.0, 0.0)
			t.tween_interval(1.0)
			t.tween_property(node, "modulate:a", 0.05, 0.0)
			t.tween_interval(1.0)
			node.set_meta("_hlt", t)
		Pattern.PULSE:
			var t := node.create_tween().set_loops()
			t.tween_property(node, "modulate:a", 0.2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.tween_property(node, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			node.set_meta("_hlt", t)
		Pattern.FLICKER:
			var rng := RandomNumberGenerator.new()
			rng.seed = node.get_instance_id()
			var t := node.create_tween().set_loops()
			for _i in 16:
				var alpha: float = 1.0 if rng.randf() > 0.3 else rng.randf_range(0.05, 0.4)
				var dur: float = rng.randf_range(0.04, 0.18)
				t.tween_property(node, "modulate:a", alpha, dur)
			node.set_meta("_hlt", t)


static func stop(node: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	if node.has_meta("_hlt"):
		var t: Tween = node.get_meta("_hlt")
		if t != null and t.is_valid():
			t.kill()
		node.remove_meta("_hlt")
	node.modulate = Color.WHITE


static func hit_flash(node: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	var base_color := node.modulate
	# Flash tween runs concurrently with any active pattern tween.
	# Since it is newer, its modulate writes dominate for ~0.4s, after which
	# the pattern tween resumes naturally (last-write-wins per frame in Godot 4).
	var t := node.create_tween()
	# Instant white-bright flash
	t.tween_callback(func(): node.modulate = Color(1.5, 1.5, 1.5, 1.0))
	# Fade back to base color
	t.tween_property(node, "modulate", base_color, 0.08).set_trans(Tween.TRANS_SINE)
	# Rapid double flicker
	t.tween_property(node, "modulate:a", 0.05, 0.06)
	t.tween_property(node, "modulate:a", 1.0, 0.06)
	t.tween_property(node, "modulate:a", 0.05, 0.06)
	t.tween_property(node, "modulate:a", 1.0, 0.08)


static func pip_flash(container: CanvasItem) -> void:
	if not is_instance_valid(container):
		return
	var base_color := container.modulate
	var t := container.create_tween()
	t.tween_property(container, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.03)
	t.tween_property(container, "modulate", base_color, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
