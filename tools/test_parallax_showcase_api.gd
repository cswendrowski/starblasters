extends SceneTree

# WP1 API test for the Parallax V4 Showcase (Roman 2026-07-06). Instances the
# production backdrop_coordinator and exercises the new engine knobs:
#   - regenerate(seed) determinism (same seed = identical planet + rock layout)
#   - regenerate(other) differs
#   - apply_lateral moves layer offsets ONLY when lateral_strength > 0
#   - get_dominant_color() returns a non-white color for a seeded planet
#     (headless may not fully init shaders — asserts non-crash + fallback path).
# Run:
#   godot --headless --path . -s tools/test_parallax_showcase_api.gd

const SCENE := "res://scenes/parallax/backdrop_coordinator.tscn"
const StellarComposer = preload("res://scripts/parallax/stellar_composer.gd")
const StellarGameplay = preload("res://scripts/parallax/stellar_gameplay.gd")

var _fails: int = 0


func _init() -> void:
	process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS " + msg)
	else:
		_fails += 1
		print("  FAIL " + msg)


# Snapshot the deterministic composition: planet type + the near-stellar rocks'
# positions. Reads the layer's synchronous _objects array (NOT get_children,
# which lingers under queue_free between two synchronous regenerate calls).
func _snapshot(coord: Node) -> Dictionary:
	var out := {"planet": -1, "rocks": PackedVector2Array()}
	var planet := coord.get_node_or_null("LayerPlanet")
	if planet != null and is_instance_valid(planet.get("_planet_node")):
		out["planet"] = int(planet._planet_node.get_instance_id())
	# Use every stellar band's rock positions for a stronger determinism check.
	for name in ["LayerStellarFar", "LayerStellarMid", "LayerStellarNear"]:
		var lyr := coord.get_node_or_null(name)
		if lyr == null:
			continue
		for entry in lyr._objects:
			var n = entry.get("node")
			if is_instance_valid(n):
				out["rocks"].append(n.position)
	return out


# Total rock objects (asteroids + minis) on a stellar band's _objects array.
func _rock_count(coord: Node, name: String) -> int:
	var lyr := coord.get_node_or_null(name)
	if lyr == null:
		return 0
	return lyr._objects.size()


# Local position.y of every spawned planet-layer BODY (children exposing update_time — the
# procedural planet/star kits; excludes halos/dots/CanvasModulate). Used to check bp=0 stasis.
func _body_ys(pl: Node) -> Array:
	var out := []
	for c in pl.get_children():
		if c.has_method("update_time"):
			out.append(c.position.y)
	return out


# position.y of the registered per-body-parallax nodes (bp > 0 path).
func _reg_body_ys(pl: Node) -> Array:
	var out := []
	for b in pl._parallax_bodies:
		var n = b["node"]
		if is_instance_valid(n):
			out.append(n.position.y)
	return out


func _floats_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(a[i], b[i]):
			return false
	return true


# True when the ColorRect runs a ShaderMaterial whose shader path contains `frag`.
func _is_shader(cr: ColorRect, frag: String) -> bool:
	var m = cr.material
	return m is ShaderMaterial and m.shader != null and String(m.shader.resource_path).find(frag) >= 0


# A minimal gameplay descriptor (StellarGameplay.compute_poi_stellar input) for a plain combat node
# in a synthetic 4-POI row. Mirrors the lab's _synth_row_pois shape.
func _gp_desc(run_seed: int, row: int, sectors: int) -> Dictionary:
	var pois: Array = []
	for i in 4:
		pois.append({"id": "s0_r%d_p%d" % [row, i], "pos_x": 160.0 + float(i) * 64.0})
	var idx: int = abs(run_seed) % pois.size()
	return {
		"id": String(pois[idx]["id"]),
		"row": row,
		"pos_x": float(pois[idx]["pos_x"]),
		"row_end_x": 448.0,
		"hazard_subtype": "",
		"belt_adjacent": false,
		"sectors_cleared": sectors,
		"run_seed": run_seed,
		"row_pois": pois,
	}


func _rocks_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


func _run() -> void:
	var mus = get_root().get_node_or_null("Music")
	if mus != null:
		mus.free()

	var ps := load(SCENE) as PackedScene
	_ck(ps != null, "coordinator scene loads")
	var coord = ps.instantiate()
	# Force asteroids ON so the determinism check has rocks to compare.
	coord.force_asteroids = true
	coord.forced_planet_idx = 3  # GasPlanet — a get_colors kit for the dominant sample
	get_root().add_child(coord)

	# --- determinism: same seed twice → identical composition ---
	coord.regenerate(12345)
	var snap_a := _snapshot(coord)
	coord.regenerate(12345)
	var snap_b := _snapshot(coord)
	_ck(snap_a["rocks"].size() > 0, "rocks spawned (%d)" % snap_a["rocks"].size())
	_ck(_rocks_equal(snap_a["rocks"], snap_b["rocks"]), "regenerate(12345) twice = identical rock layout")

	# --- different seed → different composition ---
	coord.regenerate(999)
	var snap_c := _snapshot(coord)
	_ck(not _rocks_equal(snap_a["rocks"], snap_c["rocks"]), "regenerate(999) differs from 12345")

	# --- lateral parallax: offsets move ONLY when lateral_strength > 0 ---
	var near := coord.get_node_or_null("LayerStellarNear")
	# Inert first: strength 0, input full, tick — offset.x must stay 0.
	coord.lateral_strength = 0.0
	coord.set_lateral_input(1.0)
	near.offset.x = 0.0
	for _i in 30:
		coord._process(0.016)
	_ck(is_equal_approx(near.offset.x, 0.0), "lateral_strength=0 → offset.x stays 0 (%.3f)" % near.offset.x)

	# Active: strength > 0, input full, tick — offset.x must move.
	coord.lateral_strength = 28.0
	coord.set_lateral_input(1.0)
	for _i in 60:
		coord._process(0.016)
	_ck(absf(near.offset.x) > 0.5, "lateral_strength>0 → offset.x moved (%.3f)" % near.offset.x)

	# --- dominant color: non-white for a seeded planet (or documented fallback) ---
	var planet := coord.get_node_or_null("LayerPlanet")
	var dom: Color = planet.get_dominant_color()
	var non_white := not (is_equal_approx(dom.r, 1.0) and is_equal_approx(dom.g, 1.0) and is_equal_approx(dom.b, 1.0))
	# Headless may not fully init the planet shader's palette; get_dominant_color
	# then returns the per-type FALLBACK_TINT (also non-white for idx 3). Either
	# way a non-white result confirms the sampler + fallback path runs.
	_ck(non_white, "get_dominant_color() returns non-white (%s)" % dom)

	# ─── WP3: composer fallback + palette authority ──────────────────────────
	coord.lateral_strength = 0.0
	coord.set_lateral_input(0.0)

	# (d) flags-off run: layer CanvasModulate must match the pre-WP3 constants.
	# Far layer is brightness 0.2 / contrast 0.0 → collapses to (0.1,0.1,0.1)
	# regardless of the per-planet tint (review §2b). Asserts the inert path is
	# byte-identical with all new flags off.
	coord.use_composer_fallback = false
	coord.use_palette = false
	coord.use_dominant_grade = false
	coord.forced_kind = ""
	coord.forced_planet_idx = 3
	coord.regenerate(555)
	var far := coord.get_node_or_null("LayerStellarFar")
	var far_cm := far.get_node_or_null("CanvasModulate") as CanvasModulate
	_ck(far_cm != null and far_cm.color.is_equal_approx(Color(0.1, 0.1, 0.1)),
		"flags-off: far CanvasModulate == (0.1,0.1,0.1) (%s)" % (far_cm.color if far_cm else "no CM"))

	# (a) composer determinism: same seed twice → identical composed dict + rocks.
	coord.use_composer_fallback = true
	coord.forced_planet_idx = -1     # let the composer pick
	coord.forced_kind = "asteroid"   # guarantees rocks to compare
	coord.regenerate(4242)
	var comp_a: Dictionary = coord.last_stellar.duplicate(true)
	var snap_ca := _snapshot(coord)
	coord.regenerate(4242)
	var comp_b: Dictionary = coord.last_stellar.duplicate(true)
	var snap_cb := _snapshot(coord)
	_ck(String(comp_a.get("kind", "")) == "asteroid", "composer forced_kind honored (%s)" % comp_a.get("kind"))
	_ck(int(comp_a["planet_idx"]) == int(comp_b["planet_idx"])
			and int(comp_a["planet_seed"]) == int(comp_b["planet_seed"])
			and bool(comp_a["has_asteroids"]) == bool(comp_b["has_asteroids"])
			and String(comp_a["nebula_band"]) == String(comp_b["nebula_band"]),
		"composer regenerate(4242) twice = identical composed dict")
	_ck(snap_ca["rocks"].size() > 0 and _rocks_equal(snap_ca["rocks"], snap_cb["rocks"]),
		"composer regenerate(4242) twice = identical rock layout (%d rocks)" % snap_ca["rocks"].size())

	# (b) variety across 40 seeds: >=3 kinds, >=1 asteroid, >=1 nebula.
	var kinds := {}
	var any_ast := false
	var any_neb := false
	for s in 40:
		var r := RandomNumberGenerator.new()
		r.seed = 1000 + s
		var st: Dictionary = StellarComposer.compose(r, {})
		kinds[String(st.get("kind", ""))] = true
		if bool(st.get("has_asteroids", false)):
			any_ast = true
		if String(st.get("nebula_band", "")) != "":
			any_neb = true
	_ck(kinds.size() >= 3, "composer 40 seeds → >=3 distinct kinds (%d: %s)" % [kinds.size(), kinds.keys()])
	_ck(any_ast, "composer 40 seeds → >=1 has_asteroids")
	_ck(any_neb, "composer 40 seeds → >=1 nebula band")

	# (c) + (e): use_palette populates a full palette + tints the star/streak authorities.
	coord.use_palette = true
	coord.forced_kind = "planet"
	coord.forced_planet_idx = 3
	coord.regenerate(77)
	var pal: Dictionary = coord.palette
	_ck(pal.get("key") is Color, "palette.key is Color")
	_ck(pal.get("accent") is Color, "palette.accent is Color")
	_ck(pal.get("dust") is Color, "palette.dust is Color")
	_ck(pal.get("deep") is Color, "palette.deep is Color")
	var acc: Color = pal.get("accent", Color.WHITE)
	var acc_white := is_equal_approx(acc.r, 1.0) and is_equal_approx(acc.g, 1.0) and is_equal_approx(acc.b, 1.0)
	_ck(not acc_white, "palette.accent non-white after populate (%s)" % acc)
	var stars := coord.get_node_or_null("LayerStars")
	_ck(stars.key_tint != Color.WHITE, "use_palette → stars key_tint set (%s)" % stars.key_tint)
	var streaks := coord.get_node_or_null("LayerStreaks")
	_ck(streaks.streak_tint != Color.WHITE, "use_palette → streak_tint set (%s)" % streaks.streak_tint)

	# ─── WP5 item 4: asteroid count gradient (far > mid > near) ───────────────
	coord.use_palette = false
	coord.use_composer_fallback = true
	coord.forced_planet_idx = -1
	coord.forced_kind = "asteroid"   # guarantees rocks in every band
	# Baseline ONE with a fixed seed, then the same seed under (2,1,0.7): only the
	# per-depth multiplier differs (composition + density identical), so counts scale cleanly.
	coord.asteroid_layer_mult = Vector3.ONE
	coord.regenerate(31337)
	var far0 := _rock_count(coord, "LayerStellarFar")
	var mid0 := _rock_count(coord, "LayerStellarMid")
	var near0 := _rock_count(coord, "LayerStellarNear")
	coord.asteroid_layer_mult = Vector3(2.0, 1.0, 0.7)
	coord.regenerate(31337)
	var far1 := _rock_count(coord, "LayerStellarFar")
	var mid1 := _rock_count(coord, "LayerStellarMid")
	var near1 := _rock_count(coord, "LayerStellarNear")
	_ck(far1 > mid1 and mid1 > near1, "asteroid_layer_mult(2,1,0.7) → far>mid>near (%d>%d>%d)" % [far1, mid1, near1])
	_ck(far1 > far0, "mult amplifies far band (%d > %d)" % [far1, far0])
	_ck(near1 < near0, "mult thins near band (%d < %d)" % [near1, near0])
	_ck(mid1 == mid0, "mult 1.0 leaves mid band unchanged (%d == %d)" % [mid1, mid0])
	coord.asteroid_layer_mult = Vector3.ONE

	# ─── WP5 item 5: star_mode present + both modes appear across 40 seeds ────
	var modes := {}
	for s in 40:
		var r := RandomNumberGenerator.new()
		r.seed = 2000 + s
		var st: Dictionary = StellarComposer.compose(r, {})
		modes[String(st.get("star_mode", ""))] = true
	_ck(modes.has("distant_star") and modes.has("near_star"),
		"composer 40 seeds → both star_modes appear (%s)" % str(modes.keys()))

	# ─── WP5 item 6: body_parallax 0 = static-relative, 1 = relative shift ────
	var pl := coord.get_node_or_null("LayerPlanet")
	coord.forced_kind = "system"     # spawns several bodies of differing size
	coord.forced_planet_idx = -1
	# bp=0: bodies move ONLY with the layer offset — local position.y unchanged after scroll.
	pl.body_parallax = 0.0
	coord.regenerate(8080)
	var ys_before := _body_ys(pl)
	_ck(pl._parallax_bodies.is_empty(), "body_parallax=0 → no bodies registered (short-circuit)")
	for _i in 40:
		coord._process(0.016)
	var ys_after := _body_ys(pl)
	var bp0_static := ys_before.size() > 0 and _floats_equal(ys_before, ys_after)
	_ck(bp0_static, "body_parallax=0 → body local pos.y static (moves only with layer)")
	# bp=1: same seed/bodies, but now each drifts by its own depth_mult — relative Δy differ.
	pl.body_parallax = 1.0
	coord.regenerate(8080)
	_ck(pl._parallax_bodies.size() >= 2, "body_parallax=1 → >=2 bodies registered (%d)" % pl._parallax_bodies.size())
	var reg_before := _reg_body_ys(pl)
	for _i in 40:
		coord._process(0.016)
	var reg_after := _reg_body_ys(pl)
	# Δy per body must NOT be uniform (differing depth → relative positions changed).
	var deltas := PackedFloat32Array()
	for i in reg_before.size():
		deltas.append(reg_after[i] - reg_before[i])
	var any_diff := false
	for i in deltas.size():
		if not is_equal_approx(deltas[i], deltas[0]):
			any_diff = true
			break
	_ck(any_diff and deltas.size() >= 2, "body_parallax=1 → per-body Δy differ (relative shift)")
	pl.body_parallax = 0.0
	coord.forced_kind = ""

	# ─── WP5 item 2: pixel_snap true/false both boot + scroll without error ───
	pl.pixel_snap = true
	coord.regenerate(4321)
	var oy_t: float = pl.offset.y
	for _i in 10:
		coord._process(0.016)
	_ck(not is_equal_approx(pl.offset.y, oy_t), "pixel_snap=true boots + scrolls (%.3f)" % pl.offset.y)
	pl.pixel_snap = false
	coord.regenerate(4321)
	var oy_f: float = pl.offset.y
	for _i in 10:
		coord._process(0.016)
	_ck(not is_equal_approx(pl.offset.y, oy_f), "pixel_snap=false boots + scrolls (%.3f)" % pl.offset.y)

	# ─── WP8: star FX tiers (sparkle / halo / clamp) ──────────────────────────
	pl.body_parallax = 0.0
	coord.use_palette = false
	coord.use_composer_fallback = true
	coord.forced_planet_idx = -1
	coord.forced_kind = "system"     # always spawns a star (idx 8) at frac 0

	# (a) star_fx OFF (default) → the star is a PixelPlanets kit, no star-fx container.
	pl.star_fx = false
	coord.regenerate(1212)
	var off_kit := false
	var off_tier := false
	for c in pl.get_children():
		if c.has_method("update_time"):
			off_kit = true
		if c.has_meta("star_tier"):
			off_tier = true
	_ck(off_kit and not off_tier, "star_fx=false → PixelPlanets kit spawns, no StarFx container")

	# (c) halo size formula spot-checks (call before ON so it reads the default mult 1.0).
	_ck(absf(pl._star_halo_size(32.0) - 90.0) < 0.01, "halo size @32px == 90 (%.2f)" % pl._star_halo_size(32.0))
	_ck(absf(pl._star_halo_size(120.0) - 336.0) < 0.01, "halo size @120px == 336 (%.2f)" % pl._star_halo_size(120.0))

	# (b) star_fx ON → find a sparkle-tier + a halo-tier star across seeds; no size exceeds the clamp.
	pl.star_fx = true
	var sparkle_found := false
	var sparkle_ok := false
	var halo_found := false
	var halo_ok := false
	var halo_sz_ok := false
	var clamp_ok := true
	for s in 60:
		coord.regenerate(3000 + s)
		for c in pl.get_children():
			if not c.has_meta("star_tier") or c.is_queued_for_deletion():
				continue
			var spx: float = float(c.get_meta("star_px"))
			if spx > pl.star_clamp_max + 0.01:
				clamp_ok = false
			var tier := String(c.get_meta("star_tier"))
			if tier == "sparkle" and not sparkle_found:
				sparkle_found = true
				var has_kit := false
				var has_rect := false
				var has_dot := false
				for gc in c.get_children():
					if gc.has_method("update_time"):
						has_kit = true
					if gc is ColorRect and String(gc.name).begins_with("StarSparkle") and _is_shader(gc, "sparkle_star"):
						has_rect = true
					# Star point: a ColorRect running the separable star_glint shader (round-3 fix).
					if gc is ColorRect and String(gc.name).begins_with("StarDot") and _is_shader(gc, "star_glint"):
						has_dot = true
				sparkle_ok = has_rect and has_dot and not has_kit
			elif tier == "halo" and not halo_found:
				halo_found = true
				var has_kit2 := false
				var halo_rect: ColorRect = null
				for gc in c.get_children():
					if gc.has_method("update_time"):
						has_kit2 = true
					if gc is ColorRect and String(gc.name).begins_with("StarHalo"):
						halo_rect = gc
				halo_ok = has_kit2 and halo_rect != null and _is_shader(halo_rect, "pixel_halo_glow")
				if halo_rect != null:
					halo_sz_ok = absf(halo_rect.size.x - pl._star_halo_size(spx)) < 1.0
		if sparkle_found and halo_found:
			break
	_ck(sparkle_found and sparkle_ok, "sparkle tier: sparkle ColorRect + StarDot, NO kit")
	_ck(halo_found and halo_ok, "halo tier: PixelPlanets kit + pixel_halo_glow StarHalo")
	_ck(halo_sz_ok, "halo node size ≈ lerp(90,336,t)×mult")
	_ck(clamp_ok, "no star body display size exceeds star_clamp_max")

	# (d) clear/regenerate leaves no live StarFx orphans; on = exactly one (system has one star).
	pl.star_fx = true
	coord.regenerate(4445)
	var live_on := 0
	for c in pl.get_children():
		if c.has_meta("star_tier") and not c.is_queued_for_deletion():
			live_on += 1
	_ck(live_on == 1, "star_fx on system → exactly 1 live StarFx container (%d)" % live_on)
	pl.star_fx = false
	coord.regenerate(4446)
	var live_off := 0
	for c in pl.get_children():
		if c.has_meta("star_tier") and not c.is_queued_for_deletion():
			live_off += 1
	_ck(live_off == 0, "star_fx off regenerate → no live StarFx orphans (%d)" % live_off)
	coord.forced_kind = ""

	# ─── WP11: StellarGameplay module + coordinator stellar_override ──────────
	# (a) determinism: same descriptor twice → identical dict; different node id → different seed.
	var d1 := _gp_desc(7777, 1, 3)
	var poi_a: Dictionary = StellarGameplay.compute_poi_stellar(d1)
	var poi_b: Dictionary = StellarGameplay.compute_poi_stellar(d1)
	_ck(int(poi_a["planet_seed"]) == int(poi_b["planet_seed"])
			and int(poi_a["planet_idx"]) == int(poi_b["planet_idx"])
			and String(poi_a["nebula_band"]) == String(poi_b["nebula_band"])
			and (poi_a["system"] as Array).size() == (poi_b["system"] as Array).size(),
		"compute_poi_stellar deterministic (same descriptor → identical dict)")
	var d_diff := d1.duplicate(true)
	d_diff["id"] = "s0_r1_pZ"
	var poi_c: Dictionary = StellarGameplay.compute_poi_stellar(d_diff)
	_ck(int(poi_c["planet_seed"]) != int(poi_a["planet_seed"]), "different node id → different planet_seed")

	# (b) exotic-star chance rises with sectors_cleared (monotone by construction, strictly over samples).
	var low_ex := 0
	var high_ex := 0
	for s in 300:
		if int(StellarGameplay.compute_poi_stellar(_gp_desc(9000 + s, 0, 0))["exotic_idx"]) >= 0:
			low_ex += 1
		if int(StellarGameplay.compute_poi_stellar(_gp_desc(9000 + s, 0, 16))["exotic_idx"]) >= 0:
			high_ex += 1
	_ck(high_ex > low_ex, "exotic-star chance rises with sectors_cleared (low %d < high %d)" % [low_ex, high_ex])

	# (d) gameplay star scales VARY across nodes (per-row intrinsic roll, item 4).
	var gp_scales := {}
	for s in 40:
		var st: Dictionary = StellarGameplay.compute_poi_stellar(_gp_desc(20000 + s * 13, s % 3, s % 5))
		var sysa: Array = st["system"]
		if not sysa.is_empty():
			gp_scales["%.4f" % float(sysa[0]["scale"])] = true
	_ck(gp_scales.size() >= 10, "gameplay star scales vary across 40 nodes (%d distinct)" % gp_scales.size())

	# (c) coordinator stellar_override: consumed ahead of Run.current_stellar; asteroid_base_color lands.
	coord.forced_kind = ""
	coord.use_composer_fallback = false
	coord.use_palette = false
	coord.forced_planet_idx = -1
	var ov_color := Color(0.20, 0.70, 0.90, 1.0)
	coord.stellar_override = {
		"planet_idx": 5, "planet_seed": 4242, "star_color": Color(1.0, 0.7, 0.2, 1.0),
		"has_asteroids": true, "asteroid_density": 1.5,
		"nebula_band": "", "nebula_tint": Color.WHITE, "moons": [], "system": [],
		"asteroid_base_color": ov_color,
	}
	coord.regenerate(2024)
	_ck(int(coord.last_stellar.get("planet_idx", -99)) == 5,
		"stellar_override consumed: last_stellar.planet_idx == 5 (%s)" % coord.last_stellar.get("planet_idx"))
	var near_ov := coord.get_node_or_null("LayerStellarNear")
	_ck((near_ov.get("asteroid_tint") as Color).is_equal_approx(ov_color),
		"override asteroid_base_color on near-band ramp (%s)" % near_ov.get("asteroid_tint"))
	# Clear → falls back off the override (Run.current_stellar empty in headless → asteroid_tint reverts).
	coord.stellar_override = {}
	coord.regenerate(2024)
	_ck(int(coord.last_stellar.get("planet_idx", -99)) != 5,
		"stellar_override cleared → last_stellar no longer the override dict")
	_ck(not (near_ov.get("asteroid_tint") as Color).is_equal_approx(ov_color),
		"stellar_override cleared → asteroid_tint reverts (%s)" % near_ov.get("asteroid_tint"))

	print("VERDICT: %s (%d checks failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
