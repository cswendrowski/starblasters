extends RefCounted

# Asteroid Stronghold — shared building PALETTE (Roman 2026-07-13). Used by BOTH the runtime scene
# (asteroid_stronghold.gd) and the editor (asteroid_stronghold_editor.gd) + the field (stronghold_field.gd).
#
# SELF-DISCOVERING (2026-07-13): the placeable buildings are the Enemy Bench's "Buildings" category —
# i.e. every roster entry whose scene lives under scenes/enemies/ground/ (the exact rule the bench uses,
# enemy_bench.gd::_group_of → "/ground/" ⇒ "Buildings"). So new stronghold buildings dropped into that
# folder and registered in enemy_roster.gd appear here automatically — no hand-maintained list.
#
# A building's weapon lives in the ROSTER (not its scene), so spawning one with a working turret mirrors
# the Enemy Bench's order of ops (enemy_bench.gd::_spawn_current): set movement=null + mounts=
# make_mount_specs(dicts) BEFORE add_child, then start(offset); offscreen_mode=NONE + slot_weight=0 (the
# destructible_part.gd parented-part pattern) so it rides the rock and never self-recycles.

const EnemyRoster := preload("res://scripts/levels/enemy_roster.gd")
const EnemyBase := preload("res://scripts/enemies/enemy_base.gd")

const GROUND_DIR := "/ground/"   # the Enemy Bench's "Buildings" group = any roster scene under here

# Lazily built {type_key: scene_path} + ordered key list, discovered from the roster. Key = scene
# filename minus ".tscn" and a leading "enemy_" — stable, and matches the keys the prefab editor already
# saved (e.g. enemy_square_turret.tscn → "square_turret", building_round_tank.tscn → "building_round_tank").
static var _scenes: Dictionary = {}
static var _order: Array = []

# Retired/renamed buildings: old prefab type keys → their replacement, so existing prefabs keep working
# after an art swap instead of silently dropping the building (round_tank/round_glass were replaced by
# bunker_tank/bunker_glass, 2026-07-13). Resolved in is_type/scene_for/label_for.
const ALIASES := {
	"building_round_tank": "building_bunker_tank",
	"building_round_glass": "building_bunker_glass",
	"building_square_landing_pad": "building_landing_pad_small",   # pad size split 2026-07-17
}


static func _resolve_key(type_key: String) -> String:
	return String(ALIASES.get(type_key, type_key))


# One-time scan of the roster for ground-structure entries. Safe to cache: ENTRIES is a const, so it
# can only change via a script edit, which restarts the run (and clears these statics) anyway.
static func _scan() -> void:
	if not _order.is_empty():
		return
	for e in EnemyRoster.ENTRIES:
		if not (e is Dictionary):
			continue
		var path := String(e.get("scene", ""))
		if not path.to_lower().contains(GROUND_DIR):
			continue
		var key := _key_for(path)
		if key == "" or _scenes.has(key):
			continue
		_scenes[key] = path
		_order.append(key)


static func _key_for(path: String) -> String:
	return path.get_file().trim_suffix(".tscn").trim_prefix("enemy_")


# Ordered building type keys (roster order) — the editor brush palette.
static func types() -> Array:
	_scan()
	return _order


static func is_type(type_key: String) -> bool:
	_scan()
	return _scenes.has(_resolve_key(type_key))


static func scene_for(type_key: String) -> String:
	_scan()
	return String(_scenes.get(_resolve_key(type_key), ""))


# Short brush label derived from the key: "square_turret" → "Square Turret",
# "building_round_tank" → "Round Tank".
static func label_for(type_key: String) -> String:
	var out := ""
	for w in _resolve_key(type_key).trim_prefix("building_").split("_", false):
		var s := String(w)
		if s == "":
			continue
		out += s.substr(0, 1).to_upper() + s.substr(1) + " "
	out = out.strip_edges()
	return out if out != "" else type_key


# The roster mount dicts for a building type — the SINGLE source of truth for its weapon
# (entry_for_scene returns the raw roster entry incl. its "mounts"). [] for the plain buildings.
static func mounts_for(type_key: String) -> Array:
	var path := scene_for(type_key)
	if path == "":
		return []
	var entry: Dictionary = EnemyRoster.entry_for_scene(path)
	var m: Variant = entry.get("mounts", [])
	return m if m is Array else []


# Spawn ONE building as a static, parented child at `local_offset` (relative to `parent`'s origin).
# Movement is nulled so it holds position (a null-movement enemy_core stays put and still fires);
# mounts come from the roster; offscreen self-recycle is disabled so it rides the parent. Returns the
# instance, or null if the type is unknown / the scene is bad.
static func spawn(type_key: String, parent: Node, local_offset: Vector2, rot_deg: float = 0.0) -> Node:
	var path := scene_for(type_key)
	if path == "":
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	# BEFORE add_child (the director/bench contract): kill the scene's authored drift, realize mounts.
	if "movement" in inst:
		inst.movement = null
	var md: Array = mounts_for(type_key)
	if "mounts" in inst and not md.is_empty():
		inst.mounts = EnemyRoster.make_mount_specs(md)
	if inst is Node2D:
		(inst as Node2D).position = local_offset
	parent.add_child(inst)
	# start() inits the (null) movement + presets facing; mounts arm via enemy_base._ready's deferral.
	if inst.has_method("start"):
		inst.start(local_offset)
	# Parented-part flags (destructible_part.gd): never self-recycle / self-offscreen — ride the rock.
	if "offscreen_mode" in inst:
		inst.offscreen_mode = EnemyBase.OffscreenMode.NONE
	if "slot_weight" in inst:
		inst.slot_weight = 0
	# Orientation: buildings are auto_rotate=false top-down structures, so their facing stays where set
	# (start()/_preset_spawn_facing is a no-op for them). SNAP to 90° steps here so nearest-filter pixels
	# rotate losslessly (no marring) no matter where rot_deg came from. 0 = the scene default (unchanged).
	if inst is Node2D:
		(inst as Node2D).rotation_degrees = snappedf(rot_deg, 90.0)
	return inst
