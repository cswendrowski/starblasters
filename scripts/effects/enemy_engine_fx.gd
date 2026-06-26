extends RefCounted
class_name EnemyEngineFx

# Reusable engine flame for enemy ships. Attaches a small additive COLORED POINT LIGHT at the rear of
# an Area2D enemy (was a GradientTexture2D teardrop sprite; swapped to a PointLight2D 2026-06-22 so the
# exhaust casts real light + blooms). Pulses + flickers in brightness so it reads as a live engine
# without per-frame logic on the enemy.
#
# Usage from any enemy:
#   const EngineFx = preload("res://scripts/effects/enemy_engine_fx.gd")
#   EngineFx.attach(self)
#
# Auto-rotation on EnemyBase puts the holder's "down" along the velocity direction, so the light at
# +Y in local space ends up trailing behind regardless of which way the enemy is traveling.

const FLAME_OFFSET := Vector2(0, 11)   # below the body in local space
const FLAME_RADIUS := 13.0             # point-light radius (px); the old teardrop read ~18×40
const FLAME_TINT := Color(1.0, 0.65, 0.25, 0.95)
const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")
const LightFx = preload("res://scripts/effects/light_fx.gd")


static func attach(enemy: Node2D, tint: Color = FLAME_TINT, scale_mult: float = 1.0) -> Node2D:
	# Don't double-attach if the helper was already called.
	if enemy.has_node("EngineFlame"):
		return enemy.get_node("EngineFlame") as Node2D
	var holder := Node2D.new()
	holder.name = "EngineFlame"
	# Draw behind the body so it reads as "exhaust from behind" rather than overlapping the silhouette.
	holder.z_index = -1
	holder.z_as_relative = true
	enemy.add_child(holder)
	# Colored additive point light at the rear (replaces the gradient flame sprite). Energy carries the
	# brightness — folds in the old HDR bloom gain via VfxGlow; the additive blend + WorldEnvironment
	# bloom give the glow. The caller's tint drives the hue (Dart yellow, default warm-orange, …).
	var base_energy: float = maxf(0.4, VfxGlow.prod_mult("engines") * 0.7)
	var radius: float = FLAME_RADIUS * scale_mult
	var light := LightFx.attach(holder, Color(tint.r, tint.g, tint.b, 1.0), base_energy, radius, FLAME_OFFSET)
	var base_tscale: float = light.texture_scale
	# Brightness + size flicker so it reads as a live engine (no per-frame logic on the enemy).
	var tw: Tween = holder.create_tween().set_loops()
	tw.tween_property(light, "energy", base_energy * 1.25, 0.08).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(light, "texture_scale", base_tscale * 1.12, 0.08)
	tw.tween_property(light, "energy", base_energy, 0.10).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(light, "texture_scale", base_tscale, 0.10)
	return holder
