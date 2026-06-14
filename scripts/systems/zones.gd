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


# Normalized progress through the engagement band: 0.0 at the entry edge (top),
# 1.0 at the departure edge (bottom), clamped. Path-phase firing (enemy_core
# fire_path_phases) fires when this crosses configured fractions, so a descending
# enemy shoots at fixed points in its pass instead of on a random timer.
static func band_progress(y: float) -> float:
	return clampf((y - ENTRY_END) / (DEPARTURE_START - ENTRY_END), 0.0, 1.0)
