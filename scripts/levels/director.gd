extends Node

# Drives enemy spawning for the current level. Reads a LevelData resource,
# walks its waves, spawns enemies on a timer, and emits level_cleared when
# all waves are spawned AND no enemies remain in the "enemies" group.

signal enemy_died(value, scene_path)
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

func start_level(new_level = null) -> void:
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
	if wave.fire_interval_min > 0.0 and "fire_interval_min" in enemy:
		enemy.fire_interval_min = wave.fire_interval_min
	if wave.fire_interval_max > 0.0 and "fire_interval_max" in enemy:
		enemy.fire_interval_max = wave.fire_interval_max
	if wave.max_health > 0 and "max_health" in enemy:
		enemy.max_health = wave.max_health
		if "health" in enemy:
			enemy.health = wave.max_health
	if wave.bounty_value > 0 and "bounty_value" in enemy:
		enemy.bounty_value = wave.bounty_value
	# Compute spawn x based on formation
	var viewport_w := get_viewport().get_visible_rect().size.x
	var pad: float = wave.formation_padding
	var usable_w: float = viewport_w - pad * 2.0
	var x := 0.0
	match wave.formation:
		0: # TOP_LEFT_TO_RIGHT
			var t: float = 0.0
			if wave.count > 1:
				t = float(index) / float(wave.count - 1)
			x = pad + usable_w * t
		1: # TOP_RIGHT_TO_LEFT
			var t: float = 0.0
			if wave.count > 1:
				t = float(index) / float(wave.count - 1)
			x = pad + usable_w * (1.0 - t)
		2: # TOP_RANDOM
			x = pad + randf() * usable_w
		3: # TOP_CENTER_OUT
			var center: float = viewport_w * 0.5
			var step: float = usable_w / maxf(1.0, float(wave.count))
			var offset: float = (float(index) - float(wave.count - 1) * 0.5) * step
			x = center + offset
		_:
			x = pad + randf() * usable_w
	var pos := Vector2(x, wave.spawn_y)
	# Make the enemy a child of our parent (typically Main) so it lives in the world
	var parent = get_parent()
	parent.add_child(enemy)
	enemy.add_to_group("enemies")
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

func _on_enemy_died(value, scene_path: String) -> void:
	enemy_died.emit(value, scene_path)

func _process(_delta: float) -> void:
	if _check_clear:
		if not _live_combatants_present():
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

func _ready() -> void:
	if auto_start and level != null:
		start_level()
