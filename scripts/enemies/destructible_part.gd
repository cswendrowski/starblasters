extends EnemyBase
class_name DestructiblePart

# A destructible SECTION of a multi-part enemy (cruiser prototype, 2026-06-24). Authored as a child
# Area2D in the parent's .tscn, it's an independent EnemyBase — own HP/bounty/collision — so it joins
# the "enemies" group and the player can shoot it OFF on its own (EnemyBase handles take_hit + the
# death burst). It's static (no movement) and rides the parent core's transform; the core's explode()
# cascade-detonates any survivors. Set has_turret for a firing pod, leave it off for armour/structure.

@export var part_health: int = 6
@export var part_bounty: int = 8
@export var has_turret: bool = false           # adds an aiming EnemyTurret child (a weapon pod)
@export var turret_fire_interval: float = 2.2
@export var turret_bullet_speed: float = 150.0
@export var turret_aim_tolerance_deg: float = 12.0


func _ready() -> void:
	max_health     = part_health
	bounty_value   = part_bounty
	auto_rotate    = false                     # static section; the core owns facing
	offscreen_mode = OffscreenMode.NONE        # freed with the core, never on its own offscreen check
	super._ready()
	if has_turret:
		var t := EnemyTurret.new()
		t.rotation_speed    = 1.8
		t.fire_interval_min = turret_fire_interval
		t.fire_interval_max = turret_fire_interval
		t.aim_tolerance_deg = turret_aim_tolerance_deg
		t.bullet_speed      = turret_bullet_speed
		add_child(t)
