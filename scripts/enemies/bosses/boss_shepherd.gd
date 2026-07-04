extends "res://scripts/enemies/bosses/boss_base.gd"

# The SHEPHERD — zealot capital miniboss and the TESTBED for the standardized boss
# encounter state machine (docs/design/boss_encounter_system.md).
#
# Weapon rules (Roman 2026-06-16):
#   - The TURRETS do ALL cannon fire and run in every combat phase (1 / 1.5 / 3);
#     volume falls off naturally as turrets are lost. They hold fire only in the
#     Phase 2 missile-cruiser interlude.
#   - The LauncherL/R points fire ROCKETS, only in Phase 3 (the boss flips to face
#     the player). Rockets are a separate weapon from the turret cannons.
#   - Phase 2 = an UNTOUCHABLE missile-cruiser interlude: the hull drops into the
#     pseudo-parallax (faked mid-depth) layer and runs the shared MissileSalvo area
#     attack (reused from missile_cruiser.gd).
#
# Spec: docs/design/Boss - Shepherd.md. Cadences/counts are first-pass; tune in the bench.

const TurretPart = preload("res://scripts/enemies/bosses/boss_turret_part.gd")
const TurretTex = preload("res://graphics/enemies/zealot-tank-turret.png")
const BoltVariant = preload("res://data/bullets/zealot_bolt.tres")
const RocketScene = preload("res://scenes/projectiles/enemy_rocket_large.tscn")
const MuzzleFlashTex = preload("res://graphics/gun_muzzle_flash.png")  # 5 frames, 16×16
const EngineFx = preload("res://scripts/effects/enemy_engine_fx.gd")
const ENGINE_TINT := Color(0.984314, 0.94902, 0.211765, 0.95)   # #fbf236 (matches the shared enemy trail)
const ENGINE_SCALE := 1.0

enum Mode { CYCLE, SALVO, SWEEP }

var _mode_seq: Array = []   # turret-mode order, reshuffled each combat phase
var _mode_idx: int = 0
var _cores_released: int = 0
var _rocket_pat_idx: int = 0
# Saved hull presentation so Phase 2's background look can be restored.
var _orig_scale: Vector2 = Vector2.ONE
var _orig_z: int = 0


func _ready() -> void:
	max_health = 260
	bounty_value = 400
	display_scale = 1.0
	boss_hover_y = 46.0
	super._ready()
	set_part_loss_thresholds([0.75, 0.5, 0.25])
	_build_turrets()
	_attach_engine_flames()


# The Shepherd has NO hull-mounted gun — the turrets do all cannon fire. Suppress
# the generic boss spread weapon the wave generator injects via shoot_pattern_override
# (it fired a 5-shot spread from the hull centre).
func _on_shoot_timer_timeout() -> void:
	pass


# Engine exhaust flames at each Engine* marker (bosses opt out of the base ship VFX,
# so the Shepherd attaches its own). Each flame trails ~11px behind its marker; cut
# on death in _on_boss_death.
func _attach_engine_flames() -> void:
	for marker in find_children("Engine*", "Marker2D", true, false):
		EngineFx.attach(marker as Node2D, ENGINE_TINT, ENGINE_SCALE)


# Mount a destructible turret part on each TurretL/R/L2/R2 marker.
func _build_turrets() -> void:
	for mount in find_children("Turret*", "Marker2D", true, false):
		var part = TurretPart.new()
		part.setup(self, 12)
		part.bullet_variant = BoltVariant
		part.set_meta("side", -1 if (mount as Marker2D).position.x < 0.0 else 1)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(16, 16)
		cs.shape = shape
		part.add_child(cs)
		var spr := Sprite2D.new()
		spr.texture = TurretTex
		spr.hframes = 3
		part.add_child(spr)
		part.set_barrel(spr)
		mount.add_child(part)
		register_part(part)


# ---- State graph --------------------------------------------------------

func _build_states() -> void:
	add_state(&"ARRIVAL")
	add_state(&"PHASE_1")
	add_state(&"TRANSITION_1")
	add_state(&"PHASE_2")
	add_state(&"PHASE_1_5")
	add_state(&"TRANSITION_2")
	add_state(&"PHASE_3")
	add_transition(&"ARRIVAL", t_flag(&"arrived"), &"PHASE_1")
	add_transition(&"PHASE_1", t_any([t_hp(0.75), t_after(20.0)]), &"TRANSITION_1")
	add_transition(&"TRANSITION_1", t_flag(&"anim_done"), &"PHASE_2")
	add_transition(&"PHASE_2", t_flag(&"loop_done"), &"PHASE_1_5")
	add_transition(&"PHASE_1_5", t_any([t_hp(0.50), t_after(20.0)]), &"TRANSITION_2")
	add_transition(&"TRANSITION_2", t_flag(&"anim_done"), &"PHASE_3")
	# PHASE_3 holds until death.


func _state_enter(state_name: StringName) -> void:
	match state_name:
		&"ARRIVAL":
			_arrival_seq()
		&"PHASE_1", &"PHASE_1_5":
			jiggle_hold(16.0, 4.5)
			_start_turrets(state_name)
		&"TRANSITION_1", &"TRANSITION_2":
			_transition_seq()
		&"PHASE_2":
			_phase2_seq()
		&"PHASE_3":
			_face_player(true)
			sweep_horizontal(90.0, 3.0)
			_start_turrets(state_name)     # turrets keep firing in Phase 3
			_phase3_rocket_loop()          # + rockets from the launchers + firecores


# ---- Lifecycle coroutines ----------------------------------------------

func _arrival_seq() -> void:
	await arrive_from(_arrival_lane(), 170.0)
	if _state == &"ARRIVAL":
		set_flag(&"arrived")


func _transition_seq() -> void:
	# Invincible animation: engines flash red 3×, then a muzzle-flash flare that
	# nukes incoming fire + opens a brief damage area to close players.
	set_invincible(true)
	for i in 3:
		if _dying:
			set_invincible(false)
			return
		_flash_hull(Color(1.6, 0.2, 0.2, 1.0), 0.22)   # "engines flash red"
		await _paced(0.3).timeout
	if _dying:
		set_invincible(false)
		return
	_screen_shake(8.0)
	_flare_strip()                        # gun-muzzle-flash strip at the engines (placeholder art)
	_clear_projectiles_in_radius(70.0)    # destroy incoming projectiles
	_spawn_circle_hitbox(global_position, 70.0, 0.45, 1)
	await _paced(0.5).timeout
	set_invincible(false)
	if _state == &"TRANSITION_1" or _state == &"TRANSITION_2":
		set_flag(&"anim_done")


func _phase2_seq() -> void:
	# Untouchable missile-cruiser interlude: accelerate off the top, drop into the
	# pseudo-parallax layer, rain the shared missile-salvo area attack (3 cycles,
	# 2s gaps), then restore + exit off the bottom and re-arrive -> loop to 1.5.
	set_invincible(true)
	await fly_offscreen(Vector2.UP, 340.0)
	if _state != &"PHASE_2":
		set_invincible(false)
		return
	_enter_background()
	position = Vector2(Playfield.CENTER.x, boss_hover_y - 8.0)
	_scripted_move = true   # hold; the salvo is the threat, not the hull
	var world: Node = _world()
	for i in 3:
		if _state != &"PHASE_2":
			break
		await MissileSalvo.run_salvo(self, world, {
			"zone_count": 4, "telegraph_time": 1.0, "missile_travel_time": 0.9,
			"fuse_time": 0.4, "aoe_radius": 24.0, "explosion_damage": 1,
			"launch_stagger": 0.12, "zone_y_min": 70.0, "zone_y_max": 240.0,
			# Lob each missile out of the LauncherL/R markers — forward (out the nose)
			# briefly, then curve down into the play area.
			"launch": Callable(self, "_launcher_pos"),
			"launch_forward": Vector2.UP, "launch_forward_dist": 52.0,
		})
		if _state != &"PHASE_2":
			break
		await _paced(2.0).timeout   # 2s gap between cycles
	# Stay faded on the cruiser layer while flying off the bottom, THEN restore
	# brightness off-screen and re-arrive (so it doesn't pop bright mid-exit).
	await fly_offscreen(Vector2.DOWN, 320.0)
	_exit_background()
	if _state != &"PHASE_2":
		set_invincible(false)
		return
	await arrive_from(_arrival_lane(), 200.0)
	set_invincible(false)
	if _state == &"PHASE_2":
		set_flag(&"loop_done")


# Alternating LauncherL/R world position for the i-th missile this salvo (used by
# MissileSalvo's launch callback so missiles leave the launch markers, not centre).
func _launcher_pos(idx: int) -> Vector2:
	var nm: String = "LauncherL" if (idx % 2 == 0) else "LauncherR"
	var m := get_node_or_null(nm)
	return (m as Node2D).global_position if (m is Node2D) else global_position


# Drop the hull into the faked mid-depth (pseudo-parallax) layer: scaled down,
# desaturated, drawn behind the gameplay ships. Restored by _exit_background.
# (Lightweight; MidDepthPresentation.add_above_backdrop is the fuller-fidelity option.)
func _enter_background() -> void:
	_orig_scale = scale
	_orig_z = z_index
	scale = _orig_scale * 0.7
	z_index = -5
	for s in _hull_layers():
		(s as Sprite2D).modulate = Color(0.5, 0.58, 0.72, 1.0)


func _exit_background() -> void:
	_scripted_move = false
	scale = _orig_scale
	z_index = _orig_z
	for s in _hull_layers():
		(s as Sprite2D).modulate = Color.WHITE


# The hull's direct-child Sprite2D layers (Roman's multi-layer hull: "Shepherd
# Hull" / "EngineLayer" / "Lower Hull" / masks). Excludes turret barrels (nested
# under markers). Discovered by type so it survives layer renames.
func _hull_layers() -> Array:
	return find_children("*", "Sprite2D", false, false)


# Lowest z_index across the hull layers (the back of the hull stack).
func _min_hull_z() -> int:
	var m: int = 0
	for s in _hull_layers():
		m = mini(m, (s as CanvasItem).z_index)
	return m


# Brief modulate flash across all hull layers (the base _enrage_flash keys off a
# "Sprite2D" node the Shepherd hull no longer has).
func _flash_hull(color: Color, duration: float) -> void:
	for s in _hull_layers():
		var ci := s as CanvasItem
		var orig: Color = ci.modulate
		var tw := ci.create_tween()
		tw.tween_property(ci, "modulate", color, duration * 0.4)
		tw.tween_property(ci, "modulate", orig, duration * 0.6)


# ---- Phase 3 rockets ----------------------------------------------------

func _phase3_rocket_loop() -> void:
	# Cycle the launcher firing patterns; release a firecore each cycle until gone.
	var patterns: Array = [["L", "R", "L", "R"], ["L", "L", "R", "R"], ["LR", "LR"]]
	while _state == &"PHASE_3" and not _dying:
		var pattern: Array = patterns[_rocket_pat_idx % patterns.size()]
		_rocket_pat_idx += 1
		for step in pattern:
			if _state != &"PHASE_3" or _dying:
				return
			_launch_rockets(step)
			await _paced(0.5).timeout
		if _cores_released < 4:
			_cores_released += 1
			_hide_core(_cores_released)
			release_firecore(Vector2(randf_range(-8.0, 8.0), 14.0))
		await _paced(0.6).timeout


# Launch a large rocket from the L launcher, the R launcher, or both ("LR").
func _launch_rockets(which: String) -> void:
	var names: Array = []
	if which == "L":
		names = ["LauncherL"]
	elif which == "R":
		names = ["LauncherR"]
	else:
		names = ["LauncherL", "LauncherR"]
	for nm in names:
		var m := get_node_or_null(nm)
		if m == null or not (m is Node2D):
			continue
		var r = RocketScene.instantiate()
		_world().add_child(r)
		if r.has_method("start"):
			r.start((m as Node2D).global_position)
		# Sort the rocket beneath the hull layers so it reads as launching from
		# under the ship (world-parented, so this is the boss's z + the lowest
		# hull layer's z, minus one).
		if r is CanvasItem:
			(r as CanvasItem).z_index = z_index + _min_hull_z() - 1


# Flip the hull art to face the player (Phase 3). Turrets aim independently, so
# only the hull/glow sprites flip — leaving turret aim + launcher markers intact.
func _face_player(down: bool) -> void:
	for s in _hull_layers():
		(s as Sprite2D).flip_v = down


func _hide_core(n: int) -> void:
	var nm: String = "CenterFirecoreCore" if n == 1 else "CenterFirecoreCore%d" % n
	var node := get_node_or_null(nm)
	if node != null and node is CanvasItem:
		(node as CanvasItem).visible = false


# Brief gun-muzzle-flash strip burst at each engine marker (transition flare art).
func _flare_strip() -> void:
	for marker in find_children("Engine*", "Marker2D", true, false):
		var spr := Sprite2D.new()
		spr.texture = MuzzleFlashTex
		spr.hframes = 5
		spr.frame = 0
		spr.modulate = Color(1.4, 1.1, 0.6, 1.0)
		(marker as Node2D).add_child(spr)
		var tw := spr.create_tween()
		for f in range(1, 5):
			tw.tween_callback(func() -> void: if is_instance_valid(spr): spr.frame = f)
			tw.tween_interval(0.05)
		tw.tween_callback(spr.queue_free)


# ---- Turret fire-mode coordinator --------------------------------------

func _start_turrets(state_name: StringName) -> void:
	_randomize_modes()
	_turret_combat_loop(state_name)


func _randomize_modes() -> void:
	_mode_seq = [Mode.CYCLE, Mode.SALVO, Mode.SWEEP]
	_mode_seq.shuffle()
	_mode_idx = 0


# Run the randomized mode rotation while this combat phase is active.
func _turret_combat_loop(state_name: StringName) -> void:
	while _state == state_name and not _dying:
		if live_parts().is_empty():
			await _paced(0.5).timeout
			continue
		var mode: int = int(_mode_seq[_mode_idx % _mode_seq.size()])
		_mode_idx += 1
		match mode:
			Mode.CYCLE: await _mode_cycle(state_name)
			Mode.SALVO: await _mode_salvo(state_name)
			Mode.SWEEP: await _mode_sweep(state_name)


# Cycle: each live turret fires an aimed bolt at the player in turn — slow, steady,
# every turret once before any repeats.
func _mode_cycle(state_name: StringName) -> void:
	var live := live_parts()
	live.shuffle()
	for tp in live:
		if _state != state_name or _dying:
			return
		if is_instance_valid(tp):
			tp.fire(_dir_to_player(tp.global_position))
		await _paced(0.55).timeout


# Salvo: all turrets aim straight down and fire 3-shot bursts, three times over.
func _mode_salvo(state_name: StringName) -> void:
	for burst in 3:
		if _state != state_name or _dying:
			return
		for s in 3:
			for tp in live_parts():
				if is_instance_valid(tp):
					tp.fire(Vector2.DOWN)
			await _paced(0.12).timeout
		await _paced(0.7).timeout


# Sweep: left turrets aim outward-down then swing toward center; right turrets
# mirror — not aimed, fills the screen and converges in the middle.
func _mode_sweep(state_name: StringName) -> void:
	var steps: int = 8
	for i in range(steps):
		if _state != state_name or _dying:
			return
		var t: float = float(i) / float(steps - 1)
		for tp in live_parts():
			if not is_instance_valid(tp):
				continue
			var side: int = int(tp.get_meta("side", 1))
			var outward := Vector2(side, 1.0).normalized()
			var inward := Vector2(-side * 0.3, 1.0).normalized()
			tp.fire(outward.lerp(inward, t).normalized())
		await _paced(0.16).timeout


func _dir_to_player(from: Vector2) -> Vector2:
	var p := find_player()
	if p == null or not (p is Node2D):
		return Vector2.DOWN
	var d: Vector2 = (p as Node2D).global_position - from
	return d.normalized() if d.length() > 0.01 else Vector2.DOWN


# Arrival lane (spec: "same lane as the supremacy missile cruiser"). Centre for
# now — point at the cruiser's spawn lane when that's pinned down.
func _arrival_lane() -> float:
	return Playfield.CENTER.x


func _on_boss_death() -> void:
	free_parts()
	# Cut the engines when the boss is defeated: the engine glow layer + the exhaust flames.
	var engine := get_node_or_null("EngineLayer")
	if engine is CanvasItem:
		(engine as CanvasItem).visible = false
	for marker in find_children("Engine*", "Marker2D", true, false):
		var flame := marker.get_node_or_null("EngineFlame")
		if flame is CanvasItem:
			(flame as CanvasItem).visible = false
