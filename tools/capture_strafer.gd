extends SceneTree

# One-shot capture mirroring Roman's path diagram: THREE strafers enter from
# three top X positions (left / center / right) and rush a parked mock player
# near the bottom-center. Each strafer sweeps PAST the player (offset strafe
# point), fires its burst, breaks off before the side walls, and recycles up
# to max_passes times before leaving. A visible RED marker is drawn over the
# player so non-collision is checkable frame-by-frame.
#
# Frames → captures/strafer/ → ffmpeg (capture_strafer.ps1) → strafer_paths.gif.

const OUT_DIR := "res://captures/strafer"
const FPS: int = 24
const DURATION: float = 9.0     # long enough to see multiple recycles
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const STRAFER_SCENE := preload("res://scenes/enemies/factions/corporate/enemy_strafer.tscn")


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
	# Plain dark background so the small dark strafer sprites + their arcs read
	# clearly (the random galaxy backdrop can pick a bright planet that washes
	# them out — this is a path-inspection capture, not a beauty shot).
	var bg := ColorRect.new()
	bg.name = "DarkBG"
	bg.color = Color(0.06, 0.07, 0.10, 1.0)
	bg.size = Vector2(480, 270)
	bg.z_index = -100
	root.add_child(bg)

	# Mock player parked low-center inside the playfield band (X 132..348).
	var player: Node2D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await create_timer(0.2).timeout
	if "controls_enabled" in player:
		player.controls_enabled = false
	var player_x: float = 240.0
	var player_y: float = 235.0
	player.position = Vector2(player_x, player_y)

	# Bright red collision marker over the player so overlap is checkable.
	var marker := ColorRect.new()
	marker.name = "PlayerHitMarker"
	marker.color = Color(1.0, 0.1, 0.1, 0.9)
	marker.size = Vector2(16, 16)            # matches strafer/player hit size
	marker.position = -marker.size * 0.5
	marker.z_index = 50
	player.add_child(marker)

	# Three strafers from three top X positions (left / center / right). Each
	# picks its own crossing/exit geometry from its entry X. Distinct trail
	# colors so each one's path can be traced + compared in a single frame.
	var entries := [160.0, 240.0, 320.0]
	var trail_colors := [Color(0.3, 0.8, 1.0, 0.9), Color(1.0, 0.85, 0.3, 0.9), Color(0.5, 1.0, 0.5, 0.9)]
	var strafers: Array = []
	for i in entries.size():
		var s: Node2D = STRAFER_SCENE.instantiate()
		root.add_child(s)
		s.add_to_group("enemies")
		if s.has_method("start"):
			s.start(Vector2(entries[i], -12.0))
		else:
			s.position = Vector2(entries[i], -12.0)
		strafers.append(s)

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		if is_instance_valid(player):
			player.position = Vector2(player_x, player_y)
		# Drop a small persistent trail dot per strafer so the path shape
		# (smoothness, crossing, fanning) is visible in any single frame.
		if f % 2 == 0:
			for i in strafers.size():
				var s2 = strafers[i]
				if is_instance_valid(s2):
					var dot := ColorRect.new()
					dot.color = trail_colors[i]
					dot.size = Vector2(2, 2)
					dot.position = s2.global_position - Vector2(1, 1)
					dot.z_index = 40
					root.add_child(dot)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[strafer] captured %d frames" % frame_count)
	quit()
