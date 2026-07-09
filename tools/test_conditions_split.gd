extends SceneTree

# Sector Conditions — roll_split() test (the Random/Blind bane+boon front-end
# helper). Covers determinism, sign correctness (banes = Threat>0, boons =
# Threat<0), combined-pick mutex (a shared used-groups dict spans both draws, so
# an inverse pair never appears as bane+boon), count clamping (over-ask never
# crashes + stays mutex-legal), and the zero-count no-op.
# Run: godot --headless --script res://tools/test_conditions_split.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0

	# 1. Determinism — same args + seed → identical list, several seeds.
	var det_ok := true
	for s in [1, 4242, 99999, -7]:
		var a: Array = Conditions.roll_split(3, 2, s)
		var b: Array = Conditions.roll_split(3, 2, s)
		if a != b:
			det_ok = false
			lines.append("FAIL non-deterministic at seed %d: %s vs %s" % [s, str(a), str(b)])
	lines.append("determinism = %s" % str(det_ok))
	if not det_ok:
		fails += 1

	# 2. Sign correctness — the first bane_count are Threat>0, the rest Threat<0.
	var sign_ok := true
	for s in range(30):
		var seed_v := 1000 + s * 31
		var bane_n := 3
		var boon_n := 2
		var res: Array = Conditions.roll_split(bane_n, boon_n, seed_v)
		# Because of mutex clamping the pool may yield fewer than asked; count how many
		# banes actually landed (they're drawn first) and verify the split boundary.
		var banes := 0
		for id in res:
			if Conditions.threat_of(id) > 0:
				banes += 1
			elif Conditions.threat_of(id) == 0:
				sign_ok = false   # a Threat-0 id must never enter either pool
		# banes are drawn first, so every Threat>0 must precede every Threat<0.
		var seen_boon := false
		for id in res:
			if Conditions.threat_of(id) < 0:
				seen_boon = true
			elif seen_boon and Conditions.threat_of(id) > 0:
				sign_ok = false   # a bane after a boon = wrong ordering
	lines.append("sign+ordering over 30 seeds = %s" % str(sign_ok))
	if not sign_ok:
		lines.append("FAIL roll_split sign/ordering broken"); fails += 1

	# 3. Combined-pick mutex across 30 seeds — one shared used-groups dict, so no
	#    two ids in the whole result share a nonempty mutex group.
	var mutex_ok := true
	for s in range(30):
		var res: Array = Conditions.roll_split(4, 4, 7000 + s * 13)
		var groups: Dictionary = {}
		for id in res:
			var grp := Conditions.group_of(id)
			if grp != "":
				if groups.has(grp):
					mutex_ok = false
				groups[grp] = true
	lines.append("combined mutex over 30 seeds = %s" % str(mutex_ok))
	if not mutex_ok:
		lines.append("FAIL roll_split let two ids share a mutex group"); fails += 1

	# 4. Count clamping — asking for 99/99 must not crash + stays mutex-legal, and
	#    can't exceed the sign pools.
	var big: Array = Conditions.roll_split(99, 99, 12345)
	var big_banes := 0
	var big_boons := 0
	var big_groups: Dictionary = {}
	var big_mutex_ok := true
	for id in big:
		if Conditions.threat_of(id) > 0:
			big_banes += 1
		elif Conditions.threat_of(id) < 0:
			big_boons += 1
		var grp := Conditions.group_of(id)
		if grp != "":
			if big_groups.has(grp):
				big_mutex_ok = false
			big_groups[grp] = true
	lines.append("clamp 99/99 -> total=%d banes=%d boons=%d mutex_ok=%s" % [
		big.size(), big_banes, big_boons, str(big_mutex_ok)])
	if not big_mutex_ok:
		lines.append("FAIL over-ask produced a mutex clash"); fails += 1
	# No duplicates.
	var seen: Dictionary = {}
	for id in big:
		if seen.has(id):
			lines.append("FAIL duplicate id '%s' in clamp result" % id); fails += 1
		seen[id] = true

	# 5. Zero counts -> empty.
	var z0: Array = Conditions.roll_split(0, 0, 555)
	var zb: Array = Conditions.roll_split(0, 3, 555)   # boons only
	var zg: Array = Conditions.roll_split(3, 0, 555)   # banes only
	lines.append("zero=%d boons-only=%d banes-only=%d" % [z0.size(), zb.size(), zg.size()])
	if not z0.is_empty():
		lines.append("FAIL 0/0 not empty"); fails += 1
	for id in zb:
		if Conditions.threat_of(id) >= 0:
			lines.append("FAIL boons-only drew a non-boon"); fails += 1
	for id in zg:
		if Conditions.threat_of(id) <= 0:
			lines.append("FAIL banes-only drew a non-bane"); fails += 1

	lines.append("CONDITIONS_SPLIT: " + ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
