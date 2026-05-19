extends Node2D
class_name ShipVisuals

# Modular-ship visual rig. Owns a stack of named child Sprite2Ds and exposes
# a small public API to swap each layer independently. All part PNGs share a
# 48-px frame and pre-bake their relative offset from the body anchor, so
# every overlay mounts at (0, 0) and is just z-sorted.
#
# Z order (Roman, 2026-05-16):
#   Weapon      (-1)  ← under the hull
#   Hull        ( 0)  ← base body
#   EngineMount ( 1)  ← static engine block (e.g. Big Pulse Engine.png)
#   EngineGlow  ( 2)  ← animated idle / powering strip atop the mount
#   Shield      ( 3)  ← above everything when active
#
# Weapons render as a single centered sprite, frame 0 of the strip. Mk-step
# / multi-mount visuals will land in a later phase.

const Catalog = preload("res://scripts/parts/ship_visuals_catalog.gd")

# Pixel-art animation cadence.
const ANIM_FPS := 10.0

var hull_sprite: Sprite2D
var engine_mount_sprite: Sprite2D
var engine_sprite: Sprite2D  # animated glow strip
var shield_sprite: Sprite2D
var weapon_sprite: Sprite2D

# Engine animation state (idle vs powering strip).
var _engine_idle_tex: Texture2D
var _engine_idle_frames: int = 1
var _engine_power_tex: Texture2D
var _engine_power_frames: int = 1
var _engine_powering: bool = false
var _engine_t: float = 0.0
var _engine_frame: int = 0

# Shield animation state.
var _shield_frames: int = 1
var _shield_t: float = 0.0
var _shield_frame: int = 0
var _shield_visible: bool = false


func _ready() -> void:
	_build_children()
	set_hull_state(Catalog.HullState.FULL)
	set_engine(Catalog.EngineModel.BASE)


func _build_children() -> void:
	weapon_sprite = _make_sprite("Weapon", -1)
	weapon_sprite.visible = false
	hull_sprite = _make_sprite("Hull", 0)
	engine_mount_sprite = _make_sprite("EngineMount", 1)
	engine_sprite = _make_sprite("EngineGlow", 2)
	shield_sprite = _make_sprite("Shield", 3)
	shield_sprite.visible = false


func _make_sprite(name: String, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = name
	# All part PNGs already encode their offset from the body anchor. So every
	# layer sits at (0, 0) and stacks via z_index.
	s.position = Vector2.ZERO
	s.z_index = z
	s.z_as_relative = true
	add_child(s)
	return s


# ---- Public swap API ----------------------------------------------------

func set_hull_state(state: int) -> void:
	if hull_sprite == null:
		return
	var tex: Texture2D = Catalog.HULL_TEXTURES.get(state, null)
	if tex:
		hull_sprite.texture = tex
		hull_sprite.hframes = 1
		hull_sprite.frame = 0


func set_hull_pct(pct: float) -> void:
	set_hull_state(Catalog.hull_state_for_pct(pct))


func set_engine(model: int) -> void:
	var entry: Dictionary = Catalog.ENGINES.get(model, {})
	if entry.is_empty():
		return
	# Static mount renders under the animated glow strip. Required so each
	# engine's physical block (radiator fins, intake, etc.) is visible — the
	# Idle/Powering sheets only contain the glow over the empty mount slot.
	var mount_tex: Texture2D = entry.get("mount")
	if engine_mount_sprite:
		engine_mount_sprite.texture = mount_tex
		engine_mount_sprite.hframes = 1
		engine_mount_sprite.frame = 0
		engine_mount_sprite.visible = mount_tex != null
	_engine_idle_tex = entry.get("idle")
	_engine_idle_frames = int(entry.get("idle_frames", 1))
	_engine_power_tex = entry.get("powering")
	_engine_power_frames = int(entry.get("powering_frames", 1))
	_engine_frame = 0
	_engine_t = 0.0
	_apply_engine_strip()


func set_engine_powering(on: bool) -> void:
	if _engine_powering == on:
		return
	_engine_powering = on
	_engine_frame = 0
	_engine_t = 0.0
	_apply_engine_strip()


func clear_engine() -> void:
	if engine_sprite:
		engine_sprite.texture = null
	if engine_mount_sprite:
		engine_mount_sprite.texture = null
		engine_mount_sprite.visible = false


# ---- Weapons ------------------------------------------------------------

# Mount a weapon model centered on the ship. Frame is pinned to 0 (smallest
# tier) for now; mark-based frame stepping is a follow-up phase.
func set_weapon(model: int) -> void:
	if weapon_sprite == null:
		return
	var entry: Dictionary = Catalog.WEAPONS.get(model, {})
	if entry.is_empty():
		clear_weapon()
		return
	weapon_sprite.texture = entry.get("texture")
	weapon_sprite.hframes = int(entry.get("hframes", 1))
	weapon_sprite.vframes = 1
	weapon_sprite.frame = 0
	weapon_sprite.visible = true


func clear_weapon() -> void:
	if weapon_sprite == null:
		return
	weapon_sprite.texture = null
	weapon_sprite.visible = false


# Brief vertical recoil kick on the weapon sprite. Sells the firing beat.
func recoil(amount: float = 2.0, duration: float = 0.08) -> void:
	if weapon_sprite == null or not weapon_sprite.visible:
		return
	var base: Vector2 = Vector2.ZERO
	weapon_sprite.position = base + Vector2(0, amount)
	var tw := create_tween()
	tw.tween_property(weapon_sprite, "position", base, duration).set_trans(Tween.TRANS_SINE)


# ---- Shields ------------------------------------------------------------

func set_shield(model: int) -> void:
	if shield_sprite == null:
		return
	var entry: Dictionary = Catalog.SHIELDS.get(model, {})
	if entry.is_empty():
		shield_sprite.texture = null
		return
	shield_sprite.texture = entry.get("texture")
	shield_sprite.hframes = int(entry.get("hframes", 1))
	shield_sprite.vframes = 1
	_shield_frames = shield_sprite.hframes
	_shield_frame = 0
	_shield_t = 0.0
	shield_sprite.frame = 0


func set_shield_visible(v: bool) -> void:
	if shield_sprite == null:
		return
	_shield_visible = v
	shield_sprite.visible = v


# ---- Per-frame animation ------------------------------------------------

func _process(delta: float) -> void:
	_tick_engine(delta)
	_tick_shield(delta)


func _tick_engine(delta: float) -> void:
	if engine_sprite == null or engine_sprite.texture == null:
		return
	if engine_sprite.hframes <= 1:
		return
	_engine_t += delta
	var step: float = 1.0 / ANIM_FPS
	while _engine_t >= step:
		_engine_t -= step
		_engine_frame = (_engine_frame + 1) % engine_sprite.hframes
		engine_sprite.frame = _engine_frame


func _tick_shield(delta: float) -> void:
	if not _shield_visible or shield_sprite == null or shield_sprite.texture == null:
		return
	if _shield_frames <= 1:
		return
	_shield_t += delta
	var step: float = 1.0 / ANIM_FPS
	while _shield_t >= step:
		_shield_t -= step
		_shield_frame = (_shield_frame + 1) % _shield_frames
		shield_sprite.frame = _shield_frame


func _apply_engine_strip() -> void:
	if engine_sprite == null:
		return
	if _engine_powering and _engine_power_tex:
		engine_sprite.texture = _engine_power_tex
		engine_sprite.hframes = _engine_power_frames
	elif _engine_idle_tex:
		engine_sprite.texture = _engine_idle_tex
		engine_sprite.hframes = _engine_idle_frames
	engine_sprite.vframes = 1
	engine_sprite.frame = 0
