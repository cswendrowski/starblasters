extends Node

# Hit-flash helper. Attach a shared hit_flash.gdshader material to a Sprite2D
# and tween its `flash_strength` from 1.0 → 0.0 over a short window. Used by:
#   - bullet.gd → flash enemy sprites white on every bullet impact
#   - player.gd → flash ship white on hull hit, shield-blue on shield hit
#   - mine_shielded.gd → flash mine + shield ring blue on shield hit
#
# Idempotent material attach: first call installs the ShaderMaterial; later
# calls reuse it. Concurrent flashes kill the previous tween so a rapid-fire
# barrage stays bright instead of stuttering back to baseline.

const HIT_FLASH_SHADER = preload("res://graphics/hit_flash.gdshader")
const FLASH_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const FLASH_SHIELD := Color(0.55, 0.95, 1.0, 1.0)  # matches sci_fi_shield cyan
const META_KEY := "hit_flash_state"


static func flash(target: CanvasItem, color: Color = FLASH_WHITE, duration: float = 0.12) -> void:
	if target == null or not is_instance_valid(target):
		return
	# Lazily install our ShaderMaterial. Skip if the sprite already has a
	# non-flash material (burn_fx applied on death, for instance) — flashing
	# a dying enemy isn't worth tearing down its death shader for.
	var mat: ShaderMaterial = null
	if target.material is ShaderMaterial and target.material.shader == HIT_FLASH_SHADER:
		mat = target.material
	elif target.material == null:
		mat = ShaderMaterial.new()
		mat.shader = HIT_FLASH_SHADER
		target.material = mat
	else:
		# Some other shader already running (burn, etc.). Skip.
		return
	mat.set_shader_parameter("flash_color", color)
	mat.set_shader_parameter("flash_strength", 1.0)
	# Kill any in-flight flash tween via meta so we can replace it.
	if target.has_meta(META_KEY):
		var prev = target.get_meta(META_KEY)
		if prev != null and prev is Tween and prev.is_valid():
			prev.kill()
	var tw := target.create_tween()
	tw.tween_method(
		func(v): mat.set_shader_parameter("flash_strength", v),
		1.0, 0.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	target.set_meta(META_KEY, tw)
