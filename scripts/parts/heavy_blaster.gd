extends "res://scripts/parts/primary_weapon.gd"

# Heavy Blaster. Slow-firing high-damage energy cannon. Mk scales both
# damage (4 → 28) and cadence (base_cooldown → cooldown_at_mk9) — faster
# + harder hitting at top tier.
#
# Was the canary for the 2026-05-24 WeaponPart refactor — used to silently
# inherit the previous cannon's weapon_style (e.g. Machinegun's audio loop)
# because apply() forgot to snapshot+write it. The new base auto-snapshots
# weapon_style + fire_sfx_kind, AND the virtual _fire_sfx_kind() method
# survives .tres loading (unlike @export which would default to NONE for
# resource-loaded instances since _init doesn't run).

# Cooldown shrinks from Mk.1 → Mk.9 (faster firing at top tier), but stays slow —
# this is the hard-hitting BLASTER-REPLACEMENT, not a rapid weapon.
@export var cooldown_at_mk9: float = 0.30


func _init() -> void:
	super._init()
	display_name = "Heavy Blaster"
	description = "Blaster replacement: slow, slow-moving shots that hit very hard. Unlimited ammo."
	# Stats live in resources/weapons/heavy_blaster.tres (single source of truth).


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.BLASTER_LARGE


# Heavy Blaster is now an infinite BLASTER REPLACEMENT (Roman 2026-06-11): equipping
# it sends the old blaster to the hold; it never meters ammo. -1 = infinite.
func ammo_at_mark(_mk: int) -> int:
	return -1


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [base_damage, base_damage + dmg_per_mark * 8],
		"cooldown": [base_cooldown, cooldown_at_mk9],
	}
