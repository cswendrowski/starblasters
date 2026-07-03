extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Unified Weapon resource (M6a.2) — the single, swappable firing identity any enemy
# can carry. Evolves shoot_pattern into one resource owning the volley SHAPE
# (fire_pattern), the PAYLOAD (a BulletVariant), the RATE (the inherited
# fire_interval_min/max — the single source), and the AIM. The movement axis
# (homing/wobble) is driven here onto each spawned bullet, so it's weapon-tunable
# (and faction/sector can multiply it) rather than baked per-variant.
#
# Referenced via preload (NOT a global class_name): a new class_name isn't registered
# in headless --script runs until the class cache regenerates. Preload is the
# codebase convention for pattern dependencies (see enemy_roster).
#
# The behavior (movement pattern) still owns fire TIMING (path-phase / on-hold /
# timer in enemy_core); the weapon owns fire CONTENT. Any behavior × any weapon.

const Playfield = preload("res://scripts/systems/playfield.gd")

enum FirePattern { SINGLE, AIMED, SPREAD, BURST, LOB, BROADSIDE }
# FORWARD (Roman 2026-06-08): fire along the enemy's NOSE (its facing / global_rotation),
# extracted from the strafer/crystal nose-ray firing. Pair with enemy_core.fire_only_on_target
# (the _nose_on_player gate) so the forward shot only releases when lined up on the player.
# BACKWARD/LEFT/RIGHT (Roman 2026-07-03): fire relative to the enemy's facing — out the tail,
# or off either beam. Same facing source as FORWARD (global_rotation), so a rotated hull's
# "left" is its own port side. Turret/beam ignore these (they aim their own way).
enum Aim { STRAIGHT_DOWN, TOWARD_CENTER, AT_PLAYER, FORWARD, BACKWARD, LEFT, RIGHT }

@export var fire_pattern: FirePattern = FirePattern.SINGLE
@export var payload: BulletVariant = null
@export var aim: Aim = Aim.STRAIGHT_DOWN
@export var lead_factor: float = 0.0          # AT_PLAYER velocity lead
@export var aim_angle_deg: float = 30.0       # TOWARD_CENTER diagonal angle

@export_group("Spread")
@export var spread_count: int = 3
@export var spread_degrees: float = 30.0

@export_group("Burst")
@export var burst_count: int = 3
@export var burst_interval: float = 0.12

# BROADSIDE (Roman 2026-06-08, salvaged from the retired frigate): each fire() emits ONE
# gun out the player-facing flank (the hull's local ±X normal with the larger dot toward the
# player), cycling GunLeft1..N / GunRight1..N markers so successive timer ticks ripple down
# the hull. The per-instance cycle counter lives on the enemy (set_meta), since a Weapon
# Resource is shared. Set the enemy's fire_interval to the per-gun beat (frigate used ~0.34s).
@export_group("Broadside")
@export var broadside_guns: int = 5

# Movement axis (homing/wobble) is inherited from shoot_pattern and applied inside
# _spawn_bullet — the weapon-driven homing/wobble that restores boss/enemy
# signatures and that faction/sector multipliers scale.

func fire(enemy) -> void:
	match fire_pattern:
		FirePattern.SINGLE:
			_fire_bullet(enemy, _aim_dir(enemy))
		FirePattern.AIMED:
			_fire_bullet(enemy, _aim_at_player(enemy, lead_factor))
		FirePattern.SPREAD:
			_fire_spread(enemy)
		FirePattern.BURST:
			_fire_burst(enemy)
		FirePattern.BROADSIDE:
			_fire_broadside(enemy)
		FirePattern.LOB:
			pass  # deferred payload
		_:
			_fire_bullet(enemy, _aim_dir(enemy))


# Base fire direction for the non-AT_PLAYER shapes.
func _aim_dir(enemy) -> Vector2:
	match aim:
		Aim.AT_PLAYER:
			return _aim_at_player(enemy, lead_factor)
		Aim.FORWARD:
			# Along the enemy's nose. Mirrors enemy_base.nose_dir() (Vector2.UP rotated by facing).
			return Vector2.UP.rotated(enemy.global_rotation)
		Aim.BACKWARD:
			# Opposite the nose — out the tail.
			return Vector2.DOWN.rotated(enemy.global_rotation)
		Aim.LEFT:
			# The enemy's port beam (relative to its facing).
			return Vector2.LEFT.rotated(enemy.global_rotation)
		Aim.RIGHT:
			# The enemy's starboard beam.
			return Vector2.RIGHT.rotated(enemy.global_rotation)
		Aim.TOWARD_CENTER:
			# Lean toward the playfield center: left-spawn (x < center) angles right-down,
			# right-spawn angles left-down. Sign corrected 2026-06-13 (was reversed — it
			# leaned AWAY from center; latent until 3b routed single_diagonal through here).
			var sign_x: float = 1.0 if enemy.global_position.x > Playfield.CENTER.x else -1.0
			return Vector2(0, 1).rotated(deg_to_rad(aim_angle_deg) * sign_x)
		_:
			return Vector2(0, 1)


func _fire_bullet(enemy, dir: Vector2) -> void:
	# _spawn_bullet applies the inherited movement axis to the bullet.
	_spawn_bullet(enemy, dir, payload)


func _fire_spread(enemy) -> void:
	var base_dir: Vector2 = _aim_dir(enemy)
	var n: int = maxi(1, spread_count)
	if n == 1:
		_fire_bullet(enemy, base_dir)
		return
	var total: float = deg_to_rad(spread_degrees)
	var step: float = total / float(n - 1)
	var start: float = -total * 0.5
	for i in n:
		_fire_bullet(enemy, base_dir.rotated(start + step * float(i)))


# Rolling broadside: fire ONE gun out the player-facing flank, cycling markers so each
# call ripples to the next gun. Flank = the hull-local ±X normal with the larger dot toward
# the player; shots go straight out that normal (a naval broadside, NOT aimed at the player).
func _fire_broadside(enemy) -> void:
	var to_player: Vector2 = _aim_at_player(enemy)   # normalized dir (or straight-down fallback)
	var left_n: Vector2 = Vector2(-1.0, 0.0).rotated(enemy.global_rotation)
	var right_n: Vector2 = Vector2(1.0, 0.0).rotated(enemy.global_rotation)
	var use_right: bool = right_n.dot(to_player) >= left_n.dot(to_player)
	var fire_dir: Vector2 = right_n if use_right else left_n
	var prefix: String = "GunRight" if use_right else "GunLeft"
	var n: int = maxi(1, broadside_guns)
	var gun: int = int(enemy.get_meta("_broadside_gun", 0)) % n
	# Spawn from the per-gun marker when the hull has one; else the hull centre.
	var spawn_pos = null
	var m = enemy.get_node_or_null(prefix + str(gun + 1))
	if m != null:
		spawn_pos = m.global_position
	_spawn_bullet(enemy, fire_dir, payload, spawn_pos)
	enemy.set_meta("_broadside_gun", (gun + 1) % n)


const _EnemySfx = preload("res://scripts/effects/enemy_sfx.gd")

func _fire_burst(enemy) -> void:
	var dir: Vector2 = _aim_dir(enemy)
	_fire_bullet(enemy, dir)   # shot 1's SFX is played by enemy_core after fire() returns
	for i in range(1, maxi(1, burst_count)):
		await enemy.get_tree().create_timer(burst_interval).timeout
		# Bail if the host went away OR is now held (dying / recycling / off the playfield) — a
		# hull burst that started on-screen must not keep firing into a death/recycle (Roman
		# 2026-07-01, matching mount_component's _fire_gun burst guard).
		if not is_instance_valid(enemy) or _held(enemy):
			return
		_fire_bullet(enemy, dir)
		# Each subsequent burst shot fires its OWN sound (Roman 2026-06-11: enemy
		# weapons should play their fire sound on every shot, bursts included).
		_EnemySfx.play_for(enemy)


# Hold fire while the host is dying / recycling / off the playfield. Mirrors mount_component._held +
# enemy_core's shoot-timer guards. Duck-typed: _dying/_cycling live on enemy_core (a pure enemy_base
# host may lack them); enemy_core provides _on_playfield, pure enemy_base enemies fall back to an
# inline off-screen box (X uses the full viewport so gutters never gate; only the Y edges suppress).
func _held(enemy) -> bool:
	if "_dying" in enemy and enemy._dying:
		return true
	if "_cycling" in enemy and enemy._cycling:
		return true
	if enemy.has_method("_on_playfield"):
		return not enemy._on_playfield()
	return _off_screen(enemy)


func _off_screen(enemy) -> bool:
	if not (enemy is Node2D):
		return false
	const M := 8.0
	var sz: Vector2 = enemy.get_viewport_rect().size
	var p: Vector2 = enemy.position
	return p.x < M or p.x > sz.x - M or p.y < M or p.y > sz.y - M

# (_apply_axis is inherited from shoot_pattern and applied inside _spawn_bullet — the
# duplicate override here was dead, removed per the M6 review.)
