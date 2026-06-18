extends SceneTree

# Driven test for the authored wave-pattern library. Verifies every pattern in AuthoredPatterns.DATA
# names unique, builds into a FORMATION Phrase whose specs cover all placements with valid lanes, and
# that maybe_inject can splice a forced pattern into a score. Run: godot --headless -s tools/test_authored_patterns.gd

const AuthoredPatterns = preload("res://scripts/levels/authored_patterns.gd")
const Lanes = preload("res://scripts/systems/lanes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	# (1) names unique + non-placeholder.
	var seen := {}
	for p in AuthoredPatterns.DATA:
		var nm := String(p.get("name", ""))
		if nm == "" or nm.begins_with("pattern_"):
			print("  FAIL placeholder/empty name: '%s'" % nm); ok = false
		if seen.has(nm):
			print("  FAIL duplicate name: %s" % nm); ok = false
		seen[nm] = true
	print("  patterns: %d, unique names: %d" % [AuthoredPatterns.DATA.size(), seen.size()])

	# (2) each pattern builds into a phrase covering all placements on valid lanes.
	for p in AuthoredPatterns.DATA:
		var nm := String(p.get("name", ""))
		var placements: Array = p.get("placements", [])
		var ph = AuthoredPatterns.build_phrase(p, -1, 5, rng)   # fill_faction any, sector 5
		if ph == null:
			print("  FAIL %s: build_phrase returned null" % nm); ok = false
			continue
		if ph.specs.size() != placements.size():
			print("  FAIL %s: %d specs for %d placements" % [nm, ph.specs.size(), placements.size()]); ok = false
		for ws in ph.specs:
			if ws.lane < 0 or ws.lane >= Lanes.COUNT:
				print("  FAIL %s: spec lane %d out of range" % [nm, ws.lane]); ok = false
				break
			if ws.enemy_scene == null:
				print("  FAIL %s: spec has no enemy scene" % nm); ok = false
				break

	# (3) eligibility: every pattern is faction "any" + min_sector 0, so all eligible from sector 0.
	var elig: Array = AuthoredPatterns.eligible(-1, 0)
	if elig.size() != AuthoredPatterns.DATA.size():
		print("  FAIL eligible at sector 0: %d of %d" % [elig.size(), AuthoredPatterns.DATA.size()]); ok = false

	# (4) maybe_inject splices a forced pattern's phrase into wave 0.
	var score = _stub_score()
	var run := _ensure_run()
	if run != null:
		run.set_meta("forced_pattern", "crawl_phalanx")
		AuthoredPatterns.maybe_inject(score, -1, 0, rng, 0.0)   # chance 0 → only the forced one
		if score.waves[0].phrases.size() != 1:
			print("  FAIL forced inject: %d phrases" % score.waves[0].phrases.size()); ok = false
		elif score.waves[0].phrases[0].specs.size() != 21:
			print("  FAIL forced crawl_phalanx specs: %d" % score.waves[0].phrases[0].specs.size()); ok = false
	else:
		print("  (skip inject test — no Run node)")

	print("VERDICT: %s" % ("PASS" if ok else "FAIL"))
	quit()


# A minimal score with one empty wave (a Node with a `waves` array of objects exposing `phrases`).
func _stub_score():
	var score := _Bag.new()
	var wave := _Bag.new()
	wave.set("phrases", [])
	score.set("waves", [wave])
	return score


func _ensure_run() -> Node:
	var r := root.get_node_or_null("Run")
	if r == null:
		r = Node.new()
		r.name = "Run"
		root.add_child(r)
	return r


class _Bag extends Object:
	var waves: Array = []
	var phrases: Array = []
