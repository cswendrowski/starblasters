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
