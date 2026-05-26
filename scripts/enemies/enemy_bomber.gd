extends "res://scripts/enemies/enemy_base.gd"

# Bomber Wing unit (Roman 2026-05-18). Flies in a V-formation, settles
# in the upper-middle of the screen, fires TWO slow-traversing rear
# turrets at the player. Tough (shield + high HP), rare random event.
#
# Sprite: ship_6 (48×48). Coords (sprite-local with centered pivot at
# 24,24):
#   Turret L pixel (14, 26) → (-10, 2)
#   Turret R pixel (32, 26) → (8, 2)
#   Damage tell L pixel (11, 39) → (-13, 15)
#   Damage tell R pixel (39, 39) → (15, 15)
#
# Bomber faces UP (rear toward player). Each turret's "rear" arc is a
# 150° wedge centered on +Y so the player gets hit when chasing.

const BulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const TURRET_BULLET_TEX = preload("res://graphics/projectiles/tracer-yellow.png")

# --- Shape / stats ------------------------------------------------------
@export var shield_charges_max: int = 2
@export var hover_y: float = 110.0
@export var enter_speed: float = 45.0
@export var sway_amplitude: float = 8.0
@export var sway_period: float = 7.0
@export var formation_drift_pct: float = 0.35

# --- Turret --------------------------------------------------------------
@export var turret_traverse_speed_deg: float = 35.0
@export var turret_arc_deg: float = 150.0
# Cadence halved per Roman 2026-05-18.
@export var turret_fire_interval_min: float = 0.36
@export var turret_fire_interval_max: float = 0.60
@export var turret_bullet_speed: float = 260.0
const TURRET_DEVIATION_NEAR: float = 0.06
const TURRET_DEVIATION_FAR: float = 0.32
const MIN_RANGE_PX: float = 80.0
const MAX_RANGE_PX: float = 360.0
# Two turret muzzles + two damage tells.
const TURRET_LOCALS := [Vector2(-10, 2), Vector2(8, 2)]
const DAMAGE_TELL_LOCALS := [Vector2(-13, 15), Vector2(15, 15)]

# Per-turret state.
var _turret_angles: Array = [PI * 0.5, PI * 0.5]
var _fire_ts: Array = [0.0, 0.0]
var _shield: int = 0
var _slot_anchor: Vector2 = Vector2.ZERO
var _enter_t: float = 0.0
var _sway_seed: float = 0.0

const HitFlashFx = preload("res://scripts/effects/hit_flash_fx.gd")

signal hull_changed(max_hull, hull)


func _ready() -> void:
	if max_health <= 1:
		max_health = 16
	if bounty_value <= 0:
		bounty_value = 100
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	_shield = shield_charges_max
	_sway_seed = randf() * TAU
	# V-formation slotting was only ever assigned by the deleted
	# WaveGeneratorV2 path — production WaveGen never registered wings,
	# so bombers always landed on the no-slot branch. Keep the bare
	# anchor so wing-formations could be reintroduced via a new path.
	_slot_anchor = Vector2(position.x, hover_y)
	# Two sets of damage tells — fire + smoke at both rear positions.
	var EngineTorchCls = preload("res://scripts/effects/engine_torch.gd")
	const DamageSmokeTrailCls = preload("res://scripts/effects/damage_smoke_trail.gd")
	for tell in DAMAGE_TELL_LOCALS:
		EngineTorchCls.attach_to_player(self, tell)
		var trail = DamageSmokeTrailCls.new()
		trail.emit_local = tell
		add_child(trail)
		trail.set_player(self)
	_build_shield_ring()
	hull_changed.emit(max_health, health)
	_update_shield_visual()


func _build_shield_ring() -> void:
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("alpha", 0.0)
	_shield_mat.set_shader_parameter("hit_strength", 0.0)
	_shield_ring = ColorRect.new()
	_shield_ring.name = "ShieldRing"
	_shield_ring.color = Color(1, 1, 1, 1)
	_shield_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wrap the 48×48 sprite with a bit of padding.
	var ring_sz: float = 60.0
	_shield_ring.size = Vector2(ring_sz, ring_sz)
	_shield_ring.position = -_shield_ring.size * 0.5
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 1
	add_child(_shield_ring)


func _update_shield_visual() -> void:
	if _shield_mat == null:
		return
	var lit: float = 0.0
	if _shield > 0:
		lit = clamp(float(_shield) / float(max(1, shield_charges_max)), 0.2, 1.0)
	_shield_mat.set_shader_parameter("alpha", lit * 0.85)


var hull: int:
	get:
		return health
	set(value):
		health = value
var max_hull: int:
	get:
		return max_health
	set(value):
		max_health = value


func take_hit(damage: int = 1) -> bool:
	if _dying:
		return false
	if _shield > 0:
		_shield -= 1
		if _shield_mat:
			_shield_mat.set_shader_parameter("hit_strength", 1.0)
			if _shield_hit_tween and _shield_hit_tween.is_valid():
				_shield_hit_tween.kill()
			_shield_hit_tween = create_tween()
			_shield_hit_tween.tween_method(func(v): _shield_mat.set_shader_parameter("hit_strength", v), 1.0, 0.0, 0.4)
		_update_shield_visual()
		if has_node("Sprite2D"):
			HitFlashFx.flash($Sprite2D, HitFlashFx.FLASH_SHIELD)
		hull_changed.emit(max_health, health)
		return false
	var was_killed: bool = super.take_hit(damage)
	hull_changed.emit(max_health, health)
	return was_killed


func _process(delta: float) -> void:
	if _dying:
		return
	_enter_t += delta
	if position.y < _slot_anchor.y:
		position.y = min(position.y + enter_speed * delta, _slot_anchor.y)
	var t: float = _enter_t + _sway_seed
	var sway_x: float = sway_amplitude * sin(t * TAU / sway_period)
	var sway_y: float = sway_amplitude * 0.4 * sin(t * TAU / sway_period * 1.7)
	position.x = _slot_anchor.x + sway_x * formation_drift_pct
	if position.y >= _slot_anchor.y:
		position.y = _slot_anchor.y + sway_y * formation_drift_pct
	_update_turrets(delta)


func _update_turrets(delta: float) -> void:
	var player := find_player() as Node2D
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	var rear_angle: float = to_player.angle()
	var off_from_rear: float = wrapf(rear_angle - PI * 0.5, -PI, PI)
	var arc_half: float = deg_to_rad(turret_arc_deg) * 0.5
	var target_off: float = clamp(off_from_rear, -arc_half, arc_half)
	var target_angle: float = PI * 0.5 + target_off
	var max_step: float = deg_to_rad(turret_traverse_speed_deg) * delta
	for ti in TURRET_LOCALS.size():
		var cur: float = float(_turret_angles[ti])
		var diff: float = wrapf(target_angle - cur, -PI, PI)
		if abs(diff) <= max_step:
			cur = target_angle
		else:
			cur += sign(diff) * max_step
		_turret_angles[ti] = cur
		# Per-turret fire timer.
		if abs(off_from_rear) > arc_half:
			continue
		var aim_err: float = abs(wrapf(cur - rear_angle, -PI, PI))
		if aim_err > deg_to_rad(20.0):
			continue
		_fire_ts[ti] = float(_fire_ts[ti]) - delta
		if float(_fire_ts[ti]) > 0.0:
			continue
		_fire_ts[ti] = randf_range(turret_fire_interval_min, turret_fire_interval_max)
		_fire_turret(ti, to_player.length())


func _fire_turret(idx: int, dist_to_player: float) -> void:
	var t: float = clamp((dist_to_player - MIN_RANGE_PX) / (MAX_RANGE_PX - MIN_RANGE_PX), 0.0, 1.0)
	var deviation: float = lerp(TURRET_DEVIATION_NEAR, TURRET_DEVIATION_FAR, t)
	var fire_angle: float = float(_turret_angles[idx]) + randf_range(-deviation, deviation)
	var b = BulletScene.instantiate()
	b.global_position = to_global(TURRET_LOCALS[idx])
	var dir: Vector2 = Vector2(cos(fire_angle), sin(fire_angle))
	if "velocity_dir" in b:
		b.velocity_dir = dir
	if "speed" in b:
		b.speed = turret_bullet_speed
	get_tree().root.add_child(b)
	var spr: Sprite2D = b.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		spr.texture = TURRET_BULLET_TEX
		spr.rotation = fire_angle + PI * 0.5


# Death: keep some forward momentum, darken to black overlay, slow to a
# halt, then drift off-screen (Roman 2026-05-18).
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	_run_bomber_death.call_deferred()


func _run_bomber_death() -> void:
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	# Death physics — keep most of the bomber's downward momentum so it
	# slumps off the bottom of the screen (Roman 2026-05-18).
	var v_y: float = enter_speed * 1.6
	var v_x: float = (position.x - _slot_anchor.x) * 0.5
	var decel: float = 14.0           # gentler braking — keeps falling
	var min_drift: float = 70.0       # floor velocity so it actually exits
	var blast_times := [0.0, 0.45, 1.1, 1.8]
	var t_elapsed: float = 0.0
	var max_dur: float = 6.0
	var darken_dur: float = 1.8
	# Shrink target — roughly 30% smaller over the death sequence
	# (Roman 2026-05-18: 1.0 → ~0.70 scale over time).
	var start_scale: Vector2 = scale
	var shrink_dur: float = 3.5
	var shrink_target: Vector2 = start_scale * 0.70
	if _shield_ring and is_instance_valid(_shield_ring):
		_shield_ring.visible = false
	while is_instance_valid(self) and t_elapsed < max_dur:
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		v_y = max(min_drift, v_y - decel * dt)
		v_x *= 0.96
		position += Vector2(v_x, v_y) * dt
		# Darken modulate over darken_dur.
		var dk_t: float = clamp(t_elapsed / darken_dur, 0.0, 1.0)
		var brightness: float = lerp(1.0, 0.4, dk_t)
		modulate = Color(brightness, brightness, brightness, 1.0)
		# Shrink over shrink_dur with an ease-out curve.
		var sh_t: float = clamp(t_elapsed / shrink_dur, 0.0, 1.0)
		var sh_eased: float = 1.0 - pow(1.0 - sh_t, 2.0)
		scale = start_scale.lerp(shrink_target, sh_eased)
		for bt_idx in blast_times.size():
			var bt: float = float(blast_times[bt_idx])
			if bt >= 0.0 and t_elapsed >= bt:
				if ExplosionFx:
					# 1× explosions only; jitter handles the "bigness" read.
					var jitter: Vector2 = Vector2(randf_range(-16.0, 16.0), randf_range(-12.0, 12.0))
					ExplosionFx.play(global_position + jitter, 1.0)
				blast_times[bt_idx] = -1.0
		var vp: Vector2 = get_viewport_rect().size
		if position.y > vp.y + 60.0:
			break
		t_elapsed += dt
		await get_tree().process_frame
	if is_instance_valid(self):
		queue_free()
