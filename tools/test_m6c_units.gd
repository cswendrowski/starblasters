extends SceneTree

# M6c batch 2: corp chaff pack (gray/curve/drop/hold) + the Gunship/Rocket
# divergence. Verifies scenes instantiate, markers resolve, the roster wires the
# right movement (incl. the new "omni" case), and faction tags land correctly.
# Run: godot --headless --script res://tools/test_m6c_units.gd

const RESULT := "res://tools/_m6c_units_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Factions := preload("res://scripts/levels/factions.gd")

const C_GRAY := "res://scenes/enemies/factions/corporate/enemy_c_s_gray.tscn"
const C_CURVE := "res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn"
const C_DROP := "res://scenes/enemies/factions/corporate/enemy_c_s_drop.tscn"
const C_HOLD := "res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn"
const GUNSHIP := "res://scenes/enemies/factions/privateer/enemy_gunship.tscn"
const ROCKET := "res://scenes/enemies/factions/privateer/enemy_rocket.tscn"

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _inst(path: String) -> Node:
	var n = load(path).instantiate()
	root.add_child(n)
	return n


func _has(n: Node, child: String) -> bool:
	return n.get_node_or_null(child) != null


func _mv_script(path: String) -> String:
	var e: Dictionary = Roster.entry_for_scene(path)
	if e.is_empty():
		return "<no-entry>"
	var mv = Roster.make_movement(e)
	if mv == null or mv.get_script() == null:
		return "<null>"
	return str(mv.get_script().resource_path).get_file()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# --- 1) Corp chaff muzzles ----------------------------------------------
	for p in [C_GRAY, C_CURVE]:
		var n := _inst(p)
		if n.all_muzzle_pos().size() != 0:
			_fail("%s should have 0 muzzles" % p)
		n.free()
	var drop := _inst(C_DROP)
	if drop.all_muzzle_pos().size() != 2:
		_fail("corp drop should have 2 muzzles")
	drop.free()
	var hold := _inst(C_HOLD)
	if not _has(hold, "Muzzle"):
		_fail("corp hold missing Muzzle marker")
	hold.free()

	# --- 2) Gunship / Rocket markers ----------------------------------------
	var gun := _inst(GUNSHIP)
	for m in ["MuzzleL", "MuzzleR", "CannonL", "CannonR"]:
		if not _has(gun, m):
			_fail("gunship missing marker %s" % m)
	gun.free()
	var rck := _inst(ROCKET)
	for m in ["MuzzleL", "MuzzleR", "launch_point1", "launch_point6"]:
		if not _has(rck, m):
			_fail("rocket missing marker %s" % m)
	rck.free()

	# --- 3) Roster movement wiring ------------------------------------------
	var want := {
		C_GRAY: "straight_down.gd", C_CURVE: "lane_path.gd",
		C_DROP: "straight_down.gd", C_HOLD: "loiter.gd",
		GUNSHIP: "omni_thrust.gd", ROCKET: "lane_path.gd",
	}
	for p in want:
		var got := _mv_script(p)
		if got != want[p]:
			_fail("%s movement = %s, want %s" % [p, got, want[p]])

	# --- 3b) Gunship movement variants --------------------------------------
	# The one Gunship scene should appear under several movements (omni + the
	# hold/weave/shift/skirmish variants) so the conductor has more uses for it.
	var gun_moves: Array = []
	for e in Roster.ENTRIES:
		if str(e.get("scene", "")) != GUNSHIP:
			continue
		var mv = Roster.make_movement(e)
		if mv == null:
			_fail("gunship entry has null movement (%s)" % str(e.get("movement", "?")))
		else:
			gun_moves.append(str(e.get("movement", "")))
	for needed in ["omni", "loiter_mid", "lane_weave", "lane_shift", "advance_retreat"]:
		if not (needed in gun_moves):
			_fail("gunship missing movement variant '%s'" % needed)

	# --- 4) Faction tags ----------------------------------------------------
	# Corp gray/curve/drop = corporate-exclusive.
	for p in [C_GRAY, C_CURVE, C_DROP]:
		if not Factions.allowed_in(p, Factions.Id.CORPORATE):
			_fail("%s should be allowed in corporate" % p)
		if Factions.allowed_in(p, Factions.Id.PRIVATEER):
			_fail("%s should NOT leak into privateer" % p)
	# Hold = corporate universal (in every faction).
	for fac in [Factions.Id.CORPORATE, Factions.Id.PRIVATEER, Factions.Id.ZEALOT, Factions.Id.SUPREMACY]:
		if not Factions.allowed_in(C_HOLD, fac):
			_fail("hold (universal) should be allowed in faction %d" % fac)
	# Gunship + Rocket = privateer-exclusive.
	for p in [GUNSHIP, ROCKET]:
		if not Factions.allowed_in(p, Factions.Id.PRIVATEER):
			_fail("%s should be allowed in privateer" % p)
		if Factions.allowed_in(p, Factions.Id.CORPORATE):
			_fail("%s should NOT leak into corporate" % p)
	# Old hover retired from the tag table.
	if "res://scenes/enemies/core/enemy_hover.tscn" in Factions.ENEMY_TAGS:
		_fail("enemy_hover.tscn should be retired from ENEMY_TAGS")

	_lines.append("M6C UNITS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
