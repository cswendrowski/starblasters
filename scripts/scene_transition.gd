extends Node
class_name SceneTransition

# Plain fade-to-black scene transition. Roman, 2026-05-16: "strip out all
# screen transitions. Replace with a simple transition that goes: fade to
# black, swap to new destination scene while black, fade from black."
#
# Usage:
#   const SceneTransition = preload("res://scripts/scene_transition.gd")
#   SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")

const FADE_OUT := 0.45
const FADE_IN := 0.45
const HOLD := 0.05

# `on_covered` (optional) runs once the black overlay fully covers the
# screen, BEFORE the scene swap. Use it to tear down per-scene state that
# must not be visible during the fade but must be gone before the
# destination's _ready (e.g. an HD viewport scope — see outpost._on_leave).
static func change_scene(tree: SceneTree, path: String, on_covered: Callable = Callable()) -> void:
	if tree == null:
		return
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

	var err := tree.change_scene_to_file(path)
	if err != OK:
		if is_instance_valid(cl):
			cl.queue_free()
		return

	# change_scene_to_file is deferred — wait for the swap to land before
	# fading the black overlay back out, otherwise we'd reveal an empty frame.
	await tree.process_frame
	if HOLD > 0.0:
		await tree.create_timer(HOLD).timeout
	if not is_instance_valid(rect):
		return

	var tw_in := rect.create_tween()
	tw_in.tween_property(rect, "color:a", 0.0, FADE_IN)
	await tw_in.finished

	if is_instance_valid(cl):
		cl.queue_free()
