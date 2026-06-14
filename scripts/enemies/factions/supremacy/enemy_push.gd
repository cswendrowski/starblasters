extends "res://scripts/enemies/enemy_core.gd"

# Supremacy lane pusher "Push" (M6c, Roman 2026-06-07). REPLACES the Frigate.
#
# A tall hull that descends a lane (slow or mid) or crosses the screen slowly,
# carrying player-tracking dome turrets that fire cannon slugs aimed at the
# player's CURRENT position (no lead). The turrets traverse fast enough to keep
# pressure and punish sitting still. Movement is a pattern (roster slot); only the
# turrets are bespoke here (mirrors the cruiser's inline turret).
#
# Turrets mount on the scene's `Turret*` Marker2D markers (Roman places/repositions
# them by hand) — one EnemyTurret parented to each marker, so they sit exactly where
# the marker is. No hull Muzzle markers on purpose: each turret then fires from its
# OWN position (has_muzzles() == false) rather than sharing a single parent muzzle.
#
# auto_rotate = true: the hull turns to face its travel direction (art is authored
# nose-up; auto-rotation points it down as it descends and rotates the Engine*/Turret*
# markers with it, so exhaust + turrets stay on their hull features without flipping the
# sprite). The turrets aim in WORLD space relative to the parent's rotation (EnemyTurret
# subtracts parent.global_rotation), so a rotated hull no longer fights their aim
# (Roman 2026-06-08).

const EnemyTurretC = preload("res://scripts/enemies/enemy_turret.gd")
const DomeTex = preload("res://graphics/enemies/turret_s_dome.png")
const CannonSlug = preload("res://data/bullets/heavy_slug.tres")


func _ready() -> void:
	max_health = 28
	bounty_value = 25
	auto_rotate = true
	super._ready()
	for mount in find_children("Turret*", "Marker2D", true, false):
		_build_turret(mount)


func _build_turret(mount: Marker2D) -> void:
	var t = EnemyTurretC.new()
	t.rotation_speed = 3.6        # fast traverse — keeps pressure / punishes sitting still
	t.fire_interval_min = 1.0
	t.fire_interval_max = 1.6
	t.aim_tolerance_deg = 14.0
	t.bullet_variant = CannonSlug  # slow heavy cannon slug, aimed (no lead)
	t.recoil_frames = 3            # dome strip: 0 idle, 1-2 barrel recoil
	var s := Sprite2D.new()
	s.texture = DomeTex
	s.hframes = 3
	t.add_child(s)
	mount.add_child(t)             # ride the marker, wherever Roman placed it
