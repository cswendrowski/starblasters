extends SceneTree

# Capture the burning-smoke comet (scripts/effects/burning_smoke_fx.gd) — a streaming
# fiery-smoke trail built from the explosion atlas: head = fire frame, tail = smoke
# frame. Renders to the MAIN WINDOW viewport (canvas_items stretch upscales the
# 480-authored coords to 1920×1080); grabbing a SubViewport added to root yields blank
# frames (it never renders without a container / UPDATE_ALWAYS).

const OUT_DIR := "res://captures/burning_smoke"
const FPS: int = 30
const DURATION: float = 2.4
const FRAME_TIME: float = 1.0 / float(FPS)

const BurningSmokeFx = preload("res://scripts/effects/burning_smoke_fx.gd")


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
	root.use_hdr_2d = true

	var bg := ColorRect.new()
	bg.color = Color(0.047, 0.055, 0.082, 1.0)  # ~#0c0e15
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	root.add_child(bg)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.9
	we.environment = env
	root.add_child(we)

	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)

	seed(7)
	_fire(stage)

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		if f == 36:        # re-fire ~1.2s in to keep the GIF lively
			_fire(stage)
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[burning-smoke-gif] captured %d frames" % frame_count)
	quit()


func _fire(stage: Node2D) -> void:
	for i in 3:
		var start := Vector2(240.0 + (i - 1) * 50.0, 60.0)
		var vel := Vector2(randf_range(-20.0, 20.0), randf_range(55.0, 85.0))
		BurningSmokeFx.spawn(stage, start, vel, {
			"segment_count": 14,
			"spacing": 6.0,
			"seg_scale": 0.9,
			"lifetime": 1.6,
		})
