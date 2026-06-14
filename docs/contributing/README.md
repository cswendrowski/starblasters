# Contributing to Starblaster — Newbie Godot Dev Guide

Welcome. This folder is a **narrative onboarding tour** for someone who knows
how to program but is **new to Godot and new to this project**. It teaches you
the mental model and the moving parts so you can make a change with confidence.

It complements two other docs — it does **not** repeat them:

- **`/CLAUDE.md`** (repo root) — the terse, authoritative house rules and
  conventions. Think of it as the law; these docs are the explanation.
- **`docs/godot-patterns.md`** — a running *log of Godot engine quirks* we've
  been bitten by. When something behaves weirdly and it turns out to be the
  engine (not your logic), it's probably documented there.

If anything here ever contradicts `CLAUDE.md`, `CLAUDE.md` wins — and please
fix the doc.

---

## What is Starblaster?

A 2D top-down **vertical shoot-'em-up** (shmup) with roguelite structure,
written in **GDScript** on **Godot 4.6.3** (standalone, no C#/Mono). You fly a
ship up a branching **sector map**, clearing **combat** nodes (waves of
enemies), **hazard** nodes (minefields/asteroids), shopping at **outposts**, and
fighting **bosses**. Between runs you keep nothing; within a run you bolt
**Parts** (Mk.1–9 upgrades) onto your ship and earn **bounty** to spend.

The game renders at an internal **480×270** and displays at 4× (1920×1080).
Gameplay happens in a narrow **216-wide playfield band** down the middle; the
side gutters hold the HUD. (Doc 02 explains why this matters for every position
you ever write.)

---

## Read these in order

You don't need all of it at once. Read 01 and 02 first — they're the
foundation. Then jump to whichever system you're about to touch.

| # | Doc | Read it when… |
|---|-----|----------------|
| — | **[README](README.md)** (this file) | First. Orientation + the map. |
| 01 | **[Getting Started & the Contribution Loop](01-getting-started.md)** | Before your first change — how to run, verify, commit, push. |
| 02 | **[Architecture](02-architecture.md)** | Before touching anything — the mental model, autoloads, scene flow, coordinate space. |
| 03 | **[Combat, Waves & Enemies](03-combat-waves-enemies.md)** | You're adding/tuning an enemy or wave. |
| 04 | **[Player, Parts & Economy](04-player-parts-economy.md)** | You're adding/tuning a Part, the damage model, or the shop. |
| 05 | **[Projectiles, Effects & Visuals](05-projectiles-effects-visuals.md)** | You're adding a bullet, an explosion/effect, or touching the backdrop. |
| 06 | **[Conventions & Gotchas](06-conventions-and-gotchas.md)** | Keep this open while you work — it's the checklist of traps. |

---

## "How do I add a …?" (the walkthroughs)

These are the highest-value pages — each walks the full add, end to end:

- **A new enemy** → [Doc 03 → "Add a new enemy"](03-combat-waves-enemies.md#walkthrough-add-a-new-enemy)
- **A new Part (ship upgrade)** → [Doc 04 → "Add a new Part"](04-player-parts-economy.md#walkthrough-add-a-new-part)
- **A new projectile or effect** → [Doc 05 → "Add a projectile / effect"](05-projectiles-effects-visuals.md#walkthrough-add-a-new-projectile)

---

## Where everything lives (folder map)

```
scripts/              GDScript — the brains. Subfolders:
  enemies/            enemy_base.gd, enemy_core.gd, bespoke enemies
  enemies/patterns/         movement Resources (how an enemy moves)
  enemies/shoot_patterns/   shooting Resources (how an enemy fires)
  projectiles/        bullets & missiles (base_bullet.gd, base_missile.gd)
  effects/            static VFX helpers (explosion, hit-flash, glow, muzzle…)
  parts/              Parts (ship upgrades) + PartFactory
  player/             player ship logic
  weapons/            weapon definitions
  levels/             wave_generator.gd, director.gd, enemy_roster.gd, wave_def.gd
  parallax/           backdrop parallax layers
  ui/                 HUD pieces + theme
  dev/                dev tools / tuners (run by humans, not shipped)
  run_state.gd        the Run autoload (run-wide state)
  main.gd             the combat scene controller

scenes/               .tscn scene files, mirroring scripts/ subfolders
  enemies/ projectiles/ player/ hud/ hazards/ levels/ dev/ …

resources/            .tres data (waves, patterns, weapons, materials)
graphics/  Planets/  SpaceBG/  Mini Pixel Pack 3/   art assets
shaders/  *.gdshader  +  graphics/*.gdshader         shaders
Sound/                audio (.wav)
tools/                parse_check.ps1, publish.ps1, capture_*.gd/.ps1
docs/                 design docs, research, and THIS guide (contributing/)
addons/               Godot plugins (e.g. godot_mcp)
```

Rough scale today: ~216 `.gd` scripts, ~126 scenes, ~43 enemy scenes. You will
never need to hold all of it in your head — find the subsystem, read its doc.

---

## The golden rules (the five that bite hardest)

These are expanded in the docs, but internalize them now:

1. **Gameplay bounds come from `Playfield`, never the viewport.** Import
   `scripts/systems/playfield.gd` and use `Playfield.X_MIN`/`X_MAX`/`CENTER`/`clamp_pos`.
   `get_viewport_rect()` returns the full 480 width and will let things drift
   into the HUD gutters. (Doc 02.)
2. **Projectiles parent to `get_tree().root`, never to the shooter** — the
   shooter `queue_free`s and would take its bullets with it. (Doc 05.)
3. **`parse_check` is not enough — boot the scene headless to truly verify.** A
   green parse_check has shipped hard compile errors before. (Doc 01.)
4. **Commit the `.uid` sidecar files Godot generates; never hand-edit them.**
   (Doc 06.)
5. **Never `butler`/publish without an explicit OK from the maintainer.**
   Working-branch pushes are fine; publishing is not. (Doc 01.)

---

## House style for the code you write

When you write or change code, leave **two layers of comments**:

1. **Inline notes on the non-obvious** — gotchas, invariants, *why this and not
   that*. Anything a reader couldn't infer from the code itself.
2. **A plain-language "what this block is doing and why"** above each meaningful
   chunk, written so *a newbie Godot dev can follow along* — not API jargon.

**Never restate what the code already says** (`# increment the counter` is
noise). Comment *as you go*, riding along with real work — we don't do giant
separate comment passes. The hot-spot files (`director.gd`, `wave_generator.gd`,
`glow_shader_fx.gd`, `missile_cruiser.gd`) already model this style well.

---

*These docs are living. If you learn something the hard way, add it here (or to
`docs/godot-patterns.md` if it's a raw engine quirk) so the next person doesn't.*
