extends Node

# Drives enemy spawning for the current level. Reads a LevelData resource,
# walks its waves, spawns enemies on a timer, and emits level_cleared when
# all waves are spawned AND no enemies remain in the "enemies" group.

signal enemy_died(value: int, scene_path: String)
signal enemy_spawned(scene_path: String, bounty_value: int)
signal wave_started(wave_index: int, wave_count: int, silent: bool, announce_text: String)
signal level_cleared

# Banner fade-in+hold+fade-out budget. Director waits this long before the
# first enemy of an ANNOUNCED wave so spawns never overlap the WAVE alert.
const BANNER_HOLD: float = 3.8
# Extra beat after the banner clears before enemies start (Roman, 2026-05-15).
const POST_BANNER_GRACE: float = 0.4
# Grace period AFTER a wave is cleared (all enemies in the group dead) and
# BEFORE the next banner pops. "Wait a beat, show next wave banner."
const POST_CLEAR_GRACE: float = 0.4

@export var level: Resource  # LevelData
@export var auto_start: bool = false

var _running: bool = false
var _wave_index: int = -1
var _spawn_index: int = 0
var _check_clear: bool = false

func start_level(new_level: Resource = null) -> void:
	if new_level != null:
		level = new_level
	if level == null or level.waves.is_empty():
		push_warning("WaveDirector: no level / no waves")
		return
	_running = true
	_wave_index = -1
	_spawn_index = 0
	_check_clear = false
	_advance_to_next_wave()

func stop() -> void:
	_running = false
	_check_clear = false

func _advance_to_next_wave() -> void:
	_wave_index += 1
	if _wave_index >= level.waves.size():
		_running = false
		_check_clear = true  # start watching for clear
		return
	var wave: Resource = level.waves[_wave_index]
	var is_silent: bool = false
	if "silent" in wave:
		is_silent = wave.silent
	var announce: String = ""
	if "announce_text" in wave:
		announce = wave.announce_text
	wave_started.emit(_wave_index, level.waves.size(), is_silent, announce)
	# Announced waves wait for the banner to clear before spawning. Silent
	# sub-waves just respect their own spawn_delay (typically short).
	var delay: float = wave.spawn_delay
	if not is_silent:
		delay = max(delay, BANNER_HOLD + POST_BANNER_GRACE)
	await get_tree().create_timer(delay).timeout
	if not _running:
		return
	_spawn_index = 0
	_spawn_next(wave)

func _spawn_next(wave: Resource) -> void:
	if not _running:
		return
	if _spawn_index >= wave.count:
		# Wave done spawning — wait until the playfield is clear of enemies
		# (including cycling ones), then a beat, before advancing. Silent
		# sub-waves skip this so they chain straight into the next batch.
		var is_silent: bool = false
		if "silent" in wave:
			is_silent = wave.silent
		if not is_silent:
			_wait_for_clear_then_advance()
		else:
			_advance_to_next_wave()
		return
	_spawn_enemy(wave, _spawn_index)
	_spawn_index += 1
	# Tandem pairs: spawn the partner immediately at mirrored X so the two
	# streams move in concert. Count is assumed even by the wave generator;
	# if odd, the trailing lone enemy spawns solo at CENTER - offset (its
	# index % 2 == 0 slot).
	if wave.formation == 5 and _spawn_index < wave.count and (_spawn_index % 2) == 1:
		_spawn_enemy(wave, _spawn_index)
		_spawn_index += 1
	await get_tree().create_timer(wave.spawn_interval).timeout
	_spawn_next(wave)


func _wait_for_clear_then_advance() -> void:
	# Poll the enemies group on a short interval. When empty + the cleared
	# grace beat has elapsed, advance.
	while _running and _live_combatants_present():
		await get_tree().create_timer(0.2).timeout
	if not _running:
		return
	await get_tree().create_timer(POST_CLEAR_GRACE).timeout
	if not _running:
		return
	_advance_to_next_wave()

func _spawn_enemy(wave: Resource, index: int) -> void:
	if wave.enemy_scene == null:
		push_warning("WaveDirector: wave %d has no enemy_scene" % _wave_index)
		return
	var enemy = wave.enemy_scene.instantiate()
	# 320×400 internal resolution rework (Roman, 2026-05-17): sprites render
	# at native 1× by default. Per-ship display_scale overrides still apply
	# but are now sized for the new playfield (e.g. boss 1.0 instead of 3.0).
	var s_default: float = 1.0
	if "display_scale" in enemy and enemy.display_scale > 0.0:
		s_default = enemy.display_scale
	enemy.scale = Vector2(s_default, s_default)
	# Apply per-wave overrides
	# All four overrides are guarded with `in` checks so hazard enemies
	# (mines, asteroids, bomblets) can drop the dead compatibility-shim
	# fields. (Roman, 2026-05-16 enemy refactor.)
	if wave.movement_override != null and "movement" in enemy:
		enemy.movement = wave.movement_override
	if wave.shoot_pattern_override != null and "shoot_pattern" in enemy:
		enemy.shoot_pattern = wave.shoot_pattern_override
	# Pattern-claimed intervals are step 1 (pattern owns its rhythm), wave
	# overrides win as step 2. Final precedence: wave > pattern > .tscn
	# default. Works regardless of how shoot_pattern landed on the enemy
	# (authored in .tscn vs assigned just above from wave_override).
	if "shoot_pattern" in enemy and enemy.shoot_pattern != null:
		if "fire_interval_min" in enemy.shoot_pattern \
				and enemy.shoot_pattern.fire_interval_min > 0.0 \
				and "fire_interval_min" in enemy:
			enemy.fire_interval_min = enemy.shoot_pattern.fire_interval_min
		if "fire_interval_max" in enemy.shoot_pattern \
				and enemy.shoot_pattern.fire_interval_max > 0.0 \
				and "fire_interval_max" in enemy:
			enemy.fire_interval_max = enemy.shoot_pattern.fire_interval_max
	if wave.fire_interval_min > 0.0 and "fire_interval_min" in enemy:
		enemy.fire_interval_min = wave.fire_interval_min
	if wave.fire_interval_max > 0.0 and "fire_interval_max" in enemy:
		enemy.fire_interval_max = wave.fire_interval_max
	if wave.max_health > 0 and "max_health" in enemy:
		enemy.max_health = wave.max_health
		if "health" in enemy:
			enemy.health = wave.max_health
	if wave.health_bonus > 0 and "max_health" in enemy:
		enemy.max_health += wave.health_bonus
		if "health" in enemy:
			enemy.health = enemy.max_health
	if wave.bounty_value > 0 and "bounty_value" in enemy:
		enemy.bounty_value = wave.bounty_value
	if wave.shield_charges > 0 and "max_shield" in enemy:
		enemy.max_shield = wave.shield_charges
		enemy.shield = wave.shield_charges
	if wave.recycle_passes >= -1 and "recycle_passes" in enemy:
		enemy.recycle_passes = wave.recycle_passes
	# Sector modifiers — applied last so they stack on top of wave overrides.
	var _run = get_node_or_null("/root/Run")
	if _run and "sector_modifiers" in _run and not _run.sector_modifiers.is_empty():
		_apply_sector_modifiers(enemy, _run.sector_modifiers)
	# Compute spawn x based on formation. Spawn x is confined to the
	# playfield band (Playfield.X_MIN..X_MAX), not the full viewport,
	# so the side gutters stay clear.
	var pad: float = wave.formation_padding
	var x_min: float = Playfield.X_MIN + pad
	var usable_w: float = Playfield.W - pad * 2.0
	var x := 0.0
	var pos: Vector2
	match wave.formation:
		0: # TOP_LEFT_TO_RIGHT
			var t: float = 0.0
			if wave.count > 1:
				t = float(index) / float(wave.count - 1)
			x = x_min + usable_w * t
			pos = Vector2(x, wave.spawn_y)
		1: # TOP_RIGHT_TO_LEFT
			var t: float = 0.0
			if wave.count > 1:
				t = float(index) / float(wave.count - 1)
			x = x_min + usable_w * (1.0 - t)
			pos = Vector2(x, wave.spawn_y)
		2: # TOP_RANDOM
			x = x_min + randf() * usable_w
			pos = Vector2(x, wave.spawn_y)
		3: # TOP_CENTER_OUT
			var center: float = Playfield.CENTER.x
			var step: float = usable_w / maxf(1.0, float(wave.count))
			var offset: float = (float(index) - float(wave.count - 1) * 0.5) * step
			x = center + offset
			pos = Vector2(x, wave.spawn_y)
		5: # TOP_TANDEM_PAIRS — two streams in concert, offset ±tandem_offset_x from CENTER.
			# Even index = left member; odd index = right member of the pair.
			# Both pair members share wave.movement_override (parameters: amplitude,
			# frequency, mirrored). enemy_core duplicates per spawn so per-instance
			# state (_t, _start_x) stays separate, but identical params + same spawn
			# tick = lockstep motion.
			var center: float = Playfield.CENTER.x
			var side: int = -1 if (index % 2) == 0 else 1
			x = center + float(side) * wave.tandem_offset_x
			pos = Vector2(x, wave.spawn_y)
		4: # SIDE_ALTERNATING — alternate sides per spawn; pattern direction is set to match.
			var side: int = 1 if (index % 2) == 0 else -1
			if side > 0:
				x = Playfield.X_MIN - 12.0
			else:
				x = Playfield.X_MAX + 12.0
			pos = Vector2(x, wave.spawn_y)
			# Per-instance direction override; duplicate so siblings don't share state.
			if "movement" in enemy and enemy.movement != null and "direction" in enemy.movement:
				var mv_dup: Resource = enemy.movement.duplicate()
				mv_dup.direction = side
				enemy.movement = mv_dup
		_:
			x = x_min + randf() * usable_w
			pos = Vector2(x, wave.spawn_y)
	# Make the enemy a child of our parent (typically Main) so it lives in the world
	var parent = get_parent()
	parent.add_child(enemy)
	enemy.add_to_group("enemies")
	# Per-instance wave context (e.g. gunship role assignment). Called before
	# start() so the enemy can adjust its settle position before entering.
	if enemy.has_method("on_spawned_in_wave"):
		enemy.on_spawned_in_wave(index, wave.count)
	if enemy.has_method("start"):
		enemy.start(pos)
	elif enemy.has_method("spawn"):
		enemy.spawn(pos)
	else:
		enemy.position = pos
	var scene_path: String = ""
	if wave.enemy_scene:
		scene_path = wave.enemy_scene.resource_path
	var bounty_val: int = 0
	if "bounty_value" in enemy:
		bounty_val = enemy.bounty_value
	enemy_spawned.emit(scene_path, bounty_val)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(scene_path))

func _on_enemy_died(value: int, scene_path: String) -> void:
	enemy_died.emit(value, scene_path)


func _apply_sector_modifiers(enemy: Node, modifiers: Array) -> void:
	for mod in modifiers:
		match mod:
			"shielded":
				if "max_shield" in enemy:
					if enemy.max_shield == 0:
						enemy.max_shield = 1
						if "shield" in enemy:
							enemy.shield = 1
					else:
						var boosted := ceilf(enemy.max_shield * 1.5)
						enemy.max_shield = int(boosted)
						if "shield" in enemy:
							enemy.shield = int(boosted)
			"armored":
				if "damage_reduction" in enemy:
					enemy.damage_reduction = max(enemy.damage_reduction, 0.10)
			"heavily_armored":
				if "damage_reduction" in enemy:
					enemy.damage_reduction = max(enemy.damage_reduction, 0.20)
			"aggressive":
				if enemy.has_node("ShootTimer"):
					var st: Timer = enemy.get_node("ShootTimer")
					st.wait_time = max(0.05, st.wait_time * 0.90)
			"wanted":
				if "bounty_value" in enemy:
					enemy.bounty_value = int(enemy.bounty_value * 1.20)
			"fleeing":
				if "recycle_passes" in enemy:
					enemy.recycle_passes = 0

func _process(_delta: float) -> void:
	if _check_clear:
		if not _live_combatants_present() and not _hazards_present():
			_check_clear = false
			level_cleared.emit()


# True if any "enemies"-group node is alive AND not flagged is_hazard.
# Mines / bomblets / asteroids dropped behind a minelayer don't gate
# wave progression (Cody, 2026-05-18 playtest).
func _live_combatants_present() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if "is_hazard" in n and n.is_hazard:
			continue
		return true
	return false

func _hazards_present() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if "is_hazard" in n and n.is_hazard:
			return true
	return false

func _ready() -> void:
	if auto_start and level != null:
		start_level()
