extends Node

# Minigun diagnostic (Roman 2026-06-10: "minigun does no damage + no bullet stream"). Boots combat,
# equips the Minigun, spawns an enemy directly above the player, fires the hitscan, and reports:
#   - the applied bullet_damage (is the knob reaching the ship?)
#   - the enemy's health before/after (did it take damage?)
#   - whether a minigun_tracer sprite was created (is the stream drawing?)
# Run: godot --headless --path . tools/test_minigun_diag.tscn --quit-after 120

const RESULT := "res://tools/_minigun_diag_result.txt"
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const ENEMY_SCENE = preload("res://scenes/enemies/core/enemy_bomb_drone.tscn")

var _t := 0
var _main: Node = null
var _p: Node = null
var _enemy: Node = null
var _phase := 0
var _lines: Array = []
var _hp_before := 0


func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
		# Equip the minigun into the cannon slot so it's active.
		var mg = PartCatalog._make_by_name("_make_minigun", SlotTypes.SlotType.CANNON)
		if mg != null:
			if "mark" in mg:
				mg.mark = 1
			run.equip_part(mg)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	_t += 1
	if _p == null and _main != null:
		_p = _main.get_node_or_null("Player")
	if _phase == 0 and _t >= 12 and _p != null:
		_lines.append("weapon_style=%d (MINIGUN expected), bullet_damage=%d (expect 5)" % [int(_p.weapon_style), int(_p.get("bullet_damage"))])
		# Spawn an enemy directly above the player, well inside the column.
		_enemy = ENEMY_SCENE.instantiate()
		_main.add_child(_enemy)
		if _enemy is Node2D:
			(_enemy as Node2D).global_position = (_p as Node2D).global_position + Vector2(0, -40)
		_phase = 1
		return
	if _phase == 1 and _t >= 16:
		_hp_before = int(_enemy.get("health")) if "health" in _enemy else -999
		# Force the cooldown ready + fire the hitscan a few times.
		_p.set("can_shoot", true)
		var tracer_before := _count_tracers()
		for i in 5:
			_p.call("_fire_minigun_hitscan")
			_p.set("can_shoot", true)
		var hp_after := int(_enemy.get("health")) if (is_instance_valid(_enemy) and "health" in _enemy) else -999
		var tracer_after := _count_tracers()
		_lines.append("enemy health: %d -> %d (expect a drop)" % [_hp_before, hp_after])
		_lines.append("minigun_tracer sprites created: %d (expect > 0)" % (tracer_after - tracer_before))
		var fails := 0
		if int(_p.get("bullet_damage")) <= 0:
			_lines.append("FAIL bullet_damage is 0 (knob not applied)"); fails += 1
		if hp_after >= _hp_before:
			_lines.append("FAIL no damage dealt"); fails += 1
		if tracer_after - tracer_before <= 0:
			_lines.append("FAIL no tracer drawn"); fails += 1
		# Also check the Autocannon keeps the machinegun's projectile (not the blaster).
		var ac = PartCatalog._make_by_name("_make_autocannon", SlotTypes.SlotType.CANNON)
		var ac_bullet := "null"
		if ac != null and "bullet_scene" in ac and ac.bullet_scene != null:
			ac_bullet = String(ac.bullet_scene.resource_path)
		_lines.append("autocannon bullet_scene: %s (expect bullet_minigun)" % ac_bullet)
		if not ac_bullet.contains("bullet_minigun"):
			_lines.append("FAIL autocannon not using the machinegun projectile"); fails += 1
		_lines.append("MINIGUN/AUTOCANNON DIAG: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		_finish()


func _count_tracers() -> int:
	# The tracer is now a tiled Line2D (the "beam of bullets"), not a Sprite2D.
	var n := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		var tex: Texture2D = null
		if nd is Line2D:
			tex = (nd as Line2D).texture
		elif nd is Sprite2D:
			tex = (nd as Sprite2D).texture
		if tex != null and String(tex.resource_path).contains("minigun_tracer"):
			n += 1
		for c in nd.get_children():
			stack.append(c)
	return n


func _finish() -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	get_tree().quit()
