extends CanvasLayer

# CombatPostFx (Roman renderer-polish D, 2026-06-11). A single screen-reading band
# rect over the playfield (X 132-348) carrying combat_postfx.gdshader:
#   * D3 chromatic aberration — polled from the player while an aggressive Shift-mode
#     is engaged (hyper overcharge / phase dash).
#   * D2 radial ripple — `ping_ripple(world_pos, strength)` (called via the "post_fx"
#     group by big explosions / boss slams) kicks an expanding ring of UV warp.
# Lives at layer 2: above gameplay + glass (which it may warp subtly) but BELOW the
# HUD (5) and outline (10), so UI stays crisp.

const BAND_X_MIN := 132.0
const BAND_X_MAX := 348.0
const VP := Vector2(480.0, 270.0)

# Ripple ring expansion speed (UV/sec) + how fast a ping's strength decays.
const RIPPLE_SPEED := 1.4
const RIPPLE_DECAY := 2.0
# Aberration eases toward the player's requested amount at this rate (no snapping).
const ABERR_LERP := 8.0

var _player: Node2D = null
var _rect: ColorRect = null
var _mat: ShaderMaterial = null

var _ripple_radius: float = 0.0
var _ripple_strength: float = 0.0
var _aberration: float = 0.0


func _ready() -> void:
	layer = 2
	add_to_group("post_fx")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://graphics/combat_postfx.gdshader")
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)   # shader samples the screen; rect color unused
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cover only the playfield band, full height — never the gutters/HUD.
	_rect.position = Vector2(BAND_X_MIN, 0.0)
	_rect.size = Vector2(BAND_X_MAX - BAND_X_MIN, VP.y)
	add_child(_rect)
	set_process(true)


# main.gd hands us the player so we can poll its mode-aberration each frame.
func set_player(p: Node2D) -> void:
	_player = p


func _process(delta: float) -> void:
	# D3: ease aberration toward the player's requested amount.
	var want: float = 0.0
	if _player != null and is_instance_valid(_player) and _player.has_method("postfx_aberration"):
		want = float(_player.postfx_aberration())
	_aberration = lerpf(_aberration, want, clampf(delta * ABERR_LERP, 0.0, 1.0))
	_mat.set_shader_parameter("aberration", _aberration)

	# D1: track a subtle heat-haze disc just behind the player's exhaust.
	if _player != null and is_instance_valid(_player):
		var exhaust: Vector2 = _player.global_position + Vector2(0.0, 12.0)
		_mat.set_shader_parameter("haze_center", _world_to_screen_uv(exhaust))
		_mat.set_shader_parameter("haze_strength", 0.6)
	else:
		_mat.set_shader_parameter("haze_strength", 0.0)

	# D2: expand + decay the active ripple.
	if _ripple_strength > 0.001:
		_ripple_radius += RIPPLE_SPEED * delta
		_ripple_strength = move_toward(_ripple_strength, 0.0, RIPPLE_DECAY * delta)
		_mat.set_shader_parameter("ripple_radius", _ripple_radius)
		_mat.set_shader_parameter("ripple_strength", _ripple_strength)


# Kick a ripple centered on a world position (called via call_group("post_fx", ...)).
# strength ~0.6-1.2 reads well; big bosses can push higher.
func ping_ripple(world_pos: Vector2, strength: float = 1.0) -> void:
	var uv := _world_to_screen_uv(world_pos)
	_ripple_radius = 0.0
	_ripple_strength = clampf(strength, 0.0, 2.0)
	_mat.set_shader_parameter("ripple_center", uv)
	_mat.set_shader_parameter("ripple_radius", 0.0)
	_mat.set_shader_parameter("ripple_width", 0.06)
	_mat.set_shader_parameter("ripple_strength", _ripple_strength)


func _world_to_screen_uv(world_pos: Vector2) -> Vector2:
	# Combat renders at the internal 480x270; map world → screen UV via the canvas
	# transform so the ripple centers where the explosion actually was.
	var ct := get_viewport().get_canvas_transform()
	var screen_px: Vector2 = ct * world_pos
	return Vector2(screen_px.x / VP.x, screen_px.y / VP.y)
