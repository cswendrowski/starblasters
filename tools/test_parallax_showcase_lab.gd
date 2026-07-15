extends SceneTree

# Headless test for the Parallax Showcase lab (WP2 + WP4). Instances the lab, applies PROPOSED then
# CURRENT, spot-checks ~6 properties round-trip to the table values across all destination files,
# asserts the Copy GDScript block references only real properties, and covers the WP4 composition +
# palette surface (forced_kind round-trip, use_palette round-trip, palette swatches populated,
# Copy block carries use_palette / use_composer_fallback).
#
# DETERMINISM: Roman's persisted user://tuners/parallax_showcase.json may have sections toggled off
# (e.g. lateral:false), which would skew the preset assertions (the OFF sections hold CURRENT). The
# test moves that JSON aside before building the lab and restores it after, AND force_all_sections_on()
# so every section master is ON regardless. Passes with the real JSON present OR absent.
# Run: godot --path . --headless --script tools/test_parallax_showcase_lab.gd

const LabScript = preload("res://scripts/dev/parallax_showcase.gd")
const CONFIG_PATH := "user://tuners/parallax_showcase.json"

var _fails: Array = []
var _stashed := false


func _init() -> void:
	call_deferred("_run")


func _stash_json() -> void:
	# Move the user's persisted config aside so _load() starts from defaults.
	if FileAccess.file_exists(CONFIG_PATH):
		var bak := CONFIG_PATH + ".testbak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
		var err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(CONFIG_PATH),
			ProjectSettings.globalize_path(bak))
		_stashed = err == OK


func _restore_json() -> void:
	if not _stashed:
		return
	var bak := CONFIG_PATH + ".testbak"
	# The lab auto-saves on close; the test never closed it, but be defensive.
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(bak),
		ProjectSettings.globalize_path(CONFIG_PATH))
	_stashed = false


func _run() -> void:
	_stash_json()

	var lab = LabScript.new()
	get_root().add_child(lab)
	# Force every section master ON so a persisted toggle can't skew preset assertions.
	lab.force_all_sections_on()
	# Let _ready + the two deferred frames + apply run.
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	lab.force_all_sections_on()   # re-assert after _ready's initial apply

	var bd = lab._backdrop
	if bd == null or not is_instance_valid(bd):
		_fail("backdrop not built")
		_finish()
		return
	var ln = bd.get_node_or_null("LayerStellarNear")
	var lp = bd.get_node_or_null("LayerPlanet")
	var ls = bd.get_node_or_null("LayerStreaks")
	var stars = bd.get_node_or_null("LayerStars")

	# Lab must ALWAYS drive the composer fallback (WP4).
	_expect_bool("lab sets use_composer_fallback", bd.get("use_composer_fallback"), true)

	# ── PROPOSED ─────────────────────────────────────────────────────────────
	lab._apply_preset(LabScript.PROPOSED)
	await process_frame
	await process_frame
	_expect("PROPOSED near_rate", ln.get("scroll_rate"), 1.8)                 # layer_base export
	_expect("PROPOSED near brightness", ln.get("brightness"), 0.95)           # layer_base export
	_expect("PROPOSED rock_size_pow", ln.get("asteroid_size_pow"), 1.6)       # layer_stellar export
	_expect("PROPOSED lateral_strength", bd.get("lateral_strength"), 28.0)    # coordinator export
	_expect_bool("PROPOSED use_dominant_grade", bd.get("use_dominant_grade"), true)
	_expect("PROPOSED streak_alpha", ls.get("streak_alpha"), 0.35)            # layer_streaks export
	_expect("PROPOSED planet lateral_wander", lp.get("lateral_wander"), 0.3)  # layer_planet export
	_expect_bool("PROPOSED use_palette", bd.get("use_palette"), true)         # WP4 coordinator export
	_expect_bool("PROPOSED stars key_tint set", stars.get("key_tint") != Color.WHITE, true)

	# Palette swatches populated after a regenerate (coordinator.palette → ColorRects).
	var key_rect = lab._pal_swatches.get("key")
	_ck(key_rect != null and key_rect.color != Color.BLACK, "palette swatch 'key' non-black after regen")
	var acc_rect = lab._pal_swatches.get("accent")
	_ck(acc_rect != null and acc_rect.color != Color.BLACK, "palette swatch 'accent' non-black after regen")

	# WP7: new engine knobs land on their destinations under PROPOSED.
	_expect("PROPOSED body_parallax on LayerPlanet", lp.get("body_parallax"), 1.0)   # layer_planet export
	var alm: Vector3 = bd.get("asteroid_layer_mult")                                  # coordinator export
	_ck(alm.is_equal_approx(Vector3(2.0, 1.0, 0.7)),
		"PROPOSED asteroid_layer_mult == (2,1,0.7) (%s)" % alm)
	# WP9: star FX tiers land on LayerPlanet under PROPOSED.
	_expect_bool("PROPOSED star_fx on LayerPlanet", lp.get("star_fx"), true)      # layer_planet export
	_expect("PROPOSED star_sparkle_max", lp.get("star_sparkle_max"), 32.0)
	_expect("PROPOSED star_clamp_max", lp.get("star_clamp_max"), 120.0)
	_expect("PROPOSED halo_scale_mult", lp.get("halo_scale_mult"), 1.0)
	_expect_bool("PROPOSED star_fx _vals value true", lab._vals.get("star_fx"), true)

	# pixel_snap OFF under PROPOSED -> viewport snap OFF (the property acts viewport-wide).
	var sub7 = lab._backdrop_sub
	_ck(sub7 != null and is_instance_valid(sub7), "backdrop SubViewport exists (WP7)")
	if sub7 != null:
		_expect_bool("PROPOSED pixel_snap OFF -> viewport snap OFF", sub7.snap_2d_transforms_to_pixel, false)
	_expect_bool("PROPOSED pixel_snap value false", lab._vals.get("pixel_snap"), false)

	# ── CURRENT ──────────────────────────────────────────────────────────────
	lab._apply_preset(LabScript.CURRENT)
	await process_frame
	await process_frame
	_expect("CURRENT near_rate", ln.get("scroll_rate"), 1.2)
	_expect("CURRENT near brightness", ln.get("brightness"), 0.6)
	_expect("CURRENT rock_size_pow", ln.get("asteroid_size_pow"), 3.0)
	_expect("CURRENT lateral_strength", bd.get("lateral_strength"), 0.0)
	_expect_bool("CURRENT use_dominant_grade", bd.get("use_dominant_grade"), false)
	_expect("CURRENT streak_alpha", ls.get("streak_alpha"), 0.6)
	_expect_bool("CURRENT use_palette", bd.get("use_palette"), false)
	# WP7 CURRENT: knobs revert to their inert defaults.
	_expect("CURRENT body_parallax", lp.get("body_parallax"), 0.0)
	var alm_cur: Vector3 = bd.get("asteroid_layer_mult")
	_ck(alm_cur.is_equal_approx(Vector3.ONE), "CURRENT asteroid_layer_mult == ONE (%s)" % alm_cur)
	_expect_bool("CURRENT pixel_snap value true", lab._vals.get("pixel_snap"), true)
	if sub7 != null:
		_expect_bool("CURRENT pixel_snap ON -> viewport snap ON", sub7.snap_2d_transforms_to_pixel, true)
	# WP9 CURRENT: star FX off, thresholds back at the inert defaults.
	_expect_bool("CURRENT star_fx off", lp.get("star_fx"), false)
	_expect("CURRENT star_sparkle_max", lp.get("star_sparkle_max"), 32.0)
	_expect("CURRENT star_clamp_max", lp.get("star_clamp_max"), 120.0)
	_expect("CURRENT halo_scale_mult", lp.get("halo_scale_mult"), 1.0)

	# ── WP4: forced_kind round-trip (Asteroid) ───────────────────────────────
	lab._on_kind_selected(3)   # KIND_VALUES[3] == "asteroid"
	await process_frame
	await process_frame
	_ck(String(lab._vals.get("forced_kind", "")) == "asteroid", "kind pick → _vals.forced_kind == asteroid")
	_ck(String(bd.get("forced_kind")) == "asteroid", "kind pick → coordinator.forced_kind == asteroid")
	_ck(String((bd.get("last_stellar") as Dictionary).get("kind", "")) == "asteroid",
		"kind pick → composed last_stellar.kind == asteroid")
	# Back to Auto.
	lab._on_kind_selected(0)
	await process_frame
	_ck(String(bd.get("forced_kind")) == "", "Auto → coordinator.forced_kind == \"\"")

	# ── Copy block: every emitted property name must exist on its target ──────
	# Emit with a forced kind so forced_kind appears in the block.
	lab._on_kind_selected(1)   # System
	await process_frame
	var block: String = lab._copy_snippet()
	# forced_planet_idx is a real coordinator export but a dev-only comparison control, not shipped
	# in the Copy block — so it's checked as a property below (not required in the block text).
	_check_names(block, bd, ["drift_speed", "lateral_strength", "use_dominant_grade", "warp_streak_count",
		"warp_streak_speed", "use_composer_fallback", "use_palette", "forced_kind", "asteroid_layer_mult"])
	if not ("forced_planet_idx" in bd):
		_fail("property 'forced_planet_idx' NOT on coordinator")
	_check_names(block, ln, ["scroll_rate", "brightness", "contrast", "nebula_alpha", "drift_variance", "asteroid_min_size", "asteroid_max_size", "asteroid_size_pow"])
	_check_names(block, lp, ["scroll_rate", "lateral_wander", "body_parallax", "pixel_snap",
		"star_fx", "star_sparkle_max", "star_clamp_max", "halo_scale_mult",
		"halo_mid_alpha", "halo_core_intensity",
		"sparkle_decay", "sparkle_scale_mult", "dot_size_frac", "dot_hdr"])
	_check_names(block, ls, ["streak_speed", "streak_alpha", "streak_count", "streak_speed_variance_min", "streak_tint"])
	_check_names(block, stars, ["key_tint"])
	# WP7: HD raster is a lab-only render mode — it must NEVER appear in the shipped Copy block.
	if block.contains("hd_raster"):
		_fail("Copy block leaks lab-only 'hd_raster'")

	# ── WP7: HD raster mode — assert the SubViewport render path in both states ──
	# Default ON = combat-accurate: 1920x1080 render target, 480x270 logical override, stretch.
	lab._apply_hd_raster(true)
	await process_frame
	_ck(sub7.size == Vector2i(1920, 1080), "HD raster ON -> viewport size 1920x1080 (%s)" % sub7.size)
	_ck(sub7.size_2d_override == Vector2i(480, 270), "HD raster ON -> size_2d_override 480x270 (%s)" % sub7.size_2d_override)
	_ck(sub7.size_2d_override_stretch, "HD raster ON -> size_2d_override_stretch true")
	# OFF = today's 480x270 lab view (override disabled).
	lab._apply_hd_raster(false)
	await process_frame
	_ck(sub7.size == Vector2i(480, 270), "HD raster OFF -> viewport size 480x270 (%s)" % sub7.size)
	_ck(not sub7.size_2d_override_stretch, "HD raster OFF -> size_2d_override_stretch false")
	lab._apply_hd_raster(true)   # restore default

	# ── WP6 Item 1: WorldEnvironment inside the backdrop viewport ─────────────
	var sub = lab._backdrop_sub
	_ck(sub != null and is_instance_valid(sub), "backdrop SubViewport exists")
	var we: WorldEnvironment = null
	if sub != null:
		for c in sub.get_children():
			if c is WorldEnvironment:
				we = c
				break
	_ck(we != null, "WorldEnvironment node inside backdrop viewport")
	if we != null:
		var env: Environment = we.environment
		_ck(env != null, "WorldEnvironment has an Environment")
		if env != null:
			_expect_bool("glow_enabled (default bloom ON)", env.glow_enabled, true)
			_expect("glow_intensity", env.glow_intensity, 0.8)
			_expect("glow_strength", env.glow_strength, 0.75)
			_expect("glow_blend_mode", env.glow_blend_mode, 1)
			_expect("glow_hdr_threshold", env.glow_hdr_threshold, 1.5)
		# Bloom toggle flips glow_enabled.
		lab._set_bloom(false)
		_expect_bool("bloom OFF → glow_enabled false", env.glow_enabled, false)
		lab._set_bloom(true)
		_expect_bool("bloom ON → glow_enabled true", env.glow_enabled, true)

	# ── WP6 Item 7: ship sprite renders one bank frame, not the whole strip ───
	_ck(lab._ship != null and is_instance_valid(lab._ship), "ship sprite exists")
	if lab._ship != null:
		_ck(int(lab._ship.get("hframes")) == 3, "ship sprite hframes == 3")

	# ── WP6 Item 3: control panel fits its column (no balloon over backdrop) ──
	await process_frame
	await process_frame
	var panel = lab.get_node_or_null("ControlPanel")
	_ck(panel != null, "ControlPanel node exists")
	if panel != null:
		_ck(panel.size.x <= LabScript.PANEL_W + 4.0,
			"panel width %.1f fits column %.0f" % [panel.size.x, LabScript.PANEL_W])

	# ── WP11: composition source (Composer / Gameplay) round-trip ─────────────
	# Composer (default / index 0) → the coordinator's stellar_override is empty.
	lab._on_source_selected(0)
	await process_frame
	_ck((bd.get("stellar_override") as Dictionary).is_empty(), "Composer source → stellar_override empty")
	_expect_bool("Composer source → composer fallback ON", bd.get("use_composer_fallback"), true)
	# Gameplay (index 1) → override authored + non-empty; composer fallback off; Generate rolls a node.
	lab._on_source_selected(1)
	await process_frame
	lab._on_generate_new()
	await process_frame
	await process_frame
	_ck(not (bd.get("stellar_override") as Dictionary).is_empty(), "Gameplay Generate → stellar_override non-empty")
	_expect_bool("Gameplay source → composer fallback OFF", bd.get("use_composer_fallback"), false)
	lab._refresh_status_line()
	_ck(lab._status_line != null and String(lab._status_line.text).contains("src=gameplay"),
		"Gameplay status line contains src=gameplay (%s)" % (lab._status_line.text if lab._status_line else "-"))
	# Back to Composer → override cleared, fallback restored.
	lab._on_source_selected(0)
	await process_frame
	_ck((bd.get("stellar_override") as Dictionary).is_empty(), "back to Composer → stellar_override cleared")
	_expect_bool("back to Composer → composer fallback ON", bd.get("use_composer_fallback"), true)

	_finish()


func _check_names(block: String, obj: Object, names: Array) -> void:
	# Assert the property exists on the object AND appears in the emitted block.
	for n in names:
		if not (n in obj):
			_fail("property '%s' NOT on %s" % [n, obj.get_class()])
		if not block.contains(n):
			_fail("Copy block missing '%s'" % n)


func _ck(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _expect(label: String, got, want: float) -> void:
	if abs(float(got) - want) > 0.001:
		_fail("%s: got %s want %s" % [label, got, want])


func _expect_bool(label: String, got, want: bool) -> void:
	if bool(got) != want:
		_fail("%s: got %s want %s" % [label, got, want])


func _fail(msg: String) -> void:
	_fails.append(msg)
	push_error("FAIL: " + msg)


func _finish() -> void:
	_restore_json()
	if _fails.is_empty():
		print("VERDICT: PASS")
	else:
		print("VERDICT: FAIL (%d)" % _fails.size())
		for m in _fails:
			print("  - " + m)
	quit()
