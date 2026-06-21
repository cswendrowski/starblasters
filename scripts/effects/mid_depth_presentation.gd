extends Node

# Reusable "faked mid-depth" presentation for WORLD-SPACE background ships
# (Roman, 2026-06-01). Extracted from missile_cruiser.gd so every recycling /
# background ship sells the same parallax-mid look from one source of truth.
#
# WHY FAKE IT (not parent into the real layer): the stellar parallax layers are
# CanvasLayers with their own scroll — a ship parented in loses world-space
# alignment (its X/Y no longer maps to the playfield) AND scrolls with parallax.
# A traversing ship that drops world-space ordnance onto the playfield needs
# world coords, so it stays a plain Node2D in world space and FAKES the depth:
#   • parent above the parallax backdrop but below the ships,
#   • scale DOWN (caller owns the scale — sells "further away"),
#   • tint the BODY toward the background + grade-match the live mid layer,
#   • leave the engine GLOW bright so the tint never dims it.
#
# Static helpers, called as MidDepthPresentation.method(...) like the other
# scripts/effects/ helpers. The caller keeps its own designer-facing knobs
# (scale / tint amount / glow brightness) and passes them in; the defaults here
# mirror the missile cruiser's prior hardcoded values so an argless call looks
# identical to the original.

const DEPTH_TINT_SHADER: Shader = preload("res://scripts/effects/depth_tint.gdshader")
const GlowFx = preload("res://scripts/effects/glow_fx.gd")

# Default look (mirrors missile_cruiser.gd's prior hardcoded constants).
const DEFAULT_BG_TINT := Color(0.42, 0.50, 0.62, 1.0)
const DEFAULT_TINT_AMOUNT: float = 0.45
const DEFAULT_GRADE_STRENGTH: float = 0.5
const DEFAULT_GLOW_BRIGHTNESS: float = 1.8


# Parent `node` ABOVE the parallax backdrop but BELOW the ships. `context` is a
# node whose tree contains the "Backdrop" coordinator as a child — the combat
# scene root (main.gd) or a boss's parent (boss_base). Because the Backdrop's
# parallax layers all draw at z=0 and Backdrop is an earlier sibling of the
# Player in main.tscn, tree order alone puts the node at the correct mid-depth —
# no z_index override (that would lift it above the ships). Falls back to adding
# under `context` itself when no Backdrop is found (bare dev/showcase scenes).
static func add_above_backdrop(context: Node, node: Node2D) -> void:
	if context == null or node == null:
		return
	var bd: Node = context.get_node_or_null("Backdrop")
	if bd != null:
		bd.add_child(node)
	else:
		context.add_child(node)


# Tint a BODY sprite so it reads as living in the mid parallax band: lerp the art
# toward `bg_tint` by `amount` (genuine desaturation — see depth_tint.gdshader),
# then multiply by the LIVE mid layer's grade so brightness/contrast match the
# mid-depth objects. `coordinator` is the BackdropCoordinator the object is
# parented under (pass get_parent()). grade_strength lerps the grade from white
# (0 = full brightness, 1 = exact mid-layer grade). No-op if `body` is null.
static func apply_body_tint(
	body: Sprite2D,
	coordinator: Node,
	amount: float = DEFAULT_TINT_AMOUNT,
	bg_tint: Color = DEFAULT_BG_TINT,
	grade_strength: float = DEFAULT_GRADE_STRENGTH
) -> void:
	if body == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = DEPTH_TINT_SHADER
	mat.set_shader_parameter("bg_tint", bg_tint)
	mat.set_shader_parameter("amount", amount)
	# Apply only grade_strength of the mid-layer grade (lerp from white) so the
	# object can stay a touch brighter than pure mid-layer dressing.
	mat.set_shader_parameter("grade_mul", Color.WHITE.lerp(read_mid_layer_grade(coordinator), grade_strength))
	body.material = mat


# Make a GLOW sprite read as a bright emissive element (additive overdrive +
# radial halo) that the depth tint never dims. The host must already be in-tree
# (GlowFx.attach_glow childs the halo). No-op if `glow` is null.
static func apply_glow(glow: Sprite2D, brightness: float = DEFAULT_GLOW_BRIGHTNESS) -> void:
	if glow == null:
		return
	glow.modulate = Color(brightness, brightness, brightness, 1.0)
	GlowFx.attach_glow(glow, Color.WHITE, 1.4, 0.6)


# Read the LIVE mid parallax layer's CanvasModulate color so a body multiply is
# an exact mid-depth grade match. The CanvasModulate color already bakes
# modulate_color * brightness * contrast (see ParallaxLayerBase._recompute_modulate),
# so a single multiply matches without re-running the curve. `coordinator` is the
# node the object is parented under; its mid stellar layer is "LayerStellarMid"
# with a child "CanvasModulate". Returns WHITE (no-op) if any part of that chain
# is missing (showcase/dev bare scenes), preserving the un-graded look.
static func read_mid_layer_grade(coordinator: Node) -> Color:
	if coordinator == null:
		return Color.WHITE
	var mid: Node = coordinator.get_node_or_null("LayerStellarMid")
	if mid == null:
		return Color.WHITE
	var cm: CanvasModulate = mid.get_node_or_null("CanvasModulate") as CanvasModulate
	if cm != null:
		return cm.color
	# Fallback: re-run ParallaxLayerBase._recompute_modulate from the layer's
	# exported brightness/contrast/modulate_color (matches the math exactly).
	if ("modulate_color" in mid) and ("brightness" in mid) and ("contrast" in mid):
		var base: Color = mid.get("modulate_color")
		var bri: float = float(mid.get("brightness"))
		var con: float = float(mid.get("contrast"))
		var r: float = clampf((base.r - 0.5) * con + 0.5, 0.0, 1.0) * bri
		var g: float = clampf((base.g - 0.5) * con + 0.5, 0.0, 1.0) * bri
		var b: float = clampf((base.b - 0.5) * con + 0.5, 0.0, 1.0) * bri
		return Color(r, g, b, base.a)
	return Color.WHITE
