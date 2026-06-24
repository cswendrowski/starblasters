extends Control

# Enemy Bench (Roman 2026-06-09) — replaces the Shipyard. A variant of the Hangar test bench
# (scripts/hangar.gd) flipped to ENEMIES: spawn a selected enemy in the native 480×270
# SubViewport, watch it cycle through its ELIGIBLE movement patterns (the pattern_eligibility
# matrix), and let it fire at a DUMMY PLAYER you drive with WASD/arrows. The right panel
# sets + SAVES per-enemy weapon settings: firing pattern, aim rule, payload, and death
# explosion. Persists to user://tuners/enemy_bench.json + a Copy-GDScript snippet (tuner
# contract). Esc / Back returns to the dev menu.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const EnemyStrings = preload("res://scripts/strings/enemy_strings.gd")
const PatternEligibility = preload("res://scripts/levels/pattern_eligibility.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const ShieldComponentC = preload("res://scripts/enemies/components/shield_component.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const EnemyTurretScript = preload("res://scripts/enemies/enemy_turret.gd")
const PLAYER_SCENE = preload("res://scenes/player/player.tscn")

const SAVE_PATH := "user://tuners/enemy_bench.json"

# Editor option pools.
const FIRE_PATTERNS := ["SINGLE", "AIMED", "SPREAD", "BURST", "BEAM", "LOB", "BROADSIDE"]
const AIMS := ["STRAIGHT_DOWN", "TOWARD_CENTER", "AT_PLAYER", "FORWARD"]
const PAYLOADS := {
	"Basic": EnemyRoster.BV_Basic, "Spread Pellet": EnemyRoster.BV_SpreadPellet,
	"Aimed Sniper": EnemyRoster.BV_AimedSniper, "Burst Round": EnemyRoster.BV_BurstRound,
	"Plasma Orb": EnemyRoster.BV_PlasmaOrb, "Heavy Slug": EnemyRoster.BV_HeavySlug,
	"Drop Pellet": EnemyRoster.BV_DropPellet,
	"Zealot Ball": EnemyRoster.BV_ZealotBall, "Zealot Bolt": EnemyRoster.BV_ZealotBolt,
	"Zealot Laser": EnemyRoster.BV_ZealotLaser, "Zealot Wave": EnemyRoster.BV_ZealotWave,
	"Privateer Ball": EnemyRoster.BV_PrivBall, "Privateer Bolt": EnemyRoster.BV_PrivBolt,
	"Privateer Laser": EnemyRoster.BV_PrivLaser, "Privateer Wave": EnemyRoster.BV_PrivWave,
}

# Faction filter tabs (Roman 2026-06-12). "All" + the 4 factions + Core (universal chaff) +
# Hazards (mines/asteroid) + Bosses. Group is derived from the scene PATH (folder), not the
# ENEMY_TAGS home, so untagged hazards/bosses bucket cleanly and a universal chaff stays under Core.
# Bosses are excluded from the bench (they don't tune cleanly here — a dedicated boss tuning tool
# is a separate effort). The "Bosses" group is gone and boss scenes are filtered out of the list.
const FACTION_GROUPS := ["All", "Core", "Supremacy", "Privateer", "Corporate", "Zealot", "Hazards"]

# Mounts editor pools. Kind/aim are stored lowercase (the roster dict schema); the *_LABELS are the
# dropdown text. PROJECTILES are launcher payloads (scene paths), offered alongside the BulletVariant
# PAYLOADS in a mount row's payload dropdown.
const MOUNT_KINDS := ["gun", "turret", "launcher", "beam"]
const MOUNT_KIND_LABELS := ["Gun", "Turret", "Launcher", "Beam"]
const MOUNT_AIM_KEYS := ["straight_down", "at_player", "toward_center", "forward"]
const MOUNT_AIM_LABELS := ["Down", "At Player", "To Center", "Forward"]
const PROJECTILES := {
	"Rocket": "res://scenes/projectiles/enemy_rocket.tscn",
	"Rocket Lg": "res://scenes/projectiles/enemy_rocket_large.tscn",
	"Missile": "res://scenes/projectiles/drifting_missile.tscn",
	"Bomblet": "res://scenes/enemies/enemy_bomblet.tscn",
}
# Emitters editor (the reusable EmitterComponent: drop/spawn a payload scene on a trigger — the
# generalized form of the interceptor's missile-drop). Payload names come from EnemyRoster.EMITTABLE.
const EMITTER_TRIGGERS := ["start", "timer", "death"]
const EMITTER_TRIGGER_LABELS := ["Spawn", "Timer", "On Death"]
# Faction → turret graphic for TURRET mounts so they're never invisible. The dome/zealot strips are
# 3-frame recoil; the generic fallback is a 1-frame static turret.
const TURRET_GFX := {
	"Supremacy": {"tex": "res://graphics/enemies/turret_s_dome.png", "hframes": 3, "recoil": 3},
	"Zealot": {"tex": "res://graphics/enemies/zealot-tank-turret.png", "hframes": 3, "recoil": 3},
}
const TURRET_GFX_DEFAULT := {"tex": "res://graphics/enemies/tank_turret.png", "hframes": 1, "recoil": 0}

# Size-class tuner (the "Sizes" tab). Edits EnemyRoster.SIZE_TABLE (the production size→stats table)
# and emits a paste-ready const via Copy GDScript. No in-bench live preview: size stats drive
# wave-spawn scaling (compose_stats), not the bench's direct spawn.
const SIZE_ORDER := ["tiny", "small", "medium", "large", "huge", "giant"]
const SIZE_FIELDS := [
	{"key": "hp", "label": "HP", "min": 1.0, "max": 9999.0, "step": 1.0},
	{"key": "shield_cap", "label": "Shield cap", "min": 0.0, "max": 20.0, "step": 1.0},
	{"key": "bounty", "label": "Bounty", "min": 0.0, "max": 9999.0, "step": 1.0},
	{"key": "speed_mult", "label": "Speed ×", "min": 0.1, "max": 3.0, "step": 0.05},
]
var _size_data: Dictionary = {}   # size -> {hp, shield_cap, bounty, speed_mult} (working draft)

# Locomotion table (locomotion refactor 2026-06-19): per-size chassis kinematics. Tuned in the
# "Locomotion" tab; Copy GDScript → paste into enemy_roster.gd SIZE_LOCOMOTION. Per-enemy speed is
# this base shifted by the entry's `engine` rung offset.
const LOCO_FIELDS := [
	{"key": "base_rung", "label": "Base speed (px/s)", "min": 60.0, "max": 480.0, "step": 60.0},
	{"key": "weight", "label": "Weight", "min": 0.2, "max": 8.0, "step": 0.1},
	{"key": "turn_rate", "label": "Turn (deg/s)", "min": 30.0, "max": 720.0, "step": 10.0},
	{"key": "accel", "label": "Accel (px/s2)", "min": 60.0, "max": 1800.0, "step": 20.0},
]
var _loco_data: Dictionary = {}   # size -> {base_rung, weight, turn_rate, accel} (working draft)

const FS_CAPTION := 15   # filter-toggle font size (only code-built widgets left)
const DUMMY_SPEED := 150.0

var _hd_scope: HdViewportScope = null

# Playspace — nodes authored in enemy_bench.tscn (hand-editable), bound here by unique name.
@onready var _preview_vp: SubViewport = %SubViewport
@onready var _enemy_layer: Node2D = %EnemyLayer
@onready var _dummy: Area2D = %DummyPlayer
@onready var _respawn_timer: Timer = %RespawnTimer
var _current_enemy: Node = null

# Enemy list.
@onready var _list: ItemList = %EnemyList
@onready var _filter_flow: HFlowContainer = %FilterFlow
var _paths: Array = []                # currently-shown (faction-filtered) subset
var _all_paths: Array = []            # complete enemy set, before faction filtering
var _faction_filter: String = "All"
var _selected_path: String = ""

# Pattern cycling.
var _eligible: Array = []      # eligible movement keys for the selected enemy
var _pattern_idx: int = 0
@onready var _pattern_lbl: Label = %PatternLabel

# Editors (all live in the scene's right panel).
@onready var _name_lbl: Label = %NameLabel
@onready var _stats_lbl: Label = %StatsLabel
@onready var _armed_chk: CheckButton = %ArmedCheck
@onready var _fire_dd: OptionButton = %FiringDD
@onready var _aim_dd: OptionButton = %AimDD
@onready var _payload_dd: OptionButton = %PayloadDD
@onready var _explosion_dd: OptionButton = %ExplosionDD
@onready var _recycle_chk: CheckButton = %RecycleCheck
@onready var _recycle_passes_spin: SpinBox = %RecyclePassesSpin
@onready var _recycle_chance_spin: SpinBox = %RecycleChanceSpin
# Stat knobs (live-tuned, persisted, emitted by Copy GDScript).
@onready var _hp_spin: SpinBox = %HpSpin
@onready var _bounty_spin: SpinBox = %BountySpin
@onready var _scale_spin: SpinBox = %ScaleSpin
@onready var _bspeed_spin: SpinBox = %BSpeedSpin
@onready var _bdmg_spin: SpinBox = %BDmgSpin
# Display strings (editable name + codex, persisted + emitted as an enemy_strings entry).
@onready var _name_edit: LineEdit = %NameEdit
@onready var _codex_edit: TextEdit = %CodexEdit
# Mounts editor — extra emitters (gun/turret/launcher/beam) beyond the hull weapon (Mount 0).
@onready var _mounts_list: VBoxContainer = %MountsList
@onready var _add_mount_btn: Button = %AddMountButton
# Emitters editor — EmitterComponents (drop/spawn a payload on a trigger), separate from the weapon mounts.
@onready var _emitters_list: VBoxContainer = %EmittersList
@onready var _add_emitter_btn: Button = %AddEmitterButton
# Per-enemy locomotion knobs (code-built, appended to the Enemy tab; locomotion refactor 2026-06-19):
# engine = rung offset on the size base speed; depth = hold/cross band override ("" = default).
var _engine_spin: SpinBox = null
var _depth_dd: OptionButton = null
const _DEPTH_ITEMS := ["", "high", "mid", "low"]   # OptionButton index 0 = "(default)"
# Template knobs (size + traits drive the derived stats; locomotion refactor 2026-06-19): pick a
# size + tags → HP/bounty/shield + locomotion fill from the size template, then hand-tweak below.
var _size_dd: OptionButton = null
var _tough_chk: CheckBox = null
var _shielded_chk: CheckBox = null
var _omni_chk: CheckBox = null
var _strafe_chk: CheckBox = null
var _retro_chk: CheckBox = null
const _SIZE_OPTS := ["tiny", "small", "medium", "large", "huge", "giant"]

# scene_path -> true if any roster ENTRY declares a non-null "shoot" key. This is production's
# source of truth for "this enemy_core enemy carries a generic Weapon" (the director assigns it
# from the roster; scenes never bake shoot_pattern). Used to DEFAULT the Armed toggle so the bench
# mirrors production: weaponless chaff stays silent, bespoke firers keep only their own bullets.
var _roster_armed: Dictionary = {}

# Working list of mount dicts for the selected enemy (name-based, JSON-friendly):
# {kind, marker, payload(name), aim, fire, count, spread}. Converted to MountSpecs at spawn.
var _mount_dicts: Array = []
# Working list of emitter dicts: {trigger, payload(name), cadence, count, max_emits, band_only}.
# Converted to EmitterComponents at spawn via EnemyRoster.make_emitter_specs.
var _emitter_dicts: Array = []

# Persisted per-scene settings.
var _saved: Dictionary = {}
# True while pushing saved values into the editors — suppresses the value_changed
# respawn storm (SpinBox.value setter emits the signal).
var _loading: bool = false

# Audio mute toggles (bench-local). We flip the Music/SFX bus mute via AudioServer and
# restore the prior state on exit so leaving the bench never leaves the game muted.
var _music_bus_was_muted: bool = false
var _sfx_bus_was_muted: bool = false


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	_setup_playspace()
	_setup_ui()
	_load_saved()
	_setup_size_tab()   # wrap the right panel in Enemy/Sizes tabs (needs _saved for the size draft)
	_load_list()
	if _list.item_count > 0:
		_list.select(0)
		_on_list_select(0)
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_preview_vp, "Enemy Bench")   # guard: catch the corner regression


# ---- Playspace -----------------------------------------------------------
# The SubViewport / Backdrop / dummy / EnemyLayer node tree now lives in enemy_bench.tscn so it's
# hand-editable in the editor. (The recurring "play area in the corner" regression lives in the
# SubViewportContainer's stretch=true + stretch_shrink=4 — those are set on the scene's Preview
# node; HdScreen.verify_native_subviewport above still guards the 480×270 result.) This wires the
# runtime-only bits the scene can't carry.

func _setup_playspace() -> void:
	# HDR-2D parity: match the project's hdr_2d root or additive blends (enemy muzzle flashes /
	# bullet glow) composite in the wrong colour space. (Roman 2026-06-11; docs/godot-patterns.md.)
	_preview_vp.use_hdr_2d = bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))
	# The dummy's CURRENT composed player visual (hull + livery + glow, neutral frame), cloned out
	# of player.tscn, not the retired 16×16 strip. Root sprite named "Sprite2D" so the dummy's
	# take_hit flash (hangar_dummy_target.gd) still finds it. EnemyLayer carries the "bullet_world"
	# group (set in the scene) so bespoke enemy bullets spawn into the preview, not the window corner.
	_dummy.add_child(_make_player_visual())
	_respawn_timer.timeout.connect(_cycle_and_spawn)
	# Snapshot the audio bus mute state so the Mute toggles can be restored on exit.
	_music_bus_was_muted = _bus_muted("Music")
	_sfx_bus_was_muted = _bus_muted("SFX")


# The current composed player ship as a static visual, cloned from player.tscn (hull body +
# livery tint + glow, all on the neutral centre frame). The player scene is instantiated for
# its sprites only — never added to the tree, so player.gd._ready / the loadout never run.
# Returns a Sprite2D named "Sprite2D" (the hull) so the dummy's hit-flash keeps working.
func _make_player_visual() -> Sprite2D:
	var packed := PLAYER_SCENE
	var inst := packed.instantiate()
	var ship := inst.get_node_or_null("Ship") as Sprite2D
	var body := _clone_player_sprite(ship)
	body.name = "Sprite2D"
	if ship != null:
		for child in ship.get_children():
			if child is Sprite2D:
				var c := _clone_player_sprite(child)
				c.name = String(child.name)
				body.add_child(c)
	inst.free()
	return body


# Clone a player Sprite2D preserving the frame strip + shader material (livery tint) +
# transform, so the composed look matches the in-game ship. Falls back to an empty sprite.
func _clone_player_sprite(src: Sprite2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if src == null:
		return sp
	sp.texture = src.texture
	sp.hframes = src.hframes
	sp.vframes = src.vframes
	sp.frame = src.frame
	sp.flip_h = src.flip_h
	sp.flip_v = src.flip_v
	sp.position = src.position
	sp.modulate = src.modulate
	if src.material != null:
		sp.material = src.material.duplicate()
	return sp


# ---- UI wiring -----------------------------------------------------------
# All widgets are authored in enemy_bench.tscn (container-based + edge-anchored, so the
# panels/fields can't fall off-screen at non-16:9 HD aspects). This populates the data-driven
# bits (option pools, faction toggles) and connects the signals.

func _setup_ui() -> void:
	_build_roster_armed()
	_fill_options(_fire_dd, FIRE_PATTERNS)
	_fill_options(_aim_dd, AIMS)
	_fill_options(_payload_dd, PAYLOADS.keys())
	_fill_options(_explosion_dd, ExplosionFx.variant_names())

	# Faction filter toggles — data-driven (FACTION_GROUPS) into the scene's FilterFlow. They sit
	# in the left VBox ABOVE the list, so the wrapping row pushes the list down instead of overrunning it.
	var grp := ButtonGroup.new()
	for g in FACTION_GROUPS:
		var b := Button.new()
		b.text = g
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", FS_CAPTION)
		if String(g) == _faction_filter:
			b.button_pressed = true
		b.pressed.connect(_on_faction_filter.bind(String(g)))
		_filter_flow.add_child(b)

	# Signals.
	_list.item_selected.connect(_on_list_select)
	# Weapon changes respawn (re-runs start() so BEAM/aim init correctly).
	_fire_dd.item_selected.connect(func(_i): _spawn_current())
	_aim_dd.item_selected.connect(func(_i): _spawn_current())
	_payload_dd.item_selected.connect(func(_i): _spawn_current())
	# Death explosion only matters on death, so apply it live (no respawn).
	_explosion_dd.item_selected.connect(func(_i): _apply_explosion_live())
	# Stat knobs: HP/scale respawn (live from frame 0); bounty/bullet mults apply live.
	_hp_spin.value_changed.connect(func(_v): if not _loading: _spawn_current())
	_bounty_spin.value_changed.connect(func(_v): if not _loading: _apply_stats_live())
	_scale_spin.value_changed.connect(func(_v): if not _loading: _spawn_current())
	_bspeed_spin.value_changed.connect(func(_v): if not _loading: _apply_stats_live())
	_bdmg_spin.value_changed.connect(func(_v): if not _loading: _apply_stats_live())
	_name_edit.text_changed.connect(_on_name_edited)
	# Armed toggle: gates whether the bench assigns a generic Weapon at all. Respawns so the
	# enemy is rebuilt with (or without) shoot_pattern from frame 0.
	_armed_chk.toggled.connect(func(_v):
		_refresh_weapon_editor_state()
		if not _loading: _spawn_current())
	_recycle_chk.toggled.connect(func(_v): _apply_recycle_live())
	_recycle_passes_spin.value_changed.connect(func(_v): _apply_recycle_live())
	_recycle_chance_spin.value_changed.connect(func(_v): _apply_recycle_live())
	(%NextPatternButton as Button).pressed.connect(_cycle_and_spawn)
	(%SaveButton as Button).pressed.connect(_on_save)
	(%CopyButton as Button).pressed.connect(_on_copy)
	(%BackButton as Button).pressed.connect(_on_back)
	_add_mount_btn.pressed.connect(_add_mount)
	_add_emitter_btn.pressed.connect(_add_emitter)

	# Music stays muted for dev menus (the Music toggle button was removed 2026-06-20); SFX keeps its
	# toggle. The prior bus state is still restored on exit (_on_back).
	_set_bus_muted("Music", true)
	_wire_mute_toggle(%SfxMute as Button, "SFX", _sfx_bus_was_muted)


func _fill_options(dd: OptionButton, items) -> void:
	dd.clear()
	for it in items:
		dd.add_item(String(it))


# Bind a scene mute Button to its audio bus. Pressed = muted; label flips between
# "<bus>: On" / "<bus> Muted". button_pressed is set BEFORE connecting so binding never
# perturbs the live bus state.
func _wire_mute_toggle(b: Button, bus: String, start_muted: bool) -> void:
	b.button_pressed = start_muted
	b.text = _mute_text(bus, start_muted)
	b.toggled.connect(func(on):
		_set_bus_muted(bus, on)
		b.text = _mute_text(bus, on))


func _mute_text(bus: String, muted: bool) -> String:
	return ("%s Muted" % bus) if muted else ("%s: On" % bus)


func _bus_muted(bus: String) -> bool:
	var idx := AudioServer.get_bus_index(bus)
	return idx >= 0 and AudioServer.is_bus_mute(idx)


func _set_bus_muted(bus: String, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


# ---- Sizes tab -----------------------------------------------------------
# Wraps the right panel in an Enemy/Sizes TabContainer at runtime (no scene edit): the existing
# enemy editor becomes the "Enemy" tab; the "Sizes" tab tunes the production size table.

func _setup_size_tab() -> void:
	var scroll := get_node_or_null("UI/RightPanel/RightScroll") as Control
	if scroll == null:
		return
	_setup_enemy_template_knobs(scroll)
	_setup_enemy_loco_knobs(scroll)
	var panel := scroll.get_parent()
	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", FS_CAPTION)
	panel.remove_child(scroll)
	panel.add_child(tabs)
	tabs.add_child(scroll)
	var sizes_scroll := ScrollContainer.new()
	sizes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sizes_scroll)
	tabs.set_tab_title(0, "Enemy")
	tabs.set_tab_title(1, "Sizes")
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sizes_scroll.add_child(vb)
	_build_size_editor(vb)
	# Locomotion tab (locomotion refactor 2026-06-19): the per-size chassis kinematics.
	var loco_scroll := ScrollContainer.new()
	loco_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(loco_scroll)
	tabs.set_tab_title(2, "Locomotion")
	var lvb := VBoxContainer.new()
	lvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lvb.add_theme_constant_override("separation", 6)
	loco_scroll.add_child(lvb)
	_build_loco_editor(lvb)
	# Keep the Enemy tab inside the gutter: every label wraps and every dropdown clips/sizes to its
	# selection, so no leaf can demand more width than the gutter and push the panel into the play band.
	_tighten_panel(scroll)


# Stop the Enemy tab from inflating its min-width past the gutter. Two width drivers exist in a
# narrow side panel: long single-line Labels (force their full text width) and OptionButtons (force
# their longest item's width). Wrap the labels; size dropdowns to the selection (fit_to_longest_item
# off) + clip + expand-fill. Re-applied after mount/emitter rebuilds add rows. (The static .tscn
# captions are covered here too, so they don't each need an autowrap flag in the scene.)
func _tighten_panel(root_ctl: Control) -> void:
	if root_ctl == null:
		return
	for n in root_ctl.find_children("*", "OptionButton", true, false):
		var ob := n as OptionButton
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in root_ctl.find_children("*", "Label", true, false):
		(n as Label).autowrap_mode = TextServer.AUTOWRAP_WORD


func _build_loco_editor(vb: VBoxContainer) -> void:
	vb.add_child(_mk_label("Locomotion (size → chassis)", 18, Color(0.62, 0.82, 1, 1)))
	var note := _mk_label("Per-size base speed / weight / turn / accel. Speed is a clarity rung; a per-enemy ENGINE offset (on the roster entry) shifts it without changing weight/turn. Tune, then Copy GDScript → paste into enemy_roster.gd SIZE_LOCOMOTION.", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(note)
	_loco_data = _load_loco_data()
	for sz in SIZE_ORDER:
		vb.add_child(HSeparator.new())
		vb.add_child(_mk_label(sz, 16, Color(0.62, 0.82, 1, 1)))
		for f in LOCO_FIELDS:
			vb.add_child(_mk_label(String(f["label"]), FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
			var sb := SpinBox.new()
			sb.min_value = float(f["min"])
			sb.max_value = float(f["max"])
			sb.step = float(f["step"])
			sb.custom_minimum_size = Vector2(0, 30)
			sb.value = float(_loco_data[sz][f["key"]])
			sb.value_changed.connect(_on_loco_changed.bind(String(sz), String(f["key"])))
			vb.add_child(sb)
	vb.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var save := Button.new()
	save.text = "Save Loco"
	save.custom_minimum_size = Vector2(0, 34)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_save_loco)
	row.add_child(save)
	var cp := Button.new()
	cp.text = "Copy GDScript"
	cp.custom_minimum_size = Vector2(0, 34)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp.pressed.connect(_copy_loco)
	row.add_child(cp)


func _load_loco_data() -> Dictionary:
	var saved = _saved.get("_loco_table", {})
	var out := {}
	for sz in SIZE_ORDER:
		var base: Dictionary = EnemyRoster.SIZE_LOCOMOTION.get(sz, {})
		var s: Dictionary = saved.get(sz, {}) if saved is Dictionary else {}
		out[sz] = {
			"base_rung": float(s.get("base_rung", base.get("base_rung", 180.0))),
			"weight": float(s.get("weight", base.get("weight", 1.0))),
			"turn_rate": float(s.get("turn_rate", base.get("turn_rate", 300.0))),
			"accel": float(s.get("accel", base.get("accel", 600.0))),
		}
	return out


func _on_loco_changed(value: float, sz: String, field: String) -> void:
	_loco_data[sz][field] = float(value)


func _save_loco() -> void:
	_saved["_loco_table"] = _loco_data.duplicate(true)
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_saved, "\t"))
		f.close()
	if _pattern_lbl:
		_pattern_lbl.text = "Saved locomotion draft"


func _copy_loco() -> void:
	var txt := "const SIZE_LOCOMOTION := {\n"
	for sz in SIZE_ORDER:
		var d: Dictionary = _loco_data[sz]
		txt += "\t\"%s\": {\"base_rung\": %.0f, \"weight\": %.2f, \"turn_rate\": %.0f, \"accel\": %.0f},\n" % [
			sz, float(d["base_rung"]), float(d["weight"]), float(d["turn_rate"]), float(d["accel"])]
	txt += "}\n"
	DisplayServer.clipboard_set(txt)
	if _pattern_lbl:
		_pattern_lbl.text = "Copied SIZE_LOCOMOTION to clipboard"


# Append a per-enemy TEMPLATE section (size + traits → derived stats) to the Enemy tab's content.
# Picking a size/trait fills HP/bounty (and locomotion/shield via respawn) from the size template;
# the spinboxes below stay the hand-tweak layer. (template-driven stats, 2026-06-19.)
func _setup_enemy_template_knobs(scroll: Control) -> void:
	if scroll == null or scroll.get_child_count() == 0:
		return
	var content := scroll.get_child(0)
	if not (content is Container):
		return
	content.add_child(HSeparator.new())
	content.add_child(_mk_label("Template (size + traits)", 16, Color(0.62, 0.82, 1, 1)))
	content.add_child(_mk_label("Size + traits drive HP / bounty / shield / locomotion from the size template — then hand-tweak the values below.", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	# Caption above a full-width control (the panel's consistent stack pattern) — an inline
	# label-beside-control row gets squished to clipping in this narrow gutter.
	content.add_child(_mk_label("Size", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_size_dd = OptionButton.new()
	for s in _SIZE_OPTS:
		_size_dd.add_item(s)
	_size_dd.custom_minimum_size = Vector2(0, 30)
	_size_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_dd.item_selected.connect(_on_template_changed)
	content.add_child(_size_dd)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	content.add_child(tr)
	_tough_chk = CheckBox.new()
	_tough_chk.text = "tough (x2 HP)"
	_tough_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tough_chk.toggled.connect(func(_p): _on_template_changed(0))
	tr.add_child(_tough_chk)
	_shielded_chk = CheckBox.new()
	_shielded_chk.text = "shielded"
	_shielded_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shielded_chk.toggled.connect(func(_p): _on_template_changed(0))
	tr.add_child(_shielded_chk)
	# Locomotion capability flags (omni/strafe/retro).
	var loco_tr := HBoxContainer.new()
	loco_tr.add_theme_constant_override("separation", 10)
	content.add_child(loco_tr)
	_omni_chk = CheckBox.new()
	_omni_chk.text = "omni"
	_omni_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_omni_chk.toggled.connect(func(_p): _on_template_changed(0))
	loco_tr.add_child(_omni_chk)
	_strafe_chk = CheckBox.new()
	_strafe_chk.text = "strafe"
	_strafe_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strafe_chk.toggled.connect(func(_p): _on_template_changed(0))
	loco_tr.add_child(_strafe_chk)
	_retro_chk = CheckBox.new()
	_retro_chk.text = "retro"
	_retro_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retro_chk.toggled.connect(func(_p): _on_template_changed(0))
	loco_tr.add_child(_retro_chk)


func _on_template_changed(_i: int) -> void:
	if _loading:
		return
	_apply_template_stats()
	_spawn_current()


# Fill HP/bounty from the size+tags template (the lead then hand-tweaks the spinboxes).
func _apply_template_stats() -> void:
	if _size_dd == null:
		return
	var stats: Dictionary = EnemyRoster.compose_stats(_template_entry())
	_loading = true   # suppress the spinbox value_changed respawn storm
	if _hp_spin:
		_hp_spin.value = int(stats["max_health"])
	if _bounty_spin:
		_bounty_spin.value = int(stats["bounty_value"])
	_loading = false


# The current bench size class.
func _bench_size() -> String:
	return String(_SIZE_OPTS[_size_dd.selected]) if (_size_dd != null and _size_dd.selected >= 0) else "medium"


# An entry-shaped dict (size + tags + engine/depth) for compose_stats / resolve_locomotion.
func _template_entry() -> Dictionary:
	var tags: Array = []
	if _tough_chk != null and _tough_chk.button_pressed:
		tags.append("tough")
	if _shielded_chk != null and _shielded_chk.button_pressed:
		tags.append("shielded")
	return {
		"scene": _selected_path, "size": _bench_size(), "tags": tags,
		"engine": int(_engine_spin.value) if _engine_spin != null else 0,
		"depth": _depth_for_selected(),
	}


# Append a per-enemy locomotion section (engine offset + depth band) to the Enemy tab's content,
# so the lead can dial each enemy's speed/depth with a live preview + Copy GDScript → ENTRIES.
func _setup_enemy_loco_knobs(scroll: Control) -> void:
	if scroll == null or scroll.get_child_count() == 0:
		return
	var content := scroll.get_child(0)
	if not (content is Container):
		return
	content.add_child(HSeparator.new())
	content.add_child(_mk_label("Locomotion (this enemy)", 16, Color(0.62, 0.82, 1, 1)))
	content.add_child(_mk_label("Engine = rung offset on the size base speed (+1 = +60 px/s; weight/turn unchanged). Depth = hold/cross band (default = size/identity).", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	# Engine + Depth as two equal columns (caption stacked above each control), so neither label is
	# squished by an expanding control sharing its row — they split the panel 50/50 instead.
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 8)
	content.add_child(er)
	var ecol := VBoxContainer.new()
	ecol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ecol.add_theme_constant_override("separation", 2)
	er.add_child(ecol)
	ecol.add_child(_mk_label("Engine", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_engine_spin = SpinBox.new()
	_engine_spin.min_value = -4.0
	_engine_spin.max_value = 4.0
	_engine_spin.step = 1.0
	_engine_spin.custom_minimum_size = Vector2(0, 30)
	_engine_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_engine_spin.value_changed.connect(_on_loco_knob_changed)
	ecol.add_child(_engine_spin)
	var dcol := VBoxContainer.new()
	dcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dcol.add_theme_constant_override("separation", 2)
	er.add_child(dcol)
	dcol.add_child(_mk_label("Depth", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_depth_dd = OptionButton.new()
	_depth_dd.add_item("(default)")
	_depth_dd.add_item("high")
	_depth_dd.add_item("mid")
	_depth_dd.add_item("low")
	_depth_dd.custom_minimum_size = Vector2(0, 30)
	_depth_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depth_dd.item_selected.connect(_on_loco_depth_changed)
	dcol.add_child(_depth_dd)


func _on_loco_knob_changed(_v: float) -> void:
	if not _loading:
		_spawn_current()


func _on_loco_depth_changed(_i: int) -> void:
	if not _loading:
		_spawn_current()


# The selected depth band ("" when "(default)" is chosen).
func _depth_for_selected() -> String:
	var i: int = _depth_dd.selected if _depth_dd != null else 0
	return _DEPTH_ITEMS[i] if i >= 0 and i < _DEPTH_ITEMS.size() else ""


func _build_size_editor(vb: VBoxContainer) -> void:
	vb.add_child(_mk_label("Size Classes", 18, Color(0.62, 0.82, 1, 1)))
	var note := _mk_label("Production size→stats table. Tune, then Copy GDScript → paste into enemy_roster.gd SIZE_TABLE. (No live bench preview — sizes scale wave spawns, not direct bench spawns.)", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(note)
	_size_data = _load_size_data()
	for sz in SIZE_ORDER:
		vb.add_child(HSeparator.new())
		vb.add_child(_mk_label(sz, 16, Color(0.62, 0.82, 1, 1)))
		for f in SIZE_FIELDS:
			vb.add_child(_mk_label(String(f["label"]), FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
			var sb := SpinBox.new()
			sb.min_value = float(f["min"])
			sb.max_value = float(f["max"])
			sb.step = float(f["step"])
			sb.custom_minimum_size = Vector2(0, 30)
			sb.value = float(_size_data[sz][f["key"]])
			sb.value_changed.connect(_on_size_changed.bind(String(sz), String(f["key"])))
			vb.add_child(sb)
	vb.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var save := Button.new()
	save.text = "Save Sizes"
	save.custom_minimum_size = Vector2(0, 34)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_save_sizes)
	row.add_child(save)
	var cp := Button.new()
	cp.text = "Copy GDScript"
	cp.custom_minimum_size = Vector2(0, 34)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp.pressed.connect(_copy_sizes)
	row.add_child(cp)


# Working size values: a saved draft (bench JSON "_size_table") wins, else the live SIZE_TABLE.
func _load_size_data() -> Dictionary:
	var saved = _saved.get("_size_table", {})
	var out := {}
	for sz in SIZE_ORDER:
		var base: Dictionary = EnemyRoster.SIZE_TABLE.get(sz, {})
		var s: Dictionary = saved.get(sz, {}) if saved is Dictionary else {}
		out[sz] = {
			"hp": int(s.get("hp", base.get("hp", 8))),
			"shield_cap": int(s.get("shield_cap", base.get("shield_cap", 2))),
			"bounty": int(s.get("bounty", base.get("bounty", 15))),
			"speed_mult": float(s.get("speed_mult", base.get("speed_mult", 1.0))),
		}
	return out


func _on_size_changed(value: float, sz: String, field: String) -> void:
	_size_data[sz][field] = float(value) if field == "speed_mult" else int(value)


func _save_sizes() -> void:
	_saved["_size_table"] = _size_data.duplicate(true)
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_saved, "\t"))
		f.close()
	if _pattern_lbl:
		_pattern_lbl.text = "Saved size table draft"


func _copy_sizes() -> void:
	var txt := "const SIZE_TABLE := {\n"
	for sz in SIZE_ORDER:
		var d: Dictionary = _size_data[sz]
		txt += "\t\"%s\": {\"hp\": %d, \"shield_cap\": %d, \"bounty\": %d, \"speed_mult\": %s},\n" % [
			sz, int(d["hp"]), int(d["shield_cap"]), int(d["bounty"]), String("%.2f" % float(d["speed_mult"]))]
	txt += "}\n"
	DisplayServer.clipboard_set(txt)
	if _pattern_lbl:
		_pattern_lbl.text = "Copied SIZE_TABLE to clipboard"


func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Wrap by default: this is a narrow side-gutter panel, so a long caption must wrap rather than
	# force its full text width as the panel's min-width (that pushed the whole panel off the gutter,
	# into the play band). Single-word/short labels are unaffected (they never exceed the width).
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


# ---- List / selection ----------------------------------------------------

func _load_list() -> void:
	# Complete enemy set = the shared full dev roster (curated manifest UNION every faction-tagged
	# enemy), minus bosses (separate boss tuning tool later). Single source so the bench, eligibility
	# editor + Formation Builder all stay in sync (Roman 2026-06-17).
	_all_paths = EnemyManifest.all_enemies(false)
	_rebuild_list(false)


# Re-populate the list from _all_paths, keeping only the active faction group. select_first
# auto-selects the top entry (true on a tab change; false during initial _ready, which selects).
func _rebuild_list(select_first: bool) -> void:
	_paths.clear()
	_list.clear()
	for p in _all_paths:
		if _faction_filter == "All" or _group_of(String(p)) == _faction_filter:
			_paths.append(p)
	for p in _paths:
		_list.add_item(_list_label_for(p), _icon_for(p))
	if select_first and _list.item_count > 0:
		_list.select(0)
		_on_list_select(0)


# The sidebar label for an enemy: its edited/saved name when one exists, else the baked
# display name. Keeps the list in sync with renames done in the right-panel Name field.
func _list_label_for(path: String) -> String:
	var nm := String(_saved.get(path, {}).get("name", ""))
	return nm if nm != "" else EnemyStrings.display_name(path)


# Live rename: as the right-panel Name field changes, keep the big header label AND the
# matching sidebar item in sync (empty falls back to the baked display name). Save persists
# the name so it also survives faction-tab rebuilds (see _list_label_for).
func _on_name_edited(t: String) -> void:
	var shown: String = t if t != "" else EnemyStrings.display_name(_selected_path)
	if _name_lbl:
		_name_lbl.text = shown
	var idx: int = _paths.find(_selected_path)
	if idx >= 0 and idx < _list.item_count:
		_list.set_item_text(idx, shown)


func _on_faction_filter(group: String) -> void:
	_faction_filter = group
	_rebuild_list(true)


# Faction bucket from the scene PATH. Faction-folder wins over the "mine"/"asteroid" keywords so the
# privateer minelayer (a ship that lays mines) stays under Privateer, not Hazards.
func _group_of(path: String) -> String:
	var p := path.to_lower()
	if p.contains("/factions/supremacy/"): return "Supremacy"
	if p.contains("/factions/privateer/"): return "Privateer"
	if p.contains("/factions/corporate/"): return "Corporate"
	if p.contains("/factions/zealot/"): return "Zealot"
	if p.contains("/core/"): return "Core"
	if p.contains("boss"): return "Bosses"
	if p.contains("mine") or p.contains("asteroid") or p.contains("bomblet"): return "Hazards"
	return "Core"


# Mines are contact / cluster hazards — they must never carry a weapon, even though they extend
# enemy_core (which owns the shoot_pattern slot). The minelayer is a ship, not a mine.
func _is_mine(path: String) -> bool:
	var p := path.to_lower()
	return p.contains("mine") and not p.contains("minelayer")


# Index every roster entry whose "shoot" key is non-null → that scene carries a generic Weapon
# in production. (An enemy can have several entries; armed if ANY of them shoots.)
func _build_roster_armed() -> void:
	_roster_armed.clear()
	for e in EnemyRoster.ENTRIES:
		if e.get("shoot", null) != null:
			_roster_armed[String(e.get("scene", ""))] = true


# Default Armed state for a scene: armed iff production arms it (roster "shoot"), never for mines.
# Enemies with no roster entry (bench-only units, bespoke firers) default UNARMED — the bench
# won't force a generic weapon on them; the user opts in via the Armed toggle if designing one.
func _default_armed(path: String) -> bool:
	return _roster_armed.has(path) and not _is_mine(path)


# Enable/disable the weapon editors to match the Armed state. Firing/Aim only matter for a generic
# Weapon, so they grey out when unarmed. Payload stays live (unless a mine) because it also tunes
# mounted turrets (helix) via _apply_payload_to_turrets, which fire independently of shoot_pattern.
func _refresh_weapon_editor_state() -> void:
	var mine := _is_mine(_selected_path)
	if _armed_chk: _armed_chk.disabled = mine
	var armed: bool = _armed_chk != null and _armed_chk.button_pressed and not mine
	if _fire_dd: _fire_dd.disabled = not armed
	if _aim_dd: _aim_dd.disabled = not armed
	if _payload_dd: _payload_dd.disabled = mine


func _icon_for(path: String) -> Texture2D:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var state := ps.get_state()
	# First Sprite2D = the hull (GlowMask is added after it in every enemy scene). Clip the
	# icon to its FIRST frame so the list reads as the codex/summary do — a clean single
	# appearance, not the raw multi-frame strip (issue #2).
	for i in state.get_node_count():
		if state.get_node_type(i) != &"Sprite2D":
			continue
		var tex: Texture2D = null
		var hf := 1
		var vf := 1
		for j in state.get_node_property_count(i):
			var pname := state.get_node_property_name(i, j)
			if pname == &"texture":
				tex = state.get_node_property_value(i, j) as Texture2D
			elif pname == &"hframes":
				hf = int(state.get_node_property_value(i, j))
			elif pname == &"vframes":
				vf = int(state.get_node_property_value(i, j))
		if tex != null:
			return _frame0_atlas(tex, hf, vf)
	return null


# A single-frame view of a sprite-strip texture (frame 0), for clean list icons. A 1×1
# strip is returned as-is; multi-frame strips get an AtlasTexture clipped to the first cell.
func _frame0_atlas(tex: Texture2D, hframes: int, vframes: int) -> Texture2D:
	hframes = maxi(1, hframes)
	vframes = maxi(1, vframes)
	if hframes == 1 and vframes == 1:
		return tex
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, float(tex.get_width()) / float(hframes), float(tex.get_height()) / float(vframes))
	return at


func _on_list_select(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	_selected_path = _paths[idx]
	# Eligible patterns from the matrix (identity-only if unmapped/bespoke).
	_eligible = PatternEligibility.eligible_for(_selected_path)
	if _eligible.is_empty():
		var idk := PatternEligibility.identity_for(_selected_path)
		_eligible = [idk] if idk != "" else ["straight_medium"]
	_pattern_idx = 0
	_load_settings_into_editors()
	_refresh_weapon_editor_state()   # grey out weapon editors when unarmed / a mine
	_spawn_current()


# ---- Spawn + pattern cycling ---------------------------------------------

func _cycle_and_spawn() -> void:
	if not _eligible.is_empty():
		_pattern_idx = (_pattern_idx + 1) % _eligible.size()
	_spawn_current()


func _spawn_current() -> void:
	_respawn_timer.stop()
	_clear_playspace()   # nuke the prior enemy AND its leftover bullets/drops/fx for a clean slate
	if _selected_path == "":
		return
	var ps := load(_selected_path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	var spawn_pos := Vector2(Playfield.CENTER.x, -20)
	# Configure BEFORE add_child + start() so enemy_core._start_with_pattern
	# duplicates the chosen movement and the weapon/explosion are live from frame 0.
	var key := ""
	if not _eligible.is_empty() and "movement" in inst:
		key = String(_eligible[_pattern_idx])
		inst.movement = EnemyRoster.make_movement({"movement": key})
	if "shoot_pattern" in inst:
		# Only ARM the enemy with a generic Weapon when the Armed toggle is on (defaulted from the
		# roster "shoot" key). Otherwise leave shoot_pattern null — which in enemy_core makes every
		# fire gate a no-op, so weaponless enemies stay silent and the movement pattern's fire TIMING
		# has nothing to fire. Mines and bespoke firers (sword/helix) are never generically armed:
		# bespoke ones keep firing via their own script, turrets via the payload path.
		if _armed_chk.button_pressed and not _is_mine(_selected_path):
			inst.shoot_pattern = _build_weapon()
			if "fire_on_phase" in inst:
				inst.fire_on_phase = ""    # use the generic ShootTimer cadence
		else:
			inst.shoot_pattern = null
	if "explosion_variant" in inst:
		inst.explosion_variant = ExplosionFx.variant_names()[_explosion_dd.selected]
	_apply_stats_to(inst)   # HP/scale/etc BEFORE _ready so health = max_health from frame 0
	if "mounts" in inst:
		inst.mounts = EnemyRoster.make_mount_specs(_mount_spec_dicts())   # extra emitters, BEFORE add_child
	if "components" in inst:
		var ems: Array = EnemyRoster.make_emitter_specs(_emitter_spec_dicts())
		if not ems.is_empty():
			inst.components = inst.components + ems   # append droppers/spawners to baked components
	# Shielded trait (template): add a CHARGE ShieldComponent sized to the template for a live preview.
	if _shielded_chk != null and _shielded_chk.button_pressed and "components" in inst:
		var cap: int = int(EnemyRoster.compose_stats(_template_entry()).get("shield_charges", 0))
		if cap > 0:
			var sh = ShieldComponentC.new()
			sh.mode = ShieldComponentC.Mode.CHARGE
			sh.capacity = cap
			sh.regen_interval = 0.0
			inst.components = inst.components + [sh]
	# Locomotion capability flags (omni/strafe/retro).
	if _omni_chk != null and "omni" in inst:
		inst.omni = _omni_chk.button_pressed
	if _strafe_chk != null and "strafe" in inst:
		inst.strafe = _strafe_chk.button_pressed
	if _retro_chk != null and "retro" in inst:
		inst.retro = _retro_chk.button_pressed
	if inst is Node2D:
		(inst as Node2D).position = spawn_pos
	_enemy_layer.add_child(inst)
	_current_enemy = inst
	# start() is what inits the movement pattern (anchor + on_start) — the director's
	# contract. enemy_core._ready does NOT auto-start.
	if inst.has_method("start"):
		inst.start(spawn_pos)
	_apply_payload_to_turrets(inst)   # turret-mounted enemies fire via child turrets, not shoot_pattern
	if _pattern_lbl:
		var n: int = max(1, _eligible.size())
		_pattern_lbl.text = "Pattern: %s  (%d/%d)" % [(key if key != "" else "—"), _pattern_idx + 1, n]
	_refresh_info()


func _build_weapon() -> Weapon:
	var w := Weapon.new()
	w.fire_pattern = _fire_dd.selected
	w.aim = _aim_dd.selected
	w.payload = _selected_payload()
	return w


# The BulletVariant currently picked in the Payload dropdown.
func _selected_payload():
	var pkeys: Array = PAYLOADS.keys()
	var pname: String = String(pkeys[clampi(_payload_dd.selected, 0, pkeys.size() - 1)])
	return PAYLOADS[pname]


# ---- Mounts editor -------------------------------------------------------
# Mounts are extra emitters (gun/turret/launcher/beam) beyond the hull weapon (Mount 0). The working
# list `_mount_dicts` holds JSON-friendly name-based dicts; _mount_spec_dicts() resolves them to the
# roster dict schema (payload name → BulletVariant resource / projectile scene path) that
# EnemyRoster.make_mount_specs() converts into live MountSpecs at spawn.

func _mount_spec_dicts() -> Array:
	var out: Array = []
	for d in _mount_dicts:
		var k: String = String(d.get("kind", "gun"))
		var sd: Dictionary = {
			"kind": k, "marker": String(d.get("marker", "")),
			"aim": String(d.get("aim", "straight_down")),
			"fire_min": float(d.get("fire", 1.5)), "fire_max": float(d.get("fire", 1.5)),
			"count": int(d.get("count", 1)), "spread_deg": float(d.get("spread", 0.0)),
		}
		var pname: String = String(d.get("payload", "Basic"))
		if PAYLOADS.has(pname):
			sd["payload"] = PAYLOADS[pname]
		elif PROJECTILES.has(pname):
			sd["payload_scene"] = PROJECTILES[pname]
		if k == "gun" or k == "launcher":
			# Firing pattern: marker_mode (all/cycle), burst_interval, bullet_speed
			sd["marker_mode"] = String(d.get("marker_mode", "cycle"))
			var burst: float = float(d.get("burst_interval", 0.0))
			if burst > 0.0:
				sd["burst_interval"] = burst
			var bspeed: float = float(d.get("bullet_speed", -1.0))
			if bspeed >= 0.0:
				sd["bullet_speed"] = bspeed
			# Firing conditions (gates + path-phase mode), honoured by MountComponent.
			sd["fire_zone_gated"] = bool(d.get("zone_gated", false))
			sd["fire_only_on_target"] = bool(d.get("nose_gated", false))
			sd["fire_aim_tol_deg"] = float(d.get("aim_tol", 18.0))
			sd["fire_on_phase"] = String(d.get("on_phase", ""))
			var pp_str: String = String(d.get("path_phases", "")).strip_edges()
			if pp_str != "":
				var phases: Array = []
				for tok in pp_str.split(",", false):
					phases.append(String(tok).strip_edges().to_float())
				sd["fire_path_phases"] = phases
				sd["fire_beat_synced"] = bool(d.get("beat_synced", true))
		elif k == "turret":
			# Give the turret a graphic so it's visible — faction dome/tank strip, else a generic
			# 1-frame turret. (The roster→bench conversion drops the texture, so we re-derive it here.)
			var g: Dictionary = TURRET_GFX.get(_group_of(_selected_path), TURRET_GFX_DEFAULT)
			sd["turret_texture"] = g["tex"]
			sd["turret_hframes"] = g["hframes"]
			sd["recoil_frames"] = g["recoil"]
		out.append(sd)
	return out


func _add_mount() -> void:
	_mount_dicts.append({"kind": "gun", "marker": "", "payload": "Basic", "aim": "straight_down", "fire": 1.5, "count": 1, "spread": 0.0, "marker_mode": "cycle", "burst_interval": 0.0, "bullet_speed": -1.0, "zone_gated": false, "nose_gated": false, "aim_tol": 18.0, "path_phases": "", "beat_synced": true, "on_phase": ""})
	_rebuild_mounts_ui()
	_spawn_current()


func _remove_mount(d: Dictionary) -> void:
	_mount_dicts.erase(d)
	_rebuild_mounts_ui()
	_spawn_current()


# Mutate one field of a mount dict (by reference) and respawn for a live preview.
func _set_mount(d: Dictionary, key: String, value) -> void:
	d[key] = value
	_spawn_current()


func _rebuild_mounts_ui() -> void:
	if _mounts_list == null:
		return
	for c in _mounts_list.get_children():
		_mounts_list.remove_child(c)
		c.queue_free()
	for i in _mount_dicts.size():
		_mounts_list.add_child(_make_mount_row(i))
	_tighten_panel(_mounts_list)


func _make_mount_row(idx: int) -> Control:
	var d: Dictionary = _mount_dicts[idx]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var head := HBoxContainer.new()
	var title := _row_lbl("Mount %d" % (idx + 1))
	title.add_theme_color_override("font_color", Color(0.62, 0.82, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var rm := Button.new()
	rm.text = "✕"
	rm.custom_minimum_size = Vector2(34, 26)
	rm.add_theme_font_size_override("font_size", FS_CAPTION)
	rm.pressed.connect(func(): _remove_mount(d))
	head.add_child(rm)
	row.add_child(head)

	var h1 := HBoxContainer.new()
	var kind_dd := _row_dd(MOUNT_KIND_LABELS, MOUNT_KINDS.find(String(d.get("kind", "gun"))))
	kind_dd.item_selected.connect(func(i): _set_mount(d, "kind", MOUNT_KINDS[i]))
	h1.add_child(kind_dd)
	var mopts: Array = _marker_options(_selected_path)
	var cur_mk: String = _marker_label(String(d.get("marker", "")))
	if not mopts.has(cur_mk):
		mopts.append(cur_mk)   # keep a glob like "Turret*" (from a roster mount) selectable
	var mk_dd := _row_dd(mopts, maxi(0, mopts.find(cur_mk)))
	mk_dd.item_selected.connect(func(i): _set_mount(d, "marker", _marker_value(String(mopts[i]))))
	h1.add_child(mk_dd)
	row.add_child(h1)

	var h2 := HBoxContainer.new()
	var pnames: Array = _mount_payload_names()
	var pay_dd := _row_dd(pnames, maxi(0, pnames.find(String(d.get("payload", "Basic")))))
	pay_dd.item_selected.connect(func(i): _set_mount(d, "payload", String(pnames[i])))
	h2.add_child(pay_dd)
	var aim_dd := _row_dd(MOUNT_AIM_LABELS, maxi(0, MOUNT_AIM_KEYS.find(String(d.get("aim", "straight_down")))))
	aim_dd.item_selected.connect(func(i): _set_mount(d, "aim", MOUNT_AIM_KEYS[i]))
	h2.add_child(aim_dd)
	row.add_child(h2)

	var h3 := HBoxContainer.new()
	h3.add_child(_row_lbl("rate"))
	var rate := _row_spin(0.1, 6.0, 0.1, float(d.get("fire", 1.5)))
	rate.value_changed.connect(func(v): _set_mount(d, "fire", float(v)))
	h3.add_child(rate)
	h3.add_child(_row_lbl("count"))
	var cnt := _row_spin(1, 12, 1, float(d.get("count", 1)))
	cnt.value_changed.connect(func(v): _set_mount(d, "count", int(v)))
	h3.add_child(cnt)
	h3.add_child(_row_lbl("spread"))
	var spr := _row_spin(0.0, 90.0, 2.0, float(d.get("spread", 0.0)))
	spr.value_changed.connect(func(v): _set_mount(d, "spread", float(v)))
	h3.add_child(spr)
	row.add_child(h3)

	# Firing pattern controls for gun/launcher mounts only.
	var k: String = String(d.get("kind", "gun"))
	if k == "gun" or k == "launcher":
		var h4 := HBoxContainer.new()
		var sync_labels: Array = ["All", "Cycle"]
		var sync_keys: Array = ["all", "cycle"]
		var cur_mode: String = String(d.get("marker_mode", "cycle"))
		var sync_dd := _row_dd(sync_labels, maxi(0, sync_keys.find(cur_mode)))
		sync_dd.item_selected.connect(func(i): _set_mount(d, "marker_mode", String(sync_keys[i])))
		h4.add_child(sync_dd)
		h4.add_child(_row_lbl("sync"))
		var burst := _row_spin(0.0, 0.5, 0.01, float(d.get("burst_interval", 0.0)))
		burst.value_changed.connect(func(v): _set_mount(d, "burst_interval", float(v)))
		h4.add_child(burst)
		h4.add_child(_row_lbl("burst"))
		var spd := _row_spin(-1.0, 600.0, 10.0, float(d.get("bullet_speed", -1.0)))
		spd.value_changed.connect(func(v): _set_mount(d, "bullet_speed", float(v)))
		h4.add_child(spd)
		h4.add_child(_row_lbl("speed"))
		row.add_child(h4)

		# Firing conditions: zone/nose gates + path-phase mode (mirror the hull shoot).
		var h5 := HBoxContainer.new()
		var zone_chk := CheckBox.new()
		zone_chk.text = "zone"
		zone_chk.button_pressed = bool(d.get("zone_gated", false))
		zone_chk.add_theme_font_size_override("font_size", FS_CAPTION)
		zone_chk.toggled.connect(func(on): _set_mount(d, "zone_gated", on))
		h5.add_child(zone_chk)
		var nose_chk := CheckBox.new()
		nose_chk.text = "nose"
		nose_chk.button_pressed = bool(d.get("nose_gated", false))
		nose_chk.add_theme_font_size_override("font_size", FS_CAPTION)
		nose_chk.toggled.connect(func(on): _set_mount(d, "nose_gated", on))
		h5.add_child(nose_chk)
		h5.add_child(_row_lbl("tol"))
		var tol := _row_spin(2.0, 90.0, 1.0, float(d.get("aim_tol", 18.0)))
		tol.value_changed.connect(func(v): _set_mount(d, "aim_tol", float(v)))
		h5.add_child(tol)
		row.add_child(h5)

		var h6 := HBoxContainer.new()
		h6.add_child(_row_lbl("path"))
		var pp := LineEdit.new()
		pp.placeholder_text = "0.4,0.7"
		pp.text = String(d.get("path_phases", ""))
		pp.custom_minimum_size = Vector2(72, 26)
		pp.add_theme_font_size_override("font_size", FS_CAPTION)
		pp.text_submitted.connect(func(t): _set_mount(d, "path_phases", t))
		pp.focus_exited.connect(func(): _set_mount(d, "path_phases", pp.text))
		h6.add_child(pp)
		var beat_chk := CheckBox.new()
		beat_chk.text = "beat"
		beat_chk.button_pressed = bool(d.get("beat_synced", true))
		beat_chk.add_theme_font_size_override("font_size", FS_CAPTION)
		beat_chk.toggled.connect(func(on): _set_mount(d, "beat_synced", on))
		h6.add_child(beat_chk)
		h6.add_child(_row_lbl("phase"))
		var phase_ed := LineEdit.new()
		phase_ed.placeholder_text = "name"
		phase_ed.text = String(d.get("on_phase", ""))
		phase_ed.custom_minimum_size = Vector2(64, 26)
		phase_ed.add_theme_font_size_override("font_size", FS_CAPTION)
		phase_ed.text_submitted.connect(func(t): _set_mount(d, "on_phase", t))
		phase_ed.focus_exited.connect(func(): _set_mount(d, "on_phase", phase_ed.text))
		h6.add_child(phase_ed)
		row.add_child(h6)

	return row


# ---- Emitters editor -----------------------------------------------------
# Emitters are EmitterComponents — drop/spawn a payload scene on START/TIMER/DEATH, the reusable form of
# the interceptor's missile-drop. `_emitter_dicts` holds JSON-friendly dicts; _emitter_spec_dicts()
# resolves them to the roster "emitters" shape EnemyRoster.make_emitter_specs() builds at spawn.

func _emitter_spec_dicts() -> Array:
	var out: Array = []
	for d in _emitter_dicts:
		var pname: String = String(d.get("payload", "Missile"))
		var sd: Dictionary = {
			"trigger": String(d.get("trigger", "timer")),
			"payload": pname,
			"cadence": float(d.get("cadence", 0.55)),
			"count": int(d.get("count", 1)),
			"max_emits": int(d.get("max_emits", 0)),
			"band_only": bool(d.get("band_only", false)),
		}
		if pname == "Missile":
			sd["sfx"] = "missile"   # the drifting-missile drop carries the launch sound, like the interceptor
		out.append(sd)
	return out


func _add_emitter() -> void:
	_emitter_dicts.append({"trigger": "timer", "payload": "Missile", "cadence": 0.55, "count": 1, "max_emits": 3, "band_only": true})
	_rebuild_emitters_ui()
	_spawn_current()


func _remove_emitter(d: Dictionary) -> void:
	_emitter_dicts.erase(d)
	_rebuild_emitters_ui()
	_spawn_current()


func _set_emitter(d: Dictionary, key: String, value) -> void:
	d[key] = value
	_spawn_current()


func _rebuild_emitters_ui() -> void:
	if _emitters_list == null:
		return
	for c in _emitters_list.get_children():
		_emitters_list.remove_child(c)
		c.queue_free()
	for i in _emitter_dicts.size():
		_emitters_list.add_child(_make_emitter_row(i))
	_tighten_panel(_emitters_list)


func _make_emitter_row(idx: int) -> Control:
	var d: Dictionary = _emitter_dicts[idx]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	var title := _row_lbl("Emitter %d" % (idx + 1))
	title.add_theme_color_override("font_color", Color(0.62, 0.82, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var rm := Button.new()
	rm.text = "✕"
	rm.custom_minimum_size = Vector2(34, 26)
	rm.add_theme_font_size_override("font_size", FS_CAPTION)
	rm.pressed.connect(func(): _remove_emitter(d))
	head.add_child(rm)
	row.add_child(head)
	# Row 1: trigger + payload
	var h1 := HBoxContainer.new()
	var trig_dd := _row_dd(EMITTER_TRIGGER_LABELS, maxi(0, EMITTER_TRIGGERS.find(String(d.get("trigger", "timer")))))
	trig_dd.item_selected.connect(func(i): _set_emitter(d, "trigger", EMITTER_TRIGGERS[i]))
	h1.add_child(trig_dd)
	var pnames: Array = EnemyRoster.EMITTABLE.keys()
	var pay_dd := _row_dd(pnames, maxi(0, pnames.find(String(d.get("payload", "Missile")))))
	pay_dd.item_selected.connect(func(i): _set_emitter(d, "payload", String(pnames[i])))
	h1.add_child(pay_dd)
	row.add_child(h1)
	# Row 2: cadence + count
	var h2 := HBoxContainer.new()
	h2.add_child(_row_lbl("every"))
	var cad := _row_spin(0.1, 6.0, 0.05, float(d.get("cadence", 0.55)))
	cad.value_changed.connect(func(v): _set_emitter(d, "cadence", float(v)))
	h2.add_child(cad)
	h2.add_child(_row_lbl("count"))
	var cnt := _row_spin(1, 12, 1, float(d.get("count", 1)))
	cnt.value_changed.connect(func(v): _set_emitter(d, "count", int(v)))
	h2.add_child(cnt)
	row.add_child(h2)
	# Row 3: max-per-pass (TIMER) + on-screen gate
	var h3 := HBoxContainer.new()
	h3.add_child(_row_lbl("max/pass"))
	var mx := _row_spin(0, 20, 1, float(d.get("max_emits", 0)))
	mx.value_changed.connect(func(v): _set_emitter(d, "max_emits", int(v)))
	h3.add_child(mx)
	var band := CheckBox.new()
	band.text = "on-screen"
	band.button_pressed = bool(d.get("band_only", false))
	band.add_theme_font_size_override("font_size", FS_CAPTION)
	band.toggled.connect(func(p): _set_emitter(d, "band_only", p))
	h3.add_child(band)
	row.add_child(h3)
	return row


# Default emitters for an enemy with no saved override: its production roster "emitters" block.
func _default_emitters_for(path: String) -> Array:
	var entry: Dictionary = EnemyRoster.entry_for_scene(path)
	var raw = entry.get("emitters", []) if entry is Dictionary else []
	var out: Array = []
	if raw is Array:
		for d in raw:
			if d is Dictionary:
				out.append({
					"trigger": String(d.get("trigger", "timer")),
					"payload": _emitter_payload_name(d),
					"cadence": float(d.get("cadence", 2.0)),
					"count": int(d.get("count", 1)),
					"max_emits": int(d.get("max_emits", 0)),
					"band_only": bool(d.get("band_only", false)),
				})
	return out


# Roster emitter "payload" is already a friendly EMITTABLE name; fall back from a raw path.
func _emitter_payload_name(d: Dictionary) -> String:
	var pv = d.get("payload", "Missile")
	if pv is String:
		if EnemyRoster.EMITTABLE.has(pv):
			return pv
		for k in EnemyRoster.EMITTABLE:
			if String(EnemyRoster.EMITTABLE[k]) == String(pv):
				return String(k)
	return "Missile"


# A paste-ready roster "emitters" dict literal for one emitter.
func _emitter_copy_line(d: Dictionary) -> String:
	var pname: String = String(d.get("payload", "Missile"))
	var extra: String = ", \"sfx\": \"missile\"" if pname == "Missile" else ""
	var band: String = "true" if bool(d.get("band_only", false)) else "false"
	return "{ \"trigger\": \"%s\", \"payload\": \"%s\", \"count\": %d, \"cadence\": %.2f, \"max_emits\": %d, \"band_only\": %s%s }," % [
		String(d.get("trigger", "timer")), pname, int(d.get("count", 1)), float(d.get("cadence", 0.55)),
		int(d.get("max_emits", 0)), band, extra,
	]


# Scan authored Marker2D names from a scene's state (no instantiation, like _icon_for).
func _scan_markers(path: String) -> Array:
	var ps := load(path) as PackedScene
	if ps == null:
		return []
	var st := ps.get_state()
	var out: Array = []
	for i in st.get_node_count():
		if st.get_node_type(i) == &"Marker2D":
			out.append(String(st.get_node_name(i)))
	return out


# Dropdown options for a mount's marker: "(hull)" + each exact marker + a glob per suffix family.
func _marker_options(path: String) -> Array:
	var opts: Array = ["(hull)"]
	var globs: Dictionary = {}
	for nm in _scan_markers(path):
		if not opts.has(nm):
			opts.append(nm)
		var g: String = _glob_of(nm)
		if g != "" and not globs.has(g):
			globs[g] = true
	for g in globs.keys():
		opts.append(g)
	return opts


# Strip trailing digits / L / R off a marker name to a "<prefix>*" glob (MuzzleL → Muzzle*); "" if none.
func _glob_of(nm: String) -> String:
	var base: String = nm
	while base.length() > 0 and ("0123456789LR".contains(base.substr(base.length() - 1, 1))):
		base = base.substr(0, base.length() - 1)
	return (base + "*") if (base.length() >= 2 and base != nm) else ""


func _marker_label(value: String) -> String:
	return "(hull)" if value == "" else value


func _marker_value(label: String) -> String:
	return "" if label == "(hull)" else label


func _mount_payload_names() -> Array:
	var names: Array = PAYLOADS.keys().duplicate()
	for p in PROJECTILES.keys():
		names.append(p)
	return names


func _dup_mounts(src) -> Array:
	var out: Array = []
	if src is Array:
		for d in src:
			if d is Dictionary:
				out.append(d.duplicate(true))
	return out


# Default mounts for an enemy when it has no saved bench override: its production roster `mounts`,
# converted to the bench's name-based dict shape. So a migrated enemy (gunship, helix) shows + fires
# its real mounts in the bench out of the box, and the user tunes from there.
func _default_mounts_for(path: String) -> Array:
	var entry: Dictionary = EnemyRoster.entry_for_scene(path)
	var raw = entry.get("mounts", []) if entry is Dictionary else []
	var out: Array = []
	if raw is Array:
		for d in raw:
			if d is Dictionary:
				out.append(_roster_mount_to_bench(d))
	return out


func _roster_mount_to_bench(d: Dictionary) -> Dictionary:
	var pp_toks: Array = []
	var pp_arr = d.get("fire_path_phases", [])
	if pp_arr != null:
		for f in pp_arr:
			pp_toks.append(str(f))
	return {
		"kind": String(d.get("kind", "gun")),
		"marker": String(d.get("marker", "")),
		"aim": String(d.get("aim", "straight_down")),
		"fire": float(d.get("fire_min", d.get("fire_max", 1.5))),
		"count": int(d.get("count", 1)),
		"spread": float(d.get("spread_deg", 0.0)),
		"payload": _payload_name_of(d),
		"marker_mode": String(d.get("marker_mode", "cycle")),
		"burst_interval": float(d.get("burst_interval", 0.0)),
		"bullet_speed": float(d.get("bullet_speed", -1.0)),
		"zone_gated": bool(d.get("fire_zone_gated", false)),
		"nose_gated": bool(d.get("fire_only_on_target", false)),
		"aim_tol": float(d.get("fire_aim_tol_deg", 18.0)),
		"path_phases": ",".join(pp_toks),
		"beat_synced": bool(d.get("fire_beat_synced", true)),
		"on_phase": String(d.get("fire_on_phase", "")),
	}


# Reverse-resolve a roster mount's payload (a BulletVariant resource or a scene path) to its bench
# dropdown name. Both PAYLOADS and the roster share the same preloaded BV_* consts → identity match.
func _payload_name_of(d: Dictionary) -> String:
	var pv = d.get("payload", null)
	if pv != null:
		for k in PAYLOADS:
			if PAYLOADS[k] == pv:
				return String(k)
	var ps = d.get("payload_scene", null)
	if ps != null:
		var p: String = String(ps) if ps is String else (ps.resource_path if ps is PackedScene else "")
		for k in PROJECTILES:
			if String(PROJECTILES[k]) == p:
				return String(k)
	return "Basic"


# A paste-ready roster "mounts" dict literal for one mount (payload → BV_ const or scene path).
func _mount_copy_line(d: Dictionary) -> String:
	var pname: String = String(d.get("payload", "Basic"))
	var pay: String = "\"payload\": null"
	if PAYLOADS.has(pname):
		pay = "\"payload\": BV_%s" % pname.replace(" ", "")
	elif PROJECTILES.has(pname):
		pay = "\"payload_scene\": \"%s\"" % PROJECTILES[pname]
	var line: String = "{ \"kind\": \"%s\", \"marker\": \"%s\", %s, \"aim\": \"%s\", \"fire_min\": %.2f, \"fire_max\": %.2f, \"count\": %d, \"spread_deg\": %.1f" % [
		String(d.get("kind", "gun")), String(d.get("marker", "")), pay, String(d.get("aim", "straight_down")),
		float(d.get("fire", 1.5)), float(d.get("fire", 1.5)), int(d.get("count", 1)), float(d.get("spread", 0.0)),
	]
	# Firing pattern fields for gun/launcher (emit only when non-default).
	var k: String = String(d.get("kind", "gun"))
	if k == "gun" or k == "launcher":
		var mode: String = String(d.get("marker_mode", "cycle"))
		if mode != "all":
			line += ", \"marker_mode\": \"%s\"" % mode
		var burst: float = float(d.get("burst_interval", 0.0))
		if burst > 0.0:
			line += ", \"burst_interval\": %.2f" % burst
		var bspeed: float = float(d.get("bullet_speed", -1.0))
		if bspeed >= 0.0:
			line += ", \"bullet_speed\": %.0f" % bspeed
		if bool(d.get("zone_gated", false)):
			line += ", \"fire_zone_gated\": true"
		if bool(d.get("nose_gated", false)):
			line += ", \"fire_only_on_target\": true, \"fire_aim_tol_deg\": %.0f" % float(d.get("aim_tol", 18.0))
		var pp_copy: String = String(d.get("path_phases", "")).strip_edges()
		if pp_copy != "":
			line += ", \"fire_path_phases\": [%s]" % pp_copy
			if not bool(d.get("beat_synced", true)):
				line += ", \"fire_beat_synced\": false"
		var ophase: String = String(d.get("on_phase", "")).strip_edges()
		if ophase != "":
			line += ", \"fire_on_phase\": \"%s\"" % ophase
	line += " },"
	return line


# --- compact row widget factories ---
func _row_dd(labels: Array, sel: int) -> OptionButton:
	var dd := OptionButton.new()
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dd.add_theme_font_size_override("font_size", FS_CAPTION)
	for l in labels:
		dd.add_item(String(l))
	if sel >= 0 and sel < dd.item_count:
		dd.select(sel)
	return dd


func _row_spin(mn: float, mx: float, st: float, val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn
	sb.max_value = mx
	sb.step = st
	sb.value = val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.add_theme_font_size_override("font_size", FS_CAPTION)
	return sb


func _row_lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", FS_CAPTION)
	l.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 0.70))
	# Wrap (see _mk_label): mount/emitter rows live in the same narrow gutter panel.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


# Turret-mounted enemies (zealot tank turret, gun_turret, push dome…) fire through child
# EnemyTurret nodes that carry their OWN bullet_variant and ignore the enemy's shoot_pattern —
# so the Payload dropdown is a no-op on them unless we push the selection onto each turret too.
# zealot_turret mounts a placeholder slug "to retune in the dev tools"; this is that retune.
# Runs after start() since turrets are mounted in the enemy's _ready/start. Matched by script
# identity (not the EnemyTurret class_name, which doesn't resolve in headless --script runs).
func _apply_payload_to_turrets(inst: Node) -> void:
	if not _mount_dicts.is_empty():
		return   # mount turrets carry their own payload from the spec — don't clobber
	if inst == null or _is_mine(_selected_path):
		return
	var bv = _selected_payload()
	if bv == null:
		return
	for t in _collect_turrets(inst, []):
		t.bullet_variant = bv


func _collect_turrets(node: Node, out: Array) -> Array:
	for c in node.get_children():
		if _is_turret(c):
			out.append(c)
		_collect_turrets(c, out)
	return out


# True if `n` runs enemy_turret.gd (directly or via a subclass).
func _is_turret(n: Node) -> bool:
	var s: Script = n.get_script()
	while s != null:
		if s == EnemyTurretScript:
			return true
		s = s.get_base_script()
	return false


func _apply_explosion_live() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy) and "explosion_variant" in _current_enemy:
		_current_enemy.explosion_variant = ExplosionFx.variant_names()[_explosion_dd.selected]


# Apply the stat-knob values to a (pre-_ready) enemy instance.
func _apply_stats_to(inst: Node) -> void:
	if inst == null:
		return
	if "max_health" in inst:
		inst.max_health = int(_hp_spin.value)
	if "bounty_value" in inst:
		inst.bounty_value = int(_bounty_spin.value)
	if "display_scale" in inst:
		inst.display_scale = float(_scale_spin.value)
	if "bullet_speed_mult" in inst:
		inst.bullet_speed_mult = float(_bspeed_spin.value)
	if "bullet_damage_mult" in inst:
		inst.bullet_damage_mult = float(_bdmg_spin.value)
	# Locomotion preview: resolve from the enemy's ENTRIES size + the bench engine/depth so the live
	# ship moves at the tuned speed/depth (locomotion refactor 2026-06-19).
	if "move_speed" in inst and _engine_spin != null:
		var loco: Dictionary = EnemyRoster.resolve_locomotion(_template_entry())
		inst.move_speed = float(loco["move_speed"])
		if "weight" in inst:
			inst.weight = float(loco["weight"])
		if "turn_rate" in inst:
			inst.turn_rate = float(loco["turn_rate"])
		if "accel" in inst:
			inst.accel = float(loco["accel"])
		if "depth_bp" in inst:
			inst.depth_bp = float(loco["depth_bp"])


# Cheap stats (no _ready dependency) applied to the live enemy without a respawn.
func _apply_stats_live() -> void:
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if "bounty_value" in _current_enemy:
		_current_enemy.bounty_value = int(_bounty_spin.value)
	if "bullet_speed_mult" in _current_enemy:
		_current_enemy.bullet_speed_mult = float(_bspeed_spin.value)
	if "bullet_damage_mult" in _current_enemy:
		_current_enemy.bullet_damage_mult = float(_bdmg_spin.value)


func _apply_recycle_live() -> void:
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if not "recycle_passes" in _current_enemy:
		return
	if not _recycle_chk.button_pressed:
		# Can't recycle = flee behavior
		_current_enemy.recycle_passes = 0
	else:
		# Can recycle: use the spinbox value, unless chance says flee
		var chance: float = float(_recycle_chance_spin.value)
		if randf() < chance:
			_current_enemy.recycle_passes = int(_recycle_passes_spin.value)
		else:
			_current_enemy.recycle_passes = 0  # flee


func _clear_enemy() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy):
		_current_enemy.queue_free()
	_current_enemy = null


# Full reset of the in-viewport gameplay layer: the current enemy PLUS every leftover it
# spawned (bullets, firecore drops, muzzle/explosion fx — all parented into _enemy_layer via
# the bullet_world group). The dummy player lives on _preview_vp, not _enemy_layer, so it
# survives. Used on every (re)spawn so switching enemies starts from a clean slate (issue #3).
func _clear_playspace() -> void:
	_current_enemy = null
	if _enemy_layer == null or not is_instance_valid(_enemy_layer):
		return
	for child in _enemy_layer.get_children():
		child.queue_free()


# ---- Per-frame: drive dummy + respawn check ------------------------------

func _process(delta: float) -> void:
	_drive_dummy(delta)
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if not (_current_enemy is Node2D):
		return
	var p: Vector2 = (_current_enemy as Node2D).position
	if p.y > 320 or p.x < -40 or p.x > 520:
		_clear_enemy()
		if _respawn_timer.is_stopped():
			_respawn_timer.start()


func _drive_dummy(delta: float) -> void:
	if _dummy == null or not is_instance_valid(_dummy):
		return
	var v := Vector2.ZERO
	if Input.is_action_pressed("left"): v.x -= 1.0
	if Input.is_action_pressed("right"): v.x += 1.0
	if Input.is_action_pressed("up"): v.y -= 1.0
	if Input.is_action_pressed("down"): v.y += 1.0
	if v != Vector2.ZERO:
		var np: Vector2 = _dummy.position + v.normalized() * DUMMY_SPEED * delta
		np.x = clampf(np.x, Playfield.X_MIN + 8.0, Playfield.X_MAX - 8.0)
		np.y = clampf(np.y, 20.0, 262.0)
		_dummy.position = np


# ---- Info + settings persistence -----------------------------------------

func _refresh_info() -> void:
	_name_lbl.text = _name_edit.text if (_name_edit and _name_edit.text != "") else EnemyStrings.display_name(_selected_path)
	var hp: int = int(_current_enemy.max_health) if (_current_enemy and "max_health" in _current_enemy) else 0
	var bounty: int = int(_current_enemy.bounty_value) if (_current_enemy and "bounty_value" in _current_enemy) else 0
	_stats_lbl.text = "HP %d   Bounty %d   Eligible: %s" % [hp, bounty, ", ".join(_eligible)]


func _load_settings_into_editors() -> void:
	_loading = true
	var s: Dictionary = _saved.get(_selected_path, {})
	var nat: Dictionary = _scene_defaults(_selected_path)   # native scene values = fallbacks
	_select_text(_fire_dd, String(s.get("fire_pattern", "SINGLE")), FIRE_PATTERNS)
	_select_text(_aim_dd, String(s.get("aim", "STRAIGHT_DOWN")), AIMS)
	_select_text(_payload_dd, String(s.get("payload", "Basic")), PAYLOADS.keys())
	_select_text(_explosion_dd, String(s.get("explosion", "default")), ExplosionFx.variant_names())
	if _armed_chk:
		# Default from the roster "shoot" key; a saved value (incl. user opt-in for bench-only units) wins.
		_armed_chk.button_pressed = bool(s.get("armed", _default_armed(_selected_path)))
	if _recycle_chk:
		_recycle_chk.button_pressed = bool(s.get("can_recycle", true))
	if _recycle_passes_spin:
		_recycle_passes_spin.value = int(s.get("recycle_passes", 1))
	if _recycle_chance_spin:
		_recycle_chance_spin.value = float(s.get("recycle_chance", 1.0))
	_hp_spin.value = int(s.get("max_health", nat.get("max_health", 1)))
	_bounty_spin.value = int(s.get("bounty_value", nat.get("bounty_value", 5)))
	_scale_spin.value = float(s.get("display_scale", nat.get("display_scale", 1.0)))
	_bspeed_spin.value = float(s.get("bullet_speed_mult", nat.get("bullet_speed_mult", 1.0)))
	_bdmg_spin.value = float(s.get("bullet_damage_mult", nat.get("bullet_damage_mult", 1.0)))
	if _engine_spin != null:
		var le: Dictionary = EnemyRoster.entry_for_scene(_selected_path)
		_engine_spin.value = int(s.get("engine", int(le.get("engine", 0))))
		var dstr: String = String(s.get("depth", String(le.get("depth", ""))))
		var didx: int = _DEPTH_ITEMS.find(dstr)
		_depth_dd.select(didx if didx >= 0 else 0)
		if _size_dd != null:
			var sz: String = String(s.get("size", String(le.get("size", "medium"))))
			var si: int = _SIZE_OPTS.find(sz)
			_size_dd.select(si if si >= 0 else 2)
			var etags: Array = le.get("tags", []) if le.has("tags") else []
			_tough_chk.button_pressed = bool(s.get("tough", "tough" in etags))
			_shielded_chk.button_pressed = bool(s.get("shielded", "shielded" in etags))
			if _omni_chk != null:
				_omni_chk.button_pressed = bool(s.get("omni", false))
			if _strafe_chk != null:
				_strafe_chk.button_pressed = bool(s.get("strafe", false))
			if _retro_chk != null:
				_retro_chk.button_pressed = bool(s.get("retro", false))
	_name_edit.text = String(s.get("name", EnemyStrings.display_name(_selected_path)))
	_codex_edit.text = String(s.get("codex", EnemyStrings.codex_entry(_selected_path)))
	# Saved bench override wins; otherwise default to the enemy's production roster mounts.
	_mount_dicts = _dup_mounts(s.get("mounts")) if s.has("mounts") else _default_mounts_for(_selected_path)
	_rebuild_mounts_ui()
	_emitter_dicts = _dup_mounts(s.get("emitters")) if s.has("emitters") else _default_emitters_for(_selected_path)
	_rebuild_emitters_ui()
	_loading = false


# Native stat values baked into a scene (so the spinboxes show real defaults, not
# the @export base). Instantiates once, reads, frees.
func _scene_defaults(path: String) -> Dictionary:
	var out := {}
	var ps := load(path) as PackedScene
	if ps == null:
		return out
	var inst := ps.instantiate()
	for k in ["max_health", "bounty_value", "display_scale", "bullet_speed_mult", "bullet_damage_mult"]:
		if k in inst:
			out[k] = inst.get(k)
	inst.free()
	return out


func _select_text(dd: OptionButton, text: String, pool) -> void:
	var i: int = Array(pool).find(text)
	dd.select(i if i >= 0 else 0)


func _current_settings() -> Dictionary:
	return {
		"armed": _armed_chk.button_pressed,
		"fire_pattern": FIRE_PATTERNS[_fire_dd.selected],
		"aim": AIMS[_aim_dd.selected],
		"payload": String(PAYLOADS.keys()[_payload_dd.selected]),
		"explosion": ExplosionFx.variant_names()[_explosion_dd.selected],
		"can_recycle": _recycle_chk.button_pressed,
		"recycle_passes": int(_recycle_passes_spin.value),
		"recycle_chance": float(_recycle_chance_spin.value),
		"max_health": int(_hp_spin.value),
		"bounty_value": int(_bounty_spin.value),
		"display_scale": float(_scale_spin.value),
		"bullet_speed_mult": float(_bspeed_spin.value),
		"bullet_damage_mult": float(_bdmg_spin.value),
		"name": _name_edit.text,
		"codex": _codex_edit.text,
		"mounts": _dup_mounts(_mount_dicts),
		"emitters": _dup_mounts(_emitter_dicts),
		"engine": int(_engine_spin.value) if _engine_spin != null else 0,
		"depth": _depth_for_selected(),
		"size": _bench_size(),
		"tough": _tough_chk.button_pressed if _tough_chk != null else false,
		"shielded": _shielded_chk.button_pressed if _shielded_chk != null else false,
		"omni": _omni_chk.button_pressed if _omni_chk != null else false,
		"strafe": _strafe_chk.button_pressed if _strafe_chk != null else false,
		"retro": _retro_chk.button_pressed if _retro_chk != null else false,
	}


func _on_save() -> void:
	if _selected_path == "":
		return
	_saved[_selected_path] = _current_settings()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_saved, "\t"))
		f.close()
	if _pattern_lbl:
		_pattern_lbl.text = "Saved %s" % EnemyStrings.display_name(_selected_path)


func _load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_saved = data


func _on_copy() -> void:
	var s := _current_settings()
	var payload_const: String = "BV_" + String(s["payload"]).replace(" ", "")
	var txt := "# Enemy Bench — %s\n" % String(s["name"])
	if s["armed"]:
		txt += "var w := Weapon.new()\n"
		txt += "w.fire_pattern = Weapon.FirePattern.%s\n" % s["fire_pattern"]
		txt += "w.aim = Weapon.Aim.%s\n" % s["aim"]
		txt += "w.payload = %s\n" % payload_const
		txt += "enemy.shoot_pattern = w\n"
	else:
		txt += "# (no generic weapon — weaponless or fires via its own script / turret)\n"
		txt += "enemy.shoot_pattern = null\n"
	txt += "enemy.explosion_variant = \"%s\"\n" % s["explosion"]
	txt += "# Stats:\n"
	txt += "enemy.max_health = %d\n" % s["max_health"]
	txt += "enemy.bounty_value = %d\n" % s["bounty_value"]
	txt += "enemy.display_scale = %.2f\n" % s["display_scale"]
	txt += "enemy.bullet_speed_mult = %.2f\n" % s["bullet_speed_mult"]
	txt += "enemy.bullet_damage_mult = %.2f\n" % s["bullet_damage_mult"]
	txt += "# Recycle behavior:\n"
	if s["can_recycle"]:
		txt += "enemy.recycle_passes = %d  # %.1f chance to recycle\n" % [s["recycle_passes"], s["recycle_chance"]]
	else:
		txt += "enemy.recycle_passes = 0  # flee (no recycle)\n"
	# Locomotion → roster ENTRY fields (size base + engine rung offset + optional depth band).
	var loco_bits: Array = []
	if int(s.get("engine", 0)) != 0:
		loco_bits.append("\"engine\": %d" % int(s["engine"]))
	if String(s.get("depth", "")) != "":
		loco_bits.append("\"depth\": \"%s\"" % String(s["depth"]))
	txt += "\n# -> roster ENTRY (locomotion): %s\n" % (", ".join(loco_bits) if not loco_bits.is_empty() else "(size-derived — engine 0, no depth override)")
	# Template → roster ENTRY (size + traits drive the derived stats; overrides only when tweaked).
	var t_tags: Array = []
	if bool(s.get("tough", false)):
		t_tags.append("tough")
	if bool(s.get("shielded", false)):
		t_tags.append("shielded")
	var tag_lits: Array = []
	for t in t_tags:
		tag_lits.append("\"%s\"" % String(t))
	var entry_bits: Array = ["\"size\": \"%s\"" % String(s.get("size", "medium")), "\"tags\": [%s]" % ", ".join(tag_lits)]
	var tmpl: Dictionary = EnemyRoster.compose_stats({"size": String(s.get("size", "medium")), "tags": t_tags})
	if int(s["max_health"]) != int(tmpl["max_health"]):
		entry_bits.append("\"hp_override\": %d" % int(s["max_health"]))
	if int(s["bounty_value"]) != int(tmpl["bounty_value"]):
		entry_bits.append("\"bounty_override\": %d" % int(s["bounty_value"]))
	txt += "# -> roster ENTRY (template): %s\n" % ", ".join(entry_bits)
	# Locomotion capability flags (omni/strafe/retro) — scene-baked on enemy_base.
	var loco_flags: Array = []
	if bool(s.get("omni", false)): loco_flags.append("omni")
	if bool(s.get("strafe", false)): loco_flags.append("strafe")
	if bool(s.get("retro", false)): loco_flags.append("retro")
	if not loco_flags.is_empty():
		txt += "# -> scene root (enemy_base): set %s = true\n" % ", ".join(loco_flags)
	# Mounts → a roster ENTRY "mounts" block (extra emitters beyond the hull weapon).
	if not _mount_dicts.is_empty():
		txt += "\n# -> roster ENTRY \"mounts\":\n\"mounts\": [\n"
		for d in _mount_dicts:
			txt += "\t%s\n" % _mount_copy_line(d)
		txt += "],\n"
	# Emitters → a roster ENTRY "emitters" block (droppers/spawners — the EmitterComponent path).
	if not _emitter_dicts.is_empty():
		txt += "\n# -> roster ENTRY \"emitters\":\n\"emitters\": [\n"
		for d in _emitter_dicts:
			txt += "\t%s\n" % _emitter_copy_line(d)
		txt += "],\n"
	# Paste-ready enemy_strings.gd STRINGS entry (the name + codex live in a baked
	# const dict, so this is the handoff back into source).
	var codex_one_line: String = String(s["codex"]).replace("\n", " ").replace("\"", "'")
	txt += "\n# -> scripts/enemy_strings.gd STRINGS:\n"
	txt += "\t\"%s\": {\"name\": \"%s\", \"codex\": \"%s\"},\n" % [_selected_path, String(s["name"]), codex_one_line]
	DisplayServer.clipboard_set(txt)
	if _pattern_lbl:
		_pattern_lbl.text = "Copied GDScript to clipboard"


# ---- Back ----------------------------------------------------------------

func _on_back() -> void:
	# Restore the audio bus mute state the bench inherited, so the Mute toggles never
	# leave Music/SFX muted out in the rest of the game.
	_set_bus_muted("Music", _music_bus_was_muted)
	_set_bus_muted("SFX", _sfx_bus_was_muted)
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
