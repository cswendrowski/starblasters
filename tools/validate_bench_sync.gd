extends SceneTree

# Bench↔roster sync guard (stale-literal detection, 2026-07-15).
#
# The Enemy Bench gates some fields behind per-entry override checkboxes (engine_override etc.)
# and only emits them into its Copy-GDScript snippet when the override is ON — but a literal
# already baked into Roster.ENTRIES applies in production UNCONDITIONALLY. Once a checkbox is
# flipped OFF, the bench previews the default while the live game keeps the stale literal:
# the flechette shipped at HALF speed this way ("engine": -1 in the roster, override off in
# the bench, bench showing 120 px/s while live resolved 60).
#
# This guard cross-checks every Roster entry's `engine` literal against the designer's bench
# save (user://tuners/enemy_bench.json): a nonzero roster engine whose bench entry has
# engine_override == false is a desync → FAIL naming the entry. Entries absent from the bench
# save are skipped (bench has never touched them). If no bench save exists on this machine
# (fresh clone / CI), the check SKIPS with a PASS — it guards Roman's authoring loop, not CI.
#
# Run: godot --headless -s res://tools/validate_bench_sync.gd   (prints VERDICT: PASS/FAIL)

const Roster = preload("res://scripts/levels/enemy_roster.gd")
const BENCH_SAVE := "user://tuners/enemy_bench.json"


func _init() -> void:
	if not FileAccess.file_exists(BENCH_SAVE):
		print("bench-sync check: no bench save at %s — skipped" % BENCH_SAVE)
		print("VERDICT: PASS")
		quit(0)
		return

	var f := FileAccess.open(BENCH_SAVE, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		print("bench-sync check: bench save unreadable/malformed")
		print("VERDICT: FAIL")
		quit(1)
		return

	# Bench save maps scene path (or entry key) → config dict; find the per-enemy dicts.
	var bench_by_scene: Dictionary = {}
	for key in data.keys():
		var v: Variant = data[key]
		if typeof(v) == TYPE_DICTIONARY and (v.has("engine") or v.has("engine_override")):
			var scene: String = String(v.get("scene", key))
			bench_by_scene[scene] = v

	var fails: Array = []
	var checked: int = 0
	for e in Roster.ENTRIES:
		var scene: String = String(e.get("scene", ""))
		if not bench_by_scene.has(scene):
			continue
		var bench: Dictionary = bench_by_scene[scene]
		if not bench.has("engine_override"):
			continue
		checked += 1
		var roster_engine: int = int(e.get("engine", 0))
		var override_on: bool = bool(bench.get("engine_override", false))
		if roster_engine != 0 and not override_on:
			fails.append("%s: roster engine %d but bench engine_override OFF (bench previews 0) — stale literal or untick mismatch"
				% [scene.get_file(), roster_engine])

	for msg in fails:
		push_error("bench-sync: " + msg)
		print("FAIL: " + msg)
	print("bench-sync check: %d bench-tracked entries checked" % checked)
	print("VERDICT: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	quit(0 if fails.is_empty() else 1)
