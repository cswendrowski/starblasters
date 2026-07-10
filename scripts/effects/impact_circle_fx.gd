extends Node
class_name ImpactCircleFx

# Directional GPU-particle bullet impact (impact_circle.tscn): a flash + spark spray + smoke puff at the
# hit point, ROTATED to fire along the projectile's travel direction (a bullet moving up sprays up) and
# TINTED to the shot colour — the faction muzzle colour for enemy fire (stamped in BulletCatalog.
# faction_variant), the per-projectile-tunable impact_color for the player (Weapon Lab → Projectiles).
# Replaces the flat smoke-strip impact for bullets; ImpactFx stays for the warhead EXPLOSIVE boom, which
# base_bullet layers UNDER this circle. Called Cls.spawn(...) like the other effect helpers (Roman
# 2026-07-09).
#
# HDR: the Sparks emitter's texture is already an HDR gradient (~1.57) on an ADDITIVE material, so it
# blooms via the combat WorldEnvironment (glow_hdr_threshold 1.0). The Flash is a MIX-blend strip, so its
# tint is pushed into HDR here so it blooms too. Both tints are peak-normalised so ANY input colour glows
# in its own hue (a dark colour would otherwise fall under the bloom threshold).

const IMPACT_CIRCLE := preload("res://scenes/effects/impact_circle.tscn")

# Foreground flash — above the gameplay actors (bullets/enemies render at z 0), matching the old ImpactFx.
const IMPACT_Z := 5
# The Sparks gradient already carries HDR headroom (~1.57), so its tint only needs its hue normalised to
# peak 1.0 (× the gradient lands at ~1.57 in the dominant channel). The Flash is plain MIX, so its tint is
# boosted past the 1.0 bloom threshold on its own.
const SPARK_TINT_PEAK := 1.0
const FLASH_TINT_PEAK := 1.8


# Spawn the impact at `world_pos`, oriented along `travel_dir` (the projectile's heading) and tinted to
# `color`. `parent` should be the projectile's own fx container so the effect outlives the bullet's
# queue_free and shares its coordinate space (combat window-root / hangar SubViewport world).
static func spawn(parent: Node, world_pos: Vector2, travel_dir: Vector2, color: Color) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx := IMPACT_CIRCLE.instantiate() as Node2D
	if fx == null:
		return
	fx.global_position = world_pos
	fx.z_index = IMPACT_Z
	# The emitters fire along their local +X; rotate the root so +X points along travel (an up-moving
	# bullet sprays up). A zero/degenerate direction leaves the authored orientation.
	if travel_dir.length_squared() > 0.0001:
		fx.rotation = travel_dir.angle()
	# Tint the flash + sparks to the shot colour, HDR so both bloom. The smoke keeps its neutral texture.
	_tint(fx.get_node_or_null("Flash"), color, FLASH_TINT_PEAK)
	_tint(fx.get_node_or_null("Sparks"), color, SPARK_TINT_PEAK)
	# Deferred add (the caller is mid area_entered; its parent may be busy) + fire once in the tree.
	fx.tree_entered.connect(_ignite.bind(fx), CONNECT_ONE_SHOT)
	parent.add_child.call_deferred(fx)


# Fire every one-shot emitter and free the effect once the longest particle lifetime has elapsed.
static func _ignite(fx: Node2D) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	var longest: float = 0.0
	for nm in ["Flash", "Sparks", "Smoke"]:
		var p := fx.get_node_or_null(nm)
		if p is GPUParticles2D:
			var gp := p as GPUParticles2D
			gp.restart()
			gp.emitting = true
			longest = maxf(longest, gp.lifetime)
	var tree := fx.get_tree()
	if tree != null:
		tree.create_timer(longest + 0.3).timeout.connect(fx.queue_free)
	else:
		fx.queue_free()


# Self-modulate `node` to `color`, scaled so its brightest channel hits `peak`. peak > 1 lands the tint
# in the HDR range (Flash → blooms); peak == 1 keeps full hue brightness (Sparks → the HDR gradient
# supplies the glow). Preserves hue regardless of the input colour's brightness.
static func _tint(node: Node, color: Color, peak: float) -> void:
	if node == null or not (node is CanvasItem):
		return
	var m: float = maxf(maxf(color.r, color.g), color.b)
	var scale: float = (peak / m) if m > 0.0001 else 1.0
	(node as CanvasItem).self_modulate = Color(color.r * scale, color.g * scale, color.b * scale, 1.0)
