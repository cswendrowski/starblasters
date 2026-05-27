extends SceneTree

# Capture the Firecore Cruiser in action
# Shows: horizontal traverse with turret active + death descent with upward fire trail
# Duration: 7 seconds total (4s traverse + 3s death descent at 12 fps)

const OUT_DIR := "res://captures/firecore_cruiser"
const FPS: int = 12
const DURATION: float = 7.0
const FRAME_TIME: float = 1.0 / float(FPS)
const CRUISER_SCENE := preload("res://scenes/enemies/enemy_firecore_cruiser.tscn")


class _DummyPlayer extends Node2D:
	var hull: int = 10

	func take_damage(_dmg: int) -> void:
		pass


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	
	# Clean out old frames
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

	# Black background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	root_node.add_child(bg)
	root_node.move_child(bg, 0)

	# Dummy player for turret targeting
	var player := _DummyPlayer.new()
	player.name = "DummyPlayer"
	player.position = Vector2(240, 140)
	player.add_to_group("player")
	root_node.add_child(player)

	# Firecore Cruiser — spawn off left edge, moving right
	var cruiser: Node = CRUISER_SCENE.instantiate()
	cruiser.global_position = Vector2(-40, 62)
	root_node.add_child(cruiser)
	cruiser.add_to_group("enemies")

	# Wait for setup
	await create_timer(0.3).timeout

	# Capture frames
	var frame_count: int = int(DURATION * float(FPS))
	var killed: bool = false

	for f in frame_count:
		await create_timer(FRAME_TIME).timeout

		# At ~4 second mark (frame 48), kill the cruiser to trigger death sequence
		if f == 48 and not killed and cruiser and is_instance_valid(cruiser):
			cruiser.take_hit(32)
			killed = true

		var img: Image = root_node.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))

	print("[firecore-cruiser-gif] captured %d frames" % frame_count)
	quit()
