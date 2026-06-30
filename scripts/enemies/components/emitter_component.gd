class_name EmitterComponent
extends EnemyComponent

# Emit a payload scene on a trigger — the unifier (m6 §19.1) that collapses Spawner
# (drone_carrier), CarriedTurrets (cruiser/bulwark), Dropper (minelayer), and
# DropFirecore (zealot) into one parameterized component. "Emit X on trigger Y."
#
#   trigger START  → emit once at spawn         (turrets: attach_to_enemy = true)
#   trigger TIMER  → emit every `cadence` s     (drone spawner, mine drops)
#   trigger DEATH  → emit on death, by `chance` (firecore drop, death scatter)
#
# Keep `payload` a small, explicit set of scenes (turret / mine / firecore / drone) —
# not an arbitrary-anything god-object (the §19 caution). Bullet-ring death release
# (firecore_drone) needs per-projectile direction, so it stays a separate concern.

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const WeaponSfxC = preload("res://scripts/effects/weapon_sfx.gd")

enum Trigger { START, TIMER, DEATH }

@export var payload: PackedScene = null
@export var trigger: Trigger = Trigger.DEATH
@export var count: int = 1
@export var cadence: float = 2.0          # TIMER: seconds between emits
@export var chance: float = 1.0           # probability per emit (0-1)
@export var spread: float = 0.0           # px: random positional scatter around the enemy
@export var attach_to_enemy: bool = false  # true = child of enemy (turrets ride along)
@export var tag: String = ""              # optional identifier (e.g. "firecore" for zealots)
# TIMER extras (Roman 2026-06-17, generalized from the interceptor's bespoke missile-drop):
@export var max_emits: int = 0            # stop after this many TIMER emits per pass (0 = unlimited)
@export var band_only: bool = false       # TIMER only fires while the enemy is in the visible playfield band
@export var sfx: String = ""              # optional WeaponSfx key played on each emit (e.g. "missile")
# Drop vs launch (Roman 2026-06-29): true = the payload is left at rest in the wake (no inherited
# velocity — the existing emitter behavior); false = it LAUNCHES with the enemy's current velocity.
@export var drop: bool = true

var _t: float = 0.0
var _emit_count: int = 0                  # TIMER emits so far this pass (vs max_emits)
var _last_emit_succeeded: bool = false    # track if the last emission fired
var _started: bool = false                # START fires once per instance, not once per recycle


func on_start(enemy) -> void:
	_t = 0.0
	# TIMER budget refreshes each pass — on_start re-runs on every parallax recycle
	# (enemy_core._components_start), so a `drops_per_pass`-style limit resets per pass.
	_emit_count = 0
	# on_start re-runs on every parallax recycle (enemy_core._components_start); a START emit must
	# fire only ONCE per instance, else a turret/drop stacks a fresh payload each cycle. (Audit 2026-06-15.)
	if trigger == Trigger.START and not _started:
		_started = true
		_emit(enemy)


func on_process(enemy, delta: float) -> void:
	if trigger != Trigger.TIMER:
		return
	if max_emits > 0 and _emit_count >= max_emits:
		return
	# band_only: pause the cadence while off-screen (entering from the top / past the bottom) so a fast
	# diver doesn't waste its drops, mirroring the interceptor's `60 < y < sy-80` gate.
	if band_only and not _in_band(enemy):
		return
	_t += delta
	if _t >= cadence:
		_t = 0.0
		if _roll():
			_emit(enemy)
			_emit_count += 1


func _in_band(enemy) -> bool:
	if enemy == null or not (enemy is Node2D):
		return true
	var y: float = (enemy as Node2D).global_position.y
	return y >= Playfield.Y_MIN + 10.0 and y <= Playfield.Y_MAX - 20.0


func on_death(enemy) -> void:
	if trigger == Trigger.DEATH and _roll():
		_last_emit_succeeded = true
		_emit(enemy)
	else:
		_last_emit_succeeded = false


func _roll() -> bool:
	return chance >= 1.0 or randf() < chance


func _emit(enemy) -> void:
	if payload == null:
		return
	var parent: Node = enemy
	if not attach_to_enemy:
		# Parent to the scene root so drops survive the enemy's queue_free (matches the
		# bullets/debris convention). In a SubViewport bench, the bullet_world layer wins so
		# drops land in the preview, not the window corner.
		parent = BulletWorld.resolve(enemy, enemy.get_tree().current_scene)
		if parent == null:
			parent = enemy.get_tree().root
	if parent == null:
		return
	var base_pos: Vector2 = enemy.global_position
	# Launch mode (drop == false) hands the payload the enemy's current velocity so it's thrown along;
	# drop mode leaves it at rest in the wake. Capture now — the enemy may be freed before _insert runs.
	var launch_vel: Vector2 = Vector2.ZERO
	if not drop and "_last_move_vel" in enemy:
		launch_vel = enemy._last_move_vel
	if sfx != "":
		WeaponSfxC.play(enemy.get_tree().root, base_pos, sfx)
	for _i in count:
		var inst = payload.instantiate()
		if inst == null:
			continue
		var pos: Vector2 = base_pos
		if spread > 0.0:
			pos += Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
		# Defer the tree insertion + setup: _emit can run inside a physics callback
		# (DEATH trigger fires during a bullet collision → _on_area_entered → explode →
		# _components_death). Adding an Area2D payload mid-flush trips "Can't change this
		# state while flushing queries" when the new collision shape registers. Running it
		# deferred (idle frame) sidesteps the flush. (Roman 2026-06-15.)
		_insert.call_deferred(inst, parent, pos, attach_to_enemy, launch_vel)


func _insert(inst, parent: Node, pos: Vector2, attach: bool, launch_vel: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(parent):
		# Enemy/scene torn down before the deferred call ran — drop the orphan.
		if inst is Node:
			(inst as Node).queue_free()
		return
	parent.add_child(inst)
	if attach:
		# Rides on the enemy (turrets); the payload scene positions itself.
		if inst is Node2D:
			(inst as Node2D).position = Vector2.ZERO
	elif inst.has_method("start"):
		inst.start(pos)              # spawn entry for enemies/hazards (mine.start etc.)
		if launch_vel != Vector2.ZERO:
			_impart_velocity(inst, launch_vel)
	elif inst is Node2D:
		(inst as Node2D).global_position = pos
		if launch_vel != Vector2.ZERO:
			_impart_velocity(inst, launch_vel)


# Add the enemy's velocity to the freshly-emitted payload (launch mode). Best-effort across the
# payload kinds we drop: missiles/rockets use `_vel`, bomblets `_velocity`, plain bullets `velocity`.
# Enemies move via their own `movement` resource and expose none of these — they're left unchanged.
func _impart_velocity(inst, v: Vector2) -> void:
	for f in ["_vel", "_velocity", "velocity"]:
		if f in inst:
			inst.set(f, inst.get(f) + v)
			return
