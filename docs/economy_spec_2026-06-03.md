# Economy — Earning, Spending, Supply, Ace-Chain — Design Spec (in progress)

Status: **design / not built**. Split out of
`docs/wave_streaming_variety_spec_2026-06-03.md` on 2026-06-03 so wave generation
can proceed independently; economy *balancing* (the numbers) is deliberately
deferred until wave gen is settled. What's locked here is the **structure**;
magnitudes are an `economy-sim` job.

Context: the wave-gen rework targets **~300 enemies per combat level**
(~1,500/sector). That volume is the reason this economy exists in its current
shape — see the wave spec for the density model.

---

## 0. Stopgap patch (interim, pre-redesign) — PROPOSED

A cheap, ship-now bounty cut to keep the *current* (~40-enemy) economy from
overflowing, independent of the full rework above. Flat **size-based** bounty:

| size | bounty |
|---|---|
| small / chaff | 1 |
| medium | 3 |
| large | 5 |
| huge / giant | OPEN (fold to 5, or 8/12?) |
| boss | 50 (OPEN: flat, or keep a Conductor/final premium?) |

A flawless clear is still worth doing (more kills = more bounty) but can't
overflow the economy. **This is a flat per-enemy cut — it does NOT add the
ace-chain (§2.2); that's still the redesign.**

Implementation reality (more than one edit — `enemy_roster.gd` +
`SIZE_TABLE`/`RARITY_BOUNTY_MULT` + boss scripts):
- **17 `bounty_override` entries** bypass `SIZE_TABLE` and must be stripped or
  reconciled to the size scheme (dart, drifter, hunter, burner, bomber,
  firecore_cruiser, …).
- **`RARITY_BOUNTY_MULT`** (1/2/4) multiplies size bounty → set to 1 for a
  size-only scheme (removes elite bounty reward; acceptable for a stopgap).
- **7 boss scripts** set bounty individually (Commander 300, Reaver 200, Howler
  250, Voidmaw 300, Aegis 350, Spinwright 350, Conductor 600) → set to 50 each
  (flat-50 drops the Conductor/final premium).
- `enemy_base` default `bounty_value = 5`.

Open micro-decisions: huge/giant value, whether to keep any rarity bump, flat-50
vs final-boss premium.

---

## 1. Principle: money and survival are DIFFERENT currencies — LOCKED

With ~1,500 kills/sector, **money is deliberately abundant.** So survival must
NOT be money-gated, or abundance trivializes mistakes. Two currencies, two jobs:

- **Bounty** buys **power** (upgrades/items).
- **Station supply** (hull material + ammo) buys **survival** (repairs/
  consumables). Supply is scarce and is the real limiter (§4).

A repair costs **both bounty AND a supply charge.** This is the keystone the
whole economy hangs on.

---

## 2. Earning — completion floor + ace-chain ceiling

### 2.1 Primary: node-completion bounty (the floor) — LOCKED
Flat reward for clearing a node — the dial balanced against shop prices,
**density-independent.** Tiered by node type:
- **Combat** ≈ 1 item's worth.
- **Hazard** (minefield/asteroid) ≈ 0.5–0.75 item (shorter obstacle-clears).
- **Boss** ≈ 2–3 items (the capstone payday).

### 2.2 Secondary: the "ace" kill-chain (the ceiling) — LOCKED (model)
Air-combat framing: 5 kills = an ace. Per-kill bounty scales with your **ace
level = `floor(kills_this_level / 5)`** — every 5 kills bumps the rate
(kills 20–24 pay 4 each, 25–29 pay 5 each, …).

- **Unified spendable currency — RESOLVED.** The ace payout *is* your money, not
  a separate score track. Big, satisfying, and spent in the shop.
- **It must be CAPPED.** Uncapped it is **quadratic** (`Σ floor(k/5) ≈ N²/10` →
  ~3,940 @200 kills, ~6,175 @250, ~8,910 @300), which re-couples income to
  density super-linearly (one 300-kill level pays ~2× two 150-kill levels). The
  **cap makes it linear-after-cap → density-safe.** Capped ≠ small (see §2.4).

### 2.3 What "performance" means here — KEY REFRAME
In a clear-to-advance streaming level, **everyone who completes kills ~all 300**
— raw kill count measures *level size, not skill*. So the performance signal is
**chain *maintenance*** (staying clean / not getting hit). "Really good
performance" = kept the chain alive. The ace bonus therefore measures
cleanliness, and the headline target is the **flawless-clear bonus**.

### 2.4 Three orthogonal knobs
Decoupling what kept getting tangled:

1. **Ace cap** — how the multiplier *climbs and feels* (and *where* skill
   separation lives: the climb, not the parked region). A feel/readability dial.
2. **Payout scale** — the *absolute size* of the numbers. Set **big** — it's free
   (only ratios are balance) and it makes score-accrual feel good *and* fixes
   per-kill granularity (chunky double-digit drops, not "+0.4").
3. **Hit penalty** — how much skill *swings* the take (§2.6).

### 2.5 The ratio target — OPEN (Roman to call)
Anchor under discussion: a *solid* ace clear ≈ **6k**, and **6k ≈ one item**.
Pick the cap for feel, then **peg item price = (ratio) × flawless-ace-total**:

| ace cap | flawless 300-kill ace total | (×1.9 multiplier ⇒ ~6k) |
|---|---|---|
| 10 | ~2,735 | hits 6k via scale multiplier |
| 15 | ~3,915 | hits 6k via scale multiplier |
| 25 | ~5,900 | hits 6k at flat 1:1 |

Recommended: **smaller cap (~12) × a payout multiplier** so the HUD multiplier
reads tidy ("ACE ×12") while the coins stay big.

The open ratio decision — how much skill should swing a combat clear:
- **Ace ≈ ½ item** → great clear = 1.5 items. Completion dominates; skill is a
  +50% topping. Steadier economy.
- **Ace ≈ 1 item** (the 6k anchor) → great clear = 2 items. Skill nearly
  *doubles* the take. Spicier, more score-driven.

### 2.6 Hit penalty = the performance-spread knob — OPEN (Roman to call)
Because of the cap, a sloppy player still climbs to the cap and *parks* there, so
a gentle penalty barely separates great from mediocre. The penalty sets the
spread:

| penalty on hit | sloppy clear earns (vs flawless) | feel |
|---|---|---|
| −1 tier | ~85–95% | barely rewards skill (too gentle) |
| **halve ace** | ~60–70% | skill matters, recoverable |
| **reset to 0** | ~15–30% | classic shmup combo stakes |

**Supersedes the earlier "drop one tier" lock** — that's too gentle given the
cap. Choose **halve** (forgiving) or **reset-to-0** (hardcore). With halve, a
*higher, harder-to-reach cap* (~15) spreads the contest across the whole level.

### 2.7 Ace as a multiplier on per-enemy value — RECOMMENDED
If ace **multiplies a per-enemy base** (vs flat per-kill = ace level), then
killing a fat elite at high ace is a **jackpot spike** — satisfying score-feel
*and* it makes hunting elites / high-value factions a real risk/reward (chaff ≈
near-zero base; elites carry the value). Flat-per-kill is simpler but loses that.

### 2.8 Open numbers (→ `economy-sim`)
Cap height, payout scale/multiplier, hit penalty, the ½-vs-full-item ratio, and
the price re-peg — validated by modeling flawless / N-hit clears against real
item prices, targeting "~1–2 meaningful upgrades per outpost."

---

## 3. Spending — persistent outpost hub — LOCKED (model)

- The outpost is a **persistent hub the player opens at will between missions** —
  a map-screen affordance (fits the existing return-to-map-between-nodes loop +
  the HD overlay UI), **NOT a POI node. Pulled from `_roll_poi_type` entirely**
  (`run_state.gd`).
- **Selection refreshes on boss kill** — 3 bosses/sector → initial stock + 3
  restocks. Buy from current stock anytime; refresh gated to milestones → no
  re-roll scumming.
- Near-free win because the map is **forced-clear** — outpost-as-node was never a
  real routing decision, so retiring it costs no choice and fixes the
  banked-buying-power mismatch (you can always spend; scarcity moves to "what's
  on the shelf until the next boss").
- **Freed 2–3 POI slots/sector** redistribute to combat/hazard/signal/special.
  (The slot redistribution itself is a *sector-structure* change tracked in the
  wave spec; the hub mechanics live here.) Optional **special / black-market
  nodes** carry rare or re-rollable stock as a *found* reward — distinct from the
  reliable hub, so exploration pays off without reintroducing scum.

OPEN: what services are always-on (browse/buy) vs milestone-gated; **repair is
the one to watch** — make it a *purchased* item (competes for bounty + supply) so
attrition keeps teeth, rather than free between every mission.

---

## 4. Supply gate — infinite money ≠ infinite repairs — LOCKED

Repairs/consumables draw on a **finite, capped supply pool** (hull material +
ammo), replenished two ways:

- **Per-POI trickle** — each cleared node returns a little supply (capped). More
  fights cleared = more attrition AND more repair capacity earned — self-matching.
- **Boss-kill surge** — refills supply to cap; the **cap may grow per sector** to
  match rising attrition.
- Two-tier replenishment (drip per POI + surge per boss): a player who burned
  repairs early isn't dead-ended, but can never infinite-repair.
- Per-POI supply slots alongside the per-POI completion bounty + ace progress —
  every mission feeds **money + supply + chain** at once.

OPEN: starting cap, per-POI trickle amount, per-sector cap growth, money cost per
repair/ammo charge.

---

## 5. Optional supply content — FAST-FOLLOW / flavor

- **Raid nodes** — an optional tougher node (mid-boss) that, cleared, infuses or
  raises the supply cap (still bought with money). Gives a freed POI slot real
  purpose; makes resupply an active choice. Content cost: a mid-boss. NOT v1-core.
- **Outpost attacks** — rare dynamic event, **reframed from pure denial to an
  agency-preserving objective:** "outpost under attack — clear this node to defend
  it, or it goes offline until the next boss." Lowest priority / flavor. (Straight
  "disabled for X nodes" is rejected: removes agency exactly when the player is
  hurt and needs the shop.)

---

## 6. Open decisions blocking the numbers pass

1. **Ratio** (§2.5): ace ≈ ½ item (+50% topping) vs ≈ 1 item (skill doubles).
2. **Hit penalty** (§2.6): halve vs reset-to-0.
3. **Ace flat vs multiplier** (§2.7) — recommended multiplier.
4. **Repair**: purchased item vs gated free (§3).
5. Then `economy-sim`: cap height, payout scale, supply numbers, price re-peg.
