extends Resource

# Base class for every equippable ship part.
# Subclasses override apply()/unapply() to mutate the ship.

@export var display_name: String = "Unnamed Part"
@export var description: String = ""
@export var slot_type: int = -1  # SlotTypes.SlotType
@export_range(1, 9) var mark: int = 1

# Mk.1 = 1x, Mk.2 = 2x, ... Mk.9 = 9x (per design doc).
func mark_multiplier() -> float:
	return float(mark)

func apply(_ship) -> void:
	pass

func unapply(_ship) -> void:
	pass

func get_display() -> String:
	return "Mk.%d %s" % [mark, display_name]
