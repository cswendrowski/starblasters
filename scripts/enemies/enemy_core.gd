extends "res://scripts/enemies/enemy_base.gd"

# Pattern-driven regular enemy. Adds movement_pattern + shoot_pattern slots
# on top of EnemyBase (a null movement = hold position, e.g. a stationary
# weapon dummy), plus the parallax fly-back cycle on bottom exit. All death +
# hit + offscreen + player-finding logic lives in EnemyBase; this script is
# just the combat-fighter specifics.

const _DEFAULT_BULLET = preload("res://scenes/projectiles/projectile_ball.tscn")
# (EnemySfxC removed 2026-07-07: the fire SFX moved to the hull mount's _fire with the firing-engine
# consolidation — enemy_core no longer plays a shot sound directly.)
const FiringSchedulerC = preload("res://scripts/enemies/firing_scheduler.gd")
# Named _Hull* to avoid colliding with the same preloads a subclass (enemy_drone_carrier) declares —
# a child GDScript can't redeclare a parent const of the same name.
const _HullMountSpecC = preload("res://scripts/enemies/mounts/mount_spec.gd")
const _HullMountComponentC = preload("res://scripts/enemies/mounts/mount_component.gd")
# RecycleController is inherited from EnemyBase (don't redeclare — GDScript errors on a const that
# already exists in the parent). enemy_core uses it via _on_offscreen → RecycleController.recycle().
var bullet_scene: PackedScene = _DEFAULT_BULLET

# Pattern-driven slots.
@export var movement: Resource = null
var _pattern: Resource = null

# --- Hull weapon (shoot_pattern) ---------------------------------------------------------------
# A shoot_pattern (a Weapon Resource) is the enemy's hull weapon. Assigned via a wave override
# (director.gd), a dev lab, or baked into the .tscn. Firing-engine consolidation (2026-07-07): the
# hull no longer runs its own ShootTimer/path-phase loop — instead _realize_shoot_pattern_mount()
# wraps it in a MountComponent (kind GUN, hull_pattern = shoot_pattern) at _ready, so ONE engine
# (the mount cadence/gate/path-phase/on-phase logic on FiringScheduler) drives BOTH hull + roster
# weapons. The fields below feed that realized mount's spec; they keep the same public names so the
# director/dev/tscn consumers need zero changes. See _realize_shoot_pattern_mount.
@export var shoot_pattern: Resource = null
@export var fire_interval_min: float = 1.2
@export var fire_interval_max: float = 2.5
# Gate firing on "is my nose pointed at the player" (Viper). dot(facing, dir_to_player) >=
# cos(fire_aim_tol_deg) before a shot leaves. Forwarded to spec.fire_only_on_target.
@export var fire_only_on_target: bool = false
@export var fire_aim_tol_deg: float = 18.0
# Fire one shot whenever the movement pattern emits `phase_entered(phase_name)` == this name
# (Hover/Skirmisher hold). Forwarded to spec.fire_on_phase (the mount fires from on_phase). Empty =
# cadence/path-phase firing.
@export var fire_on_phase: String = ""
# Firing-zone gating (bridge Â§1.8-1.9): only fire inside the engagement Y-band (Zones) — hold fire
# on entry, cease fire once low. The director enables this per spawn. Forwarded to spec.fire_zone_gated.
@export var fire_zone_gated: bool = false
# Path-phase firing (construction Â§8): ascending [0,1] band-progress fractions to fire at, instead of
# cadence. Auto-populated in _realize_shoot_pattern_mount for monotonic descenders (path_phase_capable
# patterns) with a weapon + no fire_on_phase; a scene/roster preset is respected. Forwarded to
# spec.fire_path_phases.
@export var fire_path_phases: PackedFloat32Array = PackedFloat32Array()
# The default phases live in the shared FiringScheduler (roadmap P3.9). DEFAULT_PATH_PHASES is its
# single source; the auto-populate at realize time reads it. (Plain Array — a PackedFloat32Array(...)
# constructor is NOT a constant expression; converted to a packed array at the assignment site.)
const DEFAULT_PATH_PHASES := FiringSchedulerC.DEFAULT_PATH_PHASES
# Shared beat (Beat): quantize path-phase shots to the next global beat so formations volley together.
# Forwarded to spec.fire_beat_synced. False = fire immediately on the phase line.
@export var fire_beat_synced: bool = true
# The realized hull-weapon mount (a MountComponent wrapping shoot_pattern), or null when the enemy has
# no hull weapon. Built lazily by _realize_shoot_pattern_mount so a late shoot_pattern assignment (dev
# labs assign then call start()) still gets a working weapon.
var _hull_mount = null

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
	# Realize the hull weapon (shoot_pattern) as a MountComponent so ONE firing engine drives both hull
	# + roster weapons (firing-engine consolidation 2026-07-07). Done AFTER super._ready() so it lands in
	# the same _components list roster mounts do; the deferred _components_start (forced below) fires its
	# on_start after start() positions the enemy — exactly like the old ShootTimer arm-on-start.
	_realize_shoot_pattern_mount()
	# Oblique drop-shadow under the enemy sprite.
	if has_node("Sprite2D"):
		var ShadowFx = load("res://scripts/effects/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D)


# Wrap the hull `shoot_pattern` in a MountComponent (kind GUN, hull_pattern = shoot_pattern) so the
# mount cadence/gate/path-phase/on-phase engine drives it — the single firing path. No-op when there's
# no hull weapon (mine carriers, mount-only enemies) or when already realized (idempotent for a late
# start()-time re-check). The spec mirrors what enemy_core's ShootTimer path used to read directly.
func _realize_shoot_pattern_mount() -> void:
	if _hull_mount != null or shoot_pattern == null:
		return
	var spec = _HullMountSpecC.new()
	spec.kind = _HullMountSpecC.Kind.GUN
	spec.fire_interval_min = fire_interval_min
	spec.fire_interval_max = fire_interval_max
	spec.fire_zone_gated = fire_zone_gated
	spec.fire_only_on_target = fire_only_on_target
	spec.fire_aim_tol_deg = fire_aim_tol_deg
	spec.fire_on_phase = fire_on_phase
	spec.fire_beat_synced = fire_beat_synced
	# Path-phase auto-populate (was in _start_with_pattern): a monotonic descender with a weapon fires by
	# band-Y progress instead of cadence when nothing more specific is set (explicit phases / fire_on_phase).
	# `movement` (the resource) is available here pre-start; a pre-set fire_path_phases is respected as-is.
	var phases: PackedFloat32Array = fire_path_phases
	if fire_on_phase == "" and phases.is_empty() and movement != null \
			and movement.has_method("path_phase_capable") and movement.path_phase_capable():
		phases = PackedFloat32Array(DEFAULT_PATH_PHASES)
	spec.fire_path_phases = phases
	var mc = _HullMountComponentC.new()
	mc.spec = spec
	mc.hull_pattern = shoot_pattern
	_hull_mount = mc
	# super._ready() defers _components_start ONLY when _components was already non-empty at its check.
	# If the hull mount is the FIRST/only component, super skipped the deferral — schedule it here so the
	# hull weapon's on_start fires. When other components already existed, super deferred it, so appending
	# is enough (don't double-defer → double on_start).
	var need_defer: bool = _components.is_empty()
	_components.append(mc)
	if need_defer:
		call_deferred("_components_start")


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
	# Firing is owned by the realized hull mount (see _realize_shoot_pattern_mount): cadence, path-phase
	# auto-populate, zone/nose gates, and beat-sync all live on the MountComponent + FiringScheduler now.
	# The mount's on_start (via the deferred _components_start / recycle _components_start) re-arms it.
	# Ship-kinematics: cache the pattern's fidelity class + reset the applied-velocity filter state
	# (spec §7 constraint 5 — reset on start/recycle) so a fresh spawn / re-used instance starts from
	# rest and doesn't inherit the previous pass's velocity.
	_kin_fidelity = _pattern.fidelity() if _pattern.has_method("fidelity") else ShipKinematics.Fidelity.EXACT
	_applied_vel = Vector2.ZERO


func _start_stationary(pos: Vector2) -> void:
	# No movement pattern → hold the spawn position (e.g. the Weapon Lab dummy: "sits at the top and just
	# fires"). Firing is handled by the realized hull mount; nothing to arm here.
	# (Replaced the legacy MoveTimer/anchor-follow path 2026-06-23.)
	position = pos


func _process(delta: float) -> void:
	# A dying enemy has handed its transform to the death VFX (DeathEffects controller / wreck drift) —
	# the pattern must NOT keep moving it, or it fights the death's own motion (2026-07-07 death wiring).
	if _dying:
		return
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
			# Firing (cadence + path-phase) is ticked by the hull mount's on_process via _tick_components.
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


# RecycleController hook: firing is suspended automatically for the fly-back — the hull mount's on_process
# holds fire while `_cycling` (MountComponent._held checks it), so there's nothing to stop here.
func _recycle_suspend() -> void:
	pass


# RecycleController hook: re-run the pattern + re-arm firing for the next pass. _components_start re-fires
# every component's on_start, which for the hull mount resets its path-phase scheduler + re-seeds cadence
# (the old _scheduler.reset() + ShootTimer re-arm now live in MountComponent.on_start).
func _recycle_resume() -> void:
	# Reset the kinematics filter for the new pass (spec §7 constraint 5) — the fly-back tween owns
	# the transform, so the applied velocity must restart from rest when the pattern resumes.
	_applied_vel = Vector2.ZERO
	if _pattern and _pattern.has_method("on_start"):
		_pattern.on_start(self)
	_components_start()  # re-fire component on_start for the new pass (hull mount + any others)


# Movement-phase event fan-out. The firing that used to live here (fire_on_phase) is now the hull
# mount's on_phase (fanned out by _components_phase below) — one firing engine. This just relays the
# event to every component (mounts + shields + emitters); _dying guards a phantom shot on a dying host.
func _on_movement_phase_entered(phase_name: String) -> void:
	if _dying:
		return
	_components_phase(phase_name)


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






