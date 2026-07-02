extends "res://scripts/enemies/enemy_core.gd"
class_name EnemyFirecoreDrone

# Firecore Drone (Roman 2026-05-31; migrated to config 2026-06-19). Small + tough drone that CREEPS
# down (30 px/s) ringed by 1-4 concentric rings of orbiting bullet shells; killing it RELEASES every
# shell as a real bullet flying radially OUTWARD — expanding concentric waves the player must dodge.
# Odd rings render + release SMALL (mixed calibre).
#
# The orbit + release is the shared OrbitComponent (VISUAL mode) now, and the descent is a chassis
# creep-speed StraightDown — no bespoke ring/descent code. The director's ring_count_override is read
# here (it's set before add_child) to size the rings.

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const OrbitComponentC = preload("res://scripts/enemies/components/orbit_component.gd")
const BV_Basic = preload("res://data/bullets/basic.tres")

# Number of concentric rings (clamped 1-4). More rings = denser flower AND a bigger death release.
@export var ring_count: int = 2

# Ring shape (was the firecore_drone ring constants).
const RING_RADIUS_BASE := 14.0
const RING_RADIUS_STEP := 10.0
const RING_BULLET_BASE := 6
const RING_BULLET_STEP := 4
const RING_SPEED_BASE := 1.6        # rad/s of the innermost ring; outer rings scale by the falloff
const RING_SPEED_FALLOFF := 0.7     # and spin in the opposite direction (alternating per ring)
const SMALL_SCALE := 0.6            # odd rings render + release small (mixed calibre)
const RELEASE_SPEED := 140.0        # outward speed of released bullets (px/s)


func _ready() -> void:
	# Stats BEFORE super._ready() (the 1-HP-bug convention). auto_rotate off so the base doesn't spin
	# the Area2D and drag the orbit children.
	max_health = 10
	bounty_value = 25
	auto_rotate = false
	display_scale = 1.0
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	explosion_variant = "ball"
	# Creep descent by default, but never clobber a move_speed the bench/director handed us
	# (Roman 2026-07-02 speed-source pass — was an unconditional override).
	if move_speed <= 0.0:
		move_speed = Clarity.CREEP_SPEED   # 30 px/s creep descent (the clean half-rung)
	if movement == null:
		movement = StraightDown.new()
	# Orbiting bullet shells via the shared OrbitComponent (VISUAL) — set BEFORE super._ready so
	# enemy_core inits + ticks it; released as real bullets on death (on_death). ring_count is the
	# director's override (set before add_child), so it's already resolved here.
	ring_count = clampi(ring_count, 1, 4)
	var oc = OrbitComponentC.new()
	oc.mode = OrbitComponentC.Mode.VISUAL
	oc.release_speed = RELEASE_SPEED
	var rings: Array = []
	for r in ring_count:
		var small: bool = (r % 2 == 1)
		rings.append({
			"radius": RING_RADIUS_BASE + RING_RADIUS_STEP * float(r),
			"count": RING_BULLET_BASE + RING_BULLET_STEP * r,
			"speed": RING_SPEED_BASE * pow(RING_SPEED_FALLOFF, float(r)) * (-1.0 if small else 1.0),
			"variant": BV_Basic,
			"scale": SMALL_SCALE if small else 1.0,
		})
	oc.rings = rings
	components = [oc]
	super._ready()
