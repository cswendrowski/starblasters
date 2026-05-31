extends MarginContainer

const HologramHUDCls = preload("res://scripts/hologram_hud.gd")
const HudLight = preload("res://scripts/hud_light.gd")

const DOT_TEX   := "res://graphics/ui/hud_dot_light.png"
const ANN_TEX   := "res://graphics/ui/hud_annunciator_danger.png"
const FONT_PATH := "res://graphics/fonts/PixelOperator.ttf"

const DOT_W      := 8
const DOT_H      := 8
const DOT_STEP   := 10
const SHIELD_ROWS := 3
const SHIELD_COLS := 10
const HULL_COLS   := 10
const BAR_W := 48
const BAR_H := 4
const Slots = preload("res://scripts/weapons/SlotTypes.gd")

const COLOR_GRAY   := Color(0.70, 0.78, 0.88, 0.70)
const COLOR_GREEN  := Color(0.55, 1.00, 0.50, 1.0)
const COLOR_AMBER  := Color(1.00, 0.65, 0.10, 1.0)
const COLOR_SHIELD := Color(0.35, 0.65, 1.00, 1.0)
const COLOR_HULL   := Color(1.00, 0.30, 0.30, 1.0)
const COLOR_KEY    := Color(1.00, 1.00, 1.00, 0.50)
const COLOR_GOLD   := Color(1.00, 0.86, 0.42, 1.0)
const COLOR_BLACK  := Color(0.00, 0.00, 0.00, 1.0)

var _hud_root_node: Control = null

var _shield_pips: Array = []  # Array[Array[Sprite2D]] — SHIELD_ROWS × SHIELD_COLS
var _hull_pips: Array = []    # Array[Sprite2D] — HULL_COLS

var _shield_pip_container: Control = null
var _hull_pip_container: Control = null

var _bounty_value_lbl: Label = null
var _blaster_status_lbl: Label = null
var _pri_name_lbl: Label = null
var _sec_name_lbl: Label = null
var _sup_name_lbl: Label = null
var _pri_ammo_lbl: Label = null
var _sec_ammo_lbl: Label = null
var _sup_ammo_lbl: Label = null

var _light_blaster: Sprite2D = null
var _light_pri: Sprite2D = null
var _light_sec: Sprite2D = null
var _light_sup: Sprite2D = null
var _fire_light: Sprite2D = null
var _threat_light: Sprite2D = null
var _ann: Sprite2D = null

var _focus_bar_fill: ColorRect = null

var _player_ref = null
var _wave_spawning: bool = false
var _sec_ammo: int = -1
# Combat Drones deploy timer: while a wave is live the secondary ammo slot
# shows a remaining-time countdown instead of the ammo count. _sec_timer_active
# gates _on_secondary_ammo_changed so the ammo signal can't clobber the timer.
var _sec_timer_active: bool = false
var _super_charge_count: int = 0

var _font: Font = null

var hologram_hud = null

var _color_shield_off: Color
var _color_hull_off: Color

var _prev_hull: int = -1
var _prev_shield: int = -1
var _cached_shield: int = 0
var _cached_shield_max: int = 1
var _hull_crit: bool = false
var _threat_state: int = 0  # 0=OFF 1=BLINK 2=STEADY


func _ready() -> void:
	anchor_left = 0.0; anchor_right = 1.0
	anchor_top = 0.0; anchor_bottom = 0.0
	offset_left = 0.0; offset_right = 0.0
	offset_top = 0.0; offset_bottom = 270.0
	# Zero margins so _hud_root_node lands at viewport (0,0).
	add_theme_constant_override("margin_left", 0)
	add_theme_constant_override("margin_right", 0)
	add_theme_constant_override("margin_top", 0)
	add_theme_constant_override("margin_bottom", 0)

	_hud_root_node = Control.new()
	_hud_root_node.name = "HUDElements"
	_hud_root_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_hud_root_node)

	_font = load(FONT_PATH) as Font

	# Off-state pip lights: neutral dark
	_color_shield_off = Color(0.18, 0.18, 0.18, 1.0)
	_color_hull_off   = Color(0.18, 0.18, 0.18, 1.0)

	_install_hud()

	hologram_hud = HologramHUDCls.new()
	hologram_hud.name = "HologramHUD"
	hologram_hud._hud_root = self
	add_child(hologram_hud)


func _mpos(path: String, fallback: Vector2) -> Vector2:
	if has_node(path):
		return (get_node(path) as Marker2D).global_position
	return fallback


func _make_label(pos: Vector2, text: String, color: Color, font_size: int = 7) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", COLOR_BLACK)
	l.add_theme_constant_override("outline_size", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_dot(pos: Vector2, tint: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(DOT_TEX) as Texture2D
	s.hframes = 2
	s.centered = false
	s.modulate = tint
	s.frame = 0
	s.position = pos
	return s


func _install_hud() -> void:
	var c := _hud_root_node

	# Section header labels
	c.add_child(_make_label(_mpos("shield_label",   Vector2(16,  16)), "SHIELD",    COLOR_GRAY))
	c.add_child(_make_label(_mpos("hull_label",     Vector2(16,  72)), "HULL",      COLOR_GRAY))
	c.add_child(_make_label(_mpos("fire_label",     Vector2(48, 104)), "FIRE",      COLOR_GRAY))
	c.add_child(_make_label(_mpos("threat_label",   Vector2(376, 72)), "THREAT",    COLOR_GRAY))
	c.add_child(_make_label(_mpos("armanent_label", Vector2(392, 16)), "ARMAMENT",  COLOR_GRAY))

	# Hull annunciator
	_ann = Sprite2D.new()
	_ann.texture = load(ANN_TEX) as Texture2D
	_ann.hframes = 4
	_ann.centered = false
	_ann.frame = 1
	_ann.position = _mpos("hull_annuciator", Vector2(16, 104))
	c.add_child(_ann)

	# Shield pip container + rows (3 × 10)
	_shield_pip_container = Control.new()
	_shield_pip_container.name = "ShieldPips"
	_shield_pip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_pip_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(_shield_pip_container)
	var row_origins := [
		_mpos("shield_label/shield_pip_row_1", Vector2(16, 24)),
		_mpos("shield_label/shield_pip_row_2", Vector2(16, 40)),
		_mpos("shield_label/shield_pip_row_3", Vector2(16, 56)),
	]
	_shield_pips.clear()
	for row_i in SHIELD_ROWS:
		var row_arr: Array = []
		for col_i in SHIELD_COLS:
			var pip := _make_dot(row_origins[row_i] + Vector2(col_i * DOT_STEP, 0), COLOR_SHIELD)
			_shield_pip_container.add_child(pip)
			row_arr.append(pip)
		_shield_pips.append(row_arr)

	# Hull pip container + row (10)
	_hull_pip_container = Control.new()
	_hull_pip_container.name = "HullPips"
	_hull_pip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hull_pip_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(_hull_pip_container)
	var hull_origin := _mpos("hull_label/hull_pip_row_1", Vector2(16, 88))
	_hull_pips.clear()
	for col_i in HULL_COLS:
		var pip := _make_dot(hull_origin + Vector2(col_i * DOT_STEP, 0), COLOR_HULL)
		_hull_pip_container.add_child(pip)
		_hull_pips.append(pip)

	# Fire + threat lights
	_fire_light = _make_dot(_mpos("fire_label/fire_light",       Vector2(64,  104)), COLOR_AMBER)
	c.add_child(_fire_light)
	_threat_light = _make_dot(_mpos("threat_label/threat_light", Vector2(376,  80)), COLOR_AMBER)
	c.add_child(_threat_light)

	# BLASTER row
	c.add_child(_make_label(_mpos("pri_blaster_label",              Vector2(392, 24)), "BLASTER", COLOR_GRAY))
	c.add_child(_make_label(_mpos("pri_blaster_label/weapon_key",   Vector2(360, 24)),
		"[%s]" % _action_key_label("shoot"), COLOR_KEY))
	_light_blaster = _make_dot(_mpos("pri_blaster_label/weapon_light", Vector2(376, 24)), COLOR_GREEN)
	c.add_child(_light_blaster)
	_blaster_status_lbl = _make_label(_mpos("pri_blaster_label/blaster_status", Vector2(456, 24)), "READY", COLOR_GREEN)
	c.add_child(_blaster_status_lbl)

	# PRI weapon row
	_pri_name_lbl = _make_label(_mpos("pri_blaster_label/pri_weapon_label", Vector2(392, 32)), "—", COLOR_GREEN)
	c.add_child(_pri_name_lbl)
	c.add_child(_make_label(_mpos("pri_blaster_label/pri_weapon_label/weapon_key", Vector2(360, 32)),
		"[%s]" % _action_key_label("shoot"), COLOR_KEY))
	_light_pri = _make_dot(_mpos("pri_blaster_label/pri_weapon_label/weapon_light", Vector2(376, 32)), COLOR_GREEN)
	c.add_child(_light_pri)
	_pri_ammo_lbl = _make_label(_mpos("pri_blaster_label/pri_weapon_label/pri_ammo_count", Vector2(456, 32)), "", COLOR_GREEN)
	c.add_child(_pri_ammo_lbl)

	# SEC weapon row
	_sec_name_lbl = _make_label(_mpos("pri_blaster_label/sec_weapon_label", Vector2(392, 40)), "—", COLOR_GREEN)
	c.add_child(_sec_name_lbl)
	c.add_child(_make_label(_mpos("pri_blaster_label/sec_weapon_label/weapon_key", Vector2(360, 40)),
		"[%s]" % _action_key_label("shoot2"), COLOR_KEY))
	_light_sec = _make_dot(_mpos("pri_blaster_label/sec_weapon_label/weapon_light", Vector2(376, 40)), COLOR_GREEN)
	c.add_child(_light_sec)
	_sec_ammo_lbl = _make_label(_mpos("pri_blaster_label/sec_weapon_label/sec_ammo_count", Vector2(456, 40)), "", COLOR_GREEN)
	c.add_child(_sec_ammo_lbl)

	# SUP weapon row
	_sup_name_lbl = _make_label(_mpos("pri_blaster_label/sup_weapon_label", Vector2(392, 48)), "—", COLOR_GREEN)
	c.add_child(_sup_name_lbl)
	c.add_child(_make_label(_mpos("pri_blaster_label/sup_weapon_label/weapon_key", Vector2(360, 48)),
		"[%s]" % _action_key_label("shoot_nose"), COLOR_KEY))
	_light_sup = _make_dot(_mpos("pri_blaster_label/sup_weapon_label/weapon_light", Vector2(376, 48)), COLOR_GREEN)
	c.add_child(_light_sup)
	_sup_ammo_lbl = _make_label(_mpos("pri_blaster_label/sup_weapon_label/sup_ammo_bars", Vector2(456, 48)), "", COLOR_GREEN)
	c.add_child(_sup_ammo_lbl)

	# Bounty
	c.add_child(_make_label(_mpos("bounty_label",              Vector2(392, 240)), "BOUNTY", COLOR_GOLD))
	_bounty_value_lbl = _make_label(_mpos("bounty_label/bounty_count", Vector2(448, 240)), "0", COLOR_GOLD)
	c.add_child(_bounty_value_lbl)


# ---------------------------------------------------------------------------
# Public update API (called by main.tscn signal connections)
# ---------------------------------------------------------------------------

func update_hull(max_value, value) -> void:
	# Rebuild pips if count doesn't match
	var expected_count := clampi(max_value, 1, HULL_COLS)
	if _hull_pips.size() != expected_count:
		_rebuild_hull_pips(expected_count)

	var filled := roundi(float(value) / max(float(max_value), 1.0) * HULL_COLS)
	for i in _hull_pips.size():
		var pip := _hull_pips[i] as Sprite2D
		var on: bool = i < filled
		pip.frame = 1 if on else 0
		pip.modulate = COLOR_HULL if on else _color_hull_off

	# Pip hit flash on damage
	if _prev_hull >= 0 and int(value) < _prev_hull and _hull_pip_container != null:
		HudLight.pip_flash(_hull_pip_container)
	_prev_hull = int(value)

	# Critical flicker on fire light at hull <= 50%
	var crit: bool = float(value) / max(float(max_value), 1.0) <= 0.5 and int(value) > 0
	if crit != _hull_crit:
		_hull_crit = crit
		if _fire_light != null:
			if crit:
				_fire_light.frame = 1
				HudLight.apply(_fire_light, HudLight.Pattern.FLICKER)
			else:
				HudLight.stop(_fire_light)
				_fire_light.frame = 0

	# Update annunciator based on shield + hull state
	_update_annunciator(_cached_shield, int(value), max_value)


func update_shield(max_value, value) -> void:
	# Cache for annunciator state
	_cached_shield = int(value)
	_cached_shield_max = max_value

	# Rebuild pips if count doesn't match
	var expected_count := clampi(max_value, 1, SHIELD_ROWS * SHIELD_COLS)
	if _get_shield_pip_count() != expected_count:
		_rebuild_shield_pips(expected_count)

	var total := SHIELD_ROWS * SHIELD_COLS
	var filled := roundi(float(value) / max(float(max_value), 1.0) * total)
	for row_i in _shield_pips.size():
		var row: Array = _shield_pips[row_i]
		for col_i in row.size():
			var pip := row[col_i] as Sprite2D
			var on: bool = (row_i * SHIELD_COLS + col_i) < filled
			pip.frame = 1 if on else 0
			pip.modulate = COLOR_SHIELD if on else _color_shield_off

	# Pip hit flash on damage
	if _prev_shield >= 0 and int(value) < _prev_shield and _shield_pip_container != null:
		HudLight.pip_flash(_shield_pip_container)
	_prev_shield = int(value)

	# Update annunciator based on shield + hull state
	_update_annunciator(int(value), _prev_hull, _cached_shield_max)


func _get_shield_pip_count() -> int:
	var count := 0
	for row in _shield_pips:
		count += (row as Array).size()
	return count


func _rebuild_hull_pips(count: int) -> void:
	for p in _hull_pips:
		if is_instance_valid(p):
			p.queue_free()
	_hull_pips.clear()
	if not is_instance_valid(_hull_pip_container):
		return
	var hull_origin := _mpos("hull_label/hull_pip_row_1", Vector2(16, 88))
	for _i in range(count):
		var pip := _make_dot(hull_origin + Vector2(_i * DOT_STEP, 0), COLOR_HULL)
		_hull_pip_container.add_child(pip)
		_hull_pips.append(pip)


func _rebuild_shield_pips(count: int) -> void:
	for row in _shield_pips:
		for p in row:
			if is_instance_valid(p):
				p.queue_free()
	_shield_pips.clear()
	if not is_instance_valid(_shield_pip_container):
		return
	var row_origins := [
		_mpos("shield_label/shield_pip_row_1", Vector2(16, 24)),
		_mpos("shield_label/shield_pip_row_2", Vector2(16, 40)),
		_mpos("shield_label/shield_pip_row_3", Vector2(16, 56)),
	]
	var pips_placed := 0
	for row_i in SHIELD_ROWS:
		var row_arr: Array = []
		for col_i in SHIELD_COLS:
			if pips_placed >= count:
				break
			var pip := _make_dot(row_origins[row_i] + Vector2(col_i * DOT_STEP, 0), COLOR_SHIELD)
			_shield_pip_container.add_child(pip)
			row_arr.append(pip)
			pips_placed += 1
		_shield_pips.append(row_arr)
		if pips_placed >= count:
			break


func _update_annunciator(shield_val: int, hull_val: int, hull_max: int) -> void:
	if _ann == null or not is_instance_valid(_ann):
		return
	if shield_val > 0:
		_ann.frame = 0  # OK — shields up
	elif float(hull_val) / max(float(hull_max), 1.0) > 0.5:
		_ann.frame = 1  # Warn — shields down, hull OK
	else:
		_ann.frame = 2  # Danger — shields down, hull critical


func update_score(value) -> void:
	if _bounty_value_lbl:
		_bounty_value_lbl.text = "%d" % int(value)


func update_wave(_idx: int, _total: int) -> void:
	pass  # wave banners carry this info


func flicker_in(duration: float = 0.6) -> void:
	if hologram_hud and hologram_hud.has_method("flicker_in"):
		hologram_hud.flicker_in(duration)


func flicker_out(duration: float = 0.5) -> void:
	if hologram_hud and hologram_hud.has_method("flicker_out"):
		hologram_hud.flicker_out(duration)


# ---------------------------------------------------------------------------
# Player binding
# ---------------------------------------------------------------------------

func bind_player(player) -> void:
	if hologram_hud:
		hologram_hud.bind_player(player)
	_disconnect_player_signals(_player_ref)
	_player_ref = player
	if player == null:
		return

	if player.has_signal("hull_changed") and not player.hull_changed.is_connected(update_hull):
		player.hull_changed.connect(update_hull)
	if player.has_signal("shield_changed") and not player.shield_changed.is_connected(update_shield):
		player.shield_changed.connect(update_shield)
	if player.has_signal("ammo_changed") and not player.ammo_changed.is_connected(_on_ammo_changed):
		player.ammo_changed.connect(_on_ammo_changed)
	if player.has_signal("secondary_ammo_changed") and not player.secondary_ammo_changed.is_connected(_on_secondary_ammo_changed):
		player.secondary_ammo_changed.connect(_on_secondary_ammo_changed)
	if player.has_signal("secondary_timer_changed") and not player.secondary_timer_changed.is_connected(_on_secondary_timer_changed):
		player.secondary_timer_changed.connect(_on_secondary_timer_changed)
	if player.has_signal("super_charges_changed") and not player.super_charges_changed.is_connected(_on_super_charges_changed):
		player.super_charges_changed.connect(_on_super_charges_changed)
	if player.has_signal("focus_charge_changed") and not player.focus_charge_changed.is_connected(_on_focus_charge_changed):
		player.focus_charge_changed.connect(_on_focus_charge_changed)
	if player.has_signal("damaged") and not player.damaged.is_connected(_on_player_damaged):
		player.damaged.connect(_on_player_damaged)

	# Seed from current values
	if "max_hull" in player and "hull" in player:
		update_hull(player.max_hull, player.hull)
	if "max_shield" in player and "shield" in player:
		update_shield(player.max_shield, player.shield)
	if "super_charges" in player and "max_super_charges" in player:
		_on_super_charges_changed(int(player.super_charges), int(player.max_super_charges))
	if "focus_charge" in player and "focus_charge_max" in player:
		_on_focus_charge_changed(float(player.focus_charge), float(player.focus_charge_max))

	_install_focus_bar()
	_refresh_weapon_names()

	var director = get_node_or_null("/root/Main/WaveDirector")
	if director == null:
		director = get_node_or_null("/root/Main/Director")
	if director != null:
		if director.has_signal("wave_started") and not director.wave_started.is_connected(_on_wave_started_threat):
			director.wave_started.connect(_on_wave_started_threat)
		if director.has_signal("level_cleared") and not director.level_cleared.is_connected(_on_level_cleared_threat):
			director.level_cleared.connect(_on_level_cleared_threat)


func _install_ammo_label() -> void:
	pass  # no-op kept for external callers


func _install_focus_bar() -> void:
	if _focus_bar_fill != null and is_instance_valid(_focus_bar_fill):
		return
	var c := _hud_root_node
	c.add_child(_make_label(_mpos("focus_label", Vector2(8, 247)), "FOCUS", Color(0.5, 0.75, 1.0, 0.85), 7))
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.15, 0.3, 0.7)
	bg.position = _mpos("focus_bar", Vector2(8, 256))
	bg.size = Vector2(BAR_W, BAR_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)
	_focus_bar_fill = ColorRect.new()
	_focus_bar_fill.color = Color(0.4, 0.7, 1.0, 0.9)
	_focus_bar_fill.position = _mpos("focus_bar", Vector2(8, 256))
	_focus_bar_fill.size = Vector2(BAR_W, BAR_H)
	_focus_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_focus_bar_fill)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_focus_charge_changed(charge: float, max_charge: float) -> void:
	if _focus_bar_fill == null:
		return
	_focus_bar_fill.size.x = float(BAR_W) * clamp(charge / max(1.0, max_charge), 0.0, 1.0)


func _on_player_damaged(_amount: int) -> void:
	if _threat_light != null:
		HudLight.hit_flash(_threat_light)


func _refresh_weapon_names() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if run.has_method("get_active_cannon"):
		var ac = run.get_active_cannon()
		if ac != null and "display_name" in ac and _pri_name_lbl:
			_pri_name_lbl.text = String(ac.display_name)
	if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
		var p_sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
		if p_sec != null and "display_name" in p_sec and _sec_name_lbl:
			_sec_name_lbl.text = String(p_sec.display_name)


func _on_ammo_changed(value: int) -> void:
	if _pri_ammo_lbl == null:
		return
	# Always show the count, incl. 0 (Roman). -1 = infinite (Energy Blaster) → ∞.
	_pri_ammo_lbl.text = "∞" if value < 0 else "%d" % value
	_refresh_weapon_names()


func _on_secondary_ammo_changed(value: int, _maximum: int) -> void:
	_sec_ammo = value
	# While a Combat Drones deploy is live the slot shows the countdown timer;
	# don't let the ammo signal overwrite it. The ammo count re-renders when
	# the timer ends (_on_secondary_timer_changed active=false).
	if _sec_timer_active:
		return
	if _sec_ammo_lbl:
		# Always show the count, incl. 0 (Roman). -1 = infinite/none → ∞.
		_sec_ammo_lbl.text = "∞" if value < 0 else "%d" % value


# Combat Drones deploy timer. While active, the secondary ammo slot shows the
# remaining time (rounded-up seconds) instead of the ammo count. On expiry
# (active=false) the slot reverts to the cached deploy-ammo count.
func _on_secondary_timer_changed(seconds: float, active: bool) -> void:
	_sec_timer_active = active
	if _sec_ammo_lbl == null:
		return
	if active:
		_sec_ammo_lbl.text = "%ds" % int(ceil(seconds))
	else:
		_sec_ammo_lbl.text = "∞" if _sec_ammo < 0 else "%d" % _sec_ammo


func _on_super_charges_changed(value: int, _maximum: int) -> void:
	_super_charge_count = value
	if _sup_ammo_lbl:
		_sup_ammo_lbl.text = "|".repeat(value) if value > 0 else ""


func _on_wave_started_threat(_idx, _total, _silent, _text) -> void:
	_wave_spawning = true


func _on_level_cleared_threat() -> void:
	_wave_spawning = false


func _disconnect_player_signals(player) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_signal("hull_changed") and player.hull_changed.is_connected(update_hull):
		player.hull_changed.disconnect(update_hull)
	if player.has_signal("shield_changed") and player.shield_changed.is_connected(update_shield):
		player.shield_changed.disconnect(update_shield)
	if player.has_signal("ammo_changed") and player.ammo_changed.is_connected(_on_ammo_changed):
		player.ammo_changed.disconnect(_on_ammo_changed)
	if player.has_signal("secondary_ammo_changed") and player.secondary_ammo_changed.is_connected(_on_secondary_ammo_changed):
		player.secondary_ammo_changed.disconnect(_on_secondary_ammo_changed)
	if player.has_signal("secondary_timer_changed") and player.secondary_timer_changed.is_connected(_on_secondary_timer_changed):
		player.secondary_timer_changed.disconnect(_on_secondary_timer_changed)
	if player.has_signal("super_charges_changed") and player.super_charges_changed.is_connected(_on_super_charges_changed):
		player.super_charges_changed.disconnect(_on_super_charges_changed)
	if player.has_signal("focus_charge_changed") and player.focus_charge_changed.is_connected(_on_focus_charge_changed):
		player.focus_charge_changed.disconnect(_on_focus_charge_changed)
	if player.has_signal("damaged") and player.damaged.is_connected(_on_player_damaged):
		player.damaged.disconnect(_on_player_damaged)


# ---------------------------------------------------------------------------
# Per-frame logic
# ---------------------------------------------------------------------------

func _enemies_on_screen() -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			var y: float = (e as Node2D).global_position.y
			var x: float = (e as Node2D).global_position.x
			if y >= -32.0 and y <= 302.0 and x >= -32.0 and x <= 512.0:
				count += 1
	return count


func _action_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: int = (ev as InputEventKey).physical_keycode
			if kc == 0:
				kc = (ev as InputEventKey).keycode
			if kc == 0:
				continue
			return OS.get_keycode_string(kc)
	return ""


func _process(_delta: float) -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		var blaster_active: bool = int(run.active_cannon_idx) == 0

		if _light_blaster:
			_light_blaster.frame = 1 if blaster_active else 0

		# _light_pri: on when a non-blaster cannon is selected
		if _light_pri:
			_light_pri.frame = 0 if blaster_active else 1

		var sec_ok: bool = false
		if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
			var sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
			sec_ok = sec != null and (_sec_ammo > 0 if _sec_ammo >= 0 else false)
		if _light_sec:
			_light_sec.frame = 1 if sec_ok else 0

		if _light_sup:
			_light_sup.frame = 1 if _super_charge_count > 0 else 0

	if _blaster_status_lbl:
		var blaster_on: bool = has_node("/root/Run") and int(get_node("/root/Run").active_cannon_idx) == 0
		_blaster_status_lbl.text = "STANDBY" if not blaster_on else ("FIRING" if Input.is_action_pressed("shoot") else "READY")

	# --- Threat light (state-tracked to avoid restarting tween every frame) ---
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var on_screen: int = _enemies_on_screen() if enemy_count > 0 else 0
	var new_threat: int = 0  # OFF
	if on_screen > 0:
		# Enemies visible on screen → STEADY threat
		new_threat = 2
	elif enemy_count > 0 or _wave_spawning:
		# Enemies exist but offscreen (recycling) or wave incoming → BLINK
		new_threat = 1
	# else new_threat = 0 (OFF)

	if new_threat != _threat_state:
		_threat_state = new_threat
		if _threat_light != null:
			match _threat_state:
				2:  # STEADY
					_threat_light.frame = 1
					HudLight.apply(_threat_light, HudLight.Pattern.STEADY)
				1:  # BLINK
					_threat_light.frame = 1
					HudLight.apply(_threat_light, HudLight.Pattern.BLINK)
				0:  # OFF
					HudLight.stop(_threat_light)
					_threat_light.frame = 0
