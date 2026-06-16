# Starblaster

A 2D top-down vertical shmup built in Godot 4 (GDScript). Roguelite structure:
a branching sector map, slotted ship parts with Mk.1–9 upgrade scaling, procedural
hazard levels (minefields, asteroid fields), and a roster of bosses.

- **Engine:** Godot 4.6.3 standalone (no Mono), `forward_plus` renderer.
- **Target:** Windows (distributed via itch.io; Web/HTML5 retired 2026-06-10).
- **Internal resolution:** 480×270 (4× → 1920×1080), with a 216×270 centered playfield band.

## Getting started

See [`ONBOARDING.md`](ONBOARDING.md) for the human dev setup and [`CLAUDE.md`](CLAUDE.md)
for the architecture reference. The newbie-friendly tour lives in [`docs/contributing/`](docs/contributing/).

```
godot --path . --headless --quit-after 2   # headless boot smoke test
tools/parse_check.ps1                        # full parse check across scenes
tools/publish.ps1 -Version "0.1.NN"          # gated Windows export + butler push
```

Originally scaffolded from the kidscancode "Classic Shmup" tutorial, since rebuilt
against the Starblaster design.
