extends "res://scripts/enemies/core/enemy_core_building_turret.gd"

# Landing Pad (Roman 2026-07-14): a drifting ground structure with a RANDOM small faction enemy parked
# on it. The parked ship is IDLE — no movement, no firing, engines/shields off — but a fully LIVE enemy:
# it can be shot and killed with its own health + bounty. If the pad drifts off the BOTTOM of the screen
# with the ship still alive (not destroyed), the ship is handed to the director (inject_live_enemy) so it
# recycles into a later wave.
#
# ESCAPE LAUNCH (Roman 2026-07-17): 20% of OCCUPIED pads scramble their ship mid-descent — the engine
# glow fades in (power-up), it lifts off the pad onto the actor plane, flies up off the TOP of the
# screen, and re-enters as part of the NEXT wave (a director recycle CREDIT — the same conducted
# re-entry a missed recycler gets, so it returns inside the choreography, not as a straggler).

const Factions = preload("res://scripts/levels/factions.gd")
const EngineGlowC = preload("res://scripts/effects/engine_glow.gd")
const WaveGenC = preload("res://scripts/levels/wave_generator.gd")
# RosterC / BulletWorldC are inherited from enemy_core_building_turret.gd (the parent) — do not redeclare.

const LAUNCH_CHANCE := 0.20

var _parked: Node = null
var _parked_entry: Dictionary = {}
var _released: bool = false
var _launch_at_y: float = -1.0   # global y that triggers the escape launch; -1 = this pad never launches
var _launching: bool = false


func _ready() -> void:
	super._ready()
	call_deferred("_spawn_parked")


func _spawn_parked() -> void:
	# 20% of pads arrive empty (Roman 2026-07-14).
	if randf() < 0.20:
		return
	var entry: Dictionary = _pick_parked_entry()
	if entry.is_empty():
		return
	var scn: PackedScene = load(String(entry["scene"]))
	if scn == null:
		return
	var e = scn.instantiate()
	# Live health from the roster (instantiated directly, so the director's size-scaling doesn't run).
	var stats: Dictionary = RosterC.compose_stats(entry)
	if "max_health" in e:
		e.max_health = maxi(1, int(stats.get("max_health", 4)))
	add_child(e)
	if e is Node2D:
		(e as Node2D).position = Vector2(0, -3)   # sit on the pad
	# IDLE: freeze its own ticks so it neither moves nor fires — it just rides the pad. Still shootable +
	# killable (take_hit is an area signal, not _process). Engines are already off (engine_trail_enabled).
	e.set_process(false)
	e.set_physics_process(false)
	if "engine_trail_enabled" in e:
		e.engine_trail_enabled = false
	# Killed WHILE parked → a DIRECT explosion, not the flying-ship spin-out/wreck (death_cheap routes
	# enemy_base to the classic instant blast). Cleared on release so a recycled ship dies normally.
	e.set_meta("death_cheap", true)
	_parked = e
	_parked_entry = entry
	# Escape-launch roll: trigger somewhere in the upper-middle band so the whole power-up + lift-off +
	# top exit plays on screen during the pad's descent.
	if randf() < LAUNCH_CHANCE:
		_launch_at_y = randf_range(60.0, 150.0)


# The size class this pad parks — from the scene filename (building_landing_pad_<size>.tscn, size split
# 2026-07-17). Small pads park small chaff; medium/large pads park medium/large ships (any role, and
# large includes RAREs/capitals — the marquee "guarded capital on the ground" moment).
func _parked_size() -> String:
	var f := scene_file_path.get_file()
	if f.contains("_large"):
		return "large"
	if f.contains("_medium"):
		return "medium"
	return "small"


# A random faction enemy of THIS pad's size class. entries_eligible is faction-filtered + skips no_wave,
# so it never parks another ground structure. Empty when nothing qualifies.
func _pick_parked_entry() -> Dictionary:
	var run = get_node_or_null("/root/Run")
	var sector: int = 1
	if run != null and "sectors_cleared" in run:
		sector = int(run.sectors_cleared) + 1
	var faction: int = -1
	if run != null and run.has_meta("active_faction"):
		faction = int(run.get_meta("active_faction", -1))
	# ONLY the level's faction (Roman 2026-07-14). No active faction known → leave the pad EMPTY rather
	# than risk parking a wrong-faction ship. (entries_eligible only faction-filters via the scoped roster
	# filter, which a no_wave stronghold/condition spawn doesn't set — so we gate on active_faction here.)
	if faction < 0:
		return {}
	var want_size := _parked_size()
	# Small pads keep the original chaff-only pool. Bigger sizes drop the chaff gate (mediums/larges are
	# mostly non-chaff) and also draw from RARE — capitals can turn up parked, and some factions keep ALL
	# their mediums in RARE (corporate's Widow), so without it their medium pads would always be vacant.
	var tiers: Array = [RosterC.Tier.COMMON, RosterC.Tier.UNCOMMON]
	if want_size != "small":
		tiers.append(RosterC.Tier.RARE)
	var pool: Array = []
	for tier in tiers:
		for e in RosterC.entries_eligible(tier, sector, 9):
			if String(e.get("size", "")) != want_size:
				continue
			if want_size == "small" and not bool(e.get("chaff", false)):
				continue
			if not Factions.allowed_in(String(e.get("scene", "")), faction):
				continue
			pool.append(e)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


# While a ship is parked, IT soaks the damage — the pad can only be hurt once the ship is gone (dead,
# released, or launched). Bullets that overlap the ship directly already hit it; this routes the ones
# that land on the PAD's own hitbox, so an occupied pad never dies out from under its ship.
func take_hit(damage: int = 1) -> bool:
	var p = _parked
	if p != null and is_instance_valid(p) and not ("_dying" in p and p._dying) and p.has_method("take_hit"):
		return p.take_hit(damage)
	return super.take_hit(damage)


# Escape-launch trigger: once the pad has descended into the rolled band with the ship still alive.
func _process(delta: float) -> void:
	super._process(delta)
	if _launching or _launch_at_y < 0.0:
		return
	if _parked == null or not is_instance_valid(_parked) or ("_dying" in _parked and _parked._dying):
		_launch_at_y = -1.0   # ship shot down while parked — nothing left to launch
		return
	if global_position.y >= _launch_at_y:
		_launching = true
		_launch()


# Escape launch: power up (engine glow fade-in at the ship's Engine* markers), lift off the pad onto the
# actor plane, fly up off the TOP, then hand the director a recycle CREDIT so the ship re-enters as part
# of the next wave. The flight is OUR tween — the ship's own ticks stay frozen — and every post-exit
# callback is bound to the SHIP or DIRECTOR, never the pad: the pad usually drifts off + frees mid-flight.
func _launch() -> void:
	var p = _parked
	_parked = null
	_released = true   # the bottom-exit release path is now a no-op for this pad
	if p == null or not is_instance_valid(p):
		return
	# POWER UP — glows fade in while the ship still sits on the pad. z 0 RELATIVE (not the scene's
	# authored -2 hull-tuck, which under the GROUND_Z pad would land below the rock and hide): at 0 they
	# draw with the ship's subtree, which tree-orders above the pad while grounded.
	var glow_pos: Array = []
	for m in p.find_children("Engine*", "Marker2D", true, false):
		glow_pos.append(p.to_local((m as Node2D).global_position))
	if glow_pos.is_empty():
		glow_pos.append(Vector2(0, 7))   # no Engine marker — plume off the tail
	for gp in glow_pos:
		var g = EngineGlowC.spawn(p, gp, 0.0)
		g.z_index = 0
		g.modulate.a = 0.0
		var gt: Tween = g.create_tween()   # owned by the glow — dies with the ship
		gt.tween_property(g, "modulate:a", 1.0, 0.55)
	await get_tree().create_timer(0.7).timeout   # power-up beat (a destroyed PAD husks, it isn't freed —
	if not is_instance_valid(p) or ("_dying" in p and p._dying):   # only the SHIP dying aborts here)
		return
	# LIFT OFF — onto the actor plane (world parent, z 0) so it sorts over the ground like any flying
	# ship; the pad keeps drifting away beneath it. Routed through BulletWorld so the bench stays correct.
	var world: Node = BulletWorldC.spawn_root(get_tree(), get_tree().current_scene)
	if world == null or not is_instance_valid(world):
		return
	p.reparent(world, true)
	if p.has_meta("death_cheap"):
		p.remove_meta("death_cheap")   # airborne — a mid-flight kill dies styled like a normal ship
	# Track it as a live combatant while it climbs (kill/bounty accounting, same as the bottom-exit
	# release). Its ticks stay FROZEN so the tween owns the motion (no pattern fighting the ascent).
	var dir := get_tree().get_first_node_in_group("wave_director")
	if dir != null and is_instance_valid(dir) and dir.has_method("inject_live_enemy"):
		dir.inject_live_enemy(p)
	var fly: Tween = p.create_tween()   # owned by the ship — a mid-flight kill just cancels the exit
	fly.tween_property(p, "global_position:y", p.global_position.y - 10.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fly.tween_property(p, "global_position:y", -60.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# NEXT WAVE — at the top: despawn + credit. The director re-spawns the same unit as a CONDUCTED row
	# at the next wave boundary (passes 0 = one re-entry; a later miss leaves for good). Both callbacks
	# are pad-independent; if the level is tearing down, the whole tree (ship + tween) dies together.
	var spec: Resource = _mk_release_spec()
	if dir != null and is_instance_valid(dir) and spec != null and dir.has_method("credit_recycled"):
		fly.tween_callback(Callable(dir, "credit_recycled").bind(spec, 0))
	fly.tween_callback(p.queue_free)


# A faithful WaveSpec for the parked entry — WaveGen's own factory (roster stats/mounts/movement stamp),
# so the credited replacement re-arms exactly like a produced wave unit. Used by the escape-launch
# credit AND stashed on the bottom-exit release so ITS later fly-back can credit properly too
# (RecycleController frees a spec-less enemy with a warning instead of re-entering it).
func _mk_release_spec() -> Resource:
	if _parked_entry.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var run = get_node_or_null("/root/Run")
	var sector: int = 1
	if run != null and "sectors_cleared" in run:
		sector = int(run.sectors_cleared) + 1
	return WaveGenC._make_wave_spec(rng, _parked_entry, sector, 0, 0)


# The pad drifted off the bottom ALIVE (recycle_passes=0 routes it to _leave). Recycle the parked ship
# into a later wave — but only if it wasn't shot down.
func _on_offscreen() -> void:
	_release_parked()
	super._on_offscreen()


func _release_parked() -> void:
	if _released:
		return
	_released = true
	var p = _parked
	_parked = null
	if p == null or not is_instance_valid(p) or ("_dying" in p and p._dying):
		return
	# Detach to the world, re-arm it as a normal descending enemy, and inject it live so the director
	# tracks + recycles it (its own off-screen check then flies it back for a later wave).
	var world := get_parent()
	if world != null and is_instance_valid(world):
		p.reparent(world, true)
	p.set_process(true)
	p.set_physics_process(true)
	if p.has_meta("death_cheap"):
		p.remove_meta("death_cheap")   # released → flies + dies like a normal enemy (styled) again
	if p.has_method("start"):
		p.start(p.global_position)   # arm its movement/firing from where it sits
	var dir := get_tree().get_first_node_in_group("wave_director")
	if dir != null and is_instance_valid(dir) and dir.has_method("inject_live_enemy"):
		# Spec attached (2026-07-17): the released ship's later fly-back hands the director this spec as
		# its recycle credit — without it RecycleController frees the ship with a warning, so the
		# documented "recycles into a later wave" silently never happened.
		dir.inject_live_enemy(p, _mk_release_spec())
