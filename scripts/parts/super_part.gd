extends "res://scripts/parts/part.gd"

# SuperPart — base for DEVICE_BAY_1 super weapons (Smart Bomb, Hyper Mode,
# Phase Shift, Drone Swarm). Standardizes the super_part / charges plumbing
# so subclasses focus on activate(ship).

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var base_charges: int = 1
@export var charges_per_mark: int = 1

# Snapshot so unequip restores any prior super_part / charges values.
var _prev_super_part = null
var _prev_max_charges: int = 0
var _prev_charges: int = 0
var _had_prev: bool = false


func _init() -> void:
	slot_type = Slots.SlotType.DEVICE_BAY_1


func _charges_at_mark(at_mark: int) -> int:
	return base_charges + (at_mark - 1) * charges_per_mark


func apply(ship) -> void:
	if not ("super_part" in ship):
		return
	_prev_super_part = ship.super_part
	_prev_max_charges = int(ship.max_super_charges) if "max_super_charges" in ship else 0
	_prev_charges = int(ship.super_charges) if "super_charges" in ship else 0
	_had_prev = true
	ship.super_part = self
	ship.max_super_charges = _charges_at_mark(int(mark))
	ship.super_charges = ship.max_super_charges
	if ship.has_signal("super_charges_changed"):
		ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)


func unapply(ship) -> void:
	if not ("super_part" in ship):
		return
	# Only relinquish the slot if we're still the active super_part.
	if ship.super_part != self:
		return
	if _had_prev:
		ship.super_part = _prev_super_part
		ship.max_super_charges = _prev_max_charges
		ship.super_charges = _prev_charges
	else:
		ship.super_part = null
		ship.super_charges = 0
		ship.max_super_charges = 0
	if ship.has_signal("super_charges_changed"):
		ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)
	_had_prev = false


# Subclasses override.
func activate(_ship) -> void:
	pass


# Shared activation-VFX helpers — every super currently re-implements the
# ExplosionFx + Camera2D.add_trauma chain. Hoist here.
func _camera_trauma(ship, amount: float) -> void:
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	var main: Node = tree.get_current_scene()
	if main and main.has_node("Camera2D"):
		var cam = main.get_node("Camera2D")
		if cam.has_method("add_trauma"):
			cam.add_trauma(amount)


func _flash_at(ship, scale: float) -> void:
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx:
		ExplosionFx.play(ship.global_position, scale, true)


func _burst_at(ship, n: int, radius: float, stagger: float) -> void:
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx:
		ExplosionFx.burst(ship.global_position, n, radius, stagger)
