extends SceneTree

# Captures the damage_noise.gdshader progression across 0.0→1.0 sensitivity.
# Shows 20 frames with sensitivity steps of 0.05.
# Each frame displays the enemy_hover sprite with the shader applied,
# on a dark background, with the sensitivity value labeled.

const OUT_DIR := "res://captures/damage_noise"
const FPS: int = 10
const FRAME_TIME: float = 1.0 / float(FPS)
const NUM_FRAMES: int = 20
const SPRITE_SCENE := preload("res://scenes/enemies/core/enemy_hover.tscn")
const NOISE_TEXTURE := preload("res://resources/noise_damage.tres")
const EDGE_DISTANCE_MAP := preload("res://resources/edge_distance_flat.tres")


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
	# Dark background (480×270)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	# Load the shader
	var damage_shader := load("res://graphics/damage_noise.gdshader")
	if damage_shader == null:
		print("[damage_noise] Failed to load shader")
		quit()
		return

	# Instantiate the sprite and scale it up
	var sprite: Node2D = SPRITE_SCENE.instantiate()
	sprite.position = Vector2(240, 135)  # Center of 480×270 viewport
	sprite.scale = Vector2(4, 4)  # 4× scale for visibility
	root.add_child(sprite)

	# Get the Sprite2D node and apply the shader
	var sprite_2d: Sprite2D = sprite.get_node("Sprite2D")
	if sprite_2d == null:
		print("[damage_noise] Failed to find Sprite2D in enemy_hover scene")
		quit()
		return

	# Create material with damage_noise shader
	var mat := ShaderMaterial.new()
	mat.shader = damage_shader
	sprite_2d.material = mat

	# Set shader uniforms
	mat.set_shader_parameter("noise_texture", NOISE_TEXTURE)
	mat.set_shader_parameter("edge_distance_map", EDGE_DISTANCE_MAP)
	mat.set_shader_parameter("noise_seed", 42.0)
	mat.set_shader_parameter("outline_color", Color(0, 0, 0, 1))
	mat.set_shader_parameter("replace_color", Color(0.08, 0.08, 0.12))
	mat.set_shader_parameter("edge_color", Color(0.3, 0.3, 0.3, 1.0))

	# Disable animation so we have a stable visual
	var anim_player: AnimationPlayer = sprite.get_node("AnimationPlayer")
	if anim_player:
		anim_player.stop()
		anim_player.seek(0)

	# Disable collisions
	var collision_shape: CollisionShape2D = sprite.get_node("CollisionShape2D")
	if collision_shape:
		collision_shape.queue_free()

	# Wait a frame for initialization
	await create_timer(0.05).timeout

	# Capture 20 frames with sensitivity stepping
	for f in NUM_FRAMES:
		var sensitivity := float(f) / float(NUM_FRAMES - 1)  # 0.0 to 1.0
		mat.set_shader_parameter("sensitivity", sensitivity)

		# Render the frame
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))

	print("[damage_noise] captured %d frames" % NUM_FRAMES)
	quit()
