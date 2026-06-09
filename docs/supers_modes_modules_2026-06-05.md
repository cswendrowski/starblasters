# Supers, Modes, Modules & Upgrades — Classification + Mode-Energy Design Spec

> ⛔ **SUPERSEDED (2026-06-08) by `docs/shift_mode_system_2026-06-08.md`.**
> Roman simplified the mode design: **one super only (Smart Bomb)**, and a **SHIFT_MODE slot**
> (Focus default; Phase/Hyper swap-ins) with **per-mode resources** — Phase = kill-earned
> charges, Hyper = a full-gated Focus-style bar. The **Mode-Energy gauge, the unified recharge
> spine, the ace-chain coupling, and the focus-save dual-hitbox in this doc are DROPPED.** The
> Super/Secondary/Module/Upgrade *classification* below is still useful background, but the
> mode mechanics here are obsolete — follow the new doc.

Status: **SUPERSEDED — see banner above.** ~~design / not built; magnitudes first-pass.~~

Context: Starblaster's "supers" layer is semi-neglected — three supers share one
device slot, "Focus" is a separate baseline modal, and hull/shield/regen/plating
are abstract `Run` integer upgrades, not parts. This spec consolidates all of it
into four crisp buckets (**Super / Secondary / Module / Upgrade**), collapses the
three supers into a single panic-button super plus a one-of-three **stance**
("mode") system, and specs the shared **Mode Energy** resource that drives the
stances.

Cross-refs:
- Ace-chain dependency: `docs/economy_spec_2026-06-03.md` §2.2 (the kill-chain
  multiplier — **LOCKED model, not built**). The stance recharge system is
  designed to work **with or without** it (see §7).
- Existing part/slot system this builds on: `scripts/parts/part.gd`,
  `scripts/weapons/SlotTypes.gd`, `scripts/weapons/loadout.gd`.
- Super→secondary migration precedent: `scripts/parts/drone_swarm.gd` (Combat
  Drones, moved 2026-05-30).

---

## 1. The four-bucket taxonomy (the litmus test)

Every player-ship system sorts into exactly one bucket. Apply the test in order;
first match wins.

| Bucket | Test | Input | Resource |
|---|---|---|---|
| **Super** | "Is this the *panic button* that saves a run?" Exactly **one** exists. | Single tap (X) + death-bomb auto-fire | **Super charges** — scarce, *bought* at outpost |
| **Secondary** | "Does it *fire* and supplement DPS / counter an enemy type?" | Hold/tap (C) | Ammo or cooldown |
| **Module** | "Does it **add a system/capability** the ship didn't have?" (a stance, regen, ablative drones) | Stance = Shift; passives = none | Mode Energy (stance) or passive |
| **Upgrade** | "Does it just make a **number** on an existing system better?" (+max hull, +speed, +ammo cap, +Mode Energy) | None | bounty (in-place Mk buy) |

**Corollary (prevents modules from absorbing everything):** a pure
capacity/number buff is always an *Upgrade*, even if it feels "installed."
That's what sends Ammo Pods to the Upgrade bucket (§9).

The decisive line, stated once: **a Module adds a thing; an Upgrade refines a
thing.** Hull regen adds a system → Module. +10 max hull refines a number →
Upgrade.

---

## 2. Slot architecture

| Layer | Slot | Input | Resource | Contents |
|---|---|---|---|---|
| **Super** | fixed (not chosen) | X + death-bomb | Super charges (bought) | Smart Bomb only |
| **Mode** | 1 dedicated stance slot | Shift | **Mode Energy** (earned) | Focus \| Phase \| Hyper — pick 1 |
| **Passive modules** | 4 slots | none (automatic) | — | Shield, Hull Regen, Plating, Targeting, Magnet, Intercept Drones… |
| **Upgrades** | — (abstract `Run` Mk) | none | bounty | +max hull, +speed, +ammo cap, **+Mode Energy max/regen** |

Two deliberate structural calls:

- **The Super is not a choosable slot.** It is *always* Smart Bomb, on X, with
  the existing Touhou death-bomb auto-fire. Reducing "which super" to a single
  permanent panic button is the point.
- **The Mode is a dedicated 5th slot, NOT one of the 4 passive slots.** Every
  build wants a stance, so making the stance compete with passives just taxes
  everyone equally — that's a tax, not a choice. The stance gets its own axis;
  the 4 passive slots are the build-variety bay.

Slot enum reality: `SlotTypes.gd` already declares `DEVICE_BAY_1/2`, `SHIELD`,
and unused wing slots. The Mode slot and the passive-module slots map onto these
reserved enum values; no new slot *infrastructure* is required, only new
`slot_type` assignments and a bay UI.

---

## 3. Two resources, kept separate

| Resource | Feeds | Refill | Character |
|---|---|---|---|
| **Super charges** | Smart Bomb (X) | *bought* at outpost (currently 120 bounty/charge) | scarce, precious, "last resort" |
| **Mode Energy** | the equipped stance (Shift) | *earned* in combat (§6–7) | renewable, skill-driven |

**Do not merge them.** If the stance drew from super charges you'd be "paying to
dodge"; if the bomb drew from Mode Energy it would stop being the sacred last
resort. Different gauges, different fantasies, different HUD anchors.

---

## 4. The stance triangle (the Mode system)

The Mode slot holds exactly one of three mutually-exclusive stances, all on
Shift, all spending Mode Energy. **Focus is the default-equipped stance** —
that, not a separate "baseline focus" mechanic, is the new-player safety floor.
A player who swaps Focus out for Hyper/Phase is *knowingly* trading away
precision-dodge.

| Stance | Identity | Effect | Refuel loop |
|---|---|---|---|
| **Focus** (default) | Defensive-precision (skill dodging) | 0.55× speed, hitbox dot, precision | **Focus-saves** (threading would-be hits) |
| **Phase** | Defensive-panic (get *through*, don't erase) | Intangible, **can't shoot**, reposition. **No bullet-clear.** | **Time floor** (+ mild kill bonus) |
| **Hyper** | Offensive sustain | Primary **ignores ammo** + fire rate **+10%** | **Kills** (strong) |

Three survival philosophies on one button: out-dodge (Focus), pass-through
(Phase), or out-damage (Hyper) the threat.

**Why each refuels the way it does** — the design's spine. Each stance refills by
the activity that matches its fantasy:
- **Focus → grazing/threading.** Rewards tight, skillful dodging. Defensive
  *skill* loop.
- **Hyper → kills.** Rewards aggression with more aggression. Offensive
  *momentum* loop.
- **Phase → time (loop-less).** The dependable "I just need to not die" button
  that doesn't ask you to earn it mid-crisis. Its loop-less-ness is a *feature*.

**Phase differentiation vs Smart Bomb:** both are defensive, but they sit on
different buttons *and* different resources, so Phase must stay the
*reposition-through* tool (intangible, can't shoot, **no bullet-clear**) while
the Bomb is the *erase-everything* panic. Drop any bullet-cancel from Phase.

---

## 5. The unified recharge spine

All three share one spine: **a passive time floor (always present, skill-free) +
a stance-flavored accelerator (skill-driven).**

| Stance | Unit | Cost | Time floor (always) | Accelerator |
|---|---|---|---|---|
| **Focus** | seconds reserve (rheostat) | drain 1s/s held | +1s/s passive, 1.5s post-use delay | +1s per focus-save (capped, §8) |
| **Phase** | segmented charges (2) | 1 charge, 2.0s duration | ~8s / charge | **weak** kill/ace bonus (≤25%) |
| **Hyper** | segmented charges (2) | 1 charge, ~3.0s duration | ~10s / charge | **strong** kill/ace bonus (≤50%) |

Phase and Hyper share a UI template (segmented pips + a filling next-pip); Focus
is the lone continuous bar. (See §10.)

**First-pass numbers (all tunable; an `economy-sim`/playtest job):**

```
Mode Energy — Focus reserve:  10.0 s   (drain 1.0/s held, regen 1.0/s after 1.5s idle)
Mode Energy — Phase:           2 charges, 2.0 s each, floor recharge 8.0 s/charge
Mode Energy — Hyper:           2 charges, 3.0 s each, floor recharge 10.0 s/charge
Focus-save value:              +1.0 s   (cap: 1 credited save / 0.5 s)
Hyper effect:                  primary ignores ammo + fire rate +10%
Phase effect:                  intangible, cannot fire
```

From a full tank: Focus ≈ 10 s held (far more when feathered), Phase ≈ 2 uses,
Hyper ≈ 3 s — note Hyper's ~3 s falls straight out of the duration, matching the
original "lasts 3 seconds" intent, now kill-extendable rather than fixed.

---

## 6. The governing balance principle (read this first)

After the stance rules, **all three reward good play with more resource**
(focus-saves, kills, kills). That is a high skill ceiling and great highlight
moments, but it is structurally **rich-get-richer**: the *struggling* player —
not dodging cleanly, not killing — gets the least help exactly when they need it
most, risking a death spiral (overwhelmed → no kills → slow recharge → fewer
escapes → more overwhelmed).

**The passive time floor is the equalizer.** It must be generous enough that a
flailing player still gets a charge back on a dependable cadence *with zero skill
input*. The skill accelerator is gravy on top — never the main meal.

> **Tune the floor first for the worst player; tune the accelerator second for
> the best player.** The floor keeps the system from being elitist; the
> accelerator keeps it from being boring.

---

## 7. Recharge driver: ace-chain primary, self-contained fallback

The Phase/Hyper accelerator is **kill-driven**. There are two ways to source
"how well are you killing," and the system is built to run on **either**, so
modes can ship before — or independently of — the economy redesign.

Both drivers feed one normalized **drive value `D ∈ [0,1]`** into a single
recharge formula:

```
charge_recharge_time = floor_time × (1 − maxBoost × D)
  Phase:  maxBoost = 0.25   → min recharge ≈ 6.0 s at D=1   (8.0 × 0.75)
  Hyper:  maxBoost = 0.50   → min recharge ≈ 5.0 s at D=1   (10.0 × 0.50)
```

### Driver A — ace-chain coupled (PREFERRED, if the ace-chain ships)

`D = clamp(ace_level / ACE_REF, 0, 1)` — reads the ace multiplier from
`economy_spec §2.2` (5 kills = an ace; the multiplier climbs with clean kills and
**drops when you get hit**). `ACE_REF` ≈ a mid-high ace tier (tune to the chosen
ace cap).

This is the elegant path: a single mistake (a hit) drops your ace, which costs
you **money *and* mode uptime** simultaneously — one unified "stay clean" stake
feeding economy + survivability + offense, with no second meter authored.

### Driver B — self-contained fallback (if the ace-chain is NOT built)

Each kill-driven stance carries a lightweight internal **kill-streak counter**
with its own decay — no economy dependency:

```
local_streak += 1 per kill
local_streak decays to 0 over STREAK_DECAY (≈ 3.0 s since last kill)
D = clamp(local_streak / STREAK_REF, 0, 1)   (STREAK_REF ≈ 8 kills)
```

The decay is what makes a *hit-free killing run* feel rewarded without needing
the ace "lose it when hit" rule. (Optional parity: also zero `local_streak` on
taking a hull/shield hit, to mimic the ace cleanliness stake.)

### What's identical across both drivers

- **Focus is driver-agnostic.** It refuels on **focus-saves**, not kills, in
  both modes — so Focus ships and balances independently of the ace-chain
  entirely.
- The **time floor** (§5–6) is always present and is the same in both drivers.
- The **asymmetry holds in both:** Hyper couples strongly (`maxBoost 0.50`),
  Phase weakly (`maxBoost 0.25`) — because tying a *defensive* button hard to
  *offensive* performance reintroduces the anti-synergy this whole design exists
  to avoid.

**Sequencing implication:** build the modes against Driver B now; swap the
single `D` source to Driver A when/if the ace-chain lands. One function changes.

---

## 8. Per-stance detail & caps

### Focus
- **Focus-save detection needs a dual hitbox.** "Evading a hit that would have
  hit you *outside* focus" = a bullet passing through the gap between the
  **unfocused** and **focused** hitboxes while focused. Implement as a second,
  larger Area2D that, during focus only, counts pass-throughs as saves. Bounded
  but net-new code (no existing graze mechanic — the `graze` string in
  `strings.gd` is unrelated ambush flavor).
- **Cap credited saves** at ~1 per 0.5 s, else dense bullet patterns hand you
  literally infinite focus. (You *want* a focus-master to stay focused in bullet
  hell — just bounded so it can end.)

### Phase
- Lean on the **floor, not the kills** (`maxBoost 0.25`). It is the reliable
  panic; do not make a struggling player earn it.
- No bullet-clear (differentiation from Smart Bomb, §4).
- Optional high-Mk flourish: a few i-frames on phase-*exit* so you don't
  re-materialize directly into a bullet.

### Hyper
- **Cap uptime even at max drive.** 3.0 s duration / 5.0 s min recharge ≈ **37%**
  uptime ceiling. Keep it under ~40% so max-ace/streak Hyper *extends* but never
  approaches permanent.
- **The accelerator must never be a purchasable upgrade** (`maxBoost`, the
  ace/streak coupling) — that's the runaway lever. Players buy Capacity and base
  Regen only (§9). Same rule retired the idea of a buyable kill-refund.
- Hyper's "no ammo" pairs specifically with the metered-ammo cannons (machinegun,
  rotary/auto laser, wave, heavy) — it's an ammo-relief + lean-DPS *sustain*
  mode, not the old "2× damage burst nuke." Role change is intentional.

---

## 9. Outpost economy

Mode Energy is **earned in combat, never bought** — so using your stance is never
gated by whether you paid. Only its *upgrades* and the *stance modules
themselves* cost bounty.

**Universal Mode Energy upgrades** (the Upgrade bucket — in-place Mk buy, like
hull/thrusters; placeholder cost `140 + (mk−1)×70`):

| Upgrade | Effect | Notes |
|---|---|---|
| **Mode Capacity** | Focus: +reserve seconds. Phase/Hyper: +max charges (milestones) | unit varies by equipped stance |
| **Mode Regen** | faster *floor* recharge / faster passive refill | the floor, never the accelerator |

**Never on the shelf:** focus-save value, the ace/streak `maxBoost`. Capacity and
floor-regen only — this protects the runaway caps (§8).

**Stance modules** are bought / swapped / upgraded at outposts **between nodes**
(not mid-combat), priced like parts (placeholder `116 + (mk−1)×70`). Each stance
is itself a `Part` with Mk.1–9 scaling its *effect* (§11).

---

## 10. HUD

Two separate gauges, two anchors:
- **Super charges** — discrete pips (existing).
- **Mode Energy** — one anchored bar, **bespoke skin per equipped stance**:
  - **Focus** → continuous draining bar; focus-save credits flash as +1s ticks.
  - **Phase** → **segmented** pips (read "I have 2 phases"); next-pip fills.
  - **Hyper** → segmented pips; next-pip fills, kill/streak accel shown as a
    fill-rate boost (pips pop on kills).

Phase + Hyper share the segmented template; Focus is bespoke continuous. Same
screen anchor regardless of stance.

---

## 11. Mk scaling summary

Three tiers of knobs — keep them legible, not sprawling:

| Tier | What scales | Bought as |
|---|---|---|
| **Pool** (universal) | Mode Capacity, Mode Regen (floor only) | Upgrade |
| **Stance** (per-module Mk.1–9) | the stance's *effect* | the stance module |
| **Accelerator** (fixed constants) | focus-save value, `maxBoost`, streak/ace coupling | **not purchasable** |

Per-stance Mk (first pass):
- **Focus:** odd Mk −drain (longer hold) / even Mk deeper slow or +focus-save
  value (the original "+time then +recharge" alternation, translated).
- **Phase:** +0.2 s duration / Mk; high Mk adds exit i-frames.
- **Hyper:** odd Mk +10% fire / even Mk +0.25 s duration. **Watch:** +10%/odd-Mk
  = +50% fire by Mk.9 on top of infinite ammo — the offensive ceiling of the
  game. Probably fine *because* uptime is capped, but it's the first number to
  playtest.

---

## 12. Disposition of every existing system

What moves where, and why. (Codebase reality as of 2026-06-05.)

### Current supers (`DEVICE_BAY_1`)
| Item | Today | → | Why |
|---|---|---|---|
| **Smart Bomb** | Super | **Super** (make permanent/baseline) | It *is* the life-saving screen-clear. Keep death-bomb + paid charges. |
| **Hyper Mode** | Super | **Module — stance** | A mode you enter, not a weapon. Redesign to no-ammo + fire-rate (role change). |
| **Phase Shift** | Super | **Module — stance** | A defensive stance; drop bullet-clear to differentiate from Bomb. |

None of the three becomes a *secondary* — secondaries fire; these are
modes/bombs. (The "super→secondary" path only ever fit Combat Drones, already
migrated.)

### Focus
| Item | Today | → | Why |
|---|---|---|---|
| **Focus** | baseline held-Shift modal | **Module — stance (default-equipped)** | Becomes 1 of 3 stances; being the *default* loadout is the new-player floor. No separate always-on focus needed. |

### Secondaries (`HARDPOINT_WING`)
| Item | → | Note |
|---|---|---|
| Seeking / Anti-Ship Missile, Rocket Pod, Particle Beam, Combat Drones | **Secondary** ✓ | Healthy roster, no change |
| **Intercept Drones** (passive ablative orbit, doesn't fire) | **→ Module (passive)** | A defensive *system*, not a weapon — frees a weapon slot |
| **Ammo Pods** (passive +ammo%) | **→ Upgrade** | Pure capacity buff = Upgrade by the §1 corollary |

### `Run` stat-Mk upgrades
| Item | Today | → | Why |
|---|---|---|---|
| `hull_mk` (+max hull) | Upgrade | **Upgrade** ✓ | number goes up |
| `thrusters_mk` (+speed) | Upgrade | **Upgrade** ✓ | number goes up |
| `shield_cap_mk` (+max shield) | Upgrade | **Upgrade** ✓ (scales the Shield module's capacity) | Shield *system* → Module; its capacity stays an Upgrade |
| `self_repair_mk` (hull regen) | Upgrade | **→ Module (Hull Regen, passive)** | "Adds regen = adds a system" |
| `hull_plating_mk` (shrug chance) | Upgrade | **→ Module (Hull Plating, passive)** | Shrug-chance is a *mechanic*, not a number |

### New default
- **Shield** becomes a passive Module the player **starts with** (occupying one
  of the 4 passive slots). Going shieldless is a deliberate glass-cannon choice.
  Reifying Shield/Hull-Regen/Plating from abstract `Run` ints into Part Resources
  is the one real refactor this spec implies (see §13).

---

## 13. Implementation scope (orientation, not a plan)

**Low-risk / reuse:**
- Modules *are* `Part`s in new slots — the `Resource` + `apply/unapply` + Mk
  snapshot/restore machinery already exists and the super→secondary migration
  proves the pattern. No new part *infrastructure*.
- Input is already solved: X = super, Shift = stance. No new binds.
- Reserved slot enums (`DEVICE_BAY_2`, `SHIELD`, wing slots) absorb the new
  slots.

**Net-new:**
- The **Mode Energy** resource + the floor/accelerator recharge spine (§5, §7),
  with the pluggable `D` driver.
- **Focus-save dual-hitbox** detection + cap (§8).
- **Mode bay UI** + the three bespoke Mode Energy bar skins (§10).
- Outpost: Mode Capacity/Regen upgrade cards + stance buy/swap/upgrade column.

**The one real refactor:**
- Reify Shield / Hull Regen / Hull Plating from `Run` integer Mk-keys into Part
  Resources (or, cheaper, keep them as `Run` ints but *present* them in the
  module bay — a build-vs-present tradeoff to decide).

**Sequencing:** modes can ship on Driver B (self-contained streak, §7) *before*
the economy redesign; swap `D` to the ace-chain (Driver A) when it lands.

---

## 14. Open decisions & tuning-risk checklist

Settled (this spec's premises):
- One permanent super (Smart Bomb, X). ✓
- One-of-three stance on Shift; Focus is default. ✓
- Stances swap/buy/upgrade at outposts between nodes. ✓
- Outpost sells Mode Capacity + Regen. ✓
- Bespoke per-stance HUD bar, shared anchor. ✓
- Dual recharge driver (ace primary, streak fallback). ✓

Still open / to decide before build:
1. **Reify or present** Shield/Hull-Regen/Plating as true Part Resources (clean,
   bigger refactor) vs `Run`-ints shown in the bay (cheaper).
2. **Mode slot count of the passive bay** — is it 4 passive slots beside the
   dedicated stance, or 3? (Spec assumes 4 + 1 stance.)
3. **Passive-module roster breadth** — the stance triangle is complete at 3, but
   4 passive slots want ~8–12 options to be a real choice. **Fleshed out in §15.**

Tuning risks (playtest order):
1. **Time-floor generosity** (§6) — tune for the worst player first. *The* lever.
2. **Hyper uptime cap** (§8) — must stay < ~40% at max drive.
3. **Focus-save cap** (§8) — must bound infinite-focus.
4. **Hyper Mk fire-rate** (§11) — +50% by Mk.9 on infinite ammo.
5. **Economy magnitudes** — all bounty costs here are placeholders for
   `economy-sim`.

---

## 15. Passive module roster

The 4 passive slots are the build-variety bay. Shield is default-equipped, so the
real choice is **3 of the rest** (or 4, if you go shieldless — see "Glass Cannon"
below). Target breadth: ~10 picks so the bay poses a decision instead of
auto-filling.

**Roster admission rules** (each candidate must pass all four):
1. **Automatic** — no input (input belongs to the stance/super).
2. **Adds a mechanic**, not a number (else it's an Upgrade — §1 corollary).
3. **No duplication** of a stance, the super, a secondary, or an existing
   upgrade.
4. **Mk.1–9 scalable** via the existing `apply/unapply` part pattern.

### The roster

| # | Module | Archetype | Mechanic | Mk axis | Balance watch |
|---|---|---|---|---|---|
| 0 | **Shield Core** *(default)* | Defensive | Charge-pool shield: each hit spends a charge + i-frames; empty → hull | +max charges, faster recharge | Semi-mandatory; dropping it = glass cannon (intended) |
| 1 | **Repair Nanites** | Defensive | Regen 1 hull pip every N s, **only after M s undamaged**, caps at max−1 | faster regen / shorter damage-gate | Slow + gated or it trivializes attrition; anti-synergy w/ Adrenal Surge |
| 2 | **Ablative Plating** | Defensive | Absorb **every Nth** hull hit (deterministic, not %) | smaller N (absorb more often) | Use deterministic, not RNG — a whiffed shrug at 1 hull feels awful |
| 3 | **Intercept Drones** | Defensive | Orbiting ablative drones block bullets, X hits each, refresh between waves | +drones / +hits | Drone-clutter; hard cap visible count for clarity |
| 4 | **Splinter Rounds** | Offensive | Killed enemies burst into short-range shrapnel damaging neighbors | +shrapnel dmg / radius | Screen clutter at 300-enemy density; keep range short + brief |
| 5 | **Targeting Computer** | Offensive | % crit chance on primary (×2 dmg, distinct flash) | +crit % | Crit × Hyper fire-rate can spike; keep crit modest |
| 6 | **Overclock Core** | Offensive | Sustained fire ramps fire-rate; resets on trigger release | +ramp cap / faster ramp | Free uptime on infinite-ammo blaster — cap the ramp |
| 7 | **Overcharge Core** | Risk-reward | +damage %, **−1 max shield charge** | +damage % (penalty fixed) | Stacks hard with Adrenal Surge — intended, but watch the ceiling |
| 8 | **Adrenal Surge** | Risk-reward | Fire-rate/damage scales **up as hull drops** (peak at 1 hull) | +low-hull bonus | Rewards near-death; must feel exciting, not just punishing |
| 9 | **Tractor Coil** | Utility | Auto-collect + pull bounty/pickups in a wide radius | +radius / pull speed | The "safe" pick; low excitement but real value at high density |
| 10 | **Siphon Core** | Risk-reward | Kills restore a sliver of **shield charge** (NOT Mode Energy) | +siphon / lower kill threshold | **Must never feed Mode Energy** — that's the Hyper runaway lever (§8) |

Spread: 4 defensive / 3 offensive / 3 risk-reward+utility. 10 picks for ~3 free
slots = a real decision with archetype identity.

### Why these are modules, not upgrades

The line is enforced hard. Each adds a *mechanic*: regeneration, deterministic
absorption, orbital interception, on-kill AoE, crits, a fire ramp, a
damage/penalty tradeoff, a hull-state curve, collection behavior, lifesteal.
Compare the things that **stay Upgrades**: +max hull, +max shield, +speed, +ammo
cap, +Mode Energy max/regen — those just move a number and live in the in-place
Mk shop.

### Build archetypes the roster enables

Proof the 4-slot bay sings (stance in parens):

- **Fortress** *(Phase)* — Shield + Repair Nanites + Ablative Plating + Intercept
  Drones. Maximum attrition resistance, low offense. Outlast everything.
- **Aggro Swarm-clear** *(Hyper)* — Shield + Splinter + Targeting + Overclock.
  Melt density, feed the ace-chain, snowball Hyper uptime.
- **Glass Cannon Duelist** *(Focus)* — **drop Shield** → Overcharge + Adrenal
  Surge + Targeting + Siphon Core. Paper-thin, enormous damage, sustains *only*
  by killing, survives *only* by dodging. High skill ceiling, build-defining.
- **Economist** *(Hyper)* — Shield + Tractor Coil + Siphon + Splinter. Maximize
  bounty throughput across dense waves; offense funds the run.

Note the deliberate tensions: **Repair Nanites vs Adrenal Surge** (regen pulls
you *out* of the low-hull bonus zone), and **dropping Shield** unlocks a 4th slot
but removes your hit-eating buffer — the roster's most interesting decision.

### Considered and cut (with reasons — be skeptical of re-adding)

| Idea | Verdict | Why |
|---|---|---|
| **Auto-Dodge** (reflexive sidestep) | **Cut** | Undermines the core dodge skill; removes agency in a dodging game |
| **Scavenger** (+bounty %) | **Cut / reclass** | A pure number → it's an *Upgrade*, not a module (§1 corollary). Reframe as a mechanic (e.g., "elites drop a one-time cache") if wanted |
| **Reflector / Thorns** | **Cut** | Reflected bullets add screen clutter at 480×270 — a motion-clarity violation; fiddly |
| **Last Stand** (auto-revive) | **Cut** | Redundant with the super's death-bomb — don't ship two "don't die" mechanics |
| **Threat Sensor** (early telegraphs) | **Cut** | An accessibility/settings concern, not slot-competitive |
| **Piercing Core** (universal +pierce) | **Hold** | Steps on Wave Gun's cannon *identity* — pierce is that weapon's thing |
| **Auto-Turret / Sentry** | **Hold** | Drone-soup overlap with Intercept + Combat Drones; revisit only if the others are cut |

### Roster open questions

1. **Repair Nanites scope** — combat regen (gated, as specced) vs between-combat
   only (the current `self_repair` behavior). Combat regen is the bigger
   trivialization risk; the no-damage gate is the safety.
2. **Shield as one of the 4 vs a dedicated defensive slot** — spec assumes Shield
   occupies one of the 4 (so it competes; dropping it is a real choice). A
   dedicated shield slot would remove that decision (and the glass-cannon build).
   Recommend keeping it in the 4.
3. **Crit visibility** — Targeting Computer crits need a distinct hit-flash so the
   ×2 reads; coordinate with `vfx-author`.
4. All magnitudes (regen rate, crit %, ramp cap, siphon, damage %) are
   placeholders for `economy-sim` + playtest.
