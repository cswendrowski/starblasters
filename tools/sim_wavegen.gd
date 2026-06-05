extends SceneTree

# Headless Monte-Carlo of the production wave generator.
#
# WaveGenerator.build() seeds deterministically per (sector_depth, level_index,
# is_boss), so a given map node always yields the identical level. The real
# spread is in what the formula *could* roll at each coordinate — so we call the
# rng-injectable internals (_build_combat_waves / _build_boss_waves) directly
# with fresh seeds to sample the distribution.
#
# Run: godot --headless -s tools/sim_wavegen.gd  [trials]
#
# Reports, per coordinate:
#   total   = sum of every wave.count in the level (enemies you face all level)
#   peak    = largest single wave.count (clarity/concurrency-critical — the
#             director is clear-gated, so peak ≈ max enemies alive at once)
#   waves   = number of WaveSpecs emitted (mixed waves emit 2)

const WaveGen = preload("res://scripts/levels/wave_generator.gd")

const SECTOR_DEPTHS := [1, 2, 3, 4, 5]
const LEVEL_INDICES := [0, 1, 2, 3, 4, 5, 6]
const BOSS_LEVEL_INDEX := 4  # representative combats_in_sector when boss is reached

var _trials := 3000
var _out: FileAccess


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		_trials = args[0].to_int()

	_out = FileAccess.open("res://sim_out.txt", FileAccess.WRITE)

	_emit("")
	_emit("=== Starblaster wavegen distribution — %d trials/coordinate ===" % _trials)
	_emit("    total = enemies faced across the whole level")
	_emit("    peak  = largest single wave (≈ max alive at once, clear-gated)")
	_emit("")

	_run_combat_table()
	_run_boss_table()
	_run_300_probe()

	if _out:
		_out.flush()
		_out.close()
	quit()


func _emit(line: String) -> void:
	print(line)
	if _out:
		_out.store_line(line)


# --- combat levels -----------------------------------------------------------

func _run_combat_table() -> void:
	_emit("--- STANDARD COMBAT levels ---")
	_emit("sd  li | waves(p50) | total: min  p50  mean  p95  max | peak: p50  max")
	_emit("-------+------------+----------------------------------+---------------")
	for sd in SECTOR_DEPTHS:
		for li in LEVEL_INDICES:
			var totals: Array = []
			var peaks: Array = []
			var wavecounts: Array = []
			for t in _trials:
				var rng := RandomNumberGenerator.new()
				rng.seed = _seed(sd, li, t, 0)
				var waves: Array = WaveGen._build_combat_waves(rng, sd, li)
				var total := 0
				var peak := 0
				for w in waves:
					total += int(w.count)
					peak = maxi(peak, int(w.count))
				totals.append(total)
				peaks.append(peak)
				wavecounts.append(waves.size())
			_print_row(sd, li, wavecounts, totals, peaks)
		_emit("-------+------------+----------------------------------+---------------")


# --- boss levels -------------------------------------------------------------

func _run_boss_table() -> void:
	_emit("")
	_emit("--- BOSS levels (lead-in chaff + 1 boss) at li=%d ---" % BOSS_LEVEL_INDEX)
	_emit("sd | waves(p50) | total: min  p50  mean  p95  max | peak: p50  max")
	_emit("---+------------+----------------------------------+---------------")
	for sd in SECTOR_DEPTHS:
		var totals: Array = []
		var peaks: Array = []
		var wavecounts: Array = []
		for t in _trials:
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed(sd, BOSS_LEVEL_INDEX, t, 1)
			var waves: Array = WaveGen._build_boss_waves(rng, sd, BOSS_LEVEL_INDEX)
			var total := 0
			var peak := 0
			for w in waves:
				total += int(w.count)
				peak = maxi(peak, int(w.count))
			totals.append(total)
			peaks.append(peak)
			wavecounts.append(waves.size())
		var s_total := _stats(totals)
		var s_peak := _stats(peaks)
		var s_waves := _stats(wavecounts)
		_emit("%2d | %5d      | %4d %4d %5.1f %4d %4d | %4d %4d" % [
			sd, s_waves["p50"],
			s_total["min"], s_total["p50"], s_total["mean"], s_total["p95"], s_total["max"],
			s_peak["p50"], s_peak["max"]])


# --- how far can the current dials reach? ------------------------------------

func _run_300_probe() -> void:
	_emit("")
	_emit("--- Reach probe: deepest standard coordinate (sd=5, li=6) ---")
	var totals: Array = []
	var peaks: Array = []
	for t in _trials:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(5, 6, t, 2)
		var waves: Array = WaveGen._build_combat_waves(rng, 5, 6)
		var total := 0
		var peak := 0
		for w in waves:
			total += int(w.count)
			peak = maxi(peak, int(w.count))
		totals.append(total)
		peaks.append(peak)
	var s := _stats(totals)
	var sp := _stats(peaks)
	_emit("    total  min=%d p50=%d mean=%.1f p95=%d max=%d" % [s["min"], s["p50"], s["mean"], s["p95"], s["max"]])
	_emit("    peak   min=%d p50=%d max=%d" % [sp["min"], sp["p50"], sp["max"]])
	_emit("    => current absolute ceiling is ~%d/level; target 300 is ~%.1fx the p50." % [s["max"], 300.0 / float(maxi(1, s["p50"]))])
	_emit("")


# --- helpers -----------------------------------------------------------------

func _print_row(sd: int, li: int, wavecounts: Array, totals: Array, peaks: Array) -> void:
	var s_total := _stats(totals)
	var s_peak := _stats(peaks)
	var s_waves := _stats(wavecounts)
	_emit("%2d  %2d | %5d      | %4d %4d %5.1f %4d %4d | %4d %4d" % [
		sd, li, s_waves["p50"],
		s_total["min"], s_total["p50"], s_total["mean"], s_total["p95"], s_total["max"],
		s_peak["p50"], s_peak["max"]])


func _stats(arr: Array) -> Dictionary:
	var a := arr.duplicate()
	a.sort()
	var n := a.size()
	var sum := 0.0
	for v in a:
		sum += float(v)
	return {
		"min": a[0],
		"p50": a[int(n * 0.50)],
		"p95": a[mini(n - 1, int(n * 0.95))],
		"max": a[n - 1],
		"mean": sum / float(n),
	}


func _seed(sd: int, li: int, trial: int, kind: int) -> int:
	# Deterministic-but-varied per trial so the sim itself is reproducible.
	return trial * 2654435761 + sd * 40503 + li * 19349663 + kind * 83492791
