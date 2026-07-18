extends Node

# Dock/cinematic engine SFX (Roman 2026-07-15). Static helpers for the hangar scenes
# (patrol_start, outpost_arrival) + the combat outro. Preload-referenced, NOT a
# class_name (headless class-cache safety, matching ship_catalog / dock_const):
#   const EngineSfx = preload("res://scripts/effects/engine_sfx.gd")
#
#   play_jet_start(parent, ship)  — engine ignition when a player hull spools up.
#       Clip family keys off the ShipCatalog entry: the Pilgrim's firecore gets its
#       own clip (F); single-nozzle hulls (Reaver, Weaver) roll A/B; twin-engine
#       hulls roll C/D/E.
#   play_exit_thruster(parent)    — the fly-off burn (shared with main._run_outro).
#   play_afterburner(parent, ship) — decelerating fly-IN (outpost arrival): the
#       Pilgrim always uses A; every other craft rolls B/C.
#
# `ship` is a ShipCatalog entry Dictionary (get_ship(idx)). All clips play on a
# self-freeing non-positional AudioStreamPlayer on the SFX bus (menu scenes — no
# world camera to pan against).

const JET_START_SINGLE := [
	preload("res://assets/audio/engines/Jet Start A.ogg"),
	preload("res://assets/audio/engines/Jet Start B.ogg"),
]
const JET_START_TWIN := [
	preload("res://assets/audio/engines/Jet Start C.ogg"),
	preload("res://assets/audio/engines/Jet Start D.ogg"),
	preload("res://assets/audio/engines/Jet Start E.ogg"),
]
const JET_START_PILGRIM := [
	preload("res://assets/audio/engines/Jet Start F.ogg"),
]
const EXIT_THRUSTER_CLIPS := [
	preload("res://assets/audio/engines/exit_thruster_1.ogg"),
	preload("res://assets/audio/engines/exit_thruster_2.ogg"),
]
const AFTERBURNER_PILGRIM := [
	preload("res://assets/audio/engines/Afterburner Slowing A.ogg"),
]
const AFTERBURNER_OTHERS := [
	preload("res://assets/audio/engines/Afterburner Slowing B.ogg"),
	preload("res://assets/audio/engines/Afterburner Slowing C.ogg"),
]

const JET_START_VOLUME_DB: float = 0.0
const EXIT_THRUSTER_VOLUME_DB: float = 0.0
const AFTERBURNER_VOLUME_DB: float = 0.0


# extra_db: per-scene loudness trim on top of the base const (patrol start passes a
# boost because its music bed drowns the stock level).
static func play_jet_start(parent: Node, ship: Dictionary, extra_db: float = 0.0) -> void:
	var pool: Array = JET_START_TWIN
	if String(ship.get("id", "")) == "pilgrim":
		pool = JET_START_PILGRIM
	elif (ship.get("engines", []) as Array).size() <= 1:
		pool = JET_START_SINGLE
	_play(parent, pool, JET_START_VOLUME_DB + extra_db)


static func play_exit_thruster(parent: Node, extra_db: float = 0.0) -> void:
	_play(parent, EXIT_THRUSTER_CLIPS, EXIT_THRUSTER_VOLUME_DB + extra_db)


static func play_afterburner(parent: Node, ship: Dictionary) -> void:
	var pool: Array = AFTERBURNER_OTHERS
	if String(ship.get("id", "")) == "pilgrim":
		pool = AFTERBURNER_PILGRIM
	_play(parent, pool, AFTERBURNER_VOLUME_DB)


static func _play(parent: Node, pool: Array, volume_db: float) -> void:
	if parent == null or pool.is_empty():
		return
	var clip: AudioStream = pool[randi() % pool.size()]
	if clip == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = clip
	p.volume_db = volume_db
	p.bus = "SFX"
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
