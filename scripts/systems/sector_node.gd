extends Resource

# One node in the sector map graph.

# STRONGHOLD (2026-07-18, appended — the int is serialized in sector_map_cache, never renumber):
# the Asteroid Stronghold assault — faction combat + the StrongholdField prefab overlay, placed on
# asteroid POIs. Capped ≤2 per row / ≤4 per sector (run_state._promote_stronghold_pois).
enum NodeType { COMBAT, OUTPOST, SIGNAL, BOSS, START, HAZARD, STRONGHOLD }

@export var id: String = ""
@export var node_type: int = NodeType.COMBAT
@export var row: int = 0
@export var col: int = 0
@export var pos: Vector2 = Vector2.ZERO
@export var edges_to: Array  # ids of nodes in the next row


func _init() -> void:
	# Force a fresh array per node so edge appends don't leak between
	# maps. (Cody, 2026-05-17 playtest: sector map "regenerated" every
	# return — was actually the same map but with edges_to carrying
	# stale state from the previous generation, because GDScript class-
	# level Array defaults are shared by reference across Resource
	# instances.)
	edges_to = []

# Stellar decoration for this node. Generated when the sector map is rolled.
#
#   planet_idx     — index into galaxy_backdrop.PLANETS (0..8). Drives the
#                    primary celestial body visible in combat.
#   nebula_band    — optional string tag. Adjacent nodes that share the same
#                    nebula_band render the same nebula tint, so a pink/blue
#                    nebula stretching across the right side of the map
#                    carries into the levels under it.
#   nebula_tint    — Color override for the nebula on this node, when
#                    nebula_band is set. RGB only; alpha unused.
@export var planet_idx: int = -1
@export var nebula_band: String = ""
@export var nebula_tint: Color = Color(1, 1, 1, 1)

static func type_name(t: int) -> String:
	match t:
		NodeType.COMBAT: return "Combat"
		NodeType.OUTPOST: return "Outpost"
		NodeType.SIGNAL: return "Signal"
		NodeType.BOSS: return "Boss"
		NodeType.START: return "Start"
		NodeType.HAZARD: return "Hazard"
		NodeType.STRONGHOLD: return "Stronghold"
		_: return "?"

static func type_symbol(t: int) -> String:
	match t:
		NodeType.COMBAT: return "X"
		NodeType.OUTPOST: return "$"
		NodeType.SIGNAL: return "?"
		NodeType.BOSS: return "!"
		NodeType.START: return "*"
		NodeType.HAZARD: return "!"
		NodeType.STRONGHOLD: return "#"
		_: return "."
