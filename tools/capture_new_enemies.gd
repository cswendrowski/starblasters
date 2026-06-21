extends SceneTree

# Captures the 2026-06-01 enemy batch — one short clip per enemy/variant into
# captures/new_enemies/<name>/. Run via tools/capture_new_enemies.ps1 (NOT
# --headless; needs a render target for the viewport grab).
#
# Each clip shows the enemy in a 480×270 frame with a faint playfield band
# (x 132–348) and a slowly-strafing dummy "player" at the bottom so aim /
# broadside / beam-tracking behaviours are visible.

const FPS: int = 30
const FRAME_TIME: float = 1.0 / float(FPS)
const BASE := "res://captures/new_enemies"

const X_MIN := 132.0
const X_MAX := 348.0

const FRIGATE := "res://scenes/enemies/factions/supremacy/enemy_frigate.tscn"
const BOMBER := "res://scenes/enemies/core/enemy_core_bomber.tscn"
const MINELAYER := "res://scenes/enemies/core/enemy_core_m_minelayer.tscn"
const BEAMER_DOWN := "res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn"
const BEAMER_TRACK := "res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn"

# name, seconds
const CLIPS := [
	["frigate_side", 4.5],
	["frigate_top", 3.5],
	["bomber_wing", 4.5],
	["minelayer", 5.0],
	["beamer_down", 5.5],
	["beamer_track", 5.5],
]

var _player: Node2D = null


func _initialize() -> void:
	_run.call_deferred()


func _build_stage() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06)
	bg.size = Vector2(480, 270)
	bg.z_index = -20  # behind everything, incl. the z=-1 engine contrails
	root.add_child(bg)
	# Faint playfield band so sprite scale reads against the 216px gameplay zone.
	var band := ColorRect.new()
	band.color = Color(0.06, 0.08, 0.13)
	band.position = Vector2(X_MIN, 0)
	band.size = Vector2(X_MAX - X_MIN, 270)
	band.z_index = -19
	root.add_child(band)
	# Dummy player (in "player" group) — an Area2D so global_position behaves,
	# with a no-op take_damage so beam/bullet hits don't error. Strafes slowly.
	var p := Area2D.new()
	var ps := GDScript.new()
	ps.source_code = "extends Area2D\nfunc take_damage(_d: int = 1) -> void:\n\tpass\n"
	ps.reload()
	p.set_script(ps)
	var marker := ColorRect.new()
	marker.color = Color(0.4, 0.8, 1.0)
	marker.size = Vector2(12, 12)
	marker.position = Vector2(-6, -6)
	p.add_child(marker)
	root.add_child(p)
	_player = p
	_player.add_to_group("player")


func _player_set(x: float) -> void:
	_player.global_position = Vector2(x, 230.0)


func _spawn(name: String) -> Array:
	var nodes: Array = []
	match name:
		"frigate_side":
			var f = load(FRIGATE).instantiate()
			root.add_child(f)
			f.set("_mode", 1)        # SIDE_CROSS
			f.set("_side_dir", 1)
			f.position = Vector2(X_MIN - 28.0, 84.0)
			f.set("_last_position", f.position)
			nodes.append(f)
		"frigate_top":
			var f = load(FRIGATE).instantiate()
			root.add_child(f)
			f.set("_mode", 0)        # TOP_DESCENT
			f.position = Vector2(240.0, -12.0)
			f.set("_last_position", f.position)
			nodes.append(f)
		"bomber_wing":
			for x in [196.0, 284.0]:
				var b = load(BOMBER).instantiate()
				root.add_child(b)
				if b.has_method("start"):
					b.call("start", Vector2(x, -12.0))
				nodes.append(b)
		"minelayer":
			var m = load(MINELAYER).instantiate()
			# Minelayer extends enemy_core — the director normally hands it a
			# side_traverse movement; supply one so start() takes the pattern path
			# (not the anchored path, which needs a MoveTimer the scene lacks).
			var st = load("res://scripts/enemies/patterns/side_traverse.gd").new()
			st.direction = 1
			m.set("movement", st)
			root.add_child(m)
			if m.has_method("start"):
				m.call("start", Vector2(240.0, 90.0))
			nodes.append(m)
		"beamer_down":
			var e = load(BEAMER_DOWN).instantiate()
			root.add_child(e)
			if e.has_method("start"):
				e.call("start", Vector2(240.0, -12.0))
			nodes.append(e)
		"beamer_track":
			var e = load(BEAMER_TRACK).instantiate()
			root.add_child(e)
			if e.has_method("start"):
				e.call("start", Vector2(240.0, -12.0))
			nodes.append(e)
	return nodes


func _run() -> void:
	_build_stage()
	# Optional subset: pass clip names after `--` (e.g. `-- beamer_down beamer_track`)
	# to re-render only those, instead of all six.
	var only := PackedStringArray(OS.get_cmdline_user_args())
	for clip in CLIPS:
		var cname: String = clip[0]
		var dur: float = clip[1]
		if only.size() > 0 and not only.has(cname):
			continue
		await _capture_clip(cname, dur)
	print("[new-enemies] done")
	quit()


func _capture_clip(cname: String, dur: float) -> void:
	var out_dir := "%s/%s" % [BASE, cname]
	var abs_dir := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(out_dir)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()

	var nodes := _spawn(cname)
	var total: int = int(dur * float(FPS))
	for f in total:
		# Strafe the player so broadside/beam aim visibly responds.
		var ph: float = float(f) / float(FPS)
		_player_set(240.0 + sin(ph * 1.6) * 70.0)
		# Minelayer: blow it up ~70% in to show the death scatter.
		if cname == "minelayer" and f == int(total * 0.7):
			for n in nodes:
				if is_instance_valid(n) and n.has_method("explode"):
					n.call("explode")
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [out_dir, f]))

	# Clear spawned enemies + any leftover projectiles/bomblets before next clip.
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	for grp in ["enemies", "bullets", "bomblets"]:
		for n in root.get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n):
				n.queue_free()
	await create_timer(0.2).timeout
	print("[new-enemies] %s: %d frames" % [cname, total])
