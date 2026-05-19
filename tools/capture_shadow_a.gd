extends SceneTree

# Drop shadow option A: topdown_shadow shader on a single Sprite2D,
# visibility gated by a hit-test against the moon's rect.

const OUT_DIR := "res://captures/shadow_a"
const FPS: int = 24
const DURATION: float = 5.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/topdown_shadow_outofbounds.gdshader")
const MOON_SCENE := preload("res://Planets/NoAtmosphere/NoAtmosphere.tscn")
const PLAYER_TEX := preload("res://graphics/player/blue-fighter-sheet.png")


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
	# Single moon centered.
	var moon = MOON_SCENE.instantiate()
	if moon is Control:
		var ctrl := moon as Control
		ctrl.position = Vector2(80, 100)
		ctrl.scale = Vector2(1.6, 1.6)
		ctrl.size = Vector2(100, 100)
	root.add_child(moon)
	# Moon rect (approximate, based on its visible drawer).
	var moon_rect := Rect2(Vector2(80, 100), Vector2(160, 160))
	# Player.
	var player := Sprite2D.new()
	player.texture = PLAYER_TEX
	player.hframes = 3
	player.frame = 1
	player.scale = Vector2(3, 3)
	player.z_index = 10
	root.add_child(player)
	# Shadow sprite (topdown_shadow shader).
	var shadow := Sprite2D.new()
	shadow.texture = PLAYER_TEX
	shadow.hframes = 3
	shadow.frame = 1
	shadow.scale = Vector2(3, 3)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("r", 0.0)
	mat.set_shader_parameter("offset", 0.0)
	mat.set_shader_parameter("shadow_only", true)
	shadow.material = mat
	shadow.z_index = 5
	shadow.visible = false
	root.add_child(shadow)
	# Capture loop.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		var x: float = 160.0 + 90.0 * sin(t * TAU * 0.35)
		var y: float = 200.0 + 18.0 * sin(t * TAU * 0.6)
		player.position = Vector2(x, y)
		var over: bool = moon_rect.has_point(player.position)
		shadow.visible = over
		if over:
			shadow.global_position = player.position + Vector2(6, 8)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[shadow-a] done")
	quit()
