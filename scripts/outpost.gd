extends Control

# Friendly Outpost — horizontal rework 2026-05-23 per Roman:
#   - HD 1920×1080 overlay scene (matches shipyard V3 pattern).
#   - 3 columns: Weapons / Upgrades / Services + a top status bar.
#   - Weapons column now rolls CANNON + HARDPOINT_WING (secondary) +
#     DEVICE_BAY_1 (super) parts, weighted 50/25/25. Click → swap into
#     loadout_snapshot for the matching slot; the displaced part goes to
#     weapon_storage.
#   - Status bar: hull, shield charges, bounty, MG ammo, secondary ammo,
#     super charges, equipped loadout one-liner. Repolled after every
#     purchase (no live Player exists in a meta scene).
#   - Services: hull repair, shield refill, MG ammo refill, secondary
#     ammo refill (NEW), per-charge super refill, storage sell/equip.
#   - Auto-restore on visit: super charges full + current_shield = max
#     (the latter mirrors what player.start() does at next combat; we
#     also write it to Run so the status bar reads correctly NOW).

const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const PartTier = preload("res://scripts/parts/part_tier.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const SectorMapRoute = preload("res://scripts/sector_map_route.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Strings = preload("res://scripts/strings.gd")

const UPGRADES := [
	{"key": "hull_mk",          "name": Strings.UPGRADE_HULL_NAME,          "desc": Strings.UPGRADE_HULL_DESC},
	{"key": "thrusters_mk",     "name": Strings.UPGRADE_THRUSTERS_NAME,     "desc": Strings.UPGRADE_THRUSTERS_DESC},
	{"key": "self_repair_mk",   "name": Strings.UPGRADE_SELF_REPAIR_NAME,   "desc": Strings.UPGRADE_SELF_REPAIR_DESC},
	{"key": "shield_cap_mk",    "name": Strings.UPGRADE_SHIELD_CAP_NAME,    "desc": Strings.UPGRADE_SHIELD_CAP_DESC},
	{"key": "hull_plating_mk",  "name": Strings.UPGRADE_HULL_PLATING_NAME,  "desc": Strings.UPGRADE_HULL_PLATING_DESC},
	# armor_mk and shield_recharge_mk retired — no longer purchasable.
]

const UPGRADE_BASE_COST := 70
const UPGRADE_COST_PER_MK := 35
const MAX_MK := 9
const HULL_REPAIR_COST := 250
# Ammo refill: cost scales with the number of rounds the player is missing,
# so a near-empty mag is more expensive than a top-up. COST_PER_ROUND tuned
# so a full 1000-round MG refill = 500 bounty (still a major expense), a
# full 60-round secondary refill = 30 bounty (incidental), and partials
# fall out linearly. Partial refills are allowed when the player can't
# cover the full top-up — see _on_primary_ammo_refill.
const AMMO_COST_PER_ROUND := 0.5
# Weapons Phase 1 (2026-05-26): primary ammo refill is now a flat-cost
# button — refills the active cannon_pool entry's magazine to full. Blaster
# (active_cannon_idx == 0) has infinite ammo so the button greys out.
# Placeholder value pending designer tuning.
const PRIMARY_REFILL_COST := 50
# Super charges: per-charge purchase. Doubled from 30 → 60 (Roman 2026-05-25):
# free auto-refill on outpost visit removed at the same time, so the player
# now PAYS to keep their super topped up — supers are a real economy lever.
const SUPER_REFILL_COST := 60
const CANNON_BASE_COST := 58
const CANNON_COST_PER_MK := 35
# Refresh stock pricing — doubles per use within the same visit. Cap at
# 7 doublings so the ceiling is 10 << 7 = 1280 bounty (designer call,
# Roman 2026-05-24: "double per use" — capped to avoid runaway numbers).
const REFRESH_BASE_COST := 10
const REFRESH_MAX_DOUBLINGS := 7
# Mark distribution: roll picks from sector_index + 3 max, with weighting
# that favors the middle of the available range and tapers at the high end.
const MK_HIGH_OFFSET := 3

# Weapons column slot weights: cannon dominates (it's primary), with
# secondary + super as occasional offers. 4 cannon / 2 secondary / 2 super
# = 8 weights; rolled with replacement for the 5-card weapons column.
const WEAPON_SLOT_WEIGHTS := [
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.HARDPOINT_WING,
	SlotTypes.SlotType.HARDPOINT_WING,
	SlotTypes.SlotType.DEVICE_BAY_1,
	SlotTypes.SlotType.DEVICE_BAY_1,
]
const WEAPONS_COLUMN_COUNT := 5
const UPGRADES_COLUMN_COUNT := 3

# ---- HD layout constants (1920×1080) -----------------------------------
const HD_W := 1920
const HD_H := 1080
const STATUS_H := 96
const MARGIN := 24
const COL_GAP := 18
const COL_WEAPONS_W := 600
const COL_UPGRADES_W := 600
const COL_SERVICES_W := 400  # fills remainder; recomputed at build
const CARD_H := 140
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)
const PANEL_BG_WEAPON := Color(0.10, 0.05, 0.12, 0.65)
const PANEL_BG_UPGRADE := Color(0.05, 0.08, 0.14, 0.65)
const PANEL_BG_SERVICE := Color(0.05, 0.10, 0.08, 0.65)
const FS_TITLE := 36
const FS_HEADER := 24
const FS_BODY := 18
const FS_CAPTION := 14
const FS_STATUS := 18
const FS_STATUS_VALUE := 22

var _weapon_offers: Array = []   # [{part, cost, sold}]
var _upgrade_offers: Array = []  # [{key, name, desc, next_mk, cost, sold}]

# UI refs.
var _bounty_value_lbl: Label = null
var _hull_value_lbl: Label = null
var _shield_value_lbl: Label = null
var _mg_ammo_lbl: Label = null
var _sec_ammo_lbl: Label = null
var _super_value_lbl: Label = null
var _loadout_lbl: Label = null
var _weapons_box: VBoxContainer = null
var _upgrades_box: VBoxContainer = null
var _services_box: VBoxContainer = null
var _storage_box: VBoxContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _refresh_btn: Button = null
# Bumped by Refresh Stock so re-rolling produces different offers (the
# deterministic seed is otherwise stable across calls in the same visit).
# Also drives exponential refresh pricing — cost doubles each use, capped
# at REFRESH_MAX_DOUBLINGS so it caps at 10 << 7 = 1280 bounty.
var _refresh_count: int = 0
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	# HD overlay (matches shipyard V3 / sector_map_hd pattern). RAII scope
	# auto-restores native scale on scene exit. _on_leave forces it earlier
	# so the next scene doesn't render at HD during the transition.
	_hd_scope = HdViewportScope.attach(self, Vector2i(HD_W, HD_H))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("outpost")
	# Auto-restore on visit. Designer policy (Roman 2026-05-25):
	# - Super charges are NO LONGER auto-refilled — supers cost real bounty
	#   now (SUPER_REFILL_COST = 60 per charge). Free refill made the paid
	#   button dead UI and devalued the resource.
	# - Shields read full at next combat start (player.start() does
	#   shield = max_shield), so write that to Run here too so the
	#   status bar shows the correct value before the player leaves.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "max_shield" in run and "current_shield" in run and int(run.max_shield) > 0:
			run.current_shield = int(run.max_shield)
	_roll_offers()
	_build_ui()
	if has_node("/root/Run"):
		get_node("/root/Run").bounty_changed.connect(_on_bounty_changed)


# ---- UI scaffold ----------------------------------------------------------

func _build_ui() -> void:
	# Static backdrop — solid dark band. Keeps the shop calm and lets the
	# floating translucent panels read clearly. Picking the cheap path
	# here per CLAUDE.md ("simpler"); galaxy_backdrop is overkill for an
	# interlude scene.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var band := ColorRect.new()
	band.color = Color(0.06, 0.08, 0.12, 1.0)
	band.position = Vector2(0, STATUS_H + MARGIN * 2)
	band.size = Vector2(HD_W, HD_H - (STATUS_H + MARGIN * 2))
	add_child(band)

	# HD overlay layer (matches shipyard V3 ui_layer.layer = 5).
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "OutpostOverlay"
	add_child(ui_layer)

	_build_status_panel(ui_layer)
	_build_columns(ui_layer)
	_build_toast(ui_layer)
	_refresh_status_panel()


func _build_status_panel(parent: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(MARGIN, MARGIN)
	panel.size = Vector2(HD_W - MARGIN * 2, STATUS_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	parent.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 32)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(h)

	# Title chunk.
	var title_v := VBoxContainer.new()
	title_v.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = Strings.OUTPOST_TITLE
	_style_label(title, FS_TITLE, Color(0.95, 0.92, 0.78))
	title_v.add_child(title)
	_loadout_lbl = Label.new()
	_loadout_lbl.text = ""
	_style_label(_loadout_lbl, FS_CAPTION, Color(0.62, 0.72, 0.82))
	title_v.add_child(_loadout_lbl)
	h.add_child(title_v)

	# Stat blocks.
	_hull_value_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_HULL)
	_shield_value_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_SHIELD)
	_mg_ammo_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_PRIMARY)
	_sec_ammo_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_SECONDARY)
	_super_value_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_SUPER)

	# Spacer to push bounty right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_bounty_value_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_BOUNTY, Color(0.95, 0.86, 0.45))


func _make_stat_block(parent: BoxContainer, caption_text: String, accent: Color = Color(0.78, 0.92, 1.0)) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var caption := Label.new()
	caption.text = caption_text
	_style_label(caption, FS_CAPTION, Color(0.55, 0.65, 0.75))
	v.add_child(caption)
	var value := Label.new()
	value.text = "—"
	_style_label(value, FS_STATUS_VALUE, accent)
	v.add_child(value)
	parent.add_child(v)
	return value


func _build_columns(parent: CanvasLayer) -> void:
	var top: float = STATUS_H + MARGIN * 2
	var height: float = HD_H - top - MARGIN
	var x: float = MARGIN
	# Weapons column.
	_weapons_box = _build_column(parent, Strings.OUTPOST_COL_WEAPONS, PANEL_BG_WEAPON,
			x, top, COL_WEAPONS_W, height)
	_render_weapon_offers()
	x += COL_WEAPONS_W + COL_GAP
	# Upgrades column.
	_upgrades_box = _build_column(parent, Strings.OUTPOST_COL_UPGRADES, PANEL_BG_UPGRADE,
			x, top, COL_UPGRADES_W, height)
	_render_upgrade_offers()
	x += COL_UPGRADES_W + COL_GAP
	# Services column gets whatever's left.
	var services_w: float = HD_W - MARGIN - x
	_services_box = _build_column(parent, Strings.OUTPOST_COL_SERVICES, PANEL_BG_SERVICE,
			x, top, services_w, height)
	_build_services()


func _build_column(parent: CanvasLayer, title_text: String, bg: Color,
		x: float, y: float, w: float, h: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(bg))
	parent.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(outer)

	var header := Label.new()
	header.text = title_text
	_style_label(header, FS_HEADER, Color(0.85, 0.90, 1.0))
	outer.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	return col


# ---- Weapons column -------------------------------------------------------

func _render_weapon_offers() -> void:
	for c in _weapons_box.get_children():
		c.queue_free()
	if _weapon_offers.is_empty():
		var lbl := Label.new()
		lbl.text = Strings.OUTPOST_WEAPONS_DEPLETED
		_style_label(lbl, FS_BODY, Color(0.72, 0.62, 0.62))
		_weapons_box.add_child(lbl)
		return
	for offer in _weapon_offers:
		_weapons_box.add_child(_make_weapon_card(offer))


func _make_weapon_card(offer: Dictionary) -> Control:
	var part = offer["part"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	var part_mk: int = int(part.mark) if "mark" in part else 1
	var tier: Dictionary = PartTier.tier_for_mk(part_mk)
	card.add_theme_stylebox_override("panel", _card_style_tier(tier["color"]))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	# Slot pill (left).
	var pill := Label.new()
	pill.text = _slot_short_name(int(part.slot_type))
	pill.custom_minimum_size = Vector2(96, 0)
	pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_label(pill, FS_CAPTION, _slot_color(int(part.slot_type)))
	row.add_child(pill)

	# Name + description (center).
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = part.get_display() if part.has_method("get_display") else String(part.display_name)
	_style_label(name_lbl, FS_BODY, Color(0.95, 0.95, 0.95))
	v.add_child(name_lbl)
	# Tier badge — color-coded label so player can size up a card at a glance.
	# Matches the card border tint (set above via _card_style_tier).
	var tier_lbl := Label.new()
	tier_lbl.text = PartTier.tier_label(part_mk)
	_style_label(tier_lbl, FS_CAPTION, tier["color"])
	v.add_child(tier_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = String(part.description)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_label(desc_lbl, FS_CAPTION, Color(0.72, 0.78, 0.85))
	v.add_child(desc_lbl)

	# Buy / equipped button (right).
	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(160, 56)
	buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_btn.add_theme_font_size_override("font_size", FS_BODY)
	var sold: bool = offer.get("sold", false)
	if sold:
		buy_btn.text = Strings.OUTPOST_BTN_EQUIPPED
		buy_btn.disabled = true
	else:
		buy_btn.text = Strings.OUTPOST_BTN_BUY % int(offer["cost"])
		buy_btn.disabled = _run_bounty() < int(offer["cost"])
	buy_btn.pressed.connect(_on_buy_weapon.bind(offer, buy_btn))
	row.add_child(buy_btn)

	return card


# ---- Upgrades column ------------------------------------------------------

func _render_upgrade_offers() -> void:
	for c in _upgrades_box.get_children():
		c.queue_free()
	if _upgrade_offers.is_empty():
		var lbl := Label.new()
		lbl.text = Strings.OUTPOST_UPGRADES_MAXED
		_style_label(lbl, FS_BODY, Color(0.72, 0.72, 0.62))
		_upgrades_box.add_child(lbl)
		return
	for offer in _upgrade_offers:
		_upgrades_box.add_child(_make_upgrade_card(offer))


func _make_upgrade_card(offer: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	var next_mk: int = int(offer["next_mk"])
	var tier: Dictionary = PartTier.tier_for_mk(next_mk)
	card.add_theme_stylebox_override("panel", _card_style_tier(tier["color"]))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = "%s  Mk.%d" % [offer["name"], next_mk]
	_style_label(name_lbl, FS_BODY, Color(0.95, 0.95, 0.95))
	v.add_child(name_lbl)
	# Tier badge — same scheme as weapons. Reads the Mk the player gets
	# AFTER buying, so a Mk.6 → Mk.7 upgrade shows "Tier IV - Improved".
	var tier_lbl := Label.new()
	tier_lbl.text = PartTier.tier_label(next_mk)
	_style_label(tier_lbl, FS_CAPTION, tier["color"])
	v.add_child(tier_lbl)
	var current_lbl := Label.new()
	current_lbl.text = "Currently Mk.%d" % _current_mk(offer["key"])
	_style_label(current_lbl, FS_CAPTION, Color(0.62, 0.72, 0.82))
	v.add_child(current_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = String(offer["desc"])
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_label(desc_lbl, FS_CAPTION, Color(0.72, 0.78, 0.85))
	v.add_child(desc_lbl)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(160, 56)
	buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_btn.add_theme_font_size_override("font_size", FS_BODY)
	var sold: bool = offer.get("sold", false)
	if sold:
		buy_btn.text = Strings.OUTPOST_BTN_PURCHASED
		buy_btn.disabled = true
	else:
		buy_btn.text = Strings.OUTPOST_BTN_BUY % int(offer["cost"])
		buy_btn.disabled = _run_bounty() < int(offer["cost"])
	buy_btn.pressed.connect(_on_buy_upgrade.bind(offer, buy_btn))
	row.add_child(buy_btn)
	return card


# ---- Services column ------------------------------------------------------

func _build_services() -> void:
	for c in _services_box.get_children():
		c.queue_free()

	# Hull Repair.
	_services_box.add_child(_make_service_button(
		Strings.SERVICE_HULL_REPAIR, HULL_REPAIR_COST, _on_repair, "repair"))
	# Shield refill button. Always shows as FREE / Shields Full — the actual
	# shield restore happened on _ready / will happen at combat start.
	var shield_btn := _make_service_button(Strings.SERVICE_SHIELD_REFILL, 0, _on_shield_refill, "shield")
	_services_box.add_child(shield_btn)
	# Primary ammo refill (CANNON: MG / Rotary Laser). Hidden when the
	# equipped cannon is unmetered (energy blaster, heavy blaster, etc.) —
	# _apply_service_button_state hides via disabled+label when ammo == -1.
	# Cost scales with rounds missing; partial refill allowed if the player
	# can't afford the full top-up. See _on_primary_ammo_refill.
	_services_box.add_child(_make_service_button(
		Strings.SERVICE_PRIMARY_AMMO, 0, _on_primary_ammo_refill, "primary_ammo"))
	# Secondary ammo refill (HARDPOINT_WING: Rocket Pod / Seeking Missile).
	# Hidden when no metered secondary is equipped. Same cost-scaled
	# partial-refill rules as primary.
	_services_box.add_child(_make_service_button(
		Strings.SERVICE_SECONDARY_AMMO, 0, _on_secondary_ammo_refill, "secondary_ammo"))
	# Super charge (per-charge purchase).
	_services_box.add_child(_make_service_button(
		Strings.SERVICE_SUPER_CHARGE, SUPER_REFILL_COST, _on_super_refill, "super"))

	# Sell Equipment subsection (storage list).
	var sep := HSeparator.new()
	_services_box.add_child(sep)
	var sell_header := Label.new()
	sell_header.text = Strings.OUTPOST_SELL_HEADER
	_style_label(sell_header, FS_CAPTION, Color(0.78, 0.92, 1.0))
	_services_box.add_child(sell_header)

	var storage_scroll := ScrollContainer.new()
	storage_scroll.custom_minimum_size = Vector2(0, 220)
	storage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_services_box.add_child(storage_scroll)
	_storage_box = VBoxContainer.new()
	_storage_box.add_theme_constant_override("separation", 6)
	_storage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_scroll.add_child(_storage_box)
	_render_storage()

	# Spacer pushes bottom buttons down.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_services_box.add_child(spacer)

	_refresh_btn = Button.new()
	_refresh_btn.custom_minimum_size = Vector2(0, 48)
	_refresh_btn.add_theme_font_size_override("font_size", FS_BODY)
	_refresh_btn.pressed.connect(_on_refresh_stock.bind(_refresh_btn))
	_update_refresh_btn_label()
	_services_box.add_child(_refresh_btn)

	var leave_btn := Button.new()
	leave_btn.text = Strings.OUTPOST_BTN_LEAVE
	leave_btn.custom_minimum_size = Vector2(0, 56)
	leave_btn.add_theme_font_size_override("font_size", FS_HEADER)
	leave_btn.pressed.connect(_on_leave)
	_services_box.add_child(leave_btn)


# Builds a Button with a meta tag so _refresh_services() can update its
# disabled state / label after every purchase. `kind` is a string key
# read by _refresh_services() to recompute affordability + visibility.
func _make_service_button(label_text: String, cost: int, handler: Callable, kind: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", FS_BODY)
	btn.set_meta("kind", kind)
	btn.set_meta("base_label", label_text)
	btn.set_meta("cost", cost)
	btn.pressed.connect(handler.bind(btn))
	_apply_service_button_state(btn)
	return btn


# Render the storage list (sell-back for any stored Part).
func _render_storage() -> void:
	if _storage_box == null:
		return
	for c in _storage_box.get_children():
		c.queue_free()
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if run.weapon_storage.is_empty():
		var lbl := Label.new()
		lbl.text = Strings.OUTPOST_STORAGE_EMPTY
		_style_label(lbl, FS_CAPTION, Color(0.55, 0.62, 0.70))
		_storage_box.add_child(lbl)
		return
	for i in range(run.weapon_storage.size()):
		_storage_box.add_child(_make_storage_row(run.weapon_storage[i], i))


func _make_storage_row(part, idx: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = part.get_display() if part.has_method("get_display") else String(part.display_name)
	_style_label(label, FS_CAPTION, Color(0.88, 0.92, 0.96))
	row.add_child(label)

	var equip_btn := Button.new()
	equip_btn.text = Strings.OUTPOST_BTN_EQUIP
	equip_btn.add_theme_font_size_override("font_size", FS_CAPTION)
	equip_btn.pressed.connect(_on_equip_stored.bind(idx))
	row.add_child(equip_btn)

	var sell_value: int = _sell_value_for(part)
	var sell_btn := Button.new()
	sell_btn.text = Strings.OUTPOST_BTN_SELL % sell_value
	sell_btn.add_theme_font_size_override("font_size", FS_CAPTION)
	sell_btn.pressed.connect(_on_sell_stored.bind(idx, sell_value))
	row.add_child(sell_btn)
	return row


# Sell price — 20% of the cannon-buy formula. Designer call (Roman 2026-05-25):
# old 50% sell-back let players resale-arbitrage and over-buy with no risk.
# 20% means re-rolling stock is an expensive mistake, not a free do-over.
# Floor of 5 so a Mk.1 part still gives the player something for the click.
func _sell_value_for(part) -> int:
	var mk: int = int(part.mark) if "mark" in part else 1
	var buy_cost: int = CANNON_BASE_COST + (mk - 1) * CANNON_COST_PER_MK
	return max(5, int(0.2 * float(buy_cost)))


# ---- Offer rolls ----------------------------------------------------------

func _roll_offers() -> void:
	# Per-visit randomization. Roman 2026-05-25: "each outpost should be
	# randomized when visited" — drop the deterministic run_seed mix so the
	# same node id revisited (or two outposts in the same sector) reroll
	# clean. _refresh_count is irrelevant once we randomize, but keep the
	# call so refreshes still touch the rng state explicitly.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if _refresh_count > 0:
		rng.seed = rng.seed ^ (_refresh_count * 101)

	var sector_idx: int = _current_sector()
	# Boss-clear cap bump: each row-boss already killed in this sector raises
	# the outpost's Mk floor. Encourages clearing the sector instead of
	# beelining bosses; rewards the player who actually risked the boss
	# fight with better stock at the next outpost they hit.
	var bosses_killed: int = _bosses_killed_in_sector()
	var max_mk_for_sector: int = mini(MAX_MK, sector_idx + MK_HIGH_OFFSET + bosses_killed)

	# Upgrades: 3 distinct rolls, skip maxed keys. The card shows the Mk
	# the player will be at AFTER buying — i.e. current_mk + 1 — so the
	# advertised number matches what the purchase handler actually
	# applies (run.set(key, _current_mk(key) + 1) at _on_buy_upgrade).
	# Pool gating uses max_mk_for_sector (sector-scaled cap), but the
	# displayed Mk is always exactly +1 over current, never the rolled
	# fantasy. Fixes "card says Mk 5 but you get Mk 3" (Roman, 2026-05-24).
	var pool: Array = []
	for u in UPGRADES:
		if _current_mk(u["key"]) < max_mk_for_sector:
			pool.append(u)
	pool.shuffle()
	_upgrade_offers.clear()
	for i in min(UPGRADES_COLUMN_COUNT, pool.size()):
		var u: Dictionary = pool[i]
		var next_mk: int = mini(MAX_MK, _current_mk(u["key"]) + 1)
		var cost: int = UPGRADE_BASE_COST + (next_mk - 1) * UPGRADE_COST_PER_MK
		_upgrade_offers.append({
			"key": u["key"], "name": u["name"], "desc": u["desc"],
			"next_mk": next_mk, "cost": cost, "sold": false,
		})

	# Weapons: WEAPONS_COLUMN_COUNT cards. Slot weighted 50/25/25 via
	# WEAPON_SLOT_WEIGHTS; mark via the triangular roll capped at sector+3.
	# Dedupe by (slot, mark, name) — Roman 2026-05-25: "shop should not
	# offer repeats". Bounded reroll so we don't loop forever if the catalog
	# can't fill 5 unique slots at the current sector cap.
	_weapon_offers.clear()
	var seen: Dictionary = {}
	for i in WEAPONS_COLUMN_COUNT:
		var picked = null
		var picked_mk: int = 1
		for attempt in 8:
			var slot: int = int(WEAPON_SLOT_WEIGHTS[rng.randi() % WEAPON_SLOT_WEIGHTS.size()])
			picked_mk = _roll_weighted_mark(rng, 1, max_mk_for_sector)
			var part = PartCatalog.roll_for_slot(rng, slot, picked_mk)
			if part == null:
				continue
			var part_name: String = String(part.display_name)
			# Weapons Phase 1: CANNON dedupe-up. If the player already owns
			# this cannon (by display_name in Run.cannon_pool), offer the
			# next mark up — provided the sector cap allows it. If the
			# owned mark is already at the cap, re-roll a different
			# cannon. Blaster at index 0 is permanent / always owned but
			# IS upgradeable, so the same rule applies to it.
			if slot == SlotTypes.SlotType.CANNON and has_node("/root/Run"):
				var run = get_node("/root/Run")
				var owned_idx: int = -1
				if run.has_method("find_owned_cannon_by_name"):
					owned_idx = int(run.find_owned_cannon_by_name(part_name))
				if owned_idx >= 0:
					var owned_mk: int = int(run.cannon_pool[owned_idx].mark)
					if owned_mk >= max_mk_for_sector or owned_mk >= MAX_MK:
						# Cap reached — try a different cannon next attempt.
						continue
					picked_mk = owned_mk + 1
					if "mark" in part:
						part.mark = picked_mk
			var key: String = "%d:%d:%s" % [slot, picked_mk, part_name]
			if seen.has(key):
				continue
			seen[key] = true
			picked = part
			break
		if picked == null:
			continue
		var cost: int = CANNON_BASE_COST + (picked_mk - 1) * CANNON_COST_PER_MK
		_weapon_offers.append({"part": picked, "cost": cost, "sold": false})


# Triangular mark roll — average of two dice peaks at the midpoint.
func _roll_weighted_mark(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if hi <= lo:
		return clampi(lo, 1, MAX_MK)
	var a: int = rng.randi_range(lo, hi)
	var b: int = rng.randi_range(lo, hi)
	return clampi(int(round(float(a + b) * 0.5)), lo, hi)


# Count of row-bosses already killed in the current sector. Drives the
# outpost Mk-cap floor bump — clearing a row boss bumps the cap for the
# rest of this sector's outposts. Walks the sector_map_cache rows since
# that's the single source of truth for boss completion.
func _bosses_killed_in_sector() -> int:
	if not has_node("/root/Run"):
		return 0
	var run = get_node("/root/Run")
	var cache: Dictionary = run.sector_map_cache
	if cache.is_empty() or not cache.has("rows"):
		return 0
	var killed: int = 0
	for row in cache.rows:
		if row.has("boss") and row.boss.get("completed", false):
			killed += 1
	return killed


func _current_sector() -> int:
	if not has_node("/root/Run"):
		return 1
	var run = get_node("/root/Run")
	if "sectors_cleared" in run:
		return int(run.sectors_cleared) + 1
	return 1


# ---- Purchase handlers ----------------------------------------------------

func _on_buy_upgrade(offer: Dictionary, btn: Button) -> void:
	if offer.get("sold", false):
		return
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var cost: int = int(offer["cost"])
	if int(run.bounty) < cost:
		return
	run.bounty -= cost
	var key: String = String(offer["key"])
	run.set(key, _current_mk(key) + 1)
	offer["sold"] = true
	btn.text = Strings.OUTPOST_BTN_PURCHASED
	btn.disabled = true
	_refresh_status_panel()
	_show_toast(Strings.TOAST_UPGRADE_PURCHASED)


func _on_buy_weapon(offer: Dictionary, btn: Button) -> void:
	if offer.get("sold", false):
		return
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var cost: int = int(offer["cost"])
	if int(run.bounty) < cost:
		return
	run.bounty -= cost
	_apply_part_to_player(offer["part"])
	offer["sold"] = true
	btn.text = Strings.OUTPOST_BTN_EQUIPPED
	btn.disabled = true
	_render_storage()
	_refresh_status_panel()
	_show_toast(Strings.TOAST_EQUIPPED)


# Generalized equip path. Looks at part.slot_type and:
#   - displaces whatever was in that slot of loadout_snapshot into
#     weapon_storage (so the player can sell it later)
#   - writes the new part into loadout_snapshot[slot]
#   - for ammo-bearing secondary parts, seeds Run.secondary_ammo so the
#     fresh magazine survives until next combat (where the part's apply()
#     reads it back via Run on equip).
# No live Player exists in a meta scene, so player-side apply runs at
# next combat via player._ready() → loadout.equip().
func _apply_part_to_player(part) -> void:
	# Delegates to Run.equip_part so the sector map's Manage Ship modal and the
	# outpost share one canonical equip path. See Run.equip_part for the
	# slot-displacement + ammo / super-charges reseed contract.
	if part == null or not has_node("/root/Run"):
		return
	get_node("/root/Run").equip_part(part)


func _on_equip_stored(idx: int) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if idx < 0 or idx >= run.weapon_storage.size():
		return
	var picked = run.weapon_storage[idx]
	run.weapon_storage.remove_at(idx)
	# Equip the picked part. _apply_part_to_player handles displacing the
	# currently-equipped same-slot part back into storage — do NOT push
	# it manually here (would double-append).
	_apply_part_to_player(picked)
	_render_storage()
	_refresh_status_panel()
	_show_toast(Strings.TOAST_EQUIPPED)


func _on_sell_stored(idx: int, sell_value: int) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if idx < 0 or idx >= run.weapon_storage.size():
		return
	run.weapon_storage.remove_at(idx)
	run.bounty += sell_value
	_render_storage()
	_refresh_status_panel()


func _hull_repair_cost() -> int:
	var base: int = HULL_REPAIR_COST
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "hull_mk" in run and int(run.hull_mk) >= 9:
			base = int(round(float(base) * 0.70))
	return base


func _on_repair(btn: Button) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	if int(run.max_hull) <= 0:
		return
	if int(run.current_hull) >= int(run.max_hull):
		return
	var cost: int = _hull_repair_cost()
	if int(run.bounty) < cost:
		return
	run.bounty -= cost
	run.current_hull = clampi(int(run.current_hull) + 1, 0, int(run.max_hull))
	_refresh_status_panel()


func _on_shield_refill(btn: Button) -> void:
	# Free refill — mirrors what player.start() does on next combat anyway.
	# This exists so the status bar reads "full" before the player leaves.
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.max_shield) <= 0:
		return
	run.current_shield = int(run.max_shield)
	_refresh_status_panel()


# ---- Cost-scaled partial ammo refills -------------------------------------
# Both refill paths share the same shape:
#   rounds_missing = max - current
#   full_cost      = ceil(rounds_missing * AMMO_COST_PER_ROUND)
#   if bounty >= full_cost: refill all, charge full_cost
#   else: refill floor(bounty / AMMO_COST_PER_ROUND) rounds, charge that much
# Partial refills are explicit (not a silent fallback) — the button label
# in _apply_service_button_state always advertises the full top-up cost so
# the player isn't surprised by the partial.

# Returns the equipped CANNON's max ammo (via its base_ammo on metered
# primaries). 0 if no metered primary is equipped.
func _primary_ammo_max() -> int:
	if not has_node("/root/Run"):
		return 0
	var run = get_node("/root/Run")
	var cannon = run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
	if cannon == null:
		return 0
	if "base_ammo" in cannon:
		return int(cannon.base_ammo)
	return 0


func _ammo_refill_cost(missing: int) -> int:
	if missing <= 0:
		return 0
	return int(ceil(float(missing) * AMMO_COST_PER_ROUND))


# Returns [refilled_rounds, cost_paid] for the affordability of `bounty`
# against a top-up of `missing` rounds. Caps refilled at `missing`.
func _ammo_refill_partial(bounty: int, missing: int) -> Array:
	if missing <= 0 or bounty <= 0:
		return [0, 0]
	var full_cost: int = _ammo_refill_cost(missing)
	if bounty >= full_cost:
		return [missing, full_cost]
	# Partial — floor(bounty / per_round), capped at missing.
	var rounds: int = int(floor(float(bounty) / AMMO_COST_PER_ROUND))
	if rounds <= 0:
		return [0, 0]
	if rounds > missing:
		rounds = missing
	var cost: int = int(ceil(float(rounds) * AMMO_COST_PER_ROUND))
	return [rounds, cost]


func _on_primary_ammo_refill(btn: Button) -> void:
	# Weapons Phase 1: flat-cost refill on the ACTIVE non-blaster cannon's
	# magazine. Reads ammo_max from the cannon Part (cannon_pool entry) and
	# fills current_ammo to that cap. Blaster (idx 0) is greyed in
	# _apply_service_button_state so this handler only runs for replacements.
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.active_cannon_idx) == 0:
		return
	var active = run.get_active_cannon()
	if active == null or not ("current_ammo" in active) or not ("ammo_max" in active):
		return
	if "no_outpost_refill" in active and bool(active.no_outpost_refill):
		return
	var cap: int = int(active.ammo_max)
	if cap <= 0:
		return
	if int(active.current_ammo) >= cap:
		return
	var cost: int = PRIMARY_REFILL_COST
	if "refill_cost_override" in active and int(active.refill_cost_override) >= 0:
		cost = int(active.refill_cost_override)
	if int(run.bounty) < cost:
		return
	run.bounty -= cost
	active.current_ammo = cap
	# Mirror to Run.ammo + player.ammo so HUD updates immediately on return.
	run.ammo = cap
	_show_toast(Strings.TOAST_PRIMARY_REFILLED)
	_refresh_status_panel()


func _on_secondary_ammo_refill(btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.secondary_ammo) < 0 or int(run.secondary_ammo_max) <= 0:
		return
	var missing: int = int(run.secondary_ammo_max) - int(run.secondary_ammo)
	if missing <= 0:
		return
	var result: Array = _ammo_refill_partial(int(run.bounty), missing)
	var rounds: int = int(result[0])
	var cost: int = int(result[1])
	if rounds <= 0:
		return
	run.bounty -= cost
	run.secondary_ammo = clampi(int(run.secondary_ammo) + rounds, 0, int(run.secondary_ammo_max))
	_show_toast(Strings.TOAST_SECONDARY_REFILLED % [rounds, cost])
	_refresh_status_panel()


func _on_super_refill(btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.bounty) < SUPER_REFILL_COST:
		return
	if not ("super_charges" in run) or not ("max_super_charges" in run):
		return
	if int(run.max_super_charges) <= 0:
		return
	if int(run.super_charges) >= int(run.max_super_charges):
		return
	run.bounty -= SUPER_REFILL_COST
	run.super_charges = clampi(int(run.super_charges) + 1, 0, int(run.max_super_charges))
	_refresh_status_panel()


func _on_refresh_stock(btn: Button) -> void:
	# Reroll the weapon + upgrade columns. Cost doubles per use within the
	# same outpost visit — keeps re-rolling from being a strict gain over
	# leaving + re-entering, and the ramp punishes spam.
	var cost: int = _current_refresh_cost()
	if not has_node("/root/Run") or int(_run_bounty()) < cost:
		return
	var run = get_node("/root/Run")
	run.bounty -= cost
	_refresh_count += 1
	_roll_offers()
	_render_weapon_offers()
	_render_upgrade_offers()
	_update_refresh_btn_label()
	_refresh_status_panel()


# Current refresh price: REFRESH_BASE_COST * 2^uses, capped at
# REFRESH_MAX_DOUBLINGS doublings so the price plateaus rather than
# running away after many refreshes.
func _current_refresh_cost() -> int:
	var doublings: int = mini(_refresh_count, REFRESH_MAX_DOUBLINGS)
	return REFRESH_BASE_COST << doublings


func _update_refresh_btn_label() -> void:
	if _refresh_btn == null:
		return
	var cost: int = _current_refresh_cost()
	if _refresh_count >= REFRESH_MAX_DOUBLINGS:
		_refresh_btn.text = Strings.OUTPOST_BTN_REFRESH_MAX % cost
	else:
		_refresh_btn.text = Strings.OUTPOST_BTN_REFRESH % cost
	_refresh_btn.disabled = _run_bounty() < cost


func _on_leave() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if String(run.current_node_id) != "":
			run.mark_node_completed(String(run.current_node_id))
	# Drop the HD scope before change_scene so the sector map's _ready
	# isn't briefly rendered at 1920×1080.
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)


# ---- Status panel refresh -------------------------------------------------

# Poll-based refresh: no Player exists in a meta scene, so the live
# player-side signals (hull_changed, secondary_ammo_changed, etc.) don't
# fire here. Every purchase handler calls _refresh_status_panel() at the
# end. Run.bounty_changed is the one signal we DO get for free.
func _refresh_status_panel() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")

	if _hull_value_lbl:
		if int(run.max_hull) > 0:
			_hull_value_lbl.text = "%d / %d" % [int(run.current_hull), int(run.max_hull)]
		else:
			_hull_value_lbl.text = "—"
	if _shield_value_lbl:
		if int(run.max_shield) > 0:
			_shield_value_lbl.text = "%d / %d" % [int(run.current_shield), int(run.max_shield)]
		else:
			_shield_value_lbl.text = "—"
	if _mg_ammo_lbl:
		# Weapons Phase 1: PRIMARY label reads active cannon. Blaster shows
		# infinity; replacement primaries show current/max from the Part.
		if int(run.active_cannon_idx) == 0:
			_mg_ammo_lbl.text = "∞"
		else:
			var active = run.get_active_cannon()
			if active != null and "current_ammo" in active and "ammo_max" in active and int(active.ammo_max) > 0:
				_mg_ammo_lbl.text = "%d / %d" % [int(active.current_ammo), int(active.ammo_max)]
			elif int(run.ammo) >= 0:
				_mg_ammo_lbl.text = "%d" % int(run.ammo)
			else:
				_mg_ammo_lbl.text = "—"
	if _sec_ammo_lbl:
		if int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0:
			_sec_ammo_lbl.text = "%d / %d" % [int(run.secondary_ammo), int(run.secondary_ammo_max)]
		elif int(run.secondary_ammo) >= 0:
			_sec_ammo_lbl.text = "%d" % int(run.secondary_ammo)
		else:
			_sec_ammo_lbl.text = "—"
	if _super_value_lbl:
		if int(run.max_super_charges) > 0:
			_super_value_lbl.text = "%d / %d" % [int(run.super_charges), int(run.max_super_charges)]
		else:
			_super_value_lbl.text = "—"
	if _bounty_value_lbl:
		_bounty_value_lbl.text = "%d" % int(run.bounty)
	if _loadout_lbl:
		_loadout_lbl.text = _format_loadout_line(run)

	_refresh_services()
	_refresh_card_affordability()
	_update_refresh_btn_label()


func _on_bounty_changed(_value) -> void:
	_refresh_status_panel()


func _refresh_card_affordability() -> void:
	# Re-evaluate disabled state for unsold buy buttons after a bounty change.
	if _weapons_box:
		for i in range(min(_weapon_offers.size(), _weapons_box.get_child_count())):
			var offer: Dictionary = _weapon_offers[i]
			if offer.get("sold", false):
				continue
			var btn := _find_buy_button(_weapons_box.get_child(i))
			if btn:
				btn.disabled = _run_bounty() < int(offer["cost"])
	if _upgrades_box:
		for i in range(min(_upgrade_offers.size(), _upgrades_box.get_child_count())):
			var offer: Dictionary = _upgrade_offers[i]
			if offer.get("sold", false):
				continue
			var btn := _find_buy_button(_upgrades_box.get_child(i))
			if btn:
				btn.disabled = _run_bounty() < int(offer["cost"])


func _find_buy_button(card: Node) -> Button:
	for child in card.get_children():
		if child is Button and (String(child.text).begins_with("Buy") or String(child.text).begins_with("Swap")):
			return child
		var nested := _find_buy_button(child)
		if nested:
			return nested
	return null


func _refresh_services() -> void:
	if _services_box == null:
		return
	for child in _services_box.get_children():
		if child is Button and child.has_meta("kind"):
			_apply_service_button_state(child)


# Per-kind enable/disable + label update. Centralizes the rules so we
# don't drift between _build_services() and the per-purchase handlers.
func _apply_service_button_state(btn: Button) -> void:
	var kind: String = String(btn.get_meta("kind"))
	var base_label: String = String(btn.get_meta("base_label"))
	var cost: int = int(btn.get_meta("cost"))
	var run = null
	if has_node("/root/Run"):
		run = get_node("/root/Run")
	match kind:
		"repair":
			if run == null or int(run.max_hull) <= 0:
				btn.disabled = true
				btn.text = "%s %s" % [base_label, Strings.SERVICE_SUFFIX_NO_SHIP]
				return
			if int(run.current_hull) >= int(run.max_hull):
				btn.disabled = true
				btn.text = Strings.SERVICE_STATE_HULL_FULL
				return
			var repair_cost: int = _hull_repair_cost()
			btn.disabled = _run_bounty() < repair_cost
			btn.text = "%s  (%d)" % [base_label, repair_cost]
		"shield":
			if run == null or int(run.max_shield) <= 0:
				btn.disabled = true
				btn.text = "%s %s" % [base_label, Strings.SERVICE_SUFFIX_NO_SHIELD]
				return
			if int(run.current_shield) >= int(run.max_shield):
				btn.disabled = true
				btn.text = Strings.SERVICE_STATE_SHIELDS_FULL
				return
			btn.disabled = false
			btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_FREE]
		"primary_ammo":
			# Weapons Phase 1: flat-cost refill on the active replacement
			# primary. Blaster active → greyed (no ammo to refill). Active
			# slot not metered or already full → greyed with reason. Cost is
			# PRIMARY_REFILL_COST unless the cannon declares refill_cost_override.
			# Cannons with no_outpost_refill (lasers) show as auto-regen.
			if run == null:
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_NO_RUN]
				return
			if int(run.active_cannon_idx) == 0:
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_BLASTER_INFINITE]
				return
			var active = run.get_active_cannon()
			if active == null or not ("current_ammo" in active) or not ("ammo_max" in active):
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_NO_PRIMARY_AMMO]
				return
			if "no_outpost_refill" in active and bool(active.no_outpost_refill):
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_AUTO_REGEN]
				return
			var pmax: int = int(active.ammo_max)
			if pmax <= 0:
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_NO_PRIMARY_AMMO]
				return
			if int(active.current_ammo) >= pmax:
				btn.disabled = true
				btn.text = Strings.SERVICE_STATE_AMMO_FULL % base_label
				return
			var pcost: int = PRIMARY_REFILL_COST
			if "refill_cost_override" in active and int(active.refill_cost_override) >= 0:
				pcost = int(active.refill_cost_override)
			btn.disabled = _run_bounty() < pcost
			btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_REFILL_COST % pcost]
		"secondary_ammo":
			if run == null or int(run.secondary_ammo) < 0 or int(run.secondary_ammo_max) <= 0:
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_NONE_EQUIPPED]
				return
			var smiss: int = int(run.secondary_ammo_max) - int(run.secondary_ammo)
			if smiss <= 0:
				btn.disabled = true
				btn.text = Strings.SERVICE_STATE_AMMO_FULL % base_label
				return
			var sfull: int = _ammo_refill_cost(smiss)
			var saff: Array = _ammo_refill_partial(_run_bounty(), smiss)
			var saff_rounds: int = int(saff[0])
			var saff_cost: int = int(saff[1])
			if saff_rounds <= 0:
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_NEED % [smiss, sfull]]
				return
			btn.disabled = false
			if saff_rounds < smiss:
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_PARTIAL % [saff_rounds, saff_cost]]
			else:
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SUFFIX_AMMO_COST % [saff_rounds, saff_cost]]
		"super":
			if run == null or int(run.max_super_charges) <= 0:
				btn.disabled = true
				btn.text = Strings.SERVICE_STATE_SUPER_NONE
				return
			if int(run.super_charges) >= int(run.max_super_charges):
				btn.disabled = true
				btn.text = Strings.SERVICE_STATE_SUPER_FULL
				return
			btn.disabled = _run_bounty() < cost
			btn.text = "%s  (%d)" % [base_label, cost]


# ---- Toast ----------------------------------------------------------------

func _build_toast(parent: CanvasLayer) -> void:
	_toast_label = Label.new()
	_toast_label.text = ""
	_toast_label.modulate.a = 0.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.position = Vector2(HD_W * 0.5 - 200, STATUS_H + MARGIN * 2 + 24)
	_toast_label.size = Vector2(400, 48)
	_style_label(_toast_label, FS_HEADER, Color(0.55, 0.95, 0.65))
	parent.add_child(_toast_label)


func _show_toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(0.7)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


# ---- Helpers --------------------------------------------------------------

func _current_mk(key: String) -> int:
	if not has_node("/root/Run"):
		return 0
	return int(get_node("/root/Run").get(key))


func _run_bounty() -> int:
	if not has_node("/root/Run"):
		return 0
	return int(get_node("/root/Run").bounty)


func _slot_short_name(slot: int) -> String:
	match slot:
		SlotTypes.SlotType.CANNON: return Strings.SLOT_NAME_PRIMARY
		SlotTypes.SlotType.HARDPOINT_WING: return Strings.SLOT_NAME_SECONDARY
		SlotTypes.SlotType.DEVICE_BAY_1: return Strings.SLOT_NAME_SUPER
		SlotTypes.SlotType.SHIELD: return Strings.SLOT_NAME_SHIELD
		SlotTypes.SlotType.ENGINE: return Strings.SLOT_NAME_ENGINE
		SlotTypes.SlotType.TAIL: return Strings.SLOT_NAME_TAIL
		SlotTypes.SlotType.WING_LEFT: return Strings.SLOT_NAME_WING_L
		SlotTypes.SlotType.WING_RIGHT: return Strings.SLOT_NAME_WING_R
	return Strings.SLOT_NAME_PART


func _slot_color(slot: int) -> Color:
	match slot:
		SlotTypes.SlotType.CANNON: return Color(1.0, 0.78, 0.45)
		SlotTypes.SlotType.HARDPOINT_WING: return Color(0.55, 0.85, 1.0)
		SlotTypes.SlotType.DEVICE_BAY_1: return Color(1.0, 0.55, 0.95)
	return Color(0.75, 0.80, 0.85)


func _format_loadout_line(run) -> String:
	var parts: Array[String] = []
	var cannon = run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
	parts.append(Strings.LOADOUT_PRIMARY % _short_part_text(cannon))
	var sec = run.loadout_snapshot.get(SlotTypes.SlotType.HARDPOINT_WING, null)
	parts.append(Strings.LOADOUT_SECONDARY % _short_part_text(sec))
	var sup = run.loadout_snapshot.get(SlotTypes.SlotType.DEVICE_BAY_1, null)
	parts.append(Strings.LOADOUT_SUPER % _short_part_text(sup))
	return "   ".join(parts)


func _short_part_text(part) -> String:
	if part == null:
		return "—"
	if part.has_method("get_display"):
		return String(part.get_display())
	return String(part.display_name)


func _panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = PANEL_BORDER
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.85)
	sb.border_color = Color(0.35, 0.45, 0.60, 0.9)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


# Tier-tinted variant — thicker left border in the tier color so cards
# fan out visually by quality. Background + other borders match _card_style
# so the layout doesn't shift.
func _card_style_tier(tier_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.85)
	sb.border_color = Color(0.35, 0.45, 0.60, 0.9)
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	# Left edge is the tier stripe (4px so it reads at HD scale).
	sb.border_width_left = 4
	# Stylebox uses one border_color for all sides; emulate per-side by
	# layering corner_detail isn't supported on StyleBoxFlat. Instead set
	# the dominant color to tier and let the thin top/right/bottom carry
	# that same hue (still reads as a left stripe due to width difference).
	sb.border_color = tier_color
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _style_label(lbl: Label, font_size: int, color: Color) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
