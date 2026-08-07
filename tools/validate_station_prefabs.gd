extends SceneTree

# Station prefab guard (Roman 2026-07-28) — the authoring contract for
# scenes/enemies/ground/station/prefab_*.tscn, checked without opening the editor.
#
# The "Play Area" Sprite2D in each prefab is an AUTHORING GUIDE: it marks exactly what the player
# will see, so Roman can place structure against a real bound. That makes two things load-bearing:
#
#   1. It must be EXACTLY the live playfield band horizontally (Playfield.X_MIN..X_MAX). A marker
#      even 1px proud biases everything authored flush to it — and the stated workflow is to align
#      the art TO the marker, so a wrong marker silently mis-places the whole prefab.
#   2. It must never ship visible. It's a toggle during authoring; this fails the run if one is
#      left on. (Belt-and-braces: station_section.configure() strips any node named "Play Area"
#      unconditionally at runtime, so a forgotten flag still can't reach the screen — see
#      docs/starbase_assault_design_2026-07-28.md §1.)
#
# Vertical extent is deliberately NOT constrained: this is a scroller, so a marker taller than one
# screen is legitimate (prefab_battle_station uses one to mark its planned extent).
#
# Run: godot --path . --headless -s res://tools/validate_station_prefabs.gd
# Must print "VERDICT: PASS".

const DIR := "res://scenes/enemies/ground/station/"
const MARKER := "Play Area"
const DECK := "Angled Platform"
const EPS := 0.01

var _fails: int = 0
var _warns: int = 0


func _init() -> void:
	print("=== station prefab guard ===")
	print("playfield band: x[%.0f, %.0f] w=%.0f centre %.0f"
		% [Playfield.X_MIN, Playfield.X_MAX, Playfield.W, Playfield.CENTER.x])
	var paths := _prefabs()
	if paths.is_empty():
		print("  FAIL  no prefab_*.tscn found under %s" % DIR)
		_fails += 1
	for p in paths:
		_check(p)
	print("")
	print("VERDICT: %s (%d failures, %d warnings)"
		% ["PASS" if _fails == 0 else "FAIL", _fails, _warns])
	quit(0 if _fails == 0 else 1)


func _prefabs() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.begins_with("prefab_") and f.ends_with(".tscn"):
			out.append(DIR + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _fail(msg: String) -> void:
	print("  FAIL  " + msg)
	_fails += 1


func _warn(msg: String) -> void:
	print("  WARN  " + msg)
	_warns += 1


func _check(path: String) -> void:
	print("")
	print("#### " + path.get_file())
	var ps := load(path) as PackedScene
	if ps == null:
		_fail("does not load as a PackedScene")
		return
	var root := ps.instantiate()
	if root == null:
		_fail("does not instantiate")
		return

	# --- Play Area marker -------------------------------------------------
	var marker: Node = root.get_node_or_null(MARKER)
	if marker == null:
		# find_child so a marker parented deeper still gets caught rather than silently missed
		marker = root.find_child(MARKER, true, false)
		if marker != null:
			_fail("'%s' is not a direct child of the root (found under %s) — configure() strips by root lookup"
				% [MARKER, String(marker.get_parent().name)])
	if marker == null:
		_fail("missing the '%s' marker — nothing pins the authoring bound" % MARKER)
		root.free()
		return
	if not (marker is Sprite2D):
		_fail("'%s' is a %s, expected Sprite2D" % [MARKER, marker.get_class()])
		root.free()
		return

	var spr := marker as Sprite2D
	if spr.visible:
		_fail("'%s' is VISIBLE — it would render over the ground plane in play. Toggle it off."
			% MARKER)
	if spr.texture == null:
		_fail("'%s' has no texture — cannot verify its width" % MARKER)
		root.free()
		return

	# Effective on-screen width, honouring node scale (battle_station scales its marker vertically).
	var tex_w: float = float(spr.texture.get_width())
	var eff_w: float = tex_w * absf(spr.scale.x)
	var centre_x: float = spr.position.x
	if not spr.centered:
		centre_x += eff_w * 0.5
	centre_x += spr.offset.x * spr.scale.x
	var left: float = centre_x - eff_w * 0.5
	var right: float = centre_x + eff_w * 0.5

	print("  marker  w=%.1f (tex %.0f x scale %.3f)  x[%.1f, %.1f]  centre %.1f  visible=%s"
		% [eff_w, tex_w, spr.scale.x, left, right, centre_x, str(spr.visible)])

	if absf(eff_w - Playfield.W) > EPS:
		_fail("marker width %.1f != playfield width %.0f (off by %+.1f)"
			% [eff_w, Playfield.W, eff_w - Playfield.W])
	if absf(centre_x - Playfield.CENTER.x) > EPS:
		_fail("marker centre %.1f != playfield centre %.0f (off by %+.1f)"
			% [centre_x, Playfield.CENTER.x, centre_x - Playfield.CENTER.x])
	if absf(left - Playfield.X_MIN) > EPS or absf(right - Playfield.X_MAX) > EPS:
		_fail("marker spans x[%.1f, %.1f], band is x[%.0f, %.0f]"
			% [left, right, Playfield.X_MIN, Playfield.X_MAX])

	# --- Deck, for information + a band sanity check ----------------------
	var deck: Node = root.find_child(DECK, true, false)
	if deck is TileMapLayer:
		var tml := deck as TileMapLayer
		var r: Rect2i = tml.get_used_rect()
		if r.size.x > 0:
			var ts: Vector2 = Vector2(tml.tile_set.tile_size) if tml.tile_set != null else Vector2(16, 16)
			var gx: Vector2 = tml.global_position
			var gs: Vector2 = tml.global_scale
			var dx0: float = gx.x + float(r.position.x) * ts.x * gs.x
			var dx1: float = gx.x + float(r.end.x) * ts.x * gs.x
			var dctr: float = (dx0 + dx1) * 0.5
			print("  deck    x[%.1f, %.1f]  centre %.1f  h=%.0f"
				% [dx0, dx1, dctr, float(r.size.y) * ts.y * gs.y])
			if absf(dctr - Playfield.CENTER.x) > 0.5:
				_warn("deck centre %.1f is off playfield centre by %+.1f" % [dctr, dctr - Playfield.CENTER.x])
			if dx0 < Playfield.X_MIN - EPS or dx1 > Playfield.X_MAX + EPS:
				_warn("deck x[%.1f, %.1f] extends past the band — intentional for understructure, check if it's the deck"
					% [dx0, dx1])
	else:
		_warn("no '%s' layer found — stitch height will fall back to the tile-union" % DECK)

	root.free()
