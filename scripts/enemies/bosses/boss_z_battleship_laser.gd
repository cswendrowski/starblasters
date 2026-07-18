extends "res://scripts/enemies/bosses/boss_part.gd"

# A destructible LASER EMITTER for the Zealot Battleship (Roman 2026-07-01). Used by:
#   boss_z_battleship_sidelaser.tscn  ("side" — a thin 2 px beam raked BROADSIDE across the screen), and
#   boss_z_battleship_mainlaser.tscn  ("main" — a fixed, FULL-LANE white/#fbf236/#df7126 beam).
# A boss_part shell (destructible + shootable) with the laser's own glow-then-fire cycle:
#   - HULL frame strip is [0 normal, 1 destroyed, 2 glow]. The GLOW (ChargeMask on the glow frame) FADES
#     IN before firing — driven off the beam's charge_fraction() (WINDUP 0→1, FIRING full, else hidden),
#     HDR-bright like the firecores. A RED warning line also paints the beam's lane during windup.
#   - Progressive damage tells (boss_part.wants_damage_tells): overlay + spark trail from 50% HP.
#   - On death it STOPS firing, drops the damage overlay, swaps to the DAMAGED frame (1) (+ optional
#     flip so paired emitters differ), and stays as a HUSK (no free) so the wreck rides the hull. The MAIN
#     laser additionally ripples explosions + debris/embers along its length. It emits part_destroyed so
#     the boss drops it from live-parts + spawns the rearward torch/smoke wreck.
#
# SIDE beams aim LOCAL_FORWARD (broadside; follows the hull's rotation → "across the screen" on a pass).
# The MAIN beam is SEGMENT — the boss calls fire_lane_beam() to project a FIXED full-lane beam (it does
# NOT move with the boss), so a pass reads: warning → full-lane beam → vanish → THEN the boss arrives.

const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
const VfxGlow = preload("res://scripts/effects/vfx_glow_config.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")

const FRAME_NORMAL := 0
const FRAME_DESTROYED := 1
const FRAME_GLOW := 2

# Laser palette (shared with the boss): core WHITE, inner #fbf236, outer #df7126; red pre-fire warning.
const LASER_CORE := Color(1, 1, 1, 1)
const LASER_INNER := Color("fbf236")
const LASER_OUTER := Color("df7126")
const LASER_WARN := Color(1.0, 0.15, 0.15, 0.7)

@export var beam_kind: String = "side"       # "side" (2 px broadside) | "main" (fixed full-lane)
@export var part_hp: int = 64                 # Roman 2026-07-01: side lasers + turrets = 64 (main .tscn overrides)
@export var flip_when_destroyed: bool = false

# `boss_ref` is inherited from boss_part.gd (the FF exclusion owner is set via set_boss below).
var _hull: Sprite2D = null
var _charge_mask: Sprite2D = null
var _beam = null
var _glow: Color = Color(1, 1, 1, 1)


func _ready() -> void:
	wants_damage_tells = true      # BEFORE super._ready(): overlay + spark trail from 50% HP (boss_part)
	super._ready()                 # boss_part: joins "enemies" + installs the damage tells
	hp = part_hp
	max_hp = part_hp
	leave_trail = false            # the battleship spawns the rearward torch+smoke wreck itself
	_hull = get_node_or_null("Hull") as Sprite2D
	if _hull != null:
		_hull.frame = FRAME_NORMAL
	_charge_mask = get_node_or_null("ChargeMask") as Sprite2D
	if _charge_mask != null:
		_charge_mask.frame = FRAME_GLOW
		_glow = VfxGlow.prod_hdr("engines")   # firecore glow multiplier → blooms via the env
		_charge_mask.modulate = Color(_glow.r, _glow.g, _glow.b, 0.0)
		_charge_mask.visible = false
	_build_beam()


func _build_beam() -> void:
	_beam = BeamEmitterC.new()
	_beam.autostart = false
	_beam.target_group = "player"
	_beam.endpoint = BeamEmitterC.Endpoint.RAY
	_beam.aim_mode = BeamEmitterC.AimMode.LOCAL_FORWARD   # follows the emitter's world rotation
	# TWO warnings before it fires: the ship's GLOW fades in (below) AND the beam paints a red warning
	# line along its path during windup.
	_beam.telegraph_color = LASER_WARN
	_beam.telegraph_width = 2.0
	# Grow-in (thin white line → full width) then shrink + flicker out at the end (Roman 2026-07-02).
	_beam.envelope = true
	# Keep the authored firecore gold/orange gradient (this IS the reference laser); the generic faction
	# auto-tint would otherwise whiten it, since a neutral boss resolves to no faction (Roman 2026-07-07).
	_beam.faction = BeamEmitterC.FACTION_OFF
	_beam.sfx_profile = "boss"   # large blasts + power flutters + field loops 4/5 (Roman 2026-07-15)
	if beam_kind == "main":
		# Fire FROM the BeamStart marker TOWARD the BeamMuzzle marker (out the muzzle), on down the lane.
		# LOCAL_FORWARD + the marker-derived direction means it always points start→muzzle in world space,
		# whatever the hull's facing. Long reach so it spans the whole lane from the (static) muzzle.
		var start_m := get_node_or_null("BeamStart") as Node2D
		var muzzle_m := get_node_or_null("BeamMuzzle") as Node2D
		_beam.emitter_offset = start_m.position if start_m != null else Vector2.ZERO
		var fwd := Vector2(0, -1)
		if start_m != null and muzzle_m != null:
			var d: Vector2 = muzzle_m.position - start_m.position
			if d.length() > 0.01:
				fwd = d.normalized()
		_beam.forward_local = fwd
		_beam.cycle = BeamEmitterC.Cycle.ONCE
		_beam.idle_time = 0.1
		_beam.windup_time = 1.2                            # red lane warning + glow fade-in
		_beam.firing_time = 4.0
		_beam.cooldown_time = 0.6
		_beam.reach = 700.0                                # spans the lane from the muzzle
		_beam.dps = 2.5                                    # ticks constantly while firing
		_beam.hit_radius = 10.0
		_beam.layers = [
			{"width": 17.0, "color": LASER_OUTER},
			{"width": 14.0, "color": LASER_INNER},
			{"width": 12.0, "color": LASER_CORE},
		]
		# The main lane laser doesn't care about friendly fire (Roman 2026-07-01): it torches the
		# player AND enemies alike, EXCEPT the battleship's own parts (ignore_owner). pierce (default)
		# makes it span the whole lane, hitting everything in the beam.
		_beam.friendly_fire = true
		_beam.ignore_owner = get_parent()                  # the boss root; refined by set_boss() below
		smart_bomb_cap = 8                                 # main laser takes the LEAST smart-bomb damage
	else:
		# Fire FROM the emitter CENTRE toward the "Beam" marker — a thin broadside that rakes the screen.
		var beam_m := get_node_or_null("Beam") as Node2D
		_beam.emitter_offset = Vector2.ZERO                # from the laser's centre
		var sfwd := Vector2(0, 1)
		if beam_m != null and beam_m.position.length() > 0.01:
			sfwd = beam_m.position.normalized()
		_beam.forward_local = sfwd
		_beam.cycle = BeamEmitterC.Cycle.LOOP_WINDUP
		_beam.idle_time = 0.3
		_beam.windup_time = 1.0                            # glow fade-in + red warning
		_beam.firing_time = 2.0
		_beam.cooldown_time = 1.4
		_beam.reach = 540.0
		_beam.dps = 3.0
		_beam.hit_radius = 8.0                             # generous so "flown into" reliably damages
		_beam.layers = [
			{"width": 4.0, "color": Color(LASER_INNER.r, LASER_INNER.g, LASER_INNER.b, 0.55)},
			{"width": 2.0, "color": LASER_CORE},
		]
		smart_bomb_cap = 20
	add_child(_beam)


# Wire the owning boss (called from the boss's _collect_lasers). Sets the friendly-fire exclusion so
# the main lane laser never damages the battleship's own turrets/lasers.
func set_boss(b: Node) -> void:
	boss_ref = b
	if _beam != null and is_instance_valid(_beam) and b != null:
		_beam.ignore_owner = b


# SIDE lasers: begin / stop the broadside cycle. No-op once destroyed. (The MAIN laser uses set_active too.)
func set_active(on: bool) -> void:
	if _destroyed or _beam == null or not is_instance_valid(_beam):
		return
	if on:
		_beam.begin()
	else:
		_beam.fade_out()   # graceful shrink+flicker OUT (same in/out as the lane laser), not a hard cut


# The full warn→fire→vanish duration of ONE beam cycle — the boss waits this out (main laser) before it
# arrives, so the warning + beam + fade all play while the boss is still off-screen.
func beam_duration() -> float:
	if _beam == null or not is_instance_valid(_beam):
		return 0.0
	return _beam.idle_time + _beam.windup_time + _beam.firing_time + _beam.cooldown_time


# The windup (red-warning) portion of the cycle, so the sweep hazard holds the warning before it pans.
func beam_windup() -> float:
	if _beam == null or not is_instance_valid(_beam):
		return 1.2
	return _beam.idle_time + _beam.windup_time


func is_destroyed() -> bool:
	return _destroyed


# Drive the glow overlay's alpha off the beam's charge each frame (fades in before firing).
func _process(_delta: float) -> void:
	if _charge_mask == null:
		return
	if _destroyed or _beam == null or not is_instance_valid(_beam):
		if _charge_mask.visible:
			_charge_mask.visible = false
		return
	var f: float = _beam.charge_fraction()
	if f < 0.0:
		if _charge_mask.visible:
			_charge_mask.visible = false
		return
	_charge_mask.visible = true
	_charge_mask.modulate = Color(_glow.r, _glow.g, _glow.b, clampf(f, 0.0, 1.0) * _glow.a)


# Override boss_part.destroy(): a WRECKED HUSK (no free). Stop firing, drop the damage overlay so the
# DAMAGED frame reads clean, swap to it (+ optional flip), then explode (MAIN = a rippling cascade along
# its length; side = a single blast) and notify the boss.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if _beam != null and is_instance_valid(_beam):
		_beam.stop()
	if _charge_mask != null:
		_charge_mask.visible = false
	if _tells != null and is_instance_valid(_tells):
		_tells.quiet()
	if _hull != null:
		_hull.material = null                 # drop the damage shader — the damaged frame shows clean
		_hull.frame = FRAME_DESTROYED
		if flip_when_destroyed:
			_hull.flip_h = not _hull.flip_h
	if beam_kind == "main":
		_main_death_cascade()
	else:
		var tree := get_tree()
		var scene: Node = tree.current_scene if tree != null else null
		ExplosionFx.play(global_position, 0.9, false, scene, ExplosionFx.scene_for("small_circle"))
	part_destroyed.emit(self)   # boss drops it from live_parts + spawns the rearward wreck FX


# The main laser is a long spar — rip circle explosions along its length (staggered), each throwing
# debris + embers. Positions are captured up-front + the booms spawn via captured locals, so they still
# fire if the husk frees mid-cascade.
func _main_death_cascade() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var container: Node = tree.current_scene
	if container == null:
		container = get_parent()
	if container == null:
		return
	var EF = ExplosionFx
	var DE = ShipDebrisEmber
	const N := 9
	# Ripple along the ART's LONG axis (the up-facing mainlaser is a TALL 36×199 spar → local Y). Derive
	# it from the Hull frame so it stays aligned if the art is re-oriented; `along` is the local long axis,
	# `perp` the small jitter across it.
	var along := Vector2(1, 0)
	var perp := Vector2(0, 1)
	var half_len := 95.0
	if _hull != null and _hull.texture != null:
		var fw: float = _hull.texture.get_width() / float(maxi(1, _hull.hframes))
		var fh: float = _hull.texture.get_height() / float(maxi(1, _hull.vframes))
		if fh >= fw:
			along = Vector2(0, 1)
			perp = Vector2(1, 0)
			half_len = fh * 0.5
		else:
			half_len = fw * 0.5
	for i in N:
		var t: float = (float(i) / float(N - 1)) * 2.0 - 1.0   # -1..1 along the spar's long axis
		var wp: Vector2 = to_global(along * (t * half_len) + perp * randf_range(-5.0, 5.0))
		var boom := func() -> void:
			EF.play(wp, 1.0, true, container, EF.scene_for("default"))
			var ang: float = randf_range(0.15, PI - 0.15)
			DE.spawn(container, wp, {
				"velocity": Vector2(cos(ang), sin(ang)) * randf_range(60.0, 140.0),
				"spin": randf_range(-6.0, 6.0),
				"piece_scale": randf_range(0.8, 1.4),
			})
		var delay: float = float(i) * 0.08
		if delay <= 0.001:
			boom.call()
		else:
			tree.create_timer(delay, false).timeout.connect(boom)   # false = pause with the game
