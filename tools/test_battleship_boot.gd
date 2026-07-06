extends SceneTree

# Headless boot + mechanic smoke for the Zealot Battleship (Roman 2026-07-01, director-synchronized
# maneuver build). Confirms: 64-HP turret shells (bench-configurable EnemyTurrets) + the authored laser
# instances (1 MainLaser @300HP + 4 SideLaser @64HP, glow-primed, main laser FRIENDLY-FIRE), the
# maneuver model (idles off-screen; play_wave_maneuver picks an eligible maneuver; laser maneuvers gate
# on the main laser; blockade side pick), the firing gate, laser destroy→husk (damaged frame, no free,
# flip on …B), the friendly-fire beam (hits player + enemies, spares the owner's own parts), and both
# exits: destroy every part → is_defeated (dramatic death) / retreat → is_defeated. Node _ready +
# start() run synchronously, so no frame-ticking is needed (the live beams/maneuvers are soaked in
# test_battleship_run.gd; the wave gate is proven in test_battleship_gate.gd).
# Run: godot --headless --path . -s tools/test_battleship_boot.gd

const SCENE := "res://scenes/enemies/factions/zealot/boss_z_battleship.tscn"
const MountSpecScript = preload("res://scripts/enemies/mounts/mount_spec.gd")
const FirecoreScript = preload("res://scripts/enemies/firecore_hazard.gd")
const BeamEmitterScript = preload("res://scripts/enemies/beam_emitter.gd")

var _fails: int = 0


# Minimal damage sinks for the friendly-fire beam check.
class FakePlayer extends Node2D:
	var hull: int = 100
	var hits: int = 0
	func take_damage(d: int) -> void:
		hull -= d
		hits += 1

class FakeEnemy extends Node2D:
	var hits: int = 0
	func take_hit(d: int = 1) -> bool:
		hits += 1
		return false


func _init() -> void:
	process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)


func _run() -> void:
	var mus = get_root().get_node_or_null("Music")
	if mus != null:
		mus.free()
	var world := Node2D.new()
	world.add_to_group("bullet_world")
	get_root().add_child(world)

	var ps := load(SCENE) as PackedScene
	if ps == null:
		print("  FAIL: could not load %s" % SCENE)
		quit(1)
		return
	var boss = ps.instantiate()
	get_root().add_child(boss)

	# --- Turret shells ------------------------------------------------------------
	_ck(boss.monitorable == false, "hull is pass-through (monitorable=false)")
	var turret_markers: int = boss.find_children("Turret*", "Marker2D", true, false).size()
	var turret_shells: int = 0
	var turret_hp_ok: bool = true
	var turret_nodes: int = 0
	for p in boss.live_parts():
		if String(p.get_meta("kind", "")) != "turret":
			continue
		turret_shells += 1
		if int(p.max_hp) != 64:
			turret_hp_ok = false
		for c in p.get_children():
			if c is EnemyTurret:
				turret_nodes += 1
	_ck(turret_shells == turret_markers and turret_shells > 0, "one turret shell per Turret* marker (%d)" % turret_shells)
	_ck(turret_hp_ok, "turret shells are 64 HP")
	_ck(turret_nodes == turret_shells, "every turret shell carries a (bench-configurable) EnemyTurret")
	var turret_tells: bool = not boss.live_parts().is_empty()
	for p in boss.live_parts():
		if String(p.get_meta("kind", "")) == "turret" and p._tells == null:
			turret_tells = false
	_ck(turret_tells, "turrets get damage tells (overlay + spark trail)")
	var st_shell = null
	for p in boss.live_parts():
		if String(p.get_meta("kind", "")) == "turret":
			st_shell = p
			break
	if st_shell != null:
		var hp0: int = int(st_shell.hp)
		st_shell.take_smart_bomb(100)   # 100 raw dmg, cap 20 → survives
		_ck(int(st_shell.hp) == hp0 - 20 and not st_shell._destroyed, "turret caps smart-bomb damage at 20 (took %d, alive)" % (hp0 - int(st_shell.hp)))
	var fc_z_ok: bool = true
	for c in boss.find_children("FireCore*", "", false, false):
		if c is CanvasItem and (c as CanvasItem).z_index != 0:
			fc_z_ok = false
	_ck(fc_z_ok, "decorative firecores dropped to z_index 0 (no longer over the player)")

	# --- Authored laser instances (1 main + 4 side) -------------------------------
	print("lasers discovered=%d  side=%d  main=%s" % [boss._lasers.size(), boss._side_lasers.size(), str(boss._main_laser != null)])
	_ck(boss._main_laser != null, "MainLaser instance discovered")
	_ck(boss._side_lasers.size() == 4, "four SideLaser instances discovered")
	if boss._main_laser != null:
		_ck(String(boss._main_laser.beam_kind) == "main", "main laser beam_kind=main")
		_ck(int(boss._main_laser.part_hp) == 300, "main laser is 300 HP")
		_ck(boss._main_laser._beam.telegraph_width > 0.0, "main laser paints a lane warning (telegraph on)")
		_ck(int(boss._main_laser._beam.endpoint) == 0, "main laser fires as a RAY (from start toward the muzzle)")
		_ck(boss._main_laser._beam.forward_local.y < -0.5, "main laser aims from BeamStart toward BeamMuzzle")
		_ck(boss._main_laser.beam_duration() > 0.0, "main laser has a warn→fire→vanish cycle (%.1fs)" % boss._main_laser.beam_duration())
		_ck(boss._main_laser.beam_windup() > 0.0, "main laser exposes its windup (for the sweep warning)")
		_ck(int(boss._main_laser.smart_bomb_cap) == 8, "main laser takes the LEAST smart-bomb damage (cap 8)")
		# FRIENDLY-FIRE: the main laser blows up the player AND enemies, excluding the boss's own parts.
		_ck(bool(boss._main_laser._beam.friendly_fire), "main laser beam is friendly-fire (player + enemies)")
		_ck(boss._main_laser._beam.ignore_owner == boss, "main laser friendly-fire excludes the boss (ignore_owner=boss)")
		_ck(bool(boss._main_laser._beam.envelope), "main laser uses the grow/shrink/flicker width envelope")
	var side_hp_ok: bool = not boss._side_lasers.is_empty()
	var glow_ok: bool = true
	var side_ff_off: bool = true
	var flipped: int = 0
	for l in boss._side_lasers:
		if int(l.part_hp) != 64:
			side_hp_ok = false
		var cm = l.get_node_or_null("ChargeMask")
		if cm == null or cm.visible or l._glow.r <= 1.5 or int(cm.frame) != 2:
			glow_ok = false
		if l._beam.friendly_fire:
			side_ff_off = false
		if l.flip_when_destroyed:
			flipped += 1
	_ck(side_hp_ok, "side lasers are 64 HP")
	_ck(glow_ok, "lasers primed: ChargeMask on the glow frame, hidden, HDR-glow")
	_ck(side_ff_off, "side lasers stay player-targeted (NOT friendly-fire)")
	_ck(flipped == 2, "one …B side laser per side flips when destroyed (%d/4)" % flipped)

	var total_parts: int = boss.live_parts().size()
	_ck(total_parts == turret_shells + 5, "all parts registered: %d turrets + 5 lasers = %d" % [turret_shells, total_parts])

	# --- Spawn (placed where start() puts it; the Bench uses this to show the boss) + IDLE park --------
	boss.start(Vector2(240.0, 100.0))
	_ck(not boss.is_defeated(), "fresh boss is not defeated")
	_ck(boss.position.is_equal_approx(Vector2(240.0, 100.0)), "start() places the boss where told (Bench-visible), no forced idle")
	boss._go_idle()   # the between-maneuvers park: off-screen below, not firing
	_ck(boss.position.y > boss.get_viewport_rect().size.y, "_go_idle parks the boss BELOW the screen")
	_ck(not boss._firing_enabled, "_go_idle holds fire")

	# --- Turret firing gate -------------------------------------------------------
	var t0 = boss._turrets[0] if not boss._turrets.is_empty() else null
	if t0 != null:
		boss.rotation = 0.0
		boss.position = Vector2(240.0, 56.0)
		boss._firing_enabled = false
		boss._update_turret_gate()
		_ck(not t0.enabled, "turret holds fire when firing disabled")
		boss._firing_enabled = true
		boss._update_turret_gate()
		_ck(t0.enabled, "turret fires when enabled + on-screen")
		var barrel: Sprite2D = null
		for c in t0.get_children():
			if c is Sprite2D:
				barrel = c
		boss._depth = 1.0   # deep background
		boss._apply_depth()
		_ck(barrel != null and barrel.modulate.is_equal_approx(boss.BG_TINT), "depth shading tints the turret barrels")
		boss._depth = 0.0
		boss._apply_depth()

	# --- Friendly-fire beam: hits player + enemies, spares the beam owner's own parts ---
	_run_friendly_fire_check()

	# --- Physics pilot: STRAFE to a lateral target while HOLDING heading (tick the integrator by hand) ---
	var b5 = ps.instantiate()
	get_root().add_child(b5)
	b5.start(Vector2(240.0, 400.0))
	b5.position = Vector2(200.0, 150.0)
	b5.rotation = PI                # facing DOWN
	b5._vel = Vector2.ZERO
	b5._ang_vel = 0.0
	b5._tgt_pos = Vector2(300.0, 150.0)   # directly to the RIGHT — a pure sideways move
	b5._tgt_heading = PI            # HOLD facing down (must strafe, not turn)
	b5._tgt_depth = 0.0
	b5._tgt_mode = b5.M_FLY
	var min_throttle: float = 999.0
	for i in 1200:
		b5._integrate_physics(1.0 / 60.0)
		min_throttle = minf(min_throttle, float(b5._cmd_throttle))
	var off: float = b5.position.distance_to(Vector2(300.0, 150.0))
	_ck(off < 45.0, "pilot STRAFES to a lateral target (%.0f px off)" % off)
	_ck(absf(wrapf(PI - b5.rotation, -PI, PI)) < 0.2, "heading HELD while strafing (didn't turn to travel: %.2f off)" % absf(wrapf(PI - b5.rotation, -PI, PI)))
	_ck(min_throttle >= 0.0, "main thrust is forward-only (throttle never < 0 — no reverse)")
	# depth axis: top thrusters dive it in, releasing surfaces it
	b5._tgt_depth = 1.0
	for i in 300:
		b5._integrate_physics(1.0 / 60.0)
	_ck(b5._depth > 0.8, "top thrusters dive it into the background (depth→%.2f)" % b5._depth)
	b5._tgt_depth = 0.0
	for i in 300:
		b5._integrate_physics(1.0 / 60.0)
	_ck(b5._depth < 0.2, "releasing surfaces it back to the foreground (depth→%.2f)" % b5._depth)
	b5.free()

	# --- Maneuver eligibility (fresh instance) ------------------------------------
	var b3 = ps.instantiate()
	get_root().add_child(b3)
	b3.start(Vector2(240.0, 400.0))
	_ck(b3._main_laser_alive(), "fresh boss: main laser alive")
	_ck(b3._blockade_side() >= 0, "fresh boss: a blockade side is available (side %d)" % b3._blockade_side())
	var laser_seen := false
	var all_valid := true
	for i in 60:
		var m: String = b3._pick_maneuver()
		if not (m in ["hook_firecores", "hook_laser", "hook_blockade", "firecore_slide", "laser_slide", "lane_laser"]):
			all_valid = false
		if m == "hook_laser" or m == "laser_slide" or m == "lane_laser":
			laser_seen = true
	_ck(all_valid, "picked maneuvers are always from the eligible set")
	_ck(laser_seen, "laser maneuvers are eligible while the main laser lives")
	# Kill the main laser → laser maneuvers must drop out of the pool.
	b3._main_laser.destroy()
	_ck(not b3._main_laser_alive(), "main laser reported dead after destroy")
	var laser_after := false
	for i in 60:
		var m: String = b3._pick_maneuver()
		if m == "hook_laser" or m == "laser_slide" or m == "lane_laser":
			laser_after = true
	_ck(not laser_after, "no laser maneuvers once the main laser is destroyed")
	# Blockade side pick: destroy both RIGHT side lasers → the fuller side is LEFT (0).
	for l in b3._side_lasers.duplicate():
		if is_instance_valid(l) and (l as Node2D).position.x > 0.0:
			l.destroy()
	_ck(b3._blockade_side() == 0, "blockade picks the side with more side-lasers (left after right pair lost)")
	b3.free()

	# --- Laser destroy → wrecked husk (damaged frame, no free, flip) --------------
	var victim = null
	for l in boss._side_lasers:
		if l.flip_when_destroyed:
			victim = l
			break
	if victim != null:
		victim.destroy()
		_ck(is_instance_valid(victim), "destroyed laser stays as a husk (not freed)")
		_ck(victim.is_destroyed(), "destroyed laser flagged _destroyed")
		_ck(int(victim.get_node("Hull").frame) == 1, "destroyed laser hull → damaged frame")
		_ck(victim.get_node("Hull").material == null, "destroyed laser drops the damage shader (clean damaged frame)")
		_ck(victim.get_node("Hull").flip_h, "…B laser hull flips when destroyed")
		_ck(not (victim in boss.live_parts()), "destroyed laser dropped from live_parts")

	# --- Bench mount-spec still drives the turret build ---------------------------
	var boss2 = ps.instantiate()
	var spec = MountSpecScript.new()
	spec.kind = MountSpecScript.Kind.TURRET
	spec.marker = "Turret*"
	spec.fire_interval_min = 0.42
	spec.fire_interval_max = 0.42
	spec.turret_texture = load("res://graphics/enemies/zealot-tank-turret.png")
	spec.turret_hframes = 3
	boss2.mounts = [spec]
	get_root().add_child(boss2)
	var custom_ok: bool = false
	for p in boss2.live_parts():
		for c in p.get_children():
			if c is EnemyTurret and absf((c as EnemyTurret).fire_interval_min - 0.42) < 0.001:
				custom_ok = true
	_ck(custom_ok, "configured turret MountSpec drives the built turrets")
	boss2.free()

	# --- Firecore release scatters in an OUTWARD fan by world x-offset (no twist) --
	boss.rotation = 0.0
	boss.position = Vector2(240.0, 60.0)
	boss._release_firecores(Vector2.DOWN)
	var cores_spawned: int = 0
	var fanned: int = 0
	var mid_depth: int = 0
	var left_core_x: float = 9999.0
	var right_core_x: float = -9999.0
	var left_burst_x: float = 0.0
	var right_burst_x: float = 0.0
	for c in world.get_children():
		if c.get_script() == FirecoreScript:
			cores_spawned += 1
			if c.burst_velocity.length() > 1.0:
				fanned += 1
			if int(c.z_index) < -1:
				mid_depth += 1
			if c.global_position.x < left_core_x:
				left_core_x = c.global_position.x
				left_burst_x = c.burst_velocity.x
			if c.global_position.x > right_core_x:
				right_core_x = c.global_position.x
				right_burst_x = c.burst_velocity.x
	_ck(cores_spawned > 0, "firecores released (%d)" % cores_spawned)
	_ck(fanned == cores_spawned, "every released firecore gets a scatter burst")
	_ck(mid_depth == cores_spawned, "released firecores sit at mid-depth z (behind the player)")
	_ck(left_burst_x < right_burst_x, "firecores fan OUTWARD by world x (left→down-left, right→down-right; no twist)")
	# Salvo count grows per firecore pass (1, then 2, …) — _launch_firecore_salvos increments synchronously.
	var passes0: int = int(boss._firecore_passes)
	boss._launch_firecore_salvos(1.0)
	_ck(int(boss._firecore_passes) == passes0 + 1, "each firecore launch counts a pass (widening volley)")

	# --- Under-layer z + body pin -------------------------------------------------
	_ck(int(boss.z_index) < -1, "boss sits at an under-layer z (%d, behind the player trail's -1)" % int(boss.z_index))
	const PLAYER_SHOT_Z := -1
	var body_ok := true
	for bn in ["Hull", "GlowMask"]:
		var bs := boss.get_node_or_null(bn) as CanvasItem
		if bs == null or bs.z_as_relative or int(bs.z_index) >= PLAYER_SHOT_Z:
			body_ok = false
	_ck(body_ok, "hull body sprites pinned absolute z < player-shot z=-1 (player shots draw over the body)")

	# --- Hull collision disabled (only the parts stop shots) ----------------------
	var hull_solid := false
	for c in boss.get_children():
		if (c is CollisionShape2D or c is CollisionPolygon2D) and not c.disabled:
			hull_solid = true
	_ck(not hull_solid, "hull collision shape disabled (player shots pass the hull, hit the parts)")

	# --- HP bar tracks aggregate part HP (not the cosmetic 1200) ------------------
	_ck(int(boss.max_health) == int(boss._parts_max_total) and int(boss._parts_max_total) > 1000,
		"HP-bar max = total part HP (%d, not the cosmetic hull max)" % int(boss._parts_max_total))
	boss._update_health_bar()   # recompute from live parts (the main + a side laser were destroyed above)
	_ck(int(boss.health) < int(boss.max_health), "HP bar drops as parts die (%d/%d)" % [int(boss.health), int(boss.max_health)])

	# --- Retreat exit (survive the waves): stops + frees, reports defeated ---------
	var b4 = ps.instantiate()
	get_root().add_child(b4)
	b4.start(Vector2(240.0, 400.0))
	b4.retreat()   # coroutine: sets _dying synchronously before its first await
	_ck(b4.is_defeated(), "retreat() marks the boss defeated (survive-the-waves exit)")

	# --- Defeat exit (destroy EVERY part) → is_defeated (dramatic death) ----------
	for p in boss.live_parts().duplicate():
		if is_instance_valid(p):
			p.destroy()
	_ck(boss.live_parts().is_empty(), "all parts destroyed")
	_ck(boss.is_defeated(), "defeated (all parts gone) → death sequence marks is_defeated")

	print("VERDICT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


# Build a friendly-fire beam over a fixed segment with a fake player, a fake enemy, and a fake part
# parented UNDER the owner; confirm the player + enemy take damage but the owner's own part does not.
func _run_friendly_fire_check() -> void:
	var owner_node := Node2D.new()
	get_root().add_child(owner_node)
	var fb = BeamEmitterScript.new()
	fb.friendly_fire = true
	fb.ignore_owner = owner_node
	fb.target_group = "player"
	fb.endpoint = BeamEmitterScript.Endpoint.SEGMENT
	fb.pierce = true
	fb.dps = 100.0
	fb.hit_radius = 20.0
	owner_node.add_child(fb)
	fb.set_segment(Vector2(100, 0), Vector2(100, 200))
	var fp := FakePlayer.new()
	fp.add_to_group("player")
	get_root().add_child(fp)
	fp.global_position = Vector2(100, 50)
	var fe := FakeEnemy.new()
	fe.add_to_group("enemies")
	get_root().add_child(fe)
	fe.global_position = Vector2(100, 100)
	var own := FakeEnemy.new()      # the boss's own part: in "enemies" AND under the owner → must be spared
	own.add_to_group("enemies")
	owner_node.add_child(own)
	own.global_position = Vector2(100, 30)
	fb._apply_damage(1.0)   # dps 100 × 1s = 100 dmg to everything on the segment (except the owner's parts)
	_ck(fp.hits > 0, "friendly-fire beam damages the player")
	_ck(fe.hits > 0, "friendly-fire beam damages enemies too")
	_ck(own.hits == 0, "friendly-fire beam spares the beam owner's own parts (ignore_owner)")
	owner_node.free()
	fp.free()
	fe.free()
