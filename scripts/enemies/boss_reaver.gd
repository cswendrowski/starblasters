extends "res://scripts/enemies/boss_base.gd"

# Lash (formerly Reaver) — sector 1-2 mobile sweeper / glass cannon.
# Identity: the dive. P1 strafes in sin^3 arcs with aimed 3-bullet fans;
# P2 stops sweeping and commits to telegraphed straight-line dives across
# the player's lane, then an aimed cone on recovery.
#
# Stats set BEFORE super._ready() — no fallback pattern.

var _phase2: bool = false


func _ready() -> void:
	max_health = 140
	bounty_value = 200
	display_scale = 1.0
	boss_hover_y = 56.0
	# ShootTimer is suppressed by our hand-rolled rotation, but keep cadence
	# defaults sane in case a wave-director shoot_pattern_override is injected.
	fire_interval_min = 0.6
	fire_interval_max = 0.9
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.5, true, 3.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	# P1: sweep across the playfield in sin^3 arcs.
	sweep_horizontal(80.0, 2.6, "sin3")


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		_phase2 = true


func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	while not _dying and is_instance_valid(self):
		if not _phase2:
			# P1: 3-bullet aimed fans every 1.2s while sweeping.
			await get_tree().create_timer(1.2).timeout
			if _dying:
				return
			fire_aimed_burst(3, 16.0)
		else:
			# P2: stop sweep, dive across player Y, fire aimed cone on
			# recovery, brief pause, repeat. dive_toward handles the 0.9s
			# red-reticle telegraph + the _charging slow-down read.
			_anchored = false
			_pattern = null
			var p := find_player()
			if p == null or not (p is Node2D):
				await get_tree().create_timer(0.6).timeout
				continue
			var pp: Vector2 = (p as Node2D).global_position
			var target := Vector2(
				clamp(pp.x, Playfield.X_MIN + 40.0, Playfield.X_MAX - 40.0),
				pp.y + 20.0,
			)
			await dive_toward(target, 280.0, true)
			if _dying:
				return
			fire_aimed_cone(5, 22.0)
			await get_tree().create_timer(0.6).timeout
