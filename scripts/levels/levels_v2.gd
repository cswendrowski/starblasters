extends Node

# Runtime LevelDef factory. Avoids .tres serialization quirks for typed
# Array[Resource] while we iterate on level design.

const WaveSpec = preload("res://scripts/levels/wave_def.gd")
const LevelData = preload("res://scripts/levels/level_def.gd")
const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const SCurve = preload("res://scripts/enemies/patterns/s_curve.gd")
const Loiter = preload("res://scripts/enemies/patterns/loiter.gd")
const SingleShot = preload("res://scripts/enemies/shoot_patterns/single_shot.gd")
const SpreadShot = preload("res://scripts/enemies/shoot_patterns/spread_shot.gd")
const AimedShot = preload("res://scripts/enemies/shoot_patterns/aimed_fire.gd")
const BurstShot = preload("res://scripts/enemies/shoot_patterns/burst_shot.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")
const FirecoreScene = preload("res://scenes/enemies/core/enemy_spitter.tscn")
const DrifterScene = preload("res://scenes/enemies/core/enemy_drifter.tscn")
const CrystalScene = preload("res://scenes/enemies/core/enemy_crystal.tscn")
const DartScene = preload("res://scenes/enemies/factions/privateer/enemy_dart.tscn")
const HoverScene = preload("res://scenes/enemies/core/enemy_hover.tscn")
const BossScene = preload("res://scenes/enemies/boss.tscn")
const BossSweep = preload("res://scripts/enemies/patterns/boss_sweep.gd")
const MineScene = preload("res://scenes/enemies/enemy_mine.tscn")
const MineShieldScene = preload("res://scenes/enemies/enemy_mine_shield.tscn")
const MineClusterScene = preload("res://scenes/enemies/enemy_mine_cluster.tscn")
const MineClusterSmartScene = preload("res://scenes/enemies/enemy_mine_cluster_smart.tscn")  # Mega Cluster
const MineSmartScene = preload("res://scenes/enemies/enemy_mine_smart.tscn")
const AsteroidScene = preload("res://scenes/enemies/enemy_asteroid.tscn")
const FrigateScene = preload("res://scenes/enemies/factions/supremacy/enemy_frigate.tscn")
const CutterScene = preload("res://scenes/enemies/core/enemy_cutter.tscn")
const SkirmisherScene = preload("res://scenes/enemies/factions/corporate/enemy_skirmisher.tscn")
const MinelayerScene = preload("res://scenes/enemies/factions/privateer/enemy_minelayer.tscn")
const InterceptorScene = preload("res://scenes/enemies/factions/privateer/enemy_interceptor.tscn")
const HunterDroneScene = preload("res://scenes/enemies/factions/corporate/enemy_hunter_drone.tscn")
const BulwarkScene = preload("res://scenes/enemies/factions/corporate/enemy_bulwark.tscn")
const FirecoreDroneScene = preload("res://scenes/enemies/factions/zealot/enemy_firecore_drone.tscn")
# Beam enemies (M6a.2 beam showcase).
const BeamerScene = preload("res://scenes/enemies/factions/zealot/enemy_beam_shooter.tscn")
const BeamerTrackerScene = preload("res://scenes/enemies/factions/zealot/enemy_beamer_tracker.tscn")
const BeamerLockScene = preload("res://scenes/enemies/factions/zealot/enemy_beamer_lock.tscn")
const BurnerScene = preload("res://scenes/enemies/factions/zealot/enemy_burner.tscn")
const CruiserScene = preload("res://scenes/enemies/core/enemy_cruiser.tscn")
const SideTraverse = preload("res://scripts/enemies/patterns/side_traverse.gd")
const SlowAdvance = preload("res://scripts/enemies/patterns/slow_advance.gd")
const TopDive = preload("res://scripts/enemies/patterns/top_dive.gd")
const SideCut = preload("res://scripts/enemies/patterns/side_cut.gd")
const AdvanceRetreat = preload("res://scripts/enemies/patterns/advance_retreat.gd")
const BeelinePlayer = preload("res://scripts/enemies/patterns/beeline_player.gd")
const BulwarkDrift = preload("res://scripts/enemies/patterns/bulwark_drift.gd")

static func _single() -> Resource:
	var sp = SingleShot.new()
	sp.bullet_scene = EnemyBullet
	return sp

static func _spread(count: int, degrees: float) -> Resource:
	var sp = SpreadShot.new()
	sp.bullet_scene = EnemyBullet
	sp.bullet_count = count
	sp.spread_degrees = degrees
	return sp

static func _aimed() -> Resource:
	var sp = AimedShot.new()
	sp.bullet_scene = EnemyBullet
	return sp

static func _burst(count: int, interval: float) -> Resource:
	var sp = BurstShot.new()
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

static func build_level_1_1():
	# WAVE 1: firecore single-shot intro
	var w1 = WaveSpec.new()
	w1.enemy_scene = FirecoreScene
	w1.count = 6
	w1.spawn_interval = 0.45
	w1.spawn_delay = 0.5
	w1.formation = 0
	var p1 = StraightDown.new()
	p1.speed = 220.0
	w1.movement_override = p1
	w1.shoot_pattern_override = _single()
	w1.fire_interval_min = 2.0
	w1.fire_interval_max = 3.5

	# WAVE 2: firecore s-curve, single shots
	var w2 = WaveSpec.new()
	w2.enemy_scene = FirecoreScene
	w2.count = 5
	w2.spawn_interval = 0.5
	w2.spawn_delay = 1.5
	w2.formation = 1
	var p2 = SCurve.new()
	p2.down_speed = 180.0
	p2.amplitude = 120.0
	p2.frequency = 1.4
	w2.movement_override = p2
	w2.shoot_pattern_override = _single()
	w2.fire_interval_min = 1.5
	w2.fire_interval_max = 3.0

	# WAVE 3: firecore loiter with spread shots — sub-wave of the firecore
	# intro; rides under WAVE 2's banner so the second wave feels meatier
	# without another announcement.
	var w3 = WaveSpec.new()
	w3.enemy_scene = FirecoreScene
	w3.count = 4
	w3.spawn_interval = 0.7
	w3.spawn_delay = 1.2
	w3.silent = true
	w3.formation = 3
	var p3 = Loiter.new()
	p3.hover_y = 240.0
	p3.enter_speed = 250.0
	p3.loiter_time = 4.0
	p3.exit_accel = 700.0
	p3.exit_max_speed = 800.0
	w3.movement_override = p3
	w3.shoot_pattern_override = _spread(3, 26.0)
	w3.fire_interval_min = 1.4
	w3.fire_interval_max = 2.4

	# WAVE 4: fast diver rush — single shots, lots of them
	var w4 = WaveSpec.new()
	w4.enemy_scene = DartScene
	w4.count = 8
	w4.spawn_interval = 0.22
	w4.spawn_delay = 1.5
	w4.formation = 2
	var p4 = StraightDown.new()
	p4.speed = 280.0
	w4.movement_override = p4
	w4.shoot_pattern_override = _single()
	w4.fire_interval_min = 0.6
	w4.fire_interval_max = 1.2

	# WAVE 5: crystal tanks — slow loiter, 3 HP, wide spread
	var w5 = WaveSpec.new()
	w5.enemy_scene = CrystalScene
	w5.count = 3
	w5.spawn_interval = 0.8
	w5.spawn_delay = 2.0
	w5.formation = 3
	var p5 = Loiter.new()
	p5.hover_y = 200.0
	p5.enter_speed = 180.0
	p5.loiter_time = 6.0
	p5.exit_accel = 400.0
	p5.exit_max_speed = 500.0
	w5.movement_override = p5
	w5.shoot_pattern_override = _spread(5, 36.0)
	w5.fire_interval_min = 1.8
	w5.fire_interval_max = 2.6
	w5.max_health = 3
	w5.bounty_value = 25

	# WAVE 6: pink dart raiders — fast s-curve, aimed shots, 2 HP
	var w6 = WaveSpec.new()
	w6.enemy_scene = DartScene
	w6.count = 6
	w6.spawn_interval = 0.4
	w6.spawn_delay = 2.0
	w6.formation = 1
	var p6 = SCurve.new()
	p6.down_speed = 240.0
	p6.amplitude = 180.0
	p6.frequency = 1.8
	w6.movement_override = p6
	w6.shoot_pattern_override = _aimed()
	w6.fire_interval_min = 1.2
	w6.fire_interval_max = 2.0
	w6.max_health = 2
	w6.bounty_value = 15

	# WAVE 7: alien hoppers — silent sub-wave of WAVE 6 dart raiders.
	var w7 = WaveSpec.new()
	w7.enemy_scene = HoverScene
	w7.count = 4
	w7.spawn_interval = 0.6
	w7.spawn_delay = 1.5
	w7.silent = true
	w7.formation = 0
	var p7 = Loiter.new()
	p7.hover_y = 320.0
	p7.enter_speed = 280.0
	p7.loiter_time = 5.0
	p7.exit_accel = 600.0
	p7.exit_max_speed = 700.0
	w7.movement_override = p7
	w7.shoot_pattern_override = _burst(3, 0.14)
	w7.fire_interval_min = 1.6
	w7.fire_interval_max = 2.4
	w7.max_health = 2
	w7.bounty_value = 20

	var level = LevelData.new()
	level.level_name = "Sector Alpha"
	level.waves = [w1, w2, w3, w4, w5, w6, w7]
	return level

# Boss level: 2 lead-in waves then a final wave with exactly 1 boss.
# WaveDirector will treat the boss like any other enemy; boss.gd handles its
# own scale, minion spawning, and fires level_cleared when it dies.
static func build_boss_level():
	# Lead-in: divers
	var w1 = WaveSpec.new()
	w1.enemy_scene = DartScene
	w1.count = 8
	w1.spawn_interval = 0.25
	w1.spawn_delay = 0.5
	w1.formation = 2  # TOP_RANDOM
	var p1 = StraightDown.new()
	p1.speed = 280.0
	w1.movement_override = p1
	w1.shoot_pattern_override = _single()
	w1.fire_interval_min = 0.7
	w1.fire_interval_max = 1.3

	# Lead-in: dart squadron
	var w2 = WaveSpec.new()
	w2.enemy_scene = DartScene
	w2.count = 6
	w2.spawn_interval = 0.4
	w2.spawn_delay = 2.0
	w2.formation = 3  # TOP_CENTER_OUT
	var p2 = SCurve.new()
	p2.down_speed = 220.0
	p2.amplitude = 160.0
	p2.frequency = 1.6
	w2.movement_override = p2
	w2.shoot_pattern_override = _aimed()
	w2.fire_interval_min = 1.4
	w2.fire_interval_max = 2.2
	w2.max_health = 2
	w2.bounty_value = 15

	# Boss wave: 1 boss. Long spawn_delay = grace period before the boss
	# actually enters and its HP bar appears (Roman, 2026-05-16).
	var w3 = WaveSpec.new()
	w3.enemy_scene = BossScene
	w3.count = 1
	w3.spawn_interval = 1.0
	w3.spawn_delay = 5.5
	w3.announce_text = "HIGH VALUE TARGET INCOMING"
	w3.formation = 3  # TOP_CENTER_OUT
	var p3 = BossSweep.new()
	p3.hover_y = 200.0
	p3.enter_speed = 140.0
	p3.sweep_amplitude = 240.0
	p3.sweep_frequency = 0.3
	w3.movement_override = p3
	w3.shoot_pattern_override = _spread(5, 50.0)
	w3.fire_interval_min = 0.9
	w3.fire_interval_max = 1.4
	# Don't override max_health here; boss.gd's @export sets 80.

	var level = LevelData.new()
	level.level_name = "Sector Commander"
	level.waves = [w1, w2, w3]
	return level


# Hazard: Minefield — phrase-native CombatScore. Lane-shaped mine drops
# (wall/pincer/spread) the conductor dispatches with real lane placement, paced by
# breathers so the player can weave through. See build_minefield_score below. (The
# old formation_padding template catalog was retired 2026-06-05 — the conductor
# lane-snaps placement, so the padding-geometry shapes no longer applied.)

# Variant pool (everything except basic).
const VARIANT_SCENES := [
	"MineShieldScene", "MineClusterScene", "MineClusterSmartScene", "MineSmartScene",
]


static func build_minefield_score() -> CombatScore:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
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
			"cluster": base_scene = _scene_by_name("MineClusterScene")
			"mega": base_scene = _scene_by_name("MineClusterSmartScene")
			# "mixed" falls through to basic + sprinkle.
	elif rng.randf() < 0.05:
		base_scene = _scene_by_name(VARIANT_SCENES[rng.randi() % VARIANT_SCENES.size()])

	# Lane-native mine beats — combat-level density, rapid succession. WALL =
	# successive rows leaving shifting gap lanes to thread; PINCER = edge-inward
	# burst; SPREAD = a tight lane-scatter. Short BREATHERs keep walls coming fast so
	# the player must commit to weaving a gap OR shooting through. Pick 4 of 5.
	var beats := [
		{"shape": &"wall",       "count": 20, "interval": 0.10},
		{"shape": &"wall",       "count": 18, "interval": 0.10},
		{"shape": &"pincer",     "count": 14, "interval": 0.10},
		{"shape": &"top_spread", "count": 24, "interval": 0.16},
		{"shape": &"wall",       "count": 22, "interval": 0.10},
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
	var beat_count: int = 4   # rapid succession of dense drops
	for k in beat_count:
		var b: Dictionary = beats[order[k]]
		var form_id: int = 2 if b["shape"] == &"top_spread" else 0
		wave.phrases.append(_formation_phrase(b["shape"],
			_haz_spec(base_scene, int(b["count"]), float(b["interval"]), form_id)))
		total_basic += int(b["count"])
		if k < beat_count - 1:
			wave.phrases.append(_breather_phrase(0.4))

	# Variant sprinkle: a final small lane-scatter of a random non-basic mine type
	# (1-20% of the basic total), only when the field is basic.
	if base_scene == MineScene:
		var sprinkle_scene = _scene_by_name(VARIANT_SCENES[rng.randi() % VARIANT_SCENES.size()])
		var vcount: int = max(1, int(round(float(total_basic) * rng.randf_range(0.01, 0.20))))
		wave.phrases.append(_breather_phrase(1.0))
		wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(sprinkle_scene, vcount, 0.35, 2)))

	var score := CombatScore.new()
	score.level_name = "Minefield"
	score.waves = [wave]
	return score


static func _scene_by_name(s: String):
	match s:
		"MineScene": return MineScene
		"MineShieldScene": return MineShieldScene
		"MineClusterScene": return MineClusterScene
		"MineClusterSmartScene": return MineClusterSmartScene
		"MineSmartScene": return MineSmartScene
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
	var wave := ScoreWave.new()
	wave.banner = "COLLISION WARNING"
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 32, 0.18, 2)))
	wave.phrases.append(_breather_phrase(0.35))
	wave.phrases.append(_formation_phrase(&"wall", _haz_spec(AsteroidScene, 20, 0.10, 0)))
	wave.phrases.append(_breather_phrase(0.35))
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 30, 0.18, 2)))
	wave.phrases.append(_breather_phrase(0.3))
	wave.phrases.append(_formation_phrase(&"top_spread", _haz_spec(AsteroidScene, 28, 0.18, 2)))
	wave.phrases.append(_breather_phrase(0.3))
	wave.phrases.append(_formation_phrase(&"wall", _haz_spec(AsteroidScene, 18, 0.10, 0)))
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
	var m1 = SlowAdvance.new()
	m1.hold_y = 220.0
	w1.movement_override = m1
	w1.shoot_pattern_override = _burst(3, 0.18)
	w1.fire_interval_min = 1.8
	w1.fire_interval_max = 2.8

	# WAVE 2: Cutters — enter from sides, cut across leaving a trail of shots.
	var w2 = WaveSpec.new()
	w2.enemy_scene = CutterScene
	w2.count = 4
	w2.spawn_interval = 0.7
	w2.spawn_delay = 2.0
	w2.formation = 0
	w2.announce_text = "CUTTERS INBOUND"
	var m2 = SideCut.new()
	m2.travel_y = 200.0
	m2.direction = 1
	w2.movement_override = m2
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
	var m3 = AdvanceRetreat.new()
	w3.movement_override = m3
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
	var m4 = SideTraverse.new()
	m4.travel_y = 180.0
	m4.direction = 1
	w4.movement_override = m4

	# WAVE 5: Interceptors — dive top→bottom dropping homing missiles.
	var w5 = WaveSpec.new()
	w5.enemy_scene = InterceptorScene
	w5.count = 4
	w5.spawn_interval = 0.45
	w5.spawn_delay = 2.0
	w5.formation = 2
	w5.announce_text = "INTERCEPTORS DIVING"
	var m5 = TopDive.new()
	w5.movement_override = m5

	# WAVE 6: Bulwark + Hunter Drones. Bulwark shields the drones until
	# you focus it down.
	var w6 = WaveSpec.new()
	w6.enemy_scene = BulwarkScene
	w6.count = 1
	w6.spawn_interval = 0.4
	w6.spawn_delay = 2.5
	w6.formation = 3
	w6.announce_text = "BULWARK ESCORT"
	var m6 = BulwarkDrift.new()
	w6.movement_override = m6

	var w7 = WaveSpec.new()
	w7.enemy_scene = HunterDroneScene
	w7.count = 4
	w7.spawn_interval = 0.6
	w7.spawn_delay = 0.5
	w7.silent = true
	w7.formation = 2
	var m7 = BeelinePlayer.new()
	w7.movement_override = m7

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
	w1.enemy_scene = DrifterScene
	w1.count = 3
	w1.spawn_interval = 6.0
	w1.spawn_delay = 4.0
	w1.formation = 0  # TOP_LEFT_TO_RIGHT
	w1.formation_padding = 48.0
	w1.announce_text = "MISSILE CRUISER"

	var w2 = WaveSpec.new()
	w2.enemy_scene = DrifterScene
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
