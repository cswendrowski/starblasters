extends SceneTree

# Focused headless sim for the director's cohort clear-gate (COHORT_CLEAR_FRACTION). Drives
# _await_cohort_clear directly with a fabricated cohort, so it needs none of the wave producer.
# Run: Godot --headless --script tools/test_cohort_gate.gd

const DirectorC = preload("res://scripts/levels/director.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame   # let the SceneTree tick once so root + node lifecycle are live
	var d: Node = DirectorC.new()
	root.add_child(d)
	await process_frame   # let d actually enter the tree (get_tree() valid for _paced)
	d._running = true

	# --- Phase 1: gate holds until >= 51% of a 10-member cohort resolves ---
	d._cohort_id = 0
	d._cohorts = {0: {"spawned": 10, "resolved": 0}}
	var expected := int(ceil(10 * DirectorC.COHORT_CLEAR_FRACTION))  # ceil(5.1) = 6
	print("[test] cohort 0: 10 spawned, need >= %.1f resolved (first release at %d)" % [10 * DirectorC.COHORT_CLEAR_FRACTION, expected])
	# Background resolver: bump resolved by 1 every 0.2s.
	_tick_resolver(d, 0)
	await d._await_cohort_clear(0)
	var at := int(d._cohorts[0]["resolved"])
	print("[test] gate released at resolved=%d/10  VERDICT: %s" % [at, "PASS" if at == expected else "FAIL"])

	# --- Phase 2: anti-softlock timeout releases a loitering cohort that never resolves ---
	d._cohort_id = 1
	d._cohorts = {1: {"spawned": 8, "resolved": 0}}
	print("[test] cohort 1: 0/8 ever resolve, expecting timeout release near %.0fs" % DirectorC.COHORT_CLEAR_TIMEOUT)
	var t0 := Time.get_ticks_msec()
	await d._await_cohort_clear(1)
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	# Wall clock runs a little slower than the awaited 0.1 beats in headless; accept a loose band.
	var ok := dt >= DirectorC.COHORT_CLEAR_TIMEOUT and dt < DirectorC.COHORT_CLEAR_TIMEOUT + 4.0
	print("[test] timeout release after %.1fs (>=%.0f)  VERDICT: %s" % [dt, DirectorC.COHORT_CLEAR_TIMEOUT, "PASS" if ok else "FAIL"])

	# --- Phase 3: empty cohort (nothing spawned) never blocks ---
	d._cohorts = {2: {"spawned": 0, "resolved": 0}}
	var t1 := Time.get_ticks_msec()
	await d._await_cohort_clear(2)
	var dt2 := (Time.get_ticks_msec() - t1) / 1000.0
	print("[test] empty cohort released immediately (%.2fs)  VERDICT: %s" % [dt2, "PASS" if dt2 < 0.5 else "FAIL"])

	# --- Phase 4: no predecessor (id < 0) never blocks ---
	var t2 := Time.get_ticks_msec()
	await d._await_cohort_clear(-1)
	var dt3 := (Time.get_ticks_msec() - t2) / 1000.0
	print("[test] id<0 released immediately (%.2fs)  VERDICT: %s" % [dt3, "PASS" if dt3 < 0.5 else "FAIL"])

	quit()

func _tick_resolver(d: Node, cid: int) -> void:
	while d._cohorts.has(cid) and int(d._cohorts[cid]["resolved"]) < int(d._cohorts[cid]["spawned"]):
		await create_timer(0.2).timeout
		if not d._cohorts.has(cid):
			return
		d._cohorts[cid]["resolved"] = int(d._cohorts[cid]["resolved"]) + 1
