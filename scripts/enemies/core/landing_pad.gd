extends "res://scripts/enemies/core/enemy_core_building_turret.gd"

# Landing Pad (Roman 2026-07-14): a drifting ground structure with a RANDOM small faction enemy parked
# on it. The parked ship is IDLE — no movement, no firing, engines/shields off — but a fully LIVE enemy:
# it can be shot and killed with its own health + bounty. If the pad drifts off the BOTTOM of the screen
# with the ship still alive (not destroyed), the ship is handed to the director (inject_live_enemy) so it
# recycles into a later wave.

const RosterC = preload("res://scripts/levels/enemy_roster.gd")
const Factions = preload("res://scripts/levels/factions.gd")

var _parked: Node = null
var _released: bool = false


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
		e.max_health = maxi(1, int(stats.get("hp", 4)))
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


# A random SMALL chaff enemy of the level's faction. entries_eligible is faction-filtered + skips no_wave,
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
	var pool: Array = []
	for tier in [RosterC.Tier.COMMON, RosterC.Tier.UNCOMMON]:
		for e in RosterC.entries_eligible(tier, sector, 9):
			if String(e.get("size", "")) != "small" or not bool(e.get("chaff", false)):
				continue
			if not Factions.allowed_in(String(e.get("scene", "")), faction):
				continue
			pool.append(e)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


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
		dir.inject_live_enemy(p)
