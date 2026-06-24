extends Node

# Runtime LevelDef factory. Avoids .tres serialization quirks for typed
# Array[Resource] while we iterate on level design.

const WaveSpec = preload("res://scripts/levels/wave_def.gd")
const LevelData = preload("res://scripts/levels/level_def.gd")
const AuthoredPatterns = preload("res://scripts/levels/authored_patterns.gd")
const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const Loiter = preload("res://scripts/enemies/patterns/loiter.gd")
# Weapons 3b (2026-06-13): hazard shoot helpers build the unified Weapon (was the legacy
# SingleShot/SpreadShot/AimedShot/BurstShot classes).
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")
const CrystalScene = preload("res://scenes/enemies/factions/corporate/enemy_c_m_widow.tscn")
const DartScene = preload("res://scenes/enemies/core/enemy_core_s_dart.tscn")
const BossScene = preload("res://scenes/enemies/bosses/boss.tscn")
const BossSweep = preload("res://scripts/enemies/patterns/boss_sweep.gd")
const MineScene = preload("res://scenes/enemies/enemy_mine.tscn")
const BombletScene = preload("res://scenes/enemies/enemy_bomblet.tscn")
const MineShieldScene = preload("res://scenes/enemies/enemy_mine_shield.tscn")
const MineGravityScene = preload("res://scenes/enemies/enemy_mine_gravity.tscn")  # replaces Cluster + Mega Cluster
const MineSmartScene = preload("res://scenes/enemies/enemy_mine_smart.tscn")
const MineArmoredScene = preload("res://scenes/enemies/enemy_mine_armored.tscn")  # 4 HP
const MineTetherScene = preload("res://scenes/enemies/enemy_mine_tether.tscn")  # non-boss tether, 4 HP
const AsteroidScene = preload("res://scenes/enemies/enemy_asteroid.tscn")
const FrigateScene = preload("res://scenes/enemies/factions/supremacy/enemy_frigate.tscn")
const SkirmisherScene = preload("res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn")  # [RETIRED: enemy_skirmisher] corp gunner substitute
const MinelayerScene = preload("res://scenes/enemies/core/enemy_core_m_minelayer.tscn")
const InterceptorScene = preload("res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn")
const HunterDroneScene = preload("res://scenes/enemies/core/enemy_core_s_flechette.tscn")  # [RETIRED: enemy_hunter_drone] small core unit substitute
const BulwarkScene = preload("res://scenes/enemies/factions/corporate/enemy_c_l_bulwark.tscn")
const FirecoreDroneScene = preload("res://scenes/enemies/factions/zealot/enemy_z_s_bloom.tscn")
# Beam enemies (M6a.2 beam showcase).
const BeamerScene = preload("res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn")
const BeamerTrackerScene = preload("res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn")
const BeamerLockScene = preload("res://scenes/enemies/factions/zealot/enemy_beamer_lock.tscn")
const BurnerScene = preload("res://scenes/enemies/factions/zealot/enemy_burner.tscn")
const CruiserScene = preload("res://scenes/enemies/core/enemy_cruiser.tscn")
# Roster-Test dev node builds its movement via EnemyRoster.make_movement (shape keys), so the
# bespoke side_traverse/slow_advance/top_dive/side_cut/advance_retreat/beeline/bulwark_drift
# pattern consts that used to live here are gone (locomotion cleanup 2026-06-20).

static func _single() -> Resource:
	var sp = Weapon.new()
	sp.fire_pattern = Weapon.FirePattern.SINGLE
	sp.aim = Weapon.Aim.STRAIGHT_DOWN
	sp.bullet_scene = EnemyBullet
	return sp

static func _spread(count: int, degrees: float) -> Resource:
	var sp = Weapon.new()
	sp.fire_pattern = Weapon.FirePattern.SPREAD
	sp.aim = Weapon.Aim.STRAIGHT_DOWN
	sp.bullet_scene = EnemyBullet
	sp.spread_count = count
	sp.spread_degrees = degrees
	return sp

static func _aimed() -> Resource:
	var sp = Weapon.new()
	sp.fire_pattern = Weapon.FirePattern.AIMED
	sp.aim = Weapon.Aim.AT_PLAYER
	sp.bullet_scene = EnemyBullet
	return sp

static func _burst(count: int, interval: float) -> Resource:
	var sp = Weapon.new()
	sp.fire_pattern = Weapon.FirePattern.BURST
	sp.aim = Weapon.Aim.STRAIGHT_DOWN
	sp.bullet_scene = EnemyBullet
	sp.burst_count = count
	sp.burst_interval = interval
	return sp


# --- Hazard score helpers (lane-native, phrase-structured) --------------------
# Hazards (mines/asteroids) are first-class CombatScores now: shaped FORMATION
# drops (wall/pincer/spread) the conductor dispatches with real lane placement,
# separated by BREATHERs. mines/asteroids self-drift (their own _process), so no
# movement_override is needed — they fall straight down from their spawn lane.
static func _haz_spec(scene, count: int, interval: float, formation: int) -> Resource:
	var sp = WaveSpec.new()
	sp.enemy_scene = scene
	sp.count = count
	sp.spawn_interval = interval
	sp.spawn_delay = 0.0
	sp.formation = formation
	return sp


static func _formation_phrase(shape: StringName, spec: Resource) -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.FORMATION
	ph.shape = shape          # &"wall" / &"pincer" / &"top_spread"
	ph.specs = [spec]
	return ph


static func _breather_phrase(dur: float) -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.BREATHER
	ph.duration = dur
	ph.alive_floor = -1       # pure-hazard levels have 0 combatants; -1 = wait full duration
	return ph


# Hazard breather with a real alive_floor: the conductor breaks out early once the field thins
# to <= floor_n (hazards count toward _alive_count now), so density visibly EBBS between swells;
# falls back to the full duration if the field is still busy. (Roman 2026-06-23.)
static func _haz_breather(dur: float, floor_n: int) -> Phrase:
	var ph := Phrase.new()
	ph.kind = Phrase.Kind.BREATHER
	ph.duration = dur
	ph.alive_floor = floor_n
	return ph


# Splice any authored HAZARD patterns of `kind` ("asteroid"/"mine") onto a hazard wave — Roman
# hand-places navigable layouts (faction "hazard" in the wave editor) ON TOP of the algorithmic
# arc. Each becomes an authored FORMATION phrase (exact lanes, navigable by construction) preceded
# by a clearing breather. None authored = the baseline arc, unchanged. (Roman 2026-06-23.)
static func _splice_hazard_patterns(wave, kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA57E + hash(kind)
	for p in AuthoredPatterns.hazard_patterns(kind):
		var ph = AuthoredPatterns.build_phrase(p, -1, 0, rng)
		if ph != null:
			wave.phrases.append(_haz_breather(2.0, 5))
			wave.phrases.append(ph)

# Hazard: Minefield — phrase-native CombatScore. Lane-shaped mine drops
# (wall/pincer/spread) the conductor dispatches with real lane placement, paced by
# breathers so the player can weave through. See build_minefield_score below. (The
# old formation_padding template catalog was retired 2026-06-05 — the conductor
# lane-snaps placement, so the padding-geometry shapes no longer applied.)

# Variant pool (everything except basic).
const VARIANT_SCENES := [
	"MineShieldScene", "MineGravityScene", "MineSmartScene", "MineArmoredScene", "MineTetherScene",
]


static func build_minefield_score() -> CombatScore:
	var rng = RandomNumberGenerator.new()
	# Seed from run_seed + the current node so a minefield reproduces per run+node (was
	# randomize() — non-deterministic). run_seed 0 (headless tools) stays deterministic.
	var _ms_rs: int = 0
	var _ms_nid: String = ""
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("Run"):
		var _ms_run = Engine.get_main_loop().root.get_node("Run")
		_ms_rs = int(_ms_run.run_seed) if "run_seed" in _ms_run else 0
		_ms_nid = String(_ms_run.current_node_id) if "current_node_id" in _ms_run else ""
	rng.seed = (_ms_rs * 2654435761) ^ (hash(_ms_nid) * 40503) ^ 0x4D696E65
	# Mine-type selection (preserved): dev forced type / 5% single-variant field /
	# basic + a variant sprinkle.
	var forced_type: String = ""
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("Run"):
		var run = Engine.get_main_loop().root.get_node("Run")
		if run.has_meta("minefield_mine_type"):
			forced_type = String(run.get_meta("minefield_mine_type"))
			run.remove_meta("minefield_mine_type")
	var base_scene = MineScene
	if forced_type != "":
		match forced_type:
			"basic": base_scene = MineScene
			"smart": base_scene = _scene_by_name("MineSmartScene")
			"shielded": base_scene = _scene_by_name("MineShieldScene")
			"gravity", "cluster", "mega": base_scene = _scene_by_name("MineGravityScene")
			"armored": base_scene = _scene_by_name("MineArmoredScene")
			"tether": base_scene = _scene_by_name("MineTetherScene")
			# "mixed" falls through to basic + sprinkle.
	elif rng.randf() < 0.05:
		base_scene = _scene_by_name(VARIANT_SCENES[rng.randi() % VARIANT_SCENES.size()])

	# Lane-native mine beats — combat-level density, rapid succession. WALL =
	# successive rows leaving shifting gap lanes to thread; PINCER = edge-inward
	# burst; SPREAD = a tight lane-scatter. Short BREATHERs keep walls coming fast so
	# the player must commit to weaving a gap OR shooting through. Pick 4 of 5.
	# Density bumped to ~300 (Roman 2026-06-11: "300 enemy mark like other levels", relax on-screen
	# limits here). ~1.6× the per-beat counts + tighter intervals; ALL beats used (was 4 of 5).
	var beats := [
		{"shape": &"wall",       "count": 32, "interval": 0.08},
		{"shape": &"wall",       "count": 30, "interval": 0.08},
		{"shape": &"pincer",     "count": 24, "interval": 0.08},
		{"shape": &"top_spread", "count": 40, "interval": 0.12},
		{"shape": &"wall",       "count": 36, "interval": 0.08},
	]
	var order := []
	for i in beats.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):  # Fisher-Yates shuffle
		var j: int = rng.randi() % (i + 1)
		var t = order[i]; order[i] = order[j]; order[j] = t

	var wave := ScoreWave.new()
	wave.banner = "MINEFIELD DETECTED"
	var total_basic: int = 0
	var beat_count: int = beats.size()   # ALL beats — rapid succession of dense drops (~162 basic)
	for k in beat_count:
		var b: Dictionary = beats[order[k]]
		var form_id: int = 2 if b["shape"] == &"top_spread" else 0
		wave.phrases.append(_formation_phrase(b["shape"],
			_haz_spec(base_scene, int(b["count"]), float(b["interval"]), form_id)))
		total_basic += int(b["count"])
		if k < beat_count - 1:
			wave.phrases.append(_haz_breather(2.0, 7))   # ebb between beats (was a flat 0.35s)
	# Bomblet WALLS (Roman 2026-06-11): dense straight-descending walls to weave/shoot
	# through, NOT scattered wiggling pockets (form_id 0 = wall). ~104 bomblets.
	for c in range(4):
		wave.phrases.append(_haz_breather(2.5, 5))   # ebb before each bomblet wall
		wave.phrases.append(_formation_phrase(&"wall", _haz_spec(BombletScene, 26, 0.10, 0)))

	# Variant sprinkle: a final lane-scatter mixing the non-basic mine types into a basic
	# field (Roman 2026-06-09 — now that the new mine art/types are in, every minefield shows
	# them off). TWO distinct random variants (shielded / smart / cluster / mega) ...
	if base_scene == MineScene:
		var pool: Array = VARIANT_SCENES.duplicate()
		for i in range(pool.size() - 1, 0, -1):   # shuffle so the two picks are distinct
			var j: int = rng.randi() % (i + 1)
			var t = pool[i]; pool[i] = pool[j]; pool[j] = t
		var vcount: int = max(1, int(round(float(total_basic) * rng.randf_range(0.01, 0.20))))
		wave.phrases.append(_haz_breather(3.0, 4))   # release before the variant finale
		wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(_scene_by_name(pool[0]), vcount, 0.35, 2)))
		wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(_scene_by_name(pool[1]), max(1, vcount / 2), 0.4, 2)))
		# ... PLUS a few Armored mines (4 HP) as tougher must-dodge anchors — the new mine type.
		var acount: int = max(2, int(round(float(total_basic) * 0.06)))
		wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(MineArmoredScene, acount, 0.4, 2)))

	_splice_hazard_patterns(wave, "mine")   # Roman's hand-placed mine layouts, if any
	var score := CombatScore.new()
	score.level_name = "Minefield"
	score.waves = [wave]
	return score


static func _scene_by_name(s: String):
	match s:
		"MineScene": return MineScene
		"MineShieldScene": return MineShieldScene
		"MineGravityScene": return MineGravityScene
		"MineSmartScene": return MineSmartScene
		"MineArmoredScene": return MineArmoredScene
		"MineTetherScene": return MineTetherScene
	return MineScene


# Hazard: Asteroid Field. Slow chunky asteroids; the player can shoot them
# down or weave around. Random formation creates organic clusters and gaps.
# Density bumped 2026-05-16 (Roman: "Asteroid hazards need to have asteroids
# in all layers of parallax and in higher number"). Gameplay-layer counts
# almost doubled, plus a tighter spawn interval — combined with the
# parallax-side asteroid_presence boost in galaxy_backdrop, the field
# should feel busy at every depth.
static func build_asteroid_field_score() -> CombatScore:
	# Busy continuous field — lane-scattered drops with a light ebb, plus one "wall
	# of rock" beat for a denser moment. Asteroids self-drift with a little x-wander
	# (asteroid.gd), placed on lanes via the spread/wall dispatch. Density tuned to
	# the prior field (~90 rocks) but now lane-shaped + paced.
	# Spawn intervals widened ~1.4× (Roman 2026-06-11: same count, but spaced out more
	# so the field is avoidable, not a wall). Counts unchanged.
	# Density ARC (Roman 2026-06-23): asteroids are conducted like enemies now — cap-throttled
	# (main.gd sets max_concurrent) + lane-spread — so each beat STREAMS instead of walling up.
	# The field ebbs and flows for tension: light approach -> building scatter -> a dense climax
	# that pegs the cap -> release -> coda. _haz_breather floors thin the field between swells
	# (hazards count toward _alive_count now). Counts ~= how long each dense beat runs (the cap
	# gates them); intervals are the min spacing; floors = how empty it gets. Baseline kept near
	# the old ~128 rocks — tune freely / author extra patterns on top.
	var wave := ScoreWave.new()
	wave.banner = "COLLISION WARNING"
	# 1. Approach — a light scatter drifts in; the field arrives gently.
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 12, 0.55, 2)))
	wave.phrases.append(_haz_breather(4.0, 2))     # nearly clears — the calm before
	# 2. Build — denser scatter, then a first "pick a gap" wall.
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 18, 0.40, 2)))
	wave.phrases.append(_formation_phrase(&"wall", _haz_spec(AsteroidScene, 14, 0.22, 0)))
	wave.phrases.append(_haz_breather(3.0, 5))     # partial thin
	# 3. Climax — sustained pressure at the cap: walls + scatter back-to-back.
	wave.phrases.append(_formation_phrase(&"wall", _haz_spec(AsteroidScene, 18, 0.20, 0)))
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 22, 0.32, 2)))
	wave.phrases.append(_formation_phrase(&"wall", _haz_spec(AsteroidScene, 16, 0.20, 0)))
	wave.phrases.append(_haz_breather(2.5, 6))     # a single tense breath at peak
	# 4. Release — one more pass, then the field empties out.
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 16, 0.45, 2)))
	wave.phrases.append(_haz_breather(4.5, 1))     # big release, near-empty
	# 5. Coda — a final light drift-through.
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 10, 0.6, 2)))
	_splice_hazard_patterns(wave, "asteroid")   # Roman's hand-placed asteroid layouts, if any
	var score := CombatScore.new()
	score.level_name = "Asteroid Field"
	score.waves = [wave]
	return score


# Test roster: showcases the 7 new enemies in sequence. Each wave introduces
# one type with the movement + shoot pattern it ships with. Used by the
# Test Roster button in the main menu.
static func build_roster_test():
	# WAVE 1: Frigate trio — slow, armored, burst-shoots in place.
	var w1 = WaveSpec.new()
	w1.enemy_scene = FrigateScene
	w1.count = 3
	w1.spawn_interval = 0.9
	w1.spawn_delay = 0.5
	w1.formation = 3  # CENTER_OUT
	w1.announce_text = "FRIGATE PATROL"
	w1.movement_override = EnemyRoster.make_movement({"movement": "straight"})
	w1.shoot_pattern_override = _burst(3, 0.18)
	w1.fire_interval_min = 1.8
	w1.fire_interval_max = 2.8

	# WAVE 2: Cutters — enter from sides, cut across leaving a trail of shots.
	var w2 = WaveSpec.new()
	w2.enemy_scene = DartScene
	w2.count = 4
	w2.spawn_interval = 0.7
	w2.spawn_delay = 2.0
	w2.formation = 0
	w2.announce_text = "CUTTERS INBOUND"
	w2.movement_override = EnemyRoster.make_movement({"movement": "side_turn"})
	w2.shoot_pattern_override = _single()
	w2.fire_interval_min = 0.3
	w2.fire_interval_max = 0.5

	# WAVE 3: Skirmishers — advance-retreat cycles, aimed fire.
	var w3 = WaveSpec.new()
	w3.enemy_scene = SkirmisherScene
	w3.count = 4
	w3.spawn_interval = 0.5
	w3.spawn_delay = 2.0
	w3.formation = 2
	w3.announce_text = "SKIRMISHER WING"
	w3.movement_override = EnemyRoster.make_movement({"movement": "skirmish_loop"})
	w3.shoot_pattern_override = _aimed()
	w3.fire_interval_min = 0.7
	w3.fire_interval_max = 1.1

	# WAVE 4: Minelayer pair — cross the screen dropping bomblets.
	var w4 = WaveSpec.new()
	w4.enemy_scene = MinelayerScene
	w4.count = 2
	w4.spawn_interval = 1.4
	w4.spawn_delay = 2.5
	w4.formation = 2
	w4.announce_text = "MINELAYER DETECTED"
	w4.movement_override = EnemyRoster.make_movement({"movement": "side_traverse"})

	# WAVE 5: Interceptors — dive top→bottom dropping homing missiles.
	var w5 = WaveSpec.new()
	w5.enemy_scene = InterceptorScene
	w5.count = 4
	w5.spawn_interval = 0.45
	w5.spawn_delay = 2.0
	w5.formation = 2
	w5.announce_text = "INTERCEPTORS DIVING"
	w5.movement_override = EnemyRoster.make_movement({"movement": "side_turn"})

	# WAVE 6: Bulwark + Hunter Drones. Bulwark shields the drones until
	# you focus it down.
	var w6 = WaveSpec.new()
	w6.enemy_scene = BulwarkScene
	w6.count = 1
	w6.spawn_interval = 0.4
	w6.spawn_delay = 2.5
	w6.formation = 3
	w6.announce_text = "BULWARK ESCORT"
	w6.movement_override = EnemyRoster.make_movement({"movement": "drift"})

	var w7 = WaveSpec.new()
	w7.enemy_scene = HunterDroneScene
	w7.count = 4
	w7.spawn_interval = 0.6
	w7.spawn_delay = 0.5
	w7.silent = true
	w7.formation = 2
	w7.movement_override = EnemyRoster.make_movement({"movement": "hunt_beeline"})

	var level = LevelData.new()
	level.level_name = "New Roster Test"
	level.waves = [w1, w2, w3, w4, w5, w6, w7]
	return level


# Firecore Drone showcase (Roman, 2026-05-31). Three waves with deliberately
# varied screen coverage on death — the whole point of this enemy is the
# expanding bullet wave it releases when killed.
#   W1: one lone 4-ring drone, dead center — a dense local bullet-flower that
#       erupts into ~30 outward bullets. Tight, intense local dodge.
#   W2: three spread 2-ring drones — wide coverage; three medium bursts across
#       the playfield force lateral movement.
#   W3: a line of five 1-ring drones — broad, shallow coverage; many small
#       simultaneous rings tile the screen with gaps to thread.
static func build_firecore_drone_showcase():
	# WAVE 1: lone 4-ring drone, center.
	var w1 = WaveSpec.new()
	w1.enemy_scene = FirecoreDroneScene
	w1.count = 1
	w1.spawn_interval = 0.5
	w1.spawn_delay = 0.5
	w1.formation = 3  # TOP_CENTER_OUT
	w1.ring_count_override = 4
	w1.announce_text = "FIRECORE DRONE"

	# WAVE 2: three spread 2-ring drones.
	var w2 = WaveSpec.new()
	w2.enemy_scene = FirecoreDroneScene
	w2.count = 3
	w2.spawn_interval = 0.4
	w2.spawn_delay = 2.5
	w2.formation = 3  # TOP_CENTER_OUT — even spread
	w2.formation_padding = 36.0
	w2.ring_count_override = 2
	w2.announce_text = "DRONE TRIAD"

	# WAVE 3: line of five 1-ring drones.
	var w3 = WaveSpec.new()
	w3.enemy_scene = FirecoreDroneScene
	w3.count = 5
	w3.spawn_interval = 0.3
	w3.spawn_delay = 2.5
	w3.formation = 0  # TOP_LEFT_TO_RIGHT — full-width line
	w3.formation_padding = 24.0
	w3.ring_count_override = 1
	w3.announce_text = "DRONE LINE"

	var level = LevelData.new()
	level.level_name = "Firecore Drone Showcase"
	level.waves = [w1, w2, w3]
	return level


# MISSILE CRUISER showcase (Roman, 2026-05-31). The cruiser itself is NOT a
# wave enemy — it is spawned into the world by main.gd (see
# _spawn_missile_cruiser) when the showcase subtype is active. This level just
# provides a light, slow trickle of drifters so a player exists and the level
# does not insta-clear (which would trigger _run_outro before the cruiser
# fires). Long spacing keeps the screen mostly clear so the telegraph circles,
# missiles, and AoE explosions read cleanly.
static func build_missile_cruiser_showcase():
	var w1 = WaveSpec.new()
	w1.enemy_scene = DartScene
	w1.count = 3
	w1.spawn_interval = 6.0
	w1.spawn_delay = 4.0
	w1.formation = 0  # TOP_LEFT_TO_RIGHT
	w1.formation_padding = 48.0
	w1.announce_text = "MISSILE CRUISER"

	var w2 = WaveSpec.new()
	w2.enemy_scene = DartScene
	w2.count = 3
	w2.spawn_interval = 6.0
	w2.spawn_delay = 12.0
	w2.formation = 0
	w2.formation_padding = 48.0

	var level = LevelData.new()
	level.level_name = "Missile Cruiser Showcase"
	level.waves = [w1, w2]
	return level


# BEAM showcase (M6a.2 step 4) — every converted beam enemy in sequence so the
# unified BeamEmitter can be eyeballed in live play: Beamer sweep (aim-down), Beamer
# track (aim-player), Burner pair (segment beam between two ships), Beam Turret
# (cruiser host, locked beam). Low counts so each reads clearly; the Beamers never
# self-despawn (offscreen_mode NONE), so the level holds until the player clears it.
static func build_beam_showcase():
	var w1 = WaveSpec.new()
	w1.enemy_scene = BeamerScene
	w1.count = 2
	w1.spawn_interval = 0.6
	w1.spawn_delay = 0.5
	w1.formation = 0  # TOP_LEFT_TO_RIGHT
	w1.formation_padding = 60.0
	w1.announce_text = "BEAMER — SWEEP"

	var w2 = WaveSpec.new()
	w2.enemy_scene = BeamerTrackerScene
	w2.count = 2
	w2.spawn_interval = 0.6
	w2.spawn_delay = 6.0
	w2.formation = 0
	w2.formation_padding = 60.0
	w2.announce_text = "BEAMER — CHASE"

	var wlock = WaveSpec.new()
	wlock.enemy_scene = BeamerLockScene
	wlock.count = 2
	wlock.spawn_interval = 0.6
	wlock.spawn_delay = 6.0
	wlock.formation = 0
	wlock.formation_padding = 60.0
	wlock.announce_text = "BEAMER — LOCK"

	var w3 = WaveSpec.new()
	w3.enemy_scene = BurnerScene
	w3.count = 2
	w3.spawn_interval = 0.1   # near-simultaneous so the pair adopts each other
	w3.spawn_delay = 6.0
	w3.formation = 5  # TOP_TANDEM_PAIRS — Burners must arrive as a pair
	w3.tandem_offset_x = 70.0
	w3.announce_text = "BURNER PAIR"

	var w4 = WaveSpec.new()
	w4.enemy_scene = CruiserScene
	w4.count = 1
	w4.spawn_interval = 0.5
	w4.spawn_delay = 6.0
	w4.formation = 3  # TOP_CENTER_OUT
	w4.announce_text = "BEAM TURRET"

	var level = LevelData.new()
	level.level_name = "Beam Enemies Showcase"
	level.waves = [w1, w2, wlock, w3, w4]
	return level
