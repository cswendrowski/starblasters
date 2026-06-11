extends Control

# Shader Lab (Roman 2026-06-10) — fire the NEW shader effects in the native
# 480×270 SubViewport and compare them against what's in-game today, without
# the GIF-capture loop:
#   Embers      — ember_spray burst, normal / inverted, tunable colour ramp
#   Smoke       — SmokeTrailFx smoke trail (light → dark), tunable colours
#   Shields     — sci_fi_shield ring (current) vs hex_shield (new) side by side
#   Glow        — diffuse glow_halo (per-sprite) on enemy bullets
#   Bloom Env   — the Godot WorldEnvironment glow (main.tscn's combat bloom)
#   Modes       — Focus / Phase / Hyper player-mode tells (moving ship)
#   Damage      — damage_noise overlay tuner (enemy hull erosion)
#   Disintegrate— pixelated_burn tuner (death burn-away)
#   Explosions  — default / small-circle / small→default combo, replayable
#   Gallery     — every other shader in the project on a test quad / sprite
# Right rail = knobs per mode, persisted to user://tuners/shader_lab.json +
# Copy GDScript (tuner contract). Esc / Back returns to the dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const Playfield = preload("res://scripts/playfield.gd")
const EmberFx = preload("res://scripts/effects/ember_fx.gd")
const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const OutlineFx = preload("res://scripts/effects/outline_fx.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")

# Live player ship sheet (3-hframe banking sheet; middle frame = level flight).
# We crop the middle frame into a standalone single-frame texture so shader UVs
# span 0..1 cleanly — see _ship_texture().
const PLAYER_BODY_PATH := "res://graphics/player/player_ship_a_body.png"

const SCI_FI_SHIELD: Shader = preload("res://graphics/sci_fi_shield.gdshader")
const HEX_SHIELD: Shader = preload("res://graphics/hex_shield.gdshader")
const DAMAGE_SHADER: Shader = preload("res://graphics/damage_noise.gdshader")
const BURN_SHADER: Shader = preload("res://graphics/pixelated_burn.gdshader")
const SMOKE_TRAIL_FX = preload("res://scripts/effects/smoke_trail_fx.gd")

# Real in-game damage-overlay resources (so the tuner matches enemy_base.gd).
const DAMAGE_NOISE_TEX_PATH := "res://resources/noise_damage.tres"
const DAMAGE_EDGE_TEX_PATH := "res://resources/edge_distance_flat.tres"

# Player-mode tells (mirrors the constants in player.gd so the lab matches the
# game — keep in sync if those change).
const FOCUS_GLOW_COLOR := Color(0.5, 0.9, 1.0)
const FOCUS_SHIP_TINT := Color(0.5, 0.7, 1.0, 0.55)
const PHASE_GLOW_COLOR := Color(0.2, 0.5, 1.0)
const HYPER_OUTLINE_COLOR := Color(1.0, 0.5, 0.0)
const PHASE_AI_INTERVAL := 0.06
const PHASE_AI_LIFETIME := 0.34
const FOCUS_TRAIL_LEN := 18
const HYPER_PULSE_HZ_SLOW := 2.0
const HYPER_PULSE_HZ_FAST := 9.0
# Modes ship is zoomed for inspection (native ship is 16px — the phase glow
# halo and the 1px hyper outline are invisible at 1×). Same idea as the
# Damage/Disintegrate tuners.
const MODE_ZOOM := 3.0

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

const MODES := ["Embers", "Smoke", "Shields", "Glow", "Bloom Env", "Modes", "Damage", "Disintegrate", "Explosions", "Gallery"]

const EMBER_VARIANTS := ["normal", "inverted"]

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
	"Smoke": [
		{"key": "amount", "label": "Particles", "min": 4.0, "max": 96.0, "step": 1.0, "def": 26.0},
		{"key": "lifetime", "label": "Lifetime (s)", "min": 0.3, "max": 3.0, "step": 0.05, "def": 1.1},
		{"key": "speed_min", "label": "Speed min", "min": 0.0, "max": 80.0, "step": 1.0, "def": 6.0},
		{"key": "speed_max", "label": "Speed max", "min": 0.0, "max": 120.0, "step": 1.0, "def": 22.0},
		{"key": "gravity", "label": "Gravity (rise<0)", "min": -60.0, "max": 60.0, "step": 1.0, "def": -8.0},
		{"key": "scale_min", "label": "Scale min", "min": 0.1, "max": 3.0, "step": 0.05, "def": 0.5},
		{"key": "scale_max", "label": "Scale max", "min": 0.1, "max": 3.0, "step": 0.05, "def": 1.0},
		{"key": "scale_grow", "label": "Grow ×", "min": 0.5, "max": 5.0, "step": 0.1, "def": 2.4},
		{"key": "spread_deg", "label": "Spread (deg)", "min": 0.0, "max": 180.0, "step": 1.0, "def": 18.0},
		{"key": "jitter_deg", "label": "Angle jitter (deg)", "min": 0.0, "max": 90.0, "step": 1.0, "def": 18.0},
	],
	"Glow": [],
	"Bloom Env": [
		{"key": "glow_intensity", "label": "Glow intensity", "min": 0.0, "max": 4.0, "step": 0.05, "def": 0.6},
		{"key": "glow_strength", "label": "Glow strength", "min": 0.0, "max": 2.0, "step": 0.05, "def": 1.0},
		{"key": "glow_bloom", "label": "Glow bloom", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.0},
		{"key": "glow_hdr_threshold", "label": "HDR threshold", "min": 0.0, "max": 2.0, "step": 0.05, "def": 0.0},
	],
	"Modes": [],
	"Damage": [
		{"key": "sensitivity", "label": "Sensitivity (dmg)", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.4},
		{"key": "max_strength", "label": "Max strength", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.6},
		{"key": "edge_bias_strength", "label": "Edge bias", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.4},
		{"key": "details_opacity", "label": "Details opacity", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.2},
	],
	"Disintegrate": [
		{"key": "borderWidth", "label": "Border width", "min": 0.02, "max": 0.5, "step": 0.01, "def": 0.3},
		{"key": "burnMult", "label": "Burn noise", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.5},
		{"key": "pixel_size", "label": "Pixel size", "min": 0.005, "max": 0.1, "step": 0.005, "def": 0.05},
		{"key": "blend_steps", "label": "Blend steps", "min": 2.0, "max": 12.0, "step": 1.0, "def": 12.0},
		{"key": "duration", "label": "Burn duration (s)", "min": 0.2, "max": 2.0, "step": 0.05, "def": 0.45},
	],
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
var _ember_variant: String = "normal"
# Tunable ember colour ramp: [{ "color": Color, "offset": float }, ...].
var _ember_stops: Array = []

# Smoke-trail showcase state.
var _smoke_host: Node2D = null
var _smoke_trail: GPUParticles2D = null
var _smoke_t: float = 0.0
var _smoke_orient: bool = true
var _smoke_colors := {"start_color": Color("bfc8c3"), "end_color": Color("100c08")}

# Player-modes showcase state.
var _pm_ship: Node2D = null
var _pm_glow: CanvasItem = null
var _pm_outline: Sprite2D = null
var _pm_dot: Node2D = null
var _pm_trail: Line2D = null
var _pm_trail_pts: PackedVector2Array = PackedVector2Array()
var _pm_mode: String = "off"
var _pm_home: Vector2 = Vector2.ZERO
var _pm_t: float = 0.0
var _pm_phase_acc: float = 0.0
var _pm_hyper_t: float = 0.0
var _pm_status: Label = null

# Bloom Env (WorldEnvironment glow) state.
var _env: Environment = null

# Damage / Disintegrate tuner state.
var _dmg_mat: ShaderMaterial = null
var _burn_mat: ShaderMaterial = null
# Tunable damage-overlay colours (defaults = damage_noise.gdshader defaults).
var _dmg_colors := {
	"replace_color": Color(0.0, 0.0, 0.0, 1.0),
	"edge_color": Color(0.984, 0.949, 0.212, 1.0),
	"details_color": Color(0.85, 0.45, 0.05, 1.0),
}

# Explosions showcase: replay-loop timer.
var _expl_acc: float = 0.0
var _expl_auto: bool = true

static var _ship_tex: Texture2D = null


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_values()
	_init_ember_stops()
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
	# Render via a SubViewportContainer that draws the viewport canvas DIRECTLY,
	# with a 4× content root so the 480-authored coords fill the stretched
	# 1920×1080 viewport at HIGH resolution. The earlier add_upscaled_backdrop
	# path rendered at native 480×270 then NEAREST-upscaled 4× through a
	# ViewportTexture — which both BLOCKED/blurred the diffuse glow_halo AND
	# mis-composited additive blends (the same bug the hangar V6 hit). At 1920-res
	# the glow's LINEAR filter stays smooth while pixel-art sprites keep their own
	# NEAREST crispness — matching the game's canvas_items look (Roman 2026-06-10).
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)  # stretch=true resizes this to 1920×1080
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	_preview_vp.use_hdr_2d = true  # screen_glow + bloom-env modes need HDR
	sub_container.add_child(_preview_vp)

	# 4× content root — 480-authored coords map onto the 1920×1080 viewport at HD.
	var hi := Node2D.new()
	hi.name = "HiRes"
	hi.scale = Vector2(4, 4)
	_preview_vp.add_child(hi)

	# Background fills sit at a deeply NEGATIVE z so they never occlude effects
	# that legitimately draw behind their host sprite — the phase glow (z -1),
	# hyper outline (z -2) and phase ghosts (z -1) were rendering BEHIND an
	# opaque z=0 band and showing nothing (Roman 2026-06-10).
	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	gutter.z_index = -101
	hi.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	band.z_index = -100
	hi.add_child(band)

	_stage = Node2D.new()
	_stage.name = "Stage"
	hi.add_child(_stage)


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
	_pm_trail = null
	_pm_trail_pts = PackedVector2Array()
	_pm_status = null
	_pm_mode = "off"
	_env = null
	_dmg_mat = null
	_burn_mat = null
	_smoke_host = null
	_smoke_trail = null
	match MODES[_mode]:
		"Embers":
			_enter_embers()
		"Smoke":
			_enter_smoke()
		"Shields":
			_enter_shields()
		"Glow":
			_enter_glow()
		"Bloom Env":
			_enter_bloom_env()
		"Modes":
			_enter_modes()
		"Damage":
			_enter_damage()
		"Disintegrate":
			_enter_disintegrate()
		"Explosions":
			_enter_explosions()
		"Gallery":
			_enter_gallery()


# ---- Embers mode -----------------------------------------------------------

func _enter_embers() -> void:
	_knob_box.add_child(_label("Ember Spray (NEW)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Click the playfield to fire at the cursor.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_knob_box.add_child(_label("Ramp", FS_CAPTION, UiTheme.COLOR_FAINT))
	var ramp_dd := OptionButton.new()
	ramp_dd.add_theme_font_override("font", UiTheme.active_font())
	ramp_dd.add_theme_font_size_override("font_size", FS_BODY)
	ramp_dd.custom_minimum_size = Vector2(0, 34)
	for vn in EMBER_VARIANTS:
		ramp_dd.add_item(String(vn))
	ramp_dd.select(maxi(0, EMBER_VARIANTS.find(_ember_variant)))
	ramp_dd.item_selected.connect(func(i: int): _ember_variant = String(EMBER_VARIANTS[i]))
	_knob_box.add_child(ramp_dd)
	_add_action("Fire Burst", func(): _fire_embers(Vector2(Playfield.CENTER.x, 170.0)))
	_add_action("Fire + Explosion", func():
		var pos := Vector2(Playfield.CENTER.x, 170.0)
		ExplosionFx.play(pos, 1.0, true, _stage)
		_fire_embers(pos))
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Embers")
	# Colour-ramp editor: a stop = colour + offset (t=0 hottest → t=1 charred;
	# the inverted variant plays it in reverse).
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Colour Ramp", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Each row = colour @ offset (0 hottest → 1 char).", FS_CAPTION, UiTheme.COLOR_FAINT))
	for i in _ember_stops.size():
		_add_ember_stop_row(i)
	_add_action("Reset ramp", _reset_ember_ramp)


func _init_ember_stops() -> void:
	_ember_stops.clear()
	for i in EmberFx.DEFAULT_RAMP_COLORS.size():
		_ember_stops.append({
			"color": EmberFx.DEFAULT_RAMP_COLORS[i],
			"offset": float(EmberFx.DEFAULT_RAMP_OFFSETS[i]),
		})


func _add_ember_stop_row(i: int) -> void:
	var stop: Dictionary = _ember_stops[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cp := ColorPickerButton.new()
	cp.color = stop["color"]
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(70, 32)
	cp.color_changed.connect(func(c: Color): _ember_stops[i]["color"] = c)
	row.add_child(cp)
	var off_lbl := _label("@%.2f" % float(stop["offset"]), FS_CAPTION, UiTheme.COLOR_FAINT)
	off_lbl.custom_minimum_size = Vector2(56, 0)
	row.add_child(off_lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = float(stop["offset"])
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float):
		_ember_stops[i]["offset"] = v
		off_lbl.text = "@%.2f" % v)
	row.add_child(sl)
	_knob_box.add_child(row)


# Build a GradientTexture1D from the current stops (sorted by offset so the
# gradient is well-formed even if the sliders cross).
func _build_ember_ramp() -> GradientTexture1D:
	var sorted: Array = _ember_stops.duplicate()
	sorted.sort_custom(func(a, b): return float(a["offset"]) < float(b["offset"]))
	var colors: Array = []
	var offsets: Array = []
	for s in sorted:
		colors.append(s["color"])
		offsets.append(float(s["offset"]))
	return EmberFx.build_ramp(colors, offsets)


func _reset_ember_ramp() -> void:
	_init_ember_stops()
	_set_mode(_mode)  # rebuild the rail to show the reset colours/offsets


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
		"variant": _ember_variant,
		"gradient": _build_ember_ramp(),
	})


# ---- Smoke trail mode ------------------------------------------------------

func _enter_smoke() -> void:
	_smoke_t = 0.0
	_smoke_host = Node2D.new()
	_smoke_host.position = Vector2(Playfield.CENTER.x, 135.0)
	# Small bright marker so the emit point reads as the host moves.
	var mk := Sprite2D.new()
	mk.texture = _orb_texture()
	mk.scale = Vector2(0.4, 0.4)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mk.material = add_mat
	mk.z_index = 5
	_smoke_host.add_child(mk)
	_stage.add_child(_smoke_host)
	_rebuild_smoke()

	_hd_note("SMOKE TRAIL", Vector2(Playfield.CENTER.x - 30.0, 56.0))
	_knob_box.add_child(_label("Smoke Trail", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("12-frame smoke_pulse sprite, played once per\npuff. Born light → darkens + fades; the host\nweaves so the trail reads.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_smoke_color("Start  (fresh)", "start_color")
	_add_smoke_color("End  (aged)", "end_color")
	var ori := CheckButton.new()
	ori.text = "Orient bottom to motion"
	ori.button_pressed = _smoke_orient
	ori.add_theme_font_override("font", UiTheme.active_font())
	ori.add_theme_font_size_override("font_size", FS_BODY)
	ori.toggled.connect(func(on: bool):
		_smoke_orient = on
		_rebuild_smoke())
	_knob_box.add_child(ori)
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Smoke")


func _add_smoke_color(caption: String, key: String) -> void:
	_knob_box.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var cp := ColorPickerButton.new()
	cp.color = _smoke_colors[key]
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(0, 34)
	cp.color_changed.connect(func(c: Color):
		_smoke_colors[key] = c
		_rebuild_smoke())
	_knob_box.add_child(cp)


func _rebuild_smoke() -> void:
	if _smoke_host == null or not is_instance_valid(_smoke_host):
		return
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.queue_free()
	var v: Dictionary = _values["Smoke"]
	_smoke_trail = SMOKE_TRAIL_FX.trail(_smoke_host, Vector2.ZERO, {
		"amount": int(v["amount"]),
		"lifetime": float(v["lifetime"]),
		"speed_min": float(v["speed_min"]),
		"speed_max": float(v["speed_max"]),
		"gravity": float(v["gravity"]),
		"scale_min": float(v["scale_min"]),
		"scale_max": float(v["scale_max"]),
		"scale_grow": float(v["scale_grow"]),
		"spread_deg": float(v["spread_deg"]),
		"jitter_deg": float(v["jitter_deg"]),
		"orient": _smoke_orient,
		"start_color": _smoke_colors["start_color"],
		"end_color": _smoke_colors["end_color"],
	})


func _tick_smoke(delta: float) -> void:
	if _smoke_host == null or not is_instance_valid(_smoke_host):
		return
	_smoke_t += delta
	_smoke_host.position = Vector2(Playfield.CENTER.x, 135.0) \
		+ Vector2(sin(_smoke_t * 1.5) * 70.0, sin(_smoke_t * 1.0 + 0.6) * 38.0)


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
	# Showcase the in-game DIFFUSE glow — the per-sprite glow_halo bloom — on a
	# centred column of enemy bullets. (The screen_glow / 2D-glow overlay was
	# dropped here: it wasn't working. The renderer bloom lives in Bloom Env.)
	var n := BULLETS.size()
	var spacing := 30.0
	var col_h := (n - 1) * spacing
	var y0 := 135.0 - col_h * 0.5
	var cx := Playfield.CENTER.x
	for i in n:
		var b := _make_bullet(Vector2(cx, y0 + i * spacing), BULLETS[i])
		GlowShaderFx.apply(b.get_node("Bullet"))

	_hd_note("DIFFUSE GLOW (glow_halo)", Vector2(cx - 58.0, y0 - 22.0))
	_knob_box.add_child(_label("Diffuse Glow", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Per-sprite glow_halo on each enemy bullet —\nthe current in-game glow.", FS_CAPTION, UiTheme.COLOR_FAINT))


# ---- Player Modes mode -----------------------------------------------------

func _enter_modes() -> void:
	_pm_home = Vector2(Playfield.CENTER.x, 135.0)
	_pm_ship = _make_ship(_pm_home)
	_pm_ship.scale = Vector2(MODE_ZOOM, MODE_ZOOM)

	_hd_note("PLAYER MODE TELLS (3x)", _pm_home + Vector2(-40.0, -46.0))

	_knob_box.add_child(_label("Player Modes", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("The Shift-stance tells, matched to player.gd:\nFocus = slow + cyan glow + tint + trail + dot,\nPhase = blue glow + additive ghosts,\nHyper = ramping orange outline pulse.\nShip weaves so trail/ghosts read.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_pm_status = _label("Mode: off", FS_CAPTION, UiTheme.COLOR_BOUNTY)
	_knob_box.add_child(_pm_status)
	_add_action("Off", func(): _set_player_mode("off"))
	_add_action("Focus", func(): _set_player_mode("focus"))
	_add_action("Phase", func(): _set_player_mode("phase"))
	_add_action("Hyper", func(): _set_player_mode("hyper"))
	_set_player_mode("focus")


func _set_player_mode(m: String) -> void:
	_clear_player_fx()
	_pm_mode = m
	_pm_t = 0.0
	_pm_phase_acc = 0.0
	_pm_hyper_t = 0.0
	_pm_trail_pts = PackedVector2Array()
	if _pm_ship == null or not is_instance_valid(_pm_ship):
		return
	_pm_ship.position = _pm_home
	var ship: Sprite2D = _pm_ship.get_node("Ship")
	ship.modulate = Color(1, 1, 1, 1)
	match m:
		"focus":
			ship.modulate = FOCUS_SHIP_TINT
			_pm_glow = GlowShaderFx.apply(ship, FOCUS_GLOW_COLOR)
			_pm_trail = _make_focus_trail()
			_pm_dot = _make_focus_dot(ship)
		"phase":
			_pm_glow = GlowShaderFx.apply(ship, PHASE_GLOW_COLOR)
		"hyper":
			_pm_outline = OutlineFx.apply(ship, HYPER_OUTLINE_COLOR)
	if _pm_status != null and is_instance_valid(_pm_status):
		_pm_status.text = "Mode: %s" % m


func _clear_player_fx() -> void:
	for n in [_pm_glow, _pm_outline, _pm_dot, _pm_trail]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_pm_glow = null
	_pm_outline = null
	_pm_dot = null
	_pm_trail = null


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


# Cyan motion trail behind the focused ship (player.gd: Line2D width 2, round
# joints/caps, z 99, gradient transparent-tail → cyan head, parented to world).
func _make_focus_trail() -> Line2D:
	var t := Line2D.new()
	t.width = 2.0
	t.joint_mode = Line2D.LINE_JOINT_ROUND
	t.begin_cap_mode = Line2D.LINE_CAP_ROUND
	t.end_cap_mode = Line2D.LINE_CAP_ROUND
	t.z_index = 99
	var g := Gradient.new()
	g.set_color(0, Color(0.4, 0.7, 1.0, 0.0))
	g.set_color(1, Color(0.4, 0.7, 1.0, 0.8))
	t.gradient = g
	_stage.add_child(t)
	return t


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
	g.scale = _pm_ship.scale   # match the zoomed ship
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
	if _pm_mode == "off":
		return
	# Weave within the playfield band so the trail / ghosts read (Focus is also
	# slowed 0.55 in game — reflected by the gentler weave speed).
	var speed := 1.0 if _pm_mode != "focus" else 0.55
	var p := _pm_home + Vector2(sin(_pm_t * 1.7 * speed) * 60.0, sin(_pm_t * 1.15 * speed + 0.6) * 28.0)
	p.x = clampf(p.x, Playfield.X_MIN + 10.0, Playfield.X_MAX - 10.0)
	_pm_ship.position = p

	match _pm_mode:
		"focus":
			if _pm_trail != null and is_instance_valid(_pm_trail):
				_pm_trail_pts.append(_pm_ship.position)
				while _pm_trail_pts.size() > FOCUS_TRAIL_LEN:
					_pm_trail_pts.remove_at(0)
				_pm_trail.points = _pm_trail_pts
		"phase":
			_pm_phase_acc += delta
			while _pm_phase_acc >= PHASE_AI_INTERVAL:
				_pm_phase_acc -= PHASE_AI_INTERVAL
				_spawn_phase_ghost()
		"hyper":
			if _pm_outline != null and is_instance_valid(_pm_outline):
				# Pulse frequency ramps slow→fast like the bar emptying (player.gd
				# lerps HZ_SLOW→HZ_FAST with depletion; a sawtooth fakes that here).
				var frac: float = fmod(_pm_t * 0.25, 1.0)
				var hz: float = lerpf(HYPER_PULSE_HZ_SLOW, HYPER_PULSE_HZ_FAST, frac)
				_pm_hyper_t += delta * hz
				_pm_outline.self_modulate.a = 0.30 + 0.70 * (0.5 + 0.5 * sin(_pm_hyper_t * TAU))


# ---- Explosions mode -------------------------------------------------------

const EXPL_X := [-72.0, 0.0, 72.0]


func _enter_explosions() -> void:
	_expl_acc = 0.0
	var cx := Playfield.CENTER.x
	_hd_note("DEFAULT", Vector2(cx + EXPL_X[0] - 22.0, 70.0))
	_hd_note("SMALL", Vector2(cx + EXPL_X[1] - 16.0, 70.0))
	_hd_note("SMALL→DEFAULT", Vector2(cx + EXPL_X[2] - 34.0, 70.0))

	_knob_box.add_child(_label("Explosions", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("All styles at native 1× (sprites 1:1 pixel-\naccurate). 3rd = small-circle spark blooming\ninto the full default boom.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Replay All", _replay_explosions)
	_add_action("Replay Default", func(): _play_explosion("default", _expl_pos(0)))
	_add_action("Replay Small Circle", func(): _play_explosion("small_circle", _expl_pos(1)))
	_add_action("Replay Small→Default", func(): _play_explosion("small_then_default", _expl_pos(2)))
	var auto := CheckButton.new()
	auto.text = "Auto-replay loop"
	auto.button_pressed = _expl_auto
	auto.add_theme_font_override("font", UiTheme.active_font())
	auto.add_theme_font_size_override("font_size", FS_BODY)
	auto.toggled.connect(func(v: bool): _expl_auto = v)
	_knob_box.add_child(auto)
	_replay_explosions()


func _expl_pos(i: int) -> Vector2:
	return Vector2(Playfield.CENTER.x + EXPL_X[i], 135.0)


func _replay_explosions() -> void:
	_play_explosion("default", _expl_pos(0))
	_play_explosion("small_circle", _expl_pos(1))
	_play_explosion("small_then_default", _expl_pos(2))


func _play_explosion(variant: String, pos: Vector2) -> void:
	ExplosionFx.play(pos, 1.0, true, _stage, ExplosionFx.scene_for(variant), false)


func _tick_explosions(delta: float) -> void:
	if not _expl_auto:
		return
	_expl_acc += delta
	if _expl_acc >= 1.6:
		_expl_acc = 0.0
		_replay_explosions()


# ---- Bloom Env mode (WorldEnvironment glow) --------------------------------

func _enter_bloom_env() -> void:
	# A real Godot WorldEnvironment glow (the same renderer bloom main.tscn uses
	# for combat) on a SubViewport — broken out from the custom glow shaders so
	# it can be tuned independently. Bright bullets + orb give it something to
	# bloom.
	var n := BULLETS.size()
	var spacing := 30.0
	var x0 := Playfield.CENTER.x - (n - 1) * spacing * 0.5
	for i in n:
		_make_bullet(Vector2(x0 + i * spacing, 110.0), BULLETS[i])

	var orb_pos := Vector2(Playfield.CENTER.x, 180.0)
	_orb = Sprite2D.new()
	_orb.texture = _orb_texture()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_orb.material = add_mat
	_orb_home = orb_pos
	_orb.position = orb_pos
	_stage.add_child(_orb)

	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CANVAS
	_env.glow_enabled = true
	we.environment = _env
	_stage.add_child(we)
	_apply_bloom_env_knobs()

	_hd_note("WORLD-ENV GLOW (combat bloom)", Vector2(x0 - 40.0, 86.0))
	_knob_box.add_child(_label("Bloom Env (WorldEnvironment)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("The renderer's built-in 2D glow — the same\nnode main.tscn uses (intensity 0.6, threshold 0).\nThis is NOT a shader; it bloates everything\nbright in the viewport.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Bloom Env")


func _apply_bloom_env_knobs() -> void:
	if _env == null:
		return
	var v: Dictionary = _values["Bloom Env"]
	_env.glow_intensity = float(v["glow_intensity"])
	_env.glow_strength = float(v["glow_strength"])
	_env.glow_bloom = float(v["glow_bloom"])
	_env.glow_hdr_threshold = float(v["glow_hdr_threshold"])


# ---- Damage tuner ----------------------------------------------------------

func _enter_damage() -> void:
	# damage_noise.gdshader (enemy hull erosion) on the ship, using the REAL
	# in-game noise + edge-distance resources so the tuner matches enemy_base.gd.
	var ship := _make_ship(Vector2(Playfield.CENTER.x, 135.0))
	var spr: Sprite2D = ship.get_node("Ship")
	spr.scale = Vector2(3, 3)   # inspection zoom (in-game it's 1×)
	_dmg_mat = ShaderMaterial.new()
	_dmg_mat.shader = DAMAGE_SHADER
	_dmg_mat.set_shader_parameter("noise_texture", load(DAMAGE_NOISE_TEX_PATH))
	_dmg_mat.set_shader_parameter("edge_distance_map", load(DAMAGE_EDGE_TEX_PATH))
	_dmg_mat.set_shader_parameter("noise_seed", 17.0)
	spr.material = _dmg_mat
	_apply_damage_knobs()

	_hd_note("DAMAGE OVERLAY", Vector2(Playfield.CENTER.x - 36.0, 90.0))
	_knob_box.add_child(_label("Damage Overlay", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("graphics/damage_noise.gdshader. In game,\nsensitivity ramps 0 (full HP) → 0.6 (1 HP).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Flash Hit", func(): _pulse_param(_dmg_mat, "flash_strength", 1.0, 0.0, 0.12))
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Damage")
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Colors", FS_BODY, UiTheme.COLOR_ACCENT))
	_add_color_picker("Replace (burnt-out)", "replace_color")
	_add_color_picker("Edge (dissolve glow)", "edge_color")
	_add_color_picker("Details", "details_color")


func _add_color_picker(caption: String, key: String) -> void:
	_knob_box.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var btn := ColorPickerButton.new()
	btn.color = _dmg_colors[key]
	btn.edit_alpha = false
	btn.custom_minimum_size = Vector2(0, 34)
	btn.color_changed.connect(func(c: Color):
		_dmg_colors[key] = c
		_apply_damage_knobs())
	_knob_box.add_child(btn)


func _apply_damage_knobs() -> void:
	if _dmg_mat == null:
		return
	var v: Dictionary = _values["Damage"]
	_dmg_mat.set_shader_parameter("sensitivity", float(v["sensitivity"]))
	_dmg_mat.set_shader_parameter("max_strength", float(v["max_strength"]))
	_dmg_mat.set_shader_parameter("edge_bias_strength", float(v["edge_bias_strength"]))
	_dmg_mat.set_shader_parameter("details_opacity", float(v["details_opacity"]))
	_dmg_mat.set_shader_parameter("replace_color", _dmg_colors["replace_color"])
	_dmg_mat.set_shader_parameter("edge_color", _dmg_colors["edge_color"])
	_dmg_mat.set_shader_parameter("details_color", _dmg_colors["details_color"])


# ---- Disintegrate (burn-away) tuner ----------------------------------------

func _enter_disintegrate() -> void:
	# pixelated_burn.gdshader — the death burn-away (in game: BurnFx.apply_burn,
	# radius 0→1.6 over 0.45s). Tune the look, hit Burn to replay the sweep.
	_expl_acc = 0.0
	var ship := _make_ship(Vector2(Playfield.CENTER.x, 135.0))
	var spr: Sprite2D = ship.get_node("Ship")
	spr.scale = Vector2(3, 3)
	_burn_mat = ShaderMaterial.new()
	_burn_mat.shader = BURN_SHADER
	_burn_mat.set_shader_parameter("noiseTexture", _build_gallery_texture("noise"))
	_burn_mat.set_shader_parameter("colorCurve", _build_gallery_texture("fire_ramp"))
	_burn_mat.set_shader_parameter("position", Vector2(0.5, 0.5))
	_burn_mat.set_shader_parameter("radius", 0.0)
	spr.material = _burn_mat
	_apply_disintegrate_knobs()

	_hd_note("BURN-AWAY", Vector2(Playfield.CENTER.x - 26.0, 90.0))
	_knob_box.add_child(_label("Disintegrate (burn-away)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("graphics/pixelated_burn.gdshader. In game,\nBurnFx.apply_burn sweeps radius 0→1.6.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Burn", _replay_burn)
	var auto := CheckButton.new()
	auto.text = "Auto-replay loop"
	auto.button_pressed = _expl_auto
	auto.add_theme_font_override("font", UiTheme.active_font())
	auto.add_theme_font_size_override("font_size", FS_BODY)
	auto.toggled.connect(func(v: bool): _expl_auto = v)
	_knob_box.add_child(auto)
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Disintegrate")
	_replay_burn()


func _apply_disintegrate_knobs() -> void:
	if _burn_mat == null:
		return
	var v: Dictionary = _values["Disintegrate"]
	_burn_mat.set_shader_parameter("borderWidth", float(v["borderWidth"]))
	_burn_mat.set_shader_parameter("burnMult", float(v["burnMult"]))
	_burn_mat.set_shader_parameter("pixel_size", float(v["pixel_size"]))
	_burn_mat.set_shader_parameter("blend_steps", float(v["blend_steps"]))


func _replay_burn() -> void:
	if _burn_mat == null:
		return
	var dur: float = float(_values["Disintegrate"]["duration"])
	_pulse_param(_burn_mat, "radius", 0.0, 1.6, dur)


func _tick_disintegrate(delta: float) -> void:
	if not _expl_auto:
		return
	_expl_acc += delta
	if _expl_acc >= float(_values["Disintegrate"]["duration"]) + 0.6:
		_expl_acc = 0.0
		_replay_burn()


# Tween a shader uniform from→to over `time` on `mat`.
func _pulse_param(mat: ShaderMaterial, param: String, from: float, to: float, time: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(param, from)
	var tw := create_tween()
	tw.tween_method(func(x: float): mat.set_shader_parameter(param, x), from, to, time)


func _process(delta: float) -> void:
	if _orb != null and is_instance_valid(_orb):
		_orb_t += delta
		_orb.position = _orb_home + Vector2(cos(_orb_t * 2.0), sin(_orb_t * 2.0)) * 18.0
	match MODES[_mode]:
		"Modes":
			_tick_modes(delta)
		"Smoke":
			_tick_smoke(delta)
		"Explosions":
			_tick_explosions(delta)
		"Disintegrate":
			_tick_disintegrate(delta)


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
			s.texture = _ship_texture()
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
		"Smoke":
			_rebuild_smoke()
		"Shields":
			_apply_shield_knobs()
		"Bloom Env":
			_apply_bloom_env_knobs()
		"Damage":
			_apply_damage_knobs()
		"Disintegrate":
			_apply_disintegrate_knobs()


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
	s.texture = _ship_texture()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.add_child(s)
	_stage.add_child(n)
	return n


# The live player ship's MIDDLE hframe (level flight), cropped into a standalone
# single-frame texture so it shows just the neutral pose AND shader UVs span
# 0..1 cleanly. Cached.
static func _ship_texture() -> Texture2D:
	if _ship_tex != null and is_instance_valid(_ship_tex):
		return _ship_tex
	var src: Texture2D = load(PLAYER_BODY_PATH)
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return null
	var fw: int = img.get_width() / 3   # 3-hframe banking sheet
	var fh: int = img.get_height()
	var mid: Image = img.get_region(Rect2i(fw, 0, fw, fh))  # frame 1 = level flight
	_ship_tex = ImageTexture.create_from_image(mid)
	return _ship_tex


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
	var out: Dictionary = _values.duplicate(true)
	var cols := {}
	for k in _dmg_colors:
		cols[k] = (_dmg_colors[k] as Color).to_html(false)
	out["DamageColors"] = cols
	var stops := []
	for s in _ember_stops:
		stops.append({"color": (s["color"] as Color).to_html(false), "offset": float(s["offset"])})
	out["EmberGradient"] = stops
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t"))
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
		var cols: Dictionary = data.get("DamageColors", {})
		for k in _dmg_colors:
			if cols.has(k):
				_dmg_colors[k] = Color(String(cols[k]))
		var stops: Array = data.get("EmberGradient", [])
		if stops.size() >= 2:
			_ember_stops.clear()
			for s in stops:
				_ember_stops.append({"color": Color(String(s["color"])), "offset": float(s["offset"])})


func _on_copy() -> void:
	var txt := ""
	match MODES[_mode]:
		"Embers":
			txt = _snippet_embers()
		"Smoke":
			txt = _snippet_smoke()
		"Shields":
			txt = _snippet_shields()
		"Glow":
			txt = _snippet_glow()
		"Bloom Env":
			txt = _snippet_bloom_env()
		"Modes":
			txt = _snippet_modes()
		"Damage":
			txt = _snippet_damage()
		"Disintegrate":
			txt = _snippet_disintegrate()
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
	t += "\t\"variant\": \"%s\",\n" % _ember_variant
	var sorted: Array = _ember_stops.duplicate()
	sorted.sort_custom(func(a, b): return float(a["offset"]) < float(b["offset"]))
	var cs := PackedStringArray()
	var os := PackedStringArray()
	for s in sorted:
		var c: Color = s["color"]
		cs.append("Color(%.3f, %.3f, %.3f)" % [c.r, c.g, c.b])
		os.append("%.2f" % float(s["offset"]))
	t += "\t\"gradient\": EmberFx.build_ramp([%s], [%s]),\n" % [", ".join(cs), ", ".join(os)]
	t += "})\n"
	return t


func _snippet_smoke() -> String:
	var v: Dictionary = _values["Smoke"]
	var sc: Color = _smoke_colors["start_color"]
	var ec: Color = _smoke_colors["end_color"]
	var t := "# Shader Lab — smoke trail\n"
	t += "# const SmokeTrailFx = preload(\"res://scripts/effects/smoke_trail_fx.gd\")\n"
	t += "# Add the returned emitter as a child of a moving node for a trail.\n"
	t += "SmokeTrailFx.trail(get_tree().root, global_position, {\n"
	t += "\t\"amount\": %d, \"lifetime\": %.2f,\n" % [int(v["amount"]), float(v["lifetime"])]
	t += "\t\"speed_min\": %.1f, \"speed_max\": %.1f, \"gravity\": %.1f,\n" % [float(v["speed_min"]), float(v["speed_max"]), float(v["gravity"])]
	t += "\t\"scale_min\": %.2f, \"scale_max\": %.2f, \"scale_grow\": %.2f,\n" % [float(v["scale_min"]), float(v["scale_max"]), float(v["scale_grow"])]
	t += "\t\"spread_deg\": %.1f, \"jitter_deg\": %.1f, \"orient\": %s,\n" % [float(v["spread_deg"]), float(v["jitter_deg"]), ("true" if _smoke_orient else "false")]
	t += "\t\"start_color\": Color(\"%s\"), \"end_color\": Color(\"%s\"),\n" % [sc.to_html(false), ec.to_html(false)]
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
	t += "ExplosionFx.play(global_position, 1.0, true, null,\n"
	t += "\tExplosionFx.scene_for(\"small_then_default\"))                    # spark → big boom\n"
	t += "# Sprites render at native 1× (halo matched to core, no upscale).\n"
	return t


func _snippet_bloom_env() -> String:
	var v: Dictionary = _values["Bloom Env"]
	var t := "# Shader Lab — WorldEnvironment glow (matches main.tscn combat bloom)\n"
	t += "var we := WorldEnvironment.new()\n"
	t += "var env := Environment.new()\n"
	t += "env.background_mode = Environment.BG_CANVAS\n"
	t += "env.glow_enabled = true\n"
	t += "env.glow_intensity = %.2f\n" % float(v["glow_intensity"])
	t += "env.glow_strength = %.2f\n" % float(v["glow_strength"])
	t += "env.glow_bloom = %.2f\n" % float(v["glow_bloom"])
	t += "env.glow_hdr_threshold = %.2f\n" % float(v["glow_hdr_threshold"])
	t += "we.environment = env\n"
	t += "add_child(we)\n"
	return t


func _snippet_damage() -> String:
	var v: Dictionary = _values["Damage"]
	var t := "# Shader Lab — damage overlay (graphics/damage_noise.gdshader)\n"
	t += "# In game enemy_base installs this + drives sensitivity = 1 - health/max.\n"
	t += "mat.set_shader_parameter(\"sensitivity\", %.2f)\n" % float(v["sensitivity"])
	t += "mat.set_shader_parameter(\"max_strength\", %.2f)\n" % float(v["max_strength"])
	t += "mat.set_shader_parameter(\"edge_bias_strength\", %.2f)\n" % float(v["edge_bias_strength"])
	t += "mat.set_shader_parameter(\"details_opacity\", %.2f)\n" % float(v["details_opacity"])
	for k in _dmg_colors:
		var c: Color = _dmg_colors[k]
		t += "mat.set_shader_parameter(\"%s\", Color(%.3f, %.3f, %.3f))\n" % [k, c.r, c.g, c.b]
	return t


func _snippet_disintegrate() -> String:
	var v: Dictionary = _values["Disintegrate"]
	var t := "# Shader Lab — disintegrate / burn-away (graphics/pixelated_burn.gdshader)\n"
	t += "# In game: BurnFx.apply_burn(sprite, %.2f) sweeps radius 0 -> 1.6.\n" % float(v["duration"])
	t += "mat.set_shader_parameter(\"borderWidth\", %.2f)\n" % float(v["borderWidth"])
	t += "mat.set_shader_parameter(\"burnMult\", %.2f)\n" % float(v["burnMult"])
	t += "mat.set_shader_parameter(\"pixel_size\", %.3f)\n" % float(v["pixel_size"])
	t += "mat.set_shader_parameter(\"blend_steps\", %.1f)\n" % float(v["blend_steps"])
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
	var t := "# Shader Lab — diffuse glow (per-sprite glow_halo bloom)\n"
	t += "# const GlowShaderFx = preload(\"res://scripts/effects/glow_shader_fx.gd\")\n"
	t += "GlowShaderFx.apply(sprite)              # auto-derive colour\n"
	t += "GlowShaderFx.apply(sprite, override)    # force a glow colour\n"
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
