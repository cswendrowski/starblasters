extends RefCounted

# BulletWorld (Roman 2026-06-16) — resolves the node that gameplay-spawned visuals
# (enemy bullets, missiles, drops, muzzle flashes, boss telegraphs) should parent to.
#
# The long-standing convention parents these to get_tree().root / current_scene so they
# share the firing node's coordinate space AND outlive its queue_free. That works in
# production because the combat scene (main.tscn) renders DIRECTLY into the window root,
# so root == the 480-native gameplay space. It BREAKS inside a SubViewport dev bench
# (enemy_bench): there get_tree().root is the 1920×1080 window, a DIFFERENT viewport than
# the bench's native SubViewport, so spawns land in the window's top-left corner instead
# of the simulated playfield.
#
# Fix without touching combat behavior: a SubViewport bench adds its in-viewport gameplay
# layer to the "bullet_world" group. resolve() prefers that node when present and otherwise
# returns the caller's own fallback — so in production (no such group node) the result is
# byte-identical to the old get_tree().root / current_scene parenting.
#
# Referenced via preload const (NOT class_name — a fresh global class doesn't resolve under
# headless `-s` until the cache regenerates; the codebase convention for pattern deps):
#
#   const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
#   var parent := BulletWorld.resolve(self, get_tree().root)

const GROUP := "bullet_world"


# Return the registered SubViewport gameplay layer if one exists, else `fallback`
# (the call site's existing parent — get_tree().root or current_scene), preserving
# production behavior exactly.
static func resolve(node: Node, fallback: Node) -> Node:
	if node != null:
		var t: SceneTree = node.get_tree()
		if t != null:
			var w: Node = t.get_first_node_in_group(GROUP)
			if w != null and is_instance_valid(w):
				return w
	return fallback
