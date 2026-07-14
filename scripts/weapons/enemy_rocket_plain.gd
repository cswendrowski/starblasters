extends "res://scripts/weapons/enemy_rocket.gd"

# Building-launcher rocket (Roman 2026-07-14): same dumb-fire rocket as EnemyRocket, but its trail is
# PLAIN — it just follows the flight path and fades, with no settling/downward drift. That drift is the
# player/enemy-SHIP missile smoke look; an emplacement's rockets shouldn't leave it. Only the trail
# differs: flight, damage, shoot-down are all inherited unchanged.


func _build_trail_line() -> void:
	super._build_trail_line()   # builds the shared MissileSmokeTrail (sets _smoke_trail synchronously)
	if _smoke_trail != null:
		_smoke_trail.plain = true
