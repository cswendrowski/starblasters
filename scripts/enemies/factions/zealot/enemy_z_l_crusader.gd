extends "res://scripts/enemies/factions/zealot/enemy_firecore_cruiser.gd"

# Crusader — large zealot capital, a heavier sibling of the Helix. Reuses the firecore-cruiser
# body wholesale (the ~1 px/frame capital speed clamp + the baked firecore drop), and gets its
# armament from data: four Helix gun turrets on "Turret*" + two hull muzzles firing zealot bolts
# on "Muzzle*" (EnemyRoster.CRUSADER_MOUNTS, realized by MountBuilder in enemy_base._ready).
# Only its hull/bounty differ from the base — bumped for its size via the overridable defaults.


func _default_hull() -> int:
	return 60

func _default_bounty() -> int:
	return 180
