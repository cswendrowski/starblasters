class_name MusicLibrary
extends RefCounted

# Thin helper over MusicLibraryData: turns the baked catalog into playable
# OvaniSongs and answers per-context eligibility. Also owns the dev-only folder
# scanner the Track Manager uses to (re)discover tracks.
#
# Runtime (Music autoload + game): construct with the loaded .tres, call
# make_song()/eligible(). Dev (Track Manager): use scan_project_folders() to
# rebuild the tracks dict from disk, then save a fresh MusicLibraryData.tres.

const DATA_PATH := "res://resources/music/music_library.tres"
const MUSIC_DIR := "res://assets/audio/music"

# Canonical context list. "silent" is special (no pool) and not included here.
const CONTEXTS: Array[String] = ["menu", "sector", "signal", "outpost", "combat", "boss"]
const CONTEXT_LABELS := {
	"menu": "Main Menu",
	"sector": "Sector Map",
	"signal": "Events",
	"outpost": "Outpost",
	"combat": "Combat",
	"boss": "Boss",
}

var data: MusicLibraryData = null
var _song_cache: Dictionary = {}   # name -> OvaniSong


func _init(d: MusicLibraryData = null) -> void:
	if d != null:
		data = d
	elif ResourceLoader.exists(DATA_PATH):
		data = load(DATA_PATH)
	else:
		data = MusicLibraryData.new()


func track_names() -> Array:
	var names: Array = data.tracks.keys()
	names.sort()
	return names


func has_track(track_name: String) -> bool:
	return data.tracks.has(track_name)


func eligible(context: String) -> Array:
	var pool: Array = data.eligibility.get(context, [])
	# Defend against the catalog drifting from the eligibility map.
	return pool.filter(func(n): return data.tracks.has(n))


func reverb_tail(track_name: String) -> float:
	if not data.tracks.has(track_name):
		return 1.0
	return float(data.tracks[track_name].get("rt", 1.0))


func make_song(track_name: String) -> OvaniSong:
	if _song_cache.has(track_name):
		return _song_cache[track_name]
	if not data.tracks.has(track_name):
		return null
	var t: Dictionary = data.tracks[track_name]
	var s := OvaniSong.new()
	s.Intensity1 = _load_stream(t.get("i1", ""))
	s.Intensity2 = _load_stream(t.get("i2", ""))
	s.Intensity3 = _load_stream(t.get("main", ""))
	s.Loop30 = _load_stream(t.get("l30", ""))
	s.Loop60 = _load_stream(t.get("l60", ""))
	s.ReverbTail = float(t.get("rt", 1.0))
	s.SongMode = OvaniSong.OvaniMode.Intensities
	_song_cache[track_name] = s
	return s


func _load_stream(path: String) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)


# ---- Dev-only: scan the project's music folders --------------------------
# Returns track_name -> data dict (same shape as MusicLibraryData.tracks).
# Folders are named "Name (RT n.nn)"; stems matched by filename suffix so the
# varying "Ambient VolN" / "Industrial" / "Electronic VolN" prefixes don't matter.
static func scan_project_folders() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var sub := dir.get_next()
	while sub != "":
		if dir.current_is_dir() and not sub.begins_with("."):
			var entry := _scan_one(sub)
			if not entry.is_empty():
				out[entry["name"]] = entry["data"]
		sub = dir.get_next()
	dir.list_dir_end()
	return out


static func _scan_one(folder: String) -> Dictionary:
	var track_name := folder
	var rt := 1.0
	var rt_idx := folder.rfind("(RT ")
	if rt_idx != -1:
		track_name = folder.substr(0, rt_idx).strip_edges()
		var rt_str := folder.substr(rt_idx + 4).rstrip(")").strip_edges()
		rt = rt_str.to_float()
	var base := "%s/%s" % [MUSIC_DIR, folder]
	var fd := DirAccess.open(base)
	if fd == null:
		return {}
	var found := {"i1": "", "i2": "", "main": "", "l30": "", "l60": ""}
	fd.list_dir_begin()
	var f := fd.get_next()
	while f != "":
		if f.ends_with(".ogg"):
			var p := "%s/%s" % [base, f]
			if f.ends_with("Intensity 1.ogg"):
				found["i1"] = p
			elif f.ends_with("Intensity 2.ogg"):
				found["i2"] = p
			elif f.ends_with("Main.ogg"):
				found["main"] = p
			elif f.ends_with("Cut 30.ogg"):
				found["l30"] = p
			elif f.ends_with("Cut 60.ogg"):
				found["l60"] = p
		f = fd.get_next()
	fd.list_dir_end()
	if found["i1"] == "" or found["main"] == "":
		return {}   # not a usable Ovani set
	found["rt"] = rt
	return {"name": track_name, "data": found}
