extends SceneTree

# One-off verification: spawn a 4×3 grid of asteroids through the same
# per-instance material-duplicate + set_seed path the stellar layer uses, and
# save a single PNG. If the 12 asteroids show distinct silhouettes, the
# shared-material fix works. Run: godot --path . -s tools/capture_asteroid_grid.gd

const ASTEROID_SCENE := "res://Planets/Asteroids/Asteroid.tscn"
const OUT_PNG := "res://captures/asteroid_grid.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())

	# Black background so asteroid silhouettes read clearly.
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	var ps := load(ASTEROID_SCENE) as PackedScene
	var cols := 4
	var rows := 3
	var cell := Vector2(120, 90)
	for i in cols * rows:
		var a := ps.instantiate()
		var sz := 64.0
		if a is Control:
			a.anchor_left = 0.0; a.anchor_top = 0.0
			a.anchor_right = 0.0; a.anchor_bottom = 0.0
			a.offset_left = 0.0; a.offset_top = 0.0
			a.offset_right = 100.0; a.offset_bottom = 100.0
			a.size = Vector2(100, 100)
			a.custom_minimum_size = Vector2(100, 100)
			a.pivot_offset = Vector2.ZERO
		var sf := sz / 100.0
		a.scale = Vector2(sf, sf)
		var cx := (i % cols) * cell.x + 20.0
		var cy := (i / cols) * cell.y + 12.0
		a.position = Vector2(cx, cy)
		root.add_child(a)
		# Per-instance material so each set_seed sticks (the fix under test).
		var inner := a.get_node_or_null("Asteroid")
		if inner != null and inner is CanvasItem and inner.material != null:
			inner.material = inner.material.duplicate()
		if a.has_method("set_seed"):
			a.set_seed(rng.randi())
		if a.has_method("set_rotates"):
			a.set_rotates(true)
		if a.has_method("set_pixels"):
			a.set_pixels(64.0)
		if inner is Control:
			inner.size = Vector2(100, 100)
			inner.position = Vector2.ZERO

	await create_timer(0.6).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT_PNG))
		print("[asteroid-grid] saved %s" % OUT_PNG)
	quit()
