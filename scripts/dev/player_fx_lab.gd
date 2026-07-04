extends Control

# Player FX Lab (Roman 2026-06-11; HD-overhauled, then torch-tuner pass). Runs the
# live player ship through hull damage levels so the damage tells — engine fire
# (engine_torch), damage smoke (damage_smoke_trail), and the damage overlay — can be
# SEEN applying at each level, and verifies they react to max-HP changes.
#
# Right rail = a LIVE TORCH TUNER (colors + size + behaviour knobs, applied to the
# player's attached torches each change) with Save + Copy GDScript (the tuner
# contract). Left rail = ship pick + hull sliders + a MARKER-DOTS toggle that drops
# 1px colour dots on the sprite-centre / engine / wing markers so you can see exactly
# where the tells should spawn.
#
# Renders the WORLD in a native 480×270 SubViewport (crisp, hdr_2d-parity, fx parent to
# the player's parent = the viewport) upscaled to fill HD, with an HD CanvasLayer UI.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")

const SAVE_PATH := "user://tuners/player_fx_lab.json"

# Torch knob schema: shader-uniform colours + scalar sliders + torch-instance knobs.
# def values mirror engine_torch.gd's defaults so an untouched lab == the game look.
const TORCH_COLORS := {
	"fromColor": Color(0.941, 0.376, 0.027),   # f06007
	"toColor": Color(0.537, 0.267, 0.0),       # 894400
	"sparkColor": Color(1.0, 0.643, 0.208),    # ffa435
	"smokeColor": Color(0.020, 0.020, 0.020),  # 050505
}
const TORCH_SLIDERS := [
	{"key": "pixelSize", "label": "Pixel size", "min": 0.02, "max": 0.2, "step": 0.005, "def": 0.08},
	{"key": "speed", "label": "Flame speed", "min": 0.5, "max": 6.0, "step": 0.1, "def": 2.5},
	{"key": "sparkSpeed", "label": "Spark speed", "min": 0.0, "max": 2.0, "step": 0.05, "def": 0.4},
	{"key": "flame_width", "label": "Flame width", "min": 0.05, "max": 0.6, "step": 0.01, "def": 0.22},
	{"key": "flame_h_min", "label": "Height @ light dmg", "min": 0.05, "max": 1.0, "step": 0.01, "def": 0.25},
	{"key": "flame_h_max", "label": "Height @ near-death", "min": 0.3, "max": 1.5, "step": 0.01, "def": 1.0},
	{"key": "severity_exp", "label": "Severity easing exp", "min": 0.5, "max": 3.0, "step": 0.05, "def": 1.5},
	{"key": "burst_severity", "label": "Burst threshold", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.6},
	{"key": "activate_below", "label": "Activate below dmg", "min": 0.0, "max": 1.0, "step": 0.01, "def": 0.01},
]

# Hex shield tuner (moved here from the Shader Lab, Roman 2026-06-11) — tunes the
# hex_shield bubble live on the actual player ship.
const HEX_SHIELD := preload("res://graphics/hex_shield.gdshader")
const SHIELD_SLIDERS := [
	{"key": "ring_px", "label": "Bubble size (px)", "min": 16.0, "max": 96.0, "step": 2.0, "def": 30.0},
	{"key": "cells", "label": "Hex cells across", "min": 2.0, "max": 24.0, "step": 0.5, "def": 7.0},
	{"key": "scroll_x", "label": "Scroll X", "min": -0.3, "max": 0.3, "step": 0.01, "def": 0.08},
	{"key": "scroll_y", "label": "Scroll Y", "min": -0.3, "max": 0.3, "step": 0.01, "def": 0.05},
	{"key": "line_width", "label": "Line width", "min": 0.02, "max": 0.45, "step": 0.01, "def": 0.12},
	{"key": "rim_power", "label": "Rim power", "min": 0.5, "max": 6.0, "step": 0.1, "def": 2.2},
	{"key": "fill_alpha", "label": "Fill alpha", "min": 0.0, "max": 0.4, "step": 0.01, "def": 0.05},
	{"key": "flicker", "label": "Cell flicker", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.35},
	{"key": "dome", "label": "Dome warp", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.65},
	{"key": "elongation", "label": "Capsule elongation", "min": 0.0, "max": 0.85, "step": 0.05, "def": 0.0},
]

# Idle-look presets — each is a set of SHIELD_SLIDERS overrides (unset keys fall back to the
# slider default). Picking one re-seeds the sliders so you start from a coherent look.
const IDLE_PRESETS := {
	"Default":         {},
	"Dense honeycomb": {"cells": 14.0, "line_width": 0.08, "fill_alpha": 0.04, "rim_power": 2.6, "flicker": 0.25},
	"Sparse plates":   {"cells": 4.0, "line_width": 0.22, "fill_alpha": 0.08, "rim_power": 1.6},
	"Solid dome":      {"cells": 9.0, "fill_alpha": 0.30, "dome": 1.0, "flicker": 0.10, "rim_power": 3.5},
	"Shimmer":         {"cells": 8.0, "flicker": 0.90, "scroll_x": 0.18, "scroll_y": 0.12, "fill_alpha": 0.03},
}
# Hit-flash presets — shape of the `hit_strength` pulse the Pulse Hit button (and an in-game
# shield hit) plays: peak strength + decay duration.
const HIT_PRESETS := {
	"Default":     {"dur": 0.45, "peak": 1.0},
	"Quick snap":  {"dur": 0.22, "peak": 1.0},
	"Slow ripple": {"dur": 0.85, "peak": 0.8},
	"Hard flash":  {"dur": 0.35, "peak": 1.6},
}

var _hd_scope: HdViewportScope = null
var _world: SubViewport = null
var _player: Node2D = null
var _hull_slider: HSlider = null
var _maxhull_slider: HSlider = null
var _readout: Label = null

# Tuner state.
var _torch_colors: Dictionary = {}
var _torch_vals: Dictionary = {}
var _markers_on: bool = false
var _marker_dots: Array = []
# Shield tuner state.
var _shield_vals: Dictionary = {}
var _shield_color := Color(0.35, 0.85, 1.0)
var _shield_rect: ColorRect = null
var _shield_mat: ShaderMaterial = null
var _shield_on: bool = false
var _shield_rows: Dictionary = {}   # key -> {"slider": HSlider, "label": Label, "name": String}
var _hit_dur: float = 0.45
var _hit_peak: float = 1.0


func _ready() -> void:
	_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world = HdScreen.make_play_subviewport(self)
	# "bullet_world" sink so a damaged player's tell fx (torch burst, smoke) + any parent-less fx
	# resolve into this native SubViewport, not the 1920×1080 window's top-left corner (no-op in prod).
	_world.add_to_group("bullet_world")
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.size = Vector2(480, 270)
	_world.add_child(bg)
	_init_tuner_defaults()
	_load_saved()
	_build_ui()
	_spawn_player(0)
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_world, "Player FX Lab")


func _init_tuner_defaults() -> void:
	for k in TORCH_COLORS:
		_torch_colors[k] = TORCH_COLORS[k]
	for d in TORCH_SLIDERS:
		_torch_vals[d["key"]] = float(d["def"])
	for d in SHIELD_SLIDERS:
		_shield_vals[d["key"]] = float(d["def"])


func _spawn_player(idx: int) -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_marker_dots.clear()
	var scn: PackedScene = load(ShipCatalog.scene_path(idx))
	_player = scn.instantiate()
	_world.add_child(_player)
	_player.position = Vector2(240.0, 175.0)
	if "is_alive" in _player:
		_player.is_alive = true
	if "controls_enabled" in _player:
		_player.controls_enabled = false   # hold still so the fx read clearly
	if "invincible" in _player:
		_player.invincible = true
	await get_tree().process_frame
	_sync_sliders_from_player()
	_apply_torch_knobs()
	_apply_hull()
	_attach_shield()
	if _markers_on:
		_rebuild_marker_dots()


func _sync_sliders_from_player() -> void:
	if _player == null:
		return
	var mh: int = int(_player.max_hull) if "max_hull" in _player else 3
	_maxhull_slider.value = mh
	_hull_slider.max_value = mh
	_hull_slider.value = mh


# Drive the player's hull (triggers hull_changed → fire/smoke/torch/overlay update).
func _apply_hull() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var mh: int = int(_maxhull_slider.value)
	var h: int = clampi(int(_hull_slider.value), 0, mh)
	if "max_hull" in _player:
		_player.max_hull = mh
	if "hull" in _player:
		_player.hull = h          # setter emits hull_changed
	if _player.has_signal("hull_changed"):
		_player.hull_changed.emit(mh, h)   # re-eval the max-HP fraction even if hull held
	if _readout:
		var frac: float = 1.0 - (float(h) / float(max(1, mh)))
		_readout.text = "Hull %d / %d   (damage %d%%)" % [h, mh, int(round(frac * 100.0))]


# ---- Torch tuner -----------------------------------------------------------

func _torches() -> Array:
	if _player == null or not is_instance_valid(_player):
		return []
	# NOTE the wildcard: player.gd names the torches "EngineTorch_0"/"EngineTorch_1"
	# (a per-point suffix), so a bare "EngineTorch" pattern matched NOTHING and the
	# tuner was a silent no-op (Roman: "torch tuner tunes the shield hit particles,
	# not the torch") — it never reached the torch material at all.
	return _player.find_children("EngineTorch*", "", true, false)


# Push the current knob values onto every live EngineTorch, then re-apply hull so the
# size lerp (which reads flame_size_min/max) recomputes immediately.
func _apply_torch_knobs() -> void:
	var w: float = float(_torch_vals["flame_width"])
	for t in _torches():
		if t == null or not is_instance_valid(t):
			continue
		var mat = t.material
		if mat is ShaderMaterial:
			for k in _torch_colors:
				mat.set_shader_parameter(k, _torch_colors[k])
			mat.set_shader_parameter("pixelSize", float(_torch_vals["pixelSize"]))
			mat.set_shader_parameter("speed", float(_torch_vals["speed"]))
			mat.set_shader_parameter("sparkSpeed", float(_torch_vals["sparkSpeed"]))
		if "flame_size_min" in t:
			t.flame_size_min = Vector2(w, float(_torch_vals["flame_h_min"]))
		if "flame_size_max" in t:
			t.flame_size_max = Vector2(w, float(_torch_vals["flame_h_max"]))
		if "severity_exp" in t:
			t.severity_exp = float(_torch_vals["severity_exp"])
		if "burst_severity" in t:
			t.burst_severity = float(_torch_vals["burst_severity"])
		if "activate_below" in t:
			t.activate_below = float(_torch_vals["activate_below"])
	_apply_hull()


# ---- Shield tuner ----------------------------------------------------------

# Tune the player's OWN hex-shield ring (player.gd::_setup_shield_ring) — do NOT stack a second
# bubble on top. The old code added a duplicate ColorRect, so "Show shield bubble" read as an
# EXTRA shield over the one the ship already carries (Roman 2026-06-17). In game the ring is
# alpha 0 until a hit; here the toggle drives its visibility via the shader alpha.
func _attach_shield() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_shield_rect = _player.get_node_or_null("ShieldRing")
	_shield_mat = null
	if _shield_rect != null and _shield_rect.material is ShaderMaterial:
		_shield_mat = _shield_rect.material
	_apply_shield_knobs()
	_set_shield_visible(_shield_on)


func _apply_shield_knobs() -> void:
	if _shield_mat == null or not is_instance_valid(_shield_rect):
		return
	_shield_mat.set_shader_parameter("cells", float(_shield_vals["cells"]))
	_shield_mat.set_shader_parameter("scroll", Vector2(float(_shield_vals["scroll_x"]), float(_shield_vals["scroll_y"])))
	_shield_mat.set_shader_parameter("line_width", float(_shield_vals["line_width"]))
	_shield_mat.set_shader_parameter("rim_power", float(_shield_vals["rim_power"]))
	_shield_mat.set_shader_parameter("fill_alpha", float(_shield_vals["fill_alpha"]))
	_shield_mat.set_shader_parameter("flicker", float(_shield_vals["flicker"]))
	_shield_mat.set_shader_parameter("dome", float(_shield_vals["dome"]))
	_shield_mat.set_shader_parameter("elongation", float(_shield_vals["elongation"]))
	_shield_mat.set_shader_parameter("shield_color", _shield_color)
	var s := float(_shield_vals["ring_px"])
	_shield_rect.size = Vector2(s, s)
	_shield_rect.position = Vector2(-s * 0.5, -s * 0.5)   # centered on the ship origin


func _set_shield_visible(on: bool) -> void:
	_shield_on = on
	# The ring's in-game visibility is shader-alpha driven (player keeps the node always present),
	# so toggle the alpha rather than the node's `visible` flag.
	if _shield_mat != null:
		_shield_mat.set_shader_parameter("alpha", 1.0 if on else 0.0)


func _pulse_shield() -> void:
	if _shield_mat == null:
		return
	# Make sure the bubble is showing so the flash is visible even with the toggle off.
	_shield_mat.set_shader_parameter("alpha", 1.0)
	var m := _shield_mat
	var peak := _hit_peak
	m.set_shader_parameter("hit_strength", peak)
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("hit_strength", v), peak, 0.0, _hit_dur)
	# Restore the toggle's alpha state after the flash if the bubble was meant to be hidden.
	if not _shield_on:
		tw.tween_callback(func():
			if _shield_mat != null:
				_shield_mat.set_shader_parameter("alpha", 0.0))


# A labelled OptionButton row for a preset group. `keys` is the preset-name list; the callback
# receives the chosen name.
func _mk_shield_preset_row(caption: String, keys: Array, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := _mk_label(caption, 15)
	lbl.custom_minimum_size = Vector2(150, 0)
	row.add_child(lbl)
	var dd := OptionButton.new()
	dd.add_theme_font_size_override("font_size", 16)
	for k in keys:
		dd.add_item(String(k))
	dd.item_selected.connect(func(i: int): cb.call(String(keys[i])))
	row.add_child(dd)
	return row


# Re-seed the idle sliders from a preset: slider defaults first, then the preset overrides.
func _apply_idle_preset(name: String) -> void:
	for d in SHIELD_SLIDERS:
		_shield_vals[d["key"]] = float(d["def"])
	var ov: Dictionary = IDLE_PRESETS.get(name, {})
	for k in ov:
		_shield_vals[k] = float(ov[k])
	# Push the new values onto the live slider rows (no signal — apply once below).
	for key in _shield_rows:
		var rec: Dictionary = _shield_rows[key]
		var sl: HSlider = rec["slider"]
		if sl != null and is_instance_valid(sl):
			sl.set_value_no_signal(float(_shield_vals[key]))
			(rec["label"] as Label).text = "%s   %.3f" % [String(rec["name"]), float(_shield_vals[key])]
	_apply_shield_knobs()


func _apply_hit_preset(name: String) -> void:
	var p: Dictionary = HIT_PRESETS.get(name, {})
	_hit_dur = float(p.get("dur", 0.45))
	_hit_peak = float(p.get("peak", 1.0))
	_pulse_shield()   # preview the chosen flash immediately


# ---- Marker dots -----------------------------------------------------------

# 1px colour dots at the sprite centre (magenta), each engine marker (cyan), and each
# wing-launch marker (yellow) — the candidate anchors the damage tells shuffle among.
func _rebuild_marker_dots() -> void:
	for d in _marker_dots:
		if d != null and is_instance_valid(d):
			d.queue_free()
	_marker_dots.clear()
	if _player == null or not is_instance_valid(_player):
		return
	_add_dot(Vector2.ZERO, Color(1, 0, 1), _player)          # sprite centre
	for m in _player.find_children("Engine*", "Marker2D", true, false):
		_add_dot(Vector2.ZERO, Color(0, 1, 1), m)             # engine markers (cyan)
	for nm in ["LaunchWingL", "LaunchWingR"]:
		var wn := _player.find_child(nm, true, false)
		if wn != null:
			_add_dot(Vector2.ZERO, Color(1, 0.9, 0.2), wn)    # wing-launch markers (yellow)


# A 1px ColorRect dot centred on `anchor` (child of it so it tracks the marker).
func _add_dot(local: Vector2, col: Color, anchor: Node) -> void:
	var dot := ColorRect.new()
	dot.color = col
	dot.size = Vector2(1, 1)
	dot.position = local - Vector2(0.5, 0.5)
	dot.z_index = 50
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(dot)
	_marker_dots.append(dot)


func _set_markers(on: bool) -> void:
	_markers_on = on
	if on:
		_rebuild_marker_dots()
	else:
		for d in _marker_dots:
			if d != null and is_instance_valid(d):
				d.queue_free()
		_marker_dots.clear()


# ---- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Left control rail.
	var rail := VBoxContainer.new()
	rail.position = Vector2(24, 24)
	rail.add_theme_constant_override("separation", 8)
	layer.add_child(rail)

	rail.add_child(_mk_label("PLAYER FX LAB", 26))

	var dd := OptionButton.new()
	for ship in ShipCatalog.SHIPS:
		dd.add_item(String(ship["name"]))
	dd.item_selected.connect(func(i): _spawn_player(i))
	dd.custom_minimum_size = Vector2(220, 40)
	rail.add_child(dd)

	rail.add_child(_mk_label("Hull (drag to damage)", 16))
	_hull_slider = _mk_slider(0, 3, 1, 3)
	_hull_slider.value_changed.connect(func(_v): _apply_hull())
	rail.add_child(_hull_slider)

	rail.add_child(_mk_label("Max Hull (max-HP test)", 16))
	_maxhull_slider = _mk_slider(1, 10, 1, 3)
	_maxhull_slider.value_changed.connect(func(_v):
		_hull_slider.max_value = _maxhull_slider.value
		_apply_hull())
	rail.add_child(_maxhull_slider)

	_readout = _mk_label("", 16)
	rail.add_child(_readout)

	var mk_toggle := CheckButton.new()
	mk_toggle.text = "Marker dots (centre/engine/wing)"
	mk_toggle.button_pressed = _markers_on
	mk_toggle.add_theme_font_size_override("font_size", 16)
	mk_toggle.toggled.connect(_set_markers)
	rail.add_child(mk_toggle)

	rail.add_child(_mk_button("Back (Esc)", _back))

	# Right knob rail (torch tuner) in a scroll.
	var panel_w := 430
	var rx := 1920 - 24 - panel_w
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(rx, 24)
	scroll.size = Vector2(panel_w, 1080 - 130)
	layer.add_child(scroll)
	var kb := VBoxContainer.new()
	kb.custom_minimum_size = Vector2(panel_w - 24, 0)
	kb.add_theme_constant_override("separation", 6)
	scroll.add_child(kb)

	kb.add_child(_mk_label("TORCH TUNER (live)", 22))
	kb.add_child(_mk_label("Drag hull down to a damaged state, then tune.\nApplies to the player's live engine torch(es).", 14))
	for k in ["fromColor", "toColor", "sparkColor", "smokeColor"]:
		_add_color_row(kb, k)
	kb.add_child(HSeparator.new())
	for d in TORCH_SLIDERS:
		_add_slider_row(kb, d)
	# Hex shield tuner (moved from the Shader Lab).
	kb.add_child(HSeparator.new())
	kb.add_child(_mk_label("HEX SHIELD TUNER (live)", 22))
	var sh_toggle := CheckButton.new()
	sh_toggle.text = "Show shield bubble"
	sh_toggle.button_pressed = _shield_on
	sh_toggle.add_theme_font_size_override("font_size", 16)
	sh_toggle.toggled.connect(_set_shield_visible)
	kb.add_child(sh_toggle)
	# Idle-look + hit-flash style presets.
	kb.add_child(_mk_shield_preset_row("Idle style", IDLE_PRESETS.keys(), _apply_idle_preset))
	kb.add_child(_mk_shield_preset_row("Hit-flash style", HIT_PRESETS.keys(), _apply_hit_preset))
	_add_shield_color_row(kb)
	kb.add_child(_mk_button("Pulse Hit", _pulse_shield))
	for d in SHIELD_SLIDERS:
		_add_shield_slider_row(kb, d)

	# Save / Copy row pinned at the bottom.
	var actions := HBoxContainer.new()
	actions.position = Vector2(rx, 1080 - 96)
	actions.add_theme_constant_override("separation", 10)
	layer.add_child(actions)
	actions.add_child(_mk_button("Save", _on_save))
	actions.add_child(_mk_button("Copy GDScript", _on_copy))
	actions.add_child(_mk_button("Reset", _on_reset))


func _add_color_row(parent: VBoxContainer, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := _mk_label(key, 15)
	lbl.custom_minimum_size = Vector2(150, 0)
	row.add_child(lbl)
	var cp := ColorPickerButton.new()
	cp.color = _torch_colors[key]
	cp.edit_alpha = (key == "smokeColor")
	cp.custom_minimum_size = Vector2(180, 32)
	cp.color_changed.connect(func(c: Color):
		_torch_colors[key] = c
		_apply_torch_knobs())
	row.add_child(cp)
	parent.add_child(row)


func _add_slider_row(parent: VBoxContainer, d: Dictionary) -> void:
	var key: String = d["key"]
	var lbl := _mk_label("%s   %.3f" % [d["label"], float(_torch_vals[key])], 15)
	parent.add_child(lbl)
	var s := HSlider.new()
	s.min_value = float(d["min"])
	s.max_value = float(d["max"])
	s.step = float(d["step"])
	s.value = float(_torch_vals[key])
	s.custom_minimum_size = Vector2(panel_slider_w(), 26)
	s.value_changed.connect(func(v: float):
		_torch_vals[key] = v
		lbl.text = "%s   %.3f" % [d["label"], v]
		_apply_torch_knobs())
	parent.add_child(s)


func _add_shield_color_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := _mk_label("shield_color", 15)
	lbl.custom_minimum_size = Vector2(150, 0)
	row.add_child(lbl)
	var cp := ColorPickerButton.new()
	cp.color = _shield_color
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(180, 32)
	cp.color_changed.connect(func(c: Color):
		_shield_color = c
		_apply_shield_knobs())
	row.add_child(cp)
	parent.add_child(row)


func _add_shield_slider_row(parent: VBoxContainer, d: Dictionary) -> void:
	var key: String = d["key"]
	var lbl := _mk_label("%s   %.3f" % [d["label"], float(_shield_vals[key])], 15)
	parent.add_child(lbl)
	var s := HSlider.new()
	s.min_value = float(d["min"])
	s.max_value = float(d["max"])
	s.step = float(d["step"])
	s.value = float(_shield_vals[key])
	s.custom_minimum_size = Vector2(panel_slider_w(), 26)
	s.value_changed.connect(func(v: float):
		_shield_vals[key] = v
		lbl.text = "%s   %.3f" % [d["label"], v]
		_apply_shield_knobs())
	parent.add_child(s)
	_shield_rows[key] = {"slider": s, "label": lbl, "name": String(d["label"])}


func panel_slider_w() -> float:
	return 390.0


# ---- Save / Copy / Reset ---------------------------------------------------

func _on_save() -> void:
	var data := {
		"colors": {}, "vals": _torch_vals.duplicate(),
		"shield": _shield_vals.duplicate(), "shield_color": _shield_color.to_html(false),
	}
	for k in _torch_colors:
		data["colors"][k] = (_torch_colors[k] as Color).to_html(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tuners"))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
	if _readout:
		_readout.text = "Saved torch tuner → %s" % SAVE_PATH


func _load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if parsed.has("colors"):
		for k in parsed["colors"]:
			_torch_colors[k] = Color.html(String(parsed["colors"][k]))
	if parsed.has("vals"):
		for k in parsed["vals"]:
			_torch_vals[k] = float(parsed["vals"][k])
	if parsed.has("shield"):
		for k in parsed["shield"]:
			_shield_vals[k] = float(parsed["shield"][k])
	if parsed.has("shield_color"):
		_shield_color = Color.html(String(parsed["shield_color"]))


func _on_copy() -> void:
	var lines := []
	lines.append("# Torch tuner values (Player FX Lab). Paste into engine_torch.gd attach_to_player()")
	lines.append("# shader params + the flame/severity defaults.")
	for k in ["fromColor", "toColor", "sparkColor", "smokeColor"]:
		lines.append('mat.set_shader_parameter("%s", Color.html("%s"))' % [k, (_torch_colors[k] as Color).to_html(true)])
	lines.append('mat.set_shader_parameter("pixelSize", %.3f)' % float(_torch_vals["pixelSize"]))
	lines.append('mat.set_shader_parameter("speed", %.2f)' % float(_torch_vals["speed"]))
	lines.append('mat.set_shader_parameter("sparkSpeed", %.2f)' % float(_torch_vals["sparkSpeed"]))
	lines.append("const FLAME_SIZE_MIN := Vector2(%.2f, %.2f)" % [float(_torch_vals["flame_width"]), float(_torch_vals["flame_h_min"])])
	lines.append("const FLAME_SIZE_MAX := Vector2(%.2f, %.2f)" % [float(_torch_vals["flame_width"]), float(_torch_vals["flame_h_max"])])
	lines.append("const SEVERITY_EXP: float = %.2f" % float(_torch_vals["severity_exp"]))
	lines.append("const BURST_SEVERITY: float = %.2f" % float(_torch_vals["burst_severity"]))
	lines.append("# activate_below (player attach arg): %.2f" % float(_torch_vals["activate_below"]))
	lines.append("")
	lines.append("# Hex shield (graphics/hex_shield.gdshader) — shield_component.gd / player.gd")
	lines.append('mat.set_shader_parameter("shield_color", Color.html("%s"))' % _shield_color.to_html(false))
	lines.append('mat.set_shader_parameter("cells", %.1f)' % float(_shield_vals["cells"]))
	lines.append('mat.set_shader_parameter("scroll", Vector2(%.2f, %.2f))' % [float(_shield_vals["scroll_x"]), float(_shield_vals["scroll_y"])])
	lines.append('mat.set_shader_parameter("line_width", %.2f)' % float(_shield_vals["line_width"]))
	lines.append('mat.set_shader_parameter("rim_power", %.1f)' % float(_shield_vals["rim_power"]))
	lines.append('mat.set_shader_parameter("fill_alpha", %.2f)' % float(_shield_vals["fill_alpha"]))
	lines.append('mat.set_shader_parameter("flicker", %.2f)' % float(_shield_vals["flicker"]))
	lines.append('mat.set_shader_parameter("dome", %.2f)' % float(_shield_vals["dome"]))
	lines.append("# bubble size (px): %.0f" % float(_shield_vals["ring_px"]))
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	if _readout:
		_readout.text = "Copied torch GDScript to clipboard"


func _on_reset() -> void:
	_init_tuner_defaults()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/player_fx_lab.tscn")


# ---- helpers ---------------------------------------------------------------

func _mk_label(t: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	return l


func _mk_slider(lo: float, hi: float, step: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(360, 28)
	return s


func _mk_button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	return b


func _back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
