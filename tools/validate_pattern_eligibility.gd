extends SceneTree

# Pattern-eligibility validation guard (movement-eligibility enforcement, 2026-07-09).
#
# Asserts the "enemies adhere to their eligible patterns" invariant the designer requires, so a data
# drift can't silently reintroduce a leak (an enemy flying a movement its scene's eligibility forbids).
# Cross-checks the STATIC assignment data — the producer runtime paths are guarded in code
# (PatternEligibility.guard_key / _pick_wildcard_entry), this catches the DATA before it ships:
#
#   1. ROSTER — every Roster.ENTRIES entry's movement key (after MOVEMENT_ALIASES collapse) is eligible
#      for its scene (PatternEligibility.allows). Fail-open scenes (unmapped) + path_* keys pass.
#   2. MINIBOSS registry — every WaveGenerator.MINIBOSS_ROSTER movement override is eligible for its
#      scene (the override is forced onto that exact mini-boss; a forbidden key would leak, and
#      _guarded_override would coerce it away from its intent — a data bug either way).
#   3. AUTHORED — every AuthoredPatterns.DATA placement with a FIXED enemy (non-wildcard, roster scene)
#      AND a fixed movement passes allows() for that scene (a hand-authored fixed+fixed mismatch).
#
# Run: godot --headless -s res://tools/validate_pattern_eligibility.gd   (prints VERDICT: PASS/FAIL)

const Roster = preload("res://scripts/levels/enemy_roster.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const AuthoredPatterns = preload("res://scripts/levels/authored_patterns.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")


func _collapse(key: String) -> String:
	return String(Roster.MOVEMENT_ALIASES.get(key, key))


func _init() -> void:
	var fails: Array = []
	var checked_roster: int = 0
	var checked_mb: int = 0
	var checked_authored: int = 0

	# 1) ROSTER entries.
	for e in Roster.ENTRIES:
		var scene: String = String(e.get("scene", ""))
		var mv_raw: Variant = e.get("movement", null)
		if mv_raw == null:
			continue   # bespoke enemy — moves via its own script, no key contract
		var key: String = _collapse(String(mv_raw))
		if key == "":
			continue
		checked_roster += 1
		if not PatternEligibility.allows(scene, key):
			var elig: Array = PatternEligibility.eligible_for(scene)
			fails.append("ROSTER: '%s' movement '%s' NOT in eligibility %s" % [scene, key, str(elig)])

	# 2) MINIBOSS registry overrides.
	for m in WaveGen.MINIBOSS_ROSTER:
		var mv: String = String(m.get("movement", ""))
		if mv == "":
			continue
		var scene: String = String(m.get("scene", ""))
		var key: String = _collapse(mv)
		checked_mb += 1
		if not PatternEligibility.allows(scene, key):
			var elig: Array = PatternEligibility.eligible_for(scene)
			fails.append("MINIBOSS: '%s' movement override '%s' NOT in eligibility %s" % [scene, key, str(elig)])

	# 3) AUTHORED fixed-enemy + fixed-movement placements.
	for p in AuthoredPatterns.DATA:
		var pname: String = String(p.get("name", "?"))
		for pl in p.get("placements", []):
			var enemy: String = String(pl.get("enemy", ""))
			var move: String = String(pl.get("movement", ""))
			if enemy == "" or move == "":
				continue   # wildcard on either axis — resolved + guarded at build time
			# Only roster-known scenes carry an eligibility contract; hazards / non-roster pins fail open.
			if PatternEligibility.eligible_for(enemy).is_empty():
				continue
			var key: String = _collapse(move)
			checked_authored += 1
			if not PatternEligibility.allows(enemy, key):
				var elig: Array = PatternEligibility.eligible_for(enemy)
				fails.append("AUTHORED[%s]: '%s' movement '%s' NOT in eligibility %s" % [pname, enemy, key, str(elig)])

	print("pattern-eligibility check: roster=%d miniboss=%d authored=%d checked" % [
		checked_roster, checked_mb, checked_authored])
	if fails.is_empty():
		print("VERDICT: PASS")
	else:
		print("FAILURES (%d):" % fails.size())
		for f in fails:
			print("  - " + f)
		print("VERDICT: FAIL")
	quit()
