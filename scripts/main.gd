extends Node2D

const Levels = preload("res://scripts/levels/levels_v2.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const SectorNode = preload("res://scripts/sector_node.gd")
const WaveBannerScene = preload("res://scenes/hud/wave_banner.tscn")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const ClearedSummaryScene = preload("res://scenes/cleared_summary.tscn")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var bounty: int = 0
# Bounty carry-in from Run at new_game() — subtract from `bounty` at clear
# to compute what was earned in THIS combat/hazard only. Read by the
# cleared summary (e.g. asteroid mining miners-thank-you line).
var _bounty_at_combat_start: int = 0
var playing: bool = false
var _boss_hooked: Node = null
# Per-enemy-type stats: scene_path → {"spawned": int, "killed": int, "bounty": int, "total_bounty": int}
var _enemy_stats: Dictionary = {}
var _current_level = null
# Asteroid Miners event: counts asteroids destroyed this level so the
# clear payout (5 bounty per) can apply. Reset on new_game(); only spent
# when Run.has_meta("asteroid_miners_event").
var _asteroids_killed_this_level: int = 0
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
		"res://scenes/enemies/enemy_drifter.tscn",
		"res://scenes/enemies/enemy_crystal.tscn",
		"res://scenes/enemies/enemy_dart.tscn",
		"res://scenes/enemies/enemy_weaver.tscn",
		"res://scenes/enemies/enemy_hover.tscn",
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
		"res://scenes/enemies/boss_howler.tscn",
		"res://scenes/enemies/boss_voidmaw.tscn",
		"res://scenes/enemies/boss_spinwright.tscn",
		"res://scenes/enemies/boss_conductor.tscn",
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
	# Bounty Board bonus: if the player opted in to a priority target type,
	# apply the multiplier when that enemy type is killed. Meta persists until
	# consumed by a new_run() or until manually cleared — intentional so it
	# survives across the combat the player opts into.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.has_meta("bounty_type_bonus_path") and scene_path != "":
			if scene_path == String(run.get_meta("bounty_type_bonus_path")):
				value = int(ceil(float(value) * float(run.get_meta("bounty_type_bonus_mult", 1.0))))
	bounty += value
	if has_node("/root/Run"):
		get_node("/root/Run").record_kill(value)
	$CanvasLayer/UI.update_score(bounty)
	$Camera2D.add_trauma(0.25)
	if scene_path != "" and _enemy_stats.has(scene_path):
		_enemy_stats[scene_path]["killed"] += 1
		_enemy_stats[scene_path]["total_bounty"] += value
	# Asteroid Miners event tracking — count asteroid kills so the
	# level-cleared payout (5 bounty per asteroid) can apply at the end.
	# Per-kill bounty stays 0 during this run; the event meta flag is
	# set by signal_event._do_freespace_miner.
	if scene_path == "res://scenes/enemies/enemy_asteroid.tscn":
		_asteroids_killed_this_level += 1

func _on_level_cleared() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		# Bump the per-sector combat count, but only for actual combat nodes —
		# bosses end the sector (handled by the endless-mode flow elsewhere),
		# and hazards/signals aren't part of the wave-scaling progression.
		var is_combat_node: bool = (run.current_node_type != SectorNode.NodeType.BOSS) and (run.current_node_type != SectorNode.NodeType.HAZARD)
		if is_combat_node:
			run.combats_in_sector += 1
		# Mark the node completed in the V3 sector cache. The map scene
		# reads this on next entry to render the green progress overlay
		# and unlock the row boss when all POIs are done.
		if String(run.current_node_id) != "":
			run.mark_node_completed(String(run.current_node_id))
		# NOTE: Run.sector_complete() (per-level sectors_cleared bump) is
		# V2-era. Sector advance now happens once all 3 row bosses are
		# defeated — driven by sector_map_v3._advance_if_complete().
		# Asteroid Miners payout — 5 bounty per asteroid destroyed, applied
		# on level clear instead of per-kill. Plants a banner message that
		# sector_map_v3 reads + displays + clears on its next _ready.
		if run.has_meta("asteroid_miners_event"):
			var miner_payout: int = _asteroids_killed_this_level * 5
			if miner_payout > 0:
				bounty += miner_payout
				run.bounty += miner_payout
				$CanvasLayer/UI.update_score(bounty)
			run.set_meta(
				"post_combat_banner",
				"The miners thank you for the help, and transfer your share of credits over. (+%d)" % miner_payout
			)
			run.remove_meta("asteroid_miners_event")
		# Consume per-run flags so they don't leak into the next level.
		run.asteroid_bonus_bounty = 0
		run.combat_intro = ""
		if player and is_instance_valid(player):
			run.current_hull = player.hull
			run.max_hull = player.max_hull
			# Shield fully restores between levels (spec: shield refills on sector map
			# return). Save max_shield so the next combat starts fully shielded.
			run.current_shield = player.max_shield
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
	_current_level = null
	_asteroids_killed_this_level = 0
	if has_node("/root/Run"):
		bounty = get_node("/root/Run").bounty
	_bounty_at_combat_start = bounty
	$CanvasLayer/UI.update_score(bounty)
	if player and is_instance_valid(player):
		player.start()
		if has_node("/root/Run"):
			var run = get_node("/root/Run")
			if run.max_hull > 0:
				player.max_hull = run.max_hull
				player.hull = run.current_hull if run.current_hull > 0 else run.max_hull
			# Shield stomp removed (Bug 2 fix, 2026-05-24): player.start()
			# already wrote max_shield = 3 + shield_cap_mk via
			# apply_run_upgrades() and then shield = max_shield. The previous
			# block here overwrote that with the stale snapshot from the
			# end of the prior combat, silently erasing any Shield Capacity
			# upgrade purchased at the outpost (and never emitting
			# shield_changed, so the HUD pip count stayed wrong).
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
		# Custom-level shortcut: dev menu's "Test Level" stashes the .tres
		# path on Run; load it directly so designers can iterate on a
		# specific wave composition without going through the generator.
		# Single-shot — meta cleared after use.
		if has_node("/root/Run") and get_node("/root/Run").has_meta("custom_level_path"):
			var run = get_node("/root/Run")
			var path: String = String(run.get_meta("custom_level_path", ""))
			run.remove_meta("custom_level_path")
			if path != "" and ResourceLoader.exists(path):
				var lvl = load(path)
				if lvl:
					_current_level = lvl
		if _current_level == null:
			# Standard combat node — dynamic wave generator. First combat
			# in a sector = 2 waves / 1 type; deepens from there.
			var sd: int = 1
			var li: int = 0
			if has_node("/root/Run"):
				sd = get_node("/root/Run").sectors_cleared + 1
				li = get_node("/root/Run").combats_in_sector
			_current_level = WaveGen.build(sd, li, false)
			# Bounty Board extra waves: append additional wave specs consumed
			# from Run meta. Only applies to standard combat nodes (not boss,
			# not hazard, not custom). Consumed after first use.
			if has_node("/root/Run"):
				var run = get_node("/root/Run")
				var extra_waves: int = int(run.get_meta("extra_combat_waves", 0))
				if extra_waves > 0:
					run.remove_meta("extra_combat_waves")
					# Extra waves reuse the last generated wave spec as a template:
					# clone the final wave and append it once per extra wave so the
					# difficulty stays consistent with what the generator produced.
					if _current_level != null and _current_level.waves.size() > 0:
						var template_wave = _current_level.waves[_current_level.waves.size() - 1]
						for _i in range(extra_waves):
							_current_level.waves.append(template_wave.duplicate())
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
	# Fade from black (Roman 2026-05-24: "replace ALL scene transitions with
	# a fade to black"). Same aesthetic as SceneTransition.change_scene's
	# fade-in half. Black ColorRect on a high CanvasLayer, alpha 1.0 -> 0.0.
	var overlay := CanvasLayer.new()
	overlay.layer = 80
	add_child(overlay)
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	overlay.add_child(fade_rect)
	var wipe_tw := create_tween()
	wipe_tw.tween_property(fade_rect, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	# Slide the player up in parallel with the fade.
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
	# Disable player collision IMMEDIATELY so the grace period + fly-out
	# tween can't be interrupted by a stray hazard hit (Roman playtest
	# 2026-05-23: "leaving a level, collision is still on, possible to
	# hit a hazard and die"). Player IS the Area2D — clearing both flags
	# stops bullets/asteroids/mines from registering. Player is freed
	# with the scene on transition, no revert needed.
	if player != null and is_instance_valid(player):
		player.monitoring = false
		player.monitorable = false
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
	# Fade to black (Roman 2026-05-24: replaced fractal wipe with a plain fade,
	# matching SceneTransition.change_scene's fade-out half). The cleared
	# summary is mounted as a sibling on top of the black overlay below, so we
	# don't actually swap scenes here — the data flow (populate(stats,…)) needs
	# the live main scene to hand its enemy tally to the summary.
	var overlay := CanvasLayer.new()
	overlay.layer = 80
	add_child(overlay)
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	overlay.add_child(fade_rect)
	var wipe_tw := create_tween()
	wipe_tw.tween_property(fade_rect, "color:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	await wipe_tw.finished
	# Asteroid-field hazard skips the cleared summary entirely (Roman,
	# 2026-05-24: "this combat doesn't need an event summary/clear screen").
	# Miners thank-you banner is delivered above the sector map instead.
	if has_node("/root/Run"):
		var run_skip = get_node("/root/Run")
		if run_skip.current_node_type == SectorNode.NodeType.HAZARD \
				and String(run_skip.current_hazard_subtype) == "asteroid_field":
			SceneTransition.change_scene(get_tree(), "res://scenes/sector_map_v3.tscn")
			return
	# Mount the cleared summary on top of the black overlay.
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
	# Stash combat-only bounty (delta from start) so the summary can render
	# context lines like the asteroid-mining "miners thank you" message
	# without re-summing _enemy_stats. Persists via Run meta because the
	# summary scene is added as a sibling and reads Run on _ready.
	var combat_bounty_earned: int = max(0, bounty - _bounty_at_combat_start)
	if has_node("/root/Run"):
		get_node("/root/Run").set_meta("last_combat_bounty", combat_bounty_earned)
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
		if cur.resource_path == "res://scripts/enemies/boss_base.gd":
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
