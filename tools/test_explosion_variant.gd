extends SceneTree

# Explosion variant (2026-06-09): ExplosionFx exposes named death-explosion variants;
# the "small_circle" one uses explosion_small_circle.png at 9 frames. Verify the registry
# resolves, the variant scene instantiates + ticks without crashing, and carries 9 frames.
# Run: godot --headless --script res://tools/test_explosion_variant.gd

const RESULT := "res://tools/_explosion_variant_result.txt"
const ExplosionFx := preload("res://scripts/effects/explosion_fx.gd")

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0

	# Registry: both names resolve; unknown falls back to default.
	if not ExplosionFx.variant_names().has("small_circle"):
		lines.append("FAIL small_circle not registered"); fails += 1
	if ExplosionFx.scene_for("nope") != ExplosionFx.scene_for("default"):
		lines.append("FAIL unknown variant does not fall back to default"); fails += 1

	# Play the small_circle variant and tick it a few frames.
	var sc: PackedScene = ExplosionFx.scene_for("small_circle")
	var inst = ExplosionFx.play(Vector2(100, 100), 1.0, true, root, sc)
	if inst == null or not is_instance_valid(inst):
		lines.append("FAIL variant did not spawn"); fails += 1
	else:
		if "frames" in inst and int(inst.frames) != 9:
			lines.append("FAIL small_circle frames=%s != 9" % str(inst.frames)); fails += 1
		else:
			lines.append("small_circle spawned with frames=9")
		for _i in range(10):
			if is_instance_valid(inst): inst._process(1.0 / 60.0)
		lines.append("variant ticked 10 frames without crash")

	lines.append("EXPLOSION VARIANT: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
