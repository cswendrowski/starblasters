extends SceneTree

# Capture the Beam Cruiser with turrets in action
# Shows: idle drift + beam turret windup + beam fire + cooldown
# Duration: 11 seconds at 30fps (330 frames)
# Covers: 2s idle + 3s windup + 2s fire + partial cooldown + side gun turret shots

const OUT_DIR := "res://captures/beam_cruiser"
const FPS: int = 30
const DURATION: float = 11.0
const FRAME_TIME: float = 1.0 / float(FPS)
const CRUISER_SCENE := preload("res://scenes/enemies/enemy_cruiser.tscn")


# Dummy player for turret targeting
class DummyPlayer extends Node2D:
	func take_damage(_dmg: int) -> void:
		pass


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
	# Black background
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	# Dummy player node for turret aim-lock
	var player := DummyPlayer.new()
	player.position = Vector2(240, 220)
	player.add_to_group("player")
	root.add_child(player)

	# Cruiser at (240, 48) with entry animation skipped
	var cruiser: Node = CRUISER_SCENE.instantiate()
	cruiser.position = Vector2(240, 48)
	cruiser._settled = true
	root.add_child(cruiser)

	# Wait for turrets to spawn and settle
	await create_timer(0.5).timeout

	# Capture frames
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))

	print("[beam-cruiser-gif] captured %d frames" % frame_count)
	quit()
