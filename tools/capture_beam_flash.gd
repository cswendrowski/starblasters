extends SceneTree

# Captures the new star_flash beam windup → hold → cool-down cycle.
# Simulates holding shoot2 for ~1.2 s then releasing for another 0.6 s
# so the cool-down frames play out before the recording ends.

const OUT_DIR := "res://captures/beam_flash"
const FPS: int = 24
const HOLD_DURATION: float = 1.2
const RELEASE_DURATION: float = 0.6
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
	await create_timer(0.1).timeout
	player.position = Vector2(240, 200)
	if player.has_node("Loadout"):
		var part = PartCatalog._make_by_name("_make_particle_beam", SlotTypes.SlotType.HARDPOINT_WING)
		if part:
			part.mark = 3
			player.get_node("Loadout").equip(SlotTypes.SlotType.HARDPOINT_WING, part)
	Input.action_press("shoot2")
	var hold_frames: int = int(HOLD_DURATION * float(FPS))
	var release_frames: int = int(RELEASE_DURATION * float(FPS))
	var idx: int = 0
	for f in hold_frames:
		await create_timer(FRAME_TIME).timeout
		_save_frame(idx)
		idx += 1
	Input.action_release("shoot2")
	for f in release_frames:
		await create_timer(FRAME_TIME).timeout
		_save_frame(idx)
		idx += 1
	print("[beam-flash] captured %d frames" % idx)
	quit()


func _save_frame(idx: int) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, idx]))
