extends Node

# Primary-fire regression test (Roman 2026-06-10: "Z does nothing with the base blaster"). Boots
# combat, force-calls the player's per-frame fire path the way _process does for the DEFAULT
# loadout (Energy Blaster, weapon_style ENERGY), and asserts bullets actually spawn. Guards the
# fire_held -> fire_primary() wiring that the weapons rework broke (fire call folded into style
# branches so non-AC/minigun styles never fired). Run:
# godot --headless --path . tools/test_fire_primary.tscn --quit-after 120

const RESULT := "res://tools/_fire_primary_result.txt"
var _t := 0
var _main: Node = null
var _p: Node = null
var _done := false
var _fired_frames := 0

func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _p == null and _main != null:
		_p = _main.get_node_or_null("Player")
	if _t < 8 or _p == null:
		return
	# Simulate held fire for ~20 frames by pressing the action (the player's _process reads
	# Input.is_action_pressed("shoot") each frame).
	if _fired_frames == 0:
		Input.action_press("shoot")
	_fired_frames += 1
	if _fired_frames < 20:
		return
	Input.action_release("shoot")
	_done = true
	var lines: Array = []
	var fails := 0
	# The default loadout = Energy Blaster (ENERGY style). Bullets parent to the bullet container
	# (root in combat). Count live "bullets"-group nodes / Bullet-named children anywhere.
	var bullets := 0
	for n in get_tree().get_nodes_in_group("bullets"):
		bullets += 1
	# Fallback: scan the tree for Bullet-prefixed Area2Ds if the group is unused by player bullets.
	if bullets == 0:
		var stack: Array = [get_tree().root]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			if String(nd.name).begins_with("Bullet") or String(nd.name).begins_with("@Bullet"):
				bullets += 1
			for c in nd.get_children():
				stack.append(c)
	lines.append("weapon_style=%d (0=ENERGY)  bullets after 20 held frames: %d" % [int(_p.weapon_style), bullets])
	if int(_p.weapon_style) != 0:
		lines.append("WARN default loadout is not ENERGY?")
	if bullets <= 0:
		lines.append("FAIL base blaster did not fire (no bullets spawned)"); fails += 1
	lines.append("FIRE PRIMARY: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
