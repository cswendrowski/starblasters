extends "res://scripts/enemy_core.gd"
class_name EnemyCruiser

# Large cruiser with three child turrets: one beam turret (center) and two gun turrets (flanks).
# Turrets are children — they follow the cruiser and are freed with it.
#
# On-lane migration 2026-06-08: enter→settle→drift is now the shared Drift pattern (a high hold,
# the matrix assigns drift_high). The turret spawning + explode handling are unchanged (decoupled
# from locomotion, mirroring enemy_firecore_cruiser).
#
# NOTE: display_scale = 2.0 affects VFX blast count and debris only.

const Drift = preload("res://scripts/enemies/patterns/drift.gd")

var _beam_turret: Node = null
var _gun_turret_l: Node = null
var _gun_turret_r: Node = null


func _ready() -> void:
	max_health   = 16
	bounty_value = 40
	auto_rotate  = false
	display_scale = 2.0
	if movement == null:
		var d := Drift.new()
		d.hover_y = 50.0          # capital hold high in the band
		movement = d
	super._ready()
	call_deferred("_spawn_turrets")


func _spawn_turrets() -> void:
	var BeamScene = load("res://scenes/enemies/enemy_beam_turret.tscn")
	var GunScene  = load("res://scenes/enemies/enemy_gun_turret.tscn")
	if BeamScene == null or GunScene == null:
		push_error("EnemyCruiser: failed to load turret scenes")
		return
	_beam_turret  = BeamScene.instantiate()
	_gun_turret_l = GunScene.instantiate()
	_gun_turret_r = GunScene.instantiate()
	_beam_turret.position  = Vector2(0, -10)
	_gun_turret_l.position = Vector2(-20, 4)
	_gun_turret_r.position = Vector2(20, 4)
	add_child(_beam_turret)
	add_child(_gun_turret_l)
	add_child(_gun_turret_r)


func explode() -> void:
	# Kill surviving turrets first so their died signals fire and bounties count.
	for t in [_beam_turret, _gun_turret_l, _gun_turret_r]:
		if t and is_instance_valid(t) and t.has_method("explode"):
			if not ("_dying" in t and t._dying):
				t.explode()
	super.explode()
