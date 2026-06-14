extends Node2D

const Levels = preload("res://scripts/levels/levels_v2.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const Factions = preload("res://scripts/levels/factions.gd")
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
# Combat screen-space sweeteners (renderer-polish D, 2026-06-11): post-fx band
# (chromatic aberration + explosion ripple) + the low-hull danger pulse. Created
# once, wired to the live player each combat in new_game().
var _postfx: CanvasLayer = null
var _danger: CanvasLayer = null
var playing: bool = false
var _boss_hooked: Node = null
# Per-enemy-type stats: scene_path → {"spawned": int, "killed": int, "bounty": int, "total_bounty": int}
var _enemy_stats: Dictionary = {}
var _current_level = null
# The CombatScore the conductor performs (M5 native emission): built from
# _current_level at the producer chokepoint in new_game(), then start_score()'d.
var _current_score = null
# Missile Cruiser (unattackable background mortar ship): when true, spawn it
# into the Backdrop world AFTER the intro completes. Set by the showcase
# subtype or the Run.set_meta("missile_cruiser", true) one-shot trigger.
var _want_missile_cruiser: bool = false
# Showcase only: keep respawning the cruiser after each fly-through so the
# tuner sees repeated salvos. Off for production one-shot spawns.
var _missile_cruiser_respawn: bool = false
# Seconds to wait AFTER the intro/start_level before spawning the cruiser. 0 =
# immediate (showcase + one-shot meta). The rare in-level encounter sets this so
# the cruiser drifts in a few seconds into the fight, while waves are spawning.
var _missile_cruiser_delay: float = 0.0

# ── Rare in-level Missile Cruiser encounter (Roman 2026-05-31) ──────────────
# On a STANDARD combat level (not boss/hazard/custom) roll a rare chance to
# schedule one cruiser fly-through mid-level, coexisting with the active waves.
# Because the cruiser is NOT in the "enemies" group it never gates wave-clear.
# Base chance per combat node; deeper sectors add a per-sector bonus (capped).
const MISSILE_CRUISER_RARE_CHANCE: float = 0.10        # KNOB: base roll (~10%)
const MISSILE_CRUISER_RARE_PER_SECTOR: float = 0.02    # KNOB: +chance per sector cleared
const MISSILE_CRUISER_RARE_CHANCE_MAX: float = 0.25    # KNOB: chance ceiling
# When the "cruiser_support" sector modifier is active the base chance is
# multiplied by Run.cruiser_encounter_chance_mult() and the ceiling is raised
# to this value so the boost isn't immediately clamped away by the normal cap.
const MISSILE_CRUISER_RARE_CHANCE_MAX_BOOSTED: float = 0.60  # KNOB: boosted ceiling
const MISSILE_CRUISER_MIN_SECTORS: int = 0             # KNOB: only after N sectors cleared
const MISSILE_CRUISER_SPAWN_DELAY: float = 4.0         # KNOB: seconds into the fight
# Asteroid Miners event: counts asteroids destroyed this level so the
# clear payout (5 bounty per) can apply. Reset on new_game(); only spent
# when Run.has_meta("asteroid_miners_event").
var _asteroids_killed_this_level: int = 0
var _level_time: float = 0.0   # active-combat seconds this level (run-timer accumulator)
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
	# Swap the baked default ship (A) for the player's chosen variant BEFORE any player wiring
	# below runs — reassigns `player` so the damage/HUD hookups (and new_game) use the new node.
	_install_chosen_player()
	game_over.hide()
	start_button.hide()
	# Warmup must defer — at _ready() the SceneTree is still building the
	# initial scene, so add_child fails with "busy setting up children".
	# Deferring also means new_game() (line below) has already built
	# _current_level by the time the warmup runs, so it can warm the level's
	# real enemy/weapon set rather than a stale hardcoded list.
	call_deferred("_warm_up_level")
	# Wreck layer (Roman 2026-06-10): the inert-drift death presentation (currently fed only by the
	# EM Torpedo). Created empty every combat — harmless if nothing uses it. Deferred so the Backdrop
	# coordinator has populated + graded the near parallax layer we match against.
	call_deferred("_ensure_wreck_layer")
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
	# Run-summary Phase 1: tally damage taken (shield vs hull) off the existing
	# Player.damaged signal (0 = shield-absorbed, 1 = hull-loss).
	if player and is_instance_valid(player) and player.has_signal("damaged"):
		if not player.damaged.is_connected(_on_player_damaged_stat):
			player.damaged.connect(_on_player_damaged_stat)
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


# Replace the scene's baked default Player (ship A) with the variant the player chose in the
# ship-select modal (Run.ship_variant: 0=A / 1=B / 2=C). No-op for variant 0 — the baked node
# already IS ship A, so most runs skip the swap entirely. Adds the new node to Main during _ready
# (safe — same as _install_playfield_frame's add_child(self)); re-wires the three signals the
# .tscn hard-wired off the old Player node, then reassigns the `player` member.
func _install_chosen_player() -> void:
	# get_node, NOT the bare `Run` identifier — bare autoload names fail to COMPILE in contexts
	# where autoloads aren't registered (-s tools, compile_check), which is why the whole codebase
	# uses the /root path (house convention; gate-hardening find 2026-06-10).
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var variant: int = int(run.ship_variant)
	if variant == 0:
		return   # baked Player is already ship A
	if not (player and is_instance_valid(player)):
		return
	var scene: PackedScene = load(run.player_scene_path())
	if scene == null:
		return
	var idx: int = player.get_index()
	var pos: Vector2 = player.position
	player.free()   # immediate (not queue_free) so the "Player" name frees for the new node
	var np: Node = scene.instantiate()
	np.name = "Player"
	add_child(np)
	move_child(np, idx)
	if np is Node2D:
		(np as Node2D).position = pos
	# Re-create the connections the .tscn baked onto the old Player node.
	np.died.connect(_on_player_died)
	if has_node("CanvasLayer/UI"):
		var ui := $CanvasLayer/UI
		np.hull_changed.connect(ui.update_hull)
		np.shield_changed.connect(ui.update_shield)
	player = np


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
	var glass_layer = CanvasLayer.new()
	glass_layer.name = "PlayfieldGlass"
	glass_layer.layer = 1
	add_child(glass_layer)

	var glass_bg = Color(0.04, 0.06, 0.10, 0.55)
	var glass_edge = UiTheme.COLOR_ACCENT_DIM
	for spec in [
		{"name": "GutterLeft",  "x": 0.0,             "w": Playfield.X_MIN,           "edge": "right"},
		{"name": "GutterRight", "x": Playfield.X_MAX, "w": 480.0 - Playfield.X_MAX,   "edge": "left"},
	]:
		var panel = Panel.new()
		panel.name = String(spec["name"])
		panel.position = Vector2(float(spec["x"]), 0.0)
		panel.size = Vector2(float(spec["w"]), 270.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gsb = StyleBoxFlat.new()
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
	var frame_layer = CanvasLayer.new()
	frame_layer.name = "PlayfieldFrame"
	frame_layer.layer = 10
	add_child(frame_layer)

	var frame = Panel.new()
	frame.name = "Frame"
	frame.position = Vector2(Playfield.X_MIN, Playfield.Y_MIN)
	frame.size = Vector2(Playfield.W, Playfield.H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
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

# Every gameplay shader. Under gl_compatibility a shader PROGRAM compiles the
# first frame any material using it is drawn, so the first bullet impact / first
# shot / first damage-tell each cost a frame spike. Compilation is per-program
# (not per-material-instance), so we can pre-pay it on a throwaway ColorRect
# instead of needing to reproduce the gameplay event that normally triggers it.
# This is what closes the hit_flash / torch / shield holes the old enemy-only
# warmup left open.
const _WARMUP_SHADERS := [
	"res://graphics/hit_flash.gdshader",       # first bullet impact
	"res://graphics/pixelated_burn.gdshader",  # first death
	"res://graphics/damage_noise.gdshader",    # enemy damage overlay
	"res://graphics/hex_shield.gdshader",       # first shielded enemy / player shield
	"res://graphics/torch_fire.gdshader",      # first hull-loss damage tell
	"res://scripts/effects/glow_halo.gdshader",# bullet glow
	"res://shaders/outline_1px.gdshader",      # enemy hull outline
]

func _warm_up_level() -> void:
	# Two-part, level-driven warmup, run deferred during the intro fly-in
	# (playing == false) so it's free cover, and spread across frames so the
	# warmup itself never produces the spike it's meant to prevent.
	#   A) Compile every gameplay shader program directly (ColorRect dummies).
	#   B) Pre-instantiate THIS level's actual enemy/boss scenes + the player's
	#      equipped projectiles off-screen so their textures upload to VRAM and
	#      burn/explosion CPU particles initialise before the first spawn/shot.
	if not is_inside_tree():
		return
	var WARM_DIR := Vector2(-9999, -9999)
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	var BurnFx = load("res://scripts/burn_fx.gd")
	var to_free: Array = []

	# --- A: direct shader-program compile ---
	# A bare ColorRect carrying the ShaderMaterial issues one draw call, which
	# is all gl_compatibility needs to compile the program. modulate.a ~ 0 keeps
	# it invisible but still drawn (a hidden node skips the draw pass and would
	# never compile — the lingering-hitch trap from the earlier passes).
	for sp in _WARMUP_SHADERS:
		var shader = load(sp)
		if shader == null:
			continue
		var rect := ColorRect.new()
		rect.size = Vector2(8, 8)
		rect.position = WARM_DIR
		var mat := ShaderMaterial.new()
		mat.shader = shader
		rect.material = mat
		rect.modulate = Color(1, 1, 1, 0.001)
		rect.set_meta("warmup_only", true)
		get_tree().root.add_child(rect)
		to_free.append(rect)

	# Pre-fire one explosion to init the CPU-particle path (all explosions 1×
	# since Roman 2026-05-18, so a single warmup variant suffices).
	var warm_explosion = ExplosionFx.play(WARM_DIR, 1.0, true, null, null, false)  # silent warmup
	if warm_explosion:
		warm_explosion.modulate = Color(1, 1, 1, 0.001)
		warm_explosion.set_meta("warmup_only", true)

	# --- B: pre-instantiate the level's real content ---
	# Dedup the scene set from the live wave plan (covers faction variants +
	# boss exactly as they'll spawn) plus the player's equipped projectiles
	# (the old warmup only ever covered the stock bullet, so a non-default
	# weapon's first shot compiled its glow live).
	var scene_paths := {
		"res://scenes/projectiles/bullet_blaster.tscn": true,        # stock player bullet
		"res://scenes/projectiles/enemy_bullet.tscn": true,  # shared enemy bullet
	}
	if _current_level != null and "waves" in _current_level:
		for w in _current_level.waves:
			if w != null and w.enemy_scene is PackedScene:
				scene_paths[w.enemy_scene.resource_path] = true
	if player and is_instance_valid(player):
		for ps in [player.bullet_scene, player.secondary_bullet_scene]:
			if ps is PackedScene:
				scene_paths[ps.resource_path] = true

	# Instantiate in small batches, yielding a frame between them so a big
	# roster never stalls. Off-screen, drawn (alpha ~0) for VRAM upload, with
	# process disabled so nothing ticks or fires.
	var batch := 0
	for path in scene_paths.keys():
		if not is_inside_tree():
			break
		var ps2 = load(path)
		if ps2 == null:
			continue
		var inst = ps2.instantiate()
		inst.process_mode = Node.PROCESS_MODE_DISABLED
		inst.visible = true
		inst.modulate = Color(1, 1, 1, 0.001)
		inst.position = WARM_DIR
		inst.set_meta("warmup_only", true)
		get_tree().root.add_child(inst)
		var sprite = inst.get_node_or_null("Sprite2D")
		if sprite and sprite is Sprite2D:
			BurnFx.apply_burn(sprite, 0.05)
		to_free.append(inst)
		batch += 1
		if batch % 3 == 0:
			await get_tree().process_frame

	# Let the last batch draw once (compile + upload) before teardown.
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()


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
	var banner = WaveBannerScene.instantiate()
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

func _on_enemy_died(value: int, scene_path: String) -> void:
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
		var _r = get_node("/root/Run")
		_r.record_kill(value)
		# Run-summary Phase 2: count cleared mines (by scene basename). Precise match
		# so the privateer "enemy_minelayer" SHIP isn't counted as a mine.
		var _fn: String = scene_path.get_file()
		if (_fn.begins_with("enemy_mine") and not _fn.begins_with("enemy_minelayer")) or _fn.begins_with("tether_mine"):
			_r.stat_add("mines_cleared", 1)
	# Phase Shift mode refills its charges on player-caused kills — this hook fires
	# only on real deaths (same path as bounty), so off-screen departs don't count.
	if is_instance_valid(player) and player.has_method("on_enemy_killed"):
		player.on_enemy_killed()
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

func _process(delta: float) -> void:
	# Run timer (Phase 1): accumulate ACTIVE combat seconds only. main is
	# PROCESS_MODE_PAUSABLE so paused time auto-excludes; `playing` is false during
	# the intro (set true at level start) so intro is excluded. _level_time is
	# committed to Run + zeroed in _on_level_cleared (BEFORE the outro), so any
	# outro/transition seconds that accumulate afterward are discarded by the next
	# level's reset rather than committed. NOTE: if a second commit point is ever
	# added (e.g. on sector-map entry), gate this on a "level live" flag to avoid
	# double-counting the outro.
	if playing:
		_level_time += delta


# Tally a damage event for the run summary: 0 = shield absorbed, 1+ = hull loss.
func _on_player_damaged_stat(amount: int) -> void:
	if not has_node("/root/Run"):
		return
	get_node("/root/Run").stat_add("damage_shield" if amount == 0 else "damage_hull", 1)


func _on_level_cleared() -> void:
	# Decompress the music to Intensity_1 the moment the level clears (Roman 2026-06-10 ramp).
	if has_node("/root/Music"):
		get_node("/root/Music").ramp_down()
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
		# Hazard-clear bounty (Roman 2026-06-08): hazard fields (asteroid/minefield)
		# otherwise pay 0 per-kill bounty — a flat +25 on clear so they're worth running.
		if run.current_node_type == SectorNode.NodeType.HAZARD:
			bounty += 25
			run.bounty += 25
			$CanvasLayer/UI.update_score(bounty)
			run.set_meta("post_combat_banner", "Hazard field cleared. (+25)")
		# Run-summary Phase 1: roll this level's active-combat time + asteroid count
		# into the run-wide accumulators before the per-level counters reset.
		run.run_time_seconds += _level_time
		run.stat_add("asteroids", _asteroids_killed_this_level)
		# Stash this level's clear-time for the cleared summary header (worklist
		# #37) before the accumulator resets.
		run.set_meta("last_combat_clear_time", _level_time)
		_level_time = 0.0
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
			# Internal Micro Fabricator (module): restock a slice of max ammo on clear,
			# topping up the persistent primary + secondary pools for the next level.
			if player.module_ammo_restore_pct > 0.0:
				run.restock_ammo_fraction(player.module_ammo_restore_pct)
	_run_outro()

func _on_player_died() -> void:
	playing = false
	# Run-summary: flush the partial level's active time into the run total.
	if has_node("/root/Run"):
		get_node("/root/Run").run_time_seconds += _level_time
	_level_time = 0.0
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

# Create the combat screen-space overlays once + (re)wire them to the live player.
# Safe to call every combat: the nodes are built lazily, and the danger-pulse hull
# hook guards against a double-connect when the player persists across levels.
func _ensure_combat_overlays() -> void:
	if _postfx == null or not is_instance_valid(_postfx):
		var PostFx = load("res://scripts/effects/combat_postfx.gd")
		_postfx = PostFx.new()
		_postfx.name = "CombatPostFx"
		add_child(_postfx)
	if _danger == null or not is_instance_valid(_danger):
		var Danger = load("res://scripts/effects/danger_pulse.gd")
		_danger = Danger.new()
		_danger.name = "DangerPulse"
		add_child(_danger)
	if player != null and is_instance_valid(player):
		_postfx.set_player(player)
		if not player.hull_changed.is_connected(_danger.on_hull_changed):
			player.hull_changed.connect(_danger.on_hull_changed)


func new_game() -> void:
	bounty = 0
	_enemy_stats.clear()
	_current_level = null
	_current_score = null
	_asteroids_killed_this_level = 0
	# M6b: clear any prior level's faction so boss/hazard/custom levels carry none;
	# the standard-combat branch sets it for this level (read per spawn by the director).
	if has_node("/root/Run"):
		get_node("/root/Run").set_meta("active_faction", -1)
	if has_node("/root/Run"):
		bounty = get_node("/root/Run").bounty
	_bounty_at_combat_start = bounty
	$CanvasLayer/UI.update_score(bounty)
	_ensure_combat_overlays()
	if player and is_instance_valid(player):
		player.start()
		if has_node("/root/Run"):
			var run = get_node("/root/Run")
			# Hull stomp removed (Bug fix, 2026-05-27): apply_run_upgrades()
			# already set player.max_hull = 3 + hull_mk. Stomping it with
			# run.max_hull would use the stale snapshot and erase any Hull
			# upgrade purchased at the outpost -- same bug as the shield stomp
			# removed 2026-05-24. Only hull (current) is loaded from Run,
			# clamped to the freshly-computed max_hull from apply_run_upgrades.
			if run.current_hull > 0:
				player.hull = mini(run.current_hull, player.max_hull)
			# else: hull stays at max_hull (first combat of a fresh run).
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
	var is_boss = false
	var is_hazard = false
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
		wave_director.max_concurrent = WaveGen.cap_for(sd, li)
	elif is_hazard:
		if hazard_subtype == "asteroid_field":
			# Hazards are now phrase-native CombatScores (lane-shaped drops +
			# breathers); set _current_score directly so the chokepoint below
			# (which only adapts a LevelData) leaves it untouched.
			_current_score = Levels.build_asteroid_field_score()
		elif hazard_subtype == "roster_test":
			_current_level = Levels.build_roster_test()
		elif hazard_subtype == "firecore_drone_showcase":
			_current_level = Levels.build_firecore_drone_showcase()
		elif hazard_subtype == "beam_showcase":
			_current_level = Levels.build_beam_showcase()
		elif hazard_subtype == "missile_cruiser_showcase":
			_current_level = Levels.build_missile_cruiser_showcase()
			# Showcase: spawn the (unattackable, non-wave) cruiser into the world
			# and keep respawning it after each fly-through so Roman can watch
			# repeated salvos for tuning (production spawns are one-shot).
			_want_missile_cruiser = true
			_missile_cruiser_respawn = true
		else:
			_current_score = Levels.build_minefield_score()
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
			var faction: int = -1
			if has_node("/root/Run"):
				var rsd = get_node("/root/Run")
				sd = rsd.sectors_cleared + 1
				li = rsd.combats_in_sector
				# M6b: faction is now stored ON the combat node (assigned at cache build)
				# so the map decoration and the actual fight agree (Roman 2026-06-11).
				# Read the current node's faction; fall back to the legacy per-level pick
				# if the node carries none (e.g. a node from an older cache).
				faction = rsd.get_node_faction(rsd.current_node_id)
				if faction < 0:
					faction = Factions.pick_for_level(sd, li, int(rsd.run_seed))
				# Dev override: Test Combat -> Faction... forces a specific faction so all
				# four can be eyeballed on demand (persists across levels until cleared).
				if rsd.has_meta("forced_faction"):
					faction = int(rsd.get_meta("forced_faction", faction))
				rsd.set_meta("active_faction", faction)
			_current_level = WaveGen.build(sd, li, false, faction)
			wave_director.max_concurrent = WaveGen.cap_for(sd, li)
			# Rare ambient encounter: roll for a mid-level Missile Cruiser
			# fly-through. STANDARD combat nodes only (we're in the generator
			# sub-branch, so not boss/hazard/custom). Chance scales with sector
			# depth (capped). Plain randf() (per the task — deterministic seeding
			# off run_seed alone would make it all-or-nothing across the run).
			# Skipped if a one-shot/showcase cruiser is already wanted.
			if not _want_missile_cruiser:
				_maybe_schedule_rare_cruiser(sd)
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
	# Missile Cruiser one-shot trigger: Run.set_meta("missile_cruiser", true)
	# spawns the unattackable background mortar ship into the world after the
	# intro. Consumed (removed) on read so it fires exactly once. Applies to any
	# combat/hazard node, not just the showcase.
	if has_node("/root/Run"):
		var mc_run = get_node("/root/Run")
		if mc_run.has_meta("missile_cruiser"):
			mc_run.remove_meta("missile_cruiser")
			_want_missile_cruiser = true
			# Explicit one-shot trigger spawns immediately (override any rare-roll
			# delay/respawn scheduled above for the same standard-combat node).
			_missile_cruiser_delay = 0.0
			_missile_cruiser_respawn = false
	# Producer chokepoint (M5 native emission, finding §0.9): every LevelData
	# originates above; lift it to the CombatScore the conductor performs HERE, at the
	# producer boundary, instead of the director doing it transiently in start_level.
	# Combat/boss/hazard/custom all converge here. (The dev Combat Slice authors its
	# own score in _run_intro and bypasses this.)
	if _current_level != null:
		_current_score = ScoreAdapter.from_level_data(_current_level)
	_run_intro(is_boss)

# ---- Intro sequence -----------------------------------------------------
# Black screen → wipe in to backdrop → player flies in from below → HUD
# flickers on → wave banner → controls live. Total budget: ~3.4s.
func _run_intro(is_boss: bool) -> void:
	# Park player just below the bottom of the viewport, controls disabled.
	var vp = get_viewport_rect().size
	# Park player roughly 30 px above the bottom edge, horizontally centred
	# on the playfield (not the full viewport — gameplay is constrained to
	# a 216-px-wide central band, see scripts/playfield.gd).
	var start_pos = Vector2(Playfield.CENTER.x, vp.y - 30.0)
	if player and is_instance_valid(player):
		player.controls_enabled = false
		player.position = Vector2(start_pos.x, vp.y + 120.0)
	# HUD starts blank — flicker_in will reveal it.
	if $CanvasLayer/UI.has_method("flicker_out"):
		$CanvasLayer/UI.flicker_out(0.001)
	# Fade from black (Roman 2026-05-24: "replace ALL scene transitions with
	# a fade to black"). Same aesthetic as SceneTransition.change_scene's
	# fade-in half. Black ColorRect on a high CanvasLayer, alpha 1.0 -> 0.0.
	var overlay = CanvasLayer.new()
	overlay.layer = 80
	add_child(overlay)
	var fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	overlay.add_child(fade_rect)
	var wipe_tw = create_tween()
	wipe_tw.tween_property(fade_rect, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	# Slide the player up in parallel with the fade.
	var slide_tw = create_tween()
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
	_level_time = 0.0  # start this level's run-timer accumulator
	# WaveDirector emits wave_started immediately, so the banner shows then.
	# Dev "Combat Slice": route a hand-authored CombatScore (formations + filler +
	# breathers) through the conductor instead of the generated level. Single-shot.
	if has_node("/root/Run") and get_node("/root/Run").get_meta("combat_slice", false):
		get_node("/root/Run").remove_meta("combat_slice")
		wave_director.start_score(CombatSlice.build())
	elif _current_score != null:
		# Native path (M5): the producer chokepoint already built the CombatScore.
		wave_director.start_score(_current_score)
	else:
		# Fallback for any LevelData that skipped the chokepoint (defensive).
		wave_director.start_level(_current_level)
	# Spawn the unattackable background Missile Cruiser now that the Backdrop +
	# player + camera all exist (deferred from level selection).
	if _want_missile_cruiser:
		_want_missile_cruiser = false
		var mc_delay: float = _missile_cruiser_delay
		_missile_cruiser_delay = 0.0
		if mc_delay > 0.0:
			# Rare in-level encounter: drift in a few seconds into the fight while
			# waves are spawning. Guard the callback against teardown (timer can
			# fire after a scene change / outro) and require playing == true.
			var tree: SceneTree = get_tree()
			if tree != null:
				var t: SceneTreeTimer = tree.create_timer(mc_delay)
				t.timeout.connect(func() -> void:
					if playing and is_inside_tree() and get_tree() != null:
						_spawn_missile_cruiser()
				)
		else:
			_spawn_missile_cruiser()


# Spawn a MISSILE CRUISER into the world above the parallax backdrop. It is a
# plain Node2D (NOT in the "enemies" group) so it never gates wave-clear. It
# starts at a random X in the gameplay band; the script picks its entry edge
# (top/bottom) and parks itself off-screen in _ready(). Parents under the
# scene's "Backdrop" Node2D (above parallax, below ships, world space) — same
# seam as boss_base.add_world_node_above_backdrop. World coords == playfield
# coords because the combat camera is centred on (240,135).
const MISSILE_CRUISER_SCENE := preload("res://scenes/enemies/core/missile_cruiser.tscn")
const MidDepthPresentation = preload("res://scripts/effects/mid_depth_presentation.gd")
const WreckLayerScript = preload("res://scripts/effects/wreck_layer.gd")


# Create the wreck layer above the backdrop (idempotent). Enemies that die via the wreck-drift
# death style reparent their hull sprite into it. See scripts/effects/wreck_layer.gd.
func _ensure_wreck_layer() -> void:
	WreckLayerScript.ensure(self)


# Roll the rare in-level encounter. `sector_depth` is sectors_cleared + 1 (the
# value the wave generator was built against). On success, schedule a single
# (non-respawning) cruiser to drift in MISSILE_CRUISER_SPAWN_DELAY seconds into
# the fight via the deferred spawn site in _run_intro. Gated to deeper sectors
# via MISSILE_CRUISER_MIN_SECTORS; chance ramps with depth up to the cap.
func _maybe_schedule_rare_cruiser(sector_depth: int) -> void:
	var sectors_cleared: int = maxi(0, sector_depth - 1)
	if sectors_cleared < MISSILE_CRUISER_MIN_SECTORS:
		return
	var chance: float = MISSILE_CRUISER_RARE_CHANCE \
		+ MISSILE_CRUISER_RARE_PER_SECTOR * float(sectors_cleared)
	# "cruiser_support" sector modifier: cruisers patrol this sector, so any
	# cruiser encounter is more likely. Route through the Run seam so future
	# cruiser-flavored encounters can reuse the same modifier-governed knob.
	# mult is 1.0 (no-op) when the modifier is absent — base behavior unchanged.
	var cap: float = MISSILE_CRUISER_RARE_CHANCE_MAX
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		var mult: float = run.cruiser_encounter_chance_mult()
		chance *= mult
		if mult > 1.0:
			cap = MISSILE_CRUISER_RARE_CHANCE_MAX_BOOSTED
	chance = minf(chance, cap)
	if randf() < chance:
		_want_missile_cruiser = true
		_missile_cruiser_respawn = false  # rare = exactly one fly-through
		_missile_cruiser_delay = MISSILE_CRUISER_SPAWN_DELAY


func _spawn_missile_cruiser() -> void:
	var cruiser: Node2D = MISSILE_CRUISER_SCENE.instantiate() as Node2D
	if cruiser == null:
		return
	# Random X within the gameplay band so salvos are centred on the playfield.
	cruiser.position = Vector2(randf_range(Playfield.X_MIN, Playfield.X_MAX), 0.0)
	# Parent above the parallax backdrop but below the ships via the shared
	# faked-mid-depth helper (same seam boss hazards use). Tree order alone gives
	# the correct mid-depth — Backdrop's layers are all z=0 and it's an earlier
	# sibling of Player in main.tscn, so no z_index override is needed.
	MidDepthPresentation.add_above_backdrop(self, cruiser)
	# Showcase: respawn another cruiser shortly after this one frees itself
	# (it queue_free()s when it traverses off the far edge) so the tuner sees
	# a continuous stream of salvos. Guarded by `playing` so it stops on outro.
	if _missile_cruiser_respawn:
		cruiser.tree_exited.connect(_on_missile_cruiser_freed)


func _on_missile_cruiser_freed() -> void:
	if not _missile_cruiser_respawn or not playing:
		return
	# Guard against teardown: tree_exited can fire while the whole scene is
	# being freed (scene change / app quit), when get_tree() is already null.
	var tree: SceneTree = get_tree()
	if tree == null or not is_inside_tree():
		return
	# Brief gap before the next fly-through.
	var t: SceneTreeTimer = tree.create_timer(1.5)
	t.timeout.connect(func() -> void:
		if _missile_cruiser_respawn and playing:
			_spawn_missile_cruiser()
	)

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
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
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
	if is_instance_valid(player):
		player.stop_all_weapon_audio()
	player.controls_enabled = false
	if $CanvasLayer/UI.has_method("flicker_out"):
		$CanvasLayer/UI.flicker_out(0.45)
	# Exit thruster SFX (Roman 2026-05-18). Plays at the start of the
	# fly-out tween — the tween itself is 1.0s, which matches "starts
	# ~1s before the ship leaves the screen." Random pick between the
	# two clips so it doesn't feel repetitive after a few sectors.
	_play_exit_thruster_sfx()
	# Accelerate the player upward and off the screen.
	var vp = get_viewport_rect().size
	var fly_tw = create_tween()
	var target = Vector2(vp.x / 2.0, -120.0)
	fly_tw.tween_property(player, "position", target, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fly_tw.finished
	# Fade to black (Roman 2026-05-24: replaced fractal wipe with a plain fade,
	# matching SceneTransition.change_scene's fade-out half). The cleared
	# summary is mounted as a sibling on top of the black overlay below, so we
	# don't actually swap scenes here — the data flow (populate(stats,…)) needs
	# the live main scene to hand its enemy tally to the summary.
	var overlay = CanvasLayer.new()
	overlay.layer = 80
	add_child(overlay)
	var fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	overlay.add_child(fade_rect)
	var wipe_tw = create_tween()
	wipe_tw.tween_property(fade_rect, "color:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	await wipe_tw.finished
	# Asteroid-field hazard skips the cleared summary entirely (Roman,
	# 2026-05-24: "this combat doesn't need an event summary/clear screen").
	# Miners thank-you banner is delivered above the sector map instead.
	if has_node("/root/Run"):
		var run_skip = get_node("/root/Run")
		if run_skip.current_node_type == SectorNode.NodeType.HAZARD \
				and String(run_skip.current_hazard_subtype) == "asteroid_field":
			# Route through the HD host (SectorMapRoute), not the raw inner map — loading
			# sector_map_v3.tscn directly was the "old sector map" round-trip after an
			# asteroid hazard (Roman 2026-06-08).
			SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)
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
