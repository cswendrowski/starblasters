extends RefCounted

# RecycleController — Pillar 2 (spec docs/archive/recycling_system_pillar2_2026-06-04.md).
# Preload-based, NOT class_name (a fresh global class_name didn't resolve in headless
# `-s` runs during Pillar 1).
#
# THE SINGLE OWNER of enemy recycling, in three parts:
#   * resolve(enemy)  — the offscreen DECISION (recycle / free / ignore), generalizing
#     the per-mode logic that used to live in enemy_base._offscreen_cleanup_check.
#   * recycle(enemy)  — the async parallax FLY-BACK (hold, reposition, ghost scale/tint,
#     up-tween, restore) + recycle_passes accounting. Enemy-specific firing suspend/re-arm
#     flows through the enemy's _recycle_suspend()/_recycle_resume() hooks, so ANY enemy
#     class can recycle (enemy_base gives no-op defaults).
#   * config()/tint()/save() — the tunable TIMING + LOOK, loaded from the RecycleTuner's
#     JSON so Roman can dial recycle feel live.
#
# Migrated off the old scattered owners (enemy_base edge-detection + enemy_core._start_cycle)
# 2026-06-29. DEFAULTS are byte-identical to the old hardcoded numbers, so with no tuner
# file present the roster behaves exactly as before. The ghost look uses Pillar 1's
# depth-tint shader (MidDepthPresentation) so the fly-back reads like the missile cruiser.
# Regression surface = the whole roster; recycle FEEL is playtest-verified, not headless.

const CONFIG_PATH := "user://tuners/recycle.json"
const Playfield = preload("res://scripts/systems/playfield.gd")
const MidDepthPresentation = preload("res://scripts/effects/mid_depth_presentation.gd")

# The decision resolve() hands back to enemy_base._offscreen_cleanup_check.
enum Action { IGNORE, RECYCLE, FREE }

# MUST mirror enemy_base.OffscreenMode's member ORDER (same int values). Mirrored rather than
# imported to avoid a circular preload (enemy_base preloads this controller). The enum is stable;
# if you reorder OffscreenMode, reorder here too.
enum Mode { CYCLE_BOTTOM, FREE_ANY_EDGE, FREE_OPPOSITE_SIDE, NONE }

# Defaults == the values enemy_core._start_cycle hardcoded before this controller.
const DEFAULTS := {
	"hold_min": 0.4,        # pre-cycle hold, randf_range low (s)
	"hold_max": 0.9,        # pre-cycle hold, randf_range high (s)
	"entry_inset": 22.0,    # px inset from the playfield band edges for re-entry x
	"fly_scale": 0.45,      # ghost-pass scale multiplier
	# Fly-back speed is PROPORTIONAL to the enemy's on-field move_speed (Roman 2026-07-05) — the ghost
	# recedes at move_speed × fly_speed_mult px/s, so a large slow ship recedes slowly and a fast one
	# zips, instead of every enemy sharing one fixed duration. Clamped so the quickest don't teleport
	# and move_speed==0 (unresolved / stationary) doesn't hang.
	"fly_speed_mult": 1.0,  # ghost recede speed as a multiple of the enemy's on-field move_speed
	"fly_time_min": 1.0,    # clamp: even the fastest ships take at least this long to recede (s)
	"fly_time_max": 4.5,    # clamp: the slowest (or 0-speed) ships take at most this long (s)
	"fly_target_y": -20.0,  # tween destination y (px)
	# Ghost tint (faux-mid-depth). Stored as 4 floats so it round-trips through JSON.
	"tint_r": 0.75, "tint_g": 0.85, "tint_b": 1.0, "tint_a": 0.55,
}

# Cached so the hot recycle path doesn't hit disk every fly-back. Call
# invalidate() (the tuner does on save) to force a reload.
static var _cache: Dictionary = {}
static var _loaded: bool = false


# Returns the merged config (disk values over DEFAULTS). Missing/!malformed file →
# pure DEFAULTS. Cached after first read.
static func config() -> Dictionary:
	if _loaded:
		return _cache
	_cache = DEFAULTS.duplicate()
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for k in DEFAULTS.keys():
					if parsed.has(k):
						_cache[k] = float(parsed[k])
	_loaded = true
	return _cache


static func invalidate() -> void:
	_loaded = false
	_cache = {}


# The ghost tint as a Color, assembled from the stored channels.
static func tint(cfg: Dictionary) -> Color:
	return Color(
		float(cfg.get("tint_r", DEFAULTS.tint_r)),
		float(cfg.get("tint_g", DEFAULTS.tint_g)),
		float(cfg.get("tint_b", DEFAULTS.tint_b)),
		float(cfg.get("tint_a", DEFAULTS.tint_a)))


# Persist a config dict to disk + invalidate the cache (used by the tuner).
static func save(cfg: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var out := {}
	for k in DEFAULTS.keys():
		out[k] = float(cfg.get(k, DEFAULTS[k]))
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	invalidate()
	return true


# Fly-back duration for a recede of `distance` px by an enemy whose on-field speed is `field_speed`
# px/s. The ghost travels at field_speed × fly_speed_mult, so duration = distance / that, clamped to
# [fly_time_min, fly_time_max]. Proportional to on-field speed (slow ship → long recede, fast → short);
# field_speed <= 0 (unresolved / stationary) floors back_speed at 1 px/s → clamps to fly_time_max.
# Shared by recycle() + the RecycleTuner preview so both read identically. Pure — unit-testable.
static func fly_duration(distance: float, field_speed: float, cfg: Dictionary) -> float:
	var back_speed: float = maxf(field_speed * float(cfg.get("fly_speed_mult", DEFAULTS.fly_speed_mult)), 1.0)
	return clampf(distance / back_speed,
		float(cfg.get("fly_time_min", DEFAULTS.fly_time_min)),
		float(cfg.get("fly_time_max", DEFAULTS.fly_time_max)))


# ---- The offscreen decision -----------------------------------------------

# Decide what an offscreen check should do for `enemy` — RECYCLE (hand to _on_offscreen), FREE
# (clean leave), or IGNORE (still on-screen / NONE mode). Pure read: enemy_base owns the _dying
# guard + the _entered_playfield latch and just routes this verdict. Mirrors the per-mode logic
# that used to live inline in enemy_base._offscreen_cleanup_check.
#
# Edges are VIEWPORT edges (not the playfield band) so in-band pong/overshoot from side-cutters
# never trips a leave; only a genuine off-screen exit does. CYCLE_BOTTOM deliberately does NOT
# watch the TOP — patterns legitimately spawn/retreat near y=0 (advance_retreat, top_dive), so a
# top trigger would misfire; a full SIDE exit counts (allow_side_exit) so sideways drifters recycle
# promptly instead of loitering offscreen until their slow Y descent crosses the bottom.
static func resolve(enemy) -> int:
	if enemy._dying:
		return Action.IGNORE
	var mode: int = enemy.offscreen_mode
	if mode == Mode.NONE:
		return Action.IGNORE
	var sz: Vector2 = enemy.get_viewport_rect().size
	var m: float = enemy.offscreen_margin
	var gp: Vector2 = enemy.global_position
	match mode:
		Mode.CYCLE_BOTTOM:
			if gp.y > sz.y + m:
				return Action.RECYCLE
			if enemy.allow_side_exit and (gp.x < -m or gp.x > sz.x + m):
				return Action.RECYCLE
		Mode.FREE_ANY_EDGE:
			if gp.y > sz.y + m \
				or (enemy._entered_playfield and gp.y < -m) \
				or gp.x < -m or gp.x > sz.x + m:
				return Action.FREE
		Mode.FREE_OPPOSITE_SIDE:
			if gp.x < -m or gp.x > sz.x + m:
				return Action.FREE
	return Action.IGNORE


# ---- The fly-back ---------------------------------------------------------

# Run the parallax fly-back on `enemy` (async, fire-and-forget). Owns the GENERIC recycle
# mechanics — recycle_passes accounting, hold, reposition into the playfield band, ghost
# scale/tint, the up-tween, and restore — and routes the enemy-specific firing suspend/re-arm
# through the enemy's _recycle_suspend()/_recycle_resume() hooks. Mirrors the old
# enemy_core._start_cycle exactly (byte-identical with no tuner file).
#
# recycle_passes: -1 unlimited / 0 leave instead / N decrement-then-cycle. is_recycling()
# (enemy._cycling) stays true for the whole window — the off-screen hit-immunity guard
# (enemy_base.take_hit) and the smart bomb both skip a mid-fly-back enemy.
# `enemy` is intentionally UNTYPED — recycle() touches Node2D/CanvasItem members (scale, modulate,
# position) + enemy fields (_cycling, recycle_passes) that a `Node`-typed param would reject at parse.
static func recycle(enemy) -> void:
	if enemy._cycling:
		return
	if enemy.recycle_passes == 0:
		enemy._leave()
		return
	if enemy.recycle_passes > 0:
		enemy.recycle_passes -= 1
	enemy._cycling = true
	enemy._recycle_suspend()                       # stop firing (enemy-specific hook)
	# Non-interactive for the WHOLE fly-back — root AND every descendant Area2D section. Multi-part hulls
	# (the cruiser's gun pods / engine / bridge) are independent Area2D "enemies"-group parts; neutralizing
	# only the root left them shootable through the ghost pass (bullets hit by group + monitorable). Restore
	# is symmetric on the legacy revive path below.
	_set_subtree_interactive(enemy, false)
	# Drop the hull outline + engine exhaust for the whole fly-back: a recycling ship reads as
	# faux-parallax (shrunk + tinted), which shouldn't carry either effect.
	enemy._set_outline_visible(false)
	enemy.set_engine_trail_emitting(false)
	enemy.visible = false
	var cfg: Dictionary = config()
	# Cody, 2026-05-18: pre-cycle hold trimmed (now cfg.hold_min/max) — "a lot of dead time
	# waiting for them" looping in the background.
	var delay: float = randf_range(float(cfg.hold_min), float(cfg.hold_max))
	await enemy.get_tree().create_timer(delay).timeout
	if not is_instance_valid(enemy):
		return
	# Re-entry x on a LANE CENTER (FIX #1, 2026-07-06). The old randf_range X dropped recyclers on
	# arbitrary sub-lane X; the pattern's on_start then re-anchored to that random X for the whole pass,
	# so re-entered enemies descended off-grid and could overlap a lane occupant. Snap to a lane center,
	# preferring one whose entry band is free (LaneTraffic scan, which now skips _cycling ghosts). If
	# none is free we fall back to a plain randi lane pick — recycle timing is already non-deterministic
	# so an un-seeded pick here is acceptable and keeps re-entry on-grid regardless.
	var entry_x: float = _pick_reentry_x(enemy)
	enemy.position = Vector2(entry_x, enemy.screensize.y + 12.0)
	var pre_scale: Vector2 = enemy.scale
	var pre_modulate: Color = enemy.modulate
	# Parallax-pass: shrink + push toward the parallax tint. NO scale.y flip — auto_rotate handles
	# orientation, so rotation = 0 points the ship UP (its fly-back travel direction).
	var fly_scale: float = float(cfg.fly_scale)
	enemy.scale = Vector2(pre_scale.x * fly_scale, pre_scale.y * fly_scale)
	_apply_ghost_look(enemy, cfg)
	enemy.rotation = 0.0
	enemy._rot_init = true
	enemy._last_position = enemy.position
	enemy.visible = true
	var tw: Tween = enemy.create_tween()
	# Duration is proportional to the enemy's on-field speed (see fly_duration): a slow ship recedes
	# slowly and a fast one zips, instead of every enemy sharing one fixed tween time.
	var target_y: float = float(cfg.fly_target_y)
	var field_speed: float = float(enemy.move_speed) if "move_speed" in enemy else 0.0
	var fly_time: float = fly_duration(absf(enemy.position.y - target_y), field_speed, cfg)
	tw.tween_property(enemy, "position:y", target_y, fly_time).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
	if not is_instance_valid(enemy):
		return
	# DESPAWN + CREDIT (despawn+credit rework, 2026-07-06). The fly-back is a DESPAWN: instead of
	# restoring the live enemy at the top (the old un-conducted re-entry), hand the director a recycle
	# CREDIT and free the enemy. The director re-spawns a faithful replacement as a CONDUCTED sweep row
	# at the next wave boundary, so a missed unit returns as part of the choreography — never a lone
	# straggler weaving through a formation. Everything above (pass accounting, suspend, ghost look,
	# speed-proportional recede) is unchanged shipped feel.
	#
	# FALLBACK: with no director in the scene (dev labs, benches, test harnesses) we keep the LEGACY
	# restore+resume path below, so every dev tool behaves exactly as before.
	# STATE-PRESERVING EXCEPTION (2026-07-11): the despawn+credit path re-spawns a FRESH instance from the
	# source WaveSpec — full HP, all destructible sections resurrected. That's fine for chaff (a pristine
	# re-entry is imperceptible) but wrong for a damaged or multi-part hull (the cruiser "Dreadnought"): it
	# would heal to full and grow its shot-off gun pods back. For those we keep the SAME live node via the
	# legacy restore-in-place path below, so hull HP + per-section damage state is inherently preserved. No
	# director-side change needed (the director owns the from-spec respawn we're opting out of).
	var director: Node = _find_director(enemy)
	if director != null and not _should_restore_in_place(enemy):
		var spec: Resource = enemy.get_meta("recycle_source_spec", null) as Resource
		if spec != null:
			# recycle_passes has already been decremented above for this pass; carry the REMAINING count
			# so the re-spawned instance doesn't reset to the spec's original budget (chaff-loop guard).
			var remaining: int = int(enemy.recycle_passes) if "recycle_passes" in enemy else -1
			director.call_deferred("credit_recycled", spec, remaining)
		else:
			# Director present but no stashed spec — a dev-spawned enemy that leaked into a real level.
			# Free without credit and warn once so it's noticed rather than silently vanishing.
			push_warning("RecycleController: recycling enemy has no recycle_source_spec meta; freeing without credit")
		enemy.queue_free()
		return
	enemy.scale = pre_scale
	_restore_ghost_look(enemy, pre_modulate)
	enemy._set_outline_visible(true)        # back on the gameplay layer — restore the outline
	enemy.set_engine_trail_emitting(true)   # ...and the engine exhaust
	enemy._cycling = false
	# Reset the auto-rotate tracker so the first post-cycle move computes a fresh delta vector.
	enemy._rot_init = false
	_set_subtree_interactive(enemy, true)          # re-arm root + every descendant section as targets
	enemy._recycle_resume()                        # re-arm firing + pattern/components (enemy-specific)


# Lane-center X for a recycler's re-entry (FIX #1). Prefers a lane whose ENTRY band (top, y<=40) is
# free of other non-hazard, non-cycling enemies — the enemy descends from the top after the fly-back,
# so a clear entry band is what prevents an overlap. Falls back to a plain randi lane pick when every
# lane is contested (recycle timing is already non-deterministic, so an un-seeded pick is fine here).
static func _pick_reentry_x(enemy) -> float:
	var tree: SceneTree = enemy.get_tree()
	var free: Array = []
	for ln in Lanes.COUNT:
		if _entry_lane_free(tree, ln, enemy):
			free.append(ln)
	var lane: int
	if not free.is_empty():
		lane = free[randi() % free.size()]
	else:
		lane = randi() % Lanes.COUNT
	return Lanes.lane_center(lane)


# True if no OTHER non-hazard, non-cycling enemy sits in `lane`'s entry band (y<=40). Mirrors the
# director's _occupied_lanes idiom, sharing lane_traffic's cycling/hazard exclusions.
static func _entry_lane_free(tree: SceneTree, lane: int, exclude) -> bool:
	if tree == null:
		return true
	for e in tree.get_nodes_in_group("enemies"):
		if e == exclude or not is_instance_valid(e) or not (e is Node2D):
			continue
		if "is_hazard" in e and e.is_hazard:
			continue
		if "_cycling" in e and e._cycling:
			continue
		if e.position.y <= 40.0 and Lanes.nearest_lane(e.position.x) == lane:
			return false
	return true


# Apply the ghost (faux-mid-depth) look for the fly-back. Step 4: uses Pillar 1's depth-tint
# shader on the body sprite so the recycler reads like the missile cruiser's mid-depth pass,
# stashing the body's original material so _restore_ghost_look can put it back. Falls back to a
# plain modulate tint when there's no body Sprite2D to grade.
static func _apply_ghost_look(enemy, cfg: Dictionary) -> void:
	_sink_ghost(enemy)
	var bodies: Array = _hull_sprites(enemy)
	if bodies.is_empty():
		enemy.modulate = tint(cfg)
		return
	# Recede via the SHARED mid-depth body look (MidDepthPresentation.recede_body — same call the wreck
	# + missile cruiser use, so a receding ship reads consistently). The tuner's ghost color drives the
	# tint, its alpha the depth-blend amount, so RecycleTuner still dials "how faded". coordinator = the
	# backdrop the enemy lives under (grade-match the live mid layer); null-safe in bare scenes.
	# Grade EVERY hull body in the subtree — a multi-part hull (the cruiser) carries a body Sprite2D per
	# destructible section, and the old single-root grade left those sections at full brightness so the
	# ship never read as background. Stash each sprite's prior material for a symmetric restore.
	var c: Color = tint(cfg)
	var scene: Node = enemy.get_tree().current_scene
	var coordinator: Node = scene.get_node_or_null("Backdrop") if scene != null else null
	var graded: Array = []
	for body in bodies:
		graded.append([body, body.material])
		MidDepthPresentation.recede_body(body, coordinator, Color(c.r, c.g, c.b, 1.0), c.a)
	enemy.set_meta("_recycle_graded", graded)


# Restore every hull material the ghost look replaced + the pre-cycle modulate + the pre-cycle depth.
static func _restore_ghost_look(enemy, pre_modulate: Color) -> void:
	enemy.modulate = pre_modulate
	_raise_ghost(enemy)
	if enemy.has_meta("_recycle_graded"):
		for pair in enemy.get_meta("_recycle_graded"):
			var spr: Sprite2D = pair[0]
			if is_instance_valid(spr):
				spr.material = pair[1]
		enemy.remove_meta("_recycle_graded")


# ---- Ghost depth (Roman 2026-07-28) --------------------------------------
# A recycling ship has RECEDED into the mid-depth band (shrunk + depth-tinted), so it must render
# BEHIND the ground plane it's flying back over — not in front of it. The ghost keeps its normal
# z_index otherwise (recycle never touched it), which left it at 0: over the asteroid stronghold
# rock (-8), over loose asteroid-POI rocks (-1), and over the starbase decks (-16..-10, see
# docs/starbase_assault_design_2026-07-28.md §5.1). GHOST_Z clears the deepest of those.
#
# Pinned ABSOLUTELY so the ghost lands at the same depth regardless of its host's z (Main at 0, a
# dev lab's world node, a boss's parent). Children keep z_as_relative, so a multi-part hull (the
# cruiser's pods/bridge) sinks as one piece with its internal ordering intact.
#
# MidDepthPresentation.add_above_backdrop warns against a z_index override — that warning is about a
# POSITIVE one lifting a mid-depth object above the ships. Sinking is the direction a receded object
# should go, and the two don't conflict: nothing routes a recycling ghost through that helper.
const GHOST_Z: int = -18


static func _sink_ghost(enemy) -> void:
	if enemy.has_meta("_recycle_depth"):
		return   # already sunk (defensive — recycle() guards on _cycling, but keep it idempotent)
	enemy.set_meta("_recycle_depth", [enemy.z_index, enemy.z_as_relative])
	enemy.z_as_relative = false
	enemy.z_index = GHOST_Z


static func _raise_ghost(enemy) -> void:
	if not enemy.has_meta("_recycle_depth"):
		return
	var prev: Array = enemy.get_meta("_recycle_depth")
	enemy.z_index = int(prev[0])
	enemy.z_as_relative = bool(prev[1])
	enemy.remove_meta("_recycle_depth")


# Every visible hull BODY sprite in the subtree — the root's "Sprite2D" plus each descendant section's
# own "Sprite2D" (multi-part hulls). Name-filtered to the hull body so the overlay layers (GlowMask /
# Livery / Outline) are left on their own presentation axis. Single-body enemies yield exactly one.
static func _hull_sprites(enemy) -> Array:
	var out: Array = []
	for n in enemy.find_children("Sprite2D", "Sprite2D", true, false):
		if n is Sprite2D:
			out.append(n)
	return out


# ---- State-preserving + subtree-interactivity helpers (2026-07-11) --------

# Whether this recycler must keep its SAME live node (legacy restore-in-place) instead of the
# despawn+credit from-spec respawn: true for a MULTI-PART hull (any DestructiblePart section — a
# from-spec respawn resurrects shot-off sections) or an already-DAMAGED hull (health < max_health —
# a respawn heals it to full). An undamaged single-body chaff respawns identically from spec, so it
# still takes the conducted despawn+credit path.
static func _should_restore_in_place(enemy) -> bool:
	if not enemy.find_children("*", "DestructiblePart", true, false).is_empty():
		return true
	if ("health" in enemy) and ("max_health" in enemy) and enemy.health < enemy.max_health:
		return true
	return false


# Toggle collision on the root AND every descendant Area2D section. A recycling ship is faux-parallax
# (shrunk + tinted background) and must be non-interactive; the root guard alone misses the independent
# Area2D parts of a multi-part hull. monitorable off stops incoming bullet hits (area_entered never
# fires); monitoring off stops the part registering contacts.
static func _set_subtree_interactive(enemy, on: bool) -> void:
	enemy.set_deferred("monitorable", on)
	enemy.set_deferred("monitoring", on)
	for part in enemy.find_children("*", "Area2D", true, false):
		if is_instance_valid(part):
			part.set_deferred("monitorable", on)
			part.set_deferred("monitoring", on)


# The wave director for this enemy's scene, or null. Found via the "wave_director" group the director
# joins in _ready (despawn+credit rework, 2026-07-06). Null in dev labs / benches / test harnesses that
# drive recycle() without a director — the caller then keeps the legacy restore+resume path. Tolerant
# of a freed tree (bare unit tests).
static func _find_director(enemy) -> Node:
	var tree: SceneTree = enemy.get_tree()
	if tree == null:
		return null
	for d in tree.get_nodes_in_group("wave_director"):
		if is_instance_valid(d):
			return d
	return null
