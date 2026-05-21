extends SceneTree

# Capture the half-second sparkling-star pre-fire flash on the Particle
# Beam, then the beam locking in. Equips the player with the Particle
# Beam part and simulates pressing `shoot2`. Records 1.2s of frames so
# we see the windup, transition, and ~0.7s of beam.

const OUT_DIR := "res://captures/beam_sparkle"
const FPS: int = 24
const DURATION: float = 1.4
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


func _run() -> void:
	# Dark backdrop so the sparkle reads. Plain ColorRect — no parallax
	# pipeline, this is purely a visual capture.
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06)
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	var player: Node2D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await create_timer(0.1).timeout
	player.position = Vector2(240, 200)
	# Keep controls_enabled TRUE so the player's _process actually runs
	# its firing logic; we use Input.action_press to drive shoot2.
	# Equip the Particle Beam in the HARDPOINT_WING slot via the live
	# PartCatalog so the player's _tick_beam path runs identically to
	# combat.
	if player.has_node("Loadout"):
		var part = PartCatalog._make_by_name("_make_particle_beam", SlotTypes.SlotType.HARDPOINT_WING)
		if part:
			part.mark = 3  # Mk.3 — beam is wide enough to read clearly
			player.get_node("Loadout").equip(SlotTypes.SlotType.HARDPOINT_WING, part)

	# Press and hold shoot2 to trigger the windup + beam.
	Input.action_press("shoot2")
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	Input.action_release("shoot2")
	print("[beam-sparkle] captured %d frames" % frame_count)
	quit()
