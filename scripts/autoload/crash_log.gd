extends Node
## CrashLog (Roman 2026-06-19) — per-launch forensic breadcrumb log. Opens a FRESH
## user://logs/session_<datetime>.log every launch and records what the game is doing as it does
## it: scene changes, a periodic heartbeat (scene / fps / enemy + node counts), and explicit events
## that other systems push via `CrashLog.note(category, msg)`. EVERY line is flushed to disk, so if
## the game hard-crashes (SIGSEGV) the tail of the newest log shows exactly what it was up to.
##
## Always-on + lightweight (one buffered+flushed line per event, a heartbeat every 2s). Keeps the
## last KEEP_LOGS sessions and prunes older ones. To read a crash: open the newest file in the user
## data folder's logs/ dir (Editor → Project → Open User Data Folder). Hunting the intermittent
## #116172 combat-load crash — keep a weather eye via these logs.

# TODO(ship): set ENABLED = false for release builds (see TODO.md "Pre-ship checklist"). ON for
# development as the weather-eye crash log; shipped copies shouldn't write forensic logs to players'
# disks. (Alternatively gate on OS.is_debug_build() to auto-disable in release exports.)
const ENABLED := true
const LOG_DIR := "user://logs"
const KEEP_LOGS := 25
const HEARTBEAT_SEC := 2.0

var _file: FileAccess = null
var _t0_ms: int = 0
var _hb_accum: float = 0.0
var _last_scene: String = ""


func _ready() -> void:
	if not ENABLED:
		set_process(false)
		return
	_t0_ms = Time.get_ticks_msec()
	_open()
	note("boot", "SESSION START  %s  display=%s  v=%s" % [
		Time.get_datetime_string_from_system(),
		DisplayServer.get_name(),
		str(ProjectSettings.get_setting("application/config/version", "?")),
	])


func _open() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_file = FileAccess.open("%s/session_%s.log" % [LOG_DIR, stamp], FileAccess.WRITE)
	_prune()


func _prune() -> void:
	var d := DirAccess.open(LOG_DIR)
	if d == null:
		return
	var files: Array = []
	for f in d.get_files():
		if f.begins_with("session_") and f.ends_with(".log"):
			files.append(f)
	files.sort()   # datetime-stamped names sort chronologically
	while files.size() > KEEP_LOGS:
		d.remove(files.pop_front())


## Push an explicit breadcrumb. Safe from anywhere — no-op before _ready / when disabled.
func note(category: String, msg: String) -> void:
	if _file == null:
		return
	var t := float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	_file.store_line("[%9.2f] %-9s %s" % [t, category, msg])
	_file.flush()


func _process(delta: float) -> void:
	if _file == null:
		return
	# Scene change → log immediately (the swap itself is the prime crash seam).
	var cs := get_tree().current_scene
	var scene := ""
	if cs != null and is_instance_valid(cs):
		scene = cs.scene_file_path.get_file() if cs.scene_file_path != "" else cs.name
	if scene != _last_scene:
		_last_scene = scene
		note("scene", "entered: %s" % scene)
	# Periodic heartbeat snapshot.
	_hb_accum += delta
	if _hb_accum >= HEARTBEAT_SEC:
		_hb_accum = 0.0
		note("hb", "scene=%s fps=%d enemies=%d nodes=%d" % [
			scene,
			Engine.get_frames_per_second(),
			get_tree().get_nodes_in_group("enemies").size(),
			get_tree().get_node_count(),
		])
