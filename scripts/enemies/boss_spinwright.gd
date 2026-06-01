extends "res://scripts/enemies/boss_base.gd"

# Spinwright — sector 2-3 transforming beam-sweeper. Identity: ring opens,
# beam sweeps, the gap moves. Phase 0 the ring deflects player bullets
# coming from above (forces side / below shots); phases 1-2 open the ring
# and start the beam attack.
#
# Stats set BEFORE super._ready() — no fallback pattern.

var _phase: int = 0  # 0/1/2 mirror phases[] index
var _deflector: Area2D = null
var _t: float = 0.0


func _ready() -> void:
	max_health = 260
	bounty_value = 350
	display_scale = 1.0
	boss_hover_y = 70.0
	fire_interval_min = 5.0
	fire_interval_max = 5.0
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.66, true, 3.0),
		BossPhase.make("Phase 3", 0.33, true, 6.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))
	_spawn_deflector()


# Top-hemisphere bullet deflector. Sits above the boss; any player bullet
# (target_group=="enemies") moving downward (velocity_dir.y > 0) that
# enters is queue_free'd. Bullets coming from the side or below are
# untouched. Disabled when phase advances out of P0.
func _spawn_deflector() -> void:
	_deflector = Area2D.new()
	_deflector.name = "RingDeflector"
	_deflector.monitoring = true
	_deflector.monitorable = false
	# Big arc above the boss so down-moving bullets get caught before they
	# reach the core.
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60, 40)
	cs.shape = shape
	cs.position = Vector2(0, -28.0)
	_deflector.add_child(cs)
	add_child(_deflector)
	_deflector.area_entered.connect(_on_deflector_area_entered)


func _on_deflector_area_entered(area: Area2D) -> void:
	if area == null:
		return
	# Only player bullets — duck-type on the BaseBullet contract instead of
	# class hierarchy (some bullet variants may not inherit BaseBullet but
	# still expose target_group + velocity_dir). target_group=="enemies"
	# identifies it as a player-fired bullet; velocity_dir.y > 0 = moving
	# down (i.e. coming from above). Side / below shots are untouched.
	if not ("target_group" in area) or String(area.target_group) != "enemies":
		return
	if not ("velocity_dir" in area):
		return
	var v: Vector2 = area.velocity_dir
	if v.y > 0.1:
		# Small visual flicker on the deflector.
		_pulse_deflector()
		area.queue_free()


func _pulse_deflector() -> void:
	if _deflector == null:
		return
	var ring := ColorRect.new()
	ring.color = Color(0.6, 1.0, 1.0, 0.6)
	ring.size = Vector2(8, 8)
	ring.position = -ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deflector.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "size", Vector2(40, 40), 0.18)
	tw.parallel().tween_property(ring, "position", Vector2(-20, -20), 0.18)
	tw.parallel().tween_property(ring, "color:a", 0.0, 0.18)
	tw.tween_callback(ring.queue_free)


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	_phase = phase_idx
	if phase_idx >= 1 and _deflector != null and is_instance_valid(_deflector):
		_deflector.queue_free()
		_deflector = null
	if has_node("Sprite2D"):
		# Accelerate sprite rotation when phases advance.
		var spr := $Sprite2D as Sprite2D
		if spr:
			spr.rotation = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	if _dying:
		return
	_t += delta
	# Spin the sprite — speeds up per phase for the "ring spinning" read.
	if has_node("Sprite2D"):
		var spr := $Sprite2D as Sprite2D
		if spr:
			var spin_rate: float = 1.0
			if _phase == 1:
				spin_rate = 2.5
			elif _phase == 2:
				spin_rate = 5.0
			spr.rotation += spin_rate * delta


func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	while not _dying and is_instance_valid(self):
		match _phase:
			0:
				# Pressure-only ring every 5s while the deflector holds the
				# player honest from above. Heavy slug: slow fat orbs match
				# the boss's deliberate mechanical identity.
				await get_tree().create_timer(5.0).timeout
				if _dying:
					return
				fire_ring(6, 0.0, load("res://data/bullets/boss/heavy_slug.tres"))
			1:
				# Single beam every ~4s; gap follows the player's X at
				# telegraph start.
				await get_tree().create_timer(0.8).timeout
				if _dying:
					return
				var gx: float = _player_x_clamped()
				await fire_beam_telegraphed(36.0, gx, 1.0, 2.2, 1)
				await get_tree().create_timer(1.0).timeout
			2:
				# Two beams per cycle, gaps offset.
				var gx1: float = _player_x_clamped()
				var gx2: float = Playfield.CENTER.x + (Playfield.CENTER.x - gx1) * 0.5
				gx2 = clamp(gx2, Playfield.X_MIN + 30.0, Playfield.X_MAX - 30.0)
				fire_beam_telegraphed(36.0, gx1, 1.0, 2.0, 1)
				await get_tree().create_timer(0.6).timeout
				await fire_beam_telegraphed(36.0, gx2, 1.0, 2.0, 1)
				await get_tree().create_timer(0.8).timeout


func _player_x_clamped() -> float:
	var p := find_player()
	if p == null or not (p is Node2D):
		return Playfield.CENTER.x
	return clamp((p as Node2D).global_position.x, Playfield.X_MIN + 30.0, Playfield.X_MAX - 30.0)


func _on_boss_death() -> void:
	if _deflector != null and is_instance_valid(_deflector):
		_deflector.queue_free()
