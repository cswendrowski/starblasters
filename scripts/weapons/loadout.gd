extends Node

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

signal slot_changed
signal loadout_applied

var _parts = {}

func _ready():
	for s in Slots.ALL_SLOTS:
		if not _parts.has(s):
			_parts[s] = null

func get_part(slot):
	return _parts.get(slot, null)

func has_part(slot):
	return _parts.get(slot, null) != null

func equip(slot, part):
	if part == null:
		return unequip(slot)
	if part.slot_type != slot:
		push_warning("Part rejects slot")
		return false
	var ship = _ship()
	if _parts.get(slot) != null and ship:
		_parts[slot].unapply(ship)
	_parts[slot] = part
	if ship:
		part.apply(ship)
	slot_changed.emit(slot, part)
	return true

func unequip(slot):
	var ship = _ship()
	if _parts.get(slot) != null and ship:
		_parts[slot].unapply(ship)
	_parts[slot] = null
	slot_changed.emit(slot, null)
	return true

func apply_all(ship):
	for s in Slots.ALL_SLOTS:
		var p = _parts.get(s, null)
		if p != null:
			p.apply(ship)
	loadout_applied.emit(ship)

func _ship():
	return get_parent()
