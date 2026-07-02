class_name MenuBackdrop
extends RefCounted

# Shared menu/lobby parallax backdrop config (Roman 2026-07-02). The main menu and the patrol-start
# hangar both build the SAME calm-lobby-tune backdrop (slower drift, present streaks, some asteroids).
# Centralizing the four knobs here keeps the two fresh-build paths (main_menu._install_backdrop +
# patrol_start._install_menu_backdrop) from drifting apart. The patrol-start LIVE launch ADOPTS the
# menu's already-rendered backdrop instead of building a fresh one (see HdScreen.adopt_upscaled_backdrop),
# so this is only the fallback / dev-launch build.

const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")

# How far (px, toward the band centre) the celestial bodies are dropped from their normal top staging.
# The menu drops them here; the patrol-start hangar starts them here and pans them up as the bay rises.
# When the patrol-start ADOPTS the live menu backdrop, the celestials are already dropped by this amount
# — do NOT re-apply it (see patrol_start._install_menu_backdrop).
const CELESTIAL_DROP := 110.0

const _CELESTIAL_LAYERS := ["LayerPlanet", "LayerStellarFar", "LayerStellarMid", "LayerStellarNear"]


# Build a fresh menu/lobby backdrop coordinator with the shared calm tune. Caller reparents it via
# HdScreen.add_upscaled_backdrop. Does NOT apply the celestial drop — call drop_celestials() after
# the backdrop is added (its _ready must run so the layers exist).
static func make() -> Node:
	var bd := BackdropCoordinatorScene.instantiate()
	bd.name = "Backdrop"
	# Calm lobby tune — present, some motion. Same call the combat scene uses, slower planet drift.
	bd.set("drift_speed", 14.0)
	bd.set("warp_streak_count", 8)
	bd.set("warp_streak_speed", 432.0)
	bd.set("asteroid_presence", 0.5)
	return bd


# Drop the celestial bodies toward the band centre (they normally stage near the top). The parallax
# layers are CanvasLayers — shift them with `offset`, not `position`.
static func drop_celestials(bd: Node) -> void:
	for nm in _CELESTIAL_LAYERS:
		var cl := bd.get_node_or_null(nm) as CanvasLayer
		if cl != null:
			cl.offset.y += CELESTIAL_DROP


# The celestial CanvasLayer nodes on a backdrop, in a stable order (for pan / replay bookkeeping).
static func celestial_layers(bd: Node) -> Array:
	var out: Array = []
	for nm in _CELESTIAL_LAYERS:
		var cl := bd.get_node_or_null(nm) as CanvasLayer
		if cl != null:
			out.append(cl)
	return out
