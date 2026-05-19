extends Node2D

const Levels = preload("res://scripts/levels/levels_v2.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const SectorNode = preload("res://scripts/sector_node.gd")
const WaveBannerScene = preload("res://scenes/hud/wave_banner.tscn")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const ClearedSummaryScene = preload("res://scenes/cleared_summary.tscn")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const HdCanvas = preload("res://scripts/ui/hd_canvas.gd")

var bounty: int = 0
var playing: bool = false
var _boss_hooked: Node = null
# Per-enemy-type stats: scene_path → {"spawned": int, "killed": int, "bounty": int, "total_bounty": int}
var _enemy_stats: Dictionary = {}
var _current_level = null
# Suppress the wave banner during the intro so it doesn't double up with the
# scripted "WAVE 1" alert we fire at the end of the slide-in.
var _suppress_wave_banner: bool = false

@onready var start_button = $CanvasLayer/CenterContainer/Start
@onready var game_over = $CanvasLayer/CenterContainer/GameOver
@onready var wave_director = $WaveDirector
@onready var player = $Player
@onready var boss_hp_bar: TextureProgressBar = $CanvasLayer/BossHpBar if has_node("CanvasLayer/BossHpBar") else null
@onready var boss_label: Label = $CanvasLayer/BossLabel if has_node("CanvasLayer/BossLabel") else null

func _ready() -> void:
	game_over.hide()
	start_button.hide()
	# Warmup must defer — at _ready() the SceneTree is still building the
	# initial scene, so add_child fails with "busy setting up children".
	call_deferred("_warm_up_explosion")
	# Volume slider lives in the pause/options menu now, not the main HUD.
	if has_node("CanvasLayer/Volume"):
		$CanvasLayer/Volume.visible = false
	var tween = create_tween().set_loops().set_parallel(false).set_trans(Tween.TRANS_SINE)
	tween.tween_property($EnemyAnchor, "position:x", $EnemyAnchor.position.x + 3, 1.0)
	tween.tween_property($EnemyAnchor, "position:x", $EnemyAnchor.position.x - 3, 1.0)
	var tween2 = create_tween().set_loops().set_parallel(false).set_trans(Tween.TRANS_BACK)
	tween2.tween_property($EnemyAnchor, "position:y", $EnemyAnchor.position.y + 3, 1.5).set_ease(Tween.EASE_IN_OUT)
	tween2.tween_property($EnemyAnchor, "position:y", $EnemyAnchor.position.y - 3, 1.5).set_ease(Tween.EASE_IN_OUT)
	if not wave_director.enemy_died.is_connected(_on_enemy_died):
		wave_director.enemy_died.connect(_on_enemy_died)
	if not wave_director.enemy_spawned.is_connected(_on_enemy_spawned):
		wave_director.enemy_spawned.connect(_on_enemy_spawned)
	if not wave_director.level_cleared.is_connected(_on_level_cleared):
		wave_director.level_cleared.connect(_on_level_cleared)
	if not wave_director.wave_started.is_connected(_on_wave_started):
		wave_director.wave_started.connect(_on_wave_started)
	get_tree().node_added.connect(_on_node_added_to_tree)
	# Wire the HUD to the player so it can react to damage/death.
	if $CanvasLayer/UI.has_method("bind_player") and player and is_instance_valid(player):
		$CanvasLayer/UI.bind_player(player)
	if boss_hp_bar:
		boss_hp_bar.visible = false
	if boss_label:
		boss_label.visible = false
	_install_playfield_frame()
	new_game()


# Light-blue card-style outline around the 216×270 playfield, plus a
# translucent "glass" tint over the two side gutters so the non-play
# space reads as reserved UI surface instead of dead backdrop.
func _install_playfield_frame() -> void:
	# Layer order, bottom → top:
	#   0: world canvas (galaxy backdrop, gameplay nodes)
	#   1: PlayfieldGlass — translucent gutter tint
	#   5: HUD canvas (main.tscn's CanvasLayer, bumped from default 1)
	#  10: PlayfieldFrame outline — always visible above HUD
	# Bumping the main HUD canvas keeps the glass below the HUD (so the
	# right-gutter bounty/ammo read on top of the tint) and the outline
	# above everything.
	if has_node("CanvasLayer"):
		($CanvasLayer as CanvasLayer).layer = 5
	var glass_layer := CanvasLayer.new()
	glass_layer.name = "PlayfieldGlass"
	glass_layer.layer = 1
	add_child(glass_layer)

	var glass_bg := Color(0.04, 0.06, 0.10, 0.55)
	var glass_edge := UiTheme.COLOR_ACCENT_DIM
	for spec in [
		{"name": "GutterLeft",  "x": 0.0,             "w": Playfield.X_MIN,           "edge": "right"},
		{"name": "GutterRight", "x": Playfield.X_MAX, "w": 480.0 - Playfield.X_MAX,   "edge": "left"},
	]:
		var panel := Panel.new()
		panel.name = String(spec["name"])
		panel.position = Vector2(float(spec["x"]), 0.0)
		panel.size = Vector2(float(spec["w"]), 270.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = glass_bg
		gsb.border_color = glass_edge
		if String(spec["edge"]) == "right":
			gsb.border_width_right = 1
		else:
			gsb.border_width_left = 1
		panel.add_theme_stylebox_override("panel", gsb)
		glass_layer.add_child(panel)

	# HD UI layer — 2× density text host. See scripts/ui/hd_canvas.gd.
	var hd_viewport := HdCanvas.install(self)
	# WaveLabel migrated to HD density (font_size=16 in 960×540).
	var wave_label := Label.new()
	wave_label.name = "WaveLabel"
	wave_label.position = Vector2(16, 16)
	wave_label.size = Vector2(280, 24)
	wave_label.add_theme_font_size_override("font_size", 16)
	wave_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	wave_label.text = ""
	wave_label.visible = false
	hd_viewport.add_child(wave_label)
	if has_node("CanvasLayer/UI"):
		var ui_node = $CanvasLayer/UI
		if ui_node.has_method("set_wave_label_node"):
			ui_node.set_wave_label_node(wave_label)
		if ui_node.has_method("migrate_hd_labels"):
			ui_node.migrate_hd_labels(hd_viewport)

	# Outline frame on its own layer ABOVE the HUD so the band's edge is
	# always visible — the 1-px transparent-fill border doesn't obscure
	# any of the corner-anchored HUD widgets.
	var frame_layer := CanvasLayer.new()
	frame_layer.name = "PlayfieldFrame"
	frame_layer.layer = 10
	add_child(frame_layer)

	var frame := Panel.new()
	frame.name = "Frame"
	frame.position = Vector2(Playfield.X_MIN, Playfield.Y_MIN)
	frame.size = Vector2(Playfield.W, Playfield.H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	# Vertical edges only — the band reads as an open column, no top /
	# bottom cap. Matches the UI Designer preview.
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	frame.add_theme_stylebox_override("panel", sb)
	frame_layer.add_child(frame)

func _warm_up_explosion() -> void:
	# The first-kill freeze is the burn shader compiling against each
	# enemy's specific Sprite2D texture + the explosion's CPU particles
	# first-time init. Pre-compile ALL hot-path resources up-front by
	# applying burn to every enemy's sprite and firing a few explosions.
	var WARM_DIR := Vector2(-9999, -9999)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	var BurnFx = load("res://scripts/burn_fx.gd")
	# Pre-fire one explosion to compile the shader path. All explosions are
	# 1× now (Roman 2026-05-18) so we only need one warmup variant.
	var warm_explosion = ExplosionFx.play(WARM_DIR, 1.0, true)
	if warm_explosion:
		warm_explosion.modulate = Color(1, 1, 1, 0.001)
	# Burn-compile each enemy's authored Sprite2D texture (each unique
	# texture is a separate shader compile) so the first death of each
	# enemy type doesn't stall the frame.
	var enemy_scenes := [
		"res://scenes/enemies/enemy_firecore.tscn",
		"res://scenes/enemies/enemy_diver.tscn",
		"res://scenes/enemies/enemy_crystal.tscn",
		"res://scenes/enemies/enemy_dart.tscn",
		"res://scenes/enemies/enemy_hopper.tscn",
		"res://scenes/enemies/enemy_mine.tscn",
		"res://scenes/enemies/enemy_mine_shield.tscn",
		"res://scenes/enemies/enemy_mine_cluster.tscn",
		"res://scenes/enemies/enemy_mine_cluster_smart.tscn",
		"res://scenes/enemies/enemy_bomblet.tscn",
		"res://scenes/enemies/enemy_asteroid.tscn",
		"res://scenes/enemies/enemy_bomber.tscn",
		"res://scenes/enemies/enemy_bulwark.tscn",
		"res://scenes/enemies/enemy_frigate.tscn",
		"res://scenes/enemies/enemy_cutter.tscn",
		"res://scenes/enemies/enemy_skirmisher.tscn",
		"res://scenes/enemies/enemy_interceptor.tscn",
		"res://scenes/enemies/enemy_minelayer.tscn",
		"res://scenes/enemies/enemy_hunter_drone.tscn",
		"res://scenes/enemies/boss.tscn",
		"res://scenes/enemies/boss_reaver.tscn",
		"res://scenes/enemies/boss_sentinel.tscn",
	]
	var to_free: Array = []
	for path in enemy_scenes:
		var ps = load(path)
		if ps == null:
			continue
		var inst = ps.instantiate()
		inst.process_mode = Node.PROCESS_MODE_DISABLED
		# Visible=true (off-screen) so the shader actually compiles. Hidden
		# nodes skip the draw pass under gl_compatibility, so a `visible=false`
		# warmup never triggers the compile we're trying to pre-pay for — that
		# was the lingering first-kill hitch after the earlier passes.
		inst.visible = true
		inst.modulate = Color(1, 1, 1, 0.001)  # invisible but still drawn
		inst.position = WARM_DIR
		inst.set_meta("warmup_only", true)
		get_tree().root.add_child(inst)
		# If the enemy has a Sprite2D, compile burn against its texture.
		var sprite = inst.get_node_or_null("Sprite2D")
		if sprite and sprite is Sprite2D:
			BurnFx.apply_burn(sprite, 0.05)
		to_free.append(inst)
	# Bullet materials.
	var pb := preload("res://scenes/projectiles/bullet.tscn").instantiate()
	pb.position = WARM_DIR
	get_tree().root.add_child(pb)
	to_free.append(pb)
	var eb := preload("res://scenes/projectiles/enemy_bullet.tscn").instantiate()
	eb.position = WARM_DIR
	get_tree().root.add_child(eb)
	to_free.append(eb)
	# Free everything one frame later — by then the shaders have compiled
	# and the materials are cached in the rendering server.
	get_tree().create_timer(0.25).timeout.connect(func():
		for n in to_free:
			if is_instance_valid(n):
				n.queue_free()
	)


func _on_wave_started(idx: int, total: int, silent: bool, announce_text: String = "") -> void:
	if $CanvasLayer/UI.has_method("update_wave"):
		$CanvasLayer/UI.update_wave(idx, total)
	# Music intensity walks up with wave progress.
	if has_node("/root/Music"):
		var has_boss: bool = false
		if has_node("/root/Run"):
			has_boss = (get_node("/root/Run").current_node_type == SectorNode.NodeType.BOSS)
		get_node("/root/Music").set_combat_progress(idx, total, has_boss)
	if silent or _suppress_wave_banner:
		return
	_show_wave_banner(idx, total, announce_text)

func _show_wave_banner(idx: int, total: int, announce_text: String = "") -> void:
	var banner := WaveBannerScene.instantiate()
	add_child(banner)
	if announce_text != "" and banner.has_method("show_text"):
		banner.show_text(announce_text)
	elif banner.has_method("show_wave"):
		banner.show_wave(idx, total)

func _on_enemy_spawned(scene_path: String, bounty_value: int) -> void:
	if scene_path == "":
		return
	if not _enemy_stats.has(scene_path):
		_enemy_stats[scene_path] = {
			"spawned": 0, "killed": 0, "bounty": bounty_value, "total_bounty": 0
		}
	_enemy_stats[scene_path]["spawned"] += 1
	# Keep bounty value fresh in case wave override changed it.
	_enemy_stats[scene_path]["bounty"] = bounty_value
	# Register first-encounter into the persistent codex (Roman, 2026-05-16).
	if has_node("/root/Run"):
		get_node("/root/Run").mark_encountered(scene_path)

func _on_enemy_died(value, scene_path: String) -> void:
	bounty += value
	if has_node("/root/Run"):
		get_node("/root/Run").record_kill(value)
	$CanvasLayer/UI.update_score(bounty)
	$Camera2D.add_trauma(0.25)
	if scene_path != "" and _enemy_stats.has(scene_path):
		_enemy_stats[scene_path]["killed"] += 1
		_enemy_stats[scene_path]["total_bounty"] += value

func _on_level_cleared() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		# Bump the per-sector combat count, but only for actual combat nodes —
		# bosses end the sector (handled by the endless-mode flow elsewhere),
		# and hazards/signals aren't part of the wave-scaling progression.
		var is_combat_node: bool = (run.current_node_type != SectorNode.NodeType.BOSS) and (run.current_node_type != SectorNode.NodeType.HAZARD)
		if is_combat_node:
			run.combats_in_sector += 1
		run.sector_complete()
		# Consume per-run flags so they don't leak into the next level.
		run.asteroid_bonus_bounty = 0
		run.combat_intro = ""
		if player and is_instance_valid(player):
			run.current_hull = player.hull
			run.max_hull = player.max_hull
			run.current_shield = player.shield
			run.max_shield = player.max_shield
	_run_outro()

func _on_player_died() -> void:
	playing = false
	$BGM.playing = false
	if has_node("/root/Music"):
		get_node("/root/Music").stop(0.8)
	$End.play()
	wave_director.stop()
	# Player explodes on death — fire the same VFX a regular kill would.
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if player and is_instance_valid(player):
		# Player death = multi-blast at 1× scale (Roman 2026-05-18 uniform).
		ExplosionFx.burst(player.global_position, 4, 14.0, 0.08)
		player.visible = false
	# HUD glitches out alongside the death (flicker_out cranks disruption +
	# fades alpha).
	if $CanvasLayer/UI.has_method("flicker_out"):
		$CanvasLayer/UI.flicker_out(0.5)
	get_tree().call_group("enemies", "queue_free")
	# Hold a beat so the explosion + HUD glitch read, then wipe to black
	# and show the run summary buttons.
	await get_tree().create_timer(1.4).timeout
	SceneTransition.change_scene(get_tree(), "res://scenes/run_summary.tscn")

func new_game() -> void:
	bounty = 0
	_enemy_stats.clear()
	if has_node("/root/Run"):
		bounty = get_node("/root/Run").bounty
	$CanvasLayer/UI.update_score(bounty)
	if player and is_instance_valid(player):
		player.start()
		if has_node("/root/Run"):
			var run = get_node("/root/Run")
			if run.max_hull > 0:
				player.max_hull = run.max_hull
				player.hull = run.current_hull if run.current_hull > 0 else run.max_hull
			if run.max_shield > 0:
				player.max_shield = run.max_shield
				# Always start each sector with full shields (Cody, 2026-05-17
				# playtest: "should we start each sector with full shields?" —
				# yes, hull persists but shield refills as the in-between beat).
				player.shield = run.max_shield
	# Old hardcoded BGM is silenced; the Music manager handles combat tracks.
	$BGM.playing = false
	# Pick level by current sector node type
	var is_boss := false
	var is_hazard := false
	var hazard_subtype: String = ""
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.current_node_type == SectorNode.NodeType.BOSS:
			is_boss = true
		elif run.current_node_type == SectorNode.NodeType.HAZARD:
			is_hazard = true
			hazard_subtype = run.current_hazard_subtype
	if has_node("/root/Music"):
		if is_boss:
			get_node("/root/Music").set_context("boss")
		else:
			get_node("/root/Music").set_context("combat")
	if is_boss:
		# Endless-mode boss arenas pull from the depth-aware generator so each
		# sector escalates. sector_depth = sectors_cleared + 1 (1-based for
		# scaling); level_index uses combats_in_sector so the boss inherits
		# the depth the player just played through.
		var sd: int = 1
		var li: int = 0
		if has_node("/root/Run"):
			sd = get_node("/root/Run").sectors_cleared + 1
			li = get_node("/root/Run").combats_in_sector
		_current_level = WaveGen.build(sd, li, true)
	elif is_hazard:
		if hazard_subtype == "asteroid_field":
			_current_level = Levels.build_asteroid_field_level()
		elif hazard_subtype == "roster_test":
			_current_level = Levels.build_roster_test()
		else:
			_current_level = Levels.build_minefield_level()
	else:
		# Roman, 2026-05-18: wave_tester stashes V2 knobs on Run via meta.
		# When present, route through WaveGeneratorV2 instead of the
		# existing dynamic generator so the tester knobs take effect.
		if has_node("/root/Run") and get_node("/root/Run").has_meta("wave_v2_knobs"):
			var run = get_node("/root/Run")
			var WaveGenV2 = load("res://scripts/levels/wave_generator_v2.gd")
			var sd_v2: int = int(run.get_meta("wave_v2_sector", 1))
			var knobs: Dictionary = run.get_meta("wave_v2_knobs", {})
			# Single-shot: clear the meta so subsequent combats use the
			# normal dynamic generator.
			run.remove_meta("wave_v2_knobs")
			run.remove_meta("wave_v2_sector")
			_current_level = WaveGenV2.build_combat(sd_v2, knobs)
		else:
			# Standard combat node — dynamic wave generator. First combat
			# in a sector = 2 waves / 1 type; deepens from there.
			var sd: int = 1
			var li: int = 0
			if has_node("/root/Run"):
				sd = get_node("/root/Run").sectors_cleared + 1
				li = get_node("/root/Run").combats_in_sector
			_current_level = WaveGen.build(sd, li, false)
	_run_intro(is_boss)

# ---- Intro sequence -----------------------------------------------------
# Black screen → wipe in to backdrop → player flies in from below → HUD
# flickers on → wave banner → controls live. Total budget: ~3.4s.
func _run_intro(is_boss: bool) -> void:
	# Park player just below the bottom of the viewport, controls disabled.
	var vp := get_viewport_rect().size
	# Park player roughly 30 px above the bottom edge, horizontally centred
	# on the playfield (not the full viewport — gameplay is constrained to
	# a 216-px-wide central band, see scripts/playfield.gd).
	var start_pos := Vector2(Playfield.CENTER.x, vp.y - 30.0)
	if player and is_instance_valid(player):
		player.controls_enabled = false
		player.position = Vector2(start_pos.x, vp.y + 120.0)
	# HUD starts blank — flicker_in will reveal it.
	if $CanvasLayer/UI.has_method("flicker_out"):
		$CanvasLayer/UI.flicker_out(0.001)
	# Wipe from black: instance the scene transition overlay at progress=1 and
	# tween down to 0 — same shader as the inter-scene wipes.
	const SceneTransitionScene = preload("res://scenes/effects/scene_transition.tscn")
	var overlay: CanvasLayer = SceneTransitionScene.instantiate()
	overlay.layer = 80
	add_child(overlay)
	if overlay.has_method("randomize_seed"):
		overlay.randomize_seed()
	if overlay.has_method("set_progress"):
		overlay.set_progress(1.0)
	var wipe_tw := create_tween()
	wipe_tw.tween_method(Callable(overlay, "set_progress"), 1.0, 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	# Slide the player up in parallel with the wipe.
	var slide_tw := create_tween()
	if player and is_instance_valid(player):
		slide_tw.tween_property(player, "position", start_pos, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Mid-slide: flicker the HUD in.
	await get_tree().create_timer(0.9).timeout
	if $CanvasLayer/UI.has_method("flicker_in"):
		$CanvasLayer/UI.flicker_in(0.55)
	# Wait for slide to finish.
	if slide_tw.is_valid():
		await slide_tw.finished
	# Clean up the overlay if still around.
	if is_instance_valid(overlay):
		overlay.queue_free()
	# Hand controls back, kick off waves, fire the first wave banner.
	if player and is_instance_valid(player):
		player.controls_enabled = true
	playing = true
	# WaveDirector emits wave_started immediately, so the banner shows then.
	wave_director.start_level(_current_level)

# ---- Outro sequence -----------------------------------------------------
# 2.5s grace → controls off → HUD flicker out → ship flies up off-screen →
# black wipe → cleared summary screen.
const EXIT_THRUSTER_CLIPS := [
	"res://Sound/exit_thruster_1.ogg",
	"res://Sound/exit_thruster_2.ogg",
]


func _play_exit_thruster_sfx() -> void:
	var pick: String = EXIT_THRUSTER_CLIPS[randi() % EXIT_THRUSTER_CLIPS.size()]
	var stream = load(pick) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Master"
	p.autoplay = false
	add_child(p)
	p.play()
	# Free the player when the clip finishes so we don't pile up.
	p.finished.connect(p.queue_free)


func _run_outro() -> void:
	# Grace period — bullets settle, last shockwave reads. Tuned down from
	# 2.5s after Cody's playtest report that the end-of-sector delay felt
	# long. With the director's POST_CLEAR_GRACE also dropped to 0.4s,
	# total clear-to-summary is ~2.2s instead of 5.4s.
	await get_tree().create_timer(0.8).timeout
	if player == null or not is_instance_valid(player):
		return
	player.controls_enabled = false
	if $CanvasLayer/UI.has_method("flicker_out"):
		$CanvasLayer/UI.flicker_out(0.45)
	# Exit thruster SFX (Roman 2026-05-18). Plays at the start of the
	# fly-out tween — the tween itself is 1.0s, which matches "starts
	# ~1s before the ship leaves the screen." Random pick between the
	# two clips so it doesn't feel repetitive after a few sectors.
	_play_exit_thruster_sfx()
	# Accelerate the player upward and off the screen.
	var vp := get_viewport_rect().size
	var fly_tw := create_tween()
	var target := Vector2(vp.x / 2.0, -120.0)
	fly_tw.tween_property(player, "position", target, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fly_tw.finished
	# Wipe to black.
	const SceneTransitionScene = preload("res://scenes/effects/scene_transition.tscn")
	var overlay: CanvasLayer = SceneTransitionScene.instantiate()
	overlay.layer = 80
	add_child(overlay)
	if overlay.has_method("randomize_seed"):
		overlay.randomize_seed()
	if overlay.has_method("set_progress"):
		overlay.set_progress(0.0)
	var wipe_tw := create_tween()
	wipe_tw.tween_method(Callable(overlay, "set_progress"), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	await wipe_tw.finished
	# Mount the cleared summary on top of the black wipe.
	var summary = ClearedSummaryScene.instantiate()
	add_child(summary)
	# Hazards don't tally enemies or bounty — pass an empty stats dict and
	# 0 bounty, and tell the summary to render the minimal layout.
	# Boss arenas swap the single Sector Map button for an endless-mode
	# Menu / Next Sector pair.
	var is_hazard_level: bool = false
	var was_boss: bool = false
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		is_hazard_level = run.current_node_type == SectorNode.NodeType.HAZARD
		was_boss = run.current_node_type == SectorNode.NodeType.BOSS
	if summary.has_method("populate"):
		if is_hazard_level:
			summary.populate({}, 0, true)
		else:
			summary.populate(_enemy_stats, bounty, false, was_boss)

func _on_start_pressed() -> void:
	new_game()

# When the boss enters the scene tree, hook its health_changed signal so we
# can drive the on-screen HP bar.
func _on_node_added_to_tree(n: Node) -> void:
	if _boss_hooked != null and is_instance_valid(_boss_hooked):
		return
	var sc = n.get_script()
	if sc == null:
		return
	# Walk the inheritance chain so boss subclasses (Reaver, Sentinel, …)
	# also trigger the HP bar — direct resource_path comparison would miss
	# them. Fix: 2026-05-16 boss-bar regression after adding boss subclasses.
	var found_boss: bool = false
	var cur = sc
	while cur != null:
		if cur.resource_path == "res://scripts/boss.gd":
			found_boss = true
			break
		cur = cur.get_base_script()
	if not found_boss:
		return
	# Skip the warmup-only boss instance — it's a hidden shader-compile dummy.
	if n.has_meta("warmup_only"):
		return
	_boss_hooked = n
	if "health_changed" in n and n.health_changed is Signal:
		if not n.health_changed.is_connected(_on_boss_health_changed):
			n.health_changed.connect(_on_boss_health_changed)
	# Boss handles its own black-hole-attack spawn — see boss.gd.
	if boss_label:
		boss_label.visible = true
	if boss_hp_bar:
		boss_hp_bar.visible = true

func _on_boss_health_changed(cur: int, mx: int) -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = mx
		boss_hp_bar.value = cur
		if cur <= 0:
			boss_hp_bar.visible = false
			if boss_label:
				boss_label.visible = false
