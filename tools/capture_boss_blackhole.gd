extends SceneTree

# Capture the boss black hole attack sequence: charge → fire → detonate.
# Sets up a minimal scene with a Backdrop sibling so boss.gd's
# _add_world_node_above_backdrop() can find it.

const OUT_DIR := "res://captures/boss_blackhole"
const FPS: int = 24
const DURATION: float = 6.5
const FRAME_TIME: float = 1.0 / float(FPS)
const BOSS_SCENE := "res://scenes/enemies/boss.tscn"


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
	# Dark backdrop so the hole reads.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# Backdrop sibling that boss.gd looks for.
	var backdrop := Node2D.new()
	backdrop.name = "Backdrop"
	root.add_child(backdrop)
	# Fake player so boss.gd's "detonate at player Y" lookup has a target.
	# Group "player" is what the boss searches for.
	var fake_player := Node2D.new()
	fake_player.add_to_group("player")
	fake_player.position = Vector2(160, 340)
	root.add_child(fake_player)
	# Spawn the boss near the top of the playfield. The capture script
	# operates at the default 320×400 internal resolution.
	var ps := load(BOSS_SCENE) as PackedScene
	if ps == null:
		print("[boss-gif] could not load boss scene")
		quit()
		return
	var boss: Node2D = ps.instantiate()
	boss.position = Vector2(160, 56)
	root.add_child(boss)
	# Settle a frame so boss._ready completes.
	await create_timer(0.2).timeout
	# Force the attack immediately rather than waiting on the random schedule.
	if boss.has_method("_spawn_black_hole_attack"):
		boss._spawn_black_hole_attack()
	# Capture frames.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[boss-gif] captured %d frames" % frame_count)
	quit()
