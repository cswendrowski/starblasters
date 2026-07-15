extends SceneTree

# Faction-purity validation guard (faction-mix fix, 2026-07-11).
#
# Asserts the "a level rolls ONE faction; only that faction's home units + universals may spawn"
# invariant the design requires, so a data/producer drift can't silently reintroduce a cross-faction
# mix (the reported zealot + supremacy + privateer boss level, caused by the boss lead-in building
# with faction=-1 → the Roster filter OFF). Builds N levels PER FACTION at a spread of coordinates,
# INCLUDING boss levels, and asserts every generated WaveSpec's enemy scene is allowed_in that faction
# (universal OR home == faction). Untagged scenes (bosses / mines / asteroids) fail open by design and
# are exempt — the check mirrors Factions.allowed_in exactly.
#
# Run: godot --headless -s res://tools/validate_faction_purity.gd   (prints VERDICT: PASS/FAIL)

const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const Factions = preload("res://scripts/levels/factions.gd")

# (sector_depth, level_index) coordinates probed per faction — shallow openers through deep nodes.
const COORDS := [
	[1, 0], [1, 1], [1, 2], [2, 0], [2, 2], [3, 1], [3, 3],
]


func _init() -> void:
	var fails: Array = []
	var checked_levels: int = 0
	var checked_specs: int = 0

	for faction in [Factions.Id.SUPREMACY, Factions.Id.PRIVATEER, Factions.Id.CORPORATE, Factions.Id.ZEALOT]:
		for is_boss in [false, true]:
			for c in COORDS:
				var sd: int = int(c[0])
				var li: int = int(c[1])
				var level = WaveGen.build(sd, li, is_boss, faction)
				checked_levels += 1
				if level == null:
					fails.append("faction=%d boss=%s sd=%d li=%d — build returned null" % [faction, str(is_boss), sd, li])
					continue
				for w in level.waves:
					if w == null or w.enemy_scene == null:
						continue
					checked_specs += 1
					var path: String = String(w.enemy_scene.resource_path)
					if not Factions.allowed_in(path, faction):
						fails.append("faction=%d boss=%s sd=%d li=%d — '%s' NOT universal/home for the faction" % [
							faction, str(is_boss), sd, li, path])

	print("faction-purity check: levels=%d specs=%d checked" % [checked_levels, checked_specs])
	if fails.is_empty():
		print("VERDICT: PASS")
	else:
		# Dedup for readability (the same leak recurs across coordinates).
		var seen: Dictionary = {}
		var uniq: Array = []
		for f in fails:
			if not seen.has(f):
				seen[f] = true
				uniq.append(f)
		print("FAILURES (%d unique, %d total):" % [uniq.size(), fails.size()])
		for f in uniq:
			print("  - " + f)
		print("VERDICT: FAIL")
	quit()
