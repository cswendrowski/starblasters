extends "res://scripts/parts/primary_weapon.gd"

# Twin Blaster — infinite BLASTER REPLACEMENT (Roman 2026-06-11). Fires a single
# bolt that ALTERNATES between +2px and -2px on the cannon marker each shot, for a
# woven twin-stream look. Uses the medium blaster bolt (speed 180 — slower than the
# core blaster's 240, faster than the heavy shot's 120). Rapid, light bolts with a
# slight lateral weave: trades the core blaster's pinpoint column + projectile speed
# for fire rate and lane coverage. Infinite ammo (swaps the old blaster to the hold).

const BulletMedium = preload("res://scenes/projectiles/bullet_blaster_medium.tscn")


func _init() -> void:
	super._init()
	display_name = "Twin Blaster"
	description = "Woven twin-stream blaster — rapid, light bolts that alternate across the muzzle. Unlimited ammo."
	# Stats live in resources/weapons/twin_blaster.tres (single source of truth).
	if bullet_scene == null:
		bullet_scene = BulletMedium


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.BLASTER_SMALL


# Infinite (blaster-replacement) — never meters ammo.
func ammo_at_mark(_mk: int) -> int:
	return -1


# primary_lateral_alternate is reset on unapply via the snapshot.
func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("primary_lateral_alternate")
	return keys


func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	# Alternate the muzzle X by ±2px each shot (the woven twin stream).
	if "primary_lateral_alternate" in ship:
		ship.primary_lateral_alternate = 2.0
