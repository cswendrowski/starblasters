extends SceneTree

# Scene-light SSOT guard (docs/scene_light_direction_2026-07-28.md).
#   L1 — every value SceneLight produces still equals the literal it replaced (these must NEVER move).
#   L2 — the consumers that deliberately re-lit now land on canonical, and no file kept a private sun.

# Files converted in L2, with the literal each one is forbidden to reintroduce.
const NO_PRIVATE_SUNS := {
	"res://scripts/parallax/layer_planet.gd": "Vector2(0.0, 0.5)",
	"res://scripts/screens/sector_map_v3.gd": "Vector2(0.0, 0.5)",
	"res://scripts/dev/sector_map_v3.gd": "Vector2(0.0, 0.5)",
	"res://scripts/parallax/asteroid_shadow_rig.gd": "Vector2(0.35, 0.9)",
	"res://scripts/parallax/flyover_backdrop.gd": "Vector2(0.40, 0.35)",
}


func _init() -> void:
	var fails := 0

	# 1. BuildingShadow: was const sun_dir = Vector2(0.7071, 0.7071) (the SHADOW direction).
	fails += _eq("building_shadow sun_dir", SceneLight.shadow_dir(), Vector2(0.7071, 0.7071))

	# 2. Stronghold + loose rocks: was the PixelPlanets shader default vec2(0.39, 0.39).
	fails += _eq("planetkit kit default",
		SceneLight.planetkit_light_origin(SceneLight.RADIUS_PLANETKIT_DEFAULT), Vector2(0.39, 0.39))

	# 3. Baked rocks: was 0.5 + 0.45 * (cos(225deg), sin(225deg)).
	var a := deg_to_rad(225.0)
	fails += _eq("baked rock light_origin",
		Vector2(0.5, 0.5) + Vector2(cos(deg_to_rad(SceneLight.DEFAULT_AZIMUTH_DEG)),
			sin(deg_to_rad(SceneLight.DEFAULT_AZIMUTH_DEG))) * SceneLight.RADIUS_BAKED_ROCK,
		Vector2(0.5 + 0.45 * cos(a), 0.5 + 0.45 * sin(a)))

	# 4. light_dir/shadow_dir must be exact opposites, both unit length.
	fails += _eq("shadow = -light", SceneLight.shadow_dir(), -SceneLight.light_dir())
	if absf(SceneLight.light_dir().length() - 1.0) > 0.0001:
		print("FAIL light_dir not unit length"); fails += 1

	# 5. The per-level override plumbing round-trips and resets to canonical.
	SceneLight.set_level_azimuth_deg(90.0)
	if not is_equal_approx(SceneLight.azimuth_deg(), 90.0):
		print("FAIL set_level_azimuth_deg did not take"); fails += 1
	SceneLight.reset_level_azimuth()
	if not is_equal_approx(SceneLight.azimuth_deg(), SceneLight.DEFAULT_AZIMUTH_DEG):
		print("FAIL reset_level_azimuth did not restore canonical"); fails += 1

	# --- L2: the deliberate re-lights all land on canonical 225°. ---
	# Planets + map bodies: same radius-0.5 terminator circle as the old (0.0, 0.5), rotated 45°.
	fails += _eq("planet/map light_origin",
		SceneLight.planetkit_light_origin(SceneLight.RADIUS_PLANET), Vector2(0.146447, 0.146447))
	if SceneLight.planetkit_light_origin(SceneLight.RADIUS_PLANET).distance_to(Vector2(0.0, 0.5)) < 0.01:
		print("FAIL planets still on the old due-left sun"); fails += 1
	# Shader Lab's Building Shadow tab works in SHADOW-direction space, so it must read 45, not 225.
	var lab_angle := fposmod(rad_to_deg(SceneLight.shadow_dir().angle()), 360.0)
	if not is_equal_approx(snappedf(lab_angle, 0.001), 45.0):
		print("FAIL shader-lab sun angle is %.3f, expected 45" % lab_angle); fails += 1

	# --- L2: nobody kept a private copy of the sun they used to own. ---
	for path in NO_PRIVATE_SUNS:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			print("FAIL could not open %s" % path); fails += 1; continue
		var src := f.get_as_text()
		f.close()
		var lit: String = NO_PRIVATE_SUNS[path]
		if src.contains(lit):
			print("FAIL %s reintroduced %s" % [path, lit]); fails += 1
		else:
			print("  ok   %-26s no private sun" % path.get_file())

	# --- L3: star-reactive azimuth. ---
	const StellarGameplay = preload("res://scripts/parallax/stellar_gameplay.gd")
	var swing := SceneLight.STAR_SWING_DEG
	var canon := SceneLight.DEFAULT_AZIMUTH_DEG
	# No row context (StellarComposer dicts, menus, labs, pre-L3 saved runs) → canonical.
	fails += _deg("no stellar → canonical", SceneLight.azimuth_for_stellar({}), canon)
	fails += _deg("frac 0.0 (at the star)", SceneLight.azimuth_for_stellar({"system_frac": 0.0}), canon - swing)
	fails += _deg("frac 0.5 (mid-row)", SceneLight.azimuth_for_stellar({"system_frac": 0.5}), canon)
	fails += _deg("frac 1.0 (rim/boss)", SceneLight.azimuth_for_stellar({"system_frac": 1.0}), canon + swing)
	# Out-of-range fracs must clamp, not fling the sun somewhere absurd.
	fails += _deg("frac clamps high", SceneLight.azimuth_for_stellar({"system_frac": 9.0}), canon + swing)
	fails += _deg("frac clamps low", SceneLight.azimuth_for_stellar({"system_frac": -9.0}), canon - swing)
	# Whatever the swing, every producible sun must stay obliquely up-left — never degenerating to
	# due-left (180°, the flat read 225° was chosen over) or straight-down (270°).
	for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var az: float = SceneLight.azimuth_for_stellar({"system_frac": f})
		if az <= 180.0 or az >= 270.0:
			print("FAIL frac %.2f → %.1f° leaves the oblique band (180,270)" % [f, az]); fails += 1

	# The real producer must actually emit the key both paths, in range.
	var poi: Dictionary = StellarGameplay.compute_poi_stellar({
		"id": "poi-test", "row": 1, "pos_x": 272.0, "row_end_x": 416.0,
		"hazard_subtype": "", "belt_adjacent": false, "sectors_cleared": 0,
		"run_seed": 12345, "row_pois": [{"id": "poi-test", "pos_x": 272.0}],
	})
	if not poi.has("system_frac"):
		print("FAIL compute_poi_stellar emits no system_frac"); fails += 1
	elif float(poi["system_frac"]) < 0.0 or float(poi["system_frac"]) > 1.0:
		print("FAIL poi system_frac out of range: %s" % poi["system_frac"]); fails += 1
	else:
		print("  ok   %-26s %.3f → %.1f°" % ["poi system_frac", float(poi["system_frac"]),
			SceneLight.azimuth_for_stellar(poi)])
	var boss: Dictionary = StellarGameplay.compute_boss_stellar({"row": 1, "run_seed": 12345, "sectors_cleared": 0})
	fails += _deg("boss = rim", SceneLight.azimuth_for_stellar(boss), canon + swing)

	print("VERDICT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _deg(label: String, got: float, want: float) -> int:
	if absf(got - want) <= 0.001:
		print("  ok   %-26s %.1f°" % [label, got])
		return 0
	print("  FAIL %-26s got %.3f want %.3f" % [label, got, want])
	return 1


func _eq(label: String, got: Vector2, want: Vector2) -> int:
	# 1e-4: the replaced literals were written to 4 decimal places.
	if got.distance_to(want) <= 0.0001:
		print("  ok   %-26s %s" % [label, got])
		return 0
	print("  FAIL %-26s got %s want %s" % [label, got, want])
	return 1
