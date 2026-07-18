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
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Strings = preload("res://scripts/strings/strings.gd")
const Conditions = preload("res://scripts/systems/conditions.gd")
const OutpostSfx = preload("res://scripts/effects/outpost_sfx.gd")

# RETIRED 2026-06-13 — ALL upgrades are now bay MODULES (hull → Reinforced Hull, thrusters
# → Thrusters, shield capacity → Shield Core's Mk; earlier armor/shield-recharge/self-repair/
# hull-plating). No purchasable upgrades remain — progression is weapons + modules, which roll
# in the PARTS column. The upgrades shop column was removed; the Run int fields stay for save compat.
const MAX_MK := 9
const HULL_REPAIR_COST := 250
# Repairs now ALWAYS cost a material at baseline (Roman 2026-07-11, design §8) —
# Cheap/Complex Repairs adjust the count, and Easy Repairs strips it to bounty only.
# The baseline count + all condition-aware cost math live in OutpostEcon (the SSOT
# shared with the LIVE dock outpost_arrival.gd) — see OutpostEcon.REPAIR_BASE_MATERIALS.
# Ammo refill: cost scales with the number of rounds the player is missing,
# so a near-empty mag is more expensive than a top-up. COST_PER_ROUND tuned
# so a full 1000-round MG refill = 500 bounty (still a major expense), a
# full 60-round secondary refill = 30 bounty (incidental), and partials
# fall out linearly. Partial refills are allowed when the player can't
# cover the full top-up — see _on_primary_ammo_refill.
const AMMO_COST_PER_ROUND := 1.0
# Weapons Phase 1 (2026-05-26): primary ammo refill is now a flat-cost
# button — refills the active cannon_pool entry's magazine to full. Blaster
# (active_cannon_idx == 0) has infinite ammo so the button greys out.
# Placeholder value pending designer tuning.
const PRIMARY_REFILL_COST := 100
# Super charges: per-charge purchase. Doubled from 30 → 60 (Roman 2026-05-25):
# free auto-refill on outpost visit removed at the same time, so the player
# now PAYS to keep their super topped up — supers are a real economy lever.
const SUPER_REFILL_COST := 120
const CANNON_BASE_COST := 116
const CANNON_COST_PER_MK := 70

# Weapons column slot weights: cannon dominates (it's primary), with secondary,
# super, Shift-mode, and passive-module swaps as occasional offers. 4 cannon /
# 2 secondary / 1 super (Smart Bomb, the lone DEVICE_BAY_1) / 2 mode (Phase|Hyper) /
# 2 module = 11 weights; rolled with replacement for the 5-card weapons column.
# SHIFT_MODE offers roll Phase/Hyper (Focus is default-only, not in the pool) + price as weapons.
const WEAPON_SLOT_WEIGHTS := [
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.CANNON,
	SlotTypes.SlotType.HARDPOINT_WING,
	SlotTypes.SlotType.HARDPOINT_WING,
	SlotTypes.SlotType.DEVICE_BAY_1,
	SlotTypes.SlotType.SHIFT_MODE,
	SlotTypes.SlotType.SHIFT_MODE,
	# Passive Module bay — modules roll in the shop like any other part (item-gen rules).
	SlotTypes.SlotType.MODULE,
	SlotTypes.SlotType.MODULE,
]
const WEAPONS_COLUMN_COUNT := 5

# ---- HD layout constants (1920×1080) -----------------------------------
const HD_W := 1920
const HD_H := 1080
const STATUS_H := 96
const MARGIN := 24
const COL_GAP := 18
const COL_WEAPONS_W := 920  # widened 2026-06-13 — absorbs the retired upgrades column
const COL_SERVICES_W := 400  # fills remainder; recomputed at build
# 3-column salvage layout (Roman 2026-06-14): SHOP | LOADOUT | SERVICES.
const COL_SHOP_W := 600
const COL_LOADOUT_W := 660
# Standardized card + button sizing (Roman 2026-06-15).
const MANAGED_CARD_H := 104
const CARD_BTN_SIZE := Vector2(112, 42)
const INFO_BTN_SIZE := Vector2(42, 42)
# Player-portrait damage overlay — same shader/maps the player + enemies use.
const _DamageShader = preload("res://graphics/damage_noise.gdshader")
const _DamageNoise = preload("res://resources/noise_damage.tres")
const _DamageEdge = preload("res://resources/edge_distance_flat.tres")
const CARD_H := 140
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)
const PANEL_BG_WEAPON := Color(0.10, 0.05, 0.12, 0.65)
const PANEL_BG_UPGRADE := Color(0.05, 0.08, 0.14, 0.65)
const PANEL_BG_SERVICE := Color(0.05, 0.10, 0.08, 0.65)
# Aligned to the UiTheme HD scale (docs/ui_color_reference.md) so the shop reads
# at the same size as every other menu. The 600px columns have room for it.
const FS_TITLE := UiTheme.FONT_SIZE_TITLE        # 48
const FS_HEADER := UiTheme.FONT_SIZE_HEADER      # 30
const FS_BODY := UiTheme.FONT_SIZE_BODY          # 22
const FS_CAPTION := UiTheme.FONT_SIZE_CAPTION    # 16
const FS_STATUS := UiTheme.FONT_SIZE_CAPTION     # 16
const FS_STATUS_VALUE := UiTheme.FONT_SIZE_BODY  # 22

var _weapon_offers: Array = []   # [{part, cost, sold}]

# UI refs.
var _bounty_value_lbl: Label = null
var _materials_value_lbl: Label = null
var _module_cap_lbl: Label = null
var _hull_value_lbl: Label = null
var _modifiers_lbl: Label = null
var _weapons_box: VBoxContainer = null
var _loadout_box: VBoxContainer = null
var _modules_box: VBoxContainer = null
var _services_box: VBoxContainer = null
# Services column tab switcher (SERVICES | STATUS) — the services body + the new
# conditions-detail view are sibling VBoxes inside _services_box; only one is
# visible at a time. Default = SERVICES (current behavior preserved).
var _services_content: VBoxContainer = null
var _status_content: VBoxContainer = null
var _tab_services_btn: Button = null
var _tab_status_btn: Button = null
var _status_active: bool = false
var _status_expanded: Dictionary = {}  # condition id -> blurb-row expanded?
var _toast_label: Label = null
# Card UPGRADE state: when true, every card shows its Upgrade button instead of the
# management buttons (Set Active / Unslot / Equip / Scrap / Remove). Toggled from Services.
var _upgrade_mode: bool = false
var _upgrade_toggle_btn: Button = null
var _damage_portrait_mat: ShaderMaterial = null
var _toast_tween: Tween = null
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	# HD (1920×1080) overlay via the shared HD base. RAII scope auto-restores
	# native scale on scene exit; _on_leave drops it earlier (once the fade
	# covers) so the next native scene doesn't flash an HD blow-up.
	_hd_scope = HdScreen.enter(self)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("outpost")
	# Auto-restore on visit. Designer policy (Roman 2026-05-25):
	# - Super charges are NO LONGER auto-refilled — supers cost real bounty
	#   now (SUPER_REFILL_COST per charge). Free refill made the paid
	#   button dead UI and devalued the resource.
	# - Shields read full at next combat start (player.start() does
	#   shield = max_shield), so write that to Run here too so the
	#   status bar shows the correct value before the player leaves.
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		if "max_shield" in run and "current_shield" in run and int(run.max_shield) > 0:
			run.current_shield = int(run.max_shield)
		# Task #4: dedupe equipped items — one of each.
		_ensure_no_duplicate_equipped(run)
		# Run-summary Phase 2: tally this outpost visit (the hub is a sector-map button,
		# not a POI, so it never flows through mark_node_completed).
		if run.has_method("stat_add"):
			run.stat_add("stations_visited", 1)
	_load_or_roll_offers()
	_build_ui()
	if has_node("/root/Run"):
		get_node("/root/Run").bounty_changed.connect(_on_bounty_changed)
		get_node("/root/Run").materials_changed.connect(_on_bounty_changed)


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
	title.text = _outpost_name()
	_style_label(title, FS_TITLE, Color(0.95, 0.92, 0.78))
	title_v.add_child(title)
	# Active sector modifiers (so the player sees the theme they're fighting in).
	_modifiers_lbl = Label.new()
	_modifiers_lbl.text = ""
	_style_label(_modifiers_lbl, FS_CAPTION, Color(0.95, 0.72, 0.55))
	title_v.add_child(_modifiers_lbl)
	h.add_child(title_v)

	# Player portrait + hull, centered in the bar (Roman 2026-06-15). Ammo / shield / super
	# readouts moved onto their part cards; hull rides next to the ship.
	var lsp := Control.new()
	lsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(lsp)
	h.add_child(_build_player_portrait())
	var rsp := Control.new()
	rsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rsp)

	_materials_value_lbl = _make_stat_block(h, Strings.OUTPOST_STAT_MATERIALS, Color(0.55, 0.95, 0.75))
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
	# SHOP — buy higher-mark parts. "Defeat a boss to restock" hint sits right of the title.
	var restock_hint := Label.new()
	restock_hint.text = Strings.OUTPOST_RESTOCK_HINT
	_style_label(restock_hint, FS_CAPTION, Color(0.88, 0.72, 0.55))
	_weapons_box = _build_column(parent, Strings.OUTPOST_COL_SHOP, PANEL_BG_WEAPON,
			x, top, COL_SHOP_W, height, restock_hint)
	_render_weapon_offers()
	x += COL_SHOP_W + COL_GAP
	# LOADOUT — equipped weapons/mode (unslot + upgrade) + CARGO (equip + scrap).
	_loadout_box = _build_column(parent, Strings.OUTPOST_COL_LOADOUT, PANEL_BG_UPGRADE,
			x, top, COL_LOADOUT_W, height)
	_build_loadout()
	x += COL_LOADOUT_W + COL_GAP
	# MODULES + SERVICES — bay occupancy (N / size) sits right of the MODULES title.
	_module_cap_lbl = Label.new()
	_style_label(_module_cap_lbl, FS_CAPTION, _slot_color(SlotTypes.SlotType.MODULE))
	var services_w: float = HD_W - MARGIN - x
	_services_box = _build_column(parent, Strings.OUTPOST_COL_MODULES, PANEL_BG_SERVICE,
			x, top, services_w, height, _module_cap_lbl)
	_build_services()


func _build_column(parent: CanvasLayer, title_text: String, bg: Color,
		x: float, y: float, w: float, h: float, header_extra: Control = null) -> VBoxContainer:
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

	# Title row: title (left) + an optional extra widget pinned to the right on the same line.
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := Label.new()
	header.text = title_text
	_style_label(header, FS_HEADER, Color(0.85, 0.90, 1.0))
	header_row.add_child(header)
	if header_extra != null:
		var hsp := Control.new()
		hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_row.add_child(hsp)
		header_extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header_row.add_child(header_extra)
	outer.add_child(header_row)

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

	# Name + subtitle + description (center). No left pill — the category lives in the subtitle
	# now (Roman 2026-06-14 card refinement).
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = String(part.display_name)
	_style_label(name_lbl, FS_BODY + 2, tier["color"])  # Rarity color on the name itself.
	v.add_child(name_lbl)

	# Subtitle: "Tier <N> <Quality> <Category>".
	var type_lbl := Label.new()
	type_lbl.text = _card_subtitle(part)
	_style_label(type_lbl, FS_CAPTION + 2, tier["color"])
	v.add_child(type_lbl)

	# Task #7: Dynamic stat line computed from the part's curves.
	var stats_text: String = _stats_display_for_part(part, part_mk)
	if not stats_text.is_empty():
		var stats_lbl := Label.new()
		stats_lbl.text = stats_text
		_style_label(stats_lbl, FS_CAPTION, Color(0.62, 0.80, 0.92))  # Stats in a cooler tone.
		v.add_child(stats_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = String(part.description)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_label(desc_lbl, FS_CAPTION, Color(0.72, 0.78, 0.85))
	v.add_child(desc_lbl)

	# Info "i" button — same part/mark codex as the loadout cards.
	row.add_child(_make_info_button(_show_info_popup.bind(part)))

	# Buy / equipped button (right).
	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(160, 56)
	buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(buy_btn)
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



# ---- Services column ------------------------------------------------------

func _build_services() -> void:
	for c in _services_box.get_children():
		c.queue_free()

	# Tab switcher — SERVICES | STATUS. Swaps which sibling content VBox shows
	# inside this column. Default = SERVICES (current behavior). STATUS lists the
	# run's active Conditions with per-row info expanders.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_services_btn = Button.new()
	_tab_services_btn.text = Strings.OUTPOST_TAB_SERVICES
	_tab_services_btn.custom_minimum_size = Vector2(0, 44)
	_tab_services_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_tab_services_btn)
	_tab_services_btn.add_theme_font_size_override("font_size", FS_BODY)
	_tab_services_btn.pressed.connect(_on_select_status_tab.bind(false))
	tabs.add_child(_tab_services_btn)
	_tab_status_btn = Button.new()
	_tab_status_btn.text = Strings.OUTPOST_TAB_STATUS
	_tab_status_btn.custom_minimum_size = Vector2(0, 44)
	_tab_status_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_tab_status_btn)
	_tab_status_btn.add_theme_font_size_override("font_size", FS_BODY)
	_tab_status_btn.pressed.connect(_on_select_status_tab.bind(true))
	tabs.add_child(_tab_status_btn)
	_services_box.add_child(tabs)

	# Content panes — one visible at a time.
	_services_content = VBoxContainer.new()
	_services_content.add_theme_constant_override("separation", 12)
	_services_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_services_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_services_box.add_child(_services_content)
	_build_services_content(_services_content)

	_status_content = VBoxContainer.new()
	_status_content.add_theme_constant_override("separation", 8)
	_status_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_services_box.add_child(_status_content)
	_build_status_content()

	_apply_status_tab_visibility()


# Original SERVICES body (modules bay + services + leave), now hosted in the
# SERVICES pane of the tab switcher.
func _build_services_content(parent: VBoxContainer) -> void:
	# MODULES section — the installed passive bay gets its own section (Roman 2026-06-14).
	# Re-rendered into _modules_box after every bay/currency change.
	var mod_scroll := ScrollContainer.new()
	mod_scroll.custom_minimum_size = Vector2(0, 380)
	mod_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(mod_scroll)
	_modules_box = VBoxContainer.new()
	_modules_box.add_theme_constant_override("separation", 8)
	_modules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_scroll.add_child(_modules_box)
	_render_modules()

	parent.add_child(HSeparator.new())
	var svc_hdr := Label.new()
	svc_hdr.text = Strings.OUTPOST_COL_SERVICES
	_style_label(svc_hdr, FS_HEADER, Color(0.85, 0.90, 1.0))
	parent.add_child(svc_hdr)

	# Hull Repair.
	parent.add_child(_make_service_button(
		Strings.SERVICE_HULL_REPAIR, HULL_REPAIR_COST, _on_repair, "repair"))
	# Restock All — buys ammo/charges for every owned ammo-using part. Per-card "Restock" buttons
	# live on the individual cards now (Roman 2026-06-15); this is the buy-everything convenience.
	var restock_all := Button.new()
	restock_all.text = Strings.OUTPOST_BTN_RESTOCK_ALL
	restock_all.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(restock_all)
	restock_all.add_theme_font_size_override("font_size", FS_BODY)
	restock_all.pressed.connect(_on_restock_all)
	parent.add_child(restock_all)
	# Upgrade-mode toggle — swaps every card to its Upgrade button (and back).
	_upgrade_toggle_btn = Button.new()
	_upgrade_toggle_btn.text = Strings.OUTPOST_BTN_MANAGE_MODE if _upgrade_mode else Strings.OUTPOST_BTN_UPGRADE_MODE
	_upgrade_toggle_btn.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(_upgrade_toggle_btn)
	_upgrade_toggle_btn.add_theme_font_size_override("font_size", FS_BODY)
	_upgrade_toggle_btn.pressed.connect(_on_toggle_upgrade_mode)
	parent.add_child(_upgrade_toggle_btn)

	# Spacer pushes bottom buttons down.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

	# (Refresh-stock button removed 2026-06-08 — stock now re-rolls only on boss kill.)
	var leave_btn := Button.new()
	leave_btn.text = Strings.OUTPOST_BTN_LEAVE
	leave_btn.custom_minimum_size = Vector2(0, 56)
	UiTheme.style_button(leave_btn)
	leave_btn.add_theme_font_size_override("font_size", FS_HEADER)
	leave_btn.pressed.connect(_on_leave)
	parent.add_child(leave_btn)


# ---- STATUS tab — active-Conditions detail view ---------------------------
# Conditions are patrol-static, so this pane is built once. Banes are listed
# first (threat descending), then boons; each row has a threat chip + an "i"
# button that toggles an expanded blurb row beneath it (independent toggles).

func _on_select_status_tab(status: bool) -> void:
	_status_active = status
	_apply_status_tab_visibility()


func _apply_status_tab_visibility() -> void:
	if _services_content != null:
		_services_content.visible = not _status_active
	if _status_content != null:
		_status_content.visible = _status_active
	# Active tab reads bright; inactive tab dims.
	if _tab_services_btn != null:
		_tab_services_btn.modulate = Color(0.52, 0.55, 0.62) if _status_active else Color(1, 1, 1)
	if _tab_status_btn != null:
		_tab_status_btn.modulate = Color(1, 1, 1) if _status_active else Color(0.52, 0.55, 0.62)


func _build_status_content() -> void:
	if _status_content == null:
		return
	for c in _status_content.get_children():
		c.queue_free()
	var run = get_node_or_null("/root/Run")
	var active: Array = []
	if run != null and "active_conditions" in run:
		active = run.active_conditions

	# Header block.
	if active.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = Strings.SECTOR_MODIFIERS_NONE
		none_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_label(none_lbl, FS_BODY, Color(0.72, 0.80, 0.88))
		_status_content.add_child(none_lbl)
		return

	var net: int = run.condition_net_threat()
	var threat_lbl := Label.new()
	# Player-facing rename Threat → Difficulty (payout coupling cut 2026-07-09; no % caption).
	threat_lbl.text = Strings.OUTPOST_STATUS_DIFFICULTY % net
	_style_label(threat_lbl, FS_HEADER, Color(0.95, 0.86, 0.45))
	_status_content.add_child(threat_lbl)
	_status_content.add_child(HSeparator.new())

	# Rows in a scroll container sized to the remaining column height.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_status_content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	# Banes first (threat descending), then boons — a plain threat-descending sort.
	var sorted: Array = active.duplicate()
	sorted.sort_custom(func(a, b): return Conditions.threat_of(String(a)) > Conditions.threat_of(String(b)))
	for id in sorted:
		_add_condition_row(rows, String(id))


func _add_condition_row(parent: VBoxContainer, id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = Conditions.label(id)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_label(name_lbl, FS_BODY, Color(0.90, 0.93, 0.98))
	row.add_child(name_lbl)

	# Threat chip — warm for a bane (+), cool for a boon (−). Reuses the status-bar
	# modifiers warm tone + the materials green already used in this file.
	var t: int = Conditions.threat_of(id)
	var chip := Label.new()
	chip.text = ("+%d" % t) if t > 0 else ("%d" % t)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.custom_minimum_size = Vector2(52, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_label(chip, FS_BODY, Color(0.95, 0.72, 0.55) if t > 0 else Color(0.55, 0.95, 0.75))
	row.add_child(chip)

	# Expanded blurb row — hidden until the "i" is pressed (independent toggle).
	# Built before the info button so the toggle closure can capture it; added to
	# the parent AFTER the row so it still renders beneath it (layout unchanged).
	var blurb := Label.new()
	blurb.text = Conditions.blurb(id)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(blurb, FS_CAPTION, Color(0.60, 0.68, 0.76))
	blurb.visible = bool(_status_expanded.get(id, false))

	# Info toggle — same "i" look as the part cards.
	row.add_child(_make_info_button(func() -> void:
		var now := not blurb.visible
		blurb.visible = now
		_status_expanded[id] = now))
	parent.add_child(row)
	parent.add_child(blurb)


# Builds a Button with a meta tag so _refresh_services() can update its
# disabled state / label after every purchase. `kind` is a string key
# read by _refresh_services() to recompute affordability + visibility.
func _make_service_button(label_text: String, cost: int, handler: Callable, kind: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(btn)
	btn.add_theme_font_size_override("font_size", FS_BODY)
	btn.set_meta("kind", kind)
	btn.set_meta("base_label", label_text)
	btn.set_meta("cost", cost)
	btn.pressed.connect(handler.bind(btn))
	_apply_service_button_state(btn)
	return btn


# The square "i" info button — one builder for all three sites (shop cards, loadout/
# module cards, STATUS-tab condition rows). Pixel-identical styling; only the pressed
# target differs, so callers pass the Callable to wire.
func _make_info_button(on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = Strings.OUTPOST_INFO
	btn.custom_minimum_size = INFO_BTN_SIZE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(btn)
	btn.add_theme_font_size_override("font_size", FS_BODY)
	btn.pressed.connect(on_pressed)
	return btn


# ---- Loadout column (folded-in Manage Ship) -------------------------------
# Equipped weapons / mode (Unslot + Upgrade) + module bay (Remove + Upgrade) + CARGO
# (owned spares: Equip + Scrap). Re-rendered after every loadout/currency action. Reuses the
# canonical Run.equip_part / unequip_slot / add_module / remove_module / set_active_cannon /
# upgrade_part paths so this stays the single source of loadout truth.

func _build_loadout() -> void:
	_render_loadout_column()


func _render_loadout_column() -> void:
	if _loadout_box == null or not has_node("/root/Run"):
		return
	for c in _loadout_box.get_children():
		c.queue_free()
	var run := get_node("/root/Run")

	# Cannons (two-slot Blaster + Primary). Blaster is permanent (no unslot).
	var blaster = run.cannon_pool[0] if run.cannon_pool.size() > 0 else run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
	var primary = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
	var active_idx: int = int(run.active_cannon_idx)
	_loadout_box.add_child(_make_managed_card("BLASTER", blaster, _cannon_buttons(blaster, 0, active_idx),
			_equipped_stats_line(blaster, SlotTypes.SlotType.CANNON)))
	if primary != null:
		_loadout_box.add_child(_make_managed_card("PRIMARY", primary, _cannon_buttons(primary, 1, active_idx),
				_equipped_stats_line(primary, SlotTypes.SlotType.CANNON)))
	else:
		_loadout_box.add_child(_make_managed_card("PRIMARY", null, []))

	# Single slots — Secondary / Super / Shift Mode (Unslot + Upgrade).
	for entry in [
			{"slot": SlotTypes.SlotType.HARDPOINT_WING, "pill": Strings.SLOT_NAME_SECONDARY},
			{"slot": SlotTypes.SlotType.DEVICE_BAY_1, "pill": Strings.SLOT_NAME_SUPER},
			{"slot": SlotTypes.SlotType.SHIFT_MODE, "pill": Strings.SLOT_NAME_MODE}]:
		var slot: int = int(entry["slot"])
		var part = run.loadout_snapshot.get(slot, null)
		_loadout_box.add_child(_make_managed_card(String(entry["pill"]), part, _slot_buttons(part, slot),
				_equipped_stats_line(part, slot)))

	# (Module bay moved to its own MODULES section in the right column — Roman 2026-06-14.)

	# Cargo — owned spares (weapon_storage + inventory), Equip + Scrap.
	_loadout_box.add_child(HSeparator.new())
	var cargo_hdr := Label.new()
	cargo_hdr.text = Strings.OUTPOST_CARGO_HEADER
	_style_label(cargo_hdr, FS_HEADER, Color(0.85, 0.90, 1.0))
	_loadout_box.add_child(cargo_hdr)
	var any := false
	for i in range(run.weapon_storage.size()):
		var wp = run.weapon_storage[i]
		_loadout_box.add_child(_make_managed_card(_slot_short_name(int(wp.slot_type)), wp, _cargo_buttons(wp, i, "weapon_storage"),
				_stats_display_for_part(wp, int(wp.mark) if "mark" in wp else 1)))
		any = true
	for i in range(run.inventory.size()):
		var ip = run.inventory[i]
		_loadout_box.add_child(_make_managed_card(_slot_short_name(int(ip.slot_type)), ip, _cargo_buttons(ip, i, "inventory"),
				_stats_display_for_part(ip, int(ip.mark) if "mark" in ip else 1)))
		any = true
	if not any:
		var empty := Label.new()
		empty.text = Strings.OUTPOST_CARGO_EMPTY
		_style_label(empty, FS_CAPTION, Color(0.55, 0.62, 0.70))
		_loadout_box.add_child(empty)


# Installed passive modules — their own section in the right column (Roman 2026-06-14).
func _render_modules() -> void:
	if _modules_box == null or not has_node("/root/Run"):
		return
	for c in _modules_box.get_children():
		c.queue_free()
	var run := get_node("/root/Run")
	if _module_cap_lbl != null:
		_module_cap_lbl.text = "%d / %d" % [run.modules.size(), run.MODULE_BAY_SIZE]
	if run.modules.is_empty():
		var empty := Label.new()
		empty.text = Strings.OUTPOST_MODULES_EMPTY
		_style_label(empty, FS_CAPTION, Color(0.55, 0.62, 0.70))
		_modules_box.add_child(empty)
		return
	for i in range(run.modules.size()):
		var m = run.modules[i]
		var mst: String = _shield_core_stats_line(m) if (m != null and "module_id" in m and String(m.module_id) in ["shield_core", "shield_core_corpo"]) else ""
		_modules_box.add_child(_make_managed_card("MODULE", m, _module_buttons(m, i), mst))


# Button-spec builders. Each spec is {text, cb, disabled} for a Button, or {badge} for a label.
# In UPGRADE MODE every owned card shows ONLY its Upgrade button; otherwise the management
# buttons (Set Active / Restock / Unslot / Equip / Scrap / Remove).
func _cannon_buttons(part, idx: int, active_idx: int) -> Array:
	if part == null:
		return []
	if _upgrade_mode:
		return [_upgrade_button_spec(part)]
	var btns: Array = []
	if idx == active_idx:
		btns.append({"badge": Strings.OUTPOST_BADGE_ACTIVE})
	else:
		btns.append({"text": Strings.OUTPOST_BTN_SET_ACTIVE, "cb": _on_set_active.bind(idx)})
	# Metered primary (slot 1) can be restocked + unslotted; the permanent blaster can't.
	if idx == 1:
		if _is_metered(part):
			btns.append({"text": Strings.OUTPOST_BTN_RESTOCK, "cb": _on_restock_primary})
		btns.append({"text": Strings.OUTPOST_BTN_UNSLOT, "cb": _on_unslot_primary})
	return btns


func _slot_buttons(part, slot: int) -> Array:
	if part == null:
		return []
	if _upgrade_mode:
		return [_upgrade_button_spec(part)]
	var btns: Array = []
	if slot == SlotTypes.SlotType.HARDPOINT_WING and _secondary_is_metered():
		btns.append({"text": Strings.OUTPOST_BTN_RESTOCK, "cb": _on_restock_secondary})
	elif slot == SlotTypes.SlotType.DEVICE_BAY_1:
		btns.append({"text": Strings.OUTPOST_BTN_RESTOCK, "cb": _on_restock_super})
	btns.append({"text": Strings.OUTPOST_BTN_UNSLOT, "cb": _on_unslot.bind(slot)})  # always-on
	return btns


func _module_buttons(part, idx: int) -> Array:
	if part == null:
		return []
	if _upgrade_mode:
		return [_upgrade_button_spec(part)]
	return [{"text": Strings.OUTPOST_BTN_REMOVE, "cb": _on_remove_module.bind(idx)}]


func _cargo_buttons(part, idx: int, source: String) -> Array:
	if _upgrade_mode:
		return [_upgrade_button_spec(part)]
	return [
		{"text": Strings.OUTPOST_BTN_EQUIP, "cb": _on_equip_owned.bind(idx, source)},
		{"text": Strings.OUTPOST_BTN_SCRAP % _scrap_value(part), "cb": _on_scrap_owned.bind(idx, source)},
	]


func _is_metered(part) -> bool:
	return part != null and "ammo_max" in part and int(part.ammo_max) > 0


func _secondary_is_metered() -> bool:
	if not has_node("/root/Run"):
		return false
	return int(get_node("/root/Run").secondary_ammo_max) > 0


# ---- Card stat lines (ammo / charges / shield) ----------------------------
# The live ammo for an EQUIPPED ammo-bearing card. Cargo/shop cards show dmg/rof instead.
func _equipped_stats_line(part, slot: int) -> String:
	if not has_node("/root/Run"):
		return ""
	var run = get_node("/root/Run")
	match slot:
		SlotTypes.SlotType.CANNON:
			if _is_metered(part):
				return Strings.CARD_STAT_AMMO % [int(part.current_ammo), int(part.ammo_max)]
			return Strings.CARD_STAT_UNLIMITED
		SlotTypes.SlotType.HARDPOINT_WING:
			if int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0:
				return Strings.CARD_STAT_AMMO % [int(run.secondary_ammo), int(run.secondary_ammo_max)]
		SlotTypes.SlotType.DEVICE_BAY_1:
			if int(run.max_super_charges) > 0:
				return Strings.CARD_STAT_CHARGES % [int(run.super_charges), int(run.max_super_charges)]
	return ""


# Shield-core stats: total charges (core base + mark bonus) + LIVE recharge delay /
# pips-per-second (base 5s / 1 per s, improved by an installed Shield Capacitor or the
# Corpo core's own fast-recharge — best wins, mirroring the player-side minf applies).
func _shield_core_stats_line(part) -> String:
	var cap: int = 10
	if part != null and part.has_method("base_charges"):
		cap = int(part.base_charges())
	if part != null and part.has_method("_capacity_bonus"):
		cap += int(part._capacity_bonus())
	var delay := 5.0
	var interval := 1.0
	var run = get_node_or_null("/root/Run")
	if run != null and "modules" in run:
		for m in run.modules:
			if m != null and m.has_method("regen_delay"):
				delay = minf(delay, float(m.regen_delay()))
			if m != null and m.has_method("regen_interval"):
				interval = minf(interval, float(m.regen_interval()))
	return Strings.CARD_STAT_SHIELD % [cap, delay, 1.0 / maxf(interval, 0.01)]


# Upgrade button: target Mk + materials + bounty cost, disabled at max Mk or when unaffordable.
func _upgrade_button_spec(part) -> Dictionary:
	var run = get_node_or_null("/root/Run")
	if run == null or not run.can_upgrade_part(part):
		return {"text": Strings.OUTPOST_BTN_UPGRADE_MAX, "disabled": true}
	var new_mk: int = int(part.mark) + 1
	var costs := _upgrade_costs(new_mk, part)
	var mats: int = int(costs["mats"])
	var bounty_cost: int = int(costs["bounty"])
	var afford: bool = int(run.materials) >= mats and int(run.bounty) >= bounty_cost
	return {
		"text": Strings.OUTPOST_BTN_UPGRADE % [new_mk, mats, bounty_cost],
		"cb": _on_upgrade_part.bind(part),
		"disabled": not afford,
	}


# A loadout/cargo/module card: name (fills the row) + a "Tier <N> <Quality> <Category>"
# subtitle + action buttons/badges (right). `slot_label` labels an EMPTY slot only. No left
# pill — the category lives in the subtitle now (Roman 2026-06-14 card refinement).
func _make_managed_card(slot_label: String, part, buttons: Array, stats_text: String = "") -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, MANAGED_CARD_H)
	var mk: int = int(part.mark) if (part != null and "mark" in part) else 0
	var tier_color: Color = PartTier.tier_for_mk(mk)["color"] if mk > 0 else Color(0.35, 0.45, 0.60)
	card.add_theme_stylebox_override("panel", _card_style_tier(tier_color))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var name_lbl := Label.new()
	name_lbl.text = String(part.display_name) if part != null else (slot_label + " — empty")
	_style_label(name_lbl, FS_BODY + 2, Color(0.95, 0.95, 0.95) if part != null else Color(0.55, 0.6, 0.7))
	v.add_child(name_lbl)
	if part != null and mk > 0:
		var sub_lbl := Label.new()
		sub_lbl.text = _card_subtitle(part)
		_style_label(sub_lbl, FS_CAPTION + 2, PartTier.tier_for_mk(mk)["color"])
		v.add_child(sub_lbl)
	if stats_text != "":
		var st_lbl := Label.new()
		st_lbl.text = stats_text
		_style_label(st_lbl, FS_CAPTION, Color(0.62, 0.80, 0.92))
		v.add_child(st_lbl)

	# Info "i" button — opens the part's stat/mark codex (Roman 2026-06-15). Always available.
	if part != null:
		row.add_child(_make_info_button(_show_info_popup.bind(part)))

	for spec in buttons:
		if spec.has("badge"):
			var badge := Label.new()
			badge.text = String(spec["badge"])
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.custom_minimum_size = CARD_BTN_SIZE
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_style_label(badge, FS_CAPTION, Color(0.55, 1.0, 0.50))
			row.add_child(badge)
			continue
		var btn := Button.new()
		btn.text = String(spec["text"])
		btn.custom_minimum_size = CARD_BTN_SIZE
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiTheme.style_button(btn)
		btn.add_theme_font_size_override("font_size", FS_CAPTION)
		btn.disabled = bool(spec.get("disabled", false))
		var cb = spec.get("cb", null)
		if cb is Callable and (cb as Callable).is_valid():
			btn.pressed.connect(cb)
		row.add_child(btn)
	return card


# ---- Part info / mark-progression popup (the card "i" button) -------------
func _show_info_popup(part) -> void:
	if part == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "InfoPopup"
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(HD_W * 0.5 - 380, HD_H * 0.5 - 320)
	panel.custom_minimum_size = Vector2(760, 640)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.06, 0.10, 0.98)))
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = String(part.display_name)
	_style_label(title, FS_HEADER, Color(0.95, 0.92, 0.78))
	v.add_child(title)
	if "description" in part and String(part.description) != "":
		var desc := Label.new()
		desc.text = String(part.description)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_label(desc, FS_CAPTION + 2, Color(0.78, 0.85, 0.92))
		v.add_child(desc)
	v.add_child(HSeparator.new())
	var hdr := Label.new()
	hdr.text = Strings.OUTPOST_INFO_PROGRESSION
	_style_label(hdr, FS_CAPTION + 2, Color(0.62, 0.80, 0.92))
	v.add_child(hdr)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var maxmk: int = int(part.max_mark) if "max_mark" in part else 9
	var cur: int = int(part.mark) if "mark" in part else 1
	for m in range(1, maxmk + 1):
		var line: String = _stats_display_for_part(part, m)
		var t: Dictionary = PartTier.tier_for_mk(m)
		var marker: String = "▶ " if m == cur else "    "
		var r := Label.new()
		r.text = "%sMk.%d  (Tier %s %s)%s" % [marker, m, t["tier"], t["name"], ("   ·   " + line) if line != "" else ""]
		_style_label(r, FS_CAPTION + 2, Color(0.98, 0.98, 0.85) if m == cur else Color(0.72, 0.78, 0.85))
		rows.add_child(r)
	var close := Button.new()
	close.text = Strings.OUTPOST_INFO_CLOSE
	close.custom_minimum_size = Vector2(0, 56)
	UiTheme.style_button(close)
	close.add_theme_font_size_override("font_size", FS_BODY)
	close.pressed.connect(func(): layer.queue_free())
	v.add_child(close)


# "Tier <N> <Quality> <Category>" — e.g. "Tier III Refined Primary Weapon" / "Tier I Basic Module".
func _card_subtitle(part) -> String:
	if part == null:
		return ""
	var mk: int = int(part.mark) if "mark" in part else 1
	var t: Dictionary = PartTier.tier_for_mk(mk)
	var slot: int = int(part.slot_type) if "slot_type" in part else -1
	# Mk first so an in-band upgrade (e.g. Mk.1->2, both "Tier I Basic") still visibly changes.
	return "Mk.%d · Tier %s %s %s" % [mk, t["tier"], t["name"], _type_name_for_part(part, slot)]


# Scrap value = the item's Mk (1 Material per Mk).
func _scrap_value(part) -> int:
	return int(part.mark) if (part != null and "mark" in part) else 1


# Upgrade bounty cost = 50% of the new Mk's shop value (the outpost labor fee). Respects
# the part's shop-cost overrides (shield cores) so a core's Mk isn't a flat-fee steal.
func _upgrade_bounty_cost(new_mk: int, part = null) -> int:
	return int(floor(0.5 * float(_part_shop_cost(part, new_mk))))


# Single source for an upgrade's material + bounty cost — read by BOTH the button
# label/affordability (_upgrade_button_spec) AND the spend (_on_upgrade_part), so
# the shown cost can never drift from the charged cost. Delegates to OutpostEcon
# (the SSOT shared with the dock): material mult / no-mats + bounty mult / no-bounty.
func _upgrade_costs(new_mk: int, part = null) -> Dictionary:
	return OutpostEcon.upgrade_costs(get_node_or_null("/root/Run"), new_mk, _upgrade_bounty_cost(new_mk, part))


func _run_materials() -> int:
	if not has_node("/root/Run"):
		return 0
	return int(get_node("/root/Run").materials)


# The generated, per-sector-persistent outpost name (set in Run.start_new_sector). Falls back to
# a generic title for dev launches that skip sector generation.
func _outpost_name() -> String:
	if has_node("/root/Run"):
		var cache = get_node("/root/Run").sector_map_cache
		if cache is Dictionary:
			var nm := String(cache.get("outpost_name", ""))
			if nm != "":
				return nm
	return "OUTPOST"


# ---- Player portrait (header center) --------------------------------------
# A static ship portrait: the real body sprite + recolored livery + the damage-overlay shader
# (no engine glow), rendered in a small SubViewport, with the hull count beside it.
func _build_player_portrait() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sub := SubViewportContainer.new()
	sub.stretch = true
	sub.custom_minimum_size = Vector2(80, 80)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var vp := SubViewport.new()
	vp.size = Vector2i(40, 40)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.add_child(vp)
	_add_ship_portrait_sprite(vp)
	box.add_child(sub)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cap := Label.new()
	cap.text = Strings.OUTPOST_STAT_HULL
	_style_label(cap, FS_CAPTION, Color(0.55, 0.65, 0.75))
	hv.add_child(cap)
	_hull_value_lbl = Label.new()
	_hull_value_lbl.text = "—"
	_style_label(_hull_value_lbl, FS_STATUS_VALUE, Color(0.78, 0.92, 1.0))
	hv.add_child(_hull_value_lbl)
	box.add_child(hv)
	return box


func _add_ship_portrait_sprite(vp: SubViewport) -> void:
	var v := "a"
	if has_node("/root/Run"):
		v = ["a", "b", "c"][clampi(int(get_node("/root/Run").ship_variant), 0, 2)]
	var body_tex = load("res://graphics/player/player_ship_%s_body.png" % v)
	if body_tex == null:
		return
	var body := Sprite2D.new()
	body.texture = body_tex
	body.hframes = 3
	body.frame = 1
	body.position = Vector2(20, 20)
	body.scale = Vector2(1.6, 1.6)
	_damage_portrait_mat = _make_portrait_damage_mat()
	if _damage_portrait_mat != null:
		body.material = _damage_portrait_mat
	var livery_tex = load("res://graphics/player/player_ship_%s_livery.png" % v)
	if livery_tex != null:
		var lv := Sprite2D.new()
		lv.texture = livery_tex
		lv.hframes = 3
		lv.frame = 1
		var lmat := ShaderMaterial.new()
		lmat.shader = load("res://scenes/player/livery_color.gdshader")
		lmat.set_shader_parameter("tint_color", _portrait_livery_color())
		lv.material = lmat
		body.add_child(lv)
	vp.add_child(body)
	_update_portrait_damage()


func _make_portrait_damage_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _DamageShader
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", _DamageNoise)
	mat.set_shader_parameter("edge_distance_map", _DamageEdge)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	mat.set_shader_parameter("max_strength", 0.9)
	mat.set_shader_parameter("edge_bias_strength", 0.3)
	mat.set_shader_parameter("details_opacity", 0.1)
	mat.set_shader_parameter("edge_color", Color("494e55"))
	mat.set_shader_parameter("details_color", Color("cacaca"))
	return mat


func _update_portrait_damage() -> void:
	if _damage_portrait_mat == null or not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var mh: int = int(run.max_hull)
	if mh <= 0:
		return
	var denom: float = maxf(float(mh) - 1.0, 1.0)
	var lvl: float = clampf(0.6 * (float(mh) - float(run.current_hull)) / denom, 0.0, 0.6)
	_damage_portrait_mat.set_shader_parameter("sensitivity", lvl)


func _portrait_livery_color() -> Color:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if bool(run.livery_chosen):
			return run.livery_color
	return Color(0.85, 0.25, 0.25)


# ---- Loadout action handlers ----------------------------------------------

func _on_set_active(idx: int) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	run.set_active_cannon(idx)
	OutpostSfx.play("equip")
	_render_loadout_column()
	_refresh_status_panel()


func _on_unslot(slot: int) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	var part = run.loadout_snapshot.get(slot, null)
	if part == null:
		return
	run.weapon_storage.append(part)
	run.unequip_slot(slot)   # erases slot + zeros secondary ammo / super charges
	OutpostSfx.play("unequip")
	_show_toast(Strings.TOAST_UNSLOTTED)
	_render_loadout_column()
	_refresh_status_panel()


func _on_remove_module(idx: int) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	var m = run.remove_module(idx)
	if m != null:
		run.inventory.append(m)
	OutpostSfx.play("unequip")
	_show_toast(Strings.TOAST_UNSLOTTED)
	_render_loadout_column()
	_refresh_status_panel()


func _on_equip_owned(idx: int, source: String) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	var arr: Array = _cargo_array(run, source)
	if idx < 0 or idx >= arr.size():
		return
	var picked = arr[idx]
	# Module → bay list (only if room; else leave it in cargo so nothing is lost).
	if "slot_type" in picked and int(picked.slot_type) == int(SlotTypes.SlotType.MODULE):
		if run.add_module(picked):
			arr.remove_at(idx)
		OutpostSfx.play("equip")
		_render_loadout_column()
		_refresh_status_panel()
		return
	arr.remove_at(idx)
	run.equip_part(picked)   # displaces same-slot part → weapon_storage
	OutpostSfx.play("equip")
	_show_toast(Strings.TOAST_EQUIPPED)
	_render_loadout_column()
	_refresh_status_panel()


func _on_scrap_owned(idx: int, source: String) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	var arr: Array = _cargo_array(run, source)
	if idx < 0 or idx >= arr.size():
		return
	var value: int = _scrap_value(arr[idx])
	arr.remove_at(idx)
	run.add_materials(value)
	OutpostSfx.play("unequip")
	_show_toast(Strings.TOAST_SCRAPPED % value)
	_render_loadout_column()
	_refresh_status_panel()


func _on_upgrade_part(part) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null or not run.can_upgrade_part(part):
		return
	var new_mk: int = int(part.mark) + 1
	var costs := _upgrade_costs(new_mk, part)
	var mats: int = int(costs["mats"])
	var bounty_cost: int = int(costs["bounty"])
	if int(run.materials) < mats or int(run.bounty) < bounty_cost:
		return
	run.spend_materials(mats)
	run.spend_bounty(bounty_cost)
	run.upgrade_part(part)
	OutpostSfx.play("upgrade")
	_show_toast(Strings.TOAST_UPGRADED % int(part.mark))
	_render_loadout_column()
	_refresh_status_panel()


func _cargo_array(run, source: String) -> Array:
	match source:
		"weapon_storage": return run.weapon_storage
		"inventory": return run.inventory
	return []


# Unslot the metered primary cannon → cargo, reverting to the permanent blaster.
func _on_unslot_primary() -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	var prim = run.get_primary_cannon()
	if prim == null:
		return
	run.weapon_storage.append(prim)
	if run.cannon_pool.size() > 1:
		run.cannon_pool.remove_at(1)
	run.active_cannon_idx = 0
	run.loadout_snapshot[SlotTypes.SlotType.CANNON] = run.get_active_cannon()
	run.ammo = -1   # back to the infinite blaster
	OutpostSfx.play("unequip")
	_show_toast(Strings.TOAST_UNSLOTTED)
	_render_loadout_column()
	_refresh_status_panel()


# Per-card restock wrappers — reuse the service-refill logic (its btn arg is unused).
func _on_restock_primary() -> void:
	_on_primary_ammo_refill(null)

func _on_restock_secondary() -> void:
	_on_secondary_ammo_refill(null)

func _on_restock_super() -> void:
	_on_super_refill(null)


# Restock All — top up the primary + secondary, then buy as many super charges as affordable.
func _on_restock_all() -> void:
	_on_primary_ammo_refill(null)
	_on_secondary_ammo_refill(null)
	var run = get_node_or_null("/root/Run")
	if run != null:
		var guard := 0
		var super_cost: int = _restock_cost(SUPER_REFILL_COST)  # Sector Conditions restock mult
		while int(run.super_charges) < int(run.max_super_charges) and int(run.bounty) >= super_cost and guard < 30:
			_on_super_refill(null)
			guard += 1
	_refresh_status_panel()


# Toggle the card UPGRADE state (Services button) — cards swap to their Upgrade buttons.
func _on_toggle_upgrade_mode() -> void:
	_upgrade_mode = not _upgrade_mode
	if _upgrade_toggle_btn != null:
		_upgrade_toggle_btn.text = Strings.OUTPOST_BTN_MANAGE_MODE if _upgrade_mode else Strings.OUTPOST_BTN_UPGRADE_MODE
	_render_loadout_column()
	_render_modules()


# ---- Offer rolls ----------------------------------------------------------

# Persistent-hub stock: keep the Run-persisted offers across visits and only re-roll
# on a boss refresh (Run.outpost_needs_refresh) or the first-ever visit (empty stock).
# The offers array is shared with Run by reference, so "sold" flags persist too.
func _load_or_roll_offers() -> void:
	if not has_node("/root/Run"):
		_roll_offers()
		return
	var run := get_node("/root/Run")
	var have_stock: bool = not run.outpost_weapon_offers.is_empty()
	if run.outpost_needs_refresh or not have_stock:
		_roll_offers()
		run.outpost_weapon_offers = _weapon_offers
		run.outpost_needs_refresh = false
	else:
		_weapon_offers = run.outpost_weapon_offers


func _roll_offers() -> void:
	# Fresh roll of the weapon + upgrade columns — called on the first outpost visit
	# and on each boss-kill refresh (flagged by Run.on_boss_defeated).
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Shop Mk cap is boss-kill driven (Roman 2026-06-08): starts at 3, +3 per boss
	# defeated this run, so 2 boss kills opens Mk9. Run-wide count (Run.bosses_defeated),
	# not per-sector — bosses are the progression gate for the whole run.
	var bosses_killed: int = int(get_node("/root/Run").bosses_defeated) if has_node("/root/Run") else 0
	var max_mk_for_sector: int = mini(MAX_MK, 3 + 3 * bosses_killed)

	# Weapons: WEAPONS_COLUMN_COUNT cards. Slot weighted 50/25/25 via
	# WEAPON_SLOT_WEIGHTS; mark via the triangular roll capped at sector+3.
	# Task #6a: Dedupe within the offer roll itself (no repeating items).
	# Task #6b: Own-better filter — don't roll an item the player owns unless
	#   it's at least +1 Mark higher than what they own. Bounded reroll so we
	#   don't loop forever if the catalog can't fill 5 unique slots at the cap.
	_weapon_offers.clear()
	var seen: Dictionary = {}
	# Sector Conditions — Market Scarcity/Surplus shift the stock count (econ.stock_delta). Via OutpostEcon SSOT.
	var stock_count: int = OutpostEcon.stock_count(get_node_or_null("/root/Run"), WEAPONS_COLUMN_COUNT)
	for i in stock_count:
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
				var run := get_node("/root/Run")
				# Owned = active OR in the hold (single-active model). Bump the
				# offer +1 Mk so re-offering a stowed cannon doesn't duplicate it.
				var owned_mk: int = -1
				if run.has_method("owned_cannon_mark"):
					owned_mk = int(run.owned_cannon_mark(part_name))
				if owned_mk >= 0:
					if owned_mk >= max_mk_for_sector or owned_mk >= MAX_MK:
						# Cap reached — try a different cannon next attempt.
						continue
					picked_mk = owned_mk + 1
					if "mark" in part:
						part.mark = picked_mk
			# Dedupe by ITEM NAME alone (Roman 2026-06-10: "each item generated should be
			# different") — the old slot:mk:name key let the same weapon appear at several
			# marks in one shop (e.g. three Auto Lasers at Mk 3/2/1).
			var key: String = part_name
			if seen.has(key):
				continue
			# Task #6b: Own-better filter — reject if owned at same or higher mark.
			if not _should_roll_weapon(slot, part_name, picked_mk):
				continue
			seen[key] = true
			picked = part
			break
		if picked == null:
			continue
		var cost: int = _part_shop_cost(picked, picked_mk)
		# Sector Conditions — Galactic Tariffs/Buyer's Market scale the offer price at
		# ROLL time so the STORED cost is both what's displayed and what's spent. Applies
		# to every slot type (all offers price via this one site). Via OutpostEcon SSOT.
		cost = OutpostEcon.offer_price(get_node_or_null("/root/Run"), cost)
		_weapon_offers.append({"part": picked, "cost": cost, "sold": false})


# Offer price for a part at a Mk: the flat curve (116 + 70/Mk) unless the part carries
# its own shop_base_cost / shop_cost_per_mk overrides (the shield cores — a core IS the
# shield, worth several Reinforced Hull Mks; part.gd 2026-07-11).
func _part_shop_cost(part, mk: int) -> int:
	var base: int = CANNON_BASE_COST
	var per_mk: int = CANNON_COST_PER_MK
	if part != null:
		if "shop_base_cost" in part and int(part.shop_base_cost) > 0:
			base = int(part.shop_base_cost)
		if "shop_cost_per_mk" in part and int(part.shop_cost_per_mk) > 0:
			per_mk = int(part.shop_cost_per_mk)
	return base + (maxi(1, mk) - 1) * per_mk


# Triangular mark roll — average of two dice peaks at the midpoint.
func _roll_weighted_mark(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if hi <= lo:
		return clampi(lo, 1, MAX_MK)
	var a: int = rng.randi_range(lo, hi)
	var b: int = rng.randi_range(lo, hi)
	var mk: int = int(round(float(a + b) * 0.5))
	# Sector Conditions — Shoddy Imports/Quality Goods shift the rolled Mk (econ.mk_bias),
	# clamped to [1, cap]; the triangular distribution is otherwise intact. Via OutpostEcon SSOT.
	return OutpostEcon.bias_mark(get_node_or_null("/root/Run"), mk, hi)


# Count of row-bosses already killed in the current sector. Drives the
# outpost Mk-cap floor bump — clearing a row boss bumps the cap for the
# rest of this sector's outposts. Walks the sector_map_cache rows since
# that's the single source of truth for boss completion.
func _bosses_killed_in_sector() -> int:
	if not has_node("/root/Run"):
		return 0
	var run := get_node("/root/Run")
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
	var run := get_node("/root/Run")
	if "sectors_cleared" in run:
		return int(run.sectors_cleared) + 1
	return 1


# ---- Purchase handlers ----------------------------------------------------


func _on_buy_weapon(offer: Dictionary, btn: Button) -> void:
	if offer.get("sold", false):
		return
	if not has_node("/root/Run"):
		return
	var run := get_node("/root/Run")
	var cost: int = int(offer["cost"])
	if int(run.bounty) < cost:
		return
	run.spend_bounty(cost)
	_apply_part_to_player(offer["part"])
	# Purchased → remove the offer from the SHOP bucket entirely (Roman 2026-06-15), not gray it
	# out. _weapon_offers is shared by reference with Run.outpost_weapon_offers, so this persists.
	_weapon_offers.erase(offer)
	OutpostSfx.play("equip")
	_render_weapon_offers()
	_render_loadout_column()
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
# Buy-equip path (Roman 2026-06-15): only auto-equip into an EMPTY target slot. If the slot is
# already occupied (or the module bay is full), the bought part goes to cargo (stocks) so the
# player decides when to swap it in — no silent displacement on purchase.
func _apply_part_to_player(part) -> void:
	if part == null or not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var slot: int = int(part.slot_type) if "slot_type" in part else -1
	if slot == SlotTypes.SlotType.MODULE:
		if not run.add_module(part):     # bay full → stocks
			run.inventory.append(part)
		return
	if _buy_slot_occupied(run, part, slot):
		run.inventory.append(part)       # occupied → stocks; player manages the swap
	else:
		run.equip_part(part)             # empty slot → equip directly


# Is the target slot for a freshly-bought part already filled? CANNON uses the two-slot model:
# an infinite cannon targets the permanent blaster slot (always filled); a metered one targets
# the optional primary slot.
func _buy_slot_occupied(run, part, slot: int) -> bool:
	if slot == SlotTypes.SlotType.CANNON:
		var infinite: bool = part.has_method("ammo_at_mark") and int(part.ammo_at_mark(int(part.mark))) < 0
		if infinite:
			return run.cannon_pool.size() > 0
		return run.get_primary_cannon() != null
	return run.loadout_snapshot.get(slot, null) != null


func _hull_repair_cost() -> int:
	var base: int = HULL_REPAIR_COST
	var run = get_node_or_null("/root/Run")
	if run != null:
		# Reinforced Hull Mk.9 perk — read off the module bay (run.hull_mk is retired,
		# always 0; the old check here left the discount dead. Audit 2026-07-11.)
		var disc: float = float(run.hull_repair_discount()) if run.has_method("hull_repair_discount") else 0.0
		if disc > 0.0:
			base = int(round(float(base) * (1.0 - disc)))
	# Sector Conditions — Easy/Costly Repairs scale the bounty side (composes with the
	# Mk-9 discount already folded into `base`); Cheap Repairs zeroes it. Via OutpostEcon SSOT.
	return int(OutpostEcon.repair_costs(run, base)["bounty"])


# Material cost of a hull repair. Baseline repairs cost REPAIR_BASE_MATERIALS (design
# §8, Roman 2026-07-11); Complex/Cheap Repairs add a flat material delta on top
# (econ.repair_mat_delta), and Easy Repairs' no-mats flag strips it to zero.
func _hull_repair_mats() -> int:
	# Mats side is base_bounty-independent, so any base works here. Via OutpostEcon SSOT.
	return int(OutpostEcon.repair_costs(get_node_or_null("/root/Run"), HULL_REPAIR_COST)["mats"])


func _on_repair(btn: Button) -> void:
	var run = get_node_or_null("/root/Run")
	if run == null:
		return
	if int(run.max_hull) <= 0:
		return
	if int(run.current_hull) >= int(run.max_hull):
		return
	if int(run.repair_charges) <= 0:
		return  # outpost out of repair charges (refresh at next boss)
	var cost: int = _hull_repair_cost()
	var mat_cost: int = _hull_repair_mats()
	if int(run.bounty) < cost:
		return
	if mat_cost > 0 and int(run.materials) < mat_cost:
		return
	run.spend_bounty(cost)
	if mat_cost > 0:
		run.spend_materials(mat_cost)
	run.repair_charges -= 1
	run.current_hull = clampi(int(run.current_hull) + 1, 0, int(run.max_hull))
	OutpostSfx.play("repair")
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
	var run := get_node("/root/Run")
	var cannon = run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
	if cannon == null:
		return 0
	if "base_ammo" in cannon:
		return int(cannon.base_ammo)
	return 0


# Sector Conditions — Costly/Cheap Restock scales every flat restock cost
# (econ.restock_cost_mult). One helper so display + spend can't drift.
func _restock_cost(base: int) -> int:
	return OutpostEcon.restock_cost(get_node_or_null("/root/Run"), base)


# Per-round ammo cost with the restock mult folded in — keeps the partial-refill
# math (ceil/floor over a per-round rate) structurally intact while scaling the
# TOTAL. Used by both _ammo_refill_cost and _ammo_refill_partial so display + spend
# stay consistent (a flat _restock_cost wrapper's maxi(1) floor would corrupt the
# zero-missing / affordable-rounds math, hence the per-round approach here).
func _restock_per_round() -> float:
	return OutpostEcon.restock_per_round(get_node_or_null("/root/Run"), AMMO_COST_PER_ROUND)


func _ammo_refill_cost(missing: int) -> int:
	if missing <= 0:
		return 0
	return int(ceil(float(missing) * _restock_per_round()))


# Returns [refilled_rounds, cost_paid] for the affordability of `bounty`
# against a top-up of `missing` rounds. Caps refilled at `missing`.
func _ammo_refill_partial(bounty: int, missing: int) -> Array:
	if missing <= 0 or bounty <= 0:
		return [0, 0]
	var per_round: float = _restock_per_round()
	var full_cost: int = _ammo_refill_cost(missing)
	if bounty >= full_cost:
		return [missing, full_cost]
	# Partial — floor(bounty / per_round), capped at missing.
	var rounds: int = int(floor(float(bounty) / per_round))
	if rounds <= 0:
		return [0, 0]
	if rounds > missing:
		rounds = missing
	var cost: int = int(ceil(float(rounds) * per_round))
	return [rounds, cost]


func _on_primary_ammo_refill(btn: Button) -> void:
	# Weapons Phase 1: flat-cost refill on the ACTIVE non-blaster cannon's
	# magazine. Reads ammo_max from the cannon Part (cannon_pool entry) and
	# fills current_ammo to that cap. Blaster (idx 0) is greyed in
	# _apply_service_button_state so this handler only runs for replacements.
	if not has_node("/root/Run"):
		return
	var run := get_node("/root/Run")
	# Two-slot model: refill targets the equipped PRIMARY (the gun with ammo),
	# regardless of which weapon is currently firing.
	var active = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
	if active == null or not ("current_ammo" in active) or not ("ammo_max" in active):
		return
	if "no_outpost_refill" in active and bool(active.no_outpost_refill):
		return
	var cap: int = int(active.ammo_max)
	if cap <= 0:
		return
	if int(active.current_ammo) >= cap:
		return
	if int(run.ammo_restock_charges) <= 0:
		return  # outpost out of ammo restocks (refresh at next boss)
	var cost: int = PRIMARY_REFILL_COST
	if "refill_cost_override" in active and int(active.refill_cost_override) >= 0:
		cost = int(active.refill_cost_override)
	cost = _restock_cost(cost)  # Sector Conditions restock mult
	if int(run.bounty) < cost:
		return
	run.spend_bounty(cost)
	run.ammo_restock_charges -= 1
	active.current_ammo = cap
	# Mirror to Run.ammo + player.ammo so HUD updates immediately on return.
	run.ammo = cap
	OutpostSfx.play("repair")
	_show_toast(Strings.TOAST_PRIMARY_REFILLED)
	_refresh_status_panel()


func _on_secondary_ammo_refill(btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run := get_node("/root/Run")
	if int(run.secondary_ammo) < 0 or int(run.secondary_ammo_max) <= 0:
		return
	var missing: int = int(run.secondary_ammo_max) - int(run.secondary_ammo)
	if missing <= 0:
		return
	if int(run.ammo_restock_charges) <= 0:
		return  # outpost out of ammo restocks (refresh at next boss)
	var result: Array = _ammo_refill_partial(int(run.bounty), missing)
	var rounds: int = int(result[0])
	var cost: int = int(result[1])
	if rounds <= 0:
		return
	run.spend_bounty(cost)
	run.ammo_restock_charges -= 1
	run.secondary_ammo = clampi(int(run.secondary_ammo) + rounds, 0, int(run.secondary_ammo_max))
	OutpostSfx.play("repair")
	_show_toast(Strings.TOAST_SECONDARY_REFILLED % [rounds, cost])
	_refresh_status_panel()


func _on_super_refill(btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run := get_node("/root/Run")
	var super_cost: int = _restock_cost(SUPER_REFILL_COST)  # Sector Conditions restock mult
	if int(run.bounty) < super_cost:
		return
	if not ("super_charges" in run) or not ("max_super_charges" in run):
		return
	if int(run.max_super_charges) <= 0:
		return
	if int(run.super_charges) >= int(run.max_super_charges):
		return
	run.spend_bounty(super_cost)
	run.super_charges = clampi(int(run.super_charges) + 1, 0, int(run.max_super_charges))
	OutpostSfx.play("repair")
	_refresh_status_panel()


func _on_leave() -> void:
	# Outpost is a persistent hub (reached from the sector-map button), NOT a POI —
	# leaving it must NOT mark any node completed (it would wrongly clear whatever
	# node_id the last combat/POI left behind). Just return to the map.
	# Drop the HD scope only once the fade-to-black FULLY covers the screen
	# (via the on_covered callback), NOT before the fade. Freeing it early
	# restored content_scale_size to 480×270 while the HD-laid-out outpost
	# was still visible, so the fade revealed a 4×-scaled blow-up of the
	# upper-left corner for ~0.45s (Roman: "blown-up view of the upper-left
	# corner before transitioning"). Freeing it while black keeps both
	# constraints: invisible during fade, gone before the destination _ready.
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE, _drop_hd_scope)


func _drop_hd_scope() -> void:
	HdScreen.drop(_hd_scope)
	_hd_scope = null


# ---- Status panel refresh -------------------------------------------------

# Poll-based refresh: no Player exists in a meta scene, so the live
# player-side signals (hull_changed, secondary_ammo_changed, etc.) don't
# fire here. Every purchase handler calls _refresh_status_panel() at the
# end. Run.bounty_changed is the one signal we DO get for free.
func _refresh_status_panel() -> void:
	if not has_node("/root/Run"):
		return
	var run := get_node("/root/Run")

	if _hull_value_lbl:
		if int(run.max_hull) > 0:
			_hull_value_lbl.text = "%d / %d" % [int(run.current_hull), int(run.max_hull)]
		else:
			_hull_value_lbl.text = "—"
	if _bounty_value_lbl:
		_bounty_value_lbl.text = "%d" % int(run.bounty)
	if _materials_value_lbl:
		_materials_value_lbl.text = "%d" % int(run.materials)
	if _modifiers_lbl:
		_modifiers_lbl.text = _format_sector_modifiers(run)

	_refresh_services()
	_refresh_card_affordability()
	_render_loadout_column()
	_render_modules()
	_update_portrait_damage()


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


func _find_buy_button(card: Node) -> Button:
	for child in card.get_children():
		if child is Button and (String(child.text).begins_with("Buy") or String(child.text).begins_with("Swap")):
			return child
		var nested := _find_buy_button(child)
		if nested:
			return nested
	return null


func _refresh_services() -> void:
	# Service buttons now live in the SERVICES pane of the tab switcher.
	if _services_content == null:
		return
	for child in _services_content.get_children():
		if child is Button and child.has_meta("kind"):
			_apply_service_button_state(child)


# Per-kind enable/disable + label update. Centralizes the rules so we
# don't drift between _build_services() and the per-purchase handlers.
# Only "repair" is ever built (via _make_service_button in _build_services_content).
# Ammo/super restock moved onto the individual part cards — see the per-card wrappers
# _on_restock_primary/_secondary/_super wired from _cannon_buttons/_slot_buttons — so
# the old primary_ammo/secondary_ammo/super arms here were unreachable and were removed.
func _apply_service_button_state(btn: Button) -> void:
	var kind: String = String(btn.get_meta("kind"))
	var base_label: String = String(btn.get_meta("base_label"))
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
			if int(run.repair_charges) <= 0:
				btn.disabled = true
				btn.text = "%s  %s" % [base_label, Strings.SERVICE_SOLD_OUT]
				return
			var repair_cost: int = _hull_repair_cost()
			var repair_mats: int = _hull_repair_mats()
			var can_afford_repair: bool = _run_bounty() >= repair_cost and (repair_mats <= 0 or int(run.materials) >= repair_mats)
			btn.disabled = not can_afford_repair
			if repair_mats > 0:
				btn.text = "%s  (%d +%dm) ·%d left" % [base_label, repair_cost, repair_mats, int(run.repair_charges)]
			else:
				btn.text = "%s  (%d) ·%d left" % [base_label, repair_cost, int(run.repair_charges)]


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

func _run_bounty() -> int:
	if not has_node("/root/Run"):
		return 0
	return int(get_node("/root/Run").bounty)


func _slot_short_name(slot: int) -> String:
	match slot:
		SlotTypes.SlotType.CANNON: return Strings.SLOT_NAME_PRIMARY
		SlotTypes.SlotType.HARDPOINT_WING: return Strings.SLOT_NAME_SECONDARY
		SlotTypes.SlotType.DEVICE_BAY_1: return Strings.SLOT_NAME_SUPER
		SlotTypes.SlotType.SHIFT_MODE: return Strings.SLOT_NAME_MODE
		SlotTypes.SlotType.SHIELD: return Strings.SLOT_NAME_SHIELD
		SlotTypes.SlotType.ENGINE: return Strings.SLOT_NAME_ENGINE
		SlotTypes.SlotType.TAIL: return Strings.SLOT_NAME_TAIL
		SlotTypes.SlotType.WING_LEFT: return Strings.SLOT_NAME_WING_L
		SlotTypes.SlotType.WING_RIGHT: return Strings.SLOT_NAME_WING_R
		SlotTypes.SlotType.MODULE: return "Module"
	return Strings.SLOT_NAME_PART


func _slot_color(slot: int) -> Color:
	match slot:
		SlotTypes.SlotType.CANNON: return Color(1.0, 0.78, 0.45)
		SlotTypes.SlotType.HARDPOINT_WING: return Color(0.55, 0.85, 1.0)
		SlotTypes.SlotType.DEVICE_BAY_1: return Color(1.0, 0.55, 0.95)
		SlotTypes.SlotType.SHIFT_MODE: return Color(0.7, 0.55, 1.0)
		SlotTypes.SlotType.MODULE: return Color(0.55, 0.95, 0.75)
	return Color(0.75, 0.80, 0.85)


# The active sector-wide modifiers, as a player-facing line for the status bar.
# Reads the sector theme pool (sector_map_cache.sector_modifiers) — the whole-sector
# conditions, not the per-combat list. (#6, Roman 2026-06-08.)
func _format_sector_modifiers(run) -> String:
	# New Conditions system takes precedence when the run carries active Conditions;
	# append a Threat/payout suffix (payout terms omitted for a net-boon run).
	if "active_conditions" in run and not run.active_conditions.is_empty():
		var cond_labels: Array[String] = []
		for id in run.active_conditions:
			cond_labels.append(Conditions.label(String(id)))
		var line := Strings.SECTOR_MODIFIERS_LABEL % "   ·   ".join(cond_labels)
		# Player-facing rename Threat → Difficulty; payout coupling cut 2026-07-09 (no % suffix).
		line += "   —   Difficulty %+d" % run.condition_net_threat()
		return line
	# Legacy kill-switched modifier cache path (unchanged).
	var mods: Array = []
	if "sector_map_cache" in run and run.sector_map_cache is Dictionary:
		mods = run.sector_map_cache.get("sector_modifiers", [])
	if mods.is_empty():
		return Strings.SECTOR_MODIFIERS_NONE
	var labels: Array[String] = []
	for k in mods:
		var key := String(k)
		labels.append(String(Strings.MODIFIER_LABELS.get(key, key.capitalize())))
	return Strings.SECTOR_MODIFIERS_LABEL % "   ·   ".join(labels)


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
	# Smooth HD menu face — without this the label falls back to the project
	# theme's crisp (AA-off) default, which renders jagged at HD 1:1.
	lbl.add_theme_font_override("font", UiTheme.menu_font())
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))


# ---- Task #1, #3: Type label mapping (Blaster vs Primary Weapon) --------

# Determines if a cannon part is the permanent Energy Blaster.
# The Blaster is always Run.cannon_pool[0] and has display_name "Energy Blaster".
func _is_energy_blaster(part) -> bool:
	if part == null:
		return false
	return String(part.display_name) == "Energy Blaster"


# Maps slot_type to a player-facing type name (task #3).
# Primary cannons split into "Blaster" (the permanent one) vs "Primary Weapon" (replaceable).
func _type_name_for_part(part, slot: int) -> String:
	if slot == SlotTypes.SlotType.CANNON:
		if _is_energy_blaster(part):
			return Strings.TYPE_NAME_BLASTER
		return Strings.TYPE_NAME_PRIMARY_WEAPON
	match slot:
		SlotTypes.SlotType.HARDPOINT_WING:
			return Strings.TYPE_NAME_SECONDARY_WEAPON
		SlotTypes.SlotType.DEVICE_BAY_1:
			return Strings.TYPE_NAME_SUPER
		SlotTypes.SlotType.SHIFT_MODE:
			return Strings.TYPE_NAME_MODE
		SlotTypes.SlotType.MODULE:
			return "Module"
		_:
			return Strings.SLOT_NAME_PART
	return Strings.SLOT_NAME_PART


# Task #4: Ensure only one of each distinct item is equipped.
# Runs on outpost open. Scans loadout_snapshot + cannon_pool for duplicates;
# keeps the higher-mark copy equipped, moves excess to weapon_storage.
static func _ensure_no_duplicate_equipped(run) -> void:
	if not run or not ("loadout_snapshot" in run):
		return

	var loadout = run.loadout_snapshot
	var to_displace: Array = []  # parts actually REMOVED from their equipped slot/pool

	# --- Non-CANNON slots --- (each slot holds one part; a dup = same item name across two slots).
	# Keep the higher-mark copy, ERASE the lower from its slot.
	var seen: Dictionary = {}  # display_name -> {slot, mark}
	for slot in SlotTypes.ALL_SLOTS:
		if slot == SlotTypes.SlotType.CANNON:
			continue
		var part = loadout.get(slot, null)
		if part == null:
			continue
		var pname: String = String(part.display_name)
		var mark: int = int(part.mark) if "mark" in part else 1
		if seen.has(pname):
			var prev = seen[pname]
			if mark < int(prev["mark"]):
				# Current is the lower-mark dup — remove it from its slot.
				loadout.erase(slot)
				to_displace.append(part)
			else:
				# Current is higher — remove the previous, keep current.
				var prev_part = loadout.get(prev["slot"], null)
				loadout.erase(prev["slot"])
				if prev_part != null:
					to_displace.append(prev_part)
				seen[pname] = {"slot": slot, "mark": mark}
		else:
			seen[pname] = {"slot": slot, "mark": mark}

	# --- CANNON pool --- [0] is the permanent Blaster (always kept). For each name keep the single
	# highest-mark entry; REBUILD the pool without the dups, and remap active_cannon_idx.
	if "cannon_pool" in run and run.cannon_pool is Array:
		var pool: Array = run.cannon_pool
		var keep_idx_for_name: Dictionary = {}  # name -> index to keep
		for i in range(pool.size()):
			var c = pool[i]
			if c == null:
				continue
			var cname: String = String(c.display_name)
			var cmk: int = int(c.mark) if "mark" in c else 1
			if i == 0:
				keep_idx_for_name[cname] = 0   # blaster slot always wins
			elif not keep_idx_for_name.has(cname):
				keep_idx_for_name[cname] = i
			else:
				var ki: int = int(keep_idx_for_name[cname])
				if ki != 0:  # never replace the kept-blaster choice
					var kmk: int = int(pool[ki].mark) if "mark" in pool[ki] else 1
					if cmk > kmk:
						keep_idx_for_name[cname] = i
		var keep_indices: Dictionary = {}
		for nm in keep_idx_for_name.keys():
			keep_indices[int(keep_idx_for_name[nm])] = true
		var active: int = int(run.active_cannon_idx) if "active_cannon_idx" in run else 0
		var new_pool: Array = []
		var new_active: int = 0
		for i in range(pool.size()):
			if keep_indices.has(i):
				if i == active:
					new_active = new_pool.size()
				new_pool.append(pool[i])
			elif pool[i] != null:
				to_displace.append(pool[i])  # removed dup
		run.cannon_pool = new_pool
		if "active_cannon_idx" in run:
			run.active_cannon_idx = clampi(new_active, 0, max(0, new_pool.size() - 1))

	# --- Move the removed dups to the hold (dedup the hold itself). ---
	if not ("weapon_storage" in run) or run.weapon_storage == null:
		run.weapon_storage = []
	for item in to_displace:
		if item != null and item not in run.weapon_storage:
			run.weapon_storage.append(item)


# Task #6b: Own-better filter — determine if a weapon offer is acceptable.
# Returns true if the player doesn't own this item, OR owns it but at a LOWER mark.
func _should_roll_weapon(slot: int, part_name: String, offered_mk: int) -> bool:
	if not has_node("/root/Run"):
		return true
	var run := get_node("/root/Run")

	# Modules live in the bay LIST (run.modules) + spare-module cargo (run.inventory), NOT
	# loadout_snapshot. A bought module APPENDS to the bay (add_module) rather than swapping,
	# so re-offering one already owned would just stack a duplicate — reject any owned module
	# regardless of mark (owned modules progress via the in-place Upgrade button, not by buying
	# a higher-Mk copy). This is the seam that keeps the always-owned Shield Core out of the
	# shop once you have it (Roman 2026-07-14).
	if slot == SlotTypes.SlotType.MODULE:
		if "modules" in run and run.modules is Array:
			for m in run.modules:
				if m != null and "display_name" in m and String(m.display_name) == part_name:
					return false
		if "inventory" in run and run.inventory is Array:
			for it in run.inventory:
				if it != null and "display_name" in it and String(it.display_name) == part_name:
					return false
		return true

	# Check loadout_snapshot for non-CANNON slots.
	if slot != SlotTypes.SlotType.CANNON:
		var equipped = run.loadout_snapshot.get(slot, null)
		if equipped != null and String(equipped.display_name) == part_name:
			var owned_mk: int = int(equipped.mark) if "mark" in equipped else 1
			if offered_mk <= owned_mk:
				return false  # Reject: player owns same or higher.
		# Check weapon_storage too.
		if "weapon_storage" in run:
			for stored in run.weapon_storage:
				if String(stored.display_name) == part_name:
					var stored_mk: int = int(stored.mark) if "mark" in stored else 1
					if offered_mk <= stored_mk:
						return false  # Reject: player owns (in storage) same or higher.
		return true

	# For CANNON, check cannon_pool AND weapon_storage — displaced/stowed cannons land in the
	# hold (the dup-equipped safeguard puts them there), and a cannon in the hold must block
	# same-or-lower-mark re-rolls just like any owned item (review fix 2026-06-10).
	if "cannon_pool" in run:
		for c in run.cannon_pool:
			if c != null and String(c.display_name) == part_name:
				var owned_mk: int = int(c.mark) if "mark" in c else 1
				if offered_mk <= owned_mk:
					return false  # Reject: player owns same or higher.
	if "weapon_storage" in run:
		for stored in run.weapon_storage:
			if stored != null and String(stored.display_name) == part_name:
				var stored_mk: int = int(stored.mark) if "mark" in stored else 1
				if offered_mk <= stored_mk:
					return false  # Reject: player owns (in hold) same or higher.

	return true


# Task #7: Compute dynamic stats for a part at a given mark.
# Mirrors hangar.gd _stats_for_part but returns a compact display string.
func _stats_display_for_part(part, mk: int) -> String:
	if part == null:
		return ""
	mk = clampi(mk, 1, 9)
	# Modules + mode parts: no dmg/rof/ammo fields — their progression line is
	# bonus_description (was blank in this popup before 2026-07-11). Weapons keep the
	# numeric path below (base_damage present).
	if part.has_method("bonus_description") and not ("base_damage" in part):
		return String(part.bonus_description(mk))
	var dmg: int = 0
	if "base_damage" in part:
		var base: int = int(part.base_damage)
		var per_mk: int = int(part.dmg_per_mark) if "dmg_per_mark" in part else 0
		dmg = base + per_mk * max(0, mk - 1)
	var rof: float = 0.0
	if "base_cooldown" in part:
		var cooldown: float = float(part.base_cooldown)
		rof = (1.0 / cooldown) if cooldown > 0.0 else 0.0
	var ammo: int = -1
	if part.has_method("_base_ammo"):
		ammo = int(part._base_ammo())

	# Format: "dmg N · rof N/s" or "dmg N · ammo N" depending on what's available.
	var parts: Array[String] = []
	if dmg > 0:
		parts.append("dmg %d" % dmg)
	if rof > 0.0:
		parts.append("%.1f/s" % rof)
	elif ammo >= 0:
		parts.append("ammo %d" % ammo)
	return " · ".join(parts) if not parts.is_empty() else ""
