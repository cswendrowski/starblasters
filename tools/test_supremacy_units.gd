extends SceneTree

# M6c supremacy batch: rush (burst fighter), hotrod (replaces strafer, alternating
# tracers), plasma (new plasma gunner). Plus the death-overlay fade wiring.
# Run: godot --headless --script res://tools/test_supremacy_units.gd

const RESULT := "res://tools/_supremacy_units_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Factions := preload("res://scripts/levels/factions.gd")
const BV_PlasmaOrb := preload("res://data/bullets/plasma_orb.tres")

const RUSH := "res://scenes/enemies/factions/supremacy/enemy_s_s_rush.tscn"
const HOTROD := "res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn"
const PLASMA := "res://scenes/enemies/factions/supremacy/enemy_s_m_plasma.tscn"

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _inst(path: String) -> Node:
	var n = load(path).instantiate()
	root.add_child(n)
	return n


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# --- Muzzles + glow on all three -----------------------------------------
	for p in [RUSH, HOTROD, PLASMA]:
		var n := _inst(p)
		if n.all_muzzle_pos().size() != 2:
			_fail("%s should have 2 muzzles (got %d)" % [p, n.all_muzzle_pos().size()])
		if n.get_node_or_null("GlowMask") == null:
			_fail("%s missing GlowMask" % p)
		n.free()

	# --- Roster shoot wiring --------------------------------------------------
	var want_shoot := {RUSH: "burst", HOTROD: "single", PLASMA: "aimed"}
	for p in want_shoot:
		var found := false
		for e in Roster.ENTRIES:
			if str(e.get("scene", "")) == p:
				found = true
				var sh = Roster.make_shoot(e)
				if sh == null:
					_fail("%s entry has no weapon" % p)
				elif p == PLASMA and sh.bullet_variant != BV_PlasmaOrb:
					_fail("plasma should fire plasma_orb")
		if not found:
			_fail("no roster entry for %s" % p)

	# --- Faction: supremacy-exclusive ----------------------------------------
	for p in [RUSH, HOTROD, PLASMA]:
		if not Factions.allowed_in(p, Factions.Id.SUPREMACY):
			_fail("%s should be allowed in supremacy" % p)
		if Factions.allowed_in(p, Factions.Id.CORPORATE):
			_fail("%s should be supremacy-exclusive" % p)
	if "res://scenes/enemies/factions/corporate/enemy_strafer.tscn" in Factions.ENEMY_TAGS:
		_fail("strafer should be retired from ENEMY_TAGS")

	# --- Death-overlay fade wiring -------------------------------------------
	var rush := _inst(RUSH)
	if not rush.has_method("_fade_death_overlays"):
		_fail("enemy_base missing _fade_death_overlays")
	else:
		rush._fade_death_overlays()   # should not error; fades GlowMask/Outline
	rush.free()

	_lines.append("SUPREMACY UNITS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
