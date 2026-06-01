extends SceneTree

# Captures two states of the V3 sector map boss icon for the boss-icon fixes:
#   1. default (fresh run)        -> boss icon VISIBLE (locked, white skull + red dot)
#   2. row 0 POIs forced complete -> boss AVAILABLE (green dot + skull, full ring
#      sorted above the poi bar)
const SCENE := "res://scenes/sector_map_v3.tscn"
const OUT_DEFAULT := "res://captures/boss_icon_default.png"
const OUT_GREEN   := "res://captures/boss_icon_green.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node_or_null("Run")
	if run == null:
		print("[cap] Run autoload missing"); quit(); return
	run.new_run()
	# Pre-build the sector cache so we can edit it before the scene reads it.
	# Match the sector_idx _ensure_sector_cache expects (sectors_cleared + 1) so
	# it does NOT regenerate over our edits.
	run.start_new_sector(run.sectors_cleared + 1, run.run_seed + run.sectors_cleared)

	# --- Capture 1: default state ---
	await _capture(OUT_DEFAULT)

	# --- Force row 0 POIs complete, leave boss undefeated -> AVAILABLE ---
	var rows: Array = run.sector_map_cache.get("rows", [])
	if rows.size() > 0:
		var pois: Array = rows[0].pois
		for p in pois:
			p.completed = true
		rows[0].boss.completed = false
		print("[cap] row 0: forced %d POIs complete; is_row_pois_complete(0)=%s" % [pois.size(), str(run.is_row_pois_complete(0))])

	# --- Capture 2: boss available (green) ---
	await _capture(OUT_GREEN)
	quit()


func _capture(out_path: String) -> void:
	var err := change_scene_to_file(SCENE)
	if err != OK:
		print("[cap] change_scene failed: ", err); return
	await create_timer(2.0).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(out_path))
		print("[cap] saved %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	else:
		print("[cap] ERROR no image for %s" % out_path)
