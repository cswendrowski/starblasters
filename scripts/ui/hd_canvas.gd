extends Object
class_name HdCanvas

# 2× density UI layer host. Attaches a SubViewport (960×540) rendered
# back into the 480×270 main viewport via SubViewportContainer with
# stretch_shrink=2. Text rendered inside the returned viewport rasterises
# at 2× the gameplay resolution — glyphs get 4× the pixel area, so
# small font sizes stay legible.
#
# UI authored inside the SubViewport uses 960×540 logical coords (i.e.
# 2× the original 480×270 numbers). Anchor presets resolve correctly
# because the SubViewport's own viewport rect is 960×540.
#
# Idempotent — calling twice on the same host returns the same viewport.
# Sprite-based UI (textures already nearest-filtered at 4×) should stay
# in the 4× canvas; only text-heavy widgets belong here.


# Install (or fetch existing) the HD layer on `host`. Returns the
# SubViewport — parent new UI under this.
static func install(host: Node) -> SubViewport:
	var existing := host.get_node_or_null("PlayfieldHd/HdContainer/HdViewport")
	if existing and existing is SubViewport:
		return existing as SubViewport
	var layer := CanvasLayer.new()
	layer.name = "PlayfieldHd"
	layer.layer = 6
	host.add_child(layer)
	var c := SubViewportContainer.new()
	c.name = "HdContainer"
	c.position = Vector2.ZERO
	c.size = Vector2(480, 270)
	c.stretch = true
	c.stretch_shrink = 2
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	var v := SubViewport.new()
	v.name = "HdViewport"
	v.transparent_bg = true
	v.handle_input_locally = false
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	c.add_child(v)
	return v


# Fetch the HD viewport if installed; null otherwise. Use this from
# sub-systems (ui.gd, hud widgets) that may load before or after the
# host's install call.
static func get_viewport(host: Node) -> SubViewport:
	var v := host.get_node_or_null("PlayfieldHd/HdContainer/HdViewport")
	return v as SubViewport if v else null
