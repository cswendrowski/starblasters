# Marker-Driven Live HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the BoxContainer-layout HUD in `scripts/ui.gd` with a fully marker-driven HUD that reads element positions from `Marker2D` nodes in `scenes/ui.tscn`.

**Architecture:** All HUD elements are built as children of a plain `Control` node (`_hud_root_node`) added to the `UI` MarginContainer. Using a `Control` (not a nested `CanvasLayer`) preserves `modulate` propagation so `HologramHUD`'s flicker_in/out and damage fade effects work correctly. `_mpos(path, fallback)` reads `Marker2D.global_position` with a hardcoded fallback, following the same pattern as `sector_map_v3.gd`.

**Tech Stack:** Godot 4.6 GDScript, existing textures at `res://graphics/ui/`, `HologramHUD` unchanged.

---

## File Map

| File | Change |
|---|---|
| `scenes/ui.tscn` | Append 6 new `Marker2D` nodes |
| `scripts/ui.gd` | Complete rewrite — keep public API signatures, gut internals |

---

### Task 1: Add new Marker2D nodes to ui.tscn

**Files:**
- Modify: `scenes/ui.tscn`

The six new markers cover `focus_label`, `focus_bar`, and `weapon_key` on each of the four weapon rows. Positions are approximate; Roman adjusts manually.

- [ ] **Step 1: Append the six marker nodes to ui.tscn**

Open `scenes/ui.tscn` and append the following lines at the very end of the file (after the last existing `[node ...]` block):

```
[node name="focus_label" type="Marker2D" parent="." unique_id=2000000001]
position = Vector2(8, 247)

[node name="focus_bar" type="Marker2D" parent="." unique_id=2000000002]
position = Vector2(8, 256)

[node name="weapon_key" type="Marker2D" parent="pri_blaster_label" unique_id=2000000003]
position = Vector2(-32, 0)

[node name="weapon_key" type="Marker2D" parent="pri_blaster_label/pri_weapon_label" unique_id=2000000004]
position = Vector2(-32, 0)

[node name="weapon_key" type="Marker2D" parent="pri_blaster_label/sec_weapon_label" unique_id=2000000005]
position = Vector2(-32, 0)

[node name="weapon_key" type="Marker2D" parent="pri_blaster_label/sup_weapon_label" unique_id=2000000006]
position = Vector2(-32, 0)
```

- [ ] **Step 2: Verify parse**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2
```

Expected: exits cleanly (exit code 0), no `E 0:00:00` parse errors in output.

- [ ] **Step 3: Commit**

```powershell
git add scenes/ui.tscn
git commit -m "hud: add focus_label, focus_bar, weapon_key markers to ui.tscn"
```

---

### Task 2: Rewrite scripts/ui.gd

**Files:**
- Modify: `scripts/ui.gd`

Replace the entire contents of `scripts/ui.gd` with the implementation below. Key design decisions:
- All elements added to `_hud_root_node` (a plain `Control` child of `self`) so `HologramHUD`'s modulate tweens propagate correctly.
- MarginContainer margins zeroed so `_hud_root_node` lands at (0,0) in viewport space, keeping marker positions accurate.
- `HologramHUD` kept unchanged — `_hud_root = self` still works because it walks up the parent chain for the CanvasLayer and tweens `self.modulate`.
- `update_wave()` kept as no-op (wired in main.tscn).
- `_install_ammo_label()` kept as no-op (called by external code).
- SUP weapon name stays "—" — `SlotTypes` has no `HARDPOINT_NOSE`.

- [ ] **Step 1: Replace scripts/ui.gd with the new implementation**

```gdscript
extends MarginContainer

const HologramHUDCls = preload("res://scripts/hologram_hud.gd")

const DOT_TEX   := "res://graphics/ui/hud_dot_light.png"
const ANN_TEX   := "res://graphics/ui/hud_annunciator_danger.png"
const FONT_PATH := "res://graphics/fonts/PixelOperator.ttf"

const DOT_W      := 8
const DOT_H      := 8
const DOT_STEP   := 10
const SHIELD_ROWS := 3
const SHIELD_COLS := 10
const HULL_COLS   := 10

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
var _threat_blink_tween: Tween = null

var _focus_bar_fill: ColorRect = null

var _player_ref = null
var _wave_spawning: bool = false
var _sec_ammo: int = -1
var _super_charge_count: int = 0

var hologram_hud = null


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
	l.add_theme_font_override("font", load(FONT_PATH) as Font)
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

	# Hull annunciator — always shows the danger frame
	var ann := Sprite2D.new()
	ann.texture = load(ANN_TEX) as Texture2D
	ann.hframes = 2
	ann.centered = false
	ann.frame = 1
	ann.position = _mpos("hull_annuciator", Vector2(16, 104))
	c.add_child(ann)

	# Shield pip rows (3 × 10)
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
			c.add_child(pip)
			row_arr.append(pip)
		_shield_pips.append(row_arr)

	# Hull pip row (10)
	var hull_origin := _mpos("hull_label/hull_pip_row_1", Vector2(16, 88))
	_hull_pips.clear()
	for col_i in HULL_COLS:
		var pip := _make_dot(hull_origin + Vector2(col_i * DOT_STEP, 0), COLOR_HULL)
		c.add_child(pip)
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
	var filled := roundi(float(value) / max(float(max_value), 1.0) * HULL_COLS)
	for i in _hull_pips.size():
		(_hull_pips[i] as Sprite2D).frame = 1 if i < filled else 0


func update_shield(max_value, value) -> void:
	var total := SHIELD_ROWS * SHIELD_COLS
	var filled := roundi(float(value) / max(float(max_value), 1.0) * total)
	for row_i in _shield_pips.size():
		var row: Array = _shield_pips[row_i]
		for col_i in row.size():
			(row[col_i] as Sprite2D).frame = 1 if (row_i * SHIELD_COLS + col_i) < filled else 0


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
	if player.has_signal("super_charges_changed") and not player.super_charges_changed.is_connected(_on_super_charges_changed):
		player.super_charges_changed.connect(_on_super_charges_changed)
	if player.has_signal("focus_charge_changed") and not player.focus_charge_changed.is_connected(_on_focus_charge_changed):
		player.focus_charge_changed.connect(_on_focus_charge_changed)

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
	const BAR_W := 48
	const BAR_H := 4
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
	_focus_bar_fill.size.x = 48.0 * clamp(charge / max(1.0, max_charge), 0.0, 1.0)


func _refresh_weapon_names() -> void:
	const Slots = preload("res://scripts/weapons/SlotTypes.gd")
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
	var blaster_active: bool = has_node("/root/Run") and int(get_node("/root/Run").active_cannon_idx) == 0
	_pri_ammo_lbl.text = "" if blaster_active else "%d" % value
	_refresh_weapon_names()


func _on_secondary_ammo_changed(value: int, _maximum: int) -> void:
	_sec_ammo = value
	if _sec_ammo_lbl:
		_sec_ammo_lbl.text = "%d" % value if value >= 0 else ""


func _on_super_charges_changed(value: int, _maximum: int) -> void:
	_super_charge_count = value
	if _sup_ammo_lbl:
		_sup_ammo_lbl.text = "|".repeat(value) if value > 0 else ""


func _on_wave_started_threat(_idx, _total, _silent, _text) -> void:
	_wave_spawning = true
	_set_threat_blink(true)


func _on_level_cleared_threat() -> void:
	_wave_spawning = false


func _set_threat_blink(on: bool) -> void:
	if on:
		if _threat_blink_tween != null and _threat_blink_tween.is_valid():
			return
		if _threat_light == null:
			return
		_threat_light.frame = 1
		_threat_blink_tween = create_tween().set_loops()
		_threat_blink_tween.tween_property(_threat_light, "modulate:a", 0.1, 0.35)
		_threat_blink_tween.tween_property(_threat_light, "modulate:a", 1.0, 0.35)
	else:
		if _threat_blink_tween != null and _threat_blink_tween.is_valid():
			_threat_blink_tween.kill()
		_threat_blink_tween = null
		if _threat_light:
			_threat_light.modulate.a = 1.0


# ---------------------------------------------------------------------------
# Per-frame logic
# ---------------------------------------------------------------------------

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
	const Slots = preload("res://scripts/weapons/SlotTypes.gd")

	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		var blaster_active: bool = int(run.active_cannon_idx) == 0

		if _light_blaster:
			_light_blaster.frame = 1 if blaster_active else 0

		var pri_ok: bool = false
		if run.has_method("get_active_cannon"):
			var ac = run.get_active_cannon()
			if ac != null:
				pri_ok = blaster_active or int(ac.current_ammo if "current_ammo" in ac else 0) > 0
		if _light_pri:
			_light_pri.frame = 1 if pri_ok else 0

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

	if _fire_light and _player_ref != null and is_instance_valid(_player_ref):
		var pct: float = float(_player_ref.hull) / max(float(_player_ref.max_hull), 1.0)
		_fire_light.frame = 1 if pct <= 0.5 and int(_player_ref.hull) > 0 else 0

	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	if _threat_light:
		if enemy_count > 0:
			if _threat_blink_tween != null and _threat_blink_tween.is_valid():
				_threat_blink_tween.kill()
				_threat_blink_tween = null
				_wave_spawning = false
			_threat_light.frame = 1
		elif _wave_spawning:
			_set_threat_blink(true)
		else:
			_set_threat_blink(false)
			_threat_light.frame = 0
```

- [ ] **Step 2: Run parse check**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2
```

Expected: exit code 0, no `E 0:00:00` lines referencing `ui.gd`.

- [ ] **Step 3: Commit**

```powershell
git add scripts/ui.gd
git commit -m "hud: rewrite ui.gd as marker-driven HUD, remove BoxContainer layout"
```

---

### Task 3: Smoke test — boot and verify

**Files:** None changed.

- [ ] **Step 1: Run the full parse check**

```powershell
tools/parse_check.ps1
```

Expected: `All N scripts parsed OK.`

- [ ] **Step 2: Check the game boots to main menu without errors**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 5 res://scenes/main_menu.tscn
```

Expected: no `E 0:00:00` errors in output.

- [ ] **Step 3: Run a combat scene headless to check HUD loads**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 8 res://scenes/main.tscn
```

Expected: no errors about missing methods on the UI node (`update_hull`, `update_shield`, `update_score`, `bind_player`, `update_wave`).

- [ ] **Step 4: Push and report**

```powershell
git push
```

Report what rendered visually (if anything observable headlessly) and flag any parse/runtime errors encountered. If errors appear, check whether they reference removed methods (e.g. `hull_warning`, `score_counter`, `wave_label`) and fix those call sites in `main.gd` or wherever they originate.
