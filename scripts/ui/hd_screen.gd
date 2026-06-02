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
