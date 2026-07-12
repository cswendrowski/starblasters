extends Object

# Canonical player-ship roster — the SINGLE source of truth for the ship picker, the
# outpost/patrol cinematics, the loading screen, the codex "Ships" category, and the dev
# labs. Index = Run.ship_variant (0 = the default Starblaster; 1/2 were the old "ship B / C"
# alternate hulls, now the Falchion / Cobra — kept at those indices for save compatibility).
#
# Each entry carries everything those consumers need so the 7-ship table lives in ONE place
# instead of being copy-pasted per screen:
#   scene .......... combat player scene (instantiated at run start)
#   name / tag ..... display name + one-line picker subtitle
#   body/livery/engine .. the 3-frame sprite sheets (frame 1 = neutral pose) for cinematic
#                         compositing + picker previews
#   engines ........ nozzle marker offsets (1 or 2) for engine glow / trail / spark placement
#   livery_color ... signature default hull tint (the picker still lets the player override)
#   codex .......... fleet-codex flavor blurb ([REVIEW] = AI first-pass draft, pending Roman)
#   armament/modules .. starting-loadout flavor shown in the codex + patrol-start panel
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
		"armament": "Blaster Cannon",
		"modules": "Shield Core",
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
		"armament": "Minigun",
		"modules": "Shield Core",
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
		"codex": "A workhorse fighter fielded by numerous miitaries across the stars. It is relatively sturdy, and its broad wings allow it to mount nearly any weapon system built. It comes with a pair of wing-mounted auto-lasers with supplementary capacitors.",
		"armament": "Auto Laser",
		"modules": "Shield Core, Ammo Pods",
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
		"armament": "Blaster",
		"modules": "Ablative Plating, Reinforced Hull",
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
		"armament": "Dual Blaster",
		"modules": "Critical System De-Limiter, Overcharge Core",
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
		"armament": "Blaster",
		"modules": "Shield Core",
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
		"codex": "The CF/A-14 is a split hull attack fighter made for speed and maneuverability. It lacks a main cannon and relies on stand-off munitions such as missiles and torpedoes to strike targets from afar.",
		"armament": "Seeker Missiles",
		"modules": "Shield Core, Micro Fabricator",
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
