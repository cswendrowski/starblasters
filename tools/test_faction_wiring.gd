extends SceneTree

# M6b producer wiring. Verifies the faction pool restriction end-to-end:
#   - allowed_in: universal allowed everywhere; exclusive only in its home.
#   - Roster faction filter restricts entries_eligible.
#   - WaveGen.build(..., faction) produces a level whose enemies contain NO other-
#     faction exclusives (and clears the filter after).
#   - pick_for_level is deterministic.
# Run: godot --headless --script res://tools/test_faction_wiring.gd

const RESULT := "res://tools/_faction_wiring_result.txt"
const Factions := preload("res://scripts/levels/factions.gd")
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const WaveGen := preload("res://scripts/levels/wave_generator.gd")

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


# Scenes that are exclusive to a faction OTHER than `faction` — must NOT appear.
func _forbidden_for(faction: int) -> Array:
	var out: Array = []
	for path in Factions.ENEMY_TAGS.keys():
		var t: Dictionary = Factions.ENEMY_TAGS[path]
		if not bool(t.get("universal", false)) and int(t.get("home", -1)) != faction:
			out.append(path)
	return out


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# allowed_in
	var dart := "res://scenes/enemies/enemy_dart.tscn"          # universal
	var fcd := "res://scenes/enemies/enemy_firecore_drone.tscn" # zealot exclusive
	if not Factions.allowed_in(dart, Factions.Id.CORPORATE):
		_fail("universal dart not allowed in corporate")
	if Factions.allowed_in(fcd, Factions.Id.CORPORATE):
		_fail("zealot-exclusive firecore_drone allowed in corporate")
	if not Factions.allowed_in(fcd, Factions.Id.ZEALOT):
		_fail("firecore_drone not allowed in its home (zealot)")

	# Roster filter
	Roster.set_faction_filter(Factions.Id.CORPORATE)
	var corp_scenes := {}
	for tier in [Roster.Tier.COMMON, Roster.Tier.UNCOMMON, Roster.Tier.RARE]:
		for e in Roster.entries_eligible(tier, 99, 99):
			corp_scenes[str(e.get("scene", ""))] = true
	Roster.set_faction_filter(-1)
	if corp_scenes.has(fcd):
		_fail("corporate filter let a zealot exclusive into entries_eligible")
	if not corp_scenes.has(dart):
		_fail("corporate filter dropped universal dart")

	# WaveGen.build end-to-end (zealot level): no other-faction exclusives in the waves.
	var lvl = WaveGen.build(3, 1, false, Factions.Id.ZEALOT)
	var forbidden := _forbidden_for(Factions.Id.ZEALOT)
	var leaked: Array = []
	for w in lvl.waves:
		if w == null or w.enemy_scene == null:
			continue
		var p: String = w.enemy_scene.resource_path
		if p in forbidden and not (p in leaked):
			leaked.append(p)
	if not leaked.is_empty():
		_fail("zealot level leaked other-faction exclusives: %s" % str(leaked))
	# filter cleared after build
	if Roster._faction_filter != -1:
		_fail("Roster faction filter not cleared after build (%d)" % Roster._faction_filter)

	# REGRESSION (2026-06-06): the empty-pool fallback leaked other factions' exclusives
	# at SHALLOW depth (gunship in every faction at sd=1). Build at the shallowest coord
	# for each faction and assert zero leaks.
	for fid in [Factions.Id.SUPREMACY, Factions.Id.PRIVATEER, Factions.Id.CORPORATE, Factions.Id.ZEALOT]:
		var shallow = WaveGen.build(1, 0, false, fid)
		var forb := _forbidden_for(fid)
		for w in shallow.waves:
			if w == null or w.enemy_scene == null:
				continue
			if w.enemy_scene.resource_path in forb:
				_fail("faction %d shallow(1,0) leaked %s" % [fid, w.enemy_scene.resource_path.get_file()])
				break

	# pick_for_level deterministic
	var a := Factions.pick_for_level(2, 1, 12345)
	var b := Factions.pick_for_level(2, 1, 12345)
	if a != b:
		_fail("pick_for_level not deterministic (%d != %d)" % [a, b])
	if a < 0 or a > 3:
		_fail("pick_for_level out of range (%d)" % a)

	_lines.append("corp pool size=%d ; zealot level waves=%d leaked=%d" % [corp_scenes.size(), lvl.waves.size(), leaked.size()])
	_lines.append("FACTION WIRING: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
