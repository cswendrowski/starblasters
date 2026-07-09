extends CanvasLayer
class_name ParallaxLayerBase

@export var scroll_rate: float = 0.0

@export var modulate_color: Color = Color.WHITE:
	set(v):
		modulate_color = v
		_recompute_modulate()

@export var brightness: float = 1.0:
	set(v):
		brightness = v
		_recompute_modulate()

@export var contrast: float = 1.0:
	set(v):
		contrast = v
		_recompute_modulate()

# HDR-bright glow multiplier on top of brightness. Default 1.0 = no change. Pushed > 1.5 (with the
# scene's HDR WorldEnvironment) it makes the whole layer bloom — the one mechanism that works on the
# shader-driven planets too, since CanvasModulate multiplies the layer's composited output post-shader
# (a CanvasItem `modulate` is ignored by planet shaders that overwrite COLOR). Tuned per-layer.
@export var glow_mult: float = 1.0:
	set(v):
		glow_mult = v
		_recompute_modulate()

# Pixel-snap toggle (Parallax V4 showcase, item 2). true = today's pipeline exactly
# (untouched — inert). false = smooth this layer's motion by turning OFF the CONTAINING
# viewport's transform snap.
#
# INVESTIGATION (why this shape): the layer's scroll offset is ALREADY a raw float —
# scroll() does `offset.y += delta_y` with no round/floor — so there is no per-layer
# rounding to strip. The visible ~1px stepping of a slow (~1.5px/s) planet has TWO
# sources: (1) the viewport's `snap_2d_transforms_to_pixel` (ON for the main window via
# project.godot; OFF by default on a code-made SubViewport), and (2) the 480×270 backdrop
# render resolution itself — a shader-driven planet ColorRect rasterizes to whole 480-texels,
# so at 0.025px/frame it only visibly jumps once every ~40 frames regardless of snap.
# CanvasLayer/CanvasItem expose no per-item snap, so the only reachable lever is the viewport
# flag. false sets it OFF (removes source 1); it does NOT fix source 2 at the lab's 480×270
# SubViewport (which already renders snap-off, so there the toggle is a visual no-op — the
# planet still steps from render res). It DOES smooth the combat/main-viewport path (snap ON)
# and would fully smooth if the backdrop rendered at HD res. Roman accepts losing pixel-snap
# for background planets. Only touches the viewport when false, so default true is byte-identical.
@export var pixel_snap: bool = true:
	set(v):
		pixel_snap = v
		_apply_pixel_snap()

var _canvas_mod: CanvasModulate = null


func _apply_pixel_snap() -> void:
	# Only act when smoothing is requested — leave the viewport untouched otherwise so
	# the default (true) is a strict no-op (byte-identical production). Viewport-global:
	# unsnapping affects every layer sharing the backdrop viewport, which is the intended
	# "smooth the whole background" behavior for the lab's planet toggle.
	if pixel_snap or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null:
		vp.snap_2d_transforms_to_pixel = false


func _ready() -> void:
	# PAUSABLE (was ALWAYS) so every parallax layer — and the decor drift its
	# subclasses run in their own _process (planet spin, stellar/star drift, bg
	# mines) — FREEZES with the game under the pause menu instead of animating
	# behind the near-opaque dim (2026-07-04). The backdrop only shows during
	# combat or on non-pausing menus, so this is a no-op outside pause.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_canvas_mod = $CanvasModulate if has_node("CanvasModulate") else null
	if _canvas_mod != null:
		_recompute_modulate()
	# Re-apply once inside the tree so a scene/editor-set pixel_snap=false reaches the viewport
	# (the setter above no-ops before the node enters the tree). Default true = no-op.
	_apply_pixel_snap()


func scroll(delta_y: float) -> void:
	offset.y += delta_y
	_on_scrolled()


# Horizontal parallax: shift the layer laterally by `px × scroll_rate` so depth
# falloff is automatic (far layers barely move, near layers swing). `px` is the
# coordinator's smoothed strafe offset; called every frame only when the
# coordinator's lateral_strength > 0, so the default (no calls) is inert.
# layer_stars overrides — its two Parallax2D children carry the scroll, not offset.
func apply_lateral(px: float) -> void:
	offset.x = px * scroll_rate
	# Re-run the scroll hook so offset-countering children (e.g. the stellar
	# nebula, screen-fixed) re-pin against the new offset.x, not just offset.y.
	_on_scrolled()


func _on_scrolled() -> void:
	pass


func reset() -> void:
	offset = Vector2.ZERO
	_on_reset()


func _on_reset() -> void:
	pass


func _recompute_modulate() -> void:
	if _canvas_mod == null:
		return
	var base := modulate_color
	var r := clampf((base.r - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness * glow_mult
	var g := clampf((base.g - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness * glow_mult
	var b := clampf((base.b - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness * glow_mult
	_canvas_mod.color = Color(r, g, b, base.a)
