extends SceneTree

# Verifies that the damage_noise shader pattern is stable across animation frames.
# The hover enemy has hframes=4. This script holds sensitivity at 0.45 (mid-damage)
# and steps through all 4 sprite frames — the noise pattern should be identical
# in every frame (same burn holes, same edge crumble position).
#
# Also captures a reference at frame=0 with sensitivity ramping to confirm the
# shader still responds correctly to damage level.

const OUT_DIR := "res://captures/damage_noise_stable"
const FPS: int = 6
const FRAME_TIME: float = 1.0 / float(FPS)
const NOISE_TEXTURE := preload("res://resources/noise_damage.tres")
const EDGE_DISTANCE_MAP := preload("res://resources/edge_distance_flat.tres")
const SPRITE_SCENE := preload("res://scenes/enemies/core/enemy_core_s_dart.tscn")

# Sensitivity mid-damage — enough to see the burn clearly
const TEST_SENSITIVITY := 0.45


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
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	var damage_shader := load("res://graphics/damage_noise.gdshader")
	if damage_shader == null:
		print("[damage_noise_stable] Failed to load shader")
		quit()
		return

	# --- Part 1: cycle all 4 animation frames at constant sensitivity ---
	# Each frame shown twice so the GIF reads clearly
	var sprite: Node2D = SPRITE_SCENE.instantiate()
	sprite.position = Vector2(240, 135)
	sprite.scale = Vector2(6, 6)
	root.add_child(sprite)

	var sprite_2d: Sprite2D = sprite.get_node("Sprite2D")
	if sprite_2d == null:
		print("[damage_noise_stable] No Sprite2D in hover scene")
		quit()
		return

	# Stop animation player so we control frames manually
	var anim_player: AnimationPlayer = sprite.get_node("AnimationPlayer")
	if anim_player:
		anim_player.stop()

	# Apply shader
	var mat := ShaderMaterial.new()
	mat.shader = damage_shader
	mat.set_shader_parameter("noise_texture", NOISE_TEXTURE)
	mat.set_shader_parameter("edge_distance_map", EDGE_DISTANCE_MAP)
	mat.set_shader_parameter("noise_seed", 42.0)
	mat.set_shader_parameter("sensitivity", TEST_SENSITIVITY)
	mat.set_shader_parameter("outline_color", Color(0, 0, 0, 1))
	mat.set_shader_parameter("replace_color", Color(0.05, 0.05, 0.05))
	mat.set_shader_parameter("edge_color", Color(0.85, 0.45, 0.05, 1.0))
	sprite_2d.material = mat

	# Disable collision to avoid warnings
	if sprite.has_node("CollisionShape2D"):
		sprite.get_node("CollisionShape2D").queue_free()

	await create_timer(0.1).timeout

	# Capture frame=0 through frame=3, twice each
	var frame_idx: int = 0
	for repeat in 2:
		for anim_frame in 4:
			sprite_2d.frame = anim_frame
			await create_timer(FRAME_TIME).timeout
			var img: Image = root.get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(ProjectSettings.globalize_path(
					"%s/frame_%04d.png" % [OUT_DIR, frame_idx]))
			frame_idx += 1

	# --- Part 2: sensitivity ramp at frame=0 (sanity check shader still responds) ---
	sprite_2d.frame = 0
	for step in 8:
		var s := float(step) / 7.0 * 0.75
		mat.set_shader_parameter("sensitivity", s)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path(
				"%s/frame_%04d.png" % [OUT_DIR, frame_idx]))
		frame_idx += 1

	print("[damage_noise_stable] captured %d frames" % frame_idx)
	quit()
