extends EnemyComponent

# Realizes a GUN or LAUNCHER MountSpec (Roman 2026-06-16). Fires the spec's payload from the spec's
# marker(s) on its OWN cadence, so two guns fire independently (the gunship MG+cannon pattern,
# generalized). Rides the component lifecycle: on_start/on_process are fanned out by enemy_base and
# ticked by enemy_core, so no new plumbing. GUN reuses the Weapon spawn helper (free homing/wobble +
# BulletWorld parenting + faction/sector mult-scaling + muzzle flash); LAUNCHER instantiates a
# projectile scene. Holds fire while the enemy is cycling / off-playfield, matching enemy_core's
# generic shoot-timer guards (_dying is already guarded upstream by _tick_components).
#
# Preload-const, NOT class_name (a self-referencing `MountComponent.new()` fails the headless compile
# pass; MountBuilder constructs it via its preload const, and the bench detects it by script-identity).

const WeaponC = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const MountSpecC = preload("res://scripts/enemies/mounts/mount_spec.gd")
const EnemyBullet = preload("res://scenes/projectiles/projectile_ball.tscn")
const FiringSchedulerC = preload("res://scripts/enemies/firing_scheduler.gd")
const WeaponSfxC = preload("res://scripts/effects/weapon_sfx.gd")   # ENTITY emit sfx (Phase 2)
const Playfield = preload("res://scripts/systems/playfield.gd")     # ENTITY band_only gate
const StraightDownC = preload("res://scripts/enemies/patterns/straight_down.gd")  # dropped-enemy default movement
const ProjectileMods = preload("res://scripts/enemies/projectile_mods.gd")  # Sector Conditions Fast/Slow Bullets

# @export so Resource.duplicate() carries the spec reference through per-instance duplication — the
# faction firecore overlay routes a MountComponent through enemy_base.components[] (which dups each
# component), and a NON-exported spec would be dropped by duplicate() (leaving spec == null). The
# roster/MountBuilder path appends already-built MountComponents straight into _components (no dup),
# so this only matters for the overlay — but exporting is harmless for both (spec is read-only config
# shared across dups, matching how EmitterComponent's @export fields were shared). (Roman 2026-07-07.)
@export var spec: Resource = null
# HULL-PATTERN delegation (firing-engine consolidation 2026-07-07): when set, this mount is the
# realized form of an enemy's hull `shoot_pattern` (assigned via wave override / dev lab / .tscn). Its
# _fire delegates straight to `hull_pattern.fire(enemy)` so the Weapon's OWN volley shape + muzzle
# cycling (next_muzzle_pos) are preserved byte-for-byte — the mount engine only supplies the shared
# cadence / gate / path-phase / on-phase timing that used to live in enemy_core's ShootTimer path. The
# spec carries the hull's fire fields (interval, zone/nose gates, path phases, fire_on_phase). Built by
# enemy_core._realize_shoot_pattern_mount; null for every roster/bench mount (they fire via spec).
@export var hull_pattern: Resource = null
var _weapon = null            # internal Weapon, borrowed for _spawn_bullet + aim helpers (GUN)
var _markers: Array = []
var _cycle: int = 0
var _t: float = 0.0
var _next: float = 2.0
# Trigger-resolution engine shared with enemy_core's hull (roadmap P3.9). Owns the path-phase
# line-crossing + beat-sync state. Note the mount deliberately does NOT auto-populate
# DEFAULT_PATH_PHASES (unlike the hull) — a mount path-fires ONLY when its spec sets fire_path_phases
# explicitly; auto-populating would change every mount's firing behavior. This difference is the
# reason the mount keeps its own `if not spec.fire_path_phases.is_empty()` guard rather than sharing
# an auto-populate config flag.
var _scheduler = FiringSchedulerC.new()
var _emit_count: int = 0          # ENTITY CADENCE emits this pass (vs spec.max_emits)
var _started_once: bool = false   # ENTITY START fires once per instance, not once per parallax recycle
var _last_emit_succeeded: bool = false   # ENTITY: did the last DEATH emit actually fire? (explosion routing;
                                         # mirrors EmitterComponent — read by enemy_base.did_emit_tagged)
var _fire_count: int = 0          # GUN/LAUNCHER fires this pass (vs spec.max_fires); reset in on_start


func on_start(enemy) -> void:
	_resolve_markers(enemy)
	# Reset the path-phase cursor for a fresh descent (spawn OR parallax recycle — on_start re-runs per
	# recycle via _recycle_resume -> _components_start). The old enemy_core hull reset its scheduler in
	# _recycle_resume; folding that here keeps recycling path-phase mounts (incl. realized hull patterns)
	# re-firing on every pass instead of staying exhausted after the first (firing-engine consolidation).
	_scheduler.reset()
	# HULL-PATTERN delegation: the Weapon does its own spawning, so skip the internal _weapon build +
	# marker resolution. Arm the cadence to match the OLD hull ShootTimer EXACTLY (not the mount's
	# randomized desync): the hull armed its first shot at a DETERMINISTIC _fire_interval() (the midpoint),
	# not a randf-seeded _t — so start _t at 0 and _next at the interval. This keeps shoot_pattern-realized
	# timing byte-identical to the retired enemy_core._on_shoot_timer_timeout path (baseline Case A).
	if hull_pattern != null:
		_t = 0.0
		_next = _roll_interval()
		_fire_count = 0
		return
	# Build the internal Weapon for GUN (bullet spawn) AND LAUNCHER (aim resolution — a launched
	# projectile fires along spec.aim / the parent facing, same as a gun; Roman 2026-07-04).
	if int(spec.kind) == MountSpecC.Kind.GUN or int(spec.kind) == MountSpecC.Kind.LAUNCHER:
		_weapon = WeaponC.new()
		_weapon.bullet_scene = EnemyBullet
		_weapon.payload = spec.payload
		_weapon.aim = int(spec.aim)
		_weapon.lead_factor = spec.lead_factor
		_weapon.bullet_speed = spec.bullet_speed
		_weapon.homing_rate = spec.homing_rate
		_weapon.wobble_amplitude = spec.wobble_amplitude
		_weapon.wobble_frequency = spec.wobble_frequency
	_t = randf_range(0.2, maxf(0.2, spec.fire_interval_max))   # desync, matches the bespoke _ready
	_next = _roll_interval()
	_fire_count = 0   # GUN/LAUNCHER per-pass fire cap resets each pass (on_start re-runs per recycle)
	# ENTITY (Phase 2): reset the per-pass emit budget; START emits once per instance (guarded vs the
	# per-recycle on_start re-run). CADENCE uses _t from 0 as the emit timer, matching EmitterComponent.
	if int(spec.kind) == MountSpecC.Kind.ENTITY:
		_emit_count = 0
		_t = 0.0
		if int(spec.trigger) == MountSpecC.Trigger.START and not _started_once:
			_started_once = true
			_emit_scene(enemy)


func on_process(enemy, delta: float) -> void:
	if int(spec.kind) == MountSpecC.Kind.ENTITY:
		_process_entity(enemy, delta)
		return
	if _held(enemy):
		return
	# MODE: path-phase firing (fixed band-progress lines) replaces the cadence timer — fires once as
	# the host descends past each fraction, beat-synced into a cross-formation volley.
	if not spec.fire_path_phases.is_empty():
		_tick_path_phases(enemy)
		return
	# MODE: phase-event firing — fires from on_phase() on a named movement phase, not the cadence.
	if String(spec.fire_on_phase) != "":
		return
	_t += delta
	if _t < _next:
		return
	# Conditional gates (zone / nose): hold fire + fast re-poll, mirroring enemy_core's hull shoot.
	if not _gates_pass(enemy):
		_t = 0.0
		_next = 0.15
		return
	_t = 0.0
	_next = _roll_interval()
	if spec.max_fires > 0 and _fire_count >= spec.max_fires:
		return   # spent this pass — hold until the next recycle resets _fire_count
	_fire(enemy)
	_fire_count += 1


# Phase-event firing (spec.fire_on_phase): the host movement entered a named phase; fire if it
# matches, subject to the same zone/nose gates. Fanned in by enemy_core._on_movement_phase_entered.
func on_phase(enemy, phase_name: String) -> void:
	if String(spec.fire_on_phase) == "" or phase_name != String(spec.fire_on_phase):
		return
	if _held(enemy) or not _gates_pass(enemy):
		return
	_fire(enemy)


# --- ENTITY payload (Phase 2 2026-07-03) — folds EmitterComponent: spawn payload_scene on a trigger.
# START fires in on_start, DEATH here, CADENCE via _process_entity. Behaviourally identical to the
# retired EmitterComponent (deferred insert, scatter, attach, drop-vs-launch, per-emit sfx). ---
# DEATH trigger. Tracks _last_emit_succeeded exactly like EmitterComponent: the flag is set true when
# the chance-roll passes AND the emit produced at least one payload, and cleared when the roll fails or
# there's nothing to spawn. enemy_base.did_emit_tagged reads this fresh every death for the firecore
# ball-vs-default explosion routing.
func on_death(enemy) -> void:
	if int(spec.kind) == MountSpecC.Kind.ENTITY and int(spec.trigger) == MountSpecC.Trigger.DEATH:
		if _roll_chance():
			_last_emit_succeeded = _emit_scene(enemy)
		else:
			_last_emit_succeeded = false


func _process_entity(enemy, delta: float) -> void:
	if int(spec.trigger) != MountSpecC.Trigger.CADENCE:
		return   # START (on_start) / DEATH (on_death) don't tick a timer
	if spec.max_emits > 0 and _emit_count >= spec.max_emits:
		return
	# band_only: pause the cadence off the visible band so a fast diver doesn't waste drops.
	if spec.band_only and not _in_band(enemy):
		return
	_t += delta
	if _t >= _emit_period():
		_t = 0.0
		if _roll_chance():
			_emit_scene(enemy)
			_emit_count += 1


func _emit_period() -> float:
	return maxf(0.05, spec.fire_interval_min)


func _roll_chance() -> bool:
	return spec.emit_chance >= 1.0 or randf() < spec.emit_chance


func _in_band(enemy) -> bool:
	if not (enemy is Node2D):
		return true
	var y: float = (enemy as Node2D).global_position.y
	return y >= Playfield.Y_MIN + 10.0 and y <= Playfield.Y_MAX - 20.0


# Spawn spec.count scenes at the origin (centre + scatter, or attached to the enemy). Parents to the
# BulletWorld so drops survive the enemy's queue_free, unless attach_to_enemy. Deferred insert — a
# DEATH emit runs inside a physics callback and adding an Area2D mid-flush trips the query-flush guard.
func _emit_scene(enemy) -> bool:
	# Returns true when at least one payload was queued for insertion (used by on_death to track
	# _last_emit_succeeded, mirroring EmitterComponent — a null payload / missing parent is a failed emit).
	if spec.payload_scene == null:
		return false
	var parent: Node = enemy
	if not spec.attach_to_enemy:
		parent = BulletWorld.resolve(enemy, enemy.get_tree().current_scene)
		if parent == null:
			parent = enemy.get_tree().root
	if parent == null:
		return false
	var base_pos: Vector2 = enemy.global_position
	# Inertia ON (no_inertia == false) launches the scene with the enemy's velocity; OFF drops it at rest.
	var launch_vel: Vector2 = Vector2.ZERO
	if not spec.no_inertia and "_last_move_vel" in enemy:
		launch_vel = enemy._last_move_vel
	if String(spec.emit_sfx) != "":
		WeaponSfxC.play(enemy.get_tree().root, base_pos, spec.emit_sfx)
	var any_emitted: bool = false
	for _i in maxi(1, spec.count):
		var inst = spec.payload_scene.instantiate()
		if inst == null:
			continue
		any_emitted = true
		# Drop speed (Roman 2026-07-04): an EXPLICIT hardpoint speed (spec.bullet_speed > 0) sets the
		# dropped entity's move_speed, so the bench preview matches live and it's directly tunable —
		# instead of implicitly inheriting the dropper's (lateral) speed. 0 = the entity's own authored
		# descent. Set BEFORE the deferred add_child so the entity's _ready reads it. Missiles ignore it.
		if spec.bullet_speed > 0.0 and "move_speed" in inst:
			inst.move_speed = spec.bullet_speed
		# A dropped ENEMY needs a movement pattern or it sits inert (the director assigns one in live);
		# give a straight-down default when it has the slot and none was set (Roman 2026-07-04).
		if "movement" in inst and inst.movement == null:
			inst.movement = StraightDownC.new()
		var pos: Vector2 = base_pos
		if spec.emit_scatter > 0.0:
			pos += Vector2(randf_range(-spec.emit_scatter, spec.emit_scatter), randf_range(-spec.emit_scatter, spec.emit_scatter))
		_insert_scene.call_deferred(inst, parent, pos, spec.attach_to_enemy, launch_vel)
	return any_emitted


func _insert_scene(inst, parent: Node, pos: Vector2, attach: bool, launch_vel: Vector2) -> void:
	if not is_instance_valid(parent):
		if inst is Node:
			(inst as Node).queue_free()
		return
	parent.add_child(inst)
	_apply_delay(inst)   # payload delay applies to the entity too (no-op when it has no motion_delay)
	if attach:
		if inst is Node2D:
			(inst as Node2D).position = Vector2.ZERO
	elif inst.has_method("start"):
		inst.start(pos)
		if launch_vel != Vector2.ZERO:
			_impart_velocity(inst, launch_vel)
	elif inst is Node2D:
		(inst as Node2D).global_position = pos
		if launch_vel != Vector2.ZERO:
			_impart_velocity(inst, launch_vel)


func _impart_velocity(inst, v: Vector2) -> void:
	for f in ["_vel", "_velocity", "velocity"]:
		if f in inst:
			inst.set(f, inst.get(f) + v)
			return


# Deterministic fire cadence (firing-consistency pass 2026-07-02). This IS the single cadence formula for
# every enemy weapon now (hull shoot_patterns are realized as mounts too — firing-engine consolidation).
# Replaces the old per-shot randf_range(min, max): re-rolling every shot made the mount's rhythm wander
# unpredictably. We fire at a FIXED interval — the midpoint of the roster's min/max — for a steady,
# readable cadence. The random spawn-time desync (on_start _t seed) keeps identical mounts from firing in
# perfect lockstep, so the fixed rate doesn't read as robotic. Floor at 0.1s so a degenerate 0/0 can't
# busy-loop the timer.
func _roll_interval() -> float:
	return maxf(0.1, (spec.fire_interval_min + spec.fire_interval_max) * 0.5)


# Hold fire while recycling or off the playfield — mirrors enemy_core._on_shoot_timer_timeout.
# enemy_core provides _on_playfield; pure enemy_base enemies (bombers, bulwark) don't, so we fall back
# to an inline off-screen check there too — EVERY mount holds fire until the enemy is on the visible
# playfield (Roman 2026-06-29: enemies shouldn't shoot while well off-screen). Recycling is enemy_core-only.
func _held(enemy) -> bool:
	if "_cycling" in enemy and enemy._cycling:
		return true
	if enemy.has_method("_on_playfield"):
		return not enemy._on_playfield()
	return _off_screen(enemy)


# Inline "off the visible playfield" check for enemies without _on_playfield. Mirrors enemy_core's
# 8px-margin box (X uses the full viewport so the gutters never gate; only the Y edges suppress fire).
func _off_screen(enemy) -> bool:
	if not (enemy is Node2D):
		return false
	const M := 8.0
	var sz: Vector2 = enemy.get_viewport_rect().size
	var p: Vector2 = enemy.global_position   # global — a parented host's local pos is its authored offset (2026-07-18)
	return p.x < M or p.x > sz.x - M or p.y < M or p.y > sz.y - M


# Conditional fire gates shared by cadence + path-phase — the zone/nose gate now lives in the shared
# FiringScheduler (P3.9). _held stays local (it also folds in recycling + the pure-enemy_base
# off-screen fallback, which is mount-host-specific), so the cadence path checks _held THEN gates.
func _gates_pass(enemy) -> bool:
	return _scheduler.gates_pass(enemy, spec.fire_zone_gated, spec.fire_only_on_target, spec.fire_aim_tol_deg)


# Path-phase firing: delegated to the shared FiringScheduler (line-crossing + beat-sync quantize +
# fast-mover departure escape) — the same engine the hull uses. The mount only reaches here when its
# spec set fire_path_phases explicitly (no auto-populate; see _scheduler declaration).
func _tick_path_phases(enemy) -> void:
	_scheduler.tick_path_phases(enemy, spec.fire_path_phases, spec.fire_beat_synced, _do_path_shot.bind(enemy))


# Fire one path-phase shot, re-checking the live guards (the beat-synced path defers the shot, so the
# host may have started dying / left the band by the time it fires). _held covers recycling +
# off-playfield (with the pure-enemy_base fallback); the dying re-check is the P3.9 SAFE unification —
# a pure enemy_base host isn't dying-gated on the deferred beat otherwise.
func _do_path_shot(enemy) -> void:
	if "_dying" in enemy and enemy._dying:
		return
	if _held(enemy):
		return
	if spec.fire_only_on_target and not FiringSchedulerC.nose_on_player(enemy, spec.fire_aim_tol_deg):
		return
	_fire(enemy)


func _resolve_markers(enemy) -> void:
	_markers = []
	if String(spec.marker) == "":
		return
	for m in enemy.find_children(spec.marker, "Marker2D", true, false):
		_markers.append(m)
	# INWARD/OUTWARD (Roman 2026-07-03): order the hardpoints by hull-local horizontal distance from
	# centre so a cycled/rippled volley walks outer→in (OUTWARD) or in→out (INWARD). ALL/CYCLE keep
	# scene-tree order. to_local keeps it correct if the hull is rotated.
	var mode: int = int(spec.marker_mode)
	if _markers.size() > 1 and (mode == MountSpecC.MarkerMode.INWARD or mode == MountSpecC.MarkerMode.OUTWARD):
		_markers.sort_custom(func(a, b): return absf(enemy.to_local(a.global_position).x) < absf(enemy.to_local(b.global_position).x))
		if mode == MountSpecC.MarkerMode.OUTWARD:
			_markers.reverse()


# CYCLE, INWARD, OUTWARD all fire ONE (ordered) marker per shot; ALL fires every marker each shot.
func _is_cycling() -> bool:
	return int(spec.marker_mode) != MountSpecC.MarkerMode.ALL


# Spawn positions for this volley: matched markers (ALL, or one cycled) or the hull centre.
func _spawn_positions(enemy) -> Array:
	if _markers.is_empty():
		return [enemy.global_position]
	if _is_cycling():
		var m = _markers[_cycle % _markers.size()]
		_cycle += 1
		return [m.global_position]
	var out: Array = []
	for m in _markers:
		out.append(m.global_position)
	return out


func _fire(enemy) -> void:
	# HULL-PATTERN delegation: the realized hull `shoot_pattern` owns its own volley shape (SINGLE/
	# SPREAD/BURST/BROADSIDE/AIMED) + muzzle cycling + fire SFX, so fire it directly and skip the mount's
	# gun/launcher spawn path entirely. This reproduces enemy_core's old `shoot_pattern.fire(self)` +
	# EnemySfxC.play_for(self) exactly (the Weapon plays its own burst SFX; play_for covers shot 1).
	if hull_pattern != null:
		hull_pattern.fire(enemy)
		EnemySfxC.play_for(enemy)
		return
	# Volleys (B2): fire the whole count-shot fan `volleys` times, staggered by volley_gap. volleys=1 is
	# a single volley = the original behavior. burst_interval still staggers shots WITHIN each volley.
	var volley_n: int = maxi(1, spec.volleys)
	for v in volley_n:
		if v > 0 and spec.volley_gap > 0.0:
			await enemy.get_tree().create_timer(spec.volley_gap, false).timeout
			if not is_instance_valid(enemy) or _held(enemy):
				return
		# Payload-driven path (Hardpoint v2 Phase A, 2026-07-05): a Projectile payload (spec.payload_scene)
		# takes the launcher spawn path; a Bullet payload (BulletVariant) takes the gun path. The LAUNCHER
		# kind is now just a GUN carrying a payload_scene — kept as a roster/bench alias, no longer its own
		# fire branch. (ENTITY never reaches _fire — it routes through _process_entity/_emit_scene.)
		if spec.payload_scene != null:
			await _fire_launcher(enemy)
		else:
			await _fire_gun(enemy)


func _fire_gun(enemy) -> void:
	if _weapon == null:
		return
	var n: int = maxi(1, spec.count)
	var cycling: bool = _is_cycling() and not _markers.is_empty()
	var is_burst: bool = spec.burst_interval > 0.0
	for i in n:
		if is_burst and i > 0:
			# Wait ONE interval between consecutive shots. The await is serial (it blocks the loop), so
			# each step already lands burst_interval after the previous shot — multiplying by i here
			# (the old bug) double-counted the elapsed time, stretching the gaps to 0.1/0.2/0.3 instead
			# of a steady 0.1 (Roman 2026-06-29: "2 fast, 1 late, 1 later").
			# process_always=false so the burst FREEZES with the game on pause.
			await enemy.get_tree().create_timer(spec.burst_interval, false).timeout
			# Bail if the host went away OR is now held (recycling / off the playfield) — a burst that
			# started on-screen must not keep firing into a recycle (Roman 2026-07-01).
			if not is_instance_valid(enemy) or _held(enemy):
				return
		# Re-aim per shot (the player moves between burst shots), fan if spread is set, then deviate.
		var dir: Vector2 = _deviate(_fan(_weapon._aim_dir(enemy), i, n))
		if cycling:
			var m = _markers[_cycle % _markers.size()]   # one cycled marker per shot (alternating MG muzzles)
			_cycle += 1
			_finish_shot(enemy, _weapon._spawn_bullet(enemy, dir, spec.payload, m.global_position), dir)
		else:
			for pos in _all_positions(enemy):            # every marker fires this shot (both cannons)
				_finish_shot(enemy, _weapon._spawn_bullet(enemy, dir, spec.payload, pos), dir)
		# A burst is several distinct shots over time, so each one gets its own fire sound (Roman
		# 2026-06-29). A simultaneous volley (no burst gap) stays a single sound — played once below.
		if is_burst:
			_play_sfx(enemy)
	if not is_burst:
		_play_sfx(enemy)


# All matched marker globals, or the hull centre when there's no marker.
func _all_positions(enemy) -> Array:
	if _markers.is_empty():
		return [enemy.global_position]
	var out: Array = []
	for m in _markers:
		out.append(m.global_position)
	return out


func _fire_launcher(enemy) -> void:
	if spec.payload_scene == null:
		return
	var world: Node = BulletWorld.resolve(enemy, enemy.get_tree().root)
	var n: int = maxi(1, spec.count)
	var is_burst: bool = spec.burst_interval > 0.0
	# Mirror _fire_gun: the `count` rockets/missiles are spaced by burst_interval (was a single-frame
	# clump that ignored burst, Roman 2026-06-29). Resolve spawn positions per shot so they follow the
	# moving launcher and CYCLE alternates muzzles per shot.
	for i in n:
		if is_burst and i > 0:
			# process_always=false so the burst FREEZES with the game on pause.
			await enemy.get_tree().create_timer(spec.burst_interval, false).timeout
			# Bail if the host went away OR is now held (recycling / off the playfield) — a burst that
			# started on-screen must not keep firing into a recycle (Roman 2026-07-01).
			if not is_instance_valid(enemy) or _held(enemy):
				return
		# Aim along spec.aim (FORWARD = the parent's nose) rather than a hardcoded straight-down, so the
		# launched projectile faces the way the launcher points (Roman 2026-07-04).
		var base_dir: Vector2 = _weapon._aim_dir(enemy) if _weapon != null else Vector2(0, 1)
		var dir: Vector2 = _deviate(_fan(base_dir, i, n))
		for pos in _spawn_positions(enemy):
			var proj = spec.payload_scene.instantiate()
			if "initial_dir" in proj:
				proj.initial_dir = dir
			_apply_delay(proj)
			world.add_child(proj)
			if proj.has_method("start"):
				proj.start(pos)
			elif proj is Node2D:
				proj.global_position = pos
			# Sector Conditions Fast/Slow Bullets (§4a): step the payload's speed AFTER start()/pos set
			# its baseline. LAUNCHER never carried faction/sector weapon scalars (no bullet_speed_mult
			# on this path — noted island), so ONLY the Condition-speed step is applied; no-op when no
			# Conditions are active or the payload has no `speed`.
			ProjectileMods.apply_condition_speed(proj)
			# Inertia ON (no_inertia == false) hands the projectile the launcher's velocity so it carries
			# the parent's motion; OFF (default) leaves the projectile's own launch velocity. (Roman:
			# "launcher inertia does nothing for the payload".)
			if not spec.no_inertia and "_last_move_vel" in enemy:
				_impart_velocity(proj, enemy._last_move_vel)
		if is_burst:
			_play_sfx(enemy)
	if not is_burst:
		_play_sfx(enemy)


# Random shot deviation (inaccuracy): jitter the direction by ±deviation_deg. No-op when 0.
func _deviate(dir: Vector2) -> Vector2:
	if spec.deviation_deg <= 0.0:
		return dir
	var d: float = deg_to_rad(spec.deviation_deg)
	return dir.rotated(randf_range(-d, d))


# i-th direction in a `n`-wide fan around `base` (no fan when spread_deg==0 or n==1).
func _fan(base: Vector2, i: int, n: int) -> Vector2:
	if spec.spread_deg <= 0.0 or n <= 1:
		return base
	var total: float = deg_to_rad(spec.spread_deg)
	return base.rotated(-total * 0.5 + total / float(n - 1) * float(i))


# Finish one gun shot: apply the payload Delay, then the drop-gun inertia strip.
func _finish_shot(enemy, b, dir: Vector2) -> void:
	_apply_delay(b)
	_drop_strip(enemy, b, dir)
	# Per-shot host hook (Roman 2026-07-28). Duck-typed, so this is a no-op for every enemy that
	# doesn't define it. Lets a host add recoil / extra flashes / casing ejection tied to the actual
	# shot rather than guessing at the cadence — see cannon_bay.on_mount_fired.
	if enemy != null and enemy.has_method("on_mount_fired"):
		enemy.on_mount_fired(dir, b.global_position if b is Node2D else Vector2.ZERO)


# Payload Delay (spec.payload_delay_ms): hold the freshly-spawned payload at the muzzle before its
# motion begins. Duck-typed on `motion_delay` (base_bullet / base_missile), ms → seconds.
func _apply_delay(b) -> void:
	if b == null or spec.payload_delay_ms <= 0.0:
		return
	if "motion_delay" in b:
		b.motion_delay = spec.payload_delay_ms / 1000.0


# Drop gun (spec.no_inertia): undo the velocity-inheritance the firing layer added, so the shot leaves
# at its OWN intended speed regardless of the gun's travel. Mirrors the "Doppler" add in
# shoot_pattern._spawn_bullet (same forward term) — kept in lockstep with it. Duck-typed on
# _last_move_vel: if the firing layer never added inertia, there's nothing to strip.
func _drop_strip(enemy, b, dir: Vector2) -> void:
	if not spec.no_inertia or b == null:
		return
	if "speed" in b and "_last_move_vel" in enemy:
		var fwd: float = maxf(0.0, enemy._last_move_vel.dot(dir))
		if fwd > 0.0:
			b.speed = maxf(b.speed - fwd, 1.0)


func _play_sfx(enemy) -> void:
	var kind: String = "enemy_blaster"
	if spec.payload != null and "enemy_sfx_kind" in spec.payload and String(spec.payload.enemy_sfx_kind) != "":
		kind = String(spec.payload.enemy_sfx_kind)
	var pos = enemy.global_position if enemy is Node2D else null
	EnemySfxC.play(enemy.get_tree().root, pos, kind)
