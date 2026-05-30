extends Control

# Demo scene showing HUD light pattern animations
# Patterns: STEADY, BLINK, PULSE, FLICKER, SHIELD_HIT

const COLOR_GREEN := Color(0.55, 1.00, 0.50)
const COLOR_SHIELD := Color(0.35, 0.65, 1.00)
const DOT_W := 8
const DOT_H := 8

var _rng := RandomNumberGenerator.new()
var _shield_hit_triggered := false


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_window().size = Vector2i(480, 270)
	
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	move_child(bg, 0)
	
	# Font for labels
	var font := load("res://graphics/fonts/PixelOperator.ttf")
	var font_size := 7
	
	# Patterns to display
	var patterns: Array[Dictionary] = [
		{"name": "STEADY", "y": 135},
		{"name": "BLINK", "y": 135},
		{"name": "PULSE", "y": 135},
		{"name": "FLICKER", "y": 135},
		{"name": "SHIELD_HIT", "y": 160},
	]
	
	# Center the dots horizontally with 80px spacing
	var center_x := 240
	var spacing := 80
	var start_x := center_x - (spacing * 2)  # 5 dots: -2, -1, 0, 1, 2
	
	for idx in range(patterns.size()):
		var pattern: Dictionary = patterns[idx]
		var dot_x := start_x + idx * spacing
		
		# Label above dot
		var label := Label.new()
		label.text = pattern["name"]
		label.position = Vector2(dot_x - 20, 120)
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", font_size)
		label.modulate = Color.WHITE
		add_child(label)
		
		if pattern["name"] == "SHIELD_HIT":
			_setup_shield_hit_demo(dot_x, pattern["y"], font, font_size)
		else:
			var dot := _create_dot(dot_x, pattern["y"], COLOR_GREEN)
			_setup_pattern_animation(dot, pattern["name"])
	
	# Trigger shield hit at 1.0s
	get_tree().create_timer(1.0).timeout.connect(_trigger_shield_hit)


func _create_dot(x: float, y: float, tint: Color) -> TextureRect:
	var dot := TextureRect.new()
	dot.texture = load("res://graphics/ui/hud_dot_light.png")
	dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot.custom_minimum_size = Vector2(DOT_W, DOT_H)
	dot.position = Vector2(x - DOT_W / 2.0, y - DOT_H / 2.0)
	dot.modulate = tint
	add_child(dot)
	return dot


func _setup_pattern_animation(dot: TextureRect, pattern_name: String) -> void:
	match pattern_name:
		"STEADY":
			# Always on, no animation
			pass
		"BLINK":
			var tw := create_tween()
			tw.set_loops()
			tw.tween_property(dot, "modulate:a", 0.05, 0.5)
			tw.tween_property(dot, "modulate:a", 1.0, 0.5)
		"PULSE":
			var tw := create_tween()
			tw.set_loops()
			tw.tween_property(dot, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(dot, "modulate:a", 0.2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		"FLICKER":
			_setup_flicker(dot)


func _setup_flicker(dot: TextureRect) -> void:
	_rng.seed = 12345
	var tw := create_tween()
	tw.set_loops()
	
	for _i in range(16):
		var alpha := 1.0 if _rng.randf() > 0.3 else _rng.randf_range(0.05, 0.4)
		var dur := _rng.randf_range(0.04, 0.18)
		tw.tween_property(dot, "modulate:a", alpha, dur)


func _setup_shield_hit_demo(x: float, y: float, font: Font, font_size: int) -> void:
	# Create indicator dot above the pips
	var indicator := _create_dot(x, y - 40, COLOR_SHIELD)
	indicator.name = "shield_indicator"
	
	# Create a container for the pip row (5 pips)
	var pip_container := Control.new()
	pip_container.position = Vector2(x - 20, y)  # 5 pips * 8px width / 2
	pip_container.name = "pip_container"
	add_child(pip_container)
	
	var pip_spacing := 8
	for i in range(5):
		var pip := _create_dot(i * pip_spacing, 0, COLOR_SHIELD)
		pip.reparent(pip_container)


func _trigger_shield_hit() -> void:
	if _shield_hit_triggered:
		return
	_shield_hit_triggered = true
	
	var indicator: Node = find_child("shield_indicator", true, false)
	var pip_container: Node = find_child("pip_container", true, false)
	
	if pip_container:
		# Flash the pip container (brightness increase)
		var tw_container := create_tween()
		tw_container.tween_property(pip_container, "modulate", Color(2, 2, 2, 1), 0.02)
		tw_container.tween_property(pip_container, "modulate", Color(1, 1, 1, 1), 0.15)
	
	if indicator:
		# Rapid flicker on the indicator dot: 1.0 → 0.0 → 1.0 → 0.0 → 1.0 pattern
		var tw_indicator := create_tween()
		tw_indicator.tween_property(indicator, "modulate:a", 0.0, 0.05)
		tw_indicator.tween_property(indicator, "modulate:a", 1.0, 0.05)
		tw_indicator.tween_property(indicator, "modulate:a", 0.0, 0.05)
		tw_indicator.tween_property(indicator, "modulate:a", 1.0, 0.1)
