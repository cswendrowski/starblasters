extends SceneTree

# Headless driver for the outpost arrival sequence: instantiate OutpostArrival, run the
# arrival, then on `landed` fire depart() and confirm `departed` fires — exercising the
# full state machine (ARRIVING → LANDED → DEPARTING → GONE) without the dev-lab UI.

func _init() -> void:
	var oa = load("res://scenes/outpost_arrival.tscn").instantiate()
	oa.manage_hd_scope = true
	oa.return_to_map = false   # driver asserts on `departed`; don't navigate away
	oa.damage_level = 0.7   # exercise the damaged-launch path (stutter glow + spark spray)
	# Short timings so the flow completes quickly headless.
	oa.arrival_time = 0.4
	oa.bars_fade_time = 0.2
	oa.shadow_settle_time = 0.2
	oa.rise_time = 0.2
	oa.flyoff_time = 0.4
	oa.landed.connect(func() -> void:
		print("LANDED ok; departing")
		oa.depart())
	oa.departed.connect(func() -> void:
		print("DEPARTED ok")
		print("VERDICT: PASS")
		quit())
	get_root().add_child(oa)
	# Safety timeout so a stuck state machine fails loudly instead of hanging.
	var t := Timer.new()
	t.wait_time = 6.0
	t.one_shot = true
	t.autostart = true   # starts when it enters the tree (can't start() before add_child in _init)
	t.timeout.connect(func() -> void:
		print("VERDICT: FAIL (timeout, state=%d)" % oa.get_state())
		quit(1))
	get_root().add_child(t)
