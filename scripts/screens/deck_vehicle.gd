extends Node2D

# DeckVehicle — wraps a real hangar vehicle scene (the lifter now; tractor later) for the Deck Life
# system (docs/deck_life_plan_2026-07-04.md). Handles loading the scene, nearest-filtering its sprites,
# and a "powered" look: dim/cool when parked, full-bright + point-lights when a crew has it working.
# DeckLife drives the position for jobs and calls set_powered(); this node stays behavior-free.
#
# Reusable + host-agnostic: positions are in the parent's (deck's) local space. Absolute z so the
# vehicle floats above the crew/crates but below the ship.

const IDLE_TINT := Color(0.52, 0.57, 0.68)   # cool + dim while parked (reactor off)
const ON_TINT := Color(1.0, 1.0, 1.0)
const VEHICLE_Z := -3                          # above crew (-5) / crates (-5), below the ship (~0)

var home: Vector2 = Vector2.ZERO
var _scene: Node2D = null
var _lights: Array = []


func setup(scene_path: String, p_home: Vector2) -> void:
	var packed = load(scene_path)
	if packed == null:
		return
	_scene = packed.instantiate()
	add_child(_scene)
	for s in _scene.find_children("*", "Sprite2D", true, false):
		(s as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for l in _scene.find_children("*", "PointLight2D", true, false):
		_lights.append(l)
	z_index = VEHICLE_Z
	z_as_relative = false
	home = p_home
	position = p_home
	set_powered(false)


# Reactor on/off — brightens the whole vehicle (its additive engine/reactor glows pop) and lights up to
# two of its point lights (the plate has a 16-light budget; see hangar_stage.gd).
func set_powered(on: bool) -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.modulate = ON_TINT if on else IDLE_TINT
	var n := 0
	for l in _lights:
		if is_instance_valid(l):
			l.visible = on and n < 2
			n += 1
