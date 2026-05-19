extends SceneTree

# Roman's "ray + reparent + mask" approach (2026-05-18).
#
# One shadow Sprite2D total. Each frame we compute the ray endpoint
# (player + fixed light offset) and ask "is this point inside a
# shadow-receiver?" If yes, reparent the shadow under that receiver's
# clipper (which has clip_children = CLIP_CHILDREN_ONLY) so the receiver
# masks the shadow to its own opaque pixels. If no receiver contains the
# endpoint, the shadow is hidden — no shadow over empty space.

const OUT_DIR := "res://captures/shadow_ray"
const FPS: int = 24
const DURATION: float = 5.5
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/topdown_shadow_outofbounds.gdshader")
const MOON_SCENE := preload("res://Planets/NoAtmosphere/NoAtmosphere.tscn")
const PLAYER_TEX := preload("res://graphics/player/blue-fighter-sheet.png")

# Light direction (sun above-and-to-left), shadow lands below-right.
const LIGHT_OFFSET := Vector2(8, 12)


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
	# Single moon centered, made into a clip receiver. Initialize the
	# planet via its own set_pixels/set_seed hooks so it actually paints.
	var moon = MOON_SCENE.instantiate()
	if moon is Control:
		var ctrl := moon as Control
		ctrl.position = Vector2(80, 100)
		ctrl.scale = Vector2(1.6, 1.6)
		ctrl.size = Vector2(100, 100)
	root.add_child(moon)
	if moon.has_method("set_pixels"):
		moon.set_pixels(150.0)
	if "override_time" in moon:
		moon.override_time = true
	if moon.has_method("set_seed"):
		moon.set_seed(42)
	if moon.has_method("randomize_colors"):
		moon.randomize_colors()
	var moon_clipper: CanvasItem = _find_first_drawer(moon)
	if moon_clipper:
		moon_clipper.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	# Moon rect for the ray hit-test (approximate, based on the clipper's
	# global bounds at run time).
	var moon_rect: Rect2 = _compute_world_rect(moon_clipper)
	# Player.
	var player := Sprite2D.new()
	player.texture = PLAYER_TEX
	player.hframes = 3
	player.frame = 1
	player.scale = Vector2(3, 3)
	player.z_index = 10
	root.add_child(player)
	# Shadow sprite — single, will be reparented each frame based on the
	# ray endpoint test. The shader samples the entire TEXTURE so the
	# raw 48×16 sheet (3 frames) renders as 3 shadows. Bake a 1-frame
	# texture out of the player sheet so the shadow is a single silhouette.
	var shadow := Sprite2D.new()
	shadow.texture = _bake_frame_texture(PLAYER_TEX, 1, 3, 1)
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
		# Ray endpoint = player + light offset (where the shadow lands).
		var endpoint: Vector2 = player.position + LIGHT_OFFSET
		if moon_rect.has_point(endpoint) and moon_clipper != null and is_instance_valid(moon_clipper):
			# Reparent shadow under the receiver so its clip_children masks
			# the silhouette to the receiver's drawn alpha.
			if shadow.get_parent() != moon_clipper:
				shadow.get_parent().remove_child(shadow)
				moon_clipper.add_child(shadow)
			shadow.visible = true
			# Convert endpoint world coord to receiver-local.
			if moon_clipper is Node2D:
				shadow.position = (moon_clipper as Node2D).to_local(endpoint)
			elif moon_clipper is Control:
				var ctrl := moon_clipper as Control
				# Control's "local" = (world - global_position) / scale
				shadow.position = (endpoint - ctrl.global_position) / ctrl.scale
		else:
			if shadow.get_parent() != root:
				shadow.get_parent().remove_child(shadow)
				root.add_child(shadow)
			shadow.visible = false
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[shadow-ray] done")
	quit()


func _bake_frame_texture(tex: Texture2D, frame_idx: int, hframes: int, vframes: int) -> Texture2D:
	# Pull a single frame out of an atlas into its own ImageTexture so a
	# canvas_item shader that samples TEXTURE sees just that frame.
	var src: Image = tex.get_image()
	var fw: int = int(src.get_width() / hframes)
	var fh: int = int(src.get_height() / vframes)
	var col: int = frame_idx % hframes
	var row: int = int(frame_idx / hframes)
	var rect := Rect2i(col * fw, row * fh, fw, fh)
	var sub := Image.create(fw, fh, false, src.get_format())
	sub.blit_rect(src, rect, Vector2i.ZERO)
	return ImageTexture.create_from_image(sub)


func _find_first_drawer(n: Node) -> CanvasItem:
	for c in n.get_children():
		if c is Sprite2D or c is ColorRect or c is TextureRect:
			return c
		var hit := _find_first_drawer(c)
		if hit:
			return hit
	if n is Sprite2D or n is ColorRect or n is TextureRect:
		return n
	return null


func _compute_world_rect(c: CanvasItem) -> Rect2:
	if c is Control:
		var ctrl := c as Control
		return Rect2(ctrl.global_position, ctrl.size * ctrl.scale)
	if c is Node2D:
		var n := c as Node2D
		# Best-effort: 100×100 around its position (planet default).
		var sz := Vector2(100, 100) * n.scale
		return Rect2(n.global_position - sz * 0.5, sz)
	return Rect2()
