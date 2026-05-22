extends SceneTree

# Captures the Rotary Laser firing — 20 shots/sec blue energy stream.

const OUT_DIR := "res://captures/rotary_laser"
const FPS: int = 30
const DURATION: float = 2.0
const FRAME_TIME: float = 1.0 / float(FPS)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


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
	await create_timer(0.15).timeout
	player.position = Vector2(240, 200)
	# Swap the default CANNON slot for the Rotary Laser.
	var catalog = PartCatalog.new()
	var rotary = catalog._make_by_name("_make_rotary_laser", SlotTypes.SlotType.CANNON)
	if rotary and player.has_method("equip_part"):
		player.equip_part(rotary)
	elif rotary and "weapon_style" in player:
		rotary.apply(player)
	await create_timer(0.05).timeout
	Input.action_press("shoot")
	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	Input.action_release("shoot")
	print("[rotary-laser] captured %d frames" % total)
	quit()
