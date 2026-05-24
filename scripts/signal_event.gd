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

@onready var title_label: Label = $Panel/VBox/Title
@onready var body_label: Label = $Panel/VBox/Body
@onready var choices_box: VBoxContainer = $Panel/VBox/Choices

var _rng: RandomNumberGenerator
var _current_event: Dictionary = {}


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("signal")
	_rng = RandomNumberGenerator.new()
	if has_node("/root/Run"):
		_rng.seed = get_node("/root/Run").run_seed + get_node("/root/Run").visited_nodes.size() * 31
	else:
		_rng.randomize()
	var events: Array = _events()
	_current_event = events[_rng.randi() % events.size()]
	_render()


# ---- Event templates ----------------------------------------------------

func _events() -> Array:
	return [
		{
			"title": "Ambush!",
			"body": "Warning lights flare in your periphery: active scan warnings. Sensors pick them up a second later — multiple incoming signatures closing from behind!",
			"choices": [
				{
					"label": "Fight through (combat)",
					"action": func(s): s._do_ambush_combat(),
				},
				{
					"label": "Evasive maneuvers (-2 hull)",
					"action": func(s): s._do_ambush_evade(),
				},
			],
		},
		{
			"title": "Drifting Nano Cloud",
			"body": "Sensors indicate micro-energy signatures. You squint, and can see a glittering cloud moving like a swarm of bugs. A nano cloud?",
			"choices": [
				{
					"label": "Fly into it (risk/reward)",
					"action": func(s): s._do_nano_cloud(),
				},
				{
					"label": "Avoid it",
					"action": func(s): s._finish_to_sector_map("Course corrected. No effect."),
				},
			],
		},
		{
			"title": "Junk Trader",
			"body": "An old cargo hauler drifts through space, a makeshift drydock bay built into its side. A hacked transponder signal bleats out garbled promises of top quality repairs and exciting deals.",
			"choices": [
				{
					"label": "Sell a part (+bounty)",
					"action": func(s): s._do_junk_sell(),
				},
				{
					"label": "Trade a part (random outcome)",
					"action": func(s): s._do_junk_trade(),
				},
				{
					"label": "Repair hull (-30 bounty, +3 hull)",
					"action": func(s): s._do_junk_repair(),
				},
				{
					"label": "Buy ammo (-15 bounty, +500 rounds)",
					"action": func(s): s._do_junk_ammo(),
				},
				{
					"label": "Leave",
					"action": func(s): s._finish_to_sector_map("You break orbit — the hauler drifts on."),
				},
			],
		},
		{
			"title": "Freespace Miner",
			"body": "Your comms light up as a wandering mining ship calls for your attention: they've found high-value minerals, but the asteroids are too tough for their mining lasers. Proper fighter weapons would crack them.",
			"choices": [
				{
					"label": "Agree (asteroid run, +bounty per rock)",
					"action": func(s): s._do_freespace_miner(),
				},
				{
					"label": "Refuse",
					"action": func(s): s._finish_to_sector_map("Channel closed."),
				},
			],
		},
		_make_wreck_event(),
	]


# Wrecked Starfighter — the scavenge option flips based on whether the
# player runs an ammo-fed weapon. Roman, 2026-05-16: "Add back in the
# wreck event as a wrecked starfighter, add scavenge ammo as an option
# if the user has ammo weapons, otherwise scavenge bounty."
func _make_wreck_event() -> Dictionary:
	var has_ammo_weapon: bool = false
	if has_node("/root/Run"):
		has_ammo_weapon = int(get_node("/root/Run").ammo) >= 0
	var scavenge_label: String = "Scavenge ammo (+300 rounds)" if has_ammo_weapon else "Scavenge bounty (+30)"
	return {
		"title": "Wrecked Starfighter",
		"body": "A burnt-out fighter tumbles end over end through the void, hull cracked and lockers spilling debris. Worth a closer look.",
		"choices": [
			{
				"label": "Tag for bounty (+25)",
				"action": func(s): s._do_wreck_tag(),
			},
			{
				"label": scavenge_label,
				"action": func(s): s._do_wreck_scavenge(has_ammo_weapon),
			},
			{
				"label": "Leave it be",
				"action": func(s): s._finish_to_sector_map("You give the wreck a wide berth."),
			},
		],
	}


# ---- Outcome implementations -------------------------------------------

# Ambush: launch combat. Flag the combat_intro so the level opens with
# fighters flying up through the parallax (wired in main.gd later).
func _do_ambush_combat() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.combat_intro = "fly_up_from_below"
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _do_ambush_evade() -> void:
	_apply_hull_delta(-2)
	_finish_to_sector_map("Evaded — hull took 2 damage")


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
		_finish_to_sector_map("Hostile nanites! -%d hull" % dmg)
		return
	if roll < 0.85:
		var rep := 2 + _rng.randi() % 3  # 2-4 hull
		_apply_hull_delta(rep)
		_finish_to_sector_map("Repair nanites. +%d hull" % rep)
		return
	if roll < 0.95:
		var part_label: String = _upgrade_random_part()
		var msg: String = "Beneficial swarm! Upgraded %s" % part_label if part_label != "" else "Beneficial swarm — but nothing upgradable!"
		_finish_to_sector_map(msg)
		return
	# Ammo outcome — only if MG equipped, else collapse to repair.
	if has_ammo_weapon and has_node("/root/Run"):
		var amt := 200 + _rng.randi() % 200  # 200-399 rounds
		var run = get_node("/root/Run")
		run.ammo = int(run.ammo) + amt
		_finish_to_sector_map("Nanites manufactured ammo! +%d rounds" % amt)
	else:
		var rep2 := 2 + _rng.randi() % 3
		_apply_hull_delta(rep2)
		_finish_to_sector_map("Repair nanites. +%d hull" % rep2)


# Junk Trader: sell an uninstalled inventory part.
func _do_junk_sell() -> void:
	if not _has_inventory():
		_finish_to_sector_map("No spare parts in cargo to sell.")
		return
	var inv: Array = _inventory()
	# Pick the first inventory item. Future: present a list to choose.
	var part = inv.pop_front()
	var price: int = _sell_price(part)
	_apply_bounty(price)
	_finish_to_sector_map("Sold %s for %d bounty" % [_part_label(part), price])


# Junk Trader: trade an inventory part for another same-slot part with a
# weighted mark-delta roll.
#   10% -1 mark, 40% same, 30% +1, 20% +2
func _do_junk_trade() -> void:
	if not _has_inventory():
		_finish_to_sector_map("No spare parts in cargo to trade.")
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
		_finish_to_sector_map("Trader has nothing for that slot.")
		return
	inv.append(new_part)
	var sign_s: String = ("+%d" % delta) if delta >= 0 else str(delta)
	_finish_to_sector_map("Traded %s → %s (Mk %s)" % [_part_label(part), _part_label(new_part), sign_s])


# Junk Trader: repair 3 hull for 30 bounty.
func _do_junk_repair() -> void:
	if _bounty() < 30:
		_finish_to_sector_map("Not enough bounty (need 30).")
		return
	_apply_bounty(-30)
	_apply_hull_delta(3)
	_finish_to_sector_map("Patched up. -30 bounty, +3 hull")


# Junk Trader: cheap ammo top-up. Adds 500 rounds for 15 bounty. Only
# meaningful when the player is running the machinegun cannon — refuses
# politely otherwise (Roman, 2026-05-16: "trader event should offer cheap
# ammo refills").
const _JUNK_AMMO_COST := 15
const _JUNK_AMMO_AMOUNT := 500
func _do_junk_ammo() -> void:
	if not has_node("/root/Run"):
		_finish_to_sector_map("Comms dropped.")
		return
	var run = get_node("/root/Run")
	if int(run.ammo) < 0:
		_finish_to_sector_map("No ammo-fed weapon to refill.")
		return
	if int(run.bounty) < _JUNK_AMMO_COST:
		_finish_to_sector_map("Not enough bounty (need %d)." % _JUNK_AMMO_COST)
		return
	run.bounty -= _JUNK_AMMO_COST
	run.ammo = int(run.ammo) + _JUNK_AMMO_AMOUNT
	_finish_to_sector_map("Crates loaded. -%d bounty, +%d rounds" % [_JUNK_AMMO_COST, _JUNK_AMMO_AMOUNT])


# Floating Wreck: three salvage paths. Tag = pure bounty grab. Parts =
# modest bounty + hull patch. Ammo = no bounty, free rounds (refuses if
# you don't have an ammo-fed weapon). Roman, 2026-05-16: "The wreck
# event for scavenging bounty should also let you scavenge for ammo".
func _do_wreck_tag() -> void:
	_apply_bounty(25)
	_finish_to_sector_map("Bounty tagged. +25 bounty")


# Single scavenge action — `prefer_ammo` is true when the player has an
# ammo-fed weapon (resolved when _events() built the wreck dict), and
# the scavenge yields rounds instead of bounty.
func _do_wreck_scavenge(prefer_ammo: bool) -> void:
	if prefer_ammo and has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.ammo = int(run.ammo) + 300
		_finish_to_sector_map("Locker pried open. +300 rounds")
	else:
		_apply_bounty(30)
		_finish_to_sector_map("Salvaged scrap. +30 bounty")


# Freespace Miner: launch asteroid hazard with bonus bounty per asteroid.
func _do_freespace_miner() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD
		run.current_hazard_subtype = "asteroid_field"
		run.asteroid_bonus_bounty = 5  # per asteroid
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


# ---- Helpers ------------------------------------------------------------

func _apply_bounty(delta: int) -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").bounty += delta


func _apply_hull_delta(delta: int) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
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
	# Mk.N parts sell for 15 + 10×(N-1) bounty. Mk.1 = 15, Mk.9 = 95.
	var m: int = int(part.mark) if part and "mark" in part else 1
	return 15 + 10 * (m - 1)


func _part_label(part) -> String:
	if part == null:
		return "unknown part"
	var n: String = part.get_class()
	if "mark" in part:
		return "Mk.%d %s" % [int(part.mark), n]
	return n


func _upgrade_random_part() -> String:
	if not has_node("/root/Run"):
		return ""
	var run = get_node("/root/Run")
	# Try equipped loadout first, then inventory cargo.
	var pool: Array = []
	for slot_key in run.loadout_snapshot.keys():
		var p = run.loadout_snapshot[slot_key]
		if p != null and "mark" in p and int(p.mark) < 9:
			pool.append(p)
	for p in run.inventory:
		if p != null and "mark" in p and int(p.mark) < 9:
			pool.append(p)
	if pool.is_empty():
		return ""
	var pick = pool[_rng.randi() % pool.size()]
	pick.mark = clampi(int(pick.mark) + 1, 1, 9)
	return _part_label(pick)


# ---- Rendering ---------------------------------------------------------

func _render() -> void:
	title_label.text = _current_event.get("title", "Unknown Signal")
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
	btn.text = "Sector Map"
	UiTheme.style_button(btn)
	btn.pressed.connect(func():
		# Mark the signal node done in the V3 sector cache before leaving.
		# Signal events that escalated into combat/hazard already routed
		# through main.gd's mark_node_completed; this covers the plain
		# choice-only exit path.
		if has_node("/root/Run"):
			var run = get_node("/root/Run")
			if String(run.current_node_id) != "":
				run.mark_node_completed(String(run.current_node_id))
		SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)
	)
	choices_box.add_child(btn)
