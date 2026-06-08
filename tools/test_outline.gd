extends SceneTree

# Enemy hull outline (Roman 2026-06-07). Verifies the 1px outline node is attached
# to ship hulls (behind the hull, glow-mask untouched), skipped for the exceptions
# (firecores / mine munitions), and toggled off while recycling.
# Run: godot --headless --script res://tools/test_outline.gd

const RESULT := "res://tools/_outline_result.txt"

const SHIP := "res://scenes/enemies/factions/privateer/enemy_dart.tscn"   # single-frame hull
const SHIP_GLOW := "res://scenes/enemies/factions/privateer/enemy_p_s_green.tscn"  # 2-frame hull+glow
const FIRECORE := "res://scenes/enemies/factions/zealot/firecore_hazard.tscn"        # excepted
const BOMBLET := "res://scenes/enemies/bomblet.tscn"                 # excepted (if present)

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _inst(path: String) -> Node:
	var n = load(path).instantiate()
	root.add_child(n)
	return n


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# --- Ship hulls get an Outline node ---------------------------------------
	var dart := _inst(SHIP)
	var o1 := dart.get_node_or_null("Outline")
	if o1 == null:
		_fail("ship hull (dart) has no Outline node")
	elif not (o1 is Sprite2D) or o1.material == null:
		_fail("dart Outline should be a Sprite2D with an outline material")
	dart.free()

	# --- 2-frame hull: outlined, drawn BEHIND the hull, glow-mask untouched ----
	var green := _inst(SHIP_GLOW)
	var hull := green.get_node_or_null("Sprite2D")
	var o2 := green.get_node_or_null("Outline")
	var glow := green.get_node_or_null("GlowMask")
	if o2 == null:
		_fail("2-frame ship has no Outline node")
	elif hull != null and o2.get_index() >= hull.get_index():
		_fail("Outline should draw BEFORE the hull (behind it)")
	if glow == null:
		_fail("GlowMask should be untouched/present")
	# Recycle toggle: hidden while faux-parallax.
	if green.has_method("_set_outline_visible"):
		green._set_outline_visible(false)
		if o2 != null and o2.visible:
			_fail("Outline should hide when recycling")
		green._set_outline_visible(true)
		if o2 != null and not o2.visible:
			_fail("Outline should restore after recycling")
	green.free()

	# --- Exceptions get NO outline --------------------------------------------
	var fc := _inst(FIRECORE)
	if fc.get_node_or_null("Outline") != null:
		_fail("firecore hazard should be excepted (no Outline)")
	fc.free()
	if ResourceLoader.exists(BOMBLET):
		var bl := _inst(BOMBLET)
		if bl.get_node_or_null("Outline") != null:
			_fail("bomblet should be excepted (no Outline)")
		bl.free()

	_lines.append("OUTLINE: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
