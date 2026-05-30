extends SceneTree

const SCENE := "res://scenes/dev/light_patterns_demo.tscn"
const FRAME_DIR := "res://captures/frames_light_patterns"
const FPS := 20
const DURATION := 4.0

func _initialize() -> void:
	# Clean up old frames
	var dir_path := ProjectSettings.globalize_path(FRAME_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	
	# Load scene
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	
	# Start async capture
	_capture_loop()


func _capture_loop() -> void:
	# Wait for warmup
	await create_timer(0.2).timeout
	
	# Capture frames
	var frame_count: int = int(DURATION * FPS)
	var step: float = 1.0 / float(FPS)
	
	for i in frame_count:
		await create_timer(step).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		var path: String = "%s/frame_%04d.png" % [FRAME_DIR, i]
		img.save_png(ProjectSettings.globalize_path(path))
	
	print("[gif] captured %d frames at %d fps" % [frame_count, FPS])
	quit()
