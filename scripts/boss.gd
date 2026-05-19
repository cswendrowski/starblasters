extends "res://scripts/enemies/enemy_base.gd"

# Sector commander. Bigger, tougher, spawns minions, has its own HP bar.
# Migrated to EnemyBase (2026-05-16) so the bullet pipeline goes through
# the unified `take_hit(damage)` contract instead of the legacy
# `area.health -= 1; area.explode()` fallback.
#
# main.gd's HP-bar wiring walks the inheritance chain looking for
# resource_path == "res://scripts/boss.gd" — that still matches because the
# node's immediate script is boss.gd; enemy_base.gd is just the parent.

signal health_changed(cur: int, max: int)

@export var shoot_pattern: Resource = null
@export var fire_interval_min: float = 0.7
@export var fire_interval_max: float = 1.4
@export var movement: Resource = null

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

# Where the boss settles after its enter sweep (Y pixels from top). Lower
# = higher on the screen. Per-boss so Reaver/Sentinel can tune their own
# stand-off. 480×270 viewport — top quarter ≈ 68 px.
@export var boss_hover_y: float = 48.0

var _pattern = null
var _minions: Array = []
var _charging: bool = false
var _charging_bh: Node2D = null
const BlackHoleScene = preload("res://scenes/hazards/black_hole.tscn")


func _ready() -> void:
	# Bosses live inside the playfield; no offscreen cleanup. They also
	# don't auto-rotate (the sprite is hand-authored facing the player) and
	# don't use the default engine-flame attachment that EnemyBase adds for
	# ships — the boss sprite carries its own art.
	# Stats assigned directly (no floor checks) so Commander behaves the
	# same as Reaver/Sentinel — the previous `<= 0` guard missed the
	# EnemyBase default of 1 and Commander spawned at 1 HP.
	max_health = 80
	bounty_value = 300
	display_scale = 1.0
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	# Fallback minion config if not set externally
	if minion_scene == null:
		minion_scene = load("res://scenes/enemies/enemy_diver.tscn")
	if minion_movement == null:
		var Straight = load("res://scripts/enemies/patterns/straight_down.gd")
		var mv = Straight.new()
		mv.speed = 360.0
		minion_movement = mv
	if has_node("ShootTimer") and not $ShootTimer.timeout.is_connected(_on_shoot_timer_timeout):
		$ShootTimer.timeout.connect(_on_shoot_timer_timeout)
	if has_node("MinionTimer"):
		$MinionTimer.wait_time = minion_spawn_interval
		if not $MinionTimer.timeout.is_connected(_on_minion_timer_timeout):
			$MinionTimer.timeout.connect(_on_minion_timer_timeout)
	_schedule_next_black_hole()
	health_changed.emit(health, max_health)
	# Oblique drop-shadow under the boss sprite — larger offset/opacity to
	# match the boss's display_scale (typically 3x normal enemies).
	if has_node("Sprite2D"):
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D, Vector2(14, 14), 0.5, 2.0)


func start(pos: Vector2) -> void:
	scale = Vector2(display_scale, display_scale)
	position = pos
	if movement != null:
		_pattern = movement.duplicate()
		# Push the per-boss hover_y onto the movement if it has the field.
		# Lets wave_generator pass a generic BossSweep without knowing about
		# each boss's preferred stand-off — boss.gd owns its own hover_y now.
		if "hover_y" in _pattern:
			_pattern.hover_y = boss_hover_y
		if _pattern.has_method("on_start"):
			_pattern.on_start(self)
	if has_node("ShootTimer"):
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()
	if has_node("MinionTimer"):
		$MinionTimer.start()
	health_changed.emit(health, max_health)


# Stub for inherited MoveTimer connection
func _on_timer_timeout() -> void:
	pass


func _process(delta: float) -> void:
	if _dying:
		return
	if _pattern != null:
		var safe_delta: float = min(delta, 1.0 / 30.0)
		var step: Vector2 = _pattern.compute_step(self, safe_delta)
		# Boss slows to a crawl during the black-hole charge so the player
		# can read "this boss is busy doing something" (Roman 2026-05-18).
		if _charging:
			step *= 0.25
		position += step
		_clamp_to_playfield()
	# While charging, the hole sticks to a fixed offset in front of the
	# boss so it tracks the boss's drift instead of being locked to its
	# spawn point (Roman 2026-05-18: "charging in front of the boss's
	# current position").
	if _charging and _charging_bh != null and is_instance_valid(_charging_bh):
		_charging_bh.global_position = global_position + Vector2(0, 60.0)
	# offscreen_mode is NONE, so no need to call _offscreen_cleanup_check.


# Keep the boss inside the visible playfield (Roman, 2026-05-17 playtest:
# "all of the bosses were zooping out of the area"). Bosses sit in the
# top 70% so the player has room to dodge below them.
func _clamp_to_playfield() -> void:
	var vp: Vector2 = get_viewport_rect().size
	const MARGIN: float = 24.0
	position.x = clamp(position.x, MARGIN, vp.x - MARGIN)
	position.y = clamp(position.y, MARGIN, vp.y * 0.7)


# Non-fatal damage reaction: white flash + HP-bar update. EnemyBase's
# take_hit() handles the health bookkeeping and calls explode() at zero,
# so all we need here is the visual + signal.
func hit() -> void:
	modulate = Color(2, 2, 2, 1)
	var tw = create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.15)
	health_changed.emit(health, max_health)


func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	if has_node("/root/Run"):
		get_node("/root/Run").sector_complete()
	for m in _minions:
		if is_instance_valid(m):
			m.queue_free()
	_minions.clear()
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# 1× explosions, count scales with the boss feel (Roman 2026-05-18).
	ExplosionFx.burst(global_position, 7, 28.0, 0.08)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 1.2)
	if has_node("AnimationPlayer") and $AnimationPlayer.has_animation("explode"):
		$AnimationPlayer.play("explode")
	# Boss death SFX — every boss scene ships an EnemyDie AudioStreamPlayer2D.
	# Roman 2026-05-19: was never being played.
	if has_node("EnemyDie"):
		$EnemyDie.play()
	health_changed.emit(0, max_health)
	await get_tree().create_timer(1.3).timeout
	queue_free()


func _schedule_next_black_hole() -> void:
	if _dying:
		return
	var t: float = randf_range(black_hole_interval_min, black_hole_interval_max)
	get_tree().create_timer(t).timeout.connect(_spawn_black_hole_attack)


# Black-hole attack timings (Roman 2026-05-18 design pass).
# Charge: spawn small in front of boss, grow ~50% over BH_CHARGE_TIME. Boss
#         slows and stops firing other attacks.
# Fire:   launch straight forward (down). Travel for BH_TRAVEL_TIME.
# Detonate: at end of travel, expand to BH_DETONATE_SCALE (3× charged) and
#         turn on the gravity well.
const BH_CHARGE_TIME: float = 2.5
const BH_DETONATE_GROW_TIME: float = 0.6   # smooth grow, not a snap
# Starts 50% smaller than the previous pass (0.25 → 0.125). Charged size
# keeps the ~50% grow ratio off the new start.
const BH_START_SCALE: float = 0.125
const BH_CHARGED_SCALE: float = 0.1875     # ~50% larger than start
const BH_DETONATE_SCALE: float = 1.125     # detonation reach (unchanged)
const BH_FIRE_SPEED: float = 220.0         # px/sec, straight down
# Fallback travel time if no player is present (e.g., capture scenes).
const BH_FALLBACK_TRAVEL_TIME: float = 1.5


func _spawn_black_hole_attack() -> void:
	if _dying:
		return
	# Queue the next attack immediately so the loop survives even if the
	# coroutine below short-circuits on boss death.
	_schedule_next_black_hole()
	_run_black_hole_sequence()


func _run_black_hole_sequence() -> void:
	_charging = true
	# Spawn small in front of the boss (below = toward the player). Scaling
	# the Node2D (not Visual) keeps the disc concentric on its own origin,
	# so the detonation grows around the same center (Roman 2026-05-18).
	var bh = BlackHoleScene.instantiate()
	bh.radius = black_hole_radius
	bh.lifetime = 999.0      # we drive lifetime manually via tweens
	bh.fade_time = 0.05
	bh.visual_scale = 1.0
	bh.pull_strength = 0.0
	bh.position = global_position + Vector2(0, 60.0)
	bh.scale = Vector2(BH_START_SCALE, BH_START_SCALE)
	_add_world_node_above_backdrop(bh)
	_charging_bh = bh
	# Wait one frame so black_hole._ready has run before tweens read state.
	await get_tree().process_frame
	if _dying or not is_instance_valid(bh):
		_charging = false
		_charging_bh = null
		return

	# Phase 1 — CHARGE. Grow start → charged over BH_CHARGE_TIME. Boss
	# _process keeps bh.global_position stuck in front of the boss while
	# _charging is true, so the hole tracks the boss's drift.
	var t_charge := create_tween()
	t_charge.tween_property(bh, "scale",
		Vector2(BH_CHARGED_SCALE, BH_CHARGED_SCALE), BH_CHARGE_TIME)
	await t_charge.finished
	if _dying or not is_instance_valid(bh):
		_charging = false
		_charging_bh = null
		return

	# Phase 2 — FIRE. Boss resumes; hole moves straight down toward the
	# player's Y at fixed speed. If no player exists (capture scenes), fall
	# back to a fixed travel time. (Roman 2026-05-18: "detonate at the same
	# Y-level as the player ship".)
	_charging = false
	_charging_bh = null
	var target_y: float = bh.position.y + BH_FIRE_SPEED * BH_FALLBACK_TRAVEL_TIME
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		target_y = (players[0] as Node2D).global_position.y
	# Don't travel upward — clamp to a non-negative distance.
	var travel_dist: float = max(0.0, target_y - bh.position.y)
	var travel_time: float = travel_dist / BH_FIRE_SPEED if BH_FIRE_SPEED > 0.0 else BH_FALLBACK_TRAVEL_TIME
	travel_time = max(travel_time, 0.05)
	var t_fire := create_tween()
	t_fire.tween_property(bh, "position",
		bh.position + Vector2(0, travel_dist), travel_time)
	await t_fire.finished
	if not is_instance_valid(bh):
		return

	# Phase 3 — DETONATE. Smooth grow to 3× scale around the same center
	# (Node2D scale, so the disc's origin stays put). Pull ramps with it.
	bh.pull_strength = black_hole_pull
	var t_det := create_tween()
	t_det.tween_property(bh, "scale",
		Vector2(BH_DETONATE_SCALE, BH_DETONATE_SCALE), BH_DETONATE_GROW_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t_det.finished
	if not is_instance_valid(bh):
		return

	# Hold the detonation for the configured lifetime, fade out, free.
	await get_tree().create_timer(black_hole_lifetime).timeout
	if not is_instance_valid(bh):
		return
	var t_out := create_tween()
	t_out.tween_property(bh, "modulate:a", 0.0, 0.6)
	await t_out.finished
	if is_instance_valid(bh):
		bh.queue_free()


# Parent a hazard so it draws ABOVE the parallax backdrop but BELOW the ships.
# Backdrop is a sibling of Player in main.tscn; default Player z=0; backdrop
# sprites are at z=0 inside their Node2D parent. Adding the hazard as the
# LAST child of Backdrop puts it at the top of the backdrop's draw stack —
# above the parallax sprites, and the whole Backdrop still draws before the
# Player sibling (so the hazard ends up behind ships and projectiles).
func _add_world_node_above_backdrop(node: Node2D) -> void:
	var p := get_parent()
	var bd: Node = null
	if p:
		bd = p.get_node_or_null("Backdrop")
	if bd:
		bd.add_child(node)
	else:
		# Fallback — no backdrop in this scene; behave as before.
		if p:
			p.add_child(node)


func _on_shoot_timer_timeout() -> void:
	if _dying:
		return
	# Suppress other fire while a black hole is being charged so the boss
	# reads as committed to that attack (Roman 2026-05-18). Timer still
	# loops so it's hot the moment the charge releases.
	if not _charging and shoot_pattern != null:
		shoot_pattern.fire(self)
	$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
	$ShootTimer.start()


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
