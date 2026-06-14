extends "res://scripts/parts/module_part.gd"

# Shield Core — the reified shield, as a passive Module (2026-06-13). DEFAULT-equipped
# in the bay. Its PRESENCE is what gives you a shield at all: drop it for a free bay
# slot and you fly shieldless — the glass-cannon build. The shield's CAPACITY still
# scales off the Shield Capacity upgrade (shield_cap_mk); this Core's Mk adds a small
# capacity bonus on top (+1 charge per Mk above 1). The "is a Shield Core equipped?"
# gate lives in player.apply_run_upgrades (reads Run.has_module). See
# docs/passive_module_bay_2026-06-13.md.


func _init() -> void:
	super._init()
	module_id = "shield_core"
	display_name = "Shield Core"
	description = "Powers your shield. Drop it for a free module slot and fly shieldless — a glass cannon. Mk adds shield charges."


func apply(ship) -> void:
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus += int(mark) - 1


func unapply(ship) -> void:
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus -= int(mark) - 1
