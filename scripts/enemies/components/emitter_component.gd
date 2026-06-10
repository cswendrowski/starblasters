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

enum Trigger { START, TIMER, DEATH }

@export var payload: PackedScene = null
@export var trigger: Trigger = Trigger.DEATH
@export var count: int = 1
@export var cadence: float = 2.0          # TIMER: seconds between emits
@export var chance: float = 1.0           # probability per emit (0-1)
@export var spread: float = 0.0           # px: random positional scatter around the enemy
@export var attach_to_enemy: bool = false  # true = child of enemy (turrets ride along)
@export var tag: String = ""              # optional identifier (e.g. "firecore" for zealots)

var _t: float = 0.0
var _last_emit_succeeded: bool = false    # track if the last emission fired


func on_start(enemy) -> void:
	_t = 0.0
	if trigger == Trigger.START:
		_emit(enemy)


func on_process(enemy, delta: float) -> void:
	if trigger != Trigger.TIMER:
		return
	_t += delta
	if _t >= cadence:
		_t = 0.0
		if _roll():
			_emit(enemy)


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
		# bullets/debris convention).
		parent = enemy.get_tree().current_scene
		if parent == null:
			parent = enemy.get_tree().root
	for _i in count:
		var inst = payload.instantiate()
		if inst == null:
			continue
		var pos: Vector2 = enemy.global_position
		if spread > 0.0:
			pos += Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
		parent.add_child(inst)
		if attach_to_enemy:
			# Rides on the enemy (turrets); the payload scene positions itself.
			if inst is Node2D:
				(inst as Node2D).position = Vector2.ZERO
		elif inst.has_method("start"):
			inst.start(pos)              # spawn entry for enemies/hazards (mine.start etc.)
		elif inst is Node2D:
			(inst as Node2D).global_position = pos
