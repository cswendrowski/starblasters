extends SceneTree

# Integrity check for res://resources/music/music_library.tres (the Ovani music
# catalog authored in the Track Manager). Verifies every track's stems load,
# every eligibility entry points at a real track, every context has a pool, and
# no track is orphaned. Prints "VERDICT: PASS" / "FAIL".
#
# Run: godot --headless --path . --script tools/validate_music_library.gd

func _init() -> void:
	var fails := 0
	var warns := 0

	if not ResourceLoader.exists(MusicLibrary.DATA_PATH):
		push_error("MISSING catalog: %s" % MusicLibrary.DATA_PATH)
		print("VERDICT: FAIL"); quit(1); return

	var lib := MusicLibrary.new()
	var data := lib.data
	var names := lib.track_names()
	print("catalog: %s — %d tracks" % [MusicLibrary.DATA_PATH, names.size()])

	# 1. Every track's required stems exist + build into a valid OvaniSong.
	for n in names:
		var t: Dictionary = data.tracks[n]
		for key in ["i1", "i2", "main"]:
			var p: String = t.get(key, "")
			if p == "":
				print("  FAIL  %-14s missing '%s' path" % [n, key]); fails += 1
			elif not ResourceLoader.exists(p):
				print("  FAIL  %-14s '%s' does not import: %s" % [n, key, p]); fails += 1
		var song := lib.make_song(n)
		if song == null or song.Intensity1 == null or song.Intensity2 == null or song.Intensity3 == null:
			print("  FAIL  %-14s OvaniSong did not build (null stem)" % n); fails += 1

	# 2. Eligibility: every context present + non-empty, every entry a real track.
	var assigned := {}
	for ctx in MusicLibrary.CONTEXTS:
		var pool: Array = data.eligibility.get(ctx, [])
		if pool.is_empty():
			print("  WARN  context '%s' has no eligible tracks (will fall back)" % ctx); warns += 1
		for n in pool:
			if not data.tracks.has(n):
				print("  FAIL  context '%s' references unknown track '%s'" % [ctx, n]); fails += 1
			else:
				assigned[n] = true
		print("  %-8s (%d): %s" % [ctx, pool.size(), ", ".join(pool)])

	# 3. Orphan tracks (assigned to no context) — playable only as a fallback.
	for n in names:
		if not assigned.has(n):
			print("  WARN  track '%s' is not eligible in any context" % n); warns += 1

	print("---")
	print("%d failure(s), %d warning(s)" % [fails, warns])
	print("VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
