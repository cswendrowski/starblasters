extends Node2D

# Mine center-blink (Roman 2026-06-09). A 2px flashing red dot + a diffuse red glow at the mine's
# centre. The flash FREQUENCY rises as the mine nears the player (a "getting hot" tell), and each
# instance carries a random PHASE OFFSET so a field of dormant mines doesn't blink in unison.
#
# Base-agnostic: any mine adds one in its _ready via `add_child(MineBlinker.new())` — works for
# enemy_core mines (basic/armored/shielded/smart) and enemy_base ones (cluster/mega/tether) alike.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")

const DOT_COLOR := Color(1.0, 0.12, 0.12)
# Flash Hz at the far/near distance bounds; lerped by player distance between them.
const FAR_DIST := 220.0
const NEAR_DIST := 34.0
const FAR_HZ := 1.3
const NEAR_HZ := 8.5
const MIN_ALPHA := 0.15

# Shared 2×2 white pixel (tinted red via modulate); one texture across the whole field.
static var _dot_tex: Texture2D = null

var _dot: Sprite2D = null
var _glow: CanvasItem = null
var _phase: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	z_index = 3   # above the mine sprite (0) + any shield ring (1)
	_phase = randf() * TAU   # per-instance offset → no unison blinking across a field
	_t = randf() * 10.0      # also desync the absolute clock
	_dot = Sprite2D.new()
	_dot.texture = _dot_texture()
	_dot.modulate = DOT_COLOR
	add_child(_dot)
	# Diffuse red glow behind the dot (forced colour so it reads off the 2px source).
	_glow = GlowShaderFx.apply(_dot, DOT_COLOR)


func _process(delta: float) -> void:
	if _dot == null or not is_instance_valid(_dot):
		return
	_t += delta
	var hz: float = FAR_HZ
	var p := _find_player()
	if p != null:
		var d: float = global_position.distance_to(p.global_position)
		var u: float = clampf(inverse_lerp(NEAR_DIST, FAR_DIST, d), 0.0, 1.0)  # 0 near → 1 far
		hz = lerpf(NEAR_HZ, FAR_HZ, u)
	# Pulse alpha [MIN_ALPHA, 1.0] at hz, offset by the per-instance phase.
	var s: float = 0.5 + 0.5 * sin(_t * hz * TAU + _phase)
	var a: float = lerpf(MIN_ALPHA, 1.0, s)
	_dot.modulate = Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, a)
	if _glow != null and is_instance_valid(_glow):
		_glow.modulate = Color(1.0, 1.0, 1.0, a)


func _find_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("player"):
		if is_instance_valid(n):
			return n as Node2D
	return null


static func _dot_texture() -> Texture2D:
	if _dot_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex
