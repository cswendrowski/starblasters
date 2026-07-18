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

# --- Boss / miniboss encounters ---
var _miniboss_pool: Array = []   # role="miniboss" prefabs
var _boss_pool: Array = []       # role="boss" prefabs
var _mini_at: int = 0            # wave index the miniboss interjects at (mid-level)
var _has_mini: bool = false
var _has_boss: bool = false
var _paused: bool = false        # encounter active → field spawns (prefabs AND rocks) held
var _encounter: Node = null      # the live miniboss/boss stronghold
var _bd_orig: float = -1.0       # stashed Backdrop.drift_speed for miniboss resume
var _bd_tw: Tween = null
var _music_raised: bool = false  # true while WE hold the combat music envelope up


func start(knobs: Dictionary = {}) -> void:
	wave_size = int(knobs.get("wave_size", wave_size))
	gap_factor = float(knobs.get("gap_factor", gap_factor))
	drift_mult = float(knobs.get("drift_mult", drift_mult))
	rock_interval_min = float(knobs.get("rock_interval_min", rock_interval_min))
	rock_interval_max = float(knobs.get("rock_interval_max", rock_interval_max))
	rock_first_delay = float(knobs.get("rock_first_delay", rock_first_delay))
	if knobs.get("wave_sequence", null) is Array and not (knobs["wave_sequence"] as Array).is_empty():
		wave_sequence = knobs["wave_sequence"]
	# Partition by role: only "normal" prefabs feed the classified wave rotation; miniboss/boss are pulled
	# out into their own pools (spawned as set-piece encounters) so they can't also appear as ambient chaff.
	var all_prefabs: Array = Strongholds.load_all()
	_miniboss_pool = all_prefabs.filter(func(p): return _role_of(p) == "miniboss")
	_boss_pool = all_prefabs.filter(func(p): return _role_of(p) == "boss")
	_buckets = _classify_all(all_prefabs.filter(func(p): return _role_of(p) == "normal"))
	_has_mini = not _miniboss_pool.is_empty()
	_has_boss = not _boss_pool.is_empty()
	_mini_at = int(wave_sequence.size() / 2)
	_wave_i = 0
	_wave_left = wave_size
	_rock_timer = rock_first_delay
	_rng.randomize()
	if _all_empty() and not _has_mini and not _has_boss:
		_done_prefabs = true   # nothing authored → just pepper rocks (which also stops, see below)
	# Player death mid-encounter must un-freeze the music envelope + drop the boss bar (teardown guard).
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_signal("died") and not pl.died.is_connected(_on_player_died):
		pl.died.connect(_on_player_died)
	set_process(true)


static func _role_of(p) -> String:
	return String((p as Dictionary).get("role", "normal")) if p is Dictionary else "normal"


func _process(delta: float) -> void:
	_tick_rocks(delta)
	_tick_prefabs()


# ---------------------------------------------------------------- prefab waves

func _tick_prefabs() -> void:
	if _paused:
		return   # an encounter is on-screen — hold ALL field spawns until it clears
	# Miniboss interjection at the mid slot (once).
	if _has_mini and _wave_i >= _mini_at:
		_has_mini = false
		var mp := _pick_pool(_miniboss_pool)
		if not mp.is_empty():
			_spawn_encounter(mp, "miniboss")
			return
	# Normal waves exhausted → the BOSS finale (once), then stop.
	if _wave_i >= wave_sequence.size():
		if _has_boss:
			_has_boss = false
			var bp := _pick_pool(_boss_pool)
			if not bp.is_empty():
				_spawn_encounter(bp, "boss")
		_done_prefabs = true
		return
	if _done_prefabs:
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


# ---------------------------------------------------------------- boss / miniboss encounters

func _pick_pool(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	return pool[_rng.randi() % pool.size()]


# Spawn a set-piece encounter (miniboss/boss) and immediately hold the field (a calm arrival beat). The
# parallax stop / music / health bar fire on the stronghold's locked_in signal (once it's fully in view).
func _spawn_encounter(prefab: Dictionary, role: String) -> void:
	if prefab.is_empty():
		return
	var size: float = float((prefab.get("asteroid", {}) as Dictionary).get("size", 120.0))
	var x: float = clampf(Playfield.CENTER.x + _rng.randf_range(-30.0, 30.0),
		Playfield.X_MIN + 18.0, Playfield.X_MAX - 18.0)
	var s := StrongholdScene.instantiate()
	s.position = Vector2(x, -size)   # drifts in at its AUTHORED speed (no drift_mult — deliberate arrival)
	add_child(s)
	s.configure(prefab)
	_encounter = s
	_last_prefab = s
	_last_size = size
	_paused = true   # hold the field the instant the base arrives
	if s.has_signal("locked_in"):
		s.locked_in.connect(_on_encounter_locked.bind(s, role))
	if s.has_signal("health_changed"):
		s.health_changed.connect(_on_encounter_hp)
	if s.has_signal("cleared"):
		s.cleared.connect(_on_encounter_cleared.bind(s, role))


func _on_encounter_locked(s: Node, role: String) -> void:
	_stop_parallax()
	_music_up()
	_show_bar(s)
	if role == "boss":
		# Hand the boss to the director as the wave gate: it excludes the base + buildings from slot math
		# and fires level_cleared once is_defeated() flips (all structures dead) + the field drains → outro.
		var m := _main()
		if m != null and "wave_director" in m and m.wave_director != null:
			m.wave_director.boss_gate = s


func _on_encounter_hp(cur: int, mx: int) -> void:
	var m := _main()
	if m == null:
		return
	if "boss_hp_bar" in m and m.boss_hp_bar != null:
		m.boss_hp_bar.max_value = maxi(1, mx)
		m.boss_hp_bar.value = cur


func _on_encounter_cleared(s: Node, role: String) -> void:
	_hide_bar()
	_music_down()
	if s != null and is_instance_valid(s) and s.has_method("release_drift"):
		s.release_drift()   # the cleared base drifts off
	_encounter = null
	# Ease the parallax back into motion for BOTH roles — the calm "hold on the base" is over, so the
	# field scrolls onward as it winds down (the ship flies out past the wreckage). This is independent of
	# _paused, which gates SPAWNS: the miniboss un-pauses (its waves resume); the BOSS stays paused so no
	# new rocks appear and the existing hazards can drain → director level_cleared → outro (player exits).
	_resume_parallax()
	if role == "miniboss":
		_paused = false      # field resumes its wave sequence


func _on_player_died() -> void:
	# Death mid-encounter must un-freeze the music envelope + drop the boss bar (else they leak).
	if _music_raised:
		_music_down()
	_hide_bar()


func _exit_tree() -> void:
	if _music_raised:
		var mm = get_node_or_null("/root/Music")
		if mm != null:
			if mm.has_method("set_intensity"):
				mm.set_intensity(0, 0.4)
			if mm.has_method("set_walk_frozen"):
				mm.set_walk_frozen(false)
		_music_raised = false


func _main() -> Node:
	return get_parent()   # StrongholdField is add_child'd to the main scene (main.gd _run_intro)


func _backdrop() -> Node:
	var m := _main()
	return m.get_node_or_null("Backdrop") if m != null else null


func _stop_parallax() -> void:
	var bd := _backdrop()
	if bd == null or not ("drift_speed" in bd):
		return
	if _bd_orig < 0.0:
		_bd_orig = float(bd.drift_speed)
	if _bd_tw != null and _bd_tw.is_valid():
		_bd_tw.kill()
	_bd_tw = create_tween()
	_bd_tw.tween_property(bd, "drift_speed", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _resume_parallax() -> void:
	var bd := _backdrop()
	if bd == null or not ("drift_speed" in bd) or _bd_orig < 0.0:
		return
	if _bd_tw != null and _bd_tw.is_valid():
		_bd_tw.kill()
	_bd_tw = create_tween()
	_bd_tw.tween_property(bd, "drift_speed", _bd_orig, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_bd_orig = -1.0


func _music_up() -> void:
	var m = get_node_or_null("/root/Music")
	if m == null:
		return
	if m.has_method("set_walk_frozen"):
		m.set_walk_frozen(true)   # stop the live combat envelope from stomping the intensity we set
	if m.has_method("set_intensity"):
		m.set_intensity(2, 2.0)   # ease to full over 2s (same track — "naturally")
	_music_raised = true


func _music_down() -> void:
	var m = get_node_or_null("/root/Music")
	_music_raised = false
	if m == null:
		return
	if m.has_method("set_intensity"):
		m.set_intensity(0, 2.5)
	if m.has_method("set_walk_frozen"):
		m.set_walk_frozen(false)   # hand the envelope back to live combat


func _show_bar(s: Node) -> void:
	var m := _main()
	if m == null:
		return
	var mx: int = int(s.max_hp()) if s.has_method("max_hp") else 1
	if "boss_hp_bar" in m and m.boss_hp_bar != null:
		m.boss_hp_bar.max_value = maxi(1, mx)
		m.boss_hp_bar.value = mx
		m.boss_hp_bar.visible = true
	if "boss_label" in m and m.boss_label != null:
		m.boss_label.text = ("STRONGHOLD" if (s.has_method("role") and s.role() == "boss") else "OUTPOST")
		m.boss_label.visible = true


func _hide_bar() -> void:
	var m := _main()
	if m == null:
		return
	if "boss_hp_bar" in m and m.boss_hp_bar != null:
		m.boss_hp_bar.visible = false
	if "boss_label" in m and m.boss_label != null:
		m.boss_label.visible = false


# ---------------------------------------------------------------- peppered asteroids

func _tick_rocks(delta: float) -> void:
	if _paused:
		return   # encounter on-screen (incl. the boss finale) — no new rocks so hazards can drain
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
