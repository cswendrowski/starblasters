# Shift-Mode System — Design + Development Scope

**Date:** 2026-06-08
**Status:** ✅ design settled · ✅ BUILT (Phases 1–5, 2026-06-08) · magnitudes first-pass (tuner job)

**Build status (2026-06-08):** Phases 1–5 landed + headless-verified
(`tools/test_shift_mode_phase{1,2,4}.gd`, `test_shift_mode_hud.gd`).
- ✅ P1 slot + ModeParts · ✅ P2 Hyper/Phase runtime · ✅ P3 HUD meter ·
  ✅ P4 outpost purchase · ✅ P5 Hangar slot + docs.
- ⏳ **Remaining:** signal-event mode *finds* (needs an event-design call — new
  "stance module cache" vs broaden a salvage event); magnitude tuning (first-pass
  numbers in §3, do via the Hangar); and Roman's in-combat **visual** verification
  (HUD meter, mode feel) — blocked until combat boots (`bulwark.gd` other-session WIP).
**Supersedes:** `docs/supers_modes_modules_2026-06-05.md` (the "Mode Energy" spec) — that
doc's complexity (a separate earned Mode-Energy gauge, ace-chain coupling, focus-save
dual-hitbox, unified recharge spine) is **dropped** in favor of the simpler per-mode
resource models below.

---

## 1. Summary

Two independent player abilities, cleanly separated:

- **SUPER** — one button (**X**), one ability: **Smart Bomb**. The panic button. **There are
  no other supers.** Hyper and Phase are *removed* from the super system. Smart Bomb is
  unchanged. Bought-charge pool, refilled at outposts (as today).
- **SHIFT MODE** — one slot (**Shift**), one-of-N stance. **Always starts with Focus.** Buy/find
  **Phase** or **Hyper** to swap the default Focus out. Exactly one mode occupies the slot at a
  time; activating it is the Shift action.

This is the **stance axis** the Hangar already *labels* but doesn't yet *implement* —
today Hyper/Phase are DEVICE_BAY_1 fire-once supers on X, and Focus is hardcoded ship
behavior unrelated to them. This spec makes the stance axis real.

---

## 2. The Shift-Mode slot

- A new slot type: **`SHIFT_MODE`**. Holds exactly one `ModePart`.
- **Default-equipped: Focus.** The slot is never empty — a fresh ship starts with the Focus
  mode part. (Focus's *behavior* already exists and works; this just makes it a swappable
  mode rather than baseline ship code.)
- **Acquisition:** Phase / Hyper are bought at outposts or granted by signal events. Equipping
  one **replaces** whatever mode is in the slot; the displaced mode goes to storage (so the
  player can swap back to Focus). Standard `Run.equip_part` slot semantics.
- **Activation:** all three modes use the existing **`focus`** input action (Shift). The
  *semantics* of the press depend on the active mode (held vs press, see each mode). Only one
  mode exists in the slot, so there's no ambiguity.
- **Mark scaling:** modes carry Mk.1–9 like any Part; per-mode scaling below.

---

## 3. The three modes

### 3.1 Focus (default — already built, unchanged)
- **Effect:** 0.55× move speed, tight hitbox dot + cyan glow/trail, intangible-feel precision
  dodging. (`player.gd` FOCUS_FACTOR / `_update_focus_dot` / focus VFX — keep as-is.)
- **Activation:** **held** Shift.
- **Resource:** continuous **seconds-reserve** — `focus_charge` 10.0s, drains 1.0/s while held,
  regens 1.0/s after a short idle delay. (Exists today: `focus_charge`, `FOCUS_REGEN_DELAY`.)
- **Mk scaling:** unchanged from today (none specified — leave as-is unless tuned later).
- **Work:** re-home it onto the mode slot as a `ModePart` whose behavior is the existing focus
  code, gated behind "active mode == FOCUS". No behavior change.

### 3.2 Phase
- **Effect:** **intangible** — identical dodge effect to Focus (passes through bullets +
  enemies, takes no hits) **but with NO dot/trail and NO speed reduction**. Lasts a **short
  fixed duration** per activation. While active the player **cannot hit bullets or enemies**
  (purely defensive — no offense, no bullet-clear). When it ends, tangibility returns.
- **Activation:** **press** Shift → fires a fixed-duration intangibility burst, consuming **one
  charge**. (Holding does not extend it.)
- **Resource:** discrete **charges**, replenished **by killing enemies** (NOT by time). No idle
  regen — you earn Phase windows by being aggressive.
  - First-pass: **base 2 charges**, **+1 charge per 4 enemy kills** (capped at max). *(tunable)*
- **Mk scaling:** **alternate +1s duration / +1 charge** per Mk.
  - Base (Mk1): **1.5s duration, 2 charges**. *(tunable)*
  - Even Mk (2,4,6,8) → **+1.0s duration**; Odd Mk >1 (3,5,7,9) → **+1 max charge**.
  - ⇒ Mk9 ≈ 5.5s / 6 charges.
- **Differentiator from Smart Bomb:** Phase has **no bullet-clear and no damage** — it's a
  *repositioning dodge*, not a panic clear. (This is the explicit design intent; today's
  `phase_shift.gd` wrongly clears all bullets — that must be removed.)

### 3.3 Hyper
- **Effect:** while active, primary fire is **+10% faster** and has **unlimited ammo** (metered
  weapons don't deplete). No invulnerability, no damage mult at base. A *sustain/uptime* buff,
  not a nuke. (Today's `hyper_mode.gd` wrongly gives 2× damage + full invuln + uncapped
  per-frame fire — all of that is replaced by the +10%/unlimited-ammo model.)
- **Activation:** **held** Shift (active while held), same feel as Focus.
- **Resource:** a **Focus-style charge bar** that **recharges only while NOT in use**, and
  **cannot be activated until fully recharged** (no tapping — you commit the whole bar, then
  wait for a full refill before re-engaging).
  - First-pass: **bar = 4.0s of active uptime**, drains 1.0/s while held, recharges **0.8/s**
    while idle (~5s to refill), **activation gated on bar == full**. *(tunable)*
- **Mk scaling:**
  - **Odd Mk (1,3,5,7,9): increase the fire-rate boost.** Base Mk1 = +10%; each further odd Mk
    adds **+5%** (Mk3 15%, Mk5 20%, Mk7 25%, Mk9 30%). *(tunable increment)*
  - **Even Mk (2,4,6,8): add a stacking +10% damage boost** (Mk2 +10%, Mk4 +20%, Mk6 +30%,
    Mk8 +40%). *(tunable)*

> All first-pass numbers above are placeholders to make the build runnable; final magnitudes
> come from a tuner (see §6) per the CLAUDE.md "human-iterated" rule.

---

## 4. What changes vs. today (the reclassification)

| Thing | Today | After |
|---|---|---|
| Supers in the game | Smart Bomb, Hyper, Phase (3 DEVICE_BAY_1 parts share one slot) | **Smart Bomb only** |
| Hyper / Phase | DEVICE_BAY_1 supers, fire-once on **X**, bought super charges | **SHIFT_MODE mode parts**, on **Shift**, own resource models |
| Focus | hardcoded ship behavior (Shift), not a part | a **ModePart** (default-equipped) wrapping the same behavior |
| Hyper effect | 2× damage + full invuln + uncapped fire | **+10% fire + unlimited ammo** (Mk adds fire/damage) |
| Phase effect | invuln + clears ALL bullets + can still shoot | **intangible dodge, no clear, no offense** |
| Hyper/Phase resource | bought super charges | Hyper: focus-style bar (full-gated); Phase: kill-earned charges |
| Death-bomb auto-fire | Smart Bomb / Hyper / Phase all eligible | **Smart Bomb only** (modes aren't supers) |

---

## 5. Development scope (architecture + file-by-file)

### 5.1 New slot + Part hierarchy
- **`scripts/weapons/SlotTypes.gd`** — add `SHIFT_MODE` enum value + `slot_name`.
- **`scripts/parts/mode_part.gd`** (new) — `ModePart extends Part`, `slot_type = SHIFT_MODE`.
  Carries a `mode_id` (FOCUS / PHASE / HYPER enum) + per-mode tunables (durations, charges,
  rates) scaled by `mark`. `apply(ship)` sets the ship's `active_mode` + pushes its params;
  `unapply(ship)` resets to Focus defaults.
- **`scripts/parts/focus_mode.gd`** (new) — `mode_id = FOCUS`; no new params (behavior already
  in player). The default-equipped mode.
- **`scripts/parts/phase_mode.gd`** — rewrite of `phase_shift.gd`: `ModePart`, sets duration +
  max charges by Mk, kill-replenish config. **Drop the super_part base + the bullet-clear.**
- **`scripts/parts/hyper_mode.gd`** — rewrite: `ModePart`, sets fire-rate boost + damage stacks
  + bar size by Mk. **Drop the super_part base, the 2× damage, the invuln, the X trigger.**
- **`scripts/parts/part_factory.gd` / `part_catalog.gd`** — register `_make_focus_mode` /
  `_make_phase_mode` / `_make_hyper_mode` under SHIFT_MODE; **remove** Hyper/Phase from the
  DEVICE_BAY_1 pool. (Smart Bomb + Drone Swarm unaffected — Drone Swarm is HARDPOINT_WING.)

### 5.2 Player runtime (`scripts/player.gd`)
- Add `active_mode: int` (enum, default FOCUS), set by the equipped ModePart's apply/unapply.
- **Refactor the `focus` input branch** (currently `_process` ~line 585) into a dispatcher on
  `active_mode`:
  - **FOCUS** → existing focus behavior (seconds-reserve + dot/trail + 0.55× speed).
  - **HYPER** → on Shift-held *and* bar full: enter Hyper (set a `_hyper_active` window), drain
    the bar; apply +fire-rate (scale GunCooldown) + unlimited-ammo flag (the four ammo decrement
    sites already gate on a flag — reuse the Hangar's "don't deplete" approach: skip decrement
    while `_hyper_active`) + Mk damage stacks (a `_hyper_dmg_mult`). On release/empty: exit,
    recharge bar while idle, re-lock until full.
  - **PHASE** → on Shift-press *and* charges > 0: consume a charge, set intangible for
    `duration` (reuse the focus invuln/intangibility path **without** the dot/trail/speed-cut),
    block the player's own fire+collision for the window. No bullet-clear.
- **Kill hook for Phase charges:** route enemy deaths to the player. `director.gd` already emits
  `enemy_died`; `main.gd` wires director↔player. Add `player.on_enemy_killed()` that, when
  `active_mode == PHASE`, increments a kill counter and grants +1 charge per threshold (capped).
  *(Wire the signal in `main.gd`; no-op for non-Phase modes.)*
- **Remove Hyper/Phase from the super path:** `fire_super()` / the death-bomb auto-fire
  (`player.gd` ~690, ~730) keep **only** Smart Bomb. Strip `HYPER_DAMAGE_MULT`, the
  `_hyper_t`/`_invuln_t`-via-hyper, and the `can_shoot` uncapped-fire bypass.
- **HUD signals:** emit a per-mode resource signal (reuse `focus_charge_changed` for Focus +
  Hyper bars; add a `phase_charges_changed(cur,max)` for the discrete pips). HUD work is its own
  phase (§5.4).

### 5.3 Loadout / economy wiring
- **`run_state.gd` `default_starting_loadout()`** — equip a Focus ModePart into SHIFT_MODE.
- **`Run.equip_part` / loadout** — handle SHIFT_MODE like any slot (displaced mode → storage).
- **Shop (`outpost`) + signal events** — add Phase / Hyper mode parts to the purchasable /
  grantable pools. Pricing → `economy-sim`.

### 5.4 HUD
- A **per-mode HUD readout** on a shared anchor: Focus + Hyper show a **bar** (reserve), Phase
  shows **discrete charge pips**. The existing focus bar is the template. Separate phase from
  the build of the modes themselves.

### 5.5 Hangar
- Replace the DEVICE_BAY_1 "Mode row" hack (`hangar.gd:58-65, 572-600, 632-661`) with the real
  **SHIFT_MODE** slot: the Mode row equips into SHIFT_MODE; the Super slot lists **only Smart
  Bomb**. Removes the "all three are DEVICE_BAY_1" caveat comment.

### 5.6 Docs
- This doc is authoritative; `supers_modes_modules_2026-06-05.md` gets a superseded banner.
- `docs/contributing/04-player-parts-economy.md` — update the supers/Focus description to "one
  super (Smart Bomb) + a Shift-Mode slot (Focus default; Phase/Hyper swap-ins)".

---

## 6. Tuner (per CLAUDE.md "human-iterated")

Magnitudes (Phase duration/charges/kill-threshold, Hyper bar size/recharge/fire-rate
increment/damage-stack) are 3+-knob systems Roman will iterate. **Scaffold a Shift-Mode tuner**
(`scripts/dev/shift_mode_tuner.gd`, parallax-tuner pattern, JSON persist + Copy-GDScript button)
before locking numbers — or fold the knobs into the existing Hangar (it already has the player +
dummy + DPS counter, the ideal mode test bench: equip a mode, hold/press Shift, watch fire-rate
/ intangibility / charges live).

---

## 7. Phasing (suggested PRs)

1. **Slot + parts skeleton** — `SHIFT_MODE` slot, `ModePart` base, Focus/Phase/Hyper mode parts
   (Focus wraps existing behavior; Phase/Hyper as data shells), factory/catalog re-registration,
   default loadout. *Outcome: modes equip into the real slot; Focus still works; Hyper/Phase
   no-op pending §2.*
2. **Hyper + Phase runtime** — player dispatcher on `active_mode`, Hyper bar + fire/ammo/damage,
   Phase charges + intangibility + kill-hook. Strip the old super behavior. *Outcome: both modes
   play to spec.*
3. **HUD** — per-mode bar/pips.
4. **Economy** — shop/signal grants + pricing.
5. **Hangar** — real SHIFT_MODE slot (drop the DEVICE_BAY_1 hack).

Each phase ships behind verification (parse_check + headless boot + a targeted test like
`tools/test_hangar_super.gd`).

---

## 8. Risks / open questions

- **Focus regen delay:** today 2.0s; original Mode-Energy doc wanted 1.5s. Leaving at 2.0
  unless tuned — flag for Roman.
- **Phase kill-credit source:** confirm `director.enemy_died` fires for *every* kill the player
  causes (and not for despawns/offscreen cleanups, which shouldn't grant charges). May need a
  "killed-by-player" flag vs. plain death.
- **Hyper unlimited-ammo seam:** reuse the four existing ammo-decrement gates (the Hangar's
  unlimited-ammo toggle proves the seam) — a `ship.unlimited_ammo`/`_hyper_active` check at
  each decrement, rather than top-off, so it's frame-rate independent.
- **Input feel for Phase:** press-to-burst vs. a brief hold — press is specced; validate it
  doesn't fight the held-Focus muscle memory when swapping modes.
- **Save/Run persistence:** the equipped mode must persist in the loadout snapshot like any part.
