extends SceneTree

# Boot main.tscn, force-equip the Particle Beam onto the player, force
# "shoot2" pressed, place a row of enemies above the player, capture
# 60 frames of the beam tick to PNG sequence for ffmpeg → GIF.

const OUT_DIR := "user://particle_beam_frames"
const DURATION := 2.0
const FPS := 30


func _init() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for _i in range(20):
		await process_frame
	if current_scene == null:
		quit()
		return
	var player = current_scene.find_child("Player", true, false)
	if player == null:
		quit()
		return
	# Equip the Particle Beam onto the player at MK.9 so the wider-beam
	# (Mk scales width +2 per Mk → Mk.9 = 19 px) shows clearly.
	var ParticleBeamScript = load("res://scripts/parts/particle_beam.gd")
	var beam = ParticleBeamScript.new()
	beam.mark = 9
	beam.apply(player)
	# Mute the camera shake so the capture doesn't jitter the frame.
	if "_shake_amp" in player and player.has_node("/root/HologramHUD"):
		pass
	# Wait for the intro slide-in to finish so controls_enabled is true
	# (otherwise the player's _process bails early and the beam never
	# ticks).
	for _i in range(120):
		await process_frame
	# Spawn a row of dart enemies above the player so the beam has things
	# to pierce + damage. Place them in a vertical column at the player's x.
	var dart_scene: PackedScene = load("res://scenes/enemies/core/enemy_dart.tscn")
	if dart_scene:
		for i in range(4):
			var dart = dart_scene.instantiate()
			dart.position = Vector2(player.position.x, player.position.y - 30 - i * 35)
			current_scene.add_child(dart)
			dart.add_to_group("enemies")
	# Force shoot2 action to be pressed for the rest of the capture, AND
	# directly drive the beam tick every frame as a belt-and-suspenders
	# fallback in case Input.action_press doesn't reach the player's
	# _process in headless mode.
	Input.action_press("shoot2")
	# Capture loop.
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for f in range(int(DURATION * FPS)):
		await process_frame
		# Belt-and-braces — call the beam tick directly each frame.
		if player.has_method("_tick_beam"):
			player._tick_beam(true, 1.0 / float(FPS))
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%04d.png" % [OUT_DIR, f])
	Input.action_release("shoot2")
	print("saved %d frames to %s" % [int(DURATION * FPS), ProjectSettings.globalize_path(OUT_DIR)])
	quit()
