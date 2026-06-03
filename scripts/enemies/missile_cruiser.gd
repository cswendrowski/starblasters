class_name MissileCruiser
extends Node2D

# MISSILE CRUISER (Roman, 2026-05-31) — a background "mortar ship" that
# traverses vertically through the MID parallax depth and rains AoE missiles
# onto the playfield. It is UNATTACKABLE and deliberately NOT a member of the
# "enemies" group: director._hazards_present()/_live_combatants_present()
# would otherwise treat it as a live combatant and freeze wave-clear forever.
#
# It is a plain world-space Node2D. The combat camera is centred on
# (240,135) of the 480x270 viewport, so world coords == playfield coords; its
# telegraph circles + missiles + explosions all spawn in plain world space
# and are parented to the WORLD (get_tree().root), never to the cruiser, so
# they outlive it when it traverses off the far edge.
#
# FAKED MID-DEPTH (confirmed faked, not literal CanvasLayer parenting): the
# node is added as a child of the scene's `Backdrop` Node2D (above the parallax
# layers, below the ships, in world space) via MidDepthPresentation — the shared
# faked-depth helper (scripts/effects/mid_depth_presentation.gd). It is scaled
# DOWN and its BODY sprite tinted toward a desaturated background blue/grey +
# grade-matched to the live mid layer so it reads as living in the mid layer.
# The engine-glow sprite is left bright (additive + shader bloom) so the tint
# never dims the glow.
#
# STRUCTURAL TEMPLATE: scripts/enemies/tether_mine.gd (fly-to-fixed-point +
# phase state machine + per-frame _draw), with the EnemyBase inheritance
# stripped out.

const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
# Shared faked-mid-depth presentation (backdrop parenting + depth-tint shader +
# live-layer grade-match + bright glow). Extracted from this script 2026-06-01
# (scripts/effects/mid_depth_presentation.gd) so every recycling / background
# ship reuses one source of truth.
const MidDepthPresentation = preload("res://scripts/effects/mid_depth_presentation.gd")

# --- Faked-depth tuning (designer-facing) -----------------------------------
# Visual scale of the whole cruiser. <1 sells "further away / mid layer".
@export var cruiser_scale: float = 0.7
# How far (0..1) the BODY sprite is tinted toward the background color. Applied
# to the body Sprite2D only — the engine glow stays bright.
@export var bg_tint_amount: float = 0.45
# Desaturated background blue/grey the body tints toward.
@export var bg_tint_color: Color = Color(0.42, 0.50, 0.62, 1.0)
# Extra emissive brightness on the engine-glow sprite (frame 1). >1 = additive
# overdrive on top of the shader bloom halo.
@export var glow_brightness: float = 1.8
# How strongly (0..1) the body adopts the mid layer's dark grade. 1 = exact
# match (as dark as mid-layer objects); 0 = full brightness. 0.5 keeps the
# cruiser reading a little brighter than the rest of the layer (Roman 2026-05-31).
@export var grade_strength: float = 0.5

# --- Traverse tuning --------------------------------------------------------
# Slow vertical traverse. If derive_speed_from_cycle is true this is treated as
# a CEILING and the actual speed is clamped down so one full salvo lands while
# the full sprite is on-screen.
# Roman 2026-05-31: HALVED 50 -> 25 so the cruiser dwells ~2x longer on-screen
# (more salvos). The derived ceiling (~66) still exceeds 25, so the
# guarantee-a-salvo-lands derivation is unchanged and just has more headroom.
@export var traverse_speed: float = 60.0
# When true, clamp traverse_speed so the on-screen dwell comfortably exceeds
# one mark->fire->explode cycle (so the explosions LAND on-screen).
@export var derive_speed_from_cycle: bool = true
# Safety margin (seconds) added to the cycle time when deriving the speed.
@export var cycle_dwell_margin: float = 1.0

# --- Attack-cycle tuning ----------------------------------------------------
@export var zone_count: int = 4              # marks/missiles per salvo
@export var telegraph_time: float = 1.2      # MARK phase duration (s)
@export var missile_travel_time: float = 0.8 # missile fly-to-zone time (s)
@export var fuse_time: float = 0.4           # delay after arrival before boom
@export var aoe_radius: float = 24.0         # explosion damage radius (px)
@export var explosion_damage: int = 1        # damage per player in radius
@export var cooldown_time: float = 2.0       # gap between salvos (s)
# Stagger between successive missile launches within a salvo. >0 makes the
# launch points fire in sequence (LaunchPoint1 → 2 → 3 → 4) instead of all at
# once (Roman 2026-06-01).
@export var launch_stagger: float = 0.16

# Y range (world/viewport) the zone points are picked within. X is always
# clamped to the gameplay band via Playfield.X_MIN/X_MAX. Kept inside 0..270.
@export var zone_y_min: float = 40.0
@export var zone_y_max: float = 240.0

# Minimum center-to-center separation between the chosen strike points so the
# red telegraph circles + AoE explosions don't visually overlap. Defaults to
# 2*aoe_radius + a small margin (kept modest: with a 216x200 band and 4 points
# this packs easily, so rejection sampling rarely hits the retry cap).
@export var min_zone_separation: float = 56.0  # ~= 2*aoe_radius(24) + 8 margin
# Retry cap for rejection sampling a non-overlapping point before accepting the
# best-spread candidate seen so far.
const ZONE_PICK_TRIES: int = 24

# --- Telegraph circle visual ------------------------------------------------
const TELEGRAPH_COLOR := Color(1.0, 0.15, 0.15, 0.5)  # filled red, alpha 0.5
const TELEGRAPH_PULSE_HZ: float = 3.0
const TELEGRAPH_PULSE_PX: float = 5.0                  # radius pulse amplitude

# --- Sprite layout ----------------------------------------------------------
const SPRITE_PX: float = 64.0   # source frame is 64x64
const BODY_FRAME: int = 0
const GLOW_FRAME: int = 1

enum Phase { ENTERING, MARK, FIRE_WAIT, COOLDOWN }

var _phase: int = Phase.ENTERING
var _phase_t: float = 0.0
var _direction: int = 1          # +1 = moving down, -1 = moving up
var _half_height: float = 0.0    # scaled half sprite height (for on-screen gate)
var _did_first_salvo: bool = false
var _live_telegraphs: Array = [] # active telegraph circle nodes this salvo
var _missiles_remaining: int = 0 # outstanding (live, in-flight) missiles this salvo
var _pending_fires: Array = []   # {zone, node} still waiting to launch (stagger)
var _stagger_t: float = 0.0      # countdown to the next staggered launch
# Cycling launch-point index. Advances by ONE per missile fired and PERSISTS
# across salvos so successive shots keep walking LaunchPoint1 -> 2 -> 3 -> 4 ->
# wrap (mod LAUNCH_POINT_COUNT). Roman 2026-05-31.
var _launch_idx: int = 0
const LAUNCH_POINT_COUNT: int = 4

@onready var _body: Sprite2D = get_node_or_null("Body") as Sprite2D
@onready var _glow: Sprite2D = get_node_or_null("Glow") as Sprite2D


func _ready() -> void:
	_half_height = SPRITE_PX * 0.5 * cruiser_scale

	# Pick entry edge (top or bottom) and park the sprite just off it.
	if randf() < 0.5:
		_direction = 1   # enter from top, move down
		global_position = Vector2(global_position.x, -_half_height - 8.0)
	else:
		_direction = -1  # enter from bottom, move up
		global_position = Vector2(global_position.x, 270.0 + _half_height + 8.0)

	scale = Vector2(cruiser_scale, cruiser_scale)

	# Rotate to face travel direction like other enemies (auto-rotate convention:
	# rotation = velocity.angle() + PI*0.5, sprite art points "up"/north).
	# Moving down (dir +1, vel (0,+1)) -> PI (nose down); moving up (dir -1,
	# vel (0,-1)) -> 0 (nose up). Children (Glow, Body, LaunchPoint) rotate with
	# the root; LaunchPoint at local (0,0) stays at center so launch/targeting are
	# rotation-invariant and missiles (world-parented) compute their own heading.
	var vel: Vector2 = Vector2(0.0, float(_direction))
	rotation = vel.angle() + PI * 0.5

	# Tint the BODY sprite only — never the root (would dim the glow + halo).
	# The shared helper lerps the art toward the bg color (true desaturation,
	# unlike modulate) and multiplies by grade_strength of the LIVE mid-layer
	# grade so the cruiser reads at mid-depth. get_parent() is the Backdrop
	# coordinator (we were add_child'd to it before _ready ran).
	if _body != null:
		_body.frame = BODY_FRAME
		MidDepthPresentation.apply_body_tint(
			_body, get_parent(), bg_tint_amount, bg_tint_color, grade_strength
		)

	# Engine glow: bright emissive frame + shader bloom halo, full brightness.
	# apply_glow parents the halo as a sibling under the host's parent, so the
	# host must already be in-tree — it is (we're inside the scene now).
	if _glow != null:
		_glow.frame = GLOW_FRAME
		MidDepthPresentation.apply_glow(_glow, glow_brightness)

	if derive_speed_from_cycle:
		traverse_speed = _derive_traverse_speed()

	_phase = Phase.ENTERING
	_phase_t = 0.0


# Cycle through EXPLODE = telegraph + travel + fuse (cooldown need NOT fit).
# Dwell (full sprite on-screen) = band_height / speed, where the band is the
# vertical range over which the sprite is FULLY on-screen.
#   band_height = 270 - 2*half_height = 270 - 64*scale
# Solve speed so dwell >= cycle + margin.
func _derive_traverse_speed() -> float:
	# The last missile in a staggered salvo launches (zone_count-1)*launch_stagger
	# after FIRE begins, so the cycle the dwell must cover grows by that much.
	var stagger_total: float = maxf(0.0, float(zone_count - 1)) * launch_stagger
	var cycle: float = telegraph_time + stagger_total + missile_travel_time + fuse_time
	var band_height: float = 270.0 - 2.0 * _half_height
	var max_speed_for_dwell: float = band_height / (cycle + cycle_dwell_margin)
	return minf(traverse_speed, max_speed_for_dwell)


func _is_fully_onscreen() -> bool:
	var top: float = global_position.y - _half_height
	var bottom: float = global_position.y + _half_height
	return top >= 0.0 and bottom <= 270.0


func _process(delta: float) -> void:
	# Always traverse (purely visual movement, no collision).
	global_position += Vector2(0.0, traverse_speed * delta * float(_direction))

	# Free ourselves once fully off the far edge. Clean up any un-launched
	# telegraph circles first so they don't linger in the world.
	if _direction > 0 and global_position.y - _half_height > 270.0:
		_clear_telegraphs()
		_clear_pending()
		queue_free()
		return
	if _direction < 0 and global_position.y + _half_height < 0.0:
		_clear_telegraphs()
		_clear_pending()
		queue_free()
		return

	match _phase:
		Phase.ENTERING:
			# Begin the first MARK the instant the full sprite is on-screen, so
			# a salvo is guaranteed to land while visible.
			if _is_fully_onscreen():
				_begin_mark()
		Phase.MARK:
			_phase_t += delta
			if _phase_t >= telegraph_time:
				_begin_fire()
		Phase.FIRE_WAIT:
			# Launch the salvo's missiles one at a time on the stagger cadence,
			# then wait for the last one's fuse before cooling down.
			if not _pending_fires.is_empty():
				_stagger_t -= delta
				if _stagger_t <= 0.0:
					_launch_next_missile()
					_stagger_t = launch_stagger
			elif _missiles_remaining <= 0:
				_phase = Phase.COOLDOWN
				_phase_t = 0.0
		Phase.COOLDOWN:
			_phase_t += delta
			if _phase_t >= cooldown_time:
				# Only start another salvo if still fully on-screen.
				if _is_fully_onscreen():
					_begin_mark()
				else:
					_phase = Phase.ENTERING


# ---- Attack cycle ----------------------------------------------------------

func _begin_mark() -> void:
	_did_first_salvo = true
	_phase = Phase.MARK
	_phase_t = 0.0
	_clear_telegraphs()
	var zones: Array = _pick_zone_points(zone_count)
	for zone_v in zones:
		var zone: Vector2 = zone_v
		var circle: Node2D = _TelegraphCircle.new()
		circle.setup(zone, aoe_radius)
		_world_parent().add_child(circle)
		# Store [node, zone] so FIRE can reuse the exact same point.
		_live_telegraphs.append({"node": circle, "zone": zone})


func _begin_fire() -> void:
	_phase = Phase.FIRE_WAIT
	_phase_t = 0.0
	_missiles_remaining = 0
	# Queue every zone for a STAGGERED launch (one missile per launch_stagger),
	# rather than spawning the whole salvo on one frame. The telegraph circles
	# keep pulsing until their missile launches + detonates.
	_pending_fires.clear()
	for entry in _live_telegraphs:
		var tdict: Dictionary = entry
		_pending_fires.append({"zone": tdict["zone"], "node": tdict["node"]})
	_stagger_t = 0.0  # fire the first immediately
	_live_telegraphs.clear()


# Launch the next queued missile from the next launch point in the walking
# sequence. Called on the stagger cadence from FIRE_WAIT.
func _launch_next_missile() -> void:
	if _pending_fires.is_empty():
		return
	var tdict: Dictionary = _pending_fires.pop_front()
	var zone: Vector2 = tdict["zone"]
	var circle: Node2D = tdict["node"]
	# Cycle the launch ORIGIN through LaunchPoint1..4 in sequence, one step per
	# missile, persisting the index across salvos so it keeps walking. Computed
	# at launch time so it tracks the cruiser's current (moving) position.
	var launch: Vector2 = _launch_point(_launch_idx)
	_launch_idx = (_launch_idx + 1) % LAUNCH_POINT_COUNT
	var missile: Node2D = _Missile.new()
	missile.setup(
		launch, zone, missile_travel_time, fuse_time,
		aoe_radius, explosion_damage, circle
	)
	_world_parent().add_child(missile)
	_missiles_remaining += 1
	# Each missile calls back when it detonates so we know the salvo is done.
	missile.detonated.connect(_on_missile_detonated)


func _on_missile_detonated() -> void:
	_missiles_remaining = maxi(0, _missiles_remaining - 1)


func _clear_telegraphs() -> void:
	for entry in _live_telegraphs:
		var tdict: Dictionary = entry
		var n: Node = tdict.get("node", null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_live_telegraphs.clear()


# Free telegraph circles for missiles that were queued but never launched
# (cruiser exited mid-salvo) so they don't pulse forever in the world.
func _clear_pending() -> void:
	for entry in _pending_fires:
		var tdict: Dictionary = entry
		var n: Node = tdict.get("node", null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_pending_fires.clear()


# Pick `count` random strike points in the gameplay band (X via Playfield, Y in
# the configured band) that do NOT overlap each other — every chosen point is at
# least `min_zone_separation` from all previously chosen points. Rejection
# sampling with a retry cap (ZONE_PICK_TRIES); if the cap is hit for a slot we
# accept the candidate that was best-spread (max min-distance to the accepted
# set) so we never loop forever and still maximize spacing. World coords.
func _pick_zone_points(count: int) -> Array:
	var points: Array = []
	var sep_sq: float = min_zone_separation * min_zone_separation
	for _i in range(count):
		var best: Vector2 = _rand_zone_point()
		var best_min_d: float = _min_dist_sq(best, points)
		# If the very first candidate already clears the separation, take it.
		if best_min_d >= sep_sq:
			points.append(best)
			continue
		# Otherwise re-roll up to the cap, keeping the best-spread candidate.
		for _try in range(ZONE_PICK_TRIES):
			var cand: Vector2 = _rand_zone_point()
			var cand_min_d: float = _min_dist_sq(cand, points)
			if cand_min_d >= sep_sq:
				best = cand
				best_min_d = cand_min_d
				break
			if cand_min_d > best_min_d:
				best = cand
				best_min_d = cand_min_d
		points.append(best)
	return points


# One uniformly random point in the gameplay band.
func _rand_zone_point() -> Vector2:
	var x: float = randf_range(Playfield.X_MIN, Playfield.X_MAX)
	var y: float = randf_range(zone_y_min, zone_y_max)
	return Vector2(x, y)


# Squared distance from `p` to the nearest point already in `pts` (INF if empty).
func _min_dist_sq(p: Vector2, pts: Array) -> float:
	var best: float = INF
	for q_v in pts:
		var q: Vector2 = q_v
		var d: float = p.distance_squared_to(q)
		if d < best:
			best = d
	return best


# Launch point for shot `idx` (0-based): the child Marker2D "LaunchPoint{idx+1}"
# (Roman added LaunchPoint1..4, 2026-05-31). Falls back to the legacy single
# "LaunchPoint" marker, then to the sprite centre (cruiser world position) when
# the indexed marker is missing — preserving the prior behavior on bare scenes.
# get_node_or_null is statically typed Node, so cast to Node2D explicitly;
# `:=` on the Variant RHS would be a parse_check-missed compile error.
func _launch_point(idx: int) -> Vector2:
	var marker: Node2D = get_node_or_null("LaunchPoint%d" % (idx + 1)) as Node2D
	if marker != null:
		return marker.global_position
	var legacy: Node2D = get_node_or_null("LaunchPoint") as Node2D
	if legacy != null:
		return legacy.global_position
	return global_position


# Soft radial gradient used as the missile's diffuse glow (built once, shared).
static var _glow_tex: GradientTexture2D = null

static func _ensure_glow_tex() -> void:
	if _glow_tex != null:
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 16
	t.height = 16
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_glow_tex = t


# Parent for world-space children (telegraphs/missiles). Prefer the live scene
# root so they survive the cruiser; fall back to the tree root.
func _world_parent() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return self
	var cs: Node = tree.current_scene
	if cs != null:
		return cs
	return tree.root


# ============================================================================
# Telegraph circle — pulsing 50%-transparent filled red disc in world space.
# ============================================================================
class _TelegraphCircle extends Node2D:
	var _radius: float = 24.0
	var _pulse_t: float = 0.0

	func setup(world_pos: Vector2, radius: float) -> void:
		global_position = world_pos
		_radius = radius

	func _process(delta: float) -> void:
		_pulse_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse: float = sin(_pulse_t * TAU * MissileCruiser.TELEGRAPH_PULSE_HZ)
		var r: float = _radius + pulse * MissileCruiser.TELEGRAPH_PULSE_PX
		var a: float = MissileCruiser.TELEGRAPH_COLOR.a * (0.7 + 0.3 * (0.5 + 0.5 * pulse))
		var col := Color(
			MissileCruiser.TELEGRAPH_COLOR.r,
			MissileCruiser.TELEGRAPH_COLOR.g,
			MissileCruiser.TELEGRAPH_COLOR.b,
			a
		)
		draw_circle(Vector2.ZERO, maxf(1.0, r), col)


# ============================================================================
# Missile — flies from launch to UNDER its zone point over travel_time
# (tether-mine fly-to-fixed-point), waits a fuse, then explodes: AoE damage to
# players in radius + ExplosionFx + clears its telegraph circle.
# ============================================================================
class _Missile extends Node2D:
	signal detonated

	# Bright-yellow tracer warhead. The core grows from 1px (just launched, far
	# back at the cruiser's mid-depth) to 2px as it "ascends" into the play area
	# toward its target zone — a cheap depth cue. Wrapped in a flickering diffuse
	# glow and trailed by the standard enemy ordnance smoke.
	const CORE_COLOR := Color(1.0, 0.96, 0.35, 1.0)
	const GLOW_COLOR := Color(1.0, 0.9, 0.45, 1.0)
	const CORE_W_LAUNCH: float = 1.0   # px at launch
	const CORE_W_ASCEND: float = 2.0   # px once ascending into the play area
	const CORE_LEN: float = 4.0        # streak length along heading
	const ASCEND_START: float = 0.18   # travel fraction at which the grow begins

	var _from: Vector2 = Vector2.ZERO
	var _to: Vector2 = Vector2.ZERO
	var _travel: float = 0.8
	var _fuse: float = 0.4
	var _radius: float = 24.0
	var _damage: int = 1
	var _telegraph: Node2D = null

	var _t: float = 0.0
	var _arrived: bool = false
	var _fuse_t: float = 0.0
	var _detonated: bool = false
	var _heading: float = 0.0
	var _trail: MissileSmokeTrail = null


	# setup() runs before we're in-tree (no get_tree() yet); build the trail here
	# in _ready(), by which point setup() has populated _from/_to for flip_drift.
	# Mirrors enemy_rocket.gd exactly: the SAME MissileSmokeTrail, world-parented
	# to the tree root and attached via call_deferred so it survives our
	# detonation and fades on its own.
	func _ready() -> void:
		var trail: MissileSmokeTrail = MissileSmokeTrail.new()
		trail.flip_drift = (_to.y > _from.y)  # downward missile → smoke lags upward
		get_tree().root.call_deferred("add_child", trail)
		trail.call_deferred("attach_to", self)
		_trail = trail

	func setup(
		from: Vector2, to: Vector2, travel: float, fuse: float,
		radius: float, damage: int, telegraph: Node2D
	) -> void:
		_from = from
		_to = to
		_travel = maxf(0.05, travel)
		_fuse = maxf(0.0, fuse)
		_radius = radius
		_damage = damage
		_telegraph = telegraph
		global_position = from
		_heading = (to - from).angle()

	func _process(delta: float) -> void:
		if _detonated:
			return
		if not _arrived:
			_t += delta
			var u: float = clampf(_t / _travel, 0.0, 1.0)
			# Ease-out so it decelerates into the zone (reads like a lobbed shot).
			var eased: float = 1.0 - pow(1.0 - u, 2.0)
			var prev: Vector2 = global_position
			global_position = _from.lerp(_to, eased)
			var step: Vector2 = global_position - prev
			if step.length_squared() > 0.0001:
				_heading = step.angle()
			queue_redraw()
			if u >= 1.0:
				_arrived = true
				_fuse_t = 0.0
		else:
			_fuse_t += delta
			queue_redraw()
			if _fuse_t >= _fuse:
				_detonate()

	func _detonate() -> void:
		if _detonated:
			return
		_detonated = true
		# AoE: damage any player within radius. take_damage auto-scales with
		# sectors + handles i-frames/shield.
		var tree: SceneTree = get_tree()
		if tree != null:
			var players: Array = tree.get_nodes_in_group("player")
			for p in players:
				if not (p is Node2D):
					continue
				var pn: Node2D = p as Node2D
				if pn.global_position.distance_to(_to) <= _radius:
					if pn.has_method("take_damage"):
						pn.take_damage(_damage)
		# VFX at the zone point.
		ExplosionFx.play(_to, 1.0)
		# Let the smoke trail dissipate on its own rather than vanishing with us.
		if _trail != null and is_instance_valid(_trail):
			_trail.attach_to(null)
			_trail = null
		# Clear this zone's telegraph circle.
		if _telegraph != null and is_instance_valid(_telegraph):
			_telegraph.queue_free()
		detonated.emit()
		queue_free()

	func _draw() -> void:
		if _detonated:
			return
		if not _arrived:
			# Core grows 1px → 2px once it starts ascending into the play area.
			var u: float = clampf(_t / _travel, 0.0, 1.0)
			var asc: float = clampf((u - ASCEND_START) / (1.0 - ASCEND_START), 0.0, 1.0)
			var core_w: float = lerpf(CORE_W_LAUNCH, CORE_W_ASCEND, asc)
			var dir := Vector2.RIGHT.rotated(_heading)
			# Flickering diffuse glow around the warhead (radial gradient).
			MissileCruiser._ensure_glow_tex()
			var flick: float = 0.65 + 0.35 * randf()
			var glow_half: float = (core_w + 1.5) * flick
			var gcol := Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.5 * flick)
			draw_texture_rect(
				MissileCruiser._glow_tex,
				Rect2(Vector2(-glow_half, -glow_half), Vector2(glow_half * 2.0, glow_half * 2.0)),
				false, gcol
			)
			# Bright-yellow core streak along the heading.
			draw_line(dir * (-CORE_LEN * 0.5), dir * (CORE_LEN * 0.5), CORE_COLOR, core_w)
		else:
			# Fuse: pulse a warning dot at the zone so the player reads "incoming".
			var pulse: float = 0.5 + 0.5 * sin(_fuse_t * 30.0)
			draw_circle(Vector2.ZERO, 2.0 + pulse * 1.5, Color(1.0, 0.9, 0.4, 0.9))
