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
	preload("res://Sound/weapons/player/blaster_small_1.ogg"),
	preload("res://Sound/weapons/player/blaster_small_2.ogg"),
	preload("res://Sound/weapons/player/blaster_small_3.ogg"),
	preload("res://Sound/weapons/player/blaster_small_4.ogg"),
	preload("res://Sound/weapons/player/blaster_small_5.ogg"),
]
const LARGE_CLIPS := [
	preload("res://Sound/weapons/player/blaster_large_1.ogg"),
	preload("res://Sound/weapons/player/blaster_large_2.ogg"),
	preload("res://Sound/weapons/player/blaster_large_3.ogg"),
	preload("res://Sound/weapons/player/blaster_large_4.ogg"),
]
const PULSE_CLIPS := [
	preload("res://Sound/weapons/player/pulse_1.ogg"),
	preload("res://Sound/weapons/player/pulse_2.ogg"),
	preload("res://Sound/weapons/player/pulse_3.ogg"),
	preload("res://Sound/weapons/player/pulse_4.ogg"),
	preload("res://Sound/weapons/player/pulse_5.ogg"),
]
# Wave Gun. WAVE = Mk.1-4 small projectile; WAVE_BIG = Mk.5+ large wave
# (wave_gun_cannon picks the kind by mark in _apply_visuals).
const WAVE_CLIPS := [
	preload("res://Sound/weapons/player/wave_shoot_1.ogg"),
	preload("res://Sound/weapons/player/wave_shoot_2.ogg"),
	preload("res://Sound/weapons/player/wave_shoot_3.ogg"),
	preload("res://Sound/weapons/player/wave_shoot_4.ogg"),
	preload("res://Sound/weapons/player/wave_shoot_5.ogg"),
	preload("res://Sound/weapons/player/wave_shoot_6.ogg"),
]
const WAVE_BIG_CLIPS := [
	preload("res://Sound/weapons/player/wave_big_shoot_1.ogg"),
	preload("res://Sound/weapons/player/wave_big_shoot_2.ogg"),
	preload("res://Sound/weapons/player/wave_big_shoot_3.ogg"),
	preload("res://Sound/weapons/player/wave_big_shoot_4.ogg"),
	preload("res://Sound/weapons/player/wave_big_shoot_5.ogg"),
	preload("res://Sound/weapons/player/wave_big_shoot_6.ogg"),
]
# Rocket + missile live in the universal/ folder — shared by player AND enemies.
const ROCKET_CLIPS := [
	preload("res://Sound/weapons/universal/rocket_launch_1.ogg"),
	preload("res://Sound/weapons/universal/rocket_launch_2.ogg"),
]
const MISSILE_CLIPS := [
	preload("res://Sound/weapons/universal/missile_launch_1.ogg"),
	preload("res://Sound/weapons/universal/missile_launch_2.ogg"),
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
		"wave":
			pool = WAVE_CLIPS
		"wave_big":
			pool = WAVE_BIG_CLIPS
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
		p.bus = "SFX"
		p.global_position = world_pos
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = clip
		p.volume_db = VOLUME_DB
		p.bus = "SFX"
		parent.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
