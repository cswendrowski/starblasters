extends SceneTree

# Capture the Firecore Drone: orbiting rings (1/2/4 ring_count side-by-side),
# then kill all three to show the radial detach bullet-wave on death.
# Real GPU (run WITHOUT --headless). 12 fps.

const OUT_DIR := "res://captures/firecore_drone"
const FPS: int = 12
const DURATION: float = 4.0           # 1.5s orbit + ~2.5s after death
const KILL_FRAME: int = 18            # ~1.5s in (18/12)
const FRAME_TIME: float = 1.0 / float(FPS)
const DroneScene := preload("res://scenes/enemies/enemy_firecore_drone.tscn")


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

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.04, 0.03, 0.06)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	root_node.add_child(bg)
	root_node.move_child(bg, 0)

	# Three drones at different ring counts to show coverage variety.
	var drones: Array = []
	var configs := [
		{"ring": 1, "x": 175.0},
		{"ring": 2, "x": 240.0},
		{"ring": 4, "x": 310.0},
	]
	for cfg in configs:
		var drone = DroneScene.instantiate()
		drone.ring_count = int(cfg["ring"])
		root_node.add_child(drone)
		drone.global_position = Vector2(float(cfg["x"]), 90.0)
		drone.add_to_group("enemies")
		drones.append(drone)

	await create_timer(0.2).timeout

	var frame_count: int = int(DURATION * float(FPS))
	var killed: bool = false
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		if f == KILL_FRAME and not killed:
			for drone in drones:
				if is_instance_valid(drone):
					drone.take_hit(99)
			killed = true
		var img: Image = root_node.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))

	print("[firecore-drone] captured %d frames to %s" % [frame_count, OUT_DIR])
	quit()
