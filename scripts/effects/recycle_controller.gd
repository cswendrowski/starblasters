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
	"fly_time": 1.8,        # fly-back tween duration (s)
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
	enemy.set_deferred("monitorable", false)
	enemy.set_deferred("monitoring", false)
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
	# Re-entry x inside the playfield band, not the full viewport — otherwise the cycle dropped
	# enemies into the side gutters where the player can't shoot back (Roman, 2026-05-19).
	var inset: float = float(cfg.entry_inset)
	var entry_x: float = randf_range(Playfield.X_MIN + inset, Playfield.X_MAX - inset)
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
	# Fly-back tween reads as a quick zip, not a leisurely parade (Cody, 2026-05-18).
	tw.tween_property(enemy, "position:y", float(cfg.fly_target_y), float(cfg.fly_time)).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
	if not is_instance_valid(enemy):
		return
	enemy.scale = pre_scale
	_restore_ghost_look(enemy, pre_modulate)
	enemy._set_outline_visible(true)        # back on the gameplay layer — restore the outline
	enemy.set_engine_trail_emitting(true)   # ...and the engine exhaust
	enemy._cycling = false
	# Reset the auto-rotate tracker so the first post-cycle move computes a fresh delta vector.
	enemy._rot_init = false
	enemy.set_deferred("monitorable", true)
	enemy.set_deferred("monitoring", true)
	enemy._recycle_resume()                        # re-arm firing + pattern/components (enemy-specific)


# Apply the ghost (faux-mid-depth) look for the fly-back. Step 4: uses Pillar 1's depth-tint
# shader on the body sprite so the recycler reads like the missile cruiser's mid-depth pass,
# stashing the body's original material so _restore_ghost_look can put it back. Falls back to a
# plain modulate tint when there's no body Sprite2D to grade.
static func _apply_ghost_look(enemy, cfg: Dictionary) -> void:
	var body := _body_sprite(enemy)
	if body == null:
		enemy.modulate = tint(cfg)
		return
	enemy.set_meta("_recycle_prev_mat", body.material)
	# Recede via the SHARED mid-depth body look (MidDepthPresentation.recede_body — same call the wreck
	# + missile cruiser use, so a receding ship reads consistently). The tuner's ghost color drives the
	# tint, its alpha the depth-blend amount, so RecycleTuner still dials "how faded". coordinator = the
	# backdrop the enemy lives under (grade-match the live mid layer); null-safe in bare scenes.
	var c: Color = tint(cfg)
	var scene: Node = enemy.get_tree().current_scene
	var coordinator: Node = scene.get_node_or_null("Backdrop") if scene != null else null
	MidDepthPresentation.recede_body(body, coordinator, Color(c.r, c.g, c.b, 1.0), c.a)


# Restore the body material the ghost look replaced + the pre-cycle modulate.
static func _restore_ghost_look(enemy, pre_modulate: Color) -> void:
	enemy.modulate = pre_modulate
	var body := _body_sprite(enemy)
	if body != null and enemy.has_meta("_recycle_prev_mat"):
		body.material = enemy.get_meta("_recycle_prev_mat")
		enemy.remove_meta("_recycle_prev_mat")


# The body Sprite2D the depth-tint rides on (the visible hull, named "Sprite2D" across the roster).
static func _body_sprite(enemy) -> Sprite2D:
	return enemy.get_node_or_null("Sprite2D") as Sprite2D
