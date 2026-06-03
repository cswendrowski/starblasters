extends "res://scripts/enemies/enemy_base.gd"

# Pattern-driven regular enemy. Adds movement_pattern + shoot_pattern slots
# on top of EnemyBase, plus the legacy "anchor follow" path used when no
# movement resource is set, plus the parallax fly-back cycle on bottom
# exit. All death + hit + offscreen + player-finding logic lives in
# EnemyBase; this script is just the combat-fighter specifics.

# Legacy anchor-follow fields (used when movement == null).
var start_pos: Vector2 = Vector2.ZERO
var speed: float = 0.0
var anchor: Node2D = null
var follow_anchor: bool = false
const _DEFAULT_BULLET = preload("res://scenes/projectiles/enemy_bullet.tscn")
const ClarityRules = preload("res://scripts/clarity.gd")
var bullet_scene: PackedScene = _DEFAULT_BULLET

# Pattern-driven slots.
@export var movement: Resource = null
var _pattern: Resource = null

@export var shoot_pattern: Resource = null
@export var fire_interval_min: float = 1.2
@export var fire_interval_max: float = 2.5
# Gate the shoot timer on "is my nose pointed at the player". Set by the
# Viper enemy (Roman, 2026-05-18) — uses dot(facing, dir_to_player) >=
# cos(fire_aim_tol_deg) before firing. When false, the timer continues
# polling but no bullet is emitted until alignment.
@export var fire_only_on_target: bool = false
@export var fire_aim_tol_deg: float = 18.0
# When non-empty, fire one shot whenever the movement pattern emits
# `phase_entered(phase_name)` with this name. Replaces the statistical
# ShootTimer for patterns that have a meaningful "shoot here" beat
# (Hover hold, Skirmisher hold). Empty = legacy timer-only firing.
@export var fire_on_phase: String = ""

# Cycling state — enemy is currently flying back up through parallax.
var _cycling: bool = false
var _cycle_tween: Tween = null
var _pre_cycle_scale: Vector2 = Vector2.ONE
var _pre_cycle_modulate: Color = Color(1, 1, 1, 1)

# Pattern-driven enemies use CYCLE_BOTTOM by default (the parallax
# re-entry). Leavers can flip this to FREE_ANY_EDGE / FREE_OPPOSITE_SIDE.


func is_recycling() -> bool:
	return _cycling


func _ready() -> void:
	super._ready()
	# Oblique drop-shadow under the enemy sprite.
	if has_node("Sprite2D"):
		var ShadowFx = load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


func start(pos: Vector2) -> void:
	if movement != null:
		_start_with_pattern(pos)
	else:
		_start_anchored(pos)


func _start_with_pattern(pos: Vector2) -> void:
	position = pos
	_pattern = movement.duplicate()
	# Sector speed scaling (Cody, 2026-05-24): +5% per cleared sector, capped
	# at 2× (so sector 21+ tops out). Applied once per spawn on the duplicated
	# pattern resource so siblings don't share state. Scales any @export float
	# whose name is `speed`, `accel`, `drift_x`, or ends in `_speed`/`_accel`.
	_apply_sector_speed_scale(_pattern)
	# Connect phase events BEFORE on_start so the initial-phase emit lands.
	if _pattern.has_signal("phase_entered") \
		and not _pattern.is_connected("phase_entered", _on_movement_phase_entered):
		_pattern.phase_entered.connect(_on_movement_phase_entered)
	if _pattern.has_method("on_start"):
		_pattern.on_start(self)
	# Only arm the shoot timer if the enemy *can* shoot. A null shoot_pattern
	# means this enemy has no weapon — don't let a timer fire bullets via
	# the legacy bullet_scene fallback. Roman, 2026-05-17: minelayer/mine
	# carriers should not shoot.
	# Phase-driven enemies (fire_on_phase != "") use the pattern's event
	# instead of the random timer, so we skip starting it.
	if shoot_pattern != null and has_node("ShootTimer") and fire_on_phase == "":
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()


func _apply_sector_speed_scale(pattern: Resource) -> void:
	if pattern == null:
		return
	var run := get_node_or_null("/root/Run")
	if run == null or not ("sectors_cleared" in run):
		return
	var cleared: int = int(run.sectors_cleared)
	if cleared <= 0:
		return
	var scale_factor: float = clamp(1.0 + 0.05 * float(cleared), 1.0, 2.0)
	for prop in pattern.get_property_list():
		if not (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if int(prop.get("type", -1)) != TYPE_FLOAT:
			continue
		var n: String = str(prop.get("name", ""))
		var is_accel: bool = n == "accel" or n.ends_with("_accel")
		var is_speed: bool = n == "speed" or n.ends_with("_speed")
		var is_drift: bool = n == "drift_x"
		if not (is_speed or is_accel or is_drift):
			continue
		var scaled: float = float(pattern.get(n)) * scale_factor
		if is_speed:
			# Keep late-game movement readable: clamp the scaled speed at the
			# 8 px/f ceiling and snap to a whole-px/frame rung so it has an
			# even cadence under pixel-snap. (accel/drift scale unclamped.)
			scaled = ClarityRules.snap_to_rung(minf(scaled, ClarityRules.ABS_MAX_SPEED))
		pattern.set(n, scaled)


func _start_anchored(pos: Vector2) -> void:
	follow_anchor = false
	speed = 0
	position = Vector2(pos.x, -pos.y)
	start_pos = pos
	await get_tree().create_timer(randf_range(0.25, 0.55)).timeout
	var tw = create_tween().set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "position:y", start_pos.y, 1.4)
	await tw.finished
	follow_anchor = true
	$MoveTimer.wait_time = randf_range(5, 20)
	$MoveTimer.start()
	$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
	$ShootTimer.start()


func _process(delta: float) -> void:
	if _pattern != null:
		# Cycling enemies are mid-fly-back in a parallax layer; their
		# movement is driven by tween, not the pattern.
		if not _cycling:
			# Cap delta so a hitch frame can't teleport the enemy a
			# screen's worth in a single step. 1/30s = ~33ms — generous
			# enough to soak normal frame variance, tight enough that a
			# 500-ms stall produces a 33-ms move, not a 500-ms move.
			var safe_delta: float = min(delta, 1.0 / 30.0)
			var step: Vector2 = _pattern.compute_step(self, safe_delta)
			position += step
			_clamp_to_sides()
			_offscreen_cleanup_check()
			_apply_auto_rotation()
		return
	if follow_anchor and anchor != null:
		position = start_pos + anchor.position
	position.y += speed * delta
	_clamp_to_sides()
	if position.y > screensize.y + 32:
		start(start_pos)


# Keep the enemy inside the horizontal playfield (Roman: enemies shouldn't
# leave via the sides unless a specific behavior requires it). Patterns
# opt out by setting `allow_side_exit` on the enemy.
# Bumped 16 → 40 so sprites stay fully on-screen instead of clipping the
# edge (sprites are ~48 px wide after 2× display × 3× world). Roman,
# 2026-05-16: enemy patterns should avoid colliding with the sides.
const SIDE_MARGIN := 14.0
func _clamp_to_sides() -> void:
	if "allow_side_exit" in self and self.allow_side_exit:
		return
	if position.x < Playfield.X_MIN + SIDE_MARGIN:
		position.x = Playfield.X_MIN + SIDE_MARGIN
	elif position.x > Playfield.X_MAX - SIDE_MARGIN:
		position.x = Playfield.X_MAX - SIDE_MARGIN


# Override EnemyBase's bottom-exit hook: instead of freeing, do the
# parallax fly-back so the enemy reappears for another pass.
# recycle_passes controls how many fly-back cycles are allowed:
#   -1 = unlimited (legacy default), 0 = leave instead of cycling,
#   N > 0 = decrement then cycle.
func _on_offscreen() -> void:
	if recycle_passes == 0:
		_leave()
		return
	if recycle_passes > 0:
		recycle_passes -= 1
	_start_cycle()


func _start_cycle() -> void:
	if _cycling:
		return
	_cycling = true
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	visible = false
	# Cody, 2026-05-18: "Ships looping back around in the background could
	# be brought up in speed, there's a lot of dead time waiting for them."
	# Pre-cycle hold trimmed 1.0-2.0s → 0.4-0.9s.
	var delay: float = randf_range(0.4, 0.9)
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self):
		return
	# Pick a re-entry x inside the playfield band, not the full viewport —
	# otherwise the cycle dropped enemies into the side gutters where the
	# player can't shoot back. 22 px inset keeps the sprite fully inside
	# the band edges (Roman, 2026-05-19).
	var x_min: float = Playfield.X_MIN + 22.0
	var x_max: float = Playfield.X_MAX - 22.0
	var entry_x: float = randf_range(x_min, x_max)
	position = Vector2(entry_x, screensize.y + 12.0)
	_pre_cycle_scale = scale
	_pre_cycle_modulate = modulate
	# Parallax-pass: shrink to 45% size, push toward parallax tint. NO
	# scale.y flip — auto_rotate handles orientation, so we rotate the
	# ship to face UP (the direction it's flying during the fly-back)
	# instead of mirroring its scale.
	scale = Vector2(_pre_cycle_scale.x * 0.45, _pre_cycle_scale.y * 0.45)
	modulate = Color(0.75, 0.85, 1.0, 0.55)
	# Face up — sprites are drawn pointing up, so rotation = 0 means
	# they point along their travel direction during the fly-back.
	rotation = 0.0
	_rot_init = true
	_last_position = position
	visible = true
	if _cycle_tween and _cycle_tween.is_valid():
		_cycle_tween.kill()
	_cycle_tween = create_tween()
	# Fly-back tween 3.5s → 1.8s so the cycle reads as a quick zip,
	# not a leisurely parade (Cody, 2026-05-18).
	_cycle_tween.tween_property(self, "position:y", -20.0, 1.8).set_trans(Tween.TRANS_LINEAR)
	await _cycle_tween.finished
	if not is_instance_valid(self):
		return
	scale = _pre_cycle_scale
	modulate = _pre_cycle_modulate
	start_pos = position
	_cycling = false
	# Reset the auto-rotate position tracker so the first post-cycle
	# move computes a fresh delta vector.
	_rot_init = false
	set_deferred("monitorable", true)
	set_deferred("monitoring", true)
	if has_node("ShootTimer") and fire_on_phase == "":
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()
	if _pattern and _pattern.has_method("on_start"):
		_pattern.on_start(self)


# enemy.tscn template wires MoveTimer/ShootTimer to legacy callbacks.
func _on_timer_timeout() -> void:
	speed = randf_range(75, 100)
	follow_anchor = false


func _on_shoot_timer_timeout() -> void:
	# Hard requirements before any bullet leaves the muzzle:
	#   - not parallax-cycling
	#   - fully inside the playfield
	#   - has a shoot pattern
	#   - if `fire_only_on_target`, nose must be aligned with the player
	if shoot_pattern == null:
		return
	if _cycling or not _on_playfield():
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()
		return
	if fire_only_on_target and not _nose_on_player():
		# Re-arm the poll but skip this trigger so the enemy waits for a
		# clean line. Slightly faster re-check than the normal interval.
		$ShootTimer.wait_time = max(0.1, randf_range(fire_interval_min, fire_interval_max) * 0.4)
		$ShootTimer.start()
		return
	shoot_pattern.fire(self)
	$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
	$ShootTimer.start()
	if has_node("EnemyShoot"):
		$EnemyShoot.play()


func _on_movement_phase_entered(phase_name: String) -> void:
	if fire_on_phase == "" or phase_name != fire_on_phase:
		return
	if shoot_pattern == null:
		return
	if _cycling or not _on_playfield():
		return
	if fire_only_on_target and not _nose_on_player():
		return
	shoot_pattern.fire(self)
	if has_node("EnemyShoot"):
		$EnemyShoot.play()


# True when the body's forward vector is within fire_aim_tol_deg of the
# direction toward the player. Mirrors the same math the omni/inertial/jet
# patterns use to decide their facing.
func _nose_on_player() -> bool:
	var player := find_player()
	if player == null:
		return false
	var to_p: Vector2 = player.global_position - global_position
	if to_p.length_squared() < 1.0:
		return false
	# Sprite faces +Y at rotation=0 → forward derived from rotation - PI/2.
	var rot: float = rotation - PI * 0.5
	var fwd: Vector2 = Vector2(cos(rot), sin(rot))
	return fwd.dot(to_p.normalized()) >= cos(deg_to_rad(fire_aim_tol_deg))


# Strict "fully inside the visible playfield" check, used by the shoot
# guard. Margin of 8 px on every edge so an enemy nudging the wall while
# clamped is still considered on-screen.
func _on_playfield() -> bool:
	const PF_MARGIN := 8.0
	var p: Vector2 = position
	return p.x >= PF_MARGIN \
		and p.x <= screensize.x - PF_MARGIN \
		and p.y >= PF_MARGIN \
		and p.y <= screensize.y - PF_MARGIN
