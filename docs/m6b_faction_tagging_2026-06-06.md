# M6b Faction Tagging — DRAFT for Roman redline (2026-06-06)

**STATUS:** Finalized and populated into `scripts/levels/factions.gd`, which is now the **SOURCE OF TRUTH**. That file has grown past this 25-enemy snapshot (new faction-namespaced units exist). Use the code + this doc as reference for the tagging rationale.

The actionable content artifact that populates `scripts/levels/factions.gd` pools and
drives the conductor's **(faction, behavior) → hull** selection. Consolidates the
scattered tagging material (m6 design §8 sizes, §12.0 homes [Roman-locked], §13.1
behaviors, §14.1 existing→behaviors) into ONE table to mark up.

**What each column means**
- **Home** — the faction that owns this hull's art/identity (→ `enemy_<home>_<size>` after
  the §11 reorg). LOCKED in §12.0 except the two flagged `?`.
- **Size** — px size-class (§8: tiny8 / small16 / medium32 / large64 / elite128 / boss256).
  Drives stats/hitbox. **These are my best-guess draft — redline the ones that feel wrong.**
- **Behaviors[]** — the §13.1 behavior slots this hull can fill (eligibility list the
  conductor selects from). From §14.1 + the audit.
- **Verdict** — **U** = universal core (overlays into ANY faction's level: faction
  modifier + tint + reskin, e.g. "Corp Dart"); **E** = faction-exclusive (home faction
  only — identity piece); **R** = retire.

---

## ✅ REDLINE RESOLVED (Roman, 2026-06-06)
1. **cutter → privateer** (confirmed) — universal small Crosser.
2. **Keep all assigned homes.** **sapper: OUT of chaff → a RARE corporate encounter** (evasive
   + dangerous in its own right) — bump its spawn rarity, NOT chaff. The other aggressive small
   units (skirmisher, strafer, interceptor) stay **corporate**, treated as their faction's own
   (verdict → **E**, not freely universal).
3. **crystal → keep as a universal Holder** (assign a faction + tune behavior later; no retire).
4. **Sizes stand** (sprite-read based) for now.
5. **spitter rename: GO** (firecore popper → `spitter`).
6. **Pool model OK as a stopgap.** **END-STATE DIRECTION (Roman):** drop the universal core —
   each faction gets its OWN unit set; the ONLY thing truly "universal" is **adding privateer
   units into another faction's pool**. The faction-gap unit backlog (→ TODO.md, logged
   2026-06-06) is the path there. Until those units exist, the universal core stands in.

The master table below reflects these resolutions (cutter=privateer/U, sapper=E+RARE,
skirmisher/strafer/interceptor=E, crystal=U Holder).

---

## Master table (all 25 production enemies)

| Enemy | Home | Size | Behaviors[] | Verdict | Note |
|---|---|---|---|---|---|
| dart | privateer | small | Diver | **U** | canonical fast chaff; overlay workhorse |
| drifter | zealot | small | Drifter, Weaver(mild) | **U** | slow drifting shooter |
| firecore (→**spitter**) | zealot | small | Diver | **U** | shooting chaff; RENAME (§12.5) — not the hazard |
| bomb_drone | supremacy | small | Diver | **U** | dart reskin → seeds supremacy small-Diver |
| weaver | corporate | small | Weaver | **U** | s-curve + aimed; gentlest pressure |
| hover | corporate | small | Holder | **U** | loiter gunner |
| crystal | supremacy | small | Holder | **U** | loiter + 5-spread (R-candidate: overlaps hover) |
| cutter | **privateer?** | small | Crosser | **U?** | side-cut crosser — UNLISTED in §12.0; home? |
| skirmisher | corporate | small | Skirmisher | **U? / E?** | aggressive — §12.6 Q4 (universal vs corp-exclusive) |
| sapper | corporate | small | Harrier | **E?** | aggressive shield-drainer — §12.6 Q4 |
| strafer | corporate | small | Charger, Striker | **E?** | head-on MG pass — §12.6 Q4 |
| interceptor | corporate | small | Slider, Dropper | **E?** | dive-feint — §12.6 Q4 |
| hunter_drone | corporate | small | Striker, Hunter | **E** | drone_carrier's spawn / kamikaze |
| minelayer | privateer | small | Crosser, Dropper | **E** | area-denial mine dropper |
| firecore_drone | zealot | medium | Diver (+ring DeathEffect) | **E** | ring-release IS the fire theme |
| bomber | corporate | medium | Anchor, Holder | **U** | universal artillery anchor |
| frigate | supremacy | medium | Anchor, Crosser | **E** | broadside warship anchor |
| cruiser | supremacy | large | Holder, Anchor | **U** | universal capital presence |
| bulwark | corporate | large | Striker, Anchor | **E** | self-regen shield = corp hardware |
| gunship | corporate | elite | Sweeper, Skirmisher | **E** | corp elite event |
| drone_carrier | corporate | elite | Holder, Anchor (+Spawner) | **E** | corp elite event |
| beam_shooter | zealot | elite | Sweeper | **E** | tough beam platform (elite event) |
| beamer_tracker | zealot | elite | Sweeper | **E** | tracking beam platform (elite event) |
| burner | zealot | elite | Diver/Anchor (pair) | **E** | beam-pair (elite event) |
| firecore_cruiser | zealot | elite | Crosser | **E** | huge fire elite |

Plus the **firecore lane hazard** (zealot) — not a unit; the Dropper+DropFirecore drop. ✅ built.

---

## Per-faction pools (rolls up into `factions.gd`)

Each faction's spawnable pool = **all universal-core hulls** (overlaid with the faction
modifier + tint) **+ its own exclusives**. The modifier is from §8 (already in factions.gd).

**Universal core (shared, overlay into every faction):**
- small Divers: `dart`, `spitter`, `bomb_drone`
- small Drifter: `drifter` · small Weaver: `weaver` · small Holder: `hover`, `crystal` · small Crosser: `cutter`
- medium Anchor/Holder: `bomber` · large capital: `cruiser`
- (aggressive small — `skirmisher` pending Q4)

**privateer** (Vertarine Armada — tough, +overlay): exclusives `minelayer`; home art for dart/cutter. *Lean by design — it's the overlay faction.*
**corporate** (UltraGalactic — shielded): exclusives `bulwark`, `gunship`(elite), `drone_carrier`(elite), `hunter_drone`, + (sapper/strafer/interceptor/skirmisher pending Q4); home art for weaver/hover/bomber.
**zealot** (Evantian Theocracy — drops firecore): exclusives `firecore_drone`, `firecore_cruiser`(elite), `beam_shooter`(elite), `beamer_tracker`(elite), `burner`(elite), + firecore hazard; home art for drifter/spitter.
**supremacy** (Crimson Supremacy — faster fire): exclusives `frigate`; home art for bomb_drone/crystal/cruiser.

---

## Behavior × faction coverage (gaps → §14.2 backlog)

Universal cores cover most behaviors for ALL factions via overlay. Per-faction **exclusive
behavior gaps** (no hull yet → new-art backlog, only if the faction wants that slot):

| Behavior | supremacy | privateer | corporate | zealot |
|---|---|---|---|---|
| Diver | ✓ bomb_drone | ✓ dart | ✓ (univ) | ✓ spitter |
| Drifter/Weaver | (univ) | (univ) | ✓ weaver | ✓ drifter |
| Holder | ✓ crystal | (univ) | ✓ hover | (univ) |
| Skirmisher | **gap** | **gap** | ✓ skirmisher | **gap** |
| Harrier | **gap** | **gap** | ✓ sapper | **gap** |
| Anchor (presence) | ✓ frigate | **gap** | ✓ bomber | (univ cruiser) |
| Crosser | (univ cutter) | ✓ minelayer | ✓ minelayer? | ✓ firecore_cruiser |
| Sweeper | **gap** | **gap** | ✓ gunship/beamers? | ✓ beamers |
| Striker/Hunter | **gap** | **gap** | ✓ hunter_drone/bulwark | **gap** |
| Dropper | **gap** | ✓ minelayer | ✓ interceptor | ✓ (firecore) |
| capital (large) | ✓ cruiser | **gap** | ✓ bulwark | ✓ firecore_cruiser |

Most "gap" cells resolve via **universal overlay** (the conductor draws a universal hull +
the faction modifier) — real new-art gaps are only where a faction wants an *exclusive*
identity in an empty slot. **privateer is the thinnest** (overlay faction — acceptable).

---

## Redline questions (the calls I need from you)
1. **`cutter` home** — UNLISTED in §12.0. Propose **privateer** (groups with dart/minelayer; helps the thin privateer set). OK, or elsewhere?
2. **Aggressive small chaff** (`skirmisher`, `sapper`, `strafer`, `interceptor`) — **universal core** (any faction fields them) or **corporate-exclusive** identity? (§12.6 Q4 — still open.)
3. **`crystal`** — keep as a universal Holder, or **retire** (it overlaps `hover`)?
4. **Sizes** — the px size-class column is my draft. Flag any that should move tier (e.g. is `bomber` medium or large? `firecore_drone` small or medium?).
5. **`spitter` rename** confirmed? (firecore popper → `spitter`, freeing "firecore" for the faction/hazard — §12.5.)
6. **Pool composition** — happy with "universal core + per-faction exclusives," or do you want per-faction OWN hulls for the core slots sooner (more art, less overlay)?

Once redlined, this drives: (a) populating `factions.gd` `core_pool`/`exclusives`, (b) the producer faction-selection + per-spawn overlay, (c) the §11 file reorg, (d) the §14.2 gap backlog.
