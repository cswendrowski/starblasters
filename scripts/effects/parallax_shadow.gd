extends Node2D
class_name ParallaxShadow

# Ground-shadow system. Each ship attaches a small dark elliptical
# sprite that lives at the scene root (so it's not clipped to the ship's
# transform), tracks the ship's global_position + an offset every
# frame, and sits at a z_index between the top parallax asteroid band
# and the active gameplay. Reads as the ship "casting a shadow" on the
# foremost parallax layer. Roman, 2026-05-16.
#
# Usage:
#   const ParallaxShadow = preload("res://scripts/effects/parallax_shadow.gd")
#   ParallaxShadow.attach(self)
#
# This script doubles as a node — when `attach()` is called it instances
# a ParallaxShadow Node2D parented to the ship's parent, with a Sprite2D
# child for the elliptical shadow. The script's _process tracks the
# ship's position.

const SHADOW_OFFSET := Vector2(10, 14)
# 60% transparent black per Roman, 2026-05-16: "60% transparent black
# sprite would serve in most cases".
const SHADOW_COLOR := Color(0, 0, 0, 0.40)
const SHADOW_Z := -2

var _ship: Node2D = null
var _sprite: Sprite2D = null


func _process(_delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		queue_free()
		return
	global_position = _ship.global_position + SHADOW_OFFSET
	# Mirror the ship's accumulated world scale so the silhouette
	# matches the ship's on-screen size. Doesn't inherit rotation —
	# shadows on the ground don't spin with the body.
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.global_scale = _effective_scale(_ship)
		# Keep the silhouette pinned to the host's current sprite frame.
		var src := _resolve_host_sprite(_ship)
		if src is Sprite2D:
			_sprite.texture = (src as Sprite2D).texture
			_sprite.hframes = (src as Sprite2D).hframes
			_sprite.vframes = (src as Sprite2D).vframes
			_sprite.frame = (src as Sprite2D).frame
			_sprite.centered = (src as Sprite2D).centered
			_sprite.offset = (src as Sprite2D).offset


static func attach(ship: Node2D) -> Node:
	if ship == null or not is_instance_valid(ship):
		return null
	if ship.has_meta("parallax_shadow"):
		return ship.get_meta("parallax_shadow") as Node
	var holder := load("res://scripts/effects/parallax_shadow.gd").new() as Node2D
	holder.name = "ParallaxShadow"
	holder._ship = ship
	holder.z_index = SHADOW_Z
	holder.z_as_relative = false
	# Silhouette sprite — clone the ship's current Sprite2D texture and
	# tint it 60%-alpha black. Roman, 2026-05-16: shadow shape should
	# match the sprite, not be a generic ellipse.
	var spr := Sprite2D.new()
	spr.modulate = SHADOW_COLOR
	holder.add_child(spr)
	holder._sprite = spr
	# Seed the first frame so the shadow is correct even before _process
	# fires.
	var src := _resolve_host_sprite(ship)
	if src is Sprite2D:
		var s := src as Sprite2D
		spr.texture = s.texture
		spr.hframes = s.hframes
		spr.vframes = s.vframes
		spr.frame = s.frame
		spr.centered = s.centered
		spr.offset = s.offset
	# Park under the ship's parent so the shadow stays at world scale.
	var host: Node = ship.get_parent()
	if host == null:
		host = ship.get_tree().current_scene
	if host == null:
		host = ship.get_tree().root
	host.add_child(holder)
	ship.set_meta("parallax_shadow", holder)
	ship.tree_exiting.connect(func():
		if is_instance_valid(holder):
			holder.queue_free()
	)
	return holder


# Resolve the ship's primary Sprite2D. Most enemies put it at "Sprite2D";
# the Player wraps it under "Ship/Sprite2D" — try both.
static func _resolve_host_sprite(ship: Node) -> Node:
	if ship == null:
		return null
	if ship.has_node("Sprite2D"):
		return ship.get_node("Sprite2D")
	if ship.has_node("Ship"):
		var sub = ship.get_node("Ship")
		if sub is Sprite2D:
			return sub
		if sub.has_node("Sprite2D"):
			return sub.get_node("Sprite2D")
	return null


# Walk up parents accumulating Node2D scale so the shadow matches the
# ship's actual on-screen size (Player root is scaled 3×, ships under
# WaveDirector are 3× via inherited scale, etc).
static func _effective_scale(node: Node) -> Vector2:
	var s := Vector2.ONE
	var cur := node
	while cur != null and cur is Node2D:
		s *= (cur as Node2D).scale
		cur = cur.get_parent()
	return s
