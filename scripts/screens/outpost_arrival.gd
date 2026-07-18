class_name OutpostArrival
extends Control

# Outpost arrival sequence + dock screen (Roman 2026-06-19). A cinematic-led menu:
# the composed player ship flies in slowly from the bottom of the screen, decelerates
# to a stop over a landing pad and cuts its engines; a close drop shadow snaps tighter
# as it sets down (the "landing" cue). Black bars on the gutters then fade away to
# reveal the dock menus (left market/services, right ship-status/hold). Departing
# reverses it: UI fades back to the narrow play band, engines relight, the ship rises
# (shadow spreads) then launches off the top.
#
# RENDER MODEL (mirrors the loading-screen / HD dev-tool pattern, scripts/screens/
# loading_screen.gd): an HD (1920×1080) Control root composites a native 480×270
# SubViewport (star parallax + the outpost hangar plate + the ship + its shadow + engine
# plume, upscaled 4×) UNDER the HD menu Controls. The center 216-band (Playfield.X_MIN..
# X_MAX → HD 528..1392) is the visible landing strip; the two 132-px gutters host the side
# panels, masked by black ColorRects that fade on landing. The hangar plate descends from
# above as the ship lands and slides out below as it leaves (flying into/out of the hangar).
#
# DAMAGE VISUALS (Roman 2026-06-19): the composited ship wears the SAME damage-overlay
# shader the combat player uses (graphics/damage_noise.gdshader), plus damage tells —
# smoke (damage_smoke_trail) that emits only while the engine runs (so it STOPS once
# the ship sets down) and sparks (spark_trail_fx, replacing the engine-torch flames)
# that persist while damaged. The engine streak + tells respect EACH body's real engine
# markers (A: 1, B/C: 2). Drive the damage with `damage_level` (0 = pristine, 1 = wreck).
#
# SCOPE: the cinematic + the dock LAYOUT are real, and the inventory is LIVE when a run exists —
# the shop reads/writes Run's real loadout/economy/storage (the `_live` flag, set from run_seed).
# The self-contained MOCK item model (buy/pull/slot/swap/scrap/lock on a local dict) remains only as
# the fallback for the dev lab, where no run is present.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const EngineTrailFx = preload("res://scripts/effects/engine_trail_fx.gd")
const EngineSfx = preload("res://scripts/effects/engine_sfx.gd")
const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const DamageSmokeTrail = preload("res://scripts/effects/damage_smoke_trail.gd")
const PF = preload("res://scripts/systems/playfield.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
const ShipVisual = preload("res://scripts/ui/ship_visual.gd")

const DamageOverlayShader = preload("res://graphics/damage_noise.gdshader")
const _DamageNoiseTex = preload("res://resources/noise_damage.tres")
const _DamageEdgeTex = preload("res://resources/edge_distance_flat.tres")

# Backdrop: two-layer star parallax (deep void) behind the shared hangar plate. HangarPlate owns
# the plate sprite + the runway lights (shared with patrol_start); the plate descends in as the ship
# lands and slides out as it leaves — reading as flying into / out of the hangar. Roman 2026-06-20.
const STARS_SCENE := "res://scenes/parallax/layers/layer_stars.tscn"
const HANGAR_STAGE := "res://scenes/hangar_stage.tscn"   # shared authorable plate + runway + lights
const PointLightFx = preload("res://scripts/effects/point_light_fx.gd")
const DockShadowRig = preload("res://scripts/effects/dock_shadow_rig.gd")
const DockConst = preload("res://scripts/effects/dock_const.gd")
const DeckLifeScript = preload("res://scripts/screens/deck_life.gd")   # living-deck crew (rides the plate)
# Live shop wiring (production): the dock reads/writes the real Run loadout/economy. Mirrors outpost.gd.
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const PartTier = preload("res://scripts/parts/part_tier.gd")
const OutpostSfx = preload("res://scripts/effects/outpost_sfx.gd")   # carried over from the old outpost menu
const ArmoryStrings = preload("res://scripts/strings/armory_strings.gd")   # the Codex's item blurbs (one source)
const Conditions = preload("res://scripts/systems/conditions.gd")
# Top-bar stat icons — one 10×10 frame each: 0=hull, 1=super, 2=bounty, 3=materials (Roman 2026-06-29).
const ICON_SHEET = preload("res://graphics/ui/outpost_icons.png")
const ICON_FRAME := 10       # native px per frame (sheet is 40×10)
const ICON_DISPLAY := 30     # HD px shown = 3× (matches the 30px header text height; nearest-filtered, crisp)
const ICON_HULL := 0
const ICON_SUPER := 1
const ICON_BOUNTY := 2
const ICON_MAT := 3
const CHIP_ICON := 20        # inline chip icon px (market price / info values, 2×)
const BTN_ICON := 16         # button-located icon px (one step smaller so buttons aren't cramped)
const SHOP_MAX_MK := 9
const CANNON_BASE_COST := 116
const CANNON_COST_PER_MK := 70
const HULL_REPAIR_COST := 250
const SUPER_REFILL_COST := 120
const PRIMARY_REFILL_COST := 100
const SECONDARY_REFILL_COST := 60
const SERVICE_BTN_W := 144.0   # uniform service-button width — fits a tagged 3-digit price ("All  ₵999")
const CARD_BTN_W := 104.0      # scrap/sell card action button (icon + "+NNN")
const UPGRADE_BTN_W := 184.0   # upgrade card button ("Mk.N ◆N ₵NNN")
const WEAPONS_COLUMN_COUNT := 5
const WEAPON_SLOT_WEIGHTS := [
	SlotTypes.SlotType.CANNON, SlotTypes.SlotType.CANNON, SlotTypes.SlotType.CANNON, SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.HARDPOINT_WING, SlotTypes.SlotType.HARDPOINT_WING,
	SlotTypes.SlotType.DEVICE_BAY_1, SlotTypes.SlotType.MODULE, SlotTypes.SlotType.MODULE,
	SlotTypes.SlotType.SHIFT_MODE,   # shift modes are buyable items now (sold/scrapped/swapped like any part)
]

const ENGINE_GLOW_COLOR := DockConst.ENGINE_GLOW_COLOR   # #00d3ff — in-game engine glowmask
const ENGINE_GLOW_OFF := 0.0   # glowmask + engine-light level when the engine is OFF (landed) — fully dark
const TELL_ACTIVATE := 0.5   # missing-hull fraction at which smoke/sparks light (player default)
const SPARK_GRAVITY := 120.0  # gentle downward drift on the sparks (lower = "less velocity")
# Landed sparks crackle intermittently (not a constant fountain); frequency + density scale
# with damage. While moving they emit continuously (the motion trails them). Roman 2026-06-19.
const SPARK_BURST_DUR := 0.2          # emit window per landed puff (s)
const SPARK_SPRAY_DUR := 0.5          # damaged spool-up spray duration (s) — "engine starting up"
const SPARK_INTERVAL_LIGHT := 3.6     # seconds between puffs at threshold damage
const SPARK_INTERVAL_HEAVY := 1.4     # ... at full damage (more frequent)
const SPARK_AMOUNT_LIGHT := 8         # particles per puff at threshold damage
const SPARK_AMOUNT_HEAVY := 55        # ... at full damage (denser)
const SPARK_SPRAY_AMOUNT := 60        # emphatic spool-up spray on a damaged launch
const SPARK_LIFETIME := 0.5           # short-lived parked sparks
const SPARK_TRAIL_LIFETIME := 0.35    # short spark ribbons
const SPARK_RADIAL_VEL := 16.0        # low spark velocity (scene default ~50)
# Point lights: blue on each engine (follows the glow on/off), orange on each spark marker
# (flashes when the ship sparks). Roman 2026-06-20.
const ENGINE_LIGHT_COLOR := DockConst.ENGINE_LIGHT_COLOR
const ENGINE_LIGHT_ENERGY := DockConst.ENGINE_LIGHT_ENERGY   # bright — the engines are the dock's main light
const ENGINE_LIGHT_SCALE := 0.45          # FOCUSED nozzle glow (64px tex → ~29px); scale wasn't the issue,
                                          # a small bright light at the marker reads better (Roman 2026-06-26)
const ENGINE_LIGHT_GLOW_GAMMA := 0.5      # <1 → the lights come in EARLY as the glow mask fades in
const ENGINE_FLARE_PEAK := DockConst.ENGINE_FLARE_PEAK   # energy × at the moment of launch
const ENGINE_FLARE_SCALE := DockConst.ENGINE_FLARE_SCALE   # light-size × at launch (bright spot blooms)
const SPARK_LIGHT_COLOR := Color(1.0, 0.55, 0.12)
const SPARK_LIGHT_ENERGY := 1.0
const SPARK_LIGHT_SCALE := 0.25           # focused orange spark flash at the nozzle (64px tex → ~16px)
const SPARK_LIGHT_RATE := 8.0         # light energy attack/decay per second (flash speed)

# Per-variant art layers + engine marker positions (index = Run.ship_variant). The roster +
# nozzle offsets are the canonical ShipCatalog (its `body`/`livery`/`engine`/`engines` keys
# are exactly what _build_ship reads), so a new ship's dock cinematic comes along for free.
const VARIANTS := ShipCatalog.SHIPS

const NATIVE_W := DockConst.NATIVE_W
const NATIVE_H := DockConst.NATIVE_H
const SHIP_X := DockConst.SHIP_X      # 240 — native viewport centre
const HD_SCALE := DockConst.HD_SCALE
const HD_W := DockConst.HD_W
const HD_H := DockConst.HD_H
const GUTTER_HD := DockConst.GUTTER_HD   # 528 — left panel / mask right edge
const RIGHT_HD := DockConst.RIGHT_HD     # 1392 — right panel / mask left edge
const BAR_H := 150.0                # HD height of the top money bar / bottom action bar
const FLYOFF_TARGET_Y := DockConst.FLYOFF_TARGET_Y    # off the top edge, same as _run_outro

const ARM_SLOTS := ["PRIMARY", "SECONDARY", "SUPER"]
const SYS_SLOTS := ["MODULE_1", "MODULE_2", "MODULE_3"]

signal landed
signal departed
signal depart_requested   # bottom-bar Depart pressed (caller may intercept; default → depart())

enum State { ARRIVING, LANDED, DEPARTING, GONE }
enum ShopMode { NONE, SCRAP, SELL, UPGRADE }
# Shadow prototype: LEGACY = baked drop shadows; KEY = one central key light (single shadow);
# FILL = the bay's 2×3 fill lights (multi-shadow). + optional dynamic engine-light casters.
enum ShadowMode { LEGACY, KEY, FILL }

# ---- Identity (set before add_child; -1/false = read from Run) ----
@export var ship_variant: int = -1
@export var livery_color: Color = Color(0.90, 0.16, 0.16)
@export var livery_set: bool = false
@export var outpost_name: String = ""
@export var manage_hd_scope: bool = true
@export var return_to_map: bool = false   # PRODUCTION: on depart, fly out → return to the sector map
@export var damage_level: float = 0.0   # 0 = pristine, 1 = near-wreck; drives shader + tells

# ---- Tuning knobs (the dev lab drives these; defaults are the shipped feel) ----
@export var arrival_time: float = 3.0       # slow decelerating fly-in (s)
@export var start_y: float = 330.0          # native-Y below the screen the ship starts at
@export var land_y: float = 132.0           # native-Y the ship sets down at (on the landing circle)
@export var idle_bob: float = 0.0           # hover bob amplitude once landed (px; 0 = dead-static)
@export var idle_bob_period: float = 2.6
# Engine exhaust drifts ZERO here: unlike combat (world scrolls past a hovering ship), the
# dock ship ACTUALLY moves — the trail streaks off real motion, idles to nothing when static.
@export var engine_drift: float = 0.0
@export var engine_spool: float = 1.5       # engine glow power-down (landing) / spool-up (liftoff) fade (s)
# Drop shadow — offset/scale while descending ("high") vs landed ("tight").
@export var shadow_fly_offset: Vector2 = Vector2(4.0, 8.0)
@export var shadow_land_offset: Vector2 = Vector2(1.0, 2.5)
@export var shadow_fly_scale: float = 0.9
@export var shadow_land_scale: float = 1.0
@export var shadow_fly_alpha: float = 0.4
@export var shadow_land_alpha: float = 0.9
@export var shadow_settle_time: float = 1.0
# Reveal / exit timing.
@export var bars_fade_time: float = 0.3
@export var rise_time: float = 1.0
@export var flyoff_time: float = 1.0
@export var star_drift: float = 1500.0  # star-parallax scroll rate during fly-in/out (depth)
@export var scene_dim: float = 0.6  # uniform dim of the whole bay output (engine lights counteract it; 1 = full)
@export var runway_speed: float = 0.9   # runway-light pulse speed (rad/s; lower = slower)
# Deck life — wandering crew on the plate (docs/deck_life_plan_2026-07-04.md). Spawns once landed.
@export var deck_crew_count: int = 5
@export var deck_crew_speed: float = 0.8   # px/frame (well under the clarity ceiling)
@export var deck_crate_count: int = 3      # movable crates for the crate-carry / walk-to-box behaviors
@export var deck_lifter: bool = true       # spawn the hover lifter (a crew boards it to move crates)
# Light-derived shadow prototype (Roman 2026-06-26) — see ShadowMode. Default LEGACY = unchanged.
@export var shadow_mode: int = ShadowMode.LEGACY
@export var shadow_dynamic: bool = false   # also cast from the bright engine lights (fade with glow)
@export var shadow_length: float = 4.0
@export var shadow_alpha: float = 0.5
@export var shadow_falloff: float = 110.0
@export var shadow_softness: float = 0.0
@export var shadow_max: int = 6
const SHIP_SHADOW_LIFT := 12.0   # px the ship's light-derived shadow pulls away when "high" (faked drop height)

var _hd: HdViewportScope = null
var _world: SubViewport = null
var _ship: Node2D = null
var _body: Sprite2D = null
var _livery: Sprite2D = null
var _shadow: Sprite2D = null
var _engine_glow: Sprite2D = null
var _trail: EngineTrailFx = null
var _smoke = null              # DamageSmokeTrail
var _sparks: Array = []        # spark trail instances (one per engine marker)
var _damage_mat: ShaderMaterial = null
var _engine_on: bool = false
var _stars = null                  # layer_stars instance (two-layer parallax + deep-space void)
var _plate: Node2D = null          # shared hangar_stage instance (descends in / slides out); owns runway + fill
var _deck = null                   # DeckLife (crew), child of _plate so it rides in/out; built on landed
var _bg_tween: Tween = null
var _bg_center_y: float = 135.0    # plate rest position (centered) — set from plate_size()
var _bg_above_y: float = -135.0    # fully off the top (fly-in start)
var _bg_below_y: float = 405.0     # fully off the bottom (departure end)
var _sparks_on: bool = false
var _spark_t: float = 0.0          # countdown to the next landed puff
var _spark_burst_t: float = 0.0    # remaining emit time of the active puff
var _spray_t: float = 0.0          # remaining time of a damaged spool-up spray
var _engine_lights: Array = []     # blue PointLight2D per engine marker
var _spark_lights: Array = []      # orange PointLight2D per engine marker
var _light_tex: Texture2D = null
var _engine_flare: float = 1.0     # 1 normally; tweened up to ENGINE_FLARE_PEAK as the ship launches out
var _flare_tween: Tween = null
var _shadow_rig = null             # DockShadowRig (owns the LightShadowFx; null until built)
var _ship_altitude: float = 1.0    # 1 = flying (shadow pulled away for height), 0 = landed (tight)
var _skip_anim: bool = false       # cinematic skipped this visit (Settings dock-anim) → instant depart too

var _state: int = State.ARRIVING
var _t: float = 0.0
var _shadow_offset: Vector2 = Vector2.ZERO   # tweened; applied to the shadow each frame
var _shadow_scale: float = 1.0               # tweened
var _phase_tween: Tween = null
var _glow_tween: Tween = null
var _ui_tween: Tween = null

# Inventory mock (local model — see file header).
var _slots: Dictionary = {}
var _hold: Array = []
var _money: int = 0
var _materials: int = 0
var _shop_mode: int = ShopMode.NONE
var _market: Array = []            # market entries (item dicts; sold ones carry ["buyback"]=true)
var _left_tabs: TabContainer = null
var _live: bool = false            # true when Run is present + run_seed != 0
var _locked_parts: Array = []      # parts locked in hold (by part reference identity)

# UI refs.
var _left_panel: Control = null
var _right_panel: Control = null
var _top_bar: Control = null
var _bottom_bar: Control = null
var _left_sidebar: ColorRect = null    # persistent black gutter bg (menus read on solid black)
var _right_sidebar: ColorRect = null
var _money_lbl: Label = null
var _parts_lbl: Label = null
var _hull_lbl: Label = null
var _super_lbl: Label = null
var _icon_cache: Dictionary = {}   # frame → shared AtlasTexture
var _toast_lbl: Label = null
var _toast_tween: Tween = null
var _info_popup: Control = null
var _page_market: VBoxContainer = null
var _page_services: VBoxContainer = null
var _page_status: VBoxContainer = null
var _page_armaments: VBoxContainer = null
var _page_systems: VBoxContainer = null
var _page_hold: VBoxContainer = null
var _built: bool = false


func _ready() -> void:
	if manage_hd_scope:
		_hd = HdScreen.enter(self)
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resolve_identity()
	_init_inventory()
	_world = HdScreen.make_play_subviewport(self)
	# The bay dim lives in the hangar stage's own CanvasModulate (authored + tuned there), so the
	# screen no longer dims the container. Roman 2026-06-21.
	_build_backdrop()
	_build_ship()
	_build_clutter()
	_build_shadow_mgr()
	# Persistent black sidebars (behind the panels), then the menu Controls.
	_build_sidebars()
	_build_left_panel()
	_build_right_panel()
	_build_top_bar()
	_build_bottom_bar()
	_build_toast()
	_built = true
	# Outpost music. Also un-silences after the sector map ducked the audio for the
	# synchronous load (sector_map_v3._duck_music_for_load) — without this the outpost
	# would stay silent. Idempotent, so re-entries (e.g. back from the Codex) are fine.
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("outpost")
	if _consume_dock_skip():
		# Returning from a side trip (e.g. the Codex) lands immediately — no second fly-in. Only the
		# ARRIVAL is skipped; depart still animates normally unless dock cinematics are turned fully off.
		begin_landed()
		_skip_anim = (_dock_anim_mode() == 3)
	elif _should_play_cinematic():
		begin_arrival()
	else:
		begin_landed()
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_world, "Outpost Arrival")


func _resolve_identity() -> void:
	var run := get_node_or_null("/root/Run")
	if ship_variant < 0:
		ship_variant = int(run.ship_variant) if run != null and "ship_variant" in run else 0
	ship_variant = clampi(ship_variant, 0, VARIANTS.size() - 1)
	if not livery_set and run != null and "livery_chosen" in run and bool(run.livery_chosen):
		livery_color = run.livery_color
	if outpost_name.is_empty():
		outpost_name = _default_outpost_name(run)


func _default_outpost_name(run: Node) -> String:
	var seed_value: int = 0
	if run != null and "run_seed" in run:
		seed_value = int(run.run_seed) ^ abs(hash(String(run.current_node_id)))
	else:
		seed_value = randi()
	return SectorNameGenerator.generate(seed_value)


func _init_inventory() -> void:
	var run := get_node_or_null("/root/Run")
	_live = run != null and "run_seed" in run and int(run.run_seed) != 0
	if _live:
		_refresh_live()
		# Production opens the dock via a plain scene change (no damage_level set) — derive the ship's
		# visual fray from the real hull so a battle-worn ship looks it AND Repair has something to clear.
		damage_level = _hull_damage_fraction(run)
	else:
		_money = _run_int("bounty", 1250)
		_materials = _run_int("materials", 8)
		_slots = {
			"PRIMARY": _mk_item("Twin Cannon", "PRIMARY", 3, 40, "Rapid dual-bolt cannon. Mk scales fire-rate + damage."),
			"SECONDARY": _mk_item("Seeker Missiles", "SECONDARY", 2, 30, "Homing missile pod. Mk adds salvo size + tracking."),
			"SUPER": _mk_item("Super Pulse Bomb", "SUPER", 1, 60, "Screen-clearing blast. Mk adds charges + radius."),
			"MODULE_1": _mk_item("Shield Core", "MODULE", 2, 50, "Adds shield charges. Mk raises the charge pool."),
			"MODULE_2": _mk_item("Thrusters", "MODULE", 1, 35, "Raises move speed. Mk sharpens handling."),
			"MODULE_3": null,
			"SHIFT": _mk_item("Focus", "SHIFT_MODE", 1, 20, "Tap Shift for a burst of bonus crit chance. Mk widens the crit window."),
		}
		_hold = [
			_mk_item("Reinforced Hull", "MODULE", 4, 55, "Adds hull pips. Mk raises max hull."),
			_mk_item("Spread Cannon", "PRIMARY", 2, 40, "Wide pellet spread. Mk widens the cone + damage."),
			_mk_item("Repair Drone", "MODULE", 1, 25, "Slow passive hull repair between waves."),
		]
		_market = _base_offers()
		_locked_parts.clear()


func _mk_item(nm: String, kind: String, mark: int, scrap: int, desc: String, part = null, src: String = "") -> Dictionary:
	var item = {"name": nm, "kind": kind, "mark": mark, "max_mark": 9, "scrap": scrap, "locked": false, "desc": desc}
	if part != null:
		item["part"] = part
	if src != "":
		item["src"] = src
	return item


# Rebuild view-model dicts FROM Run so existing card builders stay compatible.
func _refresh_live() -> void:
	if not _live:
		return
	var run := get_node_or_null("/root/Run")
	if run == null:
		return

	_money = int(run.bounty)
	_materials = int(run.materials)
	_slots.clear()
	_hold.clear()
	_locked_parts.clear()

	# Two cannon slots (Roman 2026-06-29): a ship ALWAYS has a BLASTER (infinite, cannon_pool[0]) —
	# mandatory, but swappable blaster-for-blaster (the old one drops to the hold). The PRIMARY
	# (metered, cannon_pool[1]) is OPTIONAL — it can be removed, leaving the ship with just its blaster.
	var blaster = run.cannon_pool[0] if run.cannon_pool.size() > 0 else null
	if blaster != null:
		_slots["BLASTER"] = _mk_item(
			String(blaster.display_name), "PRIMARY", int(blaster.mark),
			_scrap_value(blaster), String(blaster.description),
			blaster, "blaster")
	else:
		_slots["BLASTER"] = null

	var primary = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
	if primary != null:
		_slots["PRIMARY"] = _mk_item(
			String(primary.display_name), "PRIMARY", int(primary.mark),
			_scrap_value(primary), String(primary.description),
			primary, "primary")
	else:
		_slots["PRIMARY"] = null

	var secondary = run.loadout_snapshot.get(int(SlotTypes.SlotType.HARDPOINT_WING), null)
	if secondary != null:
		_slots["SECONDARY"] = _mk_item(
			String(secondary.display_name), "SECONDARY", int(secondary.mark),
			_scrap_value(secondary), String(secondary.description),
			secondary, "loadout")
	else:
		_slots["SECONDARY"] = null

	var super_part = run.loadout_snapshot.get(int(SlotTypes.SlotType.DEVICE_BAY_1), null)
	if super_part != null:
		_slots["SUPER"] = _mk_item(
			String(super_part.display_name), "SUPER", int(super_part.mark),
			_scrap_value(super_part), String(super_part.description),
			super_part, "loadout")
	else:
		_slots["SUPER"] = null

	# Modules: map run.modules[i] to MODULE_0..5 pseudo-slots
	for i in range(6):
		var sid = "MODULE_%d" % (i + 1)
		if i < run.modules.size() and run.modules[i] != null:
			var mod = run.modules[i]
			_slots[sid] = _mk_item(
				String(mod.display_name), "MODULE", int(mod.mark),
				_scrap_value(mod), String(mod.description),
				mod, "modules")
		else:
			_slots[sid] = null

	# Shift mode (SHIFT_MODE slot) — now a first-class owned part (Info/Pull/Swap/Scrap/Sell/Upgrade),
	# not a hardcoded Focus/Phase/Hyper toggle. An empty slot falls back to Focus behavior in combat.
	var shift_part = run.loadout_snapshot.get(int(SlotTypes.SlotType.SHIFT_MODE), null)
	if shift_part != null:
		_slots["SHIFT"] = _mk_item(
			String(shift_part.display_name), "SHIFT_MODE", int(shift_part.mark),
			_scrap_value(shift_part), String(shift_part.description),
			shift_part, "shift")
	else:
		_slots["SHIFT"] = null

	# Hold: weapon_storage + inventory
	for i in range(run.weapon_storage.size()):
		var wp = run.weapon_storage[i]
		_hold.append(_mk_item(
			String(wp.display_name), _slot_type_kind(int(wp.slot_type)), int(wp.mark),
			_scrap_value(wp), String(wp.description),
			wp, "weapon_storage"))

	for i in range(run.inventory.size()):
		var ip = run.inventory[i]
		_hold.append(_mk_item(
			String(ip.display_name), _slot_type_kind(int(ip.slot_type)), int(ip.mark),
			_scrap_value(ip), String(ip.description),
			ip, "inventory"))

	# Market: load or roll offers
	_load_or_roll_live_offers()

	# Keep the top-bar hull + super readouts in sync with the refreshed Run state (pull/slot/swap/repair
	# all route through here; the labels no-op safely if the bar isn't built yet during _ready).
	_update_status()


# Map SlotType int to kind string
func _slot_type_kind(slot_type: int) -> String:
	var ST = SlotTypes.SlotType
	match slot_type:
		ST.CANNON: return "PRIMARY"
		ST.HARDPOINT_WING: return "SECONDARY"
		ST.DEVICE_BAY_1: return "SUPER"
		ST.MODULE: return "MODULE"
		ST.SHIFT_MODE: return "SHIFT_MODE"
	return "UNKNOWN"


# Build market from Run.outpost_weapon_offers or roll fresh
# The persisted stock lives in run.outpost_weapon_offers as REAL offers [{part,cost,sold,buyback?}]
# (shared by ref, persists across visits). _market is the VIEW the card builders read.
func _load_or_roll_live_offers() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		_market = _base_offers()
		return
	var have_stock: bool = not run.outpost_weapon_offers.is_empty()
	if run.outpost_needs_refresh or not have_stock:
		_roll_live_offers(run)
		run.outpost_needs_refresh = false
	_market = _market_view_from(run.outpost_weapon_offers)


# View-dicts (for the existing card builders) from the persisted real offers — skipping sold.
func _market_view_from(offers: Array) -> Array:
	var view: Array = []
	for o in offers:
		if bool(o.get("sold", false)):
			continue
		var part = o.get("part")
		if part == null:
			continue
		view.append({
			"name": String(part.display_name), "kind": _slot_type_kind(int(part.slot_type)),
			"mark": int(part.mark), "max_mark": SHOP_MAX_MK, "scrap": _scrap_value(part),
			"locked": false, "desc": String(part.description), "part": part,
			"cost": int(o.get("cost", 0)), "offer": o, "buyback": bool(o.get("buyback", false)),
		})
	return view


# Roll fresh stock into run.outpost_weapon_offers — real Parts via PartCatalog. Ported from
# outpost.gd:_roll_offers (drops the own-better/cannon-bump refinements; same slot weights + cost).
func _roll_live_offers(run) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var max_mk: int = mini(SHOP_MAX_MK, 3 + 3 * int(run.bosses_defeated))
	var offers: Array = []
	var seen: Dictionary = {}
	# Sector Conditions — Market Scarcity/Surplus shift the stock count (econ.stock_delta). SSOT = OutpostEcon.
	for i in OutpostEcon.stock_count(run, WEAPONS_COLUMN_COUNT):
		var picked = null
		var picked_mk: int = 1
		for attempt in 8:
			var slot: int = int(WEAPON_SLOT_WEIGHTS[rng.randi() % WEAPON_SLOT_WEIGHTS.size()])
			picked_mk = _roll_weighted_mark(rng, 1, max_mk)
			var part = PartCatalog.roll_for_slot(rng, slot, picked_mk)
			if part == null:
				continue
			var key: String = String(part.display_name)
			if seen.has(key):
				continue
			seen[key] = true
			picked = part
			break
		if picked == null:
			continue
		# Sector Conditions — Galactic Tariffs/Buyer's Market scale the STORED offer price at roll
		# time so display (market card) and spend (buy handler) read the same value. SSOT = OutpostEcon.
		offers.append({"part": picked, "cost": OutpostEcon.offer_price(run, _full_cost(picked)), "sold": false})
	run.outpost_weapon_offers = offers


func _roll_weighted_mark(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if hi <= lo:
		return clampi(lo, 1, SHOP_MAX_MK)
	var a: int = rng.randi_range(lo, hi)
	var b: int = rng.randi_range(lo, hi)
	# Sector Conditions — Shoddy Imports/Quality Goods shift the rolled Mk (econ.mk_bias),
	# clamped to [1, hi]; the triangular distribution is otherwise intact. SSOT = OutpostEcon.
	return OutpostEcon.bias_mark(get_node_or_null("/root/Run"), int(round(float(a + b) * 0.5)), hi)


func _full_cost(part) -> int:
	var mk: int = int(part.mark) if (part != null and "mark" in part) else 1
	return CANNON_BASE_COST + (mk - 1) * CANNON_COST_PER_MK


func _upgrade_bounty_cost(new_mk: int) -> int:
	return int(floor(0.5 * float(CANNON_BASE_COST + (new_mk - 1) * CANNON_COST_PER_MK)))


# Buy-equip routing (port of outpost.gd:_apply_part_to_player + _buy_slot_occupied): MODULE → bay
# (overflow to cargo); occupied target slot → cargo (no silent displace on purchase); empty → equip.
func _apply_part_buy(run, part) -> void:
	if part == null:
		return
	var slot: int = int(part.slot_type) if "slot_type" in part else -1
	if slot == SlotTypes.SlotType.MODULE:
		if not run.add_module(part):
			run.inventory.append(part)
		return
	if _buy_slot_occupied(run, part, slot):
		run.inventory.append(part)
	else:
		run.equip_part(part)


func _buy_slot_occupied(run, part, slot: int) -> bool:
	if slot == SlotTypes.SlotType.CANNON:
		var infinite: bool = part.has_method("ammo_at_mark") and int(part.ammo_at_mark(int(part.mark))) < 0
		if infinite:
			return run.cannon_pool.size() > 0
		return run.get_primary_cannon() != null
	return run.loadout_snapshot.get(slot, null) != null


# Scrap value = item's Mk (1 material per Mk)
func _scrap_value(part) -> int:
	return int(part.mark) if (part != null and "mark" in part) else 1


# True when the player can afford a bounty cost. `_money` is kept in sync with Run in live mode.
func _afford(cost: int) -> bool:
	return _money >= cost


# The BLASTER slot (cannon_pool[0], infinite) is MANDATORY — it can never be pulled/scrapped/sold, only
# swapped for another blaster from the hold (which drops the old one into the hold). That guarantees the
# player always leaves with a blaster. The metered PRIMARY (cannon_pool[1]) is freely removable.
# Live-only: the mock dock has a single demo cannon slot, no separate blaster.
func _is_core_blaster(sid: String) -> bool:
	return _live and sid == "BLASTER"


# ---- World build (native 480 SubViewport) ---------------------------------

func _build_backdrop() -> void:
	# Two-layer star parallax (its own black DeepSpace void) behind the hangar plate.
	_stars = load(STARS_SCENE).instantiate()
	_world.add_child(_stars)
	if _stars.has_method("reseed"):
		_stars.reseed(randi())
	# Shared authorable hangar stage (scenes/hangar_stage.tscn, also used by patrol_start): plate +
	# runway lights + ambient fill + slot markers. The plate is centred on the node; we DESCEND/SLIDE
	# the node. The whole bay output is dimmed by scene_dim (the container), not the plate.
	_plate = load(HANGAR_STAGE).instantiate()
	_plate.runway_speed = runway_speed
	_world.add_child(_plate)
	scene_dim = _plate.scene_dim   # adopt the hangar stage's authored dim
	var h: float = _plate.plate_size().y
	_bg_center_y = NATIVE_H / 2.0
	_bg_above_y = -h / 2.0
	_bg_below_y = NATIVE_H + h / 2.0
	_plate.position = Vector2(SHIP_X, _bg_above_y)


# Randomized crate clutter on the hangar stage (rides the plate as it descends). Stable per outpost
# REFRESH — not per visit/replay — so re-entering the same outpost looks the same until the shop
# re-rolls. Plus the parts-pile HOOK flanking the pad.
func _build_clutter() -> void:
	var seed_value := _clutter_seed()
	var baked := shadow_mode == ShadowMode.LEGACY   # light-derived modes project crate shadows instead
	_plate.scatter_clutter(seed_value, -1, baked)    # amount default (production lowers it by shop storage)
	_plate.flank_pile(seed_value, _flank_count(), baked)


# Production: seed from the shop-roll/refresh seed. For now: run seed ⊕ node ⊕ a refresh counter, or
# (no run, e.g. the lab) a stable hash of the outpost name → same across replays, re-rolls on refresh.
func _clutter_seed() -> int:
	var run := get_node_or_null("/root/Run")
	if run != null and "run_seed" in run:
		var refresh: int = int(run.get_meta("outpost_refresh", 0))
		var node_id := String(run.current_node_id) if "current_node_id" in run else ""
		return int(run.run_seed) ^ abs(hash(node_id)) ^ (refresh * 0x9E3779B1)
	return abs(hash(outpost_name))


# HOOK: production scales the flanking crate piles by the parked ship's parts/ammo/weapons.
func _flank_count() -> int:
	return 2


# ---- Light-derived shadow prototype (Roman 2026-06-26) --------------------
# Compares baked drop shadows (LEGACY) against shadows PROJECTED from a central KEY light or the bay's
# 2×3 FILL lights (multi-shadow), with optional bright dynamic (engine) casters. The lab drives the
# mode + knobs live. Default LEGACY = production behaviour unchanged.

func _build_shadow_mgr() -> void:
	_shadow_rig = DockShadowRig.new()
	_shadow_rig.setup(_world, _plate)
	# Per-screen registration: the ship body (with an altitude-lift callable so its shadow pulls away
	# when "high") + the dynamic engine lights. Clutter casters + key/fill lights are handled by the rig.
	_shadow_rig.set_casters_callback(func(rig) -> void:
		if _body != null and is_instance_valid(_body):
			rig.add_caster(_body, _world, -2, func() -> float: return _ship_altitude, SHIP_SHADOW_LIFT))
	_shadow_rig.set_dynamic_lights_callback(func(rig) -> void:
		for el in _engine_lights:
			rig.add_dynamic_light(el, 0.9, ENGINE_LIGHT_ENERGY))
	_apply_shadow_mode()


func set_shadow_mode(m: int) -> void:
	shadow_mode = m
	if not _built:
		return
	_build_clutter()   # re-scatter with/without baked shadows (same seed → same layout)
	_apply_shadow_mode()


func set_shadow_dynamic(on: bool) -> void:
	shadow_dynamic = on
	if _built and _shadow_rig != null:
		_shadow_rig.rebuild_lights()


func set_shadow_length(x: float) -> void:
	shadow_length = x
	_sync_shadow_knobs()


func set_shadow_alpha(x: float) -> void:
	shadow_alpha = x
	_sync_shadow_knobs()


func set_shadow_falloff(x: float) -> void:
	shadow_falloff = x
	_sync_shadow_knobs()


func set_shadow_softness(x: float) -> void:
	shadow_softness = x
	_sync_shadow_knobs()


func set_shadow_max(x: float) -> void:
	shadow_max = int(round(x))
	_sync_shadow_knobs()


func _apply_shadow_mode() -> void:
	if _shadow_rig == null:
		return
	var proto: bool = shadow_mode != ShadowMode.LEGACY
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.visible = not proto   # legacy ship drop shadow off in the light-derived modes
	_sync_shadow_knobs()
	_shadow_rig.apply(shadow_mode, shadow_dynamic)


func _sync_shadow_knobs() -> void:
	if _shadow_rig != null:
		_shadow_rig.sync_knobs(shadow_length, shadow_alpha, shadow_falloff, shadow_softness, shadow_max)


func _build_ship() -> void:
	var data: Dictionary = VARIANTS[clampi(ship_variant, 0, VARIANTS.size() - 1)]
	# Shared dock ship stack (body + livery sibling + additive glow + engine markers). Outpost keeps the
	# livery a SIBLING of the body, the body at its default z, and the glow lit at full color (the ship
	# arrives with engines running). The livery uses the SAME screen-multiply shader the in-game ship +
	# every other menu uses (body shaded THROUGH the tint @0.8, not a flat fill). The body is dimmed to
	# the hangar by its damage-overlay `brightness` and the livery samples that dimmed body, so the dim
	# flows through automatically — the livery keeps modulate WHITE (no double-dim).
	var built := ShipVisual.build_dock_ship(data, livery_color, false, 0, 1.0)
	var host: Node2D = built["host"]
	host.name = "DockShip"
	_body = built["body"]
	_livery = built["livery"]
	_engine_glow = built["glow"]
	var markers: Array = built["markers"]
	_world.add_child(host)
	host.position = Vector2(SHIP_X, start_y)
	_ship = host

	# Damage-overlay shader on the body (mirrors player._install_damage_material).
	_install_damage_material()

	# Drop shadow: a black silhouette of the body cell, behind the ship, animated to fake height.
	var shadow := Sprite2D.new()
	shadow.name = "DropShadow"
	shadow.texture = load(String(data["body"]))
	shadow.hframes = 3
	shadow.frame = 1
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.modulate = Color(0.0, 0.0, 0.0, shadow_fly_alpha)
	shadow.z_index = -2
	_world.add_child(shadow)
	_shadow = shadow

	# Engine streak — one Line2D trail per marker (engine_trail_fx handles plural markers).
	var trail := EngineTrailFx.new()
	host.add_child(trail)
	trail.setup(host, markers, ENGINE_GLOW_COLOR, engine_drift)
	_trail = trail

	# Damage tells: sparks at every nozzle (replacing the engine-torch flames), one smoke
	# column from the primary nozzle. Both driven by damage_level + engine state.
	_sparks.clear()
	for mk in markers:
		_attach_spark(mk.position)
	_attach_smoke(markers[0].position)
	# Point lights: blue engine light + orange spark light at each nozzle.
	_build_engine_lights(markers)
	_apply_damage()


# Mirrors scripts/game/player.gd::_install_damage_material — the health-driven fray overlay.
func _install_damage_material() -> void:
	if _body == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = DamageOverlayShader
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", _DamageNoiseTex)
	mat.set_shader_parameter("edge_distance_map", _DamageEdgeTex)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	mat.set_shader_parameter("max_strength", 0.9)
	mat.set_shader_parameter("edge_bias_strength", 0.3)
	mat.set_shader_parameter("details_opacity", 0.1)
	mat.set_shader_parameter("edge_color", Color("494e55"))
	mat.set_shader_parameter("details_color", Color("cacaca"))
	_body.material = mat
	_damage_mat = mat


func _attach_spark(pos: Vector2) -> void:
	var inst = SparkTrailFx.spawn(_ship, pos)
	if inst == null:
		return
	var p = SparkTrailFx.particles(inst)
	if p != null:
		# Dupe the process material so the downward drift only touches THIS spark (the scene
		# resource is shared). Mirrors spark_trail_fx.attach_to_player.
		if p.process_material != null:
			p.process_material = p.process_material.duplicate()
			var pm := p.process_material as ParticleProcessMaterial
			if pm != null:
				pm.gravity = Vector3(0.0, SPARK_GRAVITY, 0.0)
				pm.radial_velocity_min = 0.0
				pm.radial_velocity_max = SPARK_RADIAL_VEL   # slower sparks
		p.lifetime = SPARK_LIFETIME                         # shorter-lived
		p.trail_lifetime = SPARK_TRAIL_LIFETIME             # shorter ribbons
		p.amount = mini(p.amount, 60)
		p.emitting = false
	_sparks.append(inst)


# Cached light texture for the engine/spark point lights (shared PointLightFx; 64px to match the
# scales below). The runway lights make their own inside HangarPlate.
func _make_light_texture() -> Texture2D:
	if _light_tex == null:
		_light_tex = PointLightFx.make_texture(64)
	return _light_tex


func _build_engine_lights(markers: Array) -> void:
	_engine_lights.clear()
	_spark_lights.clear()
	var tex := _make_light_texture()
	for mk in markers:
		var el := _make_point_light(mk.position, ENGINE_LIGHT_COLOR, ENGINE_LIGHT_SCALE, tex)
		_ship.add_child(el)
		_engine_lights.append(el)
		var sl := _make_point_light(mk.position, SPARK_LIGHT_COLOR, SPARK_LIGHT_SCALE, tex)
		_ship.add_child(sl)
		_spark_lights.append(sl)


func _make_point_light(pos: Vector2, col: Color, scale: float, tex: Texture2D) -> PointLight2D:
	return PointLightFx.make(pos, col, scale, tex)


func _attach_smoke(pos: Vector2) -> void:
	var s = DamageSmokeTrail.new()
	s.emit_local = pos
	s.activate_below = TELL_ACTIVATE
	_ship.add_child(s)
	# set_player keeps its host reference valid (so its world-space line is positioned and not
	# faded out). The host has no hull_changed signal — we drive its level via _drive_smoke().
	s.set_player(_ship)
	_smoke = s


func _teardown_ship_fx() -> void:
	if _smoke != null and is_instance_valid(_smoke):
		_smoke.queue_free()
	_smoke = null
	for inst in _sparks:
		if is_instance_valid(inst):
			inst.queue_free()
	_sparks.clear()
	_engine_lights.clear()   # the PointLight2Ds are ship children, freed with it
	_spark_lights.clear()
	# The smoke's world-space Line2D lives under _world independently of its node — sweep it.
	if _world != null and is_instance_valid(_world):
		for c in _world.get_children():
			if c is Line2D and String(c.name).begins_with("DamageTrailLine"):
				c.queue_free()


# ---- Damage driving -------------------------------------------------------

# Re-evaluate shader + smoke for the current damage_level. Sparks are timed in _update_sparks
# (they read damage_level live each frame), so they self-heal when the level drops on repair.
func _apply_damage() -> void:
	if _damage_mat != null:
		_damage_mat.set_shader_parameter("sensitivity", clampf(0.6 * damage_level, 0.0, 0.6))
	_drive_smoke()


# Smoke emits only while the engine runs AND the ship is damaged — so it STOPS on landing.
func _drive_smoke() -> void:
	if _smoke == null or not is_instance_valid(_smoke):
		return
	var emit: bool = _engine_on and damage_level >= TELL_ACTIVATE
	var eff: float = damage_level if emit else 0.0
	_smoke._on_hull_changed(100, int(round(100.0 * (1.0 - eff))))


# Sparks (the flame replacement). While the ship MOVES they trail continuously; once LANDED
# they crackle in intermittent puffs whose density + frequency scale with damage. Driven per
# frame from _process so a repair (damage_level → 0) tapers them out live. Roman 2026-06-19.
func _update_sparks(delta: float) -> void:
	if _sparks.is_empty():
		return
	# A timed spool-up spray (damaged launch) takes priority — a short startup burst, then off.
	if _spray_t > 0.0:
		_spray_t -= delta
		if _spray_t <= 0.0:
			_set_sparks_emitting(false)
		return
	# Ambient sparks only while ARRIVING or LANDED + damaged (no trail during departure).
	if (_state != State.ARRIVING and _state != State.LANDED) or damage_level < TELL_ACTIVATE:
		if _sparks_on:
			_set_sparks_emitting(false)
		return
	if _state == State.LANDED:
		# Intermittent puffs — interval + density scale with damage. Roman 2026-06-20.
		if _sparks_on:
			_spark_burst_t -= delta
			if _spark_burst_t <= 0.0:
				_set_sparks_emitting(false)
		else:
			_spark_t -= delta
			if _spark_t <= 0.0:
				_begin_spark_burst()
	elif not _sparks_on:
		# Arriving: a continuous trail off the engines (the motion streaks it).
		_set_spark_amount(_spark_amount_for_damage())
		_set_sparks_emitting(true)


# Drive the point lights: blue engine lights track the engine glow brightness (so they fade
# out on landing + stutter on a damaged spool-up); orange spark lights flash on each puff.
func _update_lights(delta: float) -> void:
	var glow_ratio: float = 0.0
	if _engine_glow != null and is_instance_valid(_engine_glow):
		glow_ratio = clampf(_engine_glow.modulate.b / maxf(ENGINE_GLOW_COLOR.b, 0.001), 0.0, 1.0)
	# Remap the glow's off-floor → 0 so the engine light FULLY fades out when the engine is off (landed),
	# rather than lingering as a constant blue spill. Gamma < 1 makes it come in sooner on spool-up; the
	# launch flare boosts brightness + pool size, peaking as the ship accelerates off the top.
	var power: float = clampf((glow_ratio - ENGINE_GLOW_OFF) / maxf(1.0 - ENGINE_GLOW_OFF, 0.001), 0.0, 1.0)
	var lead: float = pow(power, ENGINE_LIGHT_GLOW_GAMMA)
	var flare_norm: float = clampf((_engine_flare - 1.0) / maxf(ENGINE_FLARE_PEAK - 1.0, 0.001), 0.0, 1.0)
	var tex_scale: float = ENGINE_LIGHT_SCALE * lerpf(1.0, ENGINE_FLARE_SCALE, flare_norm)
	for l in _engine_lights:
		if is_instance_valid(l):
			l.energy = lead * ENGINE_LIGHT_ENERGY * _engine_flare
			l.texture_scale = tex_scale
			l.enabled = l.energy > 0.0   # a disabled 0-energy light frees a plate light slot (16-cap)
	var spark_target: float = SPARK_LIGHT_ENERGY if _sparks_on else 0.0
	for l in _spark_lights:
		if is_instance_valid(l):
			l.energy = move_toward(l.energy, spark_target, SPARK_LIGHT_RATE * delta)
			l.enabled = l.energy > 0.0


func _begin_spark_burst() -> void:
	_set_spark_amount(_spark_amount_for_damage())
	_set_sparks_emitting(true)
	_spark_burst_t = SPARK_BURST_DUR
	_spark_t = _spark_interval()


# Emphatic spark spray off the engine(s) when a damaged ship fights to spool up — a ~0.5s
# startup burst (gated by _spray_t in _update_sparks), not a trail through the whole launch.
func _spool_spray() -> void:
	_set_spark_amount(SPARK_SPRAY_AMOUNT)
	_set_sparks_emitting(true)
	_spray_t = SPARK_SPRAY_DUR


func _set_sparks_emitting(on: bool) -> void:
	_sparks_on = on
	for inst in _sparks:
		var p = SparkTrailFx.particles(inst)
		if p != null:
			p.emitting = on


func _set_spark_amount(amt: int) -> void:
	for inst in _sparks:
		var p = SparkTrailFx.particles(inst)
		if p != null:
			p.amount = maxi(1, amt)


func _damage_norm() -> float:
	return clampf((damage_level - TELL_ACTIVATE) / (1.0 - TELL_ACTIVATE), 0.0, 1.0)


func _spark_amount_for_damage() -> int:
	return int(round(lerpf(float(SPARK_AMOUNT_LIGHT), float(SPARK_AMOUNT_HEAVY), _damage_norm())))


func _spark_interval() -> float:
	return lerpf(SPARK_INTERVAL_LIGHT, SPARK_INTERVAL_HEAVY, _damage_norm())


# Stutter the engine glow up (a damaged ship catching) over `dur`, ending at full brightness.
func _start_glow_stutter(dur: float) -> Tween:
	var steps := 6
	var sd: float = maxf(dur, 0.05) / float(steps)
	var tw := create_tween()
	for i in range(steps):
		if i == steps - 1:
			tw.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR, sd)   # settle to full
		elif i % 2 == 0:
			var frac: float = float(i + 1) / float(steps)
			tw.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR * lerpf(0.4, 0.9, frac), sd)
		else:
			tw.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR * 0.12, sd)   # flicker-dim
	return tw


# Toggle the engine: the blue streak + smoke follow it; the glow is tweened separately.
func _set_engine_active(on: bool) -> void:
	_engine_on = on
	if _trail != null and is_instance_valid(_trail):
		_trail.set_emitting(on)
	_drive_smoke()


# ---- HD menu build --------------------------------------------------------

# All anchors 0 → offsets are absolute HD coords (the root is exactly 1920×1080).
func _set_rect(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _panel(l: float, t: float, r: float, b: float, tint: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	_set_rect(p, l, t, r, b)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _tab_container() -> TabContainer:
	var tc := TabContainer.new()
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tc.add_theme_font_override("font", UiTheme.menu_font())
	tc.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	return tc


# A scrollable tab page; the ScrollContainer's name becomes the tab title. Vertical scroll only —
# horizontal scroll OFF so content is constrained to the page width (right-aligned buttons stay in the
# margin instead of overflowing). A MarginContainer keeps content clear of the right-hand scrollbar.
func _add_page(tc: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_left", 2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(v)
	scroll.add_child(margin)
	tc.add_child(scroll)
	return v


func _build_left_panel() -> void:
	var p := _panel(0.0, 0.0, GUTTER_HD, HD_H, Color(0.07, 0.05, 0.06, 0.92))
	_left_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_header("TRADE POST"))
	var tc := _tab_container()
	_left_tabs = tc
	_page_market = _add_page(tc, "MARKET")
	_page_services = _add_page(tc, "SERVICES")
	_page_status = _add_page(tc, "STATUS")
	v.add_child(tc)
	# Swapping back to the part market ends scrap/sell mode.
	tc.tab_changed.connect(func(idx: int) -> void:
		if idx == 0:
			_set_shop_mode(ShopMode.NONE))
	_rebuild_market()
	_rebuild_services()
	_rebuild_status()


func _build_right_panel() -> void:
	var p := _panel(RIGHT_HD, 0.0, HD_W, HD_H, Color(0.05, 0.06, 0.09, 0.92))
	_right_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_header("SHIP STATUS"))
	var tc := _tab_container()
	_page_armaments = _add_page(tc, "ARMAMENTS")
	_page_systems = _add_page(tc, "SYSTEMS")
	_page_hold = _add_page(tc, "HOLD")
	v.add_child(tc)
	_rebuild_inventory()


func _build_top_bar() -> void:
	var p := _panel(GUTTER_HD, 0.0, RIGHT_HD, BAR_H, Color(0.06, 0.05, 0.10, 0.88))
	_top_bar = p
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var name_lbl := _label(outpost_name.to_upper(), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	v.add_child(row)
	# Each field is [icon + number]: 0=hull, 1=super, 2=bounty, 3=materials (custom pixel-art icons).
	_hull_lbl = _stat_field(row, ICON_HULL, "", UiTheme.COLOR_TEXT, OutpostHelpStrings.TIP_HULL)
	_super_lbl = _stat_field(row, ICON_SUPER, "", UiTheme.COLOR_ACCENT, OutpostHelpStrings.TIP_SUPER)
	_money_lbl = _stat_field(row, ICON_BOUNTY, "%d" % _money, UiTheme.COLOR_BOUNTY, OutpostHelpStrings.TIP_BOUNTY)
	_parts_lbl = _stat_field(row, ICON_MAT, "%d" % _materials, UiTheme.COLOR_GREEN, OutpostHelpStrings.TIP_MATERIALS)
	_update_status()


# One top-bar stat: a pixel-art icon (frame `frame` of the outpost_icons sheet, nearest-filtered so it
# stays crisp at 4×) + a value Label. Returns the Label so callers can update the number; hull/super
# hide the whole field (icon included) when there's no data via _stat_visible().
func _stat_field(row: HBoxContainer, frame: int, initial: String, color: Color, tip: String = "") -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	# Hover tooltip explaining the resource (what it is + where it's found). STOP so the box gets hover.
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.tooltip_text = tip
	box.add_child(_icon_widget(frame, ICON_DISPLAY, color))
	var lbl := _label(initial, UiTheme.FONT_SIZE_HEADER, color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	row.add_child(box)
	return lbl


# ---- Stat-icon helpers (bounty / materials / hull / super across the menus) ----

# Cached AtlasTexture per frame (shared read-only across every widget).
func _icon_tex(frame: int) -> AtlasTexture:
	if not _icon_cache.has(frame):
		var a := AtlasTexture.new()
		a.atlas = ICON_SHEET
		a.region = Rect2(frame * ICON_FRAME, 0, ICON_FRAME, ICON_FRAME)
		_icon_cache[frame] = a
	return _icon_cache[frame]


# Each icon's canonical tint (matches the value colors used around the UI).
func _icon_color(frame: int) -> Color:
	match frame:
		ICON_HULL: return UiTheme.COLOR_TEXT
		ICON_SUPER: return UiTheme.COLOR_ACCENT
		ICON_BOUNTY: return UiTheme.COLOR_BOUNTY
		ICON_MAT: return UiTheme.COLOR_GREEN
	return UiTheme.COLOR_TEXT


# A crisp, nearest-filtered, color-tinted icon TextureRect sized to `px`.
func _icon_widget(frame: int, px: int, color: Color) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = _icon_tex(frame)
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.custom_minimum_size = Vector2(px, px)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = color
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


# Inline [icon + text] chip for a LABEL position (market price, info values). Non-interactive.
func _icon_chip(frame: int, text: String, color: Color) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_icon_widget(frame, CHIP_ICON, color))
	if text != "":
		var lbl := _label(text, UiTheme.FONT_SIZE_BODY, color)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lbl)
	return box


# A button whose FACE is a centered icon+number row (Button can't hold rich content directly, so the
# face is a full-rect child HBox with clicks passed through). Returns [button, face] for the caller to
# fill. Grays out (disabled) when not `enabled`.
func _face_button(width: float, enabled: bool, cb: Callable) -> Array:
	var b := UiTheme.make_button("", true)
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, 0)
	b.disabled = not enabled
	if enabled:
		b.pressed.connect(cb)
	var face := HBoxContainer.new()
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.add_theme_constant_override("separation", 5)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return [b, face]


func _face_add_text(face: HBoxContainer, text: String, color: Color) -> void:
	var l := _label(text, UiTheme.FONT_SIZE_BUTTON, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(l)


# A price/amount button: optional [lead icon] (hull/super identity, next to the quantity) + tag
# ("1"/"All"/"Fill") + [value icon][value]. Grays when not enabled. lead_frame < 0 = no lead icon.
func _price_button(lead_frame: int, tag: String, frame: int, value: String, enabled: bool, cb: Callable, width: float = 0.0) -> Button:
	var pair := _face_button(width, enabled, cb)
	var b: Button = pair[0]
	var face: HBoxContainer = pair[1]
	var col: Color = _icon_color(frame) if enabled else UiTheme.COLOR_DISABLED
	if lead_frame >= 0:
		face.add_child(_icon_widget(lead_frame, BTN_ICON, _icon_color(lead_frame) if enabled else UiTheme.COLOR_DISABLED))
	if tag != "":
		_face_add_text(face, tag, UiTheme.COLOR_TEXT if enabled else UiTheme.COLOR_DISABLED)
	face.add_child(_icon_widget(frame, BTN_ICON, col))
	_face_add_text(face, value, col)
	return b


# A dual-currency button (upgrade): lead tag ("Mk.N:") + [◆ mats][₵ cost]. Grays when not enabled.
func _dual_cost_button(tag: String, mats: int, bounty_cost: int, enabled: bool, cb: Callable, width: float = 0.0) -> Button:
	var pair := _face_button(width, enabled, cb)
	var b: Button = pair[0]
	var face: HBoxContainer = pair[1]
	var mc: Color = _icon_color(ICON_MAT) if enabled else UiTheme.COLOR_DISABLED
	var bc: Color = _icon_color(ICON_BOUNTY) if enabled else UiTheme.COLOR_DISABLED
	if tag != "":
		_face_add_text(face, tag, UiTheme.COLOR_TEXT if enabled else UiTheme.COLOR_DISABLED)
	face.add_child(_icon_widget(ICON_MAT, BTN_ICON, mc))
	_face_add_text(face, str(mats), mc)
	face.add_child(_icon_widget(ICON_BOUNTY, BTN_ICON, bc))
	_face_add_text(face, str(bounty_cost), bc)
	return b


# A labelled value row: "Label:" + [icon][value] chip (used in the info popup).
func _value_row(label_text: String, frame: int, value: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label(label_text, UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_FAINT))
	row.add_child(_icon_chip(frame, value, color))
	return row


# A wrapping mode-help line (caption size, tinted). RichTextLabel so the text can WRAP (the old
# single-line captions overflowed the panel) and carry inline ◆/₵ icons. Build via add_text/_help_icon.
func _mode_help(color: Color) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", UiTheme.menu_font())
	rt.add_theme_font_size_override("normal_font_size", UiTheme.FONT_SIZE_CAPTION)
	rt.add_theme_color_override("default_color", color)
	return rt


# Append an inline stat icon into a mode-help RichTextLabel (shared sheet, tinted, button-size).
func _help_icon(rt: RichTextLabel, frame: int) -> void:
	rt.add_image(ICON_SHEET, BTN_ICON, BTN_ICON, _icon_color(frame), INLINE_ALIGNMENT_CENTER, Rect2(frame * ICON_FRAME, 0, ICON_FRAME, ICON_FRAME))


func _open_options() -> void:
	var ov = load("res://scripts/ui/options_overlay.gd")
	if ov != null:
		ov.open(self)


# Codex: jump to the holo-shaded reference, returning to the dock afterward (the codex honors
# Run's one-shot `codex_return` meta). Only when we own the HD scope (production / standalone) —
# the embedded dev lab can't change scene out from under its host, so just toast there.
func _open_codex() -> void:
	if not manage_hd_scope:
		toast("Codex unavailable here")
		return
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.set_meta("codex_return", "res://scenes/outpost_arrival.tscn")
		run.set_meta("outpost_skip_cinematic", true)   # land straight away on the way back — no re-fly-in
	SceneTransition.change_scene(get_tree(), "res://scenes/enemy_codex.tscn", drop_hd_scope)


# One-shot: a side trip (Codex) sets this so the returning dock lands immediately instead of replaying
# the fly-in. Consumed here so it only affects the very next instantiation.
func _consume_dock_skip() -> bool:
	var run := get_node_or_null("/root/Run")
	if run != null and run.has_meta("outpost_skip_cinematic"):
		run.remove_meta("outpost_skip_cinematic")
		return true
	return false


func _build_bottom_bar() -> void:
	var p := _panel(GUTTER_HD, HD_H - BAR_H, RIGHT_HD, HD_H, Color(0.05, 0.07, 0.06, 0.88))
	_bottom_bar = p
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(row)
	var depart := UiTheme.make_button("DEPART")
	depart.custom_minimum_size = Vector2(220, 60)
	depart.pressed.connect(_on_depart_pressed)
	row.add_child(depart)
	var options := UiTheme.make_button("OPTIONS", true)
	options.custom_minimum_size = Vector2(180, 60)
	options.pressed.connect(_open_options)
	row.add_child(options)
	var codex := UiTheme.make_button("CODEX", true)
	codex.custom_minimum_size = Vector2(160, 60)
	codex.pressed.connect(_open_codex)
	row.add_child(codex)
	var help := UiTheme.make_button("?", true)
	help.custom_minimum_size = Vector2(70, 60)
	help.tooltip_text = "How the outpost works"
	help.pressed.connect(_show_help)
	row.add_child(help)


# Solid-black gutter backdrops that STAY on (so the side menus read on a solid background).
# Added before the panels → they sit behind them; never faded. Roman 2026-06-20.
func _build_sidebars() -> void:
	_left_sidebar = _sidebar(0.0, 0.0, GUTTER_HD, HD_H)
	_right_sidebar = _sidebar(RIGHT_HD, 0.0, HD_W, HD_H)


func _sidebar(l: float, t: float, r: float, b: float) -> ColorRect:
	var m := ColorRect.new()
	m.color = Color(0, 0, 0, 1)
	_set_rect(m, l, t, r, b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	return m


func _build_toast() -> void:
	_toast_lbl = _label("", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_ACCENT)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(_toast_lbl, GUTTER_HD, HD_H - BAR_H - 64.0, RIGHT_HD, HD_H - BAR_H - 24.0)
	_toast_lbl.modulate.a = 0.0
	_toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_lbl)


# ---- Left panel: market + services ----------------------------------------

func _rebuild_market() -> void:
	if _page_market == null:
		return
	_clear(_page_market)
	_page_market.add_child(_caption("Buy parts → hold (sold parts list here for buyback)"))
	if _market.is_empty():
		_page_market.add_child(_label("(stock cleared)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_DISABLED))
	for entry in _market:
		_page_market.add_child(_market_card(entry))
	_page_market.add_child(_spacer())


func _base_offers() -> Array:
	return [
		_mk_item("Heavy Cannon", "PRIMARY", 3, 50, "High-damage slow cannon. Mk adds pierce."),
		_mk_item("Flak Pod", "SECONDARY", 2, 35, "Short-range flak burst. Mk widens the burst."),
		_mk_item("Overcharge", "SUPER", 1, 70, "Brief fire-rate surge. Mk extends duration."),
		_mk_item("Plating", "MODULE", 2, 45, "Flat damage reduction. Mk raises the cut."),
	]


# A market entry. Normal stock → BUY at full price; a sold part (buyback flag) → BUYBACK at
# the 20% it sold for, until the player departs (then it rises to full price).
func _market_card(entry: Dictionary) -> PanelContainer:
	var card := _card_frame()
	var v: VBoxContainer = card.get_child(0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	# Name only — the Mk lives in the subtitle below (no "· Mk.N" tail).
	var nm := _label(String(entry["name"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	row.add_child(nm)
	var is_bb: bool = bool(entry.get("buyback", false))
	var price: int = _sell_price(entry) if is_bb else int(entry.get("cost", _item_value(entry)))
	var afford: bool = _afford(price)
	# Can't afford it → the price reddens and the buy button grays out.
	row.add_child(_icon_chip(ICON_BOUNTY, str(price), UiTheme.COLOR_BOUNTY if afford else UiTheme.COLOR_DANGER))
	# Compact "i" info button (the full label pushed BUY out of frame). Same popup as owned parts.
	row.add_child(_info_btn(entry))
	var btn := UiTheme.make_button("BUYBACK" if is_bb else "BUY", true)
	btn.disabled = not afford
	if afford:
		btn.pressed.connect(func() -> void: _buy_market(entry))
	row.add_child(btn)
	v.add_child(row)
	v.add_child(_label(_card_subtitle_live(entry), UiTheme.FONT_SIZE_CAPTION + 2, _tier_color(entry)))
	if is_bb:
		v.add_child(_label("· sold — buyback until you depart", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	return card


func _buy_market(entry: Dictionary) -> void:
	var is_bb: bool = bool(entry.get("buyback", false))
	var price: int = _sell_price(entry) if is_bb else int(entry.get("cost", _item_value(entry)))
	if _money < price:
		toast("Not enough ₵")
		return
	OutpostSfx.play("equip")
	deck_react("buy")   # a crew jogs over to take delivery
	if _live:
		var run := get_node_or_null("/root/Run")
		var part = entry.get("part")
		if run == null or part == null:
			return
		run.spend_bounty(price)
		_apply_part_buy(run, part)
		var offer = entry.get("offer")
		if offer != null:
			run.outpost_weapon_offers.erase(offer)
		toast("%s %s" % ["Bought back" if is_bb else "Bought", entry["name"]])
		_refresh_live()
		_update_money_parts()
		_rebuild_market()
		_rebuild_inventory()
	else:
		_money -= price
		_market.erase(entry)
		var item := entry.duplicate()
		item.erase("buyback")
		_hold.append(item)
		toast("%s %s → hold" % ["Bought back" if is_bb else "Bought", entry["name"]])
		_update_money_parts()
		_rebuild_market()
		_rebuild_hold()


func _item_value(item: Dictionary) -> int:
	return 80 + int(item["mark"]) * 80


func _sell_price(item: Dictionary) -> int:
	return int(round(0.2 * float(_item_value(item))))


func _rebuild_services() -> void:
	if _page_services == null:
		return
	_clear(_page_services)
	_page_services.add_child(_caption("Repair, rearm and upgrade"))
	var run := get_node_or_null("/root/Run")
	# Each button grays when it's UNNECESSARY (would no-op — full / nothing to refill / no charges) or
	# unaffordable. Repair + Super refill per-pip/per-charge, so they get a "1" and an "All" button; ammo
	# refills top up the whole magazine in one go (single "Fill"). All buttons are a fixed width so a 60₵
	# price is the same size as a 999₵ one.
	if _live and run != null:
		# Repair — gated on the REAL hull (current_hull < max_hull), NOT the decorative damage_level
		# (production never sets damage_level, so the old gate left Repair grayed forever). 1 charge / pip.
		var pips: int = maxi(0, int(run.max_hull) - int(run.current_hull))
		var chg: int = int(run.repair_charges)
		# Sector Conditions — repairs cost bounty + materials at baseline (design §8), condition-adjusted
		# by the repair pairs. One OutpostEcon call feeds BOTH the button label and _do_repair's spend.
		var rc: Dictionary = OutpostEcon.repair_costs(run, HULL_REPAIR_COST)
		var r_bounty: int = int(rc["bounty"])
		var r_mats: int = int(rc["mats"])
		_page_services.add_child(_service_row("Repair Hull", [
			_repair_btn("1", r_mats, r_bounty, pips >= 1 and chg >= 1, func() -> void: _do_repair(1)),
			_repair_btn("All", r_mats * pips, r_bounty * pips, pips >= 1 and chg >= pips, func() -> void: _do_repair(pips)),
		]))
		# Sector Conditions — Costly/Cheap Restock scale every flat restock cost (econ.restock_cost_mult).
		_page_services.add_child(_service_row("Refill Primary", [
			_svc_btn(-1, "Fill", OutpostEcon.restock_cost(run, PRIMARY_REFILL_COST), _refill_primary_avail(run), _on_refill_primary_ammo)]))
		_page_services.add_child(_service_row("Refill Secondary", [
			_svc_btn(-1, "Fill", OutpostEcon.restock_cost(run, SECONDARY_REFILL_COST), _refill_secondary_avail(run), _on_refill_secondary_ammo)]))
		var sneed: int = maxi(0, int(run.max_super_charges) - int(run.super_charges))
		var super_cost: int = OutpostEcon.restock_cost(run, SUPER_REFILL_COST)
		_page_services.add_child(_service_row("Refill Super", [
			_svc_btn(ICON_SUPER, "1", super_cost, sneed >= 1, func() -> void: _on_refill_super(1)),
			_svc_btn(ICON_SUPER, "All", sneed * super_cost, sneed >= 1, func() -> void: _on_refill_super(sneed)),
		]))
	else:
		# Mock (dev lab) — single stub buttons off the visual damage_level.
		_page_services.add_child(_service_row("Repair Hull", [
			_svc_btn(ICON_HULL, "Fix", HULL_REPAIR_COST, damage_level > 0.01, func() -> void: _do_repair(1))]))
		_page_services.add_child(_service_row("Refill Primary", [
			_svc_btn(-1, "Fill", PRIMARY_REFILL_COST, true, func() -> void: toast("Refilled primary ammo (stub)"))]))
		_page_services.add_child(_service_row("Refill Super", [
			_svc_btn(ICON_SUPER, "Fill", SUPER_REFILL_COST, true, func() -> void: toast("Refilled super (stub)"))]))
	_page_services.add_child(HSeparator.new())
	_page_services.add_child(_label("PART HANDLING", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	# Scrap / Sell put the shop in a mode that retargets the owned-part action buttons.
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	var scrap_btn := UiTheme.make_button("Scrap", true)
	if _shop_mode == ShopMode.SCRAP:
		scrap_btn.add_theme_color_override("font_color", UiTheme.COLOR_DANGER)
	scrap_btn.pressed.connect(func() -> void: _toggle_shop_mode(ShopMode.SCRAP))
	modes.add_child(scrap_btn)
	var sell_btn := UiTheme.make_button("Sell", true)
	if _shop_mode == ShopMode.SELL:
		sell_btn.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	sell_btn.pressed.connect(func() -> void: _toggle_shop_mode(ShopMode.SELL))
	modes.add_child(sell_btn)
	# Upgrade is its own mode now (like scrap/sell) — it lists every owned part and Mk-ups the ones the
	# player can afford, instead of a fixed upgrade button bolted onto each card. Live-only (real parts).
	if _live:
		var up_btn := UiTheme.make_button("Upgrade", true)
		if _shop_mode == ShopMode.UPGRADE:
			up_btn.add_theme_color_override("font_color", UiTheme.COLOR_GREEN)
		up_btn.pressed.connect(func() -> void: _toggle_shop_mode(ShopMode.UPGRADE))
		modes.add_child(up_btn)
	_page_services.add_child(modes)
	# Mode help — wrapping RichTextLabels (the old single-line captions overflowed into the bay) with the
	# ◆/₵ icons inline instead of glyphs.
	if _shop_mode == ShopMode.SCRAP:
		var h := _mode_help(UiTheme.COLOR_DANGER)
		h.add_text("SCRAP MODE — tap an owned part to break it into ")
		_help_icon(h, ICON_MAT)
		h.add_text(" materials.")
		_page_services.add_child(h)
	elif _shop_mode == ShopMode.SELL:
		var h := _mode_help(UiTheme.COLOR_BOUNTY)
		h.add_text("SELL MODE — tap an owned part to sell for 20% ")
		_help_icon(h, ICON_BOUNTY)
		h.add_text(" (buyable back until you depart).")
		_page_services.add_child(h)
	elif _shop_mode == ShopMode.UPGRADE:
		var h := _mode_help(UiTheme.COLOR_GREEN)
		h.add_text("UPGRADE MODE — tap an owned part to Mk-up (costs ")
		_help_icon(h, ICON_MAT)
		h.add_text(" + ")
		_help_icon(h, ICON_BOUNTY)
		h.add_text("; grayed when maxed or unaffordable).")
		_page_services.add_child(h)
	_page_services.add_child(_spacer())


# ---- STATUS tab — active-Conditions detail view ---------------------------
# Patrol-static modifiers listed with their impact (difficulty sign and value).
# Each condition has an ⓘ button that opens a detail popup showing the label,
# signed value, blurb, and category.

func _rebuild_status() -> void:
	if _page_status == null:
		return
	_clear(_page_status)
	var run := get_node_or_null("/root/Run")
	var active: Array = []
	if run != null and "active_conditions" in run:
		active = run.active_conditions

	# Header with Difficulty value and count badge.
	if active.is_empty():
		_page_status.add_child(_caption("No active modifiers"))
		return

	var net: int = 0
	if run != null and run.has_method("condition_net_threat"):
		net = run.condition_net_threat()
	var hdr := _label("Difficulty: %+d" % net, UiTheme.FONT_SIZE_BODY, Color(0.95, 0.86, 0.45))
	_page_status.add_child(hdr)
	_page_status.add_child(HSeparator.new())

	# Rows sorted by threat descending (banes first, then boons).
	var sorted: Array = active.duplicate()
	sorted.sort_custom(func(a, b): return Conditions.threat_of(String(a)) > Conditions.threat_of(String(b)))

	# Rows go DIRECTLY on the page VBox — _add_page already wraps every page in a
	# ScrollContainer, and a nested inner scroll with EXPAND_FILL has no bounded
	# height inside it, so it collapses to 0 and the rows render invisible (the
	# "Difficulty but no modifiers" bug, Roman 2026-07-12). The page scroll owns overflow.
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_status.add_child(rows)

	for id in sorted:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := _label(Conditions.label(String(id)), UiTheme.FONT_SIZE_BODY, Color(0.90, 0.93, 0.98))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_lbl)

		# Threat chip — warm for bane (+), cool for boon (−).
		var t: int = Conditions.threat_of(String(id))
		var chip := _label(("%+d" % t) if t > 0 else ("%d" % t), UiTheme.FONT_SIZE_BODY,
			Color(0.95, 0.72, 0.55) if t > 0 else Color(0.55, 0.95, 0.75))
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.custom_minimum_size = Vector2(52, 0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)

		# Info button opens the condition detail popup.
		var info_btn := UiTheme.make_button("i", true)
		info_btn.custom_minimum_size = Vector2(40, 0)
		info_btn.pressed.connect(_show_condition_info.bind(String(id)))
		row.add_child(info_btn)

		rows.add_child(row)


func _show_condition_info(id: String) -> void:
	_close_info()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_info())
	add_child(dim)
	_info_popup = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.98)
	sb.border_color = UiTheme.COLOR_ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(600, 0)
	panel.add_child(v)

	# Title: condition label, colored by sign (threat).
	var t: int = Conditions.threat_of(id)
	var threat_color: Color = Color(0.95, 0.72, 0.55) if t > 0 else Color(0.55, 0.95, 0.75)
	var title := _label(Conditions.label(id), UiTheme.FONT_SIZE_TITLE, threat_color)
	v.add_child(title)

	# Signed difficulty value.
	var diff_text: String = "Difficulty: %+d" % t
	var diff_lbl := _label(diff_text, UiTheme.FONT_SIZE_BODY, threat_color)
	v.add_child(diff_lbl)

	# Blurb (wrapping).
	var blurb_text := Conditions.blurb(id)
	if blurb_text != "":
		var blurb := _label(blurb_text, UiTheme.FONT_SIZE_BODY, Color(0.78, 0.85, 0.92))
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(560, 0)
		v.add_child(blurb)

	# Category (e.g. "ENEMY", "PLAYER", "ECONOMY").
	var category := Conditions.category_of(id)
	if category != "":
		v.add_child(HSeparator.new())
		var cat_lbl := _label("Category: " + category, UiTheme.FONT_SIZE_CAPTION, Color(0.62, 0.80, 0.92))
		v.add_child(cat_lbl)

	var close := UiTheme.make_button("Close")
	close.pressed.connect(_close_info)
	v.add_child(close)


func _toggle_shop_mode(mode: int) -> void:
	_set_shop_mode(ShopMode.NONE if _shop_mode == mode else mode)


func _set_shop_mode(mode: int) -> void:
	if _shop_mode == mode:
		return
	_shop_mode = mode
	_rebuild_services()
	_rebuild_inventory()


# Departing for a node ends buyback: any sold parts still listed rise back to full price.
func _complete_node_shop() -> void:
	if _live:
		var run := get_node_or_null("/root/Run")
		if run != null:
			for o in run.outpost_weapon_offers:
				if bool(o.get("buyback", false)):
					o["buyback"] = false
			_market = _market_view_from(run.outpost_weapon_offers)
		_rebuild_market()
		return
	for e in _market:
		if bool(e.get("buyback", false)):
			e.erase("buyback")
	_rebuild_market()


# A service row: a title label + one or more fixed-width price buttons (built by _svc_btn). The title
# grays when every button is disabled (nothing to do). The hull/super identity icon lives IN the
# buttons (next to the quantity), not on the label.
func _service_row(title: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var any_enabled: bool = false
	for b in buttons:
		if not b.disabled:
			any_enabled = true
	var nm := _label(title, UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT if any_enabled else UiTheme.COLOR_DISABLED)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	row.add_child(nm)
	for b in buttons:
		row.add_child(b)
	return row


# One fixed-width service button: [lead icon] TAG [₵ cost]. lead_frame (hull/super) sits next to the
# quantity so you read "1 hull for ₵250". Uniform width; grayed when unavailable OR unaffordable.
func _svc_btn(lead_frame: int, tag: String, cost: int, available: bool, cb: Callable) -> Button:
	return _price_button(lead_frame, tag, ICON_BOUNTY, str(cost), available and _afford(cost), cb, SERVICE_BTN_W)


# Repair button: [hull][tag] (◆mats) ₵bounty. Repairs cost bounty + materials at baseline (condition-
# adjusted via OutpostEcon), so the mats chip shows whenever mats > 0 and affordability gates on BOTH
# currencies — display and spend both derive from the same OutpostEcon.repair_costs call in _rebuild_services.
func _repair_btn(tag: String, mats: int, bounty_cost: int, available: bool, cb: Callable) -> Button:
	var run := get_node_or_null("/root/Run")
	var have_mats: int = int(run.materials) if run != null else 0
	var enabled: bool = available and _afford(bounty_cost) and (mats <= 0 or have_mats >= mats)
	var pair := _face_button(SERVICE_BTN_W, enabled, cb)
	var face: HBoxContainer = pair[1]
	face.add_child(_icon_widget(ICON_HULL, BTN_ICON, _icon_color(ICON_HULL) if enabled else UiTheme.COLOR_DISABLED))
	if tag != "":
		_face_add_text(face, tag, UiTheme.COLOR_TEXT if enabled else UiTheme.COLOR_DISABLED)
	if mats > 0:
		var mc: Color = _icon_color(ICON_MAT) if enabled else UiTheme.COLOR_DISABLED
		face.add_child(_icon_widget(ICON_MAT, BTN_ICON, mc))
		_face_add_text(face, str(mats), mc)
	var bc: Color = _icon_color(ICON_BOUNTY) if enabled else UiTheme.COLOR_DISABLED
	face.add_child(_icon_widget(ICON_BOUNTY, BTN_ICON, bc))
	_face_add_text(face, str(bounty_cost), bc)
	return pair[0]


# Per-service "is there anything to do?" predicates — mirror each refill handler's success guards so a
# grayed button always corresponds to a no-op (full / nothing equipped / out of restock charges).
func _refill_primary_avail(run) -> bool:
	if run == null:
		return false
	var cannon = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
	if cannon == null or not ("current_ammo" in cannon) or not ("ammo_max" in cannon):
		return false
	if int(cannon.ammo_max) <= 0 or int(cannon.current_ammo) >= int(cannon.ammo_max):
		return false
	return int(run.ammo_restock_charges) > 0


func _refill_secondary_avail(run) -> bool:
	if run == null:
		return false
	if int(run.secondary_ammo) < 0 or int(run.secondary_ammo_max) <= 0:
		return false
	if int(run.secondary_ammo) >= int(run.secondary_ammo_max):
		return false
	return int(run.ammo_restock_charges) > 0


# Repair up to `times` hull pips (250₵ + 1 repair charge each). Gated on the REAL hull, not the
# decorative damage_level (which production never sets). The shader fray recedes to match the new hull.
func _do_repair(times: int = 1) -> void:
	if not _live:
		# Mock (dev lab): one visual heal off damage_level, no Run.
		if damage_level <= 0.01:
			toast("Hull already pristine")
			return
		if _money < HULL_REPAIR_COST:
			toast("Not enough ₵")
			return
		_money -= HULL_REPAIR_COST
		_update_money_parts()
		repair()
		OutpostSfx.play("repair")
		toast("Hull repaired — damage clearing")
		return

	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	if int(run.current_hull) >= int(run.max_hull):
		toast("Hull already full")
		return
	# Sector Conditions — per-pip cost (bounty + materials) via the ONE OutpostEcon call the button
	# label also uses, so the shown cost can never drift from the charged cost. Conditions are
	# patrol-static, so resolve once before the loop.
	var rc: Dictionary = OutpostEcon.repair_costs(run, HULL_REPAIR_COST)
	var pip_bounty: int = int(rc["bounty"])
	var pip_mats: int = int(rc["mats"])
	var did: int = 0
	for _i in range(maxi(1, times)):
		if int(run.current_hull) >= int(run.max_hull):
			break
		if int(run.repair_charges) <= 0:
			if did == 0: toast("No repair charges left")
			break
		if int(run.bounty) < pip_bounty:
			if did == 0: toast("Not enough ₵")
			break
		if pip_mats > 0 and int(run.materials) < pip_mats:
			if did == 0: toast("Need ◆%d to repair" % pip_mats)
			break
		run.spend_bounty(pip_bounty)
		if pip_mats > 0:
			run.spend_materials(pip_mats)
		run.repair_charges -= 1
		run.current_hull = clampi(int(run.current_hull) + 1, 0, int(run.max_hull))
		did += 1
	if did > 0:
		OutpostSfx.play("repair")
		deck_react("repair")   # crew come weld the hull as the fray recedes
		repair(_hull_damage_fraction(run))   # tween the fray down to match the restored hull
		toast("Hull repaired" if did == 1 else "Hull repaired ×%d" % did)
		_refresh_live()
		_update_money_parts()


# Visual damage_level for a hull state: 0 = full hull, 1 = empty. Keeps the dock ship's fray in sync
# with the real hull (production opens the dock via a plain scene change and never sets damage_level).
func _hull_damage_fraction(run) -> float:
	if run == null or int(run.max_hull) <= 0:
		return 0.0
	return clampf(1.0 - float(run.current_hull) / float(run.max_hull), 0.0, 1.0)


func _on_refill_primary_ammo() -> void:
	if not _live:
		toast("Refill primary ammo (stub)")
		return
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	var cannon = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
	if cannon == null or not ("current_ammo" in cannon) or not ("ammo_max" in cannon):
		toast("No primary weapon to refill")
		return
	if int(cannon.current_ammo) >= int(cannon.ammo_max):
		toast("Primary ammo already full")
		return
	if int(run.ammo_restock_charges) <= 0:
		toast("No ammo restock charges left")
		return
	var cost: int = OutpostEcon.restock_cost(run, PRIMARY_REFILL_COST)  # Sector Conditions restock mult
	if int(run.bounty) < cost:
		toast("Not enough bounty")
		return
	run.spend_bounty(cost)
	run.ammo_restock_charges -= 1
	cannon.current_ammo = int(cannon.ammo_max)
	run.ammo = int(cannon.ammo_max)
	OutpostSfx.play("repair")
	toast("Primary ammo refilled")
	_refresh_live()
	_update_money_parts()


func _on_refill_secondary_ammo() -> void:
	if not _live:
		toast("Refill secondary ammo (stub)")
		return
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	if int(run.secondary_ammo) < 0 or int(run.secondary_ammo_max) <= 0:
		toast("No secondary weapon to refill")
		return
	if int(run.secondary_ammo) >= int(run.secondary_ammo_max):
		toast("Secondary ammo already full")
		return
	if int(run.ammo_restock_charges) <= 0:
		toast("No ammo restock charges left")
		return
	var cost: int = OutpostEcon.restock_cost(run, SECONDARY_REFILL_COST)  # Sector Conditions restock mult
	if int(run.bounty) < cost:
		toast("Not enough bounty")
		return
	run.spend_bounty(cost)
	run.ammo_restock_charges -= 1
	run.secondary_ammo = int(run.secondary_ammo_max)
	OutpostSfx.play("repair")
	toast("Secondary ammo refilled")
	_refresh_live()
	_update_money_parts()


func _on_refill_super(times: int = 1) -> void:
	if not _live:
		toast("Refill super (stub)")
		return
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	if int(run.super_charges) >= int(run.max_super_charges):
		toast("Super charges already full")
		return
	var super_cost: int = OutpostEcon.restock_cost(run, SUPER_REFILL_COST)  # Sector Conditions restock mult
	var did: int = 0
	for _i in range(maxi(1, times)):
		if int(run.super_charges) >= int(run.max_super_charges):
			break
		if int(run.bounty) < super_cost:
			if did == 0: toast("Not enough bounty")
			break
		run.spend_bounty(super_cost)
		run.super_charges = clampi(int(run.super_charges) + 1, 0, int(run.max_super_charges))
		did += 1
	if did > 0:
		OutpostSfx.play("repair")
		toast("Super charge refilled" if did == 1 else "Super charges refilled ×%d" % did)
		_refresh_live()
		_update_money_parts()


# ---- Right panel: armaments / systems / hold ------------------------------

func _rebuild_inventory() -> void:
	_rebuild_armaments()
	_rebuild_systems()
	_rebuild_hold()


func _rebuild_armaments() -> void:
	if _page_armaments == null:
		return
	_clear(_page_armaments)
	_page_armaments.add_child(_caption("Installed weapons + super"))
	# Live splits the cannon into BLASTER (mandatory) + PRIMARY (optional); the mock keeps one slot.
	var slots: Array = ["BLASTER", "PRIMARY", "SECONDARY", "SUPER"] if _live else ARM_SLOTS
	for sid in slots:
		_page_armaments.add_child(_slot_card(sid))
	_page_armaments.add_child(_spacer())


func _rebuild_systems() -> void:
	if _page_systems == null:
		return
	_clear(_page_systems)
	_page_systems.add_child(_caption("Installed modules + shift mode"))
	if _live:
		for i in range(6):
			var sid = "MODULE_%d" % (i + 1)
			_page_systems.add_child(_slot_card(sid))
	else:
		for sid in SYS_SLOTS:
			_page_systems.add_child(_slot_card(sid))
	_page_systems.add_child(_label("SHIFT MODE", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	_page_systems.add_child(_slot_card("SHIFT"))
	_page_systems.add_child(_spacer())


func _rebuild_hold() -> void:
	if _page_hold == null:
		return
	_clear(_page_hold)
	_page_hold.add_child(_caption("Carried, unslotted — %d items" % _hold.size()))
	if _hold.is_empty():
		_page_hold.add_child(_label("(hold empty)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_DISABLED))
	for i in _hold.size():
		_page_hold.add_child(_hold_card(i))
	_page_hold.add_child(_spacer())


# Installed-slot card: Info + Pull (or just the slot name if empty).
func _slot_card(sid: String) -> PanelContainer:
	var item = _slots.get(sid)
	var card := _card_frame()
	var v: VBoxContainer = card.get_child(0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_label(_slot_label(sid), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var nm := _label(String(item["name"]) if item != null else "(empty)", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT if item != null else UiTheme.COLOR_DISABLED)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	v.add_child(top)
	if item != null:
		v.add_child(_label(_card_subtitle_live(item), UiTheme.FONT_SIZE_CAPTION + 2, _tier_color(item)))
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		btns.add_child(_info_btn(item))
		# The core blaster is locked in (no pull/scrap/sell) so the player can never leave unarmed — it
		# can only be swapped out by slotting another blaster from the hold. It CAN still be upgraded.
		var core: bool = _is_core_blaster(sid)
		# The mode retargets the action: Pull (default) / Scrap / Sell / Upgrade. Installed parts are unlocked.
		match _shop_mode:
			ShopMode.SCRAP:
				if not core:
					btns.add_child(_price_button(-1, "", ICON_MAT, "+%d" % int(item["scrap"]), true, func() -> void: _scrap_slot(sid), CARD_BTN_W))
			ShopMode.SELL:
				if not core:
					btns.add_child(_price_button(-1, "", ICON_BOUNTY, "+%d" % _sell_price(item), true, func() -> void: _sell_slot(sid), CARD_BTN_W))
			ShopMode.UPGRADE:
				_add_upgrade_action(btns, item)
			_:
				if not core:
					btns.add_child(_mini_btn("Pull", func() -> void: _pull(sid)))
		v.add_child(btns)
	return card


# Hold card: Info + variable Slot/Swap + Scrap(+N) + Lock toggle.
func _hold_card(idx: int) -> PanelContainer:
	var item = _hold[idx]
	var card := _card_frame()
	var v: VBoxContainer = card.get_child(0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var nm := _label(String(item["name"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	top.add_child(nm)
	v.add_child(top)
	v.add_child(_label(_card_subtitle_live(item), UiTheme.FONT_SIZE_CAPTION + 2, _tier_color(item)))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.add_child(_info_btn(item))
	var locked: bool = bool(item["locked"])
	# The mode retargets the action: Slot/Swap (default) / Scrap / Sell / Upgrade. Scrap/Sell/Upgrade
	# act only on unlocked parts.
	match _shop_mode:
		ShopMode.SCRAP:
			if not locked:
				btns.add_child(_price_button(-1, "", ICON_MAT, "+%d" % int(item["scrap"]), true, func() -> void: _scrap_hold(idx), CARD_BTN_W))
		ShopMode.SELL:
			if not locked:
				btns.add_child(_price_button(-1, "", ICON_BOUNTY, "+%d" % _sell_price(item), true, func() -> void: _sell_hold(idx), CARD_BTN_W))
		ShopMode.UPGRADE:
			if not locked:
				_add_upgrade_action(btns, item)
		_:
			# Slot into an empty target, else Swap. Cannons route by ammo type (a blaster targets the
			# BLASTER slot — always occupied — so it reads as a Swap that drops the old blaster to hold).
			var tgt := _hold_target_slot(item)
			if tgt != "" and _slots.get(tgt) == null:
				btns.add_child(_mini_btn("Slot", func() -> void: _slot_from_hold(idx, tgt)))
			else:
				btns.add_child(_mini_btn("Swap", func() -> void: _swap_from_hold(idx)))
	var lock_btn := _mini_btn("Locked" if locked else "Lock", func() -> void: _toggle_lock(idx))
	if locked:
		lock_btn.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	btns.add_child(lock_btn)
	v.add_child(btns)
	return card


# UPGRADE-mode action: a Mk-up button on an owned-part card. Disabled (grayed) when the part is at
# max Mk ("Max Mk") or the player can't afford the ◆ + ₵ cost. Live-only (mock has no real parts).
func _add_upgrade_action(btns: HBoxContainer, item) -> void:
	var part = item.get("part") if item != null else null
	var run := get_node_or_null("/root/Run")
	if not _live or part == null or run == null:
		var nb := UiTheme.make_button("Upgrade", true)
		nb.disabled = true
		btns.add_child(nb)
		return
	if not run.can_upgrade_part(part):
		var mb := UiTheme.make_button("Max Mk", true)
		mb.disabled = true
		btns.add_child(mb)
		return
	var new_mk: int = int(part.mark) + 1
	# Sector Conditions — Complex/Cheap/Costly/Easy Upgrades adjust both currencies. One OutpostEcon
	# call feeds BOTH this label and _upgrade_part_live's spend so they can't drift.
	var uc: Dictionary = OutpostEcon.upgrade_costs(run, new_mk, _upgrade_bounty_cost(new_mk))
	var mats: int = int(uc["mats"])
	var bounty_cost: int = int(uc["bounty"])
	var afford: bool = int(run.materials) >= mats and int(run.bounty) >= bounty_cost
	# "Mk.N ◆mats ₵cost" — upgrades cost BOTH materials and bounty, so both icons show.
	btns.add_child(_dual_cost_button("Mk.%d:" % new_mk, mats, bounty_cost, afford, func() -> void: _upgrade_part_live(part), UPGRADE_BTN_W))


# Card subtitle "Mk.X <Quality> <ItemType>" — Quality from PartTier; NO "Tier N" roman numeral
# (Roman 2026-06-27). Falls back to the mock "kind · Mk.X" when there's no real part.
func _card_subtitle_live(item) -> String:
	var mk: int = int(item.get("mark", 1))
	if item.get("part") == null:
		return "%s · Mk.%d" % [item.get("kind", "?"), mk]
	var quality: String = String(PartTier.tier_for_mk(mk).get("name", ""))
	return "Mk.%d %s %s" % [mk, quality, _type_name_for_kind(String(item.get("kind", "")))]


func _type_name_for_kind(kind: String) -> String:
	match kind:
		"PRIMARY": return "Primary Weapon"
		"SECONDARY": return "Secondary Weapon"
		"SUPER": return "Super"
		"MODULE": return "Module"
		"SHIFT_MODE": return "Shift Mode"
	return "Part"


# Rarity tint for the card subtitle (carried over from the old outpost — PartTier color per Mk band).
func _tier_color(item) -> Color:
	return PartTier.tier_for_mk(int(item.get("mark", 1))).get("color", UiTheme.COLOR_FAINT)


# Item blurb sourced from the SAME place the Codex reads (ArmoryStrings, keyed by catalog factory) so the
# outpost and the Codex never diverge. Falls back to the part's inline description (mock items / no entry).
func _codex_blurb(item) -> String:
	var part = item.get("part")
	if part != null:
		var factory := PartCatalog.factory_for_part(part)
		if factory != "":
			var blurb := ArmoryStrings.codex_for(factory)
			if blurb != "":
				return blurb
	return String(item.get("desc", ""))


# Compact square "i" info button — keeps the buy/action buttons in frame (the full "Info" label
# pushed them out). Opens the same Mk-aware info popup.
func _info_btn(item) -> Button:
	var b := UiTheme.make_button("i", true)
	b.custom_minimum_size = Vector2(40, 0)
	b.tooltip_text = "Info"
	b.pressed.connect(func() -> void: _show_info(item))
	return b


# Live, Mk-aware stat lines for the info panel — the numbers the cards no longer show. Reads the
# part's real Mk-scaled getters so the panel can preview ANY Mk (tap the mark track to compare).
# MODULE → computed bonus; SHIFT_MODE → duration/charges/refill; WEAPON → damage/ammo (+ super charges).
# Empty for mock items (no real part) or parts with no numeric stats.
# ---- Inventory actions ----------------------------------------------------

func _pull(sid: String) -> void:
	var item = _slots.get(sid)
	if item == null:
		return
	OutpostSfx.play("unequip")

	if _live:
		var run := get_node_or_null("/root/Run")
		if run == null:
			return
		var part = item.get("part")
		if part == null:
			return
		match sid:
			"BLASTER":
				toast("A blaster is required — swap it for another instead")
				return
			"PRIMARY":
				# Metered primary (cannon_pool[1]) → hold; the mandatory blaster (idx 0) stays.
				run.weapon_storage.append(part)
				if run.cannon_pool.size() > 1:
					run.cannon_pool.remove_at(1)
				run.active_cannon_idx = 0
				run.loadout_snapshot[int(SlotTypes.SlotType.CANNON)] = run.get_active_cannon()
				run.ammo = -1
			"SECONDARY", "SUPER":
				var slot_type = int(SlotTypes.SlotType.HARDPOINT_WING) if sid == "SECONDARY" else int(SlotTypes.SlotType.DEVICE_BAY_1)
				run.unequip_slot(slot_type)
				run.weapon_storage.append(part)
			"SHIFT":
				run.unequip_slot(int(SlotTypes.SlotType.SHIFT_MODE))
				run.inventory.append(part)
			_:
				# MODULE_i
				if sid.begins_with("MODULE_"):
					var idx: int = int(sid.split("_")[1]) - 1
					if idx >= 0 and idx < run.modules.size():
						var m = run.remove_module(idx)
						if m != null:
							run.inventory.append(m)
				else:
					return
		_refresh_live()
		_rebuild_inventory()
		toast("Pulled %s to hold" % item["name"])
	else:
		_hold.append(item)
		_slots[sid] = null
		toast("Pulled %s to hold" % item["name"])
		_rebuild_inventory()


func _slot_from_hold(idx: int, sid: String) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var nm = _hold[idx]["name"]
	OutpostSfx.play("equip")

	if _live:
		var run := get_node_or_null("/root/Run")
		if run == null:
			return
		var item = _hold[idx]
		var part = item.get("part")
		if part == null:
			return

		# Remove the part from its source BY REFERENCE (the hold concatenates storage+inventory, so
		# index math is fragile). equip_part may push a displaced part back into storage.
		var src = item.get("src", "")
		match src:
			"weapon_storage": run.weapon_storage.erase(part)
			"inventory": run.inventory.erase(part)

		# Try to equip
		if "slot_type" in part and int(part.slot_type) == int(SlotTypes.SlotType.MODULE):
			if not run.add_module(part):
				# Bay full - put back, no toast
				return
		else:
			run.equip_part(part)

		_refresh_live()
		_rebuild_inventory()
		toast("Slotted %s into %s" % [nm, _slot_label(sid)])
	else:
		_slots[sid] = _hold[idx]
		_hold.remove_at(idx)
		toast("Slotted %s → %s" % [nm, _slot_label(sid)])
		_rebuild_inventory()


func _swap_from_hold(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var item = _hold[idx]
	OutpostSfx.play("equip")
	if _live:
		var run := get_node_or_null("/root/Run")
		var part = item.get("part")
		if run == null or part == null:
			return
		var src = item.get("src", "")
		match src:
			"weapon_storage": run.weapon_storage.erase(part)
			"inventory": run.inventory.erase(part)
		if int(part.slot_type) == SlotTypes.SlotType.MODULE:
			if not run.add_module(part):   # bay full → can't swap a module without pulling one first
				if src == "inventory": run.inventory.append(part)
				else: run.weapon_storage.append(part)
				toast("Module bay full — pull one first")
				_refresh_live()
				_rebuild_inventory()
				return
		else:
			run.equip_part(part)   # Run displaces the same-slot part → weapon_storage (→ hold)
		toast("Swapped %s into the loadout" % item["name"])
		_refresh_live()
		_rebuild_inventory()
	else:
		var sid: String = _target_slots(String(item["kind"]))[0]
		var old = _slots.get(sid)
		_slots[sid] = item
		_hold[idx] = old   # the displaced part drops into the same hold slot
		toast("Swapped into %s" % _slot_label(sid))
		_rebuild_inventory()


func _scrap_hold(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var item = _hold[idx]
	if bool(item.get("locked", false)):
		toast("%s is locked" % item["name"])
		return
	OutpostSfx.play("unequip")

	if _live:
		var run := get_node_or_null("/root/Run")
		if run == null:
			return
		var part = item.get("part")
		if part == null:
			return
		var value: int = _scrap_value(part)
		run.add_materials(value)
		# Remove the part from its source by reference (index math is fragile across storage+inventory).
		match item.get("src", ""):
			"weapon_storage": run.weapon_storage.erase(part)
			"inventory": run.inventory.erase(part)
		_refresh_live()
		_update_money_parts()
		toast("Scrapped %s  (+%d ◆)" % [item["name"], value])
		_rebuild_hold()
	else:
		_materials += int(item["scrap"])
		_hold.remove_at(idx)
		toast("Scrapped %s  (+%d ◆)" % [item["name"], int(item["scrap"])])
		_update_money_parts()
		_rebuild_hold()


func _scrap_slot(sid: String) -> void:
	var item = _slots.get(sid)
	if item == null:
		return
	OutpostSfx.play("unequip")

	if _live:
		var run := get_node_or_null("/root/Run")
		if run == null:
			return
		var part = item.get("part")
		if part == null:
			return
		if not _can_remove_slot(run, sid):
			toast("The Blaster is permanent — can't scrap it")
			return
		var value: int = _scrap_value(part)
		run.add_materials(value)
		_remove_slot_part(run, sid)
		_refresh_live()
		_update_money_parts()
		toast("Scrapped %s  (+%d ◆)" % [item["name"], value])
		_rebuild_inventory()
	else:
		_materials += int(item["scrap"])
		_slots[sid] = null
		toast("Scrapped %s  (+%d ◆)" % [item["name"], int(item["scrap"])])
		_update_money_parts()
		_rebuild_inventory()


func _sell_hold(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	var item = _hold[idx]
	if bool(item.get("locked", false)):
		toast("%s is locked" % item["name"])
		return
	OutpostSfx.play("unequip")

	if _live:
		var run := get_node_or_null("/root/Run")
		if run == null:
			return
		var part = item.get("part")
		if part == null:
			return
		var gain: int = _sell_price(item)
		run.bounty += gain
		match item.get("src", ""):
			"weapon_storage": run.weapon_storage.erase(part)
			"inventory": run.inventory.erase(part)
		# List the sold part as a buyback offer in the PERSISTED stock (survives _refresh_live; cleared
		# to full price on depart by _complete_node_shop).
		run.outpost_weapon_offers.append({"part": part, "cost": _full_cost(part), "sold": false, "buyback": true})
		_refresh_live()
		_update_money_parts()
		toast("Sold %s  (+%d ₵)" % [item["name"], gain])
		_rebuild_hold()
		_rebuild_market()
	else:
		_hold.remove_at(idx)
		_complete_sale(item)
		_rebuild_hold()


func _sell_slot(sid: String) -> void:
	var item = _slots.get(sid)
	if item == null:
		return
	OutpostSfx.play("unequip")

	if _live:
		var run := get_node_or_null("/root/Run")
		if run == null:
			return
		var part = item.get("part")
		if part == null:
			return
		if not _can_remove_slot(run, sid):
			toast("The Blaster is permanent — can't sell it")
			return
		var gain: int = _sell_price(item)
		run.bounty += gain
		_remove_slot_part(run, sid)
		run.outpost_weapon_offers.append({"part": part, "cost": _full_cost(part), "sold": false, "buyback": true})
		_refresh_live()
		_update_money_parts()
		toast("Sold %s  (+%d ₵)" % [item["name"], gain])
		_rebuild_inventory()
		_rebuild_market()
	else:
		_slots[sid] = null
		_complete_sale(item)
		_rebuild_inventory()


# The mandatory BLASTER (cannon_pool[0]) can't be removed; only the metered PRIMARY (cannon_pool[1]) can.
func _can_remove_slot(run, sid: String) -> bool:
	if sid == "BLASTER":
		return false
	if sid == "PRIMARY":
		return run.get_primary_cannon() != null
	return true


# Remove the part installed in `sid` from Run (mirrors outpost.gd: metered-primary unslot incl ammo
# reset, secondary/super unequip, module remove). Caller guards the mandatory BLASTER via _can_remove_slot.
func _remove_slot_part(run, sid: String) -> void:
	match sid:
		"PRIMARY":
			if run.cannon_pool.size() > 1:
				run.cannon_pool.remove_at(1)
				run.active_cannon_idx = 0
				run.loadout_snapshot[SlotTypes.SlotType.CANNON] = run.get_active_cannon()
				run.ammo = -1   # back to the blaster
		"SECONDARY":
			run.unequip_slot(SlotTypes.SlotType.HARDPOINT_WING)
		"SUPER":
			run.unequip_slot(SlotTypes.SlotType.DEVICE_BAY_1)
		"SHIFT":
			run.unequip_slot(SlotTypes.SlotType.SHIFT_MODE)
		_:
			if sid.begins_with("MODULE_"):
				var midx: int = int(sid.split("_")[1]) - 1
				if midx >= 0 and midx < run.modules.size():
					run.remove_module(midx)


# Mk-up a part (port of outpost.gd:_on_upgrade_part): can_upgrade gate + materials + bounty fee.
func _upgrade_part_live(part) -> void:
	var run := get_node_or_null("/root/Run")
	if run == null or part == null or not run.can_upgrade_part(part):
		return
	var new_mk: int = int(part.mark) + 1
	# Sector Conditions — same OutpostEcon call the upgrade button label uses (display == spend).
	var uc: Dictionary = OutpostEcon.upgrade_costs(run, new_mk, _upgrade_bounty_cost(new_mk))
	var mats: int = int(uc["mats"])
	var bounty_cost: int = int(uc["bounty"])
	if int(run.materials) < mats or int(run.bounty) < bounty_cost:
		toast("Need ◆%d + ₵%d to upgrade" % [mats, bounty_cost])
		return
	OutpostSfx.play("upgrade")
	deck_react("upgrade")   # a pit-crew swarms the ship
	run.spend_materials(mats)
	run.spend_bounty(bounty_cost)
	run.upgrade_part(part)
	toast("Upgraded → Mk.%d" % int(part.mark))
	_refresh_live()
	_update_money_parts()
	_rebuild_inventory()


# Sell at 20% of value → money; the part lists in the market for buyback (until departure).
func _complete_sale(item: Dictionary) -> void:
	var gain: int = _sell_price(item)
	_money += gain
	var listed := item.duplicate()
	listed["locked"] = false
	listed["buyback"] = true
	_market.append(listed)
	toast("Sold %s  (+%d ₵)" % [item["name"], gain])
	_update_money_parts()
	_rebuild_market()


func _toggle_lock(idx: int) -> void:
	if idx < 0 or idx >= _hold.size():
		return
	_hold[idx]["locked"] = not bool(_hold[idx]["locked"])
	_rebuild_hold()


func _target_slots(kind: String) -> Array:
	if kind == "MODULE":
		if _live:
			var slots: Array = []
			for i in range(6):
				slots.append("MODULE_%d" % (i + 1))
			return slots
		return SYS_SLOTS
	if kind == "SHIFT_MODE":
		return ["SHIFT"]
	return [kind]   # PRIMARY / SECONDARY / SUPER map to the same-named slot


func _empty_target(kind: String) -> String:
	for sid in _target_slots(kind):
		if _slots.get(sid) == null:
			return sid
	return ""


# Which installed slot a hold item targets (drives the Slot/Swap label). Cannons route by ammo type:
# an infinite blaster → the BLASTER slot, a metered cannon → the PRIMARY slot. Everything else picks the
# first empty same-kind slot, falling back to the first target slot (a Swap).
func _hold_target_slot(item) -> String:
	var kind := String(item.get("kind", ""))
	if kind == "PRIMARY" and _live:   # a cannon
		return "BLASTER" if _cannon_is_infinite(item) else "PRIMARY"
	var empty := _empty_target(kind)
	if empty != "":
		return empty
	var targets := _target_slots(kind)
	return String(targets[0]) if not targets.is_empty() else ""


# A cannon is a BLASTER (vs a metered PRIMARY) when it has no finite magazine (infinite ammo).
func _cannon_is_infinite(item) -> bool:
	var part = item.get("part")
	if part == null:
		return false
	var mk: int = int(item.get("mark", 1))
	if part.has_method("ammo_at_mark"):
		return int(part.ammo_at_mark(mk)) < 0
	if part.has_method("_base_ammo"):
		return int(part._base_ammo()) < 0
	return false


func _slot_label(sid: String) -> String:
	match sid:
		"BLASTER": return "BLASTER"
		"PRIMARY": return "PRIMARY"
		"SECONDARY": return "SECONDARY"
		"SUPER": return "SUPER"
		"MODULE_1": return "MODULE 1"
		"MODULE_2": return "MODULE 2"
		"MODULE_3": return "MODULE 3"
		"MODULE_4": return "MODULE 4"
		"MODULE_5": return "MODULE 5"
		"MODULE_6": return "MODULE 6"
		"SHIFT": return "SHIFT MODE"
	return sid


func _update_money_parts() -> void:
	# Numbers only — the bounty / materials icons stand in for the old ₵ / ◆ prefixes.
	if _money_lbl != null and is_instance_valid(_money_lbl):
		_money_lbl.text = "%d" % _money
	if _parts_lbl != null and is_instance_valid(_parts_lbl):
		_parts_lbl.text = "%d" % _materials
	_update_status()
	# Money/materials just changed → re-evaluate the services panel's affordability graying (it's the
	# one panel whose buy/repair/upgrade-mode options gray on funds but isn't rebuilt by the action).
	_rebuild_services()


# Top-bar ship-status readouts: hull (current/max) + super charges (the Super Pulse Bomb). Each field
# (icon + number) hides when there's no data (e.g. the dev lab without a run / no super equipped).
func _update_status() -> void:
	var run := get_node_or_null("/root/Run")
	if _hull_lbl != null and is_instance_valid(_hull_lbl):
		var ok: bool = run != null and "current_hull" in run and "max_hull" in run and int(run.max_hull) > 0
		if ok:
			_hull_lbl.text = "%d/%d" % [int(run.current_hull), int(run.max_hull)]
		_stat_visible(_hull_lbl, ok)
	if _super_lbl != null and is_instance_valid(_super_lbl):
		var ok2: bool = run != null and "max_super_charges" in run and int(run.max_super_charges) > 0
		if ok2:
			_super_lbl.text = "%d/%d" % [int(run.super_charges), int(run.max_super_charges)]
		_stat_visible(_super_lbl, ok2)


# Show/hide a whole stat field (its icon + number) via the Label's parent box.
func _stat_visible(lbl: Label, vis: bool) -> void:
	var box := lbl.get_parent()
	if box != null and is_instance_valid(box):
		box.visible = vis


# ---- Info popup (codex entry) ---------------------------------------------

func _show_info(item: Dictionary) -> void:
	_close_info()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Close only on a real LEFT click on the dim — NOT the mouse wheel (scrolling a maxed-out
	# ScrollContainer bubbles the wheel button here) and not right-click.
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_info())
	add_child(dim)
	_info_popup = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.98)
	sb.border_color = UiTheme.COLOR_ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(760, 0)
	panel.add_child(v)
	var part = item.get("part")
	var cur_mk: int = int(item.get("mark", 1))
	var mx: int = int(item.get("max_mark", 9))
	v.add_child(_label(String(item["name"]), UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))
	v.add_child(_label(_card_subtitle_live(item), UiTheme.FONT_SIZE_BODY, _tier_color(item)))
	# Blurb from the Codex source (ArmoryStrings) so the dock and the Codex never show different text.
	var desc := _label(_codex_blurb(item), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_FAINT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(760, 0)
	v.add_child(desc)
	# Live, Mk-aware stat box + tappable Mark ladder — shared with the Codex via PartStatsView so the
	# two never drift. Defaults to the current Mk; tapping a chip previews that Mk before you pay.
	v.add_child(PartStatsView.build(part, cur_mk, mx))
	v.add_child(_value_row("Scrap value:", ICON_MAT, str(int(item["scrap"])), UiTheme.COLOR_GREEN))
	v.add_child(_value_row("Sell value:", ICON_BOUNTY, str(_sell_price(item)), UiTheme.COLOR_BOUNTY))
	var close := UiTheme.make_button("Close")
	close.pressed.connect(_close_info)
	v.add_child(close)


# Clickable Mk ladder: the current Mk is highlighted; every chip is tappable to preview that Mk's
# stats (on_pick(mk)). Lower Mks read as "owned", higher Mks as "locked/upgrade target".
func _close_info() -> void:
	if _info_popup != null and is_instance_valid(_info_popup):
		_info_popup.queue_free()
	_info_popup = null


# ---- Help overlay ---------------------------------------------------------
# A scrollable manual that explains every section / feature / button, each with a live visual example
# (the real icons + sample buttons). Shares the _info_popup slot so only one modal shows at a time.

func _show_help() -> void:
	_close_info()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Close only on a real LEFT click on the dim — NOT the mouse wheel (scrolling a maxed-out
	# ScrollContainer bubbles the wheel button here) and not right-click.
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_info())
	add_child(dim)
	_info_popup = dim

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.99)
	sb.border_color = UiTheme.COLOR_ACCENT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	outer.add_child(_label(OutpostHelpStrings.HELP_TITLE, UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))

	# Fixed title + Close; the sections scroll between them.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(880, 720)
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	v.add_child(_help_para(OutpostHelpStrings.HELP_INTRO))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_RESOURCES))
	v.add_child(_help_row(_icon_widget(ICON_HULL, 26, UiTheme.COLOR_TEXT), OutpostHelpStrings.HELP_HULL))
	v.add_child(_help_row(_icon_widget(ICON_SUPER, 26, UiTheme.COLOR_ACCENT), OutpostHelpStrings.HELP_SUPER))
	v.add_child(_help_row(_icon_widget(ICON_BOUNTY, 26, UiTheme.COLOR_BOUNTY), OutpostHelpStrings.HELP_BOUNTY))
	v.add_child(_help_row(_icon_widget(ICON_MAT, 26, UiTheme.COLOR_GREEN), OutpostHelpStrings.HELP_MATERIALS))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_MARKET))
	v.add_child(_help_row(_icon_chip(ICON_BOUNTY, "116", UiTheme.COLOR_BOUNTY), OutpostHelpStrings.HELP_MARKET))
	v.add_child(_help_row(_help_static_i(), OutpostHelpStrings.HELP_MARKET_INFO))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_SERVICES))
	v.add_child(_help_row(_help_svc_example(), OutpostHelpStrings.HELP_SERVICES))
	v.add_child(_help_para(OutpostHelpStrings.HELP_MODES_INTRO))
	v.add_child(_help_row(_help_mode_example("Scrap", UiTheme.COLOR_DANGER), OutpostHelpStrings.HELP_MODE_SCRAP))
	v.add_child(_help_row(_help_mode_example("Sell", UiTheme.COLOR_BOUNTY), OutpostHelpStrings.HELP_MODE_SELL))
	v.add_child(_help_row(_help_mode_example("Upgrade", UiTheme.COLOR_ACCENT), OutpostHelpStrings.HELP_MODE_UPGRADE))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_CONDITIONS))
	v.add_child(_help_row(_help_static_i(), OutpostHelpStrings.HELP_CONDITIONS))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_ACTIONS))
	v.add_child(_help_row(_help_static_i(), OutpostHelpStrings.HELP_ACTION_INFO))
	v.add_child(_help_row(_help_mode_example("Slot", UiTheme.COLOR_TEXT), OutpostHelpStrings.HELP_ACTION_SLOT))
	v.add_child(_help_row(_help_mode_example("Swap", UiTheme.COLOR_TEXT), OutpostHelpStrings.HELP_ACTION_SWAP))
	v.add_child(_help_row(_help_mode_example("Pull", UiTheme.COLOR_TEXT), OutpostHelpStrings.HELP_ACTION_PULL))
	v.add_child(_help_row(_help_mode_example("Lock", UiTheme.COLOR_FAINT), OutpostHelpStrings.HELP_ACTION_LOCK))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_ARMAMENTS))
	v.add_child(_help_para(OutpostHelpStrings.HELP_ARMAMENTS))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_SYSTEMS))
	v.add_child(_help_para(OutpostHelpStrings.HELP_SYSTEMS))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_HOLD))
	v.add_child(_help_para(OutpostHelpStrings.HELP_HOLD))

	v.add_child(_help_head(OutpostHelpStrings.HELP_HEAD_BOTTOM))
	v.add_child(_help_para(OutpostHelpStrings.HELP_BOTTOM))

	var close := UiTheme.make_button(OutpostHelpStrings.HELP_CLOSE)
	close.pressed.connect(_close_info)
	outer.add_child(close)


func _help_head(text: String) -> Label:
	return _label(text, UiTheme.FONT_SIZE_BODY + 2, UiTheme.COLOR_ACCENT)


func _help_para(text: String) -> Label:
	var l := _label(text, UiTheme.FONT_SIZE_CAPTION + 2, UiTheme.COLOR_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(800, 0)
	return l


# One help entry: a fixed example column (a live, INERT widget) + a wrapping description.
func _help_row(example: Control, text: String) -> HBoxContainer:
	_inert(example)   # examples are illustrations only — no hover glow, no clicks
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_child(example)
	row.add_child(box)
	var lbl := _label(text, UiTheme.FONT_SIZE_CAPTION + 2, UiTheme.COLOR_TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(460, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	return row


# Make a help example non-interactive: no hover highlight, no press. Recurses so face-button
# children (mouse-ignore already) and icon/label parts all stop receiving mouse events.
func _inert(ctrl: Control) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in ctrl.get_children():
		if c is Control:
			_inert(c)


func _help_static_i() -> Button:
	var b := UiTheme.make_button("i", true)
	b.custom_minimum_size = Vector2(40, 48)
	return b


func _help_svc_example() -> HBoxContainer:
	# Wide enough that the icon+quantity+price face isn't clipped (the real service buttons are
	# roomier than the card buttons). Minimum height ensures icon+text fit without squeezing.
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var btn1 := _price_button(ICON_HULL, "1", ICON_BOUNTY, "250", true, _help_noop, 168)
	btn1.custom_minimum_size = Vector2(168, 48)
	box.add_child(btn1)
	var btn2 := _price_button(ICON_HULL, "All", ICON_BOUNTY, "0", true, _help_noop, 168)
	btn2.custom_minimum_size = Vector2(168, 48)
	box.add_child(btn2)
	return box


func _help_mode_example(text: String, color: Color) -> Button:
	var b := UiTheme.make_button(text, true)
	b.add_theme_color_override("font_color", color)
	b.custom_minimum_size = Vector2(0, 48)
	return b


func _help_noop() -> void:
	pass


# ---- Small UI helpers -----------------------------------------------------

func _card_frame() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.30)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	return card


func _mini_btn(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text, true)
	b.pressed.connect(cb)
	return b


func _header(text: String) -> Label:
	return _label(text, UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_ACCENT)


func _caption(text: String) -> Label:
	return _label(text, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _run_int(field: String, fallback: int) -> int:
	var run := get_node_or_null("/root/Run")
	if run != null and field in run:
		return int(run.get(field))
	return fallback


# ---- Sequence -------------------------------------------------------------

func _kill_phase_tween() -> void:
	for tw in [_phase_tween, _glow_tween, _ui_tween, _bg_tween, _flare_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_phase_tween = null
	_glow_tween = null
	_ui_tween = null
	_bg_tween = null
	_flare_tween = null


# ARRIVING: ship below the screen, engines lit, masks closed, menus hidden →
# decelerating fly-in to the pad. Idempotent reset (the lab's Replay).
# Skip the cinematic: set up the LANDED, menus-up state directly (Settings dock-anim = never, or the
# per-boss/per-patrol gate already satisfied this visit). Depart is instant too (no fly-out).
func begin_landed() -> void:
	if not _built:
		return
	_kill_phase_tween()
	_state = State.LANDED
	_t = 0.0
	_skip_anim = true
	_engine_flare = 1.0
	_ship_altitude = 0.0
	if _ship != null:
		_ship.position = Vector2(SHIP_X, land_y)
	if _engine_glow != null:
		_engine_glow.modulate = ENGINE_GLOW_COLOR * ENGINE_GLOW_OFF
	_set_engine_active(false)
	_set_sparks_emitting(false)
	_shadow_offset = shadow_land_offset
	_shadow_scale = shadow_land_scale
	if _shadow != null:
		_shadow.modulate.a = shadow_land_alpha
	if _plate != null and is_instance_valid(_plate):
		_plate.position = Vector2(SHIP_X, _bg_center_y)
	_apply_damage()
	_set_alpha(_left_panel, 1.0)
	_set_alpha(_right_panel, 1.0)
	_set_alpha(_top_bar, 1.0)
	_set_alpha(_bottom_bar, 1.0)
	_ensure_deck_life()
	emit_signal("landed")


# Settings.outpost_dock_anim: 0 always / 1 per-boss / 2 per-patrol / 3 never. Per-boss + per-patrol
# track via Run meta (keyed by bosses_defeated / run_seed so a new boss-clear / new run replays).
func _should_play_cinematic() -> bool:
	match _dock_anim_mode():
		3:
			return false
		1:
			var run = get_node_or_null("/root/Run")
			if run == null:
				return true
			if int(run.get_meta("dock_anim_boss", -1)) != int(run.bosses_defeated):
				run.set_meta("dock_anim_boss", int(run.bosses_defeated))
				return true
			return false
		2:
			var run2 = get_node_or_null("/root/Run")
			if run2 == null:
				return true
			if int(run2.get_meta("dock_anim_run", 0)) != int(run2.run_seed):
				run2.set_meta("dock_anim_run", int(run2.run_seed))
				return true
			return false
		_:
			return true


func _dock_anim_mode() -> int:
	var s = get_node_or_null("/root/Settings")
	if s != null and "outpost_dock_anim" in s:
		return int(s.outpost_dock_anim)
	return 0


func begin_arrival() -> void:
	if not _built:
		return
	_kill_phase_tween()
	if _deck != null and is_instance_valid(_deck):
		_deck.set_active(false)   # crew hidden while the plate flies in; respawn/shown on landing
	_skip_anim = false
	_state = State.ARRIVING
	_t = 0.0
	_shadow_offset = shadow_fly_offset
	_shadow_scale = shadow_fly_scale
	if _shadow != null:
		_shadow.modulate.a = shadow_fly_alpha
	if _ship != null:
		_ship.position = Vector2(SHIP_X, start_y)
	if _engine_glow != null:
		_engine_glow.modulate = ENGINE_GLOW_COLOR
	_engine_flare = 1.0
	_ship_altitude = 1.0
	_set_engine_active(true)
	# Reset spark scheduling (the continuous fly-in trail relights via _update_sparks).
	_set_sparks_emitting(false)
	_spark_t = 0.0
	_spark_burst_t = 0.0
	_spray_t = 0.0
	_apply_damage()
	# Menus hidden (the black sidebars stay on permanently).
	_set_alpha(_left_panel, 0.0)
	_set_alpha(_right_panel, 0.0)
	_set_alpha(_top_bar, 0.0)
	_set_alpha(_bottom_bar, 0.0)

	# Fly-in SFX: decelerating afterburner — the Pilgrim gets its own clip (A), every
	# other craft rolls B/C (Roman 2026-07-15).
	EngineSfx.play_afterburner(self, ShipCatalog.get_ship(ship_variant))

	_phase_tween = create_tween()
	_phase_tween.tween_property(_ship, "position:y", land_y, arrival_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_callback(_on_landed)
	# Hangar plate descends from above to centred, in sync with the ship setting down.
	if _plate != null and is_instance_valid(_plate):
		_plate.position = Vector2(SHIP_X, _bg_above_y)
		_bg_tween = create_tween()
		_bg_tween.tween_property(_plate, "position:y", _bg_center_y, arrival_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# LANDED: settle the shadow tight, fade the gutter masks off the menus, THEN cut engines.
func _on_landed() -> void:
	_state = State.LANDED
	_t = 0.0
	# Engines stay LIT through the settle — they only cut once the ship has fully set down
	# (after the shadow converges), not the instant the descent ends. Roman 2026-06-19.
	_kill_phase_tween()
	_phase_tween = create_tween()
	_phase_tween.set_parallel(true)
	_phase_tween.tween_property(self, "_shadow_offset", shadow_land_offset, shadow_settle_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(self, "_shadow_scale", shadow_land_scale, shadow_settle_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_phase_tween.tween_property(_shadow, "modulate:a", shadow_land_alpha, shadow_settle_time)
	_phase_tween.tween_property(self, "_ship_altitude", 0.0, shadow_settle_time)   # set down → shadow tightens
	_phase_tween.tween_property(_left_panel, "modulate:a", 1.0, bars_fade_time)
	_phase_tween.tween_property(_right_panel, "modulate:a", 1.0, bars_fade_time)
	_phase_tween.tween_property(_top_bar, "modulate:a", 1.0, bars_fade_time)
	_phase_tween.tween_property(_bottom_bar, "modulate:a", 1.0, bars_fade_time)
	# Fully set down → cut engines (streak + smoke stop) and power the glow down, THEN announce.
	_phase_tween.chain().tween_callback(_cut_engines)
	_phase_tween.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR * ENGINE_GLOW_OFF, engine_spool)
	_phase_tween.chain().tween_callback(func() -> void:
		_ensure_deck_life()
		emit_signal("landed"))


func _cut_engines() -> void:
	_set_engine_active(false)   # blue streak + smoke stop; sparks persist while damaged


func _on_depart_pressed() -> void:
	emit_signal("depart_requested")
	depart()


# DEPARTING: fade the menus, close the masks, relight engines, the ship rises (shadow
# spreads), then launches off the top. No-op unless landed.
func depart() -> void:
	if _state != State.LANDED:
		return
	# Crew scatter to the deck edges, then get hidden as the plate slides out.
	if _deck != null and is_instance_valid(_deck):
		_deck.scatter()
	if _skip_anim:
		# No cinematic this visit (Settings dock-anim) → instant exit, no fly-out.
		_close_info()
		_set_shop_mode(ShopMode.NONE)
		_complete_node_shop()
		_on_departed()
		return
	_state = State.DEPARTING
	_kill_phase_tween()
	_close_info()
	_set_shop_mode(ShopMode.NONE)
	_complete_node_shop()   # heading to a node ends buyback (sold parts rise to full price)
	_set_engine_active(true)
	var damaged: bool = damage_level >= TELL_ACTIVATE

	# Menus retract (independent of the motion sequence).
	_ui_tween = create_tween()
	_ui_tween.set_parallel(true)
	_ui_tween.tween_property(_left_panel, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_right_panel, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_top_bar, "modulate:a", 0.0, bars_fade_time)
	_ui_tween.tween_property(_bottom_bar, "modulate:a", 0.0, bars_fade_time)

	# Hangar plate slides down off-screen (continuing its downward travel) as the ship flies up.
	if _plate != null and is_instance_valid(_plate):
		_bg_tween = create_tween()
		_bg_tween.tween_interval(engine_spool)
		_bg_tween.tween_property(_plate, "position:y", _bg_below_y, rise_time + flyoff_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Ignition SFX as the engines spool: Pilgrim firecore / single-nozzle / twin-engine
	# clip family per the current hull (Roman 2026-07-15).
	EngineSfx.play_jet_start(self, ShipCatalog.get_ship(ship_variant))

	# Engine spool (ship still static): a DAMAGED ship STUTTERS to life + sprays sparks off the
	# engine(s) before catching; a clean ship just fades the glow up smoothly. Roman 2026-06-19.
	if damaged:
		_spool_spray()
		_glow_tween = _start_glow_stutter(engine_spool)
	else:
		_glow_tween = create_tween()
		_glow_tween.tween_property(_engine_glow, "modulate", ENGINE_GLOW_COLOR, engine_spool)

	# Engine light flare: hold through the spool, then surge to the brightest/biggest bloom right as the
	# ship accelerates off the top (EASE_IN peaks at the launch instant). Roman 2026-06-26.
	_flare_tween = create_tween()
	_flare_tween.tween_interval(engine_spool)
	_flare_tween.tween_property(self, "_engine_flare", ENGINE_FLARE_PEAK, rise_time + flyoff_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Motion: hold through the spool, THEN rise (shadow spreads), then launch off the top.
	var hover_y: float = land_y - 10.0
	_phase_tween = create_tween()
	_phase_tween.tween_interval(engine_spool)
	_phase_tween.tween_property(self, "_shadow_offset", shadow_fly_offset, rise_time)
	_phase_tween.parallel().tween_property(self, "_shadow_scale", shadow_fly_scale, rise_time)
	_phase_tween.parallel().tween_property(_shadow, "modulate:a", shadow_fly_alpha, rise_time)
	_phase_tween.parallel().tween_property(self, "_ship_altitude", 1.0, rise_time)   # rising → shadow pulls away
	_phase_tween.parallel().tween_property(_ship, "position:y", hover_y, rise_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Exit-thruster burn fires at the launch instant — after the rise, as the ship accelerates off.
	_phase_tween.tween_callback(func() -> void: EngineSfx.play_exit_thruster(self))
	_phase_tween.tween_property(_ship, "position:y", FLYOFF_TARGET_Y, flyoff_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_phase_tween.tween_callback(_on_departed)


func _on_departed() -> void:
	_state = State.GONE
	emit_signal("departed")
	# Production: the dock is the live outpost — fly-out done, return to the sector map (drop the HD
	# scope once the fade covers, mirroring the old outpost's _on_leave). The lab/drivers leave
	# return_to_map false and handle `departed` themselves.
	if return_to_map:
		SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE, drop_hd_scope)


# ---- Runtime --------------------------------------------------------------

func _process(delta: float) -> void:
	if _state == State.LANDED and _ship != null and is_instance_valid(_ship):
		_t += delta
		_ship.position = Vector2(SHIP_X, land_y + sin(_t * TAU / maxf(idle_bob_period, 0.1)) * idle_bob)
	if _shadow != null and is_instance_valid(_shadow) and _ship != null and is_instance_valid(_ship):
		_shadow.position = _ship.position + _shadow_offset
		_shadow.scale = Vector2(_shadow_scale, _shadow_scale)
	# Star parallax scrolls only while the ship moves (arriving / departing) — depth for the
	# "flying into the hangar" beat; still once landed.
	if _stars != null and is_instance_valid(_stars) and _stars.has_method("scroll_stars"):
		if _state == State.ARRIVING or _state == State.DEPARTING:
			_stars.scroll_stars(star_drift * delta)
	_update_sparks(delta)
	_update_lights(delta)
	# (the runway pulse self-updates inside HangarPlate)


func toast(msg: String) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = msg
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_lbl.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(_toast_lbl, "modulate:a", 0.0, 0.5)


# Release the HD content-scale scope (no-op when embedded in the dev lab).
func drop_hd_scope() -> void:
	HdScreen.drop(_hd)
	_hd = null


# ---- Live setters (dev lab) -----------------------------------------------

func get_state() -> int:
	return _state


func set_damage(level: float) -> void:
	damage_level = clampf(level, 0.0, 1.0)
	_apply_damage()


# Bay dim → the hangar stage's in-scene CanvasModulate (single source; tuned via the lab).
func set_scene_dim(x: float) -> void:
	scene_dim = clampf(x, 0.0, 1.0)
	if _plate != null and is_instance_valid(_plate):
		_plate.set_scene_dim(scene_dim)


func set_runway_speed(v: float) -> void:
	runway_speed = v
	if _plate != null and is_instance_valid(_plate):
		_plate.set_runway_speed(v)


# ---- Deck life (wandering crew) -------------------------------------------
# Built lazily on landing as a child of the plate (so it rides the plate in/out). Bounds + the ship
# anchor are in plate-local coords. See docs/deck_life_plan_2026-07-04.md.

func _ensure_deck_life() -> void:
	if _plate == null or not is_instance_valid(_plate):
		return
	if _deck == null or not is_instance_valid(_deck):
		_deck = DeckLifeScript.new()
		_deck.name = "DeckLife"
		_plate.add_child(_deck)
		var ps: Vector2 = _plate.plate_size()
		# Walkable floor: a band centered horizontally, from just above the plate centre into the lower deck.
		var b := Rect2(-ps.x * 0.42, -ps.y * 0.04, ps.x * 0.84, ps.y * 0.40)
		var ship_local := Vector2(0.0, land_y - _bg_center_y)   # the docked ship, in plate-local coords
		_deck.configure(b, ship_local, int(_clutter_seed()))
	_deck.set_speed(deck_crew_speed)
	_deck.set_count(deck_crew_count)
	_deck.set_crate_count(deck_crate_count)
	_deck.set_lifter(deck_lifter)
	_deck.set_active(true)


func set_deck_crew_count(n: int) -> void:
	deck_crew_count = maxi(0, n)
	if _deck != null and is_instance_valid(_deck):
		_deck.set_count(deck_crew_count)


func set_deck_crew_speed(s: float) -> void:
	deck_crew_speed = s
	if _deck != null and is_instance_valid(_deck):
		_deck.set_speed(s)


func set_deck_crate_count(n: int) -> void:
	deck_crate_count = maxi(0, n)
	if _deck != null and is_instance_valid(_deck):
		_deck.set_crate_count(deck_crate_count)


# Force a crate carry now (dev/lab).
func deck_carry_now() -> void:
	if _deck != null and is_instance_valid(_deck):
		_deck.carry_now()


# Force a lifter run now (dev/lab).
func deck_lifter_run_now() -> void:
	if _deck != null and is_instance_valid(_deck):
		_deck.lifter_run_now()


# Cosmetic deck reaction to a shop action ("repair"/"buy"/"sell"/"scrap"/"upgrade"/"refill"). No-op
# until the deck is built (landed). Never blocks the shop.
func deck_react(kind: String) -> void:
	if _deck != null and is_instance_valid(_deck):
		_deck.react(kind)


# Heal damage to `target` over `dur`, re-driving the shader + tells each step (the overlay is
# live, so reducing the level removes the fray + stops the sparks). Services "Repair Hull"
# calls this; production would tie it to the player actually buying a hull repair.
func repair(target: float = 0.0, dur: float = 0.6) -> void:
	target = clampf(target, 0.0, 1.0)
	if not _built or dur <= 0.0:
		set_damage(target)
		return
	var tw := create_tween()
	tw.tween_method(set_damage, damage_level, target, dur)


func set_ship(variant: int, livery: Color, set_livery: bool) -> void:
	ship_variant = clampi(variant, 0, VARIANTS.size() - 1)
	livery_color = livery
	livery_set = set_livery
	if not _built:
		return
	_teardown_ship_fx()
	if _trail != null and is_instance_valid(_trail):
		_trail.queue_free()
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	if _ship != null and is_instance_valid(_ship):
		_ship.queue_free()
	_build_ship()
	_apply_shadow_mode()   # re-bind the shadow casters/lights to the freshly-built ship
	begin_arrival()


func _set_alpha(c: Control, a: float) -> void:
	if c != null and is_instance_valid(c):
		c.modulate.a = a
