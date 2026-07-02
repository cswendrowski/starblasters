extends SceneTree

# Verifies the Zealot Battleship is selectable in the Pattern Eligibility editor (Roman 2026-07-01):
# it's in the committed matrix (so it lists under "All"), and _home_of now buckets it under the ZEALOT
# faction filter via the scene-path fallback. The editor's _load_data / _home_of are UI-free, so we
# instance the script WITHOUT entering the tree (no _ready → no UI). Run:
#   godot --headless --path . -s tools/test_eligibility_boss.gd

const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const PEEditorScript = preload("res://scripts/dev/pattern_eligibility_editor.gd")
const BATTLESHIP := "res://scenes/enemies/factions/zealot/boss_z_battleship.tscn"

var _fails: int = 0


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)


func _init() -> void:
	_ck(PatternEligibility.DATA.has(BATTLESHIP), "battleship is in the eligibility matrix (lists under 'All')")

	var ed = PEEditorScript.new()   # no add_child → _ready/UI never run; _load_data + _home_of are UI-free
	ed._load_data()
	_ck(ed._scenes.has(BATTLESHIP), "battleship present in the editor's enemy list")
	_ck(int(ed._home_of(BATTLESHIP)) == int(Factions.Id.ZEALOT), "battleship buckets under the ZEALOT filter (got %d)" % int(ed._home_of(BATTLESHIP)))
	# Sanity: a tagged zealot unit still resolves via ENEMY_TAGS (fallback didn't break the normal path).
	_ck(int(ed._home_of("res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn")) == int(Factions.Id.ZEALOT), "tagged zealot unit still buckets via ENEMY_TAGS")
	ed.free()

	print("VERDICT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
