extends RefCounted

enum SlotType {
	WING_LEFT,
	WING_RIGHT,
	TAIL,
	ENGINE,
	CANNON,
	HARDPOINT_WING,
	HARDPOINT_WINGTIP,
	DEVICE_BAY_1,
	DEVICE_BAY_2,
	SHIELD,
}

const ALL_SLOTS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

static func slot_name(slot):
	match slot:
		0: return "Wing (Left)"
		1: return "Wing (Right)"
		2: return "Tail"
		3: return "Engine"
		4: return "Cannon"
		5: return "Wing Hardpoint"
		6: return "Wingtip Hardpoint"
		7: return "Device Bay 1"
		8: return "Device Bay 2"
		9: return "Shield"
		_: return "Unknown"
