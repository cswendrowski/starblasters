extends Resource
class_name BulletVariant

# Data resource describing one bullet archetype. Assign to
# BaseBullet.variant before start() to override all stats and visuals.
# Zero/null defaults cost nothing at runtime (no variant = current behavior).

@export var speed: float = 220.0
@export var damage: int = 1
@export var lifetime: float = 4.0
@export var hitbox_size: Vector2 = Vector2(6.0, 6.0)

# Visuals — leave both null to keep the scene's default appearance.
@export var sprite_frames: SpriteFrames = null    # null → use static_texture
@export var static_texture: Texture2D = null       # shown when sprite_frames is null
@export var frame_count: int = 1                   # frames in static_texture strip (1 = static)
@export var fps: float = 8.0                       # playback speed for animated strips

# VESTIGIAL (2026-05-30): glow color is now auto-derived from the bullet
# sprite by GlowShaderFx — no per-weapon authoring. This field is no longer
# read by the glow path; kept so existing .tres files load without warnings.
@export var glow_color: Color = Color(1, 0.11, 1, 0.5)

# Impact
@export var impact_kind: int = 0   # 0=SMOKE, 1=EXPLOSIVE
@export var impact_color: Color = Color(1, 1, 1, 1)

# Audio — null = default blip
@export var sfx: AudioStream = null

# Enemy fire-sound class. "" → the default enemy_blaster pool. Set to
# "enemy_mg" on small-bullet / tracer payloads so they fire the machine-gun
# clips instead (EnemySfx routes off this; see scripts/effects/enemy_sfx.gd).
@export var enemy_sfx_kind: String = ""

# Behavior knobs — zero defaults mean no extra cost for dumb bullets
@export var homing_rate: float = 0.0         # degrees/sec turn toward player
@export var wobble_amplitude: float = 0.0    # px lateral to dir
@export var wobble_frequency: float = 0.0    # Hz

# Telegraph flash at spawn (Heavy Slug style)
@export var telegraph_flash: bool = false

# Pick a random static frame on spawn (Aimed Sniper tracer)
@export var random_frame: bool = false

# Runtime cache: SpriteFrames built from static_texture + frame_count.
# Not exported — rebuilt on first use and shared across all instances of
# this variant to avoid per-bullet allocation overhead.
var _built_frames: SpriteFrames = null
