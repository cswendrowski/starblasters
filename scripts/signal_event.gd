extends Control

# Unknown Signal — narrative event with multi-choice outcomes. Roman,
# 2026-05-16: replaced the original 5 placeholder templates with these
# 4 fleshed-out events.
#
# Each entry is a Dictionary { title, body, choices }. A choice is a
# Dictionary with `label` and an `action: Callable(self) -> void`. The
# action runs whatever side effects the event needs and transitions the
# scene at the end. Callables let each event keep its own logic local
# instead of growing a giant outcome match() in _on_choice.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SectorMapRoute = preload("res://scripts/sector_map_route.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const Strings = preload("res://scripts/strings.gd")

@onready var title_label: Label = $Panel/VBox/Title
@onready var body_label: Label = $Panel/VBox/Body
@onready var choices_box: VBoxContainer = $Panel/VBox/Choices

var _rng: RandomNumberGenerator
var _current_event: Dictionary = {}
var _hd_scope: HdViewportScope = null

# Per-event setup state for events that must pre-roll before building choices.
var _derelict_weapon = null
var _derelict_price: int = 0


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	_layout_hd()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("signal")
	_rng = RandomNumberGenerator.new()
	if has_node("/root/Run"):
		# Seed off the per-node id (set before this scene loads) so each signal
		# node rolls a distinct template/outcome, while staying deterministic on
		# revisit within a run. The old seed used visited_nodes.size(), but that
		# counter is never incremented (Run.mark_node_visited is dead), so it was
		# always 0 -> the seed collapsed to a constant run_seed and EVERY signal
		# event picked the same template (Roman).
		var run = get_node("/root/Run")
		_rng.seed = run.run_seed ^ hash(run.current_node_id)
	else:
		_rng.randomize()
	var events: Array = _events()
	_current_event = events[_rng.randi() % events.size()]
	_render()
	# Debug-only viewport-overflow guard (no-op in release).
	UiTheme.assert_inside_viewport.call_deferred(self)


# The .tscn lays the panel out absolutely (320×220 @ (80,25)) for the old 480
# canvas. Re-center + size it for the 1920×1080 HD viewport and make the inner
# VBox fill it. Fonts are set by _render() via UiTheme.style_label (HD sizes),
# which override the .tscn's native font_size values.
func _layout_hd() -> void:
	var panel := $Panel as Control
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(980, 640)
	panel.size = Vector2(980, 640)
	panel.position = ((get_viewport_rect().size) - panel.size) * 0.5
	var vbox := $Panel/VBox as Control
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 40
	vbox.offset_top = 32
	vbox.offset_right = -40
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 20)
	body_label.custom_minimum_size = Vector2(0, 150)
	choices_box.add_theme_constant_override("separation", 14)


# ---- Event templates ----------------------------------------------------

func _events() -> Array:
	var is_asteroid_field: bool = false
	if has_node("/root/Run"):
		is_asteroid_field = String(get_node("/root/Run").current_hazard_subtype) == "asteroid_field"
	var list: Array = [
		{
			"title": Strings.EVENT_AMBUSH_TITLE,
			"body": Strings.EVENT_AMBUSH_BODY,
			"choices": [
				{
					"label": Strings.CHOICE_AMBUSH_FIGHT,
					"action": func(s): s._do_ambush_combat(),
				},
				{
					"label": Strings.CHOICE_AMBUSH_EVADE,
					"action": func(s): s._do_ambush_evade(),
				},
			],
		},
		{
			"title": Strings.EVENT_NANO_CLOUD_TITLE,
			"body": Strings.EVENT_NANO_CLOUD_BODY,
			"choices": [
				{
					"label": Strings.CHOICE_NANO_FLY,
					"action": func(s): s._do_nano_cloud(),
				},
				{
					"label": Strings.CHOICE_NANO_AVOID,
					"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_NANO_AVOID),
				},
			],
		},
		{
			"title": Strings.EVENT_JUNK_TRADER_TITLE,
			"body": Strings.EVENT_JUNK_TRADER_BODY,
			"choices": [
				{
					"label": Strings.CHOICE_JUNK_SELL,
					"action": func(s): s._do_junk_sell(),
				},
				{
					"label": Strings.CHOICE_JUNK_TRADE,
					"action": func(s): s._do_junk_trade(),
				},
				{
					"label": Strings.CHOICE_JUNK_REPAIR,
					"action": func(s): s._do_junk_repair(),
				},
				{
					"label": Strings.CHOICE_JUNK_AMMO,
					"action": func(s): s._do_junk_ammo(),
				},
				{
					"label": Strings.CHOICE_JUNK_LEAVE,
					"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_JUNK_LEAVE),
				},
			],
		},
		_make_wreck_event(),
		_make_salvage_cache_event(),
		_make_derelict_event(),
		_make_inspection_event(),
		_make_experimental_event(),
		_make_bounty_board_event(),
	]
	if is_asteroid_field:
		list.append({
			"title": Strings.EVENT_MINER_TITLE,
			"body": Strings.EVENT_MINER_BODY,
			"choices": [
				{
					"label": Strings.CHOICE_MINER_AGREE,
					"action": func(s): s._do_freespace_miner(),
				},
				{
					"label": Strings.CHOICE_MINER_REFUSE,
					"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_MINER_REFUSE),
				},
			],
		})
	return list


# Salvage Cache — abandoned cargo container drifting in the void. The
# salvage roll picks one of three outcomes (Cody, 2026-05-24): 40% +1Mk on a
# random upgrade, 35% offer a rolled weapon of >= current Mk for swap, 25%
# ammo refill. Ammo outcome re-rolls if the player has no metered weapons.
func _make_salvage_cache_event() -> Dictionary:
	return {
		"title": Strings.EVENT_SALVAGE_TITLE,
		"body": Strings.EVENT_SALVAGE_BODY,
		"choices": [
			{
				"label": Strings.CHOICE_SALVAGE_SALVAGE,
				"action": func(s): s._do_salvage_cache(),
			},
			{
				"label": Strings.CHOICE_SALVAGE_LEAVE,
				"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_SALVAGE_LEAVE),
			},
		],
	}


# ---- Kill-guard helper --------------------------------------------------

# Returns true if dealing `damage` hull to the player would kill them. Used
# to hide lethal-damage options so we never silently wipe the player.
func _would_kill(damage: int) -> bool:
	if not has_node("/root/Run"):
		return false
	return get_node("/root/Run").current_hull <= damage


# ---- Event 1: Derelict Warship ------------------------------------------
# Pre-rolls a weapon and IFF price before building choices so the dynamic
# label on option 2 is available at render time.

func _make_derelict_event() -> Dictionary:
	var run = get_node_or_null("/root/Run")
	var current_mark: int = 1
	if run != null:
		current_mark = clampi(run.sectors_cleared + 1, 1, 9)
	_derelict_weapon = PartCatalog.roll_for_slot(_rng, Slots.SlotType.CANNON, current_mark)
	_derelict_price = 58 + 35 * (current_mark - 1)
	var choices: Array = []
	if not _would_kill(1):
		choices.append({
			"label": Strings.CHOICE_DERELICT_RISK,
			"action": func(s): s._do_derelict_risk(),
		})
	var can_afford_iff: bool = run != null and int(run.bounty) >= _derelict_price
	if can_afford_iff:
		choices.append({
			"label": Strings.CHOICE_DERELICT_IFF % _derelict_price,
			"action": func(s): s._do_derelict_iff(),
		})
	choices.append({
		"label": Strings.CHOICE_DERELICT_TAG,
		"action": func(s): s._do_derelict_tag(),
	})
	return {
		"title": Strings.EVENT_DERELICT_TITLE,
		"body": Strings.EVENT_DERELICT_BODY,
		"choices": choices,
	}


func _do_derelict_risk() -> void:
	var weapon_label: String = _part_label(_derelict_weapon)
	if _rng.randf() < 0.5:
		_offer_weapon_stow(_derelict_weapon, Strings.OUTCOME_DERELICT_RISK_GOOD % weapon_label)
	else:
		_apply_hull_delta(-1)
		_offer_weapon_stow(_derelict_weapon, Strings.OUTCOME_DERELICT_RISK_BAD % weapon_label)


func _do_derelict_iff() -> void:
	_apply_bounty(-_derelict_price)
	var weapon_label: String = _part_label(_derelict_weapon)
	_offer_weapon_stow(_derelict_weapon, Strings.OUTCOME_DERELICT_IFF % weapon_label)


func _do_derelict_tag() -> void:
	var award: int = 75 + _rng.randi() % 26
	_apply_bounty(award)
	_finish_to_sector_map(Strings.OUTCOME_DERELICT_TAG)


# Directly stow a weapon into Run.inventory without a swap modal, then
# finish to the sector map with the given flavor text. The derelict event
# always stows (no choice) per the spec.
func _offer_weapon_stow(weapon, flavor: String) -> void:
	if has_node("/root/Run") and weapon != null:
		get_node("/root/Run").inventory.append(weapon)
	_finish_to_sector_map(flavor)


# ---- Event 2: Corporate Inspection --------------------------------------

func _make_inspection_event() -> Dictionary:
	return {
		"title": Strings.EVENT_INSPECTION_TITLE,
		"body": Strings.EVENT_INSPECTION_BODY,
		"choices": [
			{
				"label": Strings.CHOICE_INSPECTION_COMPLY,
				"action": func(s): s._do_inspection_comply(),
			},
			{
				"label": Strings.CHOICE_INSPECTION_RUN,
				"action": func(s): s._do_inspection_run(),
			},
			{
				"label": Strings.CHOICE_INSPECTION_FIGHT,
				"action": func(s): s._do_inspection_fight(),
			},
		],
	}


func _do_inspection_comply() -> void:
	var b: int = _bounty()
	var fine: int = max(1, int(float(b) * (0.25 + _rng.randf() * 0.25)))
	_apply_bounty(-fine)
	_finish_to_sector_map(Strings.OUTCOME_INSPECTION_COMPLY % fine)


func _do_inspection_run() -> void:
	# 3-way coin flip. If the damage branch would kill, collapse to a 2-way
	# flip between combat and escape so we never silently wipe the player.
	var roll: int
	if _would_kill(1):
		roll = 1 + _rng.randi() % 2  # 1 = combat, 2 = escape
	else:
		roll = _rng.randi() % 3
	match roll:
		0:
			_apply_hull_delta(-1)
			_finish_to_sector_map(Strings.OUTCOME_INSPECTION_RUN_DAMAGE)
		1:
			if has_node("/root/Run"):
				get_node("/root/Run").combat_intro = "interceptor_chase"
			SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")
		_:
			_finish_to_sector_map(Strings.OUTCOME_INSPECTION_RUN_ESCAPE)


func _do_inspection_fight() -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").combat_intro = "inspection_fight"
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


# ---- Event 3: Experimental Tech -----------------------------------------

func _make_experimental_event() -> Dictionary:
	return {
		"title": Strings.EVENT_EXPERIMENTAL_TITLE,
		"body": Strings.EVENT_EXPERIMENTAL_BODY,
		"choices": [
			{
				"label": Strings.CHOICE_EXPERIMENTAL_CHANCE,
				"action": func(s): s._do_experimental_chance(),
			},
			{
				"label": Strings.CHOICE_EXPERIMENTAL_TAG,
				"action": func(s): s._do_experimental_tag(),
			},
			{
				"label": Strings.CHOICE_EXPERIMENTAL_DESTROY,
				"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_EXPERIMENTAL_DESTROY),
			},
		],
	}


func _do_experimental_chance() -> void:
	if _rng.randf() < 0.60:
		var part_label: String = _upgrade_random_part()
		var msg: String = Strings.OUTCOME_EXPERIMENTAL_UPGRADE % part_label if part_label != "" else Strings.OUTCOME_NANO_UPGRADE_MAXED
		_finish_to_sector_map(msg)
	else:
		var part_label: String = _downgrade_random_part()
		var msg: String = Strings.OUTCOME_EXPERIMENTAL_DOWNGRADE % part_label if part_label != "" else Strings.OUTCOME_NANO_UPGRADE_MAXED
		_finish_to_sector_map(msg)


func _do_experimental_tag() -> void:
	var award: int = 50 + _rng.randi() % 76
	_apply_bounty(award)
	_finish_to_sector_map(Strings.OUTCOME_EXPERIMENTAL_TAG)


# Downgrade a random equipped or inventory part by -1 Mk (floor 1).
func _downgrade_random_part() -> String:
	if not has_node("/root/Run"):
		return ""
	var run := get_node("/root/Run")
	var pool: Array = []
	for slot_key in run.loadout_snapshot.keys():
		var p = run.loadout_snapshot[slot_key]
		if p != null and "mark" in p and int(p.mark) > 1:
			pool.append(p)
	for p in run.inventory:
		if p != null and "mark" in p and int(p.mark) > 1:
			pool.append(p)
	if pool.is_empty():
		return ""
	var pick = pool[_rng.randi() % pool.size()]
	pick.mark = clampi(int(pick.mark) - 1, 1, 9)
	return _part_label(pick)


# ---- Event 4: Bounty Board Alert ----------------------------------------

func _make_bounty_board_event() -> Dictionary:
	var enemy_path: String = ""
	var enemy_name: String = "unknown"
	var entries: Array = EnemyRoster.entries_of(EnemyRoster.Tier.COMMON)
	if not entries.is_empty():
		var entry: Dictionary = entries[_rng.randi() % entries.size()]
		enemy_path = String(entry.get("scene", ""))
		# Derive display name from scene path stem: strip prefix + suffix,
		# capitalize. e.g. "res://scenes/enemies/factions/privateer/enemy_dart.tscn" -> "Dart"
		var stem: String = enemy_path.get_file().replace(".tscn", "").replace("enemy_", "")
		enemy_name = stem.capitalize()
	return {
		"title": Strings.EVENT_BOUNTY_BOARD_TITLE,
		"body": Strings.EVENT_BOUNTY_BOARD_BODY,
		"choices": [
			{
				"label": Strings.CHOICE_BOUNTY_BOARD_OPTIN,
				"action": func(s): s._do_bounty_board_optin(enemy_path, enemy_name),
			},
			{
				"label": Strings.CHOICE_BOUNTY_BOARD_OPTOUT,
				"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_BOUNTY_BOARD_OPTOUT),
			},
		],
	}


func _do_bounty_board_optin(enemy_scene_path: String, enemy_name: String) -> void:
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		if enemy_scene_path != "":
			run.set_meta("bounty_type_bonus_path", enemy_scene_path)
			run.set_meta("bounty_type_bonus_mult", 1.15)
		run.set_meta("extra_combat_waves", 3)
	_finish_to_sector_map(Strings.OUTCOME_BOUNTY_BOARD_OPTIN % enemy_name)


# Wrecked Starfighter — five-choice rework (Roman, 2026-05-24):
#   1. Claim bounty   — random chaff enemy's bounty_value tagged on the wreck
#   2. Scavenge weapon — roll a weapon for one of the swap-eligible slots
#   3. Scavenge upgrade — +1 Mk on a random non-maxed upgrade
#   4. Scavenge ammo   — only offered if player runs a metered weapon below 100%
#   5. Leave it be     — no rewards, move on
# Ammo option is gated explicitly — omitted from the choice list when the
# player has nothing to refill (no silent fallback path).
func _make_wreck_event() -> Dictionary:
	var choices: Array = [
		{
			"label": Strings.CHOICE_WRECK_BOUNTY,
			"action": func(s): s._do_wreck_claim_bounty(),
		},
		{
			"label": Strings.CHOICE_WRECK_WEAPON,
			"action": func(s): s._do_wreck_scavenge_weapon(),
		},
		{
			"label": Strings.CHOICE_WRECK_UPGRADE,
			"action": func(s): s._do_wreck_scavenge_upgrade(),
		},
	]
	if _wreck_ammo_option_available():
		choices.append({
			"label": Strings.CHOICE_WRECK_AMMO,
			"action": func(s): s._do_wreck_scavenge_ammo(),
		})
	choices.append({
		"label": Strings.CHOICE_WRECK_LEAVE,
		"action": func(s): s._finish_to_sector_map(Strings.OUTCOME_WRECK_LEAVE),
	})
	return {
		"title": Strings.EVENT_WRECK_TITLE,
		"body": Strings.EVENT_WRECK_BODY,
		"choices": choices,
	}


# True if the player currently runs a metered weapon (MG primary or
# ammo-bearing secondary) AND that meter is below 100% — otherwise the
# ammo option is hidden so the event never offers a no-op.
func _wreck_ammo_option_available() -> bool:
	if not has_node("/root/Run"):
		return false
	var run := get_node("/root/Run")
	# MG primary: track on Run.ammo. -1 = no MG; otherwise canonical full == 1000.
	const MG_FULL := 1000
	if int(run.ammo) >= 0 and int(run.ammo) < MG_FULL:
		return true
	# Secondary: secondary_ammo_max is the canonical max for the equipped part.
	if int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0:
		if int(run.secondary_ammo) < int(run.secondary_ammo_max):
			return true
	return false


# ---- Outcome implementations -------------------------------------------

# Ambush: launch combat. Flag the combat_intro so the level opens with
# fighters flying up through the parallax (wired in main.gd later).
func _do_ambush_combat() -> void:
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		run.combat_intro = "fly_up_from_below"
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _do_ambush_evade() -> void:
	if _rng.randf() < 0.5:
		_finish_to_sector_map(Strings.OUTCOME_AMBUSH_EVADE_CLEAN)
	else:
		_apply_hull_delta(-1)
		_finish_to_sector_map(Strings.OUTCOME_AMBUSH_EVADE_HIT)


# Nano Cloud: 25% damage / 50% repair / 10% upgrade / 15% ammo. The ammo
# outcome only triggers if the player has an ammo-fed weapon equipped
# (Roman, 2026-05-16). Otherwise the roll folds into the repair bucket.
func _do_nano_cloud() -> void:
	var has_ammo_weapon: bool = false
	if has_node("/root/Run"):
		has_ammo_weapon = int(get_node("/root/Run").ammo) >= 0
	var roll: float = _rng.randf()
	if roll < 0.25:
		var dmg := 2 + _rng.randi() % 2  # 2-3 hull
		_apply_hull_delta(-dmg)
		_finish_to_sector_map(Strings.OUTCOME_NANO_DAMAGE % dmg)
		return
	if roll < 0.85:
		var rep := 2 + _rng.randi() % 3  # 2-4 hull
		_apply_hull_delta(rep)
		_finish_to_sector_map(Strings.OUTCOME_NANO_REPAIR % rep)
		return
	if roll < 0.95:
		var part_label: String = _upgrade_random_part()
		var msg: String = Strings.OUTCOME_NANO_UPGRADE % part_label if part_label != "" else Strings.OUTCOME_NANO_UPGRADE_MAXED
		_finish_to_sector_map(msg)
		return
	# Ammo outcome — only if MG equipped, else collapse to repair.
	if has_ammo_weapon and has_node("/root/Run"):
		var amt := 200 + _rng.randi() % 200  # 200-399 rounds
		var run := get_node("/root/Run")
		run.ammo = int(run.ammo) + amt
		_finish_to_sector_map(Strings.OUTCOME_NANO_AMMO % amt)
	else:
		var rep2 := 2 + _rng.randi() % 3
		_apply_hull_delta(rep2)
		_finish_to_sector_map(Strings.OUTCOME_NANO_REPAIR % rep2)


# Junk Trader: sell an uninstalled inventory part.
func _do_junk_sell() -> void:
	if not _has_inventory():
		_finish_to_sector_map(Strings.OUTCOME_JUNK_NO_CARGO_SELL)
		return
	var inv: Array = _inventory()
	# Pick the first inventory item. Future: present a list to choose.
	var part = inv.pop_front()
	var price: int = _sell_price(part)
	_apply_bounty(price)
	_finish_to_sector_map(Strings.OUTCOME_JUNK_SOLD % [_part_label(part), price])


# Junk Trader: trade an inventory part for another same-slot part with a
# weighted mark-delta roll.
#   10% -1 mark, 40% same, 30% +1, 20% +2
func _do_junk_trade() -> void:
	if not _has_inventory():
		_finish_to_sector_map(Strings.OUTCOME_JUNK_NO_CARGO_TRADE)
		return
	var inv: Array = _inventory()
	var part = inv.pop_front()
	var slot: int = part.slot_type
	var roll: float = _rng.randf()
	var delta: int = 0
	if roll < 0.10: delta = -1
	elif roll < 0.50: delta = 0
	elif roll < 0.80: delta = 1
	else: delta = 2
	var new_mark: int = clampi(int(part.mark) + delta, 1, 9)
	var new_part = PartCatalog.roll_for_slot(_rng, slot, new_mark)
	if new_part == null:
		# No alternative for this slot — give the original back, refund a token.
		inv.append(part)
		_finish_to_sector_map(Strings.OUTCOME_JUNK_NO_SLOT)
		return
	inv.append(new_part)
	var sign_s: String = ("+%d" % delta) if delta >= 0 else str(delta)
	_finish_to_sector_map(Strings.OUTCOME_JUNK_TRADED % [_part_label(part), _part_label(new_part), sign_s])


# Junk Trader: repair 3 hull for 30 bounty.
func _do_junk_repair() -> void:
	if _bounty() < 30:
		_finish_to_sector_map(Strings.OUTCOME_JUNK_REPAIR_BROKE)
		return
	_apply_bounty(-30)
	_apply_hull_delta(3)
	_finish_to_sector_map(Strings.OUTCOME_JUNK_REPAIRED)


# Junk Trader: cheap ammo top-up. Adds 500 rounds for 15 bounty. Only
# meaningful when the player is running the machinegun cannon — refuses
# politely otherwise (Roman, 2026-05-16: "trader event should offer cheap
# ammo refills").
const _JUNK_AMMO_COST := 15
const _JUNK_AMMO_AMOUNT := 500
func _do_junk_ammo() -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map(Strings.OUTCOME_JUNK_NO_RUN)
		return
	var run := get_node("/root/Run")
	if int(run.ammo) < 0:
		_finish_to_sector_map(Strings.OUTCOME_JUNK_NO_AMMO_WEAPON)
		return
	if int(run.bounty) < _JUNK_AMMO_COST:
		_finish_to_sector_map(Strings.OUTCOME_JUNK_AMMO_BROKE % _JUNK_AMMO_COST)
		return
	run.bounty -= _JUNK_AMMO_COST
	run.ammo = int(run.ammo) + _JUNK_AMMO_AMOUNT
	_finish_to_sector_map(Strings.OUTCOME_JUNK_AMMO_LOADED % [_JUNK_AMMO_COST, _JUNK_AMMO_AMOUNT])


# Wrecked Starfighter outcome handlers (Roman, 2026-05-24 rework).

# Claim bounty — pull a random chaff enemy's bounty_value out of the roster
# so the payout reflects "what a kill of that ship would yield."
func _do_wreck_claim_bounty() -> void:
	var entries: Array = EnemyRoster.entries_of(EnemyRoster.Tier.COMMON)
	if entries.is_empty():
		# Should be impossible — roster always has chaff. Fall back loud.
		push_warning("Wrecked Starfighter: no COMMON entries in roster")
		_apply_bounty(10)
		_finish_to_sector_map(Strings.OUTCOME_WRECK_BOUNTY_FALLBACK)
		return
	var entry: Dictionary = entries[_rng.randi() % entries.size()]
	var stats: Dictionary = EnemyRoster.compose_stats(entry)
	var value: int = max(1, int(stats.get("bounty_value", 5)))
	_apply_bounty(value)
	_finish_to_sector_map(Strings.OUTCOME_WRECK_BOUNTY % value)


# Scavenge weapon — same swap modal flow as Salvage Cache: roll one of
# CANNON / HARDPOINT_WING and present a Swap/Keep choice.
func _do_wreck_scavenge_weapon() -> void:
	_salvage_outcome_weapon()


# Scavenge upgrade — same +1 Mk path as Salvage Cache; if all upgrades
# are at the cap, the salvage helper escalates to a weapon offer so the
# event still pays.
func _do_wreck_scavenge_upgrade() -> void:
	_salvage_outcome_upgrade()


# Scavenge ammo — restore 25% of max on whatever metered weapons are
# below full. Guarded by _wreck_ammo_option_available; this should never
# run with nothing to refill.
func _do_wreck_scavenge_ammo() -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map(Strings.OUTCOME_WRECK_NO_RUN)
		return
	var run := get_node("/root/Run")
	var parts: Array = []
	const MG_FULL := 1000
	if int(run.ammo) >= 0 and int(run.ammo) < MG_FULL:
		var add_mg: int = int(round(float(MG_FULL) * 0.25))
		run.ammo = min(MG_FULL, int(run.ammo) + add_mg)
		parts.append(Strings.AMMO_FRAGMENT_MG % add_mg)
	if int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0 \
			and int(run.secondary_ammo) < int(run.secondary_ammo_max):
		var add_sec: int = max(1, int(round(float(run.secondary_ammo_max) * 0.25)))
		run.secondary_ammo = min(int(run.secondary_ammo_max), int(run.secondary_ammo) + add_sec)
		parts.append(Strings.AMMO_FRAGMENT_SECONDARY % add_sec)
	if parts.is_empty():
		# Shouldn't happen — option would have been hidden.
		_finish_to_sector_map(Strings.OUTCOME_WRECK_AMMO_FULL)
		return
	_finish_to_sector_map(Strings.OUTCOME_WRECK_AMMO + ", ".join(parts))


# Salvage Cache — three sub-outcomes, weighted. The ammo refill re-rolls
# itself if the player has no metered weapons so the event isn't wasted.
const _SALVAGE_UPGRADE_KEYS := [
	"hull_mk", "armor_mk", "thrusters_mk",
	"self_repair_mk", "shield_cap_mk", "shield_recharge_mk",
]
const _SALVAGE_UPGRADE_LABELS := {
	"hull_mk": "Hull",
	"armor_mk": "Armor",
	"thrusters_mk": "Thrusters",
	"self_repair_mk": "Self Repair",
	"shield_cap_mk": "Shield Capacity",
	"shield_recharge_mk": "Shield Recharge",
}
const _SALVAGE_MK_CAP := 9

# 40% +1Mk upgrade, 35% weapon offer, 25% ammo refill.
func _do_salvage_cache(reroll_depth: int = 0) -> void:
	var roll: float = _rng.randf()
	if roll < 0.40:
		_salvage_outcome_upgrade()
		return
	if roll < 0.75:
		_salvage_outcome_weapon()
		return
	# Ammo outcome — collapses to a fresh roll if no metered weapons.
	if not _has_metered_weapons():
		if reroll_depth >= 4:
			# Belt-and-suspenders: if we somehow keep rolling ammo with no
			# metered weapons, fall through to an upgrade so we never spin.
			_salvage_outcome_upgrade()
			return
		_do_salvage_cache(reroll_depth + 1)
		return
	_salvage_outcome_ammo()


func _salvage_outcome_upgrade() -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map(Strings.OUTCOME_SALVAGE_NO_RUN)
		return
	var run := get_node("/root/Run")
	var eligible: Array = []
	for k in _SALVAGE_UPGRADE_KEYS:
		if int(run.get(k)) < _SALVAGE_MK_CAP:
			eligible.append(k)
	if eligible.is_empty():
		# All upgrades maxed — try weapon offer instead so the event still pays.
		_salvage_outcome_weapon()
		return
	var key: String = eligible[_rng.randi() % eligible.size()]
	var new_mk: int = int(run.get(key)) + 1
	run.set(key, new_mk)
	var label: String = String(_SALVAGE_UPGRADE_LABELS.get(key, key))
	_finish_to_sector_map(Strings.OUTCOME_SALVAGE_UPGRADE % [label, new_mk])


# Roll a weapon at >= current Mk in either CANNON or HARDPOINT_WING slot,
# then offer the player a swap modal. Picks the slot randomly, falls back
# to the other slot if the player has nothing equipped in the first pick.
func _salvage_outcome_weapon() -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map(Strings.OUTCOME_SALVAGE_NO_RUN)
		return
	var run := get_node("/root/Run")
	var slot_pool: Array = [
		int(Slots.SlotType.CANNON),
		int(Slots.SlotType.HARDPOINT_WING),
	]
	# Try the random pick first, then the other slot.
	var first: int = slot_pool[_rng.randi() % slot_pool.size()]
	var slots: Array = [first]
	for s in slot_pool:
		if s != first:
			slots.append(s)
	for slot in slots:
		var current = run.loadout_snapshot.get(slot, null)
		var current_mark: int = int(current.mark) if current != null and "mark" in current else 1
		var new_part = PartCatalog.roll_for_slot(_rng, slot, current_mark)
		if new_part == null:
			continue
		# If we drew a lower Mk than the player's current part, snap up.
		if "mark" in new_part and int(new_part.mark) < current_mark:
			new_part.mark = current_mark
		_offer_weapon_swap(slot, current, new_part)
		return
	_finish_to_sector_map(Strings.OUTCOME_SALVAGE_NO_WEAPONS)


# Replace the choice row with a Swap / Keep modal — single-screen, no scene
# change. Outcome resolves via _finish_to_sector_map either way.
func _offer_weapon_swap(slot: int, current_part, new_part) -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map(Strings.OUTCOME_SALVAGE_NO_RUN)
		return
	var slot_name: String = Strings.PART_SLOT_NAME_PRIMARY if slot == int(Slots.SlotType.CANNON) else Strings.PART_SLOT_NAME_SECONDARY
	var new_label: String = _part_label(new_part)
	var current_label: String = _part_label(current_part) if current_part != null else Strings.PART_SLOT_EMPTY
	body_label.text = Strings.EVENT_SWAP_BODY % [new_label, slot_name, current_label]
	for c in choices_box.get_children():
		c.queue_free()
	var swap_btn := Button.new()
	swap_btn.text = Strings.EVENT_SWAP_BTN % new_label
	UiTheme.style_button(swap_btn)
	swap_btn.pressed.connect(func():
		var run := get_node("/root/Run")
		# Move the displaced part to inventory if there was one.
		if current_part != null:
			run.inventory.append(current_part)
		run.loadout_snapshot[slot] = new_part
		_finish_to_sector_map(Strings.OUTCOME_SWAP_EQUIPPED % [new_label, slot_name])
	)
	choices_box.add_child(swap_btn)
	var keep_btn := Button.new()
	keep_btn.text = Strings.EVENT_SWAP_KEEP % new_label
	UiTheme.style_button(keep_btn)
	keep_btn.pressed.connect(func():
		var run := get_node("/root/Run")
		run.inventory.append(new_part)
		_finish_to_sector_map(Strings.OUTCOME_SWAP_STOWED % new_label)
	)
	choices_box.add_child(keep_btn)


func _has_metered_weapons() -> bool:
	if not has_node("/root/Run"):
		return false
	var run := get_node("/root/Run")
	var has_mg: bool = int(run.ammo) >= 0
	var has_sec: bool = int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0
	return has_mg or has_sec


func _salvage_outcome_ammo() -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map(Strings.OUTCOME_SALVAGE_NO_RUN)
		return
	var run := get_node("/root/Run")
	var parts: Array = []
	# MG: there's no Run-side max, but the player + outpost both treat 1000
	# as the canonical full value (AMMO_FULL_VALUE). Match that here.
	const MG_FULL := 1000
	if int(run.ammo) >= 0:
		run.ammo = MG_FULL
		parts.append(Strings.AMMO_FRAGMENT_MG % MG_FULL)
	if int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0:
		run.secondary_ammo = int(run.secondary_ammo_max)
		parts.append(Strings.AMMO_FRAGMENT_SECONDARY_FULL % int(run.secondary_ammo_max))
	if parts.is_empty():
		# Shouldn't happen — _has_metered_weapons gated this. Bail safe.
		_finish_to_sector_map(Strings.OUTCOME_SALVAGE_AMMO_INERT)
		return
	_finish_to_sector_map(Strings.OUTCOME_SALVAGE_AMMO + ", ".join(parts))


# Freespace Miner: launch asteroid hazard. Per-asteroid bounty is suppressed
# (Run.asteroid_bonus_bounty stays 0); main.gd counts asteroid kills and pays
# 5 bounty per on clear, then posts the thank-you banner above the sector map
# (Roman, 2026-05-24: "give this level a level clear and count the asteroids
# destroyed, and give 5 bounty per ... above the sector map").
func _do_freespace_miner() -> void:
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD
		run.current_hazard_subtype = "asteroid_field"
		run.asteroid_bonus_bounty = 0
		run.set_meta("asteroid_miners_event", true)
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


# ---- Helpers ------------------------------------------------------------

func _apply_bounty(delta: int) -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").bounty += delta


func _apply_hull_delta(delta: int) -> void:
	if not has_node("/root/Run"):
		return
	var run := get_node("/root/Run")
	if run.max_hull <= 0:
		return
	run.current_hull = clampi(run.current_hull + delta, 0, run.max_hull)


func _has_inventory() -> bool:
	return has_node("/root/Run") and not get_node("/root/Run").inventory.is_empty()


func _inventory() -> Array:
	return get_node("/root/Run").inventory if has_node("/root/Run") else []


func _bounty() -> int:
	return int(get_node("/root/Run").bounty) if has_node("/root/Run") else 0


func _sell_price(part) -> int:
	# 20% of the cannon-buy formula (same rule as outpost._sell_value_for —
	# Roman 2026-05-25 economy pass: no more resale arbitrage between venues).
	# Mk.1 = 11, Mk.5 = 39, Mk.9 = 67. Floor of 5 so a Mk.1 still pays out.
	var m: int = int(part.mark) if part and "mark" in part else 1
	var buy_cost: int = 58 + 35 * (m - 1)  # mirrors outpost CANNON_BASE_COST / CANNON_COST_PER_MK
	return max(5, int(0.2 * float(buy_cost)))


func _part_label(part) -> String:
	if part == null:
		return Strings.PART_LABEL_UNKNOWN
	var n: String = part.get_class()
	if "mark" in part:
		return Strings.PART_LABEL_FORMAT % [int(part.mark), n]
	return n


func _upgrade_random_part() -> String:
	if not has_node("/root/Run"):
		return ""
	var run := get_node("/root/Run")
	# Try equipped loadout first, then inventory cargo.
	var pool: Array = []
	for slot_key in run.loadout_snapshot.keys():
		var p = run.loadout_snapshot[slot_key]
		if p != null and "mark" in p and int(p.mark) < _part_max_mark(p):
			pool.append(p)
	for p in run.inventory:
		if p != null and "mark" in p and int(p.mark) < _part_max_mark(p):
			pool.append(p)
	if pool.is_empty():
		return ""
	var pick = pool[_rng.randi() % pool.size()]
	pick.mark = clampi(int(pick.mark) + 1, 1, _part_max_mark(pick))
	return _part_label(pick)


# A part's Mk ceiling — engines cap at 6, everything else at 9. Older parts
# without the field fall back to 9.
func _part_max_mark(p) -> int:
	return int(p.max_mark) if (p != null and "max_mark" in p) else 9


# ---- Rendering ---------------------------------------------------------

func _render() -> void:
	title_label.text = _current_event.get("title", Strings.EVENT_UNKNOWN_TITLE)
	body_label.text = _current_event.get("body", "")
	UiTheme.style_label(title_label, UiTheme.LabelKind.HEADER)
	UiTheme.style_label(body_label, UiTheme.LabelKind.BODY)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for c in choices_box.get_children():
		c.queue_free()
	for choice in _current_event.get("choices", []):
		var b = Button.new()
		b.text = choice["label"]
		UiTheme.style_button(b)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect(_on_choice.bind(choice))
		choices_box.add_child(b)


func _on_choice(choice: Dictionary) -> void:
	# Disable all buttons so the player can't double-click while we resolve.
	for c in choices_box.get_children():
		if c is Button:
			c.disabled = true
	var action: Callable = choice.get("action", Callable())
	if action.is_valid():
		action.call(self)


# Roman, 2026-05-16: when an event resolves, swap the choices for the
# result summary and let the player click "Sector Map" to advance — same
# rhythm as a level-cleared screen. No auto-timeout.
func _finish_to_sector_map(result_text: String) -> void:
	# Replace body with the outcome so the player sees what their choice did.
	if result_text != "":
		body_label.text = result_text
	# Drop existing choice buttons and offer a single Sector Map continue.
	for c in choices_box.get_children():
		c.queue_free()
	var btn := Button.new()
	btn.text = Strings.BTN_SECTOR_MAP
	UiTheme.style_button(btn)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 56)
	btn.pressed.connect(func():
		# Mark the signal node done in the V3 sector cache before leaving.
		# Signal events that escalated into combat/hazard already routed
		# through main.gd's mark_node_completed; this covers the plain
		# choice-only exit path.
		if has_node("/root/Run"):
			var run := get_node("/root/Run")
			if String(run.current_node_id) != "":
				run.mark_node_completed(String(run.current_node_id))
		SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)
	)
	choices_box.add_child(btn)
