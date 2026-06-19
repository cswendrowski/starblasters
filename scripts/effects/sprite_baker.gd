## SpriteBaker — async rotation-strip baker for procedural sprites (asteroids, planets).
## Bakes a scene into a horizontal rotation-strip flipbook texture suitable for LOD display.
class_name SpriteBaker


## Bake a scene into a horizontal rotation-strip texture.
## Args:
##   host: Node to attach temporary SubViewport as child (must be valid for tree lifetime)
##   scene: PackedScene to instantiate and bake
##   configure: Callable(instance: Node) to set seed/colors/pixels; can be null
##   frame_px: width/height of each frame in pixels (e.g. 64 for 64×64 frames)
##   frames: number of frames/rotations to bake (e.g. 12, 16, 32)
## Returns: ImageTexture (horizontal strip) or null on failure.
static func bake_rotation_strip(
	host: Node,
	scene: PackedScene,
	configure: Callable,
	frame_px: int,
	frames: int
) -> ImageTexture:
	# Defensive checks
	if not is_instance_valid(host):
		push_error("SpriteBaker: host is invalid")
		return null
	if scene == null:
		push_error("SpriteBaker: scene is null")
		return null
	if frame_px < 1 or frames < 1:
		push_error("SpriteBaker: invalid frame_px or frames")
		return null

	# Create SubViewport for rendering
	var sub := SubViewport.new()
	sub.size = Vector2i(frame_px, frame_px)
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.handle_input_locally = false
	host.add_child(sub)

	# Instantiate scene
	var instance = scene.instantiate()
	if instance == null:
		push_error("SpriteBaker: failed to instantiate scene")
		sub.queue_free()
		return null

	# Configure instance (seed/colors/pixels)
	if configure.is_valid():
		configure.call(instance)

	# Add to SubViewport
	sub.add_child(instance)

	# Scale to fill frame_px (assuming 100×100 logical size)
	var scale_factor := float(frame_px) / 100.0
	instance.scale = Vector2(scale_factor, scale_factor)

	# Freeze time animation: disable time_speed so only explicit rotation param drives the look
	# (layer_stellar.gd drives set_shader_parameter("rotation", t) with a fixed light_origin).
	var asteroid_node = instance.get_node_or_null("Asteroid")
	if asteroid_node != null and is_instance_valid(asteroid_node):
		var mat = asteroid_node.material
		if mat is ShaderMaterial:
			# Disable time-based animation
			mat.set_shader_parameter("time_speed", 0.0)

	# Bake rotation frames into a horizontal strip Image
	var strip := Image.create(frame_px * frames, frame_px, false, Image.FORMAT_RGBA8)

	for i in frames:
		# Set rotation param
		if asteroid_node != null and is_instance_valid(asteroid_node):
			var mat = asteroid_node.material
			if mat is ShaderMaterial:
				var rot := float(i) / float(frames) * TAU
				mat.set_shader_parameter("rotation", rot)

		# Wait for render (process + render pass)
		await host.get_tree().process_frame
		await host.get_tree().process_frame

		# Capture frame from SubViewport
		var tex = sub.get_texture()
		if tex == null:
			push_error("SpriteBaker: SubViewport texture is null at frame %d" % i)
			instance.queue_free()
			sub.queue_free()
			return null

		var img = tex.get_image()
		if img == null:
			push_error("SpriteBaker: failed to get image at frame %d" % i)
			instance.queue_free()
			sub.queue_free()
			return null

		# Blit into strip at column i
		strip.blit_rect(img, Rect2i(0, 0, frame_px, frame_px), Vector2i(i * frame_px, 0))

	# Cleanup
	instance.queue_free()
	sub.queue_free()

	# Create and return ImageTexture
	var texture := ImageTexture.create_from_image(strip)
	return texture


## Bake multiple asteroid variants into a single grid atlas in one pass per variant.
## Much faster than bake_rotation_strip (which waits frame-by-frame per frame);
## this version creates a wide SubViewport per variant, renders all frames at once, then captures.
##
## Args:
##   host: Node to attach temporary SubViewports (must be valid for tree lifetime)
##   scene: PackedScene to instantiate and bake
##   configure_variant: Callable(instance: Node, variant_index: int) to set seed/colors/pixels/layout
##   variants: number of variant rows (e.g. 10)
##   frame_px: width/height of each frame in pixels (e.g. 64)
##   frames: number of frames/rotations per variant (e.g. 13)
## Returns: Dictionary { "texture": ImageTexture, "variants": int, "frames": int, "frame_px": int }
##          or {} on failure. Atlas layout: variants rows × frames columns.
static func bake_variant_atlas(
	host: Node,
	scene: PackedScene,
	configure_variant: Callable,
	variants: int,
	frame_px: int,
	frames: int
) -> Dictionary:
	# Defensive checks
	if not is_instance_valid(host):
		push_error("SpriteBaker.bake_variant_atlas: host is invalid")
		return {}
	if scene == null:
		push_error("SpriteBaker.bake_variant_atlas: scene is null")
		return {}
	if variants < 1 or frame_px < 1 or frames < 1:
		push_error("SpriteBaker.bake_variant_atlas: invalid variants/frame_px/frames")
		return {}

	# Create final atlas image: variants rows × frames columns
	var atlas := Image.create(frame_px * frames, frame_px * variants, false, Image.FORMAT_RGBA8)

	# Bake each variant
	for v in variants:
		# Create a wide SubViewport for this variant (frames copies side by side)
		var sub := SubViewport.new()
		sub.size = Vector2i(frame_px * frames, frame_px)
		sub.transparent_bg = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sub.handle_input_locally = false
		host.add_child(sub)

		# Create frame_count copies of the asteroid, each with its own material
		var instances: Array[Node] = []
		for frame_idx in frames:
			var instance = scene.instantiate()
			if instance == null:
				push_error("SpriteBaker.bake_variant_atlas: failed to instantiate scene for variant %d, frame %d" % [v, frame_idx])
				sub.queue_free()
				return {}

			# Call configure to set seed/colors/pixels and layout reset
			if configure_variant.is_valid():
				configure_variant.call(instance, v)

			# Scale to fill frame_px
			var scale_factor := float(frame_px) / 100.0
			instance.scale = Vector2(scale_factor, scale_factor)

			# Position this frame's asteroid at x = frame_idx * frame_px
			instance.position = Vector2(frame_idx * frame_px, 0)

			# Set rotation and freeze time animation
			var asteroid_node = instance.get_node_or_null("Asteroid")
			if asteroid_node != null and is_instance_valid(asteroid_node):
				# Each frame copy needs its OWN material — Asteroid.tscn's material is a shared
				# SubResource, so without duplicating, every copy writes the same material and
				# only the last rotation survives (identical frames → no rotation when cycled).
				if asteroid_node.material != null:
					asteroid_node.material = asteroid_node.material.duplicate()
				var mat = asteroid_node.material
				if mat is ShaderMaterial:
					var rot := float(frame_idx) / float(frames) * TAU
					mat.set_shader_parameter("rotation", rot)
					mat.set_shader_parameter("time_speed", 0.0)

			sub.add_child(instance)
			instances.append(instance)

		# Wait for render pass
		await host.get_tree().process_frame
		await host.get_tree().process_frame

		# Capture the entire row
		var tex = sub.get_texture()
		if tex == null:
			push_error("SpriteBaker.bake_variant_atlas: SubViewport texture is null for variant %d" % v)
			for inst in instances:
				if is_instance_valid(inst):
					inst.queue_free()
			sub.queue_free()
			return {}

		var img = tex.get_image()
		if img == null:
			push_error("SpriteBaker.bake_variant_atlas: failed to get image for variant %d" % v)
			for inst in instances:
				if is_instance_valid(inst):
					inst.queue_free()
			sub.queue_free()
			return {}

		# Blit entire row into atlas at row v
		atlas.blit_rect(img, Rect2i(0, 0, frame_px * frames, frame_px), Vector2i(0, v * frame_px))

		# Cleanup
		for inst in instances:
			if is_instance_valid(inst):
				inst.queue_free()
		sub.queue_free()

	# Create and return ImageTexture
	var texture := ImageTexture.create_from_image(atlas)
	return {
		"texture": texture,
		"variants": variants,
		"frames": frames,
		"frame_px": frame_px
	}
