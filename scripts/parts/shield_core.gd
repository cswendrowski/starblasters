extends "res://scripts/parts/module_part.gd"

# Shield Core — the reified shield, as a passive Module (2026-06-13). DEFAULT-equipped
# in the bay. Its PRESENCE is what gives you a shield at all: drop it for a free bay slot
# and you fly shieldless — the glass-cannon build. Its Mk now drives the shield CAPACITY
# (the old Shield Capacity upgrade folded in 2026-06-13): base 10 charges, +2 per Mk,
# +4 at Mk.9 → Mk.1 = 10, Mk.9 = 30. The "is a Shield Core equipped?" gate lives in
# player.apply_run_upgrades (reads Run.has_module). See docs/passive_module_bay_2026-06-13.md.


func _init() -> void:
	super._init()
	module_id = "shield_core"
	display_name = "Shield Core"
	description = "Powers your charge-pool shield (base 10 charges, +2 per Mk, +4 at Mk.9). Drop it for a free module slot and fly shieldless — a glass cannon."


# Shield capacity ABOVE the base 10 (player.apply_run_upgrades adds the 10).
func _capacity_bonus() -> int:
	return (clampi(int(mark), 1, 9) - 1) * 2 + (4 if int(mark) >= 9 else 0)


func apply(ship) -> void:
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus += _capacity_bonus()


func unapply(ship) -> void:
	if "module_shield_bonus" in ship:
		ship.module_shield_bonus -= _capacity_bonus()


func bonus_description(mk: int) -> String:
	var m := clampi(mk, 1, 9)
	var bonus: int = _capacity_bonus() if m == int(mark) else ((m - 1) * 2 + (4 if m >= 9 else 0))
	return "Shield charges: +%d (base 10)" % bonus
