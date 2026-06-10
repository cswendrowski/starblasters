extends SceneTree

# Enemy-cannon render test (Roman 2026-06-10): inspects BOTH cannon bullets (burst_round via
# enemy_bullet_cannon.tscn, heavy_slug via enemy_bullet.tscn) — confirms they ANIMATE (not frozen on
# a random frame), slice into the correct 16x16 frames (enemy_cannon.png is 32x16 = 2 frames), and
# that the ShaderGlow node crops to ONE frame (16px), NOT the whole 32px sheet. Settles the worklist
# "not animated / random frame / glow on entire sprite" report with hard numbers. Run:
# godot --headless --script res://tools/test_cannon_render.gd

const RESULT := "res://tools/_cannon_render_result.txt"
var _t := 0
var _world: Node2D = null
var _cannon: Node = null
var _slug: Node = null
var _done := false

func _process(_dt: float) -> bool:
	_t += 1
	if _t == 1:
		_world = Node2D.new()
		root.add_child(_world)
		_cannon = load("res://scenes/projectiles/enemy_bullet_cannon.tscn").instantiate()
		_world.add_child(_cannon)
		_slug = load("res://scenes/projectiles/enemy_bullet.tscn").instantiate()
		_slug.variant = load("res://data/bullets/heavy_slug.tres")
		_world.add_child(_slug)
		return false
	if _t < 5 or _done:
		return false
	_done = true
	var lines: Array = []
	var fails := 0
	for entry in [["burst_round cannon", _cannon], ["heavy_slug", _slug]]:
		var label: String = entry[0]
		var b: Node = entry[1]
		lines.append("--- %s ---" % label)
		if b == null or not is_instance_valid(b):
			lines.append("FAIL bullet gone"); fails += 1; continue
		var asp := b.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if asp == null or asp.sprite_frames == null:
			lines.append("FAIL no AnimatedSprite2D/frames"); fails += 1; continue
		var fc: int = asp.sprite_frames.get_frame_count("default")
		var playing: bool = asp.is_playing()
		var f0: Texture2D = asp.sprite_frames.get_frame_texture("default", 0)
		var fw: int = f0.get_width() if f0 != null else -1
		var fh: int = f0.get_height() if f0 != null else -1
		lines.append("frames=%d  playing=%s  frame_size=%dx%d" % [fc, playing, fw, fh])
		if fc != 2:
			lines.append("FAIL expected 2 frames (32x16 sheet), got %d" % fc); fails += 1
		if fw != 16 or fh != 16:
			lines.append("FAIL frame should be 16x16, got %dx%d" % [fw, fh]); fails += 1
		if not playing:
			lines.append("FAIL not animating (frozen frame)"); fails += 1
		# Glow node: must crop to ONE frame (16px), not the whole 32px sheet.
		var glow := b.get_node_or_null("ShaderGlow") as Sprite2D
		if glow == null or glow.texture == null:
			lines.append("FAIL no ShaderGlow node/texture"); fails += 1
		else:
			var gw: int = glow.texture.get_width()
			var gh: int = glow.texture.get_height()
			lines.append("glow_tex=%dx%d (expect 16x16, NOT 32-wide whole sheet)" % [gw, gh])
			if gw >= 32:
				lines.append("FAIL glow uses the WHOLE sheet, not one frame"); fails += 1
			elif gw != 16:
				lines.append("WARN glow width %d != 16" % gw)
	lines.append("CANNON RENDER: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
