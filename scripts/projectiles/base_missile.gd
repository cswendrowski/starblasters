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

# Anti-Ship behavior (Roman, 2026-05-30): when true, target acquisition in
# the cone prefers the LARGEST in-cone enemy instead of the nearest. "Size"
# is read from the enemy's `max_health` — it tracks the heavy-ship tier
# (cruiser 16, firecore cruiser 32) where `display_scale` reads 1.0 for some
# big hulls (e.g. bomber). Default false → the regular seeking missile keeps
# its nearest-target acquisition unchanged.
@export var prefer_large: bool = false

# Set true once a target enters the cone; never returns to false.
var _locked: bool = false
# Player seeking missiles lock onto a single target. Store the reference so
# we only home toward THIS target, never re-acquire a new one.
var _locked_target: Node = null
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
const ANIM_FPS := 12.0
# Looping muzzle-flash engine plume drawn at the exhaust marker, gated on
# ignition (off during the drift/freefall). Replaces the old code-side
# gradient flame glow.
const EngineFlareCls := preload("res://scripts/effects/engine_flare.gd")

var _vel: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _ignited: bool = false
# Engine flare + exhaust marker; resolved/created in _ready.
var _engine_flare: Sprite2D = null
var _exhaust_point: Node2D = null
var _anim_frame_t := 0.0


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
		# Player ordnance: leave the enemies group so it isn't friendly-
		# fired, and drop BACKWARD off the player during the drift phase
		# (Cobalt 2026-05-21: "missiles should drop from the player and
		# fall backwards for half a second before igniting").
		if is_in_group("enemies"):
			remove_from_group("enemies")
		# initial_dir is the POST-IGNITE heading. During drift the velocity
		# is set to the opposite direction so the warhead falls away from
		# the launching ship first.
		if initial_dir == Vector2(0, 1):
			initial_dir = Vector2(0, -1)
	scale = BASE_SCALE
	var dir: Vector2 = initial_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	# Drop-backward drift only applies to seeking missiles. Rockets keep
	# the straight-forward release (Cobalt 2026-05-21 — dumb_fire rockets
	# were firing out the back of the ship after the drop change).
	var drift_dir: Vector2 = dir
	if target_group == "enemies" and not dumb_fire:
		drift_dir = -dir
	_vel = drift_dir * drift_speed + Vector2(randf_range(-30.0, 30.0), 0.0)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	# Rockets (dumb_fire) start with a warm orange pre-ignite tint so the
	# orange warhead reads as "cold then hot." Seeking missiles (teal sprite,
	# !dumb_fire) keep their natural colour — the orange tint would muddy
	# missile-teal.png and make the sprite nearly invisible.
	if has_node("Sprite2D") and dumb_fire:
		$Sprite2D.modulate = Color(1.0, 0.85, 0.7, 1.0)
	# Resolve the exhaust marker and build the engine flare HIDDEN — it
	# ignites in _ignite() so it stays off during the drift/freefall.
	# Created for every missile with an exhaust marker, independent of the
	# flame_trail flag (which only gates the smoke trail below).
	_exhaust_point = get_node_or_null("exhaust_point")
	if _exhaust_point != null:
		_engine_flare = EngineFlareCls.new()
		_engine_flare.visible = false   # ignites in _ignite() — off during drift/freefall
		# Deferred: we're mid-_ready, the marker is busy setting up children.
		_exhaust_point.add_child.call_deferred(_engine_flare)
	if flame_trail:
		_build_trail_line()


# Replaced the inline Line2D smoke spline with the shared
# MissileSmokeTrail effect (Cobalt 2026-05-21: light-gray copy of the
# player damage-smoke effect, applied to rockets + missiles in place of
# the old trail). The trail lives on the scene root so it survives this
# missile's queue_free.
const MissileSmokeTrailCls = preload("res://scripts/effects/missile_smoke_trail.gd")
var _smoke_trail: Node = null

func _build_trail_line() -> void:
	_smoke_trail = MissileSmokeTrailCls.new()
	get_tree().root.call_deferred("add_child", _smoke_trail)
	# Defer attach_to until the trail's _ready has set up its Line2D.
	# Emit from the exhaust marker when present so smoke leaves the rear.
	var emitter: Node2D = _exhaust_point if _exhaust_point != null else self
	_smoke_trail.call_deferred("attach_to", emitter)


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
			# Roman, 2026-05-29: player seeking missiles get ONE SHOT to
			# lock — store the target and never re-acquire. If the target
			# dies/becomes invalid, fly straight off-screen.
			var fwd: Vector2 = _vel.normalized() if _vel.length_squared() > 0.001 else initial_dir.normalized()
			if fwd == Vector2.ZERO:
				fwd = Vector2(0, 1) if target_group == "player" else Vector2(0, -1)

			# Player seeking missiles (target_group == "enemies" and not dumb_fire)
			# use the one-shot lock logic. All others (enemy missiles and rockets)
			# keep their original behavior.
			var p: Node = null
			if target_group == "enemies" and not dumb_fire:
				# Player seeking missile: one-shot lock behavior
				if not _locked:
					# Looking for initial target acquisition
					p = _find_homing_target_in_cone(fwd)
					if p and is_instance_valid(p):
						_locked = true
						_locked_target = p
				elif _locked_target != null and is_instance_valid(_locked_target):
					# Locked and target still valid: track it
					p = _locked_target
				# else: locked but target is gone → fly straight, p stays null
			else:
				# Enemy missiles and rockets: use original re-acquire logic
				p = _find_homing_target_in_cone(fwd) if not _locked else _find_homing_target()
				if p and is_instance_valid(p):
					_locked = true

			var target_dir: Vector2 = fwd  # default: continue straight
			if p and is_instance_valid(p):
				target_dir = (p.global_position - global_position).normalized()
			var max_speed: float = homing_max_speed * (speed_lock_mult if _locked else 1.0)
			var accel_use: float = homing_accel * (lock_accel_mult if _locked else 1.0)
			_vel = _vel.move_toward(target_dir * max_speed, accel_use * delta)
	global_position += _vel * delta
	# Enemy missiles (target_group == "player") that leave the playfield
	# X band or go far off-screen vertically must be destroyed immediately
	# so they cannot arc back into play. Player missiles are excluded —
	# they chase enemies that may be anywhere on screen.
	# X_MIN / X_MAX sourced from Playfield class (scripts/playfield.gd).
	if target_group == "player" and _ignited:
		var px: float = global_position.x
		var py: float = global_position.y
		if px < 132.0 or px > 348.0 or py > 290.0 or py < -50.0:
			queue_free()
			return
	# Rotate the missile sprite to point along its velocity. Same trick
	# as EnemyBase auto_rotate, but applied here so missiles aren't
	# sliding sideways during their homing arc (Roman, 2026-05-16:
	# "Rockets/Missiles should be rotating as they fly").
	if _vel.length_squared() > 4.0:
		rotation = _vel.angle() + PI * 0.5
	# Thruster frame loop (no-op for single-frame sheets)
	if has_node("Sprite2D"):
		var sprite: Sprite2D = $Sprite2D
		if sprite.hframes > 1:
			_anim_frame_t += delta
			sprite.frame = int(_anim_frame_t * ANIM_FPS) % sprite.hframes
	# Smoke trail handled by MissileSmokeTrail (autonomous in its own
	# _process; nothing to do here per-frame). Engine flare is self-
	# animating (EngineFlare._process), nothing to drive here.
	# Fuse expiry detonates with VFX rather than the silent FREE_ANY_EDGE
	# path — distinguishes "I burned out" from "I flew off-screen".
	if _t >= fuse:
		explode()
		return
	_offscreen_cleanup_check()


# Player seeking missiles can drift BELOW the screen during their
# release phase — they fall backward off the ship, then ignite and
# climb back up to find targets. Without this override the missile
# would be freed by the FREE_ANY_EDGE check the moment it dropped past
# the bottom edge (Cobalt 2026-05-21).
#
# Once ignited, normal offscreen rules apply so spent ordnance still
# cleans up on the far side of the playfield.
func _offscreen_cleanup_check() -> void:
	if _dying:
		return
	if target_group == "enemies" and not dumb_fire and not _ignited:
		# In drift phase. Skip all offscreen checks; let the missile
		# coast below the screen during the 0.5s drop without being
		# freed.
		return
	super._offscreen_cleanup_check()


func _ignite() -> void:
	_ignited = true
	# Reverse the drift velocity to the post-ignite heading so the warhead
	# stops falling backward and committed forward thrust kicks in. Only
	# matters for seeking missiles (the ones that DID drop backward).
	if target_group == "enemies" and not dumb_fire:
		var fwd: Vector2 = initial_dir.normalized()
		if fwd != Vector2.ZERO:
			_vel = fwd * drift_speed
	# Orange rockets get a hot-ignition tint on the sprite. Teal seeking
	# missiles keep their natural colour — the warm modulate would make the
	# teal sprite invisible (Bug 2 fix, 2026-05-26).
	if has_node("Sprite2D") and dumb_fire:
		$Sprite2D.modulate = Color(1.6, 0.55, 0.25, 1.0)
	# Ignite the engine flare — the muzzle-flash plume at the exhaust marker
	# (Roman, 2026-05-29). Gated here so it stays off during drift/freefall.
	if _engine_flare != null:
		_engine_flare.visible = true


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
	# Anti-Ship: track the largest valid in-cone target instead of nearest.
	var best_large: Node = null
	var best_size: float = -INF
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
		if prefer_large:
			# Size metric: max_health (heavy-ship tier proxy). Tie-break on
			# nearest so two equally-tough targets resolve deterministically.
			var sz: float = 0.0
			if "max_health" in n:
				sz = float(n.max_health)
			var sd: float = abs(to_n.x) + abs(to_n.y)
			if sz > best_size or (sz == best_size and sd < best_d):
				best_size = sz
				best_d = sd
				best_large = n
		else:
			var nd: float = abs(to_n.x) + abs(to_n.y)
			if nd < best_d:
				best_d = nd
				best = n
	if prefer_large:
		return best_large
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
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		# Drop the missile reference; the trail's own _process will detect
		# the null emitter and fade out + free itself.
		_smoke_trail.call("attach_to", null)
		_smoke_trail = null
	super._leave()


func explode() -> void:
	if _dying:
		return
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.call("attach_to", null)
		_smoke_trail = null
	# Explosive impact flash + fiery explosion (Roman, 2026-05-17 sprite
	# pass). Color taken from the warhead's flame trail tint (warm
	# orange/yellow) so the flash reads as ignition.
	var ImpactFxCls = load("res://scripts/effects/impact_fx.gd")
	if ImpactFxCls:
		ImpactFxCls.spawn(get_tree().root, global_position, Color(1.0, 0.65, 0.25, 1.0), 1)
	# Fall through to EnemyBase.explode for the standard die-emit + VFX.
	super.explode()
