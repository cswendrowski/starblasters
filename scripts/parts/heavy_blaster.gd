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

# Cooldown shrinks by ~35% from Mk.1 → Mk.9 (faster firing at top tier).
@export var cooldown_at_mk9: float = 0.18


func _init() -> void:
	super._init()
	display_name = "Heavy Blaster"
	description = "Slow firing, hits hard per shot."
	base_damage = 5
	dmg_per_mark = 3
	base_cooldown = 0.28


func _fire_sfx_kind() -> int:
	return WS.FireSfxKind.BLASTER_LARGE


func _mk_knobs() -> Dictionary:
	return {
		"bullet_damage": [base_damage, base_damage + dmg_per_mark * 8],
		"cooldown": [base_cooldown, cooldown_at_mk9],
	}
