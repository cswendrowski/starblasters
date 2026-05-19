extends SceneTree

# Snap the combat HUD with the player's shield forced full vs zero so the
# hull bar's blue→red color switch is visible without enemy attrition.

const SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures/hud_states"


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	await _capture("shields_full", 3)
	await _capture("shields_zero", 0)
	print("[hud] done")
	quit()


func _capture(label: String, shield_value: int) -> void:
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(1.2).timeout
	# Find the player and force its shield value.
	var player := _find_node_with_method(inst, "take_damage")
	if player and "shield" in player:
		player.shield = shield_value
		if player.has_signal("shield_changed"):
			player.shield_changed.emit(player.max_shield, player.shield)
	await create_timer(0.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		var p := "%s/%s.png" % [OUT_DIR, label]
		img.save_png(ProjectSettings.globalize_path(p))
		print("[hud] wrote %s" % p)
	inst.queue_free()
	await create_timer(0.2).timeout


func _find_node_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var hit := _find_node_with_method(c, m)
		if hit:
			return hit
	return null
