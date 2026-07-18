extends SceneTree

# Ship-unlock pacing sim (2026-07-11 — docs/ship_unlock_system_2026-07-11.md).
# Builds REAL levels via WaveGen.build across a full patrol's shape and counts the
# namesake-enemy spawns, to answer: how many full sector patrols to unlock each hull?
#
# Patrol model (from Run.start_new_sector + main.gd):
#   - 3 rows x 3-5 POIs (avg 4) = 12 POIs; combat 5/9 -> ~6.67 combat nodes/patrol.
#   - Combat node faction: uniform 25% each (Run._faction_for_poi).
#   - li (combats_in_sector) increments run-wide: combats are li 0..6, sd = 1.
#   - 3 boss levels per patrol (faction -1 = unfiltered lead-ins), li ~2/4/6.
#   - Hazard/signal nodes excluded (asteroid strongholds would ADD some kills — floor).
#
# Counts are INITIAL SPAWNS (sum of wave.count). Recycling multiplies chaff exposure;
# waves with recycle_passes == 0 never recycle. Printed both raw and with a recycle
# multiplier applied to recyclable waves.
#   godot --path . --headless -s res://tools/sim_unlock_pacing.gd

const TRIALS := 30
const COMBAT_LI := [0, 1, 2, 3, 4, 5, 6]
const COMBAT_NODES_PER_PATROL := 6.67   # 12 POIs x 5/9
const BOSS_LI := [2, 4, 6]
const RECYCLE_MULT := 2.0               # recyclable-wave exposure multiplier (est.)

const TARGETS := {
	"enemy_z_s_shiv": "Stiletto  (Shiv, zealot-only)",
	"enemy_z_s_pilgrim": "Pilgrim   (Pilgrim, zealot-only)",
	"enemy_core_s_cobra": "Cobra     (Cobra, corpo+priv)",
	"enemy_core_s_falchion": "Falchion  (Falchion, priv-only)",
	"enemy_c_s_curve": "Weaver    (corp Weaver, corpo-only)",
	"enemy_c_s_hold": "Wraith    (Hold hull TOTAL — skirmish variants are a subset)",
	"enemy_s_s_hotrod": "Mongoose  (Lash/hotrod, supremacy-only)",
	"enemy_s_s_piercer": "Piercer   (Piercer, supremacy-only)",
}


func _initialize() -> void:
	var WaveGen = load("res://scripts/levels/wave_generator.gd")

	# avg[target][faction][li] = {raw, recyclable} initial spawns per level
	var combat_avg := {}
	var boss_avg := {}
	for t in TARGETS:
		combat_avg[t] = {}
		boss_avg[t] = {"raw": 0.0, "rec": 0.0}
		for f in 4:
			combat_avg[t][f] = {}
			for li in COMBAT_LI:
				combat_avg[t][f][li] = {"raw": 0.0, "rec": 0.0}

	var total_spawns := 0.0
	var total_levels := 0
	for f in 4:
		for li in COMBAT_LI:
			for _i in TRIALS:
				var level = WaveGen.build(1, li, false, f)
				total_levels += 1
				for w in level.waves:
					if w == null or w.enemy_scene == null:
						continue
					total_spawns += float(w.count)
					var nm: String = w.enemy_scene.resource_path.get_file().replace(".tscn", "")
					if combat_avg.has(nm):
						combat_avg[nm][f][li]["raw"] += float(w.count)
						if int(w.recycle_passes) != 0:
							combat_avg[nm][f][li]["rec"] += float(w.count)
		print("  faction %d done" % f)
	for t in TARGETS:
		for f in 4:
			for li in COMBAT_LI:
				combat_avg[t][f][li]["raw"] /= float(TRIALS)
				combat_avg[t][f][li]["rec"] /= float(TRIALS)

	# Boss lead-ins (faction -1 = unfiltered).
	for li in BOSS_LI:
		for _i in TRIALS:
			var level = WaveGen.build(1, li, true, -1)
			for w in level.waves:
				if w == null or w.enemy_scene == null:
					continue
				var nm: String = w.enemy_scene.resource_path.get_file().replace(".tscn", "")
				if boss_avg.has(nm):
					boss_avg[nm]["raw"] += float(w.count)
					if int(w.recycle_passes) != 0:
						boss_avg[nm]["rec"] += float(w.count)
	for t in TARGETS:
		boss_avg[t]["raw"] /= float(TRIALS)   # avg per patrol ACROSS the 3 boss levels (summed li's / trials)
		boss_avg[t]["rec"] /= float(TRIALS)

	print("\navg initial spawns per combat level (all types): %.1f" % (total_spawns / float(total_levels)))
	print("recycle multiplier applied to recyclable waves: x%.1f\n" % RECYCLE_MULT)

	var node_w: float = COMBAT_NODES_PER_PATROL / float(COMBAT_LI.size())
	print("%-58s %10s %10s" % ["hull (namesake)", "kills/run", "w/recycle"])
	for t in TARGETS:
		var per_run_raw := 0.0
		var per_run_amp := 0.0
		for li in COMBAT_LI:
			for f in 4:
				var raw: float = combat_avg[t][f][li]["raw"]
				var rec: float = combat_avg[t][f][li]["rec"]
				per_run_raw += 0.25 * raw * node_w
				per_run_amp += 0.25 * (raw + rec * (RECYCLE_MULT - 1.0)) * node_w
		per_run_raw += boss_avg[t]["raw"]
		per_run_amp += boss_avg[t]["raw"] + boss_avg[t]["rec"] * (RECYCLE_MULT - 1.0)
		print("%-58s %10.1f %10.1f" % [TARGETS[t], per_run_raw, per_run_amp])
	quit()
