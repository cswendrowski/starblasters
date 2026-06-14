extends "res://scripts/enemies/bosses/boss_base.gd"

# Howler — sector 1 anchored bullet-hell turret. Stubby gunboat. Identity:
# anchored turret that cycles through MANY weapons + occasionally calls
# in chaff. The rotating 12-bullet ring is still the signature read.
#
# Stats set BEFORE super._ready() (no fallback pattern — caused the 1-HP
# regression on every other boss).
#
# 2026-05-24 difficulty pass (designer feedback "too easy if it sits still"):
#   - 4-attack cycling rotation (was 2-attack alternation): aimed burst,
#     ring, downward spread cascade, aimed sniper.
#   - One reinforcement wave (3 darts from above) triggers on phase
#     transition to P2 — capped at one wave per fight.
#   - HP 130 -> 180, bounty 200 -> 250.
#
# Phase 1 (100→50%): anchored, cycle through 4 attacks every 1.4s.
# Phase 2 ( 50→0%):  cadence 1.0s, ring slot fires twice in a row,
#                    +30deg rotation per fire, enrage flash + 4.0 shake,
#                    reinforcement wave on entry.

const DartScene = preload("res://scenes/enemies/factions/privateer/enemy_dart.tscn")

var _ring_offset_deg: float = 0.0
var _ring_step_deg: float = 0.0
var _attack_idx: int = 0
var _cycle_cadence: float = 1.4
var _ring_double_fire: bool = false
var _reinforcements_spawned: bool = false

# Per-slot bullet variants. Loaded once in _ready().
var _var_aimed: BulletVariant = null   # aimed burst (slot 0)
var _var_ring: BulletVariant = null    # ring (slot 1)
var _var_spread: BulletVariant = null  # spread cascade (slot 2)
var _var_sniper: BulletVariant = null  # sniper shot (slot 3) — upgrades in P2


func _ready() -> void:
	max_health = 180
	bounty_value = 500
	display_scale = 1.0
	boss_hover_y = 60.0
	fire_interval_min = 1.4
	fire_interval_max = 1.4
	# Each slot gets a distinct variant so the player learns the rotation visually.
	# P2 enrage upgrades slot 3 to laser_bolt (swap done in _on_phase_entered).
	_var_aimed  = load("res://data/bullets/boss/aimed_sniper.tres")
	_var_ring   = load("res://data/bullets/boss/heavy_slug.tres")
	_var_spread = load("res://data/bullets/boss/plasma_orb.tres")
	_var_sniper = load("res://data/bullets/boss/aimed_sniper.tres")
	phases = [
		BossPhase.make("Phase 1", 1.0, false, 0.0),
		BossPhase.make("Phase 2", 0.5, true, 4.0),
	]
	super._ready()


func start(pos: Vector2) -> void:
	super.start(pos)
	anchor_at(Vector2(Playfield.CENTER.x, boss_hover_y))


func _on_phase_entered(phase_idx: int, _phase_name: String) -> void:
	if phase_idx == 1:
		_cycle_cadence = 1.0
		_ring_step_deg = 30.0
		_ring_double_fire = true
		# P2 enrage: upgrade the sniper slot to laser_bolt for the "panic" read.
		_var_sniper = load("res://data/bullets/boss/laser_bolt.tres")
		_spawn_reinforcement_wave()


# Howler's attack rotation. We replace ShootTimer's dumb-fire with a single
# coroutine cycling through 4 attack slots so the player learns the pattern
# but each beat is distinct.
func _attack_loop() -> void:
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	_run_cycle_loop()


func _run_cycle_loop() -> void:
	while not _dying and is_instance_valid(self):
		await get_tree().create_timer(_cycle_cadence).timeout
		if _dying:
			return
		match _attack_idx % 4:
			0:
				# Aimed burst — staggered to force the player to track.
				fire_aimed_burst(5, 30.0, 0.05, _var_aimed)
			1:
				# Rotating 360 ring. P2: fire twice for a denser wave.
				# Heavy slug: slow fat orbs make the ring readable + threatening.
				fire_ring(12, _ring_offset_deg, _var_ring)
				_ring_offset_deg += _ring_step_deg
				if _ring_double_fire:
					await get_tree().create_timer(0.25).timeout
					if _dying:
						return
					fire_ring(12, _ring_offset_deg + 15.0, _var_ring)
					_ring_offset_deg += _ring_step_deg
			2:
				# Wide downward spread cascade — punishes camping below.
				# Plasma orb: wobble adds chaos to the dumb fan.
				fire_spread(8, 60.0, true, _var_spread)
			3:
				# Sniper shot — single fast aimed bullet, "predict me".
				# Upgrades to laser_bolt in P2 enrage.
				fire_aimed_cone(1, 0.0, _var_sniper)
		_attack_idx += 1


# ---- Reinforcement wave -------------------------------------------------

# One-shot: spawn 3 darts from above Howler's position on P2 entry. Capped
# at one wave per fight so we don't drown the player.
func _spawn_reinforcement_wave() -> void:
	if _reinforcements_spawned or _dying:
		return
	_reinforcements_spawned = true
	var parent: Node = get_parent()
	if parent == null:
		return
	for i in 3:
		var d: Node = DartScene.instantiate()
		var spawn_pos: Vector2 = global_position + Vector2(-32.0 + float(i) * 32.0, -40.0)
		parent.add_child(d)
		d.add_to_group("enemies")
		if d.has_method("start"):
			d.start(spawn_pos)
		else:
			if d is Node2D:
				(d as Node2D).global_position = spawn_pos
