extends SceneTree

# Capture the reworked asteroid hazard FX (Roman 2026-06-11): the noise-based smoke
# drift trail + 1px trailing debris, then the explosion = 3-6 spinning fragment-asteroids
# dispersing in a cone + 1px jittered debris motes + dust burst.
# Renders to the MAIN WINDOW viewport (the proven pattern).

const OUT_DIR := "res://captures/asteroid_fx"
const FPS: int = 30
const DURATION: float = 3.0
const FRAME_TIME: float = 1.0 / float(FPS)

const AsteroidScene = preload("res://scenes/enemies/enemy_asteroid.tscn")

var _rock
var _exploded := false


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
	bg.color = Color(0.05, 0.06, 0.09, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	root.add_child(bg)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.5
	we.environment = env
	root.add_child(we)
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)

	seed(11)
	_rock = AsteroidScene.instantiate()
	stage.add_child(_rock)
	_rock.position = Vector2(240.0, 60.0)
	if "drift_speed" in _rock:
		_rock.drift_speed = 55.0

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		# Let it drift (showing the smoke trail + 1px debris) ~1.1s, then explode.
		if not _exploded and f == 33 and is_instance_valid(_rock) and _rock.has_method("explode"):
			_exploded = true
			_rock.explode()
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[asteroid-fx-gif] captured %d frames" % frame_count)
	quit()
