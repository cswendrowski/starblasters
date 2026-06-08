extends SceneTree

# Cannon bullet (Roman 2026-06-08): gets its intended speed (240 = 4 px/f) and uses the
# SCENE's authored hitbox (6x16), not the variant's old 5x5. Run:
# godot --headless --script res://tools/test_cannon_bullet.gd

const RESULT := "res://tools/_cannon_result.txt"
var _done := false

func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var world := Node2D.new(); root.add_child(world)
	var b = load("res://scenes/projectiles/enemy_bullet_cannon.tscn").instantiate()
	world.add_child(b)   # _ready -> _apply_variant
	if int(round(b.speed)) != 240:
		lines.append("FAIL cannon speed %d != 240" % int(round(b.speed))); fails += 1
	var cs = b.get_node_or_null("CollisionShape2D")
	var sz := Vector2.ZERO
	if cs != null and cs.shape is RectangleShape2D:
		sz = (cs.shape as RectangleShape2D).size
	if sz != Vector2(6, 16):
		lines.append("FAIL cannon hitbox %s != (6, 16)" % str(sz)); fails += 1
	# random_frame: the cannon picks ONE random frame and stops (not animated), so the static
	# glow snapshot matches the shown frame. Confirm it's stopped on a valid frame.
	var asp = b.get_node_or_null("AnimatedSprite2D")
	var playing = true
	var frame_idx = -1
	if asp != null:
		playing = asp.is_playing()
		frame_idx = asp.frame
	if playing:
		lines.append("FAIL cannon is animating (random_frame should stop it)"); fails += 1
	if frame_idx < 0 or frame_idx > 1:
		lines.append("FAIL cannon frame %d out of range" % frame_idx); fails += 1
	var glow = b.get_node_or_null("ShaderGlow")
	lines.append("cannon: speed=%d hitbox=%s frame=%d playing=%s glow=%s" % [
		int(round(b.speed)), str(sz), frame_idx, str(playing), ("yes" if glow != null else "no")])
	lines.append("CANNON BULLET: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
