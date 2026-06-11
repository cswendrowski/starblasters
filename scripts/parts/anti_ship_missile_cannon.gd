extends "res://scripts/parts/bullet_secondary.gd"

# Anti-Ship Missile launcher. Secondary weapon (HARDPOINT_WING) — fires
# alongside the primary cannon on its own cooldown. Works like the Seeking
# Missile (same one-shot lock homing), but:
#   - Fires the LARGE missile projectile (player_seeking_missile_large.tscn).
#   - The missile is SLOWER / heavier (speeds set on the large .tscn).
#   - PRIORITIZES LARGER enemies — the large .tscn sets prefer_large=true so
#     target acquisition locks the biggest (highest max_health) in-cone hull.
#   - One-shots a medium-tough enemy: the large .tscn carries
#     damage_on_contact=32, which kills every common-tier enemy outright
#     (cruiser/carrier/bomber 16, firecore cruiser 32 — the largest, i.e.
#     exactly what prefer_large locks onto).
#   - HALF the seeking missile's starting ammo (30 vs 60).
#
# Mk-scaling NOTE for Roman: the homing secondary fire path
# (player.fire_secondary) does NOT read secondary_damage onto the missile —
# missile damage comes entirely from the projectile scene's damage_on_contact.
# So base_damage / dmg_per_mark below mirror the seeking missile's structure
# for parity but do NOT actually scale missile damage. This is the same
# (pre-existing) situation as the regular Seeking Missile. To make Mk damage
# live, fire_secondary would need to set b.damage_on_contact like the burst
# rocket path does — flagged, not changed, to keep the seeking missile intact.


func _init() -> void:
	super._init()
	display_name = "Anti-Ship Missile"
	description = "Heavy seeker that locks the largest enemy and one-shots it. Slow, low ammo. Secondary."
	# Stats live in resources/weapons/anti_ship_missile.tres (single source of truth).


func _base_ammo() -> int:
	# Half the Seeking Missile's 60.
	return 30


func _homing() -> bool:
	return true
