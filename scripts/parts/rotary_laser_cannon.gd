extends "res://scripts/parts/metered_primary.gd"

# Rotary Laser Cannon. Minigun-style energy weapon — blistering rate of fire
# (20 shots/sec), limited ammo (120 base + 30/Mk), recharges at 3 shots/sec
# when not firing. Pairs with the ROTARY_LASER weapon_style branch in player.gd.
# No outpost refill — natural recharge makes sold refills redundant.
#
# Mk.5+ projectile swap (Roman 2026-06-10): from Mk.5 the rotary fires the Auto Laser bolt sprite
# (same bullet.gd, same speed 480) — damage / rate-of-fire / ammo are unchanged, only the projectile
# art changes. Mk.1-4 keep the rotary bolt.

const BulletRotaryLaser = preload("res://scenes/projectiles/bullet_rotary_laser.tscn")
const BulletAutoLaser = preload("res://scenes/projectiles/bullet_auto_laser.tscn")


func _init() -> void:
	super._init()
	display_name = "Rotary Laser"
	description = "Rapid-fire energy cannon. Mk.1: 120 ammo, recharges 3/sec. Each Mk adds 30 ammo."
	# Stats live in resources/weapons/rotary_laser.tres (single source of truth).


func ammo_at_mark(mk: int) -> int:
	return 120 + 30 * (mk - 1)


func _damage_for_mark(at_mark: int) -> int:
	# Mk1=1, Mk2=1, Mk3=2, Mk4=2, Mk5=3, Mk6=3, Mk7=4, Mk8=4, Mk9=5
	return int((at_mark - 1) / 2) + 1


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": Callable(self, "_damage_for_mark"),
		"cooldown": [base_cooldown, base_cooldown],
	}


func _weapon_style() -> int:
	return WS.WeaponStyle.ROTARY_LASER


func _apply_visuals(ship) -> void:
	# Seed the per-mark ammo BEFORE super so metered_primary._apply_visuals
	# reads the correct current_ammo value (not the stale -1 default).
	current_ammo = ammo_at_mark(int(mark))
	super._apply_visuals(ship)
	# Overwrite ammo_max after super (super writes base_ammo = 120 flat).
	if "ammo_max" in ship:
		ship.ammo_max = ammo_at_mark(int(mark))
	# Mk.5+ swaps to the Auto Laser bolt sprite (cosmetic — same speed/damage/RoF). Set after super
	# so it overrides the .tres-pinned rotary bullet that primary_weapon._apply_visuals just wrote.
	if "bullet_scene" in ship:
		ship.bullet_scene = BulletAutoLaser if int(mark) >= 5 else BulletRotaryLaser
