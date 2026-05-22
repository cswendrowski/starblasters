extends SceneTree

# Capture the Burner enemy in action — spawns at top, flies straight down
# at 200px/s, drops spinning fire mines every 0.6s. Shows the burner crossing
# the screen and the trail of mines it leaves behind.

const OUT_DIR := "res://captures/burner"
const FPS: int = 30
const DURATION: float = 7.0
const FRAME_TIME: float = 1.0 / float(FPS)
const BURNER_SCENE := preload("res://scenes/enemies/enemy_burner.tscn")


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
	var root_node = root

	# Black background container (internal viewport is 480×270).
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	root_node.add_child(bg)
	root_node.move_child(bg, 0)  # Send to back

	# Dummy player so fire mine damage checks don't error.
	var dummy_player := _DummyPlayer.new()
	dummy_player.name = "DummyPlayer"
	dummy_player.position = Vector2(240, 230)
	dummy_player.add_to_group("player")
	root_node.add_child(dummy_player)

	# Spawn burner at top-center.
	var burner: Node2D = BURNER_SCENE.instantiate()
	burner.scale = Vector2(1, 1)
	burner.position = Vector2(240, 20)
	root_node.add_child(burner)
	burner.add_to_group("enemies")

	# Capture frames.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root_node.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))

	print("[burner-gif] captured %d frames" % frame_count)
	quit()


class _DummyPlayer extends Node2D:
	var hull: int = 10

	func take_damage(dmg: int) -> void:
		pass  # Silent stub; fire mines can damage without error
