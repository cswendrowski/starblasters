extends SceneTree

# M6a.2 step 4c: the `beam` fire_pattern + enemy_core hook. An enemy_core enemy
# carrying a Weapon with fire_pattern==BEAM should attach a per-enemy BeamEmitter,
# fire it (damaging the player), and NOT arm its shoot timer. Run:
#   godot --headless --script res://tools/test_beam_weapon.gd

const RESULT := "res://tools/_beam_weapon_result.txt"
const Weapon := preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")
const BeamEmitterC := preload("res://scripts/enemies/beam_emitter.gd")
const TargetScript := preload("res://tools/_beam_target.gd")

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

	var dart = load("res://scenes/enemies/enemy_dart.tscn").instantiate()
	dart.auto_rotate = false                  # beam enemies don't spin (would flip forward)
	var mv = StraightDown.new(); mv.speed = 0.0
	dart.movement = mv
	var w = Weapon.new()
	w.fire_pattern = Weapon.FirePattern.BEAM
	w.beam_idle = 0.05; w.beam_windup = 0.05; w.beam_firing = 0.5; w.beam_cooldown = 0.1
	w.beam_aim_mode = BeamEmitterC.AimMode.LOCAL_FORWARD
	w.beam_forward_local = Vector2(0, 1)       # straight down
	w.beam_reach = 300.0; w.beam_dps = 40.0; w.beam_hit_radius = 8.0
	w.beam_emitter_offset = Vector2.ZERO
	dart.shoot_pattern = w
	world.add_child(dart)
	dart.start(Vector2(240, 40))

	var tgt := Node2D.new()
	tgt.set_script(TargetScript)
	tgt.position = Vector2(240, 130)           # directly below, in the beam
	root.add_child(tgt)
	tgt.add_to_group("player")

	# beam emitter attached?
	if dart._beam == null or not is_instance_valid(dart._beam):
		_fail("no BeamEmitter attached for beam weapon")
	elif not dart._beam.has_method("is_firing"):
		_fail("attached node is not a BeamEmitter")

	# shoot timer must NOT be running (beam is continuous, not discrete)
	if dart.has_node("ShootTimer") and not dart.get_node("ShootTimer").is_stopped():
		_fail("ShootTimer armed for a beam weapon (should be skipped)")

	# tick the beam through windup into firing; target should take damage.
	if dart._beam != null and is_instance_valid(dart._beam):
		for i in 40:
			dart._beam._process(DT)
	if tgt.hits <= 0:
		_fail("beam weapon dealt no damage to the player target")

	_lines.append("beam attached=%s ; target hits=%d" % [str(dart._beam != null), tgt.hits])
	_lines.append("BEAM WEAPON: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
