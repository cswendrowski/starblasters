extends SceneTree

# Capture the Bomber Wing in action — V-formation entry, turret fire,
# damage tells, death sequence. Player parked below so the bombers
# track it.

const OUT_DIR := "res://captures/bomber"
const FPS: int = 24
const DURATION: float = 9.0
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOMBER_SCENE := preload("res://scenes/enemies/enemy_bomber.tscn")


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
	# Galaxy backdrop so the capture has real game context.
	var BackdropScript = load("res://scripts/galaxy_backdrop.gd")
	var backdrop := Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(BackdropScript)
	root.add_child(backdrop)
	# Player parked below center.
	var player: Node2D = PLAYER_SCENE.instantiate()
	player.scale = Vector2(3, 3)
	root.add_child(player)
	await create_timer(0.3).timeout
	player.position = Vector2(160, 330)
	if "controls_enabled" in player:
		player.controls_enabled = false
	# Register a 5-bomber wing in the WaveGenV2 slot tracker so each
	# spawned bomber claims its V slot.
	var WaveGenV2 = load("res://scripts/levels/wave_generator_v2.gd")
	WaveGenV2._register_wing(5, [0.0, -62.0, 62.0, -118.0, 118.0], [0.0, 28.0, 28.0, 54.0, 54.0])
	# Spawn 5 bombers staggered.
	var bombers: Array = []
	for i in 5:
		var b: Node2D = BOMBER_SCENE.instantiate()
		# Bombers render at 1× (matches the director default). Roman 2026-05-18.
		b.scale = Vector2(1, 1)
		b.position = Vector2(160, -20 - float(i) * 18.0)
		root.add_child(b)
		b.add_to_group("enemies")
		bombers.append(b)
		await create_timer(0.18).timeout
	# Let them fly in + fire for a while. Drop bomber #2 to 40% hull at
	# t=3s so the damage tells (fire/smoke) engage, then kill it at t=5.5
	# to show the death sequence.
	var frame_count: int = int(DURATION * float(FPS))
	var damaged: bool = false
	var killed: bool = false
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		if not damaged and t >= 3.0 and bombers.size() >= 2:
			damaged = true
			var b = bombers[1]
			if is_instance_valid(b) and "max_health" in b and "health" in b:
				b.health = int(float(b.max_health) * 0.4)
				if b.has_signal("hull_changed"):
					b.hull_changed.emit(b.max_health, b.health)
		if not killed and t >= 5.5 and bombers.size() >= 2:
			killed = true
			var b = bombers[1]
			if is_instance_valid(b) and b.has_method("explode"):
				b.explode()
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[bomber-gif] captured %d frames" % frame_count)
	quit()
