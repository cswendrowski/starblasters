extends "res://scripts/parts/bullet_secondary.gd"

# Side Pods — secondary weapon. Hold shoot2 (C) to fire. Spawns a
# symmetric pair (or more, at higher Mk) of straight-forward bullets
# offset from the centerline. Raiden-style pod weapon: cheap, reliable
# damage that supplements whatever primary you have.
#
# Mk scaling adds pods (Mk.1=2 → +1 per Mk → Mk.7+ capped at 8).

@export var base_pods: int = 2
@export var pods_per_mark: int = 1
@export var max_pods: int = 8
@export var halfspan: float = 12.0


func _init() -> void:
	super._init()
	display_name = "Side Pods"
	description = "Wing-mounted forward pods. Mk adds more pods, wider spread."
	base_damage = 1
	dmg_per_mark = 1
	base_cooldown = 0.18


func _base_ammo() -> int:
	return -1  # unmetered


func _homing() -> bool:
	return false


func _snapshot_keys() -> Array:
	var keys: Array = super._snapshot_keys()
	keys.append("secondary_pod_halfspan")
	return keys


func _mk_knobs() -> Dictionary:
	return {
		"secondary_damage": [base_damage, base_damage + dmg_per_mark * 8],
		"secondary_cooldown": [base_cooldown, base_cooldown],
		"secondary_pod_count": Callable(self, "_pods_for_mark"),
		"secondary_pod_halfspan": [halfspan, halfspan],
	}


# Pod count is Mk-knob-driven; skip the base BulletSecondary writing
# pod_count=1 over the top of it. Same _apply_visuals as parent minus
# the secondary_pod_count assignment.
func _apply_visuals(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	if bullet_scene != null:
		ship.secondary_bullet_scene = bullet_scene
	if "secondary_mode" in ship:
		ship.secondary_mode = _secondary_mode()
	if "secondary_homing" in ship:
		ship.secondary_homing = _homing()
	# Skip secondary_pod_count — _mk_knobs handles it.
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)


func _pods_for_mark(at_mark: int) -> int:
	return mini(base_pods + (at_mark - 1) * pods_per_mark, max_pods)


# Editor DPS readout — per-pod × pod count.
func effective_damage(at_mark: int) -> int:
	var per_pod: int = base_damage + (at_mark - 1) * dmg_per_mark
	return per_pod * _pods_for_mark(at_mark)
