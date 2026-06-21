extends SceneTree

# Faction-scoped bonuses (Roman 2026-06-08): FactionsC.apply only overlays a unit whose HOME
# is that faction. A corpo unit gets the corpo shield; a privateer-home dart in a corpo level
# does NOT. Run: godot --headless --script res://tools/test_faction_gate.gd

const RESULT := "res://tools/_faction_gate_result.txt"
const Factions := preload("res://scripts/levels/factions.gd")
const CORPO := 2   # Factions.Id.CORPORATE
const CORPO_UNIT := "res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn"
const PRIV_UNIT := "res://scenes/enemies/factions/privateer/enemy_dart.tscn"

var _done := false


func _has_charge_shield(e) -> bool:
	if not ("components" in e) or not (e.components is Array):
		return false
	for c in e.components:
		if c != null and c.has_method("is_pool") and not c.is_pool():
			return true
	return false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	# scene_file_path is set at instantiate(), so apply()'s home-gate works without add_child.
	var corpo = load(CORPO_UNIT).instantiate()
	Factions.apply(CORPO, corpo)
	if not _has_charge_shield(corpo):
		lines.append("FAIL corpo unit did NOT get the corpo shield"); fails += 1
	corpo.free()
	var dart = load(PRIV_UNIT).instantiate()
	Factions.apply(CORPO, dart)
	if _has_charge_shield(dart):
		lines.append("FAIL privateer-home dart got a corpo shield in a corpo level"); fails += 1
	dart.free()
	lines.append("FACTION GATE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
