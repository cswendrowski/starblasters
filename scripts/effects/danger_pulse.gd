extends CanvasLayer

# DangerPulse (Roman renderer-polish D4, 2026-06-11). A subtle pulsing red gradient
# bleeding in from the LEFT edge of the screen while the player is at hull 0 — i.e.
# the next hit fires the super-bomb and then kills. Pure overlay (no screen read);
# driven by the player's hull_changed signal. Sits above the HUD (layer 6) so the
# warning always reads.

const VP := Vector2(480.0, 270.0)
# How far in from the left the gradient reaches, and its peak/idle alpha.
const REACH_PX := 150.0
const PULSE_HZ := 2.2
const ALPHA_MIN := 0.10
const ALPHA_MAX := 0.34
const DANGER_COLOR := Color(1.0, 0.12, 0.12)

var _rect: TextureRect = null
var _active: bool = false
var _t: float = 0.0
var _eased: float = 0.0   # 0..1 envelope so it fades in/out, not snaps


func _ready() -> void:
	layer = 6
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(DANGER_COLOR.r, DANGER_COLOR.g, DANGER_COLOR.b, 1.0),
		Color(DANGER_COLOR.r, DANGER_COLOR.g, DANGER_COLOR.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 1
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_rect = TextureRect.new()
	_rect.texture = gt
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.position = Vector2(0.0, 0.0)
	_rect.size = Vector2(REACH_PX, VP.y)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # glows over the dark gutter
	_rect.material = mat
	_rect.modulate.a = 0.0
	add_child(_rect)
	set_process(true)


# Hook to the player's hull_changed(max_hull, hull): danger ON at hull 0.
func on_hull_changed(_max_hull: int, hull: int) -> void:
	_active = hull <= 0


func _process(delta: float) -> void:
	var target: float = 1.0 if _active else 0.0
	_eased = move_toward(_eased, target, delta * 4.0)
	if _eased <= 0.001:
		_rect.modulate.a = 0.0
		return
	_t += delta
	var pulse: float = 0.5 + 0.5 * sin(_t * PULSE_HZ * TAU)
	var a: float = lerpf(ALPHA_MIN, ALPHA_MAX, pulse) * _eased
	_rect.modulate.a = a
