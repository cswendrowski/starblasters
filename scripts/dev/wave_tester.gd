extends Control

# Wave Tester (Roman, 2026-05-18 simplified). Two sliders only:
#   Sector — which sector (1-5)
#   Depth  — which combat into the sector (1 = first combat, N = Nth)
# WaveGeneratorV2 derives density / wave_count / tier_max from these.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const WaveGenV2 = preload("res://scripts/levels/wave_generator_v2.gd")

var _sector_slider: HSlider = null
var _depth_slider: HSlider = null
var _readout: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_update_readout()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.position = Vector2(20, 14)
	v.size = Vector2(280, 380)
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var hdr := Label.new()
	hdr.text = "WAVE TESTER"
	UiTheme.style_label(hdr, UiTheme.LabelKind.HEADER)
	v.add_child(hdr)
	var sub := Label.new()
	sub.text = "Pick a sector + how far into it.\nGenerator derives density/waves/tier."
	UiTheme.style_label(sub, UiTheme.LabelKind.CAPTION)
	v.add_child(sub)
	v.add_child(HSeparator.new())
	_sector_slider = _add_slider(v, "Sector (1-5)", 1, 5, 1)
	_depth_slider = _add_slider(v, "Depth — Nth combat in sector (1-8)", 1, 8, 1)
	v.add_child(HSeparator.new())
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 10)
	_readout.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	v.add_child(_readout)
	v.add_child(HSeparator.new())
	var launch_btn := Button.new()
	launch_btn.text = "Launch"
	UiTheme.style_button(launch_btn, true)
	launch_btn.pressed.connect(_on_launch)
	v.add_child(launch_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	v.add_child(back_btn)


func _add_slider(parent: Container, label: String, lo: int, hi: int, default_v: int) -> HSlider:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = default_v
	s.custom_minimum_size = Vector2(0, 14)
	s.value_changed.connect(_on_slider_changed)
	parent.add_child(s)
	return s


func _on_slider_changed(_v: float) -> void:
	_update_readout()


func _update_readout() -> void:
	if _readout == null:
		return
	var s: int = int(_sector_slider.value)
	var d: int = int(_depth_slider.value)
	# Mirror the auto-derivation in WaveGeneratorV2 so the player sees
	# what they're about to spawn.
	var waves: int = clampi(2 + d, 2, 8)
	var density: float = (1.0 + 0.15 * float(d - 1)) * (1.0 + 0.1 * float(s - 1))
	var tier_max: int = clampi(int(floor(float(d - 1) * 0.5)), 0, 3)
	var tier_label: String = ["Common", "+Uncommon", "+Rare", "+Elite"][tier_max]
	_readout.text = "Sector %d, depth %d\nWaves: %d   Density: %.2f×\nTier max: %s" % [s, d, waves, density, tier_label]


func _on_launch() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# Reset state so we route through the COMBAT branch of main.gd
	# (Roman 2026-05-18: tester was launching minefields because
	# current_node_type was sticky from prior tests).
	run.new_run()
	run.test_mode_active = true
	run.current_node_type = 0   # SectorNode.NodeType.COMBAT
	run.current_hazard_subtype = ""
	var knobs := {
		"sector_depth": int(_depth_slider.value),
	}
	run.set_meta("wave_v2_knobs", knobs)
	run.set_meta("wave_v2_sector", int(_sector_slider.value))
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
