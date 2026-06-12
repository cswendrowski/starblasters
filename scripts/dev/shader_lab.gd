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
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const BURNING_TRAIL = preload("res://scenes/effects/burning_trail.tscn")
const SPARK_TRAIL = preload("res://scenes/effects/spark_trail.tscn")
const ShipDamageTells = preload("res://scripts/effects/ship_damage_tells.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const Factions = preload("res://scripts/levels/factions.gd")
# Tunable damage-tell suite, tuned PER SIZE category (Roman 2026-06-12).
const SD_DMG_SCHEMA := [
	{"key": "max_sens", "label": "Overlay max", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.85},
	{"key": "spark_start", "label": "Spark start (dmg %)", "min": 0.0, "max": 0.5, "step": 0.02, "def": 0.12},
	{"key": "burn_threshold", "label": "Burn threshold (dmg %)", "min": 0.3, "max": 1.0, "step": 0.02, "def": 0.6},
	{"key": "spark_amount", "label": "Spark amount", "min": 10.0, "max": 250.0, "step": 5.0, "def": 50.0},
	{"key": "expl_size", "label": "Death expl size", "min": 0.3, "max": 3.0, "step": 0.1, "def": 1.0},
	{"key": "expl_density", "label": "Death expl density", "min": 0.5, "max": 3.0, "step": 0.1, "def": 1.0},
	{"key": "expl_shockwave", "label": "Death shockwave", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
	{"key": "debris", "label": "Death debris ×", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
]
const SD_SIZES := ["small", "medium", "large"]
const SD_PATH_SPEED := 52.0   # px/s the ship travels along the rounded-rect path

# Live player ship sheet (3-hframe banking sheet; middle frame = level flight).
# We crop the middle frame into a standalone single-frame texture so shader UVs
# span 0..1 cleanly — see _ship_texture().
const PLAYER_BODY_PATH := "res://graphics/player/player_ship_a_body.png"

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

const MODES := ["Embers", "Smoke", "Glow", "Bloom Env", "Modes", "Damage", "Disintegrate", "Explosions", "Expl. Tuner", "Ship Dmg", "Asteroids", "Gallery"]

const EMBER_VARIANTS := ["normal", "inverted", "smoke"]

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
	"Smoke": [
		{"key": "amount", "label": "Particles", "min": 4.0, "max": 96.0, "step": 1.0, "def": 26.0},
		{"key": "lifetime", "label": "Lifetime (s)", "min": 0.3, "max": 4.0, "step": 0.05, "def": 1.6},
		{"key": "speed_min", "label": "Speed min", "min": 0.0, "max": 80.0, "step": 1.0, "def": 8.0},
		{"key": "speed_max", "label": "Speed max", "min": 0.0, "max": 120.0, "step": 1.0, "def": 26.0},
		{"key": "gravity", "label": "Gravity (rise<0)", "min": -60.0, "max": 60.0, "step": 1.0, "def": -10.0},
		{"key": "damping", "label": "Damping", "min": 0.0, "max": 30.0, "step": 0.5, "def": 8.0},
		{"key": "scale_min", "label": "Scale min", "min": 0.1, "max": 3.0, "step": 0.05, "def": 0.4},
		{"key": "scale_max", "label": "Scale max", "min": 0.1, "max": 3.0, "step": 0.05, "def": 0.8},
		{"key": "scale_grow", "label": "Grow ×", "min": 0.5, "max": 5.0, "step": 0.1, "def": 2.2},
		{"key": "spread_deg", "label": "Spread (deg)", "min": 0.0, "max": 180.0, "step": 1.0, "def": 22.0},
		{"key": "spin", "label": "Spin (deg/s)", "min": 0.0, "max": 180.0, "step": 5.0, "def": 40.0},
		{"key": "randomness", "label": "Randomness", "min": 0.0, "max": 1.0, "step": 0.05, "def": 0.5},
	],
	"Glow": [
		{"key": "threshold", "label": "Color threshold", "min": 0.0, "max": 2.0, "step": 0.01, "def": 0.45},
		{"key": "intensity", "label": "Intensity", "min": 0.0, "max": 4.0, "step": 0.05, "def": 1.8},
		{"key": "opacity", "label": "Opacity", "min": 0.0, "max": 1.0, "step": 0.02, "def": 1.0},
	],
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
	"Explosions": [
		{"key": "count", "label": "Chunk count", "min": 1.0, "max": 12.0, "step": 1.0, "def": 5.0},
		{"key": "speed_min", "label": "Speed min", "min": 10.0, "max": 200.0, "step": 5.0, "def": 50.0},
		{"key": "speed_max", "label": "Speed max", "min": 20.0, "max": 300.0, "step": 5.0, "def": 120.0},
		{"key": "gravity", "label": "Gravity", "min": 0.0, "max": 240.0, "step": 5.0, "def": 90.0},
		{"key": "drag", "label": "Drag", "min": 0.0, "max": 3.0, "step": 0.05, "def": 0.6},
		{"key": "scale_min", "label": "Piece scale min", "min": 0.4, "max": 2.0, "step": 0.05, "def": 0.9},
		{"key": "scale_max", "label": "Piece scale max", "min": 0.4, "max": 2.5, "step": 0.05, "def": 1.4},
		{"key": "burn_min", "label": "Burn time min (s)", "min": 0.5, "max": 2.5, "step": 0.05, "def": 1.25},
		{"key": "burn_max", "label": "Burn time max (s)", "min": 0.5, "max": 3.0, "step": 0.05, "def": 2.0},
		{"key": "flame_w", "label": "Flame width", "min": 0.05, "max": 1.0, "step": 0.05, "def": 0.3},
		{"key": "flame_h", "label": "Flame height", "min": 0.2, "max": 2.0, "step": 0.05, "def": 0.85},
		{"key": "flame_speed", "label": "Flame speed", "min": 0.5, "max": 6.0, "step": 0.1, "def": 2.6},
	],
	"Expl. Tuner": [
		{"key": "size", "label": "Size (scale)", "min": 0.2, "max": 5.0, "step": 0.05, "def": 1.5},
		{"key": "area", "label": "Area (px spread)", "min": 0.0, "max": 80.0, "step": 1.0, "def": 16.0},
		{"key": "duration", "label": "Duration (s/frame)", "min": 0.02, "max": 0.2, "step": 0.005, "def": 0.07},
		{"key": "density", "label": "Density (booms)", "min": 1.0, "max": 12.0, "step": 1.0, "def": 3.0},
		{"key": "stagger", "label": "Stagger (s)", "min": 0.0, "max": 0.4, "step": 0.01, "def": 0.06},
		{"key": "secondaries", "label": "Per-boom satellites", "min": 0.0, "max": 4.0, "step": 0.25, "def": 1.0},
		{"key": "glow", "label": "Glow ×", "min": 0.0, "max": 3.0, "step": 0.1, "def": 0.9},
		{"key": "shockwave", "label": "Shockwave reach", "min": 0.0, "max": 3.0, "step": 0.1, "def": 0.1},
		{"key": "sparks", "label": "Spark density", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "debris", "label": "Ember density", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
	],
	"Asteroids": [],
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
var _smoke_follow: bool = true   # stream emission behind the host's motion
var _smoke_colors := {"start_color": Color("bfc8c3"), "end_color": Color("100c08")}

# glow_effect_2d tuner state — the RIGHT comparison column's materials, live-tuned by the
# Glow knobs + colour pickers. color1/color2 are the SOURCE colours keyed for emission;
# glow_color is what those pixels bloom to (× intensity).
var _glow_fx_mats: Array = []
var _glow_fx_colors := {
	"color1": Color(1, 1, 1, 1),
	"color2": Color(1, 0.85, 0.3, 1),
	"glow_color": Color(0.4, 0.8, 1.0, 1),
}

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

# Explosion Tuner (centralized ExplosionFx.play_config) state.
var _et_type: String = "basic"
var _et_acc: float = 0.0
var _et_auto: bool = true

# Ship-Damage panel state.
var _sd_ship: Node2D = null
var _sd_tells: Node2D = null
var _sd_t: float = 0.0
var _sd_center: Vector2 = Vector2.ZERO
var _sd_radius: float = 36.0
var _sd_slider: HSlider = null
var _sd_label: Label = null
var _sd_respawn_t: float = -1.0
var _sd_path: Curve2D = null          # the rounded-rect flight path (vertical, longways)
var _sd_path_len: float = 0.0
var _sd_dist: float = 0.0             # distance travelled along the path
var _sd_size_cat: String = "medium"   # selected size category (small / medium / large)
var _sd_knob_box: VBoxContainer = null # sub-box for the per-size damage-tell knobs (rebuilt on size change)
var _sd_suite_label: Label = null     # "Damage-tell suite — <size>" header (updated on size change)
var _sd_dmg_vals: Dictionary = {}     # size → {key: value}
var _sd_dead: bool = false            # ship destroyed — stays put until New Ship (no auto-respawn)

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
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_preview_vp, "Shader Lab")   # guard: catch the corner regression


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
	# Unified to the canonical HD SubViewport host (Roman 2026-06-11): stretch_shrink=4 keeps the
	# SubViewport NATIVE 480×270 (stretch=true otherwise clobbers .size to the container's 1920×1080
	# every layout pass) and the container upscales it 4×. Replaces the old "viewport at 1920 + a 4×
	# HiRes content node" variant — same result, but now identical to parallax_tuner / hangar /
	# enemy_bench so the play area can't regress into the corner. See docs/godot-patterns.md.
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.stretch_shrink = 4
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)   # honored now (stretch_shrink=4)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	_preview_vp.use_hdr_2d = true  # screen_glow + bloom-env modes need HDR
	sub_container.add_child(_preview_vp)

	# Content lives at NATIVE 480 coords directly in the viewport (no 4× node). Background fills sit
	# at a deeply NEGATIVE z so they never occlude effects that legitimately draw behind their host
	# sprite — the phase glow (z -1), hyper outline (z -2) and phase ghosts (z -1) were rendering
	# BEHIND an opaque z=0 band and showing nothing (Roman 2026-06-10).
	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	gutter.z_index = -101
	_preview_vp.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	band.z_index = -100
	_preview_vp.add_child(band)

	_stage = Node2D.new()
	_stage.name = "Stage"
	_preview_vp.add_child(_stage)


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
	_sd_ship = null
	_sd_tells = null
	_sd_slider = null
	_sd_label = null
	_sd_respawn_t = -1.0
	match MODES[_mode]:
		"Embers":
			_enter_embers()
		"Smoke":
			_enter_smoke()
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
		"Expl. Tuner":
			_enter_expl_tuner()
		"Ship Dmg":
			_enter_ship_dmg()
		"Asteroids":
			_enter_asteroids()
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
	_knob_box.add_child(_label("Procedural white billow puff, tinted by the\ncolour ramp. Born start-colour → end-colour\nover the trail; grows + tumbles + fades. The\nhost weaves so the trail reads.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_smoke_color("Start  (front half)", "start_color")
	_add_smoke_color("End  (back half)", "end_color")
	var ori := CheckButton.new()
	ori.text = "Follow motion (stream behind)"
	ori.button_pressed = _smoke_follow
	ori.add_theme_font_override("font", UiTheme.active_font())
	ori.add_theme_font_size_override("font_size", FS_BODY)
	ori.toggled.connect(func(on: bool):
		_smoke_follow = on
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
		"damping": float(v["damping"]),
		"scale_min": float(v["scale_min"]),
		"scale_max": float(v["scale_max"]),
		"scale_grow": float(v["scale_grow"]),
		"spread_deg": float(v["spread_deg"]),
		"spin": float(v["spin"]),
		"randomness": float(v["randomness"]),
		"follow_motion": _smoke_follow,
		"start_color": _smoke_colors["start_color"],
		"end_color": _smoke_colors["end_color"],
	})


func _tick_smoke(delta: float) -> void:
	if _smoke_host == null or not is_instance_valid(_smoke_host):
		return
	_smoke_t += delta
	_smoke_host.position = Vector2(Playfield.CENTER.x, 135.0) \
		+ Vector2(sin(_smoke_t * 1.5) * 70.0, sin(_smoke_t * 1.0 + 0.6) * 38.0)


# ---- Glow mode -------------------------------------------------------------

const GLOW_EFFECT_2D: Shader = preload("res://graphics/glow_effect_2d.gdshader")


func _enter_glow() -> void:
	# Two columns of enemy bullets side by side (Roman 2026-06-11): LEFT = our current
	# per-sprite glow_halo (a soft halo BEHIND the sprite); RIGHT = the candidate
	# glow_effect_2d (color-keyed in-sprite emission, blooming through a WorldEnvironment).
	var n := BULLETS.size()
	var spacing := 30.0
	var col_h := (n - 1) * spacing
	var y0 := 135.0 - col_h * 0.5
	var cx := Playfield.CENTER.x
	var lx := cx - 40.0
	var rx := cx + 40.0
	# A WorldEnvironment glow so the color-keyed shader has something to bloom into.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_hdr_threshold = 0.9
	we.environment = env
	_stage.add_child(we)
	_glow_fx_mats.clear()
	for i in n:
		var bl := _make_bullet(Vector2(lx, y0 + i * spacing), BULLETS[i])
		GlowShaderFx.apply(bl.get_node("Bullet"))
		var br := _make_bullet(Vector2(rx, y0 + i * spacing), BULLETS[i])
		var spr: Sprite2D = br.get_node("Bullet")
		var m := ShaderMaterial.new()
		m.shader = GLOW_EFFECT_2D
		spr.material = m
		_glow_fx_mats.append(m)
	_apply_glow_fx()   # push the current tuner values into every right-column material

	_hd_note("glow_halo (current)", Vector2(lx - 56.0, y0 - 22.0))
	_hd_note("glow_effect_2d (new)", Vector2(rx - 18.0, y0 - 22.0))
	_knob_box.add_child(_label("glow_effect_2d tuner", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("LEFT: current glow_halo (soft halo behind the\nsprite). RIGHT: glow_effect_2d — tune it below.\nColor1/2 = source colours keyed for emission;\nGlow = what they bloom to (× intensity).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_glow_color("Color 1 (key — bright core)", "color1")
	_add_glow_color("Color 2 (key — warm core)", "color2")
	_add_glow_color("Glow color (bloom target)", "glow_color")
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Glow")


# Push the Glow tuner state (floats + colours) into every right-column material.
func _apply_glow_fx() -> void:
	var v: Dictionary = _values["Glow"]
	for m in _glow_fx_mats:
		if m == null or not is_instance_valid(m):
			continue
		m.set_shader_parameter("color1", _glow_fx_colors["color1"])
		m.set_shader_parameter("color2", _glow_fx_colors["color2"])
		m.set_shader_parameter("glow_color", _glow_fx_colors["glow_color"])
		m.set_shader_parameter("threshold", float(v["threshold"]))
		m.set_shader_parameter("intensity", float(v["intensity"]))
		m.set_shader_parameter("opacity", float(v["opacity"]))


func _add_glow_color(caption: String, key: String) -> void:
	_knob_box.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var cp := ColorPickerButton.new()
	cp.color = _glow_fx_colors[key]
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(0, 34)
	cp.color_changed.connect(func(c: Color):
		_glow_fx_colors[key] = c
		_apply_glow_fx())
	_knob_box.add_child(cp)


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
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Ember Debris (NEW sweetener)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Hero chunks tumble out wearing the damage\nshader, trailing ember sparks + smoke, then\nburn away (trails freed on disintegration).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Fire Ember Debris", func(): _fire_ember_debris(Vector2(Playfield.CENTER.x, 120.0)))
	_add_action("Boom + Ember Debris", func():
		var pos := Vector2(Playfield.CENTER.x, 120.0)
		ExplosionFx.play(pos, 1.5, true, _stage)
		_fire_ember_debris(pos))
	_knob_box.add_child(_label("Debris fire tuner (re-fire to apply):", FS_CAPTION, UiTheme.COLOR_FAINT))
	_build_knobs("Explosions")
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Burning Trail (particle effect)", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("scenes/effects/burning_trail.tscn — GPUParticles2D\nthat plays the explosion strip per puff (fire →\nsmoke), spins + grows. Drifts down so the trail\nreads (local_coords forced off for the preview).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Burning Trail", func(): _fire_burning_trail(false))
	_add_action("Burning Trail + Sparks", func(): _fire_burning_trail(true))
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


# Spawn a small fan of ember-debris hero chunks scattering out + down from `pos`
# (the explosion-sweetener preview).
func _fire_ember_debris(pos: Vector2) -> void:
	var v: Dictionary = _values["Explosions"]
	for i in int(v["count"]):
		# Bias the burst to the lower hemisphere like the enemy_base debris scatter.
		var ang := randf_range(0.15, PI - 0.15)
		var spd := randf_range(float(v["speed_min"]), float(v["speed_max"]))
		ShipDebrisEmber.spawn(_stage, pos, {
			"velocity": Vector2(cos(ang), sin(ang)) * spd,
			"spin": randf_range(-6.0, 6.0),
			"piece_scale": randf_range(float(v["scale_min"]), float(v["scale_max"])),
			"gravity": float(v["gravity"]),
			"drag": float(v["drag"]),
			"burn_time": randf_range(float(v["burn_min"]), float(v["burn_max"])),
			"flame_size": Vector2(float(v["flame_w"]), float(v["flame_h"])),
			"flame_speed": float(v["flame_speed"]),
		})


# Drift a few burning_trail.tscn particle emitters down across the playfield so the trail reads.
# with_sparks adds a spark_trail.tscn on each emitter (the "burning trail + sparks" variant).
func _fire_burning_trail(with_sparks: bool) -> void:
	for i in 3:
		var inst: Node2D = BURNING_TRAIL.instantiate()
		var start := Vector2(Playfield.CENTER.x + (i - 1) * 44.0, 70.0)
		inst.position = start
		# Leave the puffs behind in world space so it reads as a TRAIL as the host moves
		# (lab preview convenience — bake local_coords=false into the .tscn to keep it).
		var parts := inst.get_node_or_null("GPUParticles2D")
		if parts != null:
			parts.local_coords = false
		if with_sparks:
			# Spark trail riding the same emitter (child at origin → sparks fly off the head).
			var sp: Node2D = SPARK_TRAIL.instantiate()
			inst.add_child(sp)
			for c in sp.get_children():
				if c is GPUParticles2D:
					c.local_coords = false
		_stage.add_child(inst)
		var vel := Vector2(randf_range(-20.0, 20.0), randf_range(55.0, 85.0))
		var tw := inst.create_tween()
		tw.tween_property(inst, "position", start + vel * 2.0, 2.0)
		tw.tween_interval(1.2)   # let the last puffs finish their life before freeing
		tw.tween_callback(inst.queue_free)


func _tick_explosions(delta: float) -> void:
	if not _expl_auto:
		return
	_expl_acc += delta
	if _expl_acc >= 1.6:
		_expl_acc = 0.0
		_replay_explosions()


# ---- Explosion Tuner mode --------------------------------------------------
# Drives the centralized ExplosionFx.play_config — one config (size / area / duration / density /
# type / glow / shockwave / sparks / debris) tuned live, Copy-GDScript emits the config dict.

func _enter_expl_tuner() -> void:
	_et_acc = 0.0
	_knob_box.add_child(_label("Explosion Tuner", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("The centralized ExplosionFx.play_config —\ntune every aspect, then Copy GDScript to bake\nthe config. Universal glow + shockwave ride\nevery type.", FS_CAPTION, UiTheme.COLOR_FAINT))
	# Type selector (basic / ball).
	_knob_box.add_child(_label("Type", FS_CAPTION, UiTheme.COLOR_FAINT))
	var type_dd := OptionButton.new()
	type_dd.add_theme_font_override("font", UiTheme.active_font())
	type_dd.add_theme_font_size_override("font_size", FS_BODY)
	type_dd.custom_minimum_size = Vector2(0, 34)
	var et_types := ["basic", "ball", "mixed"]
	for tn in et_types:
		type_dd.add_item(tn)
	type_dd.select(maxi(0, et_types.find(_et_type)))
	type_dd.item_selected.connect(func(i: int): _et_type = String(et_types[i]))
	_knob_box.add_child(type_dd)
	_add_action("▶ Play Explosion", func(): _fire_expl_tuner(Vector2(Playfield.CENTER.x, 135.0)))
	var auto := CheckButton.new()
	auto.text = "Auto-replay loop"
	auto.button_pressed = _et_auto
	auto.add_theme_font_override("font", UiTheme.active_font())
	auto.add_theme_font_size_override("font_size", FS_BODY)
	auto.toggled.connect(func(v: bool): _et_auto = v)
	_knob_box.add_child(auto)
	_knob_box.add_child(HSeparator.new())
	_build_knobs("Expl. Tuner")
	_fire_expl_tuner(Vector2(Playfield.CENTER.x, 135.0))


func _expl_tuner_cfg() -> Dictionary:
	var v: Dictionary = _values["Expl. Tuner"]
	return {
		"type": _et_type,
		"size": float(v["size"]), "area": float(v["area"]), "duration": float(v["duration"]),
		"density": float(v["density"]), "stagger": float(v["stagger"]), "secondaries": float(v["secondaries"]),
		"glow": float(v["glow"]), "shockwave": float(v["shockwave"]),
		"sparks": float(v["sparks"]), "debris": float(v["debris"]),
	}


func _fire_expl_tuner(pos: Vector2) -> void:
	ExplosionFx.play_config(pos, _expl_tuner_cfg(), _stage)


func _tick_expl_tuner(delta: float) -> void:
	if not _et_auto:
		return
	_et_acc += delta
	if _et_acc >= 1.8:
		_et_acc = 0.0
		_fire_expl_tuner(Vector2(Playfield.CENTER.x, 135.0))


# ---- Ship Damage mode ------------------------------------------------------
# A random enemy ship circles the playfield; the Damage slider drives ShipDamageTells, which
# escalates the battle-damage tells (overlay → spark trails per marker → burning trail →
# disintegrate + explode at 100%). Bigger ships carry more markers, so they escalate more.

func _enter_ship_dmg() -> void:
	_sd_center = Vector2(Playfield.CENTER.x, 135.0)
	_sd_t = 0.0
	_sd_dist = 0.0
	_sd_respawn_t = -1.0
	_init_sd_dmg_vals()
	_build_sd_path()
	_knob_box.add_child(_label("Ship Damage Tells", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("A live enemy flies a rounded rectangle. Drag\nDamage to escalate the tells; tune the suite per\nSIZE below. Engine trails + glow masks intact.\n(Re-spawn to apply suite changes.)", FS_CAPTION, UiTheme.COLOR_FAINT))
	_knob_box.add_child(_label("Enemy size", FS_CAPTION, UiTheme.COLOR_FAINT))
	var size_dd := OptionButton.new()
	size_dd.add_theme_font_override("font", UiTheme.active_font())
	size_dd.add_theme_font_size_override("font_size", FS_BODY)
	size_dd.custom_minimum_size = Vector2(0, 34)
	for sn in SD_SIZES:
		size_dd.add_item(String(sn).capitalize())
	size_dd.select(maxi(0, SD_SIZES.find(_sd_size_cat)))
	size_dd.item_selected.connect(func(i: int):
		_sd_size_cat = String(SD_SIZES[i])
		if _sd_suite_label != null and is_instance_valid(_sd_suite_label):
			_sd_suite_label.text = "Damage-tell suite — %s" % _sd_size_cat.capitalize()
		_rebuild_sd_dmg_knobs()
		_spawn_sd_ship())
	_knob_box.add_child(size_dd)
	_add_action("New Ship", _spawn_sd_ship)
	_knob_box.add_child(_label("Damage", FS_CAPTION, UiTheme.COLOR_FAINT))
	_sd_slider = HSlider.new()
	_sd_slider.min_value = 0.0
	_sd_slider.max_value = 1.0
	_sd_slider.step = 0.01
	_sd_slider.value = 0.0
	_sd_slider.custom_minimum_size = Vector2(0, 30)
	_sd_slider.value_changed.connect(_on_sd_damage)
	_knob_box.add_child(_sd_slider)
	_sd_label = _label("0%", FS_CAPTION, UiTheme.COLOR_BOUNTY)
	_knob_box.add_child(_sd_label)
	_knob_box.add_child(HSeparator.new())
	_sd_suite_label = _label("Damage-tell suite — %s" % _sd_size_cat.capitalize(), FS_CAPTION, UiTheme.COLOR_ACCENT)
	_knob_box.add_child(_sd_suite_label)
	_sd_knob_box = VBoxContainer.new()
	_sd_knob_box.add_theme_constant_override("separation", 6)
	_knob_box.add_child(_sd_knob_box)
	_rebuild_sd_dmg_knobs()
	_spawn_sd_ship()


func _init_sd_dmg_vals() -> void:
	if not _sd_dmg_vals.is_empty():
		return
	for sz in SD_SIZES:
		var d := {}
		for def in SD_DMG_SCHEMA:
			d[String(def["key"])] = float(def["def"])
		_sd_dmg_vals[sz] = d
	# Differentiated per-size baselines so the suite visibly shifts out of the box (small = subtler,
	# large = more dramatic). These are just starting points — tune each from here.
	_sd_dmg_vals["small"].merge({"spark_amount": 30.0, "expl_size": 0.8, "expl_density": 1.0, "expl_shockwave": 0.6, "debris": 0.7}, true)
	_sd_dmg_vals["large"].merge({"spark_amount": 90.0, "expl_size": 1.3, "expl_density": 1.4, "expl_shockwave": 1.5, "debris": 1.4}, true)


func _rebuild_sd_dmg_knobs() -> void:
	if _sd_knob_box == null or not is_instance_valid(_sd_knob_box):
		return
	for c in _sd_knob_box.get_children():
		c.queue_free()
	var vals: Dictionary = _sd_dmg_vals[_sd_size_cat]
	for def in SD_DMG_SCHEMA:
		var key := String(def["key"])
		var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(vals[key]), float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
		_sd_knob_box.add_child(row_lbl)
		var sl := HSlider.new()
		sl.min_value = float(def["min"])
		sl.max_value = float(def["max"])
		sl.step = float(def["step"])
		sl.value = float(vals[key])
		sl.custom_minimum_size = Vector2(0, 24)
		sl.value_changed.connect(func(v: float):
			vals[key] = v
			row_lbl.text = "%s: %s" % [def["label"], _fmt(v, float(def["step"]))])
		_sd_knob_box.add_child(sl)


func _sd_dmg_cfg() -> Dictionary:
	return (_sd_dmg_vals.get(_sd_size_cat, {}) as Dictionary).duplicate()


func _sd_size_category(sc: float) -> String:
	if sc < 1.15:
		return "small"
	if sc < 1.9:
		return "medium"
	return "large"


# A vertical rounded-rectangle flight path (longways top→bottom), arc-length sampled by Curve2D.
func _build_sd_path() -> void:
	_sd_path = Curve2D.new()
	var c := _sd_center
	var hw := 30.0   # half-width (narrow)
	var hh := 84.0   # half-height (tall)
	var r := 24.0
	r = minf(r, minf(hw, hh))
	var trc := c + Vector2(hw - r, -(hh - r))
	var brc := c + Vector2(hw - r, hh - r)
	var blc := c + Vector2(-(hw - r), hh - r)
	var tlc := c + Vector2(-(hw - r), -(hh - r))
	var seg := 12   # denser corner arcs → smoother circuit
	var pts := PackedVector2Array()
	pts.append(c + Vector2(-(hw - r), -hh))
	pts.append(c + Vector2(hw - r, -hh))
	for i in range(1, seg + 1):
		pts.append(trc + Vector2(cos(lerpf(-PI * 0.5, 0.0, float(i) / seg)), sin(lerpf(-PI * 0.5, 0.0, float(i) / seg))) * r)
	pts.append(c + Vector2(hw, hh - r))
	for i in range(1, seg + 1):
		pts.append(brc + Vector2(cos(lerpf(0.0, PI * 0.5, float(i) / seg)), sin(lerpf(0.0, PI * 0.5, float(i) / seg))) * r)
	pts.append(c + Vector2(-(hw - r), hh))
	for i in range(1, seg + 1):
		pts.append(blc + Vector2(cos(lerpf(PI * 0.5, PI, float(i) / seg)), sin(lerpf(PI * 0.5, PI, float(i) / seg))) * r)
	pts.append(c + Vector2(-hw, -(hh - r)))
	for i in range(1, seg + 1):
		pts.append(tlc + Vector2(cos(lerpf(PI, PI * 1.5, float(i) / seg)), sin(lerpf(PI, PI * 1.5, float(i) / seg))) * r)
	for p in pts:
		_sd_path.add_point(p)
	_sd_path.add_point(pts[0])   # close the loop
	_sd_path_len = _sd_path.get_baked_length()


func _spawn_sd_ship() -> void:
	if _sd_ship != null and is_instance_valid(_sd_ship):
		_sd_ship.queue_free()
	_sd_ship = null
	_sd_tells = null
	_sd_respawn_t = -1.0
	_sd_dead = false
	_sd_t = 0.0
	if _sd_slider != null:
		_sd_slider.set_value_no_signal(0.0)
	if _sd_label != null:
		_sd_label.text = "0%"
	_sd_dist = 0.0
	# Pull from the LIVE faction roster (every spawnable enemy), not the curated dev manifest.
	var pool: Array = []
	for p in Factions.ENEMY_TAGS.keys():
		var pp := String(p)
		if ResourceLoader.exists(pp):
			pool.append(pp)
	if pool.is_empty():
		return
	# Pick a ship MATCHING the selected size category. Measure IN-TREE (after _ready) — many enemies
	# set their sprite scale/texture in _ready, so a detached measure mis-sizes them and the wrong
	# ship spawns. Add → freeze → measure; keep on a match (last attempt accepts anything), else free.
	var ship: Node2D = null
	var sprite: Sprite2D = null
	var size_scale: float = 1.0
	for attempt in 10:
		var path := String(pool[randi() % pool.size()])
		var inst: Node2D = load(path).instantiate()
		_stage.add_child(inst)        # run _ready so the sprite/scale are final
		_freeze_node(inst)
		if inst.is_in_group("enemies"):
			inst.remove_from_group("enemies")
		var spr := _find_body_sprite(inst)
		var sc := _ship_size_scale(inst, spr)
		if _sd_size_category(sc) == _sd_size_cat or attempt == 9:
			ship = inst
			sprite = spr
			size_scale = sc
			break
		inst.queue_free()
	if ship == null:
		return
	# (engine trails keep running per _freeze_node; glow masks render — the dummy looks like a live ship.)
	ship.position = (_sd_path.sample_baked(0.0) if _sd_path != null and _sd_path_len > 0.0 else _sd_center)
	# Start already facing along the path so it doesn't snap-turn on the first frame.
	if _sd_path != null and _sd_path_len > 0.0:
		var d0: Vector2 = _sd_path.sample_baked(12.0, true) - ship.position
		if d0.length() > 0.01:
			ship.rotation = d0.angle() + PI * 0.5
	_sd_ship = ship
	# Damage-tells controller, configured by the SELECTED size's tuned suite + its measured scale.
	var tells: Node2D = ShipDamageTells.new()
	ship.add_child(tells)
	tells.setup(ship, sprite, size_scale, _sd_dmg_cfg())
	tells.destroyed.connect(_on_sd_destroyed)
	_sd_tells = tells


func _on_sd_damage(v: float) -> void:
	if _sd_label != null:
		_sd_label.text = "%d%%" % int(round(v * 100.0))
	if _sd_tells != null and is_instance_valid(_sd_tells):
		_sd_tells.set_damage(v)


func _on_sd_destroyed() -> void:
	# Ship died — leave it disintegrating in place. The New Ship button spawns the next one
	# (Roman 2026-06-12: no auto-respawn).
	_sd_dead = true


func _tick_ship_dmg(delta: float) -> void:
	if _sd_dead:
		return
	if _sd_ship != null and is_instance_valid(_sd_ship) and _sd_path != null and _sd_path_len > 0.0:
		_sd_dist += SD_PATH_SPEED * delta
		if _sd_dist >= _sd_path_len:
			_sd_dist -= _sd_path_len
		_sd_ship.position = _sd_path.sample_baked(_sd_dist, true)
		# Smooth facing: aim along the path's TANGENT (a look-ahead point, stable regardless of the
		# tiny per-frame step), EASED so corners don't snap. The old frame-delta angle was noisy on
		# sub-pixel steps, which read as jitter (Roman 2026-06-12).
		var ahead: Vector2 = _sd_path.sample_baked(fmod(_sd_dist + 12.0, _sd_path_len), true)
		var dir: Vector2 = ahead - _sd_ship.position
		if dir.length() > 0.01:
			var target_rot: float = dir.angle() + PI * 0.5
			_sd_ship.rotation = lerp_angle(_sd_ship.rotation, target_rot, clampf(delta * 9.0, 0.0, 1.0))


# Size metric from the body sprite's on-screen dimensions (robust across enemies that don't
# set display_scale). ~16px chaff ≈ 1.0; a big frigate ≈ 2+. Drives the debris count.
func _ship_size_scale(ship: Node, sprite: Sprite2D) -> float:
	if sprite != null and is_instance_valid(sprite) and sprite.texture != null:
		var fsz: Vector2 = sprite.texture.get_size()
		if sprite.hframes > 1:
			fsz.x /= float(sprite.hframes)
		if sprite.vframes > 1:
			fsz.y /= float(sprite.vframes)
		var px: float = maxf(fsz.x, fsz.y) * maxf(absf(sprite.scale.x), absf(sprite.scale.y))
		return clampf(px / 16.0, 0.6, 3.5)
	if "display_scale" in ship:
		return clampf(float(ship.display_scale), 0.6, 3.5)
	return 1.0


func _freeze_node(n: Node) -> void:
	# Stop movement / aiming / shooting, but KEEP cosmetic engine-trail emitters running so the
	# frozen dummy still shows its exhaust (Roman 2026-06-12). Glow masks are static sprites and
	# render regardless. Timers (shooting) are always stopped.
	if n is Timer:
		(n as Timer).stop()
	var scr: Variant = n.get_script()
	var is_trail: bool = scr != null and String(scr.resource_path).ends_with("engine_trail_fx.gd")
	if not is_trail:
		n.set_process(false)
		n.set_physics_process(false)
	for c in n.get_children():
		_freeze_node(c)


# The ship's body Sprite2D — prefer the conventional "Sprite2D", else the first one found.
func _find_body_sprite(ship: Node) -> Sprite2D:
	var s := ship.get_node_or_null("Sprite2D")
	if s is Sprite2D:
		return s
	for c in ship.find_children("*", "Sprite2D", true, false):
		if c is Sprite2D:
			return c as Sprite2D
	return null


# ---- Asteroids mode --------------------------------------------------------
# The gameplay hazard rock (scenes/enemies/enemy_asteroid.tscn) — procgen silhouette,
# dust trail, and the dusty shatter + burst on explode. Spawned into _stage so the
# asteroid's _fx_parent() routes all its particles into THIS SubViewport (the old
# Player FX Lab spawned the procgen VISUAL — no explode() — into a SubViewport while
# the fx went to the window root; both bugs fixed 2026-06-11).

const ASTEROID_ENEMY_SCENE := "res://scenes/enemies/enemy_asteroid.tscn"


func _enter_asteroids() -> void:
	_expl_acc = 0.0
	_hd_note("ASTEROID HAZARD FX", Vector2(Playfield.CENTER.x - 44.0, 56.0))
	_knob_box.add_child(_label("Asteroids", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Gameplay hazard rock: procgen silhouette,\n30%-opacity dust trail, and the dusty shatter\n(inert fragments + rock-colour motes) + burst\non explode.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_add_action("Explode", func(): _spawn_asteroid(true))
	_add_action("Drift", func(): _spawn_asteroid(false))
	var auto := CheckButton.new()
	auto.text = "Auto-replay explode"
	auto.button_pressed = _expl_auto
	auto.add_theme_font_override("font", UiTheme.active_font())
	auto.add_theme_font_size_override("font_size", FS_BODY)
	auto.toggled.connect(func(v: bool): _expl_auto = v)
	_knob_box.add_child(auto)
	_spawn_asteroid(true)


func _spawn_asteroid(do_explode: bool) -> void:
	var scn: PackedScene = load(ASTEROID_ENEMY_SCENE)
	if scn == null:
		return
	var a = scn.instantiate()
	_stage.add_child(a)
	if do_explode:
		a.position = Vector2(Playfield.CENTER.x, 120.0)
		await get_tree().process_frame
		if is_instance_valid(a) and a.has_method("explode"):
			a.explode()
	else:
		a.position = Vector2(randf_range(Playfield.X_MIN + 30.0, Playfield.X_MAX - 30.0), 20.0)
		if a.has_method("start"):
			a.start(a.position)


func _tick_asteroids(delta: float) -> void:
	if not _expl_auto:
		return
	_expl_acc += delta
	if _expl_acc >= 1.8:
		_expl_acc = 0.0
		_spawn_asteroid(true)


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
	# Burn COLOUR (burnColor) — tune the burning-edge hue (Roman 2026-06-11).
	_knob_box.add_child(_label("Burn colour", FS_CAPTION, UiTheme.COLOR_FAINT))
	var cp := ColorPickerButton.new()
	cp.color = Color(1.0, 0.5, 0.1)
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(0, 34)
	cp.color_changed.connect(func(c: Color):
		if _burn_mat != null:
			_burn_mat.set_shader_parameter("burnColor", c))
	_knob_box.add_child(cp)
	# Burn ORIGIN (position) — where the dissolve starts. In game, enemy_base picks a
	# random engine/turret/muzzle marker; here, presets to preview off-centre burns.
	_knob_box.add_child(_label("Burn origin", FS_CAPTION, UiTheme.COLOR_FAINT))
	var origins := {
		"Center": Vector2(0.5, 0.5), "Top": Vector2(0.5, 0.15), "Bottom": Vector2(0.5, 0.85),
		"Left": Vector2(0.2, 0.5), "Right": Vector2(0.8, 0.5),
	}
	var od := OptionButton.new()
	for k in origins.keys():
		od.add_item(String(k))
	od.add_theme_font_override("font", UiTheme.active_font())
	od.add_theme_font_size_override("font_size", FS_BODY)
	od.item_selected.connect(func(i: int):
		if _burn_mat != null:
			_burn_mat.set_shader_parameter("position", origins[origins.keys()[i]])
		_replay_burn())
	_knob_box.add_child(od)
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
		"Expl. Tuner":
			_tick_expl_tuner(delta)
		"Ship Dmg":
			_tick_ship_dmg(delta)
		"Disintegrate":
			_tick_disintegrate(delta)
		"Asteroids":
			_tick_asteroids(delta)


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
		"Glow":
			_apply_glow_fx()
		"Smoke":
			_rebuild_smoke()
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
	var glow_cols := {}
	for gk in _glow_fx_colors:
		glow_cols[gk] = (_glow_fx_colors[gk] as Color).to_html(false)
	out["GlowColors"] = glow_cols
	var stops := []
	for s in _ember_stops:
		stops.append({"color": (s["color"] as Color).to_html(false), "offset": float(s["offset"])})
	out["EmberGradient"] = stops
	if not _sd_dmg_vals.is_empty():
		out["ShipDmgSizes"] = _sd_dmg_vals
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
		var gcols: Dictionary = data.get("GlowColors", {})
		for gk in _glow_fx_colors:
			if gcols.has(gk):
				_glow_fx_colors[gk] = Color(String(gcols[gk]))
		var stops: Array = data.get("EmberGradient", [])
		if stops.size() >= 2:
			_ember_stops.clear()
			for s in stops:
				_ember_stops.append({"color": Color(String(s["color"])), "offset": float(s["offset"])})
		var sds: Dictionary = data.get("ShipDmgSizes", {})
		if not sds.is_empty():
			_sd_dmg_vals = {}
			for sz in SD_SIZES:
				var d := {}
				for def in SD_DMG_SCHEMA:
					var key := String(def["key"])
					d[key] = float((sds.get(sz, {}) as Dictionary).get(key, def["def"]))
				_sd_dmg_vals[sz] = d


func _on_copy() -> void:
	var txt := ""
	match MODES[_mode]:
		"Embers":
			txt = _snippet_embers()
		"Smoke":
			txt = _snippet_smoke()
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
		"Expl. Tuner":
			txt = _snippet_expl_tuner()
		"Ship Dmg":
			txt = _snippet_ship_dmg()
		"Asteroids":
			txt = "# Shader Lab — gameplay asteroid hazard (scenes/enemies/enemy_asteroid.tscn)\n# var a = load(\"res://scenes/enemies/enemy_asteroid.tscn\").instantiate()\n# parent.add_child(a); a.start(pos)   # then a.explode() for the dusty shatter\n"
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
	t += "\t\"speed_min\": %.1f, \"speed_max\": %.1f, \"gravity\": %.1f, \"damping\": %.1f,\n" % [float(v["speed_min"]), float(v["speed_max"]), float(v["gravity"]), float(v["damping"])]
	t += "\t\"scale_min\": %.2f, \"scale_max\": %.2f, \"scale_grow\": %.2f,\n" % [float(v["scale_min"]), float(v["scale_max"]), float(v["scale_grow"])]
	t += "\t\"spread_deg\": %.1f, \"spin\": %.1f, \"randomness\": %.2f, \"follow_motion\": %s,\n" % [float(v["spread_deg"]), float(v["spin"]), float(v["randomness"]), ("true" if _smoke_follow else "false")]
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
	t += "#\n# Ember-debris sweetener — the FIRE on each chunk (tuned values):\n"
	var v: Dictionary = _values["Explosions"]
	t += "# const ShipDebrisEmber = preload(\"res://scripts/effects/ship_debris_ember.gd\")\n"
	t += "for i in %d:\n" % int(v["count"])
	t += "\tvar ang := randf_range(0.15, PI - 0.15)\n"
	t += "\tShipDebrisEmber.spawn(parent, pos, {\n"
	t += "\t\t\"velocity\": Vector2(cos(ang), sin(ang)) * randf_range(%.0f, %.0f),\n" % [float(v["speed_min"]), float(v["speed_max"])]
	t += "\t\t\"spin\": randf_range(-6.0, 6.0),\n"
	t += "\t\t\"piece_scale\": randf_range(%.2f, %.2f),\n" % [float(v["scale_min"]), float(v["scale_max"])]
	t += "\t\t\"gravity\": %.0f, \"drag\": %.2f,\n" % [float(v["gravity"]), float(v["drag"])]
	t += "\t\t\"burn_time\": randf_range(%.2f, %.2f),\n" % [float(v["burn_min"]), float(v["burn_max"])]
	t += "\t\t\"flame_size\": Vector2(%.2f, %.2f), \"flame_speed\": %.1f,\n" % [float(v["flame_w"]), float(v["flame_h"]), float(v["flame_speed"])]
	t += "\t})\n"
	return t


func _snippet_ship_dmg() -> String:
	# Emit the per-size damage-tell suite — paste into ShipDamageTells per size, or bake the
	# numbers into a size→cfg table on enemy_base.
	var t := "# Shader Lab — damage-tell suite per size (ShipDamageTells.setup cfg)\n"
	for sz in SD_SIZES:
		var vals: Dictionary = _sd_dmg_vals.get(sz, {})
		t += "var dmg_cfg_%s := {\n" % sz
		for def in SD_DMG_SCHEMA:
			var key := String(def["key"])
			t += "\t\"%s\": %s,\n" % [key, _fmt(float(vals.get(key, def["def"])), float(def["step"]))]
		t += "}\n"
	return t


func _snippet_expl_tuner() -> String:
	var v: Dictionary = _values["Expl. Tuner"]
	var t := "# Shader Lab — centralized explosion (scripts/effects/explosion_fx.gd)\n"
	t += "ExplosionFx.play_config(world_pos, {\n"
	t += "\t\"type\": \"%s\",\n" % _et_type
	t += "\t\"size\": %.2f, \"area\": %.0f, \"duration\": %.3f,\n" % [float(v["size"]), float(v["area"]), float(v["duration"])]
	t += "\t\"density\": %d, \"stagger\": %.2f, \"secondaries\": %.2f,\n" % [int(v["density"]), float(v["stagger"]), float(v["secondaries"])]
	t += "\t\"glow\": %.2f, \"shockwave\": %.2f, \"sparks\": %.2f, \"debris\": %.2f,\n" % [float(v["glow"]), float(v["shockwave"]), float(v["sparks"]), float(v["debris"])]
	t += "}, parent)\n"
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


func _snippet_glow() -> String:
	var v: Dictionary = _values["Glow"]
	var c1: Color = _glow_fx_colors["color1"]
	var c2: Color = _glow_fx_colors["color2"]
	var gc: Color = _glow_fx_colors["glow_color"]
	var t := "# Shader Lab — glow_effect_2d (color-keyed in-sprite emission; needs a\n"
	t += "# WorldEnvironment with glow_enabled to bloom). For the soft behind-sprite\n"
	t += "# halo instead, use GlowShaderFx.apply(sprite).\n"
	t += "var m := ShaderMaterial.new()\n"
	t += "m.shader = preload(\"res://graphics/glow_effect_2d.gdshader\")\n"
	t += "m.set_shader_parameter(\"color1\", Color(%.3f, %.3f, %.3f))\n" % [c1.r, c1.g, c1.b]
	t += "m.set_shader_parameter(\"color2\", Color(%.3f, %.3f, %.3f))\n" % [c2.r, c2.g, c2.b]
	t += "m.set_shader_parameter(\"glow_color\", Color(%.3f, %.3f, %.3f))\n" % [gc.r, gc.g, gc.b]
	t += "m.set_shader_parameter(\"threshold\", %.2f)\n" % float(v["threshold"])
	t += "m.set_shader_parameter(\"intensity\", %.2f)\n" % float(v["intensity"])
	t += "m.set_shader_parameter(\"opacity\", %.2f)\n" % float(v["opacity"])
	t += "sprite.material = m\n"
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
