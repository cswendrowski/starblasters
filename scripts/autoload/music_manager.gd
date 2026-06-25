extends Node

# Music manager — autoloaded as `Music`. Drives a single Ovani OvaniPlayer
# (addons/GodotMusicPlayer0.0.9). Rewritten 2026-06-24: the old hand-rolled
# two-player crossfade + discrete 0/1/2 intensity tiers + per-frame end-of-track
# lookahead are gone. Ovani gives us:
#   - sample-accurate seamless looping (reverb tail) — no lookahead/finished net
#   - one song = three phase-locked stems crossfaded by a CONTINUOUS Intensity
#     (0..1), so escalation is smooth and mid-track.
#
# Tracks + per-context eligibility live in a baked catalog
# (res://resources/music/music_library.tres), authored in the Track Manager
# (Dev Menu → Music Lab). The 8 old loose 3-track sets are retired.
#
# Dynamic intensity schema (combat):
#   intensity = COMBAT_BASE
#             + W_WAVE     * (how deep into this combat level — wave progress)
#             + W_PROGRESS * (how deep into the run — combats/sectors cleared)
#             + W_DAMAGE   * (how hurt the player is — hull lost)
#   clamped to [0,1]. A boss pins intensity to 1.0. Non-combat contexts sit at a
#   fixed, calmer level (see CTX_INTENSITY). Music decompresses on level clear.
#
# Public API (unchanged signatures — callers use get_node("/root/Music")):
#   set_context(context, options={})       options.track forces a track; .force re-picks
#   set_combat_progress(wave_idx, total_waves, has_boss)
#   notify_damage(max_hull, hull)          NEW — drives damage-reactive intensity
#   notify_boss_spawned()
#   ramp_down()                            decompress to calm (level-clear breather)
#   set_intensity(level, fade=2.0)         legacy 0/1/2 tier → continuous
#   set_walk_frozen(bool)                  freeze auto intensity changes
#   stop(fade=0.8)

const MusicLibrary := preload("res://scripts/systems/music_library.gd")

const CTX_MENU := "menu"
const CTX_SECTOR := "sector"
const CTX_SIGNAL := "signal"
const CTX_OUTPOST := "outpost"
const CTX_COMBAT := "combat"
const CTX_BOSS := "boss"
const CTX_SILENT := "silent"

const NOMINAL_DB := 0.0
const SILENT_DB := -80.0

# Resting intensity per non-combat context (combat is computed dynamically).
const CTX_INTENSITY := {
	CTX_MENU: 0.0,
	CTX_SECTOR: 0.12,
	CTX_SIGNAL: 0.40,
	CTX_OUTPOST: 0.0,
	CTX_BOSS: 1.0,
}

# Combat intensity weights (sum > 1 on purpose — clamp handles the peak, so a
# hurt player deep in a long level naturally tops out at Main).
const COMBAT_BASE := 0.12
const W_WAVE := 0.50
const W_PROGRESS := 0.22
const W_DAMAGE := 0.30
const PROGRESS_FULL := 6.0      # run-depth (in combats) that maps to a full progress term
const SECTOR_WEIGHT := 4.0      # each cleared sector counts as this many combats of depth

# Crossfade / ramp durations (seconds).
const CTX_FADE := 2.5           # ambient context switch
const COMBAT_ENTER_FADE := 1.4  # snappier drop into combat
const WAVE_FADE := 3.0          # wave-driven escalation glide
const DAMAGE_FADE := 1.2        # damage spikes react faster
const RAMP_FADE := 3.0          # level-clear decompression
const UNSILENCE_FADE := 0.8

var _player: OvaniPlayer = null
var _lib: MusicLibrary = null

var _context: String = CTX_SILENT
var _current_track: String = ""
var _intensity_target: float = 0.0
var _silenced: bool = false

# Combat inputs (each 0..1), combined by _combat_intensity().
var _wave01: float = 0.0
var _damage01: float = 0.0

# When true, auto intensity changes (wave/damage) are suppressed — the track
# keeps playing/looping but won't escalate or de-escalate. Set by the pause menu
# and the cleared summary (Roman: paused / clear screens shouldn't ramp).
var _walk_frozen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # play through the pause menu
	_lib = MusicLibrary.new()
	_player = OvaniPlayer.new()
	_player.name = "OvaniPlayer"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.Bus = "Music"
	_player.LoopQueue = false   # a single queued song loops itself seamlessly
	add_child(_player)
	_player.Volume = NOMINAL_DB
	_player.Intensity = 0.0


# ---- Public API ---------------------------------------------------------

func set_context(context: String, options: Dictionary = {}) -> void:
	var forced: bool = options.get("force", false)
	# Idempotent re-entry: keep the track, just ensure audible + correct energy.
	if context == _context and _current_track != "" and not forced:
		if _silenced:
			_unsilence()
		_apply_context_intensity(CTX_FADE)
		return

	_context = context
	if context == CTX_SILENT:
		stop()
		return
	if _silenced:
		_unsilence()
	if context == CTX_COMBAT:
		_wave01 = 0.0
		_damage01 = 0.0

	var track: String = options.get("track", "")
	if track == "" or not _lib.has_track(track):
		track = _pick_track(context)
	if track == "":
		return

	var fade: float = COMBAT_ENTER_FADE if context == CTX_COMBAT else CTX_FADE
	if track != _current_track or _current_track == "":
		_play_track(track, fade)
	_apply_context_intensity(fade)


func set_combat_progress(wave_idx: int, total_waves: int, _has_boss: bool) -> void:
	if total_waves <= 0:
		return
	# How deep into THIS combat level (0 on the first wave → 1 on the last).
	_wave01 = clampf(float(wave_idx) / maxf(float(total_waves - 1), 1.0), 0.0, 1.0)
	if _context == CTX_COMBAT and not _walk_frozen:
		_set_intensity_target(_combat_intensity(), WAVE_FADE)


# Damage-reactive intensity. Wired off the player's hull_changed signal
# (max_hull, hull) — see main.gd. The hurter the player, the hotter the music.
func notify_damage(max_hull: int, hull: int) -> void:
	if max_hull <= 0:
		return
	_damage01 = clampf(1.0 - float(hull) / float(max_hull), 0.0, 1.0)
	if _context == CTX_COMBAT and not _walk_frozen:
		_set_intensity_target(_combat_intensity(), DAMAGE_FADE)


func notify_boss_spawned() -> void:
	set_context(CTX_BOSS)


# Decompress the current track to calm without switching songs — the level-clear
# breather. Keeps playing so the next context can crossfade smoothly.
func ramp_down() -> void:
	_set_intensity_target(0.0, RAMP_FADE)


# Legacy discrete tier (0=calm, 1=mid, 2=peak) → continuous intensity. Used by
# the patrol-start hangar's scripted escalation.
func set_intensity(level: int, fade: float = 2.0) -> void:
	_set_intensity_target(clampf(float(level) / 2.0, 0.0, 1.0), fade)


func set_walk_frozen(v: bool) -> void:
	_walk_frozen = v


func stop(fade: float = 0.8) -> void:
	if _player == null:
		return
	_player.FadeVolume(SILENT_DB, maxf(fade, 0.05))
	_silenced = true


# ---- Internal -----------------------------------------------------------

func _play_track(track: String, fade: float) -> void:
	var song: OvaniSong = _lib.make_song(track)
	if song == null:
		return
	if _current_track == "":
		_player.QueueSong(song)          # clean first start (no null-queue hop)
	else:
		_player.PlaySongNow(song, fade)  # immediate crossfade over `fade` seconds
	_current_track = track


func _apply_context_intensity(fade: float) -> void:
	var v: float
	if _context == CTX_COMBAT:
		v = _combat_intensity()
	else:
		v = float(CTX_INTENSITY.get(_context, 0.0))
	_set_intensity_target(v, fade)


func _set_intensity_target(v: float, fade: float) -> void:
	_intensity_target = clampf(v, 0.0, 1.0)
	if _player != null:
		_player.FadeIntensity(_intensity_target, maxf(fade, 0.05))


func _combat_intensity() -> float:
	return clampf(
		COMBAT_BASE + W_WAVE * _wave01 + W_PROGRESS * _run_progress01() + W_DAMAGE * _damage01,
		0.0, 1.0)


# How deep into the run we are, 0..1 — combats done this sector plus cleared
# sectors, normalized. Drives the "deeper = hotter" baseline.
func _run_progress01() -> float:
	var run := get_node_or_null("/root/Run")
	if run == null:
		return 0.0
	var combats: float = float(run.combats_in_sector) if "combats_in_sector" in run else 0.0
	var sectors: float = float(run.sectors_cleared) if "sectors_cleared" in run else 0.0
	return clampf((sectors * SECTOR_WEIGHT + combats) / PROGRESS_FULL, 0.0, 1.0)


func _pick_track(context: String) -> String:
	var pool: Array = _lib.eligible(context)
	if pool.is_empty():
		pool = _lib.eligible(CTX_COMBAT)
	if pool.is_empty():
		pool = _lib.track_names()
	if pool.is_empty():
		return ""
	# Avoid repeating the current track when the pool has alternatives.
	var choices: Array = pool.filter(func(n): return n != _current_track)
	if choices.is_empty():
		choices = pool
	return choices[randi() % choices.size()]


func _unsilence() -> void:
	_silenced = false
	if _player != null:
		_player.FadeVolume(NOMINAL_DB, UNSILENCE_FADE)
