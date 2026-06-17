extends "res://scripts/enemies/enemy_core.gd"

# Firecore Cruiser "Helix" (M6c rework, Roman 2026-06-07; turret swap 2026-06-16).
#
# A slow zealot capital. Movement comes from the roster slot (cross / lane-advance
# / hold / shift / drift) but is clamped to ~1 px/frame (60 px/s) here so the hull
# always reads as a ponderous capital regardless of which movement it rolled. It
# carries a zealot GUN TURRET on its `Turret` marker (the shared zealot_turret port
# of the supremacy dome turret), two glowing cores (authored in the scene,
# hand-tunable), and drops firecores on destruction (baked DropFirecore component,
# count 2). Only the turret mount is bespoke here; locomotion is a movement pattern.
#
# The bespoke center HOOK-TURRET beam was retired 2026-06-16 in favor of the
# marker-mounted zealot gun turret (Roman) — the scene gained a `Turret` marker for it.

# ~1 px/frame ceiling on the rolled movement (Roman: "moving at 1p/f").
const SPEED_CAP := 60.0


func _ready() -> void:
	max_health = 32
	bounty_value = 100
	display_scale = 1.0
	super._ready()
	# Gun turret is now a roster `mounts` turret (EnemyRoster.HELIX_MOUNTS), realized by MountBuilder
	# in enemy_base._ready — was ZealotTurret.mount_all here (migrated to data 2026-06-16).


func start(pos: Vector2) -> void:
	super.start(pos)   # enemy_core dups movement -> _pattern + applies sector scale
	_clamp_pattern_speed()


# Hold the capital to ~1 px/frame on every speed-like field of whatever movement
# it rolled, so cross/advance/hold/shift/drift all read as a slow capital.
func _clamp_pattern_speed() -> void:
	if _pattern == null:
		return
	for prop in _pattern.get_property_list():
		if int(prop.get("type", -1)) != TYPE_FLOAT:
			continue
		var n: String = str(prop.get("name", ""))
		if n == "speed" or n == "down_speed" or n.ends_with("_speed"):
			if float(_pattern.get(n)) > SPEED_CAP:
				_pattern.set(n, SPEED_CAP)
