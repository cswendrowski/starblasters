extends Node

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

var _parts = {}

func _ready():
	for s in Slots.ALL_SLOTS:
		_parts[s] = null
