extends SceneTree

# Pacing model for a STREAMING combat level (Roman's direction, 2026-06-03):
# keep 5-8 waves per level, but each wave is a continuous trickle of enemies
# governed by a concurrency cap instead of the current clear-gate.
#
# A level has a total enemy BUDGET (target ~300). The director spawns one
# enemy every spawn_interval seconds AS LONG AS alive < concurrency_cap
# (back-pressure). The player clears at kill_rate enemies/sec.
#
# Key question this answers: for a given (cap, interval, kill_rate), is the
# level SPAWN-limited (sparse screen, duration ~= budget*interval) or
# KILL-limited (screen saturated at the cap, duration ~= budget/kill_rate)?
# Dense shmup feel needs spawn_rate >= kill_rate so the cap is the governor.
#
# Run: godot --headless -s tools/sim_stream.gd

const BUDGET := 300        # target enemies per level
const DT := 0.05           # sim tick (s)

var _out: FileAccess


func _initialize() -> void:
	_out = FileAccess.open("res://sim_stream_out.txt", FileAccess.WRITE)
	_emit("")
	_emit("=== Streaming-level pacing model — budget %d enemies/level ===" % BUDGET)
	_emit("    spawn_rate = 1/interval enemies/s ; kill_rate = enemies/s the player clears")
	_emit("    dense shmup feel = screen saturates at the cap (spawn_rate >= kill_rate)")
	_emit("")
	_emit("cap  interval  spawn/s  kill/s | duration(s)  min  peak  mean_alive  %@cap | regime")
	_emit("-----------------------------------------------------------------------------------------")

	for cap in [12, 16, 20]:
		for interval in [0.30, 0.45, 0.60]:
			for kill_rate in [2.0, 3.0, 4.0]:
				var r := _simulate(BUDGET, cap, interval, kill_rate)
				var spawn_rate: float = 1.0 / float(interval)
				var regime: String = "KILL-limited (dense)" if spawn_rate >= float(kill_rate) else "SPAWN-limited (sparse)"
				_emit("%3d   %.2f     %.2f    %.2f  | %8.0f   %4d %5d  %9.1f  %4.0f%% | %s" % [
					cap, interval, spawn_rate, kill_rate,
					r["duration"], 0, r["peak"], r["mean_alive"], r["pct_at_cap"], regime])
		_emit("-----------------------------------------------------------------------------------------")

	# Recommended config, broken out per-wave (6 waves, even-ish split).
	_emit("")
	_emit("--- Recommended starting point: cap=15, interval=0.40s, 6 waves, budget 300 ---")
	var rec := _simulate(BUDGET, 15, 0.40, 3.0)
	_emit("    @ kill_rate 3.0/s: duration %.0fs (%.1f min), peak alive %d, mean %.1f, %.0f%% saturated" % [
		rec["duration"], rec["duration"] / 60.0, rec["peak"], rec["mean_alive"], rec["pct_at_cap"]])
	var rec_slow := _simulate(BUDGET, 15, 0.40, 2.0)
	var rec_fast := _simulate(BUDGET, 15, 0.40, 4.5)
	_emit("    slow player (2.0/s): %.0fs (%.1f min), peak %d" % [rec_slow["duration"], rec_slow["duration"] / 60.0, rec_slow["peak"]])
	_emit("    fast player (4.5/s): %.0fs (%.1f min), peak %d" % [rec_fast["duration"], rec_fast["duration"] / 60.0, rec_fast["peak"]])
	_emit("    per-wave budget (6 waves): ~%d enemies/wave streamed (vs ~20 batch today)" % (BUDGET / 6))
	_emit("")

	# Density-targeting spawner: spawn whenever alive < cap (floor 0.20s to
	# prevent instant bursts). This decouples on-screen density from player
	# kill-rate — the screen stays populated regardless of how fast they clear,
	# and duration self-adjusts to ~budget/kill_rate.
	_emit("--- Density-targeting spawner (spawn-while-under-cap, 0.20s floor), cap=15 ---")
	_emit("kill/s | duration(s)  peak  mean_alive  %@cap")
	_emit("-------+-------------------------------------")
	for kr in [2.0, 3.0, 4.0, 5.0]:
		var d := _simulate_density(BUDGET, 15, 0.20, kr)
		_emit("%5.1f  | %8.0f   %4d  %9.1f  %4.0f%%" % [kr, d["duration"], d["peak"], d["mean_alive"], d["pct_at_cap"]])
	_emit("")

	if _out:
		_out.flush()
		_out.close()
	quit()


# Discrete-time back-pressure sim. Spawns at the interval cadence while
# alive < cap; player removes kill_rate/s. Runs until budget spent and screen
# clear. Returns duration, peak/mean concurrency, and % of time at the cap.
func _simulate(budget: int, cap: int, interval: float, kill_rate: float) -> Dictionary:
	var alive := 0
	var spawned := 0
	var spawn_acc := 0.0
	var kill_acc := 0.0
	var t := 0.0
	var peak := 0
	var sum_alive := 0.0
	var samples := 0
	var time_at_cap := 0.0
	while spawned < budget or alive > 0:
		# Spawn at cadence, gated by the concurrency cap (back-pressure).
		spawn_acc += DT
		while spawn_acc >= interval and spawned < budget and alive < cap:
			alive += 1
			spawned += 1
			spawn_acc -= interval
		# Don't bank spawn credit while blocked at the cap — resume at cadence.
		if alive >= cap:
			spawn_acc = minf(spawn_acc, interval)
		# Player clears. Kill progress only accrues against live targets — a
		# player can't bank kill credit on an empty screen.
		if alive > 0:
			kill_acc += kill_rate * DT
			while kill_acc >= 1.0 and alive > 0:
				alive -= 1
				kill_acc -= 1.0
		else:
			kill_acc = 0.0
		# Sample.
		peak = maxi(peak, alive)
		sum_alive += float(alive)
		samples += 1
		if alive >= cap:
			time_at_cap += DT
		t += DT
		if t > 2000.0:
			break  # safety
	return {
		"duration": t,
		"peak": peak,
		"mean_alive": sum_alive / float(maxi(1, samples)),
		"pct_at_cap": 100.0 * time_at_cap / maxf(DT, t),
	}


# Density-targeting variant: spawn whenever alive < cap, but no faster than
# the floor interval (anti-burst). Screen stays near the cap for any kill_rate
# below 1/floor; duration tracks budget/kill_rate.
func _simulate_density(budget: int, cap: int, floor_interval: float, kill_rate: float) -> Dictionary:
	var alive := 0
	var spawned := 0
	var spawn_acc := 0.0
	var kill_acc := 0.0
	var t := 0.0
	var peak := 0
	var sum_alive := 0.0
	var samples := 0
	var time_at_cap := 0.0
	while spawned < budget or alive > 0:
		spawn_acc += DT
		while spawn_acc >= floor_interval and spawned < budget and alive < cap:
			alive += 1
			spawned += 1
			spawn_acc -= floor_interval
		if alive >= cap:
			spawn_acc = minf(spawn_acc, floor_interval)
		if alive > 0:
			kill_acc += kill_rate * DT
			while kill_acc >= 1.0 and alive > 0:
				alive -= 1
				kill_acc -= 1.0
		else:
			kill_acc = 0.0
		peak = maxi(peak, alive)
		sum_alive += float(alive)
		samples += 1
		if alive >= cap:
			time_at_cap += DT
		t += DT
		if t > 2000.0:
			break
	return {
		"duration": t,
		"peak": peak,
		"mean_alive": sum_alive / float(maxi(1, samples)),
		"pct_at_cap": 100.0 * time_at_cap / maxf(DT, t),
	}


func _emit(line: String) -> void:
	print(line)
	if _out:
		_out.store_line(line)
