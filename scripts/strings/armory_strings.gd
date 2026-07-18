extends Object

# Armory codex strings — display blurbs for player items, keyed by PartCatalog
# factory-name. The display NAME comes from the part itself (part.display_name);
# this file holds the codex BLURB (the genuinely-missing content). Mirror of the
# codex_strings.gd convention: extends Object, preload-referenced (NOT class_name —
# headless class-cache safety), const dict + static helper with a safe fallback.
#
# Authoritative-vs-mirror call (docs/armory_string_expansion_2026-06-08.md):
# MIRROR for the first pass — names stay inline on the parts (load-bearing for the
# shop/HUD + the .tres copy-back); the Armory reads the name off the part and the
# blurb from here. Passive-module blurbs slot in here when that layer is built.

const CODEX := {
	# --- Primary cannons (CANNON) ---
	"_make_basic_blaster": "Standard-issue energy cannon, a reliable weapon with its own micro-reactor so that it doesn't need to ship's energy to fire. Upgrading this weapon improves its damage output.",
	"_make_heavy_blaster": "Slow-firing, heavy energy cannon that can vaporize most enemies in one shot. Slow firing initially, upgrading this weapon improves the micro-reactor and speeds up rate of fire.",
	"_make_autocannon": "A mid-caliber kinetic cannon that fires devastating explosive shots out of an array of spinning barrels. It needs a moment to spin-up, and has limited ammo, but upgrading this weapon will improve ammo storage designs to give you more firing time.",
	"_make_minigun": "A small-calliber electric ignition minigun firing light armor-piercing rounds. What the weapon lacks in damage it makes up for in sheer rate of fire, burning through its ammo stocks rapidly, it allowed. Upgrading this weapond improves the ammo storage solution, buying you a bit more uptime in battle.",
	"_make_rotary_laser": "A high-speed laser cannon utilizing rotating microcapacitors to create a relentless stream of energy bolts. Its battery is tied to the ship's reactor, so it never truly runs out of ammo, but it does require recharging when the battery is expended. Upgrades improve energy storage, providing more shots before needing to recharge.",
	"_make_wave_gun": "This plasma wave gun fires a wide blade of plasma in a magnetized cooridor. The shots can roll over enemies, overloading systems, burning out shields, and scorching sensitive electronics. Upgrades improve rate of fire, damage, and eventually, the width of the plasma wave.",
	"_make_laser_beam": "A tandem laser cannon mount tied into the ship's reactor. These alternating cannons fire quickly, releasing fast, accurate bolts of energy. Upgrades improve the cannon's battery, and damage.",
	"_make_spread_cannon": "A split-port cannon meant to scatter shots of energy in an arc, rather than directing them at a single target. Upgrading this weapon just adds more barrels, widening the arc and increasing the shots fired. The whole system has its own micro-reactor so it can fire forever if needed.",
	# --- Secondaries (HARDPOINT_WING) ---
	"_make_rocket_pod": "Dumb-fire rocket pods unleash volleys of fast, destructive ordnance on demand. Upgrading this weapon increases the number of rockets fired at once.",
	"_make_seeking_missile": "These seeker missiles track the nearest enemy and run it down, detonating once it gets close. They work best on distant targets which the missiles can lock onto from afar.",
	"_make_anti_ship_missile": "This heavy seeker missiles automatically goes after the largest target it can find, delivering a devastating blow what will destroy all but the most resilient hulls in a single shot.",
	"_make_swarm_launcher": "Releases a salvo of homing micro-missiles that fan out and look for targets, detonating on contact. Upgrading this weapon increases the size of each salvo.",
	"_make_particle_beam": "A continuous particle lance that shreds anything in its path. Upgrading this weapon increases the emitter lense to increase the size of the beam.",
	"_make_side_pods": "A logistics module that boosts your primary and secondary ammo capacity with specialized internal containers and some space-saving adjustments to your ship's systems.",
	"_make_intercept_drones": "Spinning ablative drones orbit your ship and soak incoming bullets. They last until destroyed, but an internal fabricator will replace them ahead of your next combat mission, so they are always available.",
	"_make_drone_swarm": "Release a small grouping of autonomous combat drones that fire their blaster shots at any enemies nearby.",
	# --- Super (DEVICE_BAY_1) ---
	"_make_smart_bomb": "This pulse bomb releases a massive wave of energy that ignores shields, disrupts incoming energy shots, detonates explosives, and causes the reactors of lighter crafte to immediately rupture. When used it will clear the immediate area, and an auto-fire switch allows it to detonate ahead of any impact which would destroy the ship. Limited charges and expensive restock make this useful if limited tool.",
	# --- Shift modes (SHIFT_MODE) ---
	"_make_focus_mode": "Sharpens your aim, providing a chance for each shot to be a critical shot that does double damage.",
	"_make_phase_shift": "Provides a short intangible blink that lets you pass through bullets and ships without harm, but prevents shooting. Charges refill by killing enemies.",
	"_make_hyper_mode": "Full-auto overdrive, fire every weapon you have automatically with no ammo cost for a few seconds. Charges refill over time.",
	"_make_rush_mode": "Overcharge your movement for a brief period, and gain total impact immunity while you do. Charges refill over time.",
	"_make_refire_mode": "Overclock your weapons briefly, gaining a burst of bonus fire rate. Take care, you still spend ammo! Charges refill over time.",
	"_make_echo_mode": "Split off a ghost that mirrors your movement a beat behind and fires your primary weapon with you. Charges refill over time.",
	"_make_thief_mode": "Project a catch-field that absorbs enemy bullets and converts them to shield. Charges refill over time.",
	"_make_reflect_mode": "For a brief period you angle your shields so that incoming shots have a chance to ricochet back at the enemy. Charges refill over time.",
	# --- Engines (ENGINE) ---
	"_make_basic_engine": "Main Engine — your baseline thrust. Mk raises top speed toward the clarity ceiling.",
	"_make_vectoring_engine": "Vectoring thrusters — crisper handling and a higher speed band.",
	# --- Passive Modules (MODULE bay — automatic, no-input) ---
	"_make_shield_core": "an old, rare, and powerful shield core built by the Free Systems military before the stars were carved up, providing unmatched protection for its form factor. Its dense particle lattice surrounds your ship in a sphere of energy that can shrug off anything thrown at it, collapsing only when its charges are spent and recharging after a delay. They really aren't built like this any more. Upgrading this module adds additional shield charges.",
	"_make_corpo_shield_core": "a mass-produced Ultra Galactic shield design meant to charge quickly, without the particle density or charge capacity of a vintage Free Systems core. It holds half the charges, but snaps back online sooner and refills faster after taking fire. Upgrading this module adds additional shield charges.",
	"_make_overcharge_core": "Shunt shield energy into weapon drivers — your primary weapon hits harder at the cost of weaker shields.",
	"_make_siphon_core": "A combination of energy siphons and particle catchers on your hull allow you to capture energy from enemy kills, siphoning that energy into your shields bit by bit. The net effect is that every few kills gets you a shield charge back. Upgrades improve the kills to charges rate.",
	"_make_repair_nanites": "Regrows hull over time.",
	"_make_ablative_plating": "Layered plates shrug off every Nth hull hit outright.",
	"_make_targeting_computer": "Primary fire gains a crit chance for double damage.",
	"_make_overclock_core": "Hold the trigger and your fire-rate increases. Resets if you stop firing.",
	"_make_system_delimiter": "Strips the safety governors and shuts emergency systems to weapons. As your hull falls, fire-rate and damage improve.",
	"_make_reinforced_hull": "Bolts extra plating onto the hull, improving your ability to take hits.",
	"_make_thrusters": "Auxiliary thrusters stacked on your engine improve your maneuverability in all directions.",
	"_make_shield_capacitor": "This support capacitor stores excess reactor energy for shield recharging, reducing the delay before your shield starts refilling, and improving the rate that it does.",
	"_make_backup_shield_capacitor": "An emergency cell that fires the first time your shield drops, instantly dumping energy into your shields.",
	"_make_reflective_shield": "Tunes the shield to bounce back every Nth bullet that hits it at the nearest enemy.",
	"_make_micro_fabricator": "An onboard printer that runs between fights, restoring a portion of your expended ammunition.",
	"_make_energy_routers": "Reroutes power the moment you stop firing: while the trigger's idle, your shield's regen delay shortens and its charge-ticks come faster.",
	"_make_blaster_smart_mount": "Slaves your Blaster to a tracking turret: it auto-fires at the nearest enemy in a 120° front arc while you fly. Upgrades make the weapon more accurate and faster to track targets.",
	"_make_primary_smart_mount": "Slaves your Primary to a tracking turret: it auto-fires at the nearest enemy in a 120° front arc while you fly. Upgrades make the weapon more accurate and faster to track targets.",
}


static func codex_for(factory: String) -> String:
	return String(CODEX.get(factory, ""))
