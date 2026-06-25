extends SceneTree

# One-shot generator for res://resources/music/music_library.tres.
# Scans assets/audio/music/*/ for Ovani sets and seeds a sensible default
# per-context eligibility. Re-running PRESERVES any existing eligibility (only
# fills in tracks that aren't assigned anywhere yet), so it's safe to run after
# dropping in new folders. The Track Manager (Dev Menu → Music Lab) is the
# normal way to edit eligibility; this just bootstraps the file.
#
# Run: godot --headless --path . --script tools/build_music_library.gd

const OUT_PATH := "res://resources/music/music_library.tres"

# Default vibe-based assignment by track name. Tracks not listed anywhere fall
# back to "combat" so nothing is silent. Roman retunes in the Track Manager.
const DEFAULTS := {
	"menu":    ["Galaxy", "Milkyway"],
	"sector":  ["Saturn", "Jupiter", "Milkyway", "Limitless"],
	"signal":  ["Creep", "Shadowrun", "Grindplates"],
	"outpost": ["Limitless", "On A Mission", "Galaxy"],
	"combat":  ["Battle Tech", "Break 9", "Chugga", "Knuckles", "Swarm", "Out The Way", "Grindplates", "On A Mission"],
	"boss":    ["Retribution", "Battle Tech", "Swarm", "Chugga"],
}


func _init() -> void:
	var tracks := MusicLibrary.scan_project_folders()
	if tracks.is_empty():
		push_error("[build_music_library] no music folders found under %s" % MusicLibrary.MUSIC_DIR)
		quit(1)
		return

	# Preserve existing eligibility if the file is already there.
	var eligibility := {}
	if ResourceLoader.exists(OUT_PATH):
		var existing = load(OUT_PATH)
		if existing != null and existing.eligibility is Dictionary:
			eligibility = existing.eligibility.duplicate(true)

	var assigned := {}
	for ctx in MusicLibrary.CONTEXTS:
		var pool: Array = eligibility.get(ctx, [])
		# Seed from defaults only when this context has no saved pool yet.
		if pool.is_empty():
			for n in DEFAULTS.get(ctx, []):
				if tracks.has(n) and not pool.has(n):
					pool.append(n)
		# Drop assignments whose track no longer exists.
		pool = pool.filter(func(n): return tracks.has(n))
		eligibility[ctx] = pool
		for n in pool:
			assigned[n] = true

	# Safety net: any track assigned nowhere goes to combat.
	for n in tracks.keys():
		if not assigned.has(n):
			eligibility["combat"].append(n)

	var data := MusicLibraryData.new()
	data.tracks = tracks
	data.eligibility = eligibility

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/music"))
	var err := ResourceSaver.save(data, OUT_PATH)
	if err != OK:
		push_error("[build_music_library] save failed err=%d" % err)
		quit(1)
		return
	print("[build_music_library] saved %s — %d tracks" % [OUT_PATH, tracks.size()])
	for ctx in MusicLibrary.CONTEXTS:
		print("  %-8s : %s" % [ctx, ", ".join(eligibility[ctx])])
	quit(0)
