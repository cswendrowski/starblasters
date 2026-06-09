extends "res://scripts/projectiles/base_missile.gd"

# Swarm micro-missile — the Swarm Launcher (HARDPOINT_WING secondary) fires a salvo
# of these, each handed a DISTINCT target. It homes its assigned target; when that
# target dies it RE-ACQUIRES the nearest live enemy; with no enemies left it flies
# on and detonates harmlessly at fuse expiry.
#
# VISUAL (Roman 2026-06-09): the body has no sprite — at the scene's `Center`
# marker we build a 1px bright FLICKERING yellow-orange pixel + a diffuse glow of
# the same color, and the smoke trail emits from that same marker.
# Design: docs/swarm_launcher_secondary_2026-06-08.md.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const GLOW_COLOR := Color(1.0, 0.6, 0.1)  # yellow-orange

# 1×1 white pixel, tinted per-frame via the core sprite's modulate. Built once and
# shared across every missile in a salvo (no per-instance Image allocation).
static var _pixel_tex: Texture2D = null

var _assigned_target: Node = null
var _flicker_t: float = 0.0
var _core: Sprite2D = null  # the 1px bright pixel at the Center marker


# The launcher assigns each missile a distinct target before it enters the tree.
func assign_target(t: Node) -> void:
	_assigned_target = t


# Override the base one-shot-lock: home the assigned target; re-acquire the nearest
# live enemy when it dies; null (fly straight) only when no enemies remain.
func _resolve_player_target(_fwd: Vector2) -> Node:
	if _assigned_target != null and is_instance_valid(_assigned_target):
		_locked = true
		return _assigned_target
	# Assigned target gone — re-acquire the nearest live enemy (boss-priority is
	# moot at this point; nearest keeps the swarm aggressive).
	var t: Node = _find_homing_target()
	if t != null and is_instance_valid(t):
		_assigned_target = t
		_locked = true
		return t
	return null


func _ready() -> void:
	super._ready()
	# Build the 1px bright pixel + diffuse yellow-orange glow AT the Center marker.
	var center: Node2D = get_node_or_null("Center") as Node2D
	if center != null:
		_core = Sprite2D.new()
		_core.name = "Core"
		_core.texture = _pixel_texture()
		_core.modulate = GLOW_COLOR
		center.add_child(_core)
		# Diffuse glow, color FORCED to yellow-orange so it reads regardless of the
		# 1px source. For a 1px host the halo math gives a ~15px soft blob behind
		# the hard pixel core (GlowShaderFx.HALO_PX).
		GlowShaderFx.apply(_core, GLOW_COLOR)
	# Emit the smoke trail from the Center marker too. base_missile built it
	# emitting from the root (no `exhaust_point` node); re-point it to Center.
	# Deferred so this runs AFTER the base's own deferred attach_to(self).
	if center != null and _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.call_deferred("attach_to", center)


func _process(delta: float) -> void:
	super._process(delta)
	# Bright yellow-orange flicker on the core pixel (orange <-> yellow-orange).
	if not _dying and _core != null and is_instance_valid(_core):
		_flicker_t += delta
		var f: float = 0.6 + 0.4 * absf(sin(_flicker_t * 28.0))
		_core.modulate = Color(1.0, 0.45 + 0.35 * f, 0.1, 1.0)


# Lazily build (and cache) the shared 1×1 white pixel texture.
static func _pixel_texture() -> Texture2D:
	if _pixel_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
