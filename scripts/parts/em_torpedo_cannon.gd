extends "res://scripts/parts/bullet_secondary.gd"

# EM Torpedo — HARDPOINT_WING secondary (Roman 2026-06-10). Fires a large dumb-fire rocket that
# bursts into an electrical discharge among the enemy formation: strips/ignores shields,
# chain-detonates enemy ordnance, and sends most kills drifting into the wreck layer.
#
# BULLET mode like the Seeking/Anti-Ship missiles, but NON-homing (it's a thrown payload). The burst
# AoE damage is Mk-scaled: fire_secondary writes secondary_damage onto the spawned torpedo's `damage`
# field, which the burst uses. Heavy, low-ammo, slow cadence.


func _init() -> void:
	super._init()
	display_name = "EM Torpedo"
	description = "Large rocket that bursts into chain lightning — strips shields, detonates enemy ordnance, leaves wrecks. Secondary."
	base_damage = 6
	dmg_per_mark = 2     # burst AoE: Mk1 6 -> Mk9 22 (base_damage + dmg_per_mark*8)
	base_cooldown = 1.1


func _base_ammo() -> int:
	# UNLIMITED for the test-combat phase (Roman 2026-06-10) — the torpedo is test-gated (not in the
	# shop pool), so -1 = unmetered everywhere it can currently appear = the dev Test-Combat button.
	# Give it a real magazine here when it's promoted to a live shop weapon.
	return -1


func _homing() -> bool:
	return false
