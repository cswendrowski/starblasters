extends Node2D
class_name EnemyTurret

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
const BulletCatalog = preload("res://scripts/projectiles/bullet_catalog.gd")
const Clarity = preload("res://scripts/systems/clarity.gd")
const ProjectileMods = preload("res://scripts/enemies/projectile_mods.gd")

# Reusable aiming + firing component. Add as a child of any enemy node.
# Handles player tracking, arc clamping, post-shot rotation lock, and
# bullet spawning. The parent only needs to expose find_player() or be
# in the scene tree so the group scan fallback works.

@export var rotation_speed: float = 2.0          # rad/s
@export var arc_deg: float = 0.0                  # 0 = unlimited; ±arc_deg/2 around rest_angle_deg
@export var rest_angle_deg: float = 0.0           # arc centre in local parent space (deg)
# Arc GATING (Roman 2026-06-08, extracted from the bomber tail gunner): when true and
# arc_deg > 0, the turret HOLDS FIRE while the player is outside the arc (a rear/flank
# gunner with a true blind spot), instead of the default behavior which clamps the aim to
# the arc edge and keeps shooting. The barrel still rotates/clamps toward the player.
@export var arc_gate: bool = false
@export var lock_to_fire: bool = false            # freeze rotation for lock_duration after each shot
@export var lock_duration: float = 0.4            # seconds rotation is locked after firing
@export var fire_interval_min: float = 2.0
@export var fire_interval_max: float = 2.0
@export var aim_tolerance_deg: float = 11.0
# Target leading (spec "aimed_lead", Roman 2026-06-08): 0 = aim at the player's
# CURRENT position ("aimed_wild"); >0 leads by player.velocity × lead_factor
# seconds, so a moving player gets shot ahead of. ~0.2 reads as a competent gunner.
@export var lead_factor: float = 0.0
@export var bullet_variant: BulletVariant = null
@export var bullet_speed: float = 160.0
# Fire this far along the barrel from the turret pivot (the barrel TIP), so bullets leave the muzzle
# instead of the turret's centre. Rotates with the aim. 0 = fire from the pivot (the old behaviour).
# Only used when the host has no Muzzle markers of its own (mount-drawn turrets). (Roman 2026-07-13.)
@export var muzzle_distance: float = 0.0
@export var enabled: bool = true
# Volley shape (Roman 2026-06-29): fire `count` bullets fanned across `spread_deg` each shot, mirroring
# gun/launcher mounts. Defaults (1 / 0) = a single aimed shot, so existing turrets are unchanged.
@export var count: int = 1
@export var spread_deg: float = 0.0
# Projectile-movement axis (M6a.2): the turret is a firing emitter, so it drives
# homing/wobble on its bullets the same way shoot_pattern does — independent of the
# bullet .tres. >0 overrides the variant's seed.
@export var homing_rate: float = 0.0
@export var wobble_amplitude: float = 0.0
@export var wobble_frequency: float = 0.0
# Barrel-recoil animation (Roman 2026-06-07): when the turret's barrel Sprite2D is
# a multi-frame strip (frame 0 idle, 1..N-1 recoil), flick through the recoil frames
# on each shot then snap back to idle. 0 = no recoil (single-frame barrels unaffected).
@export var recoil_frames: int = 0
# --- Shared firing settings (Hardpoint v2 Phase B 2026-07-05): a turret is now a DELIVERY that honors
# the same firing knobs a gun mount does, so "turrets need the rest of the firing settings" is covered.
# All default to the turret's old single-aimed-shot behavior, so existing turrets are unchanged. ---
@export var deviation_deg: float = 0.0            # random ± angle jitter per shot (inaccuracy); 0 = pinpoint
@export var burst_interval: float = 0.0           # space the `count` shots over time (0 = one simultaneous fan)
@export var volleys: int = 1                      # fire the whole count-shot fan this many times per shot
@export var volley_gap: float = 0.0               # seconds between volleys
@export var payload_delay_ms: float = 0.0         # hold the spawned payload at the muzzle before it moves
@export var payload_scene: PackedScene = null     # PROJECTILE payload (missile/rocket) — a turret can now
                                                  # deliver a projectile instead of a bullet (wins over bullet_variant)

var _barrel: Sprite2D = null
var _turret_rot: float = 0.0
var _fire_t: float = 0.0
var _next_interval: float = 2.0
var _locked: bool = false
var _lock_t: float = 0.0


func _ready() -> void:
	# Random spawn-time desync (KEPT) — staggers this turret's first shot so identical turrets across a
	# wave don't volley in lockstep. The steady-state interval itself is deterministic (see _fire_interval).
	_fire_t = randf_range(0.5, fire_interval_max)
	_next_interval = _fire_interval()
	var p := get_parent()
	if p and not p.tree_exiting.is_connected(queue_free):
		p.tree_exiting.connect(queue_free)
	# Barrel = first child Sprite2D (the visual the builder added). Used for recoil.
	for c in get_children():
		if c is Sprite2D:
			_barrel = c
			break


func _process(delta: float) -> void:
	if not enabled:
		return
	var p := get_parent()
	if p == null or not is_instance_valid(p):
		return
	# Hold fire + freeze aim while the OWNING enemy is recycling (flying back through the parallax) or
	# dying — a turret on a ship mid-recycle/mid-death must not keep shooting (Roman 2026-07-01). Walk
	# the WHOLE ancestor chain: a turret can sit on a sub-part (DestructiblePart) whose recycling core is
	# higher up, so the direct parent alone isn't enough.
	if _host_suspended():
		return

	if _locked:
		_lock_t -= delta
		if _lock_t <= 0.0:
			_locked = false
		_fire_t += delta
		_try_fire()
		return

	var player := find_player()
	var target_rot: float = _turret_rot
	if player:
		var dir: Vector2 = (_aim_point(player) - global_position).normalized()
		target_rot = atan2(dir.y, dir.x) + PI * 0.5
		if arc_deg > 0.0:
			var center: float = p.global_rotation + deg_to_rad(rest_angle_deg)
			target_rot = _clamp_to_arc(target_rot, center, deg_to_rad(arc_deg * 0.5))
	var diff := angle_difference(_turret_rot, target_rot)
	_turret_rot += clamp(diff, -rotation_speed * delta, rotation_speed * delta)
	# _turret_rot is a WORLD-space aim angle (atan2 to the player). `rotation` is
	# LOCAL to the parent, so subtract the parent's world rotation to keep the
	# turret's GLOBAL facing on target even when the hull is auto-rotated to face
	# its travel direction (Roman 2026-06-08). On an unrotated hull global_rotation
	# is 0, so this is a no-op for fixed-facing platforms (gunship, cruiser, etc.).
	rotation = _turret_rot - p.global_rotation
	_fire_t += delta
	_try_fire()


# True if any ancestor enemy is recycling or dying — the turret then holds fire + freezes. Duck-typed
# on `_cycling`/`_dying` and walks to the root (NOT stopping at the first EnemyBase) so a turret on a
# sub-part still sees its recycling core above it. Non-enemy ancestors (markers, layers) are skipped.
func _host_suspended() -> bool:
	var n: Node = get_parent()
	while n != null:
		if ("_cycling" in n and n._cycling) or ("_dying" in n and n._dying):
			return true
		n = n.get_parent()
	return false


# Deterministic fire cadence (firing-consistency pass 2026-07-02, parity with MountComponent._roll_interval).
# Replaces the old per-shot randf_range(min, max): re-rolling every shot made the turret's rhythm wander
# unpredictably. We fire at a FIXED interval — the midpoint of min/max — for a steady, readable cadence.
# The random spawn-time desync (_fire_t seed in _ready) keeps identical turrets from firing in perfect
# lockstep, so the fixed rate doesn't read as robotic. Floor at 0.1s so a degenerate 0/0 can't busy-loop.
func _fire_interval() -> float:
	return maxf(0.1, (fire_interval_min + fire_interval_max) * 0.5)


func _try_fire() -> void:
	if _fire_t < _next_interval:
		return
	var player := find_player()
	if player == null:
		return
	var dir: Vector2 = (_aim_point(player) - global_position).normalized()
	var target_rot: float = atan2(dir.y, dir.x) + PI * 0.5
	# Arc gate: a blind-spot gunner holds fire when the player is outside its cone (the
	# RAW aim, before the _process arc-clamp). The barrel may sit at the arc edge; no shot.
	if arc_gate and arc_deg > 0.0:
		var p := get_parent()
		if p != null:
			var center: float = p.global_rotation + deg_to_rad(rest_angle_deg)
			if abs(angle_difference(center, target_rot)) > deg_to_rad(arc_deg * 0.5):
				return
	if abs(angle_difference(_turret_rot, target_rot)) > deg_to_rad(aim_tolerance_deg):
		# Not aimed yet — do NOT reset _fire_t; check again next frame.
		return
	_fire_t = 0.0
	_next_interval = _fire_interval()
	_shoot()
	if recoil_frames > 0:
		_recoil()
	if lock_to_fire:
		_locked = true
		_lock_t = lock_duration


# Fire the shot(s). Phase B: `volleys` fans, each a burst of `count` shots — so a turret honors the
# same volley/burst/deviation knobs a gun mount does. The default (volleys 1, burst 0, deviation 0,
# count 1) is one synchronous aimed shot, identical to the pre-Phase-B turret. Async only kicks in when
# a burst/volley gap is set; called fire-and-forget from _try_fire.
func _shoot() -> void:
	var volley_n: int = maxi(1, volleys)
	for v in volley_n:
		if v > 0 and volley_gap > 0.0:
			await get_tree().create_timer(volley_gap, false).timeout
			# A turret is a Node (freed with its host mid-burst), NOT a RefCounted component — so guard
			# self-validity INLINE before any method/property access, short-circuiting on a freed self.
			if not is_instance_valid(self) or not enabled or not is_inside_tree() or _host_suspended():
				return
		await _fire_fan()


# One fan of `count` shots from a single muzzle position (matches the old single-spawn behavior), spaced
# by burst_interval when set. Re-aims between burst shots as the turret keeps tracking.
func _fire_fan() -> void:
	var world: Node = BulletWorld.resolve(_host(), get_tree().root)
	var owner: Node = _owner_enemy()   # for the faction/sector weapon mults + velocity inheritance
	var spawn_pos: Vector2 = _muzzle_pos()
	var base_dir: Vector2 = _barrel_dir()
	var n: int = maxi(1, count)
	var is_burst: bool = burst_interval > 0.0
	for i in n:
		if is_burst and i > 0:
			await get_tree().create_timer(burst_interval, false).timeout
			if not is_instance_valid(self) or not enabled or not is_inside_tree() or _host_suspended():
				return
			base_dir = _barrel_dir()   # re-aim between burst shots
		var dir: Vector2 = _deviate(_fan_dir(base_dir, i, n))
		_spawn_shot(dir, spawn_pos, world, owner)
		if is_burst:
			_play_muzzle_sfx(spawn_pos, dir, world)
	if not is_burst:
		_play_muzzle_sfx(spawn_pos, base_dir, world)


# Spawn one shot in `dir` — a PROJECTILE payload (payload_scene) if set, else the turret's bullet.
func _spawn_shot(dir: Vector2, spawn_pos: Vector2, world: Node, owner: Node) -> void:
	# Projectile payload (Phase B): a turret can now deliver a missile/rocket, aimed by its own tracking.
	if payload_scene != null:
		var proj = payload_scene.instantiate()
		if "initial_dir" in proj:
			proj.initial_dir = dir
		_apply_delay(proj)
		world.add_child(proj)
		if proj.has_method("start"):
			proj.start(spawn_pos)
		elif proj is Node2D:
			proj.global_position = spawn_pos
		return
	# Bullet payload: faction-skin the variant + resolve its indexed scene (unified projectiles), so a
	# turret fires the same frame-reskinned bullet a gun mount does. No variant → the shared shell.
	var bv = BulletCatalog.faction_variant(bullet_variant, _faction()) if bullet_variant != null else null
	var scn: PackedScene = BulletCatalog.scene_for(bv) if bv != null else null
	if scn == null:
		scn = load("res://scenes/projectiles/projectile_ball.tscn")
	if scn == null:
		return
	var b = scn.instantiate()
	if bv != null and "variant" in b:
		b.variant = bv
	world.add_child(b)
	if b.has_method("start"):
		b.start(spawn_pos, dir)   # _apply_variant sets speed from the .tres
	else:
		b.global_position = spawn_pos
		if "velocity_dir" in b:
			b.velocity_dir = dir
		if "speed" in b:
			b.speed = bullet_speed   # fallback only for a variant-less bullet
		elif "velocity" in b:
			b.velocity = dir * bullet_speed
	# Faction/sector weapon scaling + velocity inheritance (Doppler) — the same steps gun/hull bullets get
	# in shoot_pattern._spawn_bullet, so a turret's shots aren't the odd one out (Roman 2026-07-02).
	ProjectileMods.apply_weapon_scalars(b, owner)
	ProjectileMods.apply_condition_speed(b)
	if owner != null:
		if "speed" in b and "_last_move_vel" in owner:
			var fwd: float = maxf(0.0, owner._last_move_vel.dot(dir))
			if fwd > 0.0:
				b.speed = minf(b.speed + fwd, Clarity.ABS_MAX_SPEED)
	# Movement axis — drive homing/wobble post-spawn (after _apply_variant seeded), so the firing layer
	# (turret) owns movement, not the bullet .tres.
	if homing_rate > 0.0 and "homing_rate" in b:
		b.homing_rate = homing_rate
	if wobble_amplitude > 0.0 and "wobble_amplitude" in b:
		b.wobble_amplitude = wobble_amplitude
		b.wobble_frequency = wobble_frequency
	_apply_delay(b)


# The turret's current world-space aim direction (barrel forward).
func _barrel_dir() -> Vector2:
	return Vector2(cos(_turret_rot - PI * 0.5), sin(_turret_rot - PI * 0.5))


func _host() -> Node:
	var p := get_parent()
	return p if p != null else self


# Fire from the parent enemy's muzzle marker when it has one (gun_turret has a `Muzzle`), else from this
# turret node's own position. Mount-only enemies (bulwark, firecore_cruiser) report has_muzzles()==false.
func _muzzle_pos() -> Vector2:
	var p := get_parent()
	if p != null and p.has_method("has_muzzles") and p.has_muzzles():
		return p.next_muzzle_pos()
	if muzzle_distance != 0.0:
		return global_position + _barrel_dir() * muzzle_distance   # fire from the barrel tip
	return global_position


# Random shot deviation (inaccuracy): jitter the direction by ±deviation_deg. No-op when 0.
func _deviate(dir: Vector2) -> Vector2:
	if deviation_deg <= 0.0:
		return dir
	var d: float = deg_to_rad(deviation_deg)
	return dir.rotated(randf_range(-d, d))


# Payload Delay: hold the freshly-spawned payload at the muzzle before its motion begins (ms → s).
func _apply_delay(b) -> void:
	if b == null or payload_delay_ms <= 0.0:
		return
	if "motion_delay" in b:
		b.motion_delay = payload_delay_ms / 1000.0


# Muzzle flash (only when the host exposes muzzles) + the positional fire sound, classified off this
# turret's bullet_variant (small/tracer → enemy_mg, else enemy_blaster).
func _play_muzzle_sfx(spawn_pos: Vector2, dir: Vector2, world: Node) -> void:
	var p := get_parent()
	if p != null and p.has_method("has_muzzles") and p.has_muzzles():
		var MuzzleFx = load("res://scripts/effects/muzzle_fx.gd")
		MuzzleFx.play_enemy(spawn_pos, dir, world)
	EnemySfxC.play(get_tree().root, spawn_pos, EnemySfxC.kind_for(self))


# i-th direction in an n-wide fan around `base` (no fan when spread_deg<=0 or n==1).
func _fan_dir(base: Vector2, i: int, n: int) -> Vector2:
	if spread_deg <= 0.0 or n <= 1:
		return base
	var total: float = deg_to_rad(spread_deg)
	return base.rotated(-total * 0.5 + total / float(n - 1) * float(i))


# The owning enemy's faction skin (the director/bench stamp it on the enemy). A turret is parented to
# the enemy or one of its markers, so walk up to the first node carrying the meta. -1 = no skin.
func _faction() -> int:
	var n: Node = self
	while n != null:
		if n.has_meta("faction_skin"):
			return int(n.get_meta("faction_skin"))
		n = n.get_parent()
	return -1


# The owning enemy (turret is parented to it or one of its markers) — the node carrying the weapon
# multipliers + velocity. Found by walking up to the first node with bullet_speed_mult. null = none.
func _owner_enemy() -> Node:
	var n: Node = get_parent()
	while n != null:
		if "bullet_speed_mult" in n:
			return n
		n = n.get_parent()
	return null


# Flick the barrel through its recoil frames (1 -> max -> back to idle 0) on a shot.
func _recoil() -> void:
	if _barrel == null or not is_instance_valid(_barrel) or _barrel.hframes < 2:
		return
	var last: int = mini(recoil_frames, _barrel.hframes - 1)
	_barrel.frame = 1
	var tw := create_tween()
	tw.tween_interval(0.04)
	tw.tween_callback(func(): if is_instance_valid(_barrel): _barrel.frame = last)
	tw.tween_interval(0.07)
	tw.tween_callback(func(): if is_instance_valid(_barrel): _barrel.frame = 0)


# World point to aim at: the player's current position, optionally led by
# velocity × lead_factor (spec aimed_wild vs aimed_lead). Falls back to the raw
# position when the player has no `velocity` to predict from.
func _aim_point(player: Node) -> Vector2:
	var p: Vector2 = player.global_position
	if lead_factor > 0.0 and "velocity" in player:
		p += player.velocity * lead_factor
	return p


func find_player() -> Node:
	var p := get_parent()
	if p and p.has_method("find_player"):
		return p.find_player()
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null


func _clamp_to_arc(target: float, center: float, half_arc: float) -> float:
	var d := angle_difference(center, target)
	return center + clamp(d, -half_arc, half_arc)
