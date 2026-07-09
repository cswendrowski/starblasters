extends SceneTree

# Sector Conditions core test (WP1). Covers catalog integrity, the generic
# aggregators, net-Threat / payout floors, mutex-respecting deterministic roll,
# and the Run autoload delegates.
# Run: godot --headless --script res://tools/test_conditions.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0

	# 1. Catalog integrity — validate() must return no problems, and there
	#    should be exactly 45 entries.
	var problems: Array = Conditions.validate()
	lines.append("validate() problems: %d %s" % [problems.size(), str(problems)])
	if problems.size() != 0:
		lines.append("FAIL validate() reported problems"); fails += 1
	lines.append("catalog size: %d" % Conditions.CATALOG.size())
	if Conditions.CATALOG.size() != 45:
		lines.append("FAIL expected 45 catalog entries, got %d" % Conditions.CATALOG.size()); fails += 1

	# 2a. scalar — product across two conditions sharing a mult key.
	#     heavy_ordnance (2.0) × weak_shields is not the same key; instead use
	#     two that share player.weapon_damage_mult is impossible (mutex), so
	#     build a hypothetical active list ignoring mutex for the math check.
	var mult_list: Array = ["heavy_ordnance", "weak_weapons"]
	# heavy_ordnance sets player.damage_taken_mult 2.0; weak_weapons doesn't →
	# scalar of damage_taken_mult should be 2.0.
	var dmg_mult: float = Conditions.scalar(mult_list, "player.damage_taken_mult")
	lines.append("scalar(damage_taken_mult)=%s" % str(dmg_mult))
	if not is_equal_approx(dmg_mult, 2.0):
		lines.append("FAIL expected 2.0"); fails += 1
	# Product of two that DO share a key: better_shields sets two mults; pair
	# it with more_ammo (ammo_max_mult) — check a genuine product on regen_rate.
	var prod_list: Array = ["better_shields", "better_weapons"]
	# better_shields regen_rate_mult 1.5, no other sets it → 1.5.
	var regen: float = Conditions.scalar(prod_list, "player.shield_regen_rate_mult")
	lines.append("scalar(regen_rate)=%s" % str(regen))
	if not is_equal_approx(regen, 1.5):
		lines.append("FAIL expected 1.5"); fails += 1
	# scalar default when unset.
	var missing: float = Conditions.scalar(["shielded"], "player.weapon_damage_mult", 1.0)
	if not is_equal_approx(missing, 1.0):
		lines.append("FAIL scalar default not honored (%s)" % str(missing)); fails += 1

	# 2b. sum — rung deltas. fast_enemies(+1) + slow_bullets(-1) sum on
	#     enemy.rung_delta = +1 (only fast_enemies sets enemy.rung_delta).
	var rung_list: Array = ["fast_enemies", "slow_bullets"]
	var enemy_rung: float = Conditions.sum(rung_list, "enemy.rung_delta")
	var bullet_rung: float = Conditions.sum(rung_list, "bullet.rung_delta")
	lines.append("sum(enemy.rung_delta)=%s sum(bullet.rung_delta)=%s" % [str(enemy_rung), str(bullet_rung)])
	if not is_equal_approx(enemy_rung, 1.0):
		lines.append("FAIL expected enemy rung +1"); fails += 1
	if not is_equal_approx(bullet_rung, -1.0):
		lines.append("FAIL expected bullet rung -1"); fails += 1

	# 2c. flag — glass_patrol sets player.glass_hull true.
	if not Conditions.flag(["glass_patrol"], "player.glass_hull"):
		lines.append("FAIL glass_hull flag not set"); fails += 1
	if Conditions.flag(["shielded"], "player.glass_hull"):
		lines.append("FAIL glass_hull flag falsely set"); fails += 1

	# 2d. union — pool.block_slots across no_primaries + no_modules.
	var union_list: Array = ["no_primaries", "no_modules"]
	var blocked: Array = Conditions.union(union_list, "pool.block_slots")
	lines.append("union(pool.block_slots)=%s" % str(blocked))
	if not (blocked.has("CANNON") and blocked.has("MODULE") and blocked.has("SHIFT_MODE") and blocked.size() == 3):
		lines.append("FAIL union of block_slots wrong"); fails += 1

	# 3. net_threat + payout floors.
	var mixed: Array = ["heavy_ordnance", "fast_enemies", "better_weapons"]  # 4 + 2 - 2 = 4
	var nt: int = Conditions.net_threat(mixed)
	lines.append("net_threat(mixed)=%d" % nt)
	if nt != 4:
		lines.append("FAIL expected net threat 4"); fails += 1
	var bm: float = Conditions.bounty_mult(mixed)
	var mm: float = Conditions.materials_mult(mixed)
	lines.append("bounty_mult=%s materials_mult=%s" % [str(bm), str(mm)])
	if not is_equal_approx(bm, 1.0 + Conditions.K_BOUNTY * 4.0):
		lines.append("FAIL bounty_mult math"); fails += 1
	if not is_equal_approx(mm, 1.0 + Conditions.K_MATERIALS * 4.0):
		lines.append("FAIL materials_mult math"); fails += 1
	# All-boon → net negative → payout floors at 1.0.
	var boons: Array = ["better_weapons", "faster_weapons", "salvage_rights"]
	lines.append("net_threat(boons)=%d bounty_mult=%s" % [Conditions.net_threat(boons), str(Conditions.bounty_mult(boons))])
	if Conditions.net_threat(boons) >= 0:
		lines.append("FAIL expected negative net threat for all-boon list"); fails += 1
	if not is_equal_approx(Conditions.bounty_mult(boons), 1.0):
		lines.append("FAIL bounty_mult should floor at 1.0"); fails += 1
	if not is_equal_approx(Conditions.materials_mult(boons), 1.0):
		lines.append("FAIL materials_mult should floor at 1.0"); fails += 1

	# 4. mutex — roll(45, seed) never returns two ids sharing a group; assert
	#    across 50 seeds. Also distinct ids + count respected.
	var mutex_ok := true
	var distinct_ok := true
	for s in range(50):
		var drawn: Array = Conditions.roll(45, 1000 + s * 31)
		var groups_seen: Dictionary = {}
		var ids_seen: Dictionary = {}
		for id in drawn:
			if ids_seen.has(id):
				distinct_ok = false
			ids_seen[id] = true
			var grp: String = String(Conditions.CATALOG[id].get("group", ""))
			if grp != "":
				if groups_seen.has(grp):
					mutex_ok = false
				groups_seen[grp] = true
	lines.append("roll: mutex_ok=%s distinct_ok=%s" % [str(mutex_ok), str(distinct_ok)])
	if not mutex_ok:
		lines.append("FAIL roll returned two ids in same mutex group"); fails += 1
	if not distinct_ok:
		lines.append("FAIL roll returned duplicate ids"); fails += 1
	# count respected (small count).
	var small: Array = Conditions.roll(5, 777)
	if small.size() != 5:
		lines.append("FAIL roll(5) returned %d ids" % small.size()); fails += 1

	# 5. determinism — roll(5, 1234) twice → identical.
	var a: Array = Conditions.roll(5, 1234)
	var b: Array = Conditions.roll(5, 1234)
	lines.append("determinism a=%s b=%s" % [str(a), str(b)])
	if a != b:
		lines.append("FAIL roll not deterministic"); fails += 1

	# 6. Run integration — delegates + new_run() clears.
	var run = root.get_node("/root/Run")
	run.active_conditions = ["heavy_ordnance", "glass_patrol"]
	if not run.has_condition("glass_patrol"):
		lines.append("FAIL Run.has_condition delegate"); fails += 1
	if not is_equal_approx(run.cond_scalar("player.damage_taken_mult"), 2.0):
		lines.append("FAIL Run.cond_scalar delegate"); fails += 1
	if not run.cond_flag("player.glass_hull"):
		lines.append("FAIL Run.cond_flag delegate"); fails += 1
	if run.condition_net_threat() != 9:  # 4 + 5
		lines.append("FAIL Run.condition_net_threat delegate (%d)" % run.condition_net_threat()); fails += 1
	run.new_run()
	if not run.active_conditions.is_empty():
		lines.append("FAIL new_run() did not clear active_conditions"); fails += 1

	# 7. Clarity.step_rung — the Fast/Slow Enemies|Bullets ladder-walker (Task 1). Creep half-rung is
	#    on the ladder; enemies floor at creep, bullets floor at one rung (60). Cap at 480 (rung 8).
	var sr_creep_up: float = Clarity.step_rung(Clarity.CREEP_SPEED, 1)          # 30 -> crawl 60
	var sr_crawl_down: float = Clarity.step_rung(60.0, -1)                       # 60 -> creep 30
	var sr_max_up: float = Clarity.step_rung(Clarity.ABS_MAX_SPEED, 1)          # 480 -> 480 (clamped)
	var sr_mid_up: float = Clarity.step_rung(300.0, 1)                          # 300 -> 360
	var sr_bullet_floor: float = Clarity.step_rung(Clarity.CREEP_SPEED, -1, Clarity.RUNG_STEP)  # 30 -> floored to 60
	lines.append("step_rung: creep+1=%s crawl-1=%s max+1=%s 300+1=%s bulletfloor=%s" \
		% [str(sr_creep_up), str(sr_crawl_down), str(sr_max_up), str(sr_mid_up), str(sr_bullet_floor)])
	if not is_equal_approx(sr_creep_up, 60.0):
		lines.append("FAIL step_rung creep+1 expected 60 got %s" % str(sr_creep_up)); fails += 1
	if not is_equal_approx(sr_crawl_down, 30.0):
		lines.append("FAIL step_rung crawl-1 expected 30 got %s" % str(sr_crawl_down)); fails += 1
	if not is_equal_approx(sr_max_up, 480.0):
		lines.append("FAIL step_rung max+1 expected 480 got %s" % str(sr_max_up)); fails += 1
	if not is_equal_approx(sr_mid_up, 360.0):
		lines.append("FAIL step_rung 300+1 expected 360 got %s" % str(sr_mid_up)); fails += 1
	if not is_equal_approx(sr_bullet_floor, 60.0):
		lines.append("FAIL step_rung bullet floor expected 60 got %s" % str(sr_bullet_floor)); fails += 1

	lines.append("CONDITIONS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
