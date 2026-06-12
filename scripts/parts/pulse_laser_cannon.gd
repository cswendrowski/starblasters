extends "res://scripts/parts/metered_primary.gd"

# Pulse Laser — a rapid 1px HITSCAN beam from the nose muzzle (Roman 2026-06-11).
# 2 damage per shot, fires fast. Stays pinpoint for the first `pulse_accuracy_window`
# shots of a sustained burst, then gains +1° dispersion per shot up to 20°; the beam
# tints pure white → blue (#000fd8) as it spreads. Dispersion recovers at 2°/sec when
# not firing. Mk adds +2 shots to the perfect-accuracy window (Mk.1=10 … Mk.9=26).
#
# Metered REGEN laser (Roman 2026-06-11 follow-up): 100 ammo, standard laser regen
# (3/sec, no outpost refill) — a PRIMARY-slot weapon, not a blaster. Ammo is flat
# across Marks (the Mk identity is the accuracy window). When dry it pauses + recharges
# rather than reverting (the regen-cannon path in player.fire_primary). The hitscan +
# dispersion state + beam visual live in player.gd under the PULSE_LASER weapon_style.
# Stats: resources/weapons/pulse_laser.tres.

const WSp = preload("res://scripts/weapons/WeaponStyle.gd")

@export var base_accuracy_window: int = 6   # Weapon Lab tune (Roman 2026-06-11; was 10)
@export var accuracy_window_per_mark: int = 2


func _init() -> void:
	super._init()
	display_name = "Pulse Laser"
	description = "Rapid 1px hitscan beam from the nose. Pinpoint at first, then spreads (white→blue) the longer you hold; eases back when you let off. Mk widens the accurate window. 100 ammo, recharges 3/sec."
	# Stats live in resources/weapons/pulse_laser.tres (single source of truth).


# Ammo is flat across Marks (metered_primary returns base_ammo) — the Mk upgrade is
# the accuracy window, not magazine size.


func _weapon_style() -> int:
	return WSp.WeaponStyle.PULSE_LASER


# Pulse Laser has its own fire path (_fire_pulse_laser) that returns BEFORE the shared
# per-shot SFX block, so it plays its clip explicitly there. PULSE is set here for
# semantic correctness / documentation; the shared block is never reached for pulse.
func _fire_sfx_kind() -> int:
	return WSp.FireSfxKind.PULSE


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("pulse_accuracy_window")
	return keys


# Stamp the per-Mk accuracy window onto the player (base 10, +2 per Mk).
func _apply_visuals(ship) -> void:
	super._apply_visuals(ship)
	if "pulse_accuracy_window" in ship:
		ship.pulse_accuracy_window = base_accuracy_window + accuracy_window_per_mark * (int(mark) - 1)
