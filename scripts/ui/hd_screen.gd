class_name HdScreen
extends RefCounted

# Canonical entry point for HD (1920×1080) menu screens. The in-combat game
# renders at the native 480×270 viewport; clickable menus want far more
# real-estate for clear layouts, so each swaps the window's content_scale_size
# to 1920×1080 for its lifetime (1 logical px = 1 screen px on a 1080p display)
# and lays its UI out in HD coordinates. The 480-native game backdrop, where a
# screen keeps one (sector map), is simply upscaled by the canvas stretch.
#
# This wraps HdViewportScope (the RAII content_scale swap) so every HD screen
# follows one pattern instead of hand-rolling the attach + teardown. Clicks
# map 1:1 under the swap (verified by tools/test_hd_click.gd).
#
# Usage:
#   var _hd: HdViewportScope
#   func _ready() -> void:
#       _hd = HdScreen.enter(self)
#       # ...build UI in 1920×1080 coordinates...
#   func _on_leave() -> void:
#       # Drop the scope only once a fade-to-black covers the screen, so the
#       # outgoing HD frame isn't shown blown-up at native scale mid-fade.
#       SceneTransition.change_scene(get_tree(), next, func(): HdScreen.drop(_hd))

const HD := Vector2i(1920, 1080)
const NATIVE := Vector2i(480, 270)


# Canonical "HD play-area SubViewport host" (Roman 2026-06-11). USE THIS for any HD dev screen with a
# native 480×270 play area (hangar / enemy bench / shader lab / weapon lab) instead of hand-rolling a
# SubViewportContainer — that is what kept regressing the play area into the corner.
#
# THE TRAP: SubViewportContainer.stretch=true OVERWRITES its child SubViewport.size to
# container_size / stretch_shrink on EVERY layout pass (the .size you set in code is only an initial
# value). Under HdViewportScope the full-rect container measures 1920×1080, so the DEFAULT
# stretch_shrink=1 forces the viewport to 1920×1080 and 480-native content renders in a 480×270
# corner. stretch_shrink=4 → 1920/4 = 480 keeps it native, upscaled 4× with nearest filtering.
#
# Adds the container (full-rect, behind nothing) to `host` and returns the SubViewport — add your
# content (native 480 coords) to it. Reference impl: scripts/dev/parallax_tuner.gd. Docs:
# docs/godot-patterns.md "HD SubViewport host".
static func make_play_subviewport(host: Node, native_size: Vector2i = NATIVE, shrink: int = 4) -> SubViewport:
	var container := SubViewportContainer.new()
	container.name = "PlayContainer"
	container.stretch = true
	container.stretch_shrink = shrink   # the load-bearing knob — keeps the viewport native
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(container)
	var vp := SubViewport.new()
	vp.name = "PlayViewport"
	vp.size = native_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	container.add_child(vp)
	return vp


# Regression guard. Call DEFERRED / after a frame (the container resizes the viewport on its first
# layout pass) to catch a misconfigured HD play-area host. Pushes a loud error if `stretch` clobbered
# the viewport off native size — i.e. someone dropped stretch_shrink=4 again.
static func verify_native_subviewport(vp: SubViewport, host_name: String = "") -> void:
	if vp == null or not is_instance_valid(vp):
		return
	if vp.size != NATIVE:
		push_error("HD SubViewport host '%s' MISCONFIGURED: viewport is %s, expected %s — the play area will render in the corner. Set SubViewportContainer.stretch_shrink=4 (use HdScreen.make_play_subviewport). See docs/godot-patterns.md." % [host_name, vp.size, NATIVE])


# Attach the HD content-scale scope to `host`. For Control roots, also set
# full-rect anchors so the screen fills the 1920×1080 logical viewport.
# Returns the scope (normally freed with the host; call drop() to release it
# early — e.g. once a scene-transition fade covers the screen).
static func enter(host: Node) -> HdViewportScope:
	var scope := HdViewportScope.attach(host, HD)
	if host is Control:
		(host as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return scope


# Release the scope early (restores native content_scale). Idempotent + safe
# on null/freed scopes. Use as a SceneTransition on-covered callback.
static func drop(scope: HdViewportScope) -> void:
	if scope != null and is_instance_valid(scope):
		scope.free()


# Display the live 480×270 game parallax backdrop on an HD screen, filling it.
# The backdrop's layers read their viewport size to distribute stars, so you
# can't just scale the Node2D ×4 (it double-applies and clumps top-left).
# Instead we render it into a native-sized SubViewport and show that as a
# nearest-filtered full-screen TextureRect — the exact same 4× upscale the
# combat scene gets from the canvas stretch. `backdrop` is the already-built
# (and configured) backdrop node; it's reparented under the SubViewport.
# The TextureRect is inserted at index 0 of `host` (behind the UI). Returns
# the SubViewport (freed with host).
static func add_upscaled_backdrop(host: Node, backdrop: Node, native_size: Vector2i = Vector2i(480, 270)) -> SubViewport:
	var sub := SubViewport.new()
	sub.name = "BackdropViewport"
	sub.size = native_size
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Purely decorative — must never participate in GUI input picking.
	sub.gui_disable_input = true
	sub.handle_input_locally = false
	sub.add_child(backdrop)
	host.add_child(sub)

	var view := TextureRect.new()
	view.name = "BackdropView"
	view.texture = sub.get_texture()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(view)
	host.move_child(view, 0)
	return sub
