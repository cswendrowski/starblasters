extends "res://scripts/enemies/enemy_core.gd"

# Firecore Cruiser "Helix" (M6c rework, Roman 2026-06-07).
#
# A slow zealot capital. Movement comes from the roster slot (cross / lane-advance
# / hold / shift / drift) but is clamped to ~1 px/frame (60 px/s) here so the hull
# always reads as a ponderous capital regardless of which movement it rolled. It
# carries a central HOOK-TURRET beam that tracks the player, two glowing cores
# (authored in the scene, hand-tunable), and drops firecores on destruction (baked
# DropFirecore component, count 2). Only the beam turret is bespoke; locomotion is
# a movement pattern (mirrors interceptor: enemy_core + custom firing).
#
# Was a bespoke EnemyBase side-traverse cruiser with an EnemyTurret (plasma bullets)
# and an elaborate death descent. The new identity replaces all of that.

const BeamEmitter = preload("res://scripts/enemies/beam_emitter.gd")
const HookTurretTex = preload("res://graphics/enemies/hook_turret.png")

# ~1 px/frame ceiling on the rolled movement (Roman: "moving at 1p/f").
const SPEED_CAP := 60.0

var _turret: Node = null


func _ready() -> void:
	max_health = 32
	bounty_value = 100
	display_scale = 1.0
	super._ready()
	_build_beam_turret()


func start(pos: Vector2) -> void:
	super.start(pos)   # enemy_core dups movement -> _pattern + applies sector scale
	_clamp_pattern_speed()


# Hold the capital to ~1 px/frame on every speed-like field of whatever movement
# it rolled, so cross/advance/hold/shift/drift all read as a slow capital.
func _clamp_pattern_speed() -> void:
	if _pattern == null:
		return
	for prop in _pattern.get_property_list():
		if int(prop.get("type", -1)) != TYPE_FLOAT:
			continue
		var n: String = str(prop.get("name", ""))
		if n == "speed" or n == "down_speed" or n.ends_with("_speed"):
			if float(_pattern.get(n)) > SPEED_CAP:
				_pattern.set(n, SPEED_CAP)


func _build_beam_turret() -> void:
	_turret = BeamEmitter.new()
	_turret.name = "HookTurret"
	# Tracks the player and rakes a directed beam — a slow, telegraphed capital
	# threat. LOOP_WINDUP: idle once, then windup->fire->cooldown->windup forever.
	_turret.configure({
		"idle_time": 1.5, "windup_time": 2.0, "firing_time": 2.0, "cooldown_time": 2.5,
		"cycle": BeamEmitter.Cycle.LOOP_WINDUP, "autostart": true,
		"endpoint": BeamEmitter.Endpoint.RAY, "aim_mode": BeamEmitter.AimMode.TRACKING,
		"tracking_rate": 1.0, "reach": 320.0, "dps": 3.0, "hit_radius": 8.0,
		"emitter_offset": Vector2.ZERO, "target_group": "player",
		"layers": [
			{"width": 9.0, "color": Color(0.65, 0.15, 1.0, 0.55)},
			{"width": 5.0, "color": Color(1.0, 0.5, 0.1, 0.85)},
			{"width": 2.0, "color": Color(1.0, 0.95, 0.35, 1.0)},
		],
		"telegraph_width": 1.0,
	})
	var s := Sprite2D.new()
	s.texture = HookTurretTex
	s.modulate = Color.html("9350ad")
	_turret.add_child(s)
	add_child(_turret)
