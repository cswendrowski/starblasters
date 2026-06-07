# Controller Support — Scoping & Implementation Plan

**Date:** 2026-06-05
**Status:** Scoped, not built. Plan of record for a future pass.
**Author:** Claude (Opus 4.8), from a read-only audit of the codebase.

---

## TL;DR — the surprising part

**Controller *gameplay* already works.** It shipped in `94be6ab` (see `TODO.md:12`).
The flight controls are bound (D-pad + left stick + face buttons) and the player
reads input through device-agnostic `Input.get_vector` / `Input.is_action_*` calls,
so a pad flies the ship today with zero code changes.

The thing the question is really asking about — **controller-based menu navigation** —
is the part that **does not exist at all**. Not partially. Not started. Every menu in
the game is mouse-click-only, and **nothing in the entire project uses Godot's focus
system** (`grab_focus`, `focus_mode`, `focus_neighbor` appear in zero game scripts).

So the honest framing is:

- **Gameplay controller support:** ~90% done. A few hours of cleanup.
- **Menu controller support:** a genuine project. Mechanical for ~10 screens, plus
  one genuinely hard surface (the sector map), plus a pile of polish (glyphs, rebind,
  vibration) that's easy to under-scope.

This is **not** a small task, and most of the cost is hidden in places that don't
show up in a quick look: focus *visuals*, focus *re-grab after dynamic rebuilds*, and
the sector map. Details below.

---

## 1. Current state (audited)

### 1.1 What already works (gameplay)

| Thing | State | Evidence |
|---|---|---|
| Movement (D-pad + left stick) | ✅ bound + analog | `project.godot:57-84`, `scripts/player.gd:556` `Input.get_vector(...)` |
| `shoot` / `shoot2` / `shoot_nose` | ✅ bound to A/B/X | `project.godot:85-103` |
| `focus` | ✅ bound to Y **and** LB | `project.godot:104-110`; read as digital hold `scripts/player.gd:570` |
| All gameplay reads device-agnostic | ✅ | `scripts/player.gd` uses only `Input.is_action_*` / `get_vector`; no `_input`, no `keycode`, no mouse-aim |
| No mouse aim to solve | ✅ | fixed vertical aim, `scripts/player.gd:835,847` |

**Implication:** the hard parts of "controller in a twin-stick / aim shooter" (analog
aim, cursor) **do not apply** — this is a fixed-aim vertical shmup. That's a big
discount on the gameplay side.

### 1.2 Gameplay gaps (small)

- `primary_swap` (Q) and `autofire_toggle` (R) have **no joypad binding** —
  keyboard-only (`project.godot:111-120`). A controller player cannot swap primary
  weapons or toggle autofire. Code already device-agnostic (`scripts/player.gd:601,615`),
  so this is **2 binding entries**, zero code.
- `focus` is read as a digital bool, not analog strength (`scripts/player.gd:570`).
  Variable/trigger-pressure focus is *not* possible without code changes. Probably fine
  to leave digital, but note it if "analog focus on trigger" ever comes up.

### 1.3 What does NOT exist (the actual project)

| Capability | State |
|---|---|
| **Menu navigation by focus** | ❌ nothing uses the focus system anywhere |
| **Focus visual style** (highlight on selected button) | ❌ theme has no focus StyleBox → even if focus worked, it'd be invisible |
| **Sector-map node navigation by D-pad** | ❌ mouse circle hit-test only, no adjacency data |
| **Modal dismissal with B/back** | ❌ modals are mouse-Cancel only |
| **Active-device detection** (kbd vs pad) | ❌ nothing tracks which device is "live" |
| **Controller glyphs on HUD/prompts** | ❌ `scripts/ui.gd:599` reads only `InputEventKey` |
| **Gamepad rebind in-app** | ❌ rebind capture is `InputEventKey`-only (`options_overlay.gd:249`); `TODO.md:53` already lists this as deferred |
| **Vibration** | ❌ no `start_joy_vibration` anywhere |
| **User-facing deadzone control** | ❌ hardcoded `0.5` per action in `project.godot` |

---

## 2. The blockers, ranked by how much they'll hurt

These are the things that make this "not a small task." Listed worst-first because
they're the ones most likely to be under-estimated.

### Blocker A — The focus system is completely unused (the big one)

This is not "sprinkle a few `grab_focus()` calls." Adopting focus navigation is a
**discipline** that has to be applied *consistently* and, critically, *re-applied
every time UI is rebuilt*. The failure mode is brutal: any screen where focus is lost
and not re-grabbed is a **soft-lock on controller** — the player is stuck with no way
to move, and won't know why.

Specific hazards in this codebase:

- **Dynamic rebuilds drop focus.** The outpost rebuilds its weapon/upgrade cards on
  every refresh/purchase (`scripts/outpost.gd:266-296`, `_render_*`). Signal events
  rebuild choice buttons inline (`scripts/signal_event.gd:741-771, 894-909`). Each
  rebuild **destroys the focused node**, so focus must be deterministically re-grabbed
  after every rebuild, including picking a sensible fallback when the previously-focused
  card no longer exists (e.g. you sold it).
- **No focus visuals.** Buttons are styled by `scripts/ui/ui_theme.gd`
  (`UiTheme.style_button` / `make_button`). If the theme defines no `focus` StyleBox,
  the focused button looks identical to the unfocused ones — the player literally
  cannot see where the cursor is. **A focus stylebox is a hard requirement, not polish.**
  Hover-state and focus-state are different in Godot; both need to read clearly.
- **Mouse/focus coexistence.** Moving the mouse can clear or steal focus. Mixed
  mouse+pad sessions need a coherent story (e.g. mouse motion hides the focus ring,
  pad input shows it and re-grabs). Easy to get subtly wrong.
- **Mixed control types in Options.** `scripts/ui/options_overlay.gd` has `HSlider`,
  `CheckButton`, `OptionButton`, and rebind `Button`s in two columns. A focused
  `HSlider` eats `ui_left`/`ui_right` to change its value — which collides with using
  left/right to navigate. The grid needs explicit `focus_neighbor` wiring so up/down
  moves between rows and left/right adjusts the focused slider. This is fiddlier than a
  plain button stack.
- **ScrollContainer + focus.** Outpost cards live in `ScrollContainer`s
  (`scripts/outpost.gd:266-296`). Focus has to auto-scroll the container to keep the
  focused card on-screen. Godot mostly does this for free *if* focus_mode is set and
  neighbors are sane, but the dense, dynamic layout makes it the place most likely to
  misbehave.

**Estimate:** This is the bulk of the work. ~10 surfaces × (set focus_mode + grab on
open + wire neighbors + re-grab on rebuild + B-to-back). Individually mechanical,
collectively large, and **every screen needs hands-on-pad QA** because there's no
automated way to verify "focus never dead-ends."

### Blocker B — The sector map (the genuinely hard surface)

The live map is `scenes/sector_map_hd.tscn` / `scripts/sector_map_hd.gd`, with the real
graph rendered into a SubViewport by `scripts/sector_map_v3.gd` and the interactive
chrome re-hosted into a 1920×1080 HD overlay.

Why it's hard:

- **Selection is pure mouse hit-testing against circles.** `_hd_poi_hits` /
  `_hd_boss_hits` are flat `{pos, radius}` lists; `_unhandled_input` checks
  `mouse.distance_to(hit.pos) <= radius` on click (`scripts/sector_map_hd.gd:410-449`).
  Hover reads the mouse every frame (`_process`, `:334-345`).
- **There is no "currently selected node" cursor and no adjacency data.** The branching
  topology exists in `sector_map_v3.gd` route generation, but the HD host flattens it to
  a list of clickable circles with **no neighbor graph exposed**. D-pad
  node-to-node traversal has to be built from scratch.
- **It's in HD coordinate space.** Any nav must operate in the 1920×1080 overlay coords,
  not native 480×270.

Two viable approaches:

1. **Directional nearest-node nav (recommended).** Track a `selected_node`, and on
   D-pad press pick the nearest reachable node in that direction (cone/dot-product
   filter against the circle positions you already have). Drive the existing
   `_select_visual()` ring (`:381-402`) off it, and `ui_accept` commits via the existing
   DEPART path (`:132-136`). Medium effort; reuses the circle lists and the ring.
2. **Reconstruct the real adjacency** from the route graph for "correct" branch-following
   movement. Cleaner conceptually, but means threading graph data the HD host currently
   throws away. More work, marginal UX gain over (1).

**Estimate:** This single screen is comparable in effort to several of the simple menus
combined. Budget for it explicitly; don't fold it into "do the menus."

### Blocker C — Polish that's easy to under-scope

None of these are hard individually; the trap is assuming "controller support" stops at
navigation. Players will notice if it does.

- **Active-device detection.** Need a tiny tracker that flips a "last input was pad /
  was kbd-mouse" flag by watching `InputEventJoypad*` vs key/mouse events. Everything
  glyph-related depends on it. ~1 small autoload.
- **Controller glyphs.** `scripts/ui.gd:599` `_action_key_label()` is the *single*
  extension point for the HUD weapon chips — it currently returns
  `OS.get_keycode_string(...)` and skips joypad events. Add a joypad branch that returns
  a glyph/label when the live device is a pad. Then decide the glyph **style** — Xbox
  (A/B/X/Y) vs PlayStation (✕/○/□/△) vs Switch face-button positions differ. Either ship
  abstract labels, pick one family, or detect controller type (more work). Also the
  Options "Press key…" prompt (`options_overlay.gd:246`) and `hangar.gd:208` "Esc closes"
  are keyboard-worded.
- **Gamepad rebind UI.** Already on the deferred list (`TODO.md:53`). The current rebind
  path captures `InputEventKey` only (`options_overlay.gd:249-266`) and persists via a
  keyboard-only `keyboard_overrides` dict (`scripts/settings.gd`, JSON-in-ConfigFile).
  Gamepad rebind needs a parallel capture path for `InputEventJoypadButton`/`Motion` and
  a parallel persistence structure (or a generalization of the existing one). Non-trivial.
- **Vibration.** Net-new (`Input.start_joy_vibration`), plus a persisted on/off setting.
  Optional, but cheap once the settings plumbing exists.
- **Deadzone setting.** Hardcoded `0.5` per action; no project-wide knob. A user setting
  would apply via `InputMap.action_set_deadzone(action, v)` at load, mirroring the
  `_apply_keybinds()` pattern in `scripts/settings.gd`. Optional.

### Blocker D — Testing has no automation path

- Headless smoke (`godot --headless`) **cannot** validate focus navigation or a pad —
  no controller, no focus traversal in a 2-tick boot. The capture/GIF harness doesn't
  help either.
- This feature is **manual-QA-heavy**: every screen must be walked end-to-end on a real
  pad, including the nasty cases (sell the focused card, open/close every modal, refresh
  the shop, dead-end hunting). Budget QA time explicitly; it's a real cost, not a
  rounding error.
- Mitigation: a dev checklist scene or a "controller nav smoke" that at least asserts
  every menu grabs *some* focus on `_ready` would catch the worst regressions, but the
  feel still needs a human + pad.

### Blocker E — Loose ends to confirm first

- **Legacy duplicate player.** `scripts/ship.gd` is an older standalone player still on
  disk; `scripts/main.gd` doesn't reference it, so it's presumed dead — **confirm before
  doing input work** so you don't waste effort wiring a corpse. (Related dead code already
  flagged in `TODO.md:54-55`.)
- **`ui_*` defaults.** `project.godot` does not override `ui_accept`/`ui_up`/… , so
  Godot's built-in joypad defaults (D-pad + A → `ui_*`) apply. That means once a screen
  uses focus, D-pad + A drive it **with no new input bindings** — good. Verify this holds
  and decide whether to also bind B → `ui_cancel` explicitly for back/dismiss.

---

## 3. Architecture recommendation

Keep it small and centralized so the per-screen work stays mechanical.

1. **`InputDevice` autoload (new, tiny).** Watches input events, exposes
   `last_device: {KBM, PAD}` and a `device_changed` signal, and (optionally)
   `current_pad_type` for glyph family. Everything glyph/prompt-related subscribes to it.

2. **Focus visuals in the theme (required).** Add a `focus` StyleBox to
   `scripts/ui/ui_theme.gd` so every `UiTheme`-styled button/control shows a clear ring.
   Do this **first** — without it, all focus work is invisible and untestable by feel.

3. **A `MenuNav` helper (small static/util).** Convenience for the repeated pattern:
   `grab first`, `wire vertical neighbors on a list of controls`, `re-grab after rebuild
   with a fallback index`, `bind B/ui_cancel → a 'back' callback`. Cuts the per-screen
   boilerplate and keeps the discipline consistent (which is what prevents soft-locks).

4. **Sector-map nav as a bespoke component** (Blocker B, approach 1), living in
   `sector_map_hd.gd`, reusing `_hd_poi_hits`/`_hd_boss_hits` + `_select_visual()`.

5. **Glyphs via the one extension point.** Extend `scripts/ui.gd:599`
   `_action_key_label()` to branch on `InputDevice.last_device`. One function, fans out
   to all the HUD chips already calling it.

6. **Settings extensions** follow the existing pattern in `scripts/settings.gd`
   (declare → load → save → `set_*` → emit `settings_changed`): `controller_vibration`,
   `controller_deadzone`, optional `button_prompt_style`. Gamepad rebind persistence is a
   parallel of `keyboard_overrides`.

---

## 4. Phasing (recommended order)

Ordered so each phase is independently shippable and the cheap wins land first.

### Phase 0 — Gameplay completeness (hours)
- Add joypad binds for `primary_swap` + `autofire_toggle` (`project.godot`).
- Confirm `ship.gd` is dead; confirm `ui_*` joypad defaults.
- **Outcome:** a controller can fully *play* (not navigate menus).

### Phase 1 — Focus foundation (small but load-bearing)
- Add the focus StyleBox to `UiTheme`.
- Add the `InputDevice` autoload + the `MenuNav` helper.
- **Outcome:** infrastructure ready; nothing user-visible yet.

### Phase 2 — Simple menus (mechanical, broad)
Wire focus on the plain surfaces, easiest-first:
main menu → pause menu → run summary → cleared summary → onboarding →
signal event → manage ship → options overlay (hardest of this group, mixed controls) →
**outpost** (densest, dynamic rebuilds, scroll). Plus modal dismissal (B/Cancel) for the
3 `UiTheme.make_modal` dialogs.
- **Outcome:** the whole game is controller-navigable *except* the sector map.

### Phase 3 — Sector map (the hard surface)
Build directional node nav (Blocker B, approach 1).
- **Outcome:** a full run is playable end-to-end on a pad, mouse never required.

### Phase 4 — Glyphs & prompts (polish, visible)
Active-device-driven glyph swap on the HUD chips + reword keyboard-centric prompts.
- **Outcome:** correct button hints regardless of input device.

### Phase 5 — Optional extras
Gamepad rebind UI · vibration · deadzone setting. Each independent; do by demand.

**Minimum shippable "controller support" = Phases 0–3.** Phase 4 strongly recommended
before calling it done (wrong glyphs read as broken). Phase 5 is genuinely optional.

---

## 5. Effort summary (relative, hands-on-pad time dominates)

| Phase | Scope | Effort | Risk |
|---|---|---|---|
| 0 — gameplay completeness | 2 binds + confirmations | **XS** | low |
| 1 — focus foundation | theme stylebox + 2 small helpers | **S** | low |
| 2 — simple menus | ~10 surfaces + 3 modals | **L** | med (focus dead-ends, rebuild re-grab, scroll) |
| 3 — sector map | bespoke directional nav | **M–L** | high (no adjacency, HD coords) |
| 4 — glyphs/prompts | device detect + glyph branch | **S–M** | low–med (glyph family choice) |
| 5 — rebind/vibration/deadzone | optional extras | **M** (rebind) / **S** each | low |

Sizing is deliberately relative, not in days — the dominant cost is **manual QA on a
real controller across every screen**, which doesn't compress with cleverness. There is
no headless validation for "focus never soft-locks."

---

## 6. Critical "don't forget" list

- **Focus StyleBox before anything else** — invisible focus is worse than no focus.
- **Re-grab focus after every dynamic rebuild** (outpost, signal events) with a sane
  fallback when the prior node is gone — this is the #1 soft-lock source.
- **Bind B → `ui_cancel`** and route it to each screen's back/close so "back" works
  everywhere, including modals.
- **Sector map is its own mini-project** — scope it separately, don't bury it in "menus."
- **Glyph family decision** (Xbox vs PS vs abstract) is a design call — surface it early.
- **Confirm `scripts/ship.gd` is dead** before touching input.
- **QA budget is real** — plan for a full hands-on-pad pass per phase.

---

## 7. Open questions for Roman

1. **Target controllers?** Xbox-only labels are simplest. PS/Switch glyphs multiply the
   art/label work and need controller-type detection.
2. **Vibration & deadzone settings — in or out?** Cheap once plumbing exists, but pure
   optional.
3. **Gamepad rebind in-app — ship it or stay deferred?** It's been on the deferred list
   since the gameplay binds landed (`TODO.md:53`). Fixed binds + "controller works out of
   the box" may be enough.
4. **Mouse + pad simultaneously, or modal?** Coexistence (hide focus ring on mouse move)
   is friendlier but fiddlier than "one device at a time."
