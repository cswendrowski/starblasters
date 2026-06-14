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
	SHIFT_MODE,
	# Passive Module bay (2026-06-13). NOTE: modules are stored in a list
	# (Run.modules, up to MODULE_BAY_SIZE), NOT the one-part-per-slot pegboard —
	# so MODULE is deliberately ABSENT from ALL_SLOTS below. This enum value is
	# only a TAG so the catalog/shop can recognize + roll module Parts.
	MODULE,
}

# The pegboard slots (one part each). MODULE is excluded on purpose — modules ride
# the Run.modules list + the apply loop, not this single-slot machinery.
const ALL_SLOTS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

static func slot_name(slot):
	match slot:
		0: return "Wing (Left)"
		1: return "Wing (Right)"
		2: return "Tail"
		3: return "Engine"
		4: return "Blaster"
		5: return "Wing Hardpoint"
		6: return "Wingtip Hardpoint"
		7: return "Device Bay 1"
		8: return "Device Bay 2"
		9: return "Shield"
		10: return "Shift Mode"
		11: return "Module"
		_: return "Unknown"
