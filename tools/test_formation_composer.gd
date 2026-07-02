extends SceneTree

# Driven test for FormationComposer (roadmap P2.6) + the LevelMotif escalation ledger (P2.7).
# Verifies:
#   (1) ~200 seeded formations across every primitive × escalation tier all PASS validate().
#   (2) Determinism: the same seed twice produces an identical dict.
#   (3) Member counts fit their tier budgets.
#   (4) Every composed formation compiles through AuthoredPatterns.build_phrase → a non-null Phrase.
#   (5) A full WaveGen.build() for several seeds/level indices still constructs end-to-end.
# Run: godot --headless -s tools/test_formation_composer.gd

const FormationComposer = preload("res://scripts/levels/formation_composer.gd")
const AuthoredPatterns = preload("res://scripts/levels/authored_patterns.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const Lanes = preload("res://scripts/systems/lanes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true

	# --- (1) + (3) + (4): compose across all primitives/tiers, validate + budget + build_phrase. ---
	var tier_budgets := [9, 15, 24]
	var mv_keys := ["straight", "straight_charge", "lane_drift", "lane_weave", "loiter", "lane_cut", "lane_shift"]
	var composed := 0
	var validated := 0
	var built := 0
	var budget_ok := 0
	var brng := RandomNumberGenerator.new()
	for prim in FormationComposer.PRIMITIVES:
		for tier in 3:
			for mv in mv_keys:
				brng.seed = hash("%s-%d-%s" % [prim, tier, mv])
				var flags := _flags_for_tier(tier)
				var budget: int = int(tier_budgets[tier])
				var pat: Dictionary = FormationComposer.compose(prim, mv, tier, budget, flags, brng)
				composed += 1
				if FormationComposer.validate(pat):
					validated += 1
				else:
					print("  FAIL validate: prim=%s tier=%d mv=%s (%d members)" % [prim, tier, mv, (pat.get("placements", []) as Array).size()])
					ok = false
				var n: int = (pat.get("placements", []) as Array).size()
				if n >= 1 and n <= budget:
					budget_ok += 1
				else:
					print("  FAIL budget: prim=%s tier=%d mv=%s n=%d budget=%d" % [prim, tier, mv, n, budget])
					ok = false
				# build_phrase: fill_faction any, sector 5, its own rng.
				var prng := RandomNumberGenerator.new()
				prng.seed = 777
				var ph = AuthoredPatterns.build_phrase(pat, -1, 5, prng)
				if ph == null:
					print("  FAIL build_phrase null: prim=%s tier=%d mv=%s" % [prim, tier, mv])
					ok = false
				else:
					built += 1
					for ws in ph.specs:
						if ws.lane < 0 or ws.lane >= Lanes.COUNT:
							print("  FAIL phrase lane oob: prim=%s lane=%d" % [prim, ws.lane]); ok = false; break
						if ws.enemy_scene == null:
							print("  FAIL phrase no scene: prim=%s" % prim); ok = false; break
	print("  composed=%d validated=%d budget_ok=%d built=%d" % [composed, validated, budget_ok, built])
	if composed < 189:   # 9 prims × 3 tiers × 7 keys = 189
		print("  FAIL coverage: expected >=189 compositions, got %d" % composed); ok = false

	# --- (2) determinism: same seed twice → identical dict. ---
	var det_ok := true
	for prim in FormationComposer.PRIMITIVES:
		var r1 := RandomNumberGenerator.new(); r1.seed = 424242
		var r2 := RandomNumberGenerator.new(); r2.seed = 424242
		var p1: Dictionary = FormationComposer.compose(prim, "lane_drift", 2, 24, {FormationComposer.MOD_MIRROR: true, FormationComposer.MOD_LEAD: true, FormationComposer.MOD_DEPTH_BAND: true}, r1)
		var p2: Dictionary = FormationComposer.compose(prim, "lane_drift", 2, 24, {FormationComposer.MOD_MIRROR: true, FormationComposer.MOD_LEAD: true, FormationComposer.MOD_DEPTH_BAND: true}, r2)
		if str(p1) != str(p2):
			print("  FAIL determinism: prim=%s produced differing dicts" % prim); det_ok = false; ok = false
	if det_ok:
		print("  determinism: all primitives reproduce identically")

	# --- (5) full level construction across seeds/level indices. ---
	var run := _ensure_run()
	var build_ok := true
	for seed in [0, 1, 42, 9001]:
		if run != null:
			run.set("run_seed", seed)
		for li in [0, 1, 2]:
			var level = WaveGen.build(1, li, false, -1)
			if level == null or (level.waves as Array).is_empty():
				print("  FAIL WaveGen.build seed=%d li=%d empty" % [seed, li]); build_ok = false; ok = false
				continue
			# The motif should have been stashed on Run meta for the producer to consume.
			if run != null and not run.has_meta("level_motif"):
				print("  WARN no level_motif stashed seed=%d li=%d" % [seed, li])
			# Compile the stashed motif variants through build_phrase to confirm they're valid.
			if run != null and run.has_meta("level_motif"):
				var motif: Dictionary = run.get_meta("level_motif", {})
				var variants: Array = motif.get("variants", [])
				var vbuilt := 0
				for v in variants:
					if (v as Dictionary).is_empty():
						continue
					var vr := RandomNumberGenerator.new(); vr.seed = 55
					var vph = AuthoredPatterns.build_phrase(v, -1, 1, vr)
					if vph != null:
						vbuilt += 1
					else:
						print("  FAIL motif variant build_phrase null seed=%d li=%d" % [seed, li]); ok = false
				run.remove_meta("level_motif")
	if build_ok:
		print("  WaveGen.build: 12 levels constructed end-to-end")

	print("VERDICT: %s" % ("PASS" if ok else "FAIL"))
	quit()


# Modifier ladder mirroring _roll_motif's tiers (bare / grown / full).
func _flags_for_tier(tier: int) -> Dictionary:
	match tier:
		0:
			return {FormationComposer.MOD_MIRROR: true}
		1:
			return {FormationComposer.MOD_MIRROR: true, FormationComposer.MOD_THICKEN: true}
		_:
			return {FormationComposer.MOD_MIRROR: true, FormationComposer.MOD_LEAD: true, FormationComposer.MOD_DEPTH_BAND: true}


func _ensure_run() -> Node:
	var r := root.get_node_or_null("Run")
	if r == null:
		r = _RunStub.new()
		r.name = "Run"
		root.add_child(r)
	return r


# A stub Run node exposing the run_seed property the generator's _run_seed() reads, so the test can
# vary the seed and confirm the level construction reproduces / varies.
class _RunStub extends Node:
	var run_seed: int = 0
