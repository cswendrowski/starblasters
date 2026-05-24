extends Node

const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const BasicWings = preload("res://scripts/parts/basic_wings.gd")
const BasicTail = preload("res://scripts/parts/basic_tail.gd")
const BasicEngine = preload("res://scripts/parts/basic_engine.gd")
const BasicShield = preload("res://scripts/parts/basic_shield.gd")
const BasicBlasterCannon = preload("res://scripts/parts/basic_blaster_cannon.gd")
const SmartBomb = preload("res://scripts/parts/smart_bomb.gd")
const BulletDefault = preload("res://scenes/projectiles/bullet.tscn")

# Weapon Editor parity — if a designer saves resources/weapons/<name>.tres
# with tweaked values, we load that instance instead of the hardcoded
# defaults. Editor edits land in-game with no rebuild.
const ENERGY_BLASTER_TRES := "res://resources/weapons/energy_blaster.tres"
const SMART_BOMB_TRES := "res://resources/weapons/smart_bomb.tres"


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

	var cannon = _load_or_default(ENERGY_BLASTER_TRES, BasicBlasterCannon)
	if "bullet_scene" in cannon and cannon.bullet_scene == null:
		cannon.bullet_scene = BulletDefault
	loadout.equip(Slots.SlotType.CANNON, cannon)

	# Smart Bomb ships in every starting loadout (genre staple — every
	# shmup has at least one panic bomb). Mk.1 = 3 charges.
	loadout.equip(Slots.SlotType.DEVICE_BAY_1, _load_or_default(SMART_BOMB_TRES, SmartBomb))


# Helper: load a .tres if it exists on disk (Weapon Editor authored it),
# else fall back to a fresh instance of the script. Each call returns a
# unique instance — for .tres, duplicate() so subsequent equips don't
# mutate the cached resource.
static func _load_or_default(tres_path: String, fallback_script: Script):
	var part = null
	if ResourceLoader.exists(tres_path):
		var res = load(tres_path)
		if res != null:
			part = res.duplicate()
	if part == null:
		part = fallback_script.new()
	# Godot doesn't run _init() on Resources loaded from .tres; the .tres
	# files don't persist display_name / description / slot_type. Restore
	# from a fresh script-default. Same fix as PartCatalog._build_weapon.
	# slot_type=-1 is critical: without this, Run.equip_part routes the
	# part to slot -1, so the player can't fire it.
	if fallback_script != null:
		var defaults = fallback_script.new()
		if "display_name" in part and (part.display_name == "" or part.display_name == "Unnamed Part"):
			part.display_name = defaults.display_name
			if "description" in part and "description" in defaults:
				part.description = defaults.description
		if "slot_type" in part and int(part.slot_type) < 0 and "slot_type" in defaults:
			part.slot_type = defaults.slot_type
	return part
