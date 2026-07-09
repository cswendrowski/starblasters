extends SceneTree

# M6c: privateer unit pack (green/gray/drop/cannon/pulse). Verifies the new scenes
# instantiate, muzzle markers resolve as expected (droppers/gunners have 2; the plain
# chaff have none), the roster wires movement/shoot/variants correctly, and the faction
# filter keeps them privateer-exclusive. Run:
#   godot --headless --script res://tools/test_privateer_units.gd

const RESULT := "res://tools/_privateer_units_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Factions := preload("res://scripts/levels/factions.gd")
const BV_DropPellet := preload("res://data/bullets/drop_pellet.tres")
const BV_HeavySlug := preload("res://data/bullets/bolt.tres")
const BV_PlasmaOrb := preload("res://data/bullets/wave.tres")

const GREEN := "res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn"
const GRAY := "res://scenes/enemies/core/enemy_core_s_cobra.tscn"
const DROP := "res://scenes/enemies/core/enemy_core_s_caltrop.tscn"
const CANNON := "res://scenes/enemies/factions/privateer/enemy_p_m_cannon.tscn"
const PULSE := "res://scenes/enemies/factions/privateer/enemy_p_m_pulse.tscn"

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _muzzle_count(path: String) -> int:
	var inst = load(path).instantiate()
	root.add_child(inst)   # _ready, so lazy muzzle resolution can scan children
	var c: int = inst.all_muzzle_pos().size() if inst.has_method("all_muzzle_pos") else -1
	inst.free()
	return c


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# --- 1) Muzzle resolution -------------------------------------------------
	# Plain chaff: no muzzles. Droppers/gunners: exactly two (alternating L/R).
	for p in [GREEN, GRAY]:
		var c := _muzzle_count(p)
		if c != 0:
			_fail("%s should have 0 muzzles, got %d" % [p, c])
	for p in [DROP, CANNON, PULSE]:
		var c := _muzzle_count(p)
		if c != 2:
			_fail("%s should have 2 muzzles, got %d" % [p, c])

	# --- 2) Roster wiring -----------------------------------------------------
	for p in [GREEN, GRAY, DROP, CANNON, PULSE]:
		var e: Dictionary = Roster.entry_for_scene(p)
		if e.is_empty():
			_fail("no roster entry for %s" % p)
			continue
		var mv = Roster.make_movement(e)
		if mv == null:
			_fail("%s make_movement returned null" % p)
		var sh = Roster.make_shoot(e)
		match p:
			GREEN, GRAY:
				if sh != null:
					_fail("%s should have no weapon (shoot null)" % p)
			DROP:
				if sh == null or sh.bullet_variant != BV_DropPellet:
					_fail("DROP weapon should fire drop_pellet")
			CANNON:
				if sh == null or sh.bullet_variant != BV_HeavySlug:
					_fail("CANNON weapon should fire heavy_slug")
			PULSE:
				if sh == null or sh.bullet_variant != BV_PlasmaOrb:
					_fail("PULSE weapon should fire plasma_orb")
				elif sh.wobble_amplitude <= 0.0:
					_fail("PULSE plasma should carry wobble")

	# --- 3) Faction exclusivity ----------------------------------------------
	for p in [GREEN, GRAY, DROP, CANNON, PULSE]:
		if not Factions.allowed_in(p, Factions.Id.PRIVATEER):
			_fail("%s should be allowed in privateer" % p)
		if Factions.allowed_in(p, Factions.Id.CORPORATE):
			_fail("%s should NOT be allowed in corporate (privateer-exclusive)" % p)

	# Filtered roster pool: privateer includes the new units; corporate excludes them.
	Roster.set_faction_filter(Factions.Id.PRIVATEER)
	var priv_common: Array = Roster.entries_eligible(Roster.Tier.COMMON, 9, 9)
	var priv_paths: Array = priv_common.map(func(x): return str(x.get("scene", "")))
	for p in [GREEN, GRAY, DROP]:
		if not (p in priv_paths):
			_fail("%s missing from privateer COMMON pool" % p)
	Roster.set_faction_filter(Factions.Id.CORPORATE)
	var corp_common: Array = Roster.entries_eligible(Roster.Tier.COMMON, 9, 9)
	var corp_paths: Array = corp_common.map(func(x): return str(x.get("scene", "")))
	for p in [GREEN, GRAY, DROP]:
		if p in corp_paths:
			_fail("%s leaked into corporate COMMON pool" % p)
	Roster.set_faction_filter(-1)

	_lines.append("PRIVATEER UNITS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
