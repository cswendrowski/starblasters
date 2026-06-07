extends SceneTree

# Captures the EnemyBeamShooter firing sequence:
# 0.0–1.5s: IDLE (stationary, no beam)
# 1.5–4.5s: WINDUP (telegraph pulse, 3s duration)
# 4.5–6.5s: FIRING (full beam, 2s duration)
# 6.5–9.0s: COOLDOWN (hidden beam, 2.5s duration) + loop start

const OUT_DIR := "res://captures/beam_shooter"
const FPS: int = 30
const DURATION: float = 9.0
const FRAME_TIME: float = 1.0 / float(FPS)
const BEAM_SHOOTER_SCENE := preload("res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn")


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
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06)
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	# Spawn the beam shooter at settle position (y=60) so it skips the enter animation
	var enemy: Node2D = BEAM_SHOOTER_SCENE.instantiate()
	enemy.position = Vector2(240, 60)
	root.add_child(enemy)

	# Immediately mark as settled so it doesn't animate in
	if enemy.has_meta("_settled") or "_settled" in enemy:
		enemy._settled = true

	# Create a dummy player node in the "player" group for beam damage checks
	# Position it at y=230 so it's in the line of fire
	var dummy_player := Area2D.new()
	dummy_player.global_position = Vector2(240, 230)
	dummy_player.add_to_group("player")
	root.add_child(dummy_player)

	# Wait a frame for initialization
	await create_timer(0.05).timeout

	# Capture 270 frames at 30fps = 9 seconds
	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))

	print("[beam-shooter] captured %d frames" % total)
	quit()
