extends Node

# Player warning-alarm loops (Roman 2026-07-14). Two looping klaxons driven off live
# player state, added as a child of the Player node (player._ready) and re-armed per
# combat level via reset() (player.start()).
#
#   Shield alarm — plays while a Shield Core is equipped (max_shield > 0) and the
#     charge pool sits at 0. Stops the moment a charge comes back.
#   Hull alarm — plays while hull is at 0 pips (next hit kills). Suppressed under the
#     Glass Patrol condition (player.glass_hull — every hull hit is lethal there, the
#     alarm would just always scream) and until the player has actually HELD a hull
#     pip this level, so a run that ENTERS a level at 0 hull stays silent until hull
#     rises above 0 at least once. While the player has shield charges the hull alarm
#     ducks to full silence; it eases back in when the shield empties again.
#
# Both alarms hold full volume for FULL_SECONDS then fade to DUCK_FRACTION so a long
# shields-down / hull-critical stretch isn't grating.
#
# State is POLLED per physics frame rather than signal-driven, deliberately: a Backup
# Shield Capacitor restore happens synchronously inside one take_damage() call
# (shield → 0 → back up before the frame ends), so the poll never observes the
# transient 0 and the capacitor bypasses the shield alarm entirely — per spec.

const SHIELD_LOOP := preload("res://assets/audio/shield/shield_alarm_loop.ogg")
const HULL_LOOP := preload("res://assets/audio/hull/hull_alarm_loop.ogg")

const BASE_VOLUME_DB: float = -6.0   # alarm loudness at full (envelope = 1.0)
const FULL_SECONDS: float = 2.0      # full-volume window after an alarm trips
const DUCK_FRACTION: float = 0.15    # long-run floor (15% linear) after the window
const DUCK_FADE_SECONDS: float = 1.0 # how long the 100% → 15% fade takes
const GATE_FADE_SECONDS: float = 0.6 # hull alarm ease-out/in as shield charges come and go
const SILENT_DB: float = -60.0

var _player: Node = null
var _shield_p: AudioStreamPlayer = null
var _hull_p: AudioStreamPlayer = null
var _shield_t: float = 0.0     # seconds the shield alarm has been active
var _hull_t: float = 0.0       # seconds the hull alarm has been active
var _hull_gate: float = 1.0    # eased 0–1 mult: 0 while shield charges are up
var _hull_armed: bool = false  # set once hull > 0 is seen this level


func _ready() -> void:
	_player = get_parent()
	_shield_p = _make_loop_player(SHIELD_LOOP)
	_hull_p = _make_loop_player(HULL_LOOP)


# Per-combat re-arm, called from player.start().
func reset() -> void:
	_hull_armed = false
	_shield_t = 0.0
	_hull_t = 0.0
	_hull_gate = 1.0
	if _shield_p != null:
		_shield_p.stop()
	if _hull_p != null:
		_hull_p.stop()


func _physics_process(delta: float) -> void:
	if _player == null or not ("is_alive" in _player):
		return
	var alive: bool = _player.is_alive
	# Arm the hull alarm only once the player has actually held a pip this level.
	if alive and int(_player.hull) > 0:
		_hull_armed = true

	var shield_on: bool = alive and int(_player.max_shield) > 0 and int(_player.shield) <= 0
	var hull_on: bool = alive and _hull_armed and int(_player.hull) <= 0 and not _glass_patrol()

	_shield_t = _drive(_shield_p, shield_on, _shield_t, delta, 1.0)

	# Shield charges duck the hull alarm to silence; it eases back when they're gone.
	var gate_target: float = 0.0 if (alive and int(_player.shield) > 0) else 1.0
	_hull_gate = move_toward(_hull_gate, gate_target, delta / GATE_FADE_SECONDS)
	_hull_t = _drive(_hull_p, hull_on, _hull_t, delta, _hull_gate)


# Advance one alarm: start/stop the loop on state edges, apply the envelope × gate
# volume while active. Returns the updated active-time accumulator.
func _drive(p: AudioStreamPlayer, active: bool, t: float, delta: float, gate: float) -> float:
	if p == null:
		return 0.0
	if not active:
		if p.playing:
			p.stop()
		return 0.0
	if not p.playing:
		t = 0.0
		p.play()
	else:
		t += delta
	var v: float = _envelope(t) * clampf(gate, 0.0, 1.0)
	p.volume_db = (BASE_VOLUME_DB + linear_to_db(v)) if v > 0.001 else SILENT_DB
	return t


# 1.0 for the first FULL_SECONDS, then a linear fade down to DUCK_FRACTION.
func _envelope(t: float) -> float:
	if t <= FULL_SECONDS:
		return 1.0
	var k: float = clampf((t - FULL_SECONDS) / DUCK_FADE_SECONDS, 0.0, 1.0)
	return lerpf(1.0, DUCK_FRACTION, k)


func _glass_patrol() -> bool:
	var run = get_node_or_null("/root/Run")
	return run != null and run.cond_flag("player.glass_hull")


func _make_loop_player(clip: AudioStream) -> AudioStreamPlayer:
	# Duplicate before forcing loop on — the preloaded resource is shared and the
	# .import sidecars author these clips loop=false.
	var stream: AudioStream = clip.duplicate()
	if "loop" in stream:
		stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = BASE_VOLUME_DB
	add_child(p)
	return p
