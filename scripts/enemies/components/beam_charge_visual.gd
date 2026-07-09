extends EnemyComponent

# Drives a charge-layer Sprite2D off the host's BeamEmitter FSM so a "charging" animation tracks the
# beam's windup -> fire -> cooldown cycle. Frame 0 = fully charged / firing; the LAST hframe = uncharged
# (start of windup / end of cooldown). The layer is hidden whenever the beam is idle/off. Generic +
# reusable (any beam enemy with a charge frame-strip); the zealot Spear is the first user.
#
# Pairs with a BEAM mount (the beam attaches as a child in enemy_base._ready, before this component's
# deferred on_start), so the beam exists by the time we look for it; on_process re-resolves if not.

const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")

# Name of the charge-layer Sprite2D child (a horizontal frame strip; frame 0 = fully charged).
@export var layer: String = "ChargeMask"
# FADE mode (Roman 2026-07-06): instead of stepping a frame strip, drive the layer's ALPHA off the beam's
# charge fraction — fade IN across the charge (windup), hold ON through the fire (firing), fade OUT over the
# cooldown. The scorcher's GlowCharge layer uses this.
@export var fade: bool = false
# HDR glow: multiply the layer bright (the "bullet" HDR setting) so the WorldEnvironment bloom picks it up.
@export var hdr: bool = false
@export var hdr_category: String = "bullets"

var _mask: Sprite2D = null
var _beam = null
var _last_frame: int = 0


func on_start(enemy) -> void:
	_mask = enemy.get_node_or_null(layer) as Sprite2D
	if _mask != null:
		_last_frame = maxi(0, _mask.hframes - 1)
		_mask.visible = false
	_beam = _find_beam(enemy)


func on_process(enemy, _delta: float) -> void:
	if _mask == null:
		return
	if _beam == null or not is_instance_valid(_beam):
		_beam = _find_beam(enemy)
		if _beam == null:
			return
	var f: float = _beam.charge_fraction()
	if f < 0.0:
		if _mask.visible:
			_mask.visible = false
		return
	_mask.visible = true
	if fade:
		# Fade IN over windup (f 0->1), hold through firing (f=1), fade OUT over cooldown (f 1->0). HDR-bright
		# so the layer blooms; alpha rides the charge fraction.
		var base: Color = VfxGlow.prod_hdr(hdr_category) if hdr else Color.WHITE
		_mask.modulate = Color(base.r, base.g, base.b, base.a * f)
		return
	# f = 1 (fully charged / firing) -> frame 0; f = 0 (uncharged) -> last frame.
	_mask.frame = clampi(int(round((1.0 - f) * float(_last_frame))), 0, _last_frame)


# The host's BeamEmitter (attached as a descendant by MountBuilder, or by a bespoke boss host).
func _find_beam(enemy):
	for n in enemy.find_children("*", "", true, false):
		if n.get_script() == BeamEmitterC:
			return n
	return null
