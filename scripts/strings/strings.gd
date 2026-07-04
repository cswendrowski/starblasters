class_name Strings
extends Object

# Central strings file — all user-visible text in one place.
# Static constants only; no instances needed.
# Format strings (containing %d / %s) stay as format strings — callers use
# Strings.FOO % value  or  Strings.FOO % [a, b].
#
# Sections:
#   ONBOARDING   — tutorial pages, buttons, icon labels
#   EVENTS       — signal event titles, bodies, choice labels, outcome messages
#   OUTPOST      — upgrade names/descs, service labels, toasts, UI chrome


# ===========================================================================
# ONBOARDING
# ===========================================================================

# Page titles and bodies.
const ONBOARDING_CONTROLS_TITLE := "Controls"
const ONBOARDING_CONTROLS_BODY := "Arrow Keys — move.\nSpace / Z — fire blaster or primary cannon.\nC — fire secondary hardpoint weapon.\nX — Super Pulse Bomb.\nShift — activate Shift Mode (If Available): each grants different benefits.\nG — swap between blaster and primary cannon (if you own more than one).\nA — Toggle AutoFire for blaster or primary cannon.\nS — Toggle Smart Mode for selected Blaster/Cannon (if available).\nEsc — pause."

const ONBOARDING_PARTS_TITLE := "Parts & Marks"
const ONBOARDING_PARTS_BODY := "Your ship can be upgraded with new parts during patrols. Visit the Outpost to buy them, or seek out Unknown Signal events and see what you find.\n\nEvery part has a Mark level from Mk.1 to Mk.9. A higher Mark is always better, providing more damage, more durability, better stats, etc.\n\nAside from spending Bounty and scavenging them, you can upgrade existing equipped party by spending Bounty and Materials at the Outpost. You can gain materials from Signal Events and from breaking down owned equipment."

const ONBOARDING_SHIELDS_TITLE := "Shields & Hull"
const ONBOARDING_SHIELDS_BODY := "Your ship has two layers of integrity.\n\nThe SHIELD absorbs incoming fire. When it runs out, your HULL becomes vulnerable.\n\nAt start you can sustain two hits before you're put into a danger state, if you take another hit while in this danger state you die and your patrol ends. You can repair our hull at outposts, or through some modules."

const ONBOARDING_SHIELD_REGEN_TITLE := "Shield Regen"
const ONBOARDING_SHIELD_REGEN_BODY := "Shields regenerate automatically a few seconds after the last hit, and will recharge themselves to full if given time. Taking damage while the shield is regenerating will halt the process and reset the timer.\n\nUpgrades can increase the capacity and recharge rate, and reduce the recharge delay."

const ONBOARDING_BOUNTY_TITLE := "Bounty Economy"
const ONBOARDING_BOUNTY_BODY := "Defeat enemies to earn Bounty Credits — your in-patrol currency.\n\nVisit the Outpost to spend Bounty on parts, weapons, repairs, and ammo. As you progress deeper into the patrol, Outpost prices increase — but the quality of available gear gets better too.\n\nBounty doesn't carry over — each patrol starts fresh, so spend it while you're out there."

const ONBOARDING_WAVES_TITLE := "Waves"
const ONBOARDING_WAVES_BODY := "Combat levels are split into waves. A banner pops at the start of each: WAVE 1 / 7, WAVE 2 / 7, and so on.\n\nMid-level, the wave count tells you how close you are to clearing. The last two waves of every level are the toughest — keep something in reserve."

const ONBOARDING_SECTOR_MAP_TITLE := "Sector Map"
const ONBOARDING_SECTOR_MAP_BODY := "Your patrol covers a single sector space. Each sector has three star systems, each with missions you can tackle in any order.\n\nClear all nodes in a system to unlock that system's Boss. Defeat the Boss to finish the system patrol. Clear all three systems to complete your patrol.\n\nBetween missions, visit Outposts to buy upgrades, adjust your loadout and restock and make repairs."

const ONBOARDING_NODE_TYPES_TITLE := "Location Types"
const ONBOARDING_NODE_TYPES_BODY := "Combat — defeat waves of enemies to earn Bounty.\nSignal — mysterious contact; a random event that offers rewards or risks.\nHazard — navigate through dangerous fields (mines or asteroids). Destructible but hazardous.\nBoss — the sector's commander. Defeat it to clear the system, reset the outpost stock and advance toward sector completion."

const ONBOARDING_MISSION_TITLE := "Mission Briefing"
const ONBOARDING_MISSION_BODY := "Your mission is to patrol three systems, hunting down slavers, marauders, cultists, and mercenaries preying on the local inhabitants. Each enemy you dust is worth bounty, and each bounty will help you gear up for the next fight. Search the systems, tally up kills, and eventually you'll learn where the worst of them are. Eliminate them, for the good of the galaxy and your accounts.\n\nGood luck, Starblaster!"

# Navigation buttons.
const ONBOARDING_BTN_BACK := "Back"
const ONBOARDING_BTN_NEXT := "Next"
const ONBOARDING_BTN_SKIP := "Skip Tutorial"
const ONBOARDING_BTN_BEGIN := "Begin Patrol"

# Sector-map page icon labels.
const ONBOARDING_ICON_COMBAT := "Combat"
const ONBOARDING_ICON_OUTPOST := "Outpost"
const ONBOARDING_ICON_SIGNAL := "Signal"
const ONBOARDING_ICON_HAZARD := "Hazard"
const ONBOARDING_ICON_BOSS := "Boss"


# ===========================================================================
# EVENTS  (signal_event.gd)
# ===========================================================================

# ---- Event titles and bodies ----

const EVENT_AMBUSH_TITLE := "Ambush!"
const EVENT_AMBUSH_BODY := "Warning lights flare in your periphery: active scan warnings. Sensors pick them up a second later — multiple incoming signatures closing from behind!"

const EVENT_NANO_CLOUD_TITLE := "Drifting Nano Cloud"
const EVENT_NANO_CLOUD_BODY := "Sensors indicate micro-energy signatures. You squint, and can see a glittering cloud moving like a swarm of bugs. A nano cloud?"

const EVENT_JUNK_TRADER_TITLE := "Junk Trader"
const EVENT_JUNK_TRADER_BODY := "A battered trade barge idles alongside, cargo nets bulging with stripped salvage. The merchant deals in upgrade materials — buying, selling, and slinging cut-rate ammo to anyone with bounty to spend."

const EVENT_MINER_TITLE := "Freespace Miner"
const EVENT_MINER_BODY := "Your comms light up as a wandering mining ship calls for your attention: they've found high-value minerals, but the asteroids are too tough for their mining lasers. Proper fighter weapons would crack them."

const EVENT_WRECK_TITLE := "Wrecked Starfighter"
const EVENT_WRECK_BODY := "A burnt-out fighter tumbles end over end through the void, hull cracked and lockers spilling debris. Worth a closer look."

const EVENT_SALVAGE_TITLE := "Salvage Cache"
const EVENT_SALVAGE_BODY := "Sensors flag a battered container tumbling through the dust — military markings, locks half-melted. Worth cracking open."

const EVENT_DERELICT_TITLE := "Derelict Warship"
const EVENT_DERELICT_BODY := "A gutted corporate cruiser hangs in the void, its guts strewn out behind it in a long trail. You pull in but threat detection goes live immediate: auto-defense is still hot. You see a corp crate in the debris, could be something good, might be worth the risk."

const EVENT_INSPECTION_TITLE := "Corporate Inspection"
const EVENT_INSPECTION_BODY := "A corporate frigate flanked by a wing of interceptors catches up to you, threat detection going wild. A voice demands you cut engines and prepare for inspection. You know you're clean, but they will find something. They always do."

const EVENT_EXPERIMENTAL_TITLE := "Experimental Tech"
const EVENT_EXPERIMENTAL_BODY := "Passing by, you find an abandoned corp hardware station with one bay still active. The ident system reads you as an employee vessel. The metadata is corrupted so you have no idea how effective it is, but corp nano-hives are akin to magic."

const EVENT_BOUNTY_BOARD_TITLE := "Bounty Board Alert"
const EVENT_BOUNTY_BOARD_BODY := "You get an alert on the bounty-net: new priority targets available if you decide to opt-in. The metadata looks iffy, but you know these can be lucrative."

# Fallback title when no event loaded.
const EVENT_UNKNOWN_TITLE := "Unknown Signal"

# ---- Choice labels ----

const CHOICE_AMBUSH_FIGHT := "Fight through (combat)"
const CHOICE_AMBUSH_EVADE := "Evasive maneuvers (risky)"

const CHOICE_NANO_FLY := "Fly into it (risk/reward)"
const CHOICE_NANO_AVOID := "Avoid it"

const CHOICE_JUNK_SELL := "Sell a part (+bounty)"
const CHOICE_JUNK_TRADE := "Trade a part (random outcome)"
const CHOICE_JUNK_REPAIR := "Repair hull (-30 bounty, +3 hull)"
const CHOICE_JUNK_AMMO := "Buy ammo (-15 bounty, +500 rounds)"
const CHOICE_JUNK_LEAVE := "Leave"
# Materials-merchant choices (Roman 2026-06-14).
const CHOICE_JUNK_BUY_MATS := "Buy materials (5 for 200 bounty)"
const CHOICE_JUNK_SELL_MATS := "Sell materials (5 for 75 bounty)"

const CHOICE_MINER_AGREE := "Agree (asteroid run, +bounty per rock)"
const CHOICE_MINER_REFUSE := "Refuse"

const CHOICE_WRECK_BOUNTY := "Claim bounty"
const CHOICE_WRECK_WEAPON := "Scavenge weapon"
const CHOICE_WRECK_UPGRADE := "Scavenge upgrade"
const CHOICE_WRECK_AMMO := "Scavenge ammo (+25% of max)"
const CHOICE_WRECK_LEAVE := "Leave it be"

const CHOICE_SALVAGE_SALVAGE := "Salvage the cache (random reward)"
const CHOICE_SALVAGE_LEAVE := "Leave it adrift"

const CHOICE_DERELICT_RISK := "Risk It"
const CHOICE_DERELICT_IFF := "Buy spoofed IFF codes (-%d bounty)"
const CHOICE_DERELICT_TAG := "Tag it for bounty"

const CHOICE_INSPECTION_COMPLY := "Comply"
const CHOICE_INSPECTION_RUN := "Run"
const CHOICE_INSPECTION_FIGHT := "Fight"

const CHOICE_EXPERIMENTAL_CHANCE := "Take the Chance"
const CHOICE_EXPERIMENTAL_TAG := "Tag it"
const CHOICE_EXPERIMENTAL_DESTROY := "Destroy it"

const CHOICE_BOUNTY_BOARD_OPTIN := "Opt-in"
const CHOICE_BOUNTY_BOARD_OPTOUT := "Opt-out"

# ---- Outcome messages ----
# Format strings: use  Strings.FOO % value  at call site.

const OUTCOME_AMBUSH_EVADE_CLEAN := "Evaded — escaped cleanly!"
const OUTCOME_AMBUSH_EVADE_HIT := "Evaded — hull grazed! -1 hull"

const OUTCOME_NANO_AVOID := "Course corrected. No effect."
const OUTCOME_NANO_DAMAGE := "Hostile nanites! -%d hull"
const OUTCOME_NANO_REPAIR := "Repair nanites. +%d hull"
const OUTCOME_NANO_UPGRADE := "Beneficial swarm! Upgraded %s"
const OUTCOME_NANO_UPGRADE_MAXED := "Beneficial swarm — but nothing upgradable!"
const OUTCOME_NANO_AMMO := "Nanites manufactured ammo! +%d rounds"

const OUTCOME_JUNK_NO_CARGO_SELL := "No spare parts in cargo to sell."
const OUTCOME_JUNK_SOLD := "Sold %s for %d bounty"
const OUTCOME_JUNK_NO_CARGO_TRADE := "No spare parts in cargo to trade."
const OUTCOME_JUNK_TRADED := "Traded %s → %s (Mk %s)"
const OUTCOME_JUNK_NO_SLOT := "Trader has nothing for that slot."
const OUTCOME_JUNK_REPAIR_BROKE := "Not enough bounty (need 30)."
const OUTCOME_JUNK_REPAIRED := "Patched up. -30 bounty, +3 hull"
const OUTCOME_JUNK_NO_RUN := "Comms dropped."
const OUTCOME_JUNK_BOUGHT_MATS := "Crates of salvage swapped over: -%d bounty, +%d materials."
const OUTCOME_JUNK_BUY_BROKE := "Not enough bounty (need %d)."
const OUTCOME_JUNK_SOLD_MATS := "Offloaded %d materials for a modest +%d bounty."
const OUTCOME_JUNK_NO_MATS := "You need at least %d materials to deal."
const OUTCOME_JUNK_NO_AMMO_WEAPON := "No ammo-fed weapon to refill."
const OUTCOME_JUNK_AMMO_BROKE := "Not enough bounty (need %d)."
const OUTCOME_JUNK_AMMO_LOADED := "Crates loaded. -%d bounty, +%d rounds"
const OUTCOME_JUNK_LEAVE := "You break orbit — the hauler drifts on."

const OUTCOME_MINER_REFUSE := "Channel closed."

const OUTCOME_WRECK_BOUNTY_FALLBACK := "Bounty tagged. +10 bounty"
const OUTCOME_WRECK_BOUNTY := "Bounty tagged. +%d bounty"
const OUTCOME_WRECK_AMMO := "Ammo crates salvaged: "
const OUTCOME_WRECK_AMMO_FULL := "Lockers already topped up."
const OUTCOME_WRECK_LEAVE := "You give the wreck a wide berth."
const OUTCOME_WRECK_NO_RUN := "Comms dropped."

const OUTCOME_SALVAGE_LEAVE := "You pass on the cache."
const OUTCOME_SALVAGE_NO_RUN := "Cache empty."
const OUTCOME_SALVAGE_UPGRADE := "Salvaged tech upgrade! %s → Mk %d"
const OUTCOME_SALVAGE_NO_WEAPONS := "Cache held no compatible weapons."
const OUTCOME_SALVAGE_AMMO_INERT := "Cache held only inert ammo crates."
const OUTCOME_SALVAGE_AMMO := "Ammo refilled! "

const OUTCOME_DERELICT_RISK_GOOD := "You scoop the crate, weaving through energy bolts and dodging rockets like a pro. Once clear, you crack it open and find %s."
const OUTCOME_DERELICT_RISK_BAD := "You scoop the crate, but not without some unnecessary roughness. As you fly away a hull damage indicator flashes. Once clear, you crack it open and find %s."
const OUTCOME_DERELICT_IFF := "You transmit the black market IFF and watch the auto-defenses stand down. You only need a second to grab the crate. Once clear, you crack it open and find %s."
const OUTCOME_DERELICT_TAG := "You tag the location on the Scavenger net. Within seconds a bounty payment comes through. As you fly off you wonder what was inside, but your curiosity isn't worth risking a hull breach."

const OUTCOME_INSPECTION_COMPLY := "You cut engines and let them scan you. Naturally they find something — an unlicensed firmware key, apparently — and issue a fine. You pay %d bounty and they let you go."
const OUTCOME_INSPECTION_RUN_DAMAGE := "You outrun them, but not before interceptor missiles scar your hull."
const OUTCOME_INSPECTION_RUN_ESCAPE := "Full burn, tight jink, and they lose you in the debris field. Clean escape."

const OUTCOME_EXPERIMENTAL_UPGRADE := "You decide to see what the nano-hive can do. The station hums to life and gets to work. Upgraded %s."
const OUTCOME_EXPERIMENTAL_DOWNGRADE := "You decide to see what the nano-hive can do. The station hums to life... and gets to work on the wrong thing. Downgraded %s."
const OUTCOME_EXPERIMENTAL_TAG := "You put the station location on the scavenger net. Payment comes through quickly — someone will make good use of it."
const OUTCOME_EXPERIMENTAL_DESTROY := "You light up the station with everything you have. It's gone in seconds. Felt great."

const OUTCOME_BOUNTY_BOARD_OPTIN := "A slaver worm uploads your coords and tags you for capture. On the bright side, you're now opted in to priority bounties on %s. You just need to survive long enough to collect."
const OUTCOME_BOUNTY_BOARD_OPTOUT := "You don't trust the metadata and pass. Not worth the risk."

# Ammo-line fragments (joined with ", ").
const AMMO_FRAGMENT_MG := "MG +%d rounds"
const AMMO_FRAGMENT_SECONDARY := "Secondary +%d"
const AMMO_FRAGMENT_SECONDARY_FULL := "Secondary full (%d)"

# Part-label helpers.
const PART_LABEL_FORMAT := "Mk.%d %s"
const PART_LABEL_UNKNOWN := "unknown part"
const PART_SLOT_NAME_PRIMARY := "Primary"
const PART_SLOT_NAME_SECONDARY := "Secondary"
const PART_SLOT_EMPTY := "(empty)"

# Weapon-swap modal (in _offer_weapon_swap).
const EVENT_SWAP_BODY := "SALVAGED: %s.\nSwap your current %s (%s)?"
const EVENT_SWAP_BTN := "Swap → %s"
const EVENT_SWAP_KEEP := "Keep current — stow %s"
const OUTCOME_SWAP_EQUIPPED := "Equipped %s as %s."
const OUTCOME_SWAP_STOWED := "Stowed %s in cargo."

# Continue button after any event resolves.
const BTN_SECTOR_MAP := "Sector Map"

# Combat/hazard launch confirmation — events never drop silently into combat. The
# resolve panel shows the event's flavor (or COMBAT_FLAVOR_DEFAULT) + a launch
# button. Phase A of the signal-event redesign (docs/signal_event_redesign_2026-06-08.md).
const BTN_ENGAGE := "Engage"
const BTN_ENTER_FIELD := "Enter the Field"
const COMBAT_FLAVOR_DEFAULT := "Hostiles inbound — weapons hot."
const COMBAT_FLAVOR_AMBUSH := "Raiders drop out of the dark with weapons already charged. No talking your way out of this one."
const COMBAT_FLAVOR_INSPECTION_RUN := "You slam the throttle. The inspectors don't take kindly to runners — an interceptor peels off to chase you down."
const COMBAT_FLAVOR_INSPECTION_FIGHT := "You charge weapons instead of complying. The inspection cutter answers in kind."
const HAZARD_FLAVOR_MINER := "You throw in with the mining crew. Time to earn your cut working the asteroid field."

# Salvaged weapon stowed to cargo (stow-only handoff — equip later at your ship).
const OUTCOME_SALVAGE_STOWED := "Salvaged %s — stowed in your cargo hold. Equip it at your ship."
# Phase B: the acquired-item card names the part, so the result line stays generic.
const OUTCOME_SALVAGE_STOWED_GENERIC := "You pry a working weapon free and stow it in your cargo hold."
const OUTCOME_SALVAGE_MATERIALS := "The cache is packed with raw salvage — you strip %d units of upgrade materials."

# Stance Module Cache (signal event) — the find-a-Shift-mode-module beat.
const EVENT_STANCE_TITLE := "Drifting Module Pod"
const EVENT_STANCE_BODY := "A maneuvering-systems pod tumbles in the wreckage, cradle still warm — a stance module, intact and salvageable."
const CHOICE_STANCE_SALVAGE := "Pry the module loose"
const CHOICE_STANCE_LEAVE := "Leave it tumbling"
const OUTCOME_STANCE_STOWED := "Salvaged a %s module — stowed in your cargo hold. Equip it at your ship."
const OUTCOME_STANCE_LEAVE := "You let the pod drift on into the dark."
const OUTCOME_STANCE_NO_RUN := "The pod's cradle is empty."

# Acquired-item card (Phase B resolver — shown whenever an event grants a part).
const CARD_ACQUIRED := "Acquired: %s"
const CARD_STOWED_HINT := "Stowed in cargo — equip it at your ship."
const CARD_MATERIALS := "Salvaged: +%d materials"
const CARD_MATERIALS_HINT := "Spend on Mk upgrades at the outpost."


# ===========================================================================
# OUTPOST  (outpost.gd)
# ===========================================================================

# ---- Upgrade card names and descriptions ----

const UPGRADE_HULL_NAME := "Hull"
const UPGRADE_HULL_DESC := "Increases max hull. Mk.9: Hull Repair -30%."

const UPGRADE_THRUSTERS_NAME := "Thrusters"
const UPGRADE_THRUSTERS_DESC := "+3% movement speed per Mk."

const UPGRADE_SELF_REPAIR_NAME := "Self Repair"
const UPGRADE_SELF_REPAIR_DESC := "+1 hull pip on sector map return."

const UPGRADE_SHIELD_CAP_NAME := "Shield Capacity"
const UPGRADE_SHIELD_CAP_DESC := "+2 max shield HP per Mk (base 10)."

const UPGRADE_HULL_PLATING_NAME := "Hull Plating"
const UPGRADE_HULL_PLATING_DESC := "3% chance per Mk to shrug hull hits (Mk.1–8). Mk.9: +6% bonus → 30% total."

# ---- Service button base labels ----

const SERVICE_HULL_REPAIR := "Hull Repair  +1 pip"
const SERVICE_SHIELD_REFILL := "Shield Refill"
const SERVICE_PRIMARY_AMMO := "Primary Ammo"
const SERVICE_SECONDARY_AMMO := "Secondary Ammo"
const SERVICE_SUPER_CHARGE := "Super Charge  +1"

# ---- Service button dynamic-state suffixes ----
# Appended to the base_label via "%s %s" in _apply_service_button_state.

const SERVICE_SUFFIX_NO_SHIP := "(no ship)"
const SERVICE_STATE_HULL_FULL := "Hull Full"
const SERVICE_SOLD_OUT := "— OUT (refresh at next boss)"

# Sector-modifier display (key -> player-facing "Name (effect)"). Keys are
# run_state.ALL_SECTOR_MODIFIERS. Shown in the outpost so the player can see the
# active sector theme (Roman 2026-06-08).
const MODIFIER_LABELS := {
	"wanted": "Wanted (+20% bounty)",
	"armored": "Armored (tougher enemies)",
	"heavily_armored": "Heavily Armored (much tougher)",
	"shielded": "Shielded (enemy shields)",
	"aggressive": "Aggressive (faster fire)",
	"dangerous": "Dangerous (2x damage to you)",
	"fleeing": "Fleeing (enemies don't recycle)",
	"cruiser_support": "Cruiser Support (rare heavy)",
}
const SECTOR_MODIFIERS_LABEL := "SECTOR: %s"
const SECTOR_MODIFIERS_NONE := "SECTOR: standard conditions"
const SERVICE_SUFFIX_NO_SHIELD := "(no shield)"
const SERVICE_STATE_SHIELDS_FULL := "Shields Full"
const SERVICE_SUFFIX_FREE := "(FREE)"
const SERVICE_SUFFIX_NO_RUN := "(no run)"
const SERVICE_SUFFIX_BLASTER_INFINITE := "(Blaster, infinite)"
const SERVICE_SUFFIX_NO_PRIMARY_AMMO := "(no primary ammo)"
const SERVICE_SUFFIX_AUTO_REGEN := "(auto-regen)"
const SERVICE_STATE_AMMO_FULL := "%s  Full"
const SERVICE_SUFFIX_REFILL_COST := "Refill (%d)"
const SERVICE_SUFFIX_NONE_EQUIPPED := "(none equipped)"
const SERVICE_SUFFIX_NEED := "+%d (need %d)"
const SERVICE_SUFFIX_PARTIAL := "+%d (%d, partial)"
const SERVICE_SUFFIX_AMMO_COST := "+%d (%d)"
const SERVICE_STATE_SUPER_NONE := "Super  (none equipped)"
const SERVICE_STATE_SUPER_FULL := "Super  Full"

# ---- Toast messages ----

const TOAST_UPGRADE_PURCHASED := "Upgrade purchased"
const TOAST_EQUIPPED := "EQUIPPED"
const TOAST_PRIMARY_REFILLED := "Primary refilled"
const TOAST_SECONDARY_REFILLED := "+%d rounds (%d)"

# ---- UI chrome ----

const OUTPOST_TITLE := "FRIENDLY OUTPOST"
const OUTPOST_COL_WEAPONS := "WEAPONS"
const OUTPOST_COL_UPGRADES := "UPGRADES"
const OUTPOST_COL_SERVICES := "SERVICES"
const OUTPOST_SELL_HEADER := "SELL EQUIPMENT"

const OUTPOST_STAT_HULL := "HULL"
const OUTPOST_STAT_SHIELD := "SHIELD"
const OUTPOST_STAT_PRIMARY := "PRIMARY"
const OUTPOST_STAT_SECONDARY := "SECONDARY"
const OUTPOST_STAT_SUPER := "SUPER"
const OUTPOST_STAT_BOUNTY := "BOUNTY"

# Empty-state labels.
const OUTPOST_WEAPONS_DEPLETED := "Stock depleted."
const OUTPOST_UPGRADES_MAXED := "All upgrades maxed."
const OUTPOST_STORAGE_EMPTY := "No spare equipment."

# Weapon-card button states.
const OUTPOST_BTN_EQUIPPED := "Equipped"
const OUTPOST_BTN_PURCHASED := "Purchased"
const OUTPOST_BTN_BUY := "Buy (%d)"
const OUTPOST_BTN_EQUIP := "Equip"
const OUTPOST_BTN_SELL := "Sell +%d"
const OUTPOST_BTN_LEAVE := "Leave"
const OUTPOST_BTN_REFRESH := "Refresh Stock (%d)"
const OUTPOST_BTN_REFRESH_MAX := "Refresh Stock (%d, max)"

# ---- Salvaging & Materials (Roman 2026-06-14) ----
const OUTPOST_STAT_MATERIALS := "MATERIALS"
const OUTPOST_COL_SHOP := "SHOP"
const OUTPOST_COL_LOADOUT := "LOADOUT"
const OUTPOST_COL_MODULES := "MODULES"
const OUTPOST_MODULES_EMPTY := "No modules installed."
const OUTPOST_CARGO_HEADER := "CARGO"
const OUTPOST_MODULE_BAY := "MODULE BAY  (%d / %d)"
const OUTPOST_LOADOUT_EMPTY := "Nothing equipped."
const OUTPOST_CARGO_EMPTY := "No carried equipment."
const OUTPOST_BTN_SCRAP := "Scrap +%d"
const OUTPOST_BTN_UNSLOT := "Unslot"
const OUTPOST_BTN_REMOVE := "Remove"
const OUTPOST_BTN_SET_ACTIVE := "Set Active"
const OUTPOST_BADGE_ACTIVE := "ACTIVE"
# Upgrade button: target Mk, materials cost, bounty cost — e.g. "Mk.2  2 mat·93".
const OUTPOST_BTN_UPGRADE := "Mk.%d  %d mat·%d"
const OUTPOST_BTN_UPGRADE_MAX := "Mk.MAX"
const TOAST_SCRAPPED := "Scrapped  +%d materials"
const TOAST_UPGRADED := "Upgraded to Mk.%d"
const TOAST_UNSLOTTED := "Moved to cargo"
# Card actions + states (Roman 2026-06-15 outpost pass).
const OUTPOST_INFO := "i"
const OUTPOST_BTN_RESTOCK := "Restock"
const OUTPOST_BTN_RESTOCK_ALL := "Restock All"
const OUTPOST_BTN_UPGRADE_MODE := "Upgrade Mode"
const OUTPOST_BTN_MANAGE_MODE := "Manage Mode"
const OUTPOST_INFO_PROGRESSION := "MARK PROGRESSION"
const OUTPOST_INFO_CLOSE := "Close"
const CARD_STAT_AMMO := "Ammo  %d / %d"
const CARD_STAT_CHARGES := "Charges  %d / %d"
const CARD_STAT_UNLIMITED := "Unlimited"
const CARD_STAT_SHIELD := "%d charges · %.1fs delay · %.1f/s"

# Slot short names (used in pill labels).
const SLOT_NAME_PRIMARY := "PRIMARY"
const SLOT_NAME_SECONDARY := "SECONDARY"
const SLOT_NAME_SUPER := "SUPER"
const SLOT_NAME_SHIELD := "SHIELD"
const SLOT_NAME_MODE := "MODE"
const SLOT_NAME_ENGINE := "ENGINE"
const SLOT_NAME_TAIL := "TAIL"
const SLOT_NAME_WING_L := "WING L"
const SLOT_NAME_WING_R := "WING R"
const SLOT_NAME_PART := "PART"

# Type labels (task #1, #3: distinguish Blaster from Primary Weapon).
const TYPE_NAME_BLASTER := "Blaster"
const TYPE_NAME_PRIMARY_WEAPON := "Primary Weapon"
const TYPE_NAME_SECONDARY_WEAPON := "Secondary Weapon"
const TYPE_NAME_SUPER := "Super"
const TYPE_NAME_MODE := "Mode"
const TYPE_NAME_UPGRADE := "Upgrade"

# Status bar label (task #5).
const OUTPOST_RESTOCK_HINT := "Defeat boss to restock."

# Loadout line format strings.
const LOADOUT_PRIMARY := "PRI: %s"
const LOADOUT_SECONDARY := "SEC: %s"
const LOADOUT_SUPER := "SPR: %s"
