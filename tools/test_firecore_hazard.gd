extends SceneTree

# M6b: firecore lane hazard (zealot drop). Verifies it's a hazard, drifts down,
# is destructible (lethal hit -> explode), explodes + damages on player contact, and
# that the zealot faction Emitter now resolves the firecore payload (scene exists). Run:
#   godot --headless --script res://tools/test_firecore_hazard.gd

const RESULT := "res://tools/_firecore_result.txt"
const HazardScene := preload("res://scenes/enemies/factions/zealot/firecore_hazard.tscn")
const Factions := preload("res://scripts/levels/factions.gd")
const HullTarget := preload("res://tools/_hull_target.gd")

const DT := 1.0 / 60.0
var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	var world := Node2D.new()
	root.add_child(world)

	# instantiate + basic config
	var hz = HazardScene.instantiate()
	world.add_child(hz)
	hz.start(Vector2(240, 60))
	if not ("is_hazard" in hz) or not hz.is_hazard:
		_fail("firecore is not is_hazard")
	if hz.max_health != 2:
		_fail("firecore max_health %d != 2 (should be destructible)" % hz.max_health)

	# drifts down
	var y0: float = hz.position.y
	for i in 30:
		hz._process(DT)
	if hz.position.y <= y0:
		_fail("firecore did not drift down (y %.1f -> %.1f)" % [y0, hz.position.y])

	# destructible: a lethal hit explodes it
	hz.take_hit(2)
	if not hz._dying:
		_fail("firecore not destroyed by a lethal hit (take_hit)")

	# contact: damages the player + explodes
	var hz2 = HazardScene.instantiate()
	world.add_child(hz2)
	hz2.start(Vector2(200, 80))
	var player = HullTarget.new()
	player.position = Vector2(200, 80)
	world.add_child(player)
	player.add_to_group("player")
	hz2._on_area_entered(player)
	if player.taken <= 0:
		_fail("firecore contact dealt no damage to player")
	if not hz2._dying:
		_fail("firecore did not explode on contact")

	# zealot Emitter now resolves the firecore payload (the scene exists)
	var comps: Array = Factions.build_components(Factions.Id.ZEALOT)
	if comps.is_empty():
		_fail("zealot built no components")
	elif comps[0].payload == null:
		_fail("zealot Emitter payload is null (firecore scene not wired)")

	_lines.append("FIRECORE HAZARD: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
