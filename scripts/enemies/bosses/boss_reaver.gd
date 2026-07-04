extends "res://scripts/enemies/bosses/boss_base.gd"

# Lash (formerly Reaver) — sector 1-2 mobile sweeper / glass cannon.
# Identity: the dive. P1 strafes in sin^3 arcs with aimed 3-bullet fans;
# P2 stops sweeping and commits to telegraphed straight-line dives across
# the player's lane, then alternates two recovery variations:
#   - dive-and-recycle: continues off the bottom, teleports to top of the
#     boss's pre-dive X column, resumes the loop.
#   - dive-and-return: continues off the bottom, 1.0s beat, a red vertical
#     telegraph line flashes along the lane where the boss will reappear,
#     boss races back UP from the bottom, fishtails 180° at anchor Y.
# Variations alternate per dive so playtest can read both reliably.
#
# Stats set BEFORE super._ready() — no fallback pattern.

@export var dive_collision_damage: int = 2
@export var dive_knockback_distance: float = 36.0
@export var dive_knockback_duration: float = 0.32

var _phase2: bool = false
# True from the moment a P2 dive's telegraph completes through the recovery
# variation finishing (recycle teleport / return fishtail). While set, the
# boss swallows player-collision damage and shoves the player instead.
var _in_dive: bool = false
# Alternates 0/1 per dive so playtest sees both variations reliably.
var _dive_variation_idx: int = 0


func _ready() -> void:
	max_health = 140
	bounty_value = 500
	display_scale = 1.0
	boss_hover_y = 56.0
	# ShootTimer is suppressed by our hand-rolled rotation, but keep cadence
	# defaults sane in case a wave-director shoot_pattern_override is injected.
	fire_interval_min = 0.6
	fire_interval_max = 0.9
	# Aimed sniper: cyan tracer that signals precision and threat on all
	# aimed fans + cones. Unified default fits both P1 strafe and P2 dive.
	default_bullet_variant = load("res://data/bullets/boss/aimed_sniper.tres")
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.5, true, 3.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	# P1: sweep across the playfield in sin^3 arcs.
	sweep_horizontal(80.0, 2.6, "sin3")


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		_phase2 = true


# Override the player's "ram an enemy" path. player.gd's _on_area_entered
# calls area.explode() directly when colliding with an enemy — for a
# diving boss that's a one-frame instakill. While _in_dive, we swallow the
# explode(), damage + knock the player, and let the dive carry on.
func explode() -> void:
	if _in_dive and health > 0 and not _dying:
		_apply_dive_collision()
		return
	super.explode()


func _apply_dive_collision() -> void:
	var p := find_player()
	if p == null or not (p is Node2D):
		return
	var ply := p as Node2D
	if ply.has_method("take_damage"):
		ply.take_damage(dive_collision_damage)
	# Knockback: shove the player away from the boss. Like the asteroid
	# billiards in asteroid.gd — short kinematic-feel tween.
	var to_player: Vector2 = ply.global_position - global_position
	if to_player.length() < 1.0:
		to_player = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var push: Vector2 = to_player.normalized() * dive_knockback_distance
	var tw := ply.create_tween()
	tw.tween_property(
		ply, "position", ply.position + push, dive_knockback_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	while not _dying and is_instance_valid(self):
		if not _phase2:
			# P1: 3-bullet aimed fans every 1.2s while sweeping.
			await _paced(1.2).timeout
			if _dying:
				return
			fire_aimed_burst(3, 16.0)
		else:
			await _run_dive_cycle()


func _run_dive_cycle() -> void:
	# P2 dive entry: stop sweep, lock dive target on the player.
	_anchored = false
	_pattern = null
	var p := find_player()
	if p == null or not (p is Node2D):
		await _paced(0.6).timeout
		return
	var pp: Vector2 = (p as Node2D).global_position
	# Cache the column the boss is committing to — used by both recycle
	# (teleport target) and return (telegraph X).
	var dive_x: float = clamp(pp.x, Playfield.X_MIN + 40.0, Playfield.X_MAX - 40.0)
	var target := Vector2(dive_x, pp.y + 20.0)
	# Telegraph runs INSIDE dive_toward (0.9s red reticle). Mark _in_dive only
	# once the boss is actually committing to motion — telegraph itself is
	# parry-by-dodge.
	await dive_toward(target, 280.0, true)
	if _dying:
		return
	_in_dive = true
	# Aimed cone on the way past — punishes a player who held position.
	fire_aimed_cone(5, 22.0)
	# Continue downward past the player + off the bottom of the screen.
	await _continue_off_bottom(dive_x)
	if _dying:
		_in_dive = false
		return
	# Variation: alternate per dive so both reliably show in playtest.
	var use_return: bool = (_dive_variation_idx % 2) == 1
	_dive_variation_idx += 1
	if use_return:
		await _recover_return(dive_x)
	else:
		await _recover_recycle(dive_x)
	_in_dive = false
	if _dying:
		return
	await _paced(0.6).timeout


# Drive the boss straight down past the bottom edge at dive speed.
func _continue_off_bottom(_dive_x: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var off_y: float = vp.y + 48.0
	var dist: float = max(0.0, off_y - global_position.y)
	var dur: float = dist / 280.0
	var tw := create_tween()
	tw.tween_property(self, "position:y", off_y, dur)
	await tw.finished


# Dive-and-recycle: teleport to the top of the dive column, resume sweep.
func _recover_recycle(dive_x: float) -> void:
	# Brief beat off-screen before re-entering so the recycle reads as a
	# return rather than a teleport-snap.
	await _paced(0.4).timeout
	if _dying:
		return
	# Teleport above the playfield and slide down to anchor_y.
	global_position = Vector2(dive_x, -48.0)
	var tw := create_tween()
	tw.tween_property(self, "position:y", boss_hover_y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


# Dive-and-return: 1s beat, vertical red telegraph line, race up from the
# bottom, fishtail-slide 180° near anchor_y.
func _recover_return(dive_x: float) -> void:
	# 1.0s beat of empty playfield.
	await _paced(1.0).timeout
	if _dying:
		return
	# Red telegraph line down the lane. ~4 px wide, full playfield height,
	# pulsing for ~0.4s.
	await _flash_return_telegraph(dive_x, 0.4)
	if _dying:
		return
	# Spawn boss at the bottom of the chosen column and race upward.
	var vp: Vector2 = get_viewport_rect().size
	global_position = Vector2(dive_x, vp.y + 32.0)
	var climb_speed: float = 300.0
	var target_y: float = boss_hover_y
	var dist: float = max(0.0, global_position.y - target_y)
	var climb_dur: float = dist / climb_speed
	var tw := create_tween()
	tw.tween_property(self, "position:y", target_y, climb_dur)
	await tw.finished
	if _dying:
		return
	# Fishtail-slide: spin 180°→0° while decelerating + sliding horizontally.
	# We don't rotate the sprite permanently — start at PI, end at 0 — so
	# the boss visibly whips around to face the player again.
	var slide_dx: float = (40.0 if dive_x < Playfield.CENTER.x else -40.0)
	var slide_target := Vector2(
		clamp(global_position.x + slide_dx, Playfield.X_MIN + 24.0, Playfield.X_MAX - 24.0),
		target_y,
	)
	rotation = PI
	var ftw := create_tween()
	ftw.parallel().tween_property(self, "rotation", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ftw.parallel().tween_property(self, "position", slide_target, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await ftw.finished


# Vertical telegraph line at column `x` for `duration` seconds. ColorRect
# parented to the current scene so it survives the boss reposition.
func _flash_return_telegraph(x: float, duration: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var bar := ColorRect.new()
	bar.color = Color(1.0, 0.18, 0.18, 0.0)
	bar.size = Vector2(4.0, vp.y)
	bar.position = Vector2(x - 2.0, 0.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world().add_child(bar)   # bullet_world layer in a bench; current scene in combat
	var tw := bar.create_tween()
	tw.tween_property(bar, "color:a", 0.85, duration * 0.25)
	tw.tween_property(bar, "color:a", 0.35, duration * 0.25)
	tw.tween_property(bar, "color:a", 0.85, duration * 0.25)
	tw.tween_property(bar, "color:a", 0.0, duration * 0.25)
	tw.tween_callback(bar.queue_free)
	await _paced(duration).timeout
