extends "res://scripts/enemies/enemy_base.gd"

# Pattern-driven regular enemy. Adds movement_pattern + shoot_pattern slots
# on top of EnemyBase (a null movement = hold position, e.g. a stationary
# weapon dummy), plus the parallax fly-back cycle on bottom exit. All death +
# hit + offscreen + player-finding logic lives in EnemyBase; this script is
# just the combat-fighter specifics.

const _DEFAULT_BULLET = preload("res://scenes/projectiles/enemy_bullet.tscn")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
# RecycleController is inherited from EnemyBase (don't redeclare — GDScript errors on a const that
# already exists in the parent). enemy_core uses it via _on_offscreen → RecycleController.recycle().
var bullet_scene: PackedScene = _DEFAULT_BULLET

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
# (Zones.band_progress) at which to fire â€” fires at fixed screen positions during the
# descent, instead of on the random ShootTimer. MUST be ascending. Non-empty disables
# the timer. Auto-populated in _start_with_pattern for monotonic descenders
# (path_phase_capable patterns) that have a weapon and no fire_on_phase; a scene/roster
# may set it explicitly to override.
@export var fire_path_phases: PackedFloat32Array = PackedFloat32Array()
# Plain Array const (a PackedFloat32Array(...) constructor is NOT a constant
# expression â€” it fails to parse the whole script). Converted to a packed array at
# the assignment site below.
# Firing-consistency pass (2026-07-02): first phase near the TOP of the band (0.1 -> ~y63,
# ~23px after entry = "fires promptly on entering") and the second at mid-band (0.5 -> ~y118),
# both kept clear of the DEPARTURE_START (195) edge. The old [0.35, 0.75] held fire for the
# first third (read as "fires late") and put the 2nd shot at the departure edge (read as "only
# fires when leaving"). Keep ascending + <=0.6 so no shot lands in the departure band.
const DEFAULT_PATH_PHASES := [0.1, 0.5]
var _phase_fire_idx: int = 0  # next phase index to fire (advances as the enemy descends)
# Shared beat (Beat): when true, a path-phase shot doesn't fire the instant it crosses
# its phase line - it quantizes to the next global beat (Beat.next_beat_time) so enemies
# across formations volley together. Set false to fire immediately on the phase line.
@export var fire_beat_synced: bool = true
var _beat_fire_at: float = -1.0  # engine-clock time a pending beat-synced shot fires (-1 = none)

# Ship-kinematics applied-velocity state (roadmap P1.5 — 2026-07-02). The velocity actually applied
# last frame; the ShipKinematics filter eases it toward the pattern's desired velocity per the
# pattern's fidelity class (EXACT bypasses entirely, SMOOTH is the old inertia feel, EXACT_Y_SMOOTH_X
# filters lateral only). Reset in _start_with_pattern + _recycle_resume (spec §7 constraint 5). The
# old inline INERTIA_ACCEL now lives in ShipKinematics.SMOOTH_ACCEL (same 2400 value / feel).
var _applied_vel: Vector2 = Vector2.ZERO
var _kin_fidelity: int = ShipKinematics.Fidelity.EXACT

# When an external driver (e.g. a seq_bombing_run sequence) owns this enemy's transform,
# enemy_core SUSPENDS its own movement / firing / component ticks so the two don't fight.
# The driver flips this true on start and false (or frees the enemy) when done. Set on the
# enemy_core base so any composed enemy can be driven by a sequenced attack.
var external_control: bool = false

# Cycling state (_cycling) + is_recycling() + _set_outline_visible() live on EnemyBase now — the
# fly-back itself is owned by RecycleController.recycle() (2026-06-29). This script just pauses its
# movement/firing while _cycling and supplies the firing suspend/re-arm via the hooks below.

# Pattern-driven enemies use CYCLE_BOTTOM by default (the parallax
# re-entry). Leavers can flip this to FREE_ANY_EDGE / FREE_OPPOSITE_SIDE.


func _ready() -> void:
	super._ready()
	# Oblique drop-shadow under the enemy sprite.
	if has_node("Sprite2D"):
		var ShadowFx = load("res://scripts/effects/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


func start(pos: Vector2) -> void:
	if movement != null:
		_start_with_pattern(pos)
	else:
		_start_stationary(pos)


func _start_with_pattern(pos: Vector2) -> void:
	position = pos
	_pattern = movement.duplicate()
	# Chassis move_speed/accel are applied by the director at spawn from the resolved
	# roster/formation stats, and patterns read those for SCALE. Speeds are used as
	# authored — the +5%/sector locomotion scale was dropped 2026-06-23 with the
	# single-sector switch. (Was a per-@export-float walk before the 2026-06-19 refactor.)
	# Connect phase events BEFORE on_start so the initial-phase emit lands.
	if _pattern.has_signal("phase_entered") \
		and not _pattern.is_connected("phase_entered", _on_movement_phase_entered):
		_pattern.phase_entered.connect(_on_movement_phase_entered)
	if _pattern.has_method("on_start"):
		_pattern.on_start(self)
	# Path-phase firing (Â§8): a monotonic descender with a weapon fires by band-Y
	# progress instead of the random timer. Auto-enable when the pattern supports it
	# and nothing more specific is configured (explicit phases, or a fire_on_phase
	# event). A pre-set fire_path_phases (scene/roster) is respected as-is.
	if shoot_pattern != null and fire_on_phase == "" and fire_path_phases.is_empty() \
			and _pattern.has_method("path_phase_capable") and _pattern.path_phase_capable():
		fire_path_phases = PackedFloat32Array(DEFAULT_PATH_PHASES)
	_phase_fire_idx = 0
	_beat_fire_at = -1.0
	# Ship-kinematics: cache the pattern's fidelity class + reset the applied-velocity filter state
	# (spec §7 constraint 5 — reset on start/recycle) so a fresh spawn / re-used instance starts from
	# rest and doesn't inherit the previous pass's velocity.
	_kin_fidelity = _pattern.fidelity() if _pattern.has_method("fidelity") else ShipKinematics.Fidelity.EXACT
	_applied_vel = Vector2.ZERO
	# Only arm the shoot timer if the enemy *can* shoot. A null shoot_pattern
	# means this enemy has no weapon â€” don't let a timer fire bullets via
	# the legacy bullet_scene fallback. Roman, 2026-05-17: minelayer/mine
	# carriers should not shoot.
	# Phase-driven (fire_on_phase) and path-phase (fire_path_phases) enemies fire on
	# their own triggers, so we skip the random timer for them.
	if shoot_pattern != null and has_node("ShootTimer") and fire_on_phase == "" and fire_path_phases.is_empty():
		# Zone-gated enemies arm a short first poll so the FIRST shot lands as soon
		# as they enter the engagement band (the gate fast-polls until then). The
		# full fire interval would otherwise delay the first shot until they've
		# descended near the bottom. Subsequent shots re-arm on the normal interval.
		if fire_zone_gated:
			$ShootTimer.wait_time = 0.2
		else:
			$ShootTimer.wait_time = _fire_interval()
		$ShootTimer.start()


func _start_stationary(pos: Vector2) -> void:
	# No movement pattern → hold the spawn position (e.g. the Weapon Lab dummy: "sits at the
	# top and just fires"). Still arm the shoot timer so a weapon-carrying stationary enemy fires.
	# (Replaced the legacy MoveTimer/anchor-follow path 2026-06-23.)
	position = pos
	if shoot_pattern != null and has_node("ShootTimer") and fire_on_phase == "" and fire_path_phases.is_empty():
		$ShootTimer.wait_time = _fire_interval()
		$ShootTimer.start()


func _process(delta: float) -> void:
	# A sequenced attack (bombing run) owns the transform — skip movement/firing/components.
	if external_control:
		return
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
			if _kin_fidelity != ShipKinematics.Fidelity.EXACT and safe_delta > 0.0:
				# Ship-kinematics velocity filter (roadmap P1.5 — 2026-07-02): ease the APPLIED
				# velocity toward the pattern's desired one per the pattern's fidelity class, so the
				# unit reads as a ship with mass instead of snapping direction. SMOOTH = the old
				# inertia feel (heavier = laggier); EXACT_Y_SMOOTH_X filters lateral only (lane STEP
				# hops) while leaving the descent raw. `_last_move_vel` is set from the APPLIED
				# velocity (spec §7 constraint 5 — wreck drift + beat-sync prediction consume it).
				var desired_vel: Vector2 = step / safe_delta
				_applied_vel = ShipKinematics.filter(_applied_vel, desired_vel, accel, weight,
					safe_delta, _kin_fidelity)
				var applied_step: Vector2 = _applied_vel * safe_delta
				# Lane-lag safety clamp (spec §7 constraint 2): keep the filtered lateral X within a
				# few px of the closed-form lane X the LaneTraffic free-checks assume. The high lateral
				# budget already holds this; this is a belt-and-suspenders snap under a frame hitch.
				if _kin_fidelity == ShipKinematics.Fidelity.EXACT_Y_SMOOTH_X:
					# step.x = closed_form_target_x − position.x, so (applied_step.x − step.x) is exactly
					# the cumulative error between the filtered X and the closed-form lane X this frame.
					var err_x: float = applied_step.x - step.x
					if absf(err_x) > ShipKinematics.LANE_LAT_MAX_ERR:
						var corr: float = err_x - signf(err_x) * ShipKinematics.LANE_LAT_MAX_ERR
						applied_step.x -= corr
						_applied_vel.x = applied_step.x / safe_delta
				position += applied_step
				_last_move_vel = _applied_vel
			else:
				position += step
				if safe_delta > 0.0:
					_last_move_vel = step / safe_delta   # px/s — for wreck-drift motion preservation
			_clamp_to_sides()
			_offscreen_cleanup_check()
			_apply_auto_rotation(safe_delta)
			_check_path_phase_fire()
			_tick_components(safe_delta)
		return
	# No movement pattern (stationary enemy, e.g. the Weapon Lab dummy): just tick components.
	_tick_components(delta)


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


# Override EnemyBase's offscreen hook: instead of freeing, hand off to RecycleController for the
# parallax fly-back (it owns recycle_passes accounting + the tween; -1 unlimited / 0 leave /
# N decrement-then-cycle). The firing suspend/re-arm flows back through the hooks below.
func _on_offscreen() -> void:
	RecycleController.recycle(self)


# RecycleController hook: stop firing for the duration of the fly-back.
func _recycle_suspend() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()


# RecycleController hook: re-arm firing for the next pass + re-run the pattern/components.
# Path-phase enemies just reset their phase index (they re-fire by band progress on the new
# descent); timer enemies re-arm the ShootTimer with the same short first-poll as spawn.
func _recycle_resume() -> void:
	_phase_fire_idx = 0
	_beat_fire_at = -1.0
	# Reset the kinematics filter for the new pass (spec §7 constraint 5) — the fly-back tween owns
	# the transform, so the applied velocity must restart from rest when the pattern resumes.
	_applied_vel = Vector2.ZERO
	if has_node("ShootTimer") and fire_on_phase == "" and fire_path_phases.is_empty():
		$ShootTimer.wait_time = 0.2 if fire_zone_gated else _fire_interval()
		$ShootTimer.start()
	if _pattern and _pattern.has_method("on_start"):
		_pattern.on_start(self)
	_components_start()  # re-fire component on_start for the new pass (no-op if none)


# Deterministic fire cadence (firing-consistency pass 2026-07-02). Replaces the old
# per-shot randf_range(fire_interval_min, fire_interval_max): re-rolling every shot made an
# enemy's rhythm wander unpredictably. We now fire at a FIXED interval â€” the midpoint of the
# roster's min/max â€” so a given enemy type has a steady, readable cadence. (Staggered band
# entry across a wave keeps identical enemies from firing in perfect lockstep, so the fixed
# rate doesn't read as robotic.) The roster's min/max are kept as the tuning source; their
# average IS the cadence. Floor at 0.1s so a degenerate 0/0 can't busy-loop the timer.
func _fire_interval() -> float:
	return maxf(0.1, (fire_interval_min + fire_interval_max) * 0.5)


func _on_shoot_timer_timeout() -> void:
	# Dead enemies don't shoot: explode() sets _dying before the ~0.5s death
	# animation, during which the timer could otherwise fire a phantom shot.
	if _dying:
		return
	# Suspended by an external driver (bombing run): keep the timer alive but don't fire,
	# so normal firing resumes cleanly once control returns.
	if external_control:
		if has_node("ShootTimer"):
			$ShootTimer.wait_time = 0.2
			$ShootTimer.start()
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
		# the full fire interval and fire late once it's finally low.
		$ShootTimer.wait_time = 0.15 if fire_zone_gated else _fire_interval()
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
		$ShootTimer.wait_time = max(0.1, _fire_interval() * 0.4)
		$ShootTimer.start()
		return
	shoot_pattern.fire(self)
	$ShootTimer.wait_time = _fire_interval()
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
		# Quantize to the shared tempo so cross-formation shots collapse into a volley —
		# BUT only when the enemy will still be inside the engagement band when that beat
		# lands. Fast movers (Hot Rods at 300 px/s) cross the whole 155px band in ~0.5s,
		# less than the 0.45s beat period, so a deferred shot would fire in (or past) the
		# departure band — fire NOW instead so the shot lands in-zone. Slow waves still
		# get their beat-synced volley. (Roman 2026-06-14: "fire properly in the zones even
		# when moving fast".)
		var beat_at: float = Beat.next_beat_time(Beat.now())
		var predicted_y: float = position.y + _last_move_vel.y * maxf(0.0, beat_at - Beat.now())
		if predicted_y >= Zones.DEPARTURE_START:
			_do_path_shot()
		else:
			_beat_fire_at = beat_at
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
	_components_phase(phase_name)   # mounts/components react to the phase (fire_on_phase mounts fire here)
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






