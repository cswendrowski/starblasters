extends Node2D

# Showcase scene for capture automation. Launch via:
#   godot --path . res://scenes/dev/feature_showcase.tscn \
#         --capture-demo=N --capture-duration=3 --capture-fps=30 \
#         --capture-dir=<abs-dir> --quit-after-capture
# When no capture flags are present, runs interactively for vibe-checks.

const PLAYER = preload("res://scenes/player/player.tscn")
const ENEMY_DART = preload("res://scenes/enemies/enemy_dart.tscn")
const ENEMY_DIVER = preload("res://scenes/enemies/enemy_diver.tscn")
const ENEMY_FIRECORE = preload("res://scenes/enemies/enemy_firecore.tscn")
const BOSS = preload("res://scenes/enemies/boss.tscn")
const BLACK_HOLE = preload("res://scenes/hazards/black_hole.tscn")
const WAVE_BANNER = preload("res://scenes/hud/wave_banner.tscn")
const SCENE_TRANSITION = preload("res://scenes/effects/scene_transition.tscn")
const UI_SCENE = preload("res://scenes/ui.tscn")
const MAIN_SCENE = preload("res://scenes/main.tscn")
# Match main.tscn's Player scale; rest of the world is balanced around 3x.
const PLAYER_SCALE := 3.0

var _capture_dir: String = ""
var _capture_fps: int = 30
var _capture_duration: float = 3.0
var _quit_after: bool = false
var _frame: int = 0
var _capturing: bool = false

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.03, 0.10))
	var demo = 0
	for a in OS.get_cmdline_args():
		if a.begins_with("--capture-demo="):
			demo = int(a.split("=", true, 1)[1])
		elif a.begins_with("--capture-duration="):
			_capture_duration = float(a.split("=", true, 1)[1])
		elif a.begins_with("--capture-fps="):
			_capture_fps = int(a.split("=", true, 1)[1])
		elif a.begins_with("--capture-dir="):
			_capture_dir = a.split("=", true, 1)[1]
		elif a == "--quit-after-capture":
			_quit_after = true
	_setup_demo(demo)
	if _capture_dir != "":
		Engine.max_fps = _capture_fps
		_capturing = true
		RenderingServer.frame_post_draw.connect(_on_post_draw)
		if _quit_after:
			# +0.2s buffer so the final frame flushes
			get_tree().create_timer(_capture_duration + 0.2).timeout.connect(func(): get_tree().quit())

func _setup_demo(idx: int) -> void:
	match idx:
		0: _demo_idle()
		1: _demo_wave_banner()
		2: _demo_black_hole()
		3: _demo_explosions()
		4: _demo_boss_black_hole()
		5: _demo_scene_transition()
		6: _demo_bullet_trails()
		7: _demo_hud_idle()
		8: _demo_hud_damage()
		9: _demo_hud_low_hull()
		10: _demo_hud_death()
		11: _demo_live_level()
		12: _demo_sector_map()
		13: _demo_level_intro()
		14: _demo_level_outro()
		15: _demo_minefield()
		16: _demo_asteroid_field()
		17: _demo_explosion_showcase()
		18: _demo_lighting_showcase()
		19: _demo_main_menu()
		20: _demo_run_summary()
		21: _demo_death_flow()
		22: _demo_outpost()
		23: _demo_signal_event()
		24: _demo_pause_menu()
		25: _demo_cleared_summary()
		26: _demo_menu_to_sector_transition()
		27: _demo_hangar()
		28: _demo_roster_test()
		29: _demo_onboarding()
		30: _demo_enemy_roster_sheet()
		31: _demo_codex()
		32: _demo_parallax_variant(8, "")                                  # bright Star
		33: _demo_parallax_variant(0, "nebula_amber")                       # Lava + warm nebula
		34: _demo_parallax_variant(1, "nebula_cyan")                        # Ice + cyan nebula
		35: _demo_parallax_variant(6, "")                                   # Black Hole
		36: _demo_parallax_variant(3, "nebula_magenta")                     # Gas Giant + magenta
		37: _demo_parallax_variant(7, "")                                   # Galaxy
		_: _demo_idle()

func _demo_idle() -> void:
	_spawn_player(Vector2(400, 760))
	# Mix of enemies so different display_scales are visible against player
	_spawn_enemy(Vector2(200, 280), ENEMY_DIVER)
	_spawn_enemy(Vector2(400, 260), ENEMY_FIRECORE)
	_spawn_enemy(Vector2(600, 280), ENEMY_DART)

func _demo_wave_banner() -> void:
	_demo_idle()
	var b = WAVE_BANNER.instantiate()
	add_child(b)
	if b.has_method("show_wave"):
		b.show_wave(3, 5)

func _demo_black_hole() -> void:
	_spawn_player(Vector2(400, 820))
	for i in 5:
		_spawn_enemy(Vector2(120 + i * 140, 200), ENEMY_DART)
	get_tree().create_timer(0.3).timeout.connect(func():
		var bh = BLACK_HOLE.instantiate()
		bh.position = Vector2(400, 480)
		add_child(bh)
	)

func _demo_explosions() -> void:
	_spawn_player(Vector2(400, 760))
	var enemies: Array = []
	for i in 4:
		enemies.append(_spawn_enemy(Vector2(150 + i * 170, 280), ENEMY_DART))
	get_tree().create_timer(0.6).timeout.connect(func():
		for e in enemies:
			if is_instance_valid(e) and e.has_method("explode"):
				e.explode()
	)

func _demo_boss_black_hole() -> void:
	_spawn_player(Vector2(400, 860))
	# Boss top-center, larger scale via its @export display_scale
	var b = BOSS.instantiate()
	b.scale = Vector2(3, 3)
	b.position = Vector2(400, 240)
	# Force the attack to fire fast so the capture window catches it.
	b.black_hole_interval_min = 1.2
	b.black_hole_interval_max = 1.6
	add_child(b)
	if b.has_method("start"):
		b.start(b.position)
	# Drop a few enemies as fodder so the gravity well has things to pull.
	for i in 4:
		_spawn_enemy(Vector2(150 + i * 170, 360), ENEMY_DART)

func _demo_scene_transition() -> void:
	_demo_idle()
	# Manually drive the transition overlay through a full out + in cycle so
	# the wipe is visible in a single capture without an actual scene change.
	get_tree().create_timer(0.4).timeout.connect(func():
		var overlay: CanvasLayer = SCENE_TRANSITION.instantiate()
		add_child(overlay)
		if overlay.has_method("randomize_seed"):
			overlay.randomize_seed()
		if overlay.has_method("set_progress"):
			overlay.set_progress(0.0)
		var tw := create_tween()
		tw.tween_method(Callable(overlay, "set_progress"), 0.0, 1.0, 0.7)
		tw.tween_interval(0.15)
		tw.tween_method(Callable(overlay, "set_progress"), 1.0, 0.0, 0.7)
		tw.finished.connect(func(): if is_instance_valid(overlay): overlay.queue_free())
	)

func _demo_bullet_trails() -> void:
	_spawn_player(Vector2(400, 760))
	# Spawn a row of enemies near top so we can fire enemy bullets too.
	_spawn_enemy(Vector2(200, 280), ENEMY_DART)
	_spawn_enemy(Vector2(600, 280), ENEMY_DART)
	# Fire player bullets in a stream so the cyan trail is visible all the way up.
	var bullet_scene := preload("res://scenes/projectiles/bullet.tscn")
	for i in 16:
		get_tree().create_timer(0.15 + i * 0.18).timeout.connect(func():
			var b = bullet_scene.instantiate()
			get_tree().root.add_child(b)
			if b.has_method("start"):
				b.start(Vector2(400, 720))
			else:
				b.position = Vector2(400, 720)
		)

func _setup_hud(p: Node) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "HUDLayer"
	add_child(cl)
	var ui = UI_SCENE.instantiate()
	cl.add_child(ui)
	if ui.has_method("bind_player"):
		ui.bind_player(p)
	if ui.has_method("update_score"):
		ui.update_score(2500)
	if ui.has_method("update_shield") and "max_shield" in p:
		ui.update_shield(p.max_shield, p.shield)
	if ui.has_method("update_hull") and "max_hull" in p:
		ui.update_hull(p.max_hull, p.hull)
	if ui.has_method("update_wave"):
		ui.update_wave(2, 7)
	return cl

func _demo_hud_idle() -> void:
	var p = _spawn_player(Vector2(400, 760))
	_setup_hud(p)
	# Sway the player so HUD inertia is visible
	var tw := create_tween().set_loops()
	tw.tween_property(p, "position:x", 220.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "position:x", 580.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _demo_hud_damage() -> void:
	var p = _spawn_player(Vector2(400, 760))
	_setup_hud(p)
	# Knock shield out immediately so hits land on hull and damage_level rises
	get_tree().create_timer(0.4).timeout.connect(func():
		if not is_instance_valid(p):
			return
		p.max_shield = 0
		p.shield = 0
	)
	# Rhythmic damage pulses — each one boosts disruption for ~0.4s
	for i in 5:
		get_tree().create_timer(0.8 + i * 0.7).timeout.connect(func():
			if is_instance_valid(p) and p.has_method("take_damage"):
				p.take_damage(1)
		)

func _demo_hud_low_hull() -> void:
	var p = _spawn_player(Vector2(400, 760))
	# Bump max_hull to 6 (Roman's spec'd "◆◆◆◆◆◆" pip strip).
	if "max_hull" in p:
		p.max_hull = 6
	_setup_hud(p)
	# Drop hull to critical so red-tint, pips, and the COMPROMISED warning all fire.
	get_tree().create_timer(0.1).timeout.connect(func():
		if not is_instance_valid(p):
			return
		p.max_shield = 0
		p.shield = 0
		p.hull = 2
	)
	# Subtle movement so inertia is also visible.
	var tw := create_tween().set_loops()
	tw.tween_property(p, "position:x", 320.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(p, "position:x", 480.0, 1.6).set_trans(Tween.TRANS_SINE)

func _demo_hud_death() -> void:
	var p = _spawn_player(Vector2(400, 760))
	_setup_hud(p)
	# Hold for a beat so the baseline HUD reads, then deliver a fatal blow.
	get_tree().create_timer(1.2).timeout.connect(func():
		if not is_instance_valid(p) or not p.has_method("take_damage"):
			return
		p.max_shield = 0
		p.shield = 0
		# Overkill to guarantee death + emit `damaged` for the crank-up flash
		p.take_damage(p.max_hull + 5)
	)

func _demo_level_intro() -> void:
	# Just main.tscn — its new_game() triggers the new intro sequence.
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)

func _demo_level_outro() -> void:
	# Spawn main.tscn, then after a moment force a level_cleared so we see the
	# outro fly-off + cleared summary screen.
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)
	get_tree().create_timer(3.5).timeout.connect(func():
		if not is_instance_valid(main_inst):
			return
		var wd = main_inst.get_node_or_null("WaveDirector")
		if wd:
			wd.stop() if wd.has_method("stop") else null
			# Fake some enemy stats so the cleared screen has rows to show.
			if "_enemy_stats" in main_inst:
				main_inst._enemy_stats = {
					"res://scenes/enemies/enemy_dart.tscn": {"spawned": 14, "killed": 12, "bounty": 10, "total_bounty": 120},
					"res://scenes/enemies/enemy_diver.tscn": {"spawned": 8, "killed": 7, "bounty": 15, "total_bounty": 105},
					"res://scenes/enemies/enemy_firecore.tscn": {"spawned": 4, "killed": 4, "bounty": 25, "total_bounty": 100},
				}
				main_inst.bounty = 325
			# Trigger the outro
			main_inst._on_level_cleared()
	)

func _demo_sector_map() -> void:
	# Instance the sector map scene so we capture the procgen graph with the
	# new icons in place.
	var sm_scene := load("res://scenes/sector_map.tscn")
	if sm_scene == null:
		return
	var sm = sm_scene.instantiate()
	add_child(sm)

func _demo_run_summary() -> void:
	var ps = load("res://scenes/run_summary.tscn")
	if ps == null:
		return
	var inst = ps.instantiate()
	add_child(inst)

func _demo_death_flow() -> void:
	# Live combat scene, then force the player to die so we capture the
	# full explosion + HUD flicker + wipe + run summary sequence.
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)
	get_tree().create_timer(3.0).timeout.connect(func():
		if not is_instance_valid(main_inst):
			return
		var p = main_inst.get_node_or_null("Player")
		if p and p.has_method("take_damage"):
			p.max_shield = 0
			p.shield = 0
			p.take_damage(p.max_hull + 50)
	)

func _demo_main_menu() -> void:
	var ps = load("res://scenes/main_menu.tscn")
	if ps == null:
		return
	var inst = ps.instantiate()
	add_child(inst)

func _demo_lighting_showcase() -> void:
	# Live combat scene + manual streams of player and enemy bullets so the
	# new projectile glows and the engine glow are clearly visible.
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)
	var player_bullet := preload("res://scenes/projectiles/bullet.tscn")
	var enemy_bullet := preload("res://scenes/projectiles/enemy_bullet.tscn")
	# Fire a steady player bullet stream so the cyan halo + engine glow read.
	for i in 30:
		get_tree().create_timer(2.5 + i * 0.18).timeout.connect(func():
			if not is_instance_valid(main_inst):
				return
			var p = main_inst.get_node_or_null("Player")
			if p == null or not is_instance_valid(p):
				return
			var b = player_bullet.instantiate()
			get_tree().root.add_child(b)
			if b.has_method("start"):
				b.start(p.global_position + Vector2(0, -40))
		)
	# Fire some enemy bullets from various top positions so the orange halo
	# is also visible flowing down.
	for i in 20:
		get_tree().create_timer(3.0 + i * 0.32).timeout.connect(func():
			if not is_instance_valid(main_inst):
				return
			var b = enemy_bullet.instantiate()
			get_tree().root.add_child(b)
			var x: float = randf_range(160.0, 640.0)
			if b.has_method("start"):
				b.start(Vector2(x, 60), Vector2(0, 1))
		)

func _demo_explosion_showcase() -> void:
	_spawn_player(Vector2(400, 860))
	# Stagger several explosions at varying positions and scales so each
	# instance's randomization (rotation, secondaries, sparks) is visible.
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	var spots = [
		[Vector2(220, 320), 1.0, 0.2],
		[Vector2(580, 280), 1.4, 0.5],
		[Vector2(400, 480), 2.0, 0.9],
		[Vector2(160, 560), 1.2, 1.3],
		[Vector2(620, 600), 1.6, 1.7],
		[Vector2(360, 360), 0.9, 2.1],
		[Vector2(500, 720), 1.3, 2.5],
	]
	for s in spots:
		var pos: Vector2 = s[0]
		var sc: float = s[1]
		var delay: float = s[2]
		get_tree().create_timer(delay).timeout.connect(func():
			ExplosionFx.play(pos, sc)
		)

func _demo_minefield() -> void:
	# Set Run state so main.tscn picks the minefield level builder.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD
		run.current_hazard_subtype = "minefield"
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)
	# Shoot a mine ~2s in to demonstrate activation
	get_tree().create_timer(3.5).timeout.connect(func():
		var enemies = get_tree().get_nodes_in_group("enemies")
		if enemies.size() > 0 and enemies[0].has_method("hit"):
			enemies[0].hit()
	)

func _demo_asteroid_field() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.current_node_type = 5  # HAZARD
		run.current_hazard_subtype = "asteroid_field"
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)

func _demo_live_level() -> void:
	# Instances main.tscn as a child so we capture the real combat scene with
	# wave director, enemies, full HUD, parallax background, the works.
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)
	# Periodically explode an on-screen enemy so we see the in-context
	# explosion FX over real gameplay during the capture window.
	for i in 8:
		var t: float = 4.5 + i * 0.55
		get_tree().create_timer(t).timeout.connect(func():
			var enemies = get_tree().get_nodes_in_group("enemies")
			if enemies.size() > 0:
				var pick = enemies[randi() % enemies.size()]
				if is_instance_valid(pick) and pick.has_method("explode"):
					pick.explode()
		)
	# Simulate a damage hit ~2s in so the HUD shake/disruption fires while we
	# capture, and we can see the live red-state / pip drop on a real player.
	get_tree().create_timer(2.0).timeout.connect(func():
		var p = main_inst.get_node_or_null("Player")
		if p and is_instance_valid(p) and p.has_method("take_damage"):
			p.max_shield = 0
			p.shield = 0
			p.take_damage(2)
	)

func _demo_outpost() -> void:
	var ps = load("res://scenes/outpost.tscn")
	if ps == null:
		return
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.bounty = 250
	var inst = ps.instantiate()
	add_child(inst)


func _demo_signal_event() -> void:
	var ps = load("res://scenes/signal_event.tscn")
	if ps == null:
		return
	var inst = ps.instantiate()
	add_child(inst)


func _demo_pause_menu() -> void:
	# Bring up a paused combat scene so the pause overlay reads with gameplay
	# behind it.
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)
	get_tree().create_timer(1.0).timeout.connect(func():
		get_tree().paused = true
		var pause = main_inst.get_node_or_null("PauseMenu")
		if pause and pause.has_method("show_menu"):
			pause.show_menu()
		elif pause:
			pause.visible = true
	)


func _demo_cleared_summary() -> void:
	var ps = load("res://scenes/cleared_summary.tscn")
	if ps == null:
		# Some checkouts don't have a standalone cleared scene — fall back to
		# the in-engine instantiation path via main.
		var main_inst = MAIN_SCENE.instantiate()
		add_child(main_inst)
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_instance_valid(main_inst) and main_inst.has_method("_on_level_cleared"):
				main_inst._on_level_cleared()
		)
		return
	var inst = ps.instantiate()
	add_child(inst)
	if inst.has_method("populate"):
		inst.populate({}, 320, false)


func _demo_menu_to_sector_transition() -> void:
	# Showcase the fade transition without leaving the showcase scene (the
	# capture pipeline connects to this node's frame_post_draw; a real
	# change_scene_to_file would tear it down and capture nothing). We mimic
	# the SceneTransition flow manually: instance menu, fade-to-black, swap
	# to sector map, fade-from-black.
	var menu_scene = load("res://scenes/main_menu.tscn")
	var sector_scene = load("res://scenes/sector_map.tscn")
	if menu_scene == null or sector_scene == null:
		return
	var menu = menu_scene.instantiate()
	add_child(menu)
	# Black overlay on a high CanvasLayer.
	var cl := CanvasLayer.new()
	cl.layer = 128
	add_child(cl)
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(rect)
	# Hold on menu ~0.8s, then run the same fade timings as SceneTransition.
	get_tree().create_timer(0.8).timeout.connect(func():
		var tw_out := rect.create_tween()
		tw_out.tween_property(rect, "color:a", 1.0, 0.45)
		tw_out.finished.connect(func():
			if is_instance_valid(menu):
				menu.queue_free()
			var sm = sector_scene.instantiate()
			add_child(sm)
			get_tree().create_timer(0.1).timeout.connect(func():
				var tw_in := rect.create_tween()
				tw_in.tween_property(rect, "color:a", 0.0, 0.45)
				tw_in.finished.connect(func():
					if is_instance_valid(cl):
						cl.queue_free()
				)
			)
		)
	)


func _demo_roster_test() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.test_mode_active = true
		run.current_node_type = 5  # HAZARD
		run.current_hazard_subtype = "roster_test"
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)


# Force a specific planet_idx + optional nebula tint into Run.current_stellar
# so the live combat backdrop renders that exact stellar config. Used to
# capture permutation samples of the parallax (Roman, 2026-05-16).
func _demo_parallax_variant(planet_idx: int, nebula_band: String) -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		var tint := Color(1, 1, 1, 1)
		match nebula_band:
			"nebula_amber": tint = Color(0.95, 0.75, 0.45)
			"nebula_cyan": tint = Color(0.55, 0.75, 1.00)
			"nebula_magenta": tint = Color(0.85, 0.55, 1.00)
			"nebula_green": tint = Color(0.65, 0.95, 0.65)
		run.current_stellar = {
			"planet_idx": planet_idx,
			"nebula_band": nebula_band,
			"nebula_tint": tint,
		}
	var main_inst = MAIN_SCENE.instantiate()
	add_child(main_inst)


func _demo_codex() -> void:
	# Pre-populate the codex with every entry so the list isn't empty.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		for path in [
			"res://scenes/enemies/enemy_firecore.tscn",
			"res://scenes/enemies/enemy_diver.tscn",
			"res://scenes/enemies/enemy_dart.tscn",
			"res://scenes/enemies/enemy_hunter_drone.tscn",
			"res://scenes/enemies/enemy_hopper.tscn",
			"res://scenes/enemies/enemy_frigate.tscn",
			"res://scenes/enemies/enemy_cutter.tscn",
			"res://scenes/enemies/enemy_skirmisher.tscn",
			"res://scenes/enemies/enemy_crystal.tscn",
			"res://scenes/enemies/enemy_minelayer.tscn",
		]:
			run.encountered_enemies[path] = true
	var ps = load("res://scenes/enemy_codex.tscn")
	if ps == null:
		return
	add_child(ps.instantiate())


func _demo_enemy_roster_sheet() -> void:
	# Grid sheet of every combat enemy + boss, with name labels. Used for
	# the roster reference image Roman asked for 2026-05-16.
	const ROSTER = [
		# COMMON
		{"path": "res://scenes/enemies/enemy_firecore.tscn", "name": "Firecore", "tier": "Common"},
		{"path": "res://scenes/enemies/enemy_diver.tscn",    "name": "Diver",    "tier": "Common"},
		{"path": "res://scenes/enemies/enemy_dart.tscn",     "name": "Dart",     "tier": "Common"},
		{"path": "res://scenes/enemies/enemy_hunter_drone.tscn", "name": "Hunter Drone", "tier": "Common"},
		# UNCOMMON
		{"path": "res://scenes/enemies/enemy_hopper.tscn",   "name": "Hopper",   "tier": "Uncommon"},
		{"path": "res://scenes/enemies/enemy_frigate.tscn",  "name": "Frigate",  "tier": "Uncommon"},
		{"path": "res://scenes/enemies/enemy_cutter.tscn",   "name": "Cutter",   "tier": "Uncommon"},
		{"path": "res://scenes/enemies/enemy_skirmisher.tscn", "name": "Skirmisher", "tier": "Uncommon"},
		# RARE
		{"path": "res://scenes/enemies/enemy_crystal.tscn",  "name": "Crystal",  "tier": "Rare"},
		{"path": "res://scenes/enemies/enemy_minelayer.tscn", "name": "Minelayer", "tier": "Rare"},
		{"path": "res://scenes/enemies/enemy_interceptor.tscn", "name": "Interceptor", "tier": "Rare"},
		{"path": "res://scenes/enemies/enemy_bulwark.tscn",  "name": "Bulwark",  "tier": "Rare"},
		# BOSS
		{"path": "res://scenes/enemies/boss.tscn",           "name": "Commander", "tier": "Boss"},
		{"path": "res://scenes/enemies/boss_reaver.tscn",    "name": "Reaver",   "tier": "Boss"},
		{"path": "res://scenes/enemies/boss_sentinel.tscn",  "name": "Sentinel", "tier": "Boss"},
	]
	# 4 columns × 4 rows fits 16 cells with room for labels.
	# Tightened from 200/80 → 184/56 so the rightmost column isn't clipped
	# at the 800-px viewport edge.
	var col_w := 184
	var row_h := 210
	var cols := 4
	var x_pad := 56
	var y_pad := 120
	for i in ROSTER.size():
		var entry = ROSTER[i]
		var r := i / cols
		var c := i % cols
		var cx := x_pad + c * col_w + col_w / 2
		var cy := y_pad + r * row_h + row_h / 2
		var packed = load(entry["path"])
		if packed != null:
			var inst = packed.instantiate()
			if inst is Node2D:
				inst.position = Vector2(cx, cy)
				inst.scale = Vector2(2.5, 2.5)
				inst.process_mode = Node.PROCESS_MODE_DISABLED
			add_child(inst)
			# Suppress any spawned hazard auras (bulwark) that depend on
			# enemies-group lookups.
		# Name label below the sprite.
		var lbl := Label.new()
		lbl.text = entry["name"]
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
		lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(col_w, 24)
		lbl.position = Vector2(cx - col_w / 2, cy + 56)
		add_child(lbl)
		# Tier label below name.
		var tier_lbl := Label.new()
		tier_lbl.text = entry["tier"]
		tier_lbl.add_theme_font_size_override("font_size", 13)
		var tier_color := Color(0.75, 0.85, 1.0)
		match String(entry["tier"]):
			"Common":   tier_color = Color(0.75, 0.90, 0.75)
			"Uncommon": tier_color = Color(0.70, 0.85, 1.00)
			"Rare":     tier_color = Color(1.00, 0.78, 0.55)
			"Boss":     tier_color = Color(1.00, 0.55, 0.55)
		tier_lbl.add_theme_color_override("font_color", tier_color)
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_lbl.size = Vector2(col_w, 18)
		tier_lbl.position = Vector2(cx - col_w / 2, cy + 82)
		add_child(tier_lbl)
	# Title at top.
	var title := Label.new()
	title.text = "ENEMY ROSTER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(800, 40)
	title.position = Vector2(0, 40)
	add_child(title)


func _demo_onboarding() -> void:
	var ps = load("res://scenes/onboarding.tscn")
	if ps == null:
		return
	var inst = ps.instantiate()
	add_child(inst)


func _demo_hangar() -> void:
	var ps = load("res://scenes/hangar.tscn")
	if ps == null:
		return
	var inst = ps.instantiate()
	add_child(inst)


func _spawn_player(pos: Vector2) -> Node:
	var p = PLAYER.instantiate()
	add_child(p)
	p.scale = Vector2(PLAYER_SCALE, PLAYER_SCALE)
	p.position = pos
	return p

func _spawn_enemy(pos: Vector2, scene: PackedScene = ENEMY_DART) -> Node:
	var e = scene.instantiate()
	add_child(e)
	# Match Director: per-ship display_scale @export drives final scale.
	var s: float = 1.5
	if "display_scale" in e and e.display_scale > 0.0:
		s = e.display_scale
	e.scale = Vector2(s, s)
	e.position = pos
	if e.has_method("start"):
		e.start(pos)
	e.add_to_group("enemies")
	return e

func _on_post_draw() -> void:
	if not _capturing or _capture_dir == "":
		return
	var vp := get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img = tex.get_image()
	if img == null:
		return
	var path = "%s/frame_%04d.png" % [_capture_dir, _frame]
	img.save_png(path)
	_frame += 1
