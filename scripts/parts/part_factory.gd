extends Node

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const BasicWings = preload("res://scripts/parts/basic_wings.gd")
const BasicTail = preload("res://scripts/parts/basic_tail.gd")
const BasicEngine = preload("res://scripts/parts/basic_engine.gd")
const BasicShield = preload("res://scripts/parts/basic_shield.gd")
const BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const SmartBomb = preload("res://scripts/parts/smart_bomb.gd")
const BulletDefault = preload("res://scenes/projectiles/bullet.tscn")

# Builds the default Mk.1 starting loadout from the design doc.
static func default_starting_loadout(loadout) -> void:
	var wing_l = BasicWings.new()
	wing_l.slot_type = Slots.SlotType.WING_LEFT
	loadout.equip(Slots.SlotType.WING_LEFT, wing_l)

	var wing_r = BasicWings.new()
	wing_r.slot_type = Slots.SlotType.WING_RIGHT
	loadout.equip(Slots.SlotType.WING_RIGHT, wing_r)

	loadout.equip(Slots.SlotType.TAIL, BasicTail.new())
	loadout.equip(Slots.SlotType.ENGINE, BasicEngine.new())
	loadout.equip(Slots.SlotType.SHIELD, BasicShield.new())

	var cannon = BasicBlasterCannon.new()
	cannon.bullet_scene = BulletDefault
	loadout.equip(Slots.SlotType.CANNON, cannon)

	# Smart Bomb ships in every starting loadout (genre staple — every
	# shmup has at least one panic bomb). Mk.1 = 3 charges. Outpost
	# refill / upgrade path is a TODO.
	loadout.equip(Slots.SlotType.DEVICE_BAY_1, SmartBomb.new())
