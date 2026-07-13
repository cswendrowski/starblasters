extends "res://scripts/parts/secondary_weapon.gd"

# Swarm Launcher — HARDPOINT_WING secondary (SecondaryMode.SALVO). Press shoot2 to
# release a salvo of homing micro-missiles that fan out to DISTINCT targets (else
# all chase one; each re-acquires when its target dies; flies on + explodes
# harmlessly if no enemies remain). 4 dmg each, 4 missiles at Mk.1 (+2/Mk), 6 ammo
# (1 per salvo), 3s cooldown. The Part owns the spawn loop + target assignment;
# player._tick_salvo gates on cooldown + ammo. Fire-and-forget (not tracked).
# Design: docs/swarm_launcher_secondary_2026-06-08.md.

const WSsl = preload("res://scripts/weapons/WeaponStyle.gd")
const SwarmMissileScene = preload("res://scenes/projectiles/bullet_swarm.tscn")

@export var base_ammo: int = 6


func _init() -> void:
	super._init()
	display_name = "Swarm Launcher"
	description = "Releases a salvo of homing micro-missiles that fan out to distinct targets and explode against them. Mk adds 2 missiles. Secondary."
	# Stats live in resources/weapons/swarm_launcher.tres (single source of truth).


func _secondary_mode() -> int:
	return WSsl.SecondaryMode.SALVO


func _snapshot_keys() -> Array:
	return ["secondary_mode", "secondary_cooldown"]


# No ship-written Mk knobs — count is read off this Part at fire time; cooldown is
# set in _apply_visuals. (Mirrors drone_swarm's empty-knobs DEPLOY pattern.)
func _mk_knobs() -> Dictionary:
	return {}


# +2 missiles per Mk: 4, 6, 8, ... 20 for Mk1-9.
func _missiles_at_mark(at_mark: int) -> int:
	return 4 + (at_mark - 1) * 2


func _apply_visuals(ship) -> void:
	if "secondary_mode" in ship:
		ship.secondary_mode = _secondary_mode()
	if "secondary_cooldown" in ship:
		ship.secondary_cooldown = base_cooldown
	# SALVO spawns its own missiles in fire_salvo; clear any prior secondary's
	# bullet scene so stale state doesn't linger on the ship.
	if "secondary_bullet_scene" in ship:
		ship.secondary_bullet_scene = null
	# Seed ammo (6); survives scene changes via the Run snapshot like other secondaries.
	if ship.has_method("set_secondary_ammo"):
		var seeded: int = base_ammo
		# Sector Conditions — More Ammo scales the salvo-ammo CAP once, matching the
		# run-side scaled secondary_ammo seed (avoids a current>max transient).
		var cap: int = base_ammo
		if ship.has_node("/root/Run"):
			var run = ship.get_node("/root/Run")
			if base_ammo > 0:
				cap = run.cond_ammo_cap(base_ammo)
			if "secondary_ammo" in run and int(run.secondary_ammo) >= 0:
				seeded = int(run.secondary_ammo)
		ship.set_secondary_ammo(seeded, cap)


func _on_unapply(ship) -> void:
	if ship.has_method("set_secondary_ammo"):
		ship.set_secondary_ammo(-1, -1)


# Fire one salvo: spawn N missiles, each assigned a DISTINCT target (round-robin
# over enemies sorted nearest-first), with a fanned launch heading so they spread
# before homing. Returns true if fired (always, when the ship has a tree).
func fire_salvo(ship) -> bool:
	if not ship.has_method("get_tree"):
		return false
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return false
	var n: int = _missiles_at_mark(int(mark))
	var targets: Array = _sorted_targets(ship)
	# Coroutine (not awaited): ripples the salvo out one missile per frame, alternating
	# the L/R wing markers (Roman 2026-06-11: a fan effect, not a single burst).
	_spawn_salvo(ship, n, targets)
	return true


func _spawn_salvo(ship, n: int, targets: Array) -> void:
	var parent: Node = ship.get_tree().root
	if "bullet_parent" in ship and ship.bullet_parent != null:
		parent = ship.bullet_parent
	for i in n:
		if not is_instance_valid(ship):
			return
		var right: bool = (i % 2) == 1                 # alternate left / right wing
		var wpos: Vector2 = _wing_pos(ship, right)
		var m = SwarmMissileScene.instantiate()
		# Fan the launch heading across ±55° so the salvo spreads before homing.
		var t: float = 0.5 if n <= 1 else float(i) / float(n - 1)
		var ang: float = deg_to_rad(lerpf(-55.0, 55.0, t))
		m.initial_dir = Vector2(sin(ang), -cos(ang))
		m.position = wpos
		# Distinct target per missile (round-robin). Empty list (no enemies) →
		# the missile flies its heading and detonates harmlessly at fuse.
		if not targets.is_empty() and m.has_method("assign_target"):
			m.assign_target(targets[i % targets.size()])
		parent.call_deferred("add_child", m)
		if ship.has_method("_secondary_muzzle"):
			ship._secondary_muzzle(wpos)
		await ship.get_tree().process_frame          # 1-frame pause between each


# World position of the L or R wing-launch marker (falls back to the ship origin).
func _wing_pos(ship, right: bool) -> Vector2:
	var path: String = "Ship/LaunchWingR" if right else "Ship/LaunchWingL"
	var mk = ship.get_node_or_null(path)
	if mk != null and mk is Node2D:
		return (mk as Node2D).global_position
	return ship.global_position


# Live enemies sorted nearest-first to the ship; bulwark-shielded skipped. Distinct
# assignment falls out of round-robin over this list (1 enemy → all chase it).
func _sorted_targets(ship) -> Array:
	var out: Array = []
	for e in ship.get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if e.has_meta("bulwark_shielded"):
			continue
		out.append(e)
	var sp: Vector2 = ship.global_position
	out.sort_custom(func(a, b): return sp.distance_squared_to(a.global_position) < sp.distance_squared_to(b.global_position))
	return out


# Editor DPS surrogate: missiles × per-missile damage.
func effective_damage(at_mark: int) -> int:
	return _missiles_at_mark(at_mark) * base_damage
