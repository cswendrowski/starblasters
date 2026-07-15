extends Node2D

# Asteroid Stronghold field controller (Roman 2026-07-13; wave-structured pass same day).
# The reframed asteroid_field's GROUND content: a base-assault progression of drifting stronghold
# prefab-asteroids in escalating themed WAVES, with loose asteroids peppered around them. The wave
# director runs a (lightened) faction SHIP overlay on top.
#
# Progression (fly INTO the base, then back OUT): outer light-turret pickets → heavy turrets →
# turrets + non-combat structures → core base → …and back out. Each wave = `wave_size` prefabs (6-12)
# of one category; categories are classified from each prefab's building content (see _classify).
# Prefabs spawn with VERTICAL CLEARANCE (gated on the last one descending) so big rocks don't wall up.
#
# FINITE (the sequence ends, then rocks stop) so the director's level_cleared can fire once everything
# drifts off — the "enemies" group (rocks + stronghold buildings) must be able to drain. Tunable via
# start(knobs) / Run meta "stronghold_field_knobs".

const StrongholdScene := preload("res://scenes/enemies/asteroid_stronghold.tscn")
const RockScene := preload("res://scenes/enemies/enemy_asteroid.tscn")
const Strongholds := preload("res://scripts/levels/asteroid_strongholds.gd")

# Base-assault order: pickets inward to the core, then back out. (Tunable via knobs.)
var wave_sequence: Array = ["light", "heavy", "mixed", "core", "mixed", "heavy", "light"]
var wave_size: int = 6                 # prefabs per wave (Roman: 6-12)
var gap_factor: float = 1.3            # next prefab waits until the last has descended size × (this-1)
var drift_mult: float = 1.25           # ×authored prefab drift — faster so big rocks clear sooner and
                                       # the whole field fits ~the 3-min ship schedule (so the SHIP +
                                       # asteroid budget covers every wave, not just the first half)
# Peppered loose asteroids — continuous while the assault runs, independent of the prefab waves.
var rock_interval_min: float = 2.5
var rock_interval_max: float = 5.0
var rock_first_delay: float = 1.5

var _buckets: Dictionary = {}          # category -> Array[prefab dict]
var _wave_i: int = 0
var _wave_left: int = 0
var _last_prefab: Node = null
var _last_size: float = 120.0
var _rock_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _done_prefabs: bool = false


func start(knobs: Dictionary = {}) -> void:
	wave_size = int(knobs.get("wave_size", wave_size))
	gap_factor = float(knobs.get("gap_factor", gap_factor))
	drift_mult = float(knobs.get("drift_mult", drift_mult))
	rock_interval_min = float(knobs.get("rock_interval_min", rock_interval_min))
	rock_interval_max = float(knobs.get("rock_interval_max", rock_interval_max))
	rock_first_delay = float(knobs.get("rock_first_delay", rock_first_delay))
	if knobs.get("wave_sequence", null) is Array and not (knobs["wave_sequence"] as Array).is_empty():
		wave_sequence = knobs["wave_sequence"]
	_buckets = _classify_all(Strongholds.load_all())
	_wave_i = 0
	_wave_left = wave_size
	_rock_timer = rock_first_delay
	_rng.randomize()
	if _all_empty():
		_done_prefabs = true   # no prefabs authored → just pepper rocks (which also stops, see below)
	set_process(true)


func _process(delta: float) -> void:
	_tick_rocks(delta)
	_tick_prefabs()


# ---------------------------------------------------------------- prefab waves

func _tick_prefabs() -> void:
	if _done_prefabs:
		return
	if _wave_i >= wave_sequence.size():
		_done_prefabs = true
		return
	# Vertical clearance: don't spawn the next prefab until the last has descended far enough that
	# they don't stack into an impassable wall (scaled by the last prefab's size).
	if _last_prefab != null and is_instance_valid(_last_prefab):
		if _last_prefab.position.y < _last_size * (gap_factor - 1.0):
			return
	var cat := String(wave_sequence[_wave_i])
	var prefab := _pick(cat)
	if prefab.is_empty():
		_advance_wave()   # no prefabs of this category authored — skip the wave, don't stall
		return
	_spawn_stronghold(prefab)
	_wave_left -= 1
	if _wave_left <= 0:
		_advance_wave()


func _advance_wave() -> void:
	_wave_i += 1
	_wave_left = wave_size
	if _wave_i >= wave_sequence.size():
		_done_prefabs = true


func _spawn_stronghold(prefab: Dictionary) -> void:
	var size: float = float((prefab.get("asteroid", {}) as Dictionary).get("size", 120.0))
	var x: float = clampf(Playfield.CENTER.x + _rng.randf_range(-45.0, 45.0),
		Playfield.X_MIN + 18.0, Playfield.X_MAX - 18.0)
	var s := StrongholdScene.instantiate()
	s.position = Vector2(x, -size)   # fully above the top so it drifts in
	add_child(s)
	s.configure(prefab)              # AFTER add_child (builds rock+buildings, binds shadow rig)
	if "drift_speed" in s:
		s.drift_speed *= drift_mult  # faster clear so the field fits ~the ship schedule (tunable)
	_last_prefab = s
	_last_size = size


# ---------------------------------------------------------------- peppered asteroids

func _tick_rocks(delta: float) -> void:
	# Pepper asteroids through the WHOLE assault, including the drain tail (last prefabs still drifting),
	# so loose rocks appear in the FINAL waves too — not just while prefabs dispatch. Stops only once
	# every wave is dispatched AND no stronghold is left on screen, so the field can still drain + clear.
	if _done_prefabs and not _has_live_strongholds():
		return
	_rock_timer -= delta
	if _rock_timer > 0.0:
		return
	_rock_timer = _rng.randf_range(rock_interval_min, rock_interval_max)
	_spawn_rock()


func _spawn_rock() -> void:
	var x: float = _rng.randf_range(Playfield.X_MIN + 12.0, Playfield.X_MAX - 12.0)
	var pos := Vector2(x, -_rng.randf_range(40.0, 90.0))
	var r := RockScene.instantiate()
	add_child(r)
	if r.has_method("start"):
		r.start(pos)
	elif r is Node2D:
		(r as Node2D).position = pos


# ---------------------------------------------------------------- classification

func _classify_all(prefabs: Array) -> Dictionary:
	var out := {"light": [], "heavy": [], "mixed": [], "core": []}
	for p in prefabs:
		if p is Dictionary:
			var c := _classify(p)
			if not out.has(c):
				out[c] = []
			out[c].append(p)
	return out


# Category from building content + rock size (drives the wave progression):
#   core  = big base — size >= 200 with >= 5 buildings,
#   heavy = launcher(s) or >= 4 turrets,
#   mixed = has non-combat structures (with or without turrets),
#   light = only a few small turrets.
func _classify(p: Dictionary) -> String:
	var turrets := 0
	var launchers := 0
	var noncombat := 0
	for b in p.get("buildings", []):
		if not (b is Dictionary):
			continue
		var t := String(b.get("type", ""))
		# Classify by key substring so NEW ground buildings + variants (e.g. "square_turret_wave") bucket
		# correctly without a hand-kept list.
		if "launcher" in t:
			launchers += 1
		elif "turret" in t:
			turrets += 1
		else:
			noncombat += 1
	var total := turrets + launchers + noncombat
	var size: float = float((p.get("asteroid", {}) as Dictionary).get("size", 120.0))
	if size >= 200.0 and total >= 5:
		return "core"
	if launchers >= 1 or turrets >= 4:
		return "heavy"
	if noncombat >= 1:
		return "mixed"
	return "light"


func _pick(cat: String) -> Dictionary:
	var bucket: Array = _buckets.get(cat, [])
	if bucket.is_empty():
		return {}
	return bucket[_rng.randi() % bucket.size()]


func _all_empty() -> bool:
	for k in _buckets:
		if not (_buckets[k] as Array).is_empty():
			return false
	return true


# Any stronghold still on screen? (Children with a "Buildings" holder are strongholds, not loose rocks.)
func _has_live_strongholds() -> bool:
	for c in get_children():
		if is_instance_valid(c) and c.get_node_or_null("Buildings") != null:
			return true
	return false
