extends SceneTree

# Capture harness for the MISSILE CRUISER, run against the REAL showcase so the
# capture tests the things a bare scene can't: depth layering (cruiser must
# draw ABOVE the parallax backdrop but BELOW the player + enemy ships) and the
# desaturating mid-depth tint against an actual parallax background.
#
# Boots scenes/main.tscn through the "missile_cruiser_showcase" hazard subtype
# (light combat backdrop + a real player), which spawns the cruiser into the
# Backdrop after the intro. Captures frames so the GIF shows the cruiser
# reading at mid-depth, plus a full mark -> missiles -> AoE explosion salvo.
#
# Run via tools/capture_missile_cruiser.ps1 (real GPU, NOT --headless).

const MAIN := "res://scenes/main.tscn"
const FRAME_DIR := "res://captures/frames_missile_cruiser"
const FPS := 20
# Long enough to clear the ~3.4s intro and still catch a full salvo on-screen.
const DURATION := 9.0
const START_DELAY := 4.0  # skip the intro fade/fly-in before capturing


func _initialize() -> void:
	var dir_path := ProjectSettings.globalize_path(FRAME_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)

	await process_frame
	var run = root.get_node_or_null("Run")
	if run:
		run.new_run()
		run.test_mode_active = true
		run.current_hazard_subtype = "missile_cruiser_showcase"
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD

	var ps: PackedScene = load(MAIN)
	var inst: Node = ps.instantiate()
	root.add_child(inst)

	_capture_loop()


func _capture_loop() -> void:
	await create_timer(START_DELAY).timeout
	var frame_count: int = int(DURATION * FPS)
	var step: float = 1.0 / float(FPS)
	for i in frame_count:
		await create_timer(step).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		var path: String = "%s/frame_%04d.png" % [FRAME_DIR, i]
		img.save_png(ProjectSettings.globalize_path(path))
	print("[gif] captured %d frames at %d fps" % [frame_count, FPS])
	quit()
