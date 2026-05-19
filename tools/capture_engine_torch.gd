extends SceneTree

# Preview the engine torch shader with a simulated left/right player motion
# driving windForce. The actual player ship art is overlaid as a sprite so
# the GIF shows the plume positioned correctly under the engine nozzle.

const OUT_DIR := "res://captures/engine_torch"
const FPS: int = 24
const DURATION: float = 9.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/torch_fire.gdshader")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const EngineTorchCls := preload("res://scripts/effects/engine_torch.gd")


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


func _hex(hex: String) -> Color:
	var v: int = ("0x" + hex).hex_to_int()
	return Color(
		float((v >> 16) & 0xFF) / 255.0,
		float((v >> 8) & 0xFF) / 255.0,
		float(v & 0xFF) / 255.0,
		1.0
	)


func _run() -> void:
	# Real galaxy backdrop so the smoke trail is being viewed against the
	# actual playfield (Cody 2026-05-18 "over an actual background").
	var BackdropScript = load("res://scripts/galaxy_backdrop.gd")
	var backdrop := Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(BackdropScript)
	root.add_child(backdrop)
	# Real player instance, top-level with 3× scale to match the live game.
	# player.gd::start() positions itself relative to screensize, so we
	# override the position immediately after _ready and disable its input
	# so we can drive it ourselves.
	var player: Node2D = PLAYER_SCENE.instantiate()
	player.scale = Vector2(3, 3)
	root.add_child(player)
	await create_timer(0.3).timeout
	player.position = Vector2(160, 240)
	if "controls_enabled" in player:
		player.controls_enabled = false
	# Leave hull at full for the first ~1.5s of the GIF, then drop it to
	# 40% so the threshold-cross burst is visible in the recording.
	# (See loop below for the hull-drop trigger.)
	# Capture frames while sliding the mover horizontally. Hull steps
	# through 50% → 35% → 20% → 5% across the recording so the GIF shows
	# the trail thickening as the player gets closer to death.
	var frame_count: int = int(DURATION * float(FPS))
	var hull_stages := [
		[1.0, 0.50],    # threshold trigger
		[3.0, 0.35],
		[5.0, 0.20],
		[7.0, 0.05],
	]
	var stage_idx: int = 0
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		# Sine slide ±90px from center over the duration, 0.5 Hz.
		var x: float = 160.0 + 90.0 * sin(t * TAU * 0.5)
		player.position.x = x
		while stage_idx < hull_stages.size() and t >= float(hull_stages[stage_idx][0]):
			var frac: float = float(hull_stages[stage_idx][1])
			if "max_hull" in player and "hull" in player:
				player.max_hull = max(1, int(player.max_hull))
				player.hull = int(float(player.max_hull) * frac)
				if player.has_signal("hull_changed"):
					player.hull_changed.emit(player.max_hull, player.hull)
			stage_idx += 1
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[torch-gif] captured %d frames" % frame_count)
	quit()
