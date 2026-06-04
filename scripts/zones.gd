class_name Zones
extends Object

# Combat Y-bands for firing readability (bridge §1.8-1.9). Y grows downward in the
# 270-tall playfield. Enemies hold fire in the ENTRY band (just spawned, near the
# top), fire in the ENGAGEMENT band, and cease fire in the DEPARTURE band (low /
# committed to leaving) — which keeps them from plinking the player at point-blank.
# Pure static geometry; pairs with the bottom safe-zone in lane_system_spec §1.9.

const ENTRY_END: float = 40.0          # at/above this Y = entry band (hold fire)
const DEPARTURE_START: float = 195.0   # at/below this Y = departure band (cease fire)


static func in_engagement(y: float) -> bool:
	return y >= ENTRY_END and y < DEPARTURE_START
