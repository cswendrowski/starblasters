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
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
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
# launch points fire in sequence (Launcher1 → 2 → 3 → 4) instead of all at
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
# Telegraph circles, the lobbed missiles, the non-overlapping zone picker, and the
# missile glow texture now live in the shared MissileSalvo component (used by the
# Shepherd boss's Phase 2 too). Referenced via its global class_name.

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
# across salvos so successive shots keep walking Launcher1 -> 2 -> 3 -> 4 ->
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
	# vel (0,-1)) -> 0 (nose up). Children (Glow, Body, Launcher) rotate with
	# the root; Launcher at local (0,0) stays at center so launch/targeting are
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
	var zones: Array = MissileSalvo.pick_zone_points(zone_count, zone_y_min, zone_y_max, min_zone_separation)
	for zone_v in zones:
		var zone: Vector2 = zone_v
		var circle: Node2D = MissileSalvo.TelegraphCircle.new()
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
	# Cycle the launch ORIGIN through Launcher1..4 in sequence, one step per
	# missile, persisting the index across salvos so it keeps walking. Computed
	# at launch time so it tracks the cruiser's current (moving) position.
	var launch: Vector2 = _launch_point(_launch_idx)
	_launch_idx = (_launch_idx + 1) % LAUNCH_POINT_COUNT
	var missile: Node2D = MissileSalvo.Missile.new()
	missile.setup(
		launch, zone, missile_travel_time, fuse_time,
		aoe_radius, explosion_damage, circle
	)
	_world_parent().add_child(missile)
	_missiles_remaining += 1
	# Universal missile launch sound (shared with the player's seeking missiles).
	WeaponSfx.play(get_tree().root, launch, "missile")
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


# Launch point for shot `idx` (0-based): the child Marker2D "Launcher{idx+1}"
# (Launcher1..4). Falls back to the legacy single
# "Launcher" marker, then to the sprite centre (cruiser world position) when
# the indexed marker is missing — preserving the prior behavior on bare scenes.
# get_node_or_null is statically typed Node, so cast to Node2D explicitly;
# `:=` on the Variant RHS would be a parse_check-missed compile error.
func _launch_point(idx: int) -> Vector2:
	var marker: Node2D = get_node_or_null("Launcher%d" % (idx + 1)) as Node2D
	if marker != null:
		return marker.global_position
	var legacy: Node2D = get_node_or_null("Launcher") as Node2D
	if legacy != null:
		return legacy.global_position
	return global_position


# Parent for world-space children (telegraphs/missiles). Prefer the live scene
# root so they survive the cruiser; fall back to the tree root.
func _world_parent() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return self
	var cs: Node = tree.current_scene
	# In a SubViewport bench the bullet_world layer wins, so telegraphs/missiles spawn into
	# the preview instead of the window corner; combat has no such node → current_scene/root.
	return BulletWorld.resolve(self, cs if cs != null else tree.root)
