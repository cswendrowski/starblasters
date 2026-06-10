extends SceneTree

# Audio-rewire structural test (Roman 2026-06-10): verify the new SFX helper pools resolve to the
# right clip counts and that play() runs without error (headless dummy audio). Catches wrong counts /
# missing files / bad pool selection that parse_check can't. Run:
# godot --headless --script res://tools/test_audio_sfx.gd

const RESULT := "res://tools/_audio_sfx_result.txt"
const ExpSfx = preload("res://scripts/effects/explosion_sfx.gd")
const OutSfx = preload("res://scripts/effects/outpost_sfx.gd")
const WepSfx = preload("res://scripts/effects/weapon_sfx.gd")
const EnemySfx = preload("res://scripts/effects/enemy_sfx.gd")
const SmartBomb = preload("res://scripts/parts/smart_bomb.gd")

func _init() -> void:
	var lines: Array = []
	var fails := 0
	# --- pool counts ---
	var checks := [
		["ExplosionSfx CLOSE", ExpSfx.CLOSE_CLIPS.size(), 24],
		["ExplosionSfx MEDIUM", ExpSfx.MEDIUM_CLIPS.size(), 28],
		["ExplosionSfx DISTANT", ExpSfx.DISTANT_CLIPS.size(), 28],
		["WeaponSfx AUTOLASER", WepSfx.AUTOLASER_CLIPS.size(), 7],
		["WeaponSfx SPREAD", WepSfx.SPREAD_CLIPS.size(), 6],
		["WeaponSfx WAVE", WepSfx.WAVE_CLIPS.size(), 6],
		["EnemySfx BLASTER", EnemySfx.BLASTER_CLIPS.size(), 8],
		["EnemySfx MG", EnemySfx.MG_CLIPS.size(), 6],
		["SmartBomb detonate", SmartBomb._DETONATE_CLIPS.size(), 2],
	]
	for c in checks:
		var ok: bool = int(c[1]) == int(c[2])
		lines.append("%s: %d (expect %d) %s" % [c[0], c[1], c[2], "OK" if ok else "FAIL"])
		if not ok:
			fails += 1
	# --- outpost kinds present + non-empty ---
	for k in ["equip", "unequip", "upgrade", "repair"]:
		var pool: Array = OutSfx.CLIPS.get(k, [])
		if pool.is_empty():
			lines.append("FAIL OutpostSfx kind '%s' empty" % k); fails += 1
	# --- no-clip nulls (all preloads resolved) ---
	for arr in [ExpSfx.CLOSE_CLIPS, ExpSfx.MEDIUM_CLIPS, ExpSfx.DISTANT_CLIPS, WepSfx.AUTOLASER_CLIPS, WepSfx.SPREAD_CLIPS]:
		for clip in arr:
			if clip == null:
				lines.append("FAIL a clip preload resolved null"); fails += 1
				break
	# --- play() smoke (must not throw under dummy audio) ---
	ExpSfx.play(Vector2(240, 135))                 # no player -> medium band
	ExpSfx.play(Vector2(240, 135), 2.0)            # scaled
	OutSfx.play("equip"); OutSfx.play("repair")
	WepSfx.play(root, Vector2(100, 100), "autolaser")
	WepSfx.play(root, Vector2(100, 100), "spread")
	WepSfx.play(root, Vector2(100, 100), "wave")
	lines.append("play() smoke: no crash")
	lines.append("AUDIO SFX: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
