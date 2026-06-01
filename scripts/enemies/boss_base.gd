extends "res://scripts/enemies/enemy_base.gd"

# Shared base for every boss. Owns: HP/bounty defaults appropriate for a
# boss, sweep movement plumbing, ShootTimer wiring, the HP-gated phase
# state machine, telegraph helpers, attack primitives (aimed bursts /
# rings / cones / spreads / dive / beam-with-safe-gap), shared enrage
# VFX, and the dramatic multi-blast death sequence.
#
# Subclasses define:
#   - stats in _ready() BEFORE super._ready() (no `<= 0 ? default` —
#     caused the 1-HP regression),
#   - the `phases` array (or leave empty for a 1-phase fight),
#   - override `_on_phase_entered()` to mutate cadence / spawn rates when
#     a phase gate fires,
#   - override `_attack_loop()` (or use ShootTimer + shoot_pattern_override
#     from the wave director) for their signature attack rotation.
#
# main.gd's HP-bar wiring walks the inheritance chain looking for
# resource_path == "res://scripts/enemies/boss_base.gd" — every boss
# subclass picks up the bar automatically by extending this file.

const Playfield = preload("res://scripts/playfield.gd")

# Flat base HP multiplier applied to EVERY boss (designer Roman, 2026-05-31:
# "bosses die too fast"). Layered ON TOP of the per-boss-defeated +5% run
# escalation below, so effective HP = base * BASE_HP_MULT * (1 + 0.05*defeated).
# Single shared site so all bosses pick it up; tunable here.
const BASE_HP_MULT: float = 1.5

signal health_changed(cur: int, max: int)
signal phase_changed(old_idx: int, new_idx: int, phase_name: String)

# ---- Designer-tunable @exports -----------------------------------------

@export var shoot_pattern: Resource = null
@export var fire_interval_min: float = 0.7
@export var fire_interval_max: float = 1.4
@export var movement: Resource = null

# Optional default variant applied to every primitive that doesn't receive
# an explicit variant argument. Subclasses set this in _ready() BEFORE
# super._ready() so the value is visible from the first bullet spawned.
# Leave null for default enemy_bullet visuals.
@export var default_bullet_variant: BulletVariant = null

# Where the boss settles after its enter sweep (Y pixels from top). Per-boss
# so each boss can tune its stand-off. 480×270 viewport — top quarter ≈ 68 px.
@export var boss_hover_y: float = 48.0

# Phase definitions. Empty array = single-phase fight (still emits
# phase_changed once at start with idx=0, name="").
# Array of BossPhase resources (path-based, not class_name'd, to avoid
# global-class-cache ordering on cold boot). Subclasses populate via
# `BossPhase.make(...)`.
const BossPhase = preload("res://scripts/enemies/boss_phase.gd")
@export var phases: Array[Resource] = []

# ---- Phase state machine -----------------------------------------------

var _current_phase_idx: int = -1   # -1 = not yet initialised
# Subclass-visible: true while a charged attack is winding up. Halts the
# ShootTimer fire and slows the movement step for a "boss is committed"
# read. Reuse from any signature attack that needs the read.
var _charging: bool = false

# ---- Movement plumbing -------------------------------------------------

var _pattern = null
# Anchored mode (sweep disabled). When set, _process lerps toward _anchor.
var _anchored: bool = false
var _anchor_pos: Vector2 = Vector2.ZERO
var _anchor_lerp: float = 6.0    # higher = snappier
# Per-frame mirror tracker (mirror_player_x). 0 = disabled.
var _mirror_strength: float = 0.0
var _mirror_center_x: float = 0.0


func _ready() -> void:
	# Subclass should set max_health / bounty_value / display_scale BEFORE
	# calling super._ready(). Defaults here are conservative — Commander/
	# Reaver/Sentinel each override.
	# Bosses live inside the playfield, never auto-rotate (the sprites are
	# hand-authored facing the player), and don't use EnemyBase's engine
	# attachment — boss .tscns carry their own art.
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	# Run-wide boss HP escalation: each boss defeated this run grants +5% max
	# HP to every subsequent boss (designer Roman, 2026-05-31). Applied here —
	# before super._ready() — so it lands while max_health still holds the
	# subclass base value but BEFORE enemy_base._ready() does `health =
	# max_health`. Single shared site: every boss subclass routes through this
	# _ready(), so no boss can forget the buff. Guarded for autoload-less
	# dev/test scenes (defaults to x1.0). Explicit type — never `:=` here.
	# Flat base buff FIRST — unconditional, lands even at defeated=0 and in
	# autoload-less dev/test scenes. Its own statement (not folded into the
	# run scale_mult) so the defeated==0 case still gets the x1.5. Explicit
	# type, no `:=`.
	if max_health > 0:
		max_health = int(round(float(max_health) * BASE_HP_MULT))
	var run: Node = get_node_or_null("/root/Run")
	if run != null and "bosses_defeated" in run:
		var defeated: int = int(run.bosses_defeated)
		if defeated > 0 and max_health > 0:
			var scale_mult: float = 1.0 + 0.05 * float(defeated)
			max_health = int(round(float(max_health) * scale_mult))
	super._ready()
	if has_node("ShootTimer") and not $ShootTimer.timeout.is_connected(_on_shoot_timer_timeout):
		$ShootTimer.timeout.connect(_on_shoot_timer_timeout)
	# Oblique drop-shadow under the boss sprite.
	if has_node("Sprite2D"):
		var ShadowFx := load("res://scripts/shadow_fx.gd")
		ShadowFx.attach_shadow($Sprite2D, Vector2(14, 14), 0.5, 2.0)
	# Initialise the phase machine. Phase 0 enter fires once HP is known.
	_init_phases()
	health_changed.emit(health, max_health)


func start(pos: Vector2) -> void:
	scale = Vector2(display_scale, display_scale)
	position = pos
	if movement != null:
		_pattern = movement.duplicate()
		if "hover_y" in _pattern:
			_pattern.hover_y = boss_hover_y
		if _pattern.has_method("on_start"):
			_pattern.on_start(self)
	if has_node("ShootTimer"):
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()
	health_changed.emit(health, max_health)
	# Kick the subclass attack rotation (coroutine — many subclasses will
	# leave this empty and rely on ShootTimer).
	call_deferred("_attack_loop")


# Stub for inherited MoveTimer connection — every boss .tscn wires
# MoveTimer.timeout to _on_timer_timeout. Don't remove without also
# editing the .tscns.
func _on_timer_timeout() -> void:
	pass


func _process(delta: float) -> void:
	if _dying:
		return
	if _anchored:
		position = position.lerp(_anchor_pos, clamp(delta * _anchor_lerp, 0.0, 1.0))
	elif _pattern != null:
		var safe_delta: float = min(delta, 1.0 / 30.0)
		var step: Vector2 = _pattern.compute_step(self, safe_delta)
		# Slow the boss to a crawl while a signature attack is winding up
		# so the player can read "this boss is busy".
		if _charging:
			step *= 0.25
		position += step
	if _mirror_strength > 0.0:
		var player := find_player()
		if player != null and player is Node2D:
			var tgt_x: float = _mirror_center_x + ((player as Node2D).global_position.x - _mirror_center_x) * _mirror_strength
			position.x = clamp(tgt_x, Playfield.X_MIN + 24.0, Playfield.X_MAX - 24.0)
	_clamp_to_playfield()


# Keep the boss inside the visible playfield. Bosses sit in the top 70%
# so the player has room to dodge below them.
func _clamp_to_playfield() -> void:
	var vp: Vector2 = get_viewport_rect().size
	const MARGIN: float = 24.0
	position.x = clamp(position.x, Playfield.X_MIN + MARGIN, Playfield.X_MAX - MARGIN)
	position.y = clamp(position.y, MARGIN, vp.y * 0.7)


# Non-fatal damage reaction: white flash + HP-bar update + phase check.
func hit() -> void:
	modulate = Color(2, 2, 2, 1)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.15)
	health_changed.emit(health, max_health)
	_check_phase_transition()


# Override EnemyBase.take_hit so the phase check runs even on kills (rare,
# but the kill itself emits a final health_changed via explode()).
func take_hit(damage: int = 1) -> bool:
	var killed: bool = super.take_hit(damage)
	# health_changed already emitted by hit() on non-fatal hits; emit on
	# fatal for parity (explode() emits 0/max).
	return killed


# Dramatic boss death — multi-blast cascade + debris + burn + death SFX,
# tracked over ~1.3s before the node frees.
func explode() -> void:
	if _dying:
		return
	_dying = true
	set_deferred("monitorable", false)
	# Run-wide boss-defeat tally. Drives the +5%-per-prior-boss HP escalation
	# applied at spawn in _ready(). Incremented here — exactly once per boss —
	# because the _dying guard above makes explode() a single-fire path
	# (reaver overrides explode() but calls super, so it routes through here
	# too). Guarded for autoload-less dev/test scenes. Explicit type, no `:=`.
	var run: Node = get_node_or_null("/root/Run")
	if run != null and "bosses_defeated" in run:
		run.bosses_defeated = int(run.bosses_defeated) + 1
	died.emit(bounty_value)
	# NOTE: do NOT call Run.sector_complete() here — that's the V2-era
	# per-boss sectors_cleared bump. In V3 a sector has 3 row bosses; the
	# sector only advances when ALL 3 die. Advance happens on next sector
	# map entry via sector_map_v3._advance_if_complete(), gated on
	# Run.is_sector_complete(). Bumping here on every boss death made the
	# map jump a sector after the first row boss kill.
	_on_boss_death()
	var ExplosionFx := load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.burst(global_position, 7, 28.0, 0.08)
	# Settling dust supplement (Roman 2026-05-24). Each of the 7 cascade
	# blasts gets its own smaller puff (16 particles), staggered to match
	# the 0.08s explosion cadence with mild positional jitter so the dust
	# layer mirrors the cascade rather than dumping all at the origin.
	var DeathDust := load("res://scripts/effects/death_dust.gd")
	var tree := get_tree()
	for i in range(7):
		var delay: float = float(i) * 0.08
		var jitter := Vector2(randf_range(-28.0, 28.0), randf_range(-28.0, 28.0))
		var puff_pos: Vector2 = global_position + jitter
		if delay <= 0.001:
			DeathDust.play_with_count(puff_pos, 16)
		else:
			tree.create_timer(delay).timeout.connect(DeathDust.play_with_count.bind(puff_pos, 16))
	if has_node("Sprite2D"):
		var BurnFx := load("res://scripts/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 1.2)
	if has_node("AnimationPlayer") and $AnimationPlayer.has_animation("explode"):
		$AnimationPlayer.play("explode")
	if has_node("EnemyDie"):
		$EnemyDie.play()
	health_changed.emit(0, max_health)
	await get_tree().create_timer(1.3).timeout
	queue_free()


# Subclass hook: cleanup on death (free minions, cancel timers, etc).
func _on_boss_death() -> void:
	pass


# ---- ShootTimer dumb-fire (wave director injects shoot_pattern) ---------

func _on_shoot_timer_timeout() -> void:
	if _dying:
		return
	# Suppress fire while a signature attack is being charged so the boss
	# reads as committed. Timer still loops so it's hot the moment the
	# charge releases.
	if not _charging and shoot_pattern != null:
		shoot_pattern.fire(self)
	if has_node("ShootTimer"):
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()


# ---- Phase state machine ------------------------------------------------

func _init_phases() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("boss")
	if phases.is_empty():
		# Subclass left it empty — treat as single 1.0 phase. No push_error
		# here because "1 phase" is a legitimate design choice for some bosses
		# (Reaver, Sentinel today). Subclasses that REQUIRE phases should
		# assert in their own _ready().
		_current_phase_idx = 0
		_on_phase_entered(0, "")
		return
	_current_phase_idx = 0
	var p0 = phases[0]
	if p0.enrage_flash:
		_enrage_flash()
	if p0.screen_shake_strength > 0.0:
		_screen_shake(p0.screen_shake_strength)
	phase_changed.emit(-1, 0, p0.name)
	_on_phase_entered(0, p0.name)


func _check_phase_transition() -> void:
	if phases.is_empty() or _dying:
		return
	if max_health <= 0:
		return
	var hp_pct: float = float(health) / float(max_health)
	# Find the highest-indexed phase whose threshold is met. Walking forward
	# lets us skip multiple phase gates in a single big-damage hit.
	var target_idx: int = _current_phase_idx
	for i in range(_current_phase_idx + 1, phases.size()):
		var ph = phases[i]
		if hp_pct <= ph.hp_threshold_pct:
			target_idx = i
		else:
			break
	if target_idx == _current_phase_idx:
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


# Subclass hook: react to a phase gate (mutate fire cadence, swap attack
# rotation, spawn extra adds, etc).
func _on_phase_entered(_phase_idx: int, _phase_name: String) -> void:
	pass


# Subclass hook: looped attack coroutine. Many bosses will just leave this
# empty and rely on ShootTimer + injected shoot_pattern. Subclasses with
# bespoke attack rotations (Commander's BH; future signature moves)
# implement here as `while not _dying: await ...` style.
func _attack_loop() -> void:
	pass


# ---- Telegraph helpers -------------------------------------------------

# Fire-and-forget telegraph. Spawns a brief VFX on the boss (or on the
# player if `lock_to_player`) for `duration` seconds, then auto-clears.
func start_telegraph(duration: float, color: Color = Color.RED, lock_to_player: bool = false) -> void:
	var host: Node2D = self
	if lock_to_player:
		var p := find_player()
		if p != null and p is Node2D:
			host = p as Node2D
	var ring := ColorRect.new()
	ring.color = color
	ring.color.a = 0.0
	ring.size = Vector2(24, 24)
	ring.position = -ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "color:a", 0.55, duration * 0.4)
	tw.tween_property(ring, "size", Vector2(40, 40), duration * 0.6)
	tw.parallel().tween_property(ring, "position", Vector2(-20, -20), duration * 0.6)
	tw.tween_property(ring, "color:a", 0.0, 0.15)
	tw.tween_callback(ring.queue_free)


# Awaitable telegraph — blocks the caller for `duration` seconds after
# spawning the visual.
func await_telegraph(duration: float) -> void:
	start_telegraph(duration)
	await get_tree().create_timer(duration).timeout


# ---- Attack primitives -------------------------------------------------
# All primitives spawn bullets at root via the existing enemy_bullet
# scene contract (subclasses pass the same `bullet_scene` they'd give a
# shoot_pattern Resource). Pull from a member if subclass set one.

const _DEFAULT_BULLET = preload("res://scenes/projectiles/enemy_bullet.tscn")


func _bullet_scene() -> PackedScene:
	# Prefer subclass-provided bullet via shoot_pattern.bullet_scene if set.
	if shoot_pattern != null and "bullet_scene" in shoot_pattern and shoot_pattern.bullet_scene != null:
		return shoot_pattern.bullet_scene
	return _DEFAULT_BULLET


# Resolve which variant to use: explicit override wins, then
# default_bullet_variant, then null (= plain enemy_bullet look).
func _resolve_variant(override: BulletVariant) -> BulletVariant:
	if override != null:
		return override
	return default_bullet_variant


func _spawn_bullet(dir: Vector2, variant: BulletVariant = null) -> void:
	var bs := _bullet_scene()
	if bs == null:
		return
	var b = bs.instantiate()
	# IMPORTANT: set variant BEFORE add_child so _apply_variant() fires in
	# _ready(), which runs at add_child time. Setting it after add_child
	# would be a no-op.
	var v: BulletVariant = _resolve_variant(variant)
	if v != null:
		b.variant = v
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(global_position, dir)
	else:
		b.position = global_position


# Time-staggered aimed burst. `interval=0` fires all at once aimed at the
# player's position at the start of the burst.
func fire_aimed_burst(count: int, spread_deg: float, interval: float = 0.0, variant: BulletVariant = null) -> void:
	if count <= 0:
		return
	var aim: Vector2 = _aim_at_player()
	var spread_rad: float = deg_to_rad(spread_deg)
	for i in count:
		if not is_instance_valid(self) or _dying:
			return
		var t: float = 0.0
		if count > 1:
			t = (float(i) / float(count - 1)) * 2.0 - 1.0
		var dir: Vector2 = aim.rotated(t * spread_rad * 0.5)
		_spawn_bullet(dir, variant)
		if interval > 0.0 and i < count - 1:
			await get_tree().create_timer(interval).timeout


# Synchronous aimed cone — all bullets at once.
func fire_aimed_cone(count: int, spread_deg: float, variant: BulletVariant = null) -> void:
	if count <= 0:
		return
	var aim: Vector2 = _aim_at_player()
	var spread_rad: float = deg_to_rad(spread_deg)
	for i in count:
		var t: float = 0.0
		if count > 1:
			t = (float(i) / float(count - 1)) * 2.0 - 1.0
		_spawn_bullet(aim.rotated(t * spread_rad * 0.5), variant)


# Dumb fan (not aimed). `downward=true` centers on +Y, false centers on -Y.
func fire_spread(count: int, spread_deg: float, downward: bool = true, variant: BulletVariant = null) -> void:
	if count <= 0:
		return
	var base: Vector2 = Vector2(0, 1) if downward else Vector2(0, -1)
	var spread_rad: float = deg_to_rad(spread_deg)
	for i in count:
		var t: float = 0.0
		if count > 1:
			t = (float(i) / float(count - 1)) * 2.0 - 1.0
		_spawn_bullet(base.rotated(t * spread_rad * 0.5), variant)


# Even-spaced 360 ring. `bullet_speed_override` left as a hint for future
# work — current enemy_bullet doesn't expose a speed setter from outside
# the scene.
func fire_ring(count: int, angle_offset_deg: float = 0.0, variant: BulletVariant = null) -> void:
	if count <= 0:
		return
	var step: float = TAU / float(count)
	var off: float = deg_to_rad(angle_offset_deg)
	for i in count:
		var theta: float = off + step * i
		_spawn_bullet(Vector2(cos(theta), sin(theta)), variant)


# Telegraphed horizontal beam with one safe-gap. Renders the telegraph
# line, then a solid bar minus the gap PLUS two Area2D damage hitboxes
# (one per side of the gap) that deal `damage` to bodies in the "player"
# group on contact.
func fire_beam_telegraphed(width_px: float, gap_x: float, telegraph_duration: float, beam_duration: float, damage: int = 1) -> void:
	# Telegraph: 1-px red line at the boss's Y across the whole playfield,
	# with a thin gap at gap_x to read the safe-zone.
	var beam_y: float = global_position.y
	var gap_half: float = width_px * 0.5
	var tele_left := ColorRect.new()
	tele_left.color = Color(1.0, 0.15, 0.15, 0.7)
	tele_left.size = Vector2(max(0.0, gap_x - gap_half - Playfield.X_MIN), 1.0)
	tele_left.position = Vector2(Playfield.X_MIN, beam_y - 0.5)
	tele_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(tele_left)
	var tele_right := ColorRect.new()
	tele_right.color = Color(1.0, 0.15, 0.15, 0.7)
	tele_right.size = Vector2(max(0.0, Playfield.X_MAX - (gap_x + gap_half)), 1.0)
	tele_right.position = Vector2(gap_x + gap_half, beam_y - 0.5)
	tele_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(tele_right)
	await get_tree().create_timer(telegraph_duration).timeout
	if is_instance_valid(tele_left):
		tele_left.queue_free()
	if is_instance_valid(tele_right):
		tele_right.queue_free()
	if _dying:
		return
	# Beam: width_px tall bar across the playfield minus the safe gap.
	var left := ColorRect.new()
	left.color = Color(1.0, 0.3, 0.3, 0.9)
	left.size = Vector2(max(0.0, gap_x - gap_half - Playfield.X_MIN), width_px)
	left.position = Vector2(Playfield.X_MIN, beam_y - width_px * 0.5)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(left)
	var right := ColorRect.new()
	right.color = Color(1.0, 0.3, 0.3, 0.9)
	right.size = Vector2(max(0.0, Playfield.X_MAX - (gap_x + gap_half)), width_px)
	right.position = Vector2(gap_x + gap_half, beam_y - width_px * 0.5)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(right)
	# Damage hitboxes — one per side of the gap. Spawned as children of the
	# current scene so they outlive any boss reposition mid-beam.
	_spawn_beam_hitbox(Playfield.X_MIN, gap_x - gap_half, beam_y, width_px, beam_duration, damage)
	_spawn_beam_hitbox(gap_x + gap_half, Playfield.X_MAX, beam_y, width_px, beam_duration, damage)
	await get_tree().create_timer(beam_duration).timeout
	if is_instance_valid(left):
		left.queue_free()
	if is_instance_valid(right):
		right.queue_free()


# Internal: spawn an Area2D rectangle hitbox covering [x_left, x_right] at
# beam_y, height width_px, that damages anything in the "player" group on
# contact, then auto-frees after beam_duration.
func _spawn_beam_hitbox(x_left: float, x_right: float, beam_y: float, width_px: float, beam_duration: float, damage: int) -> void:
	var w: float = max(0.0, x_right - x_left)
	if w <= 0.0:
		return
	var hb := Area2D.new()
	hb.monitoring = true
	hb.monitorable = false
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, width_px)
	cs.shape = shape
	hb.add_child(cs)
	hb.global_position = Vector2(x_left + w * 0.5, beam_y)
	get_tree().current_scene.add_child(hb)
	var dmg: int = damage
	hb.area_entered.connect(func(other: Area2D) -> void:
		if other != null and other.is_in_group("player") and other.has_method("take_damage"):
			other.take_damage(dmg)
	)
	get_tree().create_timer(beam_duration).timeout.connect(func() -> void:
		if is_instance_valid(hb):
			hb.queue_free()
	)


# ---- Movement primitives -----------------------------------------------

# Replace the current movement Resource with a sweep. Restarts the
# pattern's internal phase via on_start().
func sweep_horizontal(amplitude_x: float, period_sec: float, _ease: String = "sin3") -> void:
	var BossSweep := load("res://scripts/enemies/patterns/boss_sweep.gd")
	var mv = BossSweep.new()
	mv.hover_y = boss_hover_y
	mv.sweep_amplitude = amplitude_x
	# boss_sweep uses sweep_frequency (cycles per second) — period_sec converts.
	mv.sweep_frequency = 1.0 / max(period_sec, 0.01)
	_anchored = false
	_pattern = mv
	if _pattern.has_method("on_start"):
		_pattern.on_start(self)


# Stop the sweep and lerp toward a fixed point.
func anchor_at(pos: Vector2) -> void:
	_anchored = true
	_anchor_pos = pos
	_pattern = null


# Telegraphed straight-line dash toward a target. Ignores playfield clamp
# (caller is responsible for not parking the boss off-screen). Reuses the
# _charging slow-down read during the telegraph.
func dive_toward(target: Vector2, speed: float, telegraph_first: bool = true) -> void:
	if telegraph_first:
		_charging = true
		start_telegraph(0.9, Color.RED, true)
		await get_tree().create_timer(0.9).timeout
		_charging = false
		if _dying:
			return
	var dist: float = global_position.distance_to(target)
	var dur: float = dist / max(speed, 1.0)
	# Disable sweep/anchor during the dash so movement doesn't fight us.
	var prev_anchor: bool = _anchored
	_anchored = false
	var prev_pattern = _pattern
	_pattern = null
	var tw := create_tween()
	tw.tween_property(self, "position", target, dur)
	await tw.finished
	_pattern = prev_pattern
	_anchored = prev_anchor


# Per-frame x-tracking toward the player. Strength 0 disables, 1 = locked
# to the player. Wraps with _process clamp.
func mirror_player_x(strength: float = 1.0) -> void:
	_mirror_strength = clamp(strength, 0.0, 1.0)
	_mirror_center_x = Playfield.CENTER.x


# ---- Shared VFX --------------------------------------------------------

func _enrage_flash(color: Color = Color(1, 0.3, 0.3, 1), duration: float = 0.35) -> void:
	if not has_node("Sprite2D"):
		return
	var spr := $Sprite2D as Sprite2D
	if spr == null:
		return
	var orig: Color = spr.modulate
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate", color, duration * 0.4)
	tw.tween_property(spr, "modulate", orig, duration * 0.6)
	# Expanding palette ring — quick punch on top of the flash.
	var ring := ColorRect.new()
	ring.color = Color(color.r, color.g, color.b, 0.8)
	ring.size = Vector2(8, 8)
	ring.position = -ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	var rtw := ring.create_tween()
	rtw.tween_property(ring, "size", Vector2(48, 48), duration)
	rtw.parallel().tween_property(ring, "position", Vector2(-24, -24), duration)
	rtw.parallel().tween_property(ring, "color:a", 0.0, duration)
	rtw.tween_callback(ring.queue_free)


# Defer to the main scene's Camera2D (same pattern used by smart_bomb /
# hyper_mode). Silently no-ops if no camera is in the current scene
# (capture scenes, test harnesses).
func _screen_shake(strength: float = 4.0, _duration: float = 0.25) -> void:
	var sc: Node = get_tree().current_scene
	if sc == null:
		return
	var cam: Node = sc.get_node_or_null("Camera2D")
	if cam == null:
		return
	if cam.has_method("add_trauma"):
		# Camera tops out at 0.5 trauma; map strength 0..10 → 0..0.5.
		cam.add_trauma(clamp(strength * 0.05, 0.0, 0.5))


# ---- Aim helper --------------------------------------------------------

func _aim_at_player() -> Vector2:
	var p := find_player()
	if p == null or not (p is Node2D):
		return Vector2(0, 1)
	var to_p: Vector2 = (p as Node2D).global_position - global_position
	if to_p.length() <= 0.001:
		return Vector2(0, 1)
	return to_p.normalized()


# ---- Hazard parenting helper (used by signature attacks) ---------------

# Parent a hazard so it draws ABOVE the parallax backdrop but BELOW the
# ships. Mirrors boss.gd's previous behavior.
func add_world_node_above_backdrop(node: Node2D) -> void:
	var p := get_parent()
	var bd: Node = null
	if p:
		bd = p.get_node_or_null("Backdrop")
	if bd:
		bd.add_child(node)
	else:
		if p:
			p.add_child(node)
