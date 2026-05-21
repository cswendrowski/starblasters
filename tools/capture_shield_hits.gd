extends SceneTree

# Triggers two shield drains on the live player: first a regular hit
# (shield_hit anim), then the final-charge consumption (shield_break
# anim). Captures ~2 s so both animations finish.

const OUT_DIR := "res://captures/shield_hits"
const FPS: int = 24
const DURATION: float = 2.0
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


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
	bg.color = Color(0.02, 0.03, 0.06)
	bg.size = Vector2(480, 270)
	root.add_child(bg)
	var player: Node2D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await create_timer(0.2).timeout
	player.position = Vector2(240, 150)
	# Seed the player with 2 shield charges so we can show both a hit
	# (drain from 2→1) and a break (drain from 1→0).
	if "max_shield" in player:
		player.max_shield = 2
	if player.has_method("set_shield"):
		player.set_shield(2)
	# Frame loop. At t=0.2 drain to 1 (hit anim). At t=1.0 drain to 0
	# (break anim).
	var total_frames: int = int(DURATION * float(FPS))
	var t: float = 0.0
	var hit_fired := false
	var break_fired := false
	for f in total_frames:
		await create_timer(FRAME_TIME).timeout
		t += FRAME_TIME
		if not hit_fired and t >= 0.2:
			hit_fired = true
			player.set_shield(1)
		elif not break_fired and t >= 1.0:
			break_fired = true
			player.set_shield(0)
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[shield-hits] captured %d frames" % total_frames)
	quit()
