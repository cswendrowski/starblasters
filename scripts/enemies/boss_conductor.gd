extends "res://scripts/enemies/boss_base.gd"

# The Conductor — sector 3 row-3 finale. Mirror/predictive + multi-part +
# transforming. Two satellite drones orbit the core, mirror player X, and
# fire telegraphed bursts. Killing satellites or hitting HP gates pushes
# the boss through escalating phases — final phase: satellites gone, core
# transforms (red tint), drops anchor, dives + fires aimed cones.
#
# Stats set BEFORE super._ready() — no fallback pattern.

const SatelliteScript = preload("res://scripts/enemies/conductor_satellite.gd")

var _sat_left: Area2D = null
var _sat_right: Area2D = null
var _sats_killed: int = 0
var _ring_t: float = 0.0
var _ring_rot_deg: float = 0.0
var _dive_t: float = 0.0
var _transformed: bool = false


func _ready() -> void:
	max_health = 380
	bounty_value = 600
	display_scale = 1.0
	boss_hover_y = 56.0
	fire_interval_min = 4.0
	fire_interval_max = 4.0
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.66, true, 4.0),
		BossPhase.make("Phase 3", 0.33, true, 8.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))
	_spawn_satellites()


func _spawn_satellites() -> void:
	_sat_left = _make_satellite("left", 0.0, 1.8)
	_sat_right = _make_satellite("right", PI, -1.8)
	add_child(_sat_left)
	add_child(_sat_right)


func _make_satellite(side_name: String, phase_offset: float, spin: float) -> Area2D:
	var sat := Area2D.new()
	sat.set_script(SatelliteScript)
	sat.name = "Satellite_" + side_name
	sat.add_to_group("enemies")
	var spr := Sprite2D.new()
	spr.texture = preload("res://graphics/enemies/enemy_placeholder_16x.png")
	spr.modulate = Color(1.0, 0.85, 0.35, 1.0)
	spr.name = "Sprite2D"
	sat.add_child(spr)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	cs.shape = shape
	sat.add_child(cs)
	sat.boss_ref = self
	sat.orbit_radius = 24.0
	sat.orbit_speed = spin
	sat.orbit_phase = phase_offset
	sat.satellite_killed.connect(_on_satellite_killed)
	return sat


func _on_satellite_killed() -> void:
	_sats_killed += 1
	_enrage_flash(Color(1.0, 0.85, 0.35, 1.0), 0.4)
	_screen_shake(4.0, 0.3)
	# Phase trigger: first satellite kill = advance to Phase 2 (if not
	# already there from HP). Second satellite = Phase 3.
	if _sats_killed == 1 and _current_phase_idx < 1:
		_force_advance_phase(1)
	elif _sats_killed == 2 and _current_phase_idx < 2:
		_force_advance_phase(2)


func _force_advance_phase(target_idx: int) -> void:
	if target_idx <= _current_phase_idx:
		return
	if target_idx >= phases.size():
		return
	var old_idx: int = _current_phase_idx
	_current_phase_idx = target_idx
	var ph_new = phases[target_idx]
	if ph_new.enrage_flash:
		_enrage_flash()
	if ph_new.screen_shake_strength > 0.0:
		_screen_shake(ph_new.screen_shake_strength)
	phase_changed.emit(old_idx, target_idx, ph_new.name)
	_on_phase_entered(target_idx, ph_new.name)


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 2:
		# Final transform — core mobile, red tint.
		_transformed = true
		_anchored = false
		_pattern = null
		if has_node("Sprite2D"):
			($Sprite2D as Sprite2D).modulate = Color(1.2, 0.4, 0.4, 1.0)


func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	while not _dying and is_instance_valid(self):
		# 0.1s tick — friendlier on the scheduler than process_frame, fine
		# resolution for boss cadence (rings + dives are seconds-scale).
		await get_tree().create_timer(0.1).timeout
		if _dying:
			return
		var delta: float = 0.1
		if _current_phase_idx == 0:
			# Satellites carry the offense in P1.
			pass
		elif _current_phase_idx == 1:
			_ring_t += delta
			if _ring_t >= 4.0:
				_ring_t = 0.0
				_ring_rot_deg = fmod(_ring_rot_deg + 60.0, 360.0)
				fire_ring(18, _ring_rot_deg)
		elif _current_phase_idx == 2:
			_dive_t += delta
			if _dive_t >= 3.5:
				_dive_t = 0.0
				var p := find_player()
				if p != null and p is Node2D:
					var pp: Vector2 = (p as Node2D).global_position
					var target := Vector2(
						clamp(pp.x - 80.0, Playfield.X_MIN + 40.0, Playfield.X_MAX - 40.0),
						clamp(pp.y + 40.0, 80.0, get_viewport_rect().size.y * 0.65),
					)
					await dive_toward(target, 220.0, true)
					if _dying:
						return
					fire_aimed_cone(7, 24.0)


func _on_boss_death() -> void:
	if is_instance_valid(_sat_left):
		_sat_left.queue_free()
	if is_instance_valid(_sat_right):
		_sat_right.queue_free()
