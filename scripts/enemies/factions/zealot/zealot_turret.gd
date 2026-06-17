extends Object

# Zealot gun turret mount (Roman art 2026-06-16). Ports the supremacy dome turret
# (scripts/enemies/factions/supremacy/enemy_push.gd) 1:1 — same EnemyTurret driver,
# same 3-frame recoil strip — swapping in the zealot tank-turret sprite. The strip
# layout matches the dome (48×16 → 3 frames: 0 idle, 1-2 barrel recoil), so the
# firing animation carries over unchanged.
#
# `mount_all(enemy)` builds one turret per `Turret*` Marker2D the enemy carries
# (Roman places them by hand in the scene). Zealot enemies with no Turret markers
# are a no-op, so it's safe to call from any zealot script. The turret rides its
# marker and aims in WORLD space relative to the parent's rotation (EnemyTurret
# subtracts parent.global_rotation), so an auto-rotated hull doesn't fight the aim.

const EnemyTurretC = preload("res://scripts/enemies/enemy_turret.gd")
const TurretTex = preload("res://graphics/enemies/zealot-tank-turret.png")
const CannonSlug = preload("res://data/bullets/heavy_slug.tres")


static func mount_all(enemy: Node) -> void:
	for mount in enemy.find_children("Turret*", "Marker2D", true, false):
		_build(mount)


static func _build(mount: Marker2D) -> void:
	var t = EnemyTurretC.new()
	t.rotation_speed = 3.6        # fast traverse — keeps pressure / punishes sitting still
	t.fire_interval_min = 1.0
	t.fire_interval_max = 1.6
	t.aim_tolerance_deg = 14.0
	t.bullet_variant = CannonSlug  # placeholder payload; retune per-enemy in the dev tools
	t.recoil_frames = 3            # zealot tank strip: 0 idle, 1-2 barrel recoil
	var s := Sprite2D.new()
	s.texture = TurretTex
	s.hframes = 3
	t.add_child(s)
	mount.add_child(t)             # ride the marker, wherever Roman placed it
