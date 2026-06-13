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

const GLOW_COLOR := Color(1.0, 1.0, 0.0)  # #FFFF00 pure yellow

# 1×1 white pixel, tinted per-frame via the core sprite's modulate. Built once and
# shared across every missile in a salvo (no per-instance Image allocation).
static var _pixel_tex: Texture2D = null

var _assigned_target: Node = null
var _flicker_t: float = 0.0
var _core: Sprite2D = null  # the 1px bright pixel at the Center marker


# The launcher assigns each missile a distinct target before it enters the tree.
func assign_target(t: Node) -> void:
	_assigned_target = t


# Swarm hits use a single small-circle explosion with NO debris (Roman 2026-06-11) —
# overrides base_missile's impact-flash + enemy-style debris death.
func explode() -> void:
	if _dying:
		return
	_dying = true
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.call("attach_to", null)
		_smoke_trail = null
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, 0.8, false, _fx_parent(), ExplosionFx.scene_for("small_circle"), true)
	queue_free()


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
	# Render UNDER the player (Roman 2026-06-11): the salvo + its launch flashes sit
	# below the ship so they read as launching from beneath it.
	z_index = -3
	z_as_relative = false
	# Build the 1px bright pixel + diffuse yellow-orange glow AT the Center marker.
	var center: Node2D = get_node_or_null("Center") as Node2D
	if center != null:
		_core = Sprite2D.new()
		_core.name = "Core"
		_core.texture = _pixel_texture()
		_core.modulate = GLOW_COLOR
		# HDR-bright (no halo quad) so the WorldEnvironment bloom (glow_hdr_threshold = 1.0) glows the
		# yellow core directly — replaces the removed glow halo (Roman 2026-06-12).
		_core.self_modulate = Color(1.8, 1.8, 1.8, 1.0)
		center.add_child(_core)
	# Emit the smoke trail from the Center marker too. base_missile built it
	# emitting from the root (no `exhaust_point` node); re-point it to Center.
	# Deferred so this runs AFTER the base's own deferred attach_to(self).
	if center != null and _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.call_deferred("attach_to", center)


func _process(delta: float) -> void:
	super._process(delta)
	# Brightness flicker on the core pixel, hue pinned to pure yellow (#FFFF00 at
	# peak, dimming to a darker yellow — no hue shift).
	if not _dying and _core != null and is_instance_valid(_core):
		_flicker_t += delta
		var f: float = 0.7 + 0.3 * absf(sin(_flicker_t * 28.0))
		_core.modulate = Color(f, f, 0.0, 1.0)


# Lazily build (and cache) the shared 1×1 white pixel texture.
static func _pixel_texture() -> Texture2D:
	if _pixel_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
