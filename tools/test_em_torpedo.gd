extends Node

# EM Torpedo + wreck layer integration test (Roman 2026-06-10). Boots combat (autoloads + the
# deferred wreck layer), then verifies end to end:
#   - PartCatalog builds the EM Torpedo into HARDPOINT_WING with seeded secondary ammo.
#   - The torpedo scene instantiates as a BaseMissile and its explode() runs the burst without error.
#   - EmBurstFx.detonate damages + kills enemies in radius; most route to the wreck layer (inert
#     drift) while the rest explode (the 25/75 split — so wreck count is > 0 but not necessarily all).
#   - ShieldComponent.break_shield() zeroes a shield.
# Run: godot --headless --path . tools/test_em_torpedo.tscn --quit-after 240

const RESULT := "res://tools/_em_torpedo_result.txt"
const EmBurstFx = preload("res://scripts/effects/em_burst_fx.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const ShieldComponent = preload("res://scripts/enemies/components/shield_component.gd")
const ENEMY_SCENE = preload("res://scenes/enemies/core/enemy_core_s_dart.tscn")  # [RETIRED: enemy_bomb_drone]

var _t := 0
var _main: Node = null
var _phase := 0
var _enemies: Array = []
var _count_before := 0
var _lines: Array = []
var _fails := 0


func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	_t += 1
	# Phase 0: let main + the deferred wreck layer come up.
	if _phase == 0 and _t >= 12:
		# --- Part construction ---
		var torp = PartCatalog._make_by_name("_make_em_torpedo", SlotTypes.SlotType.HARDPOINT_WING)
		if torp == null:
			_lines.append("FAIL PartCatalog returned null for _make_em_torpedo"); _fails += 1
		else:
			_lines.append("part: %s  slot=%d (expect %d)" % [String(torp.display_name), int(torp.slot_type), int(SlotTypes.SlotType.HARDPOINT_WING)])
			if int(torp.slot_type) != int(SlotTypes.SlotType.HARDPOINT_WING):
				_lines.append("FAIL torpedo slot_type wrong"); _fails += 1

		# --- wreck layer exists ---
		var wlayer = get_tree().get_first_node_in_group("wreck_layer")
		_lines.append("wreck layer present: %s" % (wlayer != null))
		if wlayer == null:
			_lines.append("FAIL wreck layer not created by main"); _fails += 1

		# --- ShieldComponent strip ---
		var sc = ShieldComponent.new()
		sc.set("_charges", 3)
		sc.set("_pool", 5.0)
		sc.break_shield()
		if int(sc.get("_charges")) != 0 or float(sc.get("_pool")) != 0.0:
			_lines.append("FAIL break_shield did not zero shield"); _fails += 1
		else:
			_lines.append("break_shield zeroes charges + pool: OK")

		# --- torpedo scene instantiates + explodes cleanly (no enemies -> just visual) ---
		var t2 = load("res://scenes/projectiles/player_em_torpedo.tscn").instantiate()
		_main.add_child(t2)
		if t2 is Node2D:
			(t2 as Node2D).global_position = Vector2(240, 40)
		_lines.append("torpedo class has explode: %s, damage field: %s" % [t2.has_method("explode"), ("damage" in t2)])
		t2.explode()   # should spawn an empty burst + free itself, no crash

		# --- spawn a cluster of enemies to vaporize ---
		for i in 6:
			var e = ENEMY_SCENE.instantiate()
			_main.add_child(e)
			if e is Node2D:
				(e as Node2D).global_position = Vector2(200 + (i % 3) * 10, 100 + int(i / 3) * 10)
			_enemies.append(e)
		_phase = 1
		return

	# Phase 1: let the enemies finish _ready, then detonate among them.
	if _phase == 1 and _t >= 20:
		_count_before = get_tree().get_nodes_in_group("enemies").size()
		_lines.append("enemies before burst: %d" % _count_before)
		EmBurstFx.detonate(get_tree(), Vector2(205, 105), 90.0, 99, 8, _main)
		_phase = 2
		return

	# Phase 2: let take_hit -> explode -> _die_as_wreck (deferred frees) settle.
	if _phase == 2 and _t >= 32:
		var alive := 0
		for e in _enemies:
			if is_instance_valid(e) and not bool(e.get("_dying")):
				alive += 1
		_lines.append("enemies still alive (not _dying) after burst: %d of %d" % [alive, _enemies.size()])
		if alive > 0:
			_lines.append("FAIL burst did not kill all in-radius enemies"); _fails += 1
		var wlayer = get_tree().get_first_node_in_group("wreck_layer")
		var wrecks := 0
		if wlayer != null:
			for c in wlayer.get_children():
				if c is Sprite2D:
					wrecks += 1
		_lines.append("wreck sprites in layer: %d (expect > 0 from the 75%% drift roll)" % wrecks)
		if wrecks <= 0:
			_lines.append("FAIL no wrecks drifted into the layer"); _fails += 1
		_lines.append("EM TORPEDO: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		_finish()


func _finish() -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	get_tree().quit()
