@tool
extends Sprite2D
class_name EngineGlow

# Reusable, recolorable engine / thruster GLOW SPRITE (Roman 2026-07-11) — the sprite-based replacement
# for the procedural engine trails/flares. Drop `scenes/effects/engine_glow.tscn` onto an Engine/Thruster
# marker, tint it, and it self-animates through its texture strip with additive HDR bloom. The scene is
# EDITABLE in the editor (@tool previews the look live); the additive material + strip texture live in the
# .tscn as nodes/sub-resources so both can be swapped for dedicated engine art WITHOUT touching this code.
#
# Reuse from code (bosses / enemies / missiles):
#   var e := EngineGlow.spawn(parent, local_pos, plume_rotation, Color("#4dd8ff"))   # tinted, placed, playing
# or just instance the scene and set `tint` / `glow_scale` in the inspector.
#
# This is the intended standard going forward — engine SPRITES, not the yellow/blue Line2D exhaust trails
# (those were cut 2026-07-11) or the PointLight2D flame (enemy_engine_fx.gd). See `engine_flare.gd` for the
# legacy code-only version this generalizes (fixed near-white tint, no editable scene).

const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")
const SCENE_PATH := "res://scenes/effects/engine_glow.tscn"
const HFRAMES := 5      # frames in the strip; also set on the Sprite2D in the .tscn
const FRAME_PX := 16    # per-frame size of the 16x16 strip (the .tscn offset anchors the plume base)

# Engine hue. self_modulate = tint × the HDR "engines" multiplier, so the tint keeps its colour while the
# WorldEnvironment bloom lights the plume. White (default) reproduces the legacy near-white EngineFlare.
@export var tint: Color = Color(1, 1, 1, 1):
	set(v):
		tint = v
		_apply_tint()
# Uniform scale of the plume (legacy EngineFlare shipped 0.55 — a 16px flash over a small body).
@export var glow_scale: float = 0.55:
	set(v):
		glow_scale = v
		scale = Vector2(v, v)
@export var anim_fps: float = 14.0   # strip playback speed
# HDR bloom on/off. Off = a plain 1× additive sprite (no bloom); on = boosted past the combat env
# glow threshold so the plume blooms.
@export var hdr_bloom: bool = true:
	set(v):
		hdr_bloom = v
		_apply_tint()

var _t := 0.0


func _ready() -> void:
	hframes = HFRAMES
	scale = Vector2(glow_scale, glow_scale)
	_apply_tint()
	if Engine.is_editor_hint():
		frame = 2   # static mid-plume preview in the editor; no per-frame churn at design time


func _apply_tint() -> void:
	var e: float = 1.0
	if hdr_bloom:
		e = VfxGlow.prod_mult("engines")
	self_modulate = Color(tint.r * e, tint.g * e, tint.b * e, tint.a)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	frame = int(_t * anim_fps) % HFRAMES


# Instance the scene, tint + place it under `parent`, and return it. `plume_rotation` points the plume
# OUT the rear (opposite thrust), matching the boss THRUSTER_DEFS convention.
static func spawn(parent: Node, local_pos: Vector2 = Vector2.ZERO, plume_rotation: float = 0.0, tint_color: Color = Color(1, 1, 1, 1), glow_scale_mult: float = 0.55) -> EngineGlow:
	var e: EngineGlow = load(SCENE_PATH).instantiate()
	e.tint = tint_color
	e.glow_scale = glow_scale_mult
	e.position = local_pos
	e.rotation = plume_rotation
	parent.add_child(e)
	return e
