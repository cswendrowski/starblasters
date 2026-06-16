**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: docs/m6b_faction_tagging_2026-06-06.md + scripts/levels/wave_generator.gd.
Kept for design history; do not cite as the live spec.

# Wave Streaming, Density & Variety — Design Spec (in progress)

> **CANONICAL SUPERSEDER:** `docs/combat_lane_wave_bridge_2026-06-03.md` unifies
> this spec with the lane-system spec. Where they conflict, **the bridge wins.**
> Key reconciliations the bridge applies on top of this doc: the spawn texture is
> **composed formations + filler trickle + breathers** (not a pure dribble — see
> bridge §1–2), budget is **composition-first with flexible totals** (bridge §4),
> and "row (lane)" map terminology is retired in favor of **route** (bridge §0).

Status: **design / not built**. Captures decisions from the 2026-06-03 design
conversation on combat-level enemy *volume*, *pacing*, *variety*, and *visual
identity*. Companions:
- `docs/lane_system_spec_2026-06-03.md` — enemy *movement* / lane choreography.
- `docs/economy_spec_2026-06-03.md` — bounty / ace-chain / outpost / supply
  (split out so wave gen stands alone; economy balancing comes after).

Nothing here is implemented yet. **§10 is the open-work list** — the parts that
still need design before this is buildable.

---

## 0. Evidence base (measured, not guessed)

Two headless Monte-Carlo sims were built to ground these decisions. Both are
committed and reproducible:

- `tools/sim_wavegen.gd` — drives the real `WaveGenerator` internals across
  every `(sector_depth, level_index)` coordinate, 3000 trials each, reporting
  total enemies/level, peak single-wave count, and wave count.
  Run: `godot --headless -s tools/sim_wavegen.gd -- 3000` → writes `sim_out.txt`.
- `tools/sim_stream.gd` — pacing model for the proposed streaming director;
  sweeps concurrency-cap × spawn-cadence × player-kill-rate.
  Run: `godot --headless -s tools/sim_stream.gd` → writes `sim_stream_out.txt`.

### 0.1 Current per-level distribution (today's clear-gated generator)

| coordinate | total p50 | total max | peak/wave (max) |
|---|---|---|---|
| sector 1, node 1 (sd1/li0) | 18 | 21 | 12 |
| sector 1, mid (sd1/li3–4) | 47–48 | 78 | 20 |
| deep (sd5/li6) | 27 | **62** | 20 |
| boss (sd1) | 9 | 19 | 13 |
| boss (sd3+) | 17–18 | 40 | 15 |

Three findings that drive the redesign:

1. **Real per-level headcount is ~18–48 (p50), absolute ceiling ~62.** The
   earlier hand-estimate of "~72 typical" was too high — tier rolls + the
   `clamp(count, 1, base*2+cb)` ceiling
   ([`wave_generator.gd:439`](../scripts/levels/wave_generator.gd)) cap growth.
   **300/level is ~6× the p50 and ~5× the luckiest roll — structurally
   unreachable by tuning the current dials.**
2. **Headcount is non-monotonic: it PEAKS at node 3–4 then DECLINES.** Deeper
   into a sector / higher sectors shift tier weights toward UNCOMMON/RARE, which
   have tiny `base_count` and get no chaff bonus. Today "deeper" = *fewer,
   tankier* enemies — and a visibly emptier screen. This inverts goal #3.
3. **Peak concurrency is hard-capped at ~20** (dart `base*2+cb` = 16+4); p50
   concurrency is 8–16. That's the clarity-safe number the clear-gate currently
   guarantees.

### 0.2 Sector structure (for per-sector budgeting)

- 3 rows (lanes), each = 3–5 POIs + 1 boss at the right endpoint.
- **You must clear every POI in all 3 rows AND all 3 bosses** — not a
  pick-one-path map (`run_state.gd` `is_sector_complete` / `is_row_pois_complete`).
- Per sector: 9–15 POIs + 3 bosses = 12–18 nodes. Outposts clamped to 2–3.
- Typical path into combat (`main.tscn`): ~5–6 combat + ~2–3 hazard + 3 boss
  nodes; plus ~2–3 outpost and ~1 signal (non-combat).

---

## 1. Streaming combat model — LOCKED

**Decision (Roman, 2026-06-03):** keep **5–8 waves per level**, but each wave is
a **continuous stream** of enemies governed by a **concurrency cap**, not the
current spawn-batch-then-clear-gate. This is the genre-authentic shmup shape:
waves remain the *compositional* unit (distinct enemy mixes, banners), spawning
becomes a trickle.

### 1.1 Director behavior (replaces the clear-gate)

- Spawn from a wave's budget **while `live_combatant_count < max_concurrent`**.
- A wave **advances when its spawn budget is exhausted** (not when the screen
  clears), so the 5–8 waves *blend* into one stage-length stream.
- Banners become **non-blocking** wave markers (they no longer halt spawning).
- The existing silent-sub-wave chaining
  ([`director.gd:82`](../scripts/levels/director.gd)) is the seed of this; the
  clear-gate `_wait_for_clear_then_advance` is removed/replaced.

### 1.2 Spawn governance — density-targeting, NOT fixed cadence — RECOMMENDED

`sim_stream.gd` shows a **fixed `spawn_interval` is bistable**: the same level is
either sparse or saturated depending on the *player's* kill rate, with almost no
middle ground. Example (cap 16, interval 0.45s): a 2.0/s player sees a full
screen of 16; a 3.0/s player sees **mean 0.7 on screen** — identical content,
totally different game.

**Fix: spawn whenever `alive < cap`, with a small anti-burst floor (~0.20s).**
This decouples on-screen density from player skill/build:

| player kill rate | duration | mean on screen (cap 15) |
|---|---|---|
| 2.0/s | 150 s (2.5 min) | 14.3 |
| 3.0/s | 100 s (1.7 min) | 14.0 |
| 4.0/s | 75 s (1.25 min) | 13.1 |
| 5.0/s | 60 s | sparse (outpaces the 0.20s floor) |

Screen stays consistently ~14 full; **level duration self-adjusts to
`budget / kill_rate`**; peak concurrency can never exceed the cap *by
construction*. The floor's implied ceiling (1/floor) is the only escape — raise
it if a god-build goes sparse.

### 1.3 Starting parameters (first-pass, tune in a tuner)

- `max_concurrent`: **15**, ramping ~12 (early) → ~16 (deep). Below today's peak
  of 20 → clarity-safe and perf-predictable.
- anti-burst floor: **0.20 s**.
- Level budget: **see §2** (targets ~300).
- Implied level length: **~1.25–2.5 min** of combat per node.

---

## 2. Budget allocator — LOCKED (shape) / OPEN (curve)

Replace the per-wave `clamp(count, 1, base*2+cb)` ceiling with a **level budget
allocator**:

- A level has a total enemy budget **`B(sector_depth, level_index)`**, target
  **~300** at a mature node, split across the 5–8 waves.
- Each wave's `count` = its share of `B`. The tier/mixing/formation logic is
  **kept** — it decides *what* spawns and the per-enemy HP/role, it just no
  longer caps the count.
- `B` ramps so a fresh sector opens lighter (e.g. ~150–200 at node 1) and builds
  toward ~300; deep/endless creeps a ceiling (~350?).

**OPEN:** the exact `B(sd, li)` curve, the per-wave split (front-light vs even
vs back-heavy), and the deep ceiling. To be set with `sim_wavegen.gd`
instrumentation, not by feel.

---

## 3. Difficulty curve — fixes the headcount inversion — LOCKED (intent)

Goal #3 ("harder as you go deeper, bosses hardest") currently inverts late
(finding §0.1.2). With the budget allocator, difficulty becomes an **authored
curve** instead of an emergent side effect:

- **Budget grows with depth** (more enemies, not fewer).
- **Elite fraction grows with depth** — reserve an increasing slice of `B` for
  UNCOMMON/RARE, *layered on top of* a chaff floor that keeps scaling. Deeper =
  more chaff AND more elites AND denser screen.
- **`max_concurrent` ramps slightly** (12 → 16) for escalating pressure.
- **Boss levels = a budget spike + the boss**, sitting clearly above standard
  nodes.

---

## 4. Variety & progression goals — TARGETS

The five stated goals (Roman, 2026-06-03), with the mechanism for each.

### 4.1 Goal: not fighting the same 3–4 enemies each level
- **Problem is concentrated at the sector-1 opener.** At (sector 1, node 1) the
  tier roll is 100% COMMON and only **3** COMMON entries are unlocked (dart,
  bomb_drone, drifter). Every first node of every run is 2-of-those-3.
- Mid/late pools are fine (10–15 eligible). Streaming *helps automatically*
  (more wave-slots → more picks → more of the pool surfaces per level).
- Levers: widen the opener pool; revive weighted selection (§7.1); factions
  multiply *apparent* variety at the opener (§6).

### 4.2 Goal: see new enemies regularly (~one new a level)
- **Not currently designed — unlocks cluster** (sector 2 unlocks ~7 entries at
  once). No "debut" pacing or spotlight.
- **Mechanism:** an explicit **introduction schedule** — an ordered list of
  enemy debuts keyed to *global combat-node count*; the allocator reserves a
  budget slice for "the next un-introduced type" each level (ideally a clean
  debut wave + codex ping). Factions add a *second* debut track (§6).

### 4.3 Goal: harder deeper, bosses hardest
- See §3. Resolved by budget + elite-fraction + concurrency ramp.

### 4.4 Goal: each patrol's sector a little different
- **Macro already true** (map layout, modifiers, boss roster are run-seeded).
- **Micro surprisingly false:** per-node combat is seeded by `(sd, li)` ONLY —
  `_stable_seed = sd*100003 + li*7919`
  ([`wave_generator.gd:119`](../scripts/levels/wave_generator.gd)) — so the
  *fights* repeat run-to-run even as the *layout* shuffles.
- **Highest leverage-to-cost item on the list:** fold `Run.run_seed` into
  `_stable_seed`. "Sector 1 node 2" then rolls different enemies/formations every
  patrol. Keep it seeded-per-node so *retries of the same node* stay stable —
  just mix the run seed in. See §7.2.

### 4.5 Goal (optional): each row a distinct personality
- Best implemented as **faction-per-row** (§6.4). Cleaner than ad-hoc per-row
  modifiers and amplifies goals 4.1/4.3/4.4.

---

## 5. Economy → split to its own doc

The earning/spending/supply/ace-chain model moved to
**`docs/economy_spec_2026-06-03.md`** so wave generation can proceed
independently; economy *balancing* is deferred until wave gen is settled.

One piece stays wave-gen-relevant — the **sector-composition change**: the
outpost is **retired as a POI node type** (pulled from `_roll_poi_type` in
`run_state.gd`, becomes a persistent hub), freeing **2–3 POI slots/sector** that
redistribute to **combat / hazard / signal / special**. That raises combat-node
frequency per sector and is an input to §2's per-sector budgeting and §4's
variety pacing. The `_roll_poi_type` weight rework is tracked in §10.7.

---

## 6. Faction / color identity system — PROPOSED

**Origin (Roman, 2026-06-03):** enemies already cluster into ~4 colors (red,
green, orange, purple). Proposal: sprite-swap *faction variants* of core chassis
("corporate" green dart, "mercenary" orange dart) — variety & identity via art,
not density.

### 6.1 The strategic decision: color MUST mean something — RECOMMENDED
Color is a threat language; spending it on pure cosmetic noise trains players to
ignore it. The high-value model is **two orthogonal axes**:

- **Silhouette = behavior** (the chassis — dart dives, weaver s-curves).
- **Color/faction = a consistent stat-and-posture modifier** applied across
  every chassis it touches.

`N` chassis × `M` factions = `N×M` apparent enemies, but only `N + M` small
alphabets to learn. Multiplies variety *and* readability simultaneously, and
adds the mechanical variety pure skins wouldn't.

### 6.2 Faction roster (first-pass)
- **Military (red)** — baseline / default posture.
- **Corporate (green)** — defensive: +shield charge / damage-reduction.
- **Supremacy (purple)** — elite/aggressive: faster fire, tighter patterns, +bounty.
- **Mercenary (orange)** — fast & greedy: higher speed, flees/recycles, big bounty.

Keep faction stat-deltas **small and consistent** — flavor + minor tactical
adjustment, not a balance minefield. The primary threat axis stays chassis
(behavior) + tier (HP/role).

### 6.3 Implementation is nearly free on the code side
A faction = a **named bundle of `sector_modifiers` + a palette**. The per-spawn
modifier apply path already exists
([`director.gd:253`](../scripts/levels/director.gd) — shielded/armored/
aggressive/wanted/fleeing). No new combat machinery; you're naming a
configuration of existing machinery.

### 6.4 Synergies
- **Goal 4.5 (row personality):** faction-per-row (Row A Corporate wall, Row B
  Supremacy, Row C Mercenary). Pick a lane = pick a fight flavor.
- **Goal 4.4 (per-patrol difference):** run-seed *which faction holds which
  row/sector*.
- **Goal 4.2 (new enemy cadence):** a second debut track ("first green at node
  3, first purple at sector 2") doubles the steady-new without new behavior code.
- **Goal 4.1 (opener variety):** the 3-chassis opener becomes red/green/orange
  variants — 3–4× apparent variety exactly where it's thinnest.

### 6.5 Art cost — likely less than feared
- Enemies **already** cluster into these colors → formalizing latent structure,
  not inventing it; much of the work is re-tagging.
- **A hue-shift / palette-swap shader prototypes (and maybe ships) most of it at
  near-zero art cost.** Hand-draw bespoke variants only for *hero* enemies; let
  the shader cover the long tail. Validate the whole system before committing to
  ~60–80 hand-drawn sprites.

### 6.6 Cautions
- **Commit to ONE meaning for color** (faction-modifier) and never break it.
- **Palette audit required** before drawing: 4 faction colors must stay distinct
  from bullets, hit-flash, damage overlays, pickups, boss telegraphs — in a
  480×270 pixel-art frame. Storyboard the full on-screen palette first.
- **This is a breadth + identity + readability tool, not a depth tool.** It adds
  no new patterns/movement. Expectation: "the enemies we have feel like a living,
  factioned world," not "more enemies."

---

## 7. Findings to action (independent of the big rework)

### 7.1 Per-entry `weight` is dead in production — RECOMMENDED FIX
`_pick_entry` uses `Roster.entries_eligible`
([`enemy_roster.gd:526`](../scripts/levels/enemy_roster.gd)), which returns each
eligible entry **once** and **ignores `weight`**. Selection within a tier is
uniform. The `weight` field is only read by `eligible_pool`
([`enemy_roster.gd:485`](../scripts/levels/enemy_roster.gd)), which production
never calls. Same for the `chaff: true` flag. Reviving weighted selection
unblocks tuning for goals 4.1–4.3 (keep basics frequent, long tail rare).

### 7.2 Per-node combat is run-invariant — RECOMMENDED FIX
See §4.4. Fold `Run.run_seed` into `_stable_seed`. Cheapest large variety win.

---

## 8. Deferred / open

- **Economy** lives in `docs/economy_spec_2026-06-03.md` (model locked, numbers
  pending). Its only wave-gen-facing dependency is the sector-composition change
  (§5) and faction bounty deltas (§6).
- **Perf.** Streaming *caps* peak concurrency (~15) below today's ~20, so it
  should be *safer*; confirm with `perf-runner measure` at sustained
  cap+bullets.
- **+HP-per-clear / sector damage scaling** interact with restored chaff
  scaling; re-audit the difficulty curve at 300-volume.
- **Codex** under factions: color = modifier legend + silhouette = behavior
  legend (two-axis), vs per-variant entries.
- **`B(sd, li)` curve, per-wave split, deep ceiling** (§2) — set via
  `sim_wavegen.gd` instrumentation.
- **Sim instrumentation TODO:** extend `sim_wavegen.gd` to report
  distinct-types-per-level and first-seen-node-per-type so goals 4.1/4.2 get
  numeric targets (e.g. "≥4 distinct types/level after node 2", "new type every
  ≤1.3 nodes").

---

## 9. Suggested sequencing

1. **Cheap, high-leverage now:** run-seed into node seed (§7.2); revive weighted
   selection (§7.1).
2. **Close the §10 open-work items** (the wave→stream data model, spawn
   placement / lane handoff, in-stream variety) — needed before the rework is
   buildable.
3. **Streaming + budget rework:** density-targeting director (§1), budget
   allocator (§2), authored difficulty curve (§3). Economy is a parallel,
   separately-specced track (`economy_spec`).
4. **Variety layer:** enemy introduction schedule (§4.2), widened opener (§4.1).
5. **Faction system (§6):** prototype with tint shader first; faction-per-row
   (§4.5) and run-seeded faction assignment (§4.4).

---

## 10. Open work — what still needs design before this is buildable

§1–4 lock the *direction*; these are the parts a programmer would hit a wall on.
Ordered roughly by how blocking they are.

### 10.1 The wave→stream data model — BLOCKING
The single biggest gap. Streaming changes what a "wave" *is*; pin it down:
- **What replaces `WaveSpec.count`?** A wave is now a **budget segment** with a
  composition, not a fixed batch. Define the new resource shape (budget share +
  enemy mix + formation/lane hints + tier/faction).
- **Wave-count rule** for 5–8 (replacing `clamp(2+li, 2, 5)`): fixed? depth-
  scaled? And **how `B` splits across waves** (front-light / even / escalate).
- **Level-complete condition changed.** Today: all waves spawned + screen clear
  ([`director.gd:284`](../scripts/levels/director.gd)). Streaming: **budget
  exhausted + screen clear**, with waves blending (no per-wave clear-gate).
  Restate it precisely, including how `level_cleared` fires.
- **Where the concurrency cap lives** (level/allocator vs director constant) and
  how the depth ramp (12→16) is threaded in.

### 10.2 Spawn placement & the lane-conductor handoff — BLOCKING
Today's `Formation` enum interpolates X across the band for a batch of N
([`director.gd:178`](../scripts/levels/director.gd)) — that **doesn't translate
to a trickle**. Decide the boundary with the lane spec
(`lane_system_spec_2026-06-03.md`):
- Does wave gen emit *positions/formations*, or just **(type, faction, budget,
  cadence)** and the **lane conductor** owns placement? (Recommended: the latter
  — wave gen = "what & how many over time", conductor = "where & how it moves".)
- What does a streamed enemy's entry look like (lane assignment, side-spawn,
  formation-as-a-burst-within-the-stream)?
This is the seam between the two specs and must be drawn explicitly.

### 10.3 In-stream variety / mixing — BLOCKING for goal 4.1
The current 2-sub-wave mix ([`wave_generator.gd:146`](../scripts/levels/wave_generator.gd))
is a batch concept. Define how **multiple enemy types coexist in a continuous
stream**: concurrent type-variety (the cap holds a mix at once) vs sequential
single-type bursts, and how the affinity/conflict tables carry over. This is
where "≥4 distinct types/level after node 2" (§8 sim TODO) actually gets built.

### 10.4 Enemy + faction introduction schedule — design needed (goal 4.2)
§4.2 names the mechanism but not the data: the **ordered debut list** keyed to
global combat-node count, how the allocator **reserves budget for the debut**,
the **debut presentation** (clean solo burst? codex ping? telegraph?), and how
the **two tracks** (chassis debuts + faction debuts, §6) interleave so it's ~one
new thing/level without clustering.

### 10.5 Hazard & boss levels under streaming — decision needed
- **Hazard levels** (minefield/asteroid) are fixed-count and bypass `WaveGen`
  today (`levels_v2.gd`: asteroid = hard 73, minefield ~30–115). Do they adopt
  density-streaming for consistency, or stay bespoke? (Lean: keep bespoke, but
  give them the same concurrency-cap governance for clarity.)
- **Boss lead-ins** need the streaming treatment: lead-in budget, cap, and the
  hand-off into the boss (today: `n_leadin` waves + boss,
  [`wave_generator.gd:250`](../scripts/levels/wave_generator.gd)).

### 10.6 System interactions — easy to miss, will bite
- **Recycling vs the cap & clear-gate.** The director already special-cases
  `is_recycling()` enemies in the advance gate
  ([`director.gd:297`](../scripts/levels/director.gd)) — define whether recyclers
  count toward `max_concurrent` and toward the budget-exhausted/clear condition.
  (See the recycling-system direction.)
- **Faction modifiers vs per-POI `sector_modifiers` stacking.** Factions reuse
  the same apply path (§6.3); a POI that's *also* rolled "shielded" must not
  double-apply. Define precedence/stacking.
- **`+HP-per-clear` and ×1.05/sector damage scaling** at 300-volume — the
  difficulty curve (§3) must account for these or they compound.

### 10.7 Node-type roster rework — needed for §5 sector change
Drop `OUTPOST` from `_roll_poi_type` (`run_state.gd`), redistribute the 4:2:2:1
weights across combat/hazard/signal/**special**, define what **special** nodes
are, and re-derive per-sector combat-node frequency (feeds §2 budgeting).

### 10.8 Determinism — keep it debuggable
Fold `run_seed` into the node seed (§7.2) **without** losing per-node
reproducibility — the streamed generator must still produce an identical level
for a given (run, node) so bugs are reproducible and the sims stay valid.

### 10.9 Tooling & rollout — process
- **A stream/wave tuner is required** (CLAUDE.md contract: 3+ knobs → tuner).
  Knobs: cap, floor, `B` curve, wave split, mix rate, intro cadence, ramp. Extend
  the existing Wave Tester / `wave_editor.gd` or scaffold a new one — with a Copy
  GDScript button.
- **Rollout:** replace `WaveGen` wholesale vs behind a flag for A/B against the
  current generator (the director changes are invasive).

### 10.10 UX / telegraphing — cross-ref `ux-design`
Banners are now **non-blocking** (§1.1) — so how does the player read an incoming
new wave / elite / faction shift mid-stream? Needs a telegraph language that
doesn't halt the flow. And the **perf** note (§8): sustained spawning likely
wants enemy/bullet **pooling**.
