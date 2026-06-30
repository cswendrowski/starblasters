# Sector Conditions — redesign (rename of "Sector Modifiers")

**Status: SCOPED / NOT BUILT.** This is the re-eval the parked sector-modifier subsystem was
flagged for (Roman 2026-06-10). The old code is intact behind a kill-switch; this doc says what
to keep, what to fix, and how to bring it back as a *chosen, rewarded* system rather than hidden
difficulty. No code has been written against this yet.

Supersedes the modifier notes in the archived `economy_2026-05-24.md` §1.3.

---

## 1. Why it was pulled, and what changed underneath it

The original system was a per-POI random roll that scaled with sector depth. Two things have since
made it unfit:

1. **The multi-sector roguelite collapsed to a single-sector patrol.** `TOTAL_SECTORS = 1`,
   `sectors_cleared` stays 0, and the per-sector damage ramp `dangerous` was balanced against was
   retired (2026-06-23). The count driver `modifier_count = 1 + sectors_cleared`
   ([run_state.gd:602](../scripts/autoload/run_state.gd)) is therefore dead — it always yields 1.
2. **It was all-stick-no-carrot and invisible.** Seven of eight modifiers are pure player debuffs;
   only `wanted` rewards you. They roll *per-POI* but are only ever shown as a deduped sector-level
   list in the outpost — so you walk into a "dangerous" fight blind. A roguelite modifier is only
   interesting when it's a **telegraphed risk you choose**, paired with a **reward**.

**Design thesis:** a Condition is a deal the player opts into. Conditions span **two axes** —
**combat** (harder fights, paid off with a bounty + materials % bonus, per the 2026-06-27 decision)
and **economy** (the outpost ledger — prices, stock, service costs, drops — which self-balances via
inverse boon/bane pairs). The more / harsher the load, the bigger the haul, or the deeper the squeeze
the player accepts for it. That risk↔reward framing — chosen, telegraphed, rewarded — is what makes
the system worth re-enabling. (The economy axis is the bulk of the 2026-06-27 additions and is new
ground the original combat-only vocabulary never touched.)

Rename **modifier → Condition** throughout (player-facing and code) so the reframe is legible and we
don't carry the "hidden difficulty" connotation. Keep `has_modifier()` as the internal query name or
rename to `has_condition()` — cheap either way (single seam).

---

## 2. What exists today (all parked, all reusable)

| Piece | Location | State |
|---|---|---|
| Kill-switch | `run_state.gd` `SECTOR_MODIFIERS_ENABLED = false` | flip to re-enable |
| Vocabulary (8) | `run_state.gd` `ALL_SECTOR_MODIFIERS` | reframe (§4) |
| Per-enemy effects | `director.gd` `_apply_sector_modifiers` | mostly reusable |
| `dangerous` ×2 dmg | `player.gd` `take_damage` | tier it (§4) |
| `cruiser_support` mult | `run_state.gd` `cruiser_encounter_chance_mult` | keep — good seam |
| `shielded` +1 charge | `director.gd` `_resolve_shields` | keep; scope to non-chaff |
| Query seam | `run_state.gd` `has_modifier(id)` | keep |
| Active list | `run_state.gd` `sector_modifiers: Array` | becomes `active_conditions` |
| Labels | `strings.gd` `MODIFIER_LABELS` | rewrite as bane+boon (§4) |
| Outpost readout | `outpost.gd` `_format_sector_modifiers` | keep, extend with reward line |
| **Patrol-setup stepper (0–5)** | `patrol_start.gd:936`, writes `patrol_sector_modifiers` meta | **half-built — unconsumed** |
| `patrol_endless` meta | `patrol_start.gd` | also unconsumed (out of scope here) |

Two cleanups fall out of this audit regardless of which front-end ships:

- **`armed` is an orphan.** `director.gd` has a `match "armed"` arm (bullet dmg ×1.3, speed ×1.1)
  but `armed` is in neither `ALL_SECTOR_MODIFIERS` nor `MODIFIER_LABELS`. Promote it to a real
  Condition (§4 "Heavy Ordnance") or delete the arm. Promoting reuses working wiring.
- **`fleeing` is mislabeled and near-useless.** `recycle_passes = 0` means "don't loop back," which
  the player can't perceive and which is arguably a *boon* (fewer enemies) sitting in a bane pool.
  The name implies enemies flee with your bounty. Rework into real flee behavior or retire (§4).

---

## 3. Run structure this has to fit

A patrol = **1 sector = 3 rows (lanes)**. Each row has 3–5 POIs (combat / hazard / signal) plus a
boss; you must clear *every* POI on a row to unlock its boss, and kill all 3 bosses to win
([run_state.gd:923 `is_row_pois_complete`](../scripts/autoload/run_state.gd)). So a patrol is ~9–15
combats + 3 bosses, and you fight **everything** — it is not a pick-one-path map. Outposts are a hub
button, not a node.

Consequence: **patrol-wide Conditions** (apply to the whole run) are the natural primary surface —
they're a pre-commitment that colors all ~12 fights, like a Hades Pact or StS Ascension. **Per-node
Conditions** still work as a *secondary* spice layer, but since you fight every node, they're less
"route around the hard one" and more "this specific fight is hot — extra reward." Telegraphing them
on the map is mandatory if we use them.

---

## 4. Vocabulary reframe — two axes, boons & banes

The 2026-06-27 additions reveal the system spans **two orthogonal axes**, and the reward model
differs between them (§5):

- **Combat axis** — banes that harden fights, boons that buff the player. Combat banes have no
  intrinsic upside, so they **carry a reward weight** (bounty + materials %, §5). Combat boons are
  chosen advantages with no reward weight.
- **Economy / Outpost axis** — Conditions that bend the ledger directly (prices, stock, service
  costs, drops). These are **self-balancing**: a bane *is* its own penalty and a boon *is* its own
  reward, so they carry little/no extra reward weight (§5). Most arrive as clean **inverse pairs**.

**New rule — mutex groups.** Every Condition belongs to a group; **at most one per group** may be
active. Inverse pairs share a group, so the roller/picker can't produce a wash. Known groups so far:
Buy-prices (Tariffs ↔ Buyer's Market), Stock-count (Scarcity ↔ Surplus), Mk-quality (Shoddy ↔
Quality), Upgrade-materials, Upgrade-bounty, Repair-materials, Repair-bounty, Restock,
**Enemy-speed (Fast ↔ Slow Enemies)**, **Bullet-speed (Fast ↔ Slow Bullets)**, and the tiered combat
group (Armored / Armored-Heavies if kept exclusive). The roll (Wildcard) and pick (Curated) logic
must enforce this. The old per-POI roller had no inverses, so this is genuinely new wiring.

### 4a. Combat axis — banes (carry reward weight)

| Condition | Effect | Source | Fix vs. old |
|---|---|---|---|
| **Armored** | enemy damage-reduction, tiered 10/15/20% | `director` `_apply_sector_modifiers` | **Collapse `armored`+`heavily_armored`.** Scope DR to heavies/elites — global DR on chaff drags the fast-kill rhythm and fights the clarity feel. |
| **Armored Heavies** *(new — Roman)* | non-chaff enemies get +max HP | `director` (enemy `max_hull`) | Distinct *feel* from Armored: bigger HP pool, not a per-hit DR. Could merge with Armored or keep as its own group (HP vs DR). Scope to non-chaff by chassis size. |
| **Shielded** | enemy +1 shield charge | `director` `_resolve_shields` | Keep; scope to non-chaff. |
| **Trigger-Happy** | enemies fire faster (the `aggressive` fire-rate half) | `director` | **Drop the ×1.15 bullet-speed half entirely** — Fast Bullets (below) is the clarity-correct way to speed bullets. Trigger-Happy = fire-rate only. |
| **Fast Enemies** *(new — Roman)* | enemy movement +1 rung (cap rung 8 / 480 px/s) | `director`, via `Clarity.rung_of` ±1 | Rung-stepped, so clarity-safe by construction (no off-rung strobe). Floor/ceiling clamp built in. |
| **Fast Bullets** *(new — Roman)* | enemy bullet speed +1 rung (cap rung 8) | bullet speed at spawn, via `Clarity` rung step | **The clarity-correct replacement for `aggressive`'s broken ×1.15 speed half.** Step the *authored* speed by a rung, don't apply a flat mult (a mult lands off-rung). See §8 on the `bullet_speed_mult` seam. |
| **Heavy Ordnance** | enemy bullets +30% damage | `director` (the orphan `armed` arm) | Promote the dead arm; **drop its speed bump** (Fast Bullets owns speed now). |
| **Glass Patrol** | incoming player damage tiered +50% / +100% | `player.gd` `take_damage` | **Tier the old `dangerous` ×2** — flat ×2 is a cliff; keep i-frames intact. |
| **Debris Fields** *(new)* | stray asteroids/mines drift through combat nodes | hazard conductor + decorative-mine spawner | Turns plain combats into mixed hazard fights. Reuses existing hazard systems. |
| **Elite Patrol** *(new)* | heavies replace a fraction of chaff | wave palette | Composition shift, not a stat tax. |
| **Reinforced** *(new)* | active-faction overlay applies a tier up / to more spawns | `factions.gd` `apply` | Ties Conditions to the faction system. |
| **Bounty Hunters** *(new)* | an extra elite "hunter" spawns mid-wave | director spawn hook | Thematically pairs with the Wanted/Bounty Surge boon. |

### 4b. Combat axis — boons (no reward weight; a chosen edge)

| Condition | Effect | Seam |
|---|---|---|
| **Better Hull** *(new — Roman)* | starting hull +3 pips | `player.gd` `apply_run_upgrades()` — adds to `max_hull` after the loadout sets it (base 2 + module pips). |
| **Better Shields** *(new — Roman)* | shorter shield-recharge delay + faster regen ticks | `player.gd` `_effective_regen_delay()` (the `ShieldRegenTimer.wait_time`) + the 1/sec regen tick rate. |
| **More Ammo** *(new — Roman)* | +50% max ammo, all armaments | scale `ammo_max` (primary regen pool), `secondary_ammo_max`, `ammo_max` on each ammo-using part at loadout time. |
| **Slow Enemies** *(new — Roman)* | enemy movement −1 rung (floor at the min rung) | `director`, via `Clarity.rung_of` −1 | A *difficulty-down* boon (lowers Threat, §5), not a power boon. Mutex with Fast Enemies. |
| **Slow Bullets** *(new — Roman)* | enemy bullet speed −1 rung (floor rung 1 / 60 px/s) | bullet speed at spawn, via `Clarity` rung step | Difficulty-down boon. Mutex with Fast Bullets. |
| **Overcharged** *(optional)* | player +fire-rate | A chosen edge if we want a damage boon. |

*(More Ammo / Better Hull / Better Shields supersede the earlier vague "Overcharged / Quartermaster"
sketch. Slow Enemies / Slow Bullets are the first **difficulty-reducing** boons — they make the run
easier rather than the player stronger, which is also a clean accessibility lever.)*

### 4c. Economy axis — paired Conditions (self-balancing, mutex by group)

All bane | boon pairs share a mutex group. Seams verified against `outpost.gd`.

| Group | Bane | Boon | Seam |
|---|---|---|---|
| Buy prices | **Galactic Tariffs** (+20% prices) | **Buyer's Market** (−20% prices) | offer `cost` (`CANNON_BASE_COST + (mk-1)·CANNON_COST_PER_MK`) at roll/buy time. |
| Stock count | **Market Scarcity** (fewer offers / reset) | **Market Surplus** (more) | offer count in `_roll_offers` (+ `outpost_needs_refresh` re-roll). |
| Mk quality | **Shoddy Imports** (less likely to roll its max Mk) | **Quality Goods** (more likely) | the weighted Mk roll (`MK_HIGH_OFFSET = 3`); bias the high-Mk weight down/up. |
| Upgrade — materials | **Complex Upgrades** (+material) | **Cheap Upgrades** (materials only, drops the bounty fee) | upgrade cost `mats = new_mk` in `_upgrade_button_spec` / `_on_upgrade_part`. |
| Upgrade — bounty | **Costly Upgrades** (+bounty) | **Easy Upgrades** (bounty only, drops the material cost) | `_upgrade_bounty_cost(new_mk)`. |
| Repair — materials | **Complex Repairs** (+material) | **Cheap Repairs** (materials only) | `_on_repair` — **⚠ repairs cost no material today** (bounty + a repair charge). See §8. |
| Repair — bounty | **Costly Repairs** (+bounty) | **Easy Repairs** (bounty only) | `_hull_repair_cost()` (base 250). |
| Restock | **Costly Restock** (pricier) | **Cheap Restock** (cheaper) | `PRIMARY_REFILL_COST` / `AMMO_COST_PER_ROUND` / `SUPER_REFILL_COST`. |

**Cost-split semantics:** "costs *only* X" presupposes the action normally costs both currencies.
**Upgrades already do** (materials `= new_mk` **and** a bounty labor fee), so the upgrade matrix works
as-is. **Repairs don't** — they're bounty + a charge with no material cost, so Cheap/Complex Repairs
either (a) presume a small baseline material cost is added to repair, or (b) are defined as
"add/swap." Resolve in §8 before building the repair pairs.

### 4d. Economy axis — drops & grants (boons)

| Condition | Effect | Seam |
|---|---|---|
| **Salvage Rights** *(new — Roman; replaces the earlier vague "+X% materials" sketch)* | every combat level grants ≥1 material; bosses grant more | material-grant hook at `level_cleared` / boss-death payout. Concrete and legible — a guaranteed floor, not a %. |
| **Hazard Pay** *(new — Roman)* | clearing any combat POI (combat **or** hazard node) awards a flat +100 bounty | the per-node clear payout (`run_state.mark_node_completed` / the level-clear → cleared-summary award). The bounty twin of Salvage Rights. |
| **Starting Funds** *(new — Roman)* | start the patrol with 250 bounty | apply **after** `new_run()` (which zeroes `bounty` at [run_state.gd:351](../scripts/autoload/run_state.gd)) — same write point as the other patrol-setup metas in `patrol_start._launch`. |

### Pacts (pre-bundled bane+boon — one-tap flavor)

Pacts can now bundle *across* axes, which is where it gets interesting:

- **Blood Money** — enemies +50% damage to you, **+50% bounty**.
- **Scrap Run** — enemies +1 shield, **Salvage Rights** (guaranteed materials).
- **Speed Trap** — enemies fire faster, **you get +1 shield charge**.
- **Black Market** — **Galactic Tariffs** (prices up) but **Quality Goods** (better Mk rolls).
- **Hot Zone** — `cruiser_support` (more cruisers) is itself a boon+bane (more loot *and* danger);
  keep as a standalone "Heavy Escort" Condition.

**Retire or rework:** `fleeing` (mislabeled, imperceptible). If kept, make it *real*: low-HP enemies
actively bolt off-screen, trading dropped bounty for a faster clear.

---

## 5. Reward coupling (decided: bounty + materials %)

The two axes pay out differently — this is the key refinement the economy Conditions force:

**Combat banes** contribute a reward weight, aggregated into two run multipliers applied at drop time:

```
bounty_mult    = 1 + Σ(combat_bane.bounty_weight)
materials_mult = 1 + Σ(combat_bane.materials_weight)
```

Apply `bounty_mult` on the enemy `bounty_value` payout and `materials_mult` where materials drop.

**Economy Conditions are self-contained** — their effect *is* the reward or penalty (a price hike, a
better Mk roll, a guaranteed material), so they carry **little or no extra reward weight**. They
balance against each other via inverse pairs and against the combat banes via a natural **source/sink
tension**: a combat bane pumps `materials_mult` up, while an economy bane (Complex Upgrades) makes
materials *cost more to spend*. That tension is the design, not a bug — it keeps a fat materials haul
from trivializing the run.

- **Salvage Rights / Bounty Surge / Hazard Pay / Starting Funds** feed the same multipliers / flat
  injections, so a cautious player can still buff their own payout without taking combat banes — they
  just won't earn the bane bonuses.
- **Difficulty-down boons** (Slow Enemies, Slow Bullets) carry a *negative* Threat contribution: they
  make the run easier, so at a given Threat Level they'd offset a bane (or the Curated picker shows
  them lowering the projected payout). They're the easy-mode / accessibility lever.
- **Surface live numbers** in the patrol-setup panel ("Projected: +65% bounty, +40% materials,
  prices +20%") and extend the outpost readout (`_format_sector_modifiers`).
- **Tuning needs a tuner** (per CLAUDE.md's human-iterated rule): start combat banes at +15–30%
  reward weight, let `economy-sim` check a full-load run pays for itself. Economy pairs are
  symmetric (±20% etc.) so they self-balance with little tuning.

A derived **Threat score** (Σ normalized weights across *both* axes) drives the run-summary "Threat
Level" line and is the natural future meta-unlock hook — a display, not a second currency.

---

## 6. Front-ends (one pipe, multiple UIs)

All front-ends write the same `Run.active_conditions: Array` and reuse every effect site in §2.
Build the pipe once; each UI is then cheap. **Which to build, and in what order, is Roman's call —
this doc just defines them.**

1. **Wildcard count** *(smallest first ship)* — consume the 0–5 stepper that already exists and is
   already writing `patrol_sector_modifiers` ([patrol_start.gd:1245](../scripts/dev/patrol_start.gd)).
   On Begin Patrol, roll N Conditions, store them, and **reveal them** on a confirmation beat. This is
   ~1 consume-function + the roll; it proves the whole pipe end-to-end.
2. **Curated picker** — at patrol setup, hand-pick Conditions from cards showing bane **and** boon and
   the running payout multiplier. Most agency; most UI. Lives in the patrol-setup panel.
3. **Threat Level** — a named selector (Routine → Standard → Hot → Critical) that auto-stacks an
   escalating count + severity and shows the resulting payout multiplier. The Hades-Heat / StS-Ascension
   meta hook. Same pipe.
4. **Per-node Hotspots** *(Phase 2, highest polish)* — flip the per-POI roll back on but make it
   **visible**: a badge + tooltip on flagged sector-map nodes, harder fight = guaranteed bonus drop.
   Reuses the per-POI machinery in `_gen_row_pois` (the unconditional `rng` calls are already there for
   seed stability). Since you fight every node, frame these as "this fight is hot" not "avoid this one."

These map 1:1 onto Roman's brief (pick / roll-a-count / difficulty / all-of-the-above): they're not
competing designs, they're four faucets on one tank.

---

## 7. Recommended phasing

1. **Pipe + vocab reframe.** Rename to Conditions, build `active_conditions` + mutex-group metadata
   + the combat-bane reward multipliers, collapse `armored` tiers, fix `aggressive` (clarity clamp),
   tier `dangerous`, promote `armed` → Heavy Ordnance, retire/rework `fleeing`. Re-enable the combat
   effect sites behind the new flag.
2. **Economy-axis effect sites.** Thread the price / stock / Mk-roll / service-cost / drop hooks
   through `outpost.gd` (per the §4c table) and the level-clear material grant. These are independent
   of the combat sites and can land in parallel.
3. **Wildcard count front-end** (consumes the existing seam → first playable; honors mutex groups).
4. **Reward surfacing** (patrol panel + outpost line) and a balance tuner for the combat-bane weights.
5. **Curated picker**, then **Threat Level**.
6. **Per-node Hotspots** (Phase 2) if the patrol-wide version proves fun.

Seed-stability note: the per-POI roll calls (`rng.randf()` / `rng.randi()`) run **unconditionally**
today specifically so the flag doesn't shift the RNG stream
([run_state.gd:765](../scripts/autoload/run_state.gd)). Preserve that property through any rework —
changing the call count desyncs seeded runs.

---

## 8. Open questions

- **Repair cost model (blocks the repair pairs).** Repairs cost bounty + a repair charge, **no
  material** today. The four repair Conditions (Complex/Cheap/Costly/Easy Repairs) presume repairs
  cost both currencies. Resolve before building them: **(a)** add a small baseline material cost to
  repair so the matrix is symmetric with upgrades *(recommended — makes the boon/bane pair meaningful
  and ties repair into the materials economy)*, or **(b)** define Complex/Cheap Repairs as "adds a
  material cost" / "swaps bounty→materials" and accept Easy Repairs is near-baseline. Pick (a).
- **Mutex enforcement + the repair-charge axis.** The roller/picker must respect mutex groups (§4) so
  inverse pairs can't both apply. Separately: repair/restock are **charge-limited** (2d6 each, +1d6
  per boss) — that's a *different* lever than cost. A future "Quartermaster" (more charges) / "Supply
  Shortage" (fewer charges) pair could live on that axis; out of scope for v1 but noted so the cost
  Conditions don't get conflated with the charge economy.
- **Bullet-speed rung seam.** Fast/Slow Bullets must step the *authored* bullet speed by a `Clarity`
  rung, but enemy bullet speed is currently scaled by a flat `bullet_speed_mult` on `enemy_base` — a
  multiplier lands off-rung and reintroduces the strobe/wobble Clarity exists to prevent. Resolve by
  either computing the post-step target speed and deriving the exact mult per bullet, or adding a
  `bullet_rung_delta` field that the bullet applies via `Clarity.snap_to_rung` at spawn. Enemy
  *movement* speed is authored on a rung already, so Fast/Slow Enemies is a clean `rung_of ±1` clamp.
- **Bosses** carry no Conditions today (`modifiers: []`). Patrol-wide Conditions probably apply to
  boss fights; the per-node version would naturally skip bosses.
- **Hazard nodes** (asteroid/mine fields) — most combat Conditions are enemy-stat tweaks that no-op
  on hazards; Debris Fields is redundant there. Define the no-op set. Economy Conditions are
  hazard-agnostic (they live at the outpost).
- **Min payout floor** — a clean (zero-bane) run should never feel *punished*, just unrewarded; boons
  let a cautious player still buff their own payout. (Economy *banes* are the exception — they're a
  deliberate squeeze the player opts into, e.g. via Threat Level.)
- **Save/resume** — `active_conditions` (+ each one's tier) must persist in the run save (patrol-scoped).
  Add to the `run_save` whitelist alongside `sector_modifiers`.
