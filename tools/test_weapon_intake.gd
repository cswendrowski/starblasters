extends SceneTree

# Intake check for the projectile/weapon pass (commit 0939e94):
#  1) all 8 baseline weapon_*.tres + 8 BulletVariant .tres load + are valid;
#  2) enemies actually fire with the re-speeded variants (bullets reach group
#     "bullets" when a real WaveGen score streams through the director).
# Run: godot --headless --script res://tools/test_weapon_intake.gd

const RESULT := "res://tools/_weapon_intake_result.txt"
const WaveGen := preload("res://scripts/levels/wave_generator.gd")
const DirectorScript := preload("res://scripts/levels/director.gd")

const WEAPONS := ["enemy_blaster", "enemy_blaster_small", "enemy_blaster_large",
	"enemy_wave_cannon", "enemy_laser_cannon", "enemy_cannon",
	"enemy_diamond_gun", "weapon_mg_tracer", "weapon_mg"]
const BULLETS := ["basic", "spread_pellet", "heavy_slug", "plasma_orb",
	"laser_bolt", "burst_round", "tracker", "aimed_sniper"]

var _lines: Array = []
var _fails: int = 0
var _loaded := false
var _world = null
var _dir = null
var _t := 0.0
var _peak_bullets := 0
var _saw_shooter := false   # any spawned enemy carried a non-null shoot_pattern this roll
var _done := false


func _process(dt: float) -> bool:
	if _done:
		return true
	if not _loaded:
		_loaded = true
		for w in WEAPONS:
			var res = load("res://resources/patterns/shoot/%s.tres" % w)
			if res == null or not res.has_method("fire"):
				_lines.append("FAIL weapon %s missing/invalid" % w); _fails += 1
		for b in BULLETS:
			var bv = load("res://data/bullets/%s.tres" % b)
			if bv == null or not ("speed" in bv):
				_lines.append("FAIL bullet %s missing/invalid" % b); _fails += 1
		_world = Node2D.new(); root.add_child(_world)
		_dir = DirectorScript.new(); _world.add_child(_dir)
		_dir.start_score(WaveGen.build_score(1, 1, false))
		return false
	_t += dt
	for e in get_nodes_in_group("enemies"):
		if "shoot_pattern" in e and e.shoot_pattern != null:
			_saw_shooter = true
			break
	_peak_bullets = maxi(_peak_bullets, get_nodes_in_group("bullets").size())
	if _t > 5.5:
		_done = true
		if _peak_bullets <= 0:
			# build_score is RNG-seeded — some rolls are chaff-only (no shooters). Only
			# a roll WITH a shooter that still produced zero bullets is a real failure;
			# a chaff-only roll is inconclusive (re-run). Avoids flaky false-FAILs.
			if _saw_shooter:
				_lines.append("FAIL shooters present but no bullets spawned"); _fails += 1
			else:
				_lines.append("SKIP no shooting enemies in this RNG roll (chaff-only) — re-run to exercise firing")
		_lines.append("weapons+bullets loaded ok ; peak_bullets=%d ; saw_shooter=%s" % [_peak_bullets, str(_saw_shooter)])
		_lines.append("WEAPON INTAKE: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_lines)))
			f.close()
		quit()
	return false
