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
	"_make_basic_blaster": "Standard-issue energy repeater. Infinite ammo and a dependable cadence — the permanent spine of every loadout.",
	"_make_heavy_blaster": "Slow, heavy energy slugs that hit hard per shot. The cadence quickens at high Mk for a punishing top-tier rhythm.",
	"_make_machinegun": "A high-rate kinetic stream. Metered ammo, devastating uptime — hold the trigger down and keep the lane swept.",
	"_make_rotary_laser": "A spun-up laser repeater: a brief charge, then a relentless cascade of bolts.",
	"_make_wave_gun": "Fires a widening energy wave that pierces chaff. Mk broadens it into a screen-spanning sweep.",
	"_make_laser_beam": "Auto Laser — alternating twin energy bolts from the nose. Steady, no-ammo precision fire.",
	"_make_spread_cannon": "Fans a volley of bolts across an arc. Mk adds bolts — point-blank crowd control.",
	# --- Secondaries (HARDPOINT_WING) ---
	"_make_rocket_pod": "Dumb-fire rockets from the wing ports — straight-line ordnance, alternating tubes, in timed bursts.",
	"_make_seeking_missile": "Tracks the nearest enemy and runs it down. Slow cadence, heavy payload.",
	"_make_anti_ship_missile": "A heavy seeker that prefers the LARGEST target on screen. Half the ammo, an enormous hit.",
	"_make_swarm_launcher": "Releases a salvo of homing micro-missiles that fan out to distinct targets and detonate on contact. Mk adds two missiles per level.",
	"_make_particle_beam": "A continuous particle lance that shreds chaff and stalls against tough hulls. Width grows with Mk.",
	"_make_side_pods": "Ammo Pods — extra forward muzzles that fire alongside your primary. Mk adds pods.",
	"_make_drone_bits": "Intercept Drones — ablative companion drones that orbit and soak incoming bullets for you.",
	"_make_drone_swarm": "Combat Drones — deploys a timed wing of autonomous drones that fire on bosses first, then the nearest threat.",
	# --- Super (DEVICE_BAY_1) ---
	"_make_smart_bomb": "The panic button. A shockwave that ignores shields and clears the screen of chaff and ordnance; auto-fires to save you from a lethal hit. Charges are bought at outposts — the only super.",
	# --- Shift modes (SHIFT_MODE) ---
	"_make_focus_mode": "FOCUS stance (hold Shift). Slows you to a precise crawl with a pinpoint hitbox for threading dense fire. The default stance.",
	"_make_phase_shift": "PHASE stance (tap Shift). A short intangible blink — pass through bullets and ships, no offense, no screen-clear. Charges refill by killing enemies.",
	"_make_hyper_mode": "HYPER stance (hold Shift). Overdrive: +10% fire rate and unlimited ammo while the bar holds. Recharges only when idle — can't re-engage until full.",
	# --- Engines (ENGINE) ---
	"_make_basic_engine": "Main Engine — your baseline thrust. Mk raises top speed toward the clarity ceiling.",
	"_make_vectoring_engine": "Vectoring thrusters — crisper handling and a higher speed band.",
}


static func codex_for(factory: String) -> String:
	return String(CODEX.get(factory, ""))
