extends SceneTree

# M6c zealot batch: manta (drifter replacement), retro/run (firecore-core ships),
# bloom (firecore drone re-skin), helix (firecore cruiser rework). Verifies the
# decorative core, the always-drop-firecore component, the helix beam turret +
# speed clamp, markers, and faction tags.
# Run: godot --headless --script res://tools/test_zealot_units.gd

const RESULT := "res://tools/_zealot_units_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")
const Factions := preload("res://scripts/levels/factions.gd")
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")

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


# True if the enemy has a baked always-on DEATH firecore drop component.
func _always_drops(n: Node) -> bool:
	if not ("components" in n):
		return false
	for c in n.components:
		if c == null:
			continue
		if "trigger" in c and "chance" in c and int(c.trigger) == 2 and float(c.chance) >= 1.0:
			return true
	return false


const FIRECORE_PATH := "res://scenes/enemies/factions/zealot/firecore_hazard.tscn"

# Count DEATH emitters that drop a firecore (baked guaranteed + overlay chance both).
func _count_firecore_drops(n: Node) -> int:
	if not ("components" in n):
		return 0
	var c := 0
	for comp in n.components:
		if comp == null:
			continue
		if "trigger" in comp and "payload" in comp and int(comp.trigger) == 2 \
				and comp.payload != null and str(comp.payload.resource_path) == FIRECORE_PATH:
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
	# Retro fires; Run does not.
	var retro2 := _inst(RETRO)
	if not _has(retro2, "Muzzle"):
		_fail("retro (gunner) missing Muzzle")
	retro2.free()
	var run2 := _inst(RUN)
	if _has(run2, "Muzzle"):
		_fail("run should have no Muzzle (unarmed)")
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
	if not _has(helix, "HookTurret"):
		_fail("helix missing HookTurret beam")
	if helix.get_node_or_null("FirecoreCoreTop") == null or helix.get_node_or_null("FirecoreCoreBot") == null:
		_fail("helix should carry two cores")
	if not _always_drops(helix):
		_fail("helix should drop firecores on death")
	# Speed clamp: a fast rolled movement is held to <= 60 px/s.
	var fast := StraightDown.new()
	fast.speed = 200.0
	helix.movement = fast
	helix.start(Vector2(240, 60))
	if helix._pattern != null and float(helix._pattern.speed) > 60.0:
		_fail("helix did not clamp movement to ~1px/f (got %.0f)" % helix._pattern.speed)
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
	var r3 = load(RETRO).instantiate()
	root.add_child(r3)
	Factions.apply(Factions.Id.ZEALOT, r3)
	if _count_firecore_drops(r3) != 1:
		_fail("retro should have exactly 1 firecore drop after overlay (got %d)" % _count_firecore_drops(r3))
	r3.free()
	var m3 = load(MANTA).instantiate()
	root.add_child(m3)
	Factions.apply(Factions.Id.ZEALOT, m3)
	if _count_firecore_drops(m3) != 1:
		_fail("manta (no baked drop) should get the overlay firecore (got %d)" % _count_firecore_drops(m3))
	m3.free()

	# --- 7) Helix movement variants in roster ---------------------------------
	var helix_moves: Array = []
	for e in Roster.ENTRIES:
		if str(e.get("scene", "")) == HELIX:
			helix_moves.append(str(e.get("movement", "")))
	for needed in ["side_traverse", "loiter", "lane_drift"]:
		if not (needed in helix_moves):
			_fail("helix missing movement variant '%s'" % needed)

	_lines.append("ZEALOT UNITS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
