extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Side Pods — secondary weapon. Hold shoot2 (C) to fire. Spawns a
# symmetric pair (or more, at higher Mk) of straight-forward bullets
# offset from the centerline. Raiden-style pod weapon: cheap, reliable
# damage that supplements whatever primary you have.
#
# Mk scaling adds pods (Mk.1=2 → +1 per Mk → Mk.7+ capped at 8).
# Cooldown stays constant; damage per pod stays modest so it doesn't
# eclipse the primary cannon.

@export var bullet_scene: PackedScene
@export var base_damage: int = 1
@export var dmg_per_mark: int = 1
@export var base_cooldown: float = 0.18
@export var base_pods: int = 2
@export var pods_per_mark: int = 1
@export var max_pods: int = 8
@export var halfspan: float = 12.0  # px from center to outermost pod

var _prev_bullet_scene: PackedScene = null
var _prev_cooldown: float = 0.0
var _prev_damage: int = 0
var _prev_homing: bool = false
var _prev_pod_count: int = 1
var _prev_pod_halfspan: float = 10.0


func _init() -> void:
	slot_type = Slots.SlotType.HARDPOINT_WING
	display_name = "Side Pods"
	description = "Wing-mounted forward pods. Mk adds more pods, wider spread."


func apply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	_prev_bullet_scene = ship.secondary_bullet_scene
	_prev_cooldown = ship.secondary_cooldown
	_prev_damage = ship.secondary_damage
	_prev_homing = ship.secondary_homing
	if "secondary_pod_count" in ship:
		_prev_pod_count = ship.secondary_pod_count
	if "secondary_pod_halfspan" in ship:
		_prev_pod_halfspan = ship.secondary_pod_halfspan
	if bullet_scene != null:
		ship.secondary_bullet_scene = bullet_scene
	ship.secondary_cooldown = base_cooldown
	ship.secondary_damage = base_damage + (int(mark) - 1) * dmg_per_mark
	ship.secondary_homing = false
	if "secondary_pod_count" in ship:
		ship.secondary_pod_count = mini(
			base_pods + (int(mark) - 1) * pods_per_mark,
			max_pods,
		)
	if "secondary_pod_halfspan" in ship:
		ship.secondary_pod_halfspan = halfspan


func unapply(ship) -> void:
	if not ("secondary_bullet_scene" in ship):
		return
	ship.secondary_bullet_scene = _prev_bullet_scene
	ship.secondary_cooldown = _prev_cooldown
	ship.secondary_damage = _prev_damage
	ship.secondary_homing = _prev_homing
	if "secondary_pod_count" in ship:
		ship.secondary_pod_count = _prev_pod_count
	if "secondary_pod_halfspan" in ship:
		ship.secondary_pod_halfspan = _prev_pod_halfspan


# Editor DPS readout — total damage per cooldown × fire rate.
func effective_damage(at_mark: int) -> int:
	var per_pod: int = base_damage + (at_mark - 1) * dmg_per_mark
	var n_pods: int = mini(base_pods + (at_mark - 1) * pods_per_mark, max_pods)
	return per_pod * n_pods
