extends SceneTree

# Wave-reachability validation guard (reachability audit, 2026-07-15).
#
# Asserts the "every enemy the game can field IS reachable, and everything else is DELIBERATELY not"
# invariant, so a roster drift can't silently strand a unit (an armed elite that no beat ever picks —
# the chaff:false + non-heavy + non-crosser trap) without a paper trail. Two passes:
#
#   1. STATIC — every Roster.ENTRIES entry is classifiable:
#        • implicit "wave"  — chaff:true OR heavy_class set OR the scene sits in WaveGen.MINIBOSS_ROSTER
#                             (these MUST be reachable in a normal wave roll — checked empirically below).
#        • "excluded"       — no_wave:true OR a scenes/enemies/ground/ emplacement (placed by the
#                             stronghold field, never the random wave roll) — exempt from the check.
#        • explicit role    — combat_role "support" (reachable via escort/authored/boss-lead-in only —
#                             acceptable) or "codex_only" (never spawns — deliberate display-only).
#      FAILs naming any entry that is none of the above, or carries an unknown combat_role value.
#
#   2. EMPIRICAL — build a spread of levels (all factions × depths × node indices × run seeds, the
#      flat production build() path) and collect every enemy scene that actually spawns. FAILs naming
#      any "wave"-role scene that never appeared across the whole sample (its entry claims wave-role
#      but no beat reaches it). support / codex_only / excluded scenes are not required to appear.
#
# Run: godot --headless -s res://tools/validate_reachability.gd   (prints VERDICT: PASS/FAIL)

const Roster = preload("res://scripts/levels/enemy_roster.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")

const VALID_ROLES := ["support", "codex_only"]

# Sampling spread for the empirical pass. 10 run seeds × 4 factions × 3 depths × 6 node indices =
# 720 combat builds, plus 10 × 4 × 3 = 120 boss builds. Deep node indices (li up to 5) reach
# eff_depth = li + 2 = 7 at the climax so the depth-gated minibosses (Crusader min_depth 4) roll.
const SEED_COUNT := 10
const FACTIONS := [0, 1, 2, 3]
const DEPTHS := [1, 2, 3]
const NODE_INDICES := [0, 1, 2, 3, 4, 5]


# Headless has no autoloads; build()'s seed fold reads /root/Run.run_seed via the tree, so provide a stub.
class RunStub extends Node:
	var run_seed: int = 0


func _init() -> void:
	var fails: Array = []

	var mb_scenes: Dictionary = {}
	for m in WaveGen.MINIBOSS_ROSTER:
		mb_scenes[String(m.get("scene", ""))] = true

	# --- 1) STATIC classification ---
	var expected_wave: Dictionary = {}   # scene -> true : must appear empirically
	var checked_static: int = 0
	for e in Roster.ENTRIES:
		checked_static += 1
		var scene: String = String(e.get("scene", ""))
		var chaff: bool = bool(e.get("chaff", false))
		var heavy: String = String(e.get("heavy_class", ""))
		var role: String = String(e.get("combat_role", ""))
		var is_wave: bool = chaff or heavy != "" or mb_scenes.has(scene)
		var excluded: bool = bool(e.get("no_wave", false)) or scene.contains("/ground/")

		if role != "" and not VALID_ROLES.has(role):
			fails.append("STATIC: '%s' has unknown combat_role '%s' (expected one of %s)" % [scene, role, str(VALID_ROLES)])

		if is_wave:
			expected_wave[scene] = true
		elif excluded:
			pass
		elif role != "":
			pass   # support / codex_only — deliberately not a wave pick
		else:
			fails.append("STATIC: '%s' is unclassified — not chaff/heavy/miniboss, not no_wave/ground, and no combat_role (add \"combat_role\": \"support\" or \"codex_only\")" % scene)

	# --- 2) EMPIRICAL reachability ---
	var run := RunStub.new()
	run.name = "Run"
	root.add_child(run)

	var seeds: Array = []
	var srng := RandomNumberGenerator.new()
	srng.seed = 0xABCDEF
	for i in SEED_COUNT:
		seeds.append(srng.randi())

	var seen: Dictionary = {}
	var built: int = 0
	for seed in seeds:
		run.run_seed = int(seed)
		for faction in FACTIONS:
			for sd in DEPTHS:
				for li in NODE_INDICES:
					_collect(WaveGen.build(sd, li, false, faction), seen)
					built += 1
				# One boss build per (seed, faction, sd) — covers boss lead-in enemies.
				_collect(WaveGen.build(sd, 2, true, faction), seen)
				built += 1

	for scene in expected_wave.keys():
		if not seen.has(scene):
			fails.append("EMPIRICAL: '%s' is wave-role (chaff/heavy/miniboss) but NEVER spawned across %d builds — unreachable" % [scene, built])

	run.queue_free()

	print("reachability check: static=%d entries, empirical=%d builds, %d distinct scenes seen, %d wave-role scenes expected" % [
		checked_static, built, seen.size(), expected_wave.size()])
	if fails.is_empty():
		print("VERDICT: PASS")
	else:
		print("FAILURES (%d):" % fails.size())
		for f in fails:
			print("  - " + f)
		print("VERDICT: FAIL")
	quit()


func _collect(level, seen: Dictionary) -> void:
	if level == null:
		return
	for w in level.waves:
		if w == null or w.enemy_scene == null:
			continue
		seen[String(w.enemy_scene.resource_path)] = true
