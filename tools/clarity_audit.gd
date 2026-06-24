# Motion-clarity audit. Headless SceneTree script: instantiates every
# projectile + enemy scene, reads its real speed (instance value, so a
# script _init that gets overridden by the .tscn resolves correctly),
# measures the engine-loaded sprite extent along the travel axis, and
# reports per-frame displacement / sprite-length ratio at 60fps.
#
# Ratio = how far the object jumps each frame relative to its own length
# along the direction of travel. >~0.8 strobes (gaps between afterimages);
# 0.4-0.8 "steps" (snap-wobble, no glide); <0.4 reads clean.
#
# Sector scaling: enemy movement gets ×(1 + 0.05*sectors_cleared) capped
# 2×, so we print both base and ×2 (late-run) columns.
#
# Run: E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe --path . \
#        --headless --script tools/clarity_audit.gd
extends SceneTree

const FPS := 60.0
const SECTOR_MAX := 2.0

func _initialize() -> void:
	var rows: Array = []
	rows.append_array(_audit_dir("res://scenes/projectiles/", "proj"))
	rows.append_array(_audit_dir("res://scenes/enemies/", "enemy"))
	rows.sort_custom(func(a, b): return a["ratio"] > b["ratio"])
	_print_table(rows)
	quit()


func _audit_dir(dir_path: String, kind: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".tscn"):
			continue
		var path := dir_path + f
		var ps = load(path)
		if ps == null or not (ps is PackedScene):
			continue
		var inst = ps.instantiate()
		if inst == null:
			continue
		var info := _measure(inst, f, kind)
		if not info.is_empty():
			out.append(info)
		inst.free()
	return out


func _measure(inst: Node, fname: String, kind: String) -> Dictionary:
	# --- speed + travel axis ---
	var speed := -1.0
	var src := ""
	var horizontal := false
	if "speed" in inst and float(inst.get("speed")) > 0.0:
		speed = float(inst.get("speed"))
		src = "speed"
	if "movement" in inst and inst.get("movement") != null:
		var mv = inst.get("movement")
		var ms: String = mv.get_script().resource_path.get_file() if mv.get_script() else ""
		if "side" in ms:
			horizontal = true
		for prop in ["max_speed", "speed", "target_speed"]:
			if prop in mv and float(mv.get(prop)) > 0.0:
				speed = float(mv.get(prop))
				src = "mv.%s (%s)" % [prop, ms]
				break
	# bullet travel direction, if it exposes one
	if "velocity_dir" in inst:
		var vd: Vector2 = inst.get("velocity_dir")
		if abs(vd.x) > abs(vd.y):
			horizontal = true

	# --- sprite extent (engine-loaded, scale-aware) ---
	var ext := _sprite_extent(inst)
	var w: float = ext.x
	var h: float = ext.y
	var travel_len: float = (w if horizontal else h)

	if speed <= 0.0 or travel_len <= 0.0:
		return {
			"name": fname.replace(".tscn", ""), "kind": kind,
			"speed": speed, "src": (src if src != "" else "—"),
			"w": w, "h": h, "pxf": -1.0, "ratio": -1.0,
			"note": "bespoke/static — check manually",
		}

	var pxf := speed / FPS
	var ratio := pxf / travel_len
	return {
		"name": fname.replace(".tscn", ""), "kind": kind,
		"speed": speed, "src": src, "w": w, "h": h,
		"pxf": pxf, "ratio": ratio, "note": "",
	}


# Walk for the first Sprite2D / AnimatedSprite2D and return its on-screen
# size (texture × cumulative scale, frame-grid + atlas aware).
func _sprite_extent(root: Node) -> Vector2:
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_front()
		var sz := Vector2.ZERO
		if n is Sprite2D and n.texture != null:
			sz = n.texture.get_size()
			if n.hframes > 1:
				sz.x /= n.hframes
			if n.vframes > 1:
				sz.y /= n.vframes
		elif n is AnimatedSprite2D and n.sprite_frames != null:
			var anims: PackedStringArray = n.sprite_frames.get_animation_names()
			if anims.size() > 0:
				var tex = n.sprite_frames.get_frame_texture(anims[0], 0)
				if tex != null:
					sz = tex.get_size()
		if sz != Vector2.ZERO:
			return sz * _cumulative_scale(n, root)
		for c in n.get_children():
			stack.append(c)
	return Vector2.ZERO


func _cumulative_scale(node: Node, root: Node) -> Vector2:
	var s := Vector2.ONE
	var cur = node
	while cur != null:
		if cur is Node2D:
			s *= cur.scale
		if cur == root:
			break
		cur = cur.get_parent()
	return s


func _print_table(rows: Array) -> void:
	print("")
	print("=== MOTION CLARITY AUDIT (60fps internal 480x270) ===")
	print("ratio = px/frame ÷ sprite-length-along-travel.  >0.8 STROBE  0.4-0.8 step  <0.4 clean")
	print("x2 = 2x-speed headroom check (does the motion still read cleanly if doubled)")
	print("")
	print("%-26s %-6s %7s %5s %8s  %6s %6s  %s" % [
		"name", "kind", "speed", "px/f", "WxH", "ratio", "x2", "speed-src"])
	print("".rpad(96, "-"))
	for r in rows:
		if r["ratio"] < 0.0:
			print("%-26s %-6s %7s %5s %8s  %6s %6s  %s" % [
				r["name"], r["kind"], "?", "?",
				"%dx%d" % [r["w"], r["h"]], "—", "—", r["note"]])
			continue
		var x2: float = r["ratio"] * SECTOR_MAX if r["kind"] == "enemy" else r["ratio"]
		var flag := "STROBE" if r["ratio"] >= 0.8 else ("step" if r["ratio"] >= 0.4 else "")
		print("%-26s %-6s %7.0f %5.1f %8s  %6.2f %6.2f  %-14s %s" % [
			r["name"], r["kind"], r["speed"], r["pxf"],
			"%dx%d" % [r["w"], r["h"]], r["ratio"], x2, r["src"], flag])
