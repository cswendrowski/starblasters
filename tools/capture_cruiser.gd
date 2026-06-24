extends SceneTree

# Capture the multi-part Cruiser: structure + turret fire + GunL/Bridge being shot off.
# Run via tools/capture_cruiser.ps1 (real window, NOT --headless, so frame_post_draw fires).
# Key fixes vs first pass: spawn on-screen, and await RenderingServer.frame_post_draw before
# grabbing the viewport (otherwise every saved frame is the same stale texture).

const OUT_DIR := "res://captures/cruiser"
const FPS: int = 30
const DURATION: float = 5.0
const FRAME_TIME: float = 1.0 / float(FPS)
const CRUISER_SCENE := preload("res://scenes/enemies/core/enemy_cruiser.tscn")


# Dummy player for turret targeting; oscillates so the gun pods track + fire.
class DummyPlayer extends Node2D:
	var t: float = 0.0
	var base_x: float = 240.0
	func take_damage(_dmg: int) -> void:
		pass
	func _process(delta: float) -> void:
		t += delta
		position.x = base_x + sin(t * 3.0) * 30.0


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
	# Dark space background.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 1.0)
	bg.size = Vector2(480, 270)
	root.add_child(bg)

	# Dummy player target near the bottom for the gun pods to aim at.
	var player := DummyPlayer.new()
	player.position = Vector2(240, 220)
	player.add_to_group("player")
	root.add_child(player)

	# Cruiser placed on-screen near the top of the playfield; the Drift movement settles it lower.
	var cruiser: Node = CRUISER_SCENE.instantiate()
	cruiser.position = Vector2(240, 70)
	root.add_child(cruiser)

	await create_timer(0.4).timeout   # let _ready run (turret children + stats)

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		# t≈2.0s: shoot off the left gun pod (its fire should stop).
		if f == int(2.0 * float(FPS)):
			var gun_l = cruiser.get_node_or_null("GunL")
			if gun_l and is_instance_valid(gun_l):
				gun_l.take_hit(99)
				print("[cruiser-gif] GunL shot off at frame %d" % f)
		# t≈3.2s: shoot off the bridge.
		if f == int(3.2 * float(FPS)):
			var bridge = cruiser.get_node_or_null("Bridge")
			if bridge and is_instance_valid(bridge):
				bridge.take_hit(99)
				print("[cruiser-gif] Bridge shot off at frame %d" % f)

		await create_timer(FRAME_TIME).timeout
		await RenderingServer.frame_post_draw       # ensure the viewport texture is current
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))

	print("[cruiser-gif] captured %d frames" % frame_count)
	quit()
