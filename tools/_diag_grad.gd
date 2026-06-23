extends SceneTree

# Find the lingering "gradient background": force several planet types with the halo toggle OFF and
# dump every visible CanvasItem under LayerPlanet (names + class) so we see what's not being hidden.

var _lab: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _settle(n: int) -> void:
	for _i in n:
		await create_timer(0.02).timeout

func _dump(idx: int, label: String) -> void:
	_lab._forced_planet = idx
	_lab._rebuild_backdrop()
	await _settle(35)
	var lp = _lab._backdrop.get_node_or_null("LayerPlanet")
	print("== ", label, " (idx ", idx, ") ==")
	if lp != null:
		_walk(lp, 0)

func _walk(n: Node, depth: int) -> void:
	for c in n.get_children():
		if c is CanvasItem:
			var vis: bool = (c as CanvasItem).visible
			var tex := ""
			if c is Sprite2D and (c as Sprite2D).texture != null:
				tex = " tex=" + (c as Sprite2D).texture.get_class()
			print("  ".repeat(depth + 1), c.name, " [", c.get_class(), "] vis=", vis, tex)
		_walk(c, depth + 1)

func _run() -> void:
	_lab = load("res://scenes/dev/parallax_tuner.tscn").instantiate()
	root.add_child(_lab)
	await create_timer(0.6).timeout
	_lab._on_gradient_glows_toggled(false)  # halos OFF
	await _dump(3, "GasPlanet")
	await _dump(7, "Galaxy")
	await _dump(9, "GasPlanetLayers")
	await _dump(1, "IceWorld")
	quit()
