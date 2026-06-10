extends Node2D

# Wreck layer (Roman 2026-06-10) — a world-space presentation layer that sits just in front of the
# NEAR parallax layer and behind live gameplay. Dead enemies (currently only via the EM Torpedo's
# wreck-drift kill) are reparented into it as inert, drifting hulls that "fall" into the backdrop.
#
# WHY a world-space Node2D under "Backdrop" (not a CanvasLayer): the parallax layers are negative
# CanvasLayers (layer -10..-1), which always draw behind the default world canvas (layer 0). A
# Node2D parented under the Backdrop coordinator draws in that default canvas — so it renders in
# FRONT of every parallax layer but BEHIND the player/enemies (later z=0 siblings in the tree).
# Reparented wreck sprites keep their world transform, so they fall from where the enemy died.
# (Same seam the missile cruiser uses for mid-depth; see mid_depth_presentation.gd.)
#
# GRADING: we read the LIVE near parallax layer's baked CanvasModulate (tint x brightness x
# contrast, already computed by backdrop_coordinator each level) and apply it as this layer's
# modulate, so wrecks recede into the near band's colour grade. Falls back to a dim grey if the
# layer can't be found (dev scenes without a full backdrop).

const GROUP := "wreck_layer"
const _MidDepth = preload("res://scripts/effects/mid_depth_presentation.gd")

# Fallback grade when no near layer is present (dev/bare scenes): a desaturated dim like the near
# band usually lands at (near_tint * 0.6).
const FALLBACK_GRADE := Color(0.55, 0.58, 0.66, 1.0)


# Create (or return the existing) wreck layer for a combat context, parented above the backdrop and
# graded to the near parallax band. Idempotent — safe to call every combat start.
static func ensure(context: Node) -> Node2D:
	if context == null:
		return null
	var existing: Node = context.get_tree().get_first_node_in_group(GROUP) if context.is_inside_tree() else null
	if existing != null and is_instance_valid(existing):
		return existing as Node2D
	var layer := Node2D.new()
	layer.set_script(load("res://scripts/effects/wreck_layer.gd"))
	layer.name = "WreckLayer"
	layer.add_to_group(GROUP)
	# Above the backdrop, below ships (world space). Reuses the cruiser's mid-depth seam.
	_MidDepth.add_above_backdrop(context, layer)
	(layer as Node2D)._grade_to_near(context)
	return layer


# Match the near parallax layer's baked grade. Read the live CanvasModulate the coordinator wrote
# this level so we inherit the per-level planet tint + brightness/contrast automatically.
func _grade_to_near(context: Node) -> void:
	var grade: Color = FALLBACK_GRADE
	var coord: Node = context.get_node_or_null("Backdrop")
	if coord != null:
		var near_mod: Node = coord.get_node_or_null("LayerStellarNear/CanvasModulate")
		if near_mod != null and "color" in near_mod:
			grade = near_mod.color
	modulate = grade
