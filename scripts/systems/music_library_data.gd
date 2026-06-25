@tool
class_name MusicLibraryData
extends Resource

# Baked music catalog + per-context eligibility for the Ovani music system.
#
# Authored by the Track Manager (Dev Menu → Music Lab → Save) and consumed by
# the `Music` autoload (scripts/autoload/music_manager.gd). Stored as a .tres so
# it is bundled into exports (a loose .json is not guaranteed to be) and loads
# via the normal resource path.
#
#   tracks: track_name -> {
#       "rt":   float,    # reverb tail seconds (from the source folder name)
#       "i1":   String,   # res:// path to the Intensity 1 stem
#       "i2":   String,   # res:// path to the Intensity 2 stem
#       "main": String,   # res:// path to the Main (Intensity 3) stem
#       "l30":  String,   # res:// path to the 30s loop cut (unused by default)
#       "l60":  String,   # res:// path to the 60s loop cut (unused by default)
#   }
#   eligibility: context -> Array[String]   # which tracks may play in that context
#
# Contexts: "menu" / "sector" / "signal" (events) / "outpost" / "combat" / "boss".
@export var tracks: Dictionary = {}
@export var eligibility: Dictionary = {}
