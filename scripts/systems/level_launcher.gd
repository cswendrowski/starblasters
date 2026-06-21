extends RefCounted

# Flow controller for entering a heavy combat scene (main.tscn — combat / boss / hazard) via the
# loading screen. Threaded-preloads the target while the loading screen animates, enforces a
# minimum on-screen dwell so "Flying to <POI>" always lands, then flies the ship off the top and
# hands the reveal to the destination's OWN intro (cover-only swap, HD scope dropped under cover).
#
# Ownership split (Roman 2026-06-19): SceneTransition owns the cross-scene fade; LoadingScreen is a
# pure view (fly_off() / flight_complete); THIS owns the sequencing. The sector map calls
# LevelLauncher.go() instead of SceneTransition.change_scene() for the main.tscn node types.
#
# Preloaded by callers (no class_name — keeps it off the global cache):
#   const LevelLauncher = preload("res://scripts/systems/level_launcher.gd")

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const LOADING_SCENE := "res://scenes/loading_screen.tscn"
const MIN_DWELL_MS := 1500      # the loading screen shows at least this long once visible
const LOAD_TIMEOUT_MS := 20000  # safety: force the swap if the threaded load stalls


# Fire-and-forget. Runs as a detached coroutine (driven by the tree's process_frame), so it
# survives the sector-map -> loading-screen swap that happens inside it. `target_path` is the
# scene to end up in (combat/boss/hazard all = main.tscn); the loading screen reads ship + POI
# from Run itself, so nothing else needs threading through.
static func go(tree: SceneTree, target_path: String) -> void:
	if tree == null:
		return
	# 1. Kick the threaded preload now — it runs during the fade INTO the loading screen.
	ResourceLoader.load_threaded_request(target_path)
	# 2. Fade into the loading screen (fire-and-forget; we poll for it to land below).
	SceneTransition.change_scene(tree, LOADING_SCENE)
	# 3. Wait for the loading screen to become the current scene.
	var ls: Node = null
	while ls == null:
		await tree.process_frame
		var cur: Node = tree.current_scene
		if cur != null and cur is LoadingScreen:
			ls = cur
	# 4. Hold until the target is loaded AND the minimum dwell (visible time) has elapsed.
	var visible_ms: int = Time.get_ticks_msec()
	while true:
		var status: int = ResourceLoader.load_threaded_get_status(target_path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Preload broke — fall back to a plain fade swap by path so the player still gets there.
			SceneTransition.change_scene(tree, target_path)
			return
		var elapsed: int = Time.get_ticks_msec() - visible_ms
		var loaded: bool = status == ResourceLoader.THREAD_LOAD_LOADED
		if (loaded and elapsed >= MIN_DWELL_MS) or elapsed >= LOAD_TIMEOUT_MS:
			break
		await tree.process_frame
	# 5. Launch the ship off the top, then wait for it to clear the frame.
	if is_instance_valid(ls) and ls.has_method("fly_off"):
		ls.fly_off()
		await ls.flight_complete
	# 6. Cover-only swap to the preloaded scene — combat's _run_intro owns the reveal. Drop the
	#    loading screen's HD scope under the black cover (it swaps to a native-480 scene).
	var on_covered: Callable = Callable()
	if is_instance_valid(ls) and ls.has_method("drop_hd_scope"):
		on_covered = Callable(ls, "drop_hd_scope")
	var packed: PackedScene = ResourceLoader.load_threaded_get(target_path)
	if packed != null:
		SceneTransition.change_scene_packed(tree, packed, on_covered, true)
	else:
		SceneTransition.change_scene(tree, target_path, on_covered, true)
