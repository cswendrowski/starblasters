extends "res://scripts/enemy_core.gd"

# Supremacy lane pusher "Push" (M6c, Roman 2026-06-07). REPLACES the Frigate.
#
# A tall hull that descends a lane (slow or mid) or crosses the screen slowly,
# carrying TWO player-tracking dome turrets that fire cannon slugs aimed at the
# player's CURRENT position (no lead). The turrets traverse fast enough to keep
# pressure and punish sitting still. Movement is a pattern (roster slot); only the
# twin turrets are bespoke here (mirrors the cruiser's inline turret).
#
# Two-frame hull+glow sprite. No Muzzle markers on the hull on purpose: each
# EnemyTurret then fires from its OWN position (has_muzzles() == false) instead of
# sharing a single parent muzzle. Turret positions are first-pass — Roman hand-tunes.

const EnemyTurretC = preload("res://scripts/enemies/enemy_turret.gd")
const DomeTex = preload("res://graphics/enemies/turret_s_dome.png")
const CannonSlug = preload("res://data/bullets/heavy_slug.tres")


func _ready() -> void:
	max_health = 28
	bounty_value = 25
	super._ready()
	_build_turret(Vector2(0, -18))   # top mount
	_build_turret(Vector2(0, 6))     # mid mount


func _build_turret(local_pos: Vector2) -> void:
	var t = EnemyTurretC.new()
	t.position = local_pos
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
	add_child(t)
