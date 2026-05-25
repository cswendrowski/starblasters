extends RefCounted
class_name PartTier

# Mk → Tier label + color. Used by outpost cards and the sector map's
# Manage Ship modal so the player can see at a glance how rare a part
# is without doing Mk math.
#
#   Tier I  — Basic     (Mk 1-2, white)
#   Tier II — Tuned     (Mk 3-4, green)
#   Tier III— Refined   (Mk 5-6, blue)
#   Tier IV — Improved  (Mk 7-8, purple)
#   Tier V  — Perfected (Mk 9,   orange)  ← chase item

static func tier_for_mk(mk: int) -> Dictionary:
	if mk <= 2:
		return {"name": "Basic",     "tier": "I",   "color": Color(1.0, 1.0, 1.0)}
	elif mk <= 4:
		return {"name": "Tuned",     "tier": "II",  "color": Color(0.4, 1.0, 0.5)}
	elif mk <= 6:
		return {"name": "Refined",   "tier": "III", "color": Color(0.4, 0.7, 1.0)}
	elif mk <= 8:
		return {"name": "Improved",  "tier": "IV",  "color": Color(0.8, 0.4, 1.0)}
	else:
		return {"name": "Perfected", "tier": "V",   "color": Color(1.0, 0.6, 0.0)}


# "Tier III — Refined" style label, no Mk number (Mk shown elsewhere on
# the card so we don't duplicate it).
static func tier_label(mk: int) -> String:
	var t: Dictionary = tier_for_mk(mk)
	return "Tier %s - %s" % [t["tier"], t["name"]]
