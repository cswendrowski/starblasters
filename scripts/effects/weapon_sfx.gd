extends Node
class_name WeaponSfx

# Per-cannon firing sounds (Roman, 2026-05-18). Static API:
#   play(parent, world_pos, kind)
# `kind` is a string from WS.sfx_kind_string(ship.fire_sfx_kind) — the
# cannon part writes the enum, player.fire_primary bridges it to a string
# here. Pool keys:
#   "blaster_small" — Energy Blaster (5 clips)
#   "blaster_large" — Heavy Blaster   (4 clips)
# Future kinds (laser, wave, rockets, seeking) get clips dropped into
# Sound/weapons/ and added to the dictionary below.

const SMALL_CLIPS := [
	preload("res://Sound/weapons/blaster_small_1.ogg"),
	preload("res://Sound/weapons/blaster_small_2.ogg"),
	preload("res://Sound/weapons/blaster_small_3.ogg"),
	preload("res://Sound/weapons/blaster_small_4.ogg"),
	preload("res://Sound/weapons/blaster_small_5.ogg"),
]
const LARGE_CLIPS := [
	preload("res://Sound/weapons/blaster_large_1.ogg"),
	preload("res://Sound/weapons/blaster_large_2.ogg"),
	preload("res://Sound/weapons/blaster_large_3.ogg"),
	preload("res://Sound/weapons/blaster_large_4.ogg"),
]
const PULSE_CLIPS := [
	preload("res://Sound/weapons/pulse_1.ogg"),
	preload("res://Sound/weapons/pulse_2.ogg"),
	preload("res://Sound/weapons/pulse_3.ogg"),
	preload("res://Sound/weapons/pulse_4.ogg"),
	preload("res://Sound/weapons/pulse_5.ogg"),
]
const ROCKET_CLIPS := [
	preload("res://Sound/weapons/rocket_launch_1.ogg"),
	preload("res://Sound/weapons/rocket_launch_2.ogg"),
]
const MISSILE_CLIPS := [
	preload("res://Sound/weapons/missile_launch_1.ogg"),
	preload("res://Sound/weapons/missile_launch_2.ogg"),
]

const VOLUME_DB: float = -4.0


static func play(parent: Node, world_pos, kind: String) -> void:
	if parent == null:
		return
	var pool: Array = []
	match kind:
		"blaster_small":
			pool = SMALL_CLIPS
		"blaster_large":
			pool = LARGE_CLIPS
		"pulse":
			pool = PULSE_CLIPS
		"rocket":
			pool = ROCKET_CLIPS
		"missile":
			pool = MISSILE_CLIPS
		_:
			return
	if pool.is_empty():
		return
	var clip: AudioStream = pool[randi() % pool.size()]
	if clip == null:
		return
	if world_pos is Vector2:
		var p := AudioStreamPlayer2D.new()
		p.stream = clip
		p.volume_db = VOLUME_DB
		p.global_position = world_pos
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = clip
		p.volume_db = VOLUME_DB
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
