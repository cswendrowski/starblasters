extends RefCounted

# Asteroid Stronghold prefabs (Roman 2026-07-13) — hand-authored in the Asteroid Stronghold editor
# (scripts/dev/asteroid_stronghold_editor.gd); the editor's "Copy GDScript" pastes entries into DATA.
#
# Each entry:
#   { "name": String,
#     "asteroid": { "seed": int, "size": float, "roundness": float, "dither": bool,
#                   "tint": [r, g, b], "drift_speed": float },
#     "buildings": [ { "type": <palette key>, "x": float, "y": float }, ... ] }
# Building type keys + scenes: scripts/enemies/stronghold_building_palette.gd (SCENES/TYPES).
#
# The reframed asteroid_field hazard consumes these at runtime via load_all() (below): the editor's
# working user JSON merged OVER this committed DATA (a user entry shadows a DATA entry of the same
# name), matching how the editor loads. Bake authored prefabs in via the editor's "Copy GDScript".

const USER_PATH := "user://tuners/asteroid_strongholds.json"

const DATA: Array = [
]


# All prefabs the game should use: the editor's live user JSON merged over committed DATA (user
# entries shadow a DATA entry of the same name). Returns raw dicts (the runtime builder reads
# asteroid{...} + buildings[...] directly). Empty only if neither source has entries.
static func load_all() -> Array:
	var out: Array = []
	var user_names := {}
	if FileAccess.file_exists(USER_PATH):
		var f := FileAccess.open(USER_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				for e in parsed:
					if e is Dictionary:
						out.append(e)
						user_names[String(e.get("name", ""))] = true
	for d in DATA:
		if d is Dictionary and not user_names.has(String(d.get("name", ""))):
			out.append((d as Dictionary).duplicate(true))
	return out
