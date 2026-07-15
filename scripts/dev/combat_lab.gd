extends Control

# Combat Lab — HD dev screen (2026-06-14). Replaces the old modal fan-out "Test Combat"
# flow with a proper configurable launcher: pick a Primary + Secondary + Modules (with
# marks), choose an encounter (standard combat w/ faction + depth, a hazard, a boss, or
# the beam showcase), and launch main.tscn with that exact ship. Lets you work through the
# modules + weapons in controlled tests. Config persists to user://tuners/combat_lab.json.
#
# Injection contract (recon-verified): write into Run AFTER new_run() (which wipes the
# loadout/modules + one-shot metas), THEN change_scene — the player's _ready() overlays
# Run.loadout_snapshot + applies Run.modules. Cannons/secondaries go through Run.equip_part;
# modules ride the list via Run.add_module.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")

const SAVE_PATH := "user://tuners/combat_lab.json"

enum Enc { COMBAT, MINEFIELD, ASTEROID, BOSS, BEAM_SHOWCASE, CUSTOM, SIGNAL_SECTOR }
const ENC_NAMES := ["Standard Combat", "Hazard: Minefield", "Hazard: Asteroid Field", "Boss Fight", "Beam Enemy Showcase", "Custom Level (test_level.tres)", "All-Signal Sector"]
const TEST_LEVEL_PATH := "res://resources/levels/test_level.tres"

const MINEFIELD_OPTIONS := [
	["Mixed (default)", "mixed"], ["Basic only", "basic"], ["Smart", "smart"],
	["Shielded", "shielded"], ["Cluster", "cluster"], ["Mega Cluster", "mega"],
]
const BOSS_PICKS := [
	["Commander", "res://scenes/enemies/bosses/boss.tscn"],
	["Lash", "res://scenes/enemies/bosses/boss_reaver.tscn"],
	["Aegis", "res://scenes/enemies/bosses/boss_sentinel.tscn"],
	["Howler", "res://scenes/enemies/bosses/boss_howler.tscn"],
	["Voidmaw", "res://scenes/enemies/bosses/boss_voidmaw.tscn"],
	["Spinwright", "res://scenes/enemies/bosses/boss_spinwright.tscn"],
	["Conductor", "res://scenes/enemies/bosses/boss_conductor.tscn"],
	# Shepherd — testbed for the encounter state machine (dev-only; NOT in the
	# production BOSS_ROSTER yet). Launch via Combat Lab -> Boss Fight -> Shepherd.
	["Shepherd", "res://scenes/enemies/factions/zealot/boss_z_l_shepherd.tscn"],
	# Battleship — zealot turret mega-boss (WIP, dev-only). The hull is unhittable; destroy all its
	# turrets to make it flee. This is the ONLY way to exercise the destroy→flee mechanic (the Enemy
	# Bench dummy can't shoot back).
	["Battleship", "res://scenes/enemies/factions/zealot/boss_z_battleship.tscn"],
	# Director — corporate multi-part mega-boss (WIP, dev-only). Hittable body (knock-away on hit) + 2
	# destructible wing cannons; kill the body OR outlast its maneuver cycle. Same persistent-gated pattern.
	["Director", "res://scenes/enemies/factions/corporate/boss_c_director.tscn"],
]
const FACTION_PICKS := [
	["Auto (deterministic)", -1],
	["Supremacy", Factions.Id.SUPREMACY],
	["Privateer", Factions.Id.PRIVATEER],
	["Corporate", Factions.Id.CORPORATE],
	["Zealot", Factions.Id.ZEALOT],
]

var _hd_scope: HdViewportScope = null

var _primary_dd: OptionButton
var _primary_mk: SpinBox
var _secondary_dd: OptionButton
var _secondary_mk: SpinBox
# Per-module install rows (2026-07-14): one CheckBox + one mark SpinBox per module
# factory, parallel to _module_factories. Replaces the old multi-select ItemList +
# single shared "all selected" mark, and the separate Glass-cannon checkbox — the
# Shield Core is now just a module row you tick/untick at the mark you want, and the
# bay is built entirely from these rows (no hidden auto-seeded Mk.1 core).
var _module_checks: Array = []   # Array[CheckBox]
var _module_marks: Array = []    # Array[SpinBox]
var _enc_dd: OptionButton
var _faction_dd: OptionButton
var _sectors_spin: SpinBox
var _combats_spin: SpinBox
var _mine_dd: OptionButton
var _boss_dd: OptionButton
var _status: Label

var _primary_factories: Array = []    # [{factory,name}]
var _secondary_factories: Array = []  # leading {None}
var _module_factories: Array = []     # [{factory,name}]


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_primary_factories = _factories_for(SlotTypes.SlotType.CANNON)
	_secondary_factories = [{"factory": "", "name": "None"}]
	_secondary_factories.append_array(_factories_for(SlotTypes.SlotType.HARDPOINT_WING))
	_module_factories = _module_list_factories()
	_build_ui()
	_load()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


# Module rows for the lab. The Shield Core is auto-seeded by new_run() and the lab builds
# the bay entirely from these rows, so it must be listed or every launch is a glass cannon.
# It's pinned FIRST (and default-checked in _build_ui) so the shield sits at the top and
# mirrors the normal starting ship — then the rest of the pool is appended, skipping the
# Shield Core so it isn't listed twice (it now also rolls in the shop pool, so _factories_for
# includes it). Regression fix 2026-07-14.
func _module_list_factories() -> Array:
	var out: Array = []
	var sc = PartCatalog._make_by_name("_make_shield_core", SlotTypes.SlotType.MODULE)
	var sc_name: String = String(sc.display_name) if sc != null and "display_name" in sc else "Shield Core"
	out.append({"factory": "_make_shield_core", "name": sc_name})
	for e in _factories_for(SlotTypes.SlotType.MODULE):
		if String(e["factory"]) != "_make_shield_core":
			out.append(e)
	return out


# Enumerate the dedup'd factory list for a slot, with display names (mirrors hangar).
func _factories_for(slot: int) -> Array:
	var out: Array = []
	var seen := {}
	for entry in PartCatalog._all_pool():
		if int(entry["slot"]) != slot:
			continue
		var f := String(entry["factory"])
		if seen.has(f):
			continue
		seen[f] = true
		var part = PartCatalog._make_by_name(f, slot)
		var nm: String = String(part.display_name) if part != null and "display_name" in part else f
		out.append({"factory": f, "name": nm})
	return out


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var pad := MarginContainer.new()
	for m in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + m, 28)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	pad.add_child(root)

	var title := Label.new()
	title.text = "COMBAT LAB"
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "configure a ship + launch a controlled fight"
	UiTheme.style_label(sub, UiTheme.LabelKind.CAPTION)
	root.add_child(sub)
	root.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)

	# ---- Left: ship loadout ----
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(560, 0)
	cols.add_child(left)
	left.add_child(_hdr("SHIP LOADOUT"))
	_primary_dd = _dd_row(left, "Primary weapon", _primary_factories.map(func(e): return e["name"]))
	_primary_mk = _mk_row(left, "Primary mark")
	_secondary_dd = _dd_row(left, "Secondary weapon", _secondary_factories.map(func(e): return e["name"]))
	_secondary_mk = _mk_row(left, "Secondary mark")
	left.add_child(_cap("Modules — tick to install, set each mark (bay holds 6). Untick Shield Core for glass cannon."))
	# Scrollable list of per-module rows so the panel stays a fixed height regardless
	# of how many module types exist.
	var mod_scroll := ScrollContainer.new()
	mod_scroll.custom_minimum_size = Vector2(0, 340)
	mod_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(mod_scroll)
	var mod_box := VBoxContainer.new()
	mod_box.add_theme_constant_override("separation", 4)
	mod_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_scroll.add_child(mod_box)
	_module_checks.clear()
	_module_marks.clear()
	for e in _module_factories:
		var row := _module_row(mod_box, String(e["name"]))
		# Default the ship to the normal starting kit: Shield Core installed at Mk.1,
		# everything else off. What's ticked here is exactly what flies.
		if String(e["factory"]) == "_make_shield_core":
			(row["cb"] as CheckBox).button_pressed = true
		_module_checks.append(row["cb"])
		_module_marks.append(row["mk"])

	# ---- Right: encounter ----
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	right.add_child(_hdr("ENCOUNTER"))
	_enc_dd = _dd_row(right, "Type", ENC_NAMES)
	right.add_child(_cap("— Standard Combat uses Faction + Depth —"))
	_faction_dd = _dd_row(right, "Faction", FACTION_PICKS.map(func(e): return e[0]))
	_sectors_spin = _spin_row(right, "Depth: sectors cleared", 0, 8, 1, 2)
	_combats_spin = _spin_row(right, "Depth: combats in sector", 0, 5, 1, 2)
	right.add_child(_cap("— Minefield uses Composition —"))
	_mine_dd = _dd_row(right, "Minefield composition", MINEFIELD_OPTIONS.map(func(e): return e[0]))
	right.add_child(_cap("— Boss Fight uses Boss —"))
	_boss_dd = _dd_row(right, "Boss", BOSS_PICKS.map(func(e): return e[0]))

	root.add_child(HSeparator.new())
	_status = Label.new()
	_status.text = "Ready."
	UiTheme.style_label(_status, UiTheme.LabelKind.CAPTION)
	root.add_child(_status)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	root.add_child(btns)
	var launch := Button.new()
	launch.text = "▶  LAUNCH"
	launch.custom_minimum_size = Vector2(360, 60)
	UiTheme.style_button(launch)
	launch.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	launch.pressed.connect(_launch)
	btns.add_child(launch)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(220, 60)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	btns.add_child(back)


# ---- UI row helpers ----

func _hdr(text: String) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.HEADER)
	return l

func _cap(text: String) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.CAPTION)
	return l

func _dd_row(parent: VBoxContainer, caption: String, items) -> OptionButton:
	parent.add_child(_cap(caption))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.menu_font())
	dd.custom_minimum_size = Vector2(0, 40)
	for it in items:
		dd.add_item(String(it))
	parent.add_child(dd)
	return dd

func _mk_row(parent: VBoxContainer, caption: String) -> SpinBox:
	return _spin_row(parent, caption, 1, 9, 1, 1)

# One module install row: [✓ Name .............] [Mk (1–9)]. Returns {cb, mk}.
func _module_row(parent: VBoxContainer, module_name: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cb := CheckBox.new()
	cb.text = module_name
	cb.add_theme_font_override("font", UiTheme.menu_font())
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cb)
	var mk_lbl := Label.new()
	mk_lbl.text = "Mk"
	UiTheme.style_label(mk_lbl, UiTheme.LabelKind.CAPTION)
	mk_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mk_lbl)
	var sb := SpinBox.new()
	sb.add_theme_font_override("font", UiTheme.menu_font())
	sb.custom_minimum_size = Vector2(96, 36)
	sb.min_value = 1
	sb.max_value = 9
	sb.step = 1
	sb.value = 1
	row.add_child(sb)
	parent.add_child(row)
	return {"cb": cb, "mk": sb}

func _spin_row(parent: VBoxContainer, caption: String, lo: float, hi: float, step: float, val: float) -> SpinBox:
	parent.add_child(_cap(caption))
	var sb := SpinBox.new()
	sb.add_theme_font_override("font", UiTheme.menu_font())
	sb.custom_minimum_size = Vector2(0, 40)
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = val
	parent.add_child(sb)
	return sb


# ---- Launch ----

func _launch() -> void:
	if not has_node("/root/Run"):
		_status.text = "No /root/Run autoload — cannot launch."
		return
	var run = get_node("/root/Run")
	run.new_run()
	run.test_mode_active = true
	# Primary — always equip the chosen cannon.
	var prim = PartCatalog._make_by_name(_primary_factories[_primary_dd.selected]["factory"], SlotTypes.SlotType.CANNON)
	if prim != null:
		if "mark" in prim:
			prim.mark = int(_primary_mk.value)
		run.equip_part(prim)
	# Secondary — index 0 = None.
	if _secondary_dd.selected > 0:
		var sec = PartCatalog._make_by_name(_secondary_factories[_secondary_dd.selected]["factory"], SlotTypes.SlotType.HARDPOINT_WING)
		if sec != null:
			if "mark" in sec:
				sec.mark = int(_secondary_mk.value)
			run.equip_part(sec)
	# Modules — build the bay ENTIRELY from the panel. new_run() auto-seeds a Mk.1
	# Shield Core; clear it first so there's no hidden core underneath and what's ticked
	# is exactly what flies (unticking Shield Core = glass cannon; bay_initialized stays
	# true so the shieldless gate applies).
	var want: Array = []   # [{factory, mk}] in row order
	for i in _module_factories.size():
		if (_module_checks[i] as CheckBox).button_pressed:
			want.append({"factory": String(_module_factories[i]["factory"]), "mk": int((_module_marks[i] as SpinBox).value)})
	if want.size() > run.MODULE_BAY_SIZE:
		_status.text = "Bay holds %d modules — you ticked %d. Untick %d." % [run.MODULE_BAY_SIZE, want.size(), want.size() - run.MODULE_BAY_SIZE]
		return
	while run.modules.size() > 0:
		run.remove_module(run.modules.size() - 1)
	for w in want:
		var mod = PartCatalog._make_by_name(String(w["factory"]), SlotTypes.SlotType.MODULE)
		if mod != null:
			if "mark" in mod:
				mod.mark = int(w["mk"])
			run.add_module(mod)
	# Encounter.
	match _enc_dd.selected:
		Enc.COMBAT:
			run.current_node_type = 0
			run.sectors_cleared = int(_sectors_spin.value)
			run.combats_in_sector = int(_combats_spin.value)
			var fid: int = int(FACTION_PICKS[_faction_dd.selected][1])
			if fid >= 0:
				run.set_meta("forced_faction", fid)
		Enc.MINEFIELD:
			run.current_node_type = 5
			run.current_hazard_subtype = "minefield"
			run.set_meta("minefield_mine_type", String(MINEFIELD_OPTIONS[_mine_dd.selected][1]))
		Enc.ASTEROID:
			run.current_node_type = 5
			run.current_hazard_subtype = "asteroid_field"
			# Reframed as the "Asteroid Stronghold" (2026-07-13): overlay loose rocks + authored
			# stronghold prefabs on standard faction combat; honor the depth spinners + faction
			# dropdown so the overlaid enemy ships scale + theme like a standard fight.
			run.sectors_cleared = int(_sectors_spin.value)
			run.combats_in_sector = int(_combats_spin.value)
			var ast_fid: int = int(FACTION_PICKS[_faction_dd.selected][1])
			if ast_fid >= 0:
				run.set_meta("forced_faction", ast_fid)
			# Turn the DECORATIVE backdrop asteroid field on. The coordinator zeroes it unless
			# current_stellar flags has_asteroids — the sector map sets that for real asteroid
			# nodes, but Combat Lab doesn't, so the backdrop came up empty. Merge it in (keeping
			# any other stellar fields) so the baked-backdrop path is exercised here too.
			var ast_stellar: Dictionary = run.current_stellar if run.current_stellar is Dictionary else {}
			ast_stellar["has_asteroids"] = true
			if float(ast_stellar.get("asteroid_density", 0.0)) <= 0.0:
				ast_stellar["asteroid_density"] = 0.7
			run.current_stellar = ast_stellar
		Enc.BOSS:
			run.current_node_type = 3
			run.forced_boss_scene = String(BOSS_PICKS[_boss_dd.selected][1])
		Enc.BEAM_SHOWCASE:
			run.current_node_type = 5
			run.current_hazard_subtype = "beam_showcase"
		Enc.CUSTOM:
			if not ResourceLoader.exists(TEST_LEVEL_PATH):
				_status.text = "test_level.tres missing — author one as a LevelData .tres."
				return
			run.set_meta("custom_level_path", TEST_LEVEL_PATH)
		Enc.SIGNAL_SECTOR:
			# Not a combat — launch the sector map with every POI forced to a Signal Event
			# (rolled in from the old standalone dev-menu button). Uses the configured loadout.
			run.set_meta("force_all_signal", true)
			_save()
			var sc := _hd_scope
			_hd_scope = null
			SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE, func(): HdScreen.drop(sc))
			return
	_save()
	var scope := _hd_scope
	_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn", func(): HdScreen.drop(scope))


# ---- Persistence ----

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"primary": _primary_dd.selected, "primary_mk": int(_primary_mk.value),
		"secondary": _secondary_dd.selected, "secondary_mk": int(_secondary_mk.value),
		# Per-module state keyed by factory name (index-independent if the pool changes).
		"module_states": _module_states(),
		"enc": _enc_dd.selected, "faction": _faction_dd.selected,
		"sectors": int(_sectors_spin.value), "combats": int(_combats_spin.value),
		"mine": _mine_dd.selected, "boss": _boss_dd.selected,
	}, "\t"))
	f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return
	_primary_dd.select(_clampi_sel(d.get("primary", 0), _primary_dd))
	_primary_mk.value = float(d.get("primary_mk", 1))
	_secondary_dd.select(_clampi_sel(d.get("secondary", 0), _secondary_dd))
	_secondary_mk.value = float(d.get("secondary_mk", 1))
	_enc_dd.select(_clampi_sel(d.get("enc", 0), _enc_dd))
	_faction_dd.select(_clampi_sel(d.get("faction", 0), _faction_dd))
	_sectors_spin.value = float(d.get("sectors", 2))
	_combats_spin.value = float(d.get("combats", 2))
	_mine_dd.select(_clampi_sel(d.get("mine", 0), _mine_dd))
	_boss_dd.select(_clampi_sel(d.get("boss", 0), _boss_dd))
	# Per-module install state (missing/old saves keep the build-time defaults — Shield Core on).
	var ms: Variant = d.get("module_states", null)
	if ms is Dictionary:
		for i in _module_factories.size():
			var st: Variant = ms.get(String(_module_factories[i]["factory"]), null)
			if st is Dictionary:
				(_module_checks[i] as CheckBox).button_pressed = bool(st.get("on", false))
				(_module_marks[i] as SpinBox).value = float(st.get("mk", 1))


# Per-module install state keyed by factory name → {on, mk}.
func _module_states() -> Dictionary:
	var d := {}
	for i in _module_factories.size():
		d[String(_module_factories[i]["factory"])] = {
			"on": (_module_checks[i] as CheckBox).button_pressed,
			"mk": int((_module_marks[i] as SpinBox).value),
		}
	return d


func _clampi_sel(v: Variant, dd: OptionButton) -> int:
	return clampi(int(v), 0, maxi(0, dd.item_count - 1))


# ---- Nav ----

func _on_back() -> void:
	var scope := _hd_scope
	_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn", func(): HdScreen.drop(scope))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
