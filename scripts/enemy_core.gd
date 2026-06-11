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
const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
const RecycleController = preload("res://scripts/effects/recycle_controller.gd")
var bullet_scene: PackedScene = _DEFAULT_BULLET
var _beam: Node = null   # per-enemy BeamEmitter when shoot_pattern is a beam weapon

# Pattern-driven slots.
@export var movement: Resource = null
var _pattern: Resource = null

@export var shoot_pattern: Resource = null
@export var fire_interval_min: float = 1.2
@export var fire_interval_max: float = 2.5
# Gate the shoot timer on "is my nose pointed at the player". Set by the
# Viper enemy (Roman, 2026-05-18) â€” uses dot(facing, dir_to_player) >=
# cos(fire_aim_tol_deg) before firing. When false, the timer continues
# polling but no bullet is emitted until alignment.
@export var fire_only_on_target: bool = false
@export var fire_aim_tol_deg: float = 18.0
# When non-empty, fire one shot whenever the movement pattern emits
# `phase_entered(phase_name)` with this name. Replaces the statistical
# ShootTimer for patterns that have a meaningful "shoot here" beat
# (Hover hold, Skirmisher hold). Empty = legacy timer-only firing.
@export var fire_on_phase: String = ""
# Firing-zone gating (bridge Â§1.8-1.9): when true, only fire while inside the
# engagement Y-band (Zones) â€” hold fire just after spawn (entry band) and cease
# fire once low (departure band, committed to leaving). The director enables this
# for the enemies it spawns; bosses/bespoke firing are unaffected.
@export var fire_zone_gated: bool = false
# Path-phase firing (construction Â§8): fractions [0,1] of engagement-band progress
# (Zones.band_progress) at which to fire â€” e.g. [0.35, 0.75] fires twice during the
# descent, at fixed screen positions, instead of on the random ShootTimer (which
# fired "too late"). MUST be ascending. Non-empty disables the timer. Auto-populated
# in _start_with_pattern for monotonic descenders (path_phase_capable patterns) that
# have a weapon and no fire_on_phase; a scene/roster may set it explicitly to override.
@export var fire_path_phases: PackedFloat32Array = PackedFloat32Array()
# Plain Array const (a PackedFloat32Array(...) constructor is NOT a constant
# expression â€” it fails to parse the whole script). Converted to a packed array at
# the assignment site below.
const DEFAULT_PATH_PHASES := [0.35, 0.75]
var _phase_fire_idx: int = 0  # next phase index to fire (advances as the enemy descends)
# Shared beat (Beat): when true, a path-phase shot doesn't fire the instant it crosses
# its phase line - it quantizes to the next global beat (Beat.next_beat_time) so enemies
# across formations volley together. Set false to fire immediately on the phase line.
@export var fire_beat_synced: bool = true
var _beat_fire_at: float = -1.0  # engine-clock time a pending beat-synced shot fires (-1 = none)

# Cycling state â€” enemy is currently flying back up through parallax.
var _cycling: bool = false
var _cycle_tween: Tween = null
var _pre_cycle_scale: Vector2 = Vector2.ONE
var _pre_cycle_modulate: Color = Color(1, 1, 1, 1)

# Pattern-driven enemies use CYCLE_BOTTOM by default (the parallax
# re-entry). Leavers can flip this to FREE_ANY_EDGE / FREE_OPPOSITE_SIDE.


func is_recycling() -> bool:
	return _cycling


# Toggle the hull outline node (added by EnemyBase via OutlineFx) — dropped while
# recycling so a faux-parallax fly-back doesn't carry the "shootable" outline.
func _set_outline_visible(v: bool) -> void:
	var o := get_node_or_null("Outline")
	if o != null:
		o.visible = v


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
	# at 2Ã— (so sector 21+ tops out). Applied once per spawn on the duplicated
	# pattern resource so siblings don't share state. Scales any @export float
	# whose name is `speed`, `accel`, `drift_x`, or ends in `_speed`/`_accel`.
	_apply_sector_speed_scale(_pattern)
	# Connect phase events BEFORE on_start so the initial-phase emit lands.
	if _pattern.has_signal("phase_entered") \
		and not _pattern.is_connected("phase_entered", _on_movement_phase_entered):
		_pattern.phase_entered.connect(_on_movement_phase_entered)
	if _pattern.has_method("on_start"):
		_pattern.on_start(self)
	# Continuous BEAM weapon (M6a.2): attach a per-enemy BeamEmitter and skip all
	# discrete firing (no path-phase, no shoot timer) — the emitter self-runs.
	if _attach_beam_if_weapon():
		return
	# Path-phase firing (Â§8): a monotonic descender with a weapon fires by band-Y
	# progress instead of the random timer. Auto-enable when the pattern supports it
	# and nothing more specific is configured (explicit phases, or a fire_on_phase
	# event). A pre-set fire_path_phases (scene/roster) is respected as-is.
	if shoot_pattern != null and fire_on_phase == "" and fire_path_phases.is_empty() \
			and _pattern.has_method("path_phase_capable") and _pattern.path_phase_capable():
		fire_path_phases = PackedFloat32Array(DEFAULT_PATH_PHASES)
	_phase_fire_idx = 0
	_beat_fire_at = -1.0
	# Only arm the shoot timer if the enemy *can* shoot. A null shoot_pattern
	# means this enemy has no weapon â€” don't let a timer fire bullets via
	# the legacy bullet_scene fallback. Roman, 2026-05-17: minelayer/mine
	# carriers should not shoot.
	# Phase-driven (fire_on_phase) and path-phase (fire_path_phases) enemies fire on
	# their own triggers, so we skip the random timer for them.
	if shoot_pattern != null and has_node("ShootTimer") and fire_on_phase == "" and fire_path_phases.is_empty():
		# Zone-gated enemies arm a short first poll so the FIRST shot lands as soon
		# as they enter the engagement band (the gate fast-polls until then). The
		# long random interval would otherwise delay the first shot until they've
		# descended near the bottom. Subsequent shots re-arm on the normal interval.
		if fire_zone_gated:
			$ShootTimer.wait_time = 0.2
		else:
			$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()


# Attach a per-enemy BeamEmitter when the shoot_pattern is a continuous beam weapon.
# Returns true if a beam was set up (caller then skips discrete-firing arming). The
# Weapon resource stays shared (just config); the per-enemy state lives on the node.
func _attach_beam_if_weapon() -> bool:
	if shoot_pattern == null or not shoot_pattern.has_method("is_beam") or not shoot_pattern.is_beam():
		return false
	if _beam == null or not is_instance_valid(_beam):
		_beam = BeamEmitterC.new()
		_beam.configure(shoot_pattern.make_beam_config())
		add_child(_beam)
	return true


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
			# screen's worth in a single step. 1/30s = ~33ms â€” generous
			# enough to soak normal frame variance, tight enough that a
			# 500-ms stall produces a 33-ms move, not a 500-ms move.
			var safe_delta: float = min(delta, 1.0 / 30.0)
			var step: Vector2 = _pattern.compute_step(self, safe_delta)
			position += step
			if safe_delta > 0.0:
				_last_move_vel = step / safe_delta   # px/s — for wreck-drift motion preservation
			_clamp_to_sides()
			_offscreen_cleanup_check()
			_apply_auto_rotation()
			_check_path_phase_fire()
			_tick_components(safe_delta)
		return
	if follow_anchor and anchor != null:
		position = start_pos + anchor.position
	position.y += speed * delta
	_clamp_to_sides()
	_tick_components(delta)
	if position.y > screensize.y + 32:
		start(start_pos)


# Keep the enemy inside the horizontal playfield (Roman: enemies shouldn't
# leave via the sides unless a specific behavior requires it). Patterns
# opt out by setting `allow_side_exit` on the enemy.
# Bumped 16 â†’ 40 so sprites stay fully on-screen instead of clipping the
# edge (sprites are ~48 px wide after 2Ã— display Ã— 3Ã— world). Roman,
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
	# Drop the hull outline + engine exhaust for the whole fly-back: a recycling ship
	# reads as faux-parallax (shrunk + tinted), which shouldn't carry either effect.
	_set_outline_visible(false)
	set_engine_trail_emitting(false)
	visible = false
	# Recycle timing + look now flow from RecycleController (worklist #33): a single
	# tunable owner whose DEFAULTS equal the old hardcoded numbers, so behavior is
	# unchanged until Roman tunes via the RecycleTuner dev scene.
	var rcfg: Dictionary = RecycleController.config()
	# Cody, 2026-05-18: "Ships looping back around in the background could
	# be brought up in speed, there's a lot of dead time waiting for them."
	# Pre-cycle hold trimmed 1.0-2.0s â†’ 0.4-0.9s (now cfg.hold_min/max).
	var delay: float = randf_range(float(rcfg.hold_min), float(rcfg.hold_max))
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self):
		return
	# Pick a re-entry x inside the playfield band, not the full viewport â€”
	# otherwise the cycle dropped enemies into the side gutters where the
	# player can't shoot back. 22 px inset keeps the sprite fully inside
	# the band edges (Roman, 2026-05-19).
	var inset: float = float(rcfg.entry_inset)
	var x_min: float = Playfield.X_MIN + inset
	var x_max: float = Playfield.X_MAX - inset
	var entry_x: float = randf_range(x_min, x_max)
	position = Vector2(entry_x, screensize.y + 12.0)
	_pre_cycle_scale = scale
	_pre_cycle_modulate = modulate
	# Parallax-pass: shrink to 45% size, push toward parallax tint. NO
	# scale.y flip â€” auto_rotate handles orientation, so we rotate the
	# ship to face UP (the direction it's flying during the fly-back)
	# instead of mirroring its scale.
	var fly_scale: float = float(rcfg.fly_scale)
	scale = Vector2(_pre_cycle_scale.x * fly_scale, _pre_cycle_scale.y * fly_scale)
	modulate = RecycleController.tint(rcfg)
	# Face up â€” sprites are drawn pointing up, so rotation = 0 means
	# they point along their travel direction during the fly-back.
	rotation = 0.0
	_rot_init = true
	_last_position = position
	visible = true
	if _cycle_tween and _cycle_tween.is_valid():
		_cycle_tween.kill()
	_cycle_tween = create_tween()
	# Fly-back tween 3.5s â†’ 1.8s so the cycle reads as a quick zip,
	# not a leisurely parade (Cody, 2026-05-18). Duration/target now cfg-driven.
	_cycle_tween.tween_property(self, "position:y", float(rcfg.fly_target_y), float(rcfg.fly_time)).set_trans(Tween.TRANS_LINEAR)
	await _cycle_tween.finished
	if not is_instance_valid(self):
		return
	scale = _pre_cycle_scale
	modulate = _pre_cycle_modulate
	_set_outline_visible(true)        # back on the gameplay layer — restore the outline
	set_engine_trail_emitting(true)   # ...and the engine exhaust
	start_pos = position
	_cycling = false
	# Reset the auto-rotate position tracker so the first post-cycle
	# move computes a fresh delta vector.
	_rot_init = false
	set_deferred("monitorable", true)
	set_deferred("monitoring", true)
	# Re-arm firing for the next pass. Path-phase enemies just reset their phase
	# index (they re-fire by band progress on the new descent); timer enemies re-arm
	# the ShootTimer with the same short first-poll as spawn.
	_phase_fire_idx = 0
	_beat_fire_at = -1.0
	if has_node("ShootTimer") and fire_on_phase == "" and fire_path_phases.is_empty():
		# Same short first-poll as spawn (zone-gated) so a recycled enemy fires
		# again on its next engagement pass, not late on the long interval.
		$ShootTimer.wait_time = 0.2 if fire_zone_gated else randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()
	if _pattern and _pattern.has_method("on_start"):
		_pattern.on_start(self)
	_components_start()  # re-fire component on_start for the new pass (no-op if none)


# enemy.tscn template wires MoveTimer/ShootTimer to legacy callbacks.
func _on_timer_timeout() -> void:
	speed = randf_range(75, 100)
	follow_anchor = false


func _on_shoot_timer_timeout() -> void:
	# Dead enemies don't shoot: explode() sets _dying before the ~0.5s death
	# animation, during which the timer could otherwise fire a phantom shot.
	if _dying:
		return
	# Hard requirements before any bullet leaves the muzzle:
	#   - not parallax-cycling
	#   - fully inside the playfield
	#   - has a shoot pattern
	#   - if `fire_only_on_target`, nose must be aligned with the player
	if shoot_pattern == null:
		return
	if _cycling or not _on_playfield():
		# Zone-gated enemies fast-poll here too (not just in the zone check below),
		# so a slow enemy still above the playfield margin doesn't get bumped onto
		# the long random interval and fire late once it's finally low.
		$ShootTimer.wait_time = 0.15 if fire_zone_gated else randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()
		return
	# Firing zones (bridge Â§1.8-1.9): hold fire above the engagement band (just
	# spawned) and cease fire below it (committed to leaving). Poll quickly while
	# outside so the first shot lands promptly on entering engagement.
	if fire_zone_gated and not Zones.in_engagement(position.y):
		$ShootTimer.wait_time = 0.15
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
	EnemySfxC.play_for(self)


# Path-phase firing (Â§8): called each movement frame. Fires one shot each time the
# enemy descends past the next configured band-progress fraction, so shots land at
# fixed screen positions during the pass (telegraph-friendly, never "too late") and
# a descending formation volleys together at the same Y line. Phases must be
# ascending; max phase < 1.0 means firing naturally ceases before the departure band.
func _check_path_phase_fire() -> void:
	# 1) Release a pending beat-synced shot once its global beat arrives. Checked
	# first + unconditionally so the last queued shot still fires after the final
	# phase line is crossed (idx exhausted).
	if _beat_fire_at >= 0.0 and Beat.now() >= _beat_fire_at:
		_beat_fire_at = -1.0
		_do_path_shot()
	# 2) Detect crossing the next phase line.
	if fire_path_phases.is_empty() or _phase_fire_idx >= fire_path_phases.size():
		return
	if _dying or _cycling or shoot_pattern == null:
		return
	if not _on_playfield():
		return
	if Zones.band_progress(position.y) < fire_path_phases[_phase_fire_idx]:
		return
	_phase_fire_idx += 1
	if fire_beat_synced:
		# Quantize to the shared tempo so cross-formation shots collapse into a volley.
		_beat_fire_at = Beat.next_beat_time(Beat.now())
	else:
		_do_path_shot()


# Fire one path-phase shot, re-checking the live guards (the beat-synced path defers
# the shot, so the enemy may have started dying / left the band by the time it fires).
func _do_path_shot() -> void:
	if _dying or _cycling or shoot_pattern == null or not _on_playfield():
		return
	if fire_only_on_target and not _nose_on_player():
		return
	shoot_pattern.fire(self)
	EnemySfxC.play_for(self)


func _on_movement_phase_entered(phase_name: String) -> void:
	if _dying:
		return
	if fire_on_phase == "" or phase_name != fire_on_phase:
		return
	if shoot_pattern == null:
		return
	if _cycling or not _on_playfield():
		return
	if fire_only_on_target and not _nose_on_player():
		return
	shoot_pattern.fire(self)
	EnemySfxC.play_for(self)


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
	# Sprite faces +Y at rotation=0 â†’ forward derived from rotation - PI/2.
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






