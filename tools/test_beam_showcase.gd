extends SceneTree

# M6a.2: the beam showcase wiring. Confirms Levels.build_beam_showcase() builds the
# expected 4-wave level, and that each converted beam enemy instantiates cleanly
# (the _ready path that creates/configures its BeamEmitter doesn't crash). Run:
#   godot --headless --script res://tools/test_beam_showcase.gd

const RESULT := "res://tools/_beam_showcase_result.txt"
const Levels := preload("res://scripts/levels/levels_v2.gd")

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# 1) the showcase level
	var lvl = Levels.build_beam_showcase()
	if lvl == null or not ("waves" in lvl):
		_fail("build_beam_showcase returned no level")
	elif lvl.waves.size() != 4:
		_fail("expected 4 waves, got %d" % lvl.waves.size())
	else:
		var want := [
			"res://scenes/enemies/enemy_beam_shooter.tscn",
			"res://scenes/enemies/enemy_beamer_tracker.tscn",
			"res://scenes/enemies/enemy_burner.tscn",
			"res://scenes/enemies/enemy_cruiser.tscn",
		]
		for i in 4:
			if lvl.waves[i].enemy_scene == null or lvl.waves[i].enemy_scene.resource_path != want[i]:
				_fail("wave %d wrong scene" % i)

	# 2) each beam enemy instantiates + _ready runs clean (BeamEmitter wiring)
	var world := Node2D.new()
	root.add_child(world)
	var beamer = load("res://scenes/enemies/enemy_beam_shooter.tscn").instantiate()
	world.add_child(beamer)
	if not ("_beam" in beamer) or beamer._beam == null:
		_fail("Beamer did not create its BeamEmitter in _ready")
	var tracker = load("res://scenes/enemies/enemy_beamer_tracker.tscn").instantiate()
	world.add_child(tracker)
	if not ("_beam" in tracker) or tracker._beam == null:
		_fail("Beamer-tracker did not create its BeamEmitter in _ready")
	var cruiser = load("res://scenes/enemies/enemy_cruiser.tscn").instantiate()
	world.add_child(cruiser)
	cruiser._spawn_turrets()   # cruiser defers this; force it so we can verify synchronously
	if not ("_beam_turret" in cruiser) or cruiser._beam_turret == null:
		_fail("Cruiser did not create its beam turret")
	elif not ("_beam" in cruiser._beam_turret) or cruiser._beam_turret._beam == null:
		_fail("Beam turret did not create its BeamEmitter in _ready")
	# Burner: _ready does NOT make a beam (created on telegraph) — just no crash.
	var burner = load("res://scenes/enemies/enemy_burner.tscn").instantiate()
	world.add_child(burner)

	_lines.append("showcase 4 waves ok ; beamer/tracker/cruiser instantiated clean")
	_lines.append("BEAM SHOWCASE: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
