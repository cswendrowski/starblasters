extends Node
class_name SceneTransition

# Plain fade-to-black scene transition. Roman, 2026-05-16: "strip out all
# screen transitions. Replace with a simple transition that goes: fade to
# black, swap to new destination scene while black, fade from black."
#
# Usage:
#   const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
#   SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")

const FADE_OUT := 0.45
const FADE_IN := 0.45
const HOLD := 0.05

# `on_covered` (optional) runs once the black overlay fully covers the
# screen, BEFORE the scene swap. Use it to tear down per-scene state that
# must not be visible during the fade but must be gone before the
# destination's _ready (e.g. an HD viewport scope — see outpost._on_leave).
#
# `cover_only` (Roman 2026-06-19): fade to black + swap, but DON'T fade back in —
# the destination owns its own reveal (e.g. combat's _run_intro fades from black).
# Skips the fade-in to avoid a sluggish double-fade. Used by the loading-screen
# launcher so the ship's fly-off hands straight to combat's arrival.
static func change_scene(tree: SceneTree, path: String, on_covered: Callable = Callable(), cover_only: bool = false) -> void:
	await _run(tree, path, null, on_covered, cover_only)


# As change_scene, but swaps to an ALREADY-LOADED PackedScene (no disk load on the
# swap). The loading-screen launcher threaded-preloads the target, then hands the
# PackedScene here so the only main-thread cost at swap time is instantiation.
static func change_scene_packed(tree: SceneTree, packed: PackedScene, on_covered: Callable = Callable(), cover_only: bool = false) -> void:
	await _run(tree, "", packed, on_covered, cover_only)


static func _run(tree: SceneTree, path: String, packed: PackedScene, on_covered: Callable, cover_only: bool) -> void:
	if tree == null:
		return
	# Forensic breadcrumb — this swap (+ the backdrop teardown below) is the prime crash seam.
	var _crashlog: Node = tree.root.get_node_or_null("CrashLog")
	var _to: String = path.get_file() if packed == null else ("preloaded:" + packed.resource_path.get_file())
	if _crashlog != null:
		var _from: String = tree.current_scene.scene_file_path.get_file() if tree.current_scene != null else "?"
		_crashlog.note("xition", "change_scene: %s -> %s" % [_from, _to])
	var cl := CanvasLayer.new()
	cl.layer = 128
	tree.root.add_child(cl)
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	cl.add_child(rect)

	var tw_out := rect.create_tween()
	tw_out.tween_property(rect, "color:a", 1.0, FADE_OUT)
	await tw_out.finished

	if not is_instance_valid(rect):
		return
	rect.color.a = 1.0

	# Screen is now fully black — safe to flip viewport scale / tear down
	# the leaving scene's HD state without a visible blown-up frame.
	if on_covered.is_valid():
		on_covered.call()

	# Sweep stray gameplay actors. The projectile/drone convention parents them to
	# tree.root so they outlive their spawner's queue_free — which also means the
	# scene swap below never frees them: a root-parented flechette keeps recycling
	# at 0.45× over the NEXT scene (dev menus, cleared summary, sector map) forever.
	# Members inside the leaving scene are freed by the swap anyway; queue_free is
	# idempotent, so sweeping the whole group is safe and catches only-the-strays.
	# (Mirrors the player-death cleanup in main.gd, which call_groups "enemies".)
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for stray in tree.get_nodes_in_group(grp):
			if is_instance_valid(stray):
				stray.queue_free()

	# Tear down the leaving scene's parallax backdrop BEFORE the swap. change_scene_to_file frees the
	# whole scene at once; with a heavy backdrop's many shader CanvasItems in that batch, the engine's
	# draw-order reindex walks a freed RID -> "canvas_item is null" flood -> SIGSEGV. remove_child
	# unlinks the backdrop subtree cleanly (its CanvasItems EXIT the canvas instead of being freed
	# while still indexed), so the swap's free no longer touches them, and the reindex runs over only
	# the lightweight gameplay/HUD set (the baseline-stable set). Universal + safe: a no-op for any
	# scene with no "Backdrop" child. (2026-06-18 — docs/parallax_rework_safe_rebuild_2026-06-18.md)
	var leaving: Node = tree.current_scene
	if leaving != null and is_instance_valid(leaving):
		var bd: Node = leaving.get_node_or_null("Backdrop")
		if bd != null and is_instance_valid(bd):
			if _crashlog != null:
				_crashlog.note("xition", "teardown backdrop + swap -> %s" % path.get_file())
			leaving.remove_child(bd)
			bd.queue_free()

	var err: int = tree.change_scene_to_packed(packed) if packed != null else tree.change_scene_to_file(path)
	if err != OK:
		if is_instance_valid(cl):
			cl.queue_free()
		return

	# The swap is deferred — wait for it to land before revealing, otherwise we'd
	# show an empty frame.
	await tree.process_frame
	if cover_only:
		# Destination owns its reveal; its black cover is up by now (its _ready ran
		# during the swap). Drop ours with NO fade-in — black-to-black hand-off, no
		# flash, no double fade. One extra frame of slack for safety.
		await tree.process_frame
		if is_instance_valid(cl):
			cl.queue_free()
		return
	if HOLD > 0.0:
		await tree.create_timer(HOLD).timeout
	if not is_instance_valid(rect):
		return

	var tw_in := rect.create_tween()
	tw_in.tween_property(rect, "color:a", 0.0, FADE_IN)
	await tw_in.finished

	if is_instance_valid(cl):
		cl.queue_free()
