extends "res://scripts/enemies/enemy_base.gd"

# Bomblet — small munition released by Cluster / Smart Cluster mines.
# Behavior:
#   - Drifts in a randomized direction (cluster) or homes toward the player
#     when within homing_range (smart).
#   - Damages the player on contact like an enemy bullet, then self-destructs.
#   - Has 1 HP — can be shot down in a single hit.
#   - Off-screen despawn at the bottom of the playfield.
#
# Inherits the standard hit / find_player / died-signal pipeline from
# EnemyBase. Overrides `explode()` so the bomblet detonation uses its
# softer-than-mine VFX + audio.

@export var damage_on_collide: int = 1
# 320×400 res rework — speeds + radii halved.
@export var descent_speed: float = 180.0
# Continuous lateral wiggle. 0 = straight descent (Roman 2026-06-11: bomblets should
# come in dense walls, not wiggling descents — the wiggle was a cluster-mine carryover).
# The one-shot scatter on cluster RELEASE still happens via launch(); this only kills
# the ongoing side-to-side weave.
@export var lateral_jitter_speed: float = 0.0
@export var jitter_cadence: float = 0.18
@export var lifetime: float = 8.0
const BOMBLET_AVOID_RADIUS := 14.0
const BOMBLET_AVOID_STRENGTH := 140.0
const BOMBLET_NEIGHBOUR_CAP := 4
const BOMBLET_GROUP := "bomblets"
const ProximityChase = preload("res://scripts/enemies/patterns/proximity_chase.gd")
const GlowFx = preload("res://scripts/effects/glow_fx.gd")
const HELD_GLOW_COLOR := Color(0.78, 0.231, 1.0)   # #c73bff — matches the Gravity Mine glowmask

@export var smart: bool = false
@export var homing_accel: float = 360.0
@export var homing_max_speed: float = 180.0
# Smart bomblets pursue when the player crosses inside this range. On-lane migration
# 2026-06-08: the SMART path now drives the shared ProximityChase pattern — dormant it drifts
# straight_medium (per Roman: "straight_medium otherwise"), then engages + chases on proximity.
# The munition layer (neighbour repulsion, lifetime, pulse, launch kick, edge bounce) stays
# bespoke here — it's flocking/projectile behavior the movement-pattern model doesn't cover.
@export var smart_engage_range: float = 100.0
var _smart_engaged: bool = false
var _chase = null   # ProximityChase instance for the smart path

var _velocity: Vector2 = Vector2.ZERO
var _lateral_target: float = 0.0
var _jitter_timer: float = 0.0
var _age: float = 0.0
var _pulse_phase: float = 0.0
# Orbiting mode (Gravity Mine): the parent mine drives this bomblet's position while it rings the
# mine; its own drift/lifetime are suspended until release(velocity) hands it a free velocity.
var _orbiting: bool = false
var _held_glow = null   # #c73bff diffuse glow while held by the Gravity Mine; cleared on release

# Death-boom audio throttle (Roman 2026-06-27: "bomblets have no explosion sound when they die").
# Bomblets release in swarms (4-8 from a Gravity Mine) that often die together, so an un-throttled
# per-bomblet SFX stacks into a wall of close booms. A shared (static) min-gap means a simultaneous
# swarm pops ONCE while bomblets picked off one-by-one each get their own boom.
static var _last_boom_ms: int = 0
const BOOM_THROTTLE_MS := 70
const BOOM_SCALE := 0.7   # smaller munition → a softer boom than a full enemy/mine


func _ready() -> void:
	max_health = 1
	is_hazard = true
	bounty_value = 0
	# Roman, 2026-05-17: bomblet size is now a single source of truth.
	# Previously mine_cluster.gd overwrote scale to (3,3) AFTER spawn while
	# the minelayer relied on bomblet's own default — leaving cluster
	# bomblets at 3.0× and minelayer bomblets at a different size. Lock
	# it here at 3.0× and require callers NOT to override.
	display_scale = 1.0
	scale = Vector2(display_scale, display_scale)
	# Bomblets don't have a "forward" — they tumble. Skip auto-rotation
	# and the engine flame; they're not ships.
	auto_rotate = false
	has_ship_vfx = false  # no ground shadow / damage-overlay — bomblets explode, not fray
	wants_outline = false  # mine munitions are projectile-class, excepted
	# Bomblets don't parallax-cycle; they cap at the bottom edge and
	# despawn cleanly. NONE keeps EnemyBase's per-frame check out of the
	# way — this script does its own edge handling for bounce + despawn.
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	_pulse_phase = randf() * TAU
	_velocity = Vector2(randf_range(-32.0, 32.0), descent_speed)
	_lateral_target = randf_range(-lateral_jitter_speed, lateral_jitter_speed)
	add_to_group(BOMBLET_GROUP)
	if smart:
		# Shared proximity-chase: drift straight_medium → engage → relentless chase.
		_chase = ProximityChase.new()
		_chase.proximity = smart_engage_range
		_chase.on_start(self)


func start(pos: Vector2) -> void:
	position = pos


# Used by the parent mine to seed initial position with a directional kick.
func launch(pos: Vector2, dir: Vector2, speed: float) -> void:
	position = pos
	var nudge: Vector2 = dir.normalized() * speed * 0.35
	_velocity = Vector2(nudge.x, descent_speed + nudge.y * 0.5)
	_lateral_target = nudge.x


# Gravity Mine: keep this bomblet inert (parent positions it on the orbit ring) + carry the
# #c73bff held-glow while ringed.
func set_orbiting(on: bool) -> void:
	_orbiting = on
	if on:
		_attach_held_glow()
	else:
		_clear_held_glow()


# Gravity Mine: free the bomblet on the mine's death with a directly-set velocity (the mine's
# drift + the bomblet's tangential orbit velocity), so it inherits its motion + rotation. The
# held-glow is disabled on release.
func release(velocity: Vector2) -> void:
	_orbiting = false
	_age = 0.0
	_velocity = velocity
	_lateral_target = velocity.x
	_clear_held_glow()


func _attach_held_glow() -> void:
	if _held_glow != null and is_instance_valid(_held_glow):
		return
	if has_node("Sprite2D"):
		_held_glow = GlowFx.attach_glow($Sprite2D, HELD_GLOW_COLOR, 0.9, 0.7)


func _clear_held_glow() -> void:
	if _held_glow != null and is_instance_valid(_held_glow):
		_held_glow.queue_free()
	_held_glow = null


func _process(delta: float) -> void:
	if _dying:
		return
	if _orbiting:
		# Parent mine owns position; just keep the live-munition pulse going.
		_pulse_vfx()
		return
	_age += delta
	if _age >= lifetime:
		explode()
		return
	_pulse_vfx()
	if smart and _chase != null:
		# Shared ProximityChase drives drift→engage→chase (incl. its own edge bounce).
		position += _chase.compute_step(self, delta)
		position += _neighbour_push() * delta   # flocking as a positional shove
		_smart_engaged = _chase.is_armed()
	else:
		_jitter_timer -= delta
		if _jitter_timer <= 0.0:
			_jitter_timer = jitter_cadence * randf_range(0.6, 1.6)
			_lateral_target = randf_range(-lateral_jitter_speed, lateral_jitter_speed)
		_velocity.x = lerp(_velocity.x, _lateral_target, clamp(delta * 5.0, 0.0, 1.0))
		_velocity.y = lerp(_velocity.y, descent_speed, clamp(delta * 2.5, 0.0, 1.0))
		_velocity += _neighbour_push() * delta
		position += _velocity * delta
		# Bounce off the playfield band edges (not the 480-px viewport).
		var margin: float = 4.0
		if position.x < Playfield.X_MIN + margin and _velocity.x < 0.0:
			position.x = Playfield.X_MIN + margin
			_velocity.x = -_velocity.x * 0.85
		elif position.x > Playfield.X_MAX - margin and _velocity.x > 0.0:
			position.x = Playfield.X_MAX - margin
			_velocity.x = -_velocity.x * 0.85
	# Despawn off top/bottom — silent leaver.
	if position.y > screensize.y + 24.0 or position.y < -24.0:
		queue_free()


func _pulse_vfx() -> void:
	# Pulse red so it reads as "live munition".
	if has_node("Sprite2D"):
		var t: float = Time.get_ticks_msec() / 1000.0
		var pulse: float = 0.5 + 0.5 * sin(t * 6.0 + _pulse_phase)
		var k: float = 1.0 + 0.9 * pulse
		$Sprite2D.modulate = Color(k, 0.6, 0.55, 1.0)


# Bomblets explode softer than the parent mine — quieter, throttled audio + a smaller
# burn — so a salvo of 6 dying together doesn't drown the soundscape.
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	_clear_held_glow()   # if shot while orbiting a Gravity Mine, drop the #c73bff glow instantly
	# Single circle explosion (Roman 2026-06-11) — a clean one-circle pop. Now WITH a boom
	# (Roman 2026-06-27), but globally throttled (see BOOM_THROTTLE_MS): a simultaneous swarm
	# pops once, while bomblets shot down one-by-one each sound.
	var now: int = Time.get_ticks_msec()
	var with_sound: bool = (now - _last_boom_ms) >= BOOM_THROTTLE_MS
	if with_sound:
		_last_boom_ms = now
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.play(global_position, BOOM_SCALE, true, null, ExplosionFx.scene_for("small_circle"), with_sound)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/effects/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.25)
	await get_tree().create_timer(0.25).timeout
	queue_free()


# One-shot kill — bullet contact is fatal regardless of "non-fatal" path.
func hit() -> void:
	explode()


# Boid-style spacing force from nearby bomblets (pure vector; callers integrate it).
func _neighbour_push() -> Vector2:
	if _dying:
		return Vector2.ZERO
	var checked: int = 0
	var push: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group(BOMBLET_GROUP):
		if other == self or not is_instance_valid(other):
			continue
		var to_self: Vector2 = global_position - other.global_position
		var d: float = to_self.length()
		if d > 0.001 and d < BOMBLET_AVOID_RADIUS:
			var falloff: float = 1.0 - (d / BOMBLET_AVOID_RADIUS)
			push += to_self.normalized() * (BOMBLET_AVOID_STRENGTH * falloff)
		checked += 1
		if checked >= BOMBLET_NEIGHBOUR_CAP:
			break
	return push


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()
