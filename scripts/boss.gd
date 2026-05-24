extends "res://scripts/enemies/boss_base.gd"

# Commander — the sector flagship. Mobile sweeper + summoner + area-denial
# hybrid. Signature attack: charge a small black hole in front of the
# boss, fire it straight down to the player's Y, then detonate it as a
# kinematic pull well that holds the player in place for a heartbeat.
#
# 2-phase fight (added 2026-05-24):
#   P1 100→50% — normal cadence, BH charge 2.5s, minion interval 4s.
#   P2  50→0%  — BH charge tightens to 1.8s, minions every 2.6s, +4 trauma
#                screen shake on entry.
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

# Mini-black-hole attack
@export var black_hole_interval_min: float = 7.0
@export var black_hole_interval_max: float = 11.0
@export var black_hole_radius: float = 140.0
@export var black_hole_lifetime: float = 4.5
@export var black_hole_pull: float = 1100.0

var _minions: Array = []
var _charging_bh: Node2D = null
const BlackHoleScene = preload("res://scenes/hazards/black_hole.tscn")

# Black-hole attack timings. CHARGE_TIME is a var (not const) so the
# phase-2 gate can tighten it. Other values are stable across phases.
var bh_charge_time: float = 2.5
const BH_DETONATE_GROW_TIME: float = 0.6
const BH_START_SCALE: float = 0.125
const BH_CHARGED_SCALE: float = 0.1875
const BH_DETONATE_SCALE: float = 1.125
const BH_FIRE_SPEED: float = 220.0
const BH_FALLBACK_TRAVEL_TIME: float = 1.5


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
		minion_scene = load("res://scenes/enemies/enemy_dart.tscn")
	if minion_movement == null:
		var Straight = load("res://scripts/enemies/patterns/straight_down.gd")
		var mv = Straight.new()
		mv.speed = 360.0
		minion_movement = mv
	if has_node("MinionTimer"):
		$MinionTimer.wait_time = minion_spawn_interval
		if not $MinionTimer.timeout.is_connected(_on_minion_timer_timeout):
			$MinionTimer.timeout.connect(_on_minion_timer_timeout)
	_schedule_next_black_hole()


func start(pos: Vector2) -> void:
	super.start(pos)
	if has_node("MinionTimer"):
		$MinionTimer.start()


func _process(delta: float) -> void:
	super._process(delta)
	if _dying:
		return
	# While charging, the hole sticks to a fixed offset in front of the boss
	# so it tracks the boss's drift instead of being locked to its spawn
	# point.
	if _charging and _charging_bh != null and is_instance_valid(_charging_bh):
		_charging_bh.global_position = global_position + Vector2(0, 60.0)


# Phase gate — escalate cadence on entry to phase 2.
func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		bh_charge_time = 1.8
		minion_spawn_interval = 2.6
		if has_node("MinionTimer"):
			$MinionTimer.wait_time = minion_spawn_interval


# Free minions on death so they don't outlive the boss.
func _on_boss_death() -> void:
	for m in _minions:
		if is_instance_valid(m):
			m.queue_free()
	_minions.clear()


# ---- Black-hole signature attack ---------------------------------------

func _schedule_next_black_hole() -> void:
	if _dying:
		return
	var t: float = randf_range(black_hole_interval_min, black_hole_interval_max)
	get_tree().create_timer(t).timeout.connect(_spawn_black_hole_attack)


func _spawn_black_hole_attack() -> void:
	if _dying:
		return
	_schedule_next_black_hole()
	_run_black_hole_sequence()


func _run_black_hole_sequence() -> void:
	_charging = true
	var bh = BlackHoleScene.instantiate()
	bh.radius = black_hole_radius
	bh.lifetime = 999.0
	bh.fade_time = 0.05
	bh.visual_scale = 1.0
	bh.pull_strength = 0.0
	bh.position = global_position + Vector2(0, 60.0)
	bh.scale = Vector2(BH_START_SCALE, BH_START_SCALE)
	add_world_node_above_backdrop(bh)
	_charging_bh = bh
	await get_tree().process_frame
	if _dying or not is_instance_valid(bh):
		_charging = false
		_charging_bh = null
		return

	# Phase 1 — CHARGE. Boss _process keeps bh.global_position stuck in
	# front of the boss while _charging is true.
	var t_charge := create_tween()
	t_charge.tween_property(bh, "scale",
		Vector2(BH_CHARGED_SCALE, BH_CHARGED_SCALE), bh_charge_time)
	await t_charge.finished
	if _dying or not is_instance_valid(bh):
		_charging = false
		_charging_bh = null
		return

	# Phase 2 — FIRE. Hole drops to the player's Y at a fixed speed.
	_charging = false
	_charging_bh = null
	var target_y: float = bh.position.y + BH_FIRE_SPEED * BH_FALLBACK_TRAVEL_TIME
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		target_y = (players[0] as Node2D).global_position.y
	var travel_dist: float = max(0.0, target_y - bh.position.y)
	var travel_time: float = travel_dist / BH_FIRE_SPEED if BH_FIRE_SPEED > 0.0 else BH_FALLBACK_TRAVEL_TIME
	travel_time = max(travel_time, 0.05)
	var t_fire := create_tween()
	t_fire.tween_property(bh, "position",
		bh.position + Vector2(0, travel_dist), travel_time)
	await t_fire.finished
	if not is_instance_valid(bh):
		return

	# Phase 3 — DETONATE.
	bh.pull_strength = black_hole_pull
	var t_det := create_tween()
	t_det.tween_property(bh, "scale",
		Vector2(BH_DETONATE_SCALE, BH_DETONATE_SCALE), BH_DETONATE_GROW_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t_det.finished
	if not is_instance_valid(bh):
		return

	await get_tree().create_timer(black_hole_lifetime).timeout
	if not is_instance_valid(bh):
		return
	var t_out := create_tween()
	t_out.tween_property(bh, "modulate:a", 0.0, 0.6)
	await t_out.finished
	if is_instance_valid(bh):
		bh.queue_free()


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
