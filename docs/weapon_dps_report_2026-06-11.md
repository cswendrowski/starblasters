# Weapon DPS audit & armory health (2026-06-11)

Single-target DPS = (damage per projectile × projectiles per shot) ÷ cooldown, computed live from the
Part data via `PartCatalog._make_by_name` at Mk.1 and Mk.9. INF = infinite ammo (Blaster slot); the rest
are ammo-gated (lasers regen). **Multi-projectile / Callable-damage weapons corrected by hand** (the
auto-harness reads only the linear curve) — flagged below.

| Weapon | Slot | Mk.1 DPS | Mk.9 DPS | Notes |
|---|---|---:|---:|---|
| **Energy Blaster** | Blaster (∞) | 13 | **120** | dmg 2→18, cd 0.15. The free starter — and the single highest Mk.9 DPS. |
| **Heavy Blaster** | Blaster (∞) | 15 | 100 | dmg 6→30, cd 0.40→0.30. Slow 120-speed bolt; big per-hit. |
| **Twin Blaster** | Blaster (∞) | 17 | 83 | dmg 2→10, cd 0.12, medium bolt, ±2px weave. |
| **Quad Lasers** | Primary (regen) | **33** | **100** | 4 bolts × (1→3) / 0.12. Wide 4-lane; ammo-gated. *(corrected — 4-bolt)* |
| **Rotary Laser** | Primary (regen) | 20 | **100** | dmg 1→5 / 0.05 (20/s). *(corrected — Callable curve)* |
| **Minigun** | Primary (ammo) | 25 | 25 | dmg **1** / 0.04 (25/s). Flat — the weakest primary by far. |
| **Autocannon** | Primary (ammo) | **38** | 50 | dmg 5 fixed / 0.133→0.10. Best Mk.1, flat scaling → low Mk.9. |
| **Wave Gun** | Primary (ammo) | 17 | 52 | dmg 4→12 / 0.231 flat. **+ pierces** up to 4 → much higher vs lines. |
| **Spread Cannon** | Primary (ammo) | 20 | 47 | per-bullet; fires a fan (×N bullets) — high area, lower single-target. |
| **Auto Laser** | Primary (ammo) | 19 | 40 | dmg 3 / 0.162→0.076, alternating tandem bolts. |

## Findings — armory health

**1. The free Energy Blaster is the top DPS weapon (120 @ Mk.9).** It out-DPSes every specialist primary
on single targets, while being infinite and dead-accurate (fast 240 bolt, pinpoint column). There is little
mechanical reason to ever leave it except for AoE/pierce. The fallback weapon shouldn't also be the damage
king.

**2. Minigun is far too weak (25 DPS flat).** Damage 1 × 25/s = 25 — half the next-weakest and a fifth of
the blasters. It reads as a "hose" but does almost nothing. Either it's a deliberate suppression/utility
tool (then it needs a non-damage payoff) or it needs more per-bullet.

**3. Autocannon scales backwards relative to the field.** Best Mk.1 DPS (38) but its damage is fixed (5),
so by Mk.9 (50) it's near the bottom while everyone else has tripled. Its identity (spin-up burst) is fine;
the flat damage curve is the issue.

**4. The three Blasters are well-separated** (120 / 100 / 83) with real trade-offs (Energy = precise & fast;
Heavy = punchy & slow; Twin = rapid & weaving). Good — except Energy topping the chart (see #1).

**5. The AoE/utility primaries (Quad, Wave, Spread, Rotary)** land 40–100 single-target but bring width /
pierce / regen. Quad (100, 4-lane) and Rotary (100, 20/s) are the strong picks; Wave (52 + pierce) and
Spread (47 + fan) are fair given their area value. This tier looks healthy.

## Recommendations (NOT applied — report only, per Roman)

- **Trim Energy Blaster's top end** so the free fallback isn't the DPS king. Options: `dmg_per_mark` 2→1.5
  (Mk.9 = 14 → ~93 DPS), or cooldown 0.15→0.18 (Mk.9 ~100). Target ~90–100 so it sits *below* the
  specialist primaries but stays a viable fallback.
- **Buff Minigun** — per-bullet 1→2 (50 DPS) makes it a real low-mark hose without touching its huge ammo
  pool; or give it a utility hook (armor-shred / stagger) if it's meant to stay damage-light.
- **Give Autocannon a damage curve** — e.g. dmg 5→12 over Mk so its Mk.9 (~120 DPS at 0.10 cd) rewards
  investment like the others, keeping the spin-up as its cost.
- Leave Quad / Rotary / Wave / Spread / Auto-Laser / Heavy / Twin as-is — they're differentiated and in band.

## Caveats
- Single-target only. Wave (pierce), Spread/Quad (multi-lane), and the minigun's saturation are worth more
  vs grouped/lined enemies than the table shows.
- Hyper mode multiplies primary damage/ROF on top of all of this.
- Numbers are live as of this commit; re-run the harness in `/docs` history if Part data changes.
