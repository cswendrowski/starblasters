extends "res://scripts/enemies/boss_base.gd"

# Commander — the sector flagship. Mobile sweeper + summoner + area-denial
# hybrid. Signature attack (2026-05-23 rework): launches a Tether Mine
# toward a point in the upper-mid playfield. The mine arrives, activates
# (F0 -> F1 -> F2), and drags the PLAYER with a squiggly red beam until
# the player kills it, contacts it, or its active timer runs out.
# (Voidmaw still uses the old black-hole hazard — that scene is intact.)
#
# 2-phase fight:
#   P1 100→50% — normal cadence, tether mine every 7–11s, minions every 4s.
#   P2  50→0%  — tether mine every 4.5–6.5s, minions every 2.6s,
#                +4 trauma screen shake on entry.
#
# Stats are assigned in _ready() BEFORE super._ready() — never via the
# `<= 0 ? default` pattern (that pattern missed EnemyBase's max_health=1
# default and Commander spawned at 1 HP).

# Minion spawning
@export var minion_scene: PackedScene
@export var minion_movement: Resource = null
@export var minion_spawn_interval: float = 4.0
@export var minions_per_spawn: int = 2
@export var minion_max_alive: int = 6

# Tether-mine attack cadence (designer-tunable). Phase 2 tightens these.
@export var tether_mine_interval_min: float = 7.0
@export var tether_mine_interval_max: float = 11.0

var _minions: Array = []
const TetherMineScene = preload("res://scenes/enemies/tether_mine.tscn")
# Dedicated child Timer for tether-mine cadence. We use a node-bound Timer
# (not get_tree().create_timer()) so that:
#   - exactly one fire is ever pending (cancels itself on restart),
#   - the timer dies with the boss (no warmup-orphan SceneTreeTimers
#     firing on a freed instance — the cause of the "3 mines at start"
#     designer report, 2026-05-24).
var _tether_timer: Timer = null


func _ready() -> void:
	max_health = 160
	bounty_value = 300
	display_scale = 1.0
	# Two-phase fight gated at 50% HP. Phase 0 is the implicit start.
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.5, true, 4.0),
	]
	super._ready()
	# Fallback minion config (wave director can override via @export).
	if minion_scene == null:
		minion_scene = load("res://scenes/enemies/factions/privateer/enemy_dart.tscn")
	if minion_movement == null:
		var Straight = load("res://scripts/enemies/patterns/straight_down.gd")
		var mv = Straight.new()
		mv.speed = 360.0
		minion_movement = mv
	if has_node("MinionTimer"):
		$MinionTimer.wait_time = minion_spawn_interval
		if not $MinionTimer.timeout.is_connected(_on_minion_timer_timeout):
			$MinionTimer.timeout.connect(_on_minion_timer_timeout)
	_tether_timer = Timer.new()
	_tether_timer.one_shot = true
	_tether_timer.timeout.connect(_spawn_tether_mine_attack)
	add_child(_tether_timer)


func start(pos: Vector2) -> void:
	super.start(pos)
	if has_node("MinionTimer"):
		$MinionTimer.start()
	_schedule_next_tether_mine()


# Phase gate — escalate cadence on entry to phase 2.
func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		tether_mine_interval_min = 4.5
		tether_mine_interval_max = 6.5
		minion_spawn_interval = 2.6
		if has_node("MinionTimer"):
			$MinionTimer.wait_time = minion_spawn_interval


# Free minions on death so they don't outlive the boss.
func _on_boss_death() -> void:
	for m in _minions:
		if is_instance_valid(m):
			m.queue_free()
	_minions.clear()


# ---- Tether-mine signature attack -------------------------------------

func _schedule_next_tether_mine() -> void:
	if _dying or _tether_timer == null:
		return
	var t: float = randf_range(tether_mine_interval_min, tether_mine_interval_max)
	# Restarting a Timer cancels any pending fire, guaranteeing exactly one
	# pending mine spawn at all times. Prevents the multi-schedule regression.
	_tether_timer.stop()
	_tether_timer.wait_time = t
	_tether_timer.start()


func _spawn_tether_mine_attack() -> void:
	if _dying:
		return
	_schedule_next_tether_mine()
	var mine = TetherMineScene.instantiate()
	# Target a point in the upper-mid playfield so the beam length is
	# meaningful when the player is in the lower half.
	var target := Vector2(
		Playfield.CENTER.x + randf_range(-40.0, 40.0),
		120.0
	)
	add_world_node_above_backdrop(mine)
	if mine.has_method("start"):
		mine.start(global_position, target)
	else:
		push_warning("tether_mine missing start(pos,target); placing at boss")
		mine.global_position = global_position


# ---- Minion spawn ------------------------------------------------------

func _on_minion_timer_timeout() -> void:
	if _dying or minion_scene == null:
		$MinionTimer.start()
		return
	var live: Array = []
	for m in _minions:
		if is_instance_valid(m):
			live.append(m)
	_minions = live
	if _minions.size() < minion_max_alive:
		var to_spawn: int = min(minions_per_spawn, minion_max_alive - _minions.size())
		for i in range(to_spawn):
			_spawn_minion(i, to_spawn)
	$MinionTimer.start()


func _spawn_minion(index: int, total: int) -> void:
	var m = minion_scene.instantiate()
	m.scale = Vector2(1, 1)
	if "movement" in m and minion_movement != null:
		m.movement = minion_movement
	get_parent().add_child(m)
	m.add_to_group("enemies")
	var spread: float = 60.0
	var t: float = 0.0
	if total > 1:
		t = (float(index) / float(total - 1)) * 2.0 - 1.0
	var spawn_pos = position + Vector2(t * spread, 60.0)
	if m.has_method("start"):
		m.start(spawn_pos)
	else:
		m.position = spawn_pos
	_minions.append(m)
	if "died" in m and m.has_signal("died"):
		m.died.connect(_on_minion_died.bind(m))


func _on_minion_died(_value, m) -> void:
	if has_node("/root/Run") and m != null:
		var bv = 0
		if "bounty_value" in m:
			bv = m.bounty_value
		get_node("/root/Run").record_kill(bv)
