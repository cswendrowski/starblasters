extends SceneTree

# Capture the asteroid-field hazard so we can verify pixel parity across:
#   - Gameplay target asteroids (the ones you shoot — 44-64 vp-px)
#   - Parallax band asteroids deep/mid/near (6-30 vp-px, density 5× on hazard)
#   - Player ship as the reference pixel
# All should render with the same cell size on screen (~1 vp-px per cell at
# pixel_density=1.0) under the new rule.

const OUT := "res://captures/asteroid_parity.png"
const SCENE := "res://scenes/main.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if root.has_node("/root/Run"):
		var run = root.get_node("/root/Run")
		if "run_seed" in run:
			run.run_seed = 24680
		# Force the asteroid-field hazard so we get the busy version.
		if "current_hazard_subtype" in run:
			run.current_hazard_subtype = "asteroid_field"
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	# Let the wave director spin up and target asteroids spawn.
	await create_timer(2.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[asteroid-parity] wrote %s" % OUT)
	quit()
