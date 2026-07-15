extends MarginContainer

const HologramHUDCls = preload("res://scripts/hud/hologram_hud.gd")
const HudLight = preload("res://scripts/hud/hud_light.gd")

# HUD layout lives in scenes/ui.tscn (2026-07-13): every label, light, bar and
# pip-row origin is a scene node — move/edit them in the editor. This script only
# fills the variable-count pip rows (shield/hull/mode charges) and drives state.
const DOT_TEX   := "res://graphics/ui/hud_dot_light.png"

const DOT_STEP   := 10
const SHIELD_ROW_STEP := 8
const SHIELD_ROWS := 3
const SHIELD_COLS := 10
const HULL_COLS   := 10
const BAR_W := 48   # fallback duration-bar width; live width reads ModeBarBG's scene size
const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Static label/light colors are authored in scenes/ui.tscn now; these remain for
# the state-driven tints the script still writes (pips + warn lights).
const COLOR_AMBER  := Color(1.00, 0.65, 0.10, 1.0)
const COLOR_SHIELD := Color(0.35, 0.65, 1.00, 1.0)
const COLOR_HULL   := Color(1.00, 0.30, 0.30, 1.0)

var _hud_root_node: Control = null

var _shield_pips: Array = []  # Array[Array[Sprite2D]] — SHIELD_ROWS × SHIELD_COLS
var _hull_pips: Array = []    # Array[Sprite2D] — HULL_COLS

var _shield_pip_container: Node2D = null
var _hull_pip_container: Node2D = null

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
# Weapon-light ammo state animation (Roman 2026-06-10): flash while regenerating, darken when empty.
var _wlight_t: float = 0.0
const WLIGHT_FLASH_HZ: float = 3.0
# DANGER annunciator flash rate — matches danger_pulse.gd PULSE_HZ so the HUD sprite
# pulses in time with the low-hull warning overlay (Roman 2026-06-11).
const ANN_DANGER_PULSE_HZ: float = 1.5
var _ann_pulse_t: float = 0.0
var _light_sec: Sprite2D = null
var _light_sup: Sprite2D = null
var _fire_light: Sprite2D = null
var _ann: Sprite2D = null

# THREAT warn-light stack (replaces the single threat light + WAVE X/X banners,
# Roman 2026-07-12): vertical amber lights, declared as WarnLights/Light* scene
# nodes. Steady state = bottom N lights lit, N = waves remaining in the level.
# While enemies are arriving (the old BLINK state) the stack runs a downward
# chase, then settles back into the wave count.
const WARN_CHASE_STEP_S := 0.09       # chase advance interval
const WARN_CHASE_BAND := 3            # lit lights in the moving chase band
const COLOR_WARN_OFF := Color(0.30, 0.22, 0.10, 0.8)
var _warn_lights: Array = []          # Array[Sprite2D], index 0 = top (from scene)
var _warn_light_container: Node2D = null
var _waves_remaining: int = 0
var _warn_chase_t: float = 0.0
var _warn_chase_step: int = 0

# Shift-Mode meter (unified system): a DURATION bar (active countdown) + a row of
# discrete CHARGE pips (light sprites, like hull/shield). The label + bar colour + pip
# count swap by active mode in _on_mode_changed_ui.
var _focus_bar_fill: ColorRect = null   # ModeBarFill — the active-duration bar
var _mode_bar_w: float = float(BAR_W)   # full-charge fill width, read from ModeBarBG's scene size
var _mode_label: Label = null
var _mode_pips: Array = []              # Array[Sprite2D] — one per charge
var _mode_pip_container: Node2D = null
var _mode_pip_color: Color = Color(0.7, 0.45, 1.0, 0.9)  # tint of the lit charge pips (fixed purple)
var _prev_mode_charges: int = -1        # for pip-spend flash
var _ui_active_mode: int = 0  # ShiftMode enum: 0=FOCUS 1=PHASE 2=HYPER 3=RUSH 4=REFIRE 5=ECHO 6=THIEF 7=REFLECT
const _MODE_COL_FOCUS := Color(0.4, 0.7, 1.0, 0.9)
const _MODE_COL_HYPER := Color(1.0, 0.6, 0.2, 0.9)
const _MODE_COL_HYPER_ON := Color(1.0, 0.85, 0.35, 1.0)
const _MODE_COL_PHASE := Color(0.7, 0.45, 1.0, 0.9)
const _MODE_COL_RUSH := Color(0.4, 1.0, 0.6, 0.9)     # green
const _MODE_COL_REFIRE := Color(1.0, 0.45, 0.45, 0.9) # red
const _MODE_COL_ECHO := Color(0.55, 0.85, 1.0, 0.9)   # cyan
const _MODE_COL_THIEF := Color(0.72, 0.32, 1.0, 0.9)  # purple
const _MODE_COL_REFLECT := Color(0.95, 0.85, 0.35, 0.9) # gold
# mode enum int → [label, colour]. Keep in sync with player.gd ShiftMode.
const _MODE_META := {
	0: ["FOCUS", _MODE_COL_FOCUS],
	1: ["PHASE", _MODE_COL_PHASE],
	2: ["HYPER", _MODE_COL_HYPER],
	3: ["RUSH", _MODE_COL_RUSH],
	4: ["REFIRE", _MODE_COL_REFIRE],
	5: ["ECHO", _MODE_COL_ECHO],
	6: ["THIEF", _MODE_COL_THIEF],
	7: ["REFLECT", _MODE_COL_REFLECT],
}
const _MODE_PIP_OFF := Color(0.2, 0.22, 0.3, 0.7)  # spent/empty charge pip
# Meter body is fixed purple regardless of equipped mode (Roman 2026-07-12) —
# the mode label keeps its per-mode colour, the bar + charge pips don't swap.
const _MODE_METER_PURPLE := Color(0.7, 0.45, 1.0, 0.9)

var _player_ref = null
var _wave_spawning: bool = false
var _sec_ammo: int = -1
# Combat Drones deploy timer: while a wave is live the secondary ammo slot
# shows a remaining-time countdown instead of the ammo count. _sec_timer_active
# gates _on_secondary_ammo_changed so the ammo signal can't clobber the timer.
var _sec_timer_active: bool = false
var _super_charge_count: int = 0

var hologram_hud = null

var _color_shield_off: Color
var _color_hull_off: Color

var _prev_hull: int = -1
var _prev_shield: int = -1
var _cached_shield: int = 0
var _cached_shield_max: int = 1
var _hull_crit: bool = false


func _ready() -> void:
	# Root anchors/margins are authored in scenes/ui.tscn — no runtime layout
	# overrides here, so editor tweaks stick.
	_hud_root_node = $HUDElements

	# Off-state pip lights: neutral dark
	_color_shield_off = Color(0.18, 0.18, 0.18, 1.0)
	_color_hull_off   = Color(0.18, 0.18, 0.18, 1.0)

	_bind_hud_nodes()

	hologram_hud = HologramHUDCls.new()
	hologram_hud.name = "HologramHUD"
	hologram_hud._hud_root = self
	add_child(hologram_hud)


func _make_dot(pos: Vector2, tint: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(DOT_TEX) as Texture2D
	s.hframes = 2
	s.centered = false
	s.modulate = tint
	s.frame = 0
	s.position = pos
	return s


# Grab references to the scene-authored HUD nodes (scenes/ui.tscn) and fill the
# variable-count pip rows. All positions/colors are the scene's; this only wires
# state-driven behavior onto the declared nodes.
func _bind_hud_nodes() -> void:
	var c := _hud_root_node

	_ann = c.get_node("Annunciator") as Sprite2D
	_fire_light = c.get_node("FireLight") as Sprite2D

	# Pip rows: containers are scene nodes (move them to move the row); the pips
	# themselves are code-built at local offsets since their counts are live data.
	_shield_pip_container = c.get_node("ShieldPips") as Node2D
	_hull_pip_container = c.get_node("HullPips") as Node2D
	_rebuild_shield_pips(SHIELD_ROWS * SHIELD_COLS)
	_rebuild_hull_pips(HULL_COLS)

	# THREAT warn-light stack — the lights are the WarnLights/Light* scene nodes.
	_warn_light_container = c.get_node("WarnLights") as Node2D
	_warn_lights.clear()
	for child in _warn_light_container.get_children():
		if child is Sprite2D:
			_warn_lights.append(child)

	# Armament rows. Key hints render the live InputMap binding over the scene's
	# placeholder text (bindings drift + are user-rebindable).
	_light_blaster = c.get_node("BlasterRow/Light") as Sprite2D
	_blaster_status_lbl = c.get_node("BlasterRow/Status") as Label
	_light_pri = c.get_node("PriRow/Light") as Sprite2D
	_pri_name_lbl = c.get_node("PriRow/Name") as Label
	_pri_ammo_lbl = c.get_node("PriRow/Ammo") as Label
	_light_sec = c.get_node("SecRow/Light") as Sprite2D
	_sec_name_lbl = c.get_node("SecRow/Name") as Label
	_sec_ammo_lbl = c.get_node("SecRow/Ammo") as Label
	_light_sup = c.get_node("SupRow/Light") as Sprite2D
	_sup_name_lbl = c.get_node("SupRow/Name") as Label
	_sup_ammo_lbl = c.get_node("SupRow/Ammo") as Label
	(c.get_node("BlasterRow/Key") as Label).text = "[%s]" % _action_key_label("shoot")
	(c.get_node("PriRow/Key") as Label).text = "[%s]" % _action_key_label("shoot")
	(c.get_node("SecRow/Key") as Label).text = "[%s]" % _action_key_label("shoot2")
	(c.get_node("SupRow/Key") as Label).text = "[%s]" % _action_key_label("shoot_nose")

	_bounty_value_lbl = c.get_node("BountyValue") as Label

	# Shift-mode meter: label + duration bar + charge-pip row origin.
	_mode_label = c.get_node("ModeLabel") as Label
	_focus_bar_fill = c.get_node("ModeBarFill") as ColorRect
	_mode_bar_w = (c.get_node("ModeBarBG") as ColorRect).size.x
	_mode_pip_container = c.get_node("ModePips") as Node2D


# ---------------------------------------------------------------------------
# Public update API (called by main.tscn signal connections)
# ---------------------------------------------------------------------------

func update_hull(max_value, value) -> void:
	# Rebuild pips if count doesn't match
	var expected_count := clampi(max_value, 1, HULL_COLS)
	if _hull_pips.size() != expected_count:
		_rebuild_hull_pips(expected_count)

	var filled := roundi(float(value) / max(float(max_value), 1.0) * float(_hull_pips.size()))
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

	var pip_count := _get_shield_pip_count()
	var filled := roundi(float(value) / max(float(max_value), 1.0) * float(pip_count))
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
	for _i in range(count):
		var pip := _make_dot(Vector2(_i * DOT_STEP, 0), COLOR_HULL)
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
	var pips_placed := 0
	for row_i in SHIELD_ROWS:
		var row_arr: Array = []
		for col_i in SHIELD_COLS:
			if pips_placed >= count:
				break
			var pip := _make_dot(Vector2(col_i * DOT_STEP, row_i * SHIELD_ROW_STEP), COLOR_SHIELD)
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


func update_wave(idx: int, total: int) -> void:
	# Warn-light stack: waves remaining includes the wave that just started.
	_waves_remaining = clampi(total - idx, 0, _warn_lights.size())


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
	# Unified Shift-mode meter: discrete charges (pips) + active-duration bar.
	if player.has_signal("mode_charges_changed") and not player.mode_charges_changed.is_connected(_on_mode_charges_changed):
		player.mode_charges_changed.connect(_on_mode_charges_changed)
	if player.has_signal("mode_duration_changed") and not player.mode_duration_changed.is_connected(_on_mode_duration_changed):
		player.mode_duration_changed.connect(_on_mode_duration_changed)
	if player.has_signal("mode_changed") and not player.mode_changed.is_connected(_on_mode_changed_ui):
		player.mode_changed.connect(_on_mode_changed_ui)
	if player.has_signal("damaged") and not player.damaged.is_connected(_on_player_damaged):
		player.damaged.connect(_on_player_damaged)

	# Seed from current values
	if "max_hull" in player and "hull" in player:
		update_hull(player.max_hull, player.hull)
	if "max_shield" in player and "shield" in player:
		update_shield(player.max_shield, player.shield)
	if "super_charges" in player and "max_super_charges" in player:
		_on_super_charges_changed(int(player.super_charges), int(player.max_super_charges))

	# Seed the mode meter to the player's current Shift mode (rebuilds pips + colour),
	# then push the live charge + duration values into it.
	if "active_mode" in player:
		_on_mode_changed_ui(int(player.active_mode))
	if "mode_charges" in player and "mode_charges_max" in player:
		_on_mode_charges_changed(int(player.mode_charges), int(player.mode_charges_max))
	if "mode_active_t" in player and "mode_duration" in player:
		_on_mode_duration_changed(float(player.mode_active_t), float(player.mode_duration))
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


# Rebuild the Shift-mode charge pips to `count` (one light per charge). The pips
# sit on top of the duration bar (Roman 2026-07-12) — the ModePips scene node is
# parked 2 px above the bar origin so the 8×8 dots centre over the 4 px bar.
func _rebuild_mode_pips(count: int) -> void:
	for p in _mode_pips:
		if is_instance_valid(p):
			p.queue_free()
	_mode_pips.clear()
	if not is_instance_valid(_mode_pip_container):
		return
	for i in range(count):
		var pip := _make_dot(Vector2(i * DOT_STEP, 0), _MODE_PIP_OFF)
		_mode_pip_container.add_child(pip)
		_mode_pips.append(pip)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

# Discrete charges → light the pips, flash on spend. (Unified Shift-mode meter.)
func _on_mode_charges_changed(charges: int, max_charges: int) -> void:
	if _mode_pip_container == null or not is_instance_valid(_mode_pip_container):
		return
	if _mode_pips.size() != max_charges:
		_rebuild_mode_pips(max_charges)
	for i in _mode_pips.size():
		var pip := _mode_pips[i] as Sprite2D
		if pip == null:
			continue
		var on: bool = i < charges
		pip.frame = 1 if on else 0
		pip.modulate = _mode_pip_color if on else _MODE_PIP_OFF
	# Flash the pip row when a charge is spent (count dropped).
	if _prev_mode_charges >= 0 and charges < _prev_mode_charges:
		HudLight.pip_flash(_mode_pip_container)
	_prev_mode_charges = charges


# Active window → fill the duration bar (1.0 at activation, empties as it runs out).
func _on_mode_duration_changed(active_t: float, duration: float) -> void:
	if _focus_bar_fill == null:
		return
	_focus_bar_fill.size.x = _mode_bar_w * clamp(active_t / max(0.001, duration), 0.0, 1.0)


# Swap the mode meter (label, bar colour, pip count/colour) when the equipped Shift
# mode changes, then reseed it from the player's current charge + duration values.
func _on_mode_changed_ui(mode: int) -> void:
	_ui_active_mode = mode
	if _mode_label == null or _focus_bar_fill == null:
		return
	var meta = _MODE_META.get(mode, _MODE_META[0])   # default to FOCUS
	var col: Color = meta[1]
	_mode_label.text = String(meta[0])
	_mode_label.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 0.9))
	# Bar + pips stay fixed purple — only the label carries the mode colour.
	_focus_bar_fill.color = _MODE_METER_PURPLE
	_mode_pip_color = _MODE_METER_PURPLE
	# Rebuild pips for this mode's charge count, then reseed live values.
	_prev_mode_charges = -1
	var p = _player_ref
	if p != null and "mode_charges_max" in p:
		_rebuild_mode_pips(int(p.mode_charges_max))
		if "mode_charges" in p:
			_on_mode_charges_changed(int(p.mode_charges), int(p.mode_charges_max))
	if p != null and "mode_active_t" in p and "mode_duration" in p:
		_on_mode_duration_changed(float(p.mode_active_t), float(p.mode_duration))


func _on_player_damaged(_amount: int) -> void:
	if _warn_light_container != null and is_instance_valid(_warn_light_container):
		HudLight.pip_flash(_warn_light_container)


func _refresh_weapon_names() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	# PRI row: the equipped PRIMARY gun (cannon_pool[1]) — the Q-swap target,
	# shown whether or not it's currently the firing weapon (two-slot model 2026-06-11).
	if _pri_name_lbl:
		var primary = run.get_primary_cannon() if run.has_method("get_primary_cannon") else null
		if primary != null and "display_name" in primary:
			_pri_name_lbl.text = String(primary.display_name)
		else:
			_pri_name_lbl.text = "—"
	if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
		var p_sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
		if p_sec != null and "display_name" in p_sec and _sec_name_lbl:
			_sec_name_lbl.text = String(p_sec.display_name)
		# SUP row: the equipped super (DEVICE_BAY_1 = Smart Bomb, etc.). Was
		# never populated, so the name read blank even when a super was
		# equipped (Roman: Smart Bomb missing its name in the armament bar).
		var p_sup = run.loadout_snapshot.get(Slots.SlotType.DEVICE_BAY_1, null)
		if _sup_name_lbl:
			if p_sup != null and "display_name" in p_sup:
				_sup_name_lbl.text = String(p_sup.display_name)
			else:
				_sup_name_lbl.text = "—"


func _on_ammo_changed(value: int) -> void:
	if _pri_ammo_lbl == null:
		return
	# Always show the count, incl. 0 (Roman). -1 = infinite (Energy Blaster) → blank: the pixel font
	# has no ∞ glyph (rendered as a missing-char box), and a non-depleting weapon reads fine with no
	# number (Roman 2026-06-10 glyph fix). Log: if you want an explicit infinite indicator say so.
	_pri_ammo_lbl.text = "" if value < 0 else "%d" % value
	_refresh_weapon_names()


func _on_secondary_ammo_changed(value: int, _maximum: int) -> void:
	_sec_ammo = value
	# While a Combat Drones deploy is live the slot shows the countdown timer;
	# don't let the ammo signal overwrite it. The ammo count re-renders when
	# the timer ends (_on_secondary_timer_changed active=false).
	if _sec_timer_active:
		return
	if _sec_ammo_lbl:
		# Always show the count, incl. 0. -1 = infinite/none → blank (no ∞ glyph in the pixel font).
		_sec_ammo_lbl.text = "" if value < 0 else "%d" % value


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
	_waves_remaining = 0


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
	if player.has_signal("mode_charges_changed") and player.mode_charges_changed.is_connected(_on_mode_charges_changed):
		player.mode_charges_changed.disconnect(_on_mode_charges_changed)
	if player.has_signal("mode_duration_changed") and player.mode_duration_changed.is_connected(_on_mode_duration_changed):
		player.mode_duration_changed.disconnect(_on_mode_duration_changed)
	if player.has_signal("mode_changed") and player.mode_changed.is_connected(_on_mode_changed_ui):
		player.mode_changed.disconnect(_on_mode_changed_ui)
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


func _process(delta: float) -> void:
	# DANGER annunciator pulses at the warning-shader rate while hull is critical
	# (frame 2), holding full alpha otherwise (Roman 2026-06-11).
	if _ann != null and is_instance_valid(_ann):
		if _ann.frame == 2:
			_ann_pulse_t += delta
			_ann.self_modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_ann_pulse_t * ANN_DANGER_PULSE_HZ * TAU))
		else:
			_ann.self_modulate.a = 1.0
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		# "blaster" light = the active primary is an infinite blaster; "pri" light
		# = a metered cannon is active (single-active model 2026-06-11).
		var blaster_active: bool = run.is_active_cannon_infinite()

		if _light_blaster:
			_light_blaster.frame = 1 if blaster_active else 0

		# _light_pri: on when a non-blaster cannon is selected
		if _light_pri:
			_light_pri.frame = 0 if blaster_active else 1
			# Ammo-state tell on the active replacement primary (autolaser/rotary/etc.):
			#   no ammo      → darkened
			#   regenerating → flashing (below max + has a recharge rate)
			#   otherwise    → steady
			var lit := Color(1, 1, 1, 1)
			if not blaster_active and _player_ref != null and is_instance_valid(_player_ref):
				var p_ammo: int = int(_player_ref.ammo) if "ammo" in _player_ref else -1
				var p_max: int = int(_player_ref.ammo_max) if "ammo_max" in _player_ref else 0
				var p_rech: float = float(_player_ref.ammo_recharge_rate) if "ammo_recharge_rate" in _player_ref else 0.0
				if p_ammo == 0:
					lit = Color(1, 1, 1, 0.22)              # darkened — out of ammo
				elif p_ammo > 0 and p_ammo < p_max and p_rech > 0.0:
					_wlight_t += delta
					var a: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_wlight_t * WLIGHT_FLASH_HZ * TAU))
					lit = Color(1, 1, 1, a)                 # flashing — regenerating
			_light_pri.self_modulate = lit

		var sec_ok: bool = false
		if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
			var sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
			sec_ok = sec != null and (_sec_ammo > 0 if _sec_ammo >= 0 else false)
		if _light_sec:
			_light_sec.frame = 1 if sec_ok else 0

		if _light_sup:
			_light_sup.frame = 1 if _super_charge_count > 0 else 0

	if _blaster_status_lbl:
		var blaster_on: bool = has_node("/root/Run") and get_node("/root/Run").is_active_cannon_infinite()
		_blaster_status_lbl.text = "STANDBY" if not blaster_on else ("FIRING" if Input.is_action_pressed("shoot") else "READY")

	# --- Warn-light stack ---
	# Arriving (old BLINK state: enemies offscreen/recycling or wave incoming) →
	# downward chase across all 7 lights. Otherwise the stack settles into the
	# wave indicator: bottom N lights lit, N = waves remaining.
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var on_screen: int = _enemies_on_screen() if enemy_count > 0 else 0
	var arriving: bool = on_screen == 0 and (enemy_count > 0 or _wave_spawning)

	var n: int = _warn_lights.size()
	if arriving and n > 0:
		_warn_chase_t += delta
		if _warn_chase_t >= WARN_CHASE_STEP_S:
			_warn_chase_t = fmod(_warn_chase_t, WARN_CHASE_STEP_S)
			_warn_chase_step = (_warn_chase_step + 1) % n
		for i in n:
			var lit: bool = posmod(i - _warn_chase_step, n) < WARN_CHASE_BAND
			_set_warn_light(i, lit)
	else:
		_warn_chase_t = 0.0
		_warn_chase_step = 0
		for i in n:
			_set_warn_light(i, i >= n - _waves_remaining)


func _set_warn_light(i: int, lit: bool) -> void:
	var light := _warn_lights[i] as Sprite2D
	if light == null or not is_instance_valid(light):
		return
	light.frame = 1 if lit else 0
	light.modulate = COLOR_AMBER if lit else COLOR_WARN_OFF
