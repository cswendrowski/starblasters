# Regression check for the Planet Flyover Lab scene graph (Roman 2026-07-12): a botched
# edit once left the cloud-rect creation as dead code after a return — the scene booted
# "clean" while rendering zero clouds. Parse checks can't catch that; this asserts the
# built tree: 3 cloud rects with materials, 3 shadow-mask viewports, ground, atmo slices,
# and the casters (1 player + 3 enemies) with composed single-frame textures.
# Run: godot --path . --headless -s res://tools/test_flyover_clouds.gd
extends SceneTree

var _node = null
var _frames: int = 0


func _initialize() -> void:
	_node = load("res://scenes/dev/planet_flyover_lab.tscn").instantiate()
	get_root().add_child(_node)


# _ready only fires once the main loop iterates — assert a few frames in.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_run_checks(_node)
	return true


func _run_checks(n) -> void:
	var failures: Array = []
	var clouds: Dictionary = n._clouds
	if clouds.size() != 3:
		failures.append("expected 3 cloud rects, got %d" % clouds.size())
	for k in clouds:
		var rect = clouds[k]
		if rect == null or not is_instance_valid(rect):
			failures.append("cloud rect %s invalid" % k)
		elif rect.material == null:
			failures.append("cloud rect %s has no material" % k)
	if n._mask_vps.size() != 3:
		failures.append("expected 3 shadow-mask viewports, got %d" % n._mask_vps.size())
	if n._casters.size() != 4:
		failures.append("expected 4 casters (player + 3 enemies), got %d" % n._casters.size())
	for c in n._casters:
		var node = c["node"]
		if not (node.texture is AtlasTexture):
			failures.append("caster %s is not a composed single frame (texture %s)" % [node.name, node.texture])
	if n._ground == null or n._ground.material == null:
		failures.append("ground missing or has no material")
	if n._atmo_rects.size() != 3:
		failures.append("expected 3 atmosphere slices, got %d" % n._atmo_rects.size())
	if failures.is_empty():
		print("VERDICT: PASS — flyover lab scene graph intact")
		quit(0)
	else:
		for fx in failures:
			print("FAIL: ", fx)
		print("VERDICT: FAIL")
		quit(1)
