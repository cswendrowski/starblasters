extends Node2D

# Mine center-blink (Roman 2026-06-09). A 2px flashing red dot at the mine's centre. The flash
# breathes at a constant rate; each instance carries a random PHASE OFFSET so a field of dormant
# mines doesn't blink in unison.
#
# GLOW (Roman 2026-06-22): the old diffuse glow_fx halo was dropped — the dot is HDR-modulated by
# the tuned "bullets" multiplier so the WorldEnvironment bloom lights it (no per-sprite gradient).
#
# Base-agnostic: any mine adds one in its _ready via `add_child(MineBlinker.new())` — works for
# enemy_core mines (basic/armored/shielded/smart) and enemy_base ones (cluster/mega/tether) alike.

const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")

const DOT_COLOR := Color(1.0, 0.12, 0.12)
# Steady in-out breathing pulse (Roman 2026-06-11: no longer ramps up as the mine nears
# the player — it just breathes at a constant rate). Per-instance phase keeps a field
# from blinking in unison.
const PULSE_HZ := 1.6
const MIN_ALPHA := 0.15

# Shared 2×2 white pixel (tinted red via modulate); one texture across the whole field.
static var _dot_tex: Texture2D = null

var _dot: Sprite2D = null
var _dot_rgb: Color = DOT_COLOR   # HDR-bright red (DOT_COLOR × the "bullets" multiplier)
var _phase: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	z_index = 3   # above the mine sprite (0) + any shield ring (1)
	_phase = randf() * TAU   # per-instance offset → no unison blinking across a field
	_t = randf() * 10.0      # also desync the absolute clock
	# HDR-bright the red by the "bullets" multiplier so the WorldEnvironment blooms the dot.
	var m: float = VfxGlow.prod_mult("bullets")
	_dot_rgb = Color(DOT_COLOR.r * m, DOT_COLOR.g * m, DOT_COLOR.b * m, 1.0)
	_dot = Sprite2D.new()
	_dot.texture = _dot_texture()
	_dot.modulate = _dot_rgb
	add_child(_dot)


func _process(delta: float) -> void:
	if _dot == null or not is_instance_valid(_dot):
		return
	_t += delta
	# Pulse alpha [MIN_ALPHA, 1.0] at the constant breathing rate, offset by the
	# per-instance phase.
	var s: float = 0.5 + 0.5 * sin(_t * PULSE_HZ * TAU + _phase)
	var a: float = lerpf(MIN_ALPHA, 1.0, s)
	_dot.modulate = Color(_dot_rgb.r, _dot_rgb.g, _dot_rgb.b, a)


# Kill the blink instantly on mine death — hide the dot + stop the per-frame pulse so it doesn't
# linger over the explosion. (enemy_base's _fade_death_overlays calls this for any MineBlinker child.)
func stop() -> void:
	set_process(false)
	if _dot != null and is_instance_valid(_dot):
		_dot.visible = false


static func _dot_texture() -> Texture2D:
	if _dot_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex
