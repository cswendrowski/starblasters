extends "res://scripts/parts/primary_weapon.gd"

# Pulse Laser — a rapid 1px HITSCAN beam from the nose muzzle (Roman 2026-06-11).
# 2 damage per shot, fires fast. Stays pinpoint for the first `pulse_accuracy_window`
# shots of a sustained burst, then gains +1° dispersion per shot up to 20°; the beam
# tints pure white → blue (#000fd8) as it spreads. Dispersion recovers at 2°/sec when
# not firing. Mk adds +2 shots to the perfect-accuracy window (Mk.1=10 … Mk.9=26).
#
# Unlimited ammo (it's a laser) → BLASTER category: ammo_at_mark() == -1 routes it to
# the infinite blaster slot. The hitscan + dispersion state + beam visual live in
# player.gd under the PULSE_LASER weapon_style. Stats: resources/weapons/pulse_laser.tres.

const WSp = preload("res://scripts/weapons/WeaponStyle.gd")

@export var base_accuracy_window: int = 10
@export var accuracy_window_per_mark: int = 2


func _init() -> void:
	super._init()
	display_name = "Pulse Laser"
	description = "Rapid 1px hitscan beam from the nose. Pinpoint at first, then spreads (white→blue) the longer you hold; eases back when you let off. Mk widens the accurate window. Unlimited ammo."
	# Stats live in resources/weapons/pulse_laser.tres (single source of truth).


# BLASTER category: unlimited ammo (lasers don't meter). -1 routes to cannon_pool[0].
func ammo_at_mark(_mk: int) -> int:
	return -1


func _weapon_style() -> int:
	return WSp.WeaponStyle.PULSE_LASER


# No dedicated pulse SFX yet (the old pulse_* clips were retired) — NONE routes to the
# player's $ShootSound placeholder. TODO: author a pulse-laser fire clip.
func _fire_sfx_kind() -> int:
	return WSp.FireSfxKind.NONE


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("pulse_accuracy_window")
	return keys


# Stamp the per-Mk accuracy window onto the player (base 10, +2 per Mk).
func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	if "pulse_accuracy_window" in ship:
		ship.pulse_accuracy_window = base_accuracy_window + accuracy_window_per_mark * (int(mark) - 1)
