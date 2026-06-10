extends SceneTree

# Captures the new machinegun muzzle FX — random-frame strip + yellow
# glow + halved smoke puff. Equips the player with the machinegun
# cannon, presses shoot for 1.2 s, captures frames.

const OUT_DIR := "res://captures/muzzle_flash"
const FPS: int = 30
const DURATION: float = 1.4
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
	player.position = Vector2(240, 180)
	if player.has_node("Loadout"):
		# Minigun: same MG-family muzzle flash + shell eject, fires immediately (the retired
		# Machinegun factory is gone; the Autocannon's 1.5s spin-up would outlast this 1.4s capture).
		var part = PartCatalog._make_by_name("_make_minigun", SlotTypes.SlotType.CANNON)
		if part:
			part.mark = 3
			player.get_node("Loadout").equip(SlotTypes.SlotType.CANNON, part)
	# Ensure the gun has ammo so it keeps firing.
	if "ammo" in player:
		player.ammo = 999
	Input.action_press("shoot")
	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	Input.action_release("shoot")
	print("[muzzle-flash] captured %d frames" % total)
	quit()
