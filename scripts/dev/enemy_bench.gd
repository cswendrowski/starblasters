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
# Movement eligibility is READ live from DevData.eligibility_for (committed PatternEligibility.DATA +
# pending pattern_eligibility.json), not queried directly here — the bench mirrors it, never authors it.
const AuthoredPathLibrary = preload("res://scripts/enemies/patterns/authored_path_library.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const ShieldComponentC = preload("res://scripts/enemies/components/shield_component.gd")
const OrbitComponentC = preload("res://scripts/enemies/components/orbit_component.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const EnemyTurretScript = preload("res://scripts/enemies/enemy_turret.gd")
const PLAYER_SCENE = preload("res://scenes/player/player.tscn")

const SAVE_PATH := "user://tuners/enemy_bench.json"

# Editor option pools.
# Payload FAMILIES (Roman 2026-06-29): each maps to one BulletVariant that points at its
# projectile_<type> scene (a 4-frame sprite sheet, frame = faction). The faction-frame reskin
# (BulletCatalog.faction_variant, via the enemy's faction_skin) picks the frame at spawn — so the
# bench just picks the shape, and all four factions reskin from the one sheet. "Orb" is a slow round.
# Payload inventory now comes LIVE from DevData.bullet_variants() (2026-07-07 dev-tool unification):
# ONE inventory of data/bullets/*.tres shared with the Weapon Lab, so a newly added .tres appears in
# BOTH tools (was: a hardcoded list here that the weapon lab's dir-scan could diverge from). PAYLOADS
# maps family name -> the loaded BulletVariant (live preview); PAYLOAD_CONST maps family name -> the
# Copy-GDScript expression. Built once in _init() from the same {name, path} list; the "Drop" pellet
# (drop_pellet.tres) keeps emitting the roster's BV_DropPellet const so Copy output stays lossless.
const DevData = preload("res://scripts/dev/dev_data.gd")
# Default-vs-override affordance (Phase 3): decorates stat/size/loco rows with a muted "was: <baked>"
# aside + a per-field revert, so a shown value is never ambiguously "shipping default OR my un-pasted
# edit" (symptom c). Opt-in per field; the bench feeds it the roster/scene BAKED default it already has
# in hand at load. Decorated controls are refreshed on each load + on change (no per-frame work).
const DevField = preload("res://scripts/dev/dev_field.gd")
# Family name -> roster const NAME to emit in Copy (where the roster declares one). Families other than
# Drop have no roster const yet (enemy_roster migration is a follow-up — see enemy_roster.gd:108), so
# they emit a self-contained preload of their live .tres path instead.
const PAYLOAD_ROSTER_CONST := {
	"Drop": "BV_DropPellet",
}
var PAYLOADS: Dictionary = {}        # family name -> BulletVariant (loaded live)
var PAYLOAD_CONST: Dictionary = {}   # family name -> Copy-GDScript payload expression


# Build the payload inventory from the live data/bullets/*.tres scan. Family order follows
# DevData.bullet_variants(). Roster consts (Drop) emit their const; the rest emit a preload of their path.
func _build_payload_tables() -> void:
	PAYLOADS = {}
	PAYLOAD_CONST = {}
	for v in DevData.bullet_variants():
		var name: String = String(v.get("name", ""))
		var path: String = String(v.get("path", ""))
		if name == "" or path == "":
			continue
		var res: Resource = load(path)
		if res == null:
			continue
		PAYLOADS[name] = res
		if PAYLOAD_ROSTER_CONST.has(name):
			PAYLOAD_CONST[name] = String(PAYLOAD_ROSTER_CONST[name])
		else:
			PAYLOAD_CONST[name] = "preload(\"%s\")" % path
# Migration for saved tuner files written before the payload collapse (2026-06-29): the old per-faction
# / per-shape names map to the new families so an existing saved mount doesn't load with a dead payload.
const _LEGACY_PAYLOAD := {
	"Basic": "Ball", "Spread Pellet": "Ball", "Burst Round": "Ball", "Plasma Orb": "Ball",
	"Heavy Slug": "Bolt", "Aimed Sniper": "Bolt", "Drop Pellet": "Drop",
	"Zealot Ball": "Ball", "Zealot Bolt": "Bolt", "Zealot Laser": "Laser", "Zealot Wave": "Wave",
	"Privateer Ball": "Ball", "Privateer Bolt": "Bolt", "Privateer Laser": "Laser", "Privateer Wave": "Wave",
}

# Faction filter tabs (Roman 2026-06-12). "All" + the 4 factions + Core (universal chaff) +
# Hazards (mines/asteroid) + Bosses. Group is derived from the scene PATH (folder), not the
# ENEMY_TAGS home, so untagged hazards/bosses bucket cleanly and a universal chaff stays under Core.
# Bosses are excluded from the bench (they don't tune cleanly here — a dedicated boss tuning tool
# is a separate effort). The "Bosses" group is gone and boss scenes are filtered out of the list.
const FACTION_GROUPS := ["All", "Core", "Supremacy", "Privateer", "Corporate", "Zealot", "Hazards"]

# WIP mega-bosses waived from the blanket boss exclusion above, so their destructible-turret rig can be
# iterated against the dummy here (the enemy still fires at the dummy; the flee-on-turret-clear mechanic
# is exercised in the Combat Lab, where you can shoot back). Remove an entry once it graduates to the
# production boss roster + a dedicated boss tuner. Bucketed by scene path (_group_of), so the battleship
# lands under the "Zealot" tab.
const BENCH_WIP_BOSSES := [
	"res://scenes/enemies/factions/zealot/boss_z_battleship.tscn",
	"res://scenes/enemies/factions/corporate/boss_c_director.tscn",
]

# Mounts editor pools. Kind/aim are stored lowercase (the roster dict schema); the *_LABELS are the
# dropdown text. PROJECTILES are launcher payloads (scene paths), offered alongside the BulletVariant
# PAYLOADS in a mount row's payload dropdown.
const MOUNT_KINDS := ["gun", "turret", "launcher", "beam", "entity"]
const MOUNT_KIND_LABELS := ["Gun", "Turret", "Launcher", "Beam", "Entity"]
const MOUNT_AIM_KEYS := ["straight_down", "at_player", "toward_center", "forward", "backward", "left", "right"]
const MOUNT_AIM_LABELS := ["Down", "At Player", "To Center", "Forward", "Backward", "Left", "Right"]
const PROJECTILES := {
	"Rocket": "res://scenes/projectiles/enemy_rocket.tscn",
	"Rocket Lg": "res://scenes/projectiles/enemy_rocket_large.tscn",
	"Missile": "res://scenes/projectiles/drifting_missile.tscn",
	"Bomblet": "res://scenes/enemies/enemy_bomblet.tscn",
}
# Beam payload (Hardpoint v2 Phase A/beam-editor 2026-07-05): a "Beam" payload carries a beam_config,
# realized as a continuous BeamEmitter by MountBuilder (which routes on a non-empty beam_config, any kind
# — so a beam is "Beam payload × Direct delivery"). The bench authors it via editable beam rows (aim /
# reach / dps / timings) built from BEAM_DEFAULT; _beam_config_from(d) assembles the live config.
const BEAM_DEFAULT := {
	"idle_time": 0.9, "windup_time": 1.3, "firing_time": 1.1, "cooldown_time": 1.5,
	"cycle": 0, "autostart": false, "settle_y": 58.0, "endpoint": 0,
	"reach": 320.0, "dps": 3.0, "hit_radius": 8.0, "emitter_offset": Vector2(0, 0), "target_group": "player",
}
# BeamEmitter.AimMode: LOCAL_FORWARD 0 (fire along host forward), LOCKED 1 (snapshot aim at windup, the
# classic turret feel), TRACKING 2 (follow the player), TRACK_LOCK 4 (track between shots, freeze while firing).
const BEAM_AIM_LABELS := ["Forward", "Locked", "Tracking", "Track-Lock"]
const BEAM_AIM_VALUES := [0, 1, 2, 4]
const BEAM_PAYLOAD_NAME := "Beam"
# Emitter payloads (Phase 3): the retired Emitters editor is gone, but legacy roster/saved emitters still
# FOLD IN as entity mounts on load — so the payload set below is still the resolution table for that.
# Expanded emitter payload set (Roman 2026-06-29): every rocket / missile / mine / bomblet / firecore,
# plus ANY enemy (appended from the manifest at runtime — see _emitter_payload_options). The emitter
# spawns whatever scene the name resolves to via start(pos); the roster's _emitter_from_dict accepts a
# raw res:// path, so the bench doesn't need EnemyRoster.EMITTABLE to list these.
const EMITTER_PAYLOADS := {
	"Missile": "res://scenes/projectiles/drifting_missile.tscn",
	"Missile Lg": "res://scenes/projectiles/drifting_missile_large.tscn",
	"Rocket": "res://scenes/projectiles/enemy_rocket.tscn",
	"Rocket Lg": "res://scenes/projectiles/enemy_rocket_large.tscn",
	"Mine": "res://scenes/enemies/enemy_mine.tscn",
	"Mine Shield": "res://scenes/enemies/enemy_mine_shield.tscn",
	"Mine Smart": "res://scenes/enemies/enemy_mine_smart.tscn",
	"Mine Armored": "res://scenes/enemies/enemy_mine_armored.tscn",
	"Mine Tether": "res://scenes/enemies/enemy_mine_tether.tscn",
	"Mine Gravity": "res://scenes/enemies/enemy_mine_gravity.tscn",
	"Bomblet": "res://scenes/enemies/enemy_bomblet.tscn",
	"Firecore": "res://scenes/enemies/factions/zealot/firecore_hazard.tscn",
}
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
]
var _size_data: Dictionary = {}   # size -> {hp, shield_cap, bounty} (working draft)

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
@onready var _weapon_header: Label = %WeaponHeader   # "Turret payload" header (hidden when no turret)
@onready var _payload_dd: OptionButton = %PayloadDD
@onready var _explosion_dd: OptionButton = %ExplosionDD
@onready var _recycle_chk: CheckButton = %RecycleCheck
@onready var _recycle_passes_spin: SpinBox = %RecyclePassesSpin
@onready var _recycle_chance_spin: SpinBox = %RecycleChanceSpin
# Stat knobs (live-tuned, persisted, emitted by Copy GDScript). Built in code inside the Template
# section (_setup_enemy_template_knobs) so they sit with the size/traits knobs instead of in their
# own .tscn block. Display-scale + bullet-damage-mult knobs were cut 2026-06-29 (always 1×, untuned).
var _hp_spin: SpinBox = null
var _bounty_spin: SpinBox = null
var _bspeed_spin: SpinBox = null
# Opt-in override toggles (Roman 2026-06-29): HP/bounty/bullet-speed/engine are usually left at the
# template/native value, so each is gated behind a checkbox — unchecked hides the spinbox and the
# enemy uses its derived value; checked reveals the spin and applies it as an explicit override.
var _hp_override_chk: CheckBox = null
var _bounty_override_chk: CheckBox = null
var _bspeed_override_chk: CheckBox = null
var _engine_override_chk: CheckBox = null
# Display strings (editable name + codex, persisted + emitted as an enemy_strings entry).
@onready var _name_edit: LineEdit = %NameEdit
@onready var _codex_edit: TextEdit = %CodexEdit
# Mounts editor — extra emitters (gun/turret/launcher/beam) beyond the hull weapon (Mount 0).
@onready var _mounts_list: VBoxContainer = %MountsList
@onready var _add_mount_btn: Button = %AddMountButton
# (The Emitters editor was retired 2026-07-03 — droppers/spawners are authored as "Entity" hardpoints in
# the Mounts list; legacy roster/saved emitters still fold in on load. Its scene nodes are gone too.)
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
var _ram_chk: CheckBox = null   # Ram: no contact damage + knock the player back (any enemy)
# Faction eligibility (Roman 2026-07-06) — which factions a CORE ship (universal enemy) may appear with,
# i.e. its Factions.ENEMY_TAGS "allowed_in" whitelist. Shown only for core/universal ships; hidden for
# faction-exclusive units (their eligibility is fixed to their home). One checkbox per faction, ordered
# by Factions.Id (Supremacy/Privateer/Corporate/Zealot).
var _faction_elig_chks: Array = []
var _faction_elig_row: Control = null
var _faction_elig_caption: Control = null
# Eligible-movement reflection (Roman 2026-07-07) — the bench is a READ-ONLY mirror of the enemy's
# eligible movement set (shape keys + eligible authored-path "path_<name>" keys). That set is SET only in
# the Pattern Eligibility tool (persisted to user://tuners/pattern_eligibility.json → Export bakes it into
# PatternEligibility.DATA); the bench merely SHOWS it (via DevData.eligibility_for, live) and cycles the
# enemy through it (Next Pattern). No checkboxes, no editing, no eligibility persistence live here — a
# muted display label lists the keys and highlights the one currently previewed.
var _elig_display_lbl: Label = null
const _SIZE_OPTS := ["tiny", "small", "medium", "large", "huge", "giant"]

# Working list of mount dicts for the selected enemy (name-based, JSON-friendly):
# {kind, marker, payload(name), aim, fire, count, spread}. Converted to MountSpecs at spawn.
var _mount_dicts: Array = []
# Phase 3 default-vs-override for the Mounts editor: a parallel-indexed baked reference per mount. Each
# entry is the ROSTER-derived bench dict for that mount AT LOAD TIME (before user edits) — NOT the
# saved-JSON-merged working dict — so a decorated mount field shows drift from the SHIPPING roster value.
# An empty {} means "user-added / no roster counterpart": that mount's fields bake to the schema default
# (a fresh mount shows no affordances until edited). Kept aligned with _mount_dicts on add/remove.
var _mount_baked: Array = []
# Orbit rings (cluster-mine / bloom): an OrbitComponent holding N rings of payloads released on death.
# `_orbit_mode` = "visual" (bullet shells erupt outward) or "live" (real bomblets fly free).
# `_orbit_rings` = [{radius, count, speed, payload(name)}]. Built into an OrbitComponent at spawn.
var _orbit_mode: String = "live"
var _orbit_rings: Array = []
var _orbit_list: VBoxContainer = null
var _orbit_mode_dd: OptionButton = null
const ORBIT_LIVE_PAYLOADS := {"Bomblet": "res://scenes/enemies/enemy_bomblet.tscn"}

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
	_build_payload_tables()   # live data/bullets/*.tres inventory (before any UI/load reads PAYLOADS)
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
	# Payload change respawns (also retunes child-turret payloads via _apply_payload_to_turrets).
	_payload_dd.item_selected.connect(func(_i): _spawn_current())
	# Death explosion only matters on death, so apply it live (no respawn).
	_explosion_dd.item_selected.connect(func(_i): _apply_explosion_live())
	# Stat knobs (HP/bounty/bullet-speed) are built + wired in _setup_enemy_template_knobs.
	_name_edit.text_changed.connect(_on_name_edited)
	_recycle_chk.toggled.connect(func(_v): _apply_recycle_live())
	_recycle_passes_spin.value_changed.connect(func(_v): _apply_recycle_live())
	_recycle_chance_spin.value_changed.connect(func(_v): _apply_recycle_live())
	(%NextPatternButton as Button).pressed.connect(_cycle_and_spawn)
	(%SaveButton as Button).pressed.connect(_on_save)
	(%CopyButton as Button).pressed.connect(_on_copy)
	(%BackButton as Button).pressed.connect(_on_back)
	_add_mount_btn.pressed.connect(_add_mount)
	# (The Emitters editor is retired — its scene nodes are gone and the MountsHeader/AddMountButton scene
	# text now reads "Hardpoints" directly. Droppers/spawners are authored as an "Entity" hardpoint here.)

	# Music stays muted for dev menus (the Music toggle button was removed 2026-06-20); SFX keeps its
	# toggle. The prior bus state is still restored on exit (_on_back).
	_set_bus_muted("Music", true)
	_wire_mute_toggle(%SfxMute as Button, "SFX", _sfx_bus_was_muted)
	# Hard-lock the music autoload silent. The bus mute alone only HIDES music: a
	# previewed boss's _ready calls Music.set_context("boss"), which then blasts
	# when the bus un-mutes on exit. Locking makes those set_context calls no-ops.
	var _music := get_node_or_null("/root/Music")
	if _music != null and _music.has_method("lock_silent"):
		_music.lock_silent(true)


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
	_setup_orbit_editor(scroll)
	# Save/Copy were the last .tscn child, but the template + locomotion sections get appended in
	# code after them — so re-seat the separator + button row at the true bottom of the panel.
	var enemy_content := scroll.get_child(0)
	if enemy_content is Container:
		for nm in ["Sep6", "ButtonsRow"]:
			var n := enemy_content.get_node_or_null(nm)
			if n != null:
				enemy_content.move_child(n, enemy_content.get_child_count() - 1)
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
		var lbl := n as Label
		# 2-col field-grid captions must NOT autowrap: an autowrap label reports a ~0 min width, so
		# its grid column collapses and the control renders on top of the caption (the bug Roman hit).
		# Leave those at their natural width; only wrap the free-standing stacked captions.
		if lbl.get_parent() is GridContainer:
			continue
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD


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
	_style_button(save)
	save.pressed.connect(_save_loco)
	row.add_child(save)
	var cp := Button.new()
	cp.text = "Copy GDScript"
	_style_button(cp)
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
	DevField.decorate(_size_dd, 0, FS_CAPTION)   # baked (roster size index) reset per-enemy at load
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	content.add_child(tr)
	_tough_chk = CheckBox.new()
	_tough_chk.text = "tough (x2 HP)"
	_tough_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tough_chk.toggled.connect(func(_p): DevField.refresh(_tough_chk); _on_template_changed(0))
	tr.add_child(_tough_chk)
	DevField.decorate(_tough_chk, false, FS_CAPTION)
	_shielded_chk = CheckBox.new()
	_shielded_chk.text = "shielded"
	_shielded_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shielded_chk.toggled.connect(func(_p): DevField.refresh(_shielded_chk); _on_template_changed(0))
	tr.add_child(_shielded_chk)
	DevField.decorate(_shielded_chk, false, FS_CAPTION)
	# Locomotion capability flags (omni/strafe/retro).
	var loco_tr := HBoxContainer.new()
	loco_tr.add_theme_constant_override("separation", 10)
	content.add_child(loco_tr)
	_omni_chk = CheckBox.new()
	_omni_chk.text = "omni"
	_omni_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_omni_chk.toggled.connect(func(_p): DevField.refresh(_omni_chk); _on_template_changed(0))
	loco_tr.add_child(_omni_chk)
	DevField.decorate(_omni_chk, false, FS_CAPTION)
	_strafe_chk = CheckBox.new()
	_strafe_chk.text = "strafe"
	_strafe_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strafe_chk.toggled.connect(func(_p): DevField.refresh(_strafe_chk); _on_template_changed(0))
	loco_tr.add_child(_strafe_chk)
	DevField.decorate(_strafe_chk, false, FS_CAPTION)
	_retro_chk = CheckBox.new()
	_retro_chk.text = "retro"
	_retro_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retro_chk.toggled.connect(func(_p): DevField.refresh(_retro_chk); _on_template_changed(0))
	loco_tr.add_child(_retro_chk)
	DevField.decorate(_retro_chk, false, FS_CAPTION)
	_ram_chk = CheckBox.new()
	_ram_chk.text = "ram"
	_ram_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ram_chk.toggled.connect(func(_p): DevField.refresh(_ram_chk); _on_template_changed(0))
	loco_tr.add_child(_ram_chk)
	DevField.decorate(_ram_chk, false, FS_CAPTION)
	# Faction eligibility (core ships): which factions this universal core hull may appear with (its
	# Factions.ENEMY_TAGS "allowed_in" whitelist). Only meaningful for core/universal ships — hidden for
	# faction-exclusive units. Captured on Save + emitted in Copy GDScript as the ENEMY_TAGS line.
	_faction_elig_caption = _mk_label("Faction eligibility (core ships) — which factions this hull spawns with", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70))
	content.add_child(_faction_elig_caption)
	_faction_elig_row = HBoxContainer.new()
	_faction_elig_row.add_theme_constant_override("separation", 8)
	content.add_child(_faction_elig_row)
	_faction_elig_chks = []
	for fname in ["Sup", "Priv", "Corp", "Zeal"]:   # ordered by Factions.Id
		var chk := CheckBox.new()
		chk.text = fname
		chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chk.add_theme_font_size_override("font_size", FS_CAPTION)
		_faction_elig_row.add_child(chk)
		_faction_elig_chks.append(chk)
	# Eligible movement (READ-ONLY reflection): the shape keys + eligible authored paths this enemy may
	# fly, as SET in the Pattern Eligibility tool (never edited here — the bench only shows + cycles them).
	# Filled per-enemy by _refresh_elig_display(); the bracketed key is the one Next Pattern is previewing.
	content.add_child(_mk_label("Eligible movement (set in Pattern Eligibility)", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_elig_display_lbl = _mk_label("", FS_CAPTION, Color(0.6, 0.65, 0.72, 0.85))
	content.add_child(_elig_display_lbl)
	# Stat overrides (opt-in): size/traits seed HP & bounty; tick a box only when you want to pin an
	# explicit value. Unchecked = use the template/native value, and the row stays one compact line.
	content.add_child(_mk_label("Stat overrides (off = use template / native)", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_hp_spin = SpinBox.new()
	_hp_spin.min_value = 1.0
	_hp_spin.max_value = 9999.0
	_hp_spin.value = 1.0
	_hp_spin.value_changed.connect(func(_v): DevField.refresh(_hp_spin); if not _loading: _spawn_current())
	_hp_override_chk = _override_row(content, "Max HP", _hp_spin)
	DevField.decorate(_hp_spin, 1.0, FS_CAPTION)   # baked reset per-enemy in _load_settings_into_editors
	_bounty_spin = SpinBox.new()
	_bounty_spin.max_value = 9999.0
	_bounty_spin.value_changed.connect(func(_v): DevField.refresh(_bounty_spin); if not _loading: _apply_stats_live())
	_bounty_override_chk = _override_row(content, "Bounty", _bounty_spin)
	DevField.decorate(_bounty_spin, 0.0, FS_CAPTION)
	_bspeed_spin = SpinBox.new()
	_bspeed_spin.min_value = 0.25
	_bspeed_spin.max_value = 4.0
	_bspeed_spin.step = 0.05
	_bspeed_spin.value = 1.0
	_bspeed_spin.value_changed.connect(func(_v): DevField.refresh(_bspeed_spin); if not _loading: _apply_stats_live())
	_bspeed_override_chk = _override_row(content, "Bullet speed ×", _bspeed_spin)
	DevField.decorate(_bspeed_spin, 1.0, FS_CAPTION)


func _on_template_changed(_i: int) -> void:
	DevField.refresh(_size_dd)
	if _loading:
		return
	_apply_template_stats()
	# The template reseed may move HP/bounty; re-sync their affordances.
	DevField.refresh(_hp_spin)
	DevField.refresh(_bounty_spin)
	_spawn_current()


# Fill HP/bounty from the size+tags template (the lead then hand-tweaks the spinboxes).
func _apply_template_stats() -> void:
	if _size_dd == null:
		return
	var stats: Dictionary = EnemyRoster.compose_stats(_template_entry())
	_loading = true   # suppress the spinbox value_changed respawn storm
	# Only reseed spins that AREN'T pinned by an override (don't clobber a value the user set).
	if _hp_spin and not _override_on(_hp_override_chk):
		_hp_spin.value = int(stats["max_health"])
	if _bounty_spin and not _override_on(_bounty_override_chk):
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
		"engine": int(_engine_spin.value) if _override_on(_engine_override_chk) else 0,
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
	# Engine is an opt-in override (off = size-derived speed); Depth's own "(default)" already serves
	# as its no-override state, so it stays a plain stacked caption + dropdown.
	_engine_spin = SpinBox.new()
	_engine_spin.min_value = -4.0
	_engine_spin.max_value = 4.0
	_engine_spin.step = 1.0
	_engine_spin.value_changed.connect(_on_loco_knob_changed)
	_engine_override_chk = _override_row(content, "Engine ±rung", _engine_spin)
	DevField.decorate(_engine_spin, 0.0, FS_CAPTION)   # baked (roster engine) reset per-enemy at load
	content.add_child(_mk_label("Depth", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_depth_dd = OptionButton.new()
	_depth_dd.add_item("(default)")
	_depth_dd.add_item("high")
	_depth_dd.add_item("mid")
	_depth_dd.add_item("low")
	_depth_dd.custom_minimum_size = Vector2(0, 30)
	_depth_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depth_dd.item_selected.connect(_on_loco_depth_changed)
	content.add_child(_depth_dd)
	DevField.decorate(_depth_dd, 0, FS_CAPTION)   # baked (roster depth index) reset per-enemy at load


func _on_loco_knob_changed(_v: float) -> void:
	DevField.refresh(_engine_spin)
	if not _loading:
		_spawn_current()


func _on_loco_depth_changed(_i: int) -> void:
	DevField.refresh(_depth_dd)
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
	_style_button(save)
	save.pressed.connect(_save_sizes)
	row.add_child(save)
	var cp := Button.new()
	cp.text = "Copy GDScript"
	_style_button(cp)
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
		}
	return out


func _on_size_changed(value: float, sz: String, field: String) -> void:
	_size_data[sz][field] = int(value)


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
		txt += "\t\"%s\": {\"hp\": %d, \"shield_cap\": %d, \"bounty\": %d},\n" % [
			sz, int(d["hp"]), int(d["shield_cap"]), int(d["bounty"])]
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
	# Splice in the WIP mega-bosses the blanket boss filter drops (see BENCH_WIP_BOSSES), then re-sort
	# so they slot alphabetically like every other entry.
	for p in BENCH_WIP_BOSSES:
		if ResourceLoader.exists(p) and not _all_paths.has(p):
			_all_paths.append(p)
	_all_paths.sort()
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
	if p.contains("mine") or p.contains("asteroid") or p.contains("bomblet"): return "Hazards"
	# No "Bosses" tab exists (bosses are excluded / WIP bosses bucket under their faction folder above).
	# Any stray boss-scened script that reaches here falls through to Core so it stays reachable under
	# both the "All" and "Core" tabs rather than a phantom group that no tab can select.
	return "Core"


# Mines are contact / cluster hazards — they must never carry a weapon, even though they extend
# enemy_core (which owns the shoot_pattern slot). The minelayer is a ship, not a mine.
func _is_mine(path: String) -> bool:
	var p := path.to_lower()
	return p.contains("mine") and not p.contains("minelayer")




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
	# Re-read the Path Editor's user:// overrides so a path authored/saved this session (without a bench
	# restart) resolves; the library caches one file read, so reload_overrides forces a fresh read (dev-only).
	# The cyclable eligible set is then rebuilt from DevData (live matrix + pending eligibility save).
	AuthoredPathLibrary.reload_overrides()
	_pattern_idx = 0
	_rebuild_eligible_for_selected()
	_load_settings_into_editors()
	_spawn_current()


# Build the cyclable _eligible list = the enemy's LIVE eligible movement set (canonical shape keys +
# eligible authored-path "path_<name>" keys), straight from DevData.eligibility_for. That reflects the
# committed PatternEligibility.DATA with any PENDING pattern_eligibility.json save overlaid, so eligibility
# Roman SET in the Pattern Eligibility tool (and Saved) appears here without an Export/paste. Read-only:
# the bench never edits this set, it only cycles through it (Next Pattern) and mirrors it in the display.
func _rebuild_eligible_for_selected() -> void:
	_eligible = DevData.eligibility_for(_selected_path)
	_pattern_idx = clampi(_pattern_idx, 0, max(0, _eligible.size() - 1))
	_refresh_elig_display()


# Fill the read-only eligible-movement display for the selected enemy: bare key names (path_* shown
# without the "path_" prefix), the currently-previewed one bracketed. Refreshed on selection + each cycle.
func _refresh_elig_display() -> void:
	if _elig_display_lbl == null:
		return
	if _eligible.is_empty():
		_elig_display_lbl.text = "(none — set eligibility in Pattern Eligibility)"
		return
	var parts: Array = []
	for i in _eligible.size():
		var k: String = String(_eligible[i])
		var disp: String = k.trim_prefix(AuthoredPathLibrary.KEY_PREFIX) if AuthoredPathLibrary.is_path_key(k) else k
		parts.append(("[%s]" % disp) if i == _pattern_idx else disp)
	_elig_display_lbl.text = ", ".join(parts)


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
	# Stamp the faction skin (the production director does this on every spawn) so the collapsed
	# family payloads (Ball/Bolt/Laser/Wave) restyle to THIS enemy's faction in the preview.
	inst.set_meta("faction_skin", _faction_id_for_selected())
	var spawn_pos := Vector2(Playfield.CENTER.x, -12)   # match the director's spawn_y (wave_def.gd) so entry/facing read like live
	# Configure BEFORE add_child + start() so enemy_core._start_with_pattern
	# duplicates the chosen movement and the weapon/explosion are live from frame 0.
	var key := ""
	if not _eligible.is_empty() and "movement" in inst:
		key = String(_eligible[_pattern_idx])
		inst.movement = EnemyRoster.make_movement({"movement": key})
	if "shoot_pattern" in inst:
		# Mount 0 (hull weapon) retired 2026-06-23: the bench arms enemies via mounts only, so
		# leave shoot_pattern null (enemy_core's fire gates become no-ops for it).
		inst.shoot_pattern = null
	if "explosion_variant" in inst:
		inst.explosion_variant = ExplosionFx.variant_names()[_explosion_dd.selected]
	_apply_stats_to(inst)   # HP/scale/etc BEFORE _ready so health = max_health from frame 0
	# Faction weapon overlay (the director does this on every spawn — director.gd). Home-gated inside
	# Factions.apply, so it only buffs an enemy shown in its own faction: compounds bullet_speed_mult /
	# bullet_damage_mult (which the mounts read via _spawn_bullet) and adds faction components
	# (corpo shield / zealot firecore). Without this the bench fired un-multiplied vs live (Roman 2026-07-02).
	Factions.apply(_faction_id_for_selected(), inst)
	# Faction livery + tail-glow (Roman 2026-07-07): the director stamps these on every live spawn, so the
	# bench must too — otherwise a previewed enemy shows an untinted hull / muzzle glow and the bench lies
	# about its faction colours. -1 (Core / All filter) hides the livery, matching production.
	Factions.apply_livery(_faction_id_for_selected(), inst)
	Factions.apply_tailglow(_faction_id_for_selected(), inst)
	if "mounts" in inst:
		# _mount_spec_dicts() emits the SAME roster dict schema production uses (see MOUNT_FIELDS), so
		# make_mount_specs reads every field (no_inertia included) directly — no post-hoc bridge needed.
		inst.mounts = EnemyRoster.make_mount_specs(_mount_spec_dicts())   # extra hardpoints, BEFORE add_child
	if "components" in inst:
		# Legacy emitters now load into the Hardpoints (mounts) list as entity mounts, so there's no
		# separate emitter-component path here — only the orbit-ring cluster is a bespoke component.
		if not _orbit_rings.is_empty():
			inst.components = inst.components + [_build_orbit()]   # cluster-mine / bloom ring held + released
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
	if _ram_chk != null and "ram" in inst:
		inst.ram = _ram_chk.button_pressed
	if inst is Node2D:
		(inst as Node2D).position = spawn_pos
	_enemy_layer.add_child(inst)
	_current_enemy = inst
	# start() is what inits the movement pattern (anchor + on_start) — the director's
	# contract. enemy_core._ready does NOT auto-start.
	if inst.has_method("start"):
		inst.start(spawn_pos)
	_apply_payload_to_turrets(inst)   # turret-mounted enemies fire via child turrets, not shoot_pattern
	_update_turret_payload_visibility(inst)
	if _pattern_lbl:
		var n: int = max(1, _eligible.size())
		_pattern_lbl.text = "Pattern: %s  (%d/%d)" % [(key if key != "" else "—"), _pattern_idx + 1, n]
	_refresh_elig_display()   # keep the read-only eligible list's highlight on the just-spawned pattern
	_refresh_info()


# --- Faction eligibility (core-ship allowed_in) — Roman 2026-07-06 ---

# True if this scene is a CORE/universal ship — the only kind whose faction eligibility (allowed_in) is
# meaningful. Faction-exclusive units are fixed to their home faction, so the control is hidden for them.
func _is_core_ship(path: String) -> bool:
	var t: Variant = Factions.ENEMY_TAGS.get(path, null)
	return t is Dictionary and bool(t.get("universal", false))


# The default allowed-in faction id list for a scene, from its ENEMY_TAGS tag: an explicit "allowed_in"
# whitelist if present, else all four (a universal with no whitelist), else the home faction alone.
func _default_allowed_in(path: String) -> Array:
	var t: Variant = Factions.ENEMY_TAGS.get(path, null)
	if not (t is Dictionary):
		return [0, 1, 2, 3]
	var wl: Variant = t.get("allowed_in", null)
	if wl is Array:
		var out: Array = []
		for v in wl:
			out.append(int(v))
		return out
	if bool(t.get("universal", false)):
		return [0, 1, 2, 3]
	return [int(t.get("home", 0))]


# The faction ids currently ticked in the eligibility row (ordered by Factions.Id).
func _selected_allowed_in() -> Array:
	var out: Array = []
	for i in _faction_elig_chks.size():
		if (_faction_elig_chks[i] as CheckBox).button_pressed:
			out.append(i)
	return out


# Set the eligibility checkboxes from an id list + show/hide the row for core vs exclusive ships.
func _set_faction_elig(path: String, ids: Array) -> void:
	var is_core: bool = _is_core_ship(path)
	if _faction_elig_row != null:
		_faction_elig_row.visible = is_core
	if _faction_elig_caption != null:
		_faction_elig_caption.visible = is_core
	for i in _faction_elig_chks.size():
		(_faction_elig_chks[i] as CheckBox).button_pressed = i in ids


# The "Turret payload" dropdown only does anything for enemies with BAKED child turrets and no mounts
# (mount turrets carry their own payload). Hide the header + dropdown otherwise so it isn't offered on
# enemies that have no turret (Roman 2026-06-29).
func _update_turret_payload_visibility(inst: Node) -> void:
	var has_turret: bool = inst != null and _mount_dicts.is_empty() and not _collect_turrets(inst, []).is_empty()
	if _payload_dd:
		_payload_dd.visible = has_turret
	if _weapon_header:
		_weapon_header.visible = has_turret


# The faction Id for the selected enemy's group (folder), so the bench preview swaps the family
# payloads to the right faction's bullet style. -1 = no skin (Core / Hazards / All → authored base).
func _faction_id_for_selected() -> int:
	match _group_of(_selected_path):
		"Supremacy": return Factions.Id.SUPREMACY
		"Privateer": return Factions.Id.PRIVATEER
		"Corporate": return Factions.Id.CORPORATE
		"Zealot": return Factions.Id.ZEALOT
	return -1


# The BulletVariant currently picked in the Payload dropdown.
func _selected_payload():
	var pkeys: Array = PAYLOADS.keys()
	var pname: String = String(pkeys[clampi(_payload_dd.selected, 0, pkeys.size() - 1)])
	return PAYLOADS[pname]


# ---- Mounts editor -------------------------------------------------------
# Mounts are extra hardpoints (gun/turret/launcher/beam/entity) beyond the hull weapon (Mount 0). The
# working list `_mount_dicts` holds JSON-friendly name-based dicts; _mount_spec_dicts() resolves them to
# the roster dict schema EnemyRoster.make_mount_specs() converts into live MountSpecs at spawn, and
# _mount_copy_line() emits the same schema as a paste-ready roster literal.
#
# ONE field-schema table (MOUNT_FIELDS, Roman 2026-07-07) is the single source of truth for the
# roster⇄bench mount round-trip. It replaces four hand-synced copies (spec_dicts / copy_line /
# roster→bench) that drifted out of step and silently corrupted enemies on each roster→bench→Copy pass.
# Each entry:
#   bench   — key in the bench `_mount_dicts` dict
#   roster  — key in the roster mount dict (what enemy_roster.gd _mount_from_dict reads / Copy emits)
#   type    — "s"(string) "f"(float) "i"(int) "b"(bool)
#   def     — the ROSTER default (MUST match _mount_from_dict exactly); the sentinel DEF_ENTITY_INERTIA
#             means "true for entity, false otherwise" (roster's per-kind no_inertia default)
#   kinds   — mount kinds the field applies to; only those serialize/round-trip/copy it
#   omit    — Copy omit rule vs the roster default: "eq_def" (skip at default), "gt0"/"ge0"/"gt1", ""
#             (always emit). LIVE serialization always writes (make_mount_specs reads the roster default
#             itself, so an omitted-in-copy field stays correct live).
# payload / the single bench "fire" key (→ roster fire_min+fire_max) / beam_config / turret gfx are
# handled specially (not simple 1:1 fields) — see _mount_spec_dicts / _mount_copy_line.
const DEF_ENTITY_INERTIA := "@entity_inertia"   # sentinel: roster no_inertia default is (kind == ENTITY)
const MOUNT_FIELDS := [
	# firing knobs shared by gun/launcher/turret
	{"bench": "bullet_speed", "roster": "bullet_speed", "type": "f", "def": -1.0, "kinds": ["gun", "launcher", "turret"], "omit": "ge0"},
	# entity move_speed override: the bench UI's "speed" spin (min 0) stores it as bullet_speed. Roster
	# default is -1 (payload's own speed); a 0 is a valid explicit override, so match gun's def/omit so
	# both an omitted (-1) and an explicit 0 round-trip losslessly.
	{"bench": "bullet_speed", "roster": "bullet_speed", "type": "f", "def": -1.0, "kinds": ["entity"], "omit": "ge0"},
	{"bench": "burst_interval", "roster": "burst_interval", "type": "f", "def": 0.0, "kinds": ["gun", "launcher", "turret"], "omit": "gt0"},
	{"bench": "deviation_deg", "roster": "deviation_deg", "type": "f", "def": 0.0, "kinds": ["gun", "launcher", "turret"], "omit": "gt0"},
	{"bench": "volleys", "roster": "volleys", "type": "i", "def": 1, "kinds": ["gun", "launcher", "turret"], "omit": "gt1"},
	{"bench": "volley_gap", "roster": "volley_gap", "type": "f", "def": 0.0, "kinds": ["gun", "launcher", "turret"], "omit": "gt0"},
	{"bench": "payload_delay_ms", "roster": "payload_delay_ms", "type": "f", "def": 0.0, "kinds": ["gun", "launcher", "turret", "entity"], "omit": "gt0"},
	# gun/launcher (+entity) only
	{"bench": "marker_mode", "roster": "marker_mode", "type": "s", "def": "all", "kinds": ["gun", "launcher", "entity"], "omit": "eq_def"},
	# no_inertia applies to every fired/dropped kind (the push turret drops a no-inertia slug). Roster
	# default is per-kind: true for ENTITY, false otherwise (the DEF_ENTITY_INERTIA sentinel).
	{"bench": "no_inertia", "roster": "no_inertia", "type": "b", "def": DEF_ENTITY_INERTIA, "kinds": ["gun", "launcher", "turret", "entity"], "omit": "eq_def"},
	{"bench": "max_fires", "roster": "max_fires", "type": "i", "def": 0, "kinds": ["gun", "launcher", "entity"], "omit": "gt0"},
	# entity-only emit knobs
	{"bench": "trigger", "roster": "trigger", "type": "s", "def": "cadence", "kinds": ["entity"], "omit": ""},
	{"bench": "scatter", "roster": "scatter", "type": "f", "def": 0.0, "kinds": ["entity"], "omit": "gt0"},
	{"bench": "max_emits", "roster": "max_emits", "type": "i", "def": 0, "kinds": ["entity"], "omit": "gt0"},
	{"bench": "band_only", "roster": "band_only", "type": "b", "def": false, "kinds": ["entity"], "omit": "eq_def"},
]


# Resolve a schema field's roster default for one mount kind (handles the per-kind inertia sentinel).
func _field_default(f: Dictionary, kind: String):
	var d = f["def"]
	if d is String and String(d) == DEF_ENTITY_INERTIA:
		return kind == "entity"
	return d


# Read a bench-dict value for a schema field (falling back to the field's roster default), type-coerced.
func _field_val(f: Dictionary, d: Dictionary, kind: String):
	var raw = d.get(f["bench"], _field_default(f, kind))
	match String(f["type"]):
		"s": return String(raw)
		"f": return float(raw)
		"i": return int(raw)
		"b": return bool(raw)
	return raw


# True if a schema field applies to this mount kind.
func _field_applies(f: Dictionary, kind: String) -> bool:
	return (f["kinds"] as Array).has(kind)


# The bench payload NAME for a mount dict (entity/beam default to Bomblet/… vs Ball for a bullet mount).
func _mount_payload_name(d: Dictionary) -> String:
	var k: String = String(d.get("kind", "gun"))
	return String(d.get("payload", ("Bomblet" if k == "entity" else "Ball")))


# The mount's fire_max: the single-rate bench UI drives one "fire" value, but a roster mount may author
# a min<max cadence window. We preserve that authored max in the bench dict as "fire_max" so it round-
# trips losslessly; when absent (a bench-authored mount), it collapses to the single "fire" value.
func _fire_max_of(d: Dictionary) -> float:
	return float(d.get("fire_max", d.get("fire", 1.5)))


func _mount_spec_dicts() -> Array:
	var out: Array = []
	for d in _mount_dicts:
		var k: String = String(d.get("kind", "gun"))
		var pname: String = _mount_payload_name(d)
		var sd: Dictionary = {
			"kind": k, "marker": String(d.get("marker", "")),
			"aim": String(d.get("aim", "straight_down")),
			"fire_min": float(d.get("fire", 1.5)), "fire_max": _fire_max_of(d),
			"count": int(d.get("count", 1)), "spread_deg": float(d.get("spread", 0.0)),
		}
		# Payload: entity scene path / beam config / bullet variant / projectile scene.
		if k == "entity":
			sd["payload_scene"] = _emitter_payload_path(pname)
		elif pname == BEAM_PAYLOAD_NAME:
			sd["beam_config"] = _beam_config_from(d)   # beam payload → BeamEmitter (editable config)
			sd["marker_mode"] = String(d.get("marker_mode", "all"))   # Both / Alternating muzzles
		elif PAYLOADS.has(pname):
			sd["payload"] = PAYLOADS[pname]
		elif PROJECTILES.has(pname):
			sd["payload_scene"] = PROJECTILES[pname]
		# Schema-driven fields (LIVE spec always writes — make_mount_specs applies the roster default itself).
		for f in MOUNT_FIELDS:
			if _field_applies(f, k):
				sd[f["roster"]] = _field_val(f, d, k)
		# Firing-condition gates (gun/launcher only) — honoured by MountComponent. The zone gate was
		# retired 2026-06-29 (off-screen suppression is already universal via _on_playfield).
		if k == "gun" or k == "launcher":
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
			# Prefer the enemy's OWN turret graphic/config when it carries one (ground turrets: per-enemy
			# barrel art + frame + z + muzzle_distance); else derive a visible turret from the faction
			# group (bench-added mounts, which have no roster gfx).
			var tex := String(d.get("turret_texture", ""))
			if tex != "":
				sd["turret_texture"] = tex
				sd["turret_hframes"] = int(d.get("turret_hframes", 1))
				sd["turret_frame"] = int(d.get("turret_frame", 0))
				sd["turret_z"] = int(d.get("turret_z", 0))
				sd["muzzle_distance"] = float(d.get("muzzle_distance", 0.0))
				sd["recoil_frames"] = int(d.get("recoil_frames", 0))
			else:
				var g: Dictionary = TURRET_GFX.get(_group_of(_selected_path), TURRET_GFX_DEFAULT)
				sd["turret_texture"] = g["tex"]
				sd["turret_hframes"] = g["hframes"]
				sd["recoil_frames"] = g["recoil"]
			sd["rotation_speed"] = float(d.get("rotation_speed", 3.6))
			sd["aim_tolerance_deg"] = float(d.get("aim_tolerance_deg", 14.0))
		out.append(sd)
	return out


func _add_mount() -> void:
	var fresh: Dictionary = {"kind": "gun", "marker": "", "payload": "Ball", "aim": "straight_down", "fire": 1.5, "count": 1, "spread": 0.0, "marker_mode": "cycle", "burst_interval": 0.0, "bullet_speed": -1.0, "no_inertia": true, "payload_delay_ms": 0.0, "nose_gated": false, "aim_tol": 18.0, "path_phases": "", "beat_synced": true, "on_phase": ""}
	_mount_dicts.append(fresh)
	# User-added: its own initial values ARE the baseline, so a fresh mount shows NO affordances until the
	# user edits it. (Snapshot, not {} — the fresh gun defaults intentionally diverge from the roster
	# schema, e.g. inertia-off; comparing against schema defaults would false-positive on an untouched add.)
	_mount_baked.append(fresh.duplicate(true))
	_rebuild_mounts_ui()
	_spawn_current()


func _remove_mount(d: Dictionary) -> void:
	var i: int = _mount_dicts.find(d)
	if i >= 0:
		_mount_dicts.remove_at(i)
		if i < _mount_baked.size():
			_mount_baked.remove_at(i)   # keep the baked reference index-aligned
	else:
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
	_style_button(rm)
	rm.add_theme_font_size_override("font_size", FS_CAPTION)
	rm.pressed.connect(func(): _remove_mount(d))
	head.add_child(rm)
	row.add_child(head)

	# Every field as a labelled row in a 2-col grid (label | control), one per line — see _grid_row.
	var grid := _field_grid()
	row.add_child(grid)

	var kind_dd := _row_dd(MOUNT_KIND_LABELS, MOUNT_KINDS.find(String(d.get("kind", "gun"))))
	kind_dd.item_selected.connect(func(i):
		_set_mount(d, "kind", MOUNT_KINDS[i])
		_rebuild_mounts_ui.call_deferred())   # kind changes which fields show — rebuild the rows (deferred = safe)
	_grid_row(grid, "kind", kind_dd)

	var mopts: Array = _marker_options(_selected_path)
	var cur_mk: String = _marker_label(String(d.get("marker", "")))
	if not mopts.has(cur_mk):
		mopts.append(cur_mk)   # keep a glob like "Turret*" (from a roster mount) selectable
	var mk_dd := _row_dd(mopts, maxi(0, mopts.find(cur_mk)))
	mk_dd.item_selected.connect(func(i): _set_mount(d, "marker", _marker_value(String(mopts[i]))))
	_grid_row(grid, "marker", mk_dd)

	var k: String = String(d.get("kind", "gun"))
	var is_entity: bool = k == "entity"
	var pnames: Array = _emitter_payload_options() if is_entity else _mount_payload_names()
	var def_pay: String = "Bomblet" if is_entity else "Ball"
	var pay_dd := _row_dd(pnames, maxi(0, pnames.find(String(d.get("payload", def_pay)))))
	pay_dd.item_selected.connect(func(i): _set_mount(d, "payload", String(pnames[i])))
	_grid_row(grid, "payload", pay_dd)

	var aim_dd := _row_dd(MOUNT_AIM_LABELS, maxi(0, MOUNT_AIM_KEYS.find(String(d.get("aim", "straight_down")))))
	aim_dd.item_selected.connect(func(i): _set_mount(d, "aim", MOUNT_AIM_KEYS[i]))
	_grid_row(grid, "aim", aim_dd)

	var rate := _row_spin(0.1, 6.0, 0.1, float(d.get("fire", 1.5)))
	rate.value_changed.connect(func(v): _set_mount(d, "fire", float(v)))
	_grid_row(grid, "rate", rate)

	var cnt := _row_spin(1, 12, 1, float(d.get("count", 1)))
	cnt.value_changed.connect(func(v): _set_mount(d, "count", int(v)))
	_grid_row(grid, "count", cnt)

	var spr := _row_spin(0.0, 90.0, 2.0, float(d.get("spread", 0.0)))
	spr.value_changed.connect(func(v): _set_mount(d, "spread", float(v)))
	_grid_row(grid, "spread", spr)

	# Firing pattern controls for gun/launcher mounts only.
	if k == "gun" or k == "launcher":
		# muzzles: which marker(s) fire each shot — All (every marker) vs Cycle (round-robin).
		var sync_keys: Array = ["all", "cycle", "inward", "outward"]
		var sync_dd := _row_dd(["All", "Cycle", "Inward", "Outward"], maxi(0, sync_keys.find(String(d.get("marker_mode", "cycle")))))
		sync_dd.item_selected.connect(func(i): _set_mount(d, "marker_mode", String(sync_keys[i])))
		_grid_row_dec(grid, "muzzles", sync_dd, maxi(0, sync_keys.find(String(_mount_field_baked(idx, "marker_mode", k)))))

		# volley: fire all `count` bullets at once (Simultaneous, burst_interval 0) or spaced out (Burst,
		# burst_interval seconds between shots). The burst-gap spin only shows in Burst mode.
		var is_burst: bool = float(d.get("burst_interval", 0.0)) > 0.0
		var volley_dd := _row_dd(["Simultaneous", "Burst"], 1 if is_burst else 0)
		_grid_row(grid, "volley", volley_dd)
		var burst_lbl := _grid_label(grid, "burst gap")
		var burst := _row_spin(0.02, 0.5, 0.01, maxf(0.1, float(d.get("burst_interval", 0.1))))
		burst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(burst)
		burst_lbl.visible = is_burst
		burst.visible = is_burst
		volley_dd.item_selected.connect(func(i):
			var on: bool = i == 1
			burst_lbl.visible = on
			burst.visible = on
			_set_mount(d, "burst_interval", float(burst.value) if on else 0.0))
		burst.value_changed.connect(func(v):
			if volley_dd.selected == 1:
				_set_mount(d, "burst_interval", float(v)))

		var spd := _row_spin(-1.0, 600.0, 10.0, float(d.get("bullet_speed", -1.0)))
		spd.value_changed.connect(func(v): _set_mount(d, "bullet_speed", float(v)))
		_grid_row_dec(grid, "speed", spd, float(_mount_field_baked(idx, "bullet_speed", k)))

		# Deviation: random ± angle jitter per shot (inaccuracy). 0 = pinpoint.
		var dev := _row_spin(0.0, 90.0, 1.0, float(d.get("deviation_deg", 0.0)))
		dev.value_changed.connect(func(v): _set_mount(d, "deviation_deg", float(v)))
		_grid_row_dec(grid, "deviation", dev, float(_mount_field_baked(idx, "deviation_deg", k)))

		# Max fires: cap the shots per pass (0 = unlimited).
		var maxf := _row_spin(0, 20, 1, float(d.get("max_fires", 0)))
		maxf.value_changed.connect(func(v): _set_mount(d, "max_fires", int(v)))
		_grid_row_dec(grid, "max fires", maxf, float(_mount_field_baked(idx, "max_fires", k)))

		# Volleys: fire the whole spread this many times (a 3-shot spread x 4 volleys = 12), staggered
		# by the volley gap. 1 = a single volley (burst gap above still staggers shots within it).
		var vol := _row_spin(1, 12, 1, float(d.get("volleys", 1)))
		vol.value_changed.connect(func(v): _set_mount(d, "volleys", int(v)))
		_grid_row_dec(grid, "volleys", vol, float(_mount_field_baked(idx, "volleys", k)))

		var vgap := _row_spin(0.0, 1.0, 0.02, float(d.get("volley_gap", 0.0)))
		vgap.value_changed.connect(func(v): _set_mount(d, "volley_gap", float(v)))
		_grid_row_dec(grid, "volley gap", vgap, float(_mount_field_baked(idx, "volley_gap", k)))

		# Payload toggles (Roman 2026-07-03) — opt-in, off by default. Inertia ON = the shot carries the
		# enemy's velocity (Doppler); OFF (new-mount default) = it drops at its own speed. Stored as the
		# inverse no_inertia, so existing mounts keep their behaviour (absent key = carries). The affordance
		# compares the UI's inertia bool, so bake the INVERSE of the roster no_inertia default.
		var inertia_chk := _row_check(not bool(d.get("no_inertia", false)))
		inertia_chk.toggled.connect(func(on): _set_mount(d, "no_inertia", not on))
		_grid_row_dec(grid, "inertia", inertia_chk, not bool(_mount_field_baked(idx, "no_inertia", k)))

		# Delay: the payload holds at the muzzle this many milliseconds before its motion begins.
		var delay_spin := _row_spin(0.0, 2000.0, 10.0, float(d.get("payload_delay_ms", 0.0)))
		delay_spin.value_changed.connect(func(v): _set_mount(d, "payload_delay_ms", float(v)))
		_grid_row_dec(grid, "delay ms", delay_spin, float(_mount_field_baked(idx, "payload_delay_ms", k)))

		# Firing conditions: nose gate + path-phase mode (mirror the hull shoot). The old "zone" toggle
		# was dropped 2026-06-29 — off-screen suppression is already universal (_on_playfield), so the
		# per-mount zone gate was redundant clutter.
		var nose_chk := _row_check(bool(d.get("nose_gated", false)))
		nose_chk.toggled.connect(func(on): _set_mount(d, "nose_gated", on))
		_grid_row(grid, "nose", nose_chk)

		var tol := _row_spin(2.0, 90.0, 1.0, float(d.get("aim_tol", 18.0)))
		tol.value_changed.connect(func(v): _set_mount(d, "aim_tol", float(v)))
		_grid_row(grid, "tol", tol)

		var pp := _row_line(String(d.get("path_phases", "")), "0.4,0.7")
		pp.text_submitted.connect(func(t): _set_mount(d, "path_phases", t))
		pp.focus_exited.connect(func(): _set_mount(d, "path_phases", pp.text))
		_grid_row(grid, "path", pp)

		var beat_chk := _row_check(bool(d.get("beat_synced", true)))
		beat_chk.toggled.connect(func(on): _set_mount(d, "beat_synced", on))
		_grid_row(grid, "beat", beat_chk)

		var phase_ed := _row_line(String(d.get("on_phase", "")), "name")
		phase_ed.text_submitted.connect(func(t): _set_mount(d, "on_phase", t))
		phase_ed.focus_exited.connect(func(): _set_mount(d, "on_phase", phase_ed.text))
		_grid_row(grid, "phase", phase_ed)

	# Turret firing settings (Hardpoint v2 Phase B 2026-07-05): a turret honors the shared burst /
	# deviation / volley / delay knobs, and can deliver a projectile payload (pick one in the payload
	# dropdown above). The gun/launcher-only knobs (muzzle mode, nose/path gates, max-fires) don't apply
	# to a self-aiming turret, so they're intentionally absent here.
	if k == "turret":
		var is_tburst: bool = float(d.get("burst_interval", 0.0)) > 0.0
		var tvolley_dd := _row_dd(["Simultaneous", "Burst"], 1 if is_tburst else 0)
		_grid_row(grid, "volley", tvolley_dd)
		var tburst_lbl := _grid_label(grid, "burst gap")
		var tburst := _row_spin(0.02, 0.5, 0.01, maxf(0.1, float(d.get("burst_interval", 0.1))))
		tburst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tburst)
		tburst_lbl.visible = is_tburst
		tburst.visible = is_tburst
		tvolley_dd.item_selected.connect(func(i):
			var on: bool = i == 1
			tburst_lbl.visible = on
			tburst.visible = on
			_set_mount(d, "burst_interval", float(tburst.value) if on else 0.0))
		tburst.value_changed.connect(func(v):
			if tvolley_dd.selected == 1:
				_set_mount(d, "burst_interval", float(v)))

		var tspd := _row_spin(-1.0, 600.0, 10.0, float(d.get("bullet_speed", -1.0)))
		tspd.value_changed.connect(func(v): _set_mount(d, "bullet_speed", float(v)))
		_grid_row_dec(grid, "speed", tspd, float(_mount_field_baked(idx, "bullet_speed", k)))

		var tdev := _row_spin(0.0, 90.0, 1.0, float(d.get("deviation_deg", 0.0)))
		tdev.value_changed.connect(func(v): _set_mount(d, "deviation_deg", float(v)))
		_grid_row_dec(grid, "deviation", tdev, float(_mount_field_baked(idx, "deviation_deg", k)))

		var tvol := _row_spin(1, 12, 1, float(d.get("volleys", 1)))
		tvol.value_changed.connect(func(v): _set_mount(d, "volleys", int(v)))
		_grid_row_dec(grid, "volleys", tvol, float(_mount_field_baked(idx, "volleys", k)))

		var tvgap := _row_spin(0.0, 1.0, 0.02, float(d.get("volley_gap", 0.0)))
		tvgap.value_changed.connect(func(v): _set_mount(d, "volley_gap", float(v)))
		_grid_row_dec(grid, "volley gap", tvgap, float(_mount_field_baked(idx, "volley_gap", k)))

		var tdelay := _row_spin(0.0, 2000.0, 10.0, float(d.get("payload_delay_ms", 0.0)))
		tdelay.value_changed.connect(func(v): _set_mount(d, "payload_delay_ms", float(v)))
		_grid_row_dec(grid, "delay ms", tdelay, float(_mount_field_baked(idx, "payload_delay_ms", k)))

	# Beam payload config (beam editor 2026-07-05): when the payload is a Beam, author its behavior — aim
	# mode (Forward/Locked/Tracking/Track-Lock), reach, dps, and the FSM timings. Assembled into a
	# beam_config by _beam_config_from; the mount kind is irrelevant (MountBuilder routes on beam_config).
	if String(d.get("payload", "")) == BEAM_PAYLOAD_NAME:
		var baim := _row_dd(BEAM_AIM_LABELS, maxi(0, BEAM_AIM_VALUES.find(int(d.get("beam_aim", 2)))))
		baim.item_selected.connect(func(i): _set_mount(d, "beam_aim", int(BEAM_AIM_VALUES[i])))
		_grid_row(grid, "beam aim", baim)
		# Muzzles: Both = every matched marker fires in sync; Alternating = the markers fire out of phase
		# (staggered by period/n). Needs a marker glob (e.g. Muzzle*) matching 2+ markers to matter.
		var bmuz_keys: Array = ["all", "cycle"]
		var bmuz := _row_dd(["Both", "Alternating"], maxi(0, bmuz_keys.find(String(d.get("marker_mode", "all")))))
		bmuz.item_selected.connect(func(i): _set_mount(d, "marker_mode", String(bmuz_keys[i])))
		_grid_row(grid, "muzzles", bmuz)
		var breach := _row_spin(60.0, 480.0, 10.0, float(d.get("beam_reach", 320.0)))
		breach.value_changed.connect(func(v): _set_mount(d, "beam_reach", float(v)))
		_grid_row(grid, "reach", breach)
		var bdps := _row_spin(0.5, 20.0, 0.5, float(d.get("beam_dps", 3.0)))
		bdps.value_changed.connect(func(v): _set_mount(d, "beam_dps", float(v)))
		_grid_row(grid, "dps", bdps)
		var bidle := _row_spin(0.0, 5.0, 0.1, float(d.get("beam_idle", 0.9)))
		bidle.value_changed.connect(func(v): _set_mount(d, "beam_idle", float(v)))
		_grid_row(grid, "idle s", bidle)
		# charge time = beam windup (thin telegraph ramps up); fire time = beam firing (lethal).
		var bwind := _row_spin(0.1, 5.0, 0.1, float(d.get("beam_windup", 1.3)))
		bwind.value_changed.connect(func(v): _set_mount(d, "beam_windup", float(v)))
		_grid_row(grid, "charge s", bwind)
		var bfire := _row_spin(0.1, 5.0, 0.1, float(d.get("beam_firing", 1.1)))
		bfire.value_changed.connect(func(v): _set_mount(d, "beam_firing", float(v)))
		_grid_row(grid, "fire s", bfire)
		var bcool := _row_spin(0.1, 5.0, 0.1, float(d.get("beam_cooldown", 1.5)))
		bcool.value_changed.connect(func(v): _set_mount(d, "beam_cooldown", float(v)))
		_grid_row(grid, "cooldown s", bcool)

	# Entity emitter fields (Phase 3): spawn the payload scene on a trigger. Cadence uses the "rate" row
	# above as the emit period; count = scenes per emit. aim/marker/spread rows are ignored for entities.
	if is_entity:
		var trig_keys: Array = ["cadence", "start", "death"]
		var trig_dd := _row_dd(["Cadence", "Start", "Death"], maxi(0, trig_keys.find(String(d.get("trigger", "cadence")))))
		trig_dd.item_selected.connect(func(i): _set_mount(d, "trigger", String(trig_keys[i])))
		_grid_row_dec(grid, "trigger", trig_dd, maxi(0, trig_keys.find(String(_mount_field_baked(idx, "trigger", k)))))

		var maxe := _row_spin(0, 20, 1, float(d.get("max_emits", 0)))
		maxe.value_changed.connect(func(v): _set_mount(d, "max_emits", int(v)))
		_grid_row_dec(grid, "max emits", maxe, float(_mount_field_baked(idx, "max_emits", k)))

		var scat := _row_spin(0.0, 60.0, 2.0, float(d.get("scatter", 0.0)))
		scat.value_changed.connect(func(v): _set_mount(d, "scatter", float(v)))
		_grid_row_dec(grid, "scatter", scat, float(_mount_field_baked(idx, "scatter", k)))

		var band_chk := _row_check(bool(d.get("band_only", false)))
		band_chk.toggled.connect(func(on): _set_mount(d, "band_only", on))
		_grid_row_dec(grid, "band only", band_chk, bool(_mount_field_baked(idx, "band_only", k)))

		# Inertia ON = the drop carries the enemy's velocity; OFF (default) = it drops at rest. Bake the
		# INVERSE of the roster no_inertia default (the UI shows inertia, the dict stores its negation).
		var einertia := _row_check(not bool(d.get("no_inertia", true)))
		einertia.toggled.connect(func(on): _set_mount(d, "no_inertia", not on))
		_grid_row_dec(grid, "inertia", einertia, not bool(_mount_field_baked(idx, "no_inertia", k)))

		# Delay: the dropped payload holds this many ms before its motion begins (bomblets/missiles honour it).
		var edelay := _row_spin(0.0, 2000.0, 10.0, float(d.get("payload_delay_ms", 0.0)))
		edelay.value_changed.connect(func(v): _set_mount(d, "payload_delay_ms", float(v)))
		_grid_row_dec(grid, "delay ms", edelay, float(_mount_field_baked(idx, "payload_delay_ms", k)))

		# Speed: overrides the dropped entity's move_speed (px/s), so bench == live. 0 = the payload's own.
		# The spin clamps negatives to 0 (entity roster default is -1), so clamp the baked ref the same way.
		var espeed := _row_spin(0.0, 480.0, 10.0, maxf(0.0, float(d.get("bullet_speed", 0.0))))
		espeed.value_changed.connect(func(v): _set_mount(d, "bullet_speed", float(v)))
		_grid_row_dec(grid, "speed", espeed, maxf(0.0, float(_mount_field_baked(idx, "bullet_speed", k))))

	return row


# ---- Emitter payload resolution (legacy fold-in) -------------------------
# The Emitters editor was retired (droppers/spawners are "Entity" hardpoints in the Mounts list), but a
# legacy roster/saved "emitters" block still FOLDS IN as entity mounts on load — these helpers resolve
# its payload names ⇄ scene paths, and _emitter_dict_to_mount rewrites one emitter dict as an entity mount.

# Every emitter payload the bench offers: the named projectiles/mines (EMITTER_PAYLOADS) + every enemy
# (so an entity mount can drop other enemies, Roman 2026-06-29). Enemy entries use their display name.
func _emitter_payload_options() -> Array:
	var out: Array = EMITTER_PAYLOADS.keys().duplicate()
	for p in EnemyManifest.all_enemies(false):
		out.append(EnemyStrings.display_name(String(p)))
	return out


# Resolve an emitter payload NAME to its scene path (named projectile/mine, else an enemy display name).
func _emitter_payload_path(name: String) -> String:
	if EMITTER_PAYLOADS.has(name):
		return String(EMITTER_PAYLOADS[name])
	for p in EnemyManifest.all_enemies(false):
		if EnemyStrings.display_name(String(p)) == name:
			return String(p)
	return String(EMITTER_PAYLOADS.get("Missile", ""))


# Phase 3: convert a legacy emitter dict into a unified ENTITY mount dict, so a saved enemy's droppers
# load into the single Hardpoints (mounts) list. `drop` (default true) -> no_inertia; "timer" -> cadence.
func _emitter_dict_to_mount(e: Dictionary) -> Dictionary:
	var trig: String = String(e.get("trigger", "timer"))
	if trig == "timer":
		trig = "cadence"
	return {
		"kind": "entity",
		"payload": String(e.get("payload", "Bomblet")),
		"trigger": trig,
		"fire": float(e.get("cadence", 2.0)),
		"count": int(e.get("count", 1)),
		"max_emits": int(e.get("max_emits", 0)),
		"band_only": bool(e.get("band_only", false)),
		"scatter": float(e.get("spread", 0.0)),
		"no_inertia": bool(e.get("drop", true)),
	}


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


# Map a roster emitter "payload" (a friendly name OR a raw scene path) back to a bench dropdown name.
func _emitter_payload_name(d: Dictionary) -> String:
	var pv = d.get("payload", "Missile")
	if pv is String:
		if EMITTER_PAYLOADS.has(pv):
			return pv
		for k in EMITTER_PAYLOADS:
			if String(EMITTER_PAYLOADS[k]) == String(pv):
				return String(k)
		for p in EnemyManifest.all_enemies(false):
			if String(p) == String(pv):
				return EnemyStrings.display_name(String(p))
	return "Missile"


# ---- Orbit rings editor (cluster-mine / bloom) ---------------------------
# An OrbitComponent: N rings of payloads orbiting the enemy, RELEASED on death. mode "live" = real
# bomblets fly free with their orbit momentum; "visual" = bullet shells erupt radially outward. The
# generalization of the gravity-mine + bloom enemies — added to any enemy's components here.

func _setup_orbit_editor(scroll: Control) -> void:
	if scroll == null or scroll.get_child_count() == 0:
		return
	var content := scroll.get_child(0)
	if not (content is Container):
		return
	content.add_child(HSeparator.new())
	content.add_child(_mk_label("Orbit rings (held → released on death)", 16, Color(0.62, 0.82, 1, 1)))
	content.add_child(_mk_label("Rings of payloads orbiting the enemy, freed on death — the cluster mine / bloom. Live = real hittable bomblets; Visual = bullet shells flung outward.", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	content.add_child(_mk_label("Mode", FS_CAPTION, Color(0.70, 0.78, 0.88, 0.70)))
	_orbit_mode_dd = OptionButton.new()
	_orbit_mode_dd.add_item("Live (bomblets)")
	_orbit_mode_dd.add_item("Visual (bullets)")
	_orbit_mode_dd.select(0 if _orbit_mode == "live" else 1)
	_orbit_mode_dd.custom_minimum_size = Vector2(0, 30)
	_orbit_mode_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orbit_mode_dd.item_selected.connect(func(i):
		_orbit_mode = "live" if i == 0 else "visual"
		_rebuild_orbit_ui()
		if not _loading:
			_spawn_current())
	content.add_child(_orbit_mode_dd)
	_orbit_list = VBoxContainer.new()
	_orbit_list.add_theme_constant_override("separation", 6)
	content.add_child(_orbit_list)
	var add := Button.new()
	add.text = "+ Add Ring"
	_style_button(add)
	add.pressed.connect(_add_orbit_ring)
	content.add_child(add)
	_rebuild_orbit_ui()


# Payload options for an orbit ring: bomblets (Live) or bullet families (Visual).
func _orbit_payload_options() -> Array:
	return ORBIT_LIVE_PAYLOADS.keys() if _orbit_mode == "live" else PAYLOADS.keys()


func _add_orbit_ring() -> void:
	_orbit_rings.append({"radius": 16.0, "count": 6, "speed": 1.6, "payload": ("Bomblet" if _orbit_mode == "live" else "Ball")})
	_rebuild_orbit_ui()
	_spawn_current()


func _remove_orbit_ring(d: Dictionary) -> void:
	_orbit_rings.erase(d)
	_rebuild_orbit_ui()
	_spawn_current()


func _set_orbit_ring(d: Dictionary, key: String, value) -> void:
	d[key] = value
	_spawn_current()


func _rebuild_orbit_ui() -> void:
	if _orbit_list == null:
		return
	for c in _orbit_list.get_children():
		_orbit_list.remove_child(c)
		c.queue_free()
	for i in _orbit_rings.size():
		_orbit_list.add_child(_make_orbit_ring_row(i))
	_tighten_panel(_orbit_list)


func _make_orbit_ring_row(idx: int) -> Control:
	var d: Dictionary = _orbit_rings[idx]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	var title := _row_lbl("Ring %d" % (idx + 1))
	title.add_theme_color_override("font_color", Color(0.62, 0.82, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var rm := Button.new()
	rm.text = "✕"
	_style_button(rm)
	rm.add_theme_font_size_override("font_size", FS_CAPTION)
	rm.pressed.connect(func(): _remove_orbit_ring(d))
	head.add_child(rm)
	row.add_child(head)
	var grid := _field_grid()
	row.add_child(grid)
	var pnames: Array = _orbit_payload_options()
	var pay_dd := _row_dd(pnames, maxi(0, pnames.find(String(d.get("payload", "")))))
	pay_dd.item_selected.connect(func(i): _set_orbit_ring(d, "payload", String(pnames[i])))
	_grid_row(grid, "payload", pay_dd)
	var rad := _row_spin(4.0, 64.0, 1.0, float(d.get("radius", 16.0)))
	rad.value_changed.connect(func(v): _set_orbit_ring(d, "radius", float(v)))
	_grid_row(grid, "radius", rad)
	var cnt := _row_spin(1, 24, 1, float(d.get("count", 6)))
	cnt.value_changed.connect(func(v): _set_orbit_ring(d, "count", int(v)))
	_grid_row(grid, "count", cnt)
	var spd := _row_spin(-6.0, 6.0, 0.2, float(d.get("speed", 1.6)))
	spd.value_changed.connect(func(v): _set_orbit_ring(d, "speed", float(v)))
	_grid_row(grid, "spin rad/s", spd)
	return row


# Build a live OrbitComponent from the ring dicts (Live → bomblet scenes, Visual → bullet variants).
func _build_orbit():
	var oc = OrbitComponentC.new()
	oc.mode = OrbitComponentC.Mode.LIVE if _orbit_mode == "live" else OrbitComponentC.Mode.VISUAL
	oc.host_drift = 60.0
	var rings: Array = []
	for r in _orbit_rings:
		var ring: Dictionary = {"radius": float(r.get("radius", 16.0)), "count": int(r.get("count", 6)), "speed": float(r.get("speed", 1.6))}
		var pname: String = String(r.get("payload", ""))
		if _orbit_mode == "live":
			ring["scene"] = load(String(ORBIT_LIVE_PAYLOADS.get(pname, ORBIT_LIVE_PAYLOADS["Bomblet"])))
		else:
			ring["variant"] = PAYLOADS.get(pname, PAYLOADS.get("Ball", null))
		rings.append(ring)
	oc.rings = rings
	return oc


# A paste-ready roster "mounts" entry for the authored orbit as a kind:"ring" hardpoint (Phase C). The
# ring is authored in the dedicated Orbit panel (a nested mode+rings collection that doesn't fit a flat
# mount row), but its ROSTER OUTPUT is now a unified RING hardpoint, not a bespoke OrbitComponent.
func _orbit_mount_copy_line() -> String:
	var ring_parts: Array = []
	for r in _orbit_rings:
		var pname: String = String(r.get("payload", ""))
		var pay: String
		if _orbit_mode == "live":
			pay = "\"scene\": preload(\"%s\")" % String(ORBIT_LIVE_PAYLOADS.get(pname, ORBIT_LIVE_PAYLOADS["Bomblet"]))
		else:
			pay = "\"variant\": %s" % String(PAYLOAD_CONST.get(pname, PAYLOAD_CONST["Ball"]))
		ring_parts.append("{ \"radius\": %.0f, \"count\": %d, \"speed\": %.2f, %s }" % [
			float(r.get("radius", 16.0)), int(r.get("count", 6)), float(r.get("speed", 1.6)), pay])
	# orbit_mode: 0 = VISUAL, 1 = LIVE. host_drift only matters for LIVE (matches _build_orbit's 60).
	var mode_i: int = 1 if _orbit_mode == "live" else 0
	var drift: String = ", \"host_drift\": 60.0" if _orbit_mode == "live" else ""
	return "{ \"kind\": \"ring\", \"orbit_mode\": %d%s, \"rings\": [%s] }," % [mode_i, drift, ", ".join(ring_parts)]


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
	names.append(BEAM_PAYLOAD_NAME)
	return names


# Assemble a live beam_config from a mount dict's editable beam_* fields (over BEAM_DEFAULT).
func _beam_config_from(d: Dictionary) -> Dictionary:
	var cfg: Dictionary = BEAM_DEFAULT.duplicate(true)
	cfg["aim_mode"] = int(d.get("beam_aim", 2))            # default Tracking
	cfg["reach"] = float(d.get("beam_reach", 320.0))
	cfg["dps"] = float(d.get("beam_dps", 3.0))
	cfg["idle_time"] = float(d.get("beam_idle", 0.9))
	cfg["windup_time"] = float(d.get("beam_windup", 1.3))
	cfg["firing_time"] = float(d.get("beam_firing", 1.1))
	cfg["cooldown_time"] = float(d.get("beam_cooldown", 1.5))
	if int(cfg["aim_mode"]) == 2:                          # TRACKING needs a re-aim rate
		cfg["tracking_rate"] = 1.3
	return cfg


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


# Convert a production roster mount dict → the bench's name-based dict shape, so a migrated enemy shows
# + fires its real mounts and Copy re-emits them losslessly. Schema-driven: every MOUNT_FIELDS field is
# read back through its ROSTER default (matching _mount_from_dict exactly), so an absent-in-roster field
# becomes the same default the roster would apply — no default-shift on the round-trip. (Roman 2026-07-07:
# this replaces the hand-picked subset that dropped max_fires/deviation/volleys/entity-emit fields and
# mismatched marker_mode/no_inertia defaults, corrupting enemies on each intake pass.)
func _roster_mount_to_bench(d: Dictionary) -> Dictionary:
	var k: String = String(d.get("kind", "gun"))
	var pp_toks: Array = []
	var pp_arr = d.get("fire_path_phases", [])
	if pp_arr != null:
		for f in pp_arr:
			pp_toks.append(str(f))
	# Extract a beam mount's beam_config into the editable beam_* fields so it round-trips into the editor.
	var bcv = d.get("beam_config", null)
	var bc: Dictionary = bcv if bcv is Dictionary else {}
	var out: Dictionary = {
		"kind": k,
		"marker": String(d.get("marker", "")),
		"aim": String(d.get("aim", "straight_down")),
		"fire": float(d.get("fire_min", d.get("fire_max", 1.5))),
		# Preserve an authored min<max cadence window (the single-rate UI shows fire_min; fire_max is kept
		# for a lossless Copy round-trip). Only carried when it actually differs from fire_min.
		"fire_max": float(d.get("fire_max", d.get("fire_min", 1.5))),
		"count": int(d.get("count", 1)),
		"spread": float(d.get("spread_deg", 0.0)),
		"payload": _payload_name_of(d),
		# gun/launcher firing-condition gates (aliased roster keys / string+array shapes, not table fields).
		"nose_gated": bool(d.get("fire_only_on_target", false)),
		"aim_tol": float(d.get("fire_aim_tol_deg", 18.0)),
		"path_phases": ",".join(pp_toks),
		"beat_synced": bool(d.get("fire_beat_synced", true)),
		"on_phase": String(d.get("fire_on_phase", "")),
		# beam config → editable beam_* fields.
		"beam_aim": int(bc.get("aim_mode", 2)),
		"beam_reach": float(bc.get("reach", 320.0)),
		"beam_dps": float(bc.get("dps", 3.0)),
		"beam_idle": float(bc.get("idle_time", 0.9)),
		"beam_windup": float(bc.get("windup_time", 1.3)),
		"beam_firing": float(bc.get("firing_time", 1.1)),
		"beam_cooldown": float(bc.get("cooldown_time", 1.5)),
	}
	# Every schema field, read back through its per-kind ROSTER default (no default-shift).
	for f in MOUNT_FIELDS:
		if _field_applies(f, k):
			out[f["bench"]] = _field_val_from_roster(f, d, k)
	# Turret graphic + aim config — carried as data (NOT MOUNT_FIELDS, to avoid a path text field in the
	# UI) so a ground turret's per-enemy barrel art / frame / z / muzzle round-trips instead of being
	# re-derived to a generic faction turret. (Roman 2026-07-13.)
	if k == "turret":
		out["turret_texture"] = String(d.get("turret_texture", ""))
		out["turret_hframes"] = int(d.get("turret_hframes", 1))
		out["turret_frame"] = int(d.get("turret_frame", 0))
		out["turret_z"] = int(d.get("turret_z", 0))
		out["muzzle_distance"] = float(d.get("muzzle_distance", 0.0))
		out["recoil_frames"] = int(d.get("recoil_frames", 0))
		out["rotation_speed"] = float(d.get("rotation_speed", 3.6))
		out["aim_tolerance_deg"] = float(d.get("aim_tolerance_deg", 14.0))
	return out


# Read a schema field's value from a ROSTER mount dict (roster key), falling back to the roster default.
func _field_val_from_roster(f: Dictionary, d: Dictionary, kind: String):
	var raw = d.get(f["roster"], _field_default(f, kind))
	match String(f["type"]):
		"s": return String(raw)
		"f": return float(raw)
		"i": return int(raw)
		"b": return bool(raw)
	return raw


# Map a (possibly legacy) saved payload name to a current dropdown key, always returning a valid one.
# Beam / entity-scene payloads are valid too (an entity mount's payload is an EMITTER_PAYLOADS / enemy
# name), so only truly-unknown names collapse — and to a kind-appropriate default, never blindly Ball.
func _norm_payload(name: String, kind: String = "gun") -> String:
	var n: String = String(_LEGACY_PAYLOAD.get(name, name))
	if PAYLOADS.has(n) or PROJECTILES.has(n) or n == BEAM_PAYLOAD_NAME:
		return n
	if kind == "entity" and (EMITTER_PAYLOADS.has(n) or _is_enemy_display_name(n)):
		return n
	return "Bomblet" if kind == "entity" else "Ball"


# True if `name` is the display name of some manifest enemy (a valid entity-mount payload).
func _is_enemy_display_name(name: String) -> bool:
	for p in EnemyManifest.all_enemies(false):
		if EnemyStrings.display_name(String(p)) == name:
			return true
	return false


# Reverse-resolve a roster mount's payload to its bench dropdown name. Payloads collapsed to families
# (2026-06-29), so map a BulletVariant by its `family` first — any faction's clone (zealot/privateer
# ball) folds to the generic "Ball". A payload_scene resolves through PROJECTILES, then the wider entity
# set (EMITTER_PAYLOADS + every enemy scene by display name) so a mine/firecore/enemy-drop mount never
# collapses to Ball (which the entity spawn path would then mis-fire as a Missile).
func _payload_name_of(d: Dictionary) -> String:
	# Beam payload: a roster mount with a beam_config is the "Beam" payload (its knobs round-trip into the
	# editable beam_* fields via _roster_mount_to_bench).
	var bc = d.get("beam_config", null)
	if bc is Dictionary and not (bc as Dictionary).is_empty():
		return BEAM_PAYLOAD_NAME
	var ps = d.get("payload_scene", null)
	if ps != null:
		var p: String = String(ps) if ps is String else (ps.resource_path if ps is PackedScene else "")
		if p != "":
			for k in PROJECTILES:
				if String(PROJECTILES[k]) == p:
					return String(k)
			for k in EMITTER_PAYLOADS:
				if String(EMITTER_PAYLOADS[k]) == p:
					return String(k)
			if _is_enemy_display_name(EnemyStrings.display_name(p)) and EnemyStrings.display_name(p) != p:
				return EnemyStrings.display_name(p)
	var pv = d.get("payload", null)
	if pv != null:
		if "family" in pv and String(pv.family) != "":
			var fam: String = String(pv.family).capitalize()   # "ball" -> "Ball"
			if PAYLOADS.has(fam):
				return fam
		for k in PAYLOADS:
			if PAYLOADS[k] == pv:
				return String(k)
	# Nothing resolved: an entity mount defaults to Bomblet (its own kind default), else Ball.
	return "Bomblet" if String(d.get("kind", "gun")) == "entity" else "Ball"


# Serialize a beam_config dict to a paste-ready GDScript literal (handles Vector2/String/bool/number).
func _beam_cfg_literal(cfg: Dictionary) -> String:
	var parts: Array = []
	for k in cfg:
		var v = cfg[k]
		var vs: String
		if v is Vector2:
			vs = "Vector2(%s, %s)" % [v.x, v.y]
		elif v is String:
			vs = "\"%s\"" % v
		elif v is bool:
			vs = "true" if v else "false"
		else:
			vs = str(v)
		parts.append("\"%s\": %s" % [String(k), vs])
	return "{ " + ", ".join(parts) + " }"


# True if a schema field's value should be OMITTED from the Copy literal (it's at the roster default,
# per the field's omit rule) — so the pasted block stays terse and re-parses to exactly this value.
func _field_omit(f: Dictionary, val, kind: String) -> bool:
	match String(f["omit"]):
		"eq_def": return val == _field_default(f, kind)
		"ge0": return float(val) < 0.0
		"gt0": return float(val) <= 0.0
		"gt1": return int(val) <= 1
		"ne_empty": return String(val) == ""
		_: return false   # "" = always emit


# A ", \"key\": value" fragment for one schema field (typed literal), or "" when omitted.
func _field_copy_frag(f: Dictionary, d: Dictionary, kind: String) -> String:
	var val = _field_val(f, d, kind)
	if _field_omit(f, val, kind):
		return ""
	var vs: String
	match String(f["type"]):
		"s": vs = "\"%s\"" % String(val)
		"f": vs = ("%.2f" % float(val)) if String(f["roster"]) not in ["bullet_speed", "scatter", "payload_delay_ms"] else ("%.0f" % float(val))
		"i": vs = "%d" % int(val)
		"b": vs = "true" if bool(val) else "false"
		_: vs = str(val)
	return ", \"%s\": %s" % [String(f["roster"]), vs]


# Emit every schema field applicable to this mount kind (in table order), omitting roster-default values.
func _schema_copy_frags(d: Dictionary, kind: String) -> String:
	var s: String = ""
	for f in MOUNT_FIELDS:
		if _field_applies(f, kind):
			s += _field_copy_frag(f, d, kind)
	return s


# A paste-ready roster "mounts" dict literal for one mount (schema-driven; payload → const / scene path).
func _mount_copy_line(d: Dictionary) -> String:
	var k: String = String(d.get("kind", "gun"))
	var pname: String = _mount_payload_name(d)
	# ENTITY hardpoint: spawns a scene on a trigger (read by _mount_from_dict). payload -> payload_scene.
	# aim/marker are honoured by _mount_from_dict for entity too (e.g. minelayer aims its bomblet drop
	# backward), so emit them; the rest of the entity knobs come from the schema.
	if k == "entity":
		var epath: String = _emitter_payload_path(pname)
		var eaim: String = String(d.get("aim", "straight_down"))
		var eline: String = "{ \"kind\": \"entity\", \"marker\": \"%s\", \"payload_scene\": \"%s\", \"aim\": \"%s\", \"count\": %d, \"fire_min\": %.2f, \"fire_max\": %.2f" % [
			String(d.get("marker", "")), epath, eaim, int(d.get("count", 1)), float(d.get("fire", 1.5)), _fire_max_of(d)]
		eline += _schema_copy_frags(d, k)
		return eline + " },"
	# Beam payload: a kind:"beam" mount carrying the editable beam_config (routed by MountBuilder).
	if pname == BEAM_PAYLOAD_NAME:
		var bmm: String = String(d.get("marker_mode", "all"))
		var bmm_str: String = (", \"marker_mode\": \"%s\"" % bmm) if bmm != "all" else ""
		return "{ \"kind\": \"beam\", \"marker\": \"%s\"%s, \"beam_config\": %s }," % [String(d.get("marker", "")), bmm_str, _beam_cfg_literal(_beam_config_from(d))]
	# Gun / launcher / turret: bullet variant or projectile scene payload.
	var pay: String = "\"payload\": null"
	if PAYLOADS.has(pname):
		pay = "\"payload\": %s" % String(PAYLOAD_CONST.get(pname, PAYLOAD_CONST["Ball"]))
	elif PROJECTILES.has(pname):
		pay = "\"payload_scene\": \"%s\"" % PROJECTILES[pname]
	var line: String = "{ \"kind\": \"%s\", \"marker\": \"%s\", %s, \"aim\": \"%s\", \"fire_min\": %.2f, \"fire_max\": %.2f, \"count\": %d, \"spread_deg\": %.1f" % [
		k, String(d.get("marker", "")), pay, String(d.get("aim", "straight_down")),
		float(d.get("fire", 1.5)), _fire_max_of(d), int(d.get("count", 1)), float(d.get("spread", 0.0)),
	]
	line += _schema_copy_frags(d, k)
	# Gun/launcher-only firing-condition gates (not table fields — string/array shapes, aliased keys).
	if k == "gun" or k == "launcher":
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
	elif k == "turret":
		# Turret graphic + aim config (per-enemy): emit carried barrel art/frame/z/muzzle so a ground
		# turret round-trips through Copy instead of losing its graphic to the group fallback.
		var ttex := String(d.get("turret_texture", ""))
		if ttex != "":
			line += ", \"turret_texture\": \"%s\", \"turret_hframes\": %d, \"turret_frame\": %d" % [ttex, int(d.get("turret_hframes", 1)), int(d.get("turret_frame", 0))]
			if int(d.get("turret_z", 0)) != 0:
				line += ", \"turret_z\": %d" % int(d.get("turret_z", 0))
			if float(d.get("muzzle_distance", 0.0)) != 0.0:
				line += ", \"muzzle_distance\": %.1f" % float(d.get("muzzle_distance", 0.0))
			if int(d.get("recoil_frames", 0)) != 0:
				line += ", \"recoil_frames\": %d" % int(d.get("recoil_frames", 0))
		line += ", \"rotation_speed\": %.2f, \"aim_tolerance_deg\": %.1f" % [float(d.get("rotation_speed", 3.6)), float(d.get("aim_tolerance_deg", 14.0))]
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


# Append a "label | control" pair to a 2-column GridContainer. Mount/emitter fields used to cram
# three label+control pairs onto one HBox row in this narrow gutter, so the controls overran their
# captions; one field per row in a 2-col grid keeps every caption readable (Roman 2026-06-29).
# The caption sits at its natural width in col1; the control expands to fill col2.
func _grid_row(grid: GridContainer, label: String, ctl: Control) -> void:
	_grid_label(grid, label)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


# Like _grid_row, but decorates the control with the shared default-vs-override affordance (a muted
# "was: X" + ↺ revert when the current value drifts from `baked`). DevField appends the affordance as
# SIBLINGS of `ctl`, so — since a 2-col grid cell is one slot — the control is wrapped in an HBox first;
# the affordance nodes then live inside that HBox (col2) instead of spilling into the grid's columns.
# `baked` is in the control's own value-space (float for SpinBox, bool for CheckBox, item-index for
# OptionButton). Idempotent across row rebuilds — the row is rebuilt from scratch each time anyway.
func _grid_row_dec(grid: GridContainer, label: String, ctl: Control, baked) -> void:
	_grid_label(grid, label)
	var wrap := HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(ctl)
	grid.add_child(wrap)
	DevField.decorate(ctl, baked, FS_CAPTION)
	# The mount widgets' own change handlers call _set_mount (not DevField.refresh), so wire the refresh
	# here — the affordance re-evaluates on every edit, like the decorated stat/loco knobs do explicitly.
	if ctl is SpinBox:
		(ctl as SpinBox).value_changed.connect(func(_v): DevField.refresh(ctl))
	elif ctl is OptionButton:
		(ctl as OptionButton).item_selected.connect(func(_i): DevField.refresh(ctl))
	elif ctl is CheckBox or ctl is CheckButton:
		(ctl as BaseButton).toggled.connect(func(_p): DevField.refresh(ctl))


# Read a schema field's baked value for mount `idx`, in the field's NATIVE type-space. The baked source is
# the roster-derived bench dict captured at load (_mount_baked[idx]); an empty {} (user-added mount) falls
# through to the schema default for `kind`. Driven entirely by MOUNT_FIELDS — no per-field hand-wiring.
func _mount_field_baked(idx: int, key: String, kind: String):
	var src: Dictionary = _mount_baked[idx] if idx >= 0 and idx < _mount_baked.size() else {}
	for f in MOUNT_FIELDS:
		if String(f["bench"]) == key and _field_applies(f, kind):
			# _field_val reads bench key from src, falling back to the field's per-kind roster default —
			# so a user-added ({}) mount bakes to exactly the schema default (=> no affordance until edited).
			return _field_val(f, src, kind)
	return null


# Add just the col1 caption of a grid row (returned so the caller can toggle it with its control, e.g.
# to show/hide the burst-gap row). Captions must NOT autowrap — an autowrap label reports ~0 min width
# so the column collapses and the control draws over the caption (the overlap bug Roman hit).
func _grid_label(grid: GridContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FS_CAPTION)
	l.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 0.70))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	return l


# A 2-col field grid for a mount/emitter row (label col + expanding control col).
func _field_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _row_check(pressed: bool) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = pressed
	c.add_theme_font_size_override("font_size", FS_CAPTION)
	return c


func _row_line(text: String, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(0, 26)
	le.add_theme_font_size_override("font_size", FS_CAPTION)
	return le


# An opt-in override row: a checkbox captioned with the field name + a spinbox revealed only when
# checked. Off keeps the row to a single compact line and the enemy uses its template/native value;
# on shows the spin and applies it. Caller wires the spin's value_changed (HP/engine respawn,
# bounty/bullet-speed apply live). Returns the checkbox so the caller can store + persist it.
func _override_row(content: Container, label: String, spin: SpinBox) -> CheckBox:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	content.add_child(hb)
	var chk := CheckBox.new()
	chk.text = label
	chk.add_theme_font_size_override("font_size", FS_CAPTION)
	hb.add_child(chk)
	spin.custom_minimum_size = Vector2(0, 30)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.visible = false
	hb.add_child(spin)
	chk.toggled.connect(func(on):
		spin.visible = on
		if not _loading:
			_spawn_current())
	return chk


func _override_on(chk: CheckBox) -> bool:
	return chk != null and chk.button_pressed


# Restore an override row's state on load: set the checkbox + the spin's visibility directly (setting
# button_pressed to its current value wouldn't fire `toggled`, so the spin's visibility is set here).
func _set_override(chk: CheckBox, spin: SpinBox, on: bool) -> void:
	if chk != null:
		chk.button_pressed = on
	if spin != null:
		spin.visible = on


# Consistent action-button styling: a uniform height + shrink-to-content width (left-aligned), so
# buttons fit their label instead of stretching to the full panel width (Roman 2026-06-29).
const BTN_H := 30
func _style_button(b: Button) -> void:
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


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


# Apply the stat-knob values to a (pre-_ready) enemy instance. HP/bounty come from the size+traits
# template unless their override box is ticked; bullet-speed is native 1× unless overridden.
func _apply_stats_to(inst: Node) -> void:
	if inst == null:
		return
	var tmpl: Dictionary = EnemyRoster.compose_stats(_template_entry())
	if "max_health" in inst:
		inst.max_health = int(_hp_spin.value) if _override_on(_hp_override_chk) else int(tmpl["max_health"])
	if "bounty_value" in inst:
		inst.bounty_value = int(_bounty_spin.value) if _override_on(_bounty_override_chk) else int(tmpl["bounty_value"])
	if "bullet_speed_mult" in inst:
		inst.bullet_speed_mult = float(_bspeed_spin.value) if _override_on(_bspeed_override_chk) else 1.0
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


# Cheap stats (no _ready dependency) applied to the live enemy without a respawn. Only the overridden
# ones write; an un-ticked override leaves the spawn-time template/native value in place.
func _apply_stats_live() -> void:
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if _override_on(_bounty_override_chk) and "bounty_value" in _current_enemy:
		_current_enemy.bounty_value = int(_bounty_spin.value)
	if _override_on(_bspeed_override_chk) and "bullet_speed_mult" in _current_enemy:
		_current_enemy.bullet_speed_mult = float(_bspeed_spin.value)


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
	_select_text(_payload_dd, _norm_payload(String(s.get("payload", "Ball"))), PAYLOADS.keys())
	_select_text(_explosion_dd, String(s.get("explosion", "default")), ExplosionFx.variant_names())
	if _recycle_chk:
		_recycle_chk.button_pressed = bool(s.get("can_recycle", true))
	if _recycle_passes_spin:
		_recycle_passes_spin.value = int(s.get("recycle_passes", 1))
	if _recycle_chance_spin:
		_recycle_chance_spin.value = float(s.get("recycle_chance", 1.0))
	# Stat overrides: restore each spin's value + whether its box is ticked (default off → hidden).
	# Phase 3 default-vs-override: the BAKED default is the committed scene/roster value (nat / le),
	# NOT the user:// save (s). Feed it to DevField so a value that differs from shipping shows a
	# muted "was: X" + revert. When there's no saved override, current == baked → no affordance.
	if _hp_spin:
		var hp_baked: int = int(nat.get("max_health", 1))
		_hp_spin.value = int(s.get("max_health", hp_baked))
		_set_override(_hp_override_chk, _hp_spin, bool(s.get("hp_override", false)))
		DevField.set_baked(_hp_spin, float(hp_baked))
	if _bounty_spin:
		var bounty_baked: int = int(nat.get("bounty_value", 5))
		_bounty_spin.value = int(s.get("bounty_value", bounty_baked))
		_set_override(_bounty_override_chk, _bounty_spin, bool(s.get("bounty_override", false)))
		DevField.set_baked(_bounty_spin, float(bounty_baked))
	if _bspeed_spin:
		var bspeed_baked: float = float(nat.get("bullet_speed_mult", 1.0))
		_bspeed_spin.value = float(s.get("bullet_speed_mult", bspeed_baked))
		_set_override(_bspeed_override_chk, _bspeed_spin, bool(s.get("bspeed_override", false)))
		DevField.set_baked(_bspeed_spin, bspeed_baked)
	if _engine_spin != null:
		var le: Dictionary = EnemyRoster.entry_for_scene(_selected_path)
		var eng_baked: int = int(le.get("engine", 0))
		var eng: int = int(s.get("engine", eng_baked))
		_engine_spin.value = eng
		# Default the engine override ON when the roster already ships a non-zero offset, so it shows.
		_set_override(_engine_override_chk, _engine_spin, bool(s.get("engine_override", eng != 0)))
		DevField.set_baked(_engine_spin, float(eng_baked))
		var depth_baked: int = maxi(0, _DEPTH_ITEMS.find(String(le.get("depth", ""))))
		var dstr: String = String(s.get("depth", String(le.get("depth", ""))))
		var didx: int = _DEPTH_ITEMS.find(dstr)
		_depth_dd.select(didx if didx >= 0 else 0)
		DevField.set_baked(_depth_dd, depth_baked)
		if _size_dd != null:
			var size_baked: int = maxi(0, _SIZE_OPTS.find(String(le.get("size", "medium"))))
			var sz: String = String(s.get("size", String(le.get("size", "medium"))))
			var si: int = _SIZE_OPTS.find(sz)
			_size_dd.select(si if si >= 0 else 2)
			DevField.set_baked(_size_dd, size_baked)
			var etags: Array = le.get("tags", []) if le.has("tags") else []
			_tough_chk.button_pressed = bool(s.get("tough", "tough" in etags))
			DevField.set_baked(_tough_chk, "tough" in etags)
			_shielded_chk.button_pressed = bool(s.get("shielded", "shielded" in etags))
			DevField.set_baked(_shielded_chk, "shielded" in etags)
			if _omni_chk != null:
				_omni_chk.button_pressed = bool(s.get("omni", false))
				DevField.set_baked(_omni_chk, false)
			if _strafe_chk != null:
				_strafe_chk.button_pressed = bool(s.get("strafe", false))
				DevField.set_baked(_strafe_chk, false)
			if _retro_chk != null:
				_retro_chk.button_pressed = bool(s.get("retro", false))
				DevField.set_baked(_retro_chk, false)
			if _ram_chk != null:
				_ram_chk.button_pressed = bool(s.get("ram", false))
				DevField.set_baked(_ram_chk, false)
	# Faction eligibility (core ships): saved allowed_in, else the scene's ENEMY_TAGS default.
	_set_faction_elig(_selected_path, s.get("allowed_in", _default_allowed_in(_selected_path)))
	# (Authored-path eligibility is no longer edited/persisted here — the cyclable set was rebuilt from
	# DevData.eligibility_for in _on_list_select, and the read-only display reflects it. Any legacy
	# "path_eligible" key in an old save file is silently ignored.)
	_name_edit.text = String(s.get("name", EnemyStrings.display_name(_selected_path)))
	_codex_edit.text = String(s.get("codex", EnemyStrings.codex_entry(_selected_path)))
	# Saved bench override wins; otherwise default to the enemy's production roster mounts.
	_mount_dicts = _dup_mounts(s.get("mounts")) if s.has("mounts") else _default_mounts_for(_selected_path)
	for md in _mount_dicts:
		var mk: String = String(md.get("kind", "gun"))
		md["payload"] = _norm_payload(String(md.get("payload", ("Bomblet" if mk == "entity" else "Ball"))), mk)   # migrate pre-collapse names
	# Phase 3: legacy emitters (saved or roster-default) fold into the unified Hardpoints list as entity mounts.
	var _raw_em: Array = _dup_mounts(s.get("emitters")) if s.has("emitters") else _default_emitters_for(_selected_path)
	for _e in _raw_em:
		_mount_dicts.append(_emitter_dict_to_mount(_e))
	# Default-vs-override baked reference: the ROSTER-derived bench mounts (+ folded emitters), captured
	# INDEPENDENTLY of the saved JSON so the affordance shows drift from shipping (not from the last save).
	# Index-aligned to _mount_dicts; a user-added mount with no roster counterpart bakes to {} (schema
	# defaults). The roster mount list is the drift baseline whether or not a saved override loaded over it.
	_mount_baked = _default_mounts_for(_selected_path)
	for _e in _default_emitters_for(_selected_path):
		_mount_baked.append(_emitter_dict_to_mount(_e))
	# Pad or trim so _mount_baked is index-aligned with _mount_dicts (a saved override can add/remove mounts
	# relative to the roster; any surplus working mount bakes to {} = schema defaults = no affordance).
	while _mount_baked.size() < _mount_dicts.size():
		_mount_baked.append({})
	_mount_baked.resize(_mount_dicts.size())
	_rebuild_mounts_ui()
	_orbit_mode = String(s.get("orbit_mode", "live"))
	_orbit_rings = _dup_mounts(s.get("orbit_rings")) if s.has("orbit_rings") else []
	if _orbit_mode_dd != null:
		_orbit_mode_dd.select(0 if _orbit_mode == "live" else 1)
	_rebuild_orbit_ui()
	_loading = false


# Native stat values baked into a scene (so the spinboxes show real defaults, not
# the @export base). Instantiates once, reads, frees.
func _scene_defaults(path: String) -> Dictionary:
	var out := {}
	var ps := load(path) as PackedScene
	if ps == null:
		return out
	var inst := ps.instantiate()
	for k in ["max_health", "bounty_value", "bullet_speed_mult"]:
		if k in inst:
			out[k] = inst.get(k)
	inst.free()
	return out


func _select_text(dd: OptionButton, text: String, pool) -> void:
	var i: int = Array(pool).find(text)
	dd.select(i if i >= 0 else 0)


func _current_settings() -> Dictionary:
	return {
		"payload": String(PAYLOADS.keys()[_payload_dd.selected]),
		"explosion": ExplosionFx.variant_names()[_explosion_dd.selected],
		"can_recycle": _recycle_chk.button_pressed,
		"recycle_passes": int(_recycle_passes_spin.value),
		"recycle_chance": float(_recycle_chance_spin.value),
		"hp_override": _override_on(_hp_override_chk),
		"max_health": int(_hp_spin.value) if _hp_spin else 1,
		"bounty_override": _override_on(_bounty_override_chk),
		"bounty_value": int(_bounty_spin.value) if _bounty_spin else 0,
		"bspeed_override": _override_on(_bspeed_override_chk),
		"bullet_speed_mult": float(_bspeed_spin.value) if _bspeed_spin else 1.0,
		"name": _name_edit.text,
		"codex": _codex_edit.text,
		# Legacy saved "emitters" are no longer WRITTEN (they fold into "mounts" as entity hardpoints on
		# load), but old save files that still carry them are read on load — see _load_settings_into_editors.
		"mounts": _dup_mounts(_mount_dicts),
		"orbit_mode": _orbit_mode,
		"orbit_rings": _dup_mounts(_orbit_rings),
		"engine_override": _override_on(_engine_override_chk),
		"engine": int(_engine_spin.value) if _engine_spin != null else 0,
		"depth": _depth_for_selected(),
		"size": _bench_size(),
		"tough": _tough_chk.button_pressed if _tough_chk != null else false,
		"shielded": _shielded_chk.button_pressed if _shielded_chk != null else false,
		"omni": _omni_chk.button_pressed if _omni_chk != null else false,
		"strafe": _strafe_chk.button_pressed if _strafe_chk != null else false,
		"retro": _retro_chk.button_pressed if _retro_chk != null else false,
		"ram": _ram_chk.button_pressed if _ram_chk != null else false,
		"allowed_in": _selected_allowed_in(),   # core-ship faction eligibility (Factions.ENEMY_TAGS)
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
	DisplayServer.clipboard_set(_build_copy_text())
	if _pattern_lbl:
		_pattern_lbl.text = "Copied GDScript to clipboard"


# Assemble the paste-ready Copy-GDScript snippet for the selected enemy (stat overrides, recycle,
# locomotion, roster mounts, faction eligibility, strings). Split out of _on_copy so a headless probe
# can assert the output directly (the headless DisplayServer clipboard doesn't round-trip). NOTE: this
# emits NO movement-eligibility / pattern_eligibility line — eligibility is authored solely in the
# Pattern Eligibility tool, and this bench only mirrors it.
func _build_copy_text() -> String:
	var s := _current_settings()
	var txt := "# Enemy Bench — %s\n" % String(s["name"])
	# Hull weapon (Mount 0) retired 2026-06-23 — enemies fire via mounts (emitted below).
	txt += "enemy.shoot_pattern = null\n"
	txt += "enemy.explosion_variant = \"%s\"\n" % s["explosion"]
	txt += "# Stat overrides (only the ticked ones — unticked uses the size template / native):\n"
	if bool(s.get("hp_override", false)):
		txt += "enemy.max_health = %d\n" % s["max_health"]
	if bool(s.get("bounty_override", false)):
		txt += "enemy.bounty_value = %d\n" % s["bounty_value"]
	if bool(s.get("bspeed_override", false)):
		txt += "enemy.bullet_speed_mult = %.2f\n" % s["bullet_speed_mult"]
	txt += "# Recycle behavior:\n"
	if s["can_recycle"]:
		txt += "enemy.recycle_passes = %d  # %.1f chance to recycle\n" % [s["recycle_passes"], s["recycle_chance"]]
	else:
		txt += "enemy.recycle_passes = 0  # flee (no recycle)\n"
	# Locomotion → roster ENTRY fields (size base + engine rung offset + optional depth band).
	var loco_bits: Array = []
	if bool(s.get("engine_override", false)) and int(s.get("engine", 0)) != 0:
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
	if bool(s.get("hp_override", false)):
		entry_bits.append("\"hp_override\": %d" % int(s["max_health"]))
	if bool(s.get("bounty_override", false)):
		entry_bits.append("\"bounty_override\": %d" % int(s["bounty_value"]))
	txt += "# -> roster ENTRY (template): %s\n" % ", ".join(entry_bits)
	# Locomotion capability flags (omni/strafe/retro) — scene-baked on enemy_base.
	var loco_flags: Array = []
	if bool(s.get("omni", false)): loco_flags.append("omni")
	if bool(s.get("strafe", false)): loco_flags.append("strafe")
	if bool(s.get("retro", false)): loco_flags.append("retro")
	if bool(s.get("ram", false)): loco_flags.append("ram")
	if not loco_flags.is_empty():
		txt += "# -> scene root (enemy_base): set %s = true\n" % ", ".join(loco_flags)
	# Mounts → a roster ENTRY "mounts" block (extra hardpoints beyond the hull weapon). Phase C: an
	# authored orbit ring folds in here as a kind:"ring" hardpoint (was a bespoke OrbitComponent block).
	var mount_lines: Array = []
	for d in _mount_dicts:
		mount_lines.append(_mount_copy_line(d))
	if not _orbit_rings.is_empty():
		mount_lines.append(_orbit_mount_copy_line())
	if not mount_lines.is_empty():
		txt += "\n# -> roster ENTRY \"mounts\":\n\"mounts\": [\n"
		for ml in mount_lines:
			txt += "\t%s\n" % ml
		txt += "],\n"
	# (Emitters are no longer a separate copy block — droppers/spawners emit as kind:"entity" hardpoints
	# inside the "mounts" block above.)
	# (Phase C: the orbit ring now emits as a kind:"ring" entry inside the "mounts" block above,
	# not a bespoke OrbitComponent — see _orbit_mount_copy_line.)
	# Faction eligibility → Factions.ENEMY_TAGS line (core ships only). The handoff for "which factions
	# this core hull may appear with" (Roman 2026-07-06).
	if _is_core_ship(_selected_path):
		var id_names := ["Id.SUPREMACY", "Id.PRIVATEER", "Id.CORPORATE", "Id.ZEALOT"]
		var tag: Variant = Factions.ENEMY_TAGS.get(_selected_path, {})
		var home_i: int = int(tag.get("home", 0)) if tag is Dictionary else 0
		var sel: Array = _selected_allowed_in()
		var al: Array = []
		for i in sel:
			al.append(id_names[i])
		txt += "\n# -> scripts/levels/factions.gd ENEMY_TAGS:\n"
		if sel.size() >= 4:
			# All four = unrestricted; drop the redundant whitelist.
			txt += "\t\"%s\": {\"home\": %s, \"universal\": true},\n" % [_selected_path, id_names[home_i]]
		else:
			txt += "\t\"%s\": {\"home\": %s, \"universal\": true, \"allowed_in\": [%s]},\n" % [_selected_path, id_names[home_i], ", ".join(al)]
	# (No pattern_eligibility.gd DATA line is emitted here — movement eligibility is authored ONLY in the
	# Pattern Eligibility tool, which owns the pattern_eligibility.json → Export→DATA handoff. The bench is
	# a read-only mirror of that set; emitting an eligibility line here would be a second, conflicting author.)
	# Paste-ready enemy_strings.gd STRINGS entry (the name + codex live in a baked
	# const dict, so this is the handoff back into source).
	var codex_one_line: String = String(s["codex"]).replace("\n", " ").replace("\"", "'")
	txt += "\n# -> scripts/enemy_strings.gd STRINGS:\n"
	txt += "\t\"%s\": {\"name\": \"%s\", \"codex\": \"%s\"},\n" % [_selected_path, String(s["name"]), codex_one_line]
	return txt


# ---- Back ----------------------------------------------------------------

func _on_back() -> void:
	# Release the music silent-lock. It kept the autoload stopped the whole time, so
	# there's no track to blast when the Music bus un-mutes below; the dev menu we're
	# returning to sets its own silent context.
	var _music := get_node_or_null("/root/Music")
	if _music != null and _music.has_method("lock_silent"):
		_music.lock_silent(false)
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
