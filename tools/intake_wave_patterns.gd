extends SceneTree

# Intake the wave-pattern editor's saved library (user://tuners/wave_patterns.json) into the
# production const authored_patterns.DATA, formatted compactly to match the existing style
# (one placement per line). Only the DATA = [ ... ] block is replaced; the rest of the file
# (header comment, builder funcs) is preserved verbatim. Re-runnable. Verify after with
# inspect_wave_patterns.gd + parse_check.

const SAVE_PATH := "user://tuners/wave_patterns.json"
const TARGET := "res://scripts/levels/authored_patterns.gd"

func _fmt_str(v) -> String:
	return JSON.stringify(str(v))   # quoted, escaped

func _fmt_placement(pl: Dictionary) -> String:
	var parts: Array = []
	parts.append('"lane": %d' % int(pl.get("lane", 0)))
	parts.append('"row": %d' % int(pl.get("row", 0)))
	var sx: int = int(pl.get("sub_x", 1))
	var sy: int = int(pl.get("sub_y", 1))
	if sx != 1:
		parts.append('"sub_x": %d' % sx)
	if sy != 1:
		parts.append('"sub_y": %d' % sy)
	parts.append('"enemy": %s' % _fmt_str(pl.get("enemy", "")))
	parts.append('"movement": %s' % _fmt_str(pl.get("movement", "")))
	parts.append('"size": %s' % _fmt_str(pl.get("size", "")))
	var d: String = str(pl.get("dir", ""))
	if d != "":
		parts.append('"dir": %s' % _fmt_str(d))
	var dp: String = str(pl.get("depth", ""))
	if dp != "":
		parts.append('"depth": %s' % _fmt_str(dp))
	return "{" + ", ".join(parts) + "}"

func _fmt_data(lib: Array) -> String:
	var out: String = "const DATA: Array = [\n"
	for p in lib:
		# Skip empty editor slots (a "new pattern" never filled) — they'd bake as dead 0-placement
		# entries. build_phrase returns null on them anyway, but keep DATA clean.
		if (p.get("placements", []) as Array).is_empty():
			continue
		out += "\t{\n"
		out += '\t\t"name": %s,\n' % _fmt_str(p.get("name", ""))
		out += '\t\t"faction": %s,\n' % _fmt_str(p.get("faction", "any"))
		out += '\t\t"min_sector": %d,\n' % int(p.get("min_sector", 0))
		if p.has("stagger"):
			out += '\t\t"stagger": %s,\n' % str(p.get("stagger"))
		if p.has("lockstep"):
			out += '\t\t"lockstep": %s,\n' % str(bool(p.get("lockstep", false)))
		if p.has("note") and str(p.get("note")) != "":
			out += '\t\t"note": %s,\n' % _fmt_str(p.get("note"))
		out += '\t\t"placements": [\n'
		for pl in p.get("placements", []):
			out += "\t\t\t" + _fmt_placement(pl) + ",\n"
		out += "\t\t],\n"
		out += "\t},\n"
	out += "]"
	return out

func _initialize() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("MISSING library: ", SAVE_PATH); quit(); return
	var lf := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var lib = JSON.parse_string(lf.get_as_text())
	lf.close()
	if not (lib is Array):
		print("library not an array"); quit(); return

	var tf := FileAccess.open(TARGET, FileAccess.READ)
	var lines: PackedStringArray = tf.get_as_text().split("\n")
	tf.close()
	var start: int = -1
	var end: int = -1
	for i in lines.size():
		if start < 0 and lines[i].begins_with("const DATA: Array = ["):
			start = i
		elif start >= 0 and lines[i] == "]":
			end = i
			break
	if start < 0 or end < 0:
		print("DATA block not found (start=%d end=%d)" % [start, end]); quit(); return

	var head: Array = []
	for i in start:
		head.append(lines[i])
	var tail: Array = []
	for i in range(end + 1, lines.size()):
		tail.append(lines[i])
	var rebuilt: String = "\n".join(head) + "\n" + _fmt_data(lib) + "\n" + "\n".join(tail)
	var wf := FileAccess.open(TARGET, FileAccess.WRITE)
	wf.store_string(rebuilt)
	wf.close()
	print("INTAKE OK: replaced DATA block (old lines %d-%d) with %d patterns" % [start, end, (lib as Array).size()])
	quit()
