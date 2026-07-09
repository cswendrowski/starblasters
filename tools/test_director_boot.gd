extends SceneTree

# Synchronous boot test for the Corporate Director (Roman 2026-07-06). Instantiates the real boss, checks
# the body/parts/HP wiring, the wing-cannon beams, the asteroid-style knock-away, maneuver eligibility, the
# friendly-fire missile AoE, and director.inject_live_enemy — without ticking real time (see
# test_director_run.gd for the live maneuver soak). Run:
#   godot --headless --path . -s tools/test_director_boot.gd

const SCENE := "res://scenes/enemies/factions/corporate/boss_c_director.tscn"
const MissileSalvo = preload("res://scripts/effects/missile_salvo.gd")
const DirectorScript = preload("res://scripts/levels/director.gd")
const WingScript = preload("res://scripts/enemies/bosses/boss_c_director_wing.gd")

var _fails: int = 0


func _init() -> void:
	process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   " + msg)
	else:
		_fails += 1
		print("  FAIL " + msg)


func _run() -> void:
	var mus = get_root().get_node_or_null("Music")
	if mus != null:
		mus.free()
	var world := Node2D.new()
	world.add_to_group("bullet_world")
	get_root().add_child(world)

	var ps := load(SCENE) as PackedScene
	_ck(ps != null, "scene loads")
	var boss = ps.instantiate()
	get_root().add_child(boss)
	boss.start(Vector2(240, 400))

	# --- structure: the FIGHT IS THE SECTIONS (hull is pass-through) ---
	_ck(boss is Area2D, "root is Area2D")
	_ck(boss.is_in_group("enemies"), "in 'enemies' group")
	_ck(not boss.monitorable, "hull is pass-through (monitorable=false) — sections are the targets")
	_ck(boss._sections.size() == 7, "7 body sections built from the Collision* polygons")
	_ck(boss.live_parts().size() == 9, "9 destructible parts (7 sections + 2 wing cannons)")
	var poly_ok := true
	for s in boss._sections:
		var hp := false
		for c in s.get_children():
			if c is CollisionPolygon2D: hp = true
		if not (hp and s.is_in_group("enemies")): poly_ok = false
	_ck(poly_ok, "each section wraps a reparented polygon + is in 'enemies'")
	_ck(int(boss.max_health) > 0 and int(boss.health) == int(boss.max_health), "HP bar seeded from parts (%d)" % int(boss.max_health))

	# --- wing cannons (2 × 100hp beam parts) ---
	var wings_100 := true
	var wings_have_beam := true
	for w in boss._wings:
		if int(w.max_hp) != 100:
			wings_100 = false
		if w._beam == null:
			wings_have_beam = false
	_ck(boss._wings.size() == 2, "2 wing cannons built")
	_ck(wings_100, "each wing = 100hp")
	_ck(wings_have_beam, "each wing has a BeamEmitter")

	# --- knock-away on a SECTION hit (asteroid-style) ---
	boss._vel = Vector2.ZERO
	boss._knock_grace_t = 0.0
	(boss._sections[0]).take_hit(1)
	_ck(boss._vel.y < -1.0, "section hit knocks the boss up (_vel.y=%.1f)" % boss._vel.y)

	# --- fender destroy disables THAT side's cannon + muzzle ---
	var fl = _find_section(boss, "fender_l")
	if fl != null: fl.take_hit(999999)
	_ck(not boss._cannon_l and not boss._muzzle_l, "fender_l destroyed → L cannon + L muzzle disabled")
	_ck(boss._cannon_r and boss._muzzle_r, "R cannon + R muzzle still armed")
	_ck(_overlay_vis(boss, "DestroyedFenderL"), "DestroyedFenderL overlay revealed")

	# --- hood/missile is a 2-STAGE section: hood first, then missiles ---
	var hm = _find_section(boss, "hood_missile")
	if hm != null: hm.take_hit(999999)   # stage 0 → hood
	_ck(boss._missiles_ok and hm != null and not hm.is_destroyed(), "hood down but missiles still live (stage 2 pending)")
	_ck(_overlay_vis(boss, "DestroyedHood"), "DestroyedHood revealed")
	if hm != null: hm.take_hit(999999)   # stage 1 → missiles
	_ck(not boss._missiles_ok and hm != null and hm.is_destroyed(), "missiles disabled after hood (stage 2)")
	_ck(_overlay_vis(boss, "DestroyedMissile"), "DestroyedMissile revealed")

	# --- wing cannon destroy → hidden + DestroyedCannon overlay + laser_lane gate ---
	for w in boss._wings.duplicate():
		if is_instance_valid(w): w.take_hit(999999)
	_ck(not boss._wings_alive(), "wings dead → laser_lane falls back")
	var hidden_ok := true
	for w in boss._wings:
		if is_instance_valid(w) and w.visible:
			hidden_ok = false
	_ck(hidden_ok, "destroyed wing cannon is HIDDEN")
	var overlay_ok: bool = boss._wing_overlays.size() == 2
	for ov in boss._wing_overlays.values():
		if not (is_instance_valid(ov) and ov.visible):
			overlay_ok = false
	_ck(overlay_ok, "DestroyedCannonL/R overlays revealed on wing death")
	_ck(boss.MANEUVER_NAMES.size() == 6, "6 maneuver names")

	# --- friendly-fire missile AoE (hits player AND enemies, minus the owner) ---
	var pl := HitPlayer.new(); pl.add_to_group("player"); pl.position = Vector2(50, 50); get_root().add_child(pl)
	var en := HitEnemy.new(); en.add_to_group("enemies"); en.position = Vector2(50, 50); get_root().add_child(en)
	var own := Node2D.new(); get_root().add_child(own)
	var own_child := HitEnemy.new(); own_child.add_to_group("enemies"); own_child.position = Vector2(50, 50); own.add_child(own_child)
	MissileSalvo.detonate_aoe(Vector2(50, 50), 30.0, 1, self, null, true, own)
	_ck(pl.hits == 1, "FF AoE damages the player")
	_ck(en.hits == 1, "FF AoE damages a nearby enemy")
	_ck(own_child.hits == 0, "FF AoE spares the owner's own child")

	# --- inject_live_enemy wiring ---
	var d = DirectorScript.new()
	get_root().add_child(d)
	var spawned := [0]
	d.enemy_spawned.connect(func(_p, _b): spawned[0] += 1)
	var stub := InjectStub.new(); stub.add_to_group("enemies"); get_root().add_child(stub)
	d.inject_live_enemy(stub)
	_ck(spawned[0] == 1, "inject_live_enemy emits enemy_spawned")
	_ck(bool(stub.get_meta("_injected", false)), "inject marks the enemy")

	print("VERDICT: %s (%d checks failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


# --- helpers ----------------------------------------------------------------

func _find_section(boss, id: String):
	for s in boss._sections:
		if s.section_id == id:
			return s
	return null


func _overlay_vis(boss, nm: String) -> bool:
	var ov = boss.find_child(nm, true, false)
	return ov != null and ov.visible


# --- probes -----------------------------------------------------------------

class HitPlayer extends Area2D:
	var hits: int = 0
	func take_damage(_d: int = 1) -> void: hits += 1

class HitEnemy extends Area2D:
	var hits: int = 0
	func take_hit(_d: int = 1) -> bool: hits += 1; return false

class InjectStub extends Node2D:
	signal died(value: int)
	var bounty_value: int = 7
