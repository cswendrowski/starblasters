**✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: HudLight shipped (scripts/hud/hud_light.gd).
Do not cite as a to-do.

# HUD Light Patterns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable `HudLight` static class with four animation patterns (STEADY, BLINK, PULSE, FLICKER) and two one-shot effects (hit_flash, pip_flash), then wire them into the HUD's threat light, fire light, and pip rows.

**Architecture:** `scripts/hud_light.gd` is a static class owning a Dictionary of active Tweens keyed by node instance ID. `scripts/ui.gd` gains pip container nodes (enabling single-tween pip-row effects), imports HudLight, and replaces ad-hoc tween code with HudLight calls. Threat light state is now tracked via a local int (`_threat_state`) so `_process()` only re-applies a pattern when state actually changes.

**Tech Stack:** Godot 4.6 GDScript, existing `hud_dot_light.png` dot sprites, Godot Tween API.

---

## File Map

| File | Change |
|---|---|
| `scripts/hud_light.gd` | **Create** — static class with Pattern enum + apply/stop/hit_flash/pip_flash |
| `scripts/ui.gd` | **Modify** — pip containers, HudLight integration, remove ad-hoc tweens |

---

### Task 1: Create scripts/hud_light.gd

**Files:**
- Create: `scripts/hud_light.gd`

- [ ] **Step 1: Write the file**

```gdscript
extends RefCounted
class_name HudLight

enum Pattern { STEADY, BLINK, PULSE, FLICKER }

# Keyed by node.get_instance_id() -> Tween
static var _pattern_tweens: Dictionary = {}


static func apply(node: CanvasItem, pattern: Pattern) -> void:
	stop(node)
	if not is_instance_valid(node):
		return
	match pattern:
		Pattern.STEADY:
			node.modulate.a = 1.0
		Pattern.BLINK:
			var t := node.create_tween().set_loops()
			t.tween_property(node, "modulate:a", 1.0, 0.0)
			t.tween_interval(1.0)
			t.tween_property(node, "modulate:a", 0.05, 0.0)
			t.tween_interval(1.0)
			_pattern_tweens[node.get_instance_id()] = t
		Pattern.PULSE:
			var t := node.create_tween().set_loops()
			t.tween_property(node, "modulate:a", 0.2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.tween_property(node, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_pattern_tweens[node.get_instance_id()] = t
		Pattern.FLICKER:
			var rng := RandomNumberGenerator.new()
			rng.seed = node.get_instance_id()
			var t := node.create_tween().set_loops()
			for _i in 16:
				var alpha: float = 1.0 if rng.randf() > 0.3 else rng.randf_range(0.05, 0.4)
				var dur: float = rng.randf_range(0.04, 0.18)
				t.tween_property(node, "modulate:a", alpha, dur)
			_pattern_tweens[node.get_instance_id()] = t


static func stop(node: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _pattern_tweens.has(id):
		var t: Tween = _pattern_tweens[id]
		if t != null and t.is_valid():
			t.kill()
		_pattern_tweens.erase(id)
	node.modulate.a = 1.0


static func hit_flash(node: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	var base_color := node.modulate
	var t := node.create_tween()
	# Instant white-bright flash
	t.tween_callback(func(): node.modulate = Color(1.5, 1.5, 1.5, 1.0))
	# Fade back to base color
	t.tween_property(node, "modulate", base_color, 0.08).set_trans(Tween.TRANS_SINE)
	# Rapid double flicker
	t.tween_property(node, "modulate:a", 0.05, 0.06)
	t.tween_property(node, "modulate:a", 1.0, 0.06)
	t.tween_property(node, "modulate:a", 0.05, 0.06)
	t.tween_property(node, "modulate:a", 1.0, 0.08)


static func pip_flash(container: CanvasItem) -> void:
	if not is_instance_valid(container):
		return
	var t := container.create_tween()
	t.tween_property(container, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.03)
	t.tween_property(container, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
```

- [ ] **Step 2: Parse check**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2
```

Expected: exit 0, no `E 0:00:00` errors.

- [ ] **Step 3: Commit**

```powershell
git add scripts/hud_light.gd
git commit -m "hud: add HudLight static class with STEADY/BLINK/PULSE/FLICKER patterns"
```

---

### Task 2: Add pip containers to ui.gd _install_hud()

**Files:**
- Modify: `scripts/ui.gd`

This task adds two `Control` container nodes that wrap the shield and hull pip Sprite2Ds. Containers use `PRESET_FULL_RECT` so they sit at (0,0) and pip absolute positions are unchanged. This enables single-tween pip-row effects in later tasks.

- [ ] **Step 1: Add container member variables**

After line 31 (`var _hull_pips: Array = []`), add:

```gdscript
var _shield_pip_container: Control = null
var _hull_pip_container: Control = null
```

- [ ] **Step 2: Add prev-value tracking variables**

After the `_color_hull_off` declaration (line 62), add:

```gdscript
var _prev_hull: int = -1
var _prev_shield: int = -1
var _hull_crit: bool = false
var _threat_state: int = 0  # 0=OFF 1=BLINK 2=STEADY
```

- [ ] **Step 3: Replace pip construction in _install_hud() to use containers**

In `_install_hud()`, replace the shield pip block (lines 145–158) and hull pip block (lines 160–166) with:

```gdscript
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
```

- [ ] **Step 4: Parse check**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2
```

Expected: exit 0, no errors.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ui.gd
git commit -m "hud: wrap shield/hull pips in container nodes for group effects"
```

---

### Task 3: Integrate HudLight into ui.gd

**Files:**
- Modify: `scripts/ui.gd`

This task wires HudLight into the threat light, fire light, pip flash, and indicator hit flash. It also removes the now-redundant `_set_threat_blink()` / `_threat_blink_tween` code.

- [ ] **Step 1: Add HudLight preload at top of file**

After line 3 (`const HologramHUDCls = preload(...)`), add:

```gdscript
const HudLight = preload("res://scripts/hud_light.gd")
```

- [ ] **Step 2: Remove _threat_blink_tween member variable**

Delete line 48:
```gdscript
var _threat_blink_tween: Tween = null
```

- [ ] **Step 3: Rewrite update_hull() with pip flash, critical flicker, and prev tracking**

Replace the current `update_hull()` (lines 223–229) with:

```gdscript
func update_hull(max_value, value) -> void:
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
	var crit := float(value) / max(float(max_value), 1.0) <= 0.5 and int(value) > 0
	if crit != _hull_crit:
		_hull_crit = crit
		if _fire_light != null:
			if crit:
				_fire_light.frame = 1
				HudLight.apply(_fire_light, HudLight.Pattern.FLICKER)
			else:
				HudLight.stop(_fire_light)
				_fire_light.frame = 0
```

- [ ] **Step 4: Rewrite update_shield() with pip flash**

Replace `update_shield()` (lines 232–241) with:

```gdscript
func update_shield(max_value, value) -> void:
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
```

- [ ] **Step 5: Add damaged signal connection in bind_player()**

In `bind_player()`, after the `focus_charge_changed` connection block (after line 286), add:

```gdscript
	if player.has_signal("damaged") and not player.damaged.is_connected(_on_player_damaged):
		player.damaged.connect(_on_player_damaged)
```

- [ ] **Step 6: Add damaged disconnect in _disconnect_player_signals()**

In `_disconnect_player_signals()`, after the `focus_charge_changed` block (after line 418), add:

```gdscript
	if player.has_signal("damaged") and player.damaged.is_connected(_on_player_damaged):
		player.damaged.disconnect(_on_player_damaged)
```

- [ ] **Step 7: Add _on_player_damaged handler**

After `_on_level_cleared_threat()` and before `_set_threat_blink()`, add:

```gdscript
func _on_player_damaged(_amount: int) -> void:
	if _fire_light != null:
		HudLight.hit_flash(_fire_light)
	if _threat_light != null:
		HudLight.hit_flash(_threat_light)
```

- [ ] **Step 8: Rewrite threat light handling in _process() — replace _set_threat_blink calls**

In `_process()`, replace the entire threat light block (lines 470–482):

```gdscript
	# --- Threat light (state-tracked to avoid restarting tween every frame) ---
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var new_threat: int = 0  # OFF
	if enemy_count > 0:
		new_threat = 2  # STEADY
	elif _wave_spawning:
		new_threat = 1  # BLINK

	if new_threat != _threat_state:
		_threat_state = new_threat
		if _threat_light != null:
			match _threat_state:
				2:  # STEADY
					_wave_spawning = false
					_threat_light.frame = 1
					HudLight.apply(_threat_light, HudLight.Pattern.STEADY)
				1:  # BLINK
					_threat_light.frame = 1
					HudLight.apply(_threat_light, HudLight.Pattern.BLINK)
				0:  # OFF
					HudLight.stop(_threat_light)
					_threat_light.frame = 0
```

- [ ] **Step 9: Remove fire_light block from _process() — now managed by update_hull()**

Delete these lines from `_process()` (currently lines 466–468):

```gdscript
	if _fire_light and _player_ref != null and is_instance_valid(_player_ref):
		var pct: float = float(_player_ref.hull) / max(float(_player_ref.max_hull), 1.0)
		_fire_light.frame = 1 if pct <= 0.5 and int(_player_ref.hull) > 0 else 0
```

- [ ] **Step 10: Remove _set_threat_blink() and simplify wave signal handlers**

Delete the entire `_set_threat_blink()` function (lines 387–402).

Replace `_on_wave_started_threat()` (lines 378–380) with:

```gdscript
func _on_wave_started_threat(_idx, _total, _silent, _text) -> void:
	_wave_spawning = true
```

Replace `_on_level_cleared_threat()` (lines 383–384) with:

```gdscript
func _on_level_cleared_threat() -> void:
	_wave_spawning = false
```

- [ ] **Step 11: Parse check**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2
```

Expected: exit 0, no errors referencing `ui.gd` or `hud_light.gd`.

- [ ] **Step 12: Commit**

```powershell
git add scripts/ui.gd
git commit -m "hud: integrate HudLight patterns — threat blink, fire flicker, pip flash, hit flash"
```

---

### Task 4: Smoke test and push

**Files:** None changed.

- [ ] **Step 1: Full parse check**

```powershell
tools/parse_check.ps1
```

Expected: `All N scenes parse-clean.`

- [ ] **Step 2: Headless combat boot**

```powershell
& "C:\Users\Cody\AppData\Local\Godot\versions\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 8 res://scenes/main.tscn
```

Expected: no errors about missing methods, no errors from `hud_light.gd` or `ui.gd`.

- [ ] **Step 3: Push**

```powershell
git push
```

- [ ] **Step 4: Report**

Post to Discord channel `1504953786379010208`:
- What was implemented
- Any issues encountered
- Invite Roman to test in-game (hit flash, threat blink, fire flicker at hull ≤ 50%)
