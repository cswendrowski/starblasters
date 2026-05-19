extends SceneTree

# Drop shadow option B: CanvasGroup drop_shadow_canvas_group shader.
# Player sits inside a CanvasGroup; shader paints a drop shadow of the
# group's contents based on SCREEN_TEXTURE. No per-pixel masking against
# receivers — the shadow appears wherever the offset silhouette lands.

const OUT_DIR := "res://captures/shadow_b"
const FPS: int = 24
const DURATION: float = 5.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/drop_shadow_canvas_group.gdshader")
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
	# CanvasGroup wrapping the player ship.
	var group := CanvasGroup.new()
	group.z_index = 8
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("shadow_offset_x", 0.02)
	mat.set_shader_parameter("shadow_offset_y", 0.03)
	mat.set_shader_parameter("drop_shadow_color", Color(0, 0, 0, 0.6))
	mat.set_shader_parameter("shadow_blur_strength", 1.5)
	mat.set_shader_parameter("shadow_blur_samples", 4)
	group.material = mat
	root.add_child(group)
	var player := Sprite2D.new()
	player.texture = PLAYER_TEX
	player.hframes = 3
	player.frame = 1
	player.scale = Vector2(3, 3)
	group.add_child(player)
	# Capture loop.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		var x: float = 160.0 + 90.0 * sin(t * TAU * 0.35)
		var y: float = 200.0 + 18.0 * sin(t * TAU * 0.6)
		player.position = Vector2(x, y)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[shadow-b] done")
	quit()
