extends Control

# In-game wave editor — designers author/edit/playtest wave compositions
# without leaving the running game. Layout is authored in wave_editor.tscn
# (Godot editor handles sizing/placement); this script only wires data.
#
# Data round-trip: scans resources/waves/ for WaveDef .tres files, lets the
# designer edit any field, saves changes back via ResourceSaver, and the
# "Play Wave" button wraps the current wave in a one-shot LevelData that
# main.gd::new_game() loads via the existing custom_level_path meta path.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const WaveDef = preload("res://scripts/levels/wave_def.gd")
const LevelDef = preload("res://scripts/levels/level_def.gd")

const WAVES_DIR := "res://resources/waves/"
const ENEMY_DIR := "res://scenes/enemies/"
# One-shot playtest level — overwritten each "Play Wave" click. Lives in
# user:// so it's writable in any build (res:// is read-only in exports).
const PLAY_LEVEL_PATH := "user://wave_editor_play.tres"
# Companion to PLAY_LEVEL_PATH: the wave the level references. Written
# fresh on each Play Wave so unsaved in-memory changes are honored.
const PLAY_WAVE_PATH := "user://wave_editor_play_wave.tres"
# Stash unsaved in-memory state across the playtest scene transition so
# coming back from "Play Wave" doesn't reset the form.
const PENDING_WAVE_PATH := "user://wave_editor_pending.tres"

# Dev-tool viewport scale: the project ships at 480×270 for chunky-pixel
# gameplay, but a text-dense editor needs more real estate. We swap the
# window's content_scale_size to native (1920×1080) for the duration of
# this scene, then restore on Back. Other scenes are unaffected.
const HD_VIEWPORT := Vector2i(1920, 1080)
var _prev_scale_size: Vector2i = Vector2i.ZERO

const MOVEMENT_DIR := "res://resources/patterns/movement/"
const SHOOT_DIR := "res://resources/patterns/shoot/"
# Paths in MovementPick / ShootPick by item index.
var _movement_paths: Array = []
var _shoot_paths: Array = []

@onready var _wave_list: ItemList = $Body/LeftRail/WaveList
@onready var _new_btn: Button = $Body/LeftRail/LeftButtons/NewBtn
@onready var _dup_btn: Button = $Body/LeftRail/LeftButtons/DuplicateBtn
@onready var _del_btn: Button = $Body/LeftRail/LeftButtons/DeleteBtn
@onready var _name_edit: LineEdit = $Body/RightPanel/Props/NameEdit
@onready var _enemy_pick: OptionButton = $Body/RightPanel/Props/EnemyPick
@onready var _count_spin: SpinBox = $Body/RightPanel/Props/CountSpin
@onready var _interval_spin: SpinBox = $Body/RightPanel/Props/IntervalSpin
@onready var _delay_spin: SpinBox = $Body/RightPanel/Props/DelaySpin
@onready var _formation_pick: OptionButton = $Body/RightPanel/Props/FormationPick
@onready var _movement_pick: OptionButton = $Body/RightPanel/Props/MovementRow/MovementPick
@onready var _edit_movement_btn: Button = $Body/RightPanel/Props/MovementRow/EditMovementBtn
@onready var _shoot_pick: OptionButton = $Body/RightPanel/Props/ShootRow/ShootPick
@onready var _edit_shoot_btn: Button = $Body/RightPanel/Props/ShootRow/EditShootBtn
@onready var _hp_spin: SpinBox = $Body/RightPanel/Props/HpSpin
@onready var _bounty_spin: SpinBox = $Body/RightPanel/Props/BountySpin
@onready var _silent_check: CheckBox = $Body/RightPanel/Props/SilentCheck
@onready var _announce_edit: LineEdit = $Body/RightPanel/Props/AnnounceEdit
@onready var _status: Label = $Body/RightPanel/Status
@onready var _save_btn: Button = $FooterButtons/SaveBtn
@onready var _play_btn: Button = $FooterButtons/PlayBtn
@onready var _back_btn: Button = $FooterButtons/BackBtn

# Mirror of disk state. Keys: file basename (e.g. "test_wave_darts");
# values: { "path": "res://...", "res": WaveDef }.
var _waves: Dictionary = {}
# Paths of enemy .tscn files for the EnemyPick dropdown, indexed by item id.
var _enemy_paths: Array = []
# Currently selected wave key, or "" when none selected.
var _current_key: String = ""
# Suppress field-change handlers while we're populating the form from a
# loaded resource (otherwise repopulating would clobber the in-memory res).
var _populating: bool = false


func _ready() -> void:
	_enter_hd_viewport()
	_populate_enemy_picker()
	_populate_formation_picker()
	_populate_movement_picker()
	_populate_shoot_picker()
	_scan_waves()
	_wire_signals()
	# If we just came back from a Play Wave, restore the unsaved in-memory
	# state so the designer can keep iterating or save what they tested.
	if _try_restore_pending():
		return
	if _wave_list.item_count > 0:
		_wave_list.select(0)
		_on_wave_selected(0)


# Swap to 1920×1080 logical viewport so the editor has room for legible
# text. Save the previous value so we can restore it on Back.
func _enter_hd_viewport() -> void:
	var w := get_window()
	if w == null:
		return
	_prev_scale_size = w.content_scale_size
	w.content_scale_size = HD_VIEWPORT


func _exit_hd_viewport() -> void:
	var w := get_window()
	if w == null:
		return
	if _prev_scale_size != Vector2i.ZERO:
		w.content_scale_size = _prev_scale_size


func _exit_tree() -> void:
	# Defensive restore — covers crashes / unexpected exits where _on_back
	# didn't run. Idempotent if _on_back already restored.
	_exit_hd_viewport()


func _wire_signals() -> void:
	_wave_list.item_selected.connect(_on_wave_selected)
	_new_btn.pressed.connect(_on_new)
	_dup_btn.pressed.connect(_on_duplicate)
	_del_btn.pressed.connect(_on_delete)
	_save_btn.pressed.connect(_on_save)
	_play_btn.pressed.connect(_on_play)
	_back_btn.pressed.connect(_on_back)
	# Field edits flow straight into the in-memory resource — save writes
	# the whole resource to disk.
	_name_edit.text_changed.connect(func(_t): _mark_dirty())
	_enemy_pick.item_selected.connect(_on_enemy_picked)
	_count_spin.value_changed.connect(_on_count_changed)
	_interval_spin.value_changed.connect(_on_interval_changed)
	_delay_spin.value_changed.connect(_on_delay_changed)
	_formation_pick.item_selected.connect(_on_formation_picked)
	_movement_pick.item_selected.connect(_on_movement_picked)
	_shoot_pick.item_selected.connect(_on_shoot_picked)
	_edit_movement_btn.pressed.connect(_on_edit_movement)
	_edit_shoot_btn.pressed.connect(_on_edit_shoot)
	_hp_spin.value_changed.connect(_on_hp_changed)
	_bounty_spin.value_changed.connect(_on_bounty_changed)
	_silent_check.toggled.connect(_on_silent_toggled)
	_announce_edit.text_changed.connect(_on_announce_changed)


# ---- Disk scan -----------------------------------------------------------

func _scan_waves() -> void:
	_waves.clear()
	_wave_list.clear()
	# DirAccess.open("res://...") works in editor + native exports. For web,
	# this returns empty; the wave editor is dev-only so that's acceptable.
	var dir := DirAccess.open(WAVES_DIR)
	if dir == null:
		_set_status("Cannot read %s" % WAVES_DIR)
		return
	dir.list_dir_begin()
	var keys: Array = []
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var key := fname.get_basename()
			var path := WAVES_DIR + fname
			var res = load(path)
			if res != null:
				_waves[key] = {"path": path, "res": res}
				keys.append(key)
		fname = dir.get_next()
	dir.list_dir_end()
	keys.sort()
	for k in keys:
		_wave_list.add_item(k)


# ---- Dropdowns -----------------------------------------------------------

func _populate_enemy_picker() -> void:
	_enemy_pick.clear()
	_enemy_paths.clear()
	var dir := DirAccess.open(ENEMY_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var paths: Array = []
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tscn"):
			paths.append(ENEMY_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	for p in paths:
		_enemy_paths.append(p)
		_enemy_pick.add_item(String(p).get_file().get_basename())


func _populate_formation_picker() -> void:
	_formation_pick.clear()
	# Mirrors WaveDef.Formation enum order.
	for label in ["TOP_LEFT_TO_RIGHT", "TOP_RIGHT_TO_LEFT", "TOP_RANDOM", "TOP_CENTER_OUT"]:
		_formation_pick.add_item(label)


func _populate_movement_picker() -> void:
	_populate_pattern_picker(_movement_pick, _movement_paths, MOVEMENT_DIR)


func _populate_shoot_picker() -> void:
	_populate_pattern_picker(_shoot_pick, _shoot_paths, SHOOT_DIR)


# Shared between movement + shoot pickers. First entry is "<none>" with
# an empty path so the designer can clear the override.
func _populate_pattern_picker(picker: OptionButton, paths_arr: Array, source_dir: String) -> void:
	picker.clear()
	paths_arr.clear()
	picker.add_item("<none>")
	paths_arr.append("")
	var dir := DirAccess.open(source_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var found: Array = []
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			found.append(source_dir + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	found.sort()
	for p in found:
		paths_arr.append(p)
		picker.add_item(String(p).get_file().get_basename())


# ---- Selection / form binding -------------------------------------------

func _on_wave_selected(idx: int) -> void:
	if idx < 0 or idx >= _wave_list.item_count:
		return
	_current_key = _wave_list.get_item_text(idx)
	if not _waves.has(_current_key):
		return
	var w = _waves[_current_key]["res"]
	_populating = true
	_name_edit.text = _current_key
	_select_enemy_path(w.enemy_scene.resource_path if w.enemy_scene else "")
	_count_spin.value = w.count
	_interval_spin.value = w.spawn_interval
	_delay_spin.value = w.spawn_delay
	_formation_pick.select(clamp(w.formation, 0, _formation_pick.item_count - 1))
	_select_pattern_path(_movement_pick, _movement_paths,
		w.movement_override.resource_path if w.movement_override else "")
	_select_pattern_path(_shoot_pick, _shoot_paths,
		w.shoot_pattern_override.resource_path if w.shoot_pattern_override else "")
	_hp_spin.value = w.max_health
	_bounty_spin.value = w.bounty_value
	_silent_check.button_pressed = w.silent
	_announce_edit.text = w.announce_text
	_populating = false
	_set_status("Loaded %s" % _current_key)


func _select_enemy_path(path: String) -> void:
	for i in _enemy_paths.size():
		if _enemy_paths[i] == path:
			_enemy_pick.select(i)
			return
	_enemy_pick.select(-1)


func _select_pattern_path(picker: OptionButton, paths_arr: Array, path: String) -> void:
	for i in paths_arr.size():
		if paths_arr[i] == path:
			picker.select(i)
			return
	picker.select(0)  # <none>


func _current_wave() -> WaveDef:
	if _current_key == "" or not _waves.has(_current_key):
		return null
	return _waves[_current_key]["res"]


func _mark_dirty() -> void:
	if _populating:
		return
	_set_status("Unsaved changes")


# ---- Field handlers (each writes to the in-memory resource) -------------

func _on_enemy_picked(idx: int) -> void:
	if _populating:
		return
	var w := _current_wave()
	if w == null or idx < 0 or idx >= _enemy_paths.size():
		return
	w.enemy_scene = load(_enemy_paths[idx])
	_mark_dirty()


func _on_count_changed(v: float) -> void:
	var w := _current_wave()
	if w: w.count = int(v); _mark_dirty()


func _on_interval_changed(v: float) -> void:
	var w := _current_wave()
	if w: w.spawn_interval = v; _mark_dirty()


func _on_delay_changed(v: float) -> void:
	var w := _current_wave()
	if w: w.spawn_delay = v; _mark_dirty()


func _on_formation_picked(idx: int) -> void:
	var w := _current_wave()
	if w: w.formation = idx; _mark_dirty()


func _on_movement_picked(idx: int) -> void:
	var w := _current_wave()
	if w == null:
		return
	if idx <= 0 or idx >= _movement_paths.size():
		w.movement_override = null
	else:
		w.movement_override = load(_movement_paths[idx])
	_mark_dirty()


func _on_shoot_picked(idx: int) -> void:
	var w := _current_wave()
	if w == null:
		return
	if idx <= 0 or idx >= _shoot_paths.size():
		w.shoot_pattern_override = null
	else:
		w.shoot_pattern_override = load(_shoot_paths[idx])
	_mark_dirty()


func _on_hp_changed(v: float) -> void:
	var w := _current_wave()
	if w: w.max_health = int(v); _mark_dirty()


func _on_bounty_changed(v: float) -> void:
	var w := _current_wave()
	if w: w.bounty_value = int(v); _mark_dirty()


func _on_silent_toggled(pressed: bool) -> void:
	var w := _current_wave()
	if w: w.silent = pressed; _mark_dirty()


func _on_announce_changed(t: String) -> void:
	var w := _current_wave()
	if w: w.announce_text = t; _mark_dirty()


# ---- Actions ------------------------------------------------------------

func _on_save() -> void:
	var w := _current_wave()
	if w == null:
		_set_status("Nothing to save")
		return
	# Honor the Name field — if the designer renamed, save to a new path
	# and reload the list so the new key shows up.
	var new_key := _name_edit.text.strip_edges()
	if new_key == "":
		_set_status("Name required")
		return
	var new_path := WAVES_DIR + new_key + ".tres"
	var old_path: String = _waves[_current_key]["path"]
	var err := ResourceSaver.save(w, new_path)
	if err != OK:
		_set_status("Save FAILED (%d) — check res:// is writable" % err)
		return
	if new_key != _current_key and FileAccess.file_exists(old_path):
		# Renamed — wipe the old file. Rename within res:// is permitted
		# in editor builds; harmless if it fails in exports.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	_set_status("Saved %s" % new_key)
	# Refresh listing to pick up new/renamed file.
	_scan_waves()
	_select_by_key(new_key)


func _on_new() -> void:
	# Find an unused basename.
	var base := "wave_new"
	var i := 1
	while _waves.has(base if i == 1 else "%s_%d" % [base, i]):
		i += 1
	var key := base if i == 1 else "%s_%d" % [base, i]
	var w = WaveDef.new()
	w.count = 5
	w.spawn_interval = 0.35
	w.spawn_delay = 0.5
	w.formation = 0
	if _enemy_paths.size() > 0:
		w.enemy_scene = load(_enemy_paths[0])
	var path := WAVES_DIR + key + ".tres"
	var err := ResourceSaver.save(w, path)
	if err != OK:
		_set_status("New FAILED (%d)" % err)
		return
	_scan_waves()
	_select_by_key(key)
	_set_status("Created %s" % key)


func _on_duplicate() -> void:
	var w := _current_wave()
	if w == null:
		return
	var key := _current_key + "_copy"
	var i := 1
	while _waves.has(key if i == 1 else "%s%d" % [key, i]):
		i += 1
	var final_key := key if i == 1 else "%s%d" % [key, i]
	var dup: WaveDef = w.duplicate(true)
	var path := WAVES_DIR + final_key + ".tres"
	var err := ResourceSaver.save(dup, path)
	if err != OK:
		_set_status("Duplicate FAILED (%d)" % err)
		return
	_scan_waves()
	_select_by_key(final_key)
	_set_status("Duplicated to %s" % final_key)


func _on_delete() -> void:
	if _current_key == "":
		return
	var path: String = _waves[_current_key]["path"]
	var abs_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.remove_absolute(abs_path)
	if err != OK:
		_set_status("Delete FAILED (%d)" % err)
		return
	var dropped := _current_key
	_current_key = ""
	_scan_waves()
	if _wave_list.item_count > 0:
		_wave_list.select(0)
		_on_wave_selected(0)
	_set_status("Deleted %s" % dropped)


# Wrap the current wave in a single-wave one-shot level, write it to
# user://, set Run.meta, and boot main.tscn. Combat plays just this wave
# in isolation. Returning to the menu re-enters the editor via the
# normal cleared/end flows.
func _on_play() -> void:
	var w := _current_wave()
	if w == null:
		_set_status("Select a wave to play")
		return
	# Persist the current in-memory wave to its own user:// path. Doing
	# this (instead of duplicating in memory + saving the level inline)
	# preserves the movement_override / shoot_pattern_override as proper
	# ExtResource references back to their on-disk .tres files. Inline
	# duplicates lose resource_path and break script-bound sub-resources.
	var wave_err := ResourceSaver.save(w, PLAY_WAVE_PATH)
	if wave_err != OK:
		_set_status("Play FAILED to write wave (%d)" % wave_err)
		return
	# Re-load from disk to get a clean Resource with resource_path set
	# (so the level can ExtResource-reference it cleanly).
	var play_wave = load(PLAY_WAVE_PATH)
	if play_wave == null:
		_set_status("Play FAILED to reload wave")
		return
	var lvl := LevelDef.new()
	lvl.level_name = "Editor — %s" % _current_key
	lvl.waves = [play_wave]
	var err := ResourceSaver.save(lvl, PLAY_LEVEL_PATH)
	if err != OK:
		_set_status("Play FAILED to write level (%d)" % err)
		return
	# Snapshot the unsaved in-memory wave so it survives the scene
	# transition. Saved separately from PLAY_LEVEL_PATH so we keep the
	# original (unsaved) state including any rename the designer typed.
	_save_pending(w)
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.has_method("new_run"):
			run.new_run()
		run.test_mode_active = true
		run.set_meta("custom_level_path", PLAY_LEVEL_PATH)
		# When the wave finishes (or player dies), cleared_summary routes
		# us back here instead of the main menu.
		run.set_meta("test_return_scene", "res://scenes/dev/wave_editor.tscn")
		# Pass the metadata about which wave's in-memory state is pending,
		# plus what the Name field said (potential rename) so the editor
		# can restore both on return.
		run.set_meta("wave_editor_pending_key", _current_key)
		run.set_meta("wave_editor_pending_name", _name_edit.text)
	_exit_hd_viewport()
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _save_pending(w: WaveDef) -> void:
	# Save the in-memory wave directly — NO duplicate. Resource.duplicate(true)
	# deep-clones sub-resources and wipes their resource_path, which breaks
	# the round-trip for movement_override / shoot_pattern_override (they
	# come back as path-less inline Resources, and the pickers can't map
	# them back to known .tres files).
	var err := ResourceSaver.save(w, PENDING_WAVE_PATH)
	if err != OK:
		push_warning("wave_editor: failed to write pending snapshot (%d)" % err)


# Pull the unsaved snapshot back into _waves and select it. Returns true
# if a restore actually happened (caller skips the default selection).
func _try_restore_pending() -> bool:
	if not has_node("/root/Run"):
		return false
	var run = get_node("/root/Run")
	if not run.has_meta("wave_editor_pending_key"):
		return false
	var key := String(run.get_meta("wave_editor_pending_key", ""))
	var name_field := String(run.get_meta("wave_editor_pending_name", key))
	run.remove_meta("wave_editor_pending_key")
	run.remove_meta("wave_editor_pending_name")
	if key == "" or not FileAccess.file_exists(PENDING_WAVE_PATH):
		return false
	var pending = load(PENDING_WAVE_PATH)
	if pending == null:
		return false
	# Replace the disk-loaded entry with the snapshot. If the key isn't on
	# disk anymore (e.g. it was unsaved-new), inject a transient entry so
	# the designer can still see + save it.
	if _waves.has(key):
		_waves[key]["res"] = pending
	else:
		_waves[key] = {"path": WAVES_DIR + key + ".tres", "res": pending}
		_wave_list.add_item(key)
	_select_by_key(key)
	# Restore the Name field separately — it lives outside the WaveDef.
	_populating = true
	_name_edit.text = name_field
	_populating = false
	# Wipe the on-disk snapshot so a clean re-entry next session starts
	# fresh from saved state, not from this just-restored buffer.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_WAVE_PATH))
	_set_status("Restored unsaved changes — Save to persist")
	return true


func _on_back() -> void:
	_exit_hd_viewport()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# Open the movement pattern editor with the currently-selected wave's
# pending state stashed for restore on return. Pattern editor sees a
# return-scene meta and lands back here when it's done.
func _on_edit_movement() -> void:
	var w := _current_wave()
	if w == null:
		_set_status("Select a wave first")
		return
	_save_pending(w)
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.set_meta("wave_editor_pending_key", _current_key)
		run.set_meta("wave_editor_pending_name", _name_edit.text)
		run.set_meta("pattern_editor_return_scene", "res://scenes/dev/wave_editor.tscn")
	_exit_hd_viewport()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/movement_pattern_editor.tscn")


func _on_edit_shoot() -> void:
	var w := _current_wave()
	if w == null:
		_set_status("Select a wave first")
		return
	_save_pending(w)
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.set_meta("wave_editor_pending_key", _current_key)
		run.set_meta("wave_editor_pending_name", _name_edit.text)
		run.set_meta("pattern_editor_return_scene", "res://scenes/dev/wave_editor.tscn")
	_exit_hd_viewport()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/shoot_pattern_editor.tscn")


func _select_by_key(key: String) -> void:
	for i in _wave_list.item_count:
		if _wave_list.get_item_text(i) == key:
			_wave_list.select(i)
			_on_wave_selected(i)
			return


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
