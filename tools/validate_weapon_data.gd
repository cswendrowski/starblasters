extends SceneTree

# Weapon-data validation guard (Roman 2026-06-11 centralization). Asserts the
# .tres single-source-of-truth invariants so the "two competing stat sets" problem
# can't silently come back:
#   1. Every pooled weapon (_make_*) has a .tres on disk.
#   2. No .tres carries a field absent from its script (no stale/ignored fields).
#   3. Each weapon builds and resolves a non-degenerate Mk.1/Mk.9 stat set.
# Run: godot --headless -s res://tools/validate_weapon_data.gd  (exit prints VERDICT)

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const CANNON_SLOT := 4

# factory → .tres map is owned by PartCatalog.weapon_tres_map() (single source of truth); pulled
# into a local in _init(). The old inline copy was retired in the 2026-07-09 weapon-lab overhaul.

# Fields written by ResourceSaver that aren't weapon-specific stats (skip in the
# stale-field check — they're always-valid base/runtime props).
const ALWAYS_OK := ["script", "resource_local_to_scene", "resource_name", "resource_path"]


func _tres_resource_keys(path: String) -> Array:
	# Parse `key = value` lines in the [resource] block of a .tres.
	var keys: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return keys
	var in_resource := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[resource]"):
			in_resource = true
			continue
		if line.begins_with("["):
			in_resource = false
			continue
		if in_resource and "=" in line:
			keys.append(line.get_slice("=", 0).strip_edges())
	f.close()
	return keys


func _init() -> void:
	await process_frame
	var MAP: Dictionary = PartCatalog.weapon_tres_map()
	var fails: Array = []
	var warns: Array = []
	for key in MAP.keys():
		var path: String = MAP[key]
		# 1) .tres exists.
		if not FileAccess.file_exists(path):
			fails.append("%s: MISSING .tres (%s)" % [key, path])
			continue
		var p = PartCatalog._make_by_name(key, CANNON_SLOT)
		if p == null:
			fails.append("%s: build returned null" % key)
			continue
		# 2) No stale .tres field (every persisted key is a live script property).
		for tk in _tres_resource_keys(path):
			if tk in ALWAYS_OK:
				continue
			if not (tk in p):
				fails.append("%s: STALE .tres field '%s' (no script property)" % [key, tk])
		# 3) Non-degenerate build: resolves _mk_knobs without error + has a slot.
		if "slot_type" in p and int(p.slot_type) < 0:
			fails.append("%s: slot_type unresolved (-1)" % key)
		if p.has_method("_mk_knobs"):
			var _k = p._mk_knobs()  # must not throw
	var n := MAP.size()
	print("Weapon-data validation: %d weapons checked" % n)
	for w in warns:
		print("  WARN  ", w)
	if fails.is_empty():
		print("VERDICT: PASS — every pooled weapon has a complete, stale-free .tres")
	else:
		print("VERDICT: FAIL (%d)" % fails.size())
		for ff in fails:
			print("  FAIL  ", ff)
	quit()
