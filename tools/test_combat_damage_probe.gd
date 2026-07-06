extends SceneTree

# Ground-truth probe: boot the REAL combat scene (main.tscn), give the player an
# effectively infinite shield pool so it keeps absorbing, then log the MAGNITUDE of
# every per-frame shield drop along with what was overlapping the player and the i-frame
# state. Each drop is one deduped take_damage application (the 0.1s i-frame allows at most
# one per frame), so the drop size == the per-hit amount. A histogram of drop sizes tells
# us whether live enemy fire drains 1 or 2 per hit — the actual "double damage?" question.

const MAIN_SCENE := "res://scenes/main.tscn"

var _player = null
var _last_shield: int = 0
var _hist: Dictionary = {}          # delta -> count
var _samples: Array = []            # first N drops, with context
var _frames: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(MAIN_SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(1.0).timeout          # let intro/settle finish

	_player = _find(inst, "take_damage")
	if _player == null:
		print("[probe] FAIL: no player"); quit(1); return
	_player.set("invincible", false)
	_player.set("max_shield", 100000)
	_player.set("shield", 100000)
	_last_shield = int(_player.shield)
	# Keep it out of harm's "death": huge hull too, so shield stays the meter under test.
	_player.set("max_hull", 100000)
	_player.set("hull", 100000)

	# Sample for a good window of live combat.
	for i in range(900):                      # ~15s at 60fps
		await physics_frame
		_frames += 1
		if _player == null or not is_instance_valid(_player):
			break
		# Keep topping the pool so a long fight never empties it (still lets us see per-hit drops).
		if int(_player.shield) < 50000:
			_player.set("shield", 100000)
			_last_shield = 100000
		var s: int = int(_player.shield)
		if s < _last_shield:
			var delta: int = _last_shield - s
			_hist[delta] = int(_hist.get(delta, 0)) + 1
			if _samples.size() < 25:
				_samples.append({
					"delta": delta,
					"overlaps": _overlap_groups(),
					"invuln": float(_player._invuln_t),
				})
		_last_shield = int(_player.shield)

	_report()
	quit()


func _overlap_groups() -> String:
	if not _player.has_method("get_overlapping_areas"):
		return "?"
	var tags: Array = []
	for a in _player.get_overlapping_areas():
		if not is_instance_valid(a):
			continue
		var g: String = "bullets" if a.is_in_group("bullets") else ("enemies" if a.is_in_group("enemies") else String(a.name))
		var dmg: String = (" d=%s" % str(a.damage)) if ("damage" in a) else ""
		tags.append(g + dmg)
	return str(tags)


func _report() -> void:
	print("[probe] frames sampled: %d" % _frames)
	print("[probe] per-hit shield-drop histogram (delta -> count):")
	var keys: Array = _hist.keys()
	keys.sort()
	for k in keys:
		print("[probe]    drop %d  x%d" % [int(k), int(_hist[k])])
	print("[probe] first drops with context:")
	for s in _samples:
		print("[probe]    -%d  overlaps=%s  invuln=%.3f" % [int(s["delta"]), s["overlaps"], float(s["invuln"])])
	print("[probe] done")


func _find(n: Node, method: String) -> Node:
	if n.has_method(method):
		return n
	for c in n.get_children():
		var h := _find(c, method)
		if h: return h
	return null
