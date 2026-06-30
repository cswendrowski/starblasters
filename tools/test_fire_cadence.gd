extends SceneTree

# Headless cadence check for the carried-residual fire timer (player.gd).
# Drives the REAL fire_primary() each simulated frame with the trigger held and
# measures the achieved rate of fire. The 5-line recovery tick is mirrored from
# player.gd _process() (it can't run standalone — _process early-returns unless
# is_alive, which would pull in every other per-frame subsystem). Everything that
# matters for the cadence — the gate, the `cooldown` source, and the
# `_gun_cd_t += _eff_cd` carry — is the real code under test.
#
# It also prints what the OLD Timer model (ceil-to-frame + discarded remainder)
# would have produced, so the slow/jittery bias the fix removes is visible.

const DELTA := 1.0 / 60.0
const SIM_SECONDS := 3.0
const Clar = preload("res://scripts/systems/clarity.gd")

var _player
var _fails := 0
var _done := false


# Run on the first frame — by now the tree root is live, so add_child() puts the
# player in-tree and its get_tree() resolves inside fire_primary's spawn path.
func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_run_all()
	return true


func _run_all() -> void:
	# Run isn't an autoload in `-s` mode; fire_primary guards on null but a real
	# Run lets the run-summary stat calls exercise their real path too.
	var run = load("res://scripts/autoload/run_state.gd").new()
	run.name = "Run"
	get_root().add_child(run)
	if run.has_method("new_run"):
		run.new_run()

	_player = load("res://scenes/player/player.tscn").instantiate()
	get_root().add_child(_player)
	_player.bullet_scene = load("res://scenes/projectiles/bullet_blaster.tscn")

	# Frame-aligned control, the worst-case off-grid case, and a slow weapon.
	_run_case(0.05, "0.05s  (3.0 frames, frame-aligned)")
	_run_case(0.07, "0.07s  (4.2 frames, off-grid — worst case)")
	_run_case(0.0833, "0.0833s (5.0 frames, frame-aligned)")
	_run_case(0.2, "0.20s  (12.0 frames)")

	# Sub-frame spawn correction: the helper math, then proof that the off-grid
	# frame "beat" becomes an evenly-spaced effective cadence once it's applied.
	_test_subframe_helper()
	_run_evenness_case(0.07, "0.07s off-grid stream")

	# Velocity-inheritance ("Doppler") boost: does the spawned bullet's speed pick
	# up the shooter's forward velocity component, and only the forward one?
	_test_doppler()

	print("------")
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(_fails)


func _run_case(cd: float, label: String) -> void:
	_player.cooldown = cd
	_player.can_shoot = true
	_player._gun_cd_t = 0.0
	var carry: float = _player.FIRE_CARRY

	var frames := int(round(SIM_SECONDS / DELTA))
	var shots := 0
	for _f in frames:
		# --- mirror of player.gd _process() primary-cooldown recovery ---
		if not _player.can_shoot:
			_player._gun_cd_t -= DELTA
			if _player._gun_cd_t <= 0.0:
				_player.can_shoot = true
				_player._gun_cd_t = maxf(_player._gun_cd_t, -carry)
		# --- held trigger: a flipped can_shoot means a real shot went out ---
		if _player.can_shoot:
			_player.fire_primary()
			if not _player.can_shoot:
				shots += 1

	var measured := shots / SIM_SECONDS
	var target := 1.0 / cd
	# Old model: every interval rounded UP to a whole frame, remainder discarded.
	var old_interval: float = ceil(cd / DELTA) * DELTA
	var old_rate: float = 1.0 / old_interval
	# New model should land within ~1 shot of target across the window.
	var ok: bool = absf(measured - target) <= (1.0 / SIM_SECONDS) + 0.01
	if not ok:
		_fails += 1
	print("%s cd=%s" % ["ok  " if ok else "FAIL", label])
	print("     target %5.2f/s | new(measured) %5.2f/s | old(timer) %5.2f/s" % [target, measured, old_rate])


# Unit-test the offset math the spawn paths call: advance = dir × speed × late,
# zero when not late, zero when the projectile has no speed.
func _test_subframe_helper() -> void:
	var b = _player.bullet_scene.instantiate()
	get_root().add_child(b)
	var has_speed: bool = "speed" in b
	if has_speed:
		b.speed = 300.0
	var up := Vector2(0, -1)
	var got: Vector2 = _player._subframe_advance(b, up, 0.05)
	var want := up * 300.0 * 0.05                       # (0, -15)
	var ok_pos: bool = has_speed and got.distance_to(want) < 0.001
	var ok_zero: bool = _player._subframe_advance(b, up, 0.0) == Vector2.ZERO
	var plain := Node.new()
	var ok_nospeed: bool = _player._subframe_advance(plain, up, 0.05) == Vector2.ZERO
	plain.free()
	b.queue_free()
	var ok: bool = ok_pos and ok_zero and ok_nospeed
	if not ok:
		_fails += 1
	print("%s sub-frame helper: advance=%s (want %s) | late0→zero=%s | nospeed→zero=%s" \
		% ["ok  " if ok else "FAIL", str(got), str(want), str(ok_zero), str(ok_nospeed)])


# Drive the real fire_primary at an off-grid rate and record, per shot, the frame it
# fired and the `late` value fire_primary will use (read off _gun_cd_t pre-fire). The
# RAW frame gaps must vary (4/5 beat) — proving there's a beat to fix — while the
# CORRECTED emission times (fire_time − late) must be evenly spaced by exactly cd.
func _run_evenness_case(cd: float, label: String) -> void:
	_player.cooldown = cd
	_player.can_shoot = true
	_player._gun_cd_t = 0.0
	var carry: float = _player.FIRE_CARRY
	var frames := int(round(SIM_SECONDS / DELTA))
	var fire_frames: Array[int] = []
	var lates: Array[float] = []
	for f in frames:
		if not _player.can_shoot:
			_player._gun_cd_t -= DELTA
			if _player._gun_cd_t <= 0.0:
				_player.can_shoot = true
				_player._gun_cd_t = maxf(_player._gun_cd_t, -carry)
		if _player.can_shoot:
			var late: float = clampf(-_player._gun_cd_t, 0.0, carry)   # exactly what fire_primary uses
			_player.fire_primary()
			if not _player.can_shoot:
				fire_frames.append(f)
				lates.append(late)
	var raw_min := 9999
	var raw_max := 0
	var worst_dev := 0.0
	for i in range(1, fire_frames.size()):
		var g: int = fire_frames[i] - fire_frames[i - 1]
		raw_min = mini(raw_min, g)
		raw_max = maxi(raw_max, g)
		var e0: float = fire_frames[i - 1] * DELTA - lates[i - 1]
		var e1: float = fire_frames[i] * DELTA - lates[i]
		worst_dev = maxf(worst_dev, absf((e1 - e0) - cd))
	var had_beat: bool = raw_max > raw_min            # off-grid → frame gaps alternate
	var even: bool = worst_dev < 0.0006               # corrected gaps within ~0.6 ms of cd
	var ok: bool = had_beat and even
	if not ok:
		_fails += 1
	print("%s sub-frame: %s" % ["ok  " if ok else "FAIL", label])
	print("     raw frame-gap %d..%d (beat present: %s) | corrected gap error %.5f ms (target 0)" \
		% [raw_min, raw_max, str(had_beat), worst_dev * 1000.0])


# End-to-end Doppler check. Route primary bullets into a private container, fire one
# shot at a time with _move_velocity set, read each bullet's resulting speed.
func _test_doppler() -> void:
	var ceil_v: float = Clar.ABS_MAX_SPEED
	var box := Node2D.new()
	get_root().add_child(box)
	_player.bullet_parent = box
	_player.cooldown = 0.05
	var base: float = _doppler_fire(box, Vector2.ZERO)         # stationary
	var small: float = _doppler_fire(box, Vector2(0, -120.0))  # toward fire, under ceiling → +120
	var big: float = _doppler_fire(box, Vector2(0, -400.0))    # toward fire, over ceiling → clamp
	var down: float = _doppler_fire(box, Vector2(0, 300.0))    # retreating → clamped to 0
	var side: float = _doppler_fire(box, Vector2(300.0, 0))    # strafing → perpendicular, 0
	_player.bullet_parent = null
	box.queue_free()

	var ok_small: bool = absf((small - base) - 120.0) < 0.5            # full forward boost, no clamp
	var ok_big: bool = absf(big - minf(base + 400.0, ceil_v)) < 0.5    # boosted, clamped to ceiling
	var ok_down: bool = absf(down - base) < 0.5                        # forward-only → no change
	var ok_side: bool = absf(side - base) < 0.5                        # perpendicular → no change
	var ok: bool = ok_small and ok_big and ok_down and ok_side and big <= ceil_v + 0.5
	if not ok:
		_fails += 1
	print("%s doppler: base=%.0f | +120→%.0f (+%.0f) | +400→%.0f (clamp@%.0f) | down→%.0f | side→%.0f" \
		% ["ok  " if ok else "FAIL", base, small, small - base, big, ceil_v, down, side])


func _doppler_fire(box: Node, vel: Vector2) -> float:
	_player.can_shoot = true
	_player._gun_cd_t = 0.0
	_player._move_velocity = vel
	_player.fire_primary()
	var b = box.get_child(box.get_child_count() - 1)
	return float(b.speed)
