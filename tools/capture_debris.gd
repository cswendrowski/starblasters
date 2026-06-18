extends SceneTree

# Capture an enemy death + debris scatter. Spawns one small (16-px) and
# one bigger (48-px scale=3) enemy side by side, kills each, records.

const OUT_DIR := "res://captures/debris"
const FPS: int = 24
const DURATION: float = 2.2
const FRAME_TIME: float = 1.0 / float(FPS)
const SMALL_SCENE := "res://scenes/enemies/factions/privateer/enemy_dart.tscn"
const LARGE_SCENE := "res://scenes/enemies/factions/supremacy/enemy_frigate.tscn"


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
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	root.add_child(bg)
	# Two enemies of different sizes.
	var small_scene := load(SMALL_SCENE) as PackedScene
	var large_scene := load(LARGE_SCENE) as PackedScene
	var enemies: Array = []
	if small_scene:
		var e := small_scene.instantiate()
		e.position = Vector2(80, 180)
		if "display_scale" in e:
			e.display_scale = 1.0
		root.add_child(e)
		enemies.append(e)
	if large_scene:
		var e := large_scene.instantiate()
		e.position = Vector2(220, 180)
		if "display_scale" in e:
			e.display_scale = 3.0
			e.scale = Vector2(3, 3)
		root.add_child(e)
		enemies.append(e)
	# Settle a frame, then kill them both.
	await create_timer(0.3).timeout
	for e in enemies:
		if is_instance_valid(e) and e.has_method("explode"):
			e.explode()
	# Capture frames.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[debris-gif] captured %d frames" % frame_count)
	quit()
