class_name ProjectileMods
extends RefCounted

# Centralized enemy-projectile scaling — folds the identical weapon-scalar + Condition-speed math
# that used to be copy-pasted across shoot_pattern._spawn_bullet, enemy_turret, and (speed only)
# mount_component._fire_launcher. Sites call these two statics instead of inlining the blocks, so
# faction/sector projectile balance lives in ONE place.
#
# Sector Conditions Fast/Slow Bullets ride apply_condition_speed (§4a of
# docs/sector_conditions_redesign_2026-07-06.md). Both statics are strict no-ops when nothing opts
# in (owner mult == 1.0 / no active Conditions), so migrated sites stay bit-identical.

const Clarity = preload("res://scripts/systems/clarity.gd")

# Ceiling on an enemy bullet's final damage after weapon multipliers (faction/sector compound via
# *=). SSOT for the cap — shoot_pattern.gd + enemy_turret.gd reference this rather than each
# redefining it. Heaviest base today (heavy_slug=2) × any single faction/sector mult stays under 4.
const ENEMY_BULLET_DAMAGE_CAP := 4


# Faction/sector WEAPON scalars (bullet_speed_mult / bullet_damage_mult on the firing enemy). Bit-
# identical to the retired inline blocks: speed *= mult clamped to the clarity ceiling; damage *=
# mult clamped to [1, ENEMY_BULLET_DAMAGE_CAP]. No-op when the owner lacks the fields or mult == 1.0.
static func apply_weapon_scalars(b, owner) -> void:
	if b == null or owner == null:
		return
	if "speed" in b and "bullet_speed_mult" in owner and float(owner.bullet_speed_mult) != 1.0:
		b.speed = minf(b.speed * float(owner.bullet_speed_mult), Clarity.ABS_MAX_SPEED)
	if "damage" in b and "bullet_damage_mult" in owner and float(owner.bullet_damage_mult) != 1.0:
		b.damage = clampi(int(round(float(b.damage) * float(owner.bullet_damage_mult))), 1, ENEMY_BULLET_DAMAGE_CAP)


# Sector Conditions Fast/Slow Bullets (§4a): flat ±RUNG_STEP (one rung = 60 px/s) per active
# rung_delta, clamped to [RUNG_STEP, ABS_MAX_SPEED] (no creep bullets). Reads Run null-safely so
# bench/dev spawns with no autoload are a clean no-op; also no-op when delta == 0 or `b` has no speed.
static func apply_condition_speed(b) -> void:
	if b == null or not ("speed" in b):
		return
	var ml := Engine.get_main_loop()
	var run = ml.root.get_node_or_null("/root/Run") if ml is SceneTree else null
	if run == null:
		return
	var delta: int = int(run.cond_sum("bullet.rung_delta"))
	if delta == 0:
		return
	b.speed = clampf(b.speed + float(delta) * Clarity.RUNG_STEP, Clarity.RUNG_STEP, Clarity.ABS_MAX_SPEED)
