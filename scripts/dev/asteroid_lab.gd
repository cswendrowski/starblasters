extends Control

# Asteroid Lab (Roman 2026-05-19). Single procgen asteroid in the center
# of the screen with sliders for every generation knob. Regenerate button
# rolls a new seed. Useful for understanding how the asteroid shader's
# inputs map to the visual output.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"

var _visual: Control = null
var _seed: int = 12345

var _size_slider: HSlider = null
var _pixels_slider: HSlider = null
var _spin_slider: HSlider = null
var _tint_r_slider: HSlider = null
var _tint_g_slider: HSlider = null
var _tint_b_slider: HSlider = null
var _readout: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_regenerate()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Sidebar with sliders on the left, asteroid preview on the right.
	var v := VBoxContainer.new()
	v.position = Vector2(8, 8)
	v.size = Vector2(150, 380)
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var hdr := Label.new()
	hdr.text = "ASTEROID LAB"
	UiTheme.style_label(hdr, UiTheme.LabelKind.HEADER)
	v.add_child(hdr)
	var sub := Label.new()
	sub.text = "Tune the procgen knobs."
	UiTheme.style_label(sub, UiTheme.LabelKind.CAPTION)
	v.add_child(sub)
	v.add_child(HSeparator.new())
	_size_slider = _add_slider(v, "Size (30-160 px)", 30.0, 160.0, 1.0, 60.0)
	_pixels_slider = _add_slider(v, "Pixels (per side)", 30.0, 200.0, 1.0, 60.0)
	_spin_slider = _add_slider(v, "Spin (rad/sec)", -3.0, 3.0, 0.1, 0.0)
	_tint_r_slider = _add_slider(v, "Tint R", 0.5, 1.5, 0.05, 1.20)
	_tint_g_slider = _add_slider(v, "Tint G", 0.5, 1.5, 0.05, 1.05)
	_tint_b_slider = _add_slider(v, "Tint B", 0.5, 1.5, 0.05, 0.85)
	v.add_child(HSeparator.new())
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 10)
	_readout.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	v.add_child(_readout)
	v.add_child(HSeparator.new())
	var regen_btn := Button.new()
	regen_btn.text = "Reroll Seed"
	UiTheme.style_button(regen_btn, true)
	regen_btn.pressed.connect(_on_reroll)
	v.add_child(regen_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	v.add_child(back_btn)


func _add_slider(parent: Container, label: String, lo: float, hi: float, step: float, default_v: float) -> HSlider:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 9)
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = default_v
	s.custom_minimum_size = Vector2(0, 12)
	s.value_changed.connect(_on_slider_changed)
	parent.add_child(s)
	return s


func _on_slider_changed(_v: float) -> void:
	_regenerate()


func _on_reroll() -> void:
	_seed = randi()
	_regenerate()


func _regenerate() -> void:
	# Tear down old visual.
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	var ps = load(PROCGEN_ASTEROID)
	if ps == null:
		return
	var v = ps.instantiate()
	# Per-instance shader material so each seed produces a distinct rock.
	# Targets the INNER Asteroid ColorRect — that's where the shader lives.
	var inner: Control = v.get_node_or_null("Asteroid") as Control
	if inner and inner.material != null:
		inner.material = inner.material.duplicate()
	if v.has_method("set_seed"):
		v.set_seed(_seed)
	# Size is authoritative — it drives both the outer Control rect AND
	# the inner ColorRect rect (which the shader actually paints into).
	# `pixels` is a shader uniform that controls the procgen detail level
	# independently from the display size.
	var size_px: float = float(_size_slider.value)
	if v is Control:
		v.custom_minimum_size = Vector2(size_px, size_px)
		v.size = Vector2(size_px, size_px)
		v.position = Vector2(220 - size_px * 0.5, 220 - size_px * 0.5)
		# Pivot at the centre so rotation spins around the visible midpoint.
		v.pivot_offset = Vector2(size_px * 0.5, size_px * 0.5)
		v.modulate = Color(_tint_r_slider.value, _tint_g_slider.value, _tint_b_slider.value, 1.0)
	# Re-size the inner ColorRect to match outer (otherwise it stays at
	# the .tscn's 100×100 default and the Size slider does nothing
	# visible). Pivot it so any inner rotation also stays centered.
	if inner:
		inner.size = Vector2(size_px, size_px)
		inner.position = Vector2.ZERO
		inner.pivot_offset = Vector2(size_px * 0.5, size_px * 0.5)
	# `pixels` shader uniform — keep separate from display size so the
	# designer can author detail level vs. screen footprint independently.
	# Asteroid.set_pixels also force-resizes the inner ColorRect, so call
	# it AFTER our resize above and re-set the inner size to size_px.
	if v.has_method("set_pixels"):
		v.set_pixels(float(_pixels_slider.value))
	if inner:
		inner.size = Vector2(size_px, size_px)
	v.set_meta("spin", float(_spin_slider.value))
	add_child(v)
	_visual = v
	_update_readout()


func _process(delta: float) -> void:
	if _visual and is_instance_valid(_visual):
		var spin: float = float(_visual.get_meta("spin", 0.0))
		if abs(spin) > 0.001 and _visual is Control:
			_visual.rotation += spin * delta


func _update_readout() -> void:
	if _readout == null:
		return
	_readout.text = "Seed: %d\nSize: %.0f px\nPixels: %.0f\nSpin: %.1f rad/s\nTint: %.2f, %.2f, %.2f" % [
		_seed,
		_size_slider.value,
		_pixels_slider.value,
		_spin_slider.value,
		_tint_r_slider.value, _tint_g_slider.value, _tint_b_slider.value,
	]


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
