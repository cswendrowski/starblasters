extends SceneTree

# M6c zealot batch: manta (drifter replacement), retro/run (firecore-core ships),
# bloom (firecore drone re-skin), helix (firecore cruiser rework). Verifies the
# decorative core, the always-drop-firecore component, the helix beam turret +
# speed clamp, markers, and faction tags.
# Run: godot --headless --script res://tools/test_zealot_units.gd

const RESULT := "res://tools/_zealot_units_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Factions := preload("res://scripts/levels/factions.gd")

const CORE := "res://scenes/enemies/factions/zealot/firecore_core.tscn"
const MANTA := "res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn"
const RETRO := "res://scenes/enemies/factions/zealot/enemy_z_s_acolyte.tscn"
const RUN := "res://scenes/enemies/factions/zealot/enemy_z_s_drifter.tscn"
const BLOOM := "res://scenes/enemies/factions/zealot/enemy_z_s_bloom.tscn"
const HELIX := "res://scenes/enemies/factions/zealot/enemy_z_m_helix.tscn"
const SWORD := "res://scenes/enemies/factions/zealot/enemy_z_s_sword.tscn"

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _inst(path: String) -> Node:
	var n = load(path).instantiate()
	root.add_child(n)
	return n


func _has(n: Node, child: String) -> bool:
	return n.get_node_or_null(child) != null


# True if the enemy carries ANY marker matching the glob (e.g. "Muzzle*" covers the
# MuzzleL/MuzzleR marker-naming scheme, 2026-06-28). find_children globs are case-sensitive.
func _has_marker(n: Node, glob: String) -> bool:
	return n.find_children(glob, "Marker2D", true, false).size() > 0


# True if the enemy has a baked always-on DEATH firecore drop. Since the mounts-migration
# (2026-07-07) a baked firecore is a Kind.ENTITY MountSpec in `mounts`, realized by
# _attach_mounts into a MountComponent (spec.trigger DEATH, spec.emit_chance 1.0) that lives in
# the live `_components` list. The old EmitterComponent shape (c.trigger/c.chance) is gone.
func _always_drops(n: Node) -> bool:
	for c in _live_components(n):
		if c == null or not ("spec" in c) or c.spec == null:
			continue
		var sp = c.spec
		if "trigger" in sp and "emit_chance" in sp and int(sp.trigger) == 2 and float(sp.emit_chance) >= 1.0:
			return true
	return false


# Live components after _ready() realized the `mounts` array (firecore drops now ride here as
# MountComponents). Falls back to the authored `components` array when `_components` is absent.
func _live_components(n: Node) -> Array:
	if "_components" in n and n._components != null:
		return n._components
	if "components" in n and n.components != null:
		return n.components
	return []


const FIRECORE_PATH := "res://scenes/enemies/factions/zealot/firecore_hazard.tscn"

# Count DEATH emitters that drop a firecore (baked guaranteed + overlay chance both). Both are now
# ENTITY MountComponents (spec.trigger DEATH, spec.payload_scene = firecore) in the live components.
func _count_firecore_drops(n: Node) -> int:
	var c := 0
	for comp in _live_components(n):
		if comp == null or not ("spec" in comp) or comp.spec == null:
			continue
		var sp = comp.spec
		if "trigger" in sp and "payload_scene" in sp and int(sp.trigger) == 2 \
				and sp.payload_scene != null and str(sp.payload_scene.resource_path) == FIRECORE_PATH:
			c += 1
	return c


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# --- 1) Decorative core: Core sprite is HDR-bright so the WorldEnvironment
	# bloom glows it (the old GlowShaderFx halo was retired, Roman 2026-06-20) ----
	var core := _inst(CORE)
	var core_spr := core.get_node_or_null("Core") as CanvasItem
	if core_spr == null:
		_fail("firecore_core missing its Core sprite")
	elif maxf(core_spr.modulate.r, core_spr.modulate.g) < 1.5:
		_fail("firecore_core Core sprite not HDR-bright (modulate must clear the env glow_hdr_threshold 1.5)")
	core.free()

	# --- 2) Manta: central muzzle, no core ------------------------------------
	var manta := _inst(MANTA)
	if not _has(manta, "Muzzle"):
		_fail("manta missing central Muzzle")
	if manta.get_node_or_null("FirecoreCore") != null:
		_fail("manta should have NO core")
	manta.free()

	# --- 3) Retro/Run: core + always-drops-firecore ---------------------------
	for p in [RETRO, RUN]:
		var n := _inst(p)
		if not _has(n, "FirecoreCore"):
			_fail("%s missing FirecoreCore" % p)
		if not _always_drops(n):
			_fail("%s should ALWAYS drop a firecore (DEATH chance 1.0 component)" % p)
		n.free()
	# Retro fires; Run does not. (Muzzle markers follow the MuzzleL/MuzzleR naming scheme.)
	var retro2 := _inst(RETRO)
	if not _has_marker(retro2, "Muzzle*"):
		_fail("retro (gunner) missing a Muzzle marker")
	retro2.free()
	var run2 := _inst(RUN)
	if _has_marker(run2, "Muzzle*"):
		_fail("run should have no Muzzle marker (unarmed)")
	run2.free()

	# --- 4) Bloom (firecore drone re-skin): core + sprite ---------------------
	var bloom := _inst(BLOOM)
	if not _has(bloom, "FirecoreCore"):
		_fail("bloom missing FirecoreCore")
	if not _has(bloom, "Sprite2D"):
		_fail("bloom missing Sprite2D body")
	bloom.free()

	# --- 5) Helix: beam turret + two cores + drop + speed clamp ----------------
	var helix := _inst(HELIX)
	if not _has_marker(helix, "Turret*"):
		_fail("helix missing its Turret marker")
	if helix.get_node_or_null("FirecoreCoreTop") == null or helix.get_node_or_null("FirecoreCoreBot") == null:
		_fail("helix should carry two cores")
	if not _always_drops(helix):
		_fail("helix should drop firecores on death")
	# Speed clamp: the helix holds every speed-like field of its rolled movement to <= 60 px/s
	# (SPEED_CAP in enemy_firecore_cruiser). straight_down carries no bindable `speed` anymore
	# (it reads move_speed off the enemy), so the clamp iterates whatever *_speed floats exist.
	helix.start(Vector2(240, 60))
	if helix._pattern != null:
		for prop in helix._pattern.get_property_list():
			if int(prop.get("type", -1)) != TYPE_FLOAT:
				continue
			var pn: String = str(prop.get("name", ""))
			if (pn == "speed" or pn == "down_speed" or pn.ends_with("_speed")) and float(helix._pattern.get(pn)) > 60.0:
				_fail("helix did not clamp movement '%s' to ~1px/f (got %.0f)" % [pn, helix._pattern.get(pn)])
	helix.free()

	# --- 5b) Sword: multiple muzzles + rear core, no death-drop ---------------
	var sword := _inst(SWORD)
	if sword.all_muzzle_pos().size() < 2:
		_fail("sword should have multiple muzzles (got %d)" % sword.all_muzzle_pos().size())
	if not _has(sword, "FirecoreCore"):
		_fail("sword missing rear FirecoreCore")
	if _always_drops(sword):
		_fail("sword core is decorative — should NOT bake a death firecore drop")
	sword.free()

	# --- 6) Faction tags (all zealot-exclusive now; manta no longer universal) -
	for p in [MANTA, RETRO, RUN, SWORD]:
		if not Factions.allowed_in(p, Factions.Id.ZEALOT):
			_fail("%s should be allowed in zealot" % p)
		if Factions.allowed_in(p, Factions.Id.CORPORATE):
			_fail("%s should be zealot-exclusive" % p)
	if "res://scenes/enemies/core/enemy_drifter.tscn" in Factions.ENEMY_TAGS:
		_fail("enemy_drifter.tscn should be retired from ENEMY_TAGS")

	# --- 6b) Overlay does not stack onto a guaranteed firecore dropper --------
	# apply(ZEALOT) adds a CHANCE firecore drop — but NOT to enemies that already
	# bake a GUARANTEED one (retro/run/helix). manta (no baked drop) still gets it.
	# Factions.apply MUST run BEFORE add_child (its contract — enemy_base._ready dups the attached
	# components), exactly as director._spawn_enemy does. A baked firecore lives in `components` as a
	# MountComponent; the overlay's stacking guard scans `components` and skips retro's baked drop.
	var r3 = load(RETRO).instantiate()
	Factions.apply(Factions.Id.ZEALOT, r3)
	root.add_child(r3)
	if _count_firecore_drops(r3) != 1:
		_fail("retro should have exactly 1 firecore drop after overlay (got %d)" % _count_firecore_drops(r3))
	r3.free()
	var m3 = load(MANTA).instantiate()
	Factions.apply(Factions.Id.ZEALOT, m3)
	root.add_child(m3)
	if _count_firecore_drops(m3) != 1:
		_fail("manta (no baked drop) should get the overlay firecore (got %d)" % _count_firecore_drops(m3))
	m3.free()

	# --- 7) Helix carries multiple roster variants (the capital appears several ways) ---------
	# The movement keys were consolidated to "straight" (locomotion shape-key cleanup), so assert
	# the helix has 2+ roster entries rather than pinning the retired side_traverse/loiter/lane_drift
	# key names.
	var helix_entries: int = 0
	for e in Roster.ENTRIES:
		if str(e.get("scene", "")) == HELIX:
			helix_entries += 1
	if helix_entries < 2:
		_fail("helix should have 2+ roster variants (got %d)" % helix_entries)

	_lines.append("ZEALOT UNITS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
