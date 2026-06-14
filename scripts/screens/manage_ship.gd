extends Control

# Manage Ship — full-screen HD ship-management screen, styled to match the shop
# (outpost). Equip + sell spares (no BUYING — that's the outpost). Shows:
#   - Status bar: hull / shield / bounty / super (+ ammo) + equipped one-liner.
#   - LOADOUT column: equipped primary / secondary / super (name + description).
#   - OWNED KIT column: carried parts (weapon_storage + inventory) — Equip + Sell
#     (10% resale, mirrors the outpost; equipped/permanent-blaster aren't sellable).
#   - UPGRADES column: owned Mk levels (read-only).
# Reached from the sector map's Manage Ship button. Return target is read from
# Run meta "manage_ship_return" (falls back to the live sector map).

const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const PartTier = preload("res://scripts/parts/part_tier.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

# ---- HD layout (1920×1080) — mirrors outpost.gd ---------------------------
const VIEW_W := 1920
const VIEW_H := 1080
const STATUS_H := 120
const MARGIN := 24
const COL_GAP := 18
const CARD_H := 150
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)
const PANEL_BG_LOADOUT := Color(0.05, 0.08, 0.14, 0.65)
const PANEL_BG_OWNED := Color(0.10, 0.05, 0.12, 0.65)
const PANEL_BG_UPGRADE := Color(0.05, 0.10, 0.08, 0.65)

# Resale = 10% of the cannon-buy formula — mirrors outpost._sell_value_for /
# signal_event._sell_price so no venue is the better place to dump spare parts.
const CANNON_BASE_COST := 116
const CANNON_COST_PER_MK := 70

const LOADOUT_SLOTS := [
	{"slot": SlotTypes.SlotType.CANNON, "label": "PRIMARY", "color": Color(1.0, 0.78, 0.45)},
	{"slot": SlotTypes.SlotType.HARDPOINT_WING, "label": "SECONDARY", "color": Color(0.55, 0.85, 1.0)},
	{"slot": SlotTypes.SlotType.DEVICE_BAY_1, "label": "SUPER", "color": Color(1.0, 0.55, 0.95)},
	{"slot": SlotTypes.SlotType.SHIFT_MODE, "label": "SHIFT MODE", "color": Color(0.55, 1.0, 0.70)},
]
# All upgrades retired 2026-06-13 — they're bay MODULES now (Reinforced Hull, Thrusters,
# Shield Core capacity, etc.), shown in the MODULE BAY row of the loadout column. The
# old int fields stay in run_state for save compat but are no longer displayed/bought.
const UPGRADE_KEYS := []

var _loadout_box: VBoxContainer = null
var _owned_box: VBoxContainer = null
var _upgrades_box: VBoxContainer = null
var _hull_lbl: Label = null
var _shield_lbl: Label = null
var _bounty_lbl: Label = null
var _super_lbl: Label = null
var _loadout_line: Label = null
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("outpost")
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "ManageShipUI"
	add_child(ui_layer)

	_build_status_panel(ui_layer)
	_build_columns(ui_layer)
	_render_all()
	UiTheme.assert_inside_viewport.call_deferred(self)


func _build_status_panel(parent: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(MARGIN, MARGIN)
	panel.size = Vector2(VIEW_W - MARGIN * 2, STATUS_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	parent.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 32)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(h)

	var title_v := VBoxContainer.new()
	title_v.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = "MANAGE SHIP"
	_slabel(title, UiTheme.FONT_SIZE_TITLE, Color(0.95, 0.92, 0.78))
	title_v.add_child(title)
	_loadout_line = Label.new()
	_slabel(_loadout_line, UiTheme.FONT_SIZE_CAPTION, Color(0.62, 0.72, 0.82))
	title_v.add_child(_loadout_line)
	h.add_child(title_v)

	_hull_lbl = _make_stat_block(h, "HULL")
	_shield_lbl = _make_stat_block(h, "SHIELD")
	_super_lbl = _make_stat_block(h, "SUPER")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_bounty_lbl = _make_stat_block(h, "BOUNTY", Color(0.95, 0.86, 0.45))

	# Back button (top-right of the status bar).
	var back := UiTheme.make_button("‹ Done")
	back.custom_minimum_size = Vector2(180, 60)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_on_back)
	h.add_child(back)


func _make_stat_block(parent: BoxContainer, caption_text: String, accent: Color = Color(0.78, 0.92, 1.0)) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var caption := Label.new()
	caption.text = caption_text
	_slabel(caption, UiTheme.FONT_SIZE_CAPTION, Color(0.55, 0.65, 0.75))
	v.add_child(caption)
	var value := Label.new()
	value.text = "—"
	_slabel(value, UiTheme.FONT_SIZE_BODY, accent)
	v.add_child(value)
	parent.add_child(v)
	return value


func _build_columns(parent: CanvasLayer) -> void:
	var top: float = STATUS_H + MARGIN * 2
	var height: float = VIEW_H - top - MARGIN
	var col_w: float = (VIEW_W - MARGIN * 2 - COL_GAP * 2) / 3.0
	var x: float = MARGIN
	_loadout_box = _build_column(parent, "EQUIPPED LOADOUT", PANEL_BG_LOADOUT, x, top, col_w, height)
	x += col_w + COL_GAP
	_owned_box = _build_column(parent, "OWNED KIT", PANEL_BG_OWNED, x, top, col_w, height)
	x += col_w + COL_GAP
	_upgrades_box = _build_column(parent, "UPGRADES", PANEL_BG_UPGRADE, x, top, col_w, height)


func _build_column(parent: CanvasLayer, title_text: String, bg: Color, x: float, y: float, w: float, h: float) -> VBoxContainer:
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
	_slabel(header, UiTheme.FONT_SIZE_HEADER, Color(0.85, 0.90, 1.0))
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


# ---- Render ---------------------------------------------------------------

func _render_all() -> void:
	_refresh_status()
	_render_loadout()
	_render_owned()
	_render_upgrades()


func _refresh_status() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if _hull_lbl: _hull_lbl.text = "%d / %d" % [int(run.current_hull), int(run.max_hull)]
	if _shield_lbl: _shield_lbl.text = "%d / %d" % [int(run.current_shield), int(run.max_shield)]
	if _super_lbl: _super_lbl.text = "%d / %d" % [int(run.super_charges), int(run.max_super_charges)]
	if _bounty_lbl: _bounty_lbl.text = "%d" % int(run.bounty)
	if _loadout_line:
		var bits: Array = []
		for entry in LOADOUT_SLOTS:
			bits.append("%s: %s" % [entry["label"], _part_name(run.loadout_snapshot.get(int(entry["slot"]), null))])
		_loadout_line.text = "   ".join(bits)


func _render_loadout() -> void:
	for c in _loadout_box.get_children():
		c.queue_free()
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# Two-slot model (2026-06-11): BLASTER (slot 0, unlimited fallback) + PRIMARY
	# (slot 1, optional ammo gun). The active (firing) one gets an ACTIVE badge; the
	# other a "Set Active" button (the Q swap). Owned spares live in the hold below.
	var blaster = run.cannon_pool[0] if run.cannon_pool.size() > 0 else run.loadout_snapshot.get(int(SlotTypes.SlotType.CANNON), null)
	var primary = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
	var active_idx: int = int(run.active_cannon_idx)
	var slot_color: Color = LOADOUT_SLOTS[0]["color"]
	var active_color := Color(0.55, 1.0, 0.50)
	if active_idx == 0:
		_loadout_box.add_child(_make_card("BLASTER", active_color, blaster, "ACTIVE", Callable(), true))
	else:
		_loadout_box.add_child(_make_card("BLASTER", slot_color, blaster, "Set Active", _on_set_active.bind(0)))
	if primary != null:
		if active_idx == 1:
			_loadout_box.add_child(_make_card("PRIMARY", active_color, primary, "ACTIVE", Callable(), true))
		else:
			_loadout_box.add_child(_make_card("PRIMARY", slot_color, primary, "Set Active", _on_set_active.bind(1)))
	else:
		_loadout_box.add_child(_make_card("PRIMARY", slot_color, null))
	# SECONDARY + SUPER + SHIFT_MODE are single slots.
	for entry in [LOADOUT_SLOTS[1], LOADOUT_SLOTS[2], LOADOUT_SLOTS[3]]:
		var part = run.loadout_snapshot.get(int(entry["slot"]), null)
		_loadout_box.add_child(_make_card(String(entry["label"]), entry["color"], part))
	# Passive Module bay (the LIST). Each equipped module gets a Remove button (→ cargo).
	# Drop the Shield Core to free a slot and fly shieldless (glass cannon).
	var mod_color := Color(0.55, 0.95, 0.75)
	var bay_hdr := Label.new()
	bay_hdr.text = "MODULE BAY  (%d / %d)" % [run.modules.size(), run.MODULE_BAY_SIZE]
	_slabel(bay_hdr, UiTheme.FONT_SIZE_CAPTION, mod_color)
	_loadout_box.add_child(bay_hdr)
	for i in range(run.modules.size()):
		_loadout_box.add_child(_make_card("MODULE", mod_color, run.modules[i], "Remove", _on_remove_module.bind(i)))


func _render_owned() -> void:
	for c in _owned_box.get_children():
		c.queue_free()
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var any := false
	for i in range(run.weapon_storage.size()):
		var ws_part = run.weapon_storage[i]
		_owned_box.add_child(_make_card(_slot_short(ws_part), Color(0.75, 0.82, 0.9), ws_part,
			"Equip", _on_equip.bind(i, "weapon_storage"), false,
			"Sell %d" % _sell_value_for(ws_part), _on_sell.bind(i, "weapon_storage")))
		any = true
	for i in range(run.inventory.size()):
		var inv_part = run.inventory[i]
		_owned_box.add_child(_make_card(_slot_short(inv_part), Color(0.75, 0.82, 0.9), inv_part,
			"Equip", _on_equip.bind(i, "inventory"), false,
			"Sell %d" % _sell_value_for(inv_part), _on_sell.bind(i, "inventory")))
		any = true
	if not any:
		var lbl := Label.new()
		lbl.text = "No carried equipment."
		_slabel(lbl, UiTheme.FONT_SIZE_BODY, Color(0.6, 0.66, 0.74))
		_owned_box.add_child(lbl)


func _render_upgrades() -> void:
	for c in _upgrades_box.get_children():
		c.queue_free()
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var any := false
	for u in UPGRADE_KEYS:
		var lvl: int = int(run.get(String(u["key"])))
		if lvl <= 0:
			continue
		any = true
		var tier: Dictionary = PartTier.tier_for_mk(lvl)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _card_style_tier(tier["color"]))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		row.add_child(v)
		var name_lbl := Label.new()
		name_lbl.text = "%s  Mk.%d" % [u["name"], lvl]
		_slabel(name_lbl, UiTheme.FONT_SIZE_BODY, Color(0.95, 0.95, 0.95))
		v.add_child(name_lbl)
		var tier_lbl := Label.new()
		tier_lbl.text = PartTier.tier_label(lvl)
		_slabel(tier_lbl, UiTheme.FONT_SIZE_CAPTION, tier["color"])
		v.add_child(tier_lbl)
		_upgrades_box.add_child(row)
	if not any:
		var lbl := Label.new()
		lbl.text = "No upgrades owned."
		_slabel(lbl, UiTheme.FONT_SIZE_BODY, Color(0.6, 0.66, 0.74))
		_upgrades_box.add_child(lbl)


# A card: slot pill (left) + name/tier/description (center) + optional right
# element. `right_text` empty → nothing; `right_is_badge` → a static label
# (e.g. "ACTIVE"); else a button wired to `right_cb` (e.g. "Equip"/"Set Active").
# `sell_text`/`sell_cb` add a SECOND right-side button (the Sell action on
# spare/owned rows) alongside the first.
func _make_card(pill_text: String, pill_color: Color, part, right_text: String = "", right_cb: Callable = Callable(), right_is_badge: bool = false, sell_text: String = "", sell_cb: Callable = Callable()) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	var mk: int = int(part.mark) if (part != null and "mark" in part) else 0
	var tier_color: Color = PartTier.tier_for_mk(mk)["color"] if mk > 0 else Color(0.35, 0.45, 0.60)
	card.add_theme_stylebox_override("panel", _card_style_tier(tier_color))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	var pill := Label.new()
	pill.text = pill_text
	pill.custom_minimum_size = Vector2(110, 0)
	pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slabel(pill, UiTheme.FONT_SIZE_CAPTION, pill_color)
	row.add_child(pill)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = _part_name(part)
	_slabel(name_lbl, UiTheme.FONT_SIZE_BODY, Color(0.95, 0.95, 0.95) if part != null else Color(0.55, 0.6, 0.7))
	v.add_child(name_lbl)
	if part != null and mk > 0:
		var tier_lbl := Label.new()
		tier_lbl.text = PartTier.tier_label(mk)
		_slabel(tier_lbl, UiTheme.FONT_SIZE_CAPTION, PartTier.tier_for_mk(mk)["color"])
		v.add_child(tier_lbl)
	var desc := _part_description(part)
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slabel(desc_lbl, UiTheme.FONT_SIZE_CAPTION, Color(0.72, 0.78, 0.85))
		v.add_child(desc_lbl)

	if right_text != "":
		if right_is_badge:
			var badge := Label.new()
			badge.text = right_text
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_slabel(badge, UiTheme.FONT_SIZE_CAPTION, Color(0.55, 1.0, 0.50))
			row.add_child(badge)
		elif right_cb.is_valid():
			var btn := UiTheme.make_button(right_text)
			btn.custom_minimum_size = Vector2(170, 56)
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.pressed.connect(right_cb)
			row.add_child(btn)

	if sell_text != "" and sell_cb.is_valid():
		var sbtn := UiTheme.make_button(sell_text)
		sbtn.custom_minimum_size = Vector2(150, 56)
		sbtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sbtn.pressed.connect(sell_cb)
		row.add_child(sbtn)

	return card


# ---- Actions --------------------------------------------------------------

func _on_equip(idx: int, source: String) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var arr: Array
	match source:
		"weapon_storage": arr = run.weapon_storage
		"inventory": arr = run.inventory
		_: return
	if idx < 0 or idx >= arr.size():
		return
	var picked = arr[idx]
	# Module bay parts go to the LIST (Run.modules), not the pegboard — and only if the
	# bay has room (else leave it in cargo so nothing is lost).
	if "slot_type" in picked and int(picked.slot_type) == int(SlotTypes.SlotType.MODULE):
		if run.add_module(picked):
			arr.remove_at(idx)
		_render_all()
		return
	arr.remove_at(idx)
	run.equip_part(picked)  # displaces same-slot part back into storage
	_render_all()


# Remove an equipped module from the bay back into cargo (inventory) — re-equip or
# sell it from OWNED KIT. Dropping the Shield Core leaves you shieldless next combat.
func _on_remove_module(idx: int) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var m = run.remove_module(idx)
	if m != null:
		run.inventory.append(m)
	_render_all()


# Resale value for a spare part — 10% of its cannon-buy cost (floor 5),
# identical to the outpost + signal-event rate so no venue is the better dump spot.
func _sell_value_for(part) -> int:
	var mk: int = int(part.mark) if (part != null and "mark" in part) else 1
	var buy_cost: int = CANNON_BASE_COST + (mk - 1) * CANNON_COST_PER_MK
	return max(5, int(0.1 * float(buy_cost)))


# Sell a spare part (weapon_storage / inventory only — never the equipped loadout;
# the permanent blaster lives on the active loadout and is unsellable). Credits
# bounty + destroys the part, mirroring outpost._on_sell_stored.
func _on_sell(idx: int, source: String) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var arr: Array
	match source:
		"weapon_storage": arr = run.weapon_storage
		"inventory": arr = run.inventory
		_: return
	if idx < 0 or idx >= arr.size():
		return
	var value: int = _sell_value_for(arr[idx])
	arr.remove_at(idx)
	run.bounty += value
	_render_all()


func _on_set_active(idx: int) -> void:
	if not has_node("/root/Run"):
		return
	get_node("/root/Run").set_active_cannon(idx)
	_render_all()


func _on_back() -> void:
	var target := SectorMapRoute.SECTOR_MAP_SCENE
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.has_meta("manage_ship_return"):
			target = String(run.get_meta("manage_ship_return"))
	SceneTransition.change_scene(get_tree(), target)


# ---- Helpers --------------------------------------------------------------

func _part_name(part) -> String:
	if part == null:
		return "—"
	var nm: String = String(part.get("display_name")) if "display_name" in part else "Part"
	var mk: int = int(part.get("mark")) if "mark" in part else 0
	return "Mk.%d %s" % [mk, nm] if mk > 0 else nm


func _part_description(part) -> String:
	if part != null and "description" in part:
		return String(part.get("description"))
	return ""


func _slot_short(part) -> String:
	if part == null:
		return "PART"
	# Cannon-slot weapons read as Blaster (infinite) vs Primary (metered) — the
	# two-slot model (2026-06-11), not the generic slot name.
	if int(part.slot_type) == int(SlotTypes.SlotType.CANNON):
		if part.has_method("ammo_at_mark"):
			var mk: int = int(part.mark) if "mark" in part else 1
			return "Blaster" if int(part.ammo_at_mark(mk)) < 0 else "Primary"
	return SlotTypes.slot_name(int(part.slot_type))


func _slabel(lbl: Label, size: int, color: Color) -> void:
	lbl.add_theme_font_override("font", UiTheme.menu_font())
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))


func _panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _card_style_tier(tier_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.85)
	sb.border_color = tier_color
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
		get_viewport().set_input_as_handled()
