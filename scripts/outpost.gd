extends Control

# Friendly Outpost — reworked 2026-05-17 per Roman:
#   - 3 random upgrades (Hull, Armor, Thrusters, Self Repair, Shield Cap,
#     Shield Recharge) priced by next-tier Mk, +1 per buy up to Mk 9.
#   - 3 random cannons at random Mk; buying swaps the new cannon in and
#     stores the old one in Run.weapon_storage.
#   - Ammo Refill (50% of max, costs 25, multiple times, MG only).
#   - Hull Repair (25% of max hull, costs 30, multiple times).
#   - Storage shelf — equip a stored cannon, or sell it for bounty.
#   - Leave to return to the sector map.

const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

# Upgrade catalog: each entry's price scales with the *next* Mk you'd
# unlock. Buying takes the run from Mk N → N+1; costs grow accordingly.
const UPGRADES := [
	{"key": "hull_mk",            "name": "Hull",             "desc": "+10 max hull per Mk."},
	{"key": "armor_mk",           "name": "Armor Plating",    "desc": "+5% hull DR / Mk; -2% speed / Mk."},
	{"key": "thrusters_mk",       "name": "Thrusters",        "desc": "+3% movement speed per Mk."},
	{"key": "self_repair_mk",     "name": "Self Repair",      "desc": "Heal 5 + 2/Mk hull at combat start."},
	{"key": "shield_cap_mk",      "name": "Shield Capacity",  "desc": "+1 shield charge per Mk."},
	{"key": "shield_recharge_mk", "name": "Shield Recharge",  "desc": "-2s shield recharge per Mk."},
]
# Roman, 2026-05-18: prices bumped ~15% for upgrades + weapons.
const UPGRADE_BASE_COST := 70
const UPGRADE_COST_PER_MK := 35
const MAX_MK := 9
const HULL_REPAIR_COST := 30
const HULL_REPAIR_PCT := 0.25
const AMMO_REFILL_COST := 25
const AMMO_REFILL_PCT := 0.5
const AMMO_FULL_VALUE := 1000
const CANNON_BASE_COST := 58
const CANNON_COST_PER_MK := 35
# Mark distribution: roll picks from sector_index + 3 max, with weighting
# that favors the middle of the available range and tapers at the high end.
const MK_HIGH_OFFSET := 3

var _upgrade_offers: Array = []   # [{key, name, desc, cost}]
var _cannon_offers: Array = []    # [{part, cost}]
var _bounty_label: Label = null
var _status_label: Label = null
var _upgrade_box: HBoxContainer = null
var _cannon_box: HBoxContainer = null
var _storage_box: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("outpost")
	_roll_offers()
	_build_ui()
	if has_node("/root/Run"):
		get_node("/root/Run").bounty_changed.connect(_update_bounty_label)


# ---- UI scaffold ----------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "FRIENDLY OUTPOST"
	title.position = Vector2(8, 4)
	UiTheme.style_label(title, UiTheme.LabelKind.HEADER)
	add_child(title)

	_bounty_label = Label.new()
	_bounty_label.position = Vector2(200, 4)
	_bounty_label.size = Vector2(116, 14)
	_bounty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_label(_bounty_label, UiTheme.LabelKind.BOUNTY)
	add_child(_bounty_label)
	_update_bounty_label(_run_bounty())
	# Roman, 2026-05-18: display the player's hull + ammo status so the
	# player can decide whether to repair / refill before leaving.
	_status_label = Label.new()
	_status_label.position = Vector2(108, 4)
	_status_label.size = Vector2(90, 14)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 9)
	_status_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95))
	_status_label.add_theme_constant_override("outline_size", 1)
	add_child(_status_label)
	_update_status_label()

	# 480×270 widescreen rework: 2-column layout. Left column (cards)
	# stacks Upgrades + Cannons at full original height; right column
	# (170 px wide) takes Services, Storage, and the Leave button. Frees
	# enough vertical room to fit comfortably in 270.
	#   LEFT (x=8, w=300):
	#     y=  4   title strip
	#     y= 20   "Upgrades" caption
	#     y= 30   3 upgrade cards   (h=98)  → ends 128
	#     y=132   "Cannons" caption
	#     y=142   3 cannon cards    (h=98)  → ends 240
	#   RIGHT (x=312, w=160):
	#     y= 20   "Services" caption
	#     y= 32   repair + ammo (vertical stack, 2× h=16)
	#     y= 70   "Weapon Storage" caption
	#     y= 82   storage scroll (h=140)
	#     y=232   "Leave" button (h=14)

	var upgrades_lbl := Label.new()
	upgrades_lbl.text = "Upgrades"
	upgrades_lbl.position = Vector2(8, 20)
	UiTheme.style_label(upgrades_lbl, UiTheme.LabelKind.CAPTION)
	add_child(upgrades_lbl)
	_upgrade_box = HBoxContainer.new()
	_upgrade_box.position = Vector2(8, 30)
	_upgrade_box.size = Vector2(300, 98)
	_upgrade_box.add_theme_constant_override("separation", 6)
	add_child(_upgrade_box)
	_render_upgrade_offers()

	var cannons_lbl := Label.new()
	cannons_lbl.text = "Cannons"
	cannons_lbl.position = Vector2(8, 132)
	UiTheme.style_label(cannons_lbl, UiTheme.LabelKind.CAPTION)
	add_child(cannons_lbl)
	_cannon_box = HBoxContainer.new()
	_cannon_box.position = Vector2(8, 142)
	_cannon_box.size = Vector2(300, 98)
	_cannon_box.add_theme_constant_override("separation", 6)
	add_child(_cannon_box)
	_render_cannon_offers()

	var services_lbl := Label.new()
	services_lbl.text = "Services"
	services_lbl.position = Vector2(312, 30)
	UiTheme.style_label(services_lbl, UiTheme.LabelKind.CAPTION)
	add_child(services_lbl)
	var services := VBoxContainer.new()
	services.position = Vector2(312, 42)
	services.size = Vector2(160, 36)
	services.add_theme_constant_override("separation", 4)
	add_child(services)
	var repair_btn := Button.new()
	repair_btn.text = "Repair +25%% (%d)" % HULL_REPAIR_COST
	repair_btn.custom_minimum_size = Vector2(160, 16)
	UiTheme.style_button(repair_btn)
	repair_btn.pressed.connect(_on_repair.bind(repair_btn))
	services.add_child(repair_btn)
	var ammo_btn := Button.new()
	ammo_btn.text = "Ammo +50%% (%d)" % AMMO_REFILL_COST
	ammo_btn.custom_minimum_size = Vector2(160, 16)
	UiTheme.style_button(ammo_btn)
	ammo_btn.pressed.connect(_on_ammo_refill.bind(ammo_btn))
	if _run_ammo() < 0:
		ammo_btn.disabled = true
		ammo_btn.text = "Ammo (no MG)"
	services.add_child(ammo_btn)

	var storage_lbl := Label.new()
	storage_lbl.text = "Weapon Storage"
	storage_lbl.position = Vector2(312, 84)
	UiTheme.style_label(storage_lbl, UiTheme.LabelKind.CAPTION)
	add_child(storage_lbl)
	var storage_scroll := ScrollContainer.new()
	storage_scroll.position = Vector2(312, 96)
	storage_scroll.size = Vector2(160, 130)
	add_child(storage_scroll)
	_storage_box = VBoxContainer.new()
	_storage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_box.add_theme_constant_override("separation", 6)
	storage_scroll.add_child(_storage_box)
	_render_storage()

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.position = Vector2(312, 234)
	leave_btn.size = Vector2(160, 16)
	UiTheme.style_button(leave_btn, true)
	leave_btn.pressed.connect(_on_leave)
	add_child(leave_btn)


# ---- Offer rolls ----------------------------------------------------------

func _roll_offers() -> void:
	var rng := RandomNumberGenerator.new()
	if has_node("/root/Run"):
		var r = get_node("/root/Run")
		rng.seed = r.run_seed + r.visited_nodes.size() * 17
	else:
		rng.randomize()
	# 3 distinct upgrades from UPGRADES table. Skip any already at Mk 9.
	# Roman, 2026-05-18: upgrades cap at the current sector + 3 marks
	# (so Sector 1 caps Mk.4, Sector 6 caps Mk.9). Distribution is
	# triangular — middle marks roll more often than the extremes.
	var sector_idx: int = _current_sector()
	var max_mk_for_sector: int = mini(MAX_MK, sector_idx + MK_HIGH_OFFSET)
	var pool: Array = []
	for u in UPGRADES:
		if _current_mk(u["key"]) < max_mk_for_sector:
			pool.append(u)
	pool.shuffle()
	_upgrade_offers.clear()
	for i in min(3, pool.size()):
		var u: Dictionary = pool[i]
		# Pick a TARGET mk from the available range with triangular weighting
		# (middle most likely, ends rarer). The player still buys the upgrade
		# at its current mk + 1 cost, but the OFFER's quality varies.
		var rolled_mk: int = _roll_weighted_mark(rng, _current_mk(u["key"]) + 1, max_mk_for_sector)
		var cost: int = UPGRADE_BASE_COST + (rolled_mk - 1) * UPGRADE_COST_PER_MK
		_upgrade_offers.append({
			"key": u["key"], "name": u["name"], "desc": u["desc"],
			"next_mk": rolled_mk, "cost": cost,
		})
	# 3 random cannons capped at sector + 3 marks, same triangular weighting.
	_cannon_offers.clear()
	for i in 3:
		var part = PartCatalog.roll_random_part(rng)
		var tries: int = 0
		while part and part.slot_type != SlotTypes.SlotType.CANNON and tries < 10:
			part = PartCatalog.roll_random_part(rng)
			tries += 1
		if part == null or part.slot_type != SlotTypes.SlotType.CANNON:
			continue
		# Override the mark with our triangular roll capped at sector + 3.
		var picked_mk: int = _roll_weighted_mark(rng, 1, max_mk_for_sector)
		part.mark = picked_mk
		var cost: int = CANNON_BASE_COST + (picked_mk - 1) * CANNON_COST_PER_MK
		_cannon_offers.append({"part": part, "cost": cost})


# Triangular-ish mark roll. lo..hi inclusive. Picks the average of 2 dice
# so the distribution peaks at the midpoint and tapers at the ends.
func _roll_weighted_mark(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if hi <= lo:
		return clampi(lo, 1, MAX_MK)
	var a: int = rng.randi_range(lo, hi)
	var b: int = rng.randi_range(lo, hi)
	return clampi(int(round(float(a + b) * 0.5)), lo, hi)


func _update_status_label() -> void:
	if _status_label == null:
		return
	var hull_s: String = "HULL ?/?"
	var ammo_s: String = ""
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "current_hull" in run and "max_hull" in run and int(run.max_hull) > 0:
			hull_s = "HULL %d/%d" % [int(run.current_hull), int(run.max_hull)]
		if "ammo" in run and int(run.ammo) >= 0:
			ammo_s = " AMMO %d" % int(run.ammo)
	_status_label.text = hull_s + ammo_s


func _current_sector() -> int:
	if not has_node("/root/Run"):
		return 1
	var run = get_node("/root/Run")
	if "sectors_cleared" in run:
		return int(run.sectors_cleared) + 1
	return 1


# ---- Render: upgrades + cannons + storage --------------------------------

func _render_upgrade_offers() -> void:
	for c in _upgrade_box.get_children():
		c.queue_free()
	for offer in _upgrade_offers:
		_upgrade_box.add_child(_make_upgrade_card(offer))
	if _upgrade_offers.is_empty():
		var lbl := Label.new()
		lbl.text = "All upgrades maxed."
		UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
		_upgrade_box.add_child(lbl)


func _make_upgrade_card(offer: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(96, 86)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.9)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var name_lbl := Label.new()
	name_lbl.text = "%s (Mk %d)" % [offer["name"], int(offer["next_mk"])]
	UiTheme.style_label(name_lbl, UiTheme.LabelKind.BODY)
	v.add_child(name_lbl)
	var current_lbl := Label.new()
	current_lbl.text = "Currently Mk %d" % _current_mk(offer["key"])
	UiTheme.style_label(current_lbl, UiTheme.LabelKind.CAPTION)
	v.add_child(current_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = String(offer["desc"])
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(72, 22)
	UiTheme.style_label(desc_lbl, UiTheme.LabelKind.CAPTION)
	v.add_child(desc_lbl)
	var buy_btn := Button.new()
	var sold: bool = offer.get("sold", false)
	buy_btn.text = "Sold" if sold else "Buy (%d)" % int(offer["cost"])
	UiTheme.style_button(buy_btn, true)
	buy_btn.disabled = sold or _run_bounty() < int(offer["cost"])
	buy_btn.pressed.connect(_on_buy_upgrade.bind(offer, buy_btn))
	v.add_child(buy_btn)
	return card


func _render_cannon_offers() -> void:
	for c in _cannon_box.get_children():
		c.queue_free()
	for offer in _cannon_offers:
		_cannon_box.add_child(_make_cannon_card(offer))


func _make_cannon_card(offer: Dictionary) -> Control:
	var part = offer["part"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(96, 86)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.12, 0.9)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var name_lbl := Label.new()
	name_lbl.text = part.get_display() if part.has_method("get_display") else String(part.display_name)
	UiTheme.style_label(name_lbl, UiTheme.LabelKind.BODY)
	v.add_child(name_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = String(part.description)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(72, 22)
	UiTheme.style_label(desc_lbl, UiTheme.LabelKind.CAPTION)
	v.add_child(desc_lbl)
	var buy_btn := Button.new()
	buy_btn.text = "Swap In (%d)" % int(offer["cost"])
	UiTheme.style_button(buy_btn, true)
	buy_btn.disabled = _run_bounty() < int(offer["cost"])
	buy_btn.pressed.connect(_on_buy_cannon.bind(offer, buy_btn))
	v.add_child(buy_btn)
	return card


func _render_storage() -> void:
	for c in _storage_box.get_children():
		c.queue_free()
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if run.weapon_storage.is_empty():
		var lbl := Label.new()
		lbl.text = "Storage is empty."
		UiTheme.style_label(lbl, UiTheme.LabelKind.CAPTION)
		_storage_box.add_child(lbl)
		return
	for i in range(run.weapon_storage.size()):
		var part = run.weapon_storage[i]
		_storage_box.add_child(_make_storage_row(part, i))


func _make_storage_row(part, idx: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = part.get_display() if part.has_method("get_display") else String(part.display_name)
	UiTheme.style_label(label, UiTheme.LabelKind.BODY)
	row.add_child(label)
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	UiTheme.style_button(equip_btn, true)
	equip_btn.pressed.connect(_on_equip_stored.bind(idx))
	row.add_child(equip_btn)
	var sell_btn := Button.new()
	# Sell price scales with Mk like the buy price, half-back.
	var sell_value: int = max(15, int(0.5 * (CANNON_BASE_COST + (int(part.mark) - 1) * CANNON_COST_PER_MK)))
	sell_btn.text = "Sell (+%d)" % sell_value
	UiTheme.style_button(sell_btn, true)
	sell_btn.pressed.connect(_on_sell_stored.bind(idx, sell_value))
	row.add_child(sell_btn)
	return row


# ---- Purchase handlers ----------------------------------------------------

func _on_buy_upgrade(offer: Dictionary, btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var cost: int = int(offer["cost"])
	if int(run.bounty) < cost:
		return
	run.bounty -= cost
	var key: String = String(offer["key"])
	run.set(key, _current_mk(key) + 1)
	# Roman, 2026-05-18: each offered upgrade can only be bought once per
	# visit. Mark the offer dict so the renderer keeps it disabled even
	# after the affordability refresh runs.
	offer["sold"] = true
	btn.text = "Sold"
	btn.disabled = true


func _on_buy_cannon(offer: Dictionary, btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var cost: int = int(offer["cost"])
	if int(run.bounty) < cost:
		return
	run.bounty -= cost
	# Swap: old cannon → storage, new cannon → CANNON slot.
	var old_cannon = run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
	if old_cannon != null:
		run.weapon_storage.append(old_cannon)
	run.loadout_snapshot[SlotTypes.SlotType.CANNON] = offer["part"]
	btn.text = "Equipped"
	btn.disabled = true
	_render_storage()


func _on_equip_stored(idx: int) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if idx < 0 or idx >= run.weapon_storage.size():
		return
	var picked = run.weapon_storage[idx]
	var current = run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
	run.weapon_storage.remove_at(idx)
	if current != null:
		run.weapon_storage.append(current)
	run.loadout_snapshot[SlotTypes.SlotType.CANNON] = picked
	_render_storage()


func _on_sell_stored(idx: int, sell_value: int) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if idx < 0 or idx >= run.weapon_storage.size():
		return
	run.weapon_storage.remove_at(idx)
	run.bounty += sell_value
	_render_storage()


func _on_repair(btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.bounty) < HULL_REPAIR_COST or int(run.max_hull) <= 0:
		return
	if int(run.current_hull) >= int(run.max_hull):
		# Roman, 2026-05-18: repair is endlessly buyable as long as the
		# hull isn't already full. Don't permanently disable the button —
		# leave the label informative so they can buy more after combat.
		btn.text = "Hull Full"
		_update_status_label()
		return
	run.bounty -= HULL_REPAIR_COST
	var heal: int = max(1, int(round(float(run.max_hull) * HULL_REPAIR_PCT)))
	run.current_hull = clampi(int(run.current_hull) + heal, 0, int(run.max_hull))
	btn.text = "Repair +25%% (%d)" % HULL_REPAIR_COST
	_update_status_label()


func _on_ammo_refill(btn: Button) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if int(run.bounty) < AMMO_REFILL_COST or int(run.ammo) < 0:
		return
	run.bounty -= AMMO_REFILL_COST
	var add: int = int(round(float(AMMO_FULL_VALUE) * AMMO_REFILL_PCT))
	run.ammo = clampi(int(run.ammo) + add, 0, AMMO_FULL_VALUE)
	btn.text = "Ammo +50%% (%d)" % AMMO_REFILL_COST
	_update_status_label()


func _on_leave() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/sector_map_v2.tscn")


# ---- Helpers --------------------------------------------------------------

func _current_mk(key: String) -> int:
	if not has_node("/root/Run"):
		return 0
	return int(get_node("/root/Run").get(key))


func _run_bounty() -> int:
	if not has_node("/root/Run"):
		return 0
	return int(get_node("/root/Run").bounty)


func _run_ammo() -> int:
	if not has_node("/root/Run"):
		return -1
	return int(get_node("/root/Run").ammo)


func _update_bounty_label(value) -> void:
	if _bounty_label:
		_bounty_label.text = "BOUNTY %d" % int(value)
	# Refresh affordability on buy buttons.
	if _upgrade_box:
		for card in _upgrade_box.get_children():
			_refresh_card_buttons(card)
	if _cannon_box:
		for card in _cannon_box.get_children():
			_refresh_card_buttons(card)


func _refresh_card_buttons(card: Node) -> void:
	for child in card.get_children():
		_refresh_card_buttons(child)
		if child is Button and (child.text.begins_with("Buy") or child.text.begins_with("Swap In")):
			var cost_str: String = child.text
			cost_str = cost_str.substr(cost_str.find("(") + 1)
			cost_str = cost_str.replace(")", "")
			child.disabled = _run_bounty() < int(cost_str)
