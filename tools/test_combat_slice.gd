extends SceneTree

# Unit check for the v2.5 formation shapes + the CombatSlice builder.
# - _formation_lanes("wall", 6): 6 distinct lanes with exactly one safe gap.
# - _formation_lanes("pincer", 6): includes both edge lanes (0 and 6).
# - CombatSlice.build(): 3 waves; wave 0 = FORMATION(wall) + FILLER + BREATHER,
#   all specs/pool entries load a real enemy scene.
# Run: godot --headless --script res://tools/test_combat_slice.gd

const RESULT := "res://tools/_combat_slice_result.txt"


func _init() -> void:
	var log: Array = []
	var DirectorScript := load("res://scripts/levels/director.gd")
	var dir = DirectorScript.new()

	# --- wall ---
	var wl: Array = dir._formation_lanes(&"wall", 6)
	var wset: Dictionary = {}
	for l in wl:
		wset[l] = true
	if wl.size() != 6 or wset.size() != 6:
		log.append("FAIL wall not 6 distinct lanes: %s" % str(wl))
	var missing: int = 0
	for i in 7:
		if not wset.has(i):
			missing += 1
	if missing != 1:
		log.append("FAIL wall gap count=%d (expected 1)" % missing)

	# --- pincer ---
	var pl: Array = dir._formation_lanes(&"pincer", 6)
	var pset: Dictionary = {}
	for l in pl:
		pset[l] = true
	if not (pset.has(0) and pset.has(6)):
		log.append("FAIL pincer missing edge lanes: %s" % str(pl))

	# --- slice structure ---
	var score = CombatSlice.build()
	if score.waves.size() != 4:
		log.append("FAIL slice waves=%d (expected 4)" % score.waves.size())
	else:
		var w0 = score.waves[0]
		if w0.phrases[0].kind != Phrase.Kind.FORMATION or w0.phrases[0].shape != &"wall":
			log.append("FAIL w0p0 not a wall FORMATION")
		elif w0.phrases[0].specs[0].movement_override == null:
			log.append("FAIL wall spec missing lane_path movement override")
		var kinds: Dictionary = {}
		for ph in w0.phrases:
			kinds[ph.kind] = true
			for sp in ph.specs:
				if sp.enemy_scene == null:
					log.append("FAIL formation spec has null enemy_scene")
			for sp in ph.pool:
				if sp.enemy_scene == null:
					log.append("FAIL filler pool spec has null enemy_scene")
		if not (kinds.has(Phrase.Kind.FILLER) and kinds.has(Phrase.Kind.BREATHER)):
			log.append("FAIL w0 missing FILLER/BREATHER phrase")

	dir.free()

	if log.is_empty():
		log.append("COMBAT_SLICE TEST: PASS")
	else:
		log.append("COMBAT_SLICE TEST: FAIL")
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(log)))
		f.close()
	quit()
