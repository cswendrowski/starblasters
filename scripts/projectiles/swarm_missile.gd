extends "res://scripts/projectiles/base_missile.gd"

# Swarm micro-missile — the Swarm Launcher (HARDPOINT_WING secondary) fires a salvo
# of these, each handed a DISTINCT target. It homes its assigned target; when that
# target dies it RE-ACQUIRES the nearest live enemy; with no enemies left it flies
# on and detonates harmlessly at fuse expiry. Bright yellow-orange flickering pixel
# + diffuse glow + the shared missile trail.
# Design: docs/swarm_launcher_secondary_2026-06-08.md.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const GLOW_COLOR := Color(1.0, 0.6, 0.1)  # yellow-orange

var _assigned_target: Node = null
var _flicker_t: float = 0.0


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
	# Diffuse yellow-orange glow behind the pixel (color forced so it reads even if
	# the firecore sprite's derived color drifts).
	if has_node("Sprite2D"):
		GlowShaderFx.apply($Sprite2D, GLOW_COLOR)


func _process(delta: float) -> void:
	super._process(delta)
	# Bright yellow-orange flicker on the core pixel (orange <-> yellow-orange).
	if not _dying and has_node("Sprite2D"):
		_flicker_t += delta
		var f: float = 0.6 + 0.4 * absf(sin(_flicker_t * 28.0))
		$Sprite2D.modulate = Color(1.0, 0.45 + 0.35 * f, 0.1, 1.0)
