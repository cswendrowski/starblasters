extends "res://scripts/enemies/core/enemy_core_building_turret.gd"

const FactionsC = preload("res://scripts/levels/factions.gd")

# Composed ground structures (Roman 2026-07-14): buildings whose LOOK is randomly assembled from layered
# sprite overlays at spawn, and that reveal 1–2 damage decals (on the SURVIVING building) when destroyed —
# rather than swapping a whole "Destroyed" frame. Shares everything else with the base structure script
# (drift, no ship vfx, size+tough HP, explode-with-debris husk, no player impact). Two structures use it:
#
#   Fuel Tank (building_fuel_tank.tscn) — Base/Building + two STYLE overlays (OverlayHaz, OverlayRed): it
#     shows EITHER one OR neither. Damage decals: Destroyed1 / Destroyed2.
#   Shed (building_square_shed.tscn) — two BUILDING variants (Building1/Building2, pick one) + two WINDOW
#     overlays (WindowsSide, WindowsTop: one / both / neither) + a HAZARD overlay (HazardMarks) allowed
#     ONLY when there are no windows. Damage decals: Destroyed1 / Destroyed2.
#
# The variant is detected by node presence, so each structure keeps its own composition rules explicit.
# Damage overlays (Destroyed1/2) are shared and never composed at spawn — they only appear on death.


func _ready() -> void:
	_compose()          # assemble the random look BEFORE super wires shadows to the visible layers
	super._ready()
	_apply_livery()     # tint a "Livery" layer (cross tank) with the level faction, if any


# Tint a "Livery" decal layer with the active level faction's colour. no_wave structures spawn outside the
# director's livery pass, so we apply it here. No active faction / no Livery node → keep the scene default.
func _apply_livery() -> void:
	var run = get_node_or_null("/root/Run")
	if run == null or not run.has_meta("active_faction"):
		return
	var faction: int = int(run.get_meta("active_faction", -1))
	if faction < 0:
		return
	FactionsC.apply_livery(faction, self)


# Assemble a random look. Which structure we are is read from the node layout (each has distinct layers).
func _compose() -> void:
	if has_node("Base/Building1"):
		_compose_shed()
	elif has_node("Base/Building/OverlayHaz"):
		_compose_fuel_tank()


# Fuel Tank: show EITHER one style overlay OR neither (never both).
func _compose_fuel_tank() -> void:
	var r: float = randf()
	_set_layer("Base/Building/OverlayHaz", r < 0.34)
	_set_layer("Base/Building/OverlayRed", r >= 0.34 and r < 0.67)


# Shed: pick one building variant; windows are independent (one / both / neither); the hazard overlay is
# allowed only when there are NO windows.
func _compose_shed() -> void:
	var use1: bool = randf() < 0.5
	_set_layer("Base/Building1", use1)
	_set_layer("Base/Building2", not use1)
	var w_side: bool = randf() < 0.5
	var w_top: bool = randf() < 0.5
	_set_layer("Base/WindowsSide", w_side)
	_set_layer("Base/WindowsTop", w_top)
	# Hazard marks only make sense on a plain (windowless) shed — then a coin-flip to show them.
	_set_layer("Base/HazardMarks", not w_side and not w_top and randf() < 0.5)


func _set_layer(path: String, on: bool) -> void:
	var n := get_node_or_null(path)
	if n != null and n is CanvasItem:
		(n as CanvasItem).visible = on


# Death look: OVERLAY 1–2 damage decals on the surviving building (never swap it out). "One or both" —
# even odds of both when two exist, else a single random decal.
func _show_destroyed_look() -> void:
	var decals: Array = []
	for nm in ["Destroyed1", "Destroyed2"]:
		var d := find_child(nm, true, false)
		if d is CanvasItem:
			decals.append(d)
	if decals.is_empty():
		return
	if decals.size() >= 2 and randf() < 0.5:
		for d in decals:
			(d as CanvasItem).visible = true          # both
	else:
		(decals[randi() % decals.size()] as CanvasItem).visible = true   # one
