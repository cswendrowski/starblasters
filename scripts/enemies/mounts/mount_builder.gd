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


# Returns a MountComponent for GUN/LAUNCHER (caller registers it), or null for TURRET/BEAM (those
# attach as child nodes here).
static func attach(enemy: Node, spec):
	match int(spec.kind):
		MountSpecC.Kind.TURRET:
			_attach_turrets(enemy, spec)
			return null
		MountSpecC.Kind.BEAM:
			_attach_beam(enemy, spec)
			return null
		_:
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
	t.recoil_frames = spec.recoil_frames
	t.homing_rate = spec.homing_rate
	t.wobble_amplitude = spec.wobble_amplitude
	t.wobble_frequency = spec.wobble_frequency
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
