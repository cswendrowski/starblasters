extends Node
class_name ShieldSfx

# Random shield-hit / shield-break SFX (Roman, 2026-05-18). Static API:
#   play_hit(parent, world_pos = null)   — one of the 5 hit clips
#   play_break(parent, world_pos = null) — one of the 3 break clips
#
# Each call instantiates a one-shot AudioStreamPlayer2D (or AudioStreamPlayer
# if no world_pos given) so overlapping hits all play. The node frees
# itself when the stream finishes.

const HIT_CLIPS := [
	preload("res://Sound/shield/Shield_Hit_1.ogg"),
	preload("res://Sound/shield/Shield_Hit_2.ogg"),
	preload("res://Sound/shield/Shield_Hit_3.ogg"),
	preload("res://Sound/shield/Shield_Hit_4.ogg"),
	preload("res://Sound/shield/Shield_Hit_5.ogg"),
]
const BREAK_CLIPS := [
	preload("res://Sound/shield/Shield_Break_1.ogg"),
	preload("res://Sound/shield/Shield_Break_2.ogg"),
	preload("res://Sound/shield/Shield_Break_3.ogg"),
]

const HIT_VOLUME_DB: float = -2.0
const BREAK_VOLUME_DB: float = 0.0


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


static func _play(parent: Node, world_pos, clip: AudioStream, volume_db: float) -> void:
	if parent == null or clip == null:
		return
	if world_pos is Vector2:
		var p := AudioStreamPlayer2D.new()
		p.stream = clip
		p.volume_db = volume_db
		p.global_position = world_pos
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = clip
		p.volume_db = volume_db
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
