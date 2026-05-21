extends Control

# Asteroid Lab (Roman 2026-05-19, Cody 2026-05-19 tweaks). Single procgen
# asteroid in the centre of the screen with sliders for every generation
# knob. Useful for understanding how the asteroid shader's inputs map
# to the visual output.
#
# Cody 2026-05-19 tweaks:
#   - Tint sliders apply to the INNER ColorRect (the shader-bearing
#     node) so the modulate actually reaches the rendered pixels.
#   - Numeric value readout next to each slider — updated on change.
#   - "Generate New Asteroid" button reseeds + rebuilds.
#   - Sliders + fonts ~25% smaller for a tighter rail.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"

# Cody's 25%-smaller pass — used by the slider/label rows below.
const FONT_HDR := 10   # was 16 → 12 → 10 (another 20%)
const FONT_LBL := 6    # was 9 → 7 → 6
const FONT_VAL := 6    # numeric readout
const SLIDER_H := 7    # was 12 → 9 → 7

# Asteroid centred in the right half of the 480×270 viewport so the
# slider rail on the left doesn't crowd the preview.
const ASTEROID_CENTER := Vector2(360.0, 135.0)

var _visual: Control = null
var _seed: int = 12345

var _size_slider: HSlider = null
var _spin_slider: HSlider = null
var _tint_r_slider: HSlider = null
var _tint_g_slider: HSlider = null
var _tint_b_slider: HSlider = null
# Cobalt 2026-05-21: roundness knob. Internally drives the asteroid
# shader's `size` (noise frequency) and `octaves` (detail layers) —
# at 0 the rock looks jagged/lumpy, at 1 it tends toward a clean disc
# because the noise can no longer carve large divots out of the radial
# envelope.
var _roundness_slider: HSlider = null
# Pixel parity for the lab — same rule as galaxy_backdrop:
# shader_pixels = displayed_size_vp / pixel_density.
const PIXEL_DENSITY := 1.0
const PIXELS_FLOOR := 16.0
const COLORRECT_CANONICAL := Vector2(100.0, 100.0)
# Per-slider readout labels — bound by closure on slider.value_changed.
var _readouts: Dictionary = {}
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
	v.size = Vector2(96, 380)
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var hdr := Label.new()
	hdr.text = "ASTEROID LAB"
	hdr.add_theme_font_size_override("font_size", FONT_HDR)
	hdr.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	v.add_child(hdr)
	var sub := Label.new()
	sub.text = "Tune the procgen knobs."
	sub.add_theme_font_size_override("font_size", FONT_LBL)
	sub.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)
	v.add_child(sub)
	v.add_child(HSeparator.new())
	_size_slider = _add_slider(v, "Size", 30.0, 160.0, 1.0, 60.0, "%d px")
	# Pixels uniform is no longer a free slider — it's derived from Size
	# so the asteroid always renders at 1:1 pixel parity (same density as
	# the player ship). Roundness replaces it as the second knob.
	_roundness_slider = _add_slider(v, "Roundness", 0.0, 1.0, 0.05, 0.0, "%.2f")
	_spin_slider = _add_slider(v, "Spin", -3.0, 3.0, 0.1, 0.0, "%.1f rad/s")
	_tint_r_slider = _add_slider(v, "Tint R", 0.3, 1.7, 0.05, 1.20, "%.2f")
	_tint_g_slider = _add_slider(v, "Tint G", 0.3, 1.7, 0.05, 1.05, "%.2f")
	_tint_b_slider = _add_slider(v, "Tint B", 0.3, 1.7, 0.05, 0.85, "%.2f")
	v.add_child(HSeparator.new())
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", FONT_LBL)
	_readout.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	v.add_child(_readout)
	v.add_child(HSeparator.new())
	# Cody 2026-05-19: distinct from Reroll. "Generate New Asteroid"
	# always picks a fresh seed; the regen-on-slider path keeps the seed.
	var new_btn := Button.new()
	new_btn.text = "Generate New Asteroid"
	new_btn.add_theme_font_size_override("font_size", FONT_LBL)
	UiTheme.style_button(new_btn, true)
	new_btn.pressed.connect(_on_new_asteroid)
	v.add_child(new_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", FONT_LBL)
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	v.add_child(back_btn)


func _add_slider(parent: Container, label: String, lo: float, hi: float, step: float, default_v: float, fmt: String) -> HSlider:
	# Label + numeric readout share one row so the rail stays narrow.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", FONT_LBL)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var val := Label.new()
	val.text = fmt % default_v
	val.add_theme_font_size_override("font_size", FONT_VAL)
	val.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = default_v
	s.custom_minimum_size = Vector2(0, SLIDER_H)
	s.value_changed.connect(_on_slider_changed)
	# Closure that retypes the readout as the slider moves.
	s.value_changed.connect(func(v: float):
		val.text = fmt % v
	)
	parent.add_child(s)
	return s


func _on_slider_changed(_v: float) -> void:
	_regenerate()


# Cody 2026-05-19: was "Reroll Seed" — renamed to "Generate New Asteroid"
# (player-facing label) but still does the same thing: fresh randi seed
# + full regenerate.
func _on_new_asteroid() -> void:
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
	# Cobalt 2026-05-21: asteroid now renders at 1:1 pixel parity. The
	# outer Control uses scale instead of resizing so the canonical
	# 100×100 ColorRect inside the addon stays untouched; shader pixels =
	# size_px keeps cell viewport size = 1 (matches player density).
	var size_px: float = float(_size_slider.value)
	var sf: float = size_px / 100.0
	if v is Control:
		v.custom_minimum_size = COLORRECT_CANONICAL
		v.size = COLORRECT_CANONICAL
		v.scale = Vector2(sf, sf)
		v.position = ASTEROID_CENTER - COLORRECT_CANONICAL * 0.5 * sf
		v.pivot_offset = COLORRECT_CANONICAL * 0.5
	# Drive shader pixels via the parity rule. Floor protects against
	# unreadable mush at very small sizes.
	var shader_pixels: float = max(size_px / PIXEL_DENSITY, PIXELS_FLOOR)
	if v.has_method("set_pixels"):
		v.set_pixels(shader_pixels)
	# Roundness drives shader `size` (noise frequency) and `octaves`
	# inversely — high roundness = small noise lobes + few octaves =
	# rounder silhouette.
	var roundness: float = float(_roundness_slider.value)
	var asteroid_size: float = lerp(8.0, 1.5, roundness)
	var asteroid_octaves: int = int(round(lerp(4.0, 1.0, roundness)))
	if inner and inner.material is ShaderMaterial:
		var mat: ShaderMaterial = inner.material
		mat.set_shader_parameter("size", asteroid_size)
		mat.set_shader_parameter("octaves", asteroid_octaves)
	# Inner ColorRect stays at canonical 100×100 — set_pixels was resizing
	# it which couples shader resolution to footprint. Reset undoes that.
	if inner:
		inner.size = COLORRECT_CANONICAL
		inner.position = Vector2.ZERO
		inner.pivot_offset = COLORRECT_CANONICAL * 0.5
		inner.modulate = Color(_tint_r_slider.value, _tint_g_slider.value, _tint_b_slider.value, 1.0)
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
	_readout.text = "Seed: %d" % _seed


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
