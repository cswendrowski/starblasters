extends Area2D

# Aegis pylon — destructible shield-node hanging off the Aegis boss. Has
# its own HP, takes hits, emits a signal on destruction, frees itself.
# Not a real EnemyBase to avoid the engine flame / parallax shadow / etc
# pipeline — pylons are stationary props attached to the boss.
#
# 2026-05-24: Pylons no longer shoot. They visually link to the boss via
# a blue Line2D (managed by boss_aegis.gd) and uphold the shield. Killing
# one opens a 1.5s damage window on the core.
#
# 2026-06-01: Reskinned with real art via enemy_shield_pylon.tscn. The BODY
# ($Sprite2D) gets the same damage-overlay shader regular enemies use, so it
# visibly frays/darkens as HP drops. The ORB ($Orb) sits on top, stays bright
# (no material), and loops its 4 frames until the pylon dies.

signal pylon_killed(side: String)

# Damage-overlay shader resources — same trio enemy_base.gd installs. Replicated
# here because aegis_pylon is a plain Area2D, not an EnemyBase, so it can't reuse
# that base method.
const DamageOverlayShader = preload("res://graphics/damage_noise.gdshader")
const _DamageNoiseTex = preload("res://resources/noise_damage.tres")
const _DamageEdgeTex = preload("res://resources/edge_distance_flat.tres")

# Orb animation: 4 hframes, advance one frame every ORB_FRAME_TIME seconds, loop.
# GUESS (designer to confirm): 0.12s/frame reads as a steady idle shimmer.
const ORB_FRAME_TIME: float = 0.12

var hp: int = 80
var max_hp: int = 80
var side: String = ""

# True so the wave director doesn't gate clear on these — the boss core
# is the only thing that matters for sector completion.
var is_hazard: bool = true

var _damage_material: ShaderMaterial = null
var _orb_t: float = 0.0


func _ready() -> void:
	# Install the damage-overlay material on the BODY only. Mirrors
	# enemy_base.gd::_install_damage_material (which we can't call — not an
	# EnemyBase). The orb is left untouched so it stays bright.
	if has_node("Sprite2D"):
		var spr := $Sprite2D as Sprite2D
		if spr.material == null:
			var mat := ShaderMaterial.new()
			mat.shader = DamageOverlayShader
			mat.set_shader_parameter("sensitivity", 0.0)
			mat.set_shader_parameter("noise_texture", _DamageNoiseTex)
			mat.set_shader_parameter("edge_distance_map", _DamageEdgeTex)
			mat.set_shader_parameter("noise_seed", float(randi() % 999))
			spr.material = mat
			_damage_material = mat


func _process(delta: float) -> void:
	# Loop the orb's 4 frames. Drives off _process (not a SceneTreeTimer) so it
	# stops for free the moment the pylon queue_free()s its children on death.
	if hp <= 0 or not has_node("Orb"):
		return
	_orb_t += delta
	if _orb_t >= ORB_FRAME_TIME:
		_orb_t -= ORB_FRAME_TIME
		var orb := $Orb as Sprite2D
		orb.frame = (orb.frame + 1) % max(1, orb.hframes)


func take_hit(damage: int = 1) -> bool:
	if hp <= 0:
		return false
	hp -= damage
	# Push the damage level into the body shader (0 at full HP → up to 0.75 near
	# death), matching enemy_base's _update_damage_visual mapping.
	if _damage_material != null and max_hp > 0:
		var lvl: float = clamp(1.0 - float(hp) / float(max_hp), 0.0, 0.75)
		_damage_material.set_shader_parameter("sensitivity", lvl)
	if has_node("Sprite2D"):
		var spr := $Sprite2D as Sprite2D
		var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
		HitFlashFx.flash(spr, HitFlashFx.FLASH_WHITE)
	if hp <= 0:
		var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
		ExplosionFx.burst(global_position, 3, 14.0, 0.06)
		pylon_killed.emit(side)
		queue_free()
		return true
	return false
