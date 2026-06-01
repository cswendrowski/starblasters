extends SceneTree

# One-shot capture of the Strafer's head-on pass: enters from the top,
# homes on a parked mock player, fires the 6-shot alternating-marker tracer
# burst, veers off, and bee-lines for the bottom. Frames → captures/strafer/
# → ffmpeg (capture_strafer.ps1) → captures/strafer.gif.

const OUT_DIR := "res://captures/strafer"
const FPS: int = 24
const DURATION: float = 5.5
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const STRAFER_SCENE := preload("res://scenes/enemies/enemy_strafer.tscn")


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
	# Galaxy backdrop for context / so the tracers read against something.
	var BackdropScript = load("res://scripts/galaxy_backdrop.gd")
	var backdrop := Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(BackdropScript)
	root.add_child(backdrop)

	# Mock player parked low-center inside the playfield band. The Strafer
	# homes on whatever is in the "player" group, so the real player scene
	# (controls disabled) is the cleanest target.
	var player: Node2D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await create_timer(0.2).timeout
	if "controls_enabled" in player:
		player.controls_enabled = false
	# Park the mock player low and to one side of the playfield band so the
	# Strafer's intercept comes in at a diagonal and its veer-off carries it
	# clear of the player instead of ramming it (in real gameplay the player
	# dodges; here the player is stationary, so we give the pass room to
	# complete). Playfield band is X 132..348.
	var player_x: float = 285.0
	var player_y: float = 245.0
	player.position = Vector2(player_x, player_y)

	# Spawn the Strafer at the top, offset to the opposite side, so the
	# whole head-on pass + veer + beeline reads in one diagonal sweep.
	var strafer: Node2D = STRAFER_SCENE.instantiate()
	root.add_child(strafer)
	strafer.add_to_group("enemies")
	if strafer.has_method("start"):
		strafer.start(Vector2(180.0, -12.0))
	else:
		strafer.position = Vector2(180.0, -12.0)

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		# Keep the mock player pinned (controls are off, but re-pin defensively).
		if is_instance_valid(player):
			player.position = Vector2(player_x, player_y)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[strafer] captured %d frames" % frame_count)
	quit()
