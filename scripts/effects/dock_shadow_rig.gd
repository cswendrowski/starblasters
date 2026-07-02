extends RefCounted

# Shared light-derived shadow rig for the dock cinematics (outpost_arrival + patrol_start), factored
# out of their near-identical copies (Roman 2026-07-02 refactor). Owns a LightShadowFx instance and the
# knob-syncing + key/fill light selection against a shared hangar_stage; the screens keep their own thin
# @export knobs + per-screen caster/dynamic-light registration and delegate the rest here.
#
# The lab compares three modes: LEGACY = baked drop shadows (rig disabled); KEY = one central key light
# (single shadow); FILL = the bay's 2×3 fill lights (multi-shadow). Dynamic lights (bright engine / grav
# / head-tail lights) can be added on top — their shadows fade with the light's energy. Default LEGACY.
#
# Usage: the screen builds a rig with its shared hangar_stage, adds it to the world SubViewport, sets the
# knobs (from its @exports), then on each rebuild calls register_casters(...) + register_dynamic_lights(...)
# with per-screen callables, and apply(mode, dynamic). ensure_key_light() is created lazily in KEY mode
# only; an existing key light is disabled in the other modes — preserved exactly from the originals.

const LightShadowFx = preload("res://scripts/effects/light_shadow_fx.gd")

# Shadow prototype: LEGACY = baked drop shadows; KEY = one central key light (single shadow);
# FILL = the bay's 2×3 fill lights (multi-shadow). + optional dynamic (engine/grav/head-tail) casters.
enum ShadowMode { LEGACY, KEY, FILL }
const KEY_LIGHT_ENERGY := 0.0    # key light is a SHADOW SOURCE only — illuminating it floods/sweeps the bay

var fx = null                       # LightShadowFx (the projector node)
var _stage: Node = null             # shared hangar_stage instance (owns key/fill lights + clutter)
var _mode: int = ShadowMode.LEGACY
var _dynamic: bool = false
# Per-screen registration callbacks (set by the screen; run on every rebuild).
var _casters_cb: Callable = Callable()          # func(rig) -> void: calls rig.add_caster(...)
var _dynamic_lights_cb: Callable = Callable()   # func(rig) -> void: calls rig.add_dynamic_light(...)


# Build the projector as a child of `world` (the native SubViewport), bound to the shared hangar `stage`.
func setup(world: Node, stage: Node) -> void:
	_stage = stage
	fx = LightShadowFx.new()
	world.add_child(fx)


func set_stage(stage: Node) -> void:
	_stage = stage


func set_casters_callback(cb: Callable) -> void:
	_casters_cb = cb


func set_dynamic_lights_callback(cb: Callable) -> void:
	_dynamic_lights_cb = cb


# Push the screen's knob values into the projector.
func sync_knobs(length: float, alpha: float, falloff: float, softness: float, max_per: int) -> void:
	if fx == null:
		return
	fx.shadow_length = length
	fx.max_alpha = alpha
	fx.falloff = falloff
	fx.softness = softness
	fx.max_per_caster = max_per


# Full re-apply for the given mode + dynamic flag: enable/disable the projector, re-select the light set,
# and rebuild the casters. The screen still toggles its own legacy drop-shadow visibility (per-screen).
func apply(mode: int, dynamic: bool) -> void:
	_mode = mode
	_dynamic = dynamic
	if fx == null:
		return
	fx.enabled = mode != ShadowMode.LEGACY
	rebuild_lights()
	rebuild_casters()


func is_proto(mode: int = -1) -> bool:
	var m: int = mode if mode >= 0 else _mode
	return m != ShadowMode.LEGACY


# Re-select the light set for the current mode. KEY materializes the key light lazily (energy 0, shadow
# source only) — in LEGACY/FILL it stays uncreated so it never eats a slot of the plate's 16-light budget
# (see LIGHT BUDGET in hangar_stage.gd). An existing key light is disabled in the non-KEY modes. When
# dynamic is on, the screen's dynamic lights are appended via its callback.
func rebuild_lights() -> void:
	if fx == null or _stage == null or not is_instance_valid(_stage):
		return
	fx.clear_lights()
	if _mode == ShadowMode.KEY:
		var kl: PointLight2D = _stage.ensure_key_light()
		kl.energy = KEY_LIGHT_ENERGY
		fx.add_light(kl, 1.0, false)
	else:
		var existing_kl: PointLight2D = _stage.key_light_or_null()
		if existing_kl != null:
			existing_kl.energy = 0.0
			existing_kl.enabled = false
		if _mode == ShadowMode.FILL:
			for fl in _stage.fill_lights():
				fx.add_light(fl, 1.0, false)
	if _dynamic and _dynamic_lights_cb.is_valid():
		_dynamic_lights_cb.call(self)


# Rebuild the casters: nothing in LEGACY; otherwise the screen registers its bodies/ships via its callback
# plus the stage's clutter sprites (shared between both screens).
func rebuild_casters() -> void:
	if fx == null:
		return
	fx.clear_casters()
	if _mode == ShadowMode.LEGACY:
		return
	if _casters_cb.is_valid():
		_casters_cb.call(self)
	if _stage != null and is_instance_valid(_stage):
		var cl = _stage.clutter_node()
		if cl != null and is_instance_valid(cl):
			for c in cl.get_children():
				if c is Sprite2D:
					fx.add_caster(c, cl, -6)


# Thin pass-throughs so the screen callbacks read naturally (rig.add_caster / rig.add_dynamic_light).
func add_caster(src: Sprite2D, parent: Node, shadow_z: int = -2, lift_cb := Callable(), lift_px: float = 0.0) -> void:
	if fx != null:
		fx.add_caster(src, parent, shadow_z, lift_cb, lift_px)


func add_dynamic_light(node: Node2D, weight: float = 1.0, ref_energy: float = 1.0) -> void:
	if fx != null:
		fx.add_light(node, weight, true, ref_energy)


# Drop-shadow altitude pose: lerp offset/scale/alpha between the landed ("tight, dark") and flying
# ("spread, faint") states by `altitude` (0 = landed, 1 = flying). Scale lerps from 1.0 → `fly_scale`.
# Returns {offset, scale, alpha} — the caller applies them to whatever shadow it's driving. Shared by
# the dock cinematics (Roman 2026-07-02 refactor).
static func shadow_pose(altitude: float, land_offset: Vector2, fly_offset: Vector2, land_alpha: float, fly_alpha: float, fly_scale: float) -> Dictionary:
	return {
		"offset": land_offset.lerp(fly_offset, altitude),
		"scale": lerpf(1.0, fly_scale, altitude),
		"alpha": lerpf(land_alpha, fly_alpha, altitude),
	}
