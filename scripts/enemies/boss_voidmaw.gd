extends "res://scripts/enemies/boss_base.gd"

# Voidmaw — sector 2 area-denial. Identity: the drifting hole. Stationary
# boss "exhales" slow-drifting black holes that travel down the playfield
# toward the player; spatial chess as you weave the fans around them.
# Distinct from Commander because the BH is stationary-spawn + slow drift
# rather than a charged-and-fired projectile.
#
# Stats set BEFORE super._ready() — no fallback pattern.

const BlackHoleScene = preload("res://scenes/hazards/black_hole.tscn")

@export var bh_radius: float = 64.0
@export var bh_pull: float = 700.0
@export var bh_drift_speed: float = 60.0  # px/s downward

var _phase2: bool = false
var _live_holes: Array = []


func _ready() -> void:
	max_health = 220
	bounty_value = 500
	display_scale = 1.0
	boss_hover_y = 60.0
	fire_interval_min = 2.0
	fire_interval_max = 2.0
	# Plasma orb: wobbling green orbs match the organic, gravitational identity
	# of the drifting black holes. Chaos spread feels natural here.
	default_bullet_variant = load("res://data/bullets/boss/plasma_orb.tres")
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.33, true, 5.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		_phase2 = true


func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	_run_bh_loop()
	_run_fan_loop()


func _max_holes() -> int:
	return 2 if _phase2 else 1


func _live_count() -> int:
	var live: Array = []
	for h in _live_holes:
		if is_instance_valid(h):
			live.append(h)
	_live_holes = live
	return _live_holes.size()


func _run_bh_loop() -> void:
	while not _dying and is_instance_valid(self):
		await get_tree().create_timer(8.0).timeout
		if _dying:
			return
		if _live_count() >= _max_holes():
			continue
		_spawn_drifting_hole()


func _spawn_drifting_hole() -> void:
	var bh = BlackHoleScene.instantiate()
	bh.radius = bh_radius
	bh.lifetime = 999.0
	bh.fade_time = 0.4
	bh.visual_scale = 1.0
	bh.pull_strength = bh_pull
	bh.player_pull_multiplier = 0.35
	bh.visual_modulate = Color(0.85, 0.55, 1.0, 1.0)
	# Voidmaw only pulls the player — not itself, not its bullets, not its
	# own future bullets. The default groups list would suck everything in.
	bh.pull_target_groups = PackedStringArray(["player"])
	bh.position = global_position + Vector2(0, 40.0)
	# Compute travel duration BEFORE add_child so we can wire expand_in_time
	# (BH grows from 1px → full radius over its travel to player.y zone).
	var vp: Vector2 = get_viewport_rect().size
	var target_y: float = vp.y + 80.0
	var travel: float = max(0.0, target_y - bh.position.y)
	var dur: float = travel / max(bh_drift_speed, 1.0)
	# BH starts at scale 0 and expands to full size over the drift duration.
	# black_hole.gd's expand_in_time tween handles the visual ease + overshoot.
	bh.expand_in_time = dur
	add_world_node_above_backdrop(bh)
	_live_holes.append(bh)
	# Drift downward at bh_drift_speed via a tween. Despawn at bottom margin.
	var tw := bh.create_tween()
	tw.tween_property(bh, "position:y", target_y, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(bh):
			# Fade then free.
			var fout := bh.create_tween()
			fout.tween_property(bh, "modulate:a", 0.0, 0.4)
			fout.tween_callback(bh.queue_free)
	)


func _run_fan_loop() -> void:
	while not _dying and is_instance_valid(self):
		await get_tree().create_timer(2.0).timeout
		if _dying:
			return
		var count: int = 5 if _phase2 else 3
		var spread: float = 32.0 if _phase2 else 28.0
		fire_spread(count, spread, true)


func _on_boss_death() -> void:
	for h in _live_holes:
		if is_instance_valid(h):
			h.queue_free()
	_live_holes.clear()
