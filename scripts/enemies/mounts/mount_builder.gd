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
	if spec.turret_texture != null:
		var s := Sprite2D.new()
		s.texture = spec.turret_texture
		s.hframes = maxi(1, int(spec.turret_hframes))
		t.add_child(s)
	var parent: Node = mount if mount != null else enemy
	parent.add_child(t)


static func _attach_beam(enemy: Node, spec) -> void:
	var be = BeamEmitterC.new()
	be.configure(spec.beam_config)   # autostart in the cfg → _ready begins it (mirrors enemy_core)
	var mounts := _markers(enemy, String(spec.marker))
	var parent: Node = mounts[0] if not mounts.is_empty() else enemy
	parent.add_child(be)
