# Central routing constant for the sector map scene.
# To revert to the V2 480×270 map: change SECTOR_MAP_SCENE to
#   "res://scenes/sector_map_v2.tscn"
# HD renders at native 1920×1080 inside a SubViewport (crisp text + lines).
class_name SectorMapRoute

const SECTOR_MAP_SCENE: String = "res://scenes/sector_map_hd.tscn"
