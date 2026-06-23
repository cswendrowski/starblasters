extends SceneTree

# Widescreen-vertical proof — boot a stripped scene with the galaxy
# backdrop and the player ship in its proper bottom-center anchor,
# slide it left/right so the new wider (480-px) playfield is visible.
# Vertical gameplay preserved per Roman 2026-05-19 clarification.

const OUT_DIR := "res://captures/horizontal_proof"
const FPS: int = 24
const DURATION: float = 5.0
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/core/enemy_core_s_dart.tscn")
const StraightDownCls := preload("res://scripts/enemies/patterns/straight_down.gd")


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
	var BackdropScript = load("res://scripts/parallax/galaxy_backdrop.gd")
	var backdrop := Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(BackdropScript)
	root.add_child(backdrop)

	var player: Node2D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await create_timer(0.3).timeout
	if "controls_enabled" in player:
		player.controls_enabled = false

	# Player rides along the bottom, sliding left↔right across the new
	# wider 480-px playfield (was 320) so the extra maneuver room reads.
	var anchor_y: float = 210.0  # 270 - 60ish
	var center_x: float = 240.0  # half of 480
	var fire_interval: float = 0.15
	var next_fire: float = 0.0

	var spawn_times := [0.4, 1.4, 2.4, 3.4]
	var spawn_xs := [80.0, 200.0, 320.0, 410.0]
	var spawned := [false, false, false, false]

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		var x: float = center_x + 170.0 * sin(t * TAU * 0.4)
		player.position = Vector2(x, anchor_y)
		if t >= next_fire and player.has_method("fire_primary"):
			player.fire_primary()
			next_fire = t + fire_interval
		for i in spawn_times.size():
			if not spawned[i] and t >= float(spawn_times[i]):
				spawned[i] = true
				var enemy: Node2D = ENEMY_SCENE.instantiate()
				if "movement" in enemy:
					var pat := StraightDownCls.new()
					enemy.movement = pat
				if "shoot_pattern" in enemy:
					enemy.shoot_pattern = null
				root.add_child(enemy)
				enemy.add_to_group("enemies")
				if enemy.has_method("start"):
					enemy.start(Vector2(float(spawn_xs[i]), -10.0))
				else:
					enemy.position = Vector2(float(spawn_xs[i]), -10.0)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[widescreen-vertical] captured %d frames" % frame_count)
	quit()
