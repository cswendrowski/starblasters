extends SceneTree

# Crystal + Strafer on-lane migration (2026-06-08). Both now extend enemy_core with movement
# patterns (pendulum / strafe_run) + weapons. Spawn each with a dummy player present, tick, and
# assert they move on the pattern (no crash, no legacy-anchor fallback) and carry the right weapon.
# Work runs on the first _process frame so _ready + manual ticks fire.
# Run: godot --headless --script res://tools/test_crystal_strafer.gd

const RESULT := "res://tools/_crystal_strafer_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Weapon := preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const CRYSTAL := "res://scenes/enemies/core/enemy_crystal.tscn"
const STRAFER := "res://scenes/enemies/factions/corporate/enemy_strafer.tscn"

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	# Dummy player in the "player" group so find_player() works.
	var player := Node2D.new()
	player.add_to_group("player")
	player.position = Vector2(Lanes.lane_center(3), 210.0)
	root.add_child(player)
	var dt := 1.0 / 60.0

	# --- Crystal: pendulum + spread5, fires on phase ---
	var cps: PackedScene = load(CRYSTAL)
	var c = cps.instantiate()
	root.add_child(c)
	c.movement = Roster.make_movement({"movement": "pendulum"})
	c.shoot_pattern = Roster.make_shoot({"shoot": "spread5", "bullet_variant": Roster.BV_SpreadPellet})
	c.start(Vector2(Lanes.lane_center(3), 16.0))
	var c_y0: float = c.position.y
	for _i in range(120):
		if is_instance_valid(c): c._process(dt)
	if not is_instance_valid(c):
		lines.append("FAIL crystal freed unexpectedly"); fails += 1
	elif c.position.y <= c_y0 + 20.0:
		lines.append("FAIL crystal did not dive (y0=%.0f y=%.0f)" % [c_y0, c.position.y]); fails += 1
	else:
		lines.append("crystal dove to y=%.0f, fire_on_phase=%s" % [c.position.y, c.fire_on_phase])

	# --- Strafer: strafe_run + nose weapon (Aim.FORWARD) ---
	var sps: PackedScene = load(STRAFER)
	var s = sps.instantiate()
	root.add_child(s)
	s.movement = Roster.make_movement({"movement": "strafe_run"})
	s.shoot_pattern = Roster.make_shoot({"shoot": "nose", "bullet_variant": Roster.BV_SpreadPellet})
	s.start(Vector2(Lanes.lane_center(1), 16.0))
	var s_p0: Vector2 = s.position
	for _i in range(60):
		if is_instance_valid(s): s._process(dt)
	if not is_instance_valid(s):
		lines.append("FAIL strafer freed unexpectedly"); fails += 1
	elif s.position.distance_to(s_p0) < 10.0:
		lines.append("FAIL strafer did not move (%.0f,%.0f)" % [s.position.x, s.position.y]); fails += 1
	else:
		lines.append("strafer moved to (%.0f,%.0f)" % [s.position.x, s.position.y])
	# Weapon must be a FORWARD-aim unified Weapon.
	if s.shoot_pattern == null or not (s.shoot_pattern is Weapon):
		lines.append("FAIL strafer weapon is not a unified Weapon"); fails += 1
	elif s.shoot_pattern.aim != Weapon.Aim.FORWARD:
		lines.append("FAIL strafer weapon aim != FORWARD"); fails += 1
	else:
		lines.append("strafer weapon = Weapon(FORWARD)")

	lines.append("CRYSTAL+STRAFER: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true
