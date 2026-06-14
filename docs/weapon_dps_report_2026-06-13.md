# Weapon DPS audit (2026-06-13) — regen + Shredder/Pulse Laser

Supersedes `weapon_dps_report_2026-06-11.md`. Regenerated from live Part data by
`tools/weapon_dps_report.gd` (reproducible — reads each CANNON primary via `PartCatalog`
and evaluates its `_mk_knobs()` curves, so multi-projectile / Callable-damage / cooldown-curve
weapons are correct without hand-correction). Raw numbers: `docs/weapon_stats.csv`.

Single-target DPS = per-projectile damage × projectiles/shot ÷ cooldown. INF = infinite ammo;
the rest are ammo-gated (lasers regen). **Numbers are point-blank/all-hit for the fan/pierce
weapons** — see caveats.

| Weapon | Slot | Mk.1 DPS | Mk.9 DPS | Ammo Mk1→9 | Notes |
|---|---|---:|---:|---|---|
| **Energy Blaster** | Blaster (∞) | 13 | **120** | ∞ | dmg 2→18, cd 0.15. The free starter — still the single highest Mk.9 DPS. |
| **Heavy Blaster** | Blaster (∞) | 15 | 100 | ∞ | dmg 6→30, cd 0.40→0.30. Slow 120-speed bolt, big per-hit. |
| **Twin Blaster** | Blaster (∞) | 17 | 83 | ∞ | dmg 2→10, cd 0.12, ±2px weave. |
| **Quad Lasers** | Primary (regen) | **33** | 100 | 90→250 | 4 bolts × (1→3) / 0.12. Wide 4-lane. |
| **Rotary Laser** | Primary (regen) | 20 | 100 | 120→360 | dmg 1→5 / 0.05 (20/s). |
| **Minigun** | Primary (ammo) | 25 | 25 | 1000→4299 | dmg **1** / 0.04 (25/s). Flat — weakest primary by far. |
| **Autocannon** | Primary (ammo) | **38** | 50 | 1000→4299 | dmg 5 fixed / 0.133→0.10. Best Mk.1, flat dmg → low Mk.9. |
| **Wave Gun** | Primary (ammo) | 17 | 52 | 250→83 | dmg 4→12 / 0.231 flat. **+ pierces up to 4** → much higher vs lines. |
| **Scatter Blaster** | **Blaster (∞)** | 20 | 47 | **∞** | dmg 2 × (3→7) fan / 0.30. *(was "Spread Cannon" / 500 ammo — now infinite-ammo blaster category.)* |
| **Auto Laser** | Primary (ammo) | 19 | 40 | 200→440 | dmg 3 / 0.162→0.076, alternating tandem. |
| **Shredder** | Primary (ammo) | **30** | **50** | 60→124 | dmg 1 × (6→10) pellets / 0.20. *(NEW in report)* Shotgun — point-blank max. |
| **Pulse Laser** | Primary (regen) | 33 | **33** | 100 flat | dmg 2 / 0.06 (16.7/s) hitscan. *(NEW in report)* Flat — Mk = accuracy window, not dmg. |

## What changed since 2026-06-11

- **`.import` fixed** — `docs/weapon_stats.csv` was being auto-imported as a *CSV translation*
  (Godot regenerated `.translation` files on every project open). Set `importer="keep"` so the
  report CSV is left alone.
- **Spread Cannon → "Scatter Blaster", now infinite ammo.** The 06-11 row (500→500 ammo) was
  stale; it's a Blaster-category infinite-ammo weapon now (`ammo_at_mark == -1`).
- **+ Shredder** (30→50, shotgun) and **+ Pulse Laser** (33 flat, hitscan) added.
- The other 9 numbers are unchanged from 06-11 (the generator reproduces them exactly).

## Findings — armory health

1. **The free Energy Blaster is still the top DPS weapon (120 @ Mk.9)** — out-DPSes every specialist
   primary on single targets while being infinite and dead-accurate. The fallback shouldn't also be
   the damage king. *(unchanged from 06-11)*
2. **There are now TWO strong free options.** Scatter Blaster is infinite-ammo too (20→47 + a 3→7
   fan). Energy owns single-target, Scatter owns free AoE. Good variety, but worth watching that the
   two no-cost picks don't crowd out the ammo-gated specialists.
3. **Three primaries scale backwards / flat:** Minigun (25 flat — far too weak), Autocannon (38→50,
   fixed dmg), and now **Pulse Laser (33 flat)**. Pulse's Mk identity is its accuracy window, not
   damage, so flat DPS is by-design — but by Mk.9 it sits near the bottom while blasters hit 83–120.
   Fine *if* the pinpoint-hitscan accuracy is the payoff; flag if it should also reward Mk investment.
4. **Shredder reads healthy as a shotgun** (30→50 point-blank, ammo-gated). Single-target falls off
   hard with spread/range — the table is its best case. Differentiated from the other primaries.
5. **The Blasters are well-separated** (120 / 100 / 83) with real trade-offs. The AoE/utility tier
   (Quad 100, Rotary 100, Wave 52+pierce, Scatter 47+fan, Shredder 50+spread, Auto-Laser 40) is in band.

## Recommendations (NOT applied — report only, your call)

- **Trim Energy Blaster's top end** so the free fallback isn't the DPS king: `dmg_per_mark` 2→1.5
  (Mk.9 ≈ 93) or cd 0.15→0.18 (Mk.9 ≈ 100). Target ~90–100, below the specialists.
- **Buff Minigun** — per-bullet 1→2 (50 DPS), or give it a non-damage utility hook (shred/stagger).
- **Give Autocannon a damage curve** — e.g. 5→12 over Mk (Mk.9 ≈ 120 at 0.10 cd) so investment pays.
- **Decide Pulse Laser's curve** — leave flat (accuracy is the reward) or add a small damage ramp.
- **Confirm Scatter Blaster's infinite ammo is intended** — it's a free fan now; if that's too strong
  alongside the free Energy Blaster, it could go back to ammo-gated.
- Leave Quad / Rotary / Wave / Heavy / Twin / Auto-Laser / Shredder as-is — differentiated, in band.

## Caveats
- **Single-target only.** Wave (pierce), Scatter/Quad (multi-lane fan), Shredder (6–10 pellets), and
  Minigun saturation are worth more vs grouped/lined enemies than the table shows. Shredder's 30–50 is
  point-blank with every pellet landing — realistic single-target is lower.
- Hyper mode multiplies primary damage/ROF on top of all of this.
- Re-run `tools/weapon_dps_report.gd` after any weapon `.tres`/Part change to refresh the CSV + table.

---

# Effectiveness beyond raw DPS (2026-06-13)

Raw single-target DPS assumes every shot lands and every Mk is reached. Three real-world factors
shift the picture (grounded in player bolt speeds + the enemy roster's HP/speed/size). Bolt speeds are
the live `.tscn`/script values; enemy speeds are the movement rungs (60/120/180/300/360 px/s); enemy
HP clusters at **1–2** (small chaff, 33 hulls), **8–14** (medium gunners, 20 hulls), **28–32+**
(large/huge capitals, 9 hulls); fast chaff crosses at **300–360 px/s**.

## A. Bullet speed → accuracy (effective hit-rate)

A bolt slower than a target's *lateral* speed gets out-run — the enemy leaves the firing column before
the shot arrives. This penalty **flattens against large/slow targets** (a capital at 60–120 px/s with a
big hitbox is easy to hit with anything), so slow bolts are only punished vs small fast movers.

| Weapon | Bolt speed | Accuracy | Lands reliably on | Discounted vs |
|---|---|---|---|---|
| Pulse Laser | **hitscan** | perfect | everything, incl. 360 reflex darts | (decays only if you *hold* fire — beam spreads) |
| Quad / Rotary / Auto Laser | 480 (8px/f) | very high | fast chaff, crossers, everything | — |
| Autocannon | 360 | high | fast chaff, mediums | — |
| Wave Gun | 600→300 | high→mid | lines (pierce); slows as it Mks up | — |
| Shredder | 300 | mid (pellets fan) | point-blank targets | anything at range / crossing |
| Energy · Minigun · Scatter | 240 (4px/f) | mid | holders, mediums, slow targets | **fast crossers (300–360 out-run the bolt)** |
| Twin Blaster | 180 | mid-low | slow / holding targets | movers |
| Heavy Blaster | 120 (2px/f) | low | **large slow capitals** (easy hit, big payoff) | all fast/small chaff |

**Upshot:** the table's "Energy Blaster = king" assumes hits. At 240 px/s it actually *misses* a chunk
of the fast-chaff roster, while the lasers (480 / hitscan) keep their full DPS vs everything. Effective
DPS-vs-the-actual-roster compresses Energy/Heavy down and lifts the lasers up.

## B. Mk reachability — the table is front-loaded in practice

Shop Mk cap = `min(9, 3 + 3×bosses_defeated)` ([outpost.gd:650](../scripts/outpost.gd)). A patrol is
~3 sectors, ~1 boss each:

| Where you are | Bosses killed | Mk cap you can buy |
|---|---:|---:|
| Sector 1 (most of the run) | 0 | **3** |
| Sector 2 | 1 | 6 |
| Sector 3 (final) | 2 | 9 |

Upgrades are **random shop offers** over only ~3 refreshes (stock rerolls on boss kill), so committing a
single weapon to Mk.9 needs the right offers + the bounty + luck — realistically a *final-sector* or
*endless-mode* outcome. **Players field Mk.1–4 for the bulk of a run.** Re-read the table at "realistic
Mk":

- **Flat / high-Mk.1 weapons win on value** you can actually field: Autocannon (38 @ Mk.1), Quad (33),
  Pulse Laser (33 flat), Shredder (30), Minigun (25 flat, never needs upgrades to stay relevant).
- **Scaling blasters underdeliver until late:** Energy (13 → 120), Heavy (15 → 100), Rotary (20 → 100)
  are *weak early* and only pay off if you fund them to a Mk most runs never reach. The free Energy
  Blaster being "too strong" is largely a **Mk.9/endless artifact** — early-run it's one of the weakest.

## C. Role / counter matrix

The CHARGE-shield rule matters here: a shielded enemy loses **one charge per hit regardless of damage**,
so *hits-per-second* strips shields, not damage-per-shot. High-ROF / multi-projectile weapons gut
shields; slow big-hit weapons waste damage per charge.

| Weapon | Excels at / counters | Weak against |
|---|---|---|
| **Energy Blaster** | mid-HP holders/gunners you can track; clean column once scaled | fast crossers (240 bolt); 1-HP swarms (single lane, overkill); needs Mk |
| **Heavy Blaster** | large slow capitals + armored (30/hit dwarfs flat armor cuts) | fast small chaff (120 bolt whiffs); swarms |
| **Twin Blaster** | early generalist, a touch better vs movers than Energy | armored / high-HP (low per-hit) |
| **Quad Lasers** | walls + crossers (4 fast lanes sweep); charge-shields (4 strips/volley) | lone capitals (only 1 lane hits → ~¼ DPS) |
| **Rotary Laser** | charge-shields + fast singles (20 fast hits/s); mediums | high-HP capitals (needs Mk; light per-hit) |
| **Minigun** | **charge-shields (25 hits/s = instant strip)**; 1-HP saturation | anything with HP or armor (dmg 1 → armor guts it); capitals |
| **Autocannon** | early-game bruiser; mediums (fixed 5/hit clears 2-HP, chunks 8-HP); accurate (360) | late capitals (no scaling); charge-shields (low ROF) |
| **Wave Gun** | descending columns / lined formations (pierce 4) | spread singles; fast crossers (pierce wasted) |
| **Scatter Blaster** | spread swarms + crossers (wide free fan); chaff walls | single big targets (fan mostly misses → ~1–2 pellets) |
| **Auto Laser** | accurate mid-DPS single; fast movers (480) | high-HP targets (mid DPS) |
| **Shredder** | one tough target at **point-blank** (a capital you close on) or a tight cluster | ranged / spread / fast enemies (pellets fan + miss); zoning |
| **Pulse Laser** | **fast evasive small chaff** (hitscan never misses); precise sniping | high-HP capitals (dmg 2, no scaling); long held bursts (accuracy decays) |

## Re-prioritized read (vs the raw-DPS findings above)

- **Energy Blaster is less of a problem than the raw table says** — its 120 needs Mk.9 *and* assumes
  hits at 240 px/s. A nerf is lower-priority; if anything, early-Mk Energy is *under*-powered.
- **Autocannon's "backwards scaling" is arguably fine by design** — it's an *early* weapon (best Mk.1),
  and players live in the early-Mk band. Flat damage is the cost of a strong, accurate start.
- **Minigun's fix is identity, not just numbers** — it's the anti-shield / saturation hose (25 hits/s).
  Lean into charge-strip / stagger utility rather than only bumping damage.
- **Pulse Laser's flat DPS is healthy** — hitscan is the answer to the fast evasive chaff every 240-class
  weapon misses, and flat scaling fits a random-upgrade economy (it never needs a Mk it can't reach).
- **The fan/pierce weapons (Wave/Quad/Scatter/Shredder) read low single-target but are the wave-clear
  tier** — their value is the part the DPS table structurally can't show.
