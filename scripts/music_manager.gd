extends Node

# Music manager — autoloaded as `Music`. Handles track sets, intensity walks,
# end-of-track crossfade handoff, and cross-scene crossfade.
#
# Concepts:
#   - A "set" is a named group of three tracks indexed 0..2 by intensity:
#       Intensity_1 (calm) → Intensity_2 (med) → Main (peak)
#   - A "context" tells the manager how to behave:
#       MENU / SECTOR / SIGNAL / OUTPOST → random walk on the ladder
#       COMBAT → ladder index driven by wave progress; Main reserved for boss
#       BOSS → pin to Main
#   - Two AudioStreamPlayer slots used to overlap a fade-out and a fade-in.
#
# Public API:
#   set_context(context: String, options: Dictionary = {})
#     options.set_name: force a specific set; otherwise the manager picks.
#   set_combat_progress(wave_idx: int, total_waves: int, has_boss: bool)
#   notify_boss_spawned()
#   stop(fade: float = 0.6)

const FADE_LEN := 3.0              # crossfade duration in seconds
const END_LOOKAHEAD := FADE_LEN + 0.10  # start crossfade when this close to end
const TARGET_DB := -6.0            # full-volume target
const SILENT_DB := -60.0

const SET_GALAXY := "galaxy"
const SET_CREEP := "creep"
const SET_BREAK := "break"
const SET_CHUGGA := "chugga"
const SET_KNUCKLES := "knuckles"
const SET_FRIDGE := "fridge"
const SET_MINESHAFT := "mineshaft"
const SET_SHADOWRUN := "shadowrun"

const CTX_MENU := "menu"
const CTX_SECTOR := "sector"
const CTX_SIGNAL := "signal"
const CTX_OUTPOST := "outpost"
const CTX_COMBAT := "combat"
const CTX_BOSS := "boss"
const CTX_SILENT := "silent"

# Track sets — three intensity tiers each.
var _sets: Dictionary = {
	SET_GALAXY: [
		preload("res://Sound/music/Galaxy_Intensity_1.ogg"),
		preload("res://Sound/music/Galaxy_Intensity_2.ogg"),
		preload("res://Sound/music/Galaxy_Main.ogg"),
	],
	SET_CREEP: [
		preload("res://Sound/music/Creep_Intensity_1.ogg"),
		preload("res://Sound/music/Creep_Intensity_2.ogg"),
		preload("res://Sound/music/Creep_Main.ogg"),
	],
	SET_BREAK: [
		preload("res://Sound/music/Break_Intensity_1.ogg"),
		preload("res://Sound/music/Break_Intensity_2.ogg"),
		preload("res://Sound/music/Break_Main.ogg"),
	],
	SET_CHUGGA: [
		preload("res://Sound/music/Chugga_Intensity_1.ogg"),
		preload("res://Sound/music/Chugga_Intensity_2.ogg"),
		preload("res://Sound/music/Chugga_Main.ogg"),
	],
	SET_KNUCKLES: [
		preload("res://Sound/music/Knuckles_Intensity_1.ogg"),
		preload("res://Sound/music/Knuckles_Intensity_2.ogg"),
		preload("res://Sound/music/Knuckles_Main.ogg"),
	],
	SET_FRIDGE: [
		preload("res://Sound/music/Fridge_Intensity_1.ogg"),
		preload("res://Sound/music/Fridge_Intensity_2.ogg"),
		preload("res://Sound/music/Fridge_Main.ogg"),
	],
	SET_MINESHAFT: [
		preload("res://Sound/music/Mineshaft_Intensity_1.ogg"),
		preload("res://Sound/music/Mineshaft_Intensity_2.ogg"),
		preload("res://Sound/music/Mineshaft_Main.ogg"),
	],
	SET_SHADOWRUN: [
		preload("res://Sound/music/Shadowrun_Intensity_1.ogg"),
		preload("res://Sound/music/Shadowrun_Intensity_2.ogg"),
		preload("res://Sound/music/Shadowrun_Main.ogg"),
	],
}

# Per-context set pools. set_context() picks one randomly when caller doesn't
# specify; combat falls back to "any" so each level rolls a fresh set.
var _context_sets: Dictionary = {
	CTX_MENU: [SET_GALAXY],
	CTX_SECTOR: [SET_CREEP],
	CTX_SIGNAL: [SET_CREEP, SET_GALAXY],
	CTX_OUTPOST: [SET_GALAXY, SET_CREEP],
	CTX_COMBAT: [SET_BREAK, SET_CHUGGA, SET_KNUCKLES, SET_FRIDGE, SET_MINESHAFT, SET_SHADOWRUN],
	CTX_BOSS: [SET_BREAK, SET_CHUGGA, SET_KNUCKLES, SET_FRIDGE, SET_MINESHAFT, SET_SHADOWRUN],
}

var _active: AudioStreamPlayer = null
var _next: AudioStreamPlayer = null
var _active_set: String = ""
var _active_idx: int = 0           # 0/1/2 in _sets[_active_set]
var _context: String = CTX_SILENT
var _combat_target_idx: int = 0
var _allow_main: bool = false      # combat: Main is gated until boss appears
var _crossfading: bool = false
var _fade_tween: Tween = null
# When true, the per-frame end-of-track check skips the intensity walk —
# track keeps playing through but won't escalate or de-escalate. Toggled
# on by the pause menu and cleared screens (Roman, 2026-05-16: "When
# paused or in a clear screen music should not escalate or deescalate").
var _walk_frozen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # play through pause menu
	_active = _make_player("MusicA")
	_next = _make_player("MusicB")
	add_child(_active)
	add_child(_next)


func _make_player(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = name
	p.bus = "Music"
	p.volume_db = SILENT_DB
	# Safety net: the per-frame lookahead (line ~215) is the primary path for
	# end-of-track handoff, but if it misses (frame skip, oddly-reported
	# stream length, etc.) the track ends and we go silent until the next
	# set_context. Catch `finished` so we always recover into a fresh
	# intensity crossfade (Cody, 2026-05-19 playtest: "music does not loop").
	p.finished.connect(_on_player_finished.bind(p))
	return p


func _on_player_finished(p: AudioStreamPlayer) -> void:
	# Only react when this player is the currently-active one AND the
	# crossfade machinery didn't already take over. The swap in
	# _on_crossfade_done calls stop() on the previous active, which does NOT
	# emit `finished`, so this only fires on a genuine end-of-stream miss.
	if _walk_frozen or _crossfading or _context == CTX_SILENT:
		return
	if p != _active or _active_set == "":
		return
	var next_idx: int = _pick_next_idx()
	_crossfade_to(_active_set, next_idx, FADE_LEN)


# ---- Public API ---------------------------------------------------------

func set_context(context: String, options: Dictionary = {}) -> void:
	# Idempotent: re-entering the same context doesn't restart the track.
	if context == _context and _active and _active.playing:
		return
	_context = context
	if context == CTX_SILENT:
		stop()
		return
	var set_name: String = options.get("set_name", "")
	if set_name == "" or not _sets.has(set_name):
		set_name = _pick_set_for(context)
	# Starting intensity: contexts that random-walk begin at 0; combat starts
	# at 0; boss pins to 2 (Main).
	_combat_target_idx = 0
	_allow_main = (context != CTX_COMBAT)  # only combat gates Main
	var start_idx: int = 0
	if context == CTX_BOSS:
		start_idx = 2
	_active_set = set_name
	_active_idx = start_idx
	_crossfade_to(set_name, start_idx, FADE_LEN)


func set_combat_progress(wave_idx: int, total_waves: int, has_boss: bool) -> void:
	# Roman, 2026-05-16: intensity ramps at the *middle* of the wave list,
	# not gradually. Main stays gated until the boss actually spawns; without
	# a boss combat caps at Intensity_2.
	#   First half → Intensity_1 (0)
	#   Second half → Intensity_2 (1)
	#   Main (2)  → only via notify_boss_spawned()
	if total_waves <= 0:
		return
	var midpoint: int = int(floor(float(total_waves) / 2.0))
	var target: int = 0 if wave_idx < midpoint else 1
	_allow_main = false  # combat: Main is boss-only
	_combat_target_idx = target


func notify_boss_spawned() -> void:
	_allow_main = true
	_combat_target_idx = 2
	set_context(CTX_BOSS)


# Ramp the current set down to Intensity_1 without changing sets. Use when
# entering a low-energy transition screen (cleared summary, post-combat
# breather) so the music decompresses before the next context kicks in.
func ramp_down() -> void:
	if _active == null or not _active.playing or _active_set == "":
		return
	if _active_idx == 0:
		return
	_combat_target_idx = 0
	_crossfade_to(_active_set, 0, FADE_LEN)


func stop(fade: float = 0.6) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	if _active and _active.playing:
		_fade_tween.tween_property(_active, "volume_db", SILENT_DB, fade)
	if _next and _next.playing:
		_fade_tween.tween_property(_next, "volume_db", SILENT_DB, fade)
	_fade_tween.chain().tween_callback(func():
		if _active: _active.stop()
		if _next: _next.stop()
		_crossfading = false
	)


# ---- Per-frame: detect end-of-track and start crossfade -----------------

func _process(_delta: float) -> void:
	if _walk_frozen:
		return
	if _crossfading or _active == null or not _active.playing or _active.stream == null:
		return
	var stream_len: float = _active.stream.get_length()
	if stream_len <= 0.0:
		return
	var pos: float = _active.get_playback_position()
	if stream_len - pos > END_LOOKAHEAD:
		return
	# Reached the tail: pick the next intensity per current context, hand off.
	var next_idx: int = _pick_next_idx()
	_crossfade_to(_active_set, next_idx, FADE_LEN)


# Public freeze toggle. Pause menu sets this on entry/exit; cleared
# summary turns it on while the screen holds.
func set_walk_frozen(v: bool) -> void:
	_walk_frozen = v


# ---- Internal -----------------------------------------------------------

func _pick_set_for(context: String) -> String:
	var pool: Array = _context_sets.get(context, [SET_GALAXY])
	if pool.is_empty():
		return SET_GALAXY
	return pool[randi() % pool.size()]


func _pick_next_idx() -> int:
	# Per-context walk rule.
	match _context:
		CTX_MENU, CTX_SECTOR, CTX_SIGNAL, CTX_OUTPOST:
			# Random step ±1, clamped to [0, 2]. Re-rolls to a neighbor each
			# time the current track ends; gives the 1-2-Main-2-1 feel Roman
			# described without a fixed pattern.
			var step: int = (1 if randf() < 0.5 else -1)
			# Edges always step inward.
			if _active_idx == 0:
				step = 1
			elif _active_idx == 2:
				step = -1
			return clamp(_active_idx + step, 0, 2)
		CTX_COMBAT:
			# Walk one step toward the combat target. Respect the Main gate.
			var dir: int = sign(_combat_target_idx - _active_idx)
			var nxt: int = _active_idx + dir
			if not _allow_main:
				nxt = min(nxt, 1)
			return clamp(nxt, 0, 2)
		CTX_BOSS:
			return 2
		_:
			return _active_idx


func _crossfade_to(set_name: String, idx: int, fade_seconds: float) -> void:
	if not _sets.has(set_name):
		return
	idx = clamp(idx, 0, 2)
	var stream: AudioStream = _sets[set_name][idx]
	if stream == null:
		return
	# Bring up _next on the new stream, fade _active out, then swap roles.
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_next.stream = stream
	_next.volume_db = SILENT_DB
	_next.play()
	_crossfading = true
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(_next, "volume_db", TARGET_DB, fade_seconds)
	if _active and _active.playing:
		_fade_tween.tween_property(_active, "volume_db", SILENT_DB, fade_seconds)
	_fade_tween.chain().tween_callback(func(): _on_crossfade_done(set_name, idx))


func _on_crossfade_done(set_name: String, idx: int) -> void:
	if _active and _active.playing:
		_active.stop()
	# Swap so _active points at the now-playing stream.
	var swap: AudioStreamPlayer = _active
	_active = _next
	_next = swap
	_active_set = set_name
	_active_idx = idx
	_crossfading = false
