extends Resource

# Base class for every equippable ship part.
# Subclasses override apply()/unapply() to mutate the ship.

@export var display_name: String = "Unnamed Part"
@export var description: String = ""
@export var slot_type: int = -1  # SlotTypes.SlotType
@export_range(1, 9) var mark: int = 1
# Highest Mk this part can reach. Default 9; parts that cap earlier (e.g.
# engines top out at Mk.6 = 8 px/f move speed) override this. Upgrade offers
# and mark rolls respect it so the shop/events never push a part past its cap.
@export_range(1, 9) var max_mark: int = 9

# Mk.1 = 1x, Mk.2 = 2x, ... Mk.9 = 9x (per design doc).
func mark_multiplier() -> float:
	return float(mark)

func apply(_ship) -> void:
	pass

func unapply(_ship) -> void:
	pass

func get_display() -> String:
	return "Mk.%d %s" % [mark, display_name]


# Default damage formula used by every standard cannon: base + (mark-1) * per_mark.
# Override in subclasses with non-linear scaling (wave_gun_cannon).
# Returns -1 for non-weapon parts (engines/shields/wings) so the weapon
# editor can detect "not a weapon" and skip the field.
func effective_damage(at_mark: int) -> int:
	if not ("base_damage" in self):
		return -1
	var per_mark: int = 0
	if "dmg_per_mark" in self:
		per_mark = int(self.get("dmg_per_mark"))
	return int(self.get("base_damage")) + (at_mark - 1) * per_mark


# Human-readable COMPUTED bonus at a given Mk for the outpost/codex card (e.g. "+45% ammo").
# Empty by default; passive modules override it. The card falls back to `description` when
# this returns "".
func bonus_description(_mk: int) -> String:
	return ""
