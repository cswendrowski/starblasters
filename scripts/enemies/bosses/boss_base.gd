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
# resource_path == "res://scripts/enemies/bosses/boss_base.gd" — every boss
# subclass picks up the bar automatically by extending this file.

const Playfield = preload("res://scripts/systems/playfield.gd")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

# Flat base HP multiplier applied to EVERY boss (designer Roman, 2026-05-31:
# "bosses die too fast"). Layered ON TOP of the per-boss-defeated +5% run
# escalation below, so effective HP = base * BASE_HP_MULT * (1 + 0.05*defeated).
# Single shared site so all bosses pick it up; tunable here.
const BASE_HP_MULT: float = 1.5

# health_changed is INHERITED from EnemyBase (signal health_changed(current, max)) —
# do NOT redeclare it here (a duplicate parent member is a parse error that the class
# cache only catches when the parent loads first, so it surfaced intermittently in the
# --import/--script passes). boss_base's health_changed.emit(...) calls use the inherited one.
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
const BossPhase = preload("res://scripts/enemies/bosses/boss_phase.gd")
const MidDepthPresentation = preload("res://scripts/effects/mid_depth_presentation.gd")
const EnemySfxC = preload("res://scripts/effects/enemy_sfx.gd")
@export var phases: Array[Resource] = []

# ---- Phase state machine -----------------------------------------------

var _current_phase_idx: int = -1   # -1 = not yet initialised
# Subclass-visible: true while a charged attack is winding up. Halts the
# ShootTimer fire and slows the movement step for a "boss is committed"
# read. Reuse from any signature attack that needs the read.
var _charging: bool = false

# ---- Encounter state machine (2026-06-16, standardized boss system) ------
# OPT-IN second phase model that supersedes the HP-ladder above for bosses that
# need lifecycle states (scripted arrival / invincible transitions / exit
# choreography) and non-HP triggers (timers, flags, loops back to an earlier
# state). A boss opts in by overriding `_build_states()` to register a state
# graph; if it does NOT, `_states` stays empty, `_sm_active` is false, and the
# legacy `phases[]` ladder runs exactly as before (ZERO behaviour change for the
# 7 existing bosses). The two models are mutually exclusive per-boss.
#
# Behaviour dispatch mirrors the legacy split: `_state_enter/_state_tick/
# _state_exit(name)` are the analogue of `_on_phase_entered` + `_attack_loop`.
# The idiomatic per-state attack rotation is a coroutine started in `_state_enter`
# guarded by `while _state == name and not _dying:` so it self-cancels on exit.
var _sm_active: bool = false
var _states: Dictionary = {}              # StringName -> { "transitions": Array }
var _state_order: Array[StringName] = []  # registration order; [0] is the initial state
var _initial_state: StringName = &""      # override to start somewhere other than _state_order[0]
var _state: StringName = &""              # current state name
var _state_t: float = 0.0                 # seconds elapsed in the current state
var _flags: Dictionary = {}               # named booleans raised for t_flag() triggers
# Damage-immunity window — set true by transition/arrival states. While true,
# take_hit() no-ops (with a deflect tick) so the boss can't be killed mid-animation.
var _invincible: bool = false

# ---- Destructible parts (turrets / pods / weak-points) ------------------
# Registered BossPart instances. Optional HP-threshold part loss is decoupled
# from the phase machine: set_part_loss_thresholds([0.75, 0.5, 0.25]) blows a
# random live part each time HP crosses a listed fraction (the Shepherd's turrets).
var _parts: Array = []
var _part_loss_thresholds: Array = []     # descending hp fractions
var _parts_lost: int = 0

# ---- Movement plumbing -------------------------------------------------

var _pattern = null
# Scripted-move mode: while true, an awaitable movement helper (arrive_from /
# vertical_pass / fly_offscreen) owns `position` via a tween, and _process leaves
# pattern/anchor/mirror/clamp alone so the boss can travel OFF the playfield.
var _scripted_move: bool = false
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
	# Bosses carry bespoke art + their own presentation; opt out of the shared
	# ship VFX (ground shadow + damage-overlay shader) to avoid doubling with
	# boss-specific effects and to keep large hand-authored sprites untouched.
	has_ship_vfx = false
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
		var ShadowFx := load("res://scripts/effects/shadow_fx.gd")
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
	# State-machine bosses enter their initial state now (boss is placed + live).
	if _sm_active and _state == &"":
		var initial: StringName = _initial_state if _initial_state != &"" else _state_order[0]
		_enter_state(initial)
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
	# While a scripted move owns position (off-playfield arrival/pass/exit), skip
	# the normal movement + clamp so the tween isn't fought. The SM still ticks so
	# its transitions (e.g. on the move's completion flag) keep firing.
	if not _scripted_move:
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
	if _sm_active:
		_tick_state_machine(delta)


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
	_check_part_loss()


# Override EnemyBase.take_hit so the phase check runs even on kills (rare,
# but the kill itself emits a final health_changed via explode()).
func take_hit(damage: int = 1) -> bool:
	# Invincibility window (transition/arrival states) — absorb the hit with a
	# deflect tick, no health loss. Guarded so a dying boss still resolves.
	if _invincible and not _dying:
		_deflect_tick()
		return false
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
	if run != null and run.has_method("on_boss_defeated"):
		# Bumps bosses_defeated AND refreshes the outpost hub (+1d6 charges, re-roll
		# stock on next visit). See run_state.on_boss_defeated (Roman 2026-06-08).
		run.on_boss_defeated()
	elif run != null and "bosses_defeated" in run:
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
		var BurnFx := load("res://scripts/effects/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 1.2)
	if has_node("AnimationPlayer") and $AnimationPlayer.has_animation("explode"):
		$AnimationPlayer.play("explode")
	# Old $EnemyDie clip retired (Roman 2026-06-10) — the boss death burst above sounds through
	# the distance-based ExplosionSfx like every other death.
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
		EnemySfxC.play_for(self)
	if has_node("ShootTimer"):
		$ShootTimer.wait_time = randf_range(fire_interval_min, fire_interval_max)
		$ShootTimer.start()


# ---- Phase state machine ------------------------------------------------

func _init_phases() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("boss")
	# Opt-in state machine: a boss that registers a state graph runs on it and
	# skips the legacy HP-ladder entirely. Built before the initial state enters.
	_build_states()
	if not _states.is_empty():
		_sm_active = true
		# The initial state is entered from start() — once the director has placed
		# the boss and it's live — so arrival choreography sees a real position.
		return
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


# ======================================================================
# Encounter state machine (the standardized boss system). See the field
# block near the top for the opt-in contract. Subclasses author the graph in
# _build_states() and behaviour in _state_enter/_state_tick/_state_exit.
# ======================================================================

# Subclass hook: register the state graph here (called once before the initial
# state is entered). Leave empty to use the legacy phases[] HP-ladder. Example:
#   add_state(&"ARRIVAL"); add_state(&"PHASE_1"); add_state(&"TRANSITION_1")
#   add_transition(&"ARRIVAL", t_flag(&"arrived"), &"PHASE_1")
#   add_transition(&"PHASE_1", t_any([t_hp(0.75), t_after(20.0)]), &"TRANSITION_1")
func _build_states() -> void:
	pass


# Register a state. The first registered state is the initial one unless
# _initial_state is set. Safe to call twice with the same name (idempotent).
func add_state(state_name: StringName) -> void:
	if not _states.has(state_name):
		_states[state_name] = {"transitions": []}
		_state_order.append(state_name)


# Add a trigger-gated transition. Each frame the current state's transitions are
# evaluated in the order added; the FIRST whose trigger fires wins.
func add_transition(from_state: StringName, trigger: Dictionary, to_state: StringName) -> void:
	if not _states.has(from_state):
		add_state(from_state)
	_states[from_state]["transitions"].append({"trigger": trigger, "to": to_state})


# ---- Trigger library (plain data dicts: inspectable, no closure capture) ----
func t_hp(pct: float) -> Dictionary: return {"type": "hp_below", "pct": pct}
func t_after(seconds: float) -> Dictionary: return {"type": "after", "sec": seconds}
func t_flag(flag: StringName) -> Dictionary: return {"type": "flag", "flag": flag}
func t_any(subs: Array) -> Dictionary: return {"type": "any", "subs": subs}
func t_all(subs: Array) -> Dictionary: return {"type": "all", "subs": subs}
# Escape hatch — a Callable() -> bool evaluated live each frame.
func t_pred(cb: Callable) -> Dictionary: return {"type": "pred", "cb": cb}


func _eval_trigger(t: Dictionary) -> bool:
	match String(t.get("type", "")):
		"hp_below":
			return max_health > 0 and float(health) / float(max_health) <= float(t["pct"])
		"after":
			return _state_t >= float(t["sec"])
		"flag":
			return bool(_flags.get(t["flag"], false))
		"any":
			for s in t["subs"]:
				if _eval_trigger(s):
					return true
			return false
		"all":
			for s in t["subs"]:
				if not _eval_trigger(s):
					return false
			return true
		"pred":
			var cb: Callable = t["cb"]
			return cb.is_valid() and bool(cb.call())
	return false


# Raise/lower a named boolean read by t_flag() triggers (e.g. "arrived",
# "anim_done"). Cleared automatically on every state change.
func set_flag(flag: StringName, value: bool = true) -> void:
	_flags[flag] = value


# Damage-immunity window. While true, take_hit() no-ops with a deflect tick.
func set_invincible(value: bool) -> void:
	_invincible = value


# Subclass hooks — per-state behaviour. _state_enter is the place to start a
# per-state coroutine guarded by `while _state == name and not _dying:`.
func _state_enter(_state_name: StringName) -> void:
	pass
func _state_tick(_state_name: StringName, _delta: float) -> void:
	pass
func _state_exit(_state_name: StringName) -> void:
	pass


# Enter a state: run the old state's exit hook, reset the timer + per-state
# flags, fire phase_changed, run the new state's enter hook.
func _enter_state(state_name: StringName) -> void:
	if not _states.has(state_name):
		push_error("BossBase: unknown state " + String(state_name))
		return
	var old: StringName = _state
	if old != &"":
		_state_exit(old)
	_state = state_name
	_state_t = 0.0
	_flags.clear()
	phase_changed.emit(_state_order.find(old), _state_order.find(state_name), String(state_name))
	_state_enter(state_name)


# Force a jump to any registered state — escape hatch for event-driven logic
# (a destroyed part, a scripted cue) that bypasses the trigger table.
func go_to_state(state_name: StringName) -> void:
	if _sm_active:
		_enter_state(state_name)


# Per-frame pump: advance the state timer, tick the state, then evaluate
# transitions (first match wins). Called from _process while _sm_active.
func _tick_state_machine(delta: float) -> void:
	if _state == &"" or _dying:
		return
	_state_t += delta
	_state_tick(_state, delta)
	if _dying or not _sm_active:
		return
	for tr in _states[_state]["transitions"]:
		if _eval_trigger(tr["trigger"]):
			_enter_state(tr["to"])
			return


# Brief cyan deflect flash while invincible — reads as "hits aren't landing".
func _deflect_tick() -> void:
	if not has_node("Sprite2D"):
		return
	var spr := $Sprite2D as Sprite2D
	if spr == null:
		return
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate", Color(0.5, 0.9, 1.4, 1.0), 0.05)
	tw.tween_property(spr, "modulate", Color(1, 1, 1, 1), 0.1)


# ---- Destructible parts API --------------------------------------------

# Register a BossPart so the boss tracks it (for threshold loss + cleanup) and
# is notified when it dies. Call after add_child-ing the part.
func register_part(part: Node) -> void:
	if part == null or part in _parts:
		return
	_parts.append(part)
	if part.has_signal("part_destroyed") and not part.part_destroyed.is_connected(_on_part_destroyed):
		part.part_destroyed.connect(_on_part_destroyed)


func _on_part_destroyed(part: Node) -> void:
	_parts.erase(part)
	_on_part_lost(part)


# Subclass hook: react to a part being destroyed (retarget a coordinator,
# escalate a phase, etc).
func _on_part_lost(_part: Node) -> void:
	pass


# Live (still-valid) registered parts.
func live_parts() -> Array:
	var out: Array = []
	for p in _parts:
		if is_instance_valid(p):
			out.append(p)
	return out


# Blow a random live part now (used by the HP-threshold loss + on demand).
func destroy_random_part() -> void:
	var live := live_parts()
	if live.is_empty():
		return
	live[randi() % live.size()].destroy()


# Free all surviving parts — call from _on_boss_death so they don't linger or
# keep gating wave-clear after the boss dies.
func free_parts() -> void:
	for p in _parts:
		if is_instance_valid(p):
			p.queue_free()
	_parts.clear()


# Configure HP fractions at which a random part is blown (e.g. [0.75,0.5,0.25]).
func set_part_loss_thresholds(fractions: Array) -> void:
	_part_loss_thresholds = fractions.duplicate()
	_part_loss_thresholds.sort()
	_part_loss_thresholds.reverse()   # descending so we cross them as HP drops
	_parts_lost = 0


# Called from hit(): blow a part for each newly-crossed threshold.
func _check_part_loss() -> void:
	if _part_loss_thresholds.is_empty() or max_health <= 0:
		return
	var frac: float = float(health) / float(max_health)
	while _parts_lost < _part_loss_thresholds.size() and frac <= float(_part_loss_thresholds[_parts_lost]):
		_parts_lost += 1
		destroy_random_part()


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


# World parent for boss-spawned visuals (bullets, telegraphs, beam/zone hitboxes, firecore
# drops). The live combat scene normally; in a SubViewport bench the bullet_world layer wins
# so they render + collide inside the preview instead of the window's top-left corner.
func _world() -> Node:
	return BulletWorld.resolve(self, get_tree().current_scene)


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
	_world().add_child(b)
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
	_world().add_child(tele_left)
	var tele_right := ColorRect.new()
	tele_right.color = Color(1.0, 0.15, 0.15, 0.7)
	tele_right.size = Vector2(max(0.0, Playfield.X_MAX - (gap_x + gap_half)), 1.0)
	tele_right.position = Vector2(gap_x + gap_half, beam_y - 0.5)
	tele_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world().add_child(tele_right)
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
	_world().add_child(left)
	var right := ColorRect.new()
	right.color = Color(1.0, 0.3, 0.3, 0.9)
	right.size = Vector2(max(0.0, Playfield.X_MAX - (gap_x + gap_half)), width_px)
	right.position = Vector2(gap_x + gap_half, beam_y - width_px * 0.5)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world().add_child(right)
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
	_world().add_child(hb)
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


# ---- Encounter behaviour helpers (reusable across bosses) --------------
# Movement choreography (arrival / off-screen exit / vertical pass) used by
# lifecycle states, plus a few shared attack/transition primitives the Shepherd
# testbed needs. All movement helpers are awaitable so a state coroutine can
# `await arrive_from(...)` then raise a flag the trigger table reads.

# High-hold "jiggle drift": a gentle small-amplitude sweep that reads as the
# capital idling in place. Thin wrapper over sweep_horizontal.
func jiggle_hold(amplitude_x: float = 16.0, period_sec: float = 4.5) -> void:
	_scripted_move = false
	sweep_horizontal(amplitude_x, period_sec)


# Awaitable: fly fully off-screen along `direction` (e.g. Vector2.UP / DOWN).
func fly_offscreen(direction: Vector2, speed: float = 280.0) -> void:
	_scripted_move = true
	var vp: Vector2 = get_viewport_rect().size
	var dir: Vector2 = direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var target: Vector2 = position + dir * (vp.length() + 160.0)
	var dur: float = position.distance_to(target) / max(speed, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished


# Awaitable: the Shepherd's signature entrance — park below the screen in `lane_x`,
# sweep up and off the top, then descend into the hold position. Ends with the boss
# anchored at the hold so a follow-up jiggle_hold/sweep reads cleanly.
func arrive_from(lane_x: float, speed: float = 170.0) -> void:
	_scripted_move = true
	var vp: Vector2 = get_viewport_rect().size
	position = Vector2(lane_x, vp.y + 60.0)
	var top_target := Vector2(lane_x, -70.0)
	var dur1: float = position.distance_to(top_target) / max(speed, 1.0)
	var tw1 := create_tween()
	tw1.tween_property(self, "position", top_target, dur1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw1.finished
	if _dying:
		return
	# Re-enter from the top and settle into the hold.
	var hold := Vector2(Playfield.CENTER.x, boss_hover_y)
	position = Vector2(hold.x, -50.0)
	var tw2 := create_tween()
	tw2.tween_property(self, "position", hold, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw2.finished
	_scripted_move = false


# Awaitable: a top-to-bottom traverse like the missile cruiser. `on_tick` (optional
# Callable taking the 0..1 progress) lets the caller fire salvos along the pass.
func vertical_pass(speed: float = 95.0, on_tick: Callable = Callable()) -> void:
	_scripted_move = true
	var vp: Vector2 = get_viewport_rect().size
	position = Vector2(Playfield.CENTER.x, -50.0)
	var target := Vector2(position.x, vp.y + 50.0)
	var dur: float = position.distance_to(target) / max(speed, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "position", target, dur)
	if on_tick.is_valid():
		# Fire the callback a handful of times across the pass.
		var n := 6
		for i in range(1, n):
			tw.parallel().tween_callback(on_tick.bind(float(i) / float(n))).set_delay(dur * float(i) / float(n))
	await tw.finished
	_scripted_move = false


# Awaitable transition flare (Shepherd's Transition 1): N red engine flashes, then a
# flare that NUKES nearby projectiles and opens a brief damage area to close players.
# The boss is held invincible for the whole animation.
func flare_clear(radius: float = 70.0, damage: int = 1, flashes: int = 3) -> void:
	set_invincible(true)
	for i in flashes:
		if _dying:
			set_invincible(false)
			return
		_enrage_flash(Color(1.5, 0.2, 0.2, 1.0), 0.22)
		await get_tree().create_timer(0.3).timeout
	if _dying:
		set_invincible(false)
		return
	_screen_shake(8.0)
	_clear_projectiles_in_radius(radius)
	_spawn_circle_hitbox(global_position, radius, 0.45, damage)
	# Placeholder flare VFX — the expanding enrage ring stands in until the new art
	# lands (spec: "use the gun muzzle flash sprite strip for now").
	_enrage_flash(Color(1.6, 0.9, 0.4, 1.0), 0.5)
	await get_tree().create_timer(0.5).timeout
	set_invincible(false)


# Free every projectile (group "bullets") within `radius` of the boss.
func _clear_projectiles_in_radius(radius: float) -> void:
	var r2: float = radius * radius
	for b in get_tree().get_nodes_in_group("bullets"):
		if b is Node2D and (b as Node2D).global_position.distance_squared_to(global_position) <= r2:
			b.queue_free()


# Telegraphed area strikes at random playfield positions (Phase 2 "zone strike
# missiles"). Awaitable for one cycle: telegraph -> impact + brief damage area.
func fire_zone_strike(count: int = 3, telegraph: float = 0.8, radius: float = 26.0, damage: int = 1) -> void:
	var vp: Vector2 = get_viewport_rect().size
	for i in count:
		var px: float = randf_range(Playfield.X_MIN + radius, Playfield.X_MAX - radius)
		var py: float = randf_range(70.0, vp.y - 40.0)
		_zone_strike_at(Vector2(px, py), radius, telegraph, damage)
	await get_tree().create_timer(telegraph + 0.25).timeout


# Fire-and-forget single zone strike: a growing red telegraph ring, then an
# explosion + a one-shot circular damage area.
func _zone_strike_at(center: Vector2, radius: float, telegraph: float, damage: int) -> void:
	var tele := ColorRect.new()
	tele.color = Color(1.0, 0.25, 0.2, 0.0)
	tele.size = Vector2(radius * 2.0, radius * 2.0)
	tele.position = center - tele.size * 0.5
	tele.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world().add_child(tele)
	var tw := tele.create_tween()
	tw.tween_property(tele, "color:a", 0.5, telegraph * 0.8)
	tw.tween_callback(func() -> void:
		if is_instance_valid(tele):
			tele.queue_free()
		if _dying:
			return
		var ExplosionFx := load("res://scripts/effects/explosion_fx.gd")
		ExplosionFx.play(center, 1.0, true, _world())
		_spawn_circle_hitbox(center, radius, 0.3, damage)
	)


# A one-shot circular Area2D that damages the "player" group, auto-freed after
# `duration`. Companion to _spawn_beam_hitbox (rect) for radial strikes.
func _spawn_circle_hitbox(center: Vector2, radius: float, duration: float, damage: int) -> void:
	var hb := Area2D.new()
	hb.monitoring = true
	hb.monitorable = false
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	hb.add_child(cs)
	hb.global_position = center
	_world().add_child(hb)
	var dmg: int = damage
	hb.area_entered.connect(func(other: Area2D) -> void:
		if other != null and other.is_in_group("player") and other.has_method("take_damage"):
			other.take_damage(dmg)
	)
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(hb):
			hb.queue_free()
	)


# Spawn a drifting firecore hazard below the boss (Phase 3 "releases its fire
# cores one after another"). Reuses the zealot firecore hazard scene.
func release_firecore(offset: Vector2 = Vector2(0, 12)) -> void:
	var FC := load("res://scenes/enemies/factions/zealot/firecore_hazard.tscn")
	if FC == null:
		return
	var fc = FC.instantiate()
	_world().add_child(fc)
	if fc is Node2D:
		(fc as Node2D).global_position = global_position + offset
	if fc.has_method("start"):
		fc.start(global_position + offset)


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
# ships. Delegates to the shared faked-mid-depth helper (one source of truth
# for the backdrop-parenting seam). get_parent() is the scene holding Backdrop.
func add_world_node_above_backdrop(node: Node2D) -> void:
	MidDepthPresentation.add_above_backdrop(get_parent(), node)
