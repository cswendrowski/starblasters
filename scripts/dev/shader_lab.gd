extends Control

# Shader Lab (Roman 2026-06-10) — fire the NEW shader effects in the native
# 480×270 SubViewport and compare them against what's in-game today, without
# the GIF-capture loop:
#   Embers      — ember_spray burst, normal / inverted, tunable colour ramp
#   Smoke       — SmokeTrailFx smoke trail (light → dark), tunable colours
#   Shields     — sci_fi_shield ring (current) vs hex_shield (new) side by side
#   Bloom Env   — the Godot WorldEnvironment glow (main.tscn's combat bloom)
#   Modes       — Focus / Phase / Hyper player-mode tells (moving ship)
#   Damage      — damage_noise overlay tuner (enemy hull erosion)
#   Disintegrate— pixelated_burn tuner (death burn-away)
#   Explosions  — default / small-circle / small→default combo, replayable
#   Gallery     — every other shader in the project on a test quad / sprite
# Right rail = knobs per mode, persisted to user://tuners/shader_lab.json +
# Copy GDScript (tuner contract). Esc / Back returns to the dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const EmberFx = preload("res://scripts/effects/ember_fx.gd")
const GlowFx = preload("res://scripts/effects/glow_fx.gd")
const OutlineFx = preload("res://scripts/effects/outline_fx.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const BURNING_TRAIL = preload("res://scenes/effects/burning_trail_small.tscn")
const SPARK_TRAIL = preload("res://scenes/effects/spark_trail.tscn")
const ShipDamageTells = preload("res://scripts/effects/ship_damage_tells.gd")
const DeathEffectsScript = preload("res://scripts/effects/death_effects.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const ShieldRingFxC = preload("res://scripts/effects/shield_ring_fx.gd")
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
	{"key": "burn_trails", "label": "Burn trails (#)", "min": 1.0, "max": 4.0, "step": 1.0, "def": 1.0},
	{"key": "torch_lead", "label": "Torch lead (dmg %, 0=off)", "min": 0.0, "max": 0.3, "step": 0.01, "def": 0.12},
	{"key": "burn_intro", "label": "Burn intro 0burst/1scale/2rnd", "min": 0.0, "max": 2.0, "step": 1.0, "def": 2.0},
	# Marker-bias weights are RETIRED (Roman 2026-06-17): marker selection is now uniform across every
	# category in ShipDamageTells, so there's nothing to tune per-size here.
]
const SD_SIZES := ["small", "medium", "large"]
const DEATH_SIZES := ["any", "tiny", "small", "medium", "large"]   # Death tab size dial
const SD_PATH_SPEED := 52.0   # px/s the ship travels along the rounded-rect path

# Live player ship sheet (3-hframe banking sheet; middle frame = level flight).
# We crop the middle frame into a standalone single-frame texture so shader UVs
# span 0..1 cleanly — see _ship_texture().
const PLAYER_BODY_PATH := "res://graphics/player/player_ship_a_body.png"

const DAMAGE_SHADER: Shader = preload("res://graphics/damage_noise.gdshader")
const BURN_SHADER: Shader = preload("res://graphics/pixelated_burn.gdshader")
const HALO_SHADER := preload("res://graphics/pixel_halo_glow.gdshader")
const SPARKLE_SHADER := preload("res://graphics/sparkle_star.gdshader")
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
	{"name": "Orb", "path": "res://graphics/projectiles/enemy_bullet.png", "frames": 3},
	{"name": "Ball", "path": "res://graphics/projectiles/projectile_ball.png", "frames": 4},
	{"name": "Bolt", "path": "res://graphics/projectiles/projectile_bolt.png", "frames": 4},
	{"name": "Laser", "path": "res://graphics/projectiles/projectile_laser.png", "frames": 4},
	{"name": "Wave", "path": "res://graphics/projectiles/projectile_wave.png", "frames": 4},
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

const VfxGlowConfigC = preload("res://scripts/effects/vfx_glow_config.gd")
const GLOW_DEMO_TEX := {
	"bullets": "res://graphics/projectiles/enemy_bullet.png",
	"engines": "res://graphics/enemies/enemy_core_cobra.png",
	"explosions": "res://graphics/effects/explosion_small_circle.png",
}
const MODES := ["Embers", "Smoke", "Glow", "Bloom Env", "Modes", "Damage", "Disintegrate", "Explosions", "Expl. Tuner", "Ship Dmg", "Damage Smoke", "Building Shadow", "Building Boom", "Enemy Shields", "Death", "Nebula", "Asteroids", "Firecore Glow", "Star Glow", "Gallery"]

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
		{"key": "shockwave", "label": "Shockwave reach", "min": 0.0, "max": 3.0, "step": 0.1, "def": 0.0},
		{"key": "sparks", "label": "Spark density", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
		{"key": "debris", "label": "Ember density", "min": 0.0, "max": 3.0, "step": 0.1, "def": 1.0},
	],
	"Nebula": [
		{"key": "scale", "label": "Scale", "min": 0.5, "max": 8.0, "step": 0.1, "def": 2.5},
		{"key": "octaves", "label": "Octaves", "min": 1.0, "max": 8.0, "step": 1.0, "def": 5.0},
		{"key": "density", "label": "Density", "min": 0.0, "max": 2.0, "step": 0.05, "def": 1.0},
		{"key": "edge", "label": "Edge softness", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.4},
		{"key": "warp_strength", "label": "Warp strength", "min": 0.0, "max": 4.0, "step": 0.05, "def": 1.4},
		{"key": "warp_scale", "label": "Warp scale", "min": 0.2, "max": 4.0, "step": 0.05, "def": 1.0},
		{"key": "wisp", "label": "Wisp filaments", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.3},
		{"key": "swirl", "label": "Swirl speed (anim)", "min": 0.0, "max": 2.0, "step": 0.02, "def": 0.4},
		{"key": "drift", "label": "Y drift (auto)", "min": 0.0, "max": 0.05, "step": 0.001, "def": 0.004},
		{"key": "flight", "label": "Flight scroll (sim)", "min": 0.0, "max": 0.5, "step": 0.005, "def": 0.06},
		{"key": "opacity", "label": "Opacity", "min": 0.0, "max": 1.0, "step": 0.02, "def": 1.0},
		{"key": "max_alpha", "label": "Max alpha", "min": 0.0, "max": 1.0, "step": 0.02, "def": 0.7},
		{"key": "pixels", "label": "Pixelation", "min": 0.0, "max": 480.0, "step": 10.0, "def": 200.0},
	],
	"Asteroids": [],
	"Firecore Glow": [
		{"key":"halo_px","label":"Halo size (px)","min":16.0,"max":240.0,"step":2.0,"def":72.0},
		{"key":"spread","label":"Ray length (spread)","min":0.01,"max":0.4,"step":0.005,"def":0.33},
		{"key":"size","label":"Ray size","min":-1.0,"max":1.0,"step":0.01,"def":0.365},
		{"key":"speed","label":"Spin speed","min":0.0,"max":4.0,"step":0.05,"def":1.0},
		{"key":"ray1_density","label":"Ray 1 density","min":0.0,"max":16.0,"step":0.1,"def":8.5},
		{"key":"ray2_density","label":"Ray 2 density","min":0.0,"max":16.0,"step":0.1,"def":8.5},
		{"key":"ray2_intensity","label":"Ray 2 intensity","min":-2.0,"max":10.0,"step":0.1,"def":0.5},
		{"key":"core_intensity","label":"Core intensity","min":-1.0,"max":3.0,"step":0.02,"def":2.0},
		{"key":"gradient_steps","label":"Gradient steps","min":2.0,"max":64.0,"step":1.0,"def":64.0},
		{"key":"seed","label":"Seed","min":0.0,"max":20.0,"step":0.1,"def":1.0},
	],
	"Star Glow": [
		{"key":"star_size","label":"Star size (px)","min":32.0,"max":220.0,"step":2.0,"def":110.0},
		{"key":"halo_px","label":"Halo size (px)","min":16.0,"max":360.0,"step":2.0,"def":220.0},
		{"key":"spread","label":"Ray length (spread)","min":0.01,"max":0.4,"step":0.005,"def":0.33},
		{"key":"size","label":"Ray size","min":-1.0,"max":1.0,"step":0.01,"def":0.365},
		{"key":"speed","label":"Spin speed","min":0.0,"max":4.0,"step":0.05,"def":0.6},
		{"key":"ray1_density","label":"Ray 1 density","min":0.0,"max":16.0,"step":0.1,"def":8.5},
		{"key":"ray2_density","label":"Ray 2 density","min":0.0,"max":16.0,"step":0.1,"def":8.5},
		{"key":"ray2_intensity","label":"Ray 2 intensity","min":-2.0,"max":10.0,"step":0.1,"def":0.5},
		{"key":"core_intensity","label":"Core intensity","min":-1.0,"max":3.0,"step":0.02,"def":1.5},
		{"key":"gradient_steps","label":"Gradient steps","min":2.0,"max":64.0,"step":1.0,"def":64.0},
		{"key":"seed","label":"Seed","min":0.0,"max":20.0,"step":0.1,"def":1.0},
	],
	"Firecore Sparkle": [
		{"key":"halo_px","label":"Sparkle size (px)","min":16.0,"max":240.0,"step":2.0,"def":96.0},
		{"key":"scale","label":"Scale","min":100.0,"max":10000.0,"step":50.0,"def":7500.0},
		{"key":"circle_ratio","label":"Circle ratio","min":0.0,"max":2.0,"step":0.02,"def":0.0},
		{"key":"decay_magnitude","label":"Decay","min":0.0,"max":1.0,"step":0.01,"def":0.1},
		{"key":"cut_magnitude","label":"Cut","min":0.0,"max":0.3,"step":0.005,"def":0.05},
		{"key":"rotate_speed","label":"Rotate speed","min":-5.0,"max":5.0,"step":0.05,"def":1.0},
		{"key":"time_speed","label":"Twinkle speed","min":-5.0,"max":5.0,"step":0.05,"def":1.0},
		{"key":"frequency_base","label":"Frequency base","min":0.0,"max":10.0,"step":0.05,"def":1.0},
		{"key":"frequency_disturbance_scale","label":"Freq disturbance","min":0.0,"max":10.0,"step":0.05,"def":0.0},
	],
	"Star Sparkle": [
		{"key":"star_size","label":"Star size (px)","min":32.0,"max":220.0,"step":2.0,"def":110.0},
		{"key":"halo_px","label":"Sparkle size (px)","min":16.0,"max":360.0,"step":2.0,"def":220.0},
		{"key":"scale","label":"Scale","min":100.0,"max":10000.0,"step":50.0,"def":7500.0},
		{"key":"circle_ratio","label":"Circle ratio","min":0.0,"max":2.0,"step":0.02,"def":0.0},
		{"key":"decay_magnitude","label":"Decay","min":0.0,"max":1.0,"step":0.01,"def":0.1},
		{"key":"cut_magnitude","label":"Cut","min":0.0,"max":0.3,"step":0.005,"def":0.05},
		{"key":"rotate_speed","label":"Rotate speed","min":-5.0,"max":5.0,"step":0.05,"def":0.5},
		{"key":"time_speed","label":"Twinkle speed","min":-5.0,"max":5.0,"step":0.05,"def":1.0},
		{"key":"frequency_base","label":"Frequency base","min":0.0,"max":10.0,"step":0.05,"def":1.0},
		{"key":"frequency_disturbance_scale","label":"Freq disturbance","min":0.0,"max":10.0,"step":0.05,"def":0.0},
	],
	"Damage Smoke": [
		{"key":"min_width","label":"Min width (px)","min":2.0,"max":24.0,"step":0.5,"def":6.0},
		{"key":"max_width","label":"Max width (px)","min":4.0,"max":40.0,"step":0.5,"def":16.0},
		{"key":"tail_width_mult","label":"Tail width mult","min":1.0,"max":20.0,"step":0.1,"def":10.0},
		{"key":"point_lifetime","label":"Point lifetime (s)","min":0.3,"max":4.0,"step":0.1,"def":1.8},
		{"key":"sample_interval_min","label":"Sample min (s)","min":0.01,"max":0.2,"step":0.01,"def":0.04},
		{"key":"sample_interval_max","label":"Sample max (s)","min":0.05,"max":0.4,"step":0.01,"def":0.16},
		{"key":"drift_base_speed","label":"Drift base speed","min":0.0,"max":500.0,"step":10.0,"def":225.0},
		{"key":"drift_age_gain","label":"Drift age gain","min":0.0,"max":800.0,"step":20.0,"def":400.0},
		{"key":"wander_px_per_sec","label":"Wander (px/s)","min":0.0,"max":60.0,"step":1.0,"def":18.0},
	],
	# Defaults MUST mirror BuildingShadow.DEFAULTS — this tab tunes what production ships, so opening
	# it on different values makes every Copy→bake a silent regression. (They had drifted to the raw
	# shader uniform defaults; realigned 2026-07-28 with the scene-light pass.) `sun_angle_deg` is the
	# odd one out: it derives from SceneLight in _init_values, since a const can't call a function.
	"Building Shadow": [
		{"key":"sun_angle_deg","label":"Sun angle (deg)","min":0.0,"max":360.0,"step":1.0,"def":45.0},
		{"key":"sun_elevation","label":"Sun elevation","min":0.05,"max":1.5,"step":0.05,"def":1.0},
		{"key":"shadow_strength","label":"Shadow strength","min":0.0,"max":1.0,"step":0.02,"def":0.5},
		{"key":"shadow_softness","label":"Shadow softness","min":0.001,"max":0.5,"step":0.01,"def":0.001},
		{"key":"steps","label":"Ray-march steps","min":4.0,"max":96.0,"step":1.0,"def":50.0},
		{"key":"step_px","label":"Step size (px)","min":0.25,"max":3.0,"step":0.05,"def":0.25},
		{"key":"shadow_aa_radius_px","label":"AA radius (px)","min":0.0,"max":2.0,"step":0.05,"def":0.0},
		{"key":"shadow_ray_offset_px","label":"Ray offset (px)","min":0.0,"max":4.0,"step":0.1,"def":0.0},
		{"key":"carrier_scale","label":"Carrier scale","min":1.5,"max":5.0,"step":0.1,"def":1.5},
	],
	"Gallery": [],
}

const NEBULA_SHADER_PATH := "res://graphics/nebula2.gdshader"
const NEBULA_COLORSCHEME := "res://SpaceBG/Colorscheme.tres"
# A/B alternates (godotshaders.com CC0, ported to Godot 4). Selector in the Nebula tab swaps between
# these so Roman can compare the live nebula2 vs the two candidates.
const NEBULA_ALT1 := "res://graphics/nebula_alt1.gdshader"
const NEBULA_ALT2 := "res://graphics/nebula_alt2.gdshader"
const NEBULA_VARIANT_NAMES := ["Nebula 2 (current)", "Alt A: 2D Nebula", "Alt B: Stars+Clouds"]
# Per-alt direct-param knobs (set straight onto the material; compare-only, not persisted).
const NEBULA_ALT1_KNOBS := [
	{"param": "zoomScale", "label": "Zoom", "min": 1.0, "max": 20.0, "step": 0.5, "def": 6.0},
	{"param": "timescale", "label": "Time scale", "min": 0.0, "max": 10.0, "step": 0.5, "def": 5.0},
	{"param": "size", "label": "Star cell", "min": 4.0, "max": 40.0, "step": 1.0, "def": 10.0},
	{"param": "starscale", "label": "Star scale", "min": 5.0, "max": 60.0, "step": 1.0, "def": 20.0},
	{"param": "prob", "label": "Star sparsity", "min": 0.9, "max": 1.0, "step": 0.002, "def": 0.98},
	{"param": "alpha", "label": "Opacity", "min": 0.0, "max": 1.0, "step": 0.02, "def": 1.0},
]
const NEBULA_ALT2_KNOBS := [
	{"param": "brightness", "label": "Brightness", "min": 0.0, "max": 3.0, "step": 0.05, "def": 1.0},
	{"param": "clouds_resolution", "label": "Cloud zoom", "min": 0.5, "max": 10.0, "step": 0.1, "def": 3.0},
	{"param": "waveyness", "label": "Waveyness", "min": 0.0, "max": 5.0, "step": 0.05, "def": 0.5},
	{"param": "fragmentation", "label": "Fragmentation", "min": 0.0, "max": 100.0, "step": 1.0, "def": 7.0},
	{"param": "distortion", "label": "Distortion", "min": 0.0, "max": 10.0, "step": 0.1, "def": 0.5},
	{"param": "blur", "label": "Blur/falloff", "min": 0.5, "max": 5.0, "step": 0.05, "def": 1.4},
	{"param": "alpha", "label": "Opacity", "min": 0.0, "max": 1.0, "step": 0.02, "def": 1.0},
]

# Every shader currently in the project that can be shown standalone.
# mode: "rect" = ColorRect quad, "sprite" = ship sprite, "glowfx" = live
# GlowFx.attach_glow() radial halo. pulse = uniform tweened by the Pulse button.
const GALLERY := [
	{"name": "Sci-Fi Shield (current)", "path": "res://graphics/sci_fi_shield.gdshader", "mode": "rect", "size": Vector2(48, 48), "pulse": {"param": "hit_strength", "from": 1.0, "to": 0.0, "time": 0.5}},
	{"name": "Hex Shield (NEW)", "path": "res://graphics/hex_shield.gdshader", "mode": "rect", "size": Vector2(48, 48), "pulse": {"param": "hit_strength", "from": 1.0, "to": 0.0, "time": 0.5}},
	{"name": "Radial Glow (glow_fx)", "path": "res://scripts/effects/glow_fx.gd", "mode": "glowfx"},
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

# Enemy Shields tab — fit the shield bubble (size + roundness) to a spawned enemy.
var _esh_enemy: Node2D = null
var _esh_ring: ColorRect = null
var _esh_mat: ShaderMaterial = null
var _esh_fx = null
var _esh_idx: int = 0
var _esh_list: Array = []
var _esh_by_enemy: Dictionary = {}   # enemy path -> {ring_size, elongation}; persisted to disk
var _esh_knob_box: VBoxContainer = null

# Halo glow modes (Firecore Glow / Star Glow) — shared infrastructure.
var _halo_mat: ShaderMaterial = null
var _halo_rect: ColorRect = null
var _halo_wrap: Node2D = null          # inspection-zoom wrapper holding the halo + subject
var _halo_subject: Node = null         # the firecore sprite OR the star
var _halo_colors: Array = [Color(0.8,0.25,0.0,0.0), Color(1.0,0.55,0.1,0.75), Color(1.0,0.98,0.85,1.0)]
var _halo_hdr: bool = false
var _halo_star_size: float = 100.0
var _halo_kind: String = "Halo"         # "Halo" or "Sparkle" — the selected shader
var _halo_knob_box: VBoxContainer = null  # sub-box the shader-specific knobs rebuild into
var _halo_sparkle_color: Color = Color(1.0, 0.85, 0.4, 1.0)
var _halo_stop_shine: bool = false

# Mode-specific refs (nulled on every mode switch).
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

# Nebula tuner state.
var _nebula_mat: ShaderMaterial = null
var _nebula_scroll: float = 0.0   # simulated flight scroll (UV units)
var _nebula_rect: ColorRect = null
var _nebula_variant: int = 0      # 0 = nebula2 (current), 1 = Alt A, 2 = Alt B
var _nebula_knob_sub: VBoxContainer = null  # variant-specific knob box, rebuilt on switch
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
var _sd_pool_by_cat: Dictionary = {}  # "small"/"medium"/"large" → [scene paths] (measured once)

# Damage Smoke tab.
var _dmg_smoke_ship: Node2D = null    # the flying host ship with the trail attached
var _dmg_smoke_trail: Node = null     # the live DamageSmokeTrail controller
var _dmg_smoke_color: Color = Color(0.10, 0.10, 0.11, 0.90)
var _dmg_smoke_t: float = 0.0
var _dmg_smoke_vel: Vector2 = Vector2.ZERO

# Building Shadow tab.
var _bshadow_building: Node2D = null           # the instantiated building scene
var _bshadow_pairs: Array = []                 # [{rect, layer}, ...] for live re-tune
var _bshadow_knob_box: VBoxContainer = null    # sub-box for per-layer sliders
var _bshadow_ground: ColorRect = null          # mid-grey ground plane behind building
var _bshadow_idx: int = 0                      # selected building index
var _bshadow_tint: Color = Color(0.0, 0.0, 0.0, 0.8)  # shadow tint (persist)
var _bshadow_heights: Dictionary = {}          # scene_path -> {layer_name -> float}

# Building Boom tab.
var _bboom_building: Node2D = null             # the instantiated building scene
var _bboom_wrap: Node2D = null                 # the 4× zoom wrapper
var _bboom_idx: int = 0                        # selected building index (persist)
var _bboom_cfg: Dictionary = {}                # scene_path -> cfg dict (persist)
var _bboom_knob_box: VBoxContainer = null      # sub-box for explosion knobs
var _bboom_auto: bool = true
var _bboom_acc: float = 0.0

# Death-effects tab.
var _death_ship: Node2D = null        # the live dummy flying down the middle, awaiting a death
var _death_ship_vel: Vector2 = Vector2.ZERO  # its downward travel (handed to the death as the glide)
var _death_fx: Node = null            # the active DeathEffects controller (null between plays)
var _death_style: String = "spinout"
var _spinout_resolution: String = "random"   # spinout ending (random | instakill | flashout | wreck | descent)
var _death_vals: Dictionary = {}      # style → {key: value} (per-style knobs, like _sd_dmg_vals)
var _death_knob_box: VBoxContainer = null  # sub-box for the selected style's knobs (rebuilt on change)
var _death_pool: Array = []           # all spawnable ship-vfx enemy paths (measured once)
var _death_pool_2eng: Array = []      # subset with >=2 engine markers (Spinout prefers these)
var _death_pool_by_size: Dictionary = {}   # "tiny"/"small"/"medium"/"large" → [paths]
var _death_size: String = "any"       # size dial: any | tiny | small | medium | large

static var _ship_tex: Texture2D = null


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")   # dev tool: stay quiet (missed in the mute pass)
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
	# The Building Shadow tab's sun angle is the canonical scene light expressed in the shader's
	# SHADOW-direction space (building_shadow.gdshader's `sun_dir` points along the shadow, not at
	# the light — see docs/scene_light_direction_2026-07-28.md §1.1). Derived rather than hardcoded
	# so the tuner can never disagree with what BuildingShadow ships.
	_values["Building Shadow"]["sun_angle_deg"] = fposmod(rad_to_deg(SceneLight.shadow_dir().angle()), 360.0)


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
	# ViewportTexture — which both BLOCKED/blurred diffuse additive glows AND
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
	HdScreen.apply_native_parity(_preview_vp)
	HdScreen.verify_native_subviewport.call_deferred(_preview_vp, "shader_lab")
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
	# "bullet_world" sink so the Death-tab explosions/debris (and any parent-less fx) resolve into this
	# native stage, not the 1920×1080 window's top-left corner (BulletWorld.spawn_root; no-op in prod).
	_stage.add_to_group("bullet_world")
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
	_nebula_mat = null
	_nebula_rect = null
	_nebula_knob_sub = null
	_smoke_host = null
	_smoke_trail = null
	_sd_ship = null
	_sd_tells = null
	_sd_slider = null
	_sd_label = null
	_sd_respawn_t = -1.0
	# Damage smoke host + trail live in _stage, freed above; just drop the refs.
	_dmg_smoke_ship = null
	_dmg_smoke_trail = null
	_dmg_smoke_t = 0.0
	# Building shadow — building + ground plane + carrier rects live in _stage; heights + tint PERSIST.
	_bshadow_building = null
	_bshadow_pairs.clear()
	_bshadow_knob_box = null
	_bshadow_ground = null
	# Building boom — building + wrap live in _stage; cfg + idx + auto PERSIST.
	_bboom_building = null
	_bboom_wrap = null
	_bboom_knob_box = null
	_bboom_acc = 0.0
	# Death dummy + controller live in _stage, freed above; just drop the refs.
	_death_ship = null
	_death_fx = null
	_death_knob_box = null
	# Enemy Shields refs (the enemy + ring live in _stage, freed above; just drop the refs). The
	# per-enemy fit dict PERSISTS across modes — don't clear it.
	_esh_enemy = null
	_esh_ring = null
	_esh_mat = null
	_esh_fx = null
	_esh_knob_box = null
	# Halo glow refs (subject + wrap live in _stage, freed above). Color stops + kind + colors PERSIST.
	_halo_mat = null
	_halo_rect = null
	_halo_wrap = null
	_halo_subject = null
	_halo_knob_box = null
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
		"Damage Smoke":
			_enter_damage_smoke()
		"Building Shadow":
			_enter_building_shadow()
		"Building Boom":
			_enter_building_boom()
		"Enemy Shields":
			_enter_enemy_shields()
		"Death":
			_enter_death()
		"Nebula":
			_enter_nebula()
		"Asteroids":
			_enter_asteroids()
		"Firecore Glow":
			_enter_firecore_glow()
		"Star Glow":
			_enter_star_glow()
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
			_pm_glow = GlowFx.attach_glow(ship, FOCUS_GLOW_COLOR, 1.6, 0.7)
			_pm_trail = _make_focus_trail()
			_pm_dot = _make_focus_dot(ship)
		"phase":
			_pm_glow = GlowFx.attach_glow(ship, PHASE_GLOW_COLOR, 1.6, 0.7)
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
	_knob_box.add_child(_label("scenes/effects/burning_trail_small.tscn — GPUParticles2D\nthat plays the small-fireball strip per puff (fire →\nsmoke), spins + grows. Drifts down so the trail\nreads (local_coords forced off for the preview).", FS_CAPTION, UiTheme.COLOR_FAINT))
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


# Drift a few burning_trail_small.tscn particle emitters down across the playfield so the trail reads.
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
	var et_types := ["basic", "ball", "fireball", "mixed"]
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
	# Seed each size from the LIVE damage-tell presets — ship_damage_tells.SIZE_PRESETS is the SSOT the
	# game applies at spawn (cfg_for_size), so the tuner always opens at the current live configuration
	# rather than a hand-copied baseline that drifts (Roman 2026-07-15). Any schema knob the preset
	# doesn't carry falls back to its schema default.
	for sz in SD_SIZES:
		var preset: Dictionary = ShipDamageTells.SIZE_PRESETS.get(sz, {})
		var d := {}
		for def in SD_DMG_SCHEMA:
			var key := String(def["key"])
			d[key] = float(preset.get(key, def["def"]))
		_sd_dmg_vals[sz] = d


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
	# Sprite sizes cluster at ~16px (1.0), ~32px (2.0), and 48-56px (3.0+). Bands chosen so EACH is
	# populated: small = 16px chaff, medium = 32px mid, large = 48px+ (Roman 2026-06-12). The old
	# 1.15/1.9 split left MEDIUM empty — every sprite was either 1.0 or ≥2.0 — so the panel fell
	# through to the wrong-size fallback whenever "medium" was selected.
	if sc < 1.5:
		return "small"
	if sc < 2.5:
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


# Measure every spawnable faction-roster enemy ONCE (in-tree, so _ready-set scales count) and bucket
# it into small/medium/large. Cached — built on the first spawn. The categorized pools let the panel
# always honour the selected size band (or report an empty one) instead of guessing-and-falling-back.
func _build_sd_pool() -> void:
	if not _sd_pool_by_cat.is_empty():
		return
	for sz in SD_SIZES:
		_sd_pool_by_cat[sz] = []
	for p in Factions.ENEMY_TAGS.keys():
		var path := String(p)
		if not ResourceLoader.exists(path) or _is_boss_scene(path):
			continue
		var inst: Node2D = load(path).instantiate()
		_stage.add_child(inst)
		_freeze_node(inst)
		if inst.is_in_group("enemies"):
			inst.remove_from_group("enemies")
		var spr := _find_body_sprite(inst)
		var cat := _sd_size_category(_ship_size_scale(inst, spr))
		(_sd_pool_by_cat[cat] as Array).append(path)
		inst.queue_free()
	_force_quiet_music()   # a boss _ready (were one to slip in) flips the Music context — re-assert silence


# A boss scene path — bosses aren't size/death dummies, and their _ready calls Music.set_context("boss")
# (boss_base._init_phases), which would un-silence the lab. Matched by the "boss" filename prefix (the
# Shepherd is faction-tagged, not under /bosses/) plus the bosses dir for the rest.
func _is_boss_scene(path: String) -> bool:
	return String(path.get_file()).to_lower().begins_with("boss") or path.contains("/bosses/")


# Re-assert the lab's silent Music context (SFX ride their own bus, so they stay audible). Used after
# instantiating roster enemies, since a spawned unit's _ready can flip the context.
func _force_quiet_music() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


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
	# Categorize the whole roster ONCE (measured in-tree), then pick ONLY from the selected band.
	# This replaces the old random-retry-with-fallback, which spawned a wrong-size ship whenever the
	# band was sparse/empty (Roman 2026-06-12).
	_build_sd_pool()
	var band: Array = _sd_pool_by_cat.get(_sd_size_cat, [])
	if band.is_empty():
		if _sd_label != null:
			_sd_label.text = "no %s ship" % _sd_size_cat
		return
	var path := String(band[randi() % band.size()])
	var ship: Node2D = load(path).instantiate()
	_stage.add_child(ship)            # run _ready so the sprite/scale are final
	_freeze_node(ship)
	if ship.is_in_group("enemies"):
		ship.remove_from_group("enemies")
	var sprite: Sprite2D = _find_body_sprite(ship)
	var size_scale: float = _ship_size_scale(ship, sprite)
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
	# Ship died. Let the disintegrate + explosion read for a beat, then REMOVE the burnt-out hull
	# so it fully vanishes and stays gone until "New Ship" (Roman 2026-06-17). The explosion/debris
	# VFX live in _stage (the ship's parent), so they persist after the hull is freed.
	_sd_dead = true
	var ship := _sd_ship
	_sd_ship = null
	_sd_tells = null
	if ship != null and is_instance_valid(ship):
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			if is_instance_valid(ship):
				ship.queue_free())


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
		# GLOBAL scale, not local — display_scale may be applied to the ship ROOT (so the sprite's
		# own scale stays 1.0 even on a big ship). global_scale composes both (Roman 2026-06-12).
		var gs: Vector2 = sprite.global_scale
		var px: float = maxf(fsz.x, fsz.y) * maxf(absf(gs.x), absf(gs.y))
		return clampf(px / 16.0, 0.6, 3.5)
	if "display_scale" in ship:
		return clampf(float(ship.display_scale), 0.6, 3.5)
	return 1.0


# ---- Death effects mode ----------------------------------------------------
# A live enemy holds at top-centre; pick a death STYLE and Play it. DeathEffects (the production
# module) composes the fire trail / explosion / embers / disintegrate / wreck-corkscrew primitives.
# Knobs tune the suite; Copy GDScript emits the DeathEffects.play() call. Re-spawns after each death.

func _enter_death() -> void:
	if _death_style == "" or not DeathEffectsScript.STYLES.has(_death_style):
		_death_style = "spinout"
	_init_death_vals()
	_knob_box.add_child(_label("Death Effects", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("A live enemy holds at centre. Pick a style and\nPlay it — it composes the real death primitives.\nEach style has its OWN knobs below.\nSpinout auto-picks a 2-engine ship.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_knob_box.add_child(_label("Style", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for s in DeathEffectsScript.STYLES:
		dd.add_item(String(s).capitalize())
	dd.select(maxi(0, DeathEffectsScript.STYLES.find(_death_style)))
	dd.item_selected.connect(func(i: int):
		_death_style = String(DeathEffectsScript.STYLES[i])
		_rebuild_death_knobs()
		_spawn_death_ship())
	_knob_box.add_child(dd)
	# Size dial — which band of the live enemy roster to spawn/test on ("any" = the whole roster).
	_knob_box.add_child(_label("Enemy size", FS_CAPTION, UiTheme.COLOR_FAINT))
	var sd := OptionButton.new()
	sd.add_theme_font_override("font", UiTheme.active_font())
	sd.add_theme_font_size_override("font_size", FS_BODY)
	sd.custom_minimum_size = Vector2(0, 34)
	for sz in DEATH_SIZES:
		sd.add_item(String(sz).capitalize())
	sd.select(maxi(0, DEATH_SIZES.find(_death_size)))
	sd.item_selected.connect(func(i: int):
		_death_size = String(DEATH_SIZES[i])
		_spawn_death_ship())
	_knob_box.add_child(sd)
	_add_action("▶ Play Death", _play_death)
	_add_action("New Ship", _spawn_death_ship)
	_knob_box.add_child(HSeparator.new())
	_death_knob_box = VBoxContainer.new()
	_death_knob_box.add_theme_constant_override("separation", 6)
	_knob_box.add_child(_death_knob_box)
	_rebuild_death_knobs()
	_spawn_death_ship()


# Seed the per-style value dicts from each style's knob schema (the single source of truth). No-op if
# already populated (e.g. _load_saved built them from disk).
func _init_death_vals() -> void:
	if not _death_vals.is_empty():
		return
	for style in DeathEffectsScript.STYLES:
		var d := {}
		for def in DeathEffectsScript.STYLE_KNOBS.get(style, []):
			var key := String(def["key"])
			if def.get("range", false):
				d[key] = (def["def"] as Array).duplicate()   # [lo, hi] — randomized per death
			else:
				d[key] = float(def["def"])
		_death_vals[style] = d


# Rebuild the knob sliders for the SELECTED style into _death_knob_box (like the Ship Dmg per-size box).
func _rebuild_death_knobs() -> void:
	if _death_knob_box == null or not is_instance_valid(_death_knob_box):
		return
	for c in _death_knob_box.get_children():
		c.queue_free()
	# Spinout resolves into one of instakill/flashout/wreck/descent — pick which (or Random) to test.
	if _death_style == "spinout":
		_death_knob_box.add_child(_label("Resolution", FS_CAPTION, UiTheme.COLOR_FAINT))
		var rd := OptionButton.new()
		rd.add_theme_font_override("font", UiTheme.active_font())
		rd.add_theme_font_size_override("font_size", FS_BODY)
		rd.custom_minimum_size = Vector2(0, 30)
		for r in DeathEffectsScript.RESOLUTIONS:
			rd.add_item(String(r).capitalize())
		rd.select(maxi(0, DeathEffectsScript.RESOLUTIONS.find(_spinout_resolution)))
		rd.item_selected.connect(func(i: int): _spinout_resolution = String(DeathEffectsScript.RESOLUTIONS[i]))
		_death_knob_box.add_child(rd)
		_death_knob_box.add_child(HSeparator.new())
	var vals: Dictionary = _death_vals.get(_death_style, {})
	for def in DeathEffectsScript.STYLE_KNOBS.get(_death_style, []):
		if def.get("range", false):
			_add_death_range_knob(def, vals)
		else:
			_add_death_knob(def, vals)


func _add_death_knob(def: Dictionary, vals: Dictionary) -> void:
	var key := String(def["key"])
	var step := float(def["step"])
	var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(vals[key]), step)], FS_CAPTION, UiTheme.COLOR_FAINT)
	_death_knob_box.add_child(row_lbl)
	var sl := HSlider.new()
	sl.min_value = float(def["min"])
	sl.max_value = float(def["max"])
	sl.step = step
	sl.value = float(vals[key])
	sl.custom_minimum_size = Vector2(0, 24)
	sl.value_changed.connect(func(v: float):
		vals[key] = v
		row_lbl.text = "%s: %s" % [def["label"], _fmt(v, step)])
	_death_knob_box.add_child(sl)


# A RANGE knob = two sliders (Lo, Hi); the death randomizes randf_range(lo, hi) per play.
func _add_death_range_knob(def: Dictionary, vals: Dictionary) -> void:
	var key := String(def["key"])
	var step := float(def["step"])
	var arr: Array = vals[key]   # [lo, hi] — mutated in place
	var row_lbl := _label("%s: %s–%s (rand)" % [def["label"], _fmt(float(arr[0]), step), _fmt(float(arr[1]), step)], FS_CAPTION, UiTheme.COLOR_FAINT)
	_death_knob_box.add_child(row_lbl)
	var refresh := func():
		row_lbl.text = "%s: %s–%s (rand)" % [def["label"], _fmt(float(arr[0]), step), _fmt(float(arr[1]), step)]
	for idx in 2:
		var sl := HSlider.new()
		sl.min_value = float(def["min"])
		sl.max_value = float(def["max"])
		sl.step = step
		sl.value = float(arr[idx])
		sl.custom_minimum_size = Vector2(0, 22)
		sl.value_changed.connect(func(v: float):
			arr[idx] = v
			refresh.call())
		_death_knob_box.add_child(sl)


# Measure every spawnable faction-roster enemy ONCE (in-tree so _ready-set scales count), keeping the
# ship-vfx ships (skip hazards/mines) and noting which carry >=2 engine markers. Cached.
func _build_death_pool() -> void:
	if not _death_pool.is_empty():
		return
	for sz in ["tiny", "small", "medium", "large"]:
		_death_pool_by_size[sz] = []
	for p in Factions.ENEMY_TAGS.keys():
		var path := String(p)
		if not ResourceLoader.exists(path) or _is_boss_scene(path):
			continue
		var inst: Node2D = load(path).instantiate()
		_stage.add_child(inst)
		_freeze_node(inst)
		if inst.is_in_group("enemies"):
			inst.remove_from_group("enemies")
		var spr := _find_body_sprite(inst)
		var is_ship: bool = ("has_ship_vfx" in inst and bool(inst.has_ship_vfx)) and spr != null
		if is_ship:
			_death_pool.append(path)
			if inst.find_children("Engine*", "Marker2D", true, false).size() >= 2:
				_death_pool_2eng.append(path)
			(_death_pool_by_size[_death_size_bucket(_ship_size_scale(inst, spr))] as Array).append(path)
		inst.queue_free()
	_force_quiet_music()   # a boss _ready (were one to slip in) flips the Music context — re-assert silence


func _death_size_bucket(sc: float) -> String:
	if sc < 1.0:
		return "tiny"
	if sc < 1.5:
		return "small"
	if sc < 2.5:
		return "medium"
	return "large"


func _spawn_death_ship() -> void:
	if _death_ship != null and is_instance_valid(_death_ship):
		_death_ship.queue_free()
	_death_ship = null
	_build_death_pool()
	# The size dial picks the band to spawn from (any = the full ship roster).
	var pool: Array = _death_pool if _death_size == "any" else (_death_pool_by_size.get(_death_size, []) as Array)
	if pool.is_empty():
		_note.text = "no %s ship in the roster" % _death_size
		return
	var path := String(pool[randi() % pool.size()])
	var ship: Node2D = load(path).instantiate()
	_stage.add_child(ship)            # run _ready so the sprite/scale are final
	_freeze_node(ship)
	if ship.is_in_group("enemies"):
		ship.remove_from_group("enemies")
	# Enter at the TOP and FLY DOWN the middle (a better in-play representation than holding still) —
	# _tick_death advances it, and Play hands its current downward velocity to the death as the glide.
	# Sprites are authored facing UP at rotation 0; an auto_rotate ship needs rotation PI to point down
	# (matches enemy_base._apply_auto_rotation). Fixed-facing ships keep their authored orientation.
	ship.position = Vector2(Playfield.CENTER.x, 10.0)
	if "auto_rotate" in ship and bool(ship.auto_rotate):
		ship.rotation = PI
	_death_ship = ship
	_death_ship_vel = Vector2.DOWN * _death_primary_speed()


func _death_cfg() -> Dictionary:
	var cfg: Dictionary = (_death_vals.get(_death_style, {}) as Dictionary).duplicate(true)  # deep — copy range arrays
	if _death_style == "spinout":
		cfg["resolution"] = _spinout_resolution
	return cfg


# The downward flight speed handed to the dummy + the death as its inherited velocity. A representative
# constant — the death sets its own speeds (spinout randomizes within its ranges).
func _death_primary_speed() -> float:
	if _death_style == "blow_out":
		return float((_death_vals.get("blow_out", {}) as Dictionary).get("enter_speed", 40.0))
	return 50.0


func _play_death() -> void:
	if _death_fx != null and is_instance_valid(_death_fx):
		return   # a death is already playing
	if _death_ship == null or not is_instance_valid(_death_ship):
		_spawn_death_ship()
		if _death_ship == null:
			return
	var ship := _death_ship
	_death_ship = null   # hand it off to the controller
	var fx: Node = DeathEffectsScript.new()
	_stage.add_child(fx)
	_death_fx = fx
	if fx.has_signal("finished"):
		fx.finished.connect(_on_death_finished)
	# Hand the ship's CURRENT downward velocity to the death so the glide continues its in-flight motion.
	var travel := _death_ship_vel if _death_ship_vel.length() > 0.1 else Vector2.DOWN * _death_primary_speed()
	fx.play(ship, _death_style, _death_cfg(), travel, {
		"vfx_parent": _stage, "wreck_parent": _stage, "bounds": Rect2(0, 0, 480, 270),
	})


func _on_death_finished() -> void:
	_death_fx = null
	if MODES[_mode] != "Death":
		return
	# Respawn a fresh dummy a beat after the death clears, so the tab is always ready to replay.
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(_spawn_death_ship)


# Fly the awaiting dummy down the middle; loop back to the top when it clears the bottom. Paused while
# a death is playing (the dummy is handed off to the DeathEffects controller, which owns the motion).
func _tick_death(delta: float) -> void:
	if _death_fx != null and is_instance_valid(_death_fx):
		return
	if _death_ship == null or not is_instance_valid(_death_ship):
		return
	_death_ship.position += _death_ship_vel * delta
	if _death_ship.position.y > 290.0:
		_death_ship.position = Vector2(Playfield.CENTER.x, 10.0)


func _freeze_node(n: Node) -> void:
	# Stop movement / aiming / shooting, but KEEP cosmetic engine-trail emitters running so the
	# frozen dummy still shows its exhaust (Roman 2026-06-12). Glow masks are static sprites and
	# render regardless. Timers (shooting) are always stopped.
	if n is Timer:
		(n as Timer).stop()
	# Silence any audio the spawned ship carries (engine drones / spawn one-shots) so the
	# inspection dummy is quiet — the lab is a visual tuner (Roman 2026-06-17).
	if n is AudioStreamPlayer:
		(n as AudioStreamPlayer).stop()
		(n as AudioStreamPlayer).autoplay = false
	elif n is AudioStreamPlayer2D:
		(n as AudioStreamPlayer2D).stop()
		(n as AudioStreamPlayer2D).autoplay = false
	var scr: Variant = n.get_script()
	var is_trail: bool = scr != null and String(scr.resource_path).ends_with("engine_trail_fx.gd")
	if not is_trail:
		n.set_process(false)
		n.set_physics_process(false)
	for c in n.get_children():
		_freeze_node(c)


# The ship's body Sprite2D — prefer the conventional "Sprite2D", else the first non-mask Sprite2D
# (skipping glow / shadow masks, which can differ in size and would mis-measure the hull).
func _find_body_sprite(ship: Node) -> Sprite2D:
	var s := ship.get_node_or_null("Sprite2D")
	if s is Sprite2D:
		return s
	for c in ship.find_children("*", "Sprite2D", true, false):
		var nm := String(c.name).to_lower()
		if nm.contains("glow") or nm.contains("mask") or nm.contains("shadow"):
			continue
		if c is Sprite2D:
			return c as Sprite2D
	return null


# ---- Nebula mode -----------------------------------------------------------
# The live backdrop nebula (graphics/nebula2.gdshader, as spawned by layer_stellar._spawn_nebula).
# Full-screen rect so the whole cloud reads; SWIRL animates the warp field in place, FLIGHT sims the
# in-game parallax scroll. NOTE: in game it's far dimmer (max_alpha ~0.1-0.2 per band) and currently
# DISABLED on the live stellar layers — this page is where the dynamic look gets dialed in first.

func _enter_nebula() -> void:
	_nebula_scroll = 0.0
	_nebula_rect = ColorRect.new()
	_nebula_rect.name = "Nebula"
	_nebula_rect.size = Vector2(480, 270)
	_nebula_rect.position = Vector2.ZERO
	_nebula_rect.color = Color(0, 0, 0, 0)
	_nebula_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_nebula_rect)

	_hd_note("NEBULA (A/B)", Vector2(Playfield.CENTER.x - 24.0, 14.0))
	_knob_box.add_child(_label("Nebula — shader A/B", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Live nebula2 vs two godotshaders.com alternates (CC0).\nPick one; knobs rebuild per shader. The alts fill opaque\n(dial Opacity for backdrop feel) and animate on their own.", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for n in NEBULA_VARIANT_NAMES:
		dd.add_item(String(n))
	dd.select(_nebula_variant)
	dd.item_selected.connect(_select_nebula_variant)
	_knob_box.add_child(dd)
	_knob_box.add_child(HSeparator.new())
	_nebula_knob_sub = VBoxContainer.new()
	_nebula_knob_sub.add_theme_constant_override("separation", 2)
	_knob_box.add_child(_nebula_knob_sub)
	_select_nebula_variant(_nebula_variant)


# Swap the previewed nebula shader + rebuild its knob set. Variant 0 = the live nebula2 (full knobs +
# scroll sim); 1/2 = the A/B alternates (direct-param knobs, compare-only).
func _select_nebula_variant(idx: int) -> void:
	_nebula_variant = idx
	_nebula_scroll = 0.0
	if _nebula_knob_sub == null or not is_instance_valid(_nebula_knob_sub):
		return
	for c in _nebula_knob_sub.get_children():
		c.queue_free()
	_nebula_mat = ShaderMaterial.new()
	if idx == 0:
		_nebula_mat.shader = load(NEBULA_SHADER_PATH)
		var cs = load(NEBULA_COLORSCHEME)
		if cs != null:
			_nebula_mat.set_shader_parameter("colorscheme", cs)
		_nebula_mat.set_shader_parameter("seed", 7.0)
		_nebula_mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
		_nebula_mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
		_nebula_mat.set_shader_parameter("rect_size", Vector2(480.0, 270.0))
		_nebula_rect.material = _nebula_mat
		_apply_nebula_knobs()
		for def in KNOBS["Nebula"]:
			_add_nebula_v0_knob(def)
	elif idx == 1:
		_nebula_mat.shader = load(NEBULA_ALT1)
		_nebula_rect.material = _nebula_mat
		for k in NEBULA_ALT1_KNOBS:
			_add_nebula_param_knob(k)
	else:
		_nebula_mat.shader = load(NEBULA_ALT2)
		_nebula_mat.set_shader_parameter("noise_texture", _nebula_noise_texture())
		_nebula_rect.material = _nebula_mat
		var stars := CheckButton.new()
		stars.text = "Stars on"
		stars.button_pressed = true
		stars.add_theme_font_override("font", UiTheme.active_font())
		stars.add_theme_font_size_override("font_size", FS_CAPTION)
		stars.toggled.connect(func(v: bool): _nebula_mat.set_shader_parameter("stars_on", v))
		_nebula_knob_sub.add_child(stars)
		for k in NEBULA_ALT2_KNOBS:
			_add_nebula_param_knob(k)


# A nebula2 knob (variant 0) — drives _values["Nebula"] + _apply_nebula_knobs, into the sub box.
func _add_nebula_v0_knob(def: Dictionary) -> void:
	var key := String(def["key"])
	var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(_values["Nebula"][key]), float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
	_nebula_knob_sub.add_child(row_lbl)
	var sl := HSlider.new()
	sl.min_value = float(def["min"]); sl.max_value = float(def["max"]); sl.step = float(def["step"])
	sl.value = float(_values["Nebula"][key])
	sl.custom_minimum_size = Vector2(0, 24)
	sl.value_changed.connect(func(v: float):
		_values["Nebula"][key] = v
		row_lbl.text = "%s: %s" % [def["label"], _fmt(v, float(def["step"]))]
		_apply_nebula_knobs())
	_nebula_knob_sub.add_child(sl)


# An alt-shader knob — sets the shader param straight onto _nebula_mat (no _values persistence).
func _add_nebula_param_knob(k: Dictionary) -> void:
	var param := String(k["param"])
	var deff := float(k["def"])
	_nebula_mat.set_shader_parameter(param, deff)
	var row_lbl := _label("%s: %s" % [k["label"], _fmt(deff, float(k["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
	_nebula_knob_sub.add_child(row_lbl)
	var sl := HSlider.new()
	sl.min_value = float(k["min"]); sl.max_value = float(k["max"]); sl.step = float(k["step"])
	sl.value = deff
	sl.custom_minimum_size = Vector2(0, 24)
	sl.value_changed.connect(func(v: float):
		_nebula_mat.set_shader_parameter(param, v)
		row_lbl.text = "%s: %s" % [k["label"], _fmt(v, float(k["step"]))])
	_nebula_knob_sub.add_child(sl)


# Seamless noise for Alt B (nebula_alt2 reads RG channels of a tiling noise).
func _nebula_noise_texture() -> Texture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.015
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = false
	return t


func _apply_nebula_knobs() -> void:
	if _nebula_mat == null or _nebula_variant != 0:
		return
	var v: Dictionary = _values["Nebula"]
	_nebula_mat.set_shader_parameter("scale", float(v["scale"]))
	_nebula_mat.set_shader_parameter("octaves", int(v["octaves"]))
	_nebula_mat.set_shader_parameter("density", float(v["density"]))
	_nebula_mat.set_shader_parameter("edge_sharpness", float(v["edge"]))
	_nebula_mat.set_shader_parameter("warp_strength", float(v["warp_strength"]))
	_nebula_mat.set_shader_parameter("warp_scale", float(v["warp_scale"]))
	_nebula_mat.set_shader_parameter("wisp_strength", float(v["wisp"]))
	_nebula_mat.set_shader_parameter("swirl_speed", float(v["swirl"]))
	_nebula_mat.set_shader_parameter("drift_speed", float(v["drift"]))
	_nebula_mat.set_shader_parameter("opacity", float(v["opacity"]))
	_nebula_mat.set_shader_parameter("max_alpha", float(v["max_alpha"]))
	_nebula_mat.set_shader_parameter("pixels", float(v["pixels"]))


func _tick_nebula(delta: float) -> void:
	# Only nebula2 (variant 0) needs the flight-scroll sim driven; the alts animate via TIME internally.
	if _nebula_mat == null or _nebula_variant != 0:
		return
	_nebula_scroll += float(_values["Nebula"]["flight"]) * delta
	_nebula_mat.set_shader_parameter("scroll_offset", Vector2(0.0, _nebula_scroll))


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


# ---- Firecore Glow mode -----------------------------------------------------------

func _enter_firecore_glow() -> void:
	_knob_box.add_child(_label("Firecore Glow", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Radial glow behind a hazard firecore. Tune + Copy → bake behind the firecore.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_halo_wrap = Node2D.new()
	_halo_wrap.position = Vector2(Playfield.CENTER.x, 135.0)
	_halo_wrap.scale = Vector2(GALLERY_SPRITE_ZOOM, GALLERY_SPRITE_ZOOM)
	_stage.add_child(_halo_wrap)
	_make_halo_rect()
	var fc = load("res://scenes/enemies/factions/zealot/firecore_hazard.tscn").instantiate()
	_halo_wrap.add_child(fc)
	_freeze_node(fc)
	if fc.is_in_group("enemies"):
		fc.remove_from_group("enemies")
	fc.position = Vector2.ZERO
	fc.z_index = 2
	_halo_subject = fc
	_hd_note("FIRECORE GLOW", Vector2(Playfield.CENTER.x - 30.0, 84.0))
	_halo_common_rail("Firecore Glow")
	_apply_halo("Firecore Glow")


# ---- Star Glow mode ---------------------------------------------------------------

func _enter_star_glow() -> void:
	_knob_box.add_child(_label("Star Glow", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Radial glow on a backdrop star. Star size is 1:1 pixel-scaled. New Star re-rolls seed + colours.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_halo_wrap = Node2D.new()
	_halo_wrap.position = Vector2(Playfield.CENTER.x, 135.0)
	_halo_wrap.scale = Vector2(1.0, 1.0)
	_stage.add_child(_halo_wrap)
	_make_halo_rect()
	var st = load("res://Planets/Star/Star.tscn").instantiate()
	_halo_wrap.add_child(st)
	# Fix for pixel-parity SIGSEGV (anchor mismatch on ColorRect children).
	for c in st.find_children("*", "ColorRect", true, false):
		c.anchor_left = 0
		c.anchor_top = 0
		c.anchor_right = 0
		c.anchor_bottom = 0
	st.z_index = 1
	_halo_subject = st
	_size_star(float(_values["Star Glow"]["star_size"]))
	_hd_note("STAR GLOW", Vector2(Playfield.CENTER.x - 24.0, 84.0))
	_add_action("New Star", _new_star)
	_halo_common_rail("Star Glow")
	_apply_halo("Star Glow")


# ---- Halo glow shared helpers -----------------------------------------------------

func _make_halo_rect() -> void:
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	_halo_rect = ColorRect.new()
	_halo_rect.color = Color(1, 1, 1, 1)
	_halo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo_rect.z_index = 0
	_halo_rect.material = _halo_mat
	_halo_wrap.add_child(_halo_rect)


func _halo_gradient_tex() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([_halo_colors[0], _halo_colors[1], _halo_colors[2]])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


func _apply_halo(mode: String) -> void:
	if _halo_mat == null:
		return
	var key := _halo_values_key(mode)
	var v: Dictionary = _values[key]
	var px := float(v["halo_px"])
	_halo_rect.size = Vector2(px, px)
	_halo_rect.position = -_halo_rect.size * 0.5
	if _halo_kind == "Halo":
		_halo_mat.set_shader_parameter("pixelation", Vector2(px, px))
		_halo_mat.set_shader_parameter("gradient_steps", float(v["gradient_steps"]))
		_halo_mat.set_shader_parameter("spread", float(v["spread"]))
		_halo_mat.set_shader_parameter("size", float(v["size"]))
		_halo_mat.set_shader_parameter("speed", float(v["speed"]))
		_halo_mat.set_shader_parameter("ray1_density", float(v["ray1_density"]))
		_halo_mat.set_shader_parameter("ray2_density", float(v["ray2_density"]))
		_halo_mat.set_shader_parameter("ray2_intensity", float(v["ray2_intensity"]))
		_halo_mat.set_shader_parameter("core_intensity", float(v["core_intensity"]))
		_halo_mat.set_shader_parameter("seed", float(v["seed"]))
		_halo_mat.set_shader_parameter("hdr", _halo_hdr)
		_halo_mat.set_shader_parameter("gradient", _halo_gradient_tex())
	else:
		_halo_mat.set_shader_parameter("color", _halo_sparkle_color)
		_halo_mat.set_shader_parameter("scale", float(v["scale"]))
		_halo_mat.set_shader_parameter("circle_ratio", float(v["circle_ratio"]))
		_halo_mat.set_shader_parameter("decay_magnitude", float(v["decay_magnitude"]))
		_halo_mat.set_shader_parameter("cut_magnitude", float(v["cut_magnitude"]))
		_halo_mat.set_shader_parameter("rotate_speed", float(v["rotate_speed"]))
		_halo_mat.set_shader_parameter("time_speed", float(v["time_speed"]))
		_halo_mat.set_shader_parameter("frequency_base", float(v["frequency_base"]))
		_halo_mat.set_shader_parameter("frequency_disturbance_scale", float(v["frequency_disturbance_scale"]))
		_halo_mat.set_shader_parameter("stop_shine", _halo_stop_shine)
	if mode == "Star Glow" or mode == "Star Sparkle":
		_size_star(float(v["star_size"]))


# Adds into the rebuildable _halo_knob_box (NOT the main _knob_box) so the rows are cleared + rebuilt
# on every shader-kind switch instead of accumulating duplicates.
func _add_halo_color_row(caption: String, idx: int) -> void:
	_halo_knob_box.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var cp := ColorPickerButton.new()
	cp.color = _halo_colors[idx]
	cp.edit_alpha = true
	cp.custom_minimum_size = Vector2(0, 34)
	cp.color_changed.connect(func(c: Color):
		_halo_colors[idx] = c
		_apply_halo(MODES[_mode]))
	_halo_knob_box.add_child(cp)


func _halo_common_rail(mode: String) -> void:
	_knob_box.add_child(_label("Shader", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	dd.add_item("Halo")
	dd.add_item("Sparkle")
	dd.select(0 if _halo_kind == "Halo" else 1)
	dd.item_selected.connect(func(i: int):
		_halo_kind = "Halo" if i == 0 else "Sparkle"
		_halo_mat.shader = HALO_SHADER if _halo_kind == "Halo" else SPARKLE_SHADER
		_rebuild_halo_knobs(mode)
		_apply_halo(mode))
	_knob_box.add_child(dd)
	_halo_mat.shader = HALO_SHADER if _halo_kind == "Halo" else SPARKLE_SHADER
	_knob_box.add_child(HSeparator.new())
	_halo_knob_box = VBoxContainer.new()
	_halo_knob_box.add_theme_constant_override("separation", 6)
	_knob_box.add_child(_halo_knob_box)
	_rebuild_halo_knobs(mode)


func _size_star(size: float) -> void:
	if _halo_subject == null or not is_instance_valid(_halo_subject):
		return
	if not _halo_subject.has_method("set_pixels"):
		return
	_halo_subject.set_pixels(size)
	(_halo_subject as Control).position = Vector2(-size * 0.5, -size * 0.5)


func _new_star() -> void:
	if _halo_subject == null or not is_instance_valid(_halo_subject):
		return
	if _halo_subject.has_method("set_seed"):
		_halo_subject.set_seed(randi())
	if _halo_subject.has_method("randomize_colors"):
		_halo_subject.randomize_colors()
	_size_star(float(_values[_halo_values_key("Star Glow")]["star_size"]))


func _halo_values_key(mode: String) -> String:
	if _halo_kind == "Halo":
		return mode
	if mode == "Firecore Glow":
		return "Firecore Sparkle"
	if mode == "Star Glow":
		return "Star Sparkle"
	return mode


func _rebuild_halo_knobs(mode: String) -> void:
	if _halo_knob_box == null or not is_instance_valid(_halo_knob_box):
		return
	for c in _halo_knob_box.get_children():
		c.queue_free()
	var key := _halo_values_key(mode)
	var v: Dictionary = _values[key]
	for def in KNOBS[key]:
		var def_key := String(def["key"])
		var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(v[def_key]), float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
		_halo_knob_box.add_child(row_lbl)
		var sl := HSlider.new()
		sl.min_value = float(def["min"])
		sl.max_value = float(def["max"])
		sl.step = float(def["step"])
		sl.value = float(v[def_key])
		sl.custom_minimum_size = Vector2(0, 24)
		sl.value_changed.connect(func(val: float):
			v[def_key] = val
			row_lbl.text = "%s: %s" % [def["label"], _fmt(val, float(def["step"]))]
			_apply_halo(mode))
		_halo_knob_box.add_child(sl)
	_halo_knob_box.add_child(HSeparator.new())
	if _halo_kind == "Halo":
		var hdr_check := CheckButton.new()
		hdr_check.text = "HDR bloom"
		hdr_check.button_pressed = _halo_hdr
		hdr_check.add_theme_font_override("font", UiTheme.active_font())
		hdr_check.add_theme_font_size_override("font_size", FS_BODY)
		hdr_check.toggled.connect(func(v: bool):
			_halo_hdr = v
			_apply_halo(mode))
		_halo_knob_box.add_child(hdr_check)
		_halo_knob_box.add_child(HSeparator.new())
		_halo_knob_box.add_child(_label("Gradient Colours", FS_BODY, UiTheme.COLOR_ACCENT))
		_add_halo_color_row("Ray core / low", 0)
		_add_halo_color_row("Ray mid", 1)
		_add_halo_color_row("Ray tip / bright", 2)
		_halo_knob_box.add_child(HSeparator.new())
		var seed_btn := Button.new()
		seed_btn.text = "New Seed"
		UiTheme.style_button(seed_btn, true)
		seed_btn.add_theme_font_size_override("font_size", FS_BODY)
		seed_btn.custom_minimum_size = Vector2(0, 36)
		seed_btn.pressed.connect(func():
			var vals: Dictionary = _values[key]
			vals["seed"] = fmod(vals["seed"] + 3.7, 20.0)
			_apply_halo(mode))
		_halo_knob_box.add_child(seed_btn)
	else:
		_halo_knob_box.add_child(_label("Sparkle Colour", FS_CAPTION, UiTheme.COLOR_FAINT))
		var cp := ColorPickerButton.new()
		cp.color = _halo_sparkle_color
		cp.edit_alpha = true
		cp.custom_minimum_size = Vector2(0, 34)
		cp.color_changed.connect(func(c: Color):
			_halo_sparkle_color = c
			_apply_halo(mode))
		_halo_knob_box.add_child(cp)
		_halo_knob_box.add_child(HSeparator.new())
		var shine_check := CheckButton.new()
		shine_check.text = "Stop shine"
		shine_check.button_pressed = _halo_stop_shine
		shine_check.add_theme_font_override("font", UiTheme.active_font())
		shine_check.add_theme_font_size_override("font_size", FS_BODY)
		shine_check.toggled.connect(func(v: bool):
			_halo_stop_shine = v
			_apply_halo(mode))
		_halo_knob_box.add_child(shine_check)


# ---- Bloom Env mode (WorldEnvironment glow) --------------------------------

# ---- Glow mode: per-category HDR-bright modulate tuner ---------------------
# Five representative VFX (bullet / engine glowmask / laser line / explosion / particle) under a
# combat-like WorldEnvironment; one slider per category drives VfxGlowConfig's HDR multiplier and
# the demos re-modulate live. Save / Copy GDScript export the table (shared with the Combat VFX Lab).
var _glow_demo: Dictionary = {}

func _enter_glow() -> void:
	VfxGlowConfigC.ensure_loaded()
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CANVAS
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_strength = 0.7
	_env.glow_blend_mode = 1
	_env.glow_hdr_threshold = 1.5
	we.environment = _env
	_stage.add_child(we)
	_glow_demo.clear()
	var cats: Array = VfxGlowConfigC.CATEGORIES
	var spacing := 70.0
	var x0 := Playfield.CENTER.x - (cats.size() - 1) * spacing * 0.5
	for i in cats.size():
		var cat: String = cats[i]
		var pos := Vector2(x0 + i * spacing, 135.0)
		_glow_demo[cat] = _make_glow_demo(cat, pos)
		_hd_note(cat, Vector2(pos.x - 20.0, 176.0))
	_apply_vfx_glow()
	_knob_box.add_child(_label("VFX HDR Glow", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Per-category HDR-bright modulate multiplier — each demo\nblooms through the combat WorldEnvironment (threshold 1.5).\nSave / Copy GDScript export the table (shared with the\nCombat VFX Lab).", FS_CAPTION, UiTheme.COLOR_FAINT))
	_knob_box.add_child(HSeparator.new())
	for cat in cats:
		_add_glow_slider(cat)


func _make_glow_demo(cat: String, pos: Vector2) -> CanvasItem:
	if cat == "lasers":
		var line := Line2D.new()
		line.width = 4.0
		line.default_color = Color(0.6, 0.8, 1.0, 1.0)
		line.add_point(pos + Vector2(0, -26))
		line.add_point(pos + Vector2(0, 26))
		line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_stage.add_child(line)
		return line
	var s := Sprite2D.new()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos
	if cat == "particles":
		s.texture = _glow_dot_tex()
		s.scale = Vector2(7, 7)
	else:
		s.texture = load(String(GLOW_DEMO_TEX[cat]))
		s.scale = Vector2(5, 5)
		if cat == "bullets":
			s.hframes = 3
			s.frame = 0
		elif cat == "engines":
			s.hframes = 3
			s.frame = 1   # cobra glowmask (engine) frame
		elif cat == "explosions":
			s.hframes = 9
			s.frame = 4
	_stage.add_child(s)
	return s


func _apply_vfx_glow() -> void:
	for cat in _glow_demo:
		var node = _glow_demo[cat]
		if node != null and is_instance_valid(node):
			(node as CanvasItem).modulate = VfxGlowConfigC.hdr(cat)


func _add_glow_slider(cat: String) -> void:
	var m := VfxGlowConfigC.get_mult(cat)
	var row := _label("%s: %.2f" % [cat.capitalize(), m], FS_CAPTION, UiTheme.COLOR_FAINT)
	_knob_box.add_child(row)
	var sl := HSlider.new()
	sl.min_value = VfxGlowConfigC.SLIDER_MIN
	sl.max_value = VfxGlowConfigC.SLIDER_MAX
	sl.step = 0.05
	sl.value = m
	sl.custom_minimum_size = Vector2(0, 26)
	sl.value_changed.connect(func(v: float):
		VfxGlowConfigC.set_mult(cat, v)
		row.text = "%s: %.2f" % [cat.capitalize(), v]
		_apply_vfx_glow())
	_knob_box.add_child(sl)


static func _glow_dot_tex() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 8
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


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


# ---- Damage Smoke tuner -------------------------------------------------------

func _enter_damage_smoke() -> void:
	_knob_box.add_child(_label("Damage Smoke Trail", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Tunable dark damage-smoke trail from burnt\ncomponents. Spawns a flying host to emit\nthe trail continuously.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_hd_note("DAMAGE SMOKE", Vector2(Playfield.CENTER.x - 40.0, 56.0))
	_spawn_damage_smoke_ship()
	_build_knobs("Damage Smoke")
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Smoke Colour", FS_CAPTION, UiTheme.COLOR_FAINT))
	var cp := ColorPickerButton.new()
	cp.color = _dmg_smoke_color
	cp.edit_alpha = true
	cp.custom_minimum_size = Vector2(0, 34)
	cp.color_changed.connect(func(c: Color):
		_dmg_smoke_color = c
		_apply_damage_smoke())
	_knob_box.add_child(cp)


func _spawn_damage_smoke_ship() -> void:
	if _dmg_smoke_ship != null and is_instance_valid(_dmg_smoke_ship):
		_dmg_smoke_ship.queue_free()
	_dmg_smoke_ship = null
	_dmg_smoke_trail = null
	_dmg_smoke_t = 0.0
	var ship := _make_ship(Vector2(Playfield.CENTER.x, 10.0))
	_freeze_node(ship)
	if ship.is_in_group("enemies"):
		ship.remove_from_group("enemies")
	_dmg_smoke_ship = ship
	_dmg_smoke_vel = Vector2.DOWN * 60.0
	var trail = load("res://scripts/effects/damage_smoke_trail.gd").new()
	ship.add_child(trail)
	trail.set_player(ship)
	_dmg_smoke_trail = trail
	_apply_damage_smoke()


func _apply_damage_smoke() -> void:
	if _dmg_smoke_trail == null or not is_instance_valid(_dmg_smoke_trail):
		return
	var v: Dictionary = _values["Damage Smoke"]
	_dmg_smoke_trail.min_width = float(v["min_width"])
	_dmg_smoke_trail.max_width = float(v["max_width"])
	_dmg_smoke_trail.tail_width_mult = float(v["tail_width_mult"])
	_dmg_smoke_trail.point_lifetime = float(v["point_lifetime"])
	_dmg_smoke_trail.sample_interval_min = float(v["sample_interval_min"])
	_dmg_smoke_trail.sample_interval_max = float(v["sample_interval_max"])
	_dmg_smoke_trail.drift_base_speed = float(v["drift_base_speed"])
	_dmg_smoke_trail.drift_age_gain = float(v["drift_age_gain"])
	_dmg_smoke_trail.wander_px_per_sec = float(v["wander_px_per_sec"])
	_dmg_smoke_trail.smoke_color = _dmg_smoke_color
	_dmg_smoke_trail.apply_look()
	# Drive the trail to heavy damage so it actually EMITS in the lab. Production gates emission on the
	# host's hull dropping below activate_below (0.5); the frozen dummy never takes damage, so without this
	# it stays silent. Full severity (hull 0 / max 1) shows the densest max_width trail; re-driven after
	# apply_look (which resets Line2D width to min_width) so every slider change keeps the emission on.
	_dmg_smoke_trail._on_hull_changed(1.0, 0.0)


func _tick_damage_smoke(delta: float) -> void:
	if _dmg_smoke_ship != null and is_instance_valid(_dmg_smoke_ship):
		_dmg_smoke_ship.position += _dmg_smoke_vel * delta
		if _dmg_smoke_ship.position.y > 290.0:
			_dmg_smoke_ship.position = Vector2(Playfield.CENTER.x, 10.0)


# ---- Building Shadow tuner ---------------------------------------------------

# Building list = the enemy bench's "Buildings" category, pulled LIVE so NEW structures auto-appear here
# without editing this file (Roman 2026-07-13). Same source + filter the bench uses: EnemyManifest.all_enemies
# (the curated manifest ∪ every faction-tagged enemy) restricted to /ground/ scenes (enemy_bench._group_of →
# "Buildings"). Sorted + deterministic, so the OptionButton order + _bshadow_idx stay consistent across calls.
func _bshadow_buildings() -> Array:
	var out: Array = []
	for p in EnemyManifest.all_enemies(false):
		if String(p).to_lower().contains("/ground/"):
			out.append(String(p))
	return out

func _enter_building_shadow() -> void:
	_knob_box.add_child(_label("Building Shadow", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Oblique drop shadow for top-down buildings.\nPick a building; tune the sun globally + each layer's height.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_hd_note("BUILDING SHADOW", Vector2(Playfield.CENTER.x - 50.0, 56.0))
	# Ground plane — mid-grey so dark shadow is visible.
	_bshadow_ground = ColorRect.new()
	_bshadow_ground.color = Color(0.62, 0.63, 0.66, 1.0)
	_bshadow_ground.size = Vector2(160, 160)
	_bshadow_ground.position = Vector2(Playfield.CENTER.x - 80.0, 135.0 - 80.0)
	_bshadow_ground.z_index = -6
	_bshadow_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_bshadow_ground)
	# Building selector — pulled live from the bench's "Buildings" category (_bshadow_buildings).
	var paths: Array = _bshadow_buildings()
	if _bshadow_idx < 0 or _bshadow_idx >= paths.size():
		_bshadow_idx = 0
	_knob_box.add_child(_label("Building", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for path in paths:
		dd.add_item(String(path).get_file().replace(".tscn", "").replace("building_", "").replace("enemy_", ""))
	if not paths.is_empty():
		dd.select(_bshadow_idx)
	dd.item_selected.connect(func(i: int):
		_bshadow_idx = i
		_spawn_building_shadow(_bshadow_buildings()[i]))
	_knob_box.add_child(dd)
	# Global look knobs.
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Global Look", FS_BODY, UiTheme.COLOR_ACCENT))
	_build_knobs("Building Shadow")
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Shadow Tint", FS_CAPTION, UiTheme.COLOR_FAINT))
	var cp := ColorPickerButton.new()
	cp.color = _bshadow_tint
	cp.edit_alpha = true
	cp.custom_minimum_size = Vector2(0, 34)
	cp.color_changed.connect(func(c: Color):
		_bshadow_tint = c
		_apply_building_shadow())
	_knob_box.add_child(cp)
	# Per-layer sliders (built by _spawn_building_shadow).
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Per-layer Height", FS_BODY, UiTheme.COLOR_ACCENT))
	_bshadow_knob_box = VBoxContainer.new()
	_bshadow_knob_box.add_theme_constant_override("separation", 6)
	_knob_box.add_child(_bshadow_knob_box)
	if not paths.is_empty():
		_spawn_building_shadow(paths[_bshadow_idx])


func _spawn_building_shadow(path: String) -> void:
	if _bshadow_building != null and is_instance_valid(_bshadow_building):
		_bshadow_building.queue_free()
	_bshadow_building = null
	_bshadow_pairs.clear()
	if _bshadow_knob_box != null and is_instance_valid(_bshadow_knob_box):
		for c in _bshadow_knob_box.get_children():
			c.queue_free()
	var scn: PackedScene = load(path)
	if scn == null:
		return
	var building: Node2D = scn.instantiate()
	_freeze_node(building)
	if building.is_in_group("enemies"):
		building.remove_from_group("enemies")
	var wrap := Node2D.new()
	wrap.position = Vector2(Playfield.CENTER.x, 135.0)
	# 4× pixel zoom + NEAREST filtering so the buildings read as crisp in-game-style pixel art (Roman
	# 2026-07-13) — matches the game's 4× display scale. NEAREST on the wrapper propagates to the layer
	# sprites (they inherit PARENT_NODE); the shadow's own src_tex already samples filter_nearest.
	wrap.scale = Vector2(4.0, 4.0)
	wrap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrap.add_child(building)
	_stage.add_child(wrap)
	_bshadow_building = building
	# The building's _ready applies PRODUCTION setup that fights this isolated tuner: a ground z (-5 absolute,
	# which shoves the lab's shadows to -7 BEHIND the grey ground plane at -6) + its own auto-attached
	# shadows (whose raised-layer carriers collide with the ground plane as stray grey boxes). Reset z to
	# neutral so the ground plane sits UNDER the lab shadows, and strip the auto-attached ones so only the
	# lab's LIVE-tunable shadows show (Roman 2026-07-17).
	building.z_as_relative = true
	building.z_index = 0
	for existing in building.find_children("Shadow_*", "ColorRect", true, false):
		existing.free()
	var layers = load("res://scripts/effects/building_shadow.gd").casting_layers(building)
	if not _bshadow_heights.has(path):
		_bshadow_heights[path] = {}
	for layer in layers:
		var layer_name: String = String(layer.name)
		if not _bshadow_heights[path].has(layer_name):
			_bshadow_heights[path][layer_name] = 1.0 if layer_name == "Base" else 2.2
		var rect = load("res://scripts/effects/building_shadow.gd").attach(layer, _shadow_params_for(path, layer))
		if rect != null:
			building.add_child(rect)
			_bshadow_pairs.append({"rect": rect, "layer": layer})
	_rebuild_bshadow_knobs(path)


func _rebuild_bshadow_knobs(path: String) -> void:
	if _bshadow_knob_box == null or not is_instance_valid(_bshadow_knob_box):
		return
	for c in _bshadow_knob_box.get_children():
		c.queue_free()
	var layers = load("res://scripts/effects/building_shadow.gd").casting_layers(_bshadow_building)
	for layer in layers:
		var layer_name: String = String(layer.name)
		var h: float = _bshadow_heights[path].get(layer_name, 1.0)
		var row_lbl := _label("%s height: %.2f" % [layer_name, h], FS_CAPTION, UiTheme.COLOR_FAINT)
		_bshadow_knob_box.add_child(row_lbl)
		var sl := HSlider.new()
		sl.min_value = 0.2
		sl.max_value = 5.0
		sl.step = 0.05
		sl.value = h
		sl.custom_minimum_size = Vector2(0, 24)
		sl.value_changed.connect(func(v: float):
			_bshadow_heights[path][layer_name] = v
			row_lbl.text = "%s height: %.2f" % [layer_name, v]
			_apply_building_shadow())
		_bshadow_knob_box.add_child(sl)


func _shadow_params_for(path: String, layer: Sprite2D) -> Dictionary:
	var v: Dictionary = _values["Building Shadow"]
	var angle_deg: float = float(v["sun_angle_deg"])
	var sun_dir: Vector2 = Vector2(cos(deg_to_rad(angle_deg)), sin(deg_to_rad(angle_deg)))
	var height: float = _bshadow_heights.get(path, {}).get(layer.name, 1.0)
	return {
		"sun_dir": sun_dir,
		"sun_elevation": float(v["sun_elevation"]),
		"shadow_strength": float(v["shadow_strength"]),
		"shadow_softness": float(v["shadow_softness"]),
		"steps": int(v["steps"]),
		"step_px": float(v["step_px"]),
		"shadow_aa_radius_px": float(v["shadow_aa_radius_px"]),
		"shadow_ray_offset_px": float(v["shadow_ray_offset_px"]),
		"carrier_scale": float(v["carrier_scale"]),
		"shadow_tint": _bshadow_tint,
		"height_scale": height,
	}


func _apply_building_shadow() -> void:
	for pair in _bshadow_pairs:
		var rect = pair["rect"]
		var layer = pair["layer"]
		load("res://scripts/effects/building_shadow.gd").apply_params(rect, layer, _shadow_params_for(_bshadow_idx_to_path(), layer))


func _bshadow_idx_to_path() -> String:
	var paths: Array = _bshadow_buildings()
	if paths.is_empty():
		return ""
	if _bshadow_idx < 0 or _bshadow_idx >= paths.size():
		return String(paths[0])
	return String(paths[_bshadow_idx])


# ---- Building Boom tuner (death explosion per building) ----------------------

func _enter_building_boom() -> void:
	_knob_box.add_child(_label("Building Destruction", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Configure each building's DEATH explosion. Pick a building,\ntune its boom, Beat to preview. Same knobs as Expl. Tuner,\nstored per building.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_hd_note("BUILDING BOOM", Vector2(Playfield.CENTER.x - 50.0, 56.0))
	# Building selector.
	_knob_box.add_child(_label("Building", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	var paths: Array = _bshadow_buildings()
	for path in paths:
		dd.add_item(path.get_file().replace(".tscn", "").replace("building_", "").replace("enemy_", ""))
	_bboom_idx = clampi(_bboom_idx, 0, maxi(0, paths.size() - 1))
	dd.select(_bboom_idx)
	dd.item_selected.connect(func(i: int):
		_bboom_idx = i
		_spawn_bboom_building(_bshadow_buildings()[i]))
	_knob_box.add_child(dd)
	# Beat button.
	_add_action("💥 Beat Building", _beat_building)
	# Auto-replay checkbox.
	var auto := CheckButton.new()
	auto.text = "Auto-replay loop"
	auto.button_pressed = _bboom_auto
	auto.add_theme_font_override("font", UiTheme.active_font())
	auto.add_theme_font_size_override("font_size", FS_BODY)
	auto.toggled.connect(func(v: bool): _bboom_auto = v)
	_knob_box.add_child(auto)
	# Per-building knob rail (built by _spawn_bboom_building).
	_knob_box.add_child(HSeparator.new())
	_knob_box.add_child(_label("Explosion Config", FS_BODY, UiTheme.COLOR_ACCENT))
	_bboom_knob_box = VBoxContainer.new()
	_bboom_knob_box.add_theme_constant_override("separation", 6)
	_knob_box.add_child(_bboom_knob_box)
	_spawn_bboom_building(_bshadow_buildings()[_bboom_idx])


func _spawn_bboom_building(path: String) -> void:
	if _bboom_building != null and is_instance_valid(_bboom_building):
		_bboom_building.queue_free()
	_bboom_building = null
	if _bboom_wrap != null and is_instance_valid(_bboom_wrap):
		_bboom_wrap.queue_free()
	_bboom_wrap = null
	if _bboom_knob_box != null and is_instance_valid(_bboom_knob_box):
		for c in _bboom_knob_box.get_children():
			c.queue_free()
	var scn: PackedScene = load(path)
	if scn == null:
		return
	var building: Node2D = scn.instantiate()
	_freeze_node(building)
	if building.is_in_group("enemies"):
		building.remove_from_group("enemies")
	# Gameplay size (1×, no zoom) — the building reads at the same scale it appears in combat (Roman 2026-07-16).
	var wrap := Node2D.new()
	wrap.position = Vector2(Playfield.CENTER.x, 135.0)
	wrap.add_child(building)
	_stage.add_child(wrap)
	_bboom_building = building
	_bboom_wrap = wrap
	# Init config if absent.
	if not _bboom_cfg.has(path):
		_bboom_cfg[path] = {
			"type": "basic",
			"size": 1.5,
			"area": 16.0,
			"duration": 0.07,
			"density": 3.0,
			"stagger": 0.06,
			"secondaries": 1.0,
			"glow": 0.9,
			"shockwave": 0.0,
			"sparks": 1.0,
			"debris": 1.0,
		}
	_rebuild_bboom_knobs(path)


func _rebuild_bboom_knobs(path: String) -> void:
	if _bboom_knob_box == null or not is_instance_valid(_bboom_knob_box):
		return
	for c in _bboom_knob_box.get_children():
		c.queue_free()
	var cfg: Dictionary = _bboom_cfg[path]
	# Type dropdown.
	_bboom_knob_box.add_child(_label("Type", FS_CAPTION, UiTheme.COLOR_FAINT))
	var type_dd := OptionButton.new()
	type_dd.add_theme_font_override("font", UiTheme.active_font())
	type_dd.add_theme_font_size_override("font_size", FS_BODY)
	type_dd.custom_minimum_size = Vector2(0, 34)
	for t in ["basic", "ball", "fireball", "mixed"]:
		type_dd.add_item(String(t))
	type_dd.select(maxi(0, ["basic", "ball", "fireball", "mixed"].find(cfg["type"])))
	type_dd.item_selected.connect(func(i: int):
		cfg["type"] = ["basic", "ball", "fireball", "mixed"][i])
	_bboom_knob_box.add_child(type_dd)
	# Explosion knobs (from Expl. Tuner KNOBS).
	var knob_defs := [
		{"key": "size", "label": "Size", "min": 0.2, "max": 5.0, "step": 0.05},
		{"key": "area", "label": "Area", "min": 0.0, "max": 80.0, "step": 1.0},
		{"key": "duration", "label": "Duration", "min": 0.02, "max": 0.2, "step": 0.005},
		{"key": "density", "label": "Density", "min": 1.0, "max": 12.0, "step": 1.0},
		{"key": "stagger", "label": "Stagger", "min": 0.0, "max": 0.4, "step": 0.01},
		{"key": "secondaries", "label": "Secondaries", "min": 0.0, "max": 4.0, "step": 0.25},
		{"key": "glow", "label": "Glow", "min": 0.0, "max": 3.0, "step": 0.1},
		{"key": "shockwave", "label": "Shockwave", "min": 0.0, "max": 3.0, "step": 0.1},
		{"key": "sparks", "label": "Sparks", "min": 0.0, "max": 3.0, "step": 0.1},
		{"key": "debris", "label": "Debris", "min": 0.0, "max": 3.0, "step": 0.1},
	]
	for def in knob_defs:
		var key := String(def["key"])
		var val := float(cfg.get(key, def.get("def", 0.0)))
		var row_lbl := _label("%s: %s" % [def["label"], _fmt(val, float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
		_bboom_knob_box.add_child(row_lbl)
		var sl := HSlider.new()
		sl.min_value = float(def["min"])
		sl.max_value = float(def["max"])
		sl.step = float(def["step"])
		sl.value = val
		sl.custom_minimum_size = Vector2(0, 24)
		sl.value_changed.connect(func(v: float):
			cfg[key] = v
			row_lbl.text = "%s: %s" % [def["label"], _fmt(v, float(def["step"]))])
		_bboom_knob_box.add_child(sl)


func _beat_building() -> void:
	if _bboom_building == null or not is_instance_valid(_bboom_building):
		return
	if _bshadow_buildings().is_empty():
		return
	var cfg: Dictionary = _bboom_cfg.get(_bshadow_buildings()[_bboom_idx], {})
	if cfg.is_empty():
		return
	# Parent the boom to _stage (at origin), NOT the wrap: play_config sets global_position BEFORE add_child,
	# so under an offset/scaled parent the world pos blows up. _stage is at origin → the world pos resolves
	# correctly (same as the Expl. Tuner). At 1× this matches the building's gameplay scale.
	ExplosionFx.play_config(_bboom_building.global_position, cfg, _stage)
	# Also scatter the debris.png chunks the real building death throws (EnemyDeathFx.spawn_debris), so the
	# preview shows the FULL death — explosion (sparks + embers) + chunks (Roman 2026-07-17).
	load("res://scripts/effects/enemy_death_fx.gd").spawn_debris(_stage, _bboom_building.global_position, 3.0)


func _tick_building_boom(delta: float) -> void:
	if not _bboom_auto:
		return
	_bboom_acc += delta
	if _bboom_acc >= 2.0:
		_bboom_acc = 0.0
		_beat_building()


# ---- Enemy Shields tab -----------------------------------------------------
# Spawn a frozen enemy and wrap it in the REAL hex-shield ring (shared ShieldRingFx driver), so the
# bubble SIZE (ring_size) + ROUNDNESS (elongation) can be fitted to each shielded enemy. Copy emits the
# two values to paste into that enemy's ShieldComponent (bulwark .tscn exports; sapper + mine in code).
func _enter_enemy_shields() -> void:
	_esh_list = EnemyManifest.all_enemies()
	_knob_box.add_child(_label("Enemy Shields", FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Fit the hex-shield bubble to each enemy —\nsize + roundness, stored PER enemy.\nSave persists; Copy → every enemy's\nShieldComponent.", FS_CAPTION, UiTheme.COLOR_FAINT))
	_knob_box.add_child(_label("Enemy", FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for p in _esh_list:
		dd.add_item(_esh_enemy_name(String(p)))
	dd.select(clampi(_esh_idx, 0, maxi(0, _esh_list.size() - 1)))
	dd.item_selected.connect(func(i: int):
		_esh_idx = i
		_spawn_shield_enemy()
		_rebuild_esh_knobs())
	_knob_box.add_child(dd)
	_add_action("Pulse Hit", _esh_pulse_hit)
	_knob_box.add_child(HSeparator.new())
	# Size/roundness sliders live in a sub-box, rebuilt per enemy so each loads ITS stored values.
	_esh_knob_box = VBoxContainer.new()
	_esh_knob_box.add_theme_constant_override("separation", 6)
	_knob_box.add_child(_esh_knob_box)
	_hd_note("SHIELD FIT", Vector2(Playfield.CENTER.x - 26.0, 84.0))
	_spawn_shield_enemy()
	_rebuild_esh_knobs()


func _esh_enemy_name(path: String) -> String:
	return path.get_file().replace(".tscn", "").replace("enemy_", "")


func _esh_path() -> String:
	if _esh_list.is_empty():
		return ""
	return String(_esh_list[clampi(_esh_idx, 0, _esh_list.size() - 1)])


# The current enemy's {ring_size, elongation} (seeded on spawn); defaults if never touched.
func _esh_cur() -> Dictionary:
	var path := _esh_path()
	if path == "" or not _esh_by_enemy.has(path):
		return {"ring_size": 32.0, "elongation": 0.0}
	return _esh_by_enemy[path]


func _esh_faction_color(path: String) -> Color:
	var home: int = int((Factions.ENEMY_TAGS.get(path, {}) as Dictionary).get("home", -1))
	if home < 0:
		return ShieldRingFxC.PLAYER_COLOR
	return Factions.muzzle_inner(home)


func _esh_pulse_hit() -> void:
	if _esh_fx != null:
		_esh_fx.hit_flash(1.0, 0.1)


# Rebuild the size/roundness sliders for the SELECTED enemy (loads ITS stored values). Mirrors the
# Death tab's per-style knob box.
func _rebuild_esh_knobs() -> void:
	if _esh_knob_box == null or not is_instance_valid(_esh_knob_box):
		return
	for c in _esh_knob_box.get_children():
		c.queue_free()
	var path := _esh_path()
	var cur := _esh_cur()
	var knobs := [
		{"key": "ring_size", "label": "Bubble size (px)", "min": 12.0, "max": 96.0, "step": 1.0},
		{"key": "elongation", "label": "Roundness → capsule", "min": 0.0, "max": 0.85, "step": 0.02},
	]
	for def in knobs:
		var key := String(def["key"])
		var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(cur[key]), float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
		_esh_knob_box.add_child(row_lbl)
		var sl := HSlider.new()
		sl.min_value = float(def["min"])
		sl.max_value = float(def["max"])
		sl.step = float(def["step"])
		sl.value = float(cur[key])
		sl.custom_minimum_size = Vector2(0, 26)
		sl.value_changed.connect(func(v: float):
			if _esh_by_enemy.has(path):
				_esh_by_enemy[path][key] = v
			row_lbl.text = "%s: %s" % [def["label"], _fmt(v, float(def["step"]))]
			_apply_esh_knobs())
		_esh_knob_box.add_child(sl)


func _spawn_shield_enemy() -> void:
	if _esh_enemy != null and is_instance_valid(_esh_enemy):
		_esh_enemy.queue_free()
	_esh_enemy = null
	_esh_ring = null
	_esh_mat = null
	_esh_fx = null
	if _esh_list.is_empty():
		return
	var path := _esh_path()
	var enemy: Node2D = load(path).instantiate()
	_stage.add_child(enemy)          # run _ready so the sprite/scale + components settle
	# Seed this enemy's stored fit from its CURRENT ShieldComponent once, so tuning starts from live.
	if not _esh_by_enemy.has(path):
		_esh_by_enemy[path] = _esh_baked_fit(enemy)
	_freeze_node(enemy)              # no movement / firing / audio
	if enemy.is_in_group("enemies"):
		enemy.remove_from_group("enemies")
	# Drop any ring the enemy's own ShieldComponent built — the tuner drives its own.
	for r in enemy.find_children("ShieldRing", "ColorRect", true, false):
		r.queue_free()
	enemy.position = Vector2(Playfield.CENTER.x, 135.0)
	enemy.rotation = 0.0
	enemy.scale = Vector2(GALLERY_SPRITE_ZOOM, GALLERY_SPRITE_ZOOM)   # inspection zoom (tuned values stay 1×)
	_esh_enemy = enemy
	# The real hex-shield ring, driven by the shared ShieldRingFx (Sparse Plates base + HDR bloom).
	_esh_mat = ShaderMaterial.new()
	_esh_mat.shader = load("res://graphics/hex_shield.gdshader")
	_esh_ring = ColorRect.new()
	_esh_ring.name = "ShieldRing"
	_esh_ring.color = Color(1, 1, 1, 1)
	_esh_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_esh_ring.z_index = 2
	_esh_ring.material = _esh_mat
	enemy.add_child(_esh_ring)
	_esh_fx = ShieldRingFxC.new(_esh_mat, _esh_ring, _esh_faction_color(path))
	_apply_esh_knobs()
	_esh_fx.apply_state(1.0)
	_esh_fx.set_online(true, 0.0)


# An enemy's baked ShieldComponent fit (ring_size + elongation), or defaults if it has no shield.
func _esh_baked_fit(enemy: Node) -> Dictionary:
	var fit := {"ring_size": 32.0, "elongation": 0.0}
	if "components" in enemy:
		for c in enemy.components:
			if c != null and "ring_size" in c and "elongation" in c:
				fit["ring_size"] = float(c.ring_size)
				fit["elongation"] = float(c.elongation)
				break
	return fit


func _apply_esh_knobs() -> void:
	if _esh_ring == null or not is_instance_valid(_esh_ring) or _esh_mat == null or _esh_fx == null:
		return
	var cur := _esh_cur()
	_esh_fx.set_ring_size(float(cur["ring_size"]))   # size + centre + resolution-scaled cells (1:1 px)
	_esh_mat.set_shader_parameter("elongation", float(cur["elongation"]))


# Every TOUCHED enemy → a ShieldComponent line (only enemies you've spawned/tuned appear).
func _snippet_esh() -> String:
	var lines := ["# Enemy shield fit — paste each enemy's ring_size / elongation onto its ShieldComponent",
		"# (bulwark = .tscn ShieldComponent exports; sapper/mine = sh.ring_size / sh.elongation in code)."]
	var names: Array = _esh_by_enemy.keys()
	names.sort()
	for path in names:
		var fit: Dictionary = _esh_by_enemy[path]
		lines.append("%s:  ring_size = %.0f   elongation = %.2f" % [_esh_enemy_name(String(path)), float(fit["ring_size"]), float(fit["elongation"])])
	return "\n".join(lines) + "\n"


func _snippet_firecore() -> String:
	var key := _halo_values_key("Firecore Glow")
	var v: Dictionary = _values[key]
	var px := float(v["halo_px"])
	var t := ""
	if _halo_kind == "Halo":
		t = "# Shader Lab — firecore glow (graphics/pixel_halo_glow.gdshader)\n"
		t += "var mat := ShaderMaterial.new()\n"
		t += "mat.shader = preload(\"res://graphics/pixel_halo_glow.gdshader\")\n"
		t += "mat.set_shader_parameter(\"pixelation\", Vector2(%.0f, %.0f))\n" % [px, px]
		t += "mat.set_shader_parameter(\"gradient_steps\", %.0f)\n" % float(v["gradient_steps"])
		t += "mat.set_shader_parameter(\"spread\", %.3f)\n" % float(v["spread"])
		t += "mat.set_shader_parameter(\"size\", %.3f)\n" % float(v["size"])
		t += "mat.set_shader_parameter(\"speed\", %.2f)\n" % float(v["speed"])
		t += "mat.set_shader_parameter(\"ray1_density\", %.1f)\n" % float(v["ray1_density"])
		t += "mat.set_shader_parameter(\"ray2_density\", %.1f)\n" % float(v["ray2_density"])
		t += "mat.set_shader_parameter(\"ray2_intensity\", %.2f)\n" % float(v["ray2_intensity"])
		t += "mat.set_shader_parameter(\"core_intensity\", %.2f)\n" % float(v["core_intensity"])
		t += "mat.set_shader_parameter(\"seed\", %.1f)\n" % float(v["seed"])
		t += "mat.set_shader_parameter(\"hdr\", %s)\n" % ("true" if _halo_hdr else "false")
		t += "var grad := Gradient.new()\n"
		t += "grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])\n"
		t += "grad.colors = PackedColorArray([Color(\"%s\"), Color(\"%s\"), Color(\"%s\")])\n" % [_halo_colors[0].to_html(true), _halo_colors[1].to_html(true), _halo_colors[2].to_html(true)]
		t += "var gtex := GradientTexture1D.new()\n"
		t += "gtex.gradient = grad\n"
		t += "mat.set_shader_parameter(\"gradient\", gtex)\n"
		t += "# Apply to a ColorRect(size=(px,px)) or sprite with the gradient & halo params.\n"
	else:
		t = "# Shader Lab — firecore sparkle (graphics/sparkle_star.gdshader)\n"
		t += "var mat := ShaderMaterial.new()\n"
		t += "mat.shader = preload(\"res://graphics/sparkle_star.gdshader\")\n"
		t += "mat.set_shader_parameter(\"color\", Color(\"%s\"))\n" % _halo_sparkle_color.to_html(true)
		t += "mat.set_shader_parameter(\"scale\", %.1f)\n" % float(v["scale"])
		t += "mat.set_shader_parameter(\"circle_ratio\", %.2f)\n" % float(v["circle_ratio"])
		t += "mat.set_shader_parameter(\"decay_magnitude\", %.2f)\n" % float(v["decay_magnitude"])
		t += "mat.set_shader_parameter(\"cut_magnitude\", %.3f)\n" % float(v["cut_magnitude"])
		t += "mat.set_shader_parameter(\"rotate_speed\", %.2f)\n" % float(v["rotate_speed"])
		t += "mat.set_shader_parameter(\"time_speed\", %.2f)\n" % float(v["time_speed"])
		t += "mat.set_shader_parameter(\"frequency_base\", %.2f)\n" % float(v["frequency_base"])
		t += "mat.set_shader_parameter(\"frequency_disturbance_scale\", %.2f)\n" % float(v["frequency_disturbance_scale"])
		t += "mat.set_shader_parameter(\"stop_shine\", %s)\n" % ("true" if _halo_stop_shine else "false")
		t += "# Apply to a ColorRect(size=(px,px)) for the sparkle overlay.\n"
	return t


func _snippet_star() -> String:
	var key := _halo_values_key("Star Glow")
	var v: Dictionary = _values[key]
	var px := float(v["halo_px"])
	var star_size := float(v["star_size"])
	var t := ""
	if _halo_kind == "Halo":
		t = "# Shader Lab — star glow (graphics/pixel_halo_glow.gdshader)\n"
		t += "var mat := ShaderMaterial.new()\n"
		t += "mat.shader = preload(\"res://graphics/pixel_halo_glow.gdshader\")\n"
		t += "mat.set_shader_parameter(\"pixelation\", Vector2(%.0f, %.0f))\n" % [px, px]
		t += "mat.set_shader_parameter(\"gradient_steps\", %.0f)\n" % float(v["gradient_steps"])
		t += "mat.set_shader_parameter(\"spread\", %.3f)\n" % float(v["spread"])
		t += "mat.set_shader_parameter(\"size\", %.3f)\n" % float(v["size"])
		t += "mat.set_shader_parameter(\"speed\", %.2f)\n" % float(v["speed"])
		t += "mat.set_shader_parameter(\"ray1_density\", %.1f)\n" % float(v["ray1_density"])
		t += "mat.set_shader_parameter(\"ray2_density\", %.1f)\n" % float(v["ray2_density"])
		t += "mat.set_shader_parameter(\"ray2_intensity\", %.2f)\n" % float(v["ray2_intensity"])
		t += "mat.set_shader_parameter(\"core_intensity\", %.2f)\n" % float(v["core_intensity"])
		t += "mat.set_shader_parameter(\"seed\", %.1f)\n" % float(v["seed"])
		t += "mat.set_shader_parameter(\"hdr\", %s)\n" % ("true" if _halo_hdr else "false")
		t += "var grad := Gradient.new()\n"
		t += "grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])\n"
		t += "grad.colors = PackedColorArray([Color(\"%s\"), Color(\"%s\"), Color(\"%s\")])\n" % [_halo_colors[0].to_html(true), _halo_colors[1].to_html(true), _halo_colors[2].to_html(true)]
		t += "var gtex := GradientTexture1D.new()\n"
		t += "gtex.gradient = grad\n"
		t += "mat.set_shader_parameter(\"gradient\", gtex)\n"
		t += "# Star size (set_pixels): %.0f\n" % star_size
		t += "# Apply to a ColorRect(size=(px,px)) for the halo backdrop.\n"
	else:
		t = "# Shader Lab — star sparkle (graphics/sparkle_star.gdshader)\n"
		t += "var mat := ShaderMaterial.new()\n"
		t += "mat.shader = preload(\"res://graphics/sparkle_star.gdshader\")\n"
		t += "mat.set_shader_parameter(\"color\", Color(\"%s\"))\n" % _halo_sparkle_color.to_html(true)
		t += "mat.set_shader_parameter(\"scale\", %.1f)\n" % float(v["scale"])
		t += "mat.set_shader_parameter(\"circle_ratio\", %.2f)\n" % float(v["circle_ratio"])
		t += "mat.set_shader_parameter(\"decay_magnitude\", %.2f)\n" % float(v["decay_magnitude"])
		t += "mat.set_shader_parameter(\"cut_magnitude\", %.3f)\n" % float(v["cut_magnitude"])
		t += "mat.set_shader_parameter(\"rotate_speed\", %.2f)\n" % float(v["rotate_speed"])
		t += "mat.set_shader_parameter(\"time_speed\", %.2f)\n" % float(v["time_speed"])
		t += "mat.set_shader_parameter(\"frequency_base\", %.2f)\n" % float(v["frequency_base"])
		t += "mat.set_shader_parameter(\"frequency_disturbance_scale\", %.2f)\n" % float(v["frequency_disturbance_scale"])
		t += "mat.set_shader_parameter(\"stop_shine\", %s)\n" % ("true" if _halo_stop_shine else "false")
		t += "# Star size (set_pixels): %.0f\n" % star_size
		t += "# Apply to a ColorRect(size=(px,px)) for the sparkle backdrop.\n"
	return t


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
		"Damage Smoke":
			_tick_damage_smoke(delta)
		"Building Boom":
			_tick_building_boom(delta)
		"Death":
			_tick_death(delta)
		"Nebula":
			_tick_nebula(delta)
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
		GlowFx.attach_glow(bullet.get_node("Bullet"), Color(1.0, 0.85, 0.5), 0.7, 0.6)
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
		"Bloom Env":
			_apply_bloom_env_knobs()
		"Damage":
			_apply_damage_knobs()
		"Disintegrate":
			_apply_disintegrate_knobs()
		"Nebula":
			_apply_nebula_knobs()
		"Damage Smoke":
			_apply_damage_smoke()
		"Building Shadow":
			_apply_building_shadow()
		"Enemy Shields":
			_apply_esh_knobs()
		"Firecore Glow":
			_apply_halo("Firecore Glow")
		"Star Glow":
			_apply_halo("Star Glow")


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


# An enemy-bullet sprite (frame 0 of its strip) under a Node2D, so GlowFx
# can attach a radial halo. `spec` = a BULLETS entry {path, frames}.
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
	VfxGlowConfigC.save()   # persist the VFX HDR-glow table (Glow mode)
	var out: Dictionary = _values.duplicate(true)
	var cols := {}
	for k in _dmg_colors:
		cols[k] = (_dmg_colors[k] as Color).to_html(false)
	out["DamageColors"] = cols
	var stops := []
	for s in _ember_stops:
		stops.append({"color": (s["color"] as Color).to_html(false), "offset": float(s["offset"])})
	out["EmberGradient"] = stops
	# Ship Dmg + Death-style knobs are intentionally NOT persisted (Roman 2026-07-15) — they re-seed from
	# the live SSOT (SIZE_PRESETS / STYLE_KNOBS) each session so the tuner can't drift from the game. Bake
	# tunes back into those code tables via Copy GDScript instead of a save blob.
	if not _esh_by_enemy.is_empty():
		out["EnemyShieldFit"] = _esh_by_enemy
	if not _bshadow_heights.is_empty():
		out["BuildingShadowHeights"] = _bshadow_heights
	var bshadow_tint_html := (_bshadow_tint as Color).to_html(true)
	out["BuildingShadowTint"] = bshadow_tint_html
	out["BuildingShadowIdx"] = _bshadow_idx
	if not _bboom_cfg.is_empty():
		out["BuildingBoomCfg"] = _bboom_cfg
	out["BuildingBoomIdx"] = _bboom_idx
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
		var esh: Dictionary = data.get("EnemyShieldFit", {})
		for esh_path in esh:
			var e: Dictionary = esh[esh_path]
			_esh_by_enemy[String(esh_path)] = {"ring_size": float(e.get("ring_size", 32.0)), "elongation": float(e.get("elongation", 0.0))}
		var cols: Dictionary = data.get("DamageColors", {})
		for k in _dmg_colors:
			if cols.has(k):
				_dmg_colors[k] = Color(String(cols[k]))
		var stops: Array = data.get("EmberGradient", [])
		if stops.size() >= 2:
			_ember_stops.clear()
			for s in stops:
				_ember_stops.append({"color": Color(String(s["color"])), "offset": float(s["offset"])})
		# Ship Dmg + Death-style knobs are NOT loaded from the save (Roman 2026-07-15): they always re-seed
		# from the live SSOT — ship_damage_tells.SIZE_PRESETS (_init_sd_dmg_vals) and DeathEffects.STYLE_KNOBS
		# (_init_death_vals) — so the tuner opens at the current live configuration and can't go stale from an
		# old persisted blob. Tune from there; bake changes back into those tables via Copy GDScript.
		var bsh: Dictionary = data.get("BuildingShadowHeights", {})
		if not bsh.is_empty():
			for path in bsh:
				var heights: Dictionary = bsh[path]
				_bshadow_heights[String(path)] = {}
				for layer_name in heights:
					_bshadow_heights[String(path)][String(layer_name)] = float(heights[layer_name])
		var bst: Variant = data.get("BuildingShadowTint", null)
		if bst != null:
			_bshadow_tint = Color(String(bst))
		var bsi: Variant = data.get("BuildingShadowIdx", 0)
		if bsi != null:
			_bshadow_idx = int(bsi)
		var bbc: Dictionary = data.get("BuildingBoomCfg", {})
		if not bbc.is_empty():
			for path in bbc:
				var cfg: Dictionary = bbc[path]
				var out_cfg: Dictionary = {}
				for k in cfg:
					if String(k) == "type":
						out_cfg["type"] = String(cfg[k])
					else:
						out_cfg[String(k)] = float(cfg[k])
				_bboom_cfg[String(path)] = out_cfg
		var bbi: Variant = data.get("BuildingBoomIdx", 0)
		if bbi != null:
			_bboom_idx = int(bbi)


func _on_copy() -> void:
	var txt := ""
	match MODES[_mode]:
		"Embers":
			txt = _snippet_embers()
		"Smoke":
			txt = _snippet_smoke()
		"Glow":
			txt = VfxGlowConfigC.snippet()
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
		"Damage Smoke":
			txt = _snippet_damage_smoke()
		"Building Shadow":
			txt = _snippet_building_shadow()
		"Building Boom":
			txt = _snippet_building_boom()
		"Death":
			txt = _snippet_death()
		"Nebula":
			txt = _snippet_nebula()
		"Enemy Shields":
			txt = _snippet_esh()
		"Firecore Glow":
			txt = _snippet_firecore()
		"Star Glow":
			txt = _snippet_star()
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
	t += "#          GlowFx.attach_glow($Ship, Color(0.5,0.9,1.0)) + 4px hit dot\n"
	t += "#   Phase: GlowFx.attach_glow($Ship, Color(0.2,0.5,1.0)) + additive ghosts\n"
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


func _snippet_damage_smoke() -> String:
	var v: Dictionary = _values["Damage Smoke"]
	var t := "# Shader Lab — damage smoke trail (scripts/effects/damage_smoke_trail.gd)\n"
	t += "# Apply these vars to a DamageSmokeTrail instance, then call apply_look().\n"
	t += "var trail := DamageSmokeTrail.new()\n"
	t += "trail.min_width = %.1f\n" % float(v["min_width"])
	t += "trail.max_width = %.1f\n" % float(v["max_width"])
	t += "trail.tail_width_mult = %.1f\n" % float(v["tail_width_mult"])
	t += "trail.point_lifetime = %.2f\n" % float(v["point_lifetime"])
	t += "trail.sample_interval_min = %.3f\n" % float(v["sample_interval_min"])
	t += "trail.sample_interval_max = %.3f\n" % float(v["sample_interval_max"])
	t += "trail.drift_base_speed = %.1f\n" % float(v["drift_base_speed"])
	t += "trail.drift_age_gain = %.1f\n" % float(v["drift_age_gain"])
	t += "trail.wander_px_per_sec = %.1f\n" % float(v["wander_px_per_sec"])
	t += "trail.smoke_color = Color(\"%s\")\n" % _dmg_smoke_color.to_html(true)
	t += "trail.apply_look()\n"
	t += "host.add_child(trail)\n"
	t += "trail.set_player(host)\n"
	return t


func _snippet_building_shadow() -> String:
	var v: Dictionary = _values["Building Shadow"]
	var angle_deg: float = float(v["sun_angle_deg"])
	var sun_dir: Vector2 = Vector2(cos(deg_to_rad(angle_deg)), sin(deg_to_rad(angle_deg)))
	var t := "# Shader Lab — building shadow look (scripts/effects/building_shadow.gd)\n"
	t += "const BUILDING_SHADOW_LOOK := {\n"
	t += "\t\"sun_dir\": Vector2(%.3f, %.3f),\n" % [sun_dir.x, sun_dir.y]
	t += "\t\"sun_elevation\": %.2f,\n" % float(v["sun_elevation"])
	t += "\t\"shadow_strength\": %.2f,\n" % float(v["shadow_strength"])
	t += "\t\"shadow_softness\": %.3f,\n" % float(v["shadow_softness"])
	t += "\t\"steps\": %d,\n" % int(v["steps"])
	t += "\t\"step_px\": %.2f,\n" % float(v["step_px"])
	t += "\t\"shadow_aa_radius_px\": %.2f,\n" % float(v["shadow_aa_radius_px"])
	t += "\t\"shadow_ray_offset_px\": %.1f,\n" % float(v["shadow_ray_offset_px"])
	t += "\t\"carrier_scale\": %.1f,\n" % float(v["carrier_scale"])
	t += "\t\"shadow_tint\": Color(\"%s\"),\n" % _bshadow_tint.to_html(true)
	t += "}\n"
	t += "const BUILDING_SHADOW_HEIGHTS := {\n"
	for path in _bshadow_heights.keys():
		var heights: Dictionary = _bshadow_heights[path]
		t += "\t\"%s\": {" % path.get_file().replace(".tscn", "")
		var first: bool = true
		for layer_name in heights.keys():
			if not first:
				t += ", "
			t += "\"%s\": %.2f" % [layer_name, heights[layer_name]]
			first = false
		t += "},\n"
	t += "}\n"
	t += "# Paste into BuildingShadow.DEFAULTS + per-building heights table.\n"
	return t


func _snippet_building_boom() -> String:
	var t := "# Shader Lab — per-building death explosion config (ExplosionFx.play_config)\n"
	t += "const BUILDING_BOOM_CFG := {\n"
	for path in _bboom_cfg.keys():
		var cfg: Dictionary = _bboom_cfg[path]
		t += "\t\"%s\": {\n" % path.get_file().replace(".tscn", "")
		t += "\t\t\"type\": \"%s\",\n" % cfg["type"]
		t += "\t\t\"size\": %.2f,\n" % cfg["size"]
		t += "\t\t\"area\": %.1f,\n" % cfg["area"]
		t += "\t\t\"duration\": %.3f,\n" % cfg["duration"]
		t += "\t\t\"density\": %.1f,\n" % cfg["density"]
		t += "\t\t\"stagger\": %.3f,\n" % cfg["stagger"]
		t += "\t\t\"secondaries\": %.2f,\n" % cfg["secondaries"]
		t += "\t\t\"glow\": %.2f,\n" % cfg["glow"]
		t += "\t\t\"shockwave\": %.2f,\n" % cfg["shockwave"]
		t += "\t\t\"sparks\": %.2f,\n" % cfg["sparks"]
		t += "\t\t\"debris\": %.2f,\n" % cfg["debris"]
		t += "\t},\n"
	t += "}\n"
	t += "# Paste per-building into BuildingDestructible or building director spawn.\n"
	return t


func _snippet_death() -> String:
	var v: Dictionary = _death_vals.get(_death_style, {})
	var t := "# Shader Lab — death effect '%s' (scripts/effects/death_effects.gd)\n" % _death_style
	t += "# const DeathEffects = preload(\"res://scripts/effects/death_effects.gd\")\n"
	t += "var fx := DeathEffects.new()\n"
	t += "vfx_parent.add_child(fx)   # a node that OUTLIVES the enemy (combat scene root)\n"
	t += "fx.play(enemy, \"%s\", {\n" % _death_style
	if _death_style == "spinout":
		t += "\t\"resolution\": \"%s\",   # random | instakill | flashout | wreck | descent\n" % _spinout_resolution
	for def in DeathEffectsScript.STYLE_KNOBS.get(_death_style, []):
		var key := String(def["key"])
		var step := float(def["step"])
		if def.get("range", false):
			var arr: Array = v.get(key, def["def"])
			t += "\t\"%s\": [%s, %s],   # randomized per death\n" % [key, _fmt(float(arr[0]), step), _fmt(float(arr[1]), step)]
		else:
			t += "\t\"%s\": %s,\n" % [key, _fmt(float(v.get(key, def["def"])), step)]
	t += "}, Vector2.DOWN * %.1f,\n" % _death_primary_speed()
	t += "\t{\"vfx_parent\": vfx_parent, \"wreck_parent\": wreck_layer, \"bounds\": play_rect})\n"
	return t


func _snippet_nebula() -> String:
	# Alts: dump the current live shader params (they're set straight on the material).
	if _nebula_variant != 0:
		var path := (NEBULA_ALT1 if _nebula_variant == 1 else NEBULA_ALT2)
		var knobs: Array = (NEBULA_ALT1_KNOBS if _nebula_variant == 1 else NEBULA_ALT2_KNOBS)
		var ta := "# Shader Lab — nebula ALT (%s)\n" % NEBULA_VARIANT_NAMES[_nebula_variant]
		ta += "var mat := ShaderMaterial.new()\n"
		ta += "mat.shader = preload(\"%s\")\n" % path
		for k in knobs:
			var pn := String(k["param"])
			ta += "mat.set_shader_parameter(\"%s\", %s)\n" % [pn, str(_nebula_mat.get_shader_parameter(pn))]
		if _nebula_variant == 2:
			ta += "# Alt B needs a SEAMLESS NoiseTexture2D in `noise_texture`.\n"
		return ta
	var v: Dictionary = _values["Nebula"]
	var t := "# Shader Lab — nebula (graphics/nebula2.gdshader; in game: layer_stellar._spawn_nebula)\n"
	t += "mat.set_shader_parameter(\"scale\", %.1f)\n" % float(v["scale"])
	t += "mat.set_shader_parameter(\"octaves\", %d)\n" % int(v["octaves"])
	t += "mat.set_shader_parameter(\"density\", %.2f)\n" % float(v["density"])
	t += "mat.set_shader_parameter(\"edge_sharpness\", %.2f)\n" % float(v["edge"])
	t += "mat.set_shader_parameter(\"warp_strength\", %.2f)\n" % float(v["warp_strength"])
	t += "mat.set_shader_parameter(\"warp_scale\", %.2f)\n" % float(v["warp_scale"])
	t += "mat.set_shader_parameter(\"wisp_strength\", %.2f)\n" % float(v["wisp"])
	t += "mat.set_shader_parameter(\"swirl_speed\", %.2f)   # NEW — TIME-driven filament swirl\n" % float(v["swirl"])
	t += "mat.set_shader_parameter(\"drift_speed\", %.3f)\n" % float(v["drift"])
	t += "mat.set_shader_parameter(\"opacity\", %.2f)\n" % float(v["opacity"])
	t += "mat.set_shader_parameter(\"max_alpha\", %.2f)   # in game: ~0.1-0.2 per band\n" % float(v["max_alpha"])
	t += "mat.set_shader_parameter(\"pixels\", %.0f)\n" % float(v["pixels"])
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
