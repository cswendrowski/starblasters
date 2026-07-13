extends Object

# MountBuilder (Roman 2026-06-16) — realizes an enemy's `mounts: Array[MountSpec]` into live firing
# primitives at spawn. The single generic mounter that replaces the copy-pasted per-faction turret
# builders (zealot_turret / enemy_push / bulwark). Called from enemy_base._ready AFTER
# _init_components and BEFORE the _components_start deferral, so GUN/LAUNCHER MountComponents land in
# the live _components list and pick up on_start (deferred, after start()) + on_process for free.
#
# Preload-const (NOT class_name), per the firing-resource convention.

const MountSpecC = preload("res://scripts/enemies/mounts/mount_spec.gd")
const MountComponentC = preload("res://scripts/enemies/mounts/mount_component.gd")
const EnemyTurretC = preload("res://scripts/enemies/enemy_turret.gd")
const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
const OrbitComponentC = preload("res://scripts/enemies/components/orbit_component.gd")


# Realize every spec. Returns the GUN/LAUNCHER MountComponents (the caller registers them into the
# enemy's live component list — enemy_base owns that); turret/beam nodes are added to the tree here.
static func attach_all(enemy: Node, specs: Array) -> Array:
	var comps: Array = []
	for s in specs:
		if s == null:
			continue
		var c = attach(enemy, s)
		if c != null:
			comps.append(c)
	return comps


# Returns a MountComponent for a Bullet/Projectile/Entity payload (caller registers it), or null for a
# Turret delivery / Beam payload (those attach as child nodes here).
static func attach(enemy: Node, spec):
	# TURRET delivery keeps its own node realization (Phase B will let it deliver any payload).
	if int(spec.kind) == MountSpecC.Kind.TURRET:
		_attach_turrets(enemy, spec)
		return null
	# Beam PAYLOAD (Hardpoint v2 Phase A, 2026-07-05): a non-empty beam_config realizes as a continuous
	# BeamEmitter whatever the kind, so BEAM is just "Beam payload × Direct delivery" — the kind is kept
	# as a zero-churn alias (a kind:"beam" carries a beam_config; the routing now keys on the payload).
	if int(spec.kind) == MountSpecC.Kind.BEAM or not spec.beam_config.is_empty():
		_attach_beam(enemy, spec)
		return null
	# Ring DELIVERY (Hardpoint v2 Phase C, 2026-07-05): an OrbitComponent holding N rings of payloads,
	# released on death/leave. Returned as a component the caller registers — enemy_base then ticks its
	# on_start/on_process/on_death/on_leave (the same lifecycle the bespoke bloom/mines rings use).
	if int(spec.kind) == MountSpecC.Kind.RING:
		var oc = OrbitComponentC.new()
		oc.mode = int(spec.orbit_mode)
		oc.rings = spec.rings
		oc.release_speed = spec.release_speed
		oc.host_drift = spec.host_drift
		oc.release_sfx = spec.release_sfx
		return oc
	# Bullet or Projectile payload → a MountComponent with its own fire timer (the gun-vs-launcher spawn
	# path is chosen at fire time by payload_scene; Phase A launcher collapse). ENTITY also rides it.
	var mc = MountComponentC.new()
	mc.spec = spec
	return mc


static func _markers(enemy: Node, pattern: String) -> Array:
	if pattern == "":
		return []
	return enemy.find_children(pattern, "Marker2D", true, false)


static func _attach_turrets(enemy: Node, spec) -> void:
	var mounts := _markers(enemy, String(spec.marker))
	if mounts.is_empty():
		_build_turret(enemy, spec, null)   # hull-mounted (no marker, e.g. bulwark)
		return
	for m in mounts:
		_build_turret(enemy, spec, m)


static func _build_turret(enemy: Node, spec, mount) -> void:
	var t = EnemyTurretC.new()
	t.rotation_speed = spec.rotation_speed
	t.arc_deg = spec.arc_deg
	t.rest_angle_deg = spec.rest_angle_deg
	t.arc_gate = spec.arc_gate
	t.lock_to_fire = spec.lock_to_fire
	t.lock_duration = spec.lock_duration
	t.fire_interval_min = spec.fire_interval_min
	t.fire_interval_max = spec.fire_interval_max
	t.aim_tolerance_deg = spec.aim_tolerance_deg
	t.lead_factor = spec.lead_factor
	t.bullet_variant = spec.payload
	if spec.bullet_speed > 0.0:
		t.bullet_speed = spec.bullet_speed
	t.count = int(spec.count)            # fan volley (turrets honor count/spread now, like guns)
	t.spread_deg = float(spec.spread_deg)
	t.recoil_frames = spec.recoil_frames
	t.homing_rate = spec.homing_rate
	t.wobble_amplitude = spec.wobble_amplitude
	t.wobble_frequency = spec.wobble_frequency
	# Phase B: forward the shared firing settings so a turret delivery honors them (deviation, burst,
	# volleys, payload delay) and can deliver a PROJECTILE payload (payload_scene) instead of a bullet.
	t.deviation_deg = spec.deviation_deg
	t.burst_interval = spec.burst_interval
	t.volleys = spec.volleys
	t.volley_gap = spec.volley_gap
	t.payload_delay_ms = spec.payload_delay_ms
	t.payload_scene = spec.payload_scene
	t.muzzle_distance = spec.muzzle_distance   # fire from the barrel tip, not the pivot
	# Mount-drawn barrel: only when NOT reusing a scene turret sprite (turret_node).
	if String(spec.turret_node) == "" and spec.turret_texture != null:
		var s := Sprite2D.new()
		s.texture = spec.turret_texture
		s.hframes = maxi(1, int(spec.turret_hframes))
		s.frame = clampi(int(spec.turret_frame), 0, s.hframes - 1)   # combined base sheets: pick the barrel frame
		s.z_index = int(spec.turret_z)   # render above the hull's building/overlay layers when needed
		t.add_child(s)
	var parent: Node = mount if mount != null else enemy
	parent.add_child(t)
	# Scene-authored barrel (Roman 2026-07-14): reparent the named scene Sprite2D (+ its child muzzle
	# markers) UNDER the turret so the authored turret layer + its muzzles rotate as one — no mount-drawn
	# duplicate. Muzzles resolve recursively inside EnemyTurret; marker_mode picks ALL vs cycle-one.
	if String(spec.turret_node) != "":
		t.marker_mode = int(spec.marker_mode)
		var src := enemy.find_children(String(spec.turret_node), "Sprite2D", true, false)
		if not src.is_empty():
			var ts: Sprite2D = src[0]
			ts.visible = true
			ts.reparent(t, true)   # keep_global — rotates with the turret now
			if int(spec.turret_z) != 0:
				ts.z_index = int(spec.turret_z)   # lift into a higher z bucket than the hull building layers
	# Multi-muzzle firing (Roman 2026-07-13): reparent the enemy's turret-muzzle markers UNDER the turret
	# so they rotate with the barrel — the turret then fires from them exactly like an on-hull GUN mount.
	if String(spec.turret_muzzle) != "":
		t.marker_mode = int(spec.marker_mode)
		for m in enemy.find_children(String(spec.turret_muzzle), "Marker2D", true, false):
			if is_instance_valid(m):
				m.reparent(t, true)   # keep_global — preserves each tube's world offset, then rotates with t


static func _attach_beam(enemy: Node, spec) -> void:
	var mounts := _markers(enemy, String(spec.marker))
	if mounts.is_empty():
		# Hull-mounted beam (no marker) — a single emitter on the enemy.
		var be = BeamEmitterC.new()
		be.configure(spec.beam_config)   # autostart in the cfg → _ready begins it (mirrors enemy_core)
		enemy.add_child(be)
		return
	# One BeamEmitter per matched marker (Roman 2026-07-06). marker_mode ALL/INWARD/OUTWARD = both muzzles
	# fire in sync; CYCLE = alternating — each beam is staggered by period/n so the muzzles fire out of phase.
	var alternating: bool = int(spec.marker_mode) == MountSpecC.MarkerMode.CYCLE
	var period: float = _beam_period(spec.beam_config)
	var n: int = mounts.size()
	for i in n:
		var be = BeamEmitterC.new()
		be.configure(spec.beam_config)
		if alternating and n > 1:
			be.begin_delay = period * float(i) / float(n)
		mounts[i].add_child(be)


# The full BeamEmitter FSM cycle length — used to stagger alternating-muzzle beams evenly.
static func _beam_period(cfg: Dictionary) -> float:
	return maxf(0.1, float(cfg.get("idle_time", 0.9)) + float(cfg.get("windup_time", 1.3)) \
		+ float(cfg.get("firing_time", 1.1)) + float(cfg.get("cooldown_time", 1.5)))
