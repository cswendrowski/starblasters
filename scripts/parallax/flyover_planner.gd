extends Object

# FlyoverPlanner (Roman 2026-07-18) — the single source of truth for "is this combat node a
# Planet Flyover level, and what does it look like". Pure/deterministic: plan() returns {} (not
# a flyover) or the full FlyoverBackdrop settings dict; the same inputs always produce the same
# dict. Called by backdrop_coordinator (combat) and loading_screen (the fly-to screen). It may
# READ the Run autoload's forced_flyover meta but NEVER writes Run.
#
# Preload-referenced, NOT a global class_name — matches the Factions / LevelLauncher convention
# (a fresh class_name isn't registered under headless --script until the cache regenerates).

const Backdrop = preload("res://scripts/parallax/flyover_backdrop.gd")

const FLYOVER_CHANCE := 0.4
const NIGHT_CHANCE := 0.35
const SALT := 0x464C594F   # "FLYO" — decorrelates the flyover rolls from other per-node systems.

# V3 planet_type (stellar_gameplay.gd) -> FlyoverBackdrop preset name. Gas planets (4, 6) have
# no surface to fly over and are absent — plan() returns {} for them.
const TYPE_TO_PRESET := {
	0: "Lava",         # LavaWorld
	1: "Desert 2",     # DryTerran   — per Roman: desert planets use desert2
	2: "Moonsteroid",  # NoAtmosphere — per Roman: moon planets use moonsteroid
	3: "Terran",       # LandMasses
	5: "Ice",          # IceWorld
	7: "Terran",       # Rivers      — river_cutoff jitter biased UP
}

# Baked base settings mirroring the 2026-07-18 saved tuner. Per-preset fields (surface_type,
# colors, emissive, atmo, atmo_color) come from the preset; per-node jitter from the planner
# rng; the hue roll from planet_seed. user://tuners/planet_flyover.json overlays these when
# present (dev machines: lab tuning drives production).
const DEFAULTS := {
	"flight": 0.35, "feature_scale": 8.0, "loop_size": 32, "octaves": 5, "pixels": 480.0,
	"relief": 0.35, "river_cutoff": 0.5,
	"cloud_opacity": 0.6, "cloud_coverage": 0.55, "atmo_opacity": 0.18,
	"ship_shadow": 0.35,
	"cloud_on": {"Far": true, "Mid": true, "Near": true},
	"layer_style": {"Far": 0, "Mid": 0, "Near": 0},
	"layer_opacity": {"Far": 1.0, "Mid": 1.0, "Near": 1.0},
	"layer_color": {"Far": Color(0.75, 0.78, 0.83), "Mid": Color(0.82, 0.84, 0.88), "Near": Color(0.90, 0.91, 0.94)},
	"night_darkness": 0.45, "night_color": Color(0.25, 0.31, 0.53),
}

const TUNER_PATH := "user://tuners/planet_flyover.json"


# The single entry point. `stellar` = Run.current_stellar (obj_kind / planet_type / planet_seed);
# returns {} unless this node is a flyover.
static func plan(stellar: Dictionary, run_seed: int, node_id: String) -> Dictionary:
	var forced: Dictionary = _forced_meta()
	if bool(forced.get("deny", false)):
		return {}

	var obj_kind: int = int(stellar.get("obj_kind", -1))
	var ptype: int = int(stellar.get("planet_type", -1))
	# Eligibility: a real planet POI whose type maps to a surface preset. (Force bypasses the
	# CHANCE roll only — it can't conjure a surface for a gas planet.)
	if obj_kind != 0 or not TYPE_TO_PRESET.has(ptype):
		return {}

	var rng := RandomNumberGenerator.new()
	rng.seed = abs(run_seed ^ hash(node_id)) ^ SALT
	# Roll 1: flyover chance — always consumed first so the terrain jitter that follows is
	# identical whether the flyover was forced or naturally rolled for the same node.
	var chance_roll: float = rng.randf()
	var force: bool = bool(forced.get("force", false))
	if not force and chance_roll >= FLYOVER_CHANCE:
		return {}

	var pname: String = String(TYPE_TO_PRESET[ptype])
	var preset: Dictionary = Backdrop.PRESETS[pname]

	# Base = DEFAULTS overlaid with the tuner (allowed keys only; per-preset fields excluded).
	var base: Dictionary = _base_settings()

	# Per-node jitter (deterministic, clamped). Consumption order is FIXED.
	var feature_scale: float = float(base["feature_scale"]) * rng.randf_range(0.8, 1.25)
	var relief: float = float(base["relief"]) * rng.randf_range(0.75, 1.3)
	var river_delta: float = rng.randf_range(0.10, 0.25) if ptype == 7 else rng.randf_range(-0.12, 0.12)
	var river_cutoff: float = clampf(float(base["river_cutoff"]) + river_delta, 0.05, 0.95)
	var cloud_opacity: float = clampf(float(base["cloud_opacity"]) + rng.randf_range(-0.15, 0.10), 0.0, 1.0)
	var cloud_coverage: float = clampf(float(base["cloud_coverage"]) + rng.randf_range(-0.12, 0.12), 0.1, 0.9)
	var flight: float = float(base["flight"]) * rng.randf_range(0.85, 1.2)
	# Night roll (last, so it doesn't shift the terrain jitter).
	var night: bool = rng.randf() < NIGHT_CHANCE

	# Colour identity: ONE shared hue rotation of the preset palette (±0.15 turn) rolled from
	# planet_seed, with per-slot sat/val jitter. atmo + cloud-layer colours get the same rotation
	# so the whole scene reads as one coherent hue family.
	var planet_seed: int = int(stellar.get("planet_seed", 0))
	var hue_rng := RandomNumberGenerator.new()
	hue_rng.seed = abs(planet_seed)
	var dh: float = hue_rng.randf_range(-0.15, 0.15)
	var colors: Array = []
	for c in preset["colors"]:
		colors.append(Backdrop.shift_color(c, dh, hue_rng))
	var atmo_color: Color = Backdrop.shift_color(preset["atmo_color"], dh, hue_rng)
	var layer_color := {}
	for layer in Backdrop.CLOUD_LAYERS:
		layer_color[layer] = Backdrop.shift_color(base["layer_color"][layer], dh, hue_rng)

	var out := {
		"flyover": true,
		"preset": Backdrop.PRESET_NAMES.find(pname),
		"surface_type": int(preset["type"]),
		"colors": colors,
		"emissive": float(preset["emissive"]),
		# Ground-shader noise seed derived from planet_seed into the shader's meaningful 1..10
		# range (feeding the raw ~2^31 seed as a float strobes noise precision). Deterministic
		# per planet, so terrain layout is stable = "terrain layout parity".
		"seed": 1.0 + float(abs(planet_seed) % 900) / 100.0,
		"flight": flight,
		"feature_scale": feature_scale,
		"loop_size": int(base["loop_size"]),      # FIXED (never jittered)
		"octaves": int(base["octaves"]),          # FIXED
		"pixels": float(base["pixels"]),          # FIXED
		"relief": relief,
		"river_cutoff": river_cutoff,
		"atmo": bool(preset["atmo"]),
		"atmo_color": atmo_color,
		"atmo_opacity": float(base["atmo_opacity"]),
		"cloud_opacity": cloud_opacity,
		"cloud_coverage": cloud_coverage,
		"cloud_on": (base["cloud_on"] as Dictionary).duplicate(),
		"layer_style": (base["layer_style"] as Dictionary).duplicate(),
		"layer_opacity": (base["layer_opacity"] as Dictionary).duplicate(),
		"layer_color": layer_color,
		"ship_shadow": float(base["ship_shadow"]),
		"night": night,
		"night_darkness": float(base["night_darkness"]),
		"night_color": base["night_color"],
	}

	# Dev override: merge any non-control keys from forced_flyover over the planned dict.
	for k in forced.keys():
		if k != "force" and k != "deny":
			out[k] = forced[k]
	return out


# DEFAULTS overlaid with the user tuner (guarded: file may be absent or missing keys). Only the
# base/scalar/layer knobs overlay — surface_type/colors/emissive/atmo/atmo_color come from the
# preset, and the lab-only demo keys (preset, ship_on) are ignored.
static func _base_settings() -> Dictionary:
	var base: Dictionary = DEFAULTS.duplicate(true)
	var tuner: Dictionary = _load_tuner()
	for key in ["flight", "feature_scale", "loop_size", "octaves", "relief", "pixels",
			"river_cutoff", "cloud_opacity", "cloud_coverage", "atmo_opacity", "ship_shadow",
			"night_darkness"]:
		if tuner.has(key):
			base[key] = tuner[key]
	if tuner.has("night_color"):
		base["night_color"] = Color.from_string(String(tuner["night_color"]), base["night_color"])
	for layer in Backdrop.CLOUD_LAYERS:
		if tuner.has("cloud_on") and tuner["cloud_on"].has(layer):
			base["cloud_on"][layer] = bool(tuner["cloud_on"][layer])
		if tuner.has("layer_style") and tuner["layer_style"].has(layer):
			base["layer_style"][layer] = int(tuner["layer_style"][layer])
		if tuner.has("layer_opacity") and tuner["layer_opacity"].has(layer):
			base["layer_opacity"][layer] = float(tuner["layer_opacity"][layer])
		if tuner.has("layer_color") and tuner["layer_color"].has(layer):
			base["layer_color"][layer] = Color.from_string(String(tuner["layer_color"][layer]), base["layer_color"][layer])
	return base


static func _load_tuner() -> Dictionary:
	if not FileAccess.file_exists(TUNER_PATH):
		return {}
	var f := FileAccess.open(TUNER_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


# Read Run.forced_flyover meta if the Run autoload exists (dev override). Never writes.
static func _forced_meta() -> Dictionary:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root: Window = (loop as SceneTree).root
		if root != null and root.has_node("Run"):
			var run := root.get_node("Run")
			if run != null and run.has_meta("forced_flyover"):
				var m = run.get_meta("forced_flyover")
				if m is Dictionary:
					return m
	return {}
