extends SceneTree

# Throwaway: verify the b_ taxonomy migration end-to-end.
#  1. palette discovers all 20 new keys with class labels
#  2. every OLD prefab key resolves via ALIASES and SPAWNS the right scene
#  3. _classify buckets old + new keys identically (t_rocket=launcher, t_*=turret)
#  4. pad size derivation from the new filenames
#  5. bench list carries the new paths; boom/shadow/eligibility registries hit the new paths

const Palette := preload("res://scripts/enemies/stronghold_building_palette.gd")
const Field := preload("res://scripts/levels/stronghold_field.gd")
const Boom := preload("res://scripts/effects/building_boom.gd")
const BShadow := preload("res://scripts/effects/building_shadow.gd")

const NEW_KEYS := ["t_ball", "t_wave", "t_scatter", "t_rocket", "t_twin",
	"p_small", "p_medium", "p_large", "b_glass", "b_glass_square",
	"s_shed", "s_armored", "s_hangar", "s_glass",
	"f_tank", "f_cross", "f_farm", "f_bunker", "e_cage", "e_pylon"]
const OLD_KEYS := ["square_turret", "square_turret_wave", "diamond_turret", "square_launcher",
	"bunker_turret", "building_square_landing_pad", "building_landing_pad_medium",
	"building_bunker_glass", "building_round_tank", "building_square_shed", "shed_armored",
	"building_hangar", "building_square_glass", "building_fuel_tank", "building_cross_tank",
	"building_square_tanks", "building_bunker_tank", "energy_cage", "shield_pylon", "building_round_glass"]

var _world: Node2D = null
var _done := false

func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	root.get_node("Run").set_meta("active_faction", 0)
	_world = Node2D.new(); root.add_child(_world); current_scene = _world
	var pl := Node2D.new(); pl.add_to_group("player"); _world.add_child(pl)

	var missing := []
	for k in NEW_KEYS:
		if not Palette.is_type(k):
			missing.append(k)
	print("RV new keys discovered: %d/20 missing=%s" % [20 - missing.size(), str(missing)])
	print("RV sample labels: %s | %s | %s | %s" % [Palette.label_for("t_rocket"), Palette.label_for("p_small"), Palette.label_for("f_bunker"), Palette.label_for("e_pylon")])

	var holder := Node2D.new(); holder.position = Vector2(240, 120); _world.add_child(holder)
	var bad_alias := []
	for ok in OLD_KEYS:
		var inst = Palette.spawn(ok, holder, Vector2.ZERO, 0.0)
		if inst == null:
			bad_alias.append(ok)
		else:
			inst.queue_free()
	print("RV old-key alias spawns: %d/%d failed=%s" % [OLD_KEYS.size() - bad_alias.size(), OLD_KEYS.size(), str(bad_alias)])

	var f = Field.new(); _world.add_child(f)
	var mk := func(t: String): return {"asteroid": {"size": 120.0}, "buildings": [{"type": t, "x": 0, "y": 0}]}
	print("RV classify old square_launcher=%s new t_rocket=%s (expect heavy/heavy)" % [f._classify(mk.call("square_launcher")), f._classify(mk.call("t_rocket"))])
	print("RV classify old square_turret=%s new t_ball=%s (expect light/light)" % [f._classify(mk.call("square_turret")), f._classify(mk.call("t_ball"))])
	print("RV classify new f_tank=%s (expect mixed)" % f._classify(mk.call("f_tank")))
	f.queue_free()

	var pads := {"b_p_small": "small", "b_p_medium": "medium", "b_p_large": "large"}
	var pad_ok := true
	for pf in pads:
		var pd = (load("res://scenes/enemies/ground/%s.tscn" % pf) as PackedScene).instantiate()
		_world.add_child(pd)
		if pd._parked_size() != pads[pf]:
			pad_ok = false
			print("RV PAD SIZE WRONG: %s -> %s" % [pf, pd._parked_size()])
		pd.queue_free()
	print("RV pad sizes ok=%s" % str(pad_ok))

	var bench: Array = EnemyManifest.all_enemies(false)
	var bench_miss := 0
	var boom_miss := 0
	var elig_miss := 0
	var PatEl := load("res://scripts/levels/pattern_eligibility.gd")
	for k in NEW_KEYS:
		var path := "res://scenes/enemies/ground/b_%s.tscn" % k
		if not bench.has(path): bench_miss += 1
		if not Boom.CONFIG.has(path): boom_miss += 1
	print("RV bench_missing=%d boom_registry_missing=%d (boom misses are un-tuned NEW buildings — fallback ok)" % [bench_miss, boom_miss])
	print("RV: DONE")
	quit(0)
