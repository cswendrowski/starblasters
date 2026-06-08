extends SceneTree

# One-shot seed generator for pattern-eligibility data (pattern_eligibility_2026-06-08.md).
# Scans the live roster ENTRIES -> per scene: identity = most-used movement key, eligible = set
# of movement keys it uses. Output pasted into scripts/levels/pattern_eligibility.gd.
# Run: godot --headless --script res://tools/gen_pattern_eligibility.gd

const Roster := preload("res://scripts/levels/enemy_roster.gd")
const OUT := "res://tools/_eligibility_seed.txt"

var _done := false

func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var per_scene: Dictionary = {}
	for e in Roster.ENTRIES:
		var scene: String = str(e.get("scene", ""))
		if scene == "":
			continue
		# Skip bespoke-movement enemies (entry "movement": null — bomber, beam-shooters,
		# firecore_drone): they move via their own scripts, not make_movement, so they aren't
		# pattern-assignable and don't belong in the eligibility matrix.
		var mv_v: Variant = e.get("movement", null)
		if mv_v == null:
			continue
		var mv: String = str(mv_v)
		if not per_scene.has(scene):
			per_scene[scene] = {}
		per_scene[scene][mv] = int(per_scene[scene].get(mv, 0)) + 1
	var scenes: Array = per_scene.keys()
	scenes.sort()
	var out: String = "const DATA := {\n"
	for scene in scenes:
		var freq: Dictionary = per_scene[scene]
		var keys: Array = freq.keys()
		keys.sort()
		var identity: String = str(keys[0])
		var best: int = -1
		for k in keys:
			if int(freq[k]) > best:
				best = int(freq[k])
				identity = str(k)
		var elig: String = "["
		for i in range(keys.size()):
			if i > 0:
				elig += ", "
			elig += "\"" + str(keys[i]) + "\""
		elig += "]"
		out += "\t\"" + scene + "\": {\"identity\": \"" + identity + "\", \"eligible\": " + elig + "},\n"
	out += "}\n"
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string(out)
		f.close()
	quit()
	return true
