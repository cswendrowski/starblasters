extends SceneTree

# FlyoverPlanner unit checks (Roman 2026-07-18): determinism (same inputs → identical dict),
# the eligibility table (gas planets never plan, obj_kind!=0 never plans, ~40% flyover rate),
# jitter clamps hold over many seeds, and the desert→Desert 2 / NoAtmosphere→Moonsteroid preset
# mapping. Pure static funcs, so this runs in _init (no main-loop frames needed).
# Run: godot --path . --headless -s res://tools/test_flyover_planner.gd
const Planner = preload("res://scripts/parallax/flyover_planner.gd")
const Backdrop = preload("res://scripts/parallax/flyover_backdrop.gd")


func _init() -> void:
	var fails: Array = []
	_check_determinism(fails)
	_check_eligibility(fails)
	_check_chance(fails)
	_check_jitter_clamps(fails)
	_check_mapping(fails)
	if fails.is_empty():
		print("VERDICT: PASS — flyover planner deterministic + eligibility/jitter/mapping intact")
		quit(0)
	else:
		for fx in fails:
			print("FAIL: ", fx)
		print("VERDICT: FAIL")
		quit(1)


func _stellar(ptype: int, seed_val: int) -> Dictionary:
	return {"obj_kind": 0, "planet_type": ptype, "planet_seed": seed_val}


# First non-empty plan across a scan of node ids (flyover is a per-node chance roll).
func _first_plan(stellar: Dictionary, run_seed: int) -> Dictionary:
	for i in 300:
		var p: Dictionary = Planner.plan(stellar, run_seed, "scan_%d" % i)
		if not p.is_empty():
			return p
	return {}


func _check_determinism(fails: Array) -> void:
	var stellar := _stellar(3, 99999)   # Terran, eligible
	var run_seed := 12345
	var pass_id := ""
	for i in 200:
		var nid := "node_%d" % i
		if not Planner.plan(stellar, run_seed, nid).is_empty():
			pass_id = nid
			break
	if pass_id == "":
		fails.append("determinism: found no passing node id")
		return
	var a: Dictionary = Planner.plan(stellar, run_seed, pass_id)
	var b: Dictionary = Planner.plan(stellar, run_seed, pass_id)
	if not _deep_eq(a, b):
		fails.append("determinism: same inputs produced differing dicts")


func _check_eligibility(fails: Array) -> void:
	# Gas planets (types 4 and 6) never plan, no matter the node.
	for t in [4, 6]:
		var planned := false
		for i in 60:
			if not Planner.plan(_stellar(t, i * 7 + 1), 777, "gas_%d" % i).is_empty():
				planned = true
				break
		if planned:
			fails.append("eligibility: gas planet type %d produced a flyover" % t)
	# obj_kind != 0 never plans (asteroid/stronghold POIs).
	for i in 60:
		var s := {"obj_kind": (1 + i % 2), "planet_type": 3, "planet_seed": i}
		if not Planner.plan(s, 777, "nonplanet_%d" % i).is_empty():
			fails.append("eligibility: obj_kind!=0 produced a flyover")
			break


func _check_chance(fails: Array) -> void:
	var stellar := _stellar(3, 4242)
	var n := 400
	var hits := 0
	for i in n:
		if not Planner.plan(stellar, 20260718, "chance_%d" % i).is_empty():
			hits += 1
	var frac := float(hits) / float(n)
	if absf(frac - Planner.FLYOVER_CHANCE) > 0.07:
		fails.append("chance: %.3f over %d ids not within 0.07 of %.2f" % [frac, n, Planner.FLYOVER_CHANCE])


func _check_jitter_clamps(fails: Array) -> void:
	var sampled := 0
	for i in 200:
		var p: Dictionary = Planner.plan(_stellar(3 + (i % 2) * 4, i * 13 + 1), i * 31 + 7, "j_%d" % i)
		if p.is_empty():
			continue
		sampled += 1
		var rc: float = float(p["river_cutoff"])
		if rc < 0.05 or rc > 0.95:
			fails.append("jitter: river_cutoff %.3f out of [0.05,0.95]" % rc)
			break
		var co: float = float(p["cloud_opacity"])
		if co < 0.0 or co > 1.0:
			fails.append("jitter: cloud_opacity %.3f out of [0,1]" % co)
			break
		var cc: float = float(p["cloud_coverage"])
		if cc < 0.1 or cc > 0.9:
			fails.append("jitter: cloud_coverage %.3f out of [0.1,0.9]" % cc)
			break
	if sampled == 0:
		fails.append("jitter: no flyover plans sampled to check clamps")


func _check_mapping(fails: Array) -> void:
	# Desert (V3 type 1) -> Desert 2 preset (surface_type 3).
	var d: Dictionary = _first_plan(_stellar(1, 5150), 31337)
	if d.is_empty():
		fails.append("mapping: no Desert plan found")
	else:
		var idx := Backdrop.PRESET_NAMES.find("Desert 2")
		if int(d["preset"]) != idx:
			fails.append("mapping: desert preset index %d != Desert 2 (%d)" % [int(d["preset"]), idx])
		if int(d["surface_type"]) != int(Backdrop.PRESETS["Desert 2"]["type"]):
			fails.append("mapping: desert surface_type %d != %d" % [int(d["surface_type"]), int(Backdrop.PRESETS["Desert 2"]["type"])])
	# NoAtmosphere (V3 type 2) -> Moonsteroid preset (surface_type 5).
	var m: Dictionary = _first_plan(_stellar(2, 8080), 31337)
	if m.is_empty():
		fails.append("mapping: no Moonsteroid plan found")
	else:
		var midx := Backdrop.PRESET_NAMES.find("Moonsteroid")
		if int(m["preset"]) != midx:
			fails.append("mapping: moon preset index %d != Moonsteroid (%d)" % [int(m["preset"]), midx])
		if int(m["surface_type"]) != int(Backdrop.PRESETS["Moonsteroid"]["type"]):
			fails.append("mapping: moon surface_type %d != %d" % [int(m["surface_type"]), int(Backdrop.PRESETS["Moonsteroid"]["type"])])


func _deep_eq(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for k in a:
				if not b.has(k):
					return false
				if not _deep_eq(a[k], b[k]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in a.size():
				if not _deep_eq(a[i], b[i]):
					return false
			return true
		_:
			return a == b
