extends Node

# Ship-variant swap test (Roman 2026-06-09): booted via scene-path so autoloads (Run) load. Sets
# Run.ship_variant = 1 (ship B) + a chosen livery, then instantiates main.tscn as a CHILD (mirrors
# SceneTransition.change_scene entering combat — NOT the busy initial scene), and confirms main.gd
# swapped the baked ship A for ship B with its double engine markers + livery honored. Run:
# godot --headless --path . tools/test_ship_swap.tscn --quit-after 120

const RESULT := "res://tools/_ship_swap_result.txt"
var _t := 0
var _main: Node = null
var _done := false

func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
		run.ship_variant = 1
		run.livery_chosen = true
		run.livery_color = Color(0.0, 1.0, 0.0)   # green — distinct from the #ff0000 default
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _t < 10:
		return
	_done = true
	var lines: Array = []
	var fails := 0
	var player = _main.get_node_or_null("Player")
	if player == null or not is_instance_valid(player):
		lines.append("FAIL no Player in main"); fails += 1
		_finish(lines, fails); return
	# Ship B has EngineL + EngineR (ship A has a single Engine). Confirm the B node was installed.
	var has_l := player.get_node_or_null("EngineL") != null
	var has_r := player.get_node_or_null("EngineR") != null
	var has_single := player.get_node_or_null("Engine") != null
	lines.append("markers: EngineL=%s EngineR=%s Engine=%s" % [has_l, has_r, has_single])
	if not (has_l and has_r):
		lines.append("FAIL expected ship B double engine markers"); fails += 1
	# Body texture should be the B body sheet.
	var ship = player.get_node_or_null("Ship")
	var tex_path := ""
	if ship != null and ship.texture != null:
		tex_path = ship.texture.resource_path
	lines.append("body texture: %s" % tex_path)
	if not tex_path.contains("player_ship_b"):
		lines.append("FAIL expected player_ship_b body texture"); fails += 1
	# Livery tint should be the chosen green, not the seed-random fallback.
	var livery = ship.get_node_or_null("Livery") if ship != null else null
	var tint = null
	if livery != null and livery.material != null:
		tint = livery.material.get_shader_parameter("tint_color")
	lines.append("livery tint: %s" % str(tint))
	if tint == null or tint.g < 0.9 or tint.r > 0.1:
		lines.append("FAIL livery tint not the chosen green"); fails += 1
	# Engine trail attached (single Engine* lookup): a child EngineTrailFx-ish node exists.
	lines.append("SHIP SWAP: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines, fails)

func _finish(lines: Array, _fails: int) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
