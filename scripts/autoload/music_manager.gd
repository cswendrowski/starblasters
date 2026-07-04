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
# Dynamic intensity schema (combat) — a CEILING the music ramps UP TO, never snaps to:
#   ceiling = COMBAT_BASE
#           + W_WAVE     * (how deep into this combat level — wave progress)
#           + W_PROGRESS * (how deep into the run — combats/sectors cleared)
#           + W_DAMAGE   * (how hurt the player is — hull lost)
#   The per-frame GOAL (see _process) is:
#     goal = presence * ceiling + W_STREAK * streak_heat   (clamped [0,1])
#   where `presence` (0..1, raw enemy count / CROWD_FULL) makes combat OPEN QUIET and
#   rise as enemies arrive, and `streak_heat` is a mild, decaying lift from rapid kills.
#   The applied intensity DAMPS toward that goal each frame (asymmetric exponential
#   smoothing — gentler on the way down), so moves are buffered and brief action spikes
#   only partially land before they subside. A boss pins intensity to 1.0. Non-combat
#   contexts sit at a fixed, calmer level (CTX_INTENSITY). Music decompresses on clear.
#
# Loading screens warm combat up: warm_up_combat() starts a combat track at 0 and
# ramps to a middle-low "warming" level during the load; set_context("combat") then
# hands off from there instead of jamming combat music into place at level start.
#
# Public API (callers use get_node("/root/Music")):
#   set_context(context, options={})       options.track forces a track; .force re-picks
#   set_combat_progress(wave_idx, total_waves, has_boss)   raises the combat ceiling
#   notify_damage(max_hull, hull)          raises the ceiling as the player is hurt
#   notify_kill()                          adds kill-streak heat (mild, decays)
#   warm_up_combat(target=.22, ramp=3)     NEW — loading-screen combat pre-heat
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

# Live combat envelope (per-frame "breathing"). Tune these for moment-to-moment feel.
const CROWD_FULL := 5.0         # live enemy count that saturates presence (→ full ceiling)
const W_STREAK := 0.15          # max intensity lift from a hot kill streak (mild on purpose)
const STREAK_GAIN := 0.34       # streak heat added per kill (~3 fast kills → full lift)
const STREAK_DECAY := 0.5       # streak heat lost/sec when not killing (~2s to fade out)

# Damping / buffering: the applied intensity eases toward the goal with these
# exponential time constants (seconds). Larger = smoother + more lag, and brief
# action spikes are attenuated more. Falling is gentler than rising on purpose.
const INTENSITY_RISE_TAU := 1.1 # smoothing while intensity is climbing
const INTENSITY_FALL_TAU := 2.6 # smoothing while intensity is dropping (gentler)

# Loading-screen combat warm-up.
const WARM_TARGET := 0.22       # middle-low intensity to warm up to before combat starts
const WARM_RAMP := 3.0          # seconds to ramp 0 → WARM_TARGET during the load
const WARM_ENTER_FADE := 2.0    # crossfade INTO the combat track when warm-up begins

var _player: OvaniPlayer = null
var _lib: MusicLibrary = null

var _context: String = CTX_SILENT
var _current_track: String = ""
var _intensity_target: float = 0.0
var _silenced: bool = false

# Combat ceiling inputs (each 0..1), combined by _combat_ceiling().
var _wave01: float = 0.0
var _damage01: float = 0.0

# Live combat envelope state (driven per-frame in _process while in combat).
var _combat_active: bool = false     # true only in CTX_COMBAT: run the live envelope
var _warming: bool = false           # loading-screen combat warm-up in progress
var _intensity_smoothed: float = 0.0 # damped applied combat intensity (the buffer)
var _streak_heat: float = 0.0        # kill-streak heat 0..1, decays over time

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
	# Silent is special: always fade out. Handled BEFORE the idempotency check so
	# re-entering silent (e.g. returning to the dev menu) can never hit the
	# keep-playing path and un-silence a leftover track.
	if context == CTX_SILENT:
		_context = CTX_SILENT
		_combat_active = false
		_warming = false
		stop()
		return

	var forced: bool = options.get("force", false)
	# Idempotent re-entry: keep the track, just ensure audible + correct energy.
	# (Skipped while warming so the warm-up → combat handoff below always runs.)
	if context == _context and _current_track != "" and not forced and not _warming:
		if _silenced:
			_unsilence()
		if context != CTX_COMBAT:
			_apply_context_intensity(CTX_FADE)   # combat energy is driven live in _process
		return

	# Handing off from a loading-screen warm-up into actual combat: keep the
	# already-playing combat track and its warmed intensity; just seed the damping
	# buffer and switch the live envelope on (no reset-to-0, no re-pick, no jam).
	var was_warming: bool = _warming and context == CTX_COMBAT
	_warming = false
	_context = context
	if _silenced:
		_unsilence()

	# Combat runs a live per-frame envelope (_process); everything else glides to
	# a fixed resting intensity.
	_combat_active = (context == CTX_COMBAT)
	if was_warming and _player != null:
		_intensity_smoothed = _player.Intensity            # continue from the warmed level
		_player.FadeIntensity(_player.Intensity, 0.05)     # end the warm ramp; _process drives now
		return
	if _combat_active:
		# Cold open — reset combat inputs, then EASE from the current intensity down
		# to the (low) combat goal via _process. Do NOT snap Intensity to 0: it's a
		# global knob, so a hard set jolts the outgoing track's stem mix in one
		# frame = a pop on the transition. The combat goal is ~0 at open (no enemies)
		# so the ease is quiet anyway.
		_wave01 = 0.0
		_damage01 = 0.0
		_streak_heat = 0.0
		if _player != null:
			_intensity_smoothed = _player.Intensity
			_player.FadeIntensity(_player.Intensity, 0.05)  # claim/cancel any stale fade at the current value
		else:
			_intensity_smoothed = 0.0

	var track: String = options.get("track", "")
	if track == "" or not _lib.has_track(track):
		track = _pick_track(context)
	if track == "":
		return

	var fade: float = COMBAT_ENTER_FADE if context == CTX_COMBAT else CTX_FADE
	if track != _current_track or _current_track == "":
		_play_track(track, fade)
	if not _combat_active:
		_apply_context_intensity(fade)


func set_combat_progress(wave_idx: int, total_waves: int, _has_boss: bool) -> void:
	if total_waves <= 0:
		return
	# Raises the combat CEILING (the live envelope in _process ramps toward it).
	# 0 on the first wave → 1 on the last.
	_wave01 = clampf(float(wave_idx) / maxf(float(total_waves - 1), 1.0), 0.0, 1.0)


# Raises the combat ceiling as the player is hurt. Wired off the player's
# hull_changed signal (max_hull, hull) — see main.gd. Applied live in _process.
func notify_damage(max_hull: int, hull: int) -> void:
	if max_hull <= 0:
		return
	_damage01 = clampf(1.0 - float(hull) / float(max_hull), 0.0, 1.0)


# A kill adds "heat" to the streak meter, nudging combat intensity up; the heat
# decays in _process so the lift fades when the player stops scoring. Mild by
# design (capped at W_STREAK). Wired off the director's enemy_died — see main.gd.
func notify_kill() -> void:
	if _context == CTX_COMBAT:
		_streak_heat = minf(1.0, _streak_heat + STREAK_GAIN)


# Loading-screen combat pre-heat. Begins a combat track quietly and ramps it to a
# middle-low "warming up" level over `ramp` seconds, so combat doesn't jam into
# place when the level starts. The subsequent set_context("combat") (main.gd, at
# level start) hands off from this warmed state — keeping the track + intensity —
# instead of cold-opening at 0. Call when a load into a combat node begins
# (LevelLauncher.go). The live envelope stays OFF until combat actually starts.
func warm_up_combat(target_intensity: float = WARM_TARGET, ramp: float = WARM_RAMP) -> void:
	if _player == null:
		return
	if _silenced:
		_unsilence()
	_warming = true
	_combat_active = false
	_context = CTX_COMBAT
	_wave01 = 0.0
	_damage01 = 0.0
	_streak_heat = 0.0
	_intensity_smoothed = 0.0
	var track: String = _pick_track(CTX_COMBAT)
	if track != "" and (track != _current_track or _current_track == ""):
		_play_track(track, WARM_ENTER_FADE)
	# Ramp intensity from the current level to the warm target (no hard set to 0 —
	# that pops the outgoing track). The combat track fades IN by volume anyway
	# (WARM_ENTER_FADE), so the warm-up still starts quiet.
	_set_intensity_target(clampf(target_intensity, 0.0, 1.0), maxf(ramp, 0.05))


func notify_boss_spawned() -> void:
	set_context(CTX_BOSS)


# Decompress the current track to calm without switching songs — the level-clear
# breather. Stops the live envelope so the breather can settle; keeps playing so
# the next context can crossfade smoothly.
func ramp_down() -> void:
	_combat_active = false
	_warming = false
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
	# Non-combat resting intensity. (Combat is driven live in _process, not here.)
	_set_intensity_target(float(CTX_INTENSITY.get(_context, 0.0)), fade)


func _set_intensity_target(v: float, fade: float) -> void:
	_intensity_target = clampf(v, 0.0, 1.0)
	if _player != null:
		_player.FadeIntensity(_intensity_target, maxf(fade, 0.05))


# The steady-state combat intensity for the current wave depth, run depth, and
# damage — the CEILING the live envelope ramps toward (it never just snaps here).
func _combat_ceiling() -> float:
	return clampf(
		COMBAT_BASE + W_WAVE * _wave01 + W_PROGRESS * _run_progress01() + W_DAMAGE * _damage01,
		0.0, 1.0)


# Live combat envelope. Computes a GOAL intensity from how much is actually
# happening — enemies present (presence) plus recent kills (streak) — then DAMPS
# the applied intensity toward it, so moves are buffered and brief action spikes
# only partially land. Combat opens quiet and breathes. Non-combat contexts hold
# their fixed FadeIntensity target, so there's nothing to do for them here.
func _process(delta: float) -> void:
	if not _combat_active or _context != CTX_COMBAT or _walk_frozen or _player == null:
		return
	var count := get_tree().get_node_count_in_group("enemies")
	var presence := clampf(float(count) / CROWD_FULL, 0.0, 1.0)
	# Kill-streak heat decays toward 0 when the player stops scoring.
	_streak_heat = maxf(0.0, _streak_heat - STREAK_DECAY * delta)
	var goal := clampf(presence * _combat_ceiling() + W_STREAK * _streak_heat, 0.0, 1.0)
	# Damped follow (the buffer): ease toward the goal with an exponential, frame-
	# rate-independent step — gentler when falling. Short spikes never fully land
	# because the gap only closes a fraction before the spike subsides.
	var tau := INTENSITY_RISE_TAU if goal > _intensity_smoothed else INTENSITY_FALL_TAU
	_intensity_smoothed = lerpf(_intensity_smoothed, goal, 1.0 - exp(-delta / maxf(tau, 0.01)))
	_player.Intensity = _intensity_smoothed


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
