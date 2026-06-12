extends CanvasLayer

# CombatPostFx (Roman renderer-polish D, 2026-06-11). A single screen-reading band
# rect over the playfield (X 132-348) carrying combat_postfx.gdshader:
#   * D3 chromatic aberration — polled from the player while an aggressive Shift-mode
#     is engaged (hyper overcharge / phase dash).
# (D1 heat-haze shimmer + D2 radial ripple both RETIRED 2026-06-11 — Roman: the
# player-tracking distortion "wasn't working". Only the mode-driven aberration stays.)
# Lives at layer 2: above gameplay + glass but BELOW the HUD (5) and outline (10).

const BAND_X_MIN := 132.0
const BAND_X_MAX := 348.0
const VP := Vector2(480.0, 270.0)

# Aberration eases toward the player's requested amount at this rate (no snapping).
const ABERR_LERP := 8.0

var _player: Node2D = null
var _rect: ColorRect = null
var _mat: ShaderMaterial = null

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
	# D3: ease aberration toward the player's requested amount (mode-driven). The D1
	# heat-haze shimmer was retired 2026-06-11 (Roman: the player-tracking distortion
	# "wasn't working") — aberration is the only sweetener this pass drives now.
	var want: float = 0.0
	if _player != null and is_instance_valid(_player) and _player.has_method("postfx_aberration"):
		want = float(_player.postfx_aberration())
	_aberration = lerpf(_aberration, want, clampf(delta * ABERR_LERP, 0.0, 1.0))
	_mat.set_shader_parameter("aberration", _aberration)
