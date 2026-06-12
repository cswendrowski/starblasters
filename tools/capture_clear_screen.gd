extends SceneTree

# Capture the level-clear summary with the NEW size-section grouping + codex-style
# enemy previews (Roman 2026-06-11). Builds a synthetic kill tally spanning one
# enemy of each roster size so all sections (LARGE / MEDIUM / SMALL) show, then
# renders the real cleared_summary scene and captures the reveal.
#
# Renders to the MAIN WINDOW viewport (the proven pattern — a SubViewport added to
# root never renders → blank frames).

const OUT_DIR := "res://captures/clear_screen"
const FPS: int = 30
const DURATION: float = 3.2
const FRAME_TIME: float = 1.0 / float(FPS)

const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const ClearedScene = preload("res://scenes/cleared_summary.tscn")

var _screen
var _f


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


func _run() -> void:
	# One representative enemy scene per roster size → multi-section tally.
	var by_size := {}
	for e in EnemyRoster.ENTRIES:
		var sz := String(e.get("size", "medium"))
		var path := String(e.get("scene", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		if not by_size.has(sz):
			by_size[sz] = path
	var stats := {}
	var bounty_total := 0
	var i := 0
	for sz in by_size:
		var path: String = by_size[sz]
		var killed: int = 3 + i * 2
		var bounty: int = 5 + i * 20
		stats[path] = {"spawned": killed + 2, "killed": killed, "bounty": bounty, "total_bounty": bounty * killed}
		bounty_total += bounty * killed
		i += 1

	_screen = ClearedScene.instantiate()
	root.add_child(_screen)
	await process_frame
	await process_frame
	_screen.populate(stats, bounty_total, false, false)

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[clear-screen-gif] captured %d frames" % frame_count)
	quit()
