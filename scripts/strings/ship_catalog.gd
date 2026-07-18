extends Object

# Canonical player-ship roster — the SINGLE source of truth for the ship picker, the
# outpost/patrol cinematics, the loading screen, the codex "Ships" category, and the dev
# labs. Index = Run.ship_variant (0 = the default Starblaster; 1/2 were the old "ship B / C"
# alternate hulls, now the Falchion / Cobra — kept at those indices for save compatibility).
#
# Each entry carries everything those consumers need so the 10-ship table lives in ONE place
# (the hangar's 5×2 park grid is full — scenes/hangar_stage.tscn slot markers; adding an
# 11th hull means authoring new Park markers there first)
# instead of being copy-pasted per screen:
#   scene .......... combat player scene (instantiated at run start)
#   name / tag ..... display name + one-line picker subtitle
#   body/livery/engine .. the 3-frame sprite sheets (frame 1 = neutral pose) for cinematic
#                         compositing + picker previews
#   engines ........ nozzle marker offsets (1 or 2) for engine glow / trail / spark placement
#   livery_color ... signature default hull tint (the picker still lets the player override)
#   codex .......... fleet-codex flavor blurb ([REVIEW] = AI first-pass draft, pending Roman)
#   loadout ........ the REAL starting kit (2026-07-11, docs/ship_starting_loadouts_2026-07-11.md),
#                    seeded by Run._seed_default_loadout_snapshot via PartCatalog.make_part.
#                    Keys (all optional; a missing key = the classic default for that slot):
#                      blaster   [factory, mk] — infinite cannon replacing pool[0]'s Energy Blaster
#                      primary   [factory, mk] — metered cannon at pool[1], ACTIVE at start
#                      secondary [factory, mk] — pre-equipped wing-hardpoint munition
#                      modules   [[factory, mk], ...] — module bay (REPLACES the default Shield Core)
#                      mode      factory string — shift mode replacing the default Focus
#                    Kits are budgeted to ~659 effective value (par with the Reaver).
#                    The patrol-start panel + codex derive their ARMAMENT/MODULES/MODE
#                    lines from this via loadout_display() (real in-game labels + marks;
#                    the old hand-written display strings were retired 2026-07-11).
#
# Preload-referenced, NOT a class_name (headless class-cache safety, matching enemy_strings /
# codex_strings / factions). Usage:
#   const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
#   ShipCatalog.scene_path(Run.ship_variant)   ShipCatalog.get_ship(idx)   ShipCatalog.count()

const SHIPS := [
	{
		"id": "starblaster",
		"scene": "res://scenes/player/player.tscn",
		"name": "F/A-83 Reaver",
		"tag": "Standard hull",
		"body": "res://graphics/player/player_ship_a_body.png",
		"livery": "res://graphics/player/player_ship_a_livery.png",
		"engine": "res://graphics/player/player_ship_a_engines.png",
		"engines": [Vector2(0, 6)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.90, 0.16, 0.16),
		"codex": "A venerable hull flown by the last free systems before the stars were carved up by Ultra Galactic, the Supremacy, and Evantians. The Reaver lacks speed and armament, but it has one thing in spades: potential. This workhorse craft will do anything it's asked to, as long as it's given the materials and modules it needs.",
		# Baseline hull: the vintage core + Refire (it starts with the fewest toys, so the
		# mode gives its one blaster some punch).
		"loadout": {
			"modules": [["_make_shield_core", 1]],
			"mode": "_make_refire_mode",
		},
	},
	{
		"id": "falchion",
		"scene": "res://scenes/player/player_falchion.tscn",
		"name": "F/A-29 Falchion",
		"tag": "Heavy Fighter",
		"body": "res://graphics/player/player_falchion_body.png",
		"livery": "res://graphics/player/player_falchion_livery.png",
		"engine": "res://graphics/player/player_falchion_engines.png",
		"engines": [Vector2(-4, 5), Vector2(4, 5)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.25, 0.62, 0.97),
		"codex": "A broad-wing delta interceptor, the F/A-29 is an general purpose fighter with powerful engines and light armaments. It's fast and maneuvable, and despite it's minimal armaments, can mount just about any weapon needed in its enclosed weapon bays, exposing them to fire only when necessary.",
		# Privateer: tough shieldless hull, deep signature gun (dry minigun swaps to the
		# pooled Energy Blaster).
		"loadout": {
			"primary": ["_make_minigun", 3],
			"modules": [["_make_ablative_plating", 2], ["_make_repair_nanites", 1], ["_make_side_pods", 1]],
		},
	},
	{
		"id": "cobra",
		"scene": "res://scenes/player/player_cobra.tscn",
		"name": "CF/A-16D Cobra",
		"tag": "Workhorse fighter",
		"body": "res://graphics/player/player_cobra_body.png",
		"livery": "res://graphics/player/player_cobra_livery.png",
		"engine": "res://graphics/player/player_cobra_engines.png",
		"engines": [Vector2(-2, 7), Vector2(2, 7)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.98, 0.85, 0.25),
		"codex": "A workhorse fighter fielded by numerous miitaries across the stars. It is relatively sturdy, and its broad wings allow it to mount nearly any weapon system built. It comes fitted with a wing-mounted autocannon, ammo pods, and enough redundant plating to shrug off a rough patrol.",
		# Privateer: tough shieldless hull (dry autocannon swaps to the pooled Energy Blaster).
		"loadout": {
			"primary": ["_make_autocannon", 2],
			"modules": [["_make_reinforced_hull", 3], ["_make_repair_nanites", 1], ["_make_side_pods", 1]],
		},
	},
	{
		"id": "stiletto",
		"scene": "res://scenes/player/player_stiletto.tscn",
		"name": "X-1 Stiletto",
		"tag": "Captured Evantian Shiv",
		"body": "res://graphics/player/player_stiletto_body.png",
		"livery": "res://graphics/player/player_stiletto_livery.png",
		"engine": "res://graphics/player/player_stiletto_engines.png",
		"engines": [Vector2(-3, 6), Vector2(3, 6)],
		"muzzle": Vector2(0, -4),
		"livery_color": Color(0.20, 0.80, 0.65),
		"codex": "A captured Evantian Shiv stripped of its suicide rig and refitted for a pilot who intends to fly home. The reinforced hull has been retained, but removal of the firecore also required a complete overhaul of the engines, fitting a new reactor, and proper gun hardpoints. What it's lost in raw speed it makes up for in proper weaponry and general reliability. This one-of-a-kind ship is sturdy, dangerous, and an affront to the Theocracy that originally built it.",
		# Zealot: shieldless RAM hull — deep hull stack + Rush.
		"loadout": {
			"modules": [["_make_ablative_plating", 2], ["_make_reinforced_hull", 4]],
			"mode": "_make_rush_mode",
		},
	},
	{
		"id": "pilgrim",
		"scene": "res://scenes/player/player_pilgrim.tscn",
		"name": "X-2 Pilgrim",
		"tag": "Captured Evantian Pilgrim",
		"body": "res://graphics/player/player_pilgrim_body.png",
		"livery": "res://graphics/player/player_pilgrim_livery.png",
		"engine": "res://graphics/player/player_pilgrim_engines.png",
		"engines": [Vector2(-5, 4), Vector2(5, 4)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.96, 0.55, 0.13),
		"codex": "An Evantian Pilgrim taken whole, its firecore left burning rather than torn out — a calculated risk but the power is generates outstrips most reactors at the same size class. Slow and lightly armored, its plasma cannons have been replaced with dual blasters, and  spit fire as fast as the day it was consecrated. Salvage with a sermon still ringing in it.",
		# Zealot: shieldless overcharge glass cannon (Overcharge's −1 shield charge is moot).
		"loadout": {
			"blaster": ["_make_twin_blaster", 3],
			"modules": [["_make_system_delimiter", 1], ["_make_overcharge_core", 2]],
			"mode": "_make_refire_mode",
		},
	},
	{
		"id": "wraith",
		"scene": "res://scenes/player/player_wraith.tscn",
		"name": "CF-20 Wraith",
		"tag": "Retired Corpo Fighter",
		"body": "res://graphics/player/player_wraith_body.png",
		"livery": "res://graphics/player/player_wraith_livery.png",
		"engine": "res://graphics/player/player_wraith_engines.png",
		"engines": [Vector2(-4, 6), Vector2(4, 6)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.70, 0.38, 0.95),
		"codex": "The CF-20 used to be a mainline fighter used by corporate forces across the stars, but was retired in favor of the CF/A-21 Sentinel, a more maneuverable descendant. Still, the Wraith is a fast, reliable craft that kept order in corporate systems for decades. They can still be found in service all over the place, in the hands of mercenary and security companies, local militias, and bounty hunters.",
		# Corpo: fast-recharge half-shield + spread gun + Echo.
		"loadout": {
			"blaster": ["_make_spread_cannon", 1],
			"modules": [["_make_corpo_shield_core", 1]],
			"mode": "_make_echo_mode",
		},
	},
	{
		"id": "weaver",
		"scene": "res://scenes/player/player_weaver.tscn",
		"name": "CF/A-14 Weaver",
		"tag": "Captured Corpo Interceptor",
		"body": "res://graphics/player/player_weaver_body.png",
		"livery": "res://graphics/player/player_weaver_livery.png",
		"engine": "res://graphics/player/player_weaver_engines.png",
		"engines": [Vector2(0, 7)],
		"muzzle": Vector2(0, -2),
		"livery_color": Color(0.45, 0.85, 0.30),
		"codex": "The CF/A-14 is a split hull attack fighter made for speed and maneuverability. Built around stand-off munitions rather than a proper main cannon, it strikes targets from afar with missiles and torpedoes, carrying only a light blaster as a sidearm.",
		# Corpo: fast-recharge half-shield + pre-equipped missiles + Hyper (auto-fires them).
		"loadout": {
			"secondary": ["_make_seeking_missile", 1],
			"modules": [["_make_corpo_shield_core", 1]],
			"mode": "_make_hyper_mode",
		},
	},
	{
		"id": "mongoose",
		"scene": "res://scenes/player/player_mongoose.tscn",
		"name": "R-7 Mongoose",
		"tag": "Rebuilt Supremacy Racer",
		"body": "res://graphics/player/player_hotrod_body.png",
		"livery": "res://graphics/player/player_hotrod_livery.png",
		"engine": "res://graphics/player/player_hotrod_engines.png",
		"engines": [Vector2(0, 7)],
		"muzzle": Vector2(0, -7),
		"livery_color": Color(0.96, 0.40, 0.78),
		"codex": "A Crimson Supremacy Lash racing frame taken as a prize and rebuilt to hunt its siblings. The suicidal top speed remains; everything else was gutted for an overclocked reactor, a predictive targeting suite, and a heavy blaster that lands like a verdict. It doesn't dodge the strike so much as arrive before it — outriders who spot one break formation, because the Mongoose kills Lashes for sport.",
		# Supremacy speed + crit build (Roman 2026-07-11, rev 2 — replaced the "Duelist"):
		# Heavy Blaster punch, Overclock Core fire-rate ramp, Targeting Computer crits,
		# Thrusters speed, Focus for the aim. 116 + 186×3 = 674 ≈ par.
		"loadout": {
			"blaster": ["_make_heavy_blaster", 1],
			"modules": [["_make_overclock_core", 2], ["_make_targeting_computer", 2], ["_make_thrusters", 2]],
		},
	},
	{
		"id": "piercer",
		"scene": "res://scenes/player/player_piercer.tscn",
		"name": "SF-11 Piercer",
		"tag": "Captured Supremacy Interceptor",
		"body": "res://graphics/player/player_piercer_body.png",
		"livery": "res://graphics/player/player_piercer_livery.png",
		"engine": "res://graphics/player/player_piercer_engines.png",
		"engines": [Vector2(-6, 7), Vector2(6, 7), Vector2(0, 7)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.92, 0.92, 0.95),
		"codex": "A lean Crimson Supremacy interceptor flown home by a defector and pressed into free service. Built to punch a hole in a formation and be gone before it closes: twin blasters backed by tandem auto-lasers, a reinforced spar frame that shrugs off the collision it's aimed at, and engines that answer before you finish asking.",
		# Supremacy: the Stiletto's deep Reinforced Hull + dual blasters + dual lasers +
		# Rush (Roman 2026-07-11). 116 + 116 + 326 + 116 = 674 ≈ par.
		"loadout": {
			"blaster": ["_make_twin_blaster", 1],
			"primary": ["_make_laser_beam", 1],
			"modules": [["_make_reinforced_hull", 4]],
			"mode": "_make_rush_mode",
		},
	},
	{
		"id": "hive",
		"scene": "res://scenes/player/player_hive.tscn",
		"name": "CV-1 Hive",
		"tag": "Drone Carrier",
		"body": "res://graphics/player/player_hive_body.png",
		"livery": "res://graphics/player/player_hive_livery.png",
		"engine": "res://graphics/player/player_hive_engines.png",
		"engines": [Vector2(-4, 7), Vector2(4, 7)],
		"muzzle": Vector2(0, -8),
		"livery_color": Color(0.80, 0.68, 0.22),
		"codex": "Nobody builds a Hive — one accretes. A salvaged carrier frame grown over with drone bays, fabricator racks, and nanite plumbing until the original hull is a rumor. It doesn't outfly anything and it doesn't need to: combat drones sortie from its bays, interceptors swat down whatever gets close, and everything the fight takes from it grows back. Patient, self-sufficient, and very hard to make dead.",
		# PRESTIGE hull (unlock: 30 boss kills, any). Purely defensive drone fortress —
		# deliberately ABOVE the ~659 kit par (≈976 effective): the 30-boss gate is the
		# price. Corpo core (fast recharge = the sustain loop) + the drone screen +
		# regen economy; Thief mode turns enemy fire into shield.
		"loadout": {
			"secondary": ["_make_drone_swarm", 1],
			"modules": [["_make_corpo_shield_core", 1], ["_make_intercept_drones", 1], ["_make_micro_fabricator", 1], ["_make_repair_nanites", 1]],
			"mode": "_make_thief_mode",
		},
	},
]


# Number of selectable ships.
static func count() -> int:
	return SHIPS.size()


# Ship entry for a variant index (clamped to the known set).
static func get_ship(idx: int) -> Dictionary:
	return SHIPS[clampi(idx, 0, SHIPS.size() - 1)]


# Combat player-scene path for a variant index (clamped).
static func scene_path(idx: int) -> String:
	return String(SHIPS[clampi(idx, 0, SHIPS.size() - 1)]["scene"])


# Display name for a variant index (clamped).
static func display_name(idx: int) -> String:
	return String(SHIPS[clampi(idx, 0, SHIPS.size() - 1)]["name"])


# Derived starting-kit display lines — the REAL in-game part labels + marks
# ("Mk.N Name", Part.get_display()), built from `loadout` with the same PartCatalog
# factories Run seeds from, so the patrol-start panel + codex can never drift from the
# actual kit (retired the hand-written armament/modules strings, 2026-07-11). Returns
# {"armament", "modules", "mode"}. PartCatalog is load()ed lazily so this strings file
# stays preload-light for consumers that never call this (loading screen, cinematics).
static func loadout_display(idx: int) -> Dictionary:
	var PartCatalog = load("res://scripts/parts/part_catalog.gd")
	var kit_v = get_ship(idx).get("loadout", {})
	var kit: Dictionary = kit_v if kit_v is Dictionary else {}
	var arms: Array = []
	# Signature metered primary first (it starts ACTIVE), then the pooled blaster.
	if kit.has("primary"):
		arms.append(_kit_part_label(PartCatalog, kit.get("primary")))
	arms.append(_kit_part_label(PartCatalog, kit.get("blaster") if kit.has("blaster") else "_make_basic_blaster"))
	if kit.has("secondary"):
		arms.append(_kit_part_label(PartCatalog, kit.get("secondary")))
	var mods: Array = []
	for spec in kit.get("modules", [["_make_shield_core", 1]]):
		mods.append(_kit_part_label(PartCatalog, spec))
	var mode: String = _kit_part_label(PartCatalog, kit.get("mode") if kit.has("mode") else "_make_focus_mode")
	return {
		"armament": ", ".join(PackedStringArray(arms)),
		"modules": ", ".join(PackedStringArray(mods)),
		"mode": mode,
	}


# One kit spec ("factory" or [factory, mk]) → its in-game "Mk.N Name" label.
static func _kit_part_label(PartCatalog, spec) -> String:
	var factory := ""
	var mk := 1
	if spec is String:
		factory = spec
	elif spec is Array and spec.size() >= 1:
		factory = String(spec[0])
		if spec.size() >= 2:
			mk = int(spec[1])
	var part = PartCatalog.make_part(factory, mk)
	return String(part.get_display()) if part != null else "?"
