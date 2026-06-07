extends SceneTree

# Reorg safety net: instantiate EVERY roster enemy scene (from Factions.ENEMY_TAGS,
# i.e. the moved/renamed scenes) so a bad ext_resource path after the directory move
# surfaces here, not at runtime when that enemy first spawns (parse_check can't catch
# a wrong scene-path string in a dict). Run:
#   godot --headless --script res://tools/test_reorg_load.gd

const RESULT := "res://tools/_reorg_load_result.txt"
const Factions := preload("res://scripts/levels/factions.gd")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var world := Node2D.new()
	root.add_child(world)
	var n := 0
	for path in Factions.ENEMY_TAGS.keys():
		if not ResourceLoader.exists(path):
			lines.append("FAIL missing scene: %s" % path); fails += 1
			continue
		var ps = load(path)
		if ps == null:
			lines.append("FAIL load null: %s" % path); fails += 1
			continue
		var inst = ps.instantiate()
		if inst == null:
			lines.append("FAIL instantiate null: %s" % path); fails += 1
			continue
		world.add_child(inst)   # runs _ready (where bespoke enemies wire children/beams)
		inst.queue_free()
		n += 1
	lines.append("instantiated %d/%d roster scenes" % [n, Factions.ENEMY_TAGS.size()])
	lines.append("REORG LOAD: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
