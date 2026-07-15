extends Node
class_name ShieldSfx

# Random shield SFX (Roman, 2026-05-18; clip refresh 2026-07-14). Static API:
#   play_hit(parent, world_pos = null)       — one of the 3 hit clips
#   play_break(parent, world_pos = null)     — one of the 4 break clips
#   play_bounce(parent, world_pos = null)    — one of the 5 bounce clips (a shot
#                                              reflected by the Reflective Shield module)
#   play_capacitor(parent, world_pos = null) — one of the 2 Backup Shield Capacitor
#                                              clips (emergency shield restore)
#
# Each call instantiates a one-shot AudioStreamPlayer2D (or AudioStreamPlayer
# if no world_pos given) so overlapping hits all play. The node frees
# itself when the stream finishes.

const HIT_CLIPS := [
	preload("res://assets/audio/shield/shield_hit_1.ogg"),
	preload("res://assets/audio/shield/shield_hit_2.ogg"),
	preload("res://assets/audio/shield/shield_hit_3.ogg"),
]
const BREAK_CLIPS := [
	preload("res://assets/audio/shield/shield_break_1.ogg"),
	preload("res://assets/audio/shield/shield_break_2.ogg"),
	preload("res://assets/audio/shield/shield_break_3.ogg"),
	preload("res://assets/audio/shield/shield_break_4.ogg"),
]
const BOUNCE_CLIPS := [
	preload("res://assets/audio/shield/shield_bounce_1.ogg"),
	preload("res://assets/audio/shield/shield_bounce_2.ogg"),
	preload("res://assets/audio/shield/shield_bounce_3.ogg"),
	preload("res://assets/audio/shield/shield_bounce_4.ogg"),
	preload("res://assets/audio/shield/shield_bounce_5.ogg"),
]
const CAPACITOR_CLIPS := [
	preload("res://assets/audio/shield/shield_backup_capacitor_1.ogg"),
	preload("res://assets/audio/shield/shield_backup_capacitor_2.ogg"),
]

const HIT_VOLUME_DB: float = -2.0
const BREAK_VOLUME_DB: float = 0.0
const BOUNCE_VOLUME_DB: float = -2.0
const CAPACITOR_VOLUME_DB: float = 0.0


static func play_hit(parent: Node, world_pos = null) -> void:
	if HIT_CLIPS.is_empty():
		return
	var clip: AudioStream = HIT_CLIPS[randi() % HIT_CLIPS.size()]
	_play(parent, world_pos, clip, HIT_VOLUME_DB)


static func play_break(parent: Node, world_pos = null) -> void:
	if BREAK_CLIPS.is_empty():
		return
	var clip: AudioStream = BREAK_CLIPS[randi() % BREAK_CLIPS.size()]
	_play(parent, world_pos, clip, BREAK_VOLUME_DB)


static func play_bounce(parent: Node, world_pos = null) -> void:
	if BOUNCE_CLIPS.is_empty():
		return
	var clip: AudioStream = BOUNCE_CLIPS[randi() % BOUNCE_CLIPS.size()]
	_play(parent, world_pos, clip, BOUNCE_VOLUME_DB)


static func play_capacitor(parent: Node, world_pos = null) -> void:
	if CAPACITOR_CLIPS.is_empty():
		return
	var clip: AudioStream = CAPACITOR_CLIPS[randi() % CAPACITOR_CLIPS.size()]
	_play(parent, world_pos, clip, CAPACITOR_VOLUME_DB)


static func _play(parent: Node, world_pos, clip: AudioStream, volume_db: float) -> void:
	if parent == null or clip == null:
		return
	if world_pos is Vector2:
		var p := AudioStreamPlayer2D.new()
		p.stream = clip
		p.volume_db = volume_db
		p.bus = "SFX"
		p.global_position = world_pos
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = clip
		p.volume_db = volume_db
		p.bus = "SFX"
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
