extends SceneTree

# Roman's "pre-capture mask + multiply in shader" approach (2026-05-18).
#
# Each shadow receiver knows its silhouette ahead of time, so we bake
# a mask Texture2D for it once. The shadow shader samples both the
# caster (player) silhouette AND the receiver mask, and multiplies the
# alphas. Result: shadow renders only where the player silhouette AND
# the receiver mask both have alpha — clipped to the receiver's shape
# without any reparenting / clip_children gymnastics.
#
# For this POC: one moon receiver, mask is a procedural disc (matches
# the moon's roughly-circular shape). In production we'd snapshot each
# receiver scene to a SubViewport once and cache the texture.

const OUT_DIR := "res://captures/shadow_mask"
const FPS: int = 24
const DURATION: float = 5.5
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/masked_shadow.gdshader")
const MOON_SCENE := preload("res://Planets/NoAtmosphere/NoAtmosphere.tscn")
const PLAYER_TEX := preload("res://graphics/player/blue-fighter-sheet.png")

# Light offset moved well past the player sprite (player is 48px at
# scale 3; this offsets the shadow clearly to the lower-right edge so
# it doesn't sit under the ship). Roman 2026-05-18.
const LIGHT_OFFSET := Vector2(20, 34)


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
	if moon.has_method("set_pixels"):
		moon.set_pixels(150.0)
	if "override_time" in moon:
		moon.override_time = true
	if moon.has_method("set_seed"):
		moon.set_seed(42)
	if moon.has_method("randomize_colors"):
		moon.randomize_colors()
	# Use a disc mask sized to the receiver's full bounds. SubViewport
	# snapshots don't respect their size in headless mode (captured the
	# main 672×800 viewport instead of the requested 160×160), so the
	# silhouette was a tiny dot in a huge image and most of the moon
	# read as out-of-mask. Disc fits the inscribed circle of the bounds,
	# which matches the visible moon's painted disc (Roman 2026-05-18).
	var moon_world_origin: Vector2 = (moon as Control).global_position
	var moon_size_world: Vector2 = (moon as Control).size * (moon as Control).scale
	var moon_mask: Texture2D = _bake_disc_mask(128, 128)
	# Player.
	var player := Sprite2D.new()
	player.texture = PLAYER_TEX
	player.hframes = 3
	player.frame = 1
	player.scale = Vector2(3, 3)
	player.z_index = 10
	root.add_child(player)
	# Shadow sprite — single-frame texture so the shader doesn't see the
	# 3-frame atlas. Masked shader handles the per-pixel mask multiply.
	var shadow := Sprite2D.new()
	shadow.texture = _bake_frame_texture(PLAYER_TEX, 1, 3, 1)
	# Drop shadow ~50% of the caster's apparent size — sells distance
	# (Roman 2026-05-18). Player renders at scale 3 (48 px); shadow at 1.5.
	shadow.scale = Vector2(1.5, 1.5)
	shadow.z_index = 5
	var shadow_size_world: Vector2 = shadow.texture.get_size() * shadow.scale
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mask_tex", moon_mask)
	mat.set_shader_parameter("mask_active", false)
	# 40% black under blend_mul = receiver dims to 60% where the shadow lands.
	mat.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, 0.4))
	mat.set_shader_parameter("shadow_size_world", shadow_size_world)
	mat.set_shader_parameter("receiver_world_origin", moon_world_origin)
	mat.set_shader_parameter("receiver_size_world", moon_size_world)
	shadow.material = mat
	root.add_child(shadow)
	# Capture loop.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		var x: float = 160.0 + 90.0 * sin(t * TAU * 0.35)
		var y: float = 200.0 + 18.0 * sin(t * TAU * 0.6)
		player.position = Vector2(x, y)
		var endpoint: Vector2 = player.position + LIGHT_OFFSET
		shadow.global_position = endpoint
		# Always feed the receiver mask. The shader's r_uv bounds test
		# handles the in-receiver gating per-pixel — drops the rect hit
		# test that was making the shadow blink at the rect edge while
		# the visible moon disc extended further (Roman 2026-05-18
		# "vanishing inconsistently"). The mask covers the full receivable
		# space so anywhere the moon is visible can receive shadow.
		mat.set_shader_parameter("mask_active", true)
		var shadow_origin: Vector2 = endpoint - shadow_size_world * 0.5
		mat.set_shader_parameter("shadow_world_origin", shadow_origin)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[shadow-mask] done")
	quit()


# Snapshot the receiver scene to a SubViewport and grab its texture.
# Produces a perfect silhouette mask in one pass — alpha exactly matches
# the rendered output of the scene.
func _snapshot_silhouette(scene: PackedScene, size: Vector2i) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var inst = scene.instantiate()
	if inst is Control:
		var ctrl := inst as Control
		ctrl.position = Vector2.ZERO
		ctrl.size = Vector2(size)
		ctrl.scale = Vector2.ONE
	if inst.has_method("set_pixels"):
		inst.set_pixels(150.0)
	if "override_time" in inst:
		inst.override_time = true
	if inst.has_method("set_seed"):
		inst.set_seed(42)
	if inst.has_method("randomize_colors"):
		inst.randomize_colors()
	vp.add_child(inst)
	# Let the viewport render at least one frame.
	# This script extends SceneTree, so process_frame is on `self`.
	await process_frame
	await process_frame
	var vp_img: Image = vp.get_texture().get_image()
	# Dump the captured mask to disk for debugging — verify the silhouette
	# actually covers the receiver bounds.
	vp_img.save_png(ProjectSettings.globalize_path("res://captures/shadow_mask_debug.png"))
	print("[shadow-mask] mask captured, size=", vp_img.get_size())
	# Sample mask coverage — count non-zero alpha pixels.
	var nonzero: int = 0
	for y in vp_img.get_height():
		for x in vp_img.get_width():
			if vp_img.get_pixel(x, y).a > 0.05:
				nonzero += 1
	print("[shadow-mask] non-zero alpha pixels: ", nonzero, " / ", vp_img.get_width() * vp_img.get_height())
	var tex: Texture2D = ImageTexture.create_from_image(vp_img)
	vp.queue_free()
	return tex


func _bake_disc_mask(w: int, h: int) -> Texture2D:
	# Filled disc inscribed in (w, h), HARD edge. Matches the moon
	# shader's `step(d_circle, 0.49999)` exactly — anywhere inside the
	# inscribed circle is solid alpha; outside is 0. Soft falloff at the
	# edge caused the shadow to fade to 0 in the last 2 px BEFORE reaching
	# the visible moon's edge (Roman 2026-05-18). The moon ends sharp;
	# the mask should too.
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var r: float = min(cx, cy)
	for y in h:
		for x in w:
			var dx: float = float(x) - cx + 0.5
			var dy: float = float(y) - cy + 0.5
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = 1.0 if d < r else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _bake_frame_texture(tex: Texture2D, frame_idx: int, hframes: int, vframes: int) -> Texture2D:
	var src: Image = tex.get_image()
	var fw: int = int(src.get_width() / hframes)
	var fh: int = int(src.get_height() / vframes)
	var col: int = frame_idx % hframes
	var row: int = int(frame_idx / hframes)
	var rect := Rect2i(col * fw, row * fh, fw, fh)
	var sub := Image.create(fw, fh, false, src.get_format())
	sub.blit_rect(src, rect, Vector2i.ZERO)
	return ImageTexture.create_from_image(sub)
