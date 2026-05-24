extends "res://scripts/enemies/boss_base.gd"

# Howler — sector 1 anchored bullet-hell turret. Stubby gunboat. Identity:
# the rotating 12-bullet ring you have to commit to a gap and chase.
#
# Stats set BEFORE super._ready() (no fallback pattern — caused the 1-HP
# regression on every other boss).
#
# Phase 1 (100→50%): anchored, alternating 5-bullet aimed burst (1.4s) +
#                    360 ring (4.0s).
# Phase 2 ( 50→0%):  ring cadence 2.5s, +30deg rotation per fire, enrage
#                    flash + 4.0 shake on entry.

var _ring_offset_deg: float = 0.0
var _ring_cadence: float = 4.0
var _ring_step_deg: float = 0.0


func _ready() -> void:
	max_health = 130
	bounty_value = 200
	display_scale = 1.0
	boss_hover_y = 60.0
	fire_interval_min = 1.4
	fire_interval_max = 1.4
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.5, true, 4.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		_ring_cadence = 2.5
		_ring_step_deg = 30.0


# Howler's attack rotation. Concurrent loops: aimed burst on a 1.4s tick
# (uses ShootTimer is awkward — we just run our own coroutine) and the
# ring on its own cadence.
func _attack_loop() -> void:
	# Replace ShootTimer's bullet output with our hand-rolled rotation.
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	_run_burst_loop()
	_run_ring_loop()


func _run_burst_loop() -> void:
	while not _dying and is_instance_valid(self):
		await get_tree().create_timer(1.4).timeout
		if _dying:
			return
		fire_aimed_burst(5, 30.0, 0.05)


func _run_ring_loop() -> void:
	while not _dying and is_instance_valid(self):
		await get_tree().create_timer(_ring_cadence).timeout
		if _dying:
			return
		fire_ring(12, _ring_offset_deg)
		_ring_offset_deg += _ring_step_deg
