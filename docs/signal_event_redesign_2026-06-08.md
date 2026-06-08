# Signal Event Screen — Redesign Proposal

**Date:** 2026-06-08 · **Status:** ✅ COMPLETE — **Phases A + B + C all SHIPPED** (commits on
`m6c-polish-r2`). Decisions: (1) stow-only found parts, (2) Engage/Fight
confirm with event-supplied flavor + fallback, (3) rely on RESOLVE text (combat_intro stays inert),
(4) phasing approved.

**Phase A done (verified headless):** `_part_label` uses `display_name` (name bug fixed); salvaged
weapons stow to cargo, named (swap modal removed); the four combat/hazard drops now resolve to a
flavor line + an Engage/Enter-the-Field launch button (`_finish_to_launch`) instead of a silent
`change_scene`. Strings added to `strings.gd`.

**Phase B done (verified headless):** a single resolver (`_resolve` over an `_make_outcome` value
object) is the only resolution path — every choice routes through it via the now-thin
`_finish_to_sector_map` / `_finish_to_launch` wrappers (no handler churn). It renders the RESOLVE
state consistently: result text (tone-colored via `_apply_tone`), an optional **acquired-item card**
("Acquired: <name>" + stow hint), and the right continue/launch button. Item handoff is centralized —
the resolver stows a granted Part to cargo and cards it; grant sites pass `grant` instead of
hand-appending. Tone plumbing in (grants = GOOD); the full per-outcome tone pass lands with Phase C.

**Phase C done (verified headless):** events gain `id` + `weight`; selection is weighted
(`_pick_event`) instead of uniform — rarer payoff events appear less often, and the asteroid-only
Miner stays gated by the catalog's conditional append. Per-outcome tone pass: damage = BAD (red),
gains = GOOD (green). The redesign is complete — events are data-schema-tagged, every choice routes
through the single resolver into a consistent RESOLVE state with named item cards + combat confirms,
and item names/handoff are fixed. Future authoring: extend the catalog with `id`/`weight` + a resolve
that returns through `_finish_to_sector_map`/`_finish_to_launch`. A dev launcher (Test Combat →
"All-Signal Sector") forces a full sector of signal POIs for testing.
**Files:** `scripts/signal_event.gd`, `scenes/signal_event.tscn`, `scripts/signal_event_builder.gd`
(unused scaffolding), `scripts/run_state.gd`.

## The problem, in one line

Events have **no shared lifecycle**. Each event is a bespoke handler that applies its effects and
then *happens* to end in one of two ways — `_finish_to_sector_map(text)` (which shows outcome text) or
`SceneTransition.change_scene(...)` (which shows **nothing**). So whether the player understands what
their choice did is an accident of how each handler was written.

### The four symptoms (root causes, cited)
1. **Rarely any followup/outcome text.** Outcome text only exists because `_finish_to_sector_map()`
   (`signal_event.gd:934-957`) overwrites the body label with a result string. Handlers that transition
   instead (combat/hazard) show nothing. There is no dedicated outcome surface and no state machine —
   just the Title/Body/Choices nodes reused in two ad-hoc states.
2. **Dropped into combat with no explanation/confirm.** Four paths (`_do_ambush_combat` 476-480,
   `_do_inspection_run` combat branch 303-305, `_do_inspection_fight` 311-313, `_do_freespace_miner`
   818-824) call `change_scene` the instant the button is pressed — zero confirm, zero flavor. Worse:
   the `combat_intro` flag they set (`"fly_up_from_below"`, etc.) is **never read by anything** — it's a
   dead flag, so combat just starts vanilla. The "explained, staged combat drop" was scaffolded and
   never wired.
3. **Scav item handoff is broken two ways.**
   - **No real name.** `_part_label()` (`:866-872`) uses `part.get_class()` — which returns the engine/
     script base class (e.g. "Resource"), NOT the human `part.display_name`. Every salvaged-item name on
     this screen is therefore garbage. (The outpost + `part.gd::_to_string` correctly use `display_name`.)
   - **Doesn't land in the hold correctly.** Weapon swaps hand-roll `loadout_snapshot[slot] = new_part` +
     `inventory.append` (`:764-766`), **bypassing the canonical `Run.equip_part()`** (`run_state.gd:746-805`)
     that the outpost uses. So a swapped-in secondary skips ammo/super-charge reseed and the displaced
     part lands in `inventory` (sellable at Junk Trader) instead of `weapon_storage` (where the outpost
     expects it). Upgrade/ammo/bounty outcomes grant no named artifact at all — just silent stat bumps.
4. **Every event is bespoke.** ~10 events, two authoring styles (inline dicts + `_make_*` builders),
   each with its own `_do_*` effect handlers. No `id`, `weight`, `condition`, or `outcome_text` in the
   schema; selection is uniform-random. An unused `SignalEventBuilder` (`signal_event_builder.gd`) already
   has the right composable shape but was never adopted.

## Current architecture (for reference)

- **Schema:** event = `{title, body, choices:[{label, action: Callable(self)}]}` (`:6-11`).
- **Flow:** button `pressed` → `_on_choice()` (`:921-928`) disables buttons + calls `action.call(self)` →
  bespoke `_do_*` applies effects directly → terminal call (`_finish_to_sector_map` OR `change_scene`).
- **States:** none formal. Visually: PRESENT (title+body+choices) and RESOLVED (outcome-in-body + one
  "Sector Map" button), both rendered into the same nodes, plus an ad-hoc swap "modal" (`_offer_weapon_swap`
  `:748-778`).
- Already HD (`HdScreen.enter` `:35`, `_layout_hd` `:62-76`) + UiTheme styled.

---

## Proposal

### 1. A single event lifecycle (state machine)

Every event — no exceptions — flows through the same four states, rendered by one screen:

```
PRESENT  →  (choose)  →  RESOLVE  →  (continue/confirm)  →  ACT
 lead +       player      "here's        single button       apply effects,
 choices      picks       what            that performs       then transition
 (preview)    an option   happened" +     the transition      (sector map /
              ----------   acquired-item   (= the CONFIRM      combat / hazard)
                           card            for combat)
```

- **PRESENT** — title, lead body, choice buttons. Choice labels may preview cost/odds where known
  (several events already do this — keep it; make it the norm).
- **RESOLVE** — the missing beat. After a choice, ALWAYS show *what happened*: a result paragraph
  (color-coded good/bad/neutral) and, when a part is granted, a small **acquired-item card** (real name
  + icon + slot/tier). Effects are computed here but the **transition is gated behind the Continue
  button**, so nothing teleports silently.
- **ACT / CONFIRM** — the Continue button performs the transition. For sector-map returns it's just
  "Continue". For **combat/hazard it IS the confirm**: RESOLVE shows the flavor ("IFF spoofed — they're
  not buying it. Hostiles inbound.") and the button reads "Engage" (plus a flee/alternative when the
  event allows). No more silent combat drops.

This makes outcome text **structural, not optional** — a choice cannot resolve without producing a
result to show. It fixes symptoms (1) and (2) by construction.

### 2. Data-driven event + outcome schema (adopt/extend `SignalEventBuilder`)

Resurrect the abandoned builder as the spine. An event becomes pure data; the screen is a generic
runner. Proposed shape:

```gdscript
event(id, title, lead_body, weight, condition) -> [
  choice(label, enabled_if, resolve = func(ctx) -> Outcome { ... }),
  ...
]

# Outcome is a value object, not a side-effecting handler:
Outcome {
  result_text: String,        # ALWAYS present — the followup text
  tone: GOOD | BAD | NEUTRAL, # color-codes the resolve panel
  grant: Part | null,         # if set, show the acquired-item card (display_name!)
  effects: [ bounty(+n), hull(±n), ammo(+n), mark(+1), ... ],  # composable, applied on Continue
  next: SECTOR_MAP | COMBAT(intro, flavor) | HAZARD(subtype, flavor),
}
```

- **One resolver** applies `effects` + grants + transition (no per-handler `change_scene`). The roll
  (e.g. salvage 40/35/25) happens inside `resolve()` and returns a *fully-described* Outcome, so the
  RESOLVE panel can name exactly what was rolled.
- Schema gains `id` (telemetry/codex), `weight` (rarity), `condition` (context gates — replaces the
  hardcoded asteroid-field check at `:147`). Selection becomes weighted + conditional instead of uniform.
- This collapses ~20 bespoke `_do_*` handlers into data + a handful of reusable effect builders.

### 3. Fix the three concrete bugs (small, can land first as quick wins)

- **(c-1) Item name:** `_part_label()` → use `part.display_name` (fallback to a derived name), not
  `get_class()`. One-line-ish fix; immediately un-garbles every salvaged-item name.
- **(c-2) Equip/stow parity:** route "equip now" through `Run.equip_part(part)` (the outpost's path) so
  ammo/super reseed + `weapon_storage` routing run. Decide the stow model (below).
- **(2) Combat confirm:** never `change_scene` straight from a choice — always pass through RESOLVE; the
  combat/hazard transition is the Continue/Engage button. Either wire a real `combat_intro` consumer
  (intro variety) or drop the dead flag and let the RESOLVE flavor carry the explanation.

### 4. Screen / UI

- Rebuild the shell cleanly at HD (the `.tscn` is legacy 480-coords; all real layout is already in
  `_layout_hd`). Use `UiTheme.make_panel_stylebox` + LabelKind typography (consistent with the codex/
  manage-ship pass) — title, lead/result body, a choices/continue button row, and a reusable
  **acquired-item card** (name + tier + slot, mirroring the outpost offer card).
- Reuse `UiTheme.make_modal` only if a true overlay is wanted; otherwise the in-panel PRESENT→RESOLVE
  swap is fine as long as RESOLVE is a real, always-present state.
- Consistent **acquired-item card + toast** ("Stowed Spread Cannon in cargo" / "Equipped …"), mirroring
  the outpost's `_show_toast(Strings.TOAST_EQUIPPED)`.

---

## Decisions I need from you

1. **Found-part handling — stow vs equip.** Cleanest model: events **stow** found parts into cargo
   (`Run.inventory`) with a named card + toast, and the player equips later at Manage Ship / outpost
   (one equip path, no in-event slot juggling). Today some events offer swap-now. Options:
   (a) **stow-only** (recommended — simplest, consistent, removes the buggy in-event swap),
   (b) **stow + optional "equip now"** (offer an extra button that routes through `Run.equip_part`),
   (c) keep per-event swap (not recommended — it's the source of the c-2 bug).
2. **Combat drops — confirm style.** A simple "Engage" continue on the RESOLVE panel (recommended), or
   a dedicated confirm modal? And should some combat drops offer a *flee* alternative, or is the choice
   already made by then (you picked the risky option)?
3. **`combat_intro` flag.** Wire a real consumer (staged intros per event — more work, more flavor) or
   drop it and rely on RESOLVE flavor text (recommended for now)?
4. **Scope of the first cut.** Recommended phasing:
   - **Phase A (quick wins):** fix the 3 bugs (name, equip parity, no-silent-combat) on the *current*
     bespoke structure. Low risk, immediate player-facing improvement.
   - **Phase B (the unification):** introduce the Outcome value-object + single resolver + always-on
     RESOLVE state; rebuild the shell.
   - **Phase C:** migrate all ~10 events to the data schema (adopt `SignalEventBuilder`), add weights/
     conditions.
   Approve the phasing, or do you want it all in one pass?

## Best-practice notes (folded into the above)
- **Show before you commit:** preview cost/odds in choice labels; never apply effects the player can't
  see the result of. RESOLVE makes "what happened" mandatory.
- **Name everything:** real `display_name` on every granted part, in a consistent card.
- **One transition path:** all exits flow through the resolver, so combat/hazard always get a confirm
  beat and flavor — no silent teleports.
- **Color-coded tone** on outcomes (good/bad/neutral) for instant readability.
- **Data-driven events** make new events cheap and consistent, and unlock weighting/conditions + codex/
  telemetry hooks.
