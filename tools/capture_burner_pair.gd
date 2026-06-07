extends SceneTree

# Capture the Burner pair: arrival -> beam established -> descend together ->
# kill one -> beam drops + both explode. Windowed (real GPU renderer; headless
# returns null viewport textures). Run:
#   godot --path . -s tools/capture_burner_pair.gd

const BURNER := "res://scenes/enemies/factions/zealot/enemy_burner.tscn"
const OUT_DIR := "res://captures/burner_pair"
const FPS := 24
const DURATION := 4.0
const KILL_AT := 2.7  # seconds — when to shoot one of the pair

var _burners: Array = []
var _killed := false

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
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.size = Vector2(480, 270)
	var cl := CanvasLayer.new()
	cl.layer = -5
	cl.add_child(bg)
	root.add_child(cl)

	var cam := Camera2D.new()
	cam.position = Vector2(240, 135)
	root.add_child(cam)
	cam.make_current()

	var ps = load(BURNER)
	# Spawn the pair near the top, spaced around center; they self-adopt + beam.
	for i in 2:
		var b = (ps as PackedScene).instantiate()
		root.add_child(b)
		var x: float = 240.0 + (-26.0 if i == 0 else 26.0)
		b.global_position = Vector2(x, 18.0)
		_burners.append(b)
	print("[burner] spawned pair")

	var frame_count := int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(1.0 / float(FPS)).timeout
		var t: float = float(f) / float(FPS)
		if not _killed and t >= KILL_AT:
			_killed = true
			var victim = _burners[0]
			if is_instance_valid(victim) and victim.has_method("take_hit"):
				victim.take_hit(999)
				print("[burner] killed one at t=%.2f" % t)
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[burner] done")
	quit()
