extends Control

# Shader Lab (Roman 2026-06-10) — fire the NEW shader effects in the native
# 480×270 SubViewport and compare them against what's in-game today, without
# the GIF-capture loop:
#   Embers     — ember_spray burst (cool-down) + the inverted heat-up variant
#   Shields    — sci_fi_shield ring (current) vs hex_shield (new) side by side
#   Glow       — glow_halo per-sprite bloom (current) vs screen_glow overlay,
#                showcased on ENEMY BULLETS
#   Modes      — Focus / Phase / Hyper player-mode tells, replicated
#   Explosions — both explosion styles (default + small-circle), replayable
#   Gallery    — every other shader in the project on a test quad / sprite
# Right rail = knobs per mode, persisted to user://tuners/shader_lab.json +
# Copy GDScript (tuner contract). Esc / Back returns to the dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const Playfield = preload("res://scripts/playfield.gd")
const EmberFx = preload("res://scripts/effects/ember_fx.gd")
const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const OutlineFx = preload("res://scripts/effects/outline_fx.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const PLAYER_SPRITE = preload("res://Mini Pixel Pack 3/Player ship/Player_ship (16 x 16).png")

const SCI_FI_SHIELD: Shader = preload("res://graphics/sci_fi_shield.gdshader")
const HEX_SHIELD: Shader = preload("res://graphics/hex_shield.gdshader")
const SCREEN_GLOW: Shader = preload("res://graphics/screen_glow.gdshader")

# Player-mode tells (mirrors the constants in player.gd so the lab matches the
# game — keep in sync if those change).
const FOCUS_GLOW_COLOR := Color(0.5, 0.9, 1.0)
const FOCUS_SHIP_TINT := Color(0.5, 0.7, 1.0, 0.55)
const PHASE_GLOW_COLOR := Color(0.2, 0.5, 1.0)
const HYPER_OUTLINE_COLOR := Color(1.0, 0.5, 0.0)
const PHASE_AI_INTERVAL := 0.06
const PHASE_AI_LIFETIME := 0.34

# Enemy bullet sprites for the glow showcase: {texture path, hframes}.
const BULLETS := [
	{"name": "Plasma orb", "path": "res://graphics/projectiles/enemy_bullet.png", "frames": 3},
	{"name": "Pellet", "path": "res://graphics/projectiles/enemy_bullet_small.png", "frames": 3},
	{"name": "Tracer", "path": "res://graphics/projectiles/enemy_tracer.png", "frames": 3},
	{"name": "Cannon slug", "path": "res://graphics/projectiles/enemy_cannon.png", "frames": 2},
	{"name": "Wave orb", "path": "res://graphics/projectiles/enemy_bullet_wave.png", "frames": 4},
]

const SAVE_PATH := "user://tuners/shader_lab.json"

const FS_TITLE := 40
const FS_BODY := 18
const FS_CAPTION := 15
const RAIL_W := 280
const KNOB_W := 430
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)

# Gallery ship targets are zoomed for INSPECTION only — in-game sprites stay 1×.
const GALLERY_SPRITE_ZOOM := 3.0

const MODES := ["Embers", "Shields", "Glow", "Modes", "Explosions", "Gallery"]

const KNOBS := {
	"Embers": [
		{"key": "amount", "label": "Particles", "min": 4.0, "max": 96.0, "step": 1.0, "def": 28.0},
		{"key": "lifetime", "label": "Lifetime (s)", "min": 0.3, "max": 2.0, "step": 0.05, "def": 0.9},
		{"key": "explosiveness", "label": "Explosiveness", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.85},
		{"key": "angle_deg", "label": "Direction (deg)", "min": -180.0, "max": 180.0, "step": 5.0, "def": -90.0},
		{"key": "spread_deg", "label": "Spread (deg)", "min": 2.0, "max": 180.0, "step": 1.0, "def": 35.0},
		{"key": "speed_min", "label": "Speed min (px/s)", "min": 20.0, "max": 400.0, "step": 5.0, "def": 110.0},
		{"key": "speed_max", "label": "Speed max (px/s)", "min": 40.0, "max": 600.0, "step": 5.0, "def": 320.0},
		{"key": "drag", "label": "Drag", "min": 0.0, "max": 8.0, "step": 0.1, "def": 2.6},
		{"key": "gravity", "label": "Gravity (px/s²)", "min": -100.0, "max": 240.0, "step": 5.0, "def": 30.0},
		{"key": "streak_sec", "label": "Streak length (s)", "min": 0.0, "max": 0.15, "step": 0.005, "def": 0.05},
		{"key": "cool_bias", "label": "Cool-by-speed bias", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.55},
		{"key": "fade_start", "label": "Fade start (life %)", "min": 0.4, "max": 0.95, "step": 0.01, "def": 0.78},
		{"key": "lifetime_rand", "label": "Lifetime jitter", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.4},
	],
	"Shields": [
		{"key": "ring_px", "label": "Bubble size (px)", "min": 16.0, "max": 96.0, "step": 2.0, "def": 30.0},
		{"key": "cells", "label": "Hex cells across", "min": 2.0, "max": 24.0, "step": 0.5, "def": 7.0},
		{"key": "scroll_x", "label": "Scroll X", "min": -0.3, "max": 0.3, "step": 0.01, "def": 0.08},
		{"key": "scroll_y", "label": "Scroll Y", "min": -0.3, "max": 0.3, "step": 0.01, "def": 0.05},
		{"key": "line_width", "label": "Line width", "min": 0.02, "max": 0.45, "step": 0.01, "def": 0.12},
		{"key": "rim_power", "label": "Rim power", "min": 0.5, "max": 6.0, "step": 0.1, "def": 2.2},
		{"key": "fill_alpha", "label": "Fill alpha", "min": 0.0, "max": 0.4, "step": 0.01, "def": 0.05},
		{"key": "flicker", "label": "Cell flicker", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.35},
		{"key": "dome", "label": "Dome warp", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.65},
	],
	"Glow": [
		{"key": "threshold", "label": "Threshold", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.6},
		{"key": "knee", "label": "Knee", "min": 0.01, "max": 0.5, "step": 0.01, "def": 0.2},
		{"key": "intensity", "label": "Intensity", "min": 0.0, "max": 4.0, "step": 0.1, "def": 1.2},
		{"key": "max_lod", "label": "Radius (mip levels)", "min": 1.0, "max": 6.0, "step": 1.0, "def": 4.0},
	],
	"Modes": [],
	"Explosions": [],
	"Gallery": [],
}

# Every shader currently in the project that can be shown standalone.
# mode: "rect" = ColorRect quad, "sprite" = ship sprite, "glowfx" = live
# GlowShaderFx.apply() on a ship. pulse = uniform tweened by the Pulse button.
const GALLERY := [
	{"name": "Sci-Fi Shield (current)", "path": "res://graphics/sci_fi_shield.gdshader", "mode": "rect", "size": Vector2(48, 48), "pulse": {"param": "hit_strength", "from": 1.0, "to": 0.0, "time": 0.5}},
	{"name": "Hex Shield (NEW)", "path": "res://graphics/hex_shield.gdshader", "mode": "rect", "size": Vector2(48, 48), "pulse": {"param": "hit_strength", "from": 1.0, "to": 0.0, "time": 0.5}},
	{"name": "Glow Halo (current bloom)", "path": "res://scripts/effects/glow_halo.gdshader", "mode": "glowfx"},
	{"name": "Pulse Glow (legacy)", "path": "res://graphics/pulse_glow.gdshader", "mode": "sprite"},
	{"name": "Hit Flash", "path": "res://graphics/hit_flash.gdshader", "mode": "sprite", "pulse": {"param": "flash_strength", "from": 1.0, "to": 0.0, "time": 0.35}},
	{"name": "Hologram", "path": "res://graphics/hologram.gdshader", "mode": "sprite"},
	{"name": "Torch Fire (damage tell)", "path": "res://graphics/torch_fire.gdshader", "mode": "rect", "size": Vector2(28, 44)},
	{"name": "Billow Smoke", "path": "res://graphics/billow_smoke.gdshader", "mode": "rect", "size": Vector2(64, 64)},
	{"name": "Nebula v2 (backdrop)", "path": "res://graphics/nebula2.gdshader", "mode": "rect", "size": Vector2(180, 120), "textures": {"colorscheme": "scheme"}},
	{"name": "Starfield (backdrop)", "path": "res://graphics/starfield.gdshader", "mode": "rect", "size": Vector2(180, 120)},
	{"name": "Black Hole (backdrop)", "path": "res://graphics/black_hole.gdshader", "mode": "rect", "size": Vector2(96, 96)},
	{"name": "Pixelated Burn", "path": "res://graphics/pixelated_burn.gdshader", "mode": "sprite", "textures": {"noiseTexture": "noise", "colorCurve": "fire_ramp"}, "pulse": {"param": "radius", "from": 0.0, "to": 1.0, "time": 1.2}},
	{"name": "Damage Noise (enemy overlay)", "path": "res://graphics/damage_noise.gdshader", "mode": "sprite", "textures": {"noise_texture": "noise"}, "pulse": {"param": "sensitivity", "from": 0.0, "to": 0.8, "time": 1.2}},
	{"name": "Oblique Shadow", "path": "res://graphics/oblique_shadow.gdshader", "mode": "sprite"},
	{"name": "Outline 1px", "path": "res://shaders/outline_1px.gdshader", "mode": "sprite", "params": {"clr": Color(1.0, 1.0, 0.4, 1.0)}},
	{"name": "Sapper Beam", "path": "res://graphics/sapper_beam.gdshader", "mode": "rect", "size": Vector2(120, 6)},
	{"name": "Depth Tint (mid-depth ships)", "path": "res://scripts/effects/depth_tint.gdshader", "mode": "sprite"},
]

var _hd_scope: HdViewportScope = null

# Playspace.
var _preview_vp: SubViewport = null
var _stage: Node2D = null

# Overlay UI.
var _ui: CanvasLayer = null
var _mode_list: ItemList = null
var _knob_box: VBoxContainer = null
var _mode_overlay: Control = null
var _note: Label = null

# State.
var _mode: int = 0
var _values: Dictionary = {}

# Mode-specific refs (nulled on every mode switch).
var _scifi_mat: ShaderMaterial = null
var _hex_mat: ShaderMaterial = null
var _hex_rect: ColorRect = null
var _glow_mat: ShaderMaterial = null
var _glow_rect: ColorRect = null
var _orb: Sprite2D = null
var _orb_home: Vector2 = Vector2.ZERO
var _orb_t: float = 0.0
var _gallery_idx: int = 0
var _gallery_mat: ShaderMaterial = null
var _gallery_pulse_btn: Button = null
var _ember_inverted: bool = false

# Player-modes showcase state.
var _pm_ship: Node2D = null
var _pm_glow: CanvasItem = null
var _pm_outline: Sprite2D = null
var _pm_dot: Node2D = null
var _pm_mode: String = "off"
var _pm_home: Vector2 = Vector2.ZERO
var _pm_t: float = 0.0
var _pm_phase_acc: float = 0.0
var _pm_hyper_t: float = 0.0
var _pm_status: Label = null

# Explosions showcase: replay-loop timer.
var _expl_acc: float = 0.0
var _expl_auto: bool = true


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_values()
	_load_saved()
	_build_playspace()
	_build_overlay()
	_set_mode(0)


func _init_values() -> void:
	for mode in KNOBS:
		var d := {}
		for def in KNOBS[mode]:
			d[def["key"]] = float(def["def"])
		_values[mode] = d


# ---- Playspace -----------------------------------------------------------

func _build_playspace() -> void:
	# Native 480×270 SubViewport upscaled to fill the HD window via the blessed
	# pattern (HdScreen.add_upscaled_backdrop — full-rect STRETCH_SCALE+nearest
	# TextureRect). Keeps all Playfield coords native. The earlier
	# SubViewportContainer(stretch=true) RESIZED the viewport to 1920×1080 and
	# left the 480-coord stage content tiny in the top-left corner — the same
	# bug the hangar/shipyard hit (see hangar.gd _build_playspace).
	var root := Node2D.new()
	root.name = "Playspace"

	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	root.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	root.add_child(band)

	_stage = Node2D.new()
	_stage.name = "Stage"
	root.add_child(_stage)

	_preview_vp = HdScreen.add_upscaled_backdrop(self, root, Vector2i(480, 270))


# ---- Overlay UI ----------------------------------------------------------

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var header := _label("SHADER LAB", FS_TITLE, UiTheme.COLOR_ACCENT)
	header.position = Vector2(MARGIN, 12)
	header.add_theme_constant_override("outline_size", 6)
	_ui.add_child(header)

	_note = _label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_note.position = Vector2(MARGIN + 360, 28)
	_ui.add_child(_note)

	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(1920 - MARGIN - 120, 16)
	back.size = Vector2(120, 40)
	UiTheme.style_button(back, true)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.pressed.connect(_on_back)
	_ui.add_child(back)

	# HD annotations over the preview (cleared per mode switch).
	_mode_overlay = Control.new()
	_mode_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mode_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_mode_overlay)

	# Left rail: mode list.
	var ly := HEADER_H + MARGIN + 24
	var lh := MODES.size() * 52 + 60
	_ui.add_child(_panel(Vector2(MARGIN, ly), Vector2(RAIL_W, lh)))
	var lbl := _label("Mode", FS_CAPTION, UiTheme.COLOR_FAINT)
	lbl.position = Vector2(MARGIN + 14, ly + 10)
	_ui.add_child(lbl)
	_mode_list = ItemList.new()
	_mode_list.position = Vector2(MARGIN + 14, ly + 36)
	_mode_list.size = Vector2(RAIL_W - 28, lh - 50)
	_mode_list.add_theme_font_override("font", UiTheme.active_font())
	_mode_list.add_theme_font_size_override("font_size", FS_BODY)
	for m in MODES:
		_mode_list.add_item(String(m))
	_mode_list.item_selected.connect(_set_mode)
	_ui.add_child(_mode_list)

	# Right rail: knobs + actions in a scroll, Save/Copy fixed below.
	var rx := 1920 - MARGIN - KNOB_W
	var ry := HEADER_H + MARGIN + 24
	var rh := int((1080.0 - ry - MARGIN) * 0.9)
	_ui.add_child(_panel(Vector2(rx, ry), Vector2(KNOB_W, rh)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(rx + 16, ry + 14)
	scroll.size = Vector2(KNOB_W - 32, rh - 92)
	_ui.add_child(scroll)
	_knob_box = VBoxContainer.new()
	_knob_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_knob_box.custom_minimum_size = Vector2(KNOB_W - 56, 0)
	_knob_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_knob_box)

	var row := HBoxContainer.new()
	row.position = Vector2(rx + 16, ry + rh - 64)
	row.add_theme_constant_override("separation", 10)
	_ui.add_child(row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	UiTheme.style_button(save_btn, true)
	save_btn.add_theme_font_size_override("font_size", FS_BODY)
	save_btn.custom_minimum_size = Vector2(120, 40)
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy GDScript"
	UiTheme.style_button(copy_btn, false)
	copy_btn.add_theme_font_size_override("font_size", FS_BODY)
	copy_btn.custom_minimum_size = Vector2(200, 40)
	copy_btn.pressed.connect(_on_copy)
	row.add_child(copy_btn)


# ---- Mode switching --------------------------------------------------------

func _set_mode(idx: int) -> void:
	_mode = idx
	if _mode_list.item_count > idx and not _mode_list.is_selected(idx):
		_mode_list.select(idx)
	for c in _stage.get_children():
		c.queue_free()
	for c in _knob_box.get_children():
		c.queue_free()
	for c in _mode_overlay.get_children():
		c.queue_free()
	_scifi_mat = null
	_hex_mat = null
	_hex_rect = null
	_glow_mat = null
	_glow_rect = null
	_orb = null
	_gallery_mat = null
	_gallery_pulse_btn = null
	_pm_ship = null
	_pm_glow = null
	_pm_outline = null
	_pm_dot = null
	_pm_status = null
	_pm_mode = "off"
	match MODES[_mode]:
		"Embers":
			_enter_embers()
		"Shields":
			_enter_shields()
		"Glow":
			_enter_glow()
		"Modes":
			_enter_modes()
		"Explosions":
			_enter_explosions()
		"Gallery":
			_enter_gallery()


# ---- Embers mode -----------------------------------------------------------

func _enter_embers() -> void:
	_knob_box.add_child(_label("Ember Spray (NEW)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Click the playfield to fire at the cursor.", FS_CAPTION, UiTheme.COLOR_FAINT))
	var inv := CheckButton.new()
	inv.text = "Inverted ramp (heat-up)"
	inv.button_pressed = _ember_inverted
	inv.add_theme_font_override("font", UiTheme.active_font())
	inv.add_theme_font_size_override("font_size", FS_BODY)
	inv.toggled.connect(func(v: bool): _ember_inverted = v)
	_knob_box.add_child(inv)
	_add_action("Fire Burst", func(): _fire_embers(Vector2(Playfield.CENTER.x, 170.0)))
	_add_action("Fire + Explosion", func():
		var pos := Vector2(Playfield.CENTER.x, 170.0)
		ExplosionFx.play(pos, 1.0, true, _stage)
		_fire_embers(pos))
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Embers")


func _fire_embers(pos: Vector2) -> void:
	var v: Dictionary = _values["Embers"]
	var dir := Vector2.RIGHT.rotated(deg_to_rad(float(v["angle_deg"])))
	EmberFx.spray(_stage, pos, dir, {
		"amount": int(v["amount"]),
		"lifetime": float(v["lifetime"]),
		"explosiveness": float(v["explosiveness"]),
		"spread_deg": float(v["spread_deg"]),
		"speed_min": float(v["speed_min"]),
		"speed_max": float(v["speed_max"]),
		"drag": float(v["drag"]),
		"gravity": float(v["gravity"]),
		"streak_sec": float(v["streak_sec"]),
		"cool_bias": float(v["cool_bias"]),
		"fade_start": float(v["fade_start"]),
		"lifetime_rand": float(v["lifetime_rand"]),
		"inverted": _ember_inverted,
	})


# ---- Shields mode ----------------------------------------------------------

func _enter_shields() -> void:
	var y := 150.0
	var left := Vector2(Playfield.CENTER.x - 50.0, y)
	var right := Vector2(Playfield.CENTER.x + 50.0, y)

	var old_ship := _make_ship(left)
	var old_ring := _add_ring(old_ship, SCI_FI_SHIELD, 26.0)
	_scifi_mat = old_ring["mat"]

	var new_ship := _make_ship(right)
	var new_ring := _add_ring(new_ship, HEX_SHIELD, float(_values["Shields"]["ring_px"]))
	_hex_mat = new_ring["mat"]
	_hex_rect = new_ring["rect"]
	_apply_shield_knobs()

	_hd_note("SCI-FI (CURRENT)", left + Vector2(-22.0, 18.0))
	_hd_note("HEX (NEW)", right + Vector2(-14.0, 18.0))

	_knob_box.add_child(_label("Hex Shield (NEW)", FS_BODY, UiTheme.COLOR_ACCENT))
	_add_action("Pulse Hit (both)", _pulse_shields)
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Shields")


func _pulse_shields() -> void:
	for mat in [_scifi_mat, _hex_mat]:
		if mat == null:
			continue
		var m: ShaderMaterial = mat
		m.set_shader_parameter("hit_strength", 1.0)
		var tw := create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("hit_strength", v), 1.0, 0.0, 0.45)


func _apply_shield_knobs() -> void:
	if _hex_mat == null:
		return
	var v: Dictionary = _values["Shields"]
	_hex_mat.set_shader_parameter("cells", float(v["cells"]))
	_hex_mat.set_shader_parameter("scroll", Vector2(float(v["scroll_x"]), float(v["scroll_y"])))
	_hex_mat.set_shader_parameter("line_width", float(v["line_width"]))
	_hex_mat.set_shader_parameter("rim_power", float(v["rim_power"]))
	_hex_mat.set_shader_parameter("fill_alpha", float(v["fill_alpha"]))
	_hex_mat.set_shader_parameter("flicker", float(v["flicker"]))
	_hex_mat.set_shader_parameter("dome", float(v["dome"]))
	if _hex_rect != null:
		var s := float(v["ring_px"])
		_hex_rect.size = Vector2(s, s)
		_hex_rect.position = Vector2(-s / 2.0, -s / 2.0)


# ---- Glow mode -------------------------------------------------------------

func _enter_glow() -> void:
	# Two rows of enemy bullets: top row RAW, bottom row with the per-sprite
	# glow_halo bloom — so you can read the bloom against the bare sprite for
	# each bullet type. Plus a bright orb for the screen-glow overlay to bloom.
	var n := BULLETS.size()
	var spacing := 38.0
	var x0 := Playfield.CENTER.x - (n - 1) * spacing * 0.5
	var raw_y := 95.0
	var glow_y := 150.0
	for i in n:
		var bx := x0 + i * spacing
		_make_bullet(Vector2(bx, raw_y), BULLETS[i])
		var lit := _make_bullet(Vector2(bx, glow_y), BULLETS[i])
		GlowShaderFx.apply(lit.get_node("Bullet"))

	var orb_pos := Vector2(Playfield.CENTER.x, 215.0)
	_orb = Sprite2D.new()
	_orb.texture = _orb_texture()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_orb.material = add_mat
	_orb_home = orb_pos
	_orb.position = orb_pos
	_stage.add_child(_orb)

	_glow_rect = ColorRect.new()
	_glow_rect.size = Vector2(480, 270)
	_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_rect.z_index = 100
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = SCREEN_GLOW
	_glow_rect.material = _glow_mat
	_stage.add_child(_glow_rect)
	_apply_glow_knobs()

	_hd_note("RAW BULLETS", Vector2(x0 - 16.0, raw_y - 22.0))
	_hd_note("+ GLOW HALO (CURRENT)", Vector2(x0 - 16.0, glow_y + 16.0))
	_hd_note("BRIGHT ORB", orb_pos + Vector2(-16.0, 16.0))

	_knob_box.add_child(_label("Screen Glow (NEW)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Whole-screen mip-pyramid bloom vs the\nper-sprite glow_halo on the bullet row.", FS_CAPTION, UiTheme.COLOR_FAINT))
	var chk := CheckButton.new()
	chk.text = "Screen glow ON"
	chk.button_pressed = true
	chk.add_theme_font_override("font", UiTheme.active_font())
	chk.add_theme_font_size_override("font_size", FS_BODY)
	chk.toggled.connect(func(v: bool):
		if _glow_rect != null:
			_glow_rect.visible = v)
	_knob_box.add_child(chk)
	_add_action("Fire Embers (current knobs)", func(): _fire_embers(Vector2(Playfield.CENTER.x, 200.0)))
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Glow")


func _apply_glow_knobs() -> void:
	if _glow_mat == null:
		return
	var v: Dictionary = _values["Glow"]
	_glow_mat.set_shader_parameter("threshold", float(v["threshold"]))
	_glow_mat.set_shader_parameter("knee", float(v["knee"]))
	_glow_mat.set_shader_parameter("intensity", float(v["intensity"]))
	_glow_mat.set_shader_parameter("max_lod", int(v["max_lod"]))


# ---- Player Modes mode -----------------------------------------------------

func _enter_modes() -> void:
	_pm_home = Vector2(Playfield.CENTER.x, 135.0)
	_pm_ship = _make_ship(_pm_home)

	_hd_note("PLAYER MODE TELLS", _pm_home + Vector2(-34.0, -34.0))

	_knob_box.add_child(_label("Player Modes", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("The Shift-stance visual tells, as replicated\nin player.gd (glow/tint/outline/ghosts).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_pm_status = _label("Mode: off", FS_CAPTION, UiTheme.COLOR_BOUNTY)
	_knob_box.add_child(_pm_status)
	_add_action("Off", func(): _set_player_mode("off"))
	_add_action("Focus  (cyan glow + tint + hit dot)", func(): _set_player_mode("focus"))
	_add_action("Phase  (blue glow + afterimage ghosts)", func(): _set_player_mode("phase"))
	_add_action("Hyper  (pulsing orange outline)", func(): _set_player_mode("hyper"))
	_set_player_mode("focus")


func _set_player_mode(m: String) -> void:
	_clear_player_fx()
	_pm_mode = m
	_pm_t = 0.0
	_pm_phase_acc = 0.0
	_pm_hyper_t = 0.0
	if _pm_ship == null or not is_instance_valid(_pm_ship):
		return
	_pm_ship.position = _pm_home
	var ship: Sprite2D = _pm_ship.get_node("Ship")
	ship.modulate = Color(1, 1, 1, 1)
	match m:
		"focus":
			ship.modulate = FOCUS_SHIP_TINT
			_pm_glow = GlowShaderFx.apply(ship, FOCUS_GLOW_COLOR)
			_pm_dot = _make_focus_dot(ship)
		"phase":
			_pm_glow = GlowShaderFx.apply(ship, PHASE_GLOW_COLOR)
		"hyper":
			_pm_outline = OutlineFx.apply(ship, HYPER_OUTLINE_COLOR)
	if _pm_status != null and is_instance_valid(_pm_status):
		_pm_status.text = "Mode: %s" % m


func _clear_player_fx() -> void:
	for n in [_pm_glow, _pm_outline, _pm_dot]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_pm_glow = null
	_pm_outline = null
	_pm_dot = null


func _make_focus_dot(ship: Sprite2D) -> Node2D:
	var dot := Node2D.new()
	dot.name = "FocusDot"
	dot.z_index = 100
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 0.95)
	rect.size = Vector2(4, 4)
	rect.position = Vector2(-2, -2)
	dot.add_child(rect)
	ship.add_child(dot)
	return dot


func _spawn_phase_ghost() -> void:
	if _pm_ship == null or not is_instance_valid(_pm_ship):
		return
	var src: Sprite2D = _pm_ship.get_node("Ship")
	var g := Sprite2D.new()
	g.texture = src.texture
	g.hframes = src.hframes
	g.vframes = src.vframes
	g.frame = src.frame
	g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	g.global_position = src.global_position
	g.modulate = Color(PHASE_GLOW_COLOR.r, PHASE_GLOW_COLOR.g, PHASE_GLOW_COLOR.b, 0.55)
	g.z_index = -1
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = m
	_stage.add_child(g)
	var tw := create_tween()
	tw.tween_property(g, "modulate:a", 0.0, PHASE_AI_LIFETIME)
	tw.tween_callback(g.queue_free)


func _tick_modes(delta: float) -> void:
	if _pm_ship == null or not is_instance_valid(_pm_ship):
		return
	_pm_t += delta
	if _pm_mode == "phase":
		# Drift the ship so the afterimage ghosts visibly trail (in game the
		# ghosts trail because the player is moving).
		_pm_ship.position = _pm_home + Vector2(cos(_pm_t * 2.4), sin(_pm_t * 1.5)) * 42.0
		_pm_phase_acc += delta
		while _pm_phase_acc >= PHASE_AI_INTERVAL:
			_pm_phase_acc -= PHASE_AI_INTERVAL
			_spawn_phase_ghost()
	elif _pm_mode == "hyper" and _pm_outline != null and is_instance_valid(_pm_outline):
		# Pulse the orange outline (player.gd ramps the rate as the bar empties;
		# here a steady ~4 Hz is enough to read the tell).
		_pm_hyper_t += delta
		_pm_outline.self_modulate.a = 0.30 + 0.70 * (0.5 + 0.5 * sin(_pm_hyper_t * TAU * 4.0))


# ---- Explosions mode -------------------------------------------------------

func _enter_explosions() -> void:
	_expl_acc = 0.0
	_hd_note("DEFAULT", Vector2(Playfield.CENTER.x - 66.0, 70.0))
	_hd_note("SMALL CIRCLE", Vector2(Playfield.CENTER.x + 28.0, 70.0))

	_knob_box.add_child(_label("Explosions", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Both styles at native 1× scale (sprites are\n1:1 pixel-accurate — no upscaled halo).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Replay Both", _replay_explosions)
	_add_action("Replay Default", func(): _play_explosion("default", Vector2(Playfield.CENTER.x - 48.0, 130.0)))
	_add_action("Replay Small Circle", func(): _play_explosion("small_circle", Vector2(Playfield.CENTER.x + 48.0, 130.0)))
	var auto := CheckButton.new()
	auto.text = "Auto-replay loop"
	auto.button_pressed = _expl_auto
	auto.add_theme_font_override("font", UiTheme.active_font())
	auto.add_theme_font_size_override("font_size", FS_BODY)
	auto.toggled.connect(func(v: bool): _expl_auto = v)
	_knob_box.add_child(auto)
	_replay_explosions()


func _replay_explosions() -> void:
	_play_explosion("default", Vector2(Playfield.CENTER.x - 48.0, 130.0))
	_play_explosion("small_circle", Vector2(Playfield.CENTER.x + 48.0, 130.0))


func _play_explosion(variant: String, pos: Vector2) -> void:
	ExplosionFx.play(pos, 1.0, true, _stage, ExplosionFx.scene_for(variant), false)


func _tick_explosions(delta: float) -> void:
	if not _expl_auto:
		return
	_expl_acc += delta
	if _expl_acc >= 1.4:
		_expl_acc = 0.0
		_replay_explosions()


func _process(delta: float) -> void:
	if _orb != null and is_instance_valid(_orb):
		_orb_t += delta
		_orb.position = _orb_home + Vector2(cos(_orb_t * 2.0), sin(_orb_t * 2.0)) * 18.0
	match MODES[_mode]:
		"Modes":
			_tick_modes(delta)
		"Explosions":
			_tick_explosions(delta)


# Bright white-core radial orb — gives the screen glow something hot to bloom.
static func _orb_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.4, 0.9, 1.0, 0.7),
		Color(0.1, 0.4, 0.9, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 16
	t.height = 16
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# ---- Gallery mode ----------------------------------------------------------

func _enter_gallery() -> void:
	_knob_box.add_child(_label("Shader Gallery", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Every shader in the project, on a quad\nor the ship sprite (3× inspection zoom).", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 36)
	for e in GALLERY:
		dd.add_item(String(e["name"]))
	dd.select(_gallery_idx)
	dd.item_selected.connect(_show_gallery)
	_knob_box.add_child(dd)
	_gallery_pulse_btn = Button.new()
	_gallery_pulse_btn.text = "Pulse"
	UiTheme.style_button(_gallery_pulse_btn, true)
	_gallery_pulse_btn.add_theme_font_size_override("font_size", FS_BODY)
	_gallery_pulse_btn.custom_minimum_size = Vector2(0, 36)
	_gallery_pulse_btn.pressed.connect(_pulse_gallery)
	_knob_box.add_child(_gallery_pulse_btn)
	_show_gallery(_gallery_idx)


func _show_gallery(idx: int) -> void:
	_gallery_idx = idx
	for c in _stage.get_children():
		c.queue_free()
	_gallery_mat = null
	var e: Dictionary = GALLERY[idx]
	var center := Vector2(Playfield.CENTER.x, 135.0)

	if String(e["mode"]) == "glowfx":
		var bullet := _make_bullet(center, BULLETS[0])
		GlowShaderFx.apply(bullet.get_node("Bullet"))
	else:
		var shader: Shader = load(String(e["path"]))
		var mat := ShaderMaterial.new()
		mat.shader = shader
		for k in e.get("params", {}):
			mat.set_shader_parameter(k, e["params"][k])
		for k in e.get("textures", {}):
			mat.set_shader_parameter(k, _build_gallery_texture(String(e["textures"][k])))
		_gallery_mat = mat
		if String(e["mode"]) == "rect":
			var sz: Vector2 = e["size"]
			var rect := ColorRect.new()
			rect.size = sz
			rect.position = center - sz / 2.0
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.material = mat
			_stage.add_child(rect)
		else:
			var s := Sprite2D.new()
			s.texture = PLAYER_SPRITE
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.scale = Vector2(GALLERY_SPRITE_ZOOM, GALLERY_SPRITE_ZOOM)
			s.position = center
			s.material = mat
			_stage.add_child(s)

	if _gallery_pulse_btn != null:
		if e.has("pulse"):
			_gallery_pulse_btn.disabled = false
			_gallery_pulse_btn.text = "Pulse %s" % String(e["pulse"]["param"])
		else:
			_gallery_pulse_btn.disabled = true
			_gallery_pulse_btn.text = "Pulse (n/a)"


func _pulse_gallery() -> void:
	var e: Dictionary = GALLERY[_gallery_idx]
	if _gallery_mat == null or not e.has("pulse"):
		return
	var p: Dictionary = e["pulse"]
	var m: ShaderMaterial = _gallery_mat
	var param := String(p["param"])
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter(param, v), float(p["from"]), float(p["to"]), float(p["time"]))


func _build_gallery_texture(kind: String) -> Texture2D:
	match kind:
		"noise":
			var n := FastNoiseLite.new()
			n.frequency = 0.08
			var t := NoiseTexture2D.new()
			t.noise = n
			t.width = 64
			t.height = 64
			return t
		"fire_ramp":
			var g := Gradient.new()
			g.colors = PackedColorArray([
				Color("ffffff"), Color("fbd12f"), Color("ff4b00"), Color("8a1000"), Color("100605"),
			])
			g.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.7, 1.0])
			var gt := GradientTexture1D.new()
			gt.gradient = g
			return gt
		"scheme":
			var g2 := Gradient.new()
			g2.colors = PackedColorArray([
				Color(0.05, 0.02, 0.12, 0.0), Color(0.25, 0.1, 0.45, 0.6), Color(0.7, 0.35, 0.8, 1.0),
			])
			g2.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
			var gt2 := GradientTexture1D.new()
			gt2.gradient = g2
			return gt2
	return null


# ---- Knob rail -------------------------------------------------------------

func _build_knobs(mode: String) -> void:
	for def in KNOBS[mode]:
		_add_knob(def, mode)


func _add_knob(def: Dictionary, mode: String) -> void:
	var key := String(def["key"])
	var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(_values[mode][key]), float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
	_knob_box.add_child(row_lbl)
	var sl := HSlider.new()
	sl.min_value = float(def["min"])
	sl.max_value = float(def["max"])
	sl.step = float(def["step"])
	sl.value = float(_values[mode][key])
	sl.custom_minimum_size = Vector2(0, 26)
	sl.value_changed.connect(func(v: float):
		_values[mode][key] = v
		row_lbl.text = "%s: %s" % [def["label"], _fmt(v, float(def["step"]))]
		_apply_live())
	_knob_box.add_child(sl)


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return str(int(v))
	return "%.3f" % v if step < 0.01 else "%.2f" % v


func _apply_live() -> void:
	match MODES[_mode]:
		"Shields":
			_apply_shield_knobs()
		"Glow":
			_apply_glow_knobs()


func _add_action(text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	UiTheme.style_button(btn, true)
	btn.add_theme_font_size_override("font_size", FS_BODY)
	btn.custom_minimum_size = Vector2(0, 36)
	btn.pressed.connect(cb)
	_knob_box.add_child(btn)


# ---- Stage helpers ---------------------------------------------------------

func _make_ship(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	var s := Sprite2D.new()
	s.name = "Ship"
	s.texture = PLAYER_SPRITE
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.add_child(s)
	_stage.add_child(n)
	return n


# An enemy-bullet sprite (frame 0 of its strip) under a Node2D, so GlowShaderFx
# can attach a sibling halo. `spec` = a BULLETS entry {path, frames}.
func _make_bullet(pos: Vector2, spec: Dictionary) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	var s := Sprite2D.new()
	s.name = "Bullet"
	s.texture = load(String(spec["path"]))
	s.hframes = int(spec["frames"])
	s.frame = 0
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.add_child(s)
	_stage.add_child(n)
	return n


func _add_ring(ship: Node2D, shader: Shader, size_px: float) -> Dictionary:
	var rect := ColorRect.new()
	rect.size = Vector2(size_px, size_px)
	rect.position = Vector2(-size_px / 2.0, -size_px / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("alpha", 1.0)
	rect.material = mat
	ship.add_child(rect)
	return {"rect": rect, "mat": mat}


# Annotation over the preview: preview coords × 4 = HD coords.
func _hd_note(text: String, preview_pos: Vector2) -> void:
	var l := _label(text, FS_CAPTION, UiTheme.COLOR_BOUNTY)
	l.position = preview_pos * 4.0
	_mode_overlay.add_child(l)


# ---- Persistence + Copy GDScript -------------------------------------------

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_values, "\t"))
		f.close()
	_note.text = "Saved %s" % SAVE_PATH


func _load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		for mode in _values:
			var saved: Dictionary = data.get(mode, {})
			for key in _values[mode]:
				if saved.has(key):
					_values[mode][key] = float(saved[key])


func _on_copy() -> void:
	var txt := ""
	match MODES[_mode]:
		"Embers":
			txt = _snippet_embers()
		"Shields":
			txt = _snippet_shields()
		"Glow":
			txt = _snippet_glow()
		"Modes":
			txt = _snippet_modes()
		"Explosions":
			txt = _snippet_explosions()
		"Gallery":
			var e: Dictionary = GALLERY[_gallery_idx]
			txt = "# Shader Lab gallery — %s\n# %s\n" % [e["name"], e["path"]]
	DisplayServer.clipboard_set(txt)
	_note.text = "Copied GDScript to clipboard"


func _snippet_embers() -> String:
	var v: Dictionary = _values["Embers"]
	var t := "# Shader Lab — ember spray\n"
	t += "# const EmberFx = preload(\"res://scripts/effects/ember_fx.gd\")\n"
	t += "EmberFx.spray(get_tree().root, global_position,\n"
	t += "\tVector2.RIGHT.rotated(deg_to_rad(%.1f)), {\n" % float(v["angle_deg"])
	t += "\t\"amount\": %d, \"lifetime\": %.2f, \"explosiveness\": %.2f,\n" % [int(v["amount"]), float(v["lifetime"]), float(v["explosiveness"])]
	t += "\t\"spread_deg\": %.1f, \"speed_min\": %.1f, \"speed_max\": %.1f,\n" % [float(v["spread_deg"]), float(v["speed_min"]), float(v["speed_max"])]
	t += "\t\"drag\": %.2f, \"gravity\": %.1f, \"streak_sec\": %.3f,\n" % [float(v["drag"]), float(v["gravity"]), float(v["streak_sec"])]
	t += "\t\"cool_bias\": %.2f, \"fade_start\": %.2f, \"lifetime_rand\": %.2f,\n" % [float(v["cool_bias"]), float(v["fade_start"]), float(v["lifetime_rand"])]
	t += "\t\"inverted\": %s,\n" % ("true" if _ember_inverted else "false")
	t += "})\n"
	return t


func _snippet_modes() -> String:
	var t := "# Shader Lab — player-mode tells live in scripts/player.gd:\n"
	t += "#   Focus: $Ship.modulate = Color(0.5,0.7,1.0,0.55)\n"
	t += "#          GlowShaderFx.apply($Ship, Color(0.5,0.9,1.0)) + 4px hit dot\n"
	t += "#   Phase: GlowShaderFx.apply($Ship, Color(0.2,0.5,1.0)) + additive ghosts\n"
	t += "#   Hyper: OutlineFx.apply($Ship, Color(1.0,0.5,0.0)) pulsing alpha\n"
	t += "# This mode is a read-only showcase; tune the source constants in player.gd.\n"
	return t


func _snippet_explosions() -> String:
	var t := "# Shader Lab — explosions (scripts/effects/explosion_fx.gd)\n"
	t += "ExplosionFx.play(global_position, 1.0)                              # default\n"
	t += "ExplosionFx.play(global_position, 1.0, true, null,\n"
	t += "\tExplosionFx.scene_for(\"small_circle\"))                          # small circle\n"
	t += "# Sprites render at native 1× (halo matched to core, no upscale).\n"
	return t


func _snippet_shields() -> String:
	var v: Dictionary = _values["Shields"]
	var s := float(v["ring_px"])
	var t := "# Shader Lab — hex shield (drop-in for sci_fi_shield drivers:\n"
	t += "# swap the SHIELD_SHADER preload in player.gd / shield_component.gd)\n"
	t += "# ring ColorRect size: %d×%d (offset %.1f, %.1f)\n" % [int(s), int(s), -s / 2.0, -s / 2.0]
	t += "mat.shader = preload(\"res://graphics/hex_shield.gdshader\")\n"
	t += "mat.set_shader_parameter(\"cells\", %.1f)\n" % float(v["cells"])
	t += "mat.set_shader_parameter(\"scroll\", Vector2(%.2f, %.2f))\n" % [float(v["scroll_x"]), float(v["scroll_y"])]
	t += "mat.set_shader_parameter(\"line_width\", %.2f)\n" % float(v["line_width"])
	t += "mat.set_shader_parameter(\"rim_power\", %.1f)\n" % float(v["rim_power"])
	t += "mat.set_shader_parameter(\"fill_alpha\", %.2f)\n" % float(v["fill_alpha"])
	t += "mat.set_shader_parameter(\"flicker\", %.2f)\n" % float(v["flicker"])
	t += "mat.set_shader_parameter(\"dome\", %.2f)\n" % float(v["dome"])
	return t


func _snippet_glow() -> String:
	var v: Dictionary = _values["Glow"]
	var t := "# Shader Lab — screen glow overlay (last child of the gameplay viewport)\n"
	t += "var glow_rect := ColorRect.new()\n"
	t += "glow_rect.size = Vector2(480, 270)\n"
	t += "glow_rect.z_index = 100\n"
	t += "glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE\n"
	t += "var m := ShaderMaterial.new()\n"
	t += "m.shader = preload(\"res://graphics/screen_glow.gdshader\")\n"
	t += "m.set_shader_parameter(\"threshold\", %.2f)\n" % float(v["threshold"])
	t += "m.set_shader_parameter(\"knee\", %.2f)\n" % float(v["knee"])
	t += "m.set_shader_parameter(\"intensity\", %.2f)\n" % float(v["intensity"])
	t += "m.set_shader_parameter(\"max_lod\", %d)\n" % int(v["max_lod"])
	t += "glow_rect.material = m\n"
	t += "add_child(glow_rect)\n"
	return t


# ---- Input + back ----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if MODES[_mode] != "Embers":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# The playspace fills the HD logical viewport; map the HD mouse position
		# back into native 480×270 stage coords.
		var vp := get_viewport_rect().size
		if vp.x <= 0.0 or vp.y <= 0.0:
			return
		var gmp := get_global_mouse_position()
		var pos := Vector2(gmp.x / vp.x * 480.0, gmp.y / vp.y * 270.0)
		if pos.x >= Playfield.X_MIN and pos.x <= Playfield.X_MAX and pos.y >= 0.0 and pos.y <= 270.0:
			_fire_embers(pos)


func _on_back() -> void:
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---- UI helpers ------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_top = 10
	sb.content_margin_right = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.size = sz
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel
