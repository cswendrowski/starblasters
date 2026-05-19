extends "res://scripts/enemies/enemy_base.gd"
class_name BaseMissile

# Shared missile class for both enemy ordnance (Interceptor drops,
# Sentinel salvos) and player ordnance (rocket pods, seeking missiles).
# Drift → ignite → home → detonate. Single HP, 2× scale.
#
# `target_group` switches sides:
#   "player"  — enemy missile: joins "enemies" group, homes the player,
#               damages player on contact (calls take_damage).
#   "enemies" — player missile: stays out of "enemies" group so it isn't
#               friendly-fire-able, homes the nearest enemy, damages via
#               take_hit() on contact.
@export var target_group: String = "player"

# 320×400 res rework: speed-based fields halve so missiles cross the
# same fraction of playfield per second.
@export var drift_time: float = 0.25
@export var drift_speed: float = 80.0
@export var homing_accel: float = 380.0
@export var homing_max_speed: float = 220.0
# Roman, 2026-05-18 seeker rework: missiles fly straight unless a target
# is within seeker_cone_deg of the nose. When acquired, max_speed is
# doubled to `homing_max_speed * speed_lock_mult` so the missile dives
# decisively. `lock_accel_mult` ramps acceleration too so the speed-up
# happens in a beat instead of half a second.
@export var seeker_cone_deg: float = 25.0
@export var speed_lock_mult: float = 2.0
@export var lock_accel_mult: float = 2.5

# Set true once a target enters the cone; never returns to false.
var _locked: bool = false
@export var fuse: float = 6.0
@export var damage_on_contact: int = 1
# Dumb-fire mode (Roman, 2026-05-16): straight-line acceleration in the
# initial direction, NO homing toward the player. Used for rocket-pod
# style ordnance where the launch direction is the lock.
@export var dumb_fire: bool = false
# Visual flame trail toggle. When true, the missile draws a small
# additive flame at its rear (post-ignite) and trails a Line2D smoke
# spline behind it that fades over ~1.5s. Off by default so existing
# Interceptor/Sentinel missiles keep their compact look.
@export var flame_trail: bool = false

# Direction of the initial drift. Callers can set this in start() if they
# want a forward-fired launch (e.g. Sentinel salvos pointing toward the
# player).
@export var initial_dir: Vector2 = Vector2(0, 1)

const BASE_SCALE := Vector2(1.0, 1.0)

var _vel: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _ignited: bool = false
# Flame + smoke trail nodes; created on _ready when `flame_trail` is true.
var _trail_line: Line2D = null
var _flame_sprite: Sprite2D = null
var _flame_t: float = 0.0


func _ready() -> void:
	max_health = 1
	bounty_value = 5
	display_scale = 1.0
	# Missiles leave the playfield naturally and should free themselves on
	# any edge rather than parallax-cycling.
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	# Player missiles (target_group == "enemies") must NOT join the
	# "enemies" group — they'd otherwise be self-targeted. EnemyBase
	# joins the group by default; remove it after super._ready() runs.
	super._ready()
	if target_group == "enemies":
		# Player ordnance: leave the enemies group; pin a default initial
		# direction of "up" so launch goes from ship muzzle toward the top.
		if is_in_group("enemies"):
			remove_from_group("enemies")
		if initial_dir == Vector2(0, 1):
			initial_dir = Vector2(0, -1)
	scale = BASE_SCALE
	var dir: Vector2 = initial_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	_vel = dir * drift_speed + Vector2(randf_range(-30.0, 30.0), 0.0)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1.0, 0.85, 0.7, 1.0)
	if flame_trail:
		_build_trail_line()


# Smoke trail spline parented to the SceneTree root so it survives the
# missile's queue_free at detonation (the trail fades out on its own).
func _build_trail_line() -> void:
	_trail_line = Line2D.new()
	_trail_line.width = 5.0
	_trail_line.default_color = Color(0.85, 0.85, 0.9, 0.55)
	# Gradient — bright/opaque at the rocket end, transparent at the tail.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.95, 0.92, 0.86, 0.0),
		Color(0.85, 0.85, 0.9, 0.65),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	_trail_line.gradient = grad
	# Slight thinning toward the tail for a "smoke dissipates" feel.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	_trail_line.width_curve = curve
	get_tree().root.call_deferred("add_child", _trail_line)


func start(pos: Vector2) -> void:
	global_position = pos


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	if not _ignited and _t >= drift_time:
		_ignite()
	if _ignited:
		if dumb_fire:
			# Accelerate along the initial heading — don't turn toward the
			# player. Steady push so the rocket reads as committed.
			var fwd: Vector2 = initial_dir.normalized()
			if fwd == Vector2.ZERO:
				fwd = Vector2(0, 1)
			_vel = _vel.move_toward(fwd * homing_max_speed, homing_accel * delta)
		else:
			# Roman, 2026-05-18: seeker missiles fly straight unless a
			# target enters the cone in front of them. Once acquired,
			# they LOCK and don't unlock — double speed rapidly.
			var fwd: Vector2 = _vel.normalized() if _vel.length_squared() > 0.001 else initial_dir.normalized()
			if fwd == Vector2.ZERO:
				fwd = Vector2(0, 1) if target_group == "player" else Vector2(0, -1)
			var p = _find_homing_target_in_cone(fwd) if not _locked else _find_homing_target()
			var target_dir: Vector2 = fwd  # default: continue straight
			if p and is_instance_valid(p):
				target_dir = (p.global_position - global_position).normalized()
				_locked = true
			var max_speed: float = homing_max_speed * (speed_lock_mult if _locked else 1.0)
			var accel_use: float = homing_accel * (lock_accel_mult if _locked else 1.0)
			_vel = _vel.move_toward(target_dir * max_speed, accel_use * delta)
	global_position += _vel * delta
	# Rotate the missile sprite to point along its velocity. Same trick
	# as EnemyBase auto_rotate, but applied here so missiles aren't
	# sliding sideways during their homing arc (Roman, 2026-05-16:
	# "Rockets/Missiles should be rotating as they fly").
	if _vel.length_squared() > 4.0:
		rotation = _vel.angle() + PI * 0.5
	# Smoke trail: append current world pos to the Line2D each frame.
	# Roman 2026-05-18: drift older points toward the bottom of the screen
	# so the trail reads as "left behind" by forward motion; sprinkle a
	# tiny per-emit perpendicular jitter so it reads as turbulent smoke.
	if _trail_line != null and is_instance_valid(_trail_line):
		const FORWARD_DRIFT_SPEED: float = 60.0
		const PUFF_NOISE_PX: float = 1.4
		var emit_pos: Vector2 = global_position + Vector2(
			randf_range(-PUFF_NOISE_PX, PUFF_NOISE_PX),
			randf_range(-PUFF_NOISE_PX * 0.4, PUFF_NOISE_PX * 0.4),
		)
		_trail_line.add_point(emit_pos)
		# Drift all but the newest point downward; the newest sits at the
		# rocket and shouldn't lag behind.
		var pc: int = _trail_line.get_point_count()
		var drift: float = FORWARD_DRIFT_SPEED * delta
		for i in range(pc - 1):
			# Older points drift faster (newer → smaller offset).
			var t: float = 1.0 - float(i) / float(max(1, pc - 1))
			var p: Vector2 = _trail_line.get_point_position(i)
			_trail_line.set_point_position(i, p + Vector2(0.0, drift * (0.4 + 0.9 * (1.0 - t))))
		while _trail_line.get_point_count() > 50:
			_trail_line.remove_point(0)
	# Flame flicker — wobble the rear glow's scale + brightness so it
	# reads as a live engine rather than a static halo.
	if _flame_sprite != null and is_instance_valid(_flame_sprite):
		_flame_t += delta * 14.0
		var pulse: float = 0.85 + 0.25 * sin(_flame_t)
		_flame_sprite.scale = Vector2(0.55 + 0.15 * pulse, 0.85 + 0.25 * pulse)
		_flame_sprite.modulate = Color(1.0, 0.55 + 0.1 * pulse, 0.20 + 0.10 * pulse, 1.0)
	# Fuse expiry detonates with VFX rather than the silent FREE_ANY_EDGE
	# path — distinguishes "I burned out" from "I flew off-screen".
	if _t >= fuse:
		explode()
		return
	_offscreen_cleanup_check()


func _ignite() -> void:
	_ignited = true
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1.6, 0.55, 0.25, 1.0)
	# Flickering orange glow at the rear (Roman, 2026-05-16: "flickering
	# orange glow on their rear when active"). Sits behind the sprite,
	# additive blend, scale wobble driven by _flame_t in _process.
	if flame_trail and _flame_sprite == null:
		var s := Sprite2D.new()
		s.texture = _flame_glow_texture()
		s.position = Vector2(0, 8)
		s.scale = Vector2(0.6, 0.9)
		s.modulate = Color(1.0, 0.6, 0.25, 1.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		s.material = mat
		s.z_index = -1
		add_child(s)
		_flame_sprite = s


static var _flame_glow_tex: Texture2D = null
static func _flame_glow_texture() -> Texture2D:
	if _flame_glow_tex != null:
		return _flame_glow_tex
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 24
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.4)
	t.fill_to = Vector2(1.0, 0.7)
	_flame_glow_tex = t
	return t


# Player contact: deal damage and self-destruct with VFX.
# Find a homing target — the player for enemy missiles, the nearest
# enemy (by Manhattan distance, cheap) for player missiles.
# Scan the target group for the nearest valid target whose direction
# from the missile is within `seeker_cone_deg` of forward. Used to
# decide whether to acquire a target on a missile that's flying
# straight (pre-lock). Once locked, fall back to plain _find_homing_target.
func _find_homing_target_in_cone(fwd: Vector2):
	var cos_tol: float = cos(deg_to_rad(seeker_cone_deg))
	if target_group == "player":
		var best_p: Node = null
		for n in get_tree().get_nodes_in_group("player"):
			var to_n: Vector2 = n.global_position - global_position
			if to_n.length_squared() < 1.0:
				continue
			if fwd.dot(to_n.normalized()) >= cos_tol:
				return n
		return best_p
	var best: Node = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or n == self:
			continue
		if n.has_meta("bulwark_shielded"):
			continue
		var to_n: Vector2 = n.global_position - global_position
		if to_n.length_squared() < 1.0:
			continue
		if fwd.dot(to_n.normalized()) < cos_tol:
			continue
		var nd: float = abs(to_n.x) + abs(to_n.y)
		if nd < best_d:
			best_d = nd
			best = n
	return best


func _find_homing_target():
	if target_group == "player":
		for n in get_tree().get_nodes_in_group("player"):
			return n
		return null
	# Player ordnance: scan the enemies group and pick the closest one
	# that's actually inside the playfield. Skip bulwark-shielded enemies
	# so a wild missile doesn't waste itself chasing an invulnerable target.
	var best: Node = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n) or n == self:
			continue
		if n.has_meta("bulwark_shielded"):
			continue
		var nd: float = abs(n.global_position.x - global_position.x) + abs(n.global_position.y - global_position.y)
		if nd < best_d:
			best_d = nd
			best = n
	return best


func _on_area_entered(area: Area2D) -> void:
	if area == self or _dying:
		return
	if not area.is_in_group(target_group):
		return
	if target_group == "player":
		# Enemy missile hitting player.
		if area.has_method("take_damage") and "hull" in area:
			area.take_damage(damage_on_contact)
			explode()
	else:
		# Player missile hitting enemy. Use the unified take_hit contract
		# from EnemyBase; fall back to direct health decrement for any
		# legacy enemy that hasn't migrated.
		if area.has_method("take_hit"):
			area.take_hit(damage_on_contact)
		elif "health" in area:
			area.health -= damage_on_contact
			if area.health < 1 and area.has_method("explode"):
				area.explode()
			elif area.has_method("hit"):
				area.hit()
		explode()


# Single HP — any bullet hit is fatal. EnemyBase.take_hit covers this
# automatically; the override here is just to skip the non-fatal `hit()`
# branch entirely (no hit-particle node on this scene).
func hit() -> void:
	explode()


# When the missile dies — by bullet, contact, or fuse — hand off the
# Line2D smoke spline so it can fade on its own after we queue_free.
# Override _leave so the trail Line2D fades out when the missile exits
# the playfield via FREE_ANY_EDGE rather than getting orphaned at the
# scene root (Cody, 2026-05-18 playtest: "missiles that leave the top
# of the screen never clean up their trail").
func _leave() -> void:
	if _dying:
		return
	if _trail_line != null and is_instance_valid(_trail_line):
		var line: Line2D = _trail_line
		_trail_line = null
		var tw: Tween = line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(line.queue_free)
	super._leave()


func explode() -> void:
	if _dying:
		return
	if _trail_line != null and is_instance_valid(_trail_line):
		var line: Line2D = _trail_line
		_trail_line = null
		var tw: Tween = line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(line.queue_free)
	# Explosive impact flash + fiery explosion (Roman, 2026-05-17 sprite
	# pass). Color taken from the warhead's flame trail tint (warm
	# orange/yellow) so the flash reads as ignition.
	var ImpactFxCls = load("res://scripts/effects/impact_fx.gd")
	if ImpactFxCls:
		ImpactFxCls.spawn(get_tree().root, global_position, Color(1.0, 0.65, 0.25, 1.0), 1)
	# Fall through to EnemyBase.explode for the standard die-emit + VFX.
	super.explode()
